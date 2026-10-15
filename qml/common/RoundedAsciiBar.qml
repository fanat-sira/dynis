import QtQuick
import QtQuick.Effects

Item {
    id: root

    property string text: ""
    property color textColor: "white"
    property string fontFamily: "sans-serif"
    property real pixelSize: 14
    property int radius: 5

    implicitWidth: metrics.advanceWidth
    implicitHeight: Math.ceil(pixelSize + 2)
    width: implicitWidth
    height: implicitHeight
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: roundedMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    TextMetrics {
        id: metrics
        text: root.text
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        font.weight: Font.Medium
    }

    Text {
        anchors.centerIn: parent
        text: root.text
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        font.weight: Font.Medium
    }

    Item {
        id: roundedMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Rectangle {
            anchors.fill: parent
            radius: Math.min(root.radius, height / 2)
            antialiasing: true
            color: "white"
        }
    }
}
