#include "LauncherBackend.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLockFile>
#include <QProcess>
#include <QPointer>
#include <QRegularExpression>
#include <QSaveFile>
#include <cmath>

// GLib's public structs contain a member named `signals`.
#pragma push_macro("signals")
#undef signals
#include <gio/gdesktopappinfo.h>
#pragma pop_macro("signals")

namespace {
constexpr qint64 day = 24LL * 60 * 60 * 1000;
constexpr qint64 maximumAge = 7 * day;
QString stateDirectory()
{
    const QString override = qEnvironmentVariable("XDG_STATE_HOME");
    const QString base = QDir::isAbsolutePath(override) ? override : QDir::homePath() + QStringLiteral("/.local/state");
    return base + QStringLiteral("/dynis");
}
}

LauncherBackend::LauncherBackend(QObject *parent)
    : QObject(parent), m_historyPath(stateDirectory() + QStringLiteral("/launcher-usage.json"))
{
    reloadHistory();
}

QString LauncherBackend::historyPath() const { return m_historyPath; }

QVariantList LauncherBackend::applications()
{
    reloadHistory();
    QVariantList result;
    GList *apps = g_app_info_get_all();
    for (GList *item = apps; item; item = item->next) {
        GAppInfo *app = G_APP_INFO(item->data);
        const char *id = g_app_info_get_id(app);
        if (!id || !g_app_info_should_show(app))
            continue;
        QString icon = QStringLiteral("application-x-executable");
        GIcon *gicon = g_app_info_get_icon(app);
        if (gicon && G_IS_THEMED_ICON(gicon)) {
            const char *const *names = g_themed_icon_get_names(G_THEMED_ICON(gicon));
            if (names && names[0]) icon = QString::fromUtf8(names[0]);
        } else if (gicon && G_IS_FILE_ICON(gicon)) {
            char *path = g_file_get_path(g_file_icon_get_file(G_FILE_ICON(gicon)));
            if (path) icon = QString::fromUtf8(path);
            g_free(path);
        }
        result.append(QVariantMap{
            {QStringLiteral("id"), QString::fromUtf8(id)},
            {QStringLiteral("name"), QString::fromUtf8(g_app_info_get_display_name(app))},
            {QStringLiteral("icon"), icon}
        });
    }
    g_list_free_full(apps, g_object_unref);
    return result;
}

bool LauncherBackend::launch(const QString &desktopId)
{
    // Resolve an installed desktop ID through GIO; never evaluate Exec as shell text.
    GDesktopAppInfo *app = g_desktop_app_info_new(desktopId.toUtf8().constData());
    if (!app) {
        emit errorOccurred(QStringLiteral("Application is no longer installed: %1").arg(desktopId));
        return false;
    }
    GError *error = nullptr;
    GAppLaunchContext *context = g_app_launch_context_new();
    const bool launched = g_app_info_launch(G_APP_INFO(app), nullptr, context, &error);
    if (!launched)
        emit errorOccurred(QStringLiteral("Could not launch %1: %2").arg(desktopId, QString::fromUtf8(error ? error->message : "Unknown GIO error")));
    g_clear_error(&error);
    g_object_unref(context);
    g_object_unref(app);
    if (launched)
        recordLaunch(desktopId);
    return launched;
}

QJsonObject LauncherBackend::prunedHistory(const QJsonObject &source) const
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QJsonObject result;
    for (auto it = source.begin(); it != source.end(); ++it) {
        if (!it.value().isArray()) continue;
        QJsonArray timestamps;
        for (const auto &value : it.value().toArray()) {
            if (!value.isDouble()) continue;
            const double age = double(now) - value.toDouble();
            if (std::isfinite(age) && age >= 0 && age <= maximumAge)
                timestamps.append(value);
        }
        if (!timestamps.isEmpty()) result.insert(it.key(), timestamps);
    }
    return result;
}

bool LauncherBackend::reloadHistory()
{
    QFile file(m_historyPath);
    if (!file.exists()) {
        m_history = {};
        return true;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        emit errorOccurred(QStringLiteral("Could not read launcher history: %1").arg(file.errorString()));
        return false;
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        emit errorOccurred(QStringLiteral("Invalid launcher history; file was left unchanged."));
        return false;
    }
    m_history = prunedHistory(document.object());
    emit historyChanged();
    return true;
}

bool LauncherBackend::recordLaunch(const QString &desktopId)
{
    const QString directory = QFileInfo(m_historyPath).absolutePath();
    if (!QDir().mkpath(directory)) {
        emit errorOccurred(QStringLiteral("Could not create launcher state directory."));
        return false;
    }
    QLockFile lock(m_historyPath + QStringLiteral(".lock"));
    // Other processes cannot lose updates; monitors share this singleton.
    if (!lock.tryLock(100)) {
        emit errorOccurred(QStringLiteral("Launcher history is busy."));
        return false;
    }
    if (!reloadHistory()) return false;
    QJsonObject next = prunedHistory(m_history);
    QJsonArray timestamps = next.value(desktopId).toArray();
    timestamps.append(double(QDateTime::currentMSecsSinceEpoch()));
    next.insert(desktopId, timestamps);
    QSaveFile output(m_historyPath);
    const QByteArray data = QJsonDocument(next).toJson(QJsonDocument::Compact);
    if (!output.open(QIODevice::WriteOnly)
        || !output.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)
        || output.write(data) != data.size() || !output.commit()) {
        emit errorOccurred(QStringLiteral("Could not save launcher history: %1").arg(output.errorString()));
        return false;
    }
    m_history = next;
    emit historyChanged();
    return true;
}

double LauncherBackend::usageScore(const QString &desktopId) const
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    double score = 0;
    for (const auto &value : m_history.value(desktopId).toArray()) {
        const double age = double(now) - value.toDouble();
        if (age >= 0 && age <= maximumAge)
            score += std::exp(-age / (3.0 * day));
    }
    return score;
}

void LauncherBackend::copyClipboard(const QString &id)
{
    if (!QRegularExpression(QStringLiteral("^[0-9]+$")).match(id).hasMatch()) {
        emit errorOccurred(QStringLiteral("Invalid clipboard entry ID."));
        return;
    }
    auto *decode = new QProcess(this);
    auto *copy = new QProcess(this);
    decode->setStandardOutputProcess(copy);
    connect(decode, &QProcess::finished, decode, &QObject::deleteLater);
    connect(copy, &QProcess::finished, copy, &QObject::deleteLater);
    QPointer<QProcess> decodeGuard(decode), copyGuard(copy);
    connect(decode, &QProcess::errorOccurred, this, [this, decode, copyGuard] {
        emit errorOccurred(QStringLiteral("Clipboard decode failed: %1").arg(decode->errorString()));
        if (copyGuard) copyGuard->kill();
        decode->deleteLater();
    });
    connect(copy, &QProcess::errorOccurred, this, [this, copy, decodeGuard] {
        emit errorOccurred(QStringLiteral("Clipboard copy failed: %1").arg(copy->errorString()));
        if (decodeGuard) decodeGuard->kill();
        copy->deleteLater();
    });
    copy->start(QStringLiteral("wl-copy"), {});
    decode->start(QStringLiteral("cliphist"), {QStringLiteral("decode"), id});
}
