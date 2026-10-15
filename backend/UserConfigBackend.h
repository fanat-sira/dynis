#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqml.h>

class UserConfigBackend final : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(UserConfig)
    QML_SINGLETON

    Q_PROPERTY(QString userConfigPath READ userConfigPath CONSTANT FINAL)
    Q_PROPERTY(QString configError READ configError NOTIFY configErrorChanged FINAL)
    Q_PROPERTY(QString defaultWallpaperPath READ defaultWallpaperPath WRITE setDefaultWallpaperPath NOTIFY defaultWallpaperPathChanged FINAL)

    Q_PROPERTY(QString wallpaperPath READ wallpaperPath NOTIFY wallpaperPathChanged FINAL)
    Q_PROPERTY(QString iconFontFamily READ iconFontFamily NOTIFY iconFontFamilyChanged FINAL)
    Q_PROPERTY(QString textFontFamily READ textFontFamily NOTIFY textFontFamilyChanged FINAL)
    Q_PROPERTY(QString heroFontFamily READ heroFontFamily NOTIFY heroFontFamilyChanged FINAL)
    Q_PROPERTY(QString timeFontFamily READ timeFontFamily NOTIFY timeFontFamilyChanged FINAL)
    Q_PROPERTY(QString tlpPermissionMode READ tlpPermissionMode NOTIFY tlpPermissionModeChanged FINAL)

    Q_PROPERTY(QString overviewGlobalShortcutAppid READ overviewGlobalShortcutAppid NOTIFY overviewGlobalShortcutAppidChanged FINAL)
    Q_PROPERTY(QString overviewGlobalShortcutName READ overviewGlobalShortcutName NOTIFY overviewGlobalShortcutNameChanged FINAL)

    Q_PROPERTY(int workspaceOverviewWindowDragButton READ workspaceOverviewWindowDragButton NOTIFY workspaceOverviewWindowDragButtonChanged FINAL)

    Q_PROPERTY(int dynamicIslandPrimaryButton READ dynamicIslandPrimaryButton NOTIFY dynamicIslandPrimaryButtonChanged FINAL)
    Q_PROPERTY(QString dynamicIslandPrimaryAction READ dynamicIslandPrimaryAction NOTIFY dynamicIslandPrimaryActionChanged FINAL)
    Q_PROPERTY(int dynamicIslandSecondaryButton READ dynamicIslandSecondaryButton NOTIFY dynamicIslandSecondaryButtonChanged FINAL)
    Q_PROPERTY(QString dynamicIslandSecondaryAction READ dynamicIslandSecondaryAction NOTIFY dynamicIslandSecondaryActionChanged FINAL)
    Q_PROPERTY(QVariantList dynamicIslandLeftSwipeItems READ dynamicIslandLeftSwipeItems NOTIFY dynamicIslandLeftSwipeItemsChanged FINAL)
    Q_PROPERTY(bool disableAutoExpandOnTrackChange READ disableAutoExpandOnTrackChange NOTIFY disableAutoExpandOnTrackChangeChanged FINAL)

    Q_PROPERTY(int screenCornerRadius READ screenCornerRadius NOTIFY screenCornerRadiusChanged FINAL)
    Q_PROPERTY(bool screenEdgeShadowEnabled READ screenEdgeShadowEnabled NOTIFY screenEdgeShadowEnabledChanged FINAL)
    Q_PROPERTY(int screenEdgeShadowRadius READ screenEdgeShadowRadius NOTIFY screenEdgeShadowRadiusChanged FINAL)
    Q_PROPERTY(qreal screenEdgeShadowOpacity READ screenEdgeShadowOpacity NOTIFY screenEdgeShadowOpacityChanged FINAL)
    Q_PROPERTY(QString screenEdgeShadowColor READ screenEdgeShadowColor NOTIFY screenEdgeShadowColorChanged FINAL)

