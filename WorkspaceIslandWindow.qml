import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import DynisBackend
import "qml/common"
import "qml/workspace"

PanelWindow {
    id: root

    property var shellRootController: null

    readonly property var hyprMonitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property string hyprMonitorName: hyprMonitor && hyprMonitor.name ? String(hyprMonitor.name) : ""
    readonly property bool monitorFocused: hyprMonitor ? hyprMonitor.focused : false
    readonly property int currentMonitorWorkspaceId: hyprMonitor && hyprMonitor.activeWorkspace
        ? hyprMonitor.activeWorkspace.id : 1
    readonly property var nativeWorkspaceValues: Hyprland.workspaces.values

    readonly property var userConfig: UserConfig
    readonly property string textFontFamily: userConfig.textFontFamily
    property bool workspaceGeometryTraceEnabled: false
    readonly property real workspacePillTargetWidth: Math.max(root.pillHeight, contentRow.implicitWidth + 12)

    // Align to Hyprland's visible 20px outer gap.
    readonly property real pillEdgeMargin: 20
    readonly property real pillTopInset: 20
    readonly property real pillHeight: 32
    readonly property real pillRadius: 0
    readonly property real workspaceBottomInset: 0

    readonly property bool fullscreenShellHidden: currentWorkspaceHasFullscreenWindow()

    color: StyleTokens.transparent
    visible: !fullscreenShellHidden
    // Full-width bottom layer; the capsule itself is centered inside it.
    anchors { bottom: true; left: true; right: true }
    implicitHeight: Math.ceil(pillHeight)
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dynis-left-island"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        Region {
            intersection: Intersection.Combine
            x: Math.floor(workspaceIslandV2.x)
            y: Math.floor(workspaceIslandV2.y)
            width: Math.ceil(workspaceIslandV2.width)
            height: Math.ceil(workspaceIslandV2.height)
        }
    }

    HyprlandData { id: hyprlandData }
    HyprlandDispatch { id: hyprDispatch }

    function listValues(rawList) {
        if (!rawList) return [];
        if (Array.isArray(rawList)) return rawList;
        const length = Number(rawList.length);
        if (!isFinite(length) || length < 0) return [];
        const out = [];
        for (let i = 0; i < Math.floor(length); i++) out.push(rawList[i]);
        return out;
    }

    function computeWorkspaceIds() {
        const seen = {};
        const ids = [];
        // Show every workspace that actually contains a mapped window. This
        // avoids transient empty workspaces emitted during a switch, while
        // retaining the currently selected empty workspace.
        const list = listValues(hyprlandData.windowList);
        for (let i = 0; i < list.length; i++) {
            const windowData = list[i];
            if (!windowData || !windowData.mapped || windowData.hidden) continue;
            const wsId = windowData.workspace ? Number(windowData.workspace.id) : NaN;
            if (!isFinite(wsId) || wsId < 1 || wsId > 100) continue;
            const wsMonitor = windowData.monitorName !== undefined
                ? String(windowData.monitorName) : "";
            if (hyprMonitorName !== "" && wsMonitor !== "" && wsMonitor !== hyprMonitorName) continue;
            if (seen[wsId]) continue;
            seen[wsId] = true;
            ids.push(wsId);
        }
        const activeId = Number(currentMonitorWorkspaceId);
        if (activeId >= 1 && !seen[activeId]) ids.push(activeId);
        ids.sort((a, b) => a - b);
        return ids;
    }

    function syncWorkspaceModel() {
        const desiredIds = computeWorkspaceIds();
        const desiredSet = {};
        for (let i = 0; i < desiredIds.length; i++) desiredSet[desiredIds[i]] = true;

        // Keep the list dynamic: empty workspaces that Hyprland has removed
        // disappear from the island as well.
        for (let i = workspaceModel.count - 1; i >= 0; i--) {
            const existingId = workspaceModel.get(i).wsId;
            if (!desiredSet[existingId])
                workspaceModel.remove(i);
        }

        const presentSet = {};
        for (let i = 0; i < workspaceModel.count; i++) presentSet[workspaceModel.get(i).wsId] = true;

        for (let i = 0; i < desiredIds.length; i++) {
            const targetId = desiredIds[i];
            if (presentSet[targetId]) continue;

            let insertAt = 0;
            while (insertAt < workspaceModel.count && workspaceModel.get(insertAt).wsId < targetId)
                insertAt++;
            workspaceModel.insert(insertAt, { wsId: targetId });
        }

    }

    function currentWorkspaceHasFullscreenWindow() {
        const windows = listValues(hyprlandData.windowList);
        const workspaceId = Number(root.currentMonitorWorkspaceId);
        const monitorName = String(root.hyprMonitorName || "");
        const monitorId = root.hyprMonitor && root.hyprMonitor.id !== undefined
            ? Number(root.hyprMonitor.id) : NaN;

        for (let index = 0; index < windows.length; index++) {
            const w = windows[index];
            if (!w || w.hidden || !w.mapped) continue;
            const wsId = w.workspace ? Number(w.workspace.id) : NaN;
            if (wsId !== workspaceId) continue;

            const wMonName = w.monitorName !== undefined ? String(w.monitorName) : "";
            const wMonId = w.monitor !== undefined ? Number(w.monitor) : NaN;
            const monitorMatches = wMonName !== ""
                ? wMonName === monitorName
                : (!isNaN(monitorId) && !isNaN(wMonId) ? wMonId === monitorId : true);
            if (!monitorMatches) continue;

            if (Number(w.fullscreen) > 0 || Number(w.fullscreenClient) > 0) return true;
        }
        return false;
    }

    ListModel {
        id: workspaceModel
    }

    onNativeWorkspaceValuesChanged: syncWorkspaceModel()
    onWorkspacePillTargetWidthChanged: {
        if (workspaceGeometryTraceEnabled)
            console.log("[WS GEOMETRY TARGET]", workspacePillTargetWidth, Date.now());
    }

    Connections {
        target: hyprlandData
        function onWindowListChanged() { root.syncWorkspaceModel(); }
    }
    // Keep a newly selected empty workspace in the model immediately.
    onCurrentMonitorWorkspaceIdChanged: syncWorkspaceModel()
    onHyprMonitorNameChanged: syncWorkspaceModel()
    Component.onCompleted: syncWorkspaceModel()

    Rectangle {
        id: pill
        visible: false
        x: root.pillEdgeMargin
        y: root.pillTopInset
        height: root.pillHeight
        radius: root.pillRadius
        color: StyleTokens.black
        width: root.workspacePillTargetWidth

        onWidthChanged: {
            if (root.workspaceGeometryTraceEnabled)
                console.log("[WS GEOMETRY WIDTH]", width, "target", root.workspacePillTargetWidth, Date.now());
        }

        Behavior on width {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutBack
                easing.overshoot: 1.05
            }
        }

        Row {
            id: contentRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 6
            spacing: 2

            onImplicitWidthChanged: {
                if (root.workspaceGeometryTraceEnabled)
                    console.log("[WS GEOMETRY ROW]", implicitWidth, Date.now());
            }

            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 140
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.05
                }
            }
            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0; to: 1
                    duration: 100
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "scale"
                    from: 0.4; to: 1
                    duration: 140
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.4
                }
            }
            Repeater {
                model: workspaceModel

                Item {
                    id: cell
                    required property int wsId
                    readonly property bool isActive: wsId === root.currentMonitorWorkspaceId
                    width: 26
                    height: 26
                    anchors.verticalCenter: parent.verticalCenter

                    onXChanged: {
                        if (root.workspaceGeometryTraceEnabled)
                            console.log("[WS GEOMETRY X]", wsId, x, Date.now());
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 0
                        color: cell.isActive ? StyleTokens.cardFillActive : StyleTokens.transparent

                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(cell.wsId)
                        color: cell.isActive ? StyleTokens.textPrimaryBright : StyleTokens.textMuted
                        font.family: root.textFontFamily
                        font.pixelSize: 14
                        font.weight: cell.isActive ? Font.Bold : Font.Medium
                        font.letterSpacing: 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        z: 1
                        onClicked: {
                            // Hyprland's Lua config provider requires a Lua
                            // dispatcher expression, not legacy `workspace N`.
                            Hyprland.dispatch("hl.dsp.focus({ workspace = \""
                                + cell.wsId + "\", on_current_monitor = true })");
                        }
                    }
                }
            }
        }
    }

    WorkspaceIslandV2 {
        id: workspaceIslandV2

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.workspaceBottomInset
        monitorName: root.hyprMonitorName
        activeWorkspaceId: root.currentMonitorWorkspaceId
        textFontFamily: root.textFontFamily
        itemSize: 26
        spacing: 2
        horizontalPadding: 6
    }
}
