pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.modules.theme

// Tailnet as a picture, for HomelabPreview's floating layout: this host in
// the centre, peers on a ring around it. A direct path is a solid edge, a
// relayed one a dashed edge bent through a "DERP <region>" tag, offline
// peers are hollow dashed circles, exit nodes get a halo. Clicking an online
// node asks for a ping (pingRequested); while it runs a dot travels the
// edge, and the result lands as a label on it (in the DERP tag when
// relayed). A ping's path ("via") wins
// over the one from `tailscale status`, since it's the fresher answer.
Item {
    id: root

    // HomelabState.tsPeers / tsSelf, and HomelabPreview's ping results:
    // { ip: { state: "pinging" | "ok" | "fail", ms, via } }.
    required property var peers
    required property var self
    required property var pings
    property color downColor: "#ff4d4d"

    signal pingRequested(string ip)

    // Past ~12 nodes the ring is unreadable, so online peers get the
    // places first; on the ring they're by name, so a peer going offline
    // doesn't reshuffle everyone.
    readonly property int maxNodes: 12
    readonly property var shown: root.peers.slice()
        .sort((a, b) => (b.online - a.online) || a.hostName.localeCompare(b.hostName))
        .slice(0, root.maxNodes)
        .sort((a, b) => a.hostName.localeCompare(b.hostName))
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real rx: width / 2 - 56
    readonly property real ry: height / 2 - 46

    function glyph(kind) {
        return String.fromCodePoint(kind === "phone" ? 0xf011c      // md-cellphone
                                    : kind === "tablet" ? 0xf04f6   // md-tablet
                                    : kind === "laptop" ? 0xf0322   // md-laptop
                                    : 0xf048b);                     // md-server
    }

    function viaOf(p) {
        const r = root.pings[p.ip];
        return r && r.via ? r.via : p.via;
    }

    component Glyph: Text {
        font.family: Theme.fontFamily
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Full circle outline (dashable, unlike a Rectangle border).
    component Ring: Shape {
        id: ring
        property real radius: 17
        property color stroke: Theme.accent
        property color fill: "transparent"
        property bool dashed: false
        width: radius * 2 + 2
        height: radius * 2 + 2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ring.stroke
            strokeWidth: 1.5
            fillColor: ring.fill
            strokeStyle: ring.dashed ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: [2, 2]
            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // ---- Edges (under everything) ----

    Repeater {
        model: root.shown
        delegate: Item {
            id: edge
            required property var modelData
            required property int index

            readonly property real angle: -Math.PI / 2 + (index + 0.5) * 2 * Math.PI / root.shown.length
            readonly property real nx: root.cx + Math.cos(angle) * root.rx
            readonly property real ny: root.cy + Math.sin(angle) * root.ry
            readonly property string via: root.viaOf(modelData)
            readonly property bool relayed: via.length > 0 && via !== "direct"
            // Relayed edges bend sideways a little at 55% to make room
            // for the region tag.
            readonly property real len: Math.max(1, Math.hypot(nx - root.cx, ny - root.cy))
            readonly property real bx: root.cx + (nx - root.cx) * 0.55 - (relayed ? (ny - root.cy) / len * 16 : 0)
            readonly property real by: root.cy + (ny - root.cy) * 0.55 + (relayed ? (nx - root.cx) / len * 16 : 0)
            readonly property var ping: root.pings[modelData.ip] ?? null

            // Point at t (0..1) along centre -> bend -> node.
            function at(t) {
                return t < 0.5
                    ? Qt.point(root.cx + (bx - root.cx) * t * 2, root.cy + (by - root.cy) * t * 2)
                    : Qt.point(bx + (nx - bx) * (t - 0.5) * 2, by + (ny - by) * (t - 0.5) * 2);
            }

            anchors.fill: parent
            visible: modelData.online

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: edge.relayed ? 0.65 : 0.85
                ShapePath {
                    strokeColor: edge.ping?.state === "fail" ? root.downColor : Theme.accent
                    strokeWidth: edge.relayed ? 1.2 : 1.5
                    fillColor: "transparent"
                    strokeStyle: edge.relayed ? ShapePath.DashLine : ShapePath.SolidLine
                    dashPattern: [3, 3]
                    startX: root.cx
                    startY: root.cy
                    PathLine { x: edge.bx; y: edge.by }
                    PathLine { x: edge.nx; y: edge.ny }
                }
            }

            Rectangle {
                visible: edge.relayed
                x: edge.bx - width / 2
                y: edge.by - height / 2
                width: derpLabel.implicitWidth + 10
                height: 16
                radius: 3
                color: Theme.color0
                border.width: 1
                border.color: edge.ping?.state === "ok" ? Theme.withAlpha(Theme.accent, 0.6) : Theme.pillBorder
                // A relayed edge carries its ping result in the tag.
                Text {
                    id: derpLabel
                    anchors.centerIn: parent
                    text: "DERP " + edge.via + (edge.ping?.state === "ok" ? "  ·  " + edge.ping.ms : "")
                    color: edge.ping?.state === "ok" ? Theme.text : Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 6
                }
            }

            // The ping result, on the branch.
            Rectangle {
                readonly property point p: edge.at(edge.relayed ? 0.75 : 0.45)
                visible: edge.ping !== null && (edge.ping.state === "fail" || (edge.ping.state === "ok" && !edge.relayed))
                x: p.x - width / 2
                y: p.y - height / 2
                width: pingLabel.implicitWidth + 12
                height: 16
                radius: 8
                color: Theme.color0
                border.width: 1
                border.color: edge.ping?.state === "fail" ? root.downColor : Theme.withAlpha(Theme.accent, 0.6)
                Text {
                    id: pingLabel
                    anchors.centerIn: parent
                    text: edge.ping?.state === "fail" ? "no reply" : (edge.ping?.ms ?? "")
                    color: edge.ping?.state === "fail" ? root.downColor : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 5
                }
            }

            // Travels the edge while the ping is out.
            Rectangle {
                id: pingDot
                property real t: 0
                readonly property point p: edge.at(t)
                visible: edge.ping?.state === "pinging"
                x: p.x - 3.5
                y: p.y - 3.5
                width: 7
                height: 7
                radius: 3.5
                color: Theme.accent
                NumberAnimation on t {
                    running: pingDot.visible
                    from: 0
                    to: 1
                    duration: 700
                    loops: Animation.Infinite
                }
            }
        }
    }

    // ---- This host ----

    Ring {
        x: root.cx - width / 2
        y: root.cy - height / 2
        radius: 36
        stroke: Theme.withAlpha(Theme.accent, 0.45)
        dashed: true
    }
    Ring {
        x: root.cx - width / 2
        y: root.cy - height / 2
        radius: 28
        stroke: Theme.accent
        fill: Qt.tint(Theme.color0, Theme.withAlpha(Theme.accent, 0.12))
    }
    Glyph {
        x: root.cx - width / 2
        y: root.cy - height / 2 - 6
        text: root.glyph("server")
        color: Theme.accent
        font.pixelSize: 20
    }
    Text {
        x: root.cx - width / 2
        y: root.cy + 8
        width: 52
        horizontalAlignment: Text.AlignHCenter
        text: root.self?.hostName ?? "this host"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 6
        font.bold: true
        elide: Text.ElideRight
    }

    // ---- Peers ----

    Repeater {
        model: root.shown
        delegate: Item {
            id: node
            required property var modelData
            required property int index

            readonly property real angle: -Math.PI / 2 + (index + 0.5) * 2 * Math.PI / root.shown.length
            readonly property bool online: modelData.online
            // Labels go on the far side from the centre, so edges never
            // run through them.
            readonly property bool above: Math.sin(angle) < -0.3

            x: root.cx + Math.cos(angle) * root.rx - width / 2
            y: root.cy + Math.sin(angle) * root.ry - (above ? 48 : 18)
            width: 124
            height: 66

            Ring {
                visible: node.modelData.exitNode || node.modelData.exitOption
                anchors.centerIn: nodeCircle
                radius: 22
                stroke: Theme.withAlpha(Theme.accent, node.modelData.exitNode ? 0.8 : 0.35)
            }
            Ring {
                id: nodeCircle
                anchors.horizontalCenter: parent.horizontalCenter
                y: node.above ? 30 : 0
                radius: 17
                stroke: nodeMa.containsMouse && node.online ? Theme.text : node.online ? Theme.accent : Theme.dimText
                fill: node.online ? Theme.color0 : "transparent"
                dashed: !node.online
            }
            Glyph {
                anchors.centerIn: nodeCircle
                text: root.glyph(node.modelData.kind)
                color: node.online ? Theme.accent : Theme.dimText
                font.pixelSize: 15
            }
            Column {
                y: node.above ? 0 : 39
                width: parent.width
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: node.modelData.hostName
                    color: node.online ? Theme.text : Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 5
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: (node.modelData.exitNode ? "exit node · " : "")
                          + (node.online ? node.modelData.ip : "offline")
                    color: Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 6
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: nodeMa
                anchors.fill: nodeCircle
                anchors.margins: -4
                enabled: node.online
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pingRequested(node.modelData.ip)
            }
        }
    }

    Text {
        visible: root.peers.length > root.shown.length
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: "+" + (root.peers.length - root.shown.length) + " more"
        color: Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 5
    }

    Text {
        visible: root.peers.length === 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        text: "No peers"
        color: Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 4
    }
}
