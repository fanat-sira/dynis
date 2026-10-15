import QtQuick

// Geometry in LiquidGroup-local logical pixels.  A shape may be animated
// independently; LiquidGroup then blends all active shapes into one surface.
QtObject {
    property real x: 0
    property real y: 0
    property real width: 64
    property real height: 64
    property real radius: 32
    property real presence: 1
}
