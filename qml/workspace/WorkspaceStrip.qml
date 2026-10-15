import QtQuick
import Quickshell
import Quickshell.Hyprland
import DynisBackend

Item {
    id: root

    required property string monitorName
    required property int activeWorkspaceId
    property string textFontFamily: "sans-serif"
    property real itemSize: 24
    property real spacing: 2

    // Keep a stable 1–10 scale. Inactive entries are intentionally subdued,
    // rather than removed, so the workspace side of the island never jumps.
    readonly property var workspaces: Hyprland.workspaces.values
    readonly property var occupiedWorkspaceIds: {
        const result = {};
        for (let index = 0; index < workspaces.length; index++) {
            const workspace = workspaces[index];
            if (!workspace || workspace.id < 1 || workspace.id > 10)
                continue;
            if (monitorName !== "" && workspace.monitor
                    && String(workspace.monitor.name || "") !== monitorName)
                continue;
            if (Number((workspace.lastIpcObject || {}).windows || 0) > 0)
                result[workspace.id] = true;
        }
        return result;
    }
    readonly property var ids: {
        const result = [];
        for (let workspaceId = 1; workspaceId <= 10; workspaceId++)
            result.push(workspaceId);
        return result;
    }

    readonly property real minimumWidth: itemSize * 5 + spacing * 4
    implicitWidth: minimumWidth
    implicitHeight: itemSize * 2 + 2
    height: implicitHeight

    Grid {
        id: grid
        anchors.fill: parent
        columns: 5
        rows: 2
        flow: Grid.LeftToRight
        columnSpacing: 0
        rowSpacing: 2

        Repeater {
            model: ScriptModel { values: root.ids }

            Item {
                required property int modelData
                readonly property bool active: modelData === root.activeWorkspaceId
                readonly property bool occupied: root.occupiedWorkspaceIds[modelData] === true
                // Each workspace owns one equal rectangular fifth of the row,
                // including the otherwise empty space around its label.
                width: grid.width / grid.columns
                height: root.itemSize

                Text {
                    anchors.centerIn: parent
                    text: String(parent.modelData)
                    color: parent.active
                        ? StyleTokens.textPrimaryBright
                        : StyleTokens.textMuted
                    opacity: parent.active ? 1.0 : (parent.occupied ? 0.72 : 0.42)
                    font.family: root.textFontFamily
                    font.pixelSize: 14
                    font.weight: parent.active ? Font.Bold : Font.Medium
                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: 12
                    height: 2
                    radius: 1
                    color: parent.active
                        ? Qt.rgba(183 / 255, 131 / 255, 142 / 255, 0.9) // Hyprland $primary / WezTerm dusty rose
                        : Qt.rgba(170 / 255, 170 / 255, 170 / 255, 0.65)
                    opacity: parent.active || workspaceHitArea.containsMouse ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: workspaceHitArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = \""
                        + parent.modelData + "\", on_current_monitor = true })")
                }
            }
        }
    }
}
