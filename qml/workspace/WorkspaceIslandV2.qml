import QtQuick
import Quickshell
import Quickshell.Hyprland
import DynisBackend

// Deliberately static first pass. Keep the state flow small and independent
// from the legacy Lua snapshot path; animations will be introduced separately.
Item {
    id: root

    required property string monitorName
    required property int activeWorkspaceId
    property string textFontFamily: "sans-serif"
    property real itemSize: 26
    property real spacing: 2
    property real horizontalPadding: 6

    readonly property var nativeWorkspaces: Hyprland.workspaces.values
    readonly property var workspaceIds: {
        const ids = [];
        const seen = {};
        for (let index = 0; index < nativeWorkspaces.length; index++) {
            const workspace = nativeWorkspaces[index];
            if (!workspace || workspace.id < 1 || workspace.id > 100) continue;
            if (monitorName !== "" && workspace.monitor
                    && String(workspace.monitor.name || "") !== monitorName) continue;
            const snapshot = workspace.lastIpcObject || {};
            if (Number(snapshot.windows || 0) <= 0 && workspace.id !== activeWorkspaceId) continue;
            if (!seen[workspace.id]) {
                seen[workspace.id] = true;
                ids.push(workspace.id);
            }
        }
        if (activeWorkspaceId >= 1 && !seen[activeWorkspaceId]) ids.push(activeWorkspaceId);
        ids.sort((left, right) => left - right);
        return ids;
    }

    readonly property real targetWidth: Math.max(
        root.itemSize,
        row.implicitWidth + root.horizontalPadding * 2
    )
    property real displayedWidth: targetWidth

    onTargetWidthChanged: displayedWidth = targetWidth

    implicitWidth: displayedWidth
    implicitHeight: root.itemSize
    width: displayedWidth
    height: implicitHeight

    // This Item is horizontally centered by the host window. Animating its
    // width (rather than a child width) makes both capsule edges move from the
    // centre together instead of jumping left before growing right.
    Behavior on displayedWidth {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutBack
            easing.overshoot: 1.05
        }
    }

    Rectangle {
        id: capsule

        anchors.fill: parent
        radius: 0
        color: StyleTokens.black

        Row {
            id: row

            x: (parent.width - implicitWidth) / 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.spacing

            // A center anchor would move the whole Row to its new x in one
            // frame when implicitWidth changes. Animate that row-level shift
            // so the left half travels left while the right half travels right.
            Behavior on x {
                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.05
                }
            }

            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 380
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.05
                }
            }
            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 180
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "scale"
                    from: 0.88
                    to: 1
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
            Repeater {
                model: ScriptModel {
                    values: root.workspaceIds
                }

                Item {
                    required property int modelData
                    readonly property int workspaceId: modelData
                    readonly property bool active: workspaceId === root.activeWorkspaceId

                    width: root.itemSize
                    height: root.itemSize

                    Rectangle {
                        anchors.fill: parent
                        radius: 0
                        color: parent.active ? StyleTokens.cardFillActive : StyleTokens.transparent

                        Behavior on color {
                            ColorAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(parent.workspaceId)
                        color: parent.active ? StyleTokens.textPrimaryBright : StyleTokens.textMuted
                        font.family: root.textFontFamily
                        font.pixelSize: 14
                        font.weight: parent.active ? Font.Bold : Font.Medium

                        Behavior on color {
                            ColorAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = \""
                            + parent.workspaceId + "\", on_current_monitor = true })")
                    }
                }
            }
        }
    }
}
