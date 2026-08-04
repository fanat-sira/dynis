import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property int cornerRadius: 10

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

    mask: Region {
        Region {
            x: 0
            y: 0
            width: root.cornerRadius
            height: root.cornerRadius
        }

        Region {
            x: root.width - root.cornerRadius
            y: 0
            width: root.cornerRadius
            height: root.cornerRadius
        }

        Region {
            x: 0
            y: root.height - root.cornerRadius
            width: root.cornerRadius
            height: root.cornerRadius
        }

        Region {
            x: root.width - root.cornerRadius
            y: root.height - root.cornerRadius
            width: root.cornerRadius
            height: root.cornerRadius
        }
    }

    function paintCorner(ctx, corner) {
        const r = root.cornerRadius;
        ctx.reset();
        ctx.clearRect(0, 0, r, r);
        ctx.fillStyle = "#000000";
        ctx.fillRect(0, 0, r, r);
        ctx.globalCompositeOperation = "destination-out";
        ctx.beginPath();

        const cx = corner === "topLeft" || corner === "bottomLeft" ? r : 0;
        const cy = corner === "topLeft" || corner === "topRight" ? r : 0;
        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
        ctx.fill();
    }

    Canvas {
        id: topLeftCorner
        x: 0
        y: 0
        width: root.cornerRadius
        height: root.cornerRadius
        antialiasing: false
        smooth: false
        onPaint: root.paintCorner(getContext("2d"), "topLeft")
    }

    Canvas {
        id: topRightCorner
        x: root.width - width
        y: 0
        width: root.cornerRadius
        height: root.cornerRadius
        antialiasing: false
        smooth: false
        onPaint: root.paintCorner(getContext("2d"), "topRight")
    }

    Canvas {
        id: bottomLeftCorner
        x: 0
        y: root.height - height
        width: root.cornerRadius
        height: root.cornerRadius
        antialiasing: false
        smooth: false
        onPaint: root.paintCorner(getContext("2d"), "bottomLeft")
    }

    Canvas {
        id: bottomRightCorner
        x: root.width - width
        y: root.height - height
        width: root.cornerRadius
        height: root.cornerRadius
        antialiasing: false
        smooth: false
        onPaint: root.paintCorner(getContext("2d"), "bottomRight")
    }
}
