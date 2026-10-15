import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import DynisBackend
import "qml/common"

PanelWindow {
    id: root

    property bool launcherOpen: false
    property bool clipboardOpen: false
    // Shell selects one instance when the shortcut is pressed. Once selected,
    // this is the only authority for the surface's keyboard focus.
    property bool launcherActive: false
    property string pendingLaunchId: ""
    property string query: ""
    property int selectedIndex: 0
    property var usageHistory: ({})
    property bool usageHistoryLoaded: false
    readonly property int itemHeight: 52
    readonly property int itemGap: 7
    readonly property int visibleItems: 5
    readonly property bool active: launcherActive && (launcherOpen || clipboardOpen)
    readonly property var hyprMonitor: screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
    readonly property bool monitorFocused: hyprMonitor ? hyprMonitor.focused : false
    readonly property string textFontFamily: UserConfig.textFontFamily
    readonly property string iconFontFamily: UserConfig.iconFontFamily
    readonly property real cardRadius: 28

    color: "transparent"
    visible: launcherActive
    anchors { top: true; bottom: true; left: true; right: true }
    // Only the card and four dismiss strips receive pointer input. The mask
    // collapses to zero immediately on close, so the desktop never remains
    // blocked by an invisible fullscreen surface.
    mask: Region {
        Region {
            x: card.visible ? Math.floor(card.x) : 0
            y: card.visible ? Math.floor(card.y) : 0
            width: card.visible ? Math.ceil(card.width) : 0
            height: card.visible ? Math.ceil(card.height) : 0
        }
        Region {
            x: 0; y: 0
            width: root.active ? root.width : 0
            height: card.visible ? Math.floor(card.y) : 0
        }
        Region {
            x: 0
            y: card.visible ? Math.ceil(card.y + card.height) : 0
            width: root.active ? root.width : 0
            height: card.visible ? Math.max(0, root.height - y) : 0
        }
        Region {
            x: 0
            y: card.visible ? Math.floor(card.y) : 0
            width: card.visible ? Math.floor(card.x) : 0
            height: card.visible ? Math.ceil(card.height) : 0
        }
        Region {
            x: card.visible ? Math.ceil(card.x + card.width) : 0
            y: card.visible ? Math.floor(card.y) : 0
            width: card.visible ? Math.max(0, root.width - x) : 0
            height: card.visible ? Math.ceil(card.height) : 0
        }
    }
    exclusiveZone: 0
    aboveWindows: true
    focusable: launcherActive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dynis-launcher"

    // The launcher itself is fullscreen for keyboard and outside-click input.
    // Its optical layer must instead be exactly the size of this card, below
    // the Overlay UI, so refraction only exists along the rounded card edge.
    IslandGlassCarrier {
        hostScreen: root.screen
        islandWidth: card.width
        islandHeight: card.height
        islandX: card.x
        islandY: card.y
        islandRadius: root.cardRadius
        islandVisible: root.active && card.visible
        WlrLayershell.namespace: "dynis-glass-launcher"
    }

    ListModel { id: entries }
    ListModel { id: clipboardEntries }
    ListModel { id: filteredEntries }

    function openLauncher() {
        clipboardOpen = false;
        launcherOpen = true;
        launcherActive = true;
        query = "";
        selectedIndex = 0;
        appScan.exec(appScan.command);
    }

    function openClipboard() {
        launcherOpen = false;
        clipboardOpen = true;
        launcherActive = true;
        query = "";
        selectedIndex = 0;
        clipboardScan.exec(clipboardScan.command);
    }

    function close() {
        launcherActive = false;
        launcherOpen = false;
        clipboardOpen = false;
        query = "";
    }

    function rebuildFrom(text, clipboard) {
        const source = clipboard ? clipboardEntries : entries;
        source.clear();
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const fields = lines[i].split("\t");
            if (clipboard) {
                if (fields.length < 2) continue;
                source.append({ id: fields[0], name: fields.slice(1).join("\t"), icon: "edit-paste", exec: "" });
            } else {
                if (fields.length < 4) continue;
                source.append({ id: fields[0], name: fields[1], icon: fields[2] || "application-x-executable", exec: fields.slice(3).join("\t") });
            }
        }
        selectedIndex = 0;
        rebuildFiltered();
    }

    function matches(entry) {
        return matchScore(entry) >= 0;
    }

    function matchScore(entry) {
        const needle = query.toLowerCase().trim();
        if (needle === "") return 0;

        const name = String(entry.name).toLowerCase();
        if (name === needle) return 100000;
        if (name.startsWith(needle)) return 90000;
        const wordIndex = name.search(new RegExp("(^|[^a-z0-9])" + needle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
        if (wordIndex >= 0) return 80000 - wordIndex;
        const substringIndex = name.indexOf(needle);
        if (substringIndex >= 0) return 70000 - substringIndex;

        // A small fuzzy fallback: all query characters must appear in order.
        let cursor = 0;
        let gapPenalty = 0;
        for (let index = 0; index < needle.length; index++) {
            const found = name.indexOf(needle[index], cursor);
            if (found < 0) return -1;
            gapPenalty += found - cursor;
            cursor = found + 1;
        }
        return 1000 - gapPenalty;
    }

    function usageScore(entryId) {
        const timestamps = usageHistory[entryId] || [];
        const now = Date.now();
        const maximumAge = 7 * 24 * 60 * 60 * 1000;
        let score = 0;
        for (let index = 0; index < timestamps.length; index++) {
            const age = now - Number(timestamps[index]);
            if (age >= 0 && age <= maximumAge)
                score += Math.exp(-(age / (24 * 60 * 60 * 1000)) / 3);
        }
        return score;
    }

    function recordLaunch(entryId) {
        const now = Date.now();
        const maximumAge = 7 * 24 * 60 * 60 * 1000;
        const updated = {};
        for (const id in usageHistory) {
            const timestamps = (usageHistory[id] || []).filter((timestamp) => {
                const age = now - Number(timestamp);
                return age >= 0 && age <= maximumAge;
            });
            if (timestamps.length > 0)
                updated[id] = timestamps;
        }
        const timestamps = (updated[entryId] || []).slice();
        timestamps.push(now);
        updated[entryId] = timestamps;
        usageHistory = updated;
        usageSaveTimer.restart();
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function executableCommand(desktopExec) {
        let command = String(desktopExec || "").replace(/(?:\s|^)%[fFuUdDnNickvm]/g, "").replace(/%%/g, "%").trim();
        // Some desktop entries use `-- %U`; without a URI, the separator has
        // no meaning and can alter an application's command-line behaviour.
        command = command.replace(/\s+--\s*$/, "");
        return command;
    }

    function loadUsageHistory() {
        try {
            const parsed = JSON.parse(usageFile.text());
            usageHistory = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
        } catch (error) {
            usageHistory = ({});
        }
        usageHistoryLoaded = true;
        if (entries.count > 0)
            rebuildFiltered();
    }

    function rebuildFiltered() {
        filteredEntries.clear();
        const matches = [];
        const source = clipboardOpen ? clipboardEntries : entries;
        for (let i = 0; i < source.count; i++) {
            const entry = source.get(i);
            const score = matchScore(entry);
            if (score >= 0)
                matches.push({ id: entry.id, name: entry.name, icon: entry.icon, exec: entry.exec, sourceIndex: i, matchScore: score, usageScore: usageScore(entry.id) });
        }
        const hasQuery = query.trim() !== "";
        matches.sort((left, right) => {
            // cliphist already emits newest entries first. Preserve that order
            // unless a search query explicitly asks us to rank matches.
            if (clipboardOpen) {
                if (hasQuery && right.matchScore !== left.matchScore)
                    return right.matchScore - left.matchScore;
                return left.sourceIndex - right.sourceIndex;
            }
            if (hasQuery && right.matchScore !== left.matchScore)
                return right.matchScore - left.matchScore;
            if (right.usageScore !== left.usageScore)
                return right.usageScore - left.usageScore;
            return left.name.localeCompare(right.name);
        });
        for (let i = 0; i < matches.length; i++) {
            const entry = matches[i];
            filteredEntries.append({ id: entry.id, name: entry.name, icon: entry.icon, exec: entry.exec });
        }
        selectedIndex = 0;
        list.positionViewAtBeginning();
    }

    function setQuery(value) {
        query = value;
        rebuildFiltered();
    }

    function filteredCount() {
        return filteredEntries.count;
    }

    function entryAtFilteredIndex(index) {
        return index >= 0 && index < filteredEntries.count ? filteredEntries.get(index) : null;
    }

    function moveSelection(delta) {
        const count = filteredCount();
        if (count === 0) return;
        const nextIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta));
        selectedIndex = nextIndex;
        list.currentIndex = nextIndex;
        list.positionViewAtIndex(nextIndex, ListView.Contain);
    }

    function scrollRows(rows) {
        const maximumY = Math.max(0, list.contentHeight - list.height);
        const rowHeight = itemHeight + itemGap;
        list.contentY = Math.max(0, Math.min(maximumY, list.contentY + rows * rowHeight));
    }

    // Mouse navigation moves the viewport, so make the visually central row
    // the keyboard starting point without repositioning the viewport again.
    function syncSelectionToViewportCenter() {
        const centerY = list.contentY + list.height / 2;
        let index = list.indexAt(list.width / 2, centerY);
        if (index < 0)
            index = list.indexAt(list.width / 2, centerY - 4);
        if (index < 0)
            index = list.indexAt(list.width / 2, centerY + 4);
        if (index >= 0)
            selectedIndex = index;
    }

    function activateSelected() {
        const entry = entryAtFilteredIndex(selectedIndex);
        if (!entry) return;
        if (clipboardOpen) {
            clipboardApply.command = ["bash", "-lc", "cliphist decode " + entry.id + " | wl-copy"];
            clipboardApply.running = true;
        } else {
            const command = executableCommand(entry.exec);
            if (command === "") return;
            pendingLaunchId = entry.id;
            console.debug("[Launcher] launching " + entry.id + ": " + command);
            // Hyprland 0.56's Lua dispatcher no longer accepts the legacy
            // `hyprctl dispatch exec <command>` syntax. Launch the desktop
            // entry directly in Dynis' Wayland session and detach it so the
            // launcher process can exit immediately.
            appLaunch.exec(["bash", "-lc", "setsid " + command + " >/dev/null 2>&1 < /dev/null &"]);
        }
        close();
    }

    function handleKey(event) {
        if (!active) return;
        if (event.key === Qt.Key_Escape) { close(); event.accepted = true; }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activateSelected(); event.accepted = true; }
        else if (event.key === Qt.Key_Up) { moveSelection(-1); event.accepted = true; }
        else if (event.key === Qt.Key_Down) { moveSelection(1); event.accepted = true; }
        else if (event.key === Qt.Key_Backspace) { setQuery(query.slice(0, -1)); event.accepted = true; }
        else if (event.text && event.text.length > 0 && !event.modifiers) { setQuery(query + event.text); event.accepted = true; }
    }


    Process {
        id: appScan
        running: true
        command: ["bash", "-lc", "find /usr/share/applications $HOME/.local/share/applications -type f -name '*.desktop' 2>/dev/null | sort -u | while IFS= read -r f; do grep -qx 'NoDisplay=true' \"$f\" && continue; n=$(sed -n 's/^Name=//p' \"$f\" | head -n1); i=$(sed -n 's/^Icon=//p' \"$f\" | head -n1); e=$(sed -n 's/^Exec=//p' \"$f\" | head -n1); [ -n \"$n\" ] && [ -n \"$e\" ] && printf '%s\\t%s\\t%s\\t%s\\n' \"$(basename \"$f\" .desktop)\" \"$n\" \"$i\" \"$e\"; done"]
        stdout: StdioCollector { onStreamFinished: root.rebuildFrom(this.text, false) }
    }

    Process {
        id: clipboardScan
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: root.rebuildFrom(this.text, true) }
    }

    Process {
        id: appLaunch
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "")
                    console.warn("[Launcher] app launch: " + this.text.trim());
            }
        }
        onStarted: console.debug("[Launcher] app launch started: " + root.pendingLaunchId)
        onExited: function(exitCode) {
            console.debug("[Launcher] app launch exited=" + exitCode + " id=" + root.pendingLaunchId);
            if (exitCode === 0 && root.pendingLaunchId !== "")
                root.recordLaunch(root.pendingLaunchId);
            root.pendingLaunchId = "";
        }
    }
    Process { id: clipboardApply }

    FileView {
        id: usageFile
        path: Qt.resolvedUrl("launcher-usage.json")
        printErrors: false
        onLoaded: root.loadUsageHistory()
        onLoadFailed: root.usageHistoryLoaded = true
    }

    Timer {
        id: usageSaveTimer
        interval: 250
        repeat: false
        onTriggered: usageFile.setText(JSON.stringify(root.usageHistory, null, 2) + "\n")
    }

    onLauncherActiveChanged: {
        console.debug("[Launcher] active=" + launcherActive
            + " monitorFocused=" + monitorFocused
            + " visible=" + active
            + " focusable=" + focusable);
        if (!launcherActive) {
            focusGrab.active = false;
            return;
        }

        // A focus grab only starts after a listed window is visible.
        Qt.callLater(function() {
            if (!root.launcherActive)
                return;
            console.debug("[Launcher] requesting focus grab; visible=" + root.visible);
            focusGrab.active = true;
            launcherFocusTimer.restart();
        });
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onActiveChanged: console.debug("[Launcher] focusGrab.active=" + active)
        onCleared: {
            console.debug("[Launcher] focus grab cleared by compositor");
            if (root.launcherActive)
                root.close();
        }
    }

    // The compositor assigns layer-shell focus after the surface is mapped.
    // Defer QML focus by one event-loop turn, as the overview already does.
    Timer {
        id: launcherFocusTimer
        interval: 16
        repeat: true
        property int attempts: 0
        onTriggered: {
            keyCatcher.forceActiveFocus();
            if (attempts === 0)
                console.debug("[Launcher] activeFocus=" + keyCatcher.activeFocus);
            attempts++;
            if (attempts >= 12)
                stop();
        }
        onRunningChanged: if (running) attempts = 0
    }


    // No fullscreen dimmer: it would turn the entire screen into an alpha
    // mask for HyprGlass instead of leaving glass only on the card.
    Item { anchors.fill: parent; visible: false }

    // Click outside the card closes the overlay. These are intentionally four
    // separate areas, never layered over the card itself.
    MouseArea { x: 0; y: 0; width: root.width; height: card.y; visible: root.active; onClicked: root.close() }
    MouseArea { x: 0; y: card.y + card.height; width: root.width; height: root.height - y; visible: root.active; onClicked: root.close() }
    MouseArea { x: 0; y: card.y; width: card.x; height: card.height; visible: root.active; onClicked: root.close() }
    MouseArea { x: card.x + card.width; y: card.y; width: root.width - x; height: card.height; visible: root.active; onClicked: root.close() }

    Rectangle {
        id: card
        visible: root.active
        width: Math.min(620, parent.width - 48)
        height: Math.min(438, parent.height - 48)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        radius: root.cardRadius
        clip: true
        color: "transparent"
        border.width: 0

        LiquidGlassSurface {
            anchors.fill: parent
            // Rendered by the tightly-sized Top-layer carrier behind the UI.
            visible: false
            cornerRadius: root.cardRadius
            tint: Qt.rgba(0, 0, 0, 0.004)
            edgeColor: "transparent"
            edgeWidth: 0
        }

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Text {
                text: root.clipboardOpen ? "Clipboard" : "Launch"
                color: "#eef8fc"
                font.family: root.textFontFamily
                font.pixelSize: 22
            }

            Rectangle {
                width: parent.width
                height: 54
                radius: 16
                // Keep the controls neutral even when the glass behind them
                // samples a saturated wallpaper.
                color: "#b0555555"
                border.width: 1
                border.color: "#a0d8d8d8"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    text: root.query === "" ? "Search…" : root.query
                    color: root.query === "" ? "#b9ccd5" : "#f4fbff"
                    font.family: root.textFontFamily
                    font.pixelSize: 18
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - 110
                model: filteredEntries
                clip: true
                spacing: 7
                // The mouse wheel is deliberately discrete: one wheel notch
                // advances exactly three complete rows. Disable Flickable's
                // smooth scrolling so it cannot add its own partial offset.
                interactive: false
                delegate: Item {
                    required property string id
                    required property string name
                    required property string icon
                    required property int index
                    width: list.width
                    height: root.itemHeight
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: index === root.selectedIndex ? "#c0787878" : "#b0555555"
                        border.width: index === root.selectedIndex ? 1 : 0
                        border.color: "#a8d8d8d8"
                    }
                    Image {
                        id: appIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28
                        visible: !root.clipboardOpen
                        source: Quickshell.iconPath(icon, "application-x-executable")
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: root.clipboardOpen ? 14 : appIcon.width + 28
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: name
                        color: "#f0f8fc"
                        elide: Text.ElideRight
                        font.family: root.textFontFamily
                        font.pixelSize: 17
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: function(mouse) {
                        const index = list.indexAt(mouse.x, mouse.y + list.contentY);
                        if (index >= 0)
                            root.selectedIndex = index;
                    }
                    onClicked: function(mouse) {
                        const index = list.indexAt(mouse.x, mouse.y + list.contentY);
                        if (index >= 0) {
                            root.selectedIndex = index;
                            list.currentIndex = index;
                            root.activateSelected();
                        }
                    }
                    onWheel: function(wheel) {
                        if (wheel.angleDelta.y === 0)
                            return;
                        root.scrollRows(wheel.angleDelta.y < 0 ? 3 : -3);
                        Qt.callLater(root.syncSelectionToViewportCenter);
                        wheel.accepted = true;
                    }
                }
                onCountChanged: positionViewAtBeginning()
            }
        }
    }

    // PanelWindow itself is not an Item, so this focus target must be a child.
    // The layershell window still has Exclusive keyboard focus while open.
    FocusScope {
        id: keyCatcher
        anchors.fill: parent
        focus: root.launcherActive
        Keys.onPressed: function(event) { root.handleKey(event); }
    }
}
