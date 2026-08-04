import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import DynisBackend

Scope {
    id: shellRoot

    readonly property bool screenRecordingActive: SystemServices.screenRecordingActive
    property bool shuttingDown: false

    readonly property var userConfig: UserConfig

    property real cpuUsage: 0
    property real ramUsage: 0
    property var cpuSamples: []
    property var ramSamples: []
    readonly property int maxCpuSamples: 24
    property real _lastStatsAcceptedAt: 0

    function clamp01(v) { return Math.max(0, Math.min(1, v)); }

    Timer {
        id: systemStatsTimer
        interval: 1500
        running: !shellRoot.shuttingDown
        repeat: true
        triggeredOnStart: true
        onTriggered: SystemServices.requestSystemStats()
    }

    Connections {
        target: SystemServices

        function onSystemStatsReady(cpuVal, ramVal, errorString) {
            if (errorString !== "") return;
            // Skip readings that arrive on the heels of a prior one — another
            // caller (IslandSystemState swipe poller) is racing us and the
            // back-to-back read sees ~0 CPU delta. We want stable, well-spaced
            // samples for the sparkline.
            const now = Date.now();
            if (now - shellRoot._lastStatsAcceptedAt < 800) return;
            shellRoot._lastStatsAcceptedAt = now;

            if (cpuVal >= 0) {
                shellRoot.cpuUsage = shellRoot.clamp01(cpuVal);
                const samples = shellRoot.cpuSamples.slice();
                samples.push(shellRoot.cpuUsage);
                while (samples.length > shellRoot.maxCpuSamples) samples.shift();
                shellRoot.cpuSamples = samples;
            }
            if (ramVal >= 0) {
                shellRoot.ramUsage = shellRoot.clamp01(ramVal);
                const ramHistory = shellRoot.ramSamples.slice();
                ramHistory.push(shellRoot.ramUsage);
                while (ramHistory.length > shellRoot.maxCpuSamples) ramHistory.shift();
                shellRoot.ramSamples = ramHistory;
            }
        }
    }

    function forEachWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window)
                callback(window);
        }
    }

    function windowForScreen(screenObject) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.screen === screenObject)
                return window;
        }

        return null;
    }

    function showNotificationAll(notification, appName, appIcon, summary, body) {
        shellRoot.forEachWindow((window) => {
            if (window && window.showNotification)
                window.showNotification(notification, appName, appIcon, summary, body);
        });
    }

    function setMainModPreviewAll(active) {
        shellRoot.forEachWindow((window) => {
            if (window && window.setMainModPreview)
                window.setMainModPreview(active);
        });
    }

    function anyOverviewOpen() {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.overviewPhase !== "closed")
                return true;
        }

        return false;
    }

    function prepareOverviewAll() {
        shellRoot.forEachWindow((window) => window.prepareOverview());
    }

    function cancelPreparedOverviewAll() {
        shellRoot.forEachWindow((window) => window.cancelPreparedOverview());
    }

    function openOverviewAll() {
        shellRoot.forEachWindow((window) => window.openOverview());
    }

    function closeOverviewAll() {
        shellRoot.forEachWindow((window) => window.closeOverview());
    }

    function toggleOverviewAll() {
        if (shellRoot.anyOverviewOpen())
            shellRoot.closeOverviewAll();
        else
            shellRoot.openOverviewAll();
    }

    function forFocusedWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.monitorFocused) {
                callback(window);
                return;
            }
        }
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            shellRoot.toggleOverviewAll();
        }

        function open() {
            shellRoot.openOverviewAll();
        }

        function close() {
            shellRoot.closeOverviewAll();
        }

        function refreshWallpaperCache() {
            shellRoot.forEachWindow((window) => {
                if (window && window.prewarmWallpaperCache)
                    window.prewarmWallpaperCache();
            });
        }
    }

    IpcHandler {
        target: "dynis"

        function showClock() {
            shellRoot.forFocusedWindow((window) => window.showClockWindow());
        }

        function showCustom() {
            shellRoot.forFocusedWindow((window) => window.showCustomInfoWindow());
        }

        function showLyrics() {
            shellRoot.forFocusedWindow((window) => window.showLyricsWindow());
        }

        function togglePlayer() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }

        function showWifi() {
            shellRoot.forFocusedWindow((window) => window.showWifiPanel());
        }

        function showBluetooth() {
            shellRoot.forFocusedWindow((window) => window.showBluetoothPanel());
        }

        function mainModDown() {
            shellRoot.setMainModPreviewAll(true);
        }

        function mainModUp() {
            shellRoot.setMainModPreviewAll(false);
        }

        function mainmoddown() {
            shellRoot.setMainModPreviewAll(true);
        }

        function mainmodup() {
            shellRoot.setMainModPreviewAll(false);
        }
    }

    GlobalShortcut {
        appid: userConfig.overviewGlobalShortcutAppid
        name: userConfig.overviewGlobalShortcutName

        onPressed: shellRoot.toggleOverviewAll()
    }

    NotificationServer {
        id: notificationServer

        keepOnReload: false
        persistenceSupported: false
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: true
        imageSupported: true
        actionsSupported: false
        actionIconsSupported: false
        inlineReplySupported: false

        onNotification: function(notification) {
            notification.tracked = true;
            const image = String(notification.image || "");
            const iconSource = image.length > 0 ? image : String(notification.appIcon || "");
            shellRoot.showNotificationAll(
                notification,
                String(notification.appName || ""),
                iconSource,
                String(notification.summary || ""),
                String(notification.body || "")
            );
        }
    }

    Component.onDestruction: {
        shuttingDown = true;
    }

    Component.onCompleted: {
        SystemServices.ensureSetupComplete(Quickshell.shellDir);
        SystemServices.requestScreenRecordingSnapshot();
    }

    Variants {
        model: Quickshell.screens

        RoundedScreenCornersWindow {
            required property var modelData

            screen: modelData
        }
    }

    Variants {
        id: panelVariants

        model: Quickshell.screens

        DynamicIslandWindow {
            required property var modelData

            screen: modelData
            shellRootController: shellRoot
        }
    }

    Variants {
        model: Quickshell.screens

        LeftIsland {
            required property var modelData

            screen: modelData
            shellRootController: shellRoot
        }
    }

}
