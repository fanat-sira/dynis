#pragma once

#include <QJsonObject>
#include <QObject>
#include <QVariantList>
#include <QtQml/qqml.h>

// One QML singleton owns launcher state for every monitor in the shell.
class LauncherBackend final : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString historyPath READ historyPath CONSTANT FINAL)
public:
    explicit LauncherBackend(QObject *parent = nullptr);
    QString historyPath() const;
    Q_INVOKABLE QVariantList applications();
    Q_INVOKABLE bool launch(const QString &desktopId);
    Q_INVOKABLE double usageScore(const QString &desktopId) const;
    Q_INVOKABLE void copyClipboard(const QString &id);

    // Also used by tests and future alternative launch surfaces.
    bool recordLaunch(const QString &desktopId);
    bool reloadHistory();
signals:
    void errorOccurred(const QString &message);
    void historyChanged();
private:
    QJsonObject prunedHistory(const QJsonObject &source) const;
    QString m_historyPath;
    QJsonObject m_history;
};
