import QtQuick

// Adapted from bea4dev/LiquidIslandQS. Up to eight rounded forms are merged
// in one SDF pass, so a moving satellite joins and separates without a seam.
ShaderEffect {
    id: group

    property list<LiquidShape> shapes: []
    property real blendRadius: 28
    property color tint: Qt.rgba(0.13, 0.19, 0.23, 0.20)
    readonly property vector2d resolution: Qt.vector2d(width, height)
    readonly property int shapeCount: Math.min(shapes.length, 8)

    function geometry(index) {
        if (index >= shapes.length)
            return Qt.vector4d(0, 0, 0, 0);
        const shape = shapes[index];
        const presence = Math.max(0, Math.min(1, shape.presence));
        const shapeWidth = Math.max(0, shape.width);
        const shapeHeight = Math.max(0, shape.height);
        return Qt.vector4d(shape.x + shapeWidth * (1 - presence) / 2,
                           shape.y + shapeHeight * (1 - presence) / 2,
                           shapeWidth * presence, shapeHeight * presence);
    }

    function corner(index) {
        if (index >= shapes.length)
            return 0;
        const shape = shapes[index];
        return Math.max(0, shape.radius) * Math.max(0, Math.min(1, shape.presence));
    }

    readonly property vector4d shape0: geometry(0)
    readonly property vector4d shape1: geometry(1)
    readonly property vector4d shape2: geometry(2)
    readonly property vector4d shape3: geometry(3)
    readonly property vector4d shape4: geometry(4)
    readonly property vector4d shape5: geometry(5)
    readonly property vector4d shape6: geometry(6)
    readonly property vector4d shape7: geometry(7)
    readonly property vector4d radii0: Qt.vector4d(corner(0), corner(1), corner(2), corner(3))
    readonly property vector4d radii1: Qt.vector4d(corner(4), corner(5), corner(6), corner(7))

    fragmentShader: Qt.resolvedUrl("../shaders/liquid.frag.qsb")

    onStatusChanged: {
        if (status === ShaderEffect.Error)
            console.error("[Dynis] Liquid group shader:", log)
    }
}
