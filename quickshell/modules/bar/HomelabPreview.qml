pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.common
import qs.modules.overlay

// Homelab popup, opened from Homelab.qml. Two layouts on the same state:
//
// Docked - exceptions first: three summary tiles (services with a
// per-container dot matrix, Syncthing completion ring, tailnet peer dots),
// then only what's wrong or in progress, worst first, each with its one
// action (Start for a stopped container). Nothing wrong collapses to one
// "Everything's healthy" line.
//
// Floating - left: every container with its uptime bead strip (click a row
// to follow its logs), then a Folders / Activity switch (Syncthing folders
// and devices, or the merged feed of container, peer and file events).
// Right: the tailnet topology (HomelabTopology.qml) - click a node to ping
// it, the latency lands on its edge - with Status (`tailscale status`).
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    readonly property color downColor: "#ff4d4d"
    property string tsStatusText: ""
    property bool showTsStatus: false
    property string tab: "folders"

    // Ticks the "12s ago" strings over.
    property real now: Date.now()
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: popup.now = Date.now()
    }

    // Container whose logs are expanded ("" = none). Kept by id rather than
    // on the row, since rows rebuild whenever a status string ticks over.
    property string logsId: ""
    property var logLines: []
    property string logsText: ""
    property string logsError: ""
    property bool logsEnded: false
    readonly property int maxLogLines: 200

    // { ip: { state: "pinging" | "ok" | "fail", ms, via } }
    property var pings: ({})
    // Start actions in flight / their last error.
    property var starting: ({})
    property string actionError: ""

    Component.onCompleted: HomelabState.refresh()

    // Syncthing's traffic counters are the one thing with no event; only
    // the floating layout shows them.
    Timer {
        interval: 5000
        running: HomelabState.stConfigured && popup.floating
        repeat: true
        onTriggered: HomelabState.stRefreshConnections()
    }

    readonly property var icons: ({
        box: String.fromCodePoint(0xf01a7),     // md-cube-outline
        sync: "󰓦",
        mesh: "󰖂",
        folder: String.fromCodePoint(0xf024b),  // md-folder
        check: "󰄬",
        device: "󰌹",
        alert: String.fromCodePoint(0xf0026)    // md-alert
    })

    function setMapKey(prop, key, value) {
        const m = Object.assign({}, popup[prop]);
        if (value === undefined)
            delete m[key];
        else
            m[key] = value;
        popup[prop] = m;
    }

    function start(id) {
        if (popup.starting[id])
            return;
        popup.setMapKey("starting", id, true);
        popup.actionError = "";
        HomelabState.startContainer(id, err => {
            popup.setMapKey("starting", id, undefined);
            if (err)
                popup.actionError = "Start failed: " + err;
        });
    }

    // ---- Summary (docked) ----

    readonly property var folderTotals: {
        let global = 0, inSync = 0, syncing = 0, errors = 0, idle = 0;
        for (const f of HomelabState.stFolders) {
            if (f.paused)
                continue;
            global += f.globalBytes;
            inSync += f.inSyncBytes;
            if (f.errors > 0 || f.state === "error")
                errors++;
            else if (f.needFiles > 0 || f.state.startsWith("sync"))
                syncing++;
            else
                idle++;
        }
        return { pct: global > 0 ? inSync / global : 1, syncing: syncing, errors: errors, idle: idle };
    }

    // Everything that needs a look, worst first:
    // [{ sev, icon, title, detail, progress (0..1 or -1), action, id }]
    readonly property var issues: {
        const out = [];
        if (HomelabState.configured && HomelabState.servicesError.length > 0)
            out.push({ sev: "err", icon: "box", title: "Portainer unreachable", detail: HomelabState.servicesError });
        for (const c of HomelabState.containers) {
            const sev = HomelabState.containerSeverity(c);
            if (sev === "ok")
                continue;
            out.push({
                sev: sev, icon: "box", title: c.name,
                detail: c.health === "unhealthy"
                        ? "healthcheck failing  ·  " + c.status.replace(/\s*\(unhealthy\)/, "") : c.status,
                action: c.state === "exited" || c.state === "created" ? "start" : "", id: c.id
            });
        }
        if (HomelabState.stConfigured && !HomelabState.stReachable && HomelabState.stError.length > 0)
            out.push({ sev: "err", icon: "sync", title: "Syncthing unreachable", detail: HomelabState.stError });
        for (const f of HomelabState.stFolders) {
            if (f.paused) {
                out.push({ sev: "off", icon: "folder", title: f.label + " paused", detail: f.path });
            } else if (f.errors > 0 || f.state === "error") {
                out.push({ sev: "err", icon: "folder", title: f.label + "  ·  " + f.errors + " errors",
                           detail: f.state });
            } else if (f.needFiles > 0 || f.state.startsWith("sync")) {
                out.push({ sev: "busy", icon: "sync", title: f.label + " syncing",
                           detail: f.needFiles + " files  ·  " + HomelabState.fmtBytes(f.needBytes) + " left",
                           progress: f.globalBytes > 0 ? f.inSyncBytes / f.globalBytes : 0 });
            }
        }
        const gone = HomelabState.stDevices.filter(d => !d.connected && !d.paused);
        if (HomelabState.stReachable && gone.length > 0)
            out.push({ sev: "off", icon: "device", title: gone.map(d => d.name).join(", ") + " disconnected",
                       detail: "Syncthing devices" });
        if (HomelabState.tsState.length > 0 && HomelabState.tsState !== "Running")
            out.push({ sev: "err", icon: "mesh", title: "Tailscale " + HomelabState.tsState, detail: "" });
        const offline = HomelabState.tsPeers.filter(p => !p.online);
        if (offline.length > 0)
            out.push({ sev: "off", icon: "mesh", title: offline.map(p => p.hostName).join(", ") + " offline",
                       detail: offline.map(p => p.lastSeen ? "seen " + HomelabState.ago(p.lastSeen, popup.now) : "")
                                      .filter(s => s.length > 0).join("  ·  ") });
        const rank = { err: 0, busy: 1, off: 2 };
        return out.map((x, i) => Object.assign({ progress: -1, action: "", id: "", key: i }, x))
                  .sort((a, b) => rank[a.sev] - rank[b.sev] || a.key - b.key);
    }

    // ---- Logs (floating) ----

    function toggleLogs(id) {
        logsProc.running = false;
        popup.logsId = popup.logsId === id ? "" : id;
        popup.logLines = [];
        popup.logsText = "";
        popup.logsError = "";
        popup.logsEnded = false;
        if (popup.logsId.length > 0)
            Qt.callLater(() => logsProc.running = true);
    }

    // Non-TTY containers send Docker's multiplexed stream: an 8-byte header
    // ([stream, 0, 0, 0, len32]) before every chunk. Chunks are usually
    // whole lines, so headers sit at line starts; strip them wherever they
    // are. A length byte of 0x0a splits a header across two "lines" - drop
    // the stub and the leftover control bytes.
    function cleanLogLine(line) {
        if (/^[\x01\x02]\x00\x00\x00[\s\S]{0,3}$/.test(line))
            return null;
        return line.replace(/[\x01\x02]\x00\x00\x00[\s\S]{4}/g, "")
            .replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "")
            .replace(/\r/g, "")
            .replace(/^[\x00-\x08\x0b-\x1f]+/, "");
    }

    // Follows the log live (tail=40, then new lines as they're written)
    // until collapsed or the panel closes. Lines are batched into one text
    // update per event-loop turn so a chatty container doesn't re-layout
    // the Text per line.
    Process {
        id: logsProc
        command: ["curl", "-fsSN", "--keepalive-time", "20", "-K", "-",
            HomelabState.dockerApi + "/containers/" + popup.logsId + "/logs?follow=1&stdout=1&stderr=1&tail=40"]
        stdinEnabled: true
        onStarted: {
            logsProc.write(HomelabState.curlHeader(HomelabState.token));
            logsProc.stdinEnabled = false;
        }
        stdout: SplitParser {
            onRead: line => {
                const l = popup.cleanLogLine(line);
                if (l === null)
                    return;
                popup.logLines.push(l);
                Qt.callLater(popup.flushLogs);
            }
        }
        stderr: StdioCollector {
            id: logsErr
            onStreamFinished: {
                const err = logsErr.text.trim();
                if (err.length > 0)
                    popup.logsError = err.split("\n").pop();
            }
        }
        onExited: {
            logsProc.stdinEnabled = true;
            popup.logsEnded = true;
        }
    }

    function flushLogs() {
        if (popup.logLines.length > popup.maxLogLines)
            popup.logLines = popup.logLines.slice(-popup.maxLogLines);
        popup.logsText = popup.logLines.join("\n");
    }

    // ---- Tailscale ----

    Process {
        id: tsStatusProc
        command: ["tailscale", "status"]
        stdout: StdioCollector {
            id: tsStatusOut
            onStreamFinished: popup.tsStatusText = tsStatusOut.text.replace(/\s+$/, "")
        }
        stderr: StdioCollector {
            id: tsStatusErr
            onStreamFinished: {
                const err = tsStatusErr.text.trim();
                if (err.length > 0 && popup.tsStatusText.length === 0)
                    popup.tsStatusText = err;
            }
        }
    }

    function toggleTsStatus() {
        popup.showTsStatus = !popup.showTsStatus;
        if (popup.showTsStatus && !tsStatusProc.running) {
            popup.tsStatusText = "";
            tsStatusProc.running = true;
        }
    }

    function ping(ip) {
        if (popup.pings[ip]?.state === "pinging")
            return;
        popup.setMapKey("pings", ip, { state: "pinging", ms: "", via: popup.pings[ip]?.via ?? "" });
        pingComp.createObject(popup, { ip: ip });
    }

    function pingAll() {
        for (const p of HomelabState.tsPeers)
            if (p.online)
                popup.ping(p.ip);
    }

    // One process per ping, so several can run at once. stdout's end and
    // the exit come in either order; whichever is second settles it.
    // `tailscale ping` prints e.g. "pong from host (100.x.y.z) via
    // DERP(nyc) in 45ms", or "via 192.168.1.5:41641 in 2ms" when direct.
    Component {
        id: pingComp
        Process {
            id: pingProc
            required property string ip
            property string out: ""
            property int code: -1
            property int done: 0

            function settle() {
                if (++pingProc.done < 2)
                    return;
                const line = pingProc.out.trim().split("\n").pop() ?? "";
                const m = line.match(/via (.+) in (\S+)/);
                if (m) {
                    const derp = m[1].match(/^DERP\((.+)\)$/);
                    popup.setMapKey("pings", pingProc.ip, { state: "ok", ms: m[2], via: derp ? derp[1] : "direct" });
                } else {
                    popup.setMapKey("pings", pingProc.ip, { state: "fail", ms: "", via: "" });
                }
                pingProc.destroy();
            }

            command: ["tailscale", "ping", "-c", "1", "--timeout", "3s", pingProc.ip]
            running: true
            stdout: StdioCollector {
                id: pingOut
                onStreamFinished: {
                    pingProc.out = pingOut.text;
                    pingProc.settle();
                }
            }
            onExited: code => {
                pingProc.code = code;
                pingProc.settle();
            }
        }
    }

    // ---- Shared bits ----

    component Caption: Text {
        color: Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 5
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
    }

    component Meta: Text {
        color: Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 4
        elide: Text.ElideRight
    }

    component Body: Text {
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
        elide: Text.ElideRight
    }

    // Small clickable glyph.
    component IconButton: Text {
        id: iconButton
        signal triggered

        color: iconMa.containsMouse ? Theme.accent : Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        anchors.verticalCenter: parent?.verticalCenter

        MouseArea {
            id: iconMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.triggered()
        }
    }

    component TextButton: Rectangle {
        id: textButton
        property alias text: label.text
        property bool active: false
        signal triggered

        width: label.implicitWidth + 16
        height: label.implicitHeight + 6
        radius: 4
        color: textButtonMa.containsMouse || textButton.active ? Theme.hoverBg : "transparent"
        border.width: 1
        border.color: textButton.active ? Theme.accent : Theme.pillBorder
        anchors.verticalCenter: parent?.verticalCenter

        Text {
            id: label
            anchors.centerIn: parent
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
        }

        MouseArea {
            id: textButtonMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: textButton.triggered()
        }
    }

    // State by shape first: ok solid, off hollow, err red, busy pulsing.
    component StatusDot: Rectangle {
        id: statusDot
        property string sev: "ok"
        width: 8
        height: 8
        radius: 4
        color: sev === "err" ? popup.downColor : sev === "ok" || sev === "busy" ? Theme.accent : "transparent"
        border.width: sev === "off" || sev === "" ? 1.5 : 0
        border.color: Theme.dimText
        onSevChanged: if (sev !== "busy") opacity = 1
        SequentialAnimation on opacity {
            running: statusDot.sev === "busy"
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 700 }
            NumberAnimation { to: 1; duration: 700 }
        }
    }

    // Section heading with a hairline to the right.
    component Section: Item {
        id: section
        property alias text: sectionLabel.text
        property string badge: ""
        property bool badgeBad: false
        width: parent?.width ?? 0
        height: 20

        Caption {
            id: sectionLabel
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            id: badgeRect
            visible: section.badge.length > 0
            anchors.left: sectionLabel.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: badgeText.implicitWidth + 10
            height: 14
            radius: 7
            color: section.badgeBad ? Theme.withAlpha(popup.downColor, 0.2) : Theme.hoverBg
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: section.badge
                color: section.badgeBad ? popup.downColor : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 6
            }
        }
        Rectangle {
            anchors.left: section.badge.length > 0 ? badgeRect.right : sectionLabel.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Theme.withAlpha(Theme.foreground, 0.1)
        }
    }

    component ProgressRing: Shape {
        id: progressRing
        property real value: 0
        property real size: 34
        property real thickness: 3
        width: size
        height: size
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.withAlpha(Theme.foreground, 0.12)
            strokeWidth: progressRing.thickness
            fillColor: "transparent"
            PathAngleArc {
                centerX: progressRing.size / 2
                centerY: progressRing.size / 2
                radiusX: (progressRing.size - progressRing.thickness) / 2
                radiusY: (progressRing.size - progressRing.thickness) / 2
                startAngle: 0
                sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: Theme.accent
            strokeWidth: progressRing.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: progressRing.size / 2
                centerY: progressRing.size / 2
                radiusX: (progressRing.size - progressRing.thickness) / 2
                radiusY: (progressRing.size - progressRing.thickness) / 2
                startAngle: -90
                sweepAngle: 360 * Math.max(0, Math.min(1, progressRing.value))
            }
        }
    }

    component ProgressBar: Rectangle {
        property real value: 0
        height: 4
        radius: 2
        color: Theme.withAlpha(Theme.foreground, 0.12)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }

    // Summary tile: caption, big value + a visual, a sub line.
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property alias caption: tileCaption.text
        property alias value: tileValue.text
        property alias sub: tileSub.text
        property bool bad: false
        default property alias visual: visualSlot.data

        height: 86
        radius: 8
        color: Theme.withAlpha(Theme.foreground, 0.04)
        border.width: 1
        border.color: tile.bad ? Theme.withAlpha(popup.downColor, 0.45) : Theme.withAlpha(Theme.foreground, 0.1)

        Row {
            x: 10
            y: 9
            spacing: 6
            Text {
                text: tile.icon
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }
            Caption {
                id: tileCaption
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            id: tileValue
            x: 10
            y: 28
            color: tile.bad ? popup.downColor : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 20
            font.bold: true
        }
        Item {
            id: visualSlot
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: 28
            width: childrenRect.width
            height: 32
        }
        Meta {
            id: tileSub
            x: 10
            y: 64
            width: parent.width - 20
            font.pixelSize: Theme.fontSize - 5
        }
    }

    // Grid of small cells, one per entry: sev per cell.
    component DotMatrix: Grid {
        id: matrix
        property var cells: []
        property bool round: false
        columns: Math.max(1, Math.min(6, Math.ceil(Math.sqrt(cells.length * 1.4))))
        spacing: 3
        anchors.verticalCenter: parent?.verticalCenter
        Repeater {
            model: matrix.cells
            delegate: Rectangle {
                required property string modelData
                width: 9
                height: 9
                radius: matrix.round ? 4.5 : 2
                color: modelData === "err" ? popup.downColor : modelData === "ok" ? Theme.accent : "transparent"
                border.width: modelData === "off" ? 1.5 : 0
                border.color: Theme.dimText
            }
        }
    }

    Item {
        id: card
        width: popup.floating ? 940 : 440
        height: (contentLoader.item?.implicitHeight ?? 0) + 32

        Loader {
            id: contentLoader
            x: 16
            y: 16
            width: card.width - 32
            sourceComponent: popup.floating ? floatingView : dockedView
        }
    }

    // ================= Docked: exceptions first =================

    Component {
        id: dockedView

        Column {
            id: docked
            spacing: 8

            Item {
                width: docked.width
                height: 22

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text {
                        text: "Homelab"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    Meta {
                        anchors.verticalCenter: parent.verticalCenter
                        text: [HomelabState.tsSelf?.hostName ?? "", HomelabState.tsTailnet]
                              .filter(s => s.length > 0).join("  ·  ")
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    spacing: 14
                    IconButton {
                        text: String.fromCharCode(0xf021) // fa-refresh
                        onTriggered: HomelabState.refresh()
                    }
                }
            }

            Row {
                id: tiles
                readonly property real tileWidth: (docked.width - 2 * spacing) / 3
                spacing: 8

                Tile {
                    width: tiles.tileWidth
                    icon: popup.icons.box
                    caption: "Services"
                    bad: HomelabState.servicesError.length > 0
                         || HomelabState.containers.some(c => HomelabState.containerSeverity(c) === "err")
                    value: !HomelabState.configured ? "—"
                           : HomelabState.servicesError.length > 0 && HomelabState.totalCount === 0 ? "?"
                           : HomelabState.upCount + "/" + HomelabState.totalCount
                    sub: {
                        if (!HomelabState.configured)
                            return "not configured";
                        const sev = HomelabState.containers.map(c => HomelabState.containerSeverity(c));
                        const bad = sev.filter(s => s === "err").length, off = sev.filter(s => s === "off").length;
                        if (bad + off === 0)
                            return HomelabState.totalCount > 0 ? "all healthy" : "";
                        return [bad > 0 ? bad + " failing" : "", off > 0 ? off + " off" : ""]
                               .filter(s => s.length > 0).join(" · ");
                    }
                    DotMatrix {
                        cells: HomelabState.containers.map(c => HomelabState.containerSeverity(c))
                    }
                }

                Tile {
                    width: tiles.tileWidth
                    icon: popup.icons.sync
                    caption: "Syncthing"
                    bad: popup.folderTotals.errors > 0 || (HomelabState.stConfigured && !HomelabState.stReachable)
                    value: !HomelabState.stReachable ? "—"
                           : Math.floor(popup.folderTotals.pct * 100) + "%"
                    sub: !HomelabState.stConfigured ? "not configured"
                         : !HomelabState.stReachable ? "unreachable"
                         : popup.folderTotals.syncing + popup.folderTotals.errors === 0
                           ? popup.folderTotals.idle + " folders idle"
                         : [popup.folderTotals.syncing > 0 ? popup.folderTotals.syncing + " syncing" : "",
                            popup.folderTotals.errors > 0 ? popup.folderTotals.errors + " error" : ""]
                           .filter(s => s.length > 0).join(" · ")
                    ProgressRing {
                        visible: HomelabState.stReachable
                        value: popup.folderTotals.pct
                        size: 30
                    }
                }

                Tile {
                    width: tiles.tileWidth
                    icon: popup.icons.mesh
                    caption: "Tailnet"
                    bad: HomelabState.tsState.length > 0 && HomelabState.tsState !== "Running"
                    value: HomelabState.tsState === "Running"
                           ? HomelabState.tsPeers.filter(p => p.online).length + "/" + HomelabState.tsPeers.length
                           : "—"
                    sub: HomelabState.tsState === "Running" ? "peers online" : (HomelabState.tsState || "…")
                    DotMatrix {
                        round: true
                        cells: HomelabState.tsPeers.slice(0, 18).map(p => p.online ? "ok" : "off")
                    }
                }
            }

            Section {
                text: popup.issues.length > 0 ? "Needs attention" : "Status"
                badge: popup.issues.filter(i => i.sev === "err").length > 0
                       ? "" + popup.issues.filter(i => i.sev === "err").length : ""
                badgeBad: true
            }

            // All good: one line.
            Row {
                visible: popup.issues.length === 0
                leftPadding: 8
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: popup.icons.check
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                }
                Column {
                    Body { text: "Everything's healthy" }
                    Meta {
                        width: docked.width - 40
                        readonly property var last: HomelabState.activityFeed[0] ?? null
                        text: last ? "last change: " + last.title + " " + last.detail + "  ·  " + HomelabState.ago(last.time, popup.now)
                                   : "no recent changes"
                        elide: Text.ElideMiddle
                    }
                }
            }

            Column {
                visible: popup.issues.length > 0
                width: docked.width
                spacing: 2

                Repeater {
                    model: popup.issues
                    delegate: Rectangle {
                        id: issueRow
                        required property var modelData
                        width: docked.width
                        height: issueText.implicitHeight + 12
                        radius: 4
                        color: issueMa.containsMouse ? Theme.hoverBg : "transparent"
                        opacity: modelData.sev === "off" ? 0.8 : 1

                        MouseArea {
                            id: issueMa
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        StatusDot {
                            x: 8
                            y: 10
                            sev: issueRow.modelData.sev
                        }
                        Text {
                            x: 24
                            y: 5
                            text: popup.icons[issueRow.modelData.icon] ?? ""
                            color: Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Column {
                            id: issueText
                            x: 46
                            y: 6
                            width: parent.width - x - (issueAction.visible ? issueAction.width + 16 : 8)
                            spacing: 1
                            Body {
                                width: parent.width
                                text: issueRow.modelData.title
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Meta {
                                visible: text.length > 0
                                width: parent.width
                                text: issueRow.modelData.detail
                                color: issueRow.modelData.sev === "err" ? popup.downColor : Theme.dimText
                            }
                            ProgressBar {
                                visible: issueRow.modelData.progress >= 0
                                width: parent.width
                                value: issueRow.modelData.progress
                            }
                        }
                        TextButton {
                            id: issueAction
                            visible: issueRow.modelData.action === "start"
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: undefined
                            y: 6
                            text: popup.starting[issueRow.modelData.id] ? "Starting…" : "Start"
                            active: popup.starting[issueRow.modelData.id] ?? false
                            onTriggered: popup.start(issueRow.modelData.id)
                        }
                    }
                }
            }

            Meta {
                visible: popup.actionError.length > 0
                width: docked.width
                text: popup.actionError
                color: popup.downColor
                wrapMode: Text.Wrap
            }
        }
    }

    // ================= Floating: beads + feed | topology =================

    Component {
        id: floatingView

        Column {
            id: floating
            spacing: 10

            readonly property real leftWidth: 480
            readonly property real rightWidth: floating.width - leftWidth - 24

            Item {
                width: floating.width
                height: 24

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text {
                        text: "Homelab"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    Meta {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "beads: " + Math.round(HomelabState.beadMs / 1000) + " s each, last "
                              + Math.round(HomelabState.beadCount * HomelabState.beadMs / 60000) + " min"
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    spacing: 8
                    TextButton {
                        visible: HomelabState.configured
                        text: "󰏌  Portainer"
                        onTriggered: Quickshell.execDetached(["firefox", "--new-tab", HomelabState.portainerUrl])
                    }
                    TextButton {
                        visible: HomelabState.stConfigured
                        text: "󰏌  Syncthing"
                        onTriggered: Quickshell.execDetached(["firefox", "--new-tab", HomelabState.stUrl])
                    }
                    Item { width: 4; height: 1 }
                    IconButton {
                        text: String.fromCharCode(0xf021) // fa-refresh
                        onTriggered: HomelabState.refresh()
                    }
                }
            }

            Row {
                spacing: 24

                // ---------- Left: services + folders/activity ----------
                Column {
                    id: left
                    width: floating.leftWidth
                    spacing: 4

                    Section {
                        text: "Services"
                        badge: HomelabState.configured ? HomelabState.upCount + "/" + HomelabState.totalCount : ""
                        badgeBad: HomelabState.upCount < HomelabState.totalCount
                    }

                    Meta {
                        visible: !HomelabState.configured || HomelabState.servicesError.length > 0
                        width: left.width
                        text: !HomelabState.configured ? "Set PORTAINER, TOKEN and ENV_ID" : HomelabState.servicesError
                        color: popup.downColor
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: HomelabState.containers
                        delegate: Column {
                            id: containerItem
                            required property var modelData
                            readonly property bool expanded: popup.logsId === modelData.id
                            readonly property string sev: HomelabState.containerSeverity(modelData)
                            readonly property var strip: HomelabState.beadsFor(modelData.id)
                            readonly property int known: strip.filter(b => b !== "").length

                            width: left.width
                            spacing: 2

                            Rectangle {
                                width: left.width
                                height: 32
                                radius: 4
                                color: containerMa.containsMouse || containerItem.expanded ? Theme.hoverBg : "transparent"

                                MouseArea {
                                    id: containerMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: popup.toggleLogs(containerItem.modelData.id)
                                }

                                StatusDot {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    sev: containerItem.sev
                                }
                                Column {
                                    x: 24
                                    width: 150
                                    anchors.verticalCenter: parent.verticalCenter
                                    Body {
                                        width: parent.width
                                        text: containerItem.modelData.name
                                        font.pixelSize: Theme.fontSize - 3
                                        color: containerItem.sev === "off" ? Theme.dimText : Theme.text
                                    }
                                    Meta {
                                        width: parent.width
                                        text: containerItem.modelData.status
                                        font.pixelSize: Theme.fontSize - 6
                                        color: containerItem.sev === "err" ? popup.downColor : Theme.dimText
                                    }
                                }
                                // Oldest left, newest (the open slot) right.
                                Row {
                                    id: beadRow
                                    x: 184
                                    width: parent.width - x - 50
                                    height: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Repeater {
                                        model: containerItem.strip
                                        delegate: Rectangle {
                                            required property string modelData
                                            required property int index
                                            width: (beadRow.width - (HomelabState.beadCount - 1) * beadRow.spacing) / HomelabState.beadCount
                                            height: beadRow.height
                                            radius: 2
                                            color: modelData === "ok" ? Theme.withAlpha(Theme.accent, 0.45 + 0.55 * index / HomelabState.beadCount)
                                                   : modelData === "err" ? popup.downColor : "transparent"
                                            border.width: modelData === "off" || modelData === "" ? 1 : 0
                                            border.color: modelData === "off" ? Theme.dimText : Theme.withAlpha(Theme.foreground, 0.12)
                                        }
                                    }
                                }
                                Meta {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: containerItem.known === 0 ? "—"
                                          : Math.round(100 * containerItem.strip.filter(b => b === "ok").length / containerItem.known) + "%"
                                }
                            }

                            // Live log follow, pinned to the bottom unless
                            // scrolled up.
                            Rectangle {
                                visible: containerItem.expanded
                                width: left.width
                                height: Math.min(logsView.implicitHeight + 12, 360)
                                radius: 4
                                color: Theme.withAlpha(Theme.color0, 0.6)
                                border.width: 1
                                border.color: Theme.pillBorder
                                clip: true

                                Flickable {
                                    id: logsFlick
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    contentWidth: width
                                    contentHeight: logsView.implicitHeight
                                    boundsBehavior: Flickable.StopAtBounds
                                    property bool pinned: true
                                    onMovementEnded: logsFlick.pinned = logsFlick.atYEnd
                                    onContentHeightChanged: if (logsFlick.pinned) logsFlick.contentY = Math.max(0, contentHeight - height)
                                    onHeightChanged: if (logsFlick.pinned) logsFlick.contentY = Math.max(0, contentHeight - height)

                                    Text {
                                        id: logsView
                                        width: logsFlick.width
                                        text: popup.logsError.length > 0 && popup.logsText.length === 0 ? popup.logsError
                                              : popup.logsText.length > 0 ? popup.logsText
                                              : popup.logsEnded ? "(no log output)" : "Loading…"
                                        color: popup.logsError.length > 0 && popup.logsText.length === 0 ? popup.downColor : Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 5
                                        wrapMode: Text.WrapAnywhere
                                        textFormat: Text.PlainText
                                    }
                                }
                            }
                        }
                    }

                    // Folders | Activity
                    Item {
                        width: left.width
                        height: 34

                        Rectangle {
                            id: tabs
                            anchors.bottom: parent.bottom
                            width: tabRow.width + 4
                            height: 24
                            radius: 6
                            color: Theme.withAlpha(Theme.foreground, 0.06)

                            Row {
                                id: tabRow
                                x: 2
                                anchors.verticalCenter: parent.verticalCenter
                                Repeater {
                                    model: [["folders", "Folders"], ["activity", "Activity"]]
                                    delegate: Rectangle {
                                        id: tabButton
                                        required property var modelData
                                        readonly property bool on: popup.tab === modelData[0]
                                        width: tabLabel.implicitWidth + 20
                                        height: 20
                                        radius: 5
                                        color: on ? Theme.withAlpha(Theme.accent, 0.25) : tabMa.containsMouse ? Theme.hoverBg : "transparent"
                                        Text {
                                            id: tabLabel
                                            anchors.centerIn: parent
                                            text: tabButton.modelData[1]
                                            color: tabButton.on ? Theme.text : Theme.dimText
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 4
                                        }
                                        MouseArea {
                                            id: tabMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: popup.tab = tabButton.modelData[0]
                                        }
                                    }
                                }
                            }
                        }
                        Meta {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: tabs.verticalCenter
                            text: {
                                if (popup.tab === "activity")
                                    return HomelabState.activityFeed.length + " events";
                                const d = HomelabState.stDevices;
                                let t = d.filter(x => x.connected).length + "/" + d.length + " devices";
                                const tot = HomelabState.stTotals;
                                if (tot)
                                    t += "  ·  ↓ " + HomelabState.fmtBytes(tot.inBytes) + "  ↑ " + HomelabState.fmtBytes(tot.outBytes);
                                return t;
                            }
                        }
                    }

                    // ---- Folders tab ----
                    Column {
                        visible: popup.tab === "folders"
                        width: left.width
                        spacing: 2

                        Meta {
                            visible: !HomelabState.stConfigured || HomelabState.stError.length > 0
                            width: left.width
                            text: !HomelabState.stConfigured ? "Set SYNCTHING_URL and SYNCTHING_API_KEY" : HomelabState.stError
                            color: popup.downColor
                            wrapMode: Text.Wrap
                        }

                        Repeater {
                            model: HomelabState.stFolders
                            delegate: Item {
                                id: folderRow
                                required property var modelData
                                readonly property bool bad: modelData.errors > 0 || modelData.state === "error"
                                readonly property bool busy: modelData.state.startsWith("sync") || modelData.state.startsWith("scan")
                                                             || modelData.needFiles > 0
                                readonly property real pct: modelData.globalBytes > 0
                                                            ? 100 * modelData.inSyncBytes / modelData.globalBytes : 100

                                width: left.width
                                height: 36

                                StatusDot {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    sev: folderRow.bad ? "err" : folderRow.modelData.paused ? "off" : folderRow.busy ? "busy" : "ok"
                                }
                                Column {
                                    x: 24
                                    width: parent.width - x - 8
                                    anchors.verticalCenter: parent.verticalCenter

                                    Item {
                                        width: parent.width
                                        height: folderName.implicitHeight
                                        Body {
                                            id: folderName
                                            width: parent.width - folderState.implicitWidth - 8
                                            text: folderRow.modelData.label
                                            font.pixelSize: Theme.fontSize - 3
                                        }
                                        Meta {
                                            id: folderState
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: folderRow.modelData.paused ? "paused"
                                                  : folderRow.bad ? folderRow.modelData.errors + " errors"
                                                  : folderRow.modelData.needFiles > 0
                                                    ? folderRow.modelData.state + "  " + folderRow.pct.toFixed(1) + "%"
                                                  : folderRow.modelData.state === "idle" ? "up to date" : folderRow.modelData.state
                                            color: folderRow.bad ? popup.downColor : folderRow.busy ? Theme.accent : Theme.dimText
                                        }
                                    }
                                    Meta {
                                        width: parent.width
                                        font.pixelSize: Theme.fontSize - 5
                                        text: folderRow.modelData.globalFiles + " files  ·  " + HomelabState.fmtBytes(folderRow.modelData.globalBytes)
                                              + (folderRow.modelData.needFiles > 0
                                                 ? "  ·  need " + folderRow.modelData.needFiles + " (" + HomelabState.fmtBytes(folderRow.modelData.needBytes) + ")"
                                                 : folderRow.modelData.lastFile.length > 0
                                                   ? "  ·  last " + folderRow.modelData.lastFile.split("/").pop()
                                                     + " " + HomelabState.ago(folderRow.modelData.lastFileAt, popup.now)
                                                   : "")
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: HomelabState.stDevices
                            delegate: Item {
                                id: deviceRow
                                required property var modelData
                                width: left.width
                                height: 22

                                Meta {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.right: deviceTraffic.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (deviceRow.modelData.connected ? "󰌹  " : "󰌺  ") + deviceRow.modelData.name
                                          + (deviceRow.modelData.connected && deviceRow.modelData.type.length > 0
                                             ? "  ·  " + deviceRow.modelData.type : "")
                                          + (deviceRow.modelData.paused ? "  ·  paused" : "")
                                    color: deviceRow.modelData.connected ? Theme.text : Theme.dimText
                                }
                                Meta {
                                    id: deviceTraffic
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: deviceRow.modelData.connected
                                    font.pixelSize: Theme.fontSize - 5
                                    text: "↓ " + HomelabState.fmtBytes(deviceRow.modelData.inBytes)
                                          + "  ↑ " + HomelabState.fmtBytes(deviceRow.modelData.outBytes)
                                }
                            }
                        }
                    }

                    // ---- Activity tab ----
                    Item {
                        visible: popup.tab === "activity"
                        width: left.width
                        height: feed.height

                        // Timeline spine through the dots.
                        Rectangle {
                            visible: HomelabState.activityFeed.length > 1
                            x: 53
                            y: 12
                            width: 1
                            height: Math.max(0, feed.height - 24)
                            color: Theme.withAlpha(Theme.foreground, 0.1)
                        }

                        Column {
                            id: feed
                            width: parent.width

                            Meta {
                                visible: HomelabState.activityFeed.length === 0
                                leftPadding: 8
                                text: "Nothing yet - container, peer and file events show up here."
                            }

                            Repeater {
                                model: HomelabState.activityFeed.slice(0, 16)
                                delegate: Item {
                                    id: feedRow
                                    required property var modelData
                                    width: left.width
                                    height: 32

                                    Meta {
                                        width: 40
                                        y: 3
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize: Theme.fontSize - 5
                                        text: HomelabState.ago(feedRow.modelData.time, popup.now).replace(" ago", "")
                                    }
                                    StatusDot {
                                        x: 50
                                        y: 5
                                        sev: feedRow.modelData.sev
                                    }
                                    Column {
                                        x: 68
                                        width: parent.width - x - 8
                                        Body {
                                            width: parent.width
                                            font.pixelSize: Theme.fontSize - 3
                                            text: feedRow.modelData.title
                                            color: feedRow.modelData.sev === "err" ? popup.downColor : Theme.text
                                            elide: Text.ElideMiddle
                                        }
                                        Meta {
                                            width: parent.width
                                            font.pixelSize: Theme.fontSize - 5
                                            text: (feedRow.modelData.source === "docker" ? popup.icons.box
                                                   : feedRow.modelData.source === "peer" ? popup.icons.mesh
                                                   : popup.icons.sync) + "  " + feedRow.modelData.detail
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------- Right: tailnet topology ----------
                Column {
                    id: right
                    width: floating.rightWidth
                    spacing: 6

                    Item {
                        width: right.width
                        height: 24

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Caption {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Tailnet"
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property bool up: HomelabState.tsState === "Running"
                                width: stateChip.implicitWidth + 12
                                height: 16
                                radius: 8
                                color: up ? Theme.withAlpha(Theme.accent, 0.2) : Theme.withAlpha(popup.downColor, 0.2)
                                Text {
                                    id: stateChip
                                    anchors.centerIn: parent
                                    text: HomelabState.tsState || "…"
                                    color: parent.up ? Theme.text : popup.downColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 6
                                }
                            }
                            Meta {
                                anchors.verticalCenter: parent.verticalCenter
                                text: HomelabState.tsTailnet
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            TextButton {
                                text: "Status"
                                active: popup.showTsStatus
                                onTriggered: popup.toggleTsStatus()
                            }
                            TextButton {
                                text: "Ping all"
                                onTriggered: popup.pingAll()
                            }
                        }
                    }

                    HomelabTopology {
                        width: right.width
                        height: 360
                        peers: HomelabState.tsPeers
                        self: HomelabState.tsSelf
                        pings: popup.pings
                        downColor: popup.downColor
                        onPingRequested: ip => popup.ping(ip)
                    }

                    Meta {
                        width: right.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSize - 5
                        text: "── direct    ╌╌ via DERP relay    ◌ offline    ◎ exit node"
                    }

                    Meta {
                        visible: HomelabState.tsSelf !== null
                        width: right.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSize - 5
                        text: HomelabState.tsSelf
                              ? "this host  ·  " + HomelabState.tsSelf.hostName + "  ·  " + HomelabState.tsSelf.ip : ""
                    }

                    Rectangle {
                        visible: popup.showTsStatus
                        width: right.width
                        height: Math.min(tsStatusView.implicitHeight + 12, 220)
                        radius: 4
                        color: Theme.hoverBg
                        clip: true

                        Text {
                            id: tsStatusView
                            x: 6
                            y: 6
                            width: parent.width - 12
                            text: tsStatusProc.running ? "Loading…" : popup.tsStatusText
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 5
                        }
                    }
                }
            }
        }
    }
}
