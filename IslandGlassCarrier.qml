import QtQuick
import Quickshell
import Quickshell.Wayland
import "qml/common"

// HyprGlass calculates its curved optical edge from the layer-surface bounds,
// not from an alpha mask inside a larger surface.  Keep this surface exactly
// the size of the visible island and put it one layer below Dynis's Overlay UI.
PanelWindow {
    id: root

    property var hostScreen: null
    property real islandWidth: 0
    property real islandHeight: 0
    property real islandX: Math.round(((root.screen ? root.screen.width : 0) - root.islandWidth) / 2)
    property real islandY: 0
    property real islandRadius: 0
    property bool islandVisible: false

    screen: root.hostScreen
    visible: root.islandVisible && root.islandWidth > 0 && root.islandHeight > 0
    color: "transparent"
    implicitWidth: Math.ceil(root.islandWidth)
    implicitHeight: Math.ceil(root.islandHeight)
    anchors { top: true; left: true }
    margins {
        top: Math.round(root.islandY)
        left: Math.round(root.islandX)
    }
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: false
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "dynis-glass-island"

    // An imperceptible alpha is the exact rounded silhouette HyprGlass uses.
    // It is replaced by the compositor's clear optical pass, not a QML tint.
    LiquidGlassSurface {
        anchors.fill: parent
        cornerRadius: root.islandRadius
        tint: Qt.rgba(0, 0, 0, 0.004)
        edgeColor: "transparent"
        edgeWidth: 0
    }
}