public:
    explicit UserConfigBackend(QObject *parent = nullptr);

    QString userConfigPath() const;
    QString configError() const;
    QString defaultWallpaperPath() const;
    QString wallpaperPath() const;
    QString iconFontFamily() const;
    QString textFontFamily() const;
    QString heroFontFamily() const;
    QString timeFontFamily() const;
    QString tlpPermissionMode() const;
    QString overviewGlobalShortcutAppid() const;
    QString overviewGlobalShortcutName() const;
    int workspaceOverviewWindowDragButton() const;
    int dynamicIslandPrimaryButton() const;
    QString dynamicIslandPrimaryAction() const;
    int dynamicIslandSecondaryButton() const;
    QString dynamicIslandSecondaryAction() const;
    const QVariantList &dynamicIslandLeftSwipeItems() const;
    bool disableAutoExpandOnTrackChange() const;
    int screenCornerRadius() const;
    bool screenEdgeShadowEnabled() const;
    int screenEdgeShadowRadius() const;
    qreal screenEdgeShadowOpacity() const;
    QString screenEdgeShadowColor() const;
    void setDefaultWallpaperPath(const QString &path);

    Q_INVOKABLE int mouseButton(const QVariant &button) const;
    Q_INVOKABLE int mouseButtonsMask(const QVariant &buttons) const;
    Q_INVOKABLE void reload();

signals:
    void configErrorChanged();
    void defaultWallpaperPathChanged();
    void wallpaperPathChanged();
    void iconFontFamilyChanged();
    void textFontFamilyChanged();
    void heroFontFamilyChanged();
    void timeFontFamilyChanged();
    void tlpPermissionModeChanged();
    void overviewGlobalShortcutAppidChanged();
    void overviewGlobalShortcutNameChanged();
    void workspaceOverviewWindowDragButtonChanged();
    void dynamicIslandPrimaryButtonChanged();
    void dynamicIslandPrimaryActionChanged();
    void dynamicIslandSecondaryButtonChanged();
    void dynamicIslandSecondaryActionChanged();
    void dynamicIslandLeftSwipeItemsChanged();
    void disableAutoExpandOnTrackChangeChanged();
    void screenCornerRadiusChanged();
    void screenEdgeShadowEnabledChanged();
    void screenEdgeShadowRadiusChanged();
    void screenEdgeShadowOpacityChanged();
    void screenEdgeShadowColorChanged();

private:
    void scheduleReload();
    void loadConfig();
    void updateWatchedPaths();
    QString configHome() const;
    void migrateLegacyConfigIfNeeded();

    QString m_userConfigPath;
    QString m_configError;
    QString m_defaultWallpaperPath;
    QString m_wallpaperPath;
    QString m_iconFontFamily = QStringLiteral("Symbols Nerd Font");
    QString m_textFontFamily = QStringLiteral("Xanh Mono");
    QString m_heroFontFamily = QStringLiteral("Xanh Mono");
    QString m_timeFontFamily = QStringLiteral("Xanh Mono");
    QString m_tlpPermissionMode = QStringLiteral("ask");
    QString m_overviewGlobalShortcutAppid = QStringLiteral("quickshell");
    QString m_overviewGlobalShortcutName = QStringLiteral("dynamic-island-overview");
    int m_workspaceOverviewWindowDragButton = 1;
    int m_dynamicIslandPrimaryButton = 1;
    QString m_dynamicIslandPrimaryAction = QStringLiteral("toggleExpandedPlayer");
    int m_dynamicIslandSecondaryButton = 3;
    QString m_dynamicIslandSecondaryAction = QStringLiteral("toggleOverview");
    QVariantList m_dynamicIslandLeftSwipeItems;
    bool m_disableAutoExpandOnTrackChange = false;
    int m_screenCornerRadius = 15;
    bool m_screenEdgeShadowEnabled = true;
    int m_screenEdgeShadowRadius = 24;
    qreal m_screenEdgeShadowOpacity = 0.35;
    QString m_screenEdgeShadowColor = QStringLiteral("#000000");

    QFileSystemWatcher m_watcher;
    QTimer m_reloadTimer;
};
