import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import DynisBackend
import "qml/common"
import "qml/controlcenter"
import "qml/connectivity"
import "qml/island"
import "qml/workspace"

PanelWindow {
    id: root
    property var shellRootController: null
    property string overviewPhase: "closed"
    property bool overviewPreloading: false
    readonly property bool overviewPreparing: overviewPhase === "preparing"
    readonly property bool overviewVisible: overviewPhase === "preparing" || overviewPhase === "opening" || overviewPhase === "open"
    readonly property bool overviewMounted: overviewPhase !== "closed" || overviewPreloading
    readonly property bool overviewLoaderActive: overviewMounted || overviewUnloadGraceTimer.running
    readonly property bool overviewDataReady: overviewLoader.item
        ? !!overviewLoader.item.overviewDataReady
        : false
    readonly property bool overviewWallpaperReady: overviewWallpaperCache.ready
    readonly property bool overviewVisualReady: overviewDataReady && overviewWallpaperReady
    readonly property bool overviewContentVisible: (overviewPhase === "opening" || overviewPhase === "open")
        && overviewVisualReady
    readonly property var hyprMonitor: screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
    readonly property string hyprMonitorName: hyprMonitor && hyprMonitor.name ? String(hyprMonitor.name) : ""
    readonly property bool monitorFocused: hyprMonitor ? hyprMonitor.focused : false
    readonly property bool connectivityPromptActive: controlCenterLoader.item
        ? controlCenterLoader.item.hasConnectivityPrompt
        : false
    readonly property int currentMonitorWorkspaceId: hyprMonitor && hyprMonitor.activeWorkspace
        ? hyprMonitor.activeWorkspace.id
        : 1
    readonly property bool screenRecordingActive: shellRootController
        && shellRootController.screenRecordingActive !== undefined
        ? !!shellRootController.screenRecordingActive
        : false
    property bool mainModPreviewActive: false
    readonly property bool fullscreenShellHidden: !root.overviewVisible
        && root.currentWorkspaceHasFullscreenWindow()

    readonly property var userConfig: UserConfig

    HyprlandDispatch {
        id: hyprDispatch
    }

    color: StyleTokens.transparent
    visible: !root.fullscreenShellHidden
    anchors { top: true; left: true; right: true }
    mask: Region {
        // Input is the union of the island's visible surfaces plus a compact top
        // gesture strip. The gesture strip must not grow with expanded content.
        Region {
            x: 0
            y: 0
            width: root.width
            height: Math.ceil(root.topGestureInputHeight)
        }

        Region {
            intersection: Intersection.Combine
            x: Math.floor(mainCapsule.x)
            y: Math.floor(mainCapsule.y)
            width: Math.ceil(mainCapsule.width)
            height: Math.ceil(mainCapsule.height)
        }
        
        Region {
            intersection: Intersection.Combine
            x: Math.floor(leftBarPanel.x)
            y: Math.floor(leftBarPanel.y)
            width: leftBarPanel.visible ? Math.ceil(leftBarPanel.width) : 0
            height: leftBarPanel.visible ? Math.ceil(leftBarPanel.height) : 0
        }

        Region {
            intersection: Intersection.Combine
            x: Math.floor(rightBarPanel.x)
            y: Math.floor(rightBarPanel.y)
            width: rightBarPanel.visible ? Math.ceil(rightBarPanel.width) : 0
            height: rightBarPanel.visible ? Math.ceil(rightBarPanel.height) : 0
        }

        Region {
            intersection: Intersection.Combine
            x: Math.floor(leftBottomOuterBlend.x)
            y: Math.floor(leftBottomOuterBlend.y)
            width: leftBottomOuterBlend.visible ? Math.ceil(leftBottomOuterBlend.width) : 0
            height: leftBottomOuterBlend.visible ? Math.ceil(leftBottomOuterBlend.height) : 0
        }

        Region {
            intersection: Intersection.Combine
            x: Math.floor(rightBottomOuterBlend.x)
            y: Math.floor(rightBottomOuterBlend.y)
            width: rightBottomOuterBlend.visible ? Math.ceil(rightBottomOuterBlend.width) : 0
            height: rightBottomOuterBlend.visible ? Math.ceil(rightBottomOuterBlend.height) : 0
        }

    }
    // 20px screen gap + 32px island + 20px gap before tiled windows.
    readonly property real reservedBarTopInset: 0
    readonly property real reservedBarHeight: Math.ceil(root.reservedBarTopInset + root.sideBarHeight)
    readonly property real edgeBlendOverflowHeight: (!root.overviewVisible && root.sideBarY <= 0.5)
        ? (root.sideBarRadius + 1)
        : 0
    readonly property real collapsedWindowHeight: Math.ceil(root.reservedBarHeight + root.edgeBlendOverflowHeight)
    // Reserve enough vertical space to host any non-overview state (idle,
    // notification, expanded player, control center at max extras) so the
    // layer-shell surface never resizes mid-morph. Avoiding the resize prevents
    // FPS drops from per-frame Wayland reconfigures, clipping during shrink
    // animations, and the empty-area rendering artifacts that appear when the
    // window is held larger than the rendered capsule. The pixels above the
    // capsule mask region are fully transparent — no visual cost.
    readonly property real capsuleReserveHeight: 480
    readonly property real capsuleWindowHeight: Math.ceil(root.sideBarY + Math.max(mainCapsule.targetHeight, root.capsuleReserveHeight))
    readonly property real connectivityWindowHeight: Math.ceil(4 + root.connectivityDetailHeight + 12)
    implicitHeight: root.overviewVisible
        ? Math.max(
            root.collapsedWindowHeight,
            root.capsuleWindowHeight,
            root.connectivityWindowHeight,
            Math.ceil(root.controlCenterWindowHeight)
        )
        : Math.max(
            root.collapsedWindowHeight,
            root.capsuleWindowHeight,
            root.anyConnectivityDetailMounted ? root.connectivityWindowHeight : 0,
            islandContainer.controlCenterLayerVisible ? Math.ceil(root.controlCenterWindowHeight) : 0
        )
    // The monitor owns the fixed 67px top work area. Keep this surface at the
    // physical screen edge, so all islands stay aligned at y = 20.
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: root.monitorFocused && (root.overviewVisible || root.connectivityPromptActive)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dynis-capsule"
    WlrLayershell.keyboardFocus: root.monitorFocused && (root.overviewVisible || root.connectivityPromptActive)
        ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None

    // The actual Dynis panel is deliberately wider than the visible capsule.
    // Put the glass in its own tightly-sized Top-layer surface so HyprGlass's
    // edge SDF, refraction, and chromatic split follow the capsule itself.
    IslandGlassCarrier {
        hostScreen: root.screen
        islandWidth: mainCapsule.displayedWidth
        islandHeight: mainCapsule.targetHeight
        islandX: mainCapsule.x
        islandY: root.sideBarY
        islandRadius: mainCapsule.visualRadius
        islandVisible: root.visible && !root.overviewContentVisible
    }
    readonly property string iconFontFamily: userConfig.iconFontFamily
    readonly property string textFontFamily: userConfig.textFontFamily
    readonly property string heroFontFamily: userConfig.heroFontFamily
    readonly property string timeFontFamily: userConfig.timeFontFamily
    readonly property string defaultSplitIcon: "\ud83c\udfa7"
    readonly property string notificationStatusIcon: "\uf0f3"
    readonly property real overviewWindowCornerRadius: 0
    readonly property int dynamicIslandAcceptedButtons: userConfig.mouseButtonsMask([
        1,
        userConfig.dynamicIslandPrimaryButton,
        userConfig.dynamicIslandSecondaryButton
    ])
    readonly property bool topGestureInputActive: false
    readonly property real topGestureInputHeight: topGestureInputActive ? root.exclusiveZone : 0
    readonly property real overviewCapsuleWidth: islandContainer.overviewView ? islandContainer.overviewView.width : 760
    readonly property real overviewCapsuleHeight: islandContainer.overviewView ? islandContainer.overviewView.height : 308
    readonly property real overviewCapsuleRadius: 0
    readonly property color overviewCapsuleColor: islandContainer.overviewView
        ? islandContainer.overviewView.cardColor
        : StyleTokens.overviewCard
    readonly property color overviewCapsuleBorderColor: islandContainer.overviewView
        ? islandContainer.overviewView.cardBorderColor
        : StyleTokens.overviewBorder
    property bool wifiConnectivityDetailOpen: false
    property bool wifiConnectivityDetailMounted: false
    property bool bluetoothConnectivityDetailOpen: false
    property bool bluetoothConnectivityDetailMounted: false
    readonly property bool anyConnectivityDetailMounted: wifiConnectivityDetailMounted || bluetoothConnectivityDetailMounted
    readonly property real connectivityDetailWidth: 318
    readonly property real connectivityDetailHeight: 404
    readonly property real controlCenterMaximumExtraHeight: controlCenterLoader.item
        ? controlCenterLoader.item.controlCenterMaximumExtraHeight
        : 120
    readonly property real controlCenterWindowHeight: islandContainer.controlCenterLayerVisible
        ? 4 + 320 + root.controlCenterMaximumExtraHeight + 12
        : 0
    readonly property real connectivityDetailGap: 16
    readonly property int connectivityDetailAnimationDuration: 360
    readonly property string overviewWallpaperSource: overviewWallpaperCache.effectiveSource
    // Align top islands with Hyprland's visible 20px outer gap.
    readonly property real sideBarInset: 20
    // Center the 32 px island inside Hyprland's 80 px top outer gap.
    readonly property real sideBarY: 24
    readonly property real sideBarHeight: 32
    readonly property real sideBarRadius: sideBarHeight / 2
    readonly property int primaryWorkspaceCount: 10
    // Match LiquidIslandQS: a light dark tint lets the compositor-blurred
    // wallpaper remain visible instead of reading as a solid black bar.
    readonly property color barBackgroundColor: Qt.rgba(0.13, 0.19, 0.23, 0.20)
    readonly property color barBorderColor: Qt.rgba(0.88, 0.94, 1.0, 0.32)
    readonly property color barChipHoverColor: Qt.rgba(28 / 255, 31 / 255, 35 / 255, 0.98)
    readonly property color barTextMutedColor: Qt.rgba(178 / 255, 184 / 255, 192 / 255, 1.0)
    readonly property color barUrgentColor: Qt.rgba(108 / 255, 92 / 255, 98 / 255, 1.0)
    readonly property color capsuleLightBackgroundColor: barBackgroundColor
    readonly property color capsuleLightBorderColor: barBorderColor
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property real normalCapsuleWidth: Math.max(132, Math.ceil(normalClockMetrics.advanceWidth + 28))
    readonly property real topBarCpuUsage: shellRootController ? shellRootController.cpuUsage : -1
    readonly property real topBarRamUsage: shellRootController ? shellRootController.ramUsage : -1
    property string pendingConnectivityPanelKind: ""
    property int pendingConnectivityPanelAttempts: 0

    TextMetrics {
        id: normalClockMetrics
        font.family: root.timeFontFamily
        font.pixelSize: 17
        font.weight: Font.Medium
        text: timeObj.currentBarLabel
    }

    function beginOverviewOpening() {
        if (!overviewPreparing) return;
        if (overviewLoader.status !== Loader.Ready || !overviewVisualReady) return;
        overviewPreloading = false;
        overviewPhase = "opening";
        overviewRevealTimer.restart();
    }

    function prepareOverview() {
        if (overviewPhase !== "closed") return;
        overviewUnloadGraceTimer.stop();
        overviewPreloading = true;
        overviewPreloadExpireTimer.restart();
    }

    function cancelPreparedOverview() {
        if (overviewPhase !== "closed") return;
        overviewPreloadExpireTimer.stop();
        overviewPreloading = false;
    }

    function openOverview() {
        if (overviewPhase !== "closed") return;
        overviewUnloadGraceTimer.stop();
        overviewPreloadExpireTimer.stop();
        overviewPreloading = true;
        overviewPhase = "preparing";
        if (overviewLoader.status === Loader.Ready) {
            beginOverviewOpening();
        }
    }

    function closeOverview() {
        if (!overviewMounted) return;
        if (overviewLoader.status === Loader.Ready)
            overviewUnloadGraceTimer.restart();
        overviewRevealTimer.stop();
        overviewPreloadExpireTimer.stop();
        islandContainer.restoreRestingCapsule(true);
        overviewPreloading = false;
        overviewPhase = "closed";
    }

    function closeOverviewEverywhere() {
        if (shellRootController && shellRootController.closeOverviewAll) {
            shellRootController.closeOverviewAll();
            return;
        }

        closeOverview();
    }

    function setConnectivityDetailVisible(kind, open) {
        const nextOpen = !!open;

        if (kind === "wifi") {
            if (nextOpen) {
                wifiConnectivityDetailCleanupTimer.stop();
                wifiConnectivityDetailMounted = true;
                wifiConnectivityDetailOpen = true;
            } else {
                if (!wifiConnectivityDetailMounted && !wifiConnectivityDetailOpen)
                    return;
                wifiConnectivityDetailOpen = false;
                wifiConnectivityDetailCleanupTimer.restart();
            }
            return;
        }

        if (kind === "bluetooth") {
            if (nextOpen) {
                bluetoothConnectivityDetailCleanupTimer.stop();
                bluetoothConnectivityDetailMounted = true;
                bluetoothConnectivityDetailOpen = true;
            } else {
                if (!bluetoothConnectivityDetailMounted && !bluetoothConnectivityDetailOpen)
                    return;
                bluetoothConnectivityDetailOpen = false;
                bluetoothConnectivityDetailCleanupTimer.restart();
            }
        }
    }

    function closeAllConnectivityDetails() {
        setConnectivityDetailVisible("wifi", false);
        setConnectivityDetailVisible("bluetooth", false);
    }

    function listValues(rawItems) {
        if (!rawItems)
            return [];
        if (Array.isArray(rawItems))
            return rawItems;

        const length = Number(rawItems.length);
        if (!isFinite(length) || length < 0)
            return [];

        const resolved = [];
        for (let index = 0; index < Math.floor(length); index++)
            resolved.push(rawItems[index]);
        return resolved;
    }

    function currentWorkspaceHasFullscreenWindow() {
        const windows = hyprlandData ? listValues(hyprlandData.windowList) : [];
        const workspaceId = Number(root.currentMonitorWorkspaceId);
        const monitorName = String(root.hyprMonitorName || "");
        const monitorId = root.hyprMonitor && root.hyprMonitor.id !== undefined
            ? Number(root.hyprMonitor.id)
            : NaN;

        for (let index = 0; index < windows.length; index++) {
            const windowData = windows[index];
            if (!windowData || windowData.hidden || !windowData.mapped)
                continue;

            const windowWorkspaceId = windowData.workspace ? Number(windowData.workspace.id) : NaN;
            if (windowWorkspaceId !== workspaceId)
                continue;

            const windowMonitorName = windowData.monitorName !== undefined
                ? String(windowData.monitorName)
                : "";
            const windowMonitorId = windowData.monitor !== undefined
                ? Number(windowData.monitor)
                : NaN;
            const monitorMatches = windowMonitorName !== ""
                ? windowMonitorName === monitorName
                : (!isNaN(monitorId) && !isNaN(windowMonitorId) ? windowMonitorId === monitorId : true);
            if (!monitorMatches)
                continue;

            if (Number(windowData.fullscreen) > 0 || Number(windowData.fullscreenClient) > 0)
                return true;
        }

        return false;
    }

    function workspaceSnapshot(workspaceId) {
        const workspaces = hyprlandData ? listValues(hyprlandData.workspaces) : [];
        for (let index = 0; index < workspaces.length; index++) {
            const workspace = workspaces[index];
            if (workspace && Number(workspace.id) === workspaceId)
                return workspace;
        }

        return null;
    }

    function workspaceHasUrgency(workspaceId) {
        const windows = hyprlandData ? listValues(hyprlandData.windowList) : [];
        for (let index = 0; index < windows.length; index++) {
            const windowData = windows[index];
            const windowWorkspaceId = windowData && windowData.workspace ? Number(windowData.workspace.id) : -1;
            if (windowWorkspaceId === workspaceId && !!windowData.urgent)
                return true;
        }

        return false;
    }

    function workspaceIsOccupied(workspaceId) {
        const snapshot = workspaceSnapshot(workspaceId);
        if (!snapshot)
            return false;

        const windowCount = Number(snapshot.windows);
        if (isFinite(windowCount) && windowCount > 0)
            return true;

        return String(snapshot.lastwindowtitle || "").trim() !== "";
    }

    function formatUsagePercent(value) {
        if (!(value >= 0))
            return "--%";
        const percent = Math.round(Math.max(0, value) * 100);
        return (percent < 10 ? "0" : "") + percent + "%";
    }

    function formatUsageBar(value, slots) {
        if (!(value >= 0))
            return "????????";
        const count = slots || 8;
        const filled = Math.max(0, Math.min(count, Math.round(value * count)));
        let result = "";
        for (let index = 0; index < count; index++)
            result += index < filled ? "█" : "░";
        return result;
    }

    function drawStatSparkline(ctx, samples, strokeColor) {
        const canvas = ctx.canvas;
        const w = canvas.width;
        const h = canvas.height;
        ctx.reset();
        ctx.clearRect(0, 0, w, h);
        if (!samples || samples.length < 2) return;

        const padY = 2;
        const usableH = h - padY * 2;
        const step = w / (samples.length - 1);

        const points = [];
        for (let i = 0; i < samples.length; i++) {
            const x = i * step;
            const y = padY + (1 - Math.max(0, Math.min(1, samples[i]))) * usableH;
            points.push({ x: x, y: y });
        }

        ctx.beginPath();
        ctx.moveTo(points[0].x, h);
        for (let i = 0; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y);
        ctx.lineTo(points[points.length - 1].x, h);
        ctx.closePath();

        const gradient = ctx.createLinearGradient(0, 0, 0, h);
        gradient.addColorStop(0, Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, 0.35));
        gradient.addColorStop(1, Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, 0));
        ctx.fillStyle = gradient;
        ctx.fill();

        ctx.beginPath();
        for (let i = 0; i < points.length; i++) {
            if (i === 0) ctx.moveTo(points[i].x, points[i].y);
            else ctx.lineTo(points[i].x, points[i].y);
        }
        ctx.strokeStyle = strokeColor;
        ctx.lineWidth = 1.4;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.stroke();
    }

    function bluetoothConnected() {
        const devices = bluetoothAdapter && bluetoothAdapter.devices
            ? listValues(bluetoothAdapter.devices.values)
            : [];

        for (let index = 0; index < devices.length; index++) {
            if (devices[index] && devices[index].connected)
                return true;
        }

        return false;
    }

    function batteryGlyph() {
        if (islandContainer.isCharging)
            return "\uf0e7";

        const capacity = islandContainer.batteryCapacity;
        if (capacity < 0)
            return "\uf244";
        if (capacity >= 90)
            return "\uf240";
        if (capacity >= 65)
            return "\uf241";
        if (capacity >= 40)
            return "\uf242";
        if (capacity >= 15)
            return "\uf243";
        return "\uf244";
    }

    function volumeGlyph() {
        if (islandContainer.isMuted)
            return "\uf6a9";

        const volume = islandContainer.currentVolume;
        if (volume < 0.34)
            return "\uf026";
        if (volume < 0.68)
            return "\uf027";
        return "\uf028";
    }

    function volumeLabel() {
        if (islandContainer.isMuted)
            return volumeGlyph();

        return volumeGlyph() + " "
            + (islandContainer.currentVolume >= 0
                ? Math.round(Math.max(0, islandContainer.currentVolume) * 100) + "%"
                : "--%");
    }

    component TopEdgeBlendCorner: Canvas {
        property bool cutoutOnRight: true
        property bool activeBlend: true

        width: root.sideBarRadius + 1
        height: root.sideBarRadius + 1
        antialiasing: false
        smooth: false
        visible: activeBlend && !root.overviewVisible && root.sideBarY <= 0.5
        z: 6

        onPaint: {
            const ctx = getContext("2d");
            const r = Math.max(1, width);

            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.fillStyle = root.barBackgroundColor;
            ctx.fillRect(0, 0, width, height);
            ctx.globalCompositeOperation = "destination-out";
            ctx.beginPath();

            if (cutoutOnRight) {
                ctx.moveTo(width, height);
                ctx.arc(width, height, r, Math.PI, 1.5 * Math.PI, false);
                ctx.lineTo(width, height);
            } else {
                ctx.moveTo(0, height);
                ctx.arc(0, height, r, 1.5 * Math.PI, 0, false);
                ctx.lineTo(0, height);
            }

            ctx.closePath();
            ctx.fill();
        }
    }

    component BottomEdgeBlendCorner: Canvas {
        property bool cutoutOnRight: true
        property bool activeBlend: true

        width: root.sideBarRadius + 1
        height: root.sideBarRadius + 1
        antialiasing: false
        smooth: false
        visible: activeBlend && !root.overviewVisible && root.sideBarY <= 0.5
        z: 6

        onPaint: {
            const ctx = getContext("2d");
            const r = Math.max(1, width);

            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.fillStyle = root.barBackgroundColor;
            ctx.fillRect(0, 0, width, height);
            ctx.globalCompositeOperation = "destination-out";
            ctx.beginPath();

            if (cutoutOnRight) {
                ctx.moveTo(width, 0);
                ctx.arc(width, 0, r, Math.PI, 0.5 * Math.PI, true);
                ctx.lineTo(width, 0);
            } else {
                ctx.moveTo(0, 0);
                ctx.arc(0, 0, r, 1.5 * Math.PI, 0, false);
                ctx.lineTo(0, 0);
            }

            ctx.closePath();
            ctx.fill();
        }
    }

    function showConnectivityPanel(kind) {
        pendingConnectivityPanelKind = kind;
        pendingConnectivityPanelAttempts = 0;
        islandContainer.showControlCenter();
        connectivityPanelRevealTimer.restart();
    }

    function applyPendingConnectivityPanel() {
        if (pendingConnectivityPanelKind === "")
            return;

        const panel = controlCenterLoader.item;
        if (!panel) {
            if (pendingConnectivityPanelAttempts < 20) {
                pendingConnectivityPanelAttempts += 1;
                connectivityPanelRevealTimer.restart();
            } else {
                pendingConnectivityPanelKind = "";
            }
            return;
        }

        panel.setConnectivityPanelOpen("wifi", pendingConnectivityPanelKind === "wifi", true);
        panel.setConnectivityPanelOpen("bluetooth", pendingConnectivityPanelKind === "bluetooth", true);
        pendingConnectivityPanelKind = "";
        pendingConnectivityPanelAttempts = 0;
    }

    function openOverviewEverywhere() {
        if (shellRootController && shellRootController.openOverviewAll) {
            shellRootController.openOverviewAll();
            return;
        }

        openOverview();
    }

    function prepareOverviewEverywhere() {
        if (shellRootController && shellRootController.prepareOverviewAll) {
            shellRootController.prepareOverviewAll();
            return;
        }

        prepareOverview();
    }

    function cancelPreparedOverviewEverywhere() {
        if (shellRootController && shellRootController.cancelPreparedOverviewAll) {
            shellRootController.cancelPreparedOverviewAll();
            return;
        }

        cancelPreparedOverview();
    }

    function toggleOverviewEverywhere() {
        if (shellRootController && shellRootController.toggleOverviewAll) {
            shellRootController.toggleOverviewAll();
            return;
        }

        if (overviewMounted)
            closeOverviewEverywhere();
        else
            openOverviewEverywhere();
    }

    function prewarmWallpaperCache() {
        overviewWallpaperCache.prewarm();
    }

    function showNotification(notification, appName, appIcon, summary, body) {
        islandContainer.showNotificationCapsule(notification, appName, appIcon, summary, body);
    }

    function setMainModPreview(active) {
        mainModPreviewActive = !!active;
    }

    function showClockWindow() { islandContainer.showTimeCapsule(); }
    function showCustomInfoWindow() { islandContainer.showCustomCapsule(); }
    function showLyricsWindow() { islandContainer.showLyricsCapsule(); }

    function togglePlayerWindow() {
        if (islandContainer.islandState === "expanded")
            islandContainer.smartRestoreState();
        else
            islandContainer.showExpandedPlayer(false);
    }

    function showWifiPanel() {
        if (islandContainer.islandState === "wifi")
            islandContainer.smartRestoreState();
        else
            islandContainer.showConnectivityIsland("wifi");
    }

    function showBluetoothPanel() {
        if (islandContainer.islandState === "bluetooth")
            islandContainer.smartRestoreState();
        else
            islandContainer.showConnectivityIsland("bluetooth");
    }

    onOverviewVisibleChanged: {
        if (overviewVisible && monitorFocused) overviewFocusTimer.restart();
    }
    onConnectivityPromptActiveChanged: {
        if (connectivityPromptActive && monitorFocused)
            connectivityPromptFocusTimer.restart();
    }
    onFullscreenShellHiddenChanged: {
        if (fullscreenShellHidden) {
            closeAllConnectivityDetails();
            if (islandContainer.islandState !== "normal")
                islandContainer.restoreRestingCapsule(true);
        }
    }
    onOverviewVisualReadyChanged: {
        if (overviewVisualReady) beginOverviewOpening();
    }
    onMonitorFocusedChanged: {
        if (overviewVisible && monitorFocused) overviewFocusTimer.restart();
        if (connectivityPromptActive && monitorFocused) connectivityPromptFocusTimer.restart();
    }

    Timer {
        id: overviewFocusTimer
        interval: 0
        repeat: false
        onTriggered: islandContainer.forceActiveFocus()
    }

    Timer {
        id: connectivityPromptFocusTimer
        interval: 0
        repeat: false
        onTriggered: islandContainer.forceActiveFocus()
    }

    Timer {
        id: overviewRevealTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root.overviewPhase === "opening") root.overviewPhase = "open";
        }
    }

    Timer {
        id: overviewPreloadExpireTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (root.overviewPhase === "closed")
                root.overviewPreloading = false;
        }
    }

    Timer {
        id: overviewUnloadGraceTimer
        interval: 260
        repeat: false
    }

    Timer {
        id: wifiConnectivityDetailCleanupTimer
        interval: root.connectivityDetailAnimationDuration
        repeat: false
        onTriggered: root.wifiConnectivityDetailMounted = false
    }

    Timer {
        id: bluetoothConnectivityDetailCleanupTimer
        interval: root.connectivityDetailAnimationDuration
        repeat: false
        onTriggered: root.bluetoothConnectivityDetailMounted = false
    }

    Timer {
        id: connectivityPanelRevealTimer
        interval: 16
        repeat: false
        onTriggered: root.applyPendingConnectivityPanel()
    }

    Component.onCompleted: {
        WifiController.refreshState();
    }

    OverviewWallpaperCacheController {
        id: overviewWallpaperCache

        active: root.overviewLoaderActive
        wallpaperPath: userConfig.wallpaperPath
        hyprMonitor: root.hyprMonitor
        screenObject: root.screen
    }

    IslandClock {
        id: timeObj
    }

    HyprlandData {
        id: hyprlandData
    }

    // --- 灵动岛主容器与全局状态 ---
    FocusScope {
        id: islandContainer
        anchors.fill: parent
        focus: root.monitorFocused && (root.overviewVisible || root.connectivityPromptActive)

        property string islandState: "normal"
        property string splitIcon: root.defaultSplitIcon
        property real osdProgress: -1.0
        property bool osdProgressAnimationEnabled: true
        property string osdCustomText: ""
        property int currentWs: root.currentMonitorWorkspaceId > 0 ? root.currentMonitorWorkspaceId : 1
        readonly property int batteryCapacity: systemState.batteryCapacity
        readonly property bool isCharging: systemState.isCharging
        readonly property real currentVolume: systemState.currentVolume
        readonly property bool isMuted: systemState.isMuted
        readonly property real currentBrightness: systemState.currentBrightness
        readonly property real currentCpuUsage: systemState.currentCpuUsage
        readonly property real currentRamUsage: systemState.currentRamUsage
        property string notificationAppName: ""
        property string notificationAppIcon: ""
        property string notificationSummary: ""
        property string notificationBody: ""
        property var notifications: []
        property int notificationNextId: 1
        property var bluetoothExpandedDevice: null
        readonly property var cavaLevels: systemState.cavaLevels
        property real swipeTransitionProgress: 0
        property string workspaceOriginSide: "none"
        property string splitOriginSide: "none"
        property string restingState: "normal"
        property bool expandedByPlayerAutoOpen: false
        property real customCapsuleWidth: 200
        property real lyricsCapsuleWidth: 200
        property bool sideSwipeSettling: false
        property real contentMorphProgress: 1
        readonly property real contentMorphOpacity: contentMorphProgress
        readonly property real contentMorphScale: 0.88 + contentMorphProgress * 0.12
        readonly property int defaultAutoHideInterval: 1250
        readonly property int notificationAutoHideInterval: 4200
        readonly property int notificationHistoryLimit: 20
        readonly property int bluetoothExpandedAutoHideInterval: 2500
        readonly property int playerAutoHideInterval: 3000
        readonly property int swipeAnimationDuration: 220
        readonly property bool blocksTransientSplit: islandState === "expanded"
            || islandState === "bluetooth_expanded"
            || islandState === "control_center"
            || islandState === "notification"
        readonly property bool isPillIslandState: !root.overviewVisible
            && (islandState === "normal"
                || islandState === "split"
                || islandState === "long_capsule"
                || islandState === "custom"
                || islandState === "lyrics"
                || islandState === "notification")

        // Direction-aware easing: spring overshoot looks great on grow but
        // turns into a visible undershoot/bounce on big shrinks (control center
        // or expanded player closing back to idle). When we leave a box state,
        // morphSoftEasingActive flips true so the in-flight morph uses a
        // smooth OutCubic landing instead of OutBack.
        property string _previousIslandState: islandState
        property bool morphSoftEasingActive: false
        function _isBoxIslandState(state) {
            return state === "control_center"
                || state === "expanded"
                || state === "bluetooth_expanded"
                || state === "wifi"
                || state === "bluetooth";
        }

        onIslandStateChanged: {
            morphSoftEasingActive = _isBoxIslandState(_previousIslandState)
                && !_isBoxIslandState(islandState);
            _previousIslandState = islandState;
            restartContentMorph();
        }
        readonly property bool splitShowsProgress: islandState === "split" && osdProgress >= 0
        readonly property bool splitShowsText: islandState === "split" && osdProgress < 0 && osdCustomText !== ""
        readonly property bool splitShowsIconOnly: islandState === "split" && osdProgress < 0 && osdCustomText === ""
        readonly property bool splitUsesExtendedLayout: splitShowsProgress || splitShowsText
        // The volume OSD carries a 20-step (5% each) textual bar and needs a
        // wider capsule than the legacy icon + slider layout.
        readonly property real splitCapsuleWidth: splitShowsProgress
            ? (splitIcon === "VOL" ? 360 : 228)
            : (splitShowsText ? 200 : 118)
        readonly property bool canShowSideSwipe: false
        readonly property real rightSwipeProgress: Math.max(0, swipeTransitionProgress)
        readonly property var customLeftItems: systemState.customLeftItems
        readonly property bool hasCustomLeftItems: systemState.hasCustomLeftItems
        readonly property bool customSwipeVisible: !root.overviewVisible
            && hasCustomLeftItems
            && (
                capsuleMouseArea.sideSwipeInteractive
                ? swipeTransitionProgress < 0
                : (
                    islandState === "custom"
                    || (islandState === "normal" && swipeTransitionProgress < -0.001)
                    || (islandState === "split" && splitOriginSide === "left")
                    || (islandState === "long_capsule"
                        && (workspaceOriginSide === "left" || swipeTransitionProgress < 0))
                )
            )
        readonly property bool lyricsSwipeVisible: !root.overviewVisible && (
            capsuleMouseArea.sideSwipeInteractive
            ? swipeTransitionProgress >= 0
            : (
                islandState === "lyrics"
                || (islandState === "normal" && swipeTransitionProgress > 0.001)
                || (islandState === "split" && splitOriginSide === "right")
                || (islandState === "long_capsule"
                    && (workspaceOriginSide === "right" || swipeTransitionProgress > 0))
            )
        )
        readonly property bool expandedLayerVisible: !root.overviewVisible && islandState === "expanded"
        readonly property bool bluetoothExpandedLayerVisible: !root.overviewVisible && islandState === "bluetooth_expanded"
        readonly property bool notificationLayerVisible: !root.overviewVisible && islandState === "notification"
        readonly property int notificationCount: notifications.length
        readonly property bool controlCenterLayerVisible: !root.overviewVisible && islandState === "control_center"
        readonly property bool wifiLayerVisible: !root.overviewVisible && islandState === "wifi"
        readonly property bool bluetoothLayerVisible: !root.overviewVisible && islandState === "bluetooth"
        readonly property bool connectivityLayerVisible: wifiLayerVisible || bluetoothLayerVisible
        readonly property var activePlayer: mediaController.activePlayer
        readonly property bool playerIsPlaying: mediaController.isPlaying
        readonly property string lyricsDisplayText: mediaController.displayText
        readonly property string currentTrack: mediaController.currentTrack
        readonly property string currentArtist: mediaController.currentArtist
        readonly property string currentArtUrl: mediaController.currentArtUrl
        readonly property real trackProgress: mediaController.trackProgress
        readonly property string timePlayed: mediaController.timePlayed
        readonly property string timeTotal: mediaController.timeTotal
        readonly property bool screenRecordingActive: root.screenRecordingActive
        readonly property var bluetoothDevices: bluetoothConnectionTracker.devices
        readonly property var overviewView: overviewLoader.item && overviewLoader.item.overviewView
            ? overviewLoader.item.overviewView
            : null
        readonly property bool normalClockVisible: islandState === "normal"
            && Math.abs(swipeTransitionProgress) < 0.001

        function workspaceAppsLabel(wsId) {
            const windows = hyprlandData ? (hyprlandData.windowList || []) : [];
            const names = [];
            const seen = {};
            for (let index = 0; index < windows.length; index++) {
                const entry = windows[index];
                if (!entry || !entry.workspace) continue;
                if (Number(entry.workspace.id) !== Number(wsId)) continue;

                let name = String(entry.class || "").trim();
                if (name === "") name = String(entry.title || "").trim();
                if (name === "") continue;

                const key = name.toLowerCase();
                if (seen[key]) continue;
                seen[key] = true;
                names.push(name.charAt(0).toUpperCase() + name.slice(1));
            }

            if (names.length === 0)
                return "Workspace " + wsId;
            return names.join(", ");
        }

        readonly property string currentWorkspaceLabel: workspaceAppsLabel(currentWs)

        TextMetrics {
            id: workspaceLabelMetrics
            font.family: root.textFontFamily
            font.pixelSize: 17
            font.weight: Font.Medium
            text: islandContainer.currentWorkspaceLabel
        }

        // Workspace labels are allowed to be narrower than the idle clock
        // capsule: a short app/workspace name should shrink to its content.
        readonly property real workspaceCapsuleWidth: Math.max(
            64,
            Math.min(440, Math.ceil(workspaceLabelMetrics.advanceWidth + 36))
        )

        onControlCenterLayerVisibleChanged: {
            if (!controlCenterLayerVisible) {
                if (controlCenterLoader.item)
                    controlCenterLoader.item.closeConnectivityPanels();
                else
                    root.closeAllConnectivityDetails();
            }
        }

        Behavior on contentMorphProgress {
            NumberAnimation {
                duration: islandContainer.contentMorphProgress > 0
                    ? mainCapsule.contentFadeInDuration
                    : mainCapsule.contentFadeOutDuration
                easing.type: Easing.OutCubic
            }
        }

        onCustomLeftItemsChanged: {
            if (restingState === "custom" && !hasCustomLeftItems) {
                restingState = "normal";

                if (islandState === "custom"
                        || (islandState === "split" && splitOriginSide === "left")
                        || (islandState === "long_capsule" && workspaceOriginSide === "left")) {
                    restoreRestingCapsule(true);
                } else {
                    applyRestingVisuals();
                }
            } else if (restingState === "custom") {
                syncCustomCapsuleWidth();
            }
        }

        IslandMprisController {
            id: mediaController

            expanded: islandContainer.islandState === "expanded"
        }

        BluetoothConnectionTracker {
            id: bluetoothConnectionTracker

            onAdapterChanged: islandContainer.bluetoothExpandedDevice = null

            onNewConnection: function(device) {
                islandContainer.showBluetoothExpanded(device);
            }
        }

        IslandSystemState {
            id: systemState

            configuredLeftSwipeItems: userConfig.dynamicIslandLeftSwipeItems
            timeText: timeObj.currentTime
            dateText: timeObj.currentDateLabel
            currentWorkspace: islandContainer.currentWs
            customSwipeActive: customSwipeLoader.active

            onTransientRequested: function(icon, progress, text) {
                islandContainer.showTransientCapsule(icon, progress, text);
            }
        }

        HyprlandWorkspaceTracker {
            id: workspaceTracker

            hyprMonitor: root.hyprMonitor
            monitorName: root.hyprMonitorName
            monitorFocused: root.monitorFocused

            onWorkspaceSynced: function(workspaceId) {
                islandContainer.currentWs = workspaceId;
            }

            onWorkspaceActivated: function(workspaceId) {
                islandContainer.showWorkspaceCapsule(workspaceId);
            }
        }

        Behavior on osdProgress {
            enabled: islandContainer.osdProgressAnimationEnabled

            SmoothedAnimation { velocity: 1.2; duration: 180; easing.type: Easing.InOutQuad }
        }
        Behavior on swipeTransitionProgress {
            NumberAnimation {
                duration: capsuleMouseArea.sideSwipeInteractive ? 0 : islandContainer.swipeAnimationDuration
                easing.type: Easing.OutCubic
            }
        }

        Keys.onPressed: (event) => {
            if (!root.overviewVisible) return;

            if ((event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Backtab) {
                hyprDispatch.focusWorkspace("r-1");
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                hyprDispatch.focusWorkspace("r+1");
                event.accepted = true;
            }
        }

        function handleConfiguredClickAction(actionName) {
            switch (actionName) {
            case "":
            case "none":
                return;
            case "toggleExpandedPlayer":
                if (islandState === "expanded") {
                    autoHideTimer.stop();
                    smartRestoreState();
                } else {
                    showExpandedPlayer(false);
                }
                return;
            case "openExpandedPlayer":
                showExpandedPlayer(false);
                return;
            case "closeExpandedPlayer":
                if (islandState === "expanded")
                    smartRestoreState();
                return;
            // Legacy control_center actions are kept for config compatibility
            // but now just dismiss back to idle (control_center was removed).
            case "toggleControlCenter":
            case "openControlCenter":
            case "closeControlCenter":
                smartRestoreState();
                return;
            case "toggleOverview":
                root.toggleOverviewEverywhere();
                return;
            case "openOverview":
                root.openOverviewEverywhere();
                return;
            case "closeOverview":
                root.closeOverviewEverywhere();
                return;
            case "toggleLyrics":
                if (restingState === "lyrics")
                    showTimeCapsule();
                else
                    showLyricsCapsule();
                return;
            case "showLyrics":
                showLyricsCapsule();
                return;
            case "showTime":
                showTimeCapsule();
                return;
            case "restoreRestingCapsule":
                smartRestoreState();
                return;
            default:
            }
        }

        function clamp01(value) {
            return Math.max(0, Math.min(1, value));
        }

        function normalizeRestingState(nextState) {
            if (nextState === "lyrics") return "lyrics";
            if (nextState === "custom" && hasCustomLeftItems) return "custom";
            return "normal";
        }

        function restingStateProgress(nextState) {
            switch (normalizeRestingState(nextState)) {
            case "custom":
                return -1;
            case "lyrics":
                return 1;
            default:
                return 0;
            }
        }

        function restingStateSide(nextState) {
            switch (normalizeRestingState(nextState)) {
            case "custom":
                return "left";
            case "lyrics":
                return "right";
            default:
                return "none";
            }
        }

        function swipeRestProgressForState() {
            switch (islandState) {
            case "custom":
                return -1;
            case "lyrics":
                return 1;
            default:
                return 0;
            }
        }

        function currentTransientOriginSide() {
            switch (islandState) {
            case "custom":
                return "left";
            case "lyrics":
                return "right";
            case "long_capsule":
                return workspaceOriginSide;
            case "split":
                return splitOriginSide;
            default:
                return "none";
            }
        }

        function setOsdProgress(nextProgress, animate) {
            osdProgressAnimationReset.stop();
            osdProgressAnimationEnabled = animate;
            osdProgress = nextProgress;
            if (!animate) osdProgressAnimationReset.restart();
        }

        function abortSideTransientMode() {
            sideTransientRestoreTimer.stop();
            workspaceOriginSide = "none";
            splitOriginSide = "none";
        }

        function clearTransientCapsule() {
            setOsdProgress(-1.0, false);
            osdCustomText = "";
            // Notification fields are intentionally not cleared here: the
            // notification loader takes ~140ms to fade out and would otherwise
            // re-render with empty fields, flashing the "New notification" +
            // bell empty-state. The fields are overwritten by addNotification
            // when the next notification arrives.
            bluetoothExpandedDevice = null;
        }

        function cleanNotificationText(text) {
            return String(text === undefined || text === null ? "" : text)
                .replace(/<[^>]*>/g, " ")
                .replace(/&nbsp;/g, " ")
                .replace(/&amp;/g, "&")
                .replace(/&quot;/g, "\"")
                .replace(/&lt;/g, "<")
                .replace(/&gt;/g, ">")
                .replace(/\s+/g, " ")
                .trim();
        }

        function notificationContentText(notification) {
            if (!notification)
                return "New notification";
            if (notification.summary !== "" && notification.body !== "" && notification.body !== notification.summary)
                return notification.summary + "  " + notification.body;
            if (notification.summary !== "")
                return notification.summary;
            if (notification.body !== "")
                return notification.body;
            return "New notification";
        }

        function latestNotification() {
            return notifications.length > 0 ? notifications[notifications.length - 1] : null;
        }

        function syncLatestNotificationFields() {
            const latest = latestNotification();
            if (!latest) {
                notificationAppName = "";
                notificationAppIcon = "";
                notificationSummary = "";
                notificationBody = "";
                return;
            }

            notificationAppName = latest.appName;
            notificationAppIcon = latest.appIcon;
            notificationSummary = latest.summary;
            notificationBody = latest.body;
        }

        function addNotification(notificationRef, appName, appIcon, summary, body) {
            notifications = [{
                id: notificationNextId,
                notificationRef: notificationRef,
                appName: appName,
                appIcon: appIcon,
                summary: summary,
                body: body,
                createdAt: Date.now()
            }];
            notificationNextId += 1;
            syncLatestNotificationFields();
        }

        function expireAllNotifications() {
            for (let i = 0; i < notifications.length; i++) {
                const ref = notifications[i].notificationRef;
                if (ref && typeof ref.expire === "function")
                    ref.expire();
            }
            notifications = [];
        }

        function removeNotification(notificationId) {
            const dismissed = notifications.find((notification) => notification.id === notificationId);
            if (dismissed && dismissed.notificationRef && typeof dismissed.notificationRef.dismiss === "function")
                dismissed.notificationRef.dismiss();

            const nextNotifications = notifications.filter((notification) => notification.id !== notificationId);
            notifications = nextNotifications;

            if (notifications.length === 0) {
                // Intentionally leave the notification fields populated with the
                // last-shown content so the loader fades out displaying that
                // notification instead of flashing the empty-state fallback
                // ("New notification" + bell) during the dismiss morph.
                if (islandState === "notification")
                    restoreRestingCapsule(true);
                return;
            }

            syncLatestNotificationFields();

            if (islandState === "notification")
                mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
        }

        function openNotification(notificationId) {
            console.log("[Dynis] Notification actions are not wired yet:", notificationId);
            removeNotification(notificationId);
        }

        function openLatestNotification() {
            const latest = latestNotification();
            if (latest)
                openNotification(latest.id);
        }

        function dismissLatestNotification() {
            const latest = latestNotification();
            if (latest)
                removeNotification(latest.id);
            else if (islandState === "notification")
                restoreRestingCapsule(true);
        }

        function prepareRestingCapsuleGeometry() {
            if (restingState === "custom")
                syncCustomCapsuleWidth();
            if (restingState === "lyrics")
                syncLyricsCapsuleWidth();
        }

        function applyRestingVisuals() {
            prepareRestingCapsuleGeometry();
            swipeTransitionProgress = restingStateProgress(restingState);
        }

        function sideSwipeRestProgressForProgress(progressValue) {
            if (progressValue <= -0.5) return -1;
            if (progressValue >= 0.5) return 1;
            return 0;
        }

        function sideSwipeRestWidthForProgress(progressValue) {
            if (progressValue <= -0.5) return customCapsuleWidth;
            if (progressValue >= 0.5) return lyricsCapsuleWidth;
            return root.normalCapsuleWidth;
        }

        function customSideSwipeDragDistance() {
            const view = customSwipeLoader.item;
            if (view && view.dragDistance > 0) return view.dragDistance;
            return Math.max(root.normalCapsuleWidth, customCapsuleWidth + 4);
        }

        function lyricsSideSwipeDragDistance() {
            const view = lyricsSwipeLoader.item;
            if (view && view.dragDistance > 0) return view.dragDistance;
            return Math.max(root.normalCapsuleWidth, lyricsCapsuleWidth + 2);
        }

        function sideSwipeDragDistanceForDirection(direction) {
            if (direction === "left") return customSideSwipeDragDistance();
            if (direction === "right") return lyricsSideSwipeDragDistance();
            return root.normalCapsuleWidth;
        }

        function advanceSideSwipeProgress(currentProgress, deltaX) {
            const minProgress = hasCustomLeftItems ? -1 : 0;
            let nextProgress = Math.max(minProgress, Math.min(1, currentProgress));
            let remainingDelta = deltaX;

            if (remainingDelta > 0) {
                if (nextProgress < 0) {
                    const leftDistance = Math.max(1, sideSwipeDragDistanceForDirection("left"));
                    const progressToCenter = Math.min(-nextProgress, remainingDelta / leftDistance);
                    nextProgress += progressToCenter;
                    remainingDelta -= progressToCenter * leftDistance;
                }

                if (remainingDelta > 0 && nextProgress < 1) {
                    const rightDistance = Math.max(1, sideSwipeDragDistanceForDirection("right"));
                    nextProgress = Math.min(1, nextProgress + remainingDelta / rightDistance);
                }
            } else if (remainingDelta < 0) {
                if (nextProgress > 0) {
                    const rightDistance = Math.max(1, sideSwipeDragDistanceForDirection("right"));
                    const progressToCenter = Math.min(nextProgress, -remainingDelta / rightDistance);
                    nextProgress -= progressToCenter;
                    remainingDelta += progressToCenter * rightDistance;
                }

                if (remainingDelta < 0 && nextProgress > minProgress) {
                    const leftDistance = Math.max(1, sideSwipeDragDistanceForDirection("left"));
                    nextProgress = Math.max(minProgress, nextProgress + remainingDelta / leftDistance);
                }
            }

            return Math.max(minProgress, Math.min(1, nextProgress));
        }

        function resolveSideSwipeSettle(startProgress, finalProgress) {
            let settleAction = "";
            let settleProgress = sideSwipeRestProgressForProgress(startProgress);
            let settleWidth = sideSwipeRestWidthForProgress(startProgress);

            if (finalProgress >= 0.56) {
                settleAction = "lyrics";
                settleProgress = 1;
                settleWidth = lyricsCapsuleWidth;
            } else if (hasCustomLeftItems && finalProgress <= -0.56) {
                settleAction = "custom";
                settleProgress = -1;
                settleWidth = customCapsuleWidth;
            } else if (startProgress <= -0.5) {
                if (finalProgress >= -0.44) {
                    settleAction = "time";
                    settleProgress = 0;
                    settleWidth = root.normalCapsuleWidth;
                }
            } else if (startProgress >= 0.5) {
                if (finalProgress <= 0.44) {
                    settleAction = "time";
                    settleProgress = 0;
                    settleWidth = root.normalCapsuleWidth;
                }
            } else {
                settleAction = "time";
                settleProgress = 0;
                settleWidth = root.normalCapsuleWidth;
            }

            return {
                action: settleAction,
                progress: settleProgress,
                width: settleWidth
            };
        }

        function beginSideSwipeSettle(targetWidth) {
            sideSwipeSettling = true;
            mainCapsule.displayedWidth = targetWidth;
            sideSwipeSettleReset.restart();
        }

        function cancelSideSwipeSettle() {
            sideSwipeSettleReset.stop();
            sideSwipeSettling = false;
        }

        function finishSideSwipeSettle() {
            sideSwipeSettling = false;
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
        }

        function restartAutoHideTimer(duration) {
            autoHideTimer.interval = duration === undefined ? defaultAutoHideInterval : duration;
            autoHideTimer.restart();
        }

        function stopAutoHideTimer() {
            autoHideTimer.stop();
            autoHideTimer.interval = defaultAutoHideInterval;
        }

        function showTransientCapsule(icon, progress, customText) {
            if (progress === undefined)    progress = -1.0;
            if (customText === undefined)  customText = "";

            if (blocksTransientSplit) return;

            const nextProgress = progress >= 0 ? progress : -1.0;
            const animateProgress = islandState === "split" && osdProgress >= 0 && nextProgress >= 0;
            const animateFromSide = currentTransientOriginSide();

            abortSideTransientMode();
            splitIcon = icon;
            osdCustomText = customText;
            setOsdProgress(nextProgress, animateProgress);
            splitOriginSide = animateFromSide;
            islandState = "split";
            swipeTransitionProgress = 0;
            restartAutoHideTimer();
        }

        function showNotificationCapsule(notificationRef, appName, appIcon, summary, body) {
            if (root.overviewVisible || islandState === "control_center" || islandState === "expanded") {
                if (notificationRef && typeof notificationRef.dismiss === "function")
                    notificationRef.dismiss();
                return;
            }

            const cleanedAppName = cleanNotificationText(appName);
            const cleanedAppIcon = cleanNotificationText(appIcon);
            const cleanedSummary = cleanNotificationText(summary);
            const cleanedBody = cleanNotificationText(body);
            const resolvedSummary = cleanedSummary !== ""
                ? cleanedSummary
                : (cleanedBody !== "" ? cleanedBody : "New notification");

            abortSideTransientMode();
            clearTransientCapsule();
            addNotification(
                notificationRef,
                cleanedAppName !== "" ? cleanedAppName : "Notification",
                cleanedAppIcon,
                resolvedSummary,
                cleanedSummary !== "" ? cleanedBody : ""
            );

            if (root.fullscreenShellHidden)
                return;

            islandState = "notification";
            restartAutoHideTimer(notificationAutoHideInterval);
        }

        function suppressCapsuleClick() {
            capsuleMouseArea.suppressNextClick = true;
            swipeSuppressReset.restart();
        }

        function restoreRestingCapsule(forceImmediate) {
            if (forceImmediate === undefined) forceImmediate = false;
            const normalizedRestingState = normalizeRestingState(restingState);
            const targetSide = restingStateSide(normalizedRestingState);
            const shouldAnimateToSide = targetSide !== "none"
                && ((islandState === "long_capsule" && workspaceOriginSide === targetSide)
                    || (islandState === "split" && splitOriginSide === targetSide));

            if (!forceImmediate && shouldAnimateToSide) {
                expandedByPlayerAutoOpen = false;
                prepareRestingCapsuleGeometry();
                swipeTransitionProgress = restingStateProgress(normalizedRestingState);
                stopAutoHideTimer();
                sideTransientRestoreTimer.restart();
                return;
            }

            abortSideTransientMode();
            prepareRestingCapsuleGeometry();
            islandState = normalizedRestingState;
            clearTransientCapsule();
            applyRestingVisuals();
            expandedByPlayerAutoOpen = false;
            stopAutoHideTimer();
        }

        function setRestingState(nextState) {
            restingState = normalizeRestingState(nextState);
        }

        function smartRestoreState() {
            restoreRestingCapsule();
        }

        function showRestingCapsule(nextState) {
            setRestingState(nextState);
            restoreRestingCapsule();
            stopAutoHideTimer();
        }

        function showExpandedPlayer(autoOpened) {
            if (root.fullscreenShellHidden)
                return;

            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "expanded";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            expandedByPlayerAutoOpen = autoOpened;
            if (autoOpened) restartAutoHideTimer(playerAutoHideInterval);
            else stopAutoHideTimer();
        }

        function showConnectivityIsland(kind) {
            if (root.fullscreenShellHidden || root.overviewVisible)
                return;
            if (kind !== "wifi" && kind !== "bluetooth")
                return;

            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = kind;
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function showBluetoothExpanded(device) {
            if (!device || root.fullscreenShellHidden || root.overviewVisible
                    || islandState === "control_center" || islandState === "notification")
                return;

            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            bluetoothExpandedDevice = device;
            islandState = "bluetooth_expanded";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            expandedByPlayerAutoOpen = false;
            restartAutoHideTimer(bluetoothExpandedAutoHideInterval);
        }

        function showControlCenter() {
            if (root.fullscreenShellHidden)
                return;

            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "control_center";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function showCustomCapsule() {
            if (!hasCustomLeftItems) {
                showTimeCapsule();
                return;
            }

            systemState.refreshMissingValues();
            showRestingCapsule("custom");
        }

        function showLyricsCapsule() {
            showRestingCapsule("lyrics");
        }

        function showTimeCapsule() {
            showRestingCapsule("normal");
        }

        function showWorkspaceCapsule(wsId) {
            currentWs = wsId;
            if (islandState === "control_center" || islandState === "notification") return;
            const animateFromSide = currentTransientOriginSide();
            clearTransientCapsule();
            sideTransientRestoreTimer.stop();
            workspaceOriginSide = animateFromSide;
            splitOriginSide = "none";
            islandState = "long_capsule";
            swipeTransitionProgress = 0;
            restartAutoHideTimer();
        }

        Timer {
            id: autoHideTimer
            interval: islandContainer.defaultAutoHideInterval
            onTriggered: {
                if (islandContainer.islandState === "notification")
                    islandContainer.expireAllNotifications();
                islandContainer.smartRestoreState();
            }
        }
        Timer {
            id: osdProgressAnimationReset
            interval: 0
            onTriggered: islandContainer.osdProgressAnimationEnabled = true
        }
        Timer {
            id: sideTransientRestoreTimer
            interval: islandContainer.swipeAnimationDuration
            onTriggered: {
                islandContainer.workspaceOriginSide = "none";
                islandContainer.splitOriginSide = "none";
                islandContainer.prepareRestingCapsuleGeometry();
                islandContainer.islandState = islandContainer.normalizeRestingState(islandContainer.restingState);
                islandContainer.clearTransientCapsule();
                islandContainer.applyRestingVisuals();
                islandContainer.expandedByPlayerAutoOpen = false;
            }
        }
        Timer {
            id: sideSwipeSettleReset
            interval: mainCapsule.morphDuration
            onTriggered: islandContainer.finishSideSwipeSettle()
        }

        Timer {
            id: contentMorphRevealTimer
            interval: mainCapsule.contentFadeInDelay
            repeat: false
            onTriggered: islandContainer.contentMorphProgress = 1
        }

        function restartContentMorph() {
            contentMorphRevealTimer.stop();

            if (capsuleMouseArea.sideSwipeInteractive
                    || sideSwipeSettling
                    || root.overviewVisible
                    || islandState === "normal") {
                contentMorphProgress = 1;
                return;
            }

            contentMorphProgress = 0;
            contentMorphRevealTimer.restart();
        }

        function syncCustomCapsuleWidth() {
            const view = customSwipeLoader.item;
            if (!view) return;
            customCapsuleWidth = Math.max(188, Math.min(root.width - 48, view.preferredWidth));
        }

        function syncLyricsCapsuleWidth() {
            const view = lyricsSwipeLoader.item;
            if (!view) return;
            lyricsCapsuleWidth = Math.max(188, Math.min(root.width - 48, view.preferredWidth));
        }

        onCurrentTrackChanged: {
            if (userConfig.disableAutoExpandOnTrackChange) return;
            if (!playerIsPlaying) return;
            if (currentTrack !== ""
                    && islandState !== "control_center"
                    && islandState !== "notification"
                    && islandState !== "bluetooth_expanded") {
                if (islandState === "expanded" && !expandedByPlayerAutoOpen) return;
                showExpandedPlayer(true);
            }
        }

        onPlayerIsPlayingChanged: {
            if (userConfig.disableAutoExpandOnTrackChange) return;
            if (!playerIsPlaying) return;
            if (currentTrack === "") return;
            if (islandState === "control_center"
                    || islandState === "notification"
                    || islandState === "bluetooth_expanded"
                    || islandState === "wifi"
                    || islandState === "bluetooth") {
                return;
            }
            if (islandState === "expanded" && !expandedByPlayerAutoOpen) return;
            showExpandedPlayer(true);
        }

        // --- UI 渲染：灵动岛主干 ---
        Rectangle {
            id: mainCapsule
            z: 5
            property int morphDuration: 400
            readonly property int springMorphDuration: 380
            readonly property real springOvershoot: 1.05
            readonly property int contentFadeInDelay: 70
            readonly property int contentFadeInDuration: 180
            readonly property int contentFadeOutDuration: 140
            readonly property int contentMorphDuration: contentFadeInDuration
            readonly property real maxCornerRadius: 30
            readonly property bool usesWaybarVisualStyle: !root.overviewVisible
                && ["normal", "long_capsule", "split", "notification", "custom", "lyrics"].indexOf(islandContainer.islandState) !== -1
            property real outlineWidth: root.overviewContentVisible ? 1 : 0
            property color outlineColor: root.overviewContentVisible
                ? root.overviewCapsuleBorderColor
                : (usesWaybarVisualStyle ? root.capsuleLightBorderColor : StyleTokens.clearBlack)
            property real displayedWidth: baseTargetWidth
            readonly property real visualRadius: root.overviewContentVisible
                ? root.overviewCapsuleRadius
                : (islandContainer.islandState === "notification"
                    ? Math.max(0, Math.min(width / 2, height / 2))
                    : Math.max(0, Math.min(width / 2, height / 2, maxCornerRadius)))
            readonly property real baseTargetWidth: {
                if (root.overviewVisible) return root.overviewCapsuleWidth;
                if (sideTransientRestoreTimer.running) {
                    if (islandContainer.restingState === "lyrics"
                            && ((islandContainer.islandState === "split" && islandContainer.splitOriginSide === "right")
                                || (islandContainer.islandState === "long_capsule" && islandContainer.workspaceOriginSide === "right"))) {
                        return islandContainer.lyricsCapsuleWidth;
                    }

                    if (islandContainer.restingState === "custom"
                            && ((islandContainer.islandState === "split" && islandContainer.splitOriginSide === "left")
                                || (islandContainer.islandState === "long_capsule" && islandContainer.workspaceOriginSide === "left"))) {
                        return islandContainer.customCapsuleWidth;
                    }
                }

                switch (islandContainer.islandState) {
                case "normal":
                    return centralBarLayer ? centralBarLayer.preferredWidth : root.normalCapsuleWidth;
                case "split":
                    return islandContainer.splitCapsuleWidth;
                case "long_capsule":
                    return islandContainer.workspaceCapsuleWidth;
                case "custom":
                    return islandContainer.customCapsuleWidth;
                case "lyrics":
                    return islandContainer.lyricsCapsuleWidth;
                case "control_center":
                    return 420;
                case "wifi":
                case "bluetooth":
                    return root.connectivityDetailWidth + 48;
                case "expanded":
                case "bluetooth_expanded":
                    return 400;
                case "notification":
                    if (!notificationLoader.item) return 272;
                    return Math.max(
                        notificationLoader.item.minimumWidth,
                        Math.min(notificationLoader.item.maximumWidth, notificationLoader.item.preferredWidth)
                    );
                default:
                    return root.normalCapsuleWidth;
                }
            }
            readonly property real targetHeight: {
                if (root.overviewVisible) return root.overviewCapsuleHeight;

                switch (islandContainer.islandState) {
                case "control_center":
                    return 320 + (controlCenterLoader.item ? controlCenterLoader.item.controlCenterExtraHeight : 32);
                case "wifi":
                case "bluetooth":
                    return root.connectivityDetailHeight + 32;
                case "expanded":
                case "bluetooth_expanded":
                    return 165;
                case "notification":
                    return notificationLoader.item
                        ? notificationLoader.item.preferredHeight
                        : 56;
                case "normal":
                    // The expanded grid is 50px tall; 3px padding on both
                    // sides preserves the clock's idle position and keeps the
                    // two rows vertically balanced.
                    return centralBarLayer && centralBarLayer.detailsMode ? 56 : root.sideBarHeight;
                default:
                    return root.sideBarHeight;
                }
            }
            readonly property real targetRadius: {
                if (root.overviewVisible) return root.overviewCapsuleRadius;

                switch (islandContainer.islandState) {
                case "control_center":
                    return 28;
                case "expanded":
                case "bluetooth_expanded":
                    return 32;
                case "notification":
                    return mainCapsule.targetHeight / 2;
                default:
                    return root.sideBarRadius;
                }
            }
            function sideSwipeWidthForProgress(progressValue) {
                if (progressValue < 0)
                    return root.normalCapsuleWidth
                        + (islandContainer.customCapsuleWidth - root.normalCapsuleWidth)
                        * islandContainer.clamp01(-progressValue);
                if (progressValue > 0)
                    return root.normalCapsuleWidth
                        + (islandContainer.lyricsCapsuleWidth - root.normalCapsuleWidth)
                        * islandContainer.clamp01(progressValue);
                return root.normalCapsuleWidth;
            }
            readonly property real sideSwipePreviewWidth: mainCapsule.sideSwipeWidthForProgress(
                islandContainer.swipeTransitionProgress
            )
            color: root.overviewContentVisible ? root.overviewCapsuleColor : StyleTokens.transparent
            y: root.sideBarY
            anchors.horizontalCenter: parent.horizontalCenter
            clip: true
            width: displayedWidth
            height: targetHeight
            radius: visualRadius
            topLeftRadius: visualRadius
            topRightRadius: visualRadius
            bottomLeftRadius: visualRadius
            bottomRightRadius: visualRadius

            LiquidGlassSurface {
                anchors.fill: parent
                // The optical carrier is a separate small layer surface below
                // this Overlay UI; keeping it out of this wide parent prevents
                // a second blur pass with no local refractive edge.
                visible: false
                cornerRadius: mainCapsule.visualRadius
                tint: Qt.rgba(0, 0, 0, 0.004)
                edgeColor: "transparent"
                edgeWidth: 0
            }

            HoverHandler {
                id: capsuleHoverHandler

                enabled: !root.overviewVisible
                    && (islandContainer.islandState === "normal"
                        || islandContainer.islandState === "long_capsule")
            }

            // Scroll anywhere over the hovered capsule to cycle workspaces.
            // Keep the same e±1 semantics as the Hyprland mouse bindings and
            // scope it to the monitor owning this island.
            WheelHandler {
                id: capsuleWorkspaceWheel
                enabled: capsuleHoverHandler.hovered
                    && !root.overviewVisible
                    && (islandContainer.islandState === "normal"
                        || islandContainer.islandState === "long_capsule")
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (wheel) => {
                    if (wheel.angleDelta.y === 0 && wheel.pixelDelta.y === 0)
                        return;

                    const forward = wheel.angleDelta.y !== 0
                        ? wheel.angleDelta.y > 0
                        : wheel.pixelDelta.y > 0;
                    Hyprland.dispatch("hl.dsp.focus({ workspace = \""
                        + (forward ? "e+1" : "e-1")
                        + "\", on_current_monitor = true })");
                    wheel.accepted = true;
                }
            }

            onBaseTargetWidthChanged: {
                if (!capsuleMouseArea.sideSwipeInteractive && !islandContainer.sideSwipeSettling)
                    displayedWidth = baseTargetWidth;
            }

            Behavior on displayedWidth  {
                NumberAnimation {
                    duration: capsuleMouseArea.sideSwipeInteractive ? 0 : mainCapsule.springMorphDuration
                    easing.type: islandContainer.morphSoftEasingActive ? Easing.OutCubic : Easing.OutBack
                    easing.overshoot: mainCapsule.springOvershoot
                }
            }
            Behavior on height {
                enabled: !(controlCenterLoader.item && controlCenterLoader.item.batteryDrawerMoving)

                NumberAnimation {
                    duration: mainCapsule.springMorphDuration
                    easing.type: islandContainer.morphSoftEasingActive ? Easing.OutCubic : Easing.OutBack
                    easing.overshoot: mainCapsule.springOvershoot
                }
            }
            Behavior on color { ColorAnimation { duration: mainCapsule.contentMorphDuration; easing.type: Easing.OutCubic } }
            Behavior on outlineWidth { NumberAnimation { duration: mainCapsule.contentMorphDuration; easing.type: Easing.OutCubic } }
            Behavior on outlineColor { ColorAnimation { duration: mainCapsule.contentMorphDuration; easing.type: Easing.OutCubic } }
            border.width: outlineWidth
            border.color: outlineColor

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(parent.radius - 1, 0)
                color: StyleTokens.transparent
                border.width: 1
                border.color: StyleTokens.overviewInnerBorder
                opacity: root.overviewContentVisible ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.overviewContentVisible ? 260 : 140
                        easing.type: Easing.InOutQuad
                    }
                }
            }


            MouseArea {
                id: capsuleMouseArea
                anchors.fill: parent
                z: -1
                enabled: !root.overviewVisible && twoFingerTouchArea.touchPoints.length < 2
                acceptedButtons: root.dynamicIslandAcceptedButtons
                preventStealing: true
                property real swipeStartX: 0
                property real swipeStartY: 0
                property real swipeStartProgress: 0
                property real swipeLastX: 0
                readonly property real sideSwipeVerticalTolerance: 24
                property bool swipeArmed: false
                property bool swipeMoved: false
                property bool sideSwipeInteractive: false
                property bool suppressNextClick: false
                property bool preparedOverviewOnPress: false

                Timer {
                    id: swipeSuppressReset
                    interval: 180
                    repeat: false
                    onTriggered: capsuleMouseArea.suppressNextClick = false
                }

                onPressed: (mouse) => {
                    const mappedPoint = capsuleMouseArea.mapToItem(islandContainer, mouse.x, mouse.y);
                    swipeStartX = mappedPoint.x;
                    swipeStartY = mappedPoint.y;
                    islandContainer.cancelSideSwipeSettle();
                    swipeArmed = false;
                    swipeStartProgress = islandContainer.swipeTransitionProgress;
                    swipeLastX = mappedPoint.x;
                    swipeMoved = false;
                    sideSwipeInteractive = false;

                    let pressedAction = "";
                    if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandPrimaryButton)) {
                        pressedAction = userConfig.dynamicIslandPrimaryAction;
                    } else if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandSecondaryButton)) {
                        pressedAction = userConfig.dynamicIslandSecondaryAction;
                    }

                    preparedOverviewOnPress = pressedAction === "openOverview"
                        || (pressedAction === "toggleOverview" && root.overviewPhase === "closed");
                    if (preparedOverviewOnPress)
                        root.prepareOverviewEverywhere();
                }

                onPositionChanged: (mouse) => {
                    mouse.accepted = false;
                }

                onReleased: {
                    if (swipeMoved) {
                        if (preparedOverviewOnPress)
                            root.cancelPreparedOverviewEverywhere();
                        preparedOverviewOnPress = false;
                        suppressNextClick = true;
                        swipeSuppressReset.restart();
                    }
                    let settleResult = {
                        action: "",
                        progress: islandContainer.sideSwipeRestProgressForProgress(swipeStartProgress),
                        width: islandContainer.sideSwipeRestWidthForProgress(swipeStartProgress)
                    };

                    if (swipeArmed)
                        settleResult = islandContainer.resolveSideSwipeSettle(
                            swipeStartProgress,
                            islandContainer.swipeTransitionProgress
                        );

                    sideSwipeInteractive = false;

                    if (swipeArmed)
                        islandContainer.beginSideSwipeSettle(settleResult.width);
                    else
                        mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;

                    if (swipeArmed) {
                        switch (settleResult.action) {
                        case "time":
                            islandContainer.showTimeCapsule();
                            break;
                        case "custom":
                            islandContainer.showCustomCapsule();
                            break;
                        case "lyrics":
                            islandContainer.showLyricsCapsule();
                            break;
                        default:
                            islandContainer.swipeTransitionProgress = settleResult.progress;
                        }
                    } else {
                        islandContainer.swipeTransitionProgress = settleResult.progress;
                    }
                    swipeArmed = false;
                    swipeMoved = false;
                }

                onCanceled: {
                    if (preparedOverviewOnPress)
                        root.cancelPreparedOverviewEverywhere();
                    swipeArmed = false;
                    swipeMoved = false;
                    sideSwipeInteractive = false;
                    suppressNextClick = false;
                    preparedOverviewOnPress = false;
                    swipeSuppressReset.stop();
                    mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
                    islandContainer.swipeTransitionProgress = islandContainer.swipeRestProgressForState();
                }

                onClicked: (mouse) => {
                    if (suppressNextClick) {
                        swipeSuppressReset.stop();
                        suppressNextClick = false;
                        preparedOverviewOnPress = false;
                        return;
                    }

                    if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandPrimaryButton)) {
                        preparedOverviewOnPress = false;
                        // Player opening is deliberately owned by the clock hitbox
                        // below, not by the entire expanding capsule.
                        if (userConfig.dynamicIslandPrimaryAction !== "toggleExpandedPlayer")
                            islandContainer.handleConfiguredClickAction(userConfig.dynamicIslandPrimaryAction);
                        return;
                    }

                    if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandSecondaryButton)) {
                        preparedOverviewOnPress = false;
                        islandContainer.handleConfiguredClickAction(userConfig.dynamicIslandSecondaryAction);
                    }
                }
            }

            MultiPointTouchArea {
                id: twoFingerTouchArea
                anchors.fill: parent
                z: 0
                enabled: false
                mouseEnabled: false
                minimumTouchPoints: 2
                maximumTouchPoints: 2

                property real swipeStartX: 0
                property real swipeStartProgress: 0
                property bool swipeMoved: false

                onPressed: (touchPoints) => {
                    const centerPoint = islandContainer.mapFromItem(twoFingerTouchArea, 
                        (touchPoints[0].x + touchPoints[1].x) / 2,
                        (touchPoints[0].y + touchPoints[1].y) / 2);
                    swipeStartX = centerPoint.x;
                    swipeStartProgress = islandContainer.swipeTransitionProgress;
                    swipeMoved = false;
                    islandContainer.cancelSideSwipeSettle();
                }

                onUpdated: (touchPoints) => {
                    const centerPoint = islandContainer.mapFromItem(twoFingerTouchArea, 
                        (touchPoints[0].x + touchPoints[1].x) / 2,
                        (touchPoints[0].y + touchPoints[1].y) / 2);
                    
                    const deltaX = centerPoint.x - swipeStartX;
                    const nextProgress = islandContainer.advanceSideSwipeProgress(
                        swipeStartProgress,
                        deltaX
                    );

                    if (Math.abs(nextProgress - swipeStartProgress) > 0.03) {
                        swipeMoved = true;
                    }

                    islandContainer.swipeTransitionProgress = nextProgress;
                    mainCapsule.displayedWidth = mainCapsule.sideSwipePreviewWidth;
                }

                onReleased: {
                    if (swipeMoved) {
                        const settleResult = islandContainer.resolveSideSwipeSettle(
                            swipeStartProgress,
                            islandContainer.swipeTransitionProgress
                        );

                        islandContainer.beginSideSwipeSettle(settleResult.width);

                        switch (settleResult.action) {
                        case "time":
                            islandContainer.showTimeCapsule();
                            break;
                        case "custom":
                            islandContainer.showCustomCapsule();
                            break;
                        case "lyrics":
                            islandContainer.showLyricsCapsule();
                            break;
                        default:
                            islandContainer.swipeTransitionProgress = settleResult.progress;
                        }
                    } else {
                        islandContainer.swipeTransitionProgress = islandContainer.sideSwipeRestProgressForProgress(swipeStartProgress);
                    }
                    swipeMoved = false;
                }
            }



            Item {
                id: centralBarLayer

                anchors.fill: parent
                readonly property bool shouldShow: !root.overviewVisible && islandContainer.islandState === "normal"
                visible: shouldShow || opacity > 0.001
                opacity: shouldShow ? 1 : 0

                readonly property bool detailsMode: root.mainModPreviewActive || capsuleHoverHandler.hovered
                readonly property bool workspaceMode: detailsMode
                readonly property bool statusMode: detailsMode
                readonly property real horizontalPadding: 14
                readonly property real sideGap: 22
                readonly property real sideWidth: detailsMode ? Math.max(
                    integratedWorkspaceStrip.implicitWidth,
                    centralStatusStrip.implicitWidth
                ) : 0
                readonly property real trailingWidth: sideWidth
                readonly property real contentWidth: sideWidth * 2
                    + centralDateTimeText.implicitWidth + sideGap * 2
                readonly property real preferredWidth: Math.max(
                    root.normalCapsuleWidth,
                    Math.ceil(contentWidth + horizontalPadding * 2)
                )

                Behavior on opacity {
                    NumberAnimation {
                        duration: centralBarLayer.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Item {
                    id: centralContentLayer

                    anchors.fill: parent

                    WorkspaceStrip {
                        id: integratedWorkspaceStrip

                        x: centralDateTimeText.x - centralBarLayer.sideGap
                            - centralBarLayer.sideWidth
                        width: centralBarLayer.sideWidth
                        y: 3
                        visible: centralBarLayer.workspaceMode
                        monitorName: root.hyprMonitorName
                        activeWorkspaceId: root.currentMonitorWorkspaceId
                        textFontFamily: root.textFontFamily
                        itemSize: 24
                        spacing: 14
                    }

                    Text {
                        id: centralDateTimeText

                        anchors.horizontalCenter: parent.horizontalCenter
                        // The expanded island grows down from the top edge; the clock
                        // deliberately keeps its exact idle Y position.
                        y: (root.sideBarHeight - height) / 2
                        text: timeObj.currentBarLabel
                        color: StyleTokens.textPrimary
                        font.pixelSize: 17
                        font.family: root.timeFontFamily
                        font.weight: Font.Medium
                        font.letterSpacing: 0
                        wrapMode: Text.NoWrap

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.togglePlayerWindow()
                        }
                    }

                    Text {
                        id: centralVolumeBelowClock

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 33
                        text: islandContainer.isMuted
                            ? "VOL MUTE"
                            : "VOL " + root.formatUsagePercent(islandContainer.currentVolume)
                        color: StyleTokens.textPrimary
                        font.family: root.textFontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        opacity: centralBarLayer.detailsMode ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: centralBarLayer.detailsMode ? 180 : 100
                                easing.type: Easing.InOutQuad
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton)
                                    islandContainer.showControlCenter();
                                else
                                    SystemServices.launchDetached("wpctl", ["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                            }
                        }
                    }

                    Item {
                        id: centralTrailingSlot

                        x: centralDateTimeText.x + centralDateTimeText.implicitWidth
                            + centralBarLayer.sideGap
                        width: centralBarLayer.trailingWidth
                        height: parent.height
                        clip: true

                        Behavior on width {
                            NumberAnimation {
                                duration: mainCapsule.morphDuration
                                easing.type: Easing.OutQuint
                            }
                        }

                        Row {
                            id: centralWorkspaceStrip

                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            // Superseded by integratedWorkspaceStrip on the left of the
                            // clock. Keeping this legacy strip visible duplicates the
                            // workspace UI over the status slot on hover.
                            opacity: 0
                            visible: false

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: centralBarLayer.workspaceMode ? 180 : 100
                                    easing.type: Easing.InOutQuad
                                }
                            }

                            Repeater {
                                model: root.primaryWorkspaceCount

                                delegate: Rectangle {
                                    required property int index

                                    readonly property int workspaceId: index + 1
                                    readonly property bool activeWorkspace: workspaceId === root.currentMonitorWorkspaceId
                                    readonly property bool urgentWorkspace: root.workspaceHasUrgency(workspaceId)
                                    readonly property bool occupiedWorkspace: root.workspaceIsOccupied(workspaceId)

                                    width: centralWorkspaceLabel.implicitWidth + 8
                                    height: 18
                                    radius: 6
                                    color: urgentWorkspace
                                        ? root.barUrgentColor
                                        : (activeWorkspace ? root.barBorderColor : "transparent")
                                    border.width: activeWorkspace ? 1 : 0
                                    border.color: activeWorkspace ? Qt.rgba(161 / 255, 170 / 255, 180 / 255, 1.0) : "transparent"

                                    Text {
                                        id: centralWorkspaceLabel

                                        anchors.centerIn: parent
                                        text: String(parent.workspaceId)
                                        color: activeWorkspace
                                            ? StyleTokens.textPrimary
                                            : (occupiedWorkspace ? root.barTextMutedColor : Qt.rgba(138 / 255, 145 / 255, 154 / 255, 1.0))
                                        font.family: root.textFontFamily
                                        font.pixelSize: 17
                                        font.weight: Font.Medium
                                        renderType: Text.NativeRendering
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: hyprDispatch.focusWorkspace(parent.workspaceId)
                                    }
                                }
                            }
                        }

                        Row {
                            id: legacyCentralStatusStrip

                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            opacity: 0
                            visible: false

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: centralBarLayer.statusMode ? 180 : 100
                                    easing.type: Easing.InOutQuad
                                }
                            }

                            Item {
                                width: centralStatRow.implicitWidth + 12
                                height: 18

                                Row {
                                    id: centralStatRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Canvas {
                                        id: centralCpuSpark
                                        width: 34
                                        height: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        antialiasing: true
                                        onPaint: {
                                            const samples = root.shellRootController
                                                ? root.shellRootController.cpuSamples
                                                : [];
                                            root.drawStatSparkline(getContext("2d"), samples, StyleTokens.textMuted);
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "CPU " + root.formatUsagePercent(root.topBarCpuUsage)
                                        color: StyleTokens.textPrimary
                                        font.family: root.textFontFamily
                                        font.pixelSize: 17
                                        font.weight: Font.Medium
                                    }

                                    Canvas {
                                        id: centralRamSpark
                                        width: 34
                                        height: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        antialiasing: true
                                        onPaint: {
                                            const samples = root.shellRootController
                                                ? root.shellRootController.ramSamples
                                                : [];
                                            root.drawStatSparkline(getContext("2d"), samples, StyleTokens.textMuted);
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "RAM " + root.formatUsagePercent(root.topBarRamUsage)
                                        color: StyleTokens.textPrimary
                                        font.family: root.textFontFamily
                                        font.pixelSize: 17
                                        font.weight: Font.Medium
                                    }
                                }

                                Connections {
                                    target: root.shellRootController
                                    function onCpuSamplesChanged() { centralCpuSpark.requestPaint(); }
                                    function onRamSamplesChanged() { centralRamSpark.requestPaint(); }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: SystemServices.launchDetached("kitty", ["-e", "btop"])
                                }
                            }

                            Rectangle {
                                width: 24
                                height: 18
                                radius: 6
                                color: centralWifiArea.containsMouse ? root.barChipHoverColor : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: WifiController.enabled
                                        ? (WifiController.currentSsid !== "" ? "󰤨" : "󰤥")
                                        : "󰤮"
                                    color: StyleTokens.textPrimary
                                    font.family: root.iconFontFamily
                                    font.pixelSize: 17
                                }

                                MouseArea {
                                    id: centralWifiArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: islandContainer.showConnectivityIsland("wifi")
                                }
                            }

                            Rectangle {
                                width: 24
                                height: 18
                                radius: 6
                                color: centralBluetoothArea.containsMouse ? root.barChipHoverColor : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: !root.bluetoothAdapter || !root.bluetoothAdapter.enabled
                                        ? "󰂲"
                                        : (root.bluetoothConnected() ? "󰂱" : "󰂯")
                                    color: StyleTokens.textPrimary
                                    font.family: root.iconFontFamily
                                    font.pixelSize: 17
                                }

                                MouseArea {
                                    id: centralBluetoothArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: islandContainer.showConnectivityIsland("bluetooth")
                                }
                            }

                            Rectangle {
                                width: centralVolumeText.implicitWidth + 10
                                height: 18
                                radius: 6
                                color: centralVolumeArea.containsMouse ? root.barChipHoverColor : "transparent"

                                Text {
                                    id: centralVolumeText

                                    anchors.centerIn: parent
                                    text: root.volumeLabel()
                                    color: StyleTokens.textPrimary
                                    font.family: root.textFontFamily
                                    font.pixelSize: 17
                                    font.weight: Font.Medium
                                    renderType: Text.NativeRendering
                                }

                                MouseArea {
                                    id: centralVolumeArea

                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton)
                                            islandContainer.showControlCenter();
                                        else
                                            SystemServices.launchDetached("wpctl", ["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                                    }
                                }
                            }
                        }

                        Column {
                            id: centralStatusStrip

                            y: 3
                            spacing: 2
                            opacity: centralBarLayer.statusMode ? 1 : 0
                            visible: opacity > 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: centralBarLayer.statusMode ? 180 : 100
                                    easing.type: Easing.InOutQuad
                                }
                            }

                            Row {
                                height: 24
                                spacing: 2

                                Canvas {
                                    id: compactCpuSpark
                                    width: 0
                                    height: 14
                                    visible: false
                                    anchors.verticalCenter: parent.verticalCenter
                                    antialiasing: true
                                    onPaint: root.drawStatSparkline(getContext("2d"),
                                        root.shellRootController ? root.shellRootController.cpuSamples : [],
                                        StyleTokens.textMuted)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "CPU " + root.formatUsagePercent(root.topBarCpuUsage)
                                    color: StyleTokens.textPrimary
                                    font.family: root.textFontFamily
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }

                                RoundedAsciiBar {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.formatUsageBar(root.topBarCpuUsage, 8)
                                    textColor: StyleTokens.textMuted
                                    fontFamily: root.textFontFamily
                                    pixelSize: 13
                                }

                            }

                            Row {
                                height: 24
                                spacing: 2

                                Canvas {
                                    id: compactRamSpark
                                    width: 0
                                    height: 14
                                    visible: false
                                    anchors.verticalCenter: parent.verticalCenter
                                    antialiasing: true
                                    onPaint: root.drawStatSparkline(getContext("2d"),
                                        root.shellRootController ? root.shellRootController.ramSamples : [],
                                        StyleTokens.textMuted)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "RAM " + root.formatUsagePercent(root.topBarRamUsage)
                                    color: StyleTokens.textPrimary
                                    font.family: root.textFontFamily
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }

                                RoundedAsciiBar {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.formatUsageBar(root.topBarRamUsage, 8)
                                    textColor: StyleTokens.textMuted
                                    fontFamily: root.textFontFamily
                                    pixelSize: 13
                                }

                            }

                            Connections {
                                target: root.shellRootController
                                function onCpuSamplesChanged() { compactCpuSpark.requestPaint(); }
                                function onRamSamplesChanged() { compactRamSpark.requestPaint(); }
                            }
                        }
                    }
                }

            }

            Loader {
                id: customSwipeLoader
                anchors.fill: parent
                readonly property bool shouldShow: islandContainer.customSwipeVisible
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                opacity: shouldShow ? islandContainer.contentMorphOpacity : 0
                scale: shouldShow ? islandContainer.contentMorphScale : 0.98
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        unloadTimer.stop();
                        mounted = true;
                    } else {
                        unloadTimer.restart();
                    }
                }

                Timer {
                    id: unloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: customSwipeLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: customSwipeLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: customSwipeLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                onLoaded: islandContainer.syncCustomCapsuleWidth()

                sourceComponent: Component {
                    SwipeCustomInfoLayer {
                        items: islandContainer.customLeftItems
                        cavaLevels: islandContainer.cavaLevels
                        timeText: timeObj.currentBarLabel
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.heroFontFamily
                        timeFontFamily: root.heroFontFamily
                        minimumWidth: 188
                        maximumWidth: Math.max(188, root.width - 48)
                        transitionProgress: islandContainer.swipeTransitionProgress
                        recordingActive: islandContainer.screenRecordingActive
                        showSecondaryText: islandContainer.workspaceOriginSide !== "left"
                            && islandContainer.splitOriginSide !== "left"
                        showCondition: true
                        onPreferredWidthChanged: islandContainer.syncCustomCapsuleWidth()
                    }
                }
            }

            Loader {
                id: lyricsSwipeLoader
                anchors.fill: parent
                readonly property bool shouldShow: islandContainer.lyricsSwipeVisible
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                opacity: shouldShow ? islandContainer.contentMorphOpacity : 0
                scale: shouldShow ? islandContainer.contentMorphScale : 0.98
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        unloadTimer.stop();
                        mounted = true;
                    } else {
                        unloadTimer.restart();
                    }
                }

                Timer {
                    id: lyricsUnloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: lyricsSwipeLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: lyricsSwipeLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: lyricsSwipeLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                onLoaded: islandContainer.syncLyricsCapsuleWidth()

                sourceComponent: Component {
                    SwipeLyricsLayer {
                        lyricText: islandContainer.lyricsDisplayText
                        timeText: timeObj.currentBarLabel
                        textFontFamily: root.textFontFamily
                        timeFontFamily: root.timeFontFamily
                        textPixelSize: 17
                        minimumWidth: 188
                        maximumWidth: Math.max(188, root.width - 48)
                        transitionProgress: islandContainer.rightSwipeProgress
                        recordingActive: islandContainer.screenRecordingActive
                        showSecondaryText: islandContainer.workspaceOriginSide !== "right"
                            && islandContainer.splitOriginSide !== "right"
                        showCondition: true
                        onPreferredWidthChanged: islandContainer.syncLyricsCapsuleWidth()
                    }
                }
            }

            Loader {
                id: splitIconLoader
                anchors.fill: parent
                readonly property bool shouldShow: !root.overviewVisible && islandContainer.splitShowsIconOnly
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                opacity: shouldShow ? islandContainer.contentMorphOpacity : 0
                scale: shouldShow ? islandContainer.contentMorphScale : 0.98
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        splitIconUnloadTimer.stop();
                        mounted = true;
                    } else {
                        splitIconUnloadTimer.restart();
                    }
                }

                Timer {
                    id: splitIconUnloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: splitIconLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: splitIconLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: splitIconLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                sourceComponent: Component {
                    SplitIconLayer {
                        iconText: islandContainer.splitIcon
                        iconFontFamily: root.iconFontFamily
                        transitionProgress: islandContainer.swipeTransitionProgress
                        slideDirection: islandContainer.splitOriginSide
                        showCondition: true
                    }
                }
            }

            Loader {
                id: osdLayerLoader
                anchors.fill: parent
                readonly property bool shouldShow: !root.overviewVisible && islandContainer.splitUsesExtendedLayout
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                opacity: shouldShow ? islandContainer.contentMorphOpacity : 0
                scale: shouldShow ? islandContainer.contentMorphScale : 0.98
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        osdUnloadTimer.stop();
                        mounted = true;
                    } else {
                        osdUnloadTimer.restart();
                    }
                }

                Timer {
                    id: osdUnloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: osdLayerLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: osdLayerLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: osdLayerLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                sourceComponent: Component {
                    OsdLayer {
                        iconText: islandContainer.splitIcon
                        progress: islandContainer.osdProgress
                        customText: islandContainer.osdCustomText
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        transitionProgress: islandContainer.swipeTransitionProgress
                        slideDirection: islandContainer.splitOriginSide
                        showCondition: true
                    }
                }
            }

            Loader {
                id: workspaceLayerLoader
                anchors.fill: parent
                readonly property bool shouldShow: !root.overviewVisible
                    && islandContainer.islandState === "long_capsule"
                    && (islandContainer.workspaceOriginSide !== "none"
                        || Math.abs(islandContainer.swipeTransitionProgress) < 0.001)
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                opacity: shouldShow ? islandContainer.contentMorphOpacity : 0
                scale: shouldShow ? islandContainer.contentMorphScale : 0.98
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        workspaceUnloadTimer.stop();
                        mounted = true;
                    } else {
                        workspaceUnloadTimer.restart();
                    }
                }

                Timer {
                    id: workspaceUnloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: workspaceLayerLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: workspaceLayerLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: workspaceLayerLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                sourceComponent: Component {
                    WorkspaceLayer {
                        workspaceId: islandContainer.currentWs
                        displayText: islandContainer.currentWorkspaceLabel
                        textFontFamily: root.textFontFamily
                        textPixelSize: 17
                        animateVisibility: islandContainer.restingState === "normal"
                        transitionProgress: islandContainer.swipeTransitionProgress
                        showCondition: true
                        slideDirection: islandContainer.workspaceOriginSide
                    }
                }
            }

            Loader {
                id: expandedPlayerLoader
                anchors.fill: parent
                readonly property bool shouldShow: islandContainer.expandedLayerVisible
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                opacity: shouldShow ? islandContainer.contentMorphOpacity : 0
                scale: shouldShow ? islandContainer.contentMorphScale : 0.98
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        expandedPlayerUnloadTimer.stop();
                        mounted = true;
                    } else {
                        expandedPlayerUnloadTimer.restart();
                    }
                }

                Timer {
                    id: expandedPlayerUnloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: expandedPlayerLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: expandedPlayerLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: expandedPlayerLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                sourceComponent: Component {
                    ExpandedPlayerLayer {
                        currentArtUrl: islandContainer.currentArtUrl
                        currentTrack: islandContainer.currentTrack
                        currentArtist: islandContainer.currentArtist
                        timePlayed: islandContainer.timePlayed
                        timeTotal: islandContainer.timeTotal
                        trackProgress: islandContainer.trackProgress
                        activePlayer: islandContainer.activePlayer
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        showCondition: islandContainer.expandedLayerVisible
                        onControlPressed: islandContainer.suppressCapsuleClick()
                    }
                }
            }

            Loader {
                id: bluetoothExpandedLoader
                anchors.fill: parent
                readonly property bool shouldShow: islandContainer.bluetoothExpandedLayerVisible
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                opacity: shouldShow ? islandContainer.contentMorphOpacity : 0
                scale: shouldShow ? islandContainer.contentMorphScale : 0.98
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        bluetoothExpandedUnloadTimer.stop();
                        mounted = true;
                    } else {
                        bluetoothExpandedUnloadTimer.restart();
                    }
                }

                Timer {
                    id: bluetoothExpandedUnloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: bluetoothExpandedLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: bluetoothExpandedLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: bluetoothExpandedLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                sourceComponent: Component {
                    BluetoothExpandedLayer {
                        device: islandContainer.bluetoothExpandedDevice
                        volumeLevel: islandContainer.currentVolume
                        iconText: ""
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        showCondition: islandContainer.bluetoothExpandedLayerVisible
                    }
                }
            }

            Loader {
                id: notificationLoader
                anchors.fill: parent
                readonly property bool shouldShow: islandContainer.notificationLayerVisible
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                opacity: shouldShow ? islandContainer.contentMorphOpacity : 0
                scale: shouldShow ? islandContainer.contentMorphScale : 0.98
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        notificationUnloadTimer.stop();
                        mounted = true;
                    } else {
                        notificationUnloadTimer.restart();
                    }
                }

                Timer {
                    id: notificationUnloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: notificationLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: notificationLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: notificationLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                sourceComponent: Component {
                    NotificationLayer {
                        appName: islandContainer.notificationAppName
                        appIcon: islandContainer.notificationAppIcon
                        summary: islandContainer.notificationSummary
                        body: islandContainer.notificationBody
                        notifications: islandContainer.notifications
                        notificationCount: islandContainer.notificationCount
                        iconText: root.notificationStatusIcon
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: true
                        onDismissRequested: (notificationId) => islandContainer.removeNotification(notificationId)
                        onOpenRequested: (notificationId) => islandContainer.openNotification(notificationId)
                    }
                }
            }

            Loader {
                id: controlCenterLoader
                anchors.fill: parent
                readonly property bool shouldShow: islandContainer.controlCenterLayerVisible
                    || root.anyConnectivityDetailMounted
                    || islandContainer.connectivityLayerVisible
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                // Loader stays mounted as the wifi/bluetooth state provider, but
                // its visual UI is always hidden — control_center is no longer
                // a user-facing state.
                opacity: 0
                scale: 1
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        controlCenterUnloadTimer.stop();
                        mounted = true;
                    } else {
                        controlCenterUnloadTimer.restart();
                    }
                }

                Timer {
                    id: controlCenterUnloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: controlCenterLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: controlCenterLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: controlCenterLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                sourceComponent: Component {
                    ControlCenterLayer {
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        sliderIntroDelay: mainCapsule.morphDuration
                        currentTime: timeObj.currentTime
                        currentDateLabel: timeObj.currentDateLabel
                        batteryCapacity: islandContainer.batteryCapacity
                        isCharging: islandContainer.isCharging
                        volumeLevel: islandContainer.currentVolume
                        brightnessLevel: islandContainer.currentBrightness
                        currentWorkspace: islandContainer.currentWs
                        currentTrack: islandContainer.currentTrack
                        currentArtist: islandContainer.currentArtist
                        showCondition: islandContainer.controlCenterLayerVisible
                        onConnectivityPanelRequested: function(kind, open) {
                            root.setConnectivityDetailVisible(kind, open);
                        }
                    }
                }
            }

            Loader {
                id: connectivityPanelLoader
                anchors.fill: parent
                readonly property bool shouldShow: islandContainer.connectivityLayerVisible
                property bool mounted: shouldShow
                active: mounted
                asynchronous: false
                visible: shouldShow || opacity > 0.001
                enabled: shouldShow
                opacity: shouldShow ? islandContainer.contentMorphOpacity : 0
                scale: shouldShow ? islandContainer.contentMorphScale : 0.98
                transformOrigin: Item.Center

                onShouldShowChanged: {
                    if (shouldShow) {
                        connectivityPanelUnloadTimer.stop();
                        mounted = true;
                    } else {
                        connectivityPanelUnloadTimer.restart();
                    }
                }

                Timer {
                    id: connectivityPanelUnloadTimer
                    interval: mainCapsule.contentFadeOutDuration
                    repeat: false
                    onTriggered: connectivityPanelLoader.mounted = false
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: connectivityPanelLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: connectivityPanelLoader.shouldShow
                            ? mainCapsule.contentFadeInDuration
                            : mainCapsule.contentFadeOutDuration
                        easing.type: Easing.OutCubic
                    }
                }

                sourceComponent: Component {
                    ConnectivityDetailPanel {
                        provider: controlCenterLoader.item
                        panelKind: islandContainer.wifiLayerVisible ? "wifi" : "bluetooth"
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        presentationProgress: islandContainer.contentMorphOpacity
                    }
                }
            }

            Loader {
                id: overviewLoader

                anchors.fill: parent
                active: root.overviewLoaderActive
                asynchronous: false
                visible: root.overviewContentVisible

                onStatusChanged: {
                    if (status === Loader.Ready && root.overviewPreparing) {
                        root.beginOverviewOpening();
                    }
                }

                sourceComponent: Component {
                    WorkspaceOverviewScene {
                        screen: root.screen
                        showCondition: root.overviewVisible
                        previewsEnabled: root.overviewContentVisible
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        wallpaperPath: root.overviewWallpaperSource
                        windowCornerRadius: root.overviewWindowCornerRadius
                        onCloseRequested: root.closeOverviewEverywhere()
                    }
                }
            }

        }

    }

    Rectangle {
        id: leftBarPanel

        visible: false
        x: root.sideBarInset
        y: root.sideBarY
        height: root.sideBarHeight
        width: workspaceStripRow.implicitWidth + 18
        radius: root.sideBarRadius
        color: root.barBackgroundColor
        border.width: 0
        border.color: root.barBorderColor
        z: 4

        Row {
            id: workspaceStripRow

            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Repeater {
                model: root.primaryWorkspaceCount

                delegate: Rectangle {
                    required property int index

                    readonly property int workspaceId: index + 1
                    readonly property bool activeWorkspace: workspaceId === root.currentMonitorWorkspaceId
                    readonly property bool urgentWorkspace: root.workspaceHasUrgency(workspaceId)
                    readonly property bool occupiedWorkspace: root.workspaceIsOccupied(workspaceId)

                    width: workspaceLabel.implicitWidth + 8
                    height: 18
                    radius: 6
                    color: urgentWorkspace
                        ? root.barUrgentColor
                        : (activeWorkspace ? root.barBorderColor : "transparent")
                    border.width: activeWorkspace ? 1 : 0
                    border.color: activeWorkspace ? Qt.rgba(161 / 255, 170 / 255, 180 / 255, 1.0) : "transparent"

                    Text {
                        id: workspaceLabel

                        anchors.centerIn: parent
                        text: String(parent.workspaceId)
                        color: activeWorkspace
                            ? StyleTokens.textPrimary
                            : (occupiedWorkspace ? root.barTextMutedColor : Qt.rgba(138 / 255, 145 / 255, 154 / 255, 1.0))
                        font.family: root.textFontFamily
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hyprDispatch.focusWorkspace(parent.workspaceId)
                    }
                }
            }
        }
    }

    TopEdgeBlendCorner {
        x: leftBarPanel.x - width + 1
        y: root.sideBarY
        cutoutOnRight: false
        activeBlend: false
    }

    TopEdgeBlendCorner {
        x: leftBarPanel.x + leftBarPanel.width - 1
        y: root.sideBarY
        cutoutOnRight: true
        activeBlend: false
    }

    TopEdgeBlendCorner {
        x: mainCapsule.x - width + 1
        y: root.sideBarY
        cutoutOnRight: false
        activeBlend: false
    }

    TopEdgeBlendCorner {
        x: mainCapsule.x + mainCapsule.width - 1
        y: root.sideBarY
        cutoutOnRight: true
        activeBlend: false
    }

    BottomEdgeBlendCorner {
        id: leftBottomOuterBlend
        x: leftBarPanel.x
        y: leftBarPanel.y + leftBarPanel.height - 1
        cutoutOnRight: true
        activeBlend: false
        rotation: 90
        transformOrigin: Item.Center
    }

    Rectangle {
        id: rightBarPanel

        visible: false
        x: root.width - width - root.sideBarInset
        y: root.sideBarY
        height: root.sideBarHeight
        width: rightBarRow.implicitWidth + 20
        radius: root.sideBarRadius
        color: root.barBackgroundColor
        border.width: 0
        border.color: root.barBorderColor
        z: 4

        Row {
            id: rightBarRow

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Item {
                width: sideStatRow.implicitWidth + 12
                height: 18

                Row {
                    id: sideStatRow
                    anchors.centerIn: parent
                    spacing: 5

                    Canvas {
                        id: sideCpuSpark
                        width: 28
                        height: 12
                        anchors.verticalCenter: parent.verticalCenter
                        antialiasing: true
                        onPaint: {
                            const samples = root.shellRootController
                                ? root.shellRootController.cpuSamples
                                : [];
                            root.drawStatSparkline(getContext("2d"), samples, StyleTokens.textMuted);
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CPU " + root.formatUsagePercent(root.topBarCpuUsage)
                        color: StyleTokens.textPrimary
                        font.family: root.textFontFamily
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }

                    Canvas {
                        id: sideRamSpark
                        width: 28
                        height: 12
                        anchors.verticalCenter: parent.verticalCenter
                        antialiasing: true
                        onPaint: {
                            const samples = root.shellRootController
                                ? root.shellRootController.ramSamples
                                : [];
                            root.drawStatSparkline(getContext("2d"), samples, StyleTokens.textMuted);
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "RAM " + root.formatUsagePercent(root.topBarRamUsage)
                        color: StyleTokens.textPrimary
                        font.family: root.textFontFamily
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                }

                Connections {
                    target: root.shellRootController
                    function onCpuSamplesChanged() { sideCpuSpark.requestPaint(); }
                    function onRamSamplesChanged() { sideRamSpark.requestPaint(); }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SystemServices.launchDetached("kitty", ["-e", "btop"])
                }
            }

            Rectangle {
                id: wifiChip

                width: 24
                height: 18
                radius: 6
                color: wifiArea.containsMouse ? root.barChipHoverColor : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: WifiController.enabled
                        ? (WifiController.currentSsid !== "" ? "󰤨" : "󰤥")
                        : "󰤮"
                    color: StyleTokens.textPrimary
                    font.family: root.iconFontFamily
                    font.pixelSize: 15
                }

                MouseArea {
                    id: wifiArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: islandContainer.showConnectivityIsland("wifi")
                }
            }

            Rectangle {
                id: bluetoothChip

                width: 24
                height: 18
                radius: 6
                color: bluetoothArea.containsMouse ? root.barChipHoverColor : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: !root.bluetoothAdapter || !root.bluetoothAdapter.enabled
                        ? "󰂲"
                        : (root.bluetoothConnected() ? "󰂱" : "󰂯")
                    color: StyleTokens.textPrimary
                    font.family: root.iconFontFamily
                    font.pixelSize: 15
                }

                MouseArea {
                    id: bluetoothArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: islandContainer.showConnectivityIsland("bluetooth")
                }
            }

            Rectangle {
                id: volumeChip

                width: volumeText.implicitWidth + 10
                height: 18
                radius: 6
                color: volumeArea.containsMouse ? root.barChipHoverColor : "transparent"

                Text {
                    id: volumeText

                    anchors.centerIn: parent
                    text: root.volumeLabel()
                    color: StyleTokens.textPrimary
                    font.family: root.textFontFamily
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    id: volumeArea

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton)
                            islandContainer.showControlCenter();
                        else
                            SystemServices.launchDetached("wpctl", ["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                    }
                }
            }
        }
    }

    TopEdgeBlendCorner {
        x: rightBarPanel.x - width + 1
        y: root.sideBarY
        cutoutOnRight: false
        activeBlend: false
    }

    TopEdgeBlendCorner {
        x: rightBarPanel.x + rightBarPanel.width - 1
        y: root.sideBarY
        cutoutOnRight: true
        activeBlend: false
    }

    BottomEdgeBlendCorner {
        id: rightBottomOuterBlend
        x: rightBarPanel.x + rightBarPanel.width - width
        y: rightBarPanel.y + rightBarPanel.height - 1
        cutoutOnRight: true
        activeBlend: false
        rotation: 180
        transformOrigin: Item.Center
    }


    IslandRootGestureArea {
        anchors.fill: parent
        enabled: false
        islandController: islandContainer
        capsule: mainCapsule
    }
}
