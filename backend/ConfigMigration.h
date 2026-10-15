#pragma once

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

namespace ConfigMigration {
// Never keep a backup of a file containing an administrative password.
inline bool sanitize(QJsonObject &config)
{
    bool changed = config.contains(QStringLiteral("tlpSudoPassword"))
        || config.contains(QStringLiteral("defaultTlpSudoPassword"));
    config.remove(QStringLiteral("tlpSudoPassword"));
    config.remove(QStringLiteral("defaultTlpSudoPassword"));
    if (config.value(QStringLiteral("tlpPermissionMode")) == QStringLiteral("password")) {
        config.insert(QStringLiteral("tlpPermissionMode"), QStringLiteral("ask"));
        changed = true;
    }
    return changed;
}

inline bool save(const QString &path, const QJsonObject &config, QString *error = nullptr)
{
    QSaveFile file(path);
    const QByteArray bytes = QJsonDocument(config).toJson(QJsonDocument::Indented);
    if (!file.open(QIODevice::WriteOnly)
        || !file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)
        || file.write(bytes) != bytes.size() || !file.commit()) {
        if (error)
            *error = QStringLiteral("Could not save %1: %2").arg(path, file.errorString());
        return false;
    }
    return true;
}

inline bool scrubFile(const QString &path, QString *error = nullptr)
{
    QFile file(path);
    if (!file.exists())
        return true;
    if (!file.open(QIODevice::ReadOnly)) {
        if (error) *error = QStringLiteral("Could not read %1: %2").arg(path, file.errorString());
        return false;
    }
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    file.close();
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        if (error) *error = QStringLiteral("Invalid configuration JSON: %1").arg(path);
        return false;
    }
    QJsonObject object = doc.object();
    return !sanitize(object) || save(path, object, error);
}
}
