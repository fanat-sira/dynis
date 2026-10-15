import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    // Mirror the current Hyprland decoration: rounding = 15,
    // shadow.range = 20. These values are intentionally local: UserConfig
    // does not expose screen-edge properties, so binding to it yielded
    // undefined and disabled both the masks and shadows.
    readonly property int cornerRadius: 15
    readonly property bool shadowEnabled: true
    readonly property int shadowRadius: 20
    readonly property real shadowOpacity: 0.35
    readonly property color shadowColorBase: "#000000"

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dynis-corners"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Empty region ensures the entire overlay is click-through
    mask: Region { }

    function shadowColorAt(factor) {
        const a = Math.max(0, Math.min(1, factor * root.shadowOpacity));
        return Qt.rgba(shadowColorBase.r, shadowColorBase.g, shadowColorBase.b, a);
    }

    // --- Top Edge Shadow ---
    Rectangle {
        id: topEdgeShadow
        x: 0
        y: 0
        width: root.width
        height: root.shadowRadius
        visible: root.shadowEnabled && root.shadowRadius > 0 && width > 0
        color: "transparent"
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.shadowColorAt(1.0) }
            GradientStop { position: 0.25; color: root.shadowColorAt(0.5625) }
            GradientStop { position: 0.5; color: root.shadowColorAt(0.25) }
            GradientStop { position: 0.75; color: root.shadowColorAt(0.0625) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // --- Bottom Edge Shadow ---
    Rectangle {
        id: bottomEdgeShadow
        x: 0
        y: root.height - root.shadowRadius
        width: root.width
        height: root.shadowRadius
        visible: root.shadowEnabled && root.shadowRadius > 0 && width > 0
        color: "transparent"
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.25; color: root.shadowColorAt(0.0625) }
            GradientStop { position: 0.5; color: root.shadowColorAt(0.25) }
            GradientStop { position: 0.75; color: root.shadowColorAt(0.5625) }
            GradientStop { position: 1.0; color: root.shadowColorAt(1.0) }
        }
    }

    // --- Left Edge Shadow ---
    Rectangle {
        id: leftEdgeShadow
        x: 0
        y: 0
        width: root.shadowRadius
        height: root.height
        visible: root.shadowEnabled && root.shadowRadius > 0 && height > 0
        color: "transparent"
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root.shadowColorAt(1.0) }
            GradientStop { position: 0.25; color: root.shadowColorAt(0.5625) }
            GradientStop { position: 0.5; color: root.shadowColorAt(0.25) }
            GradientStop { position: 0.75; color: root.shadowColorAt(0.0625) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // --- Right Edge Shadow ---
    Rectangle {
        id: rightEdgeShadow
        x: root.width - root.shadowRadius
        y: 0
        width: root.shadowRadius
        height: root.height
        visible: root.shadowEnabled && root.shadowRadius > 0 && height > 0
        color: "transparent"
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.25; color: root.shadowColorAt(0.0625) }
            GradientStop { position: 0.5; color: root.shadowColorAt(0.25) }
            GradientStop { position: 0.75; color: root.shadowColorAt(0.5625) }
            GradientStop { position: 1.0; color: root.shadowColorAt(1.0) }
        }
    }

    // Four opaque outside-corner cutouts. Shapes are GPU primitives; unlike
    // the previous Canvas/image-data implementation they do not allocate a
    // bitmap or schedule repaint work.
    Shape {
        x: 0; y: 0; width: root.cornerRadius; height: root.cornerRadius
        ShapePath { fillColor: "black"; strokeColor: "transparent"; PathSvg { path: "M 0 0 L 15 0 A 15 15 0 0 0 0 15 Z" } }
    }
    Shape {
        x: root.width - width; y: 0; width: root.cornerRadius; height: root.cornerRadius
        ShapePath { fillColor: "black"; strokeColor: "transparent"; PathSvg { path: "M 15 0 L 0 0 A 15 15 0 0 1 15 15 Z" } }
    }
    Shape {
        x: 0; y: root.height - height; width: root.cornerRadius; height: root.cornerRadius
        ShapePath { fillColor: "black"; strokeColor: "transparent"; PathSvg { path: "M 0 15 L 0 0 A 15 15 0 0 0 15 15 Z" } }
    }
    Shape {
        x: root.width - width; y: root.height - height; width: root.cornerRadius; height: root.cornerRadius
        ShapePath { fillColor: "black"; strokeColor: "transparent"; PathSvg { path: "M 15 15 L 15 0 A 15 15 0 0 1 0 15 Z" } }
    }
}
