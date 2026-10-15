import QtQuick

// The default one-shape group is also suitable for conventional rounded cards.
// Additional LiquidShape objects can be passed through `shapes` to create the
// characteristic smooth merge/separation used by LiquidIslandQS.
Item {
    id: root

    property real cornerRadius: Math.min(width, height) / 2
    property real blendRadius: 28
    // HyprGlass uses this barely-visible alpha as its silhouette.  It keeps
    // the QML layer optically clear while preserving the exact rounded mask.
    property color tint: Qt.rgba(0, 0, 0, 0.004)
    property color edgeColor: "transparent"
    property real edgeWidth: 0
    property list<LiquidShape> shapes: []

    LiquidGroup {
        anchors.fill: parent
        blendRadius: root.blendRadius
        tint: root.tint
        shapes: root.shapes.length > 0 ? root.shapes : [baseShape]

        LiquidShape {
            id: baseShape
            width: root.width
            height: root.height
            radius: root.cornerRadius
        }
    }

    // A restrained rim makes the translucent surface legible on bright and
    // dark wallpapers without turning it into an opaque card.
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.edgeWidth / 2
        radius: Math.max(0, root.cornerRadius - root.edgeWidth / 2)
        color: "transparent"
        border.width: root.edgeWidth
        border.color: root.edgeColor
        antialiasing: true
        visible: root.edgeWidth > 0
    }
}
