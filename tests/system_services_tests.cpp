#include "SystemServices.h"
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <unistd.h>

class SystemServicesTests final : public QObject {
    Q_OBJECT
    QTemporaryDir m_root;
    QByteArray m_previousPath;
    void executable(const QString &name, const QByteArray &script) {
        QFile file(m_root.filePath(name));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(script);
        file.close();
        QVERIFY(file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner));
    }
private slots:
    void init() {
        m_previousPath = qgetenv("PATH");
        qputenv("PATH", m_root.path().toUtf8());
    }
    void cleanup() { qputenv("PATH", m_previousPath); }
    void rejectsInvalidModes() {
        SystemServices services;
        QSignalSpy result(&services, &SystemServices::tlpSetFinished);
        services.setTlpMode("performance; touch /tmp/invalid");
        QCOMPARE(result.size(), 1);
        QCOMPARE(result.at(0).at(0).toBool(), false);
        QCOMPARE(result.at(0).at(1).toInt(), 125);
    }
    void delegatesAuthorizationWithoutPasswordInput() {
        if (::getuid() == 0) QSKIP("Authorization path requires an unprivileged user");
        const QString output = m_root.filePath("pkexec-args");
        qputenv("DYNIS_TEST_AUTH_OUTPUT", output.toUtf8());
        executable("tlp", "#!/bin/sh\nexit 0\n");
        executable("pkexec", "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$DYNIS_TEST_AUTH_OUTPUT\"\nif IFS= read -r password; then exit 99; fi\nexit 0\n");
        SystemServices services;
        QSignalSpy result(&services, &SystemServices::tlpSetFinished);
        services.setTlpMode("performance");
        QTRY_COMPARE(result.size(), 1);
        QVERIFY(result.at(0).at(0).toBool());
        QFile file(output);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), m_root.filePath("tlp").toUtf8() + "\nperformance\n");
    }
};
QTEST_GUILESS_MAIN(SystemServicesTests)
#include "system_services_tests.moc"
