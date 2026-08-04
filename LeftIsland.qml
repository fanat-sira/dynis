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

    readonly property var userConfig: UserConfig
    readonly property string textFontFamily: userConfig.textFontFamily

    readonly property real pillEdgeMargin: 14
    readonly property real pillTopInset: 13
    readonly property real pillHeight: 32
    readonly property real pillRadius: 16

    readonly property bool fullscreenShellHidden: currentWorkspaceHasFullscreenWindow()

    color: StyleTokens.transparent
    visible: !fullscreenShellHidden
    anchors { top: true; left: true; right: true }
    implicitHeight: Math.ceil(pillTopInset + pillHeight + 8)
    exclusiveZone: 0
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
            x: Math.floor(pill.x)
            y: Math.floor(pill.y)
            width: pill.visible ? Math.ceil(pill.width) : 0
            height: pill.visible ? Math.ceil(pill.height) : 0
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
        const list = listValues(hyprlandData.workspaces);
        for (let i = 0; i < list.length; i++) {
            const ws = list[i];
            if (!ws) continue;
            const wsId = Number(ws.id);
            if (!isFinite(wsId) || wsId < 1 || wsId > 100) continue;
            const wsMonitor = String(ws.monitor || "");
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

    Connections {
        target: hyprlandData
        function onWorkspacesChanged() { root.syncWorkspaceModel(); }
    }

    onCurrentMonitorWorkspaceIdChanged: syncWorkspaceModel()
    onHyprMonitorNameChanged: syncWorkspaceModel()
    Component.onCompleted: syncWorkspaceModel()

    Rectangle {
        id: pill
        x: root.pillEdgeMargin
        y: root.pillTopInset
        height: root.pillHeight
        radius: root.pillRadius
        color: StyleTokens.black
        width: Math.max(root.pillHeight, contentRow.implicitWidth + 12)

        Behavior on width {
            NumberAnimation {
                duration: 380
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

            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 320
                    easing.type: Easing.OutCubic
                }
            }
            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0; to: 1
                    duration: 260
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "scale"
                    from: 0.4; to: 1
                    duration: 380
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

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
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
                            Hyprland.dispatch("workspace " + cell.wsId);
                        }
                    }
                }
            }
        }
    }
}
