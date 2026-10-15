// Exercise the actual wizard's file-editing functions without a desktop session.
#define main dynisSetupProgramMain
#include "../tools/dynis-setup.cpp"
#undef main
#include <QTemporaryDir>
#include <QTest>

class SetupTests final : public QObject {
    Q_OBJECT
private slots:
    void addsBindingAtomicallyWithBackupAndIsIdempotent() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/hyprland.conf";
        qputenv("DYNIS_HYPRLAND_CONFIG", path.toUtf8());
        const QByteArray original("# existing config\n$mainMod = SUPER\n");
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(original);
        file.close();
        QString error;
        QVERIFY(appendHyprlandBind(&error));
        QVERIFY(error.isEmpty());
        QVERIFY(overviewBindPresent());
        const auto backups = QDir(dir.path()).entryList({"*.dynis-backup-*"}, QDir::Files);
        QCOMPARE(backups.size(), 1);
        QFile backup(dir.filePath(backups.first()));
        QVERIFY(backup.open(QIODevice::ReadOnly));
        QCOMPARE(backup.readAll(), original);
        QVERIFY(!appendHyprlandBind(&error));
        QCOMPARE(QDir(dir.path()).entryList({"*.dynis-backup-*"}, QDir::Files).size(), 1);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll().count(overviewBindLine), 1);
    }
    void refusesConcurrentEditWithoutTruncatingConfig() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/hyprland.conf";
        qputenv("DYNIS_HYPRLAND_CONFIG", path.toUtf8());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("keep me\n");
        file.close();
        QLockFile lock(path + ".dynis.lock");
        QVERIFY(lock.tryLock());
        QString error;
        QVERIFY(!appendHyprlandBind(&error));
        QVERIFY(!error.isEmpty());
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), QByteArray("keep me\n"));
    }
    void preservesSymlink() {
        QTemporaryDir dir;
        const QString target = dir.path() + "/dotfiles.conf";
        QFile file(target);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("# dotfiles\n");
        file.close();
        const QString link = dir.path() + "/hyprland.conf";
        QVERIFY(QFile::link(target, link));
        qputenv("DYNIS_HYPRLAND_CONFIG", link.toUtf8());
        QString error;
        QVERIFY(appendHyprlandBind(&error));
        QVERIFY(QFileInfo(link).isSymLink());
        QVERIFY(overviewBindPresent());
    }
    void setupScrubsCredentialsAndRejectsBrokenJson() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/userconfig.json";
        qputenv("DYNIS_USER_CONFIG", path.toUtf8());
        qputenv("DYNIS_CONFIG_HOME", dir.path().toUtf8());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("{\"tlpSudoPassword\":\"old secret\",\"tlpPermissionMode\":\"password\"}");
        file.close();
        auto config = loadUserConfig();
        mergeUserConfigDefaults(&config);
        QVERIFY(!config.contains("tlpSudoPassword"));
        QCOMPARE(config.value("tlpPermissionMode").toString(), QStringLiteral("ask"));
        QVERIFY(saveUserConfig(config));
        QVERIFY(file.open(QIODevice::ReadOnly));
        QVERIFY(!file.readAll().contains("old secret"));
        file.close();
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write("{broken");
        file.close();
        QVERIFY_EXCEPTION_THROWN(loadUserConfig(), std::runtime_error);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), QByteArray("{broken"));
    }
};
QTEST_GUILESS_MAIN(SetupTests)
#include "setup_tests.moc"
