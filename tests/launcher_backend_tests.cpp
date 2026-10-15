#include "LauncherBackend.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLockFile>
#include <QTemporaryDir>
#include <QTest>

class LauncherBackendTests final : public QObject {
    Q_OBJECT
    QTemporaryDir m_root;
    void desktop(const QString &base, const QString &id, const QByteArray &data) {
        QDir().mkpath(base + "/applications");
        QFile file(base + "/applications/" + id);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write(data), data.size());
    }
private slots:
    void initTestCase() {
        QVERIFY(m_root.isValid());
        qputenv("XDG_DATA_HOME", (m_root.path() + "/user").toUtf8());
        qputenv("XDG_DATA_DIRS", (m_root.path() + "/system").toUtf8());
        qputenv("XDG_CURRENT_DESKTOP", "Hyprland");
        desktop(m_root.path() + "/system", "override.desktop", "[Desktop Entry]\nType=Application\nName=System\nExec=/bin/true\n");
        desktop(m_root.path() + "/user", "override.desktop", "[Desktop Entry]\nType=Application\nName=User\nExec=/bin/true\n");
        desktop(m_root.path() + "/user", "hidden.desktop", "[Desktop Entry]\nType=Application\nName=Hidden\nExec=/bin/true\nNoDisplay=true\n");
        desktop(m_root.path() + "/user", "other.desktop", "[Desktop Entry]\nType=Application\nName=Other\nExec=/bin/true\nOnlyShowIn=GNOME;\n");
        desktop(m_root.path() + "/user", "missing.desktop", "[Desktop Entry]\nType=Application\nName=Missing\nExec=/does/not/exist\nTryExec=/does/not/exist\n");
        const QByteArray exec = "\"" + QCoreApplication::applicationFilePath().toUtf8() + "\" --capture \"" + (m_root.path() + "/args.json").toUtf8()
            + "\" \"two words\" \"$(touch " + (m_root.path() + "/injected").toUtf8() + ")\" %c %k %i %f";
        desktop(m_root.path() + "/user", "safe.desktop", "[Desktop Entry]\nType=Application\nName=Safe App\nIcon=test-icon\nExec=" + exec + "\n");
    }
    void init() {
        const QString state = m_root.path() + "/state-" + QString::fromLatin1(QTest::currentTestFunction());
        qputenv("XDG_STATE_HOME", state.toUtf8());
    }
    void respectsDesktopVisibilityAndUserOverrides() {
        LauncherBackend backend;
        const auto entries = backend.applications();
        QStringList ids;
        for (const auto &value : entries) {
            const auto entry = value.toMap();
            ids.append(entry.value("id").toString());
            if (entry.value("id") == "override.desktop")
                QCOMPARE(entry.value("name").toString(), QStringLiteral("User"));
        }
        QVERIFY(ids.contains("override.desktop"));
        QVERIFY(ids.contains("safe.desktop"));
        QVERIFY(!ids.contains("hidden.desktop"));
        QVERIFY(!ids.contains("other.desktop"));
        QVERIFY(!ids.contains("missing.desktop"));
        QCOMPARE(ids.count("override.desktop"), 1);
    }
    void launchesWithoutShellAndExpandsDesktopFields() {
        LauncherBackend backend;
        QVERIFY(backend.launch("safe.desktop"));
        const QString path = m_root.path() + "/args.json";
        QTRY_VERIFY(QFile::exists(path));
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        const auto args = QJsonDocument::fromJson(file.readAll()).array();
        QCOMPARE(args.size(), 6);
        QCOMPARE(args.at(0).toString(), QStringLiteral("two words"));
        QCOMPARE(args.at(1).toString(), "$(touch " + m_root.path() + "/injected)");
        QCOMPARE(args.at(2).toString(), QStringLiteral("Safe App"));
        QVERIFY(args.at(3).toString().endsWith("/safe.desktop"));
        QCOMPARE(args.at(4).toString(), QStringLiteral("--icon"));
        QCOMPARE(args.at(5).toString(), QStringLiteral("test-icon"));
        QVERIFY(!QFile::exists(m_root.path() + "/injected"));
        QVERIFY(backend.usageScore("safe.desktop") > 0);
        QVERIFY(!backend.launch("does-not-exist.desktop"));
        QCOMPARE(backend.usageScore("does-not-exist.desktop"), 0.0);
    }
    void persistsStateAndMergesWriters() {
        LauncherBackend first, second;
        QVERIFY(first.historyPath().startsWith(qEnvironmentVariable("XDG_STATE_HOME") + "/dynis/"));
        QVERIFY(first.recordLaunch("one.desktop"));
        QVERIFY(second.recordLaunch("two.desktop"));
        QVERIFY(first.recordLaunch("one.desktop"));
        LauncherBackend restored;
        QVERIFY(restored.usageScore("one.desktop") > 1.9);
        QVERIFY(restored.usageScore("two.desktop") > 0.9);
        QVERIFY(!(QFile::permissions(first.historyPath()) & (QFileDevice::ReadGroup | QFileDevice::ReadOther)));
    }
    void preservesMalformedHistory() {
        LauncherBackend backend;
        QDir().mkpath(QFileInfo(backend.historyPath()).absolutePath());
        QFile file(backend.historyPath());
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("{broken");
        file.close();
        QVERIFY(!backend.recordLaunch("test.desktop"));
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), QByteArray("{broken"));
    }
    void refusesLockedHistory() {
        LauncherBackend backend;
        QDir().mkpath(QFileInfo(backend.historyPath()).absolutePath());
        QLockFile lock(backend.historyPath() + ".lock");
        QVERIFY(lock.tryLock());
        QVERIFY(!backend.recordLaunch("test.desktop"));
    }
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (app.arguments().value(1) == "--capture") {
        QFile file(app.arguments().value(2));
        if (!file.open(QIODevice::WriteOnly)) return 1;
        QJsonArray args;
        for (const auto &arg : app.arguments().mid(3)) args.append(arg);
        file.write(QJsonDocument(args).toJson());
        return 0;
    }
    LauncherBackendTests tests;
    return QTest::qExec(&tests, argc, argv);
}
#include "launcher_backend_tests.moc"
