import QtQuick
import DynisBackend
import "../common"

Item {
    id: root

    readonly property var userConfig: UserConfig

    property string iconText: ""
    property real progress: -1
    property string customText: ""
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string iconFontFamily: activeConfig.iconFontFamily
    property string textFontFamily: activeConfig.textFontFamily
    property string heroFontFamily: activeConfig.heroFontFamily
    property string slideDirection: "none"
    property real transitionProgress: 0
    readonly property bool showProgress: progress >= 0
    readonly property bool showText: progress < 0 && customText !== ""
    readonly property bool isVolumeOsd: iconText === "VOL"
    property bool showCondition: false
    property real hiddenLeftPadding: 16
    property real hiddenRightPadding: 16
    readonly property real clampedProgress: slideDirection === "right"
        ? Math.max(0, Math.min(1, transitionProgress))
        : (slideDirection === "left"
            ? Math.max(0, Math.min(1, -transitionProgress))
            : 0)
    readonly property real revealProgress: slideDirection === "none" ? 1 : (1 - clampedProgress)
    readonly property real contentX: slideDirection === "right"
        ? (width + hiddenRightPadding) * clampedProgress
        : (slideDirection === "left"
            ? -(width + hiddenLeftPadding) * clampedProgress
            : 0)

    function asciiBar(value, slots) {
        const count = slots || 8;
        const filled = Math.max(0, Math.min(count, Math.round(value * count)));
        let result = "";
        for (let index = 0; index < count; index++)
            result += index < filled ? "█" : "░";
        return result;
    }

    anchors.fill: parent
    clip: true
    opacity: showCondition ? revealProgress : 0

    Behavior on opacity {
        enabled: slideDirection === "none"

        NumberAnimation {
            duration: showCondition ? 280 : 200
            easing.type: Easing.InOutQuad
        }
    }

    TextMetrics {
        id: osdMaxPercentMetrics

        font.family: heroFontFamily
        font.pixelSize: 17
        font.weight: Font.Medium
        text: "100%"
    }

    readonly property real osdIconReserve: 18
    readonly property real osdIconPercentGap: 4

    Item {
        x: contentX
        width: parent.width
        height: parent.height
        visible: showProgress

        Item {
            id: osdProgressLeading

            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: root.osdIconReserve + root.osdIconPercentGap + osdMaxPercentMetrics.advanceWidth
            height: parent.height
            visible: !root.isVolumeOsd

            Text {
                id: osdProgressIcon

                text: iconText
                color: StyleTokens.textPrimary
                font.pixelSize: 16
                font.family: iconFontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.osdIconReserve
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                text: Math.round(progress * 100) + "%"
                color: StyleTokens.textPrimary
                font.pixelSize: 17
                font.family: heroFontFamily
                font.weight: Font.Medium
                font.letterSpacing: 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: osdMaxPercentMetrics.advanceWidth
                horizontalAlignment: Text.AlignRight
            }
        }

        Rectangle {
            id: osdProgressTrack

            anchors.left: osdProgressLeading.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            height: 7
            radius: 0
            antialiasing: true
            color: Qt.rgba(89 / 255, 96 / 255, 104 / 255, 0.22)
            visible: !root.isVolumeOsd

            Rectangle {
                id: osdProgressFill

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, Math.min(1, progress))
                radius: 0
                antialiasing: true
                color: StyleTokens.textPrimary

                Behavior on width {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 6
            visible: root.isVolumeOsd

            Text {
                text: "VOL " + Math.round(progress * 100) + "%"
                color: StyleTokens.textPrimary
                font.pixelSize: 17
                font.family: heroFontFamily
                font.weight: Font.Medium
            }

            RoundedAsciiBar {
                text: root.asciiBar(progress, 20)
                textColor: StyleTokens.textPrimary
                pixelSize: 16
                fontFamily: textFontFamily
            }
        }
    }

    Item {
        x: contentX
        width: parent.width
        height: parent.height
        visible: showText

        Row {
            anchors.centerIn: parent
            spacing: 14

            Text {
                text: iconText
                color: StyleTokens.textPrimary
                font.pixelSize: 16
                font.family: iconFontFamily
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: customText
                color: StyleTokens.textPrimary
                font.pixelSize: 17
                font.family: textFontFamily
                font.weight: Font.Medium
                font.letterSpacing: 0
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
