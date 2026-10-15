import QtQuick
import QtQuick.Effects
import Quickshell
import DynisBackend

Item {
    id: root

    readonly property var userConfig: UserConfig

    signal dismissRequested(int notificationId)
    signal openRequested(int notificationId)

    property bool showCondition: false
    property string appName: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property var notifications: []
    property int notificationCount: notifications ? notifications.length : 0
    property string iconText: ""
    property var configSource: null
    property real revealProgress: 0
    readonly property var activeConfig: configSource || userConfig
    property string iconFontFamily: activeConfig.iconFontFamily
    property string textFontFamily: activeConfig.textFontFamily
    property string heroFontFamily: activeConfig.heroFontFamily

    readonly property int latestNotificationId: notificationCount > 0
        ? notifications[notificationCount - 1].id
        : -1
    readonly property string resolvedIconName: resolveIconName(appIcon, appName)
    readonly property string appIconSource: resolveIconSource(resolvedIconName)
    readonly property bool hasAppIconImage: appIconSource !== "" && !appIconImage.iconLoadFailed
    readonly property bool hasDirectNotificationImage: {
        const icon = String(appIcon === undefined || appIcon === null ? "" : appIcon).trim();
        return icon.charAt(0) === "/"
            || icon.indexOf("file://") === 0
            || icon.indexOf("image://") === 0
            || icon.indexOf("qrc:/") === 0;
    }
    readonly property string appInitial: {
        const name = String(appName || "").trim();
        return name !== "" ? name.charAt(0).toUpperCase() : "!";
    }
    readonly property bool hasAppInitial: String(appName || "").trim() !== ""
    readonly property string contentText: {
        if (summary !== "" && body !== "" && body !== summary) return summary + "  " + body;
        if (summary !== "") return summary;
        if (body !== "") return body;
        return "New notification";
    }
    readonly property real minimumWidth: 272
    readonly property real maximumWidth: 400
    readonly property real compactSingleLineHeight: 56
    readonly property real compactWrappedHeight: 68
    readonly property real compactNotificationIconMargin: 5
    readonly property real compactSingleLineIconSize: compactSingleLineHeight - compactNotificationIconMargin * 2
    readonly property real compactNotificationIconLeftMargin: compactNotificationIconMargin
    readonly property real compactNotificationIconGap: 14
    readonly property real compactNotificationBellHorizontalOffset: -5
    readonly property real compactNotificationIconVerticalOffset: -1
    readonly property real compactNotificationRightMargin: 16
    readonly property real compactVerticalPadding: 7
    readonly property real verticalPadding: compactVerticalPadding
    readonly property real textBlockWidthAtMaximum: maximumWidth
        - compactNotificationIconLeftMargin
        - compactNotificationRightMargin
        - compactSingleLineIconSize
        - compactNotificationIconGap
    readonly property bool prefersWrappedContent: contentMetrics.advanceWidth > textBlockWidthAtMaximum
    readonly property real compactPreferredHeight: prefersWrappedContent ? compactWrappedHeight : compactSingleLineHeight
    readonly property real compactNotificationIconSize: compactPreferredHeight - compactNotificationIconMargin * 2
    readonly property real compactNotificationBellPixelSize: compactNotificationIconSize * 0.43
    readonly property real compactPreferredWidth: prefersWrappedContent
        ? maximumWidth
        : Math.max(
            minimumWidth,
            Math.min(
                maximumWidth,
                contentMetrics.advanceWidth
                    + compactNotificationIconLeftMargin
                    + compactNotificationRightMargin
                    + compactNotificationIconSize
                    + compactNotificationIconGap
            )
        )
    readonly property real preferredWidth: compactPreferredWidth
    readonly property real preferredHeight: compactPreferredHeight
    readonly property real outerRadius: 0

    function resolveIconName(rawIcon, rawAppName) {
        const icon = String(rawIcon === undefined || rawIcon === null ? "" : rawIcon).trim();
        const app = String(rawAppName === undefined || rawAppName === null ? "" : rawAppName).trim();
        const lowerApp = app.toLowerCase();

        if (icon !== "" && icon.toLowerCase() !== lowerApp)
            return icon;

        if (app === "")
            return "";

        switch (lowerApp) {
        case "code":
        case "visual studio code":
            return "visual-studio-code";
        case "firefox":
        case "mozilla firefox":
            return "firefox";
        case "chromium":
        case "google chrome":
            return "google-chrome";
        case "spotify":
            return "spotify";
        case "telegram":
        case "telegram desktop":
            return "org.telegram.desktop";
        case "hyprshot":
            return "applets-screenshooter";
        default:
            return "";
        }
    }

    function resolveIconSource(iconName) {
        const name = String(iconName === undefined || iconName === null ? "" : iconName).trim();
        if (name === "")
            return "";
        if (name.indexOf("file://") === 0 || name.indexOf("qrc:/") === 0 || name.indexOf("image://") === 0)
            return name;
        if (name.charAt(0) === "/")
            return "file://" + name;

        const iconPath = Quickshell.iconPath(name, "");
        return iconPath === undefined || iconPath === null ? "" : String(iconPath);
    }

    anchors.fill: parent
    anchors.margins: 0
    opacity: showCondition ? revealProgress : 0

    Component.onCompleted: revealProgress = showCondition ? 1 : 0

    onShowConditionChanged: revealProgress = showCondition ? 1 : 0

    Behavior on revealProgress {
        NumberAnimation {
            duration: showCondition ? 260 : 120
            easing.type: Easing.OutCubic
        }
    }

    TextMetrics {
        id: contentMetrics

        font.family: textFontFamily
        font.pixelSize: 17
        font.weight: Font.Medium
        text: contentText
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: compactNotificationIconLeftMargin
        anchors.rightMargin: compactNotificationRightMargin
        anchors.topMargin: verticalPadding
        anchors.bottomMargin: verticalPadding
        spacing: compactNotificationIconGap
        anchors.verticalCenter: parent.verticalCenter

        Item {
            id: appIconFrame

            width: compactNotificationIconSize
            height: compactNotificationIconSize
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: appIconBackground

                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: compactMouseArea.containsMouse
                    ? Qt.rgba(36 / 255, 39 / 255, 44 / 255, 0.98)
                    : Qt.rgba(28 / 255, 31 / 255, 35 / 255, 0.98)
            }

            Image {
                id: appIconImage

                property bool iconLoadFailed: false

                anchors.fill: parent
                anchors.margins: root.hasDirectNotificationImage ? 0 : 7
                source: root.hasAppIconImage ? root.appIconSource : ""
                sourceSize: Qt.size(width, height)
                fillMode: root.hasDirectNotificationImage ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                smooth: true
                mipmap: true
                visible: source !== ""
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: appIconCircleMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                onStatusChanged: {
                    if (status === Image.Error)
                        iconLoadFailed = true;
                }

                Connections {
                    target: root

                    function onAppIconSourceChanged() {
                        appIconImage.iconLoadFailed = false;
                    }
                }
            }

            Item {
                id: appIconCircleMask

                anchors.fill: appIconImage
                visible: false
                layer.enabled: true
                layer.smooth: true

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: "white"
                }
            }

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: root.hasAppIconImage ? 0 : root.compactNotificationBellHorizontalOffset
                anchors.verticalCenterOffset: root.hasAppIconImage ? 0 : root.compactNotificationIconVerticalOffset
                text: root.hasAppInitial ? root.appInitial : root.iconText
                visible: !root.hasAppIconImage
                color: StyleTokens.textPrimary
                font.pixelSize: root.hasAppInitial
                    ? root.compactNotificationIconSize * 0.42
                    : root.compactNotificationBellPixelSize
                font.family: root.hasAppInitial ? root.textFontFamily : root.iconFontFamily
                font.weight: root.hasAppInitial ? Font.DemiBold : Font.Medium
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Item {
            width: parent.width - compactNotificationIconSize - compactNotificationIconGap
            height: parent.height

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: contentText
                color: StyleTokens.textPrimary
                font.pixelSize: 17
                font.family: textFontFamily
                font.weight: Font.Medium
                font.letterSpacing: 0
                width: parent.width
                wrapMode: prefersWrappedContent ? Text.WordWrap : Text.NoWrap
                maximumLineCount: prefersWrappedContent ? 2 : 1
                elide: Text.ElideRight
                lineHeight: 0.95
            }
        }
    }

    MouseArea {
        id: compactMouseArea

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton)
                root.dismissRequested(root.latestNotificationId);
            else if (mouse.button === Qt.LeftButton)
                root.openRequested(root.latestNotificationId);
        }
    }
}
