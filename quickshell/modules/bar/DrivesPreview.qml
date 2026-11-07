pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.overlay

// Drive/phone popup, opened from Drives.qml. Every disk's filesystems, the
// removable ones first.
//   Docked: a two-column bento of tiles - a ring for % used (dashed while
//   unmounted / unknown), name, size · fstype and one state chip. Clicking
//   a tile mounts it if needed and opens a terminal there; the per-tile
//   actions (unmount / eject, phone GUI / mirror) float over its corner on
//   hover. Small internal partitions (EFI, /boot) are left to the map.
//   Floating: a storage map - one strip per physical disk, partitions as
//   segments sized by capacity and filled to their used fraction, unmounted
//   ones hatched, eject on the disk header - with the phone drawn as a
//   handset on the right holding its actions.
// All actions go through scripts/hypr-usb (udisksctl for drives,
// aft-mtp-mount / android-file-transfer / scrcpy for phones), run as a
// Process so a failure's stderr can be shown inline instead of silently
// vanishing.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    required property var drives
    required property var phones
    required property string phoneMount

    signal actionFinished

    property string status: ""
    property string lastError: ""
    // Device the running / last failed action was about, for its chip.
    property string busyPath: ""
    property string errorPath: ""
    readonly property bool busy: actionProc.running

    readonly property color errorColor: "#ff4d4d"
    readonly property color trackColor: Theme.withAlpha(Theme.foreground, 0.12)
    readonly property real gib: 1024 * 1024 * 1024

    readonly property var sorted: popup.drives.filter(d => d.removable).concat(popup.drives.filter(d => !d.removable))
    readonly property var tiles: popup.sorted.filter(d => d.removable || d.size >= 2 * popup.gib)
    readonly property var disks: {
        const out = [], byPath = {};
        for (const d of popup.sorted) {
            if (!byPath[d.disk]) {
                byPath[d.disk] = {
                    path: d.disk,
                    model: d.model,
                    size: d.diskSize,
                    kind: d.kind,
                    removable: d.removable,
                    parts: []
                };
                out.push(byPath[d.disk]);
            }
            byPath[d.disk].parts.push(d);
        }
        return out;
    }
    readonly property var phone: popup.phones.length > 0 ? popup.phones[0] : null
    readonly property bool phoneMounted: popup.phoneMount.length > 0

    function run(args, message, path) {
        if (actionProc.running)
            return;
        popup.status = message;
        popup.lastError = "";
        popup.busyPath = path ?? "";
        popup.errorPath = "";
        actionProc.command = ["hypr-usb"].concat(args);
        actionProc.running = true;
    }

    function fmtBytes(b) {
        const units = ["B", "K", "M", "G", "T", "P"];
        let v = Number(b) || 0, i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + units[i];
    }

    // Used fraction, or -1 when unmounted / not reported.
    function usedFrac(d) {
        if (d.mountpoint.length === 0 || !(Number(d.fssize) > 0) || d.fsused === null)
            return -1;
        return Math.min(1, Number(d.fsused) / Number(d.fssize));
    }

    function displayName(d) {
        const mp = d.mountpoint === "/" ? "root" : d.mountpoint.split("/").pop();
        return d.label || mp || (d.removable ? d.model : "") || d.path.replace("/dev/", "");
    }

    function kindGlyph(kind) {
        if (kind === "usb")
            return String.fromCodePoint(0xf129e); // md-usb_flash_drive
        if (kind === "sd")
            return String.fromCodePoint(0xf07dc); // md-micro_sd
        return String.fromCodePoint(0xf02ca); // md-harddisk
    }

    function chipText(d) {
        if (popup.busy && popup.busyPath === d.path)
            return "working…";
        if (popup.errorPath === d.path || popup.errorPath === d.disk)
            return "error";
        if (d.mountpoint.length === 0)
            return "idle";
        return d.removable ? "mounted" : d.mountpoint;
    }

    // Segment widths for one disk strip: proportional to partition size,
    // clamped to a readable minimum, the rest sharing what's left.
    function segWidths(parts, total) {
        const gap = 4, minW = 84, avail = total - gap * (parts.length - 1);
        const widths = parts.map(() => 0), fixed = parts.map(() => false);
        for (let pass = 0; pass < parts.length; pass++) {
            let free = avail, weight = 0;
            parts.forEach((p, i) => {
                if (fixed[i])
                    free -= minW;
                else
                    weight += Math.max(1, Number(p.size));
            });
            let changed = false;
            parts.forEach((p, i) => {
                if (fixed[i])
                    return;
                widths[i] = free * Math.max(1, Number(p.size)) / weight;
                if (widths[i] < minW) {
                    fixed[i] = true;
                    changed = true;
                }
            });
            if (!changed)
                break;
        }
        return widths.map((w, i) => Math.floor(fixed[i] ? minW : w));
    }

    // stderr's end and the exit can arrive in either order - whichever
    // lands second settles the final status line.
    Process {
        id: actionProc
        stderr: StdioCollector {
            id: actionErr
            onStreamFinished: {
                const err = actionErr.text.trim();
                popup.lastError = err.length > 0 ? err.split("\n").pop() : "";
                if (!actionProc.running && popup.lastError.length > 0)
                    popup.status = popup.lastError;
            }
        }
        onExited: code => {
            popup.status = code === 0 ? "" : (popup.lastError || "Failed (exit " + code + ")");
            popup.errorPath = code === 0 ? "" : popup.busyPath;
            popup.busyPath = "";
            popup.actionFinished();
        }
    }

    // Fill levels have no event of their own - re-list on open.
    Component.onCompleted: popup.actionFinished()

    // Small clickable glyph used for the per-tile actions.
    component IconButton: Text {
        id: iconButton
        signal triggered
        property bool danger: false

        color: iconMa.containsMouse ? (iconButton.danger ? popup.errorColor : Theme.accent) : Theme.dimText
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

    // Outlined glyph + label button (floating layout).
    component TextButton: Rectangle {
        id: textButton
        signal triggered
        property string icon: ""
        property string label: ""
        property bool danger: false

        implicitWidth: buttonRow.implicitWidth + 16
        implicitHeight: 24
        radius: 6
        color: buttonMa.containsMouse ? Theme.hoverBg : "transparent"
        border.width: 1
        border.color: buttonMa.containsMouse && textButton.danger ? popup.errorColor : Theme.pillBorder

        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: textButton.icon
                color: buttonMa.containsMouse ? (textButton.danger ? popup.errorColor : Theme.accent) : Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }
            Text {
                text: textButton.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 4
            }
        }

        MouseArea {
            id: buttonMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: textButton.triggered()
        }
    }

    // % used ring: a full track (dashed when there's no figure) and the
    // used arc over it from 12 o'clock.
    component Ring: Item {
        id: ring
        property real frac: -1
        property color color: Theme.accent
        property bool dashed: ring.frac < 0
        property real thickness: 4
        default property alias inner: ringInner.data

        implicitWidth: 44
        implicitHeight: 44

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: popup.trackColor
                strokeWidth: ring.thickness
                fillColor: "transparent"
                strokeStyle: ring.dashed ? ShapePath.DashLine : ShapePath.SolidLine
                dashPattern: [1.2, 1.4]
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: (ring.width - ring.thickness) / 2
                    radiusY: radiusX
                    startAngle: 0
                    sweepAngle: 360
                }
            }
            ShapePath {
                strokeColor: ring.frac > 0 ? ring.color : "transparent"
                strokeWidth: ring.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: (ring.width - ring.thickness) / 2
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0, ring.frac)
                }
            }
        }

        Item {
            id: ringInner
            anchors.fill: parent
        }
    }

    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool on: false
        property bool error: false

        implicitWidth: chipText.implicitWidth + 10
        implicitHeight: 16
        radius: 4
        color: chip.error ? Theme.withAlpha(popup.errorColor, 0.2) : chip.on ? Theme.withAlpha(Theme.accent, 0.2) : Theme.withAlpha(Theme.foreground, 0.08)

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.text
            color: chip.error ? popup.errorColor : chip.on ? Theme.text : Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 5
        }
    }

    // One bento tile: ring on the left, three text lines, hover actions.
    component Tile: Rectangle {
        id: tile
        signal clicked
        property real frac: -1
        property color ringColor: Theme.accent
        // Ring centre: the % (StyledText) or a glyph.
        property string ringText: ""
        property color ringTextColor: Theme.dimText
        property bool ringTextLarge: false
        property string title: ""
        property string meta: ""
        property string chipLabel: ""
        property bool chipOn: false
        property bool chipError: false
        default property alias actions: tileActions.data
        readonly property bool hovered: tileHover.hovered

        height: 66
        radius: 8
        color: tileMa.containsMouse ? Theme.hoverBg : Theme.withAlpha(Theme.foreground, 0.03)
        border.width: 1
        border.color: tile.chipError ? Theme.withAlpha(popup.errorColor, 0.5) : Theme.withAlpha(Theme.foreground, 0.1)

        HoverHandler {
            id: tileHover
        }

        MouseArea {
            id: tileMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }

        Ring {
            id: tileRing
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            frac: tile.frac
            color: tile.ringColor

            Text {
                anchors.centerIn: parent
                textFormat: Text.StyledText
                text: tile.ringText
                color: tile.ringTextColor
                font.family: Theme.fontFamily
                font.pixelSize: tile.ringTextLarge ? Theme.fontSize + 1 : Theme.fontSize - 3
                font.bold: !tile.ringTextLarge
            }
        }

        Column {
            anchors.left: tileRing.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: tile.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: tile.meta
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 5
                elide: Text.ElideRight
            }
            Item {
                width: 1
                height: 2
            }
            Chip {
                width: Math.min(implicitWidth, parent.width)
                text: tile.chipLabel
                on: tile.chipOn
                error: tile.chipError
            }
        }

        Rectangle {
            visible: tile.hovered && tileActions.children.length > 0
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5
            width: tileActions.implicitWidth + 12
            height: 22
            radius: 6
            // Opaque - it sits over the tile's title.
            color: Theme.color0
            border.width: 1
            border.color: Theme.withAlpha(Theme.foreground, 0.1)

            Row {
                id: tileActions
                anchors.centerIn: parent
                height: parent.height
                spacing: 10
            }
        }
    }

    Item {
        id: card
        width: popup.floating ? 780 : 340
        height: (popup.floating ? floatLayout.implicitHeight : dockLayout.implicitHeight) + 32

        // ── Docked: ring bento ───────────────────────────────────────────
        Column {
            id: dockLayout
            visible: !popup.floating
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 16
            width: parent.width - 32
            spacing: 8

            Item {
                width: parent.width
                height: dockTitle.height
                Text {
                    id: dockTitle
                    text: "Devices"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
            }

            Grid {
                id: tileGrid
                columns: 2
                spacing: 8
                readonly property real tileWidth: (dockLayout.width - spacing) / 2

                Repeater {
                    model: popup.tiles
                    delegate: Tile {
                        id: driveTile
                        required property var modelData
                        readonly property bool mounted: modelData.mountpoint.length > 0

                        width: tileGrid.tileWidth
                        title: popup.displayName(modelData)
                        meta: popup.fmtBytes(modelData.size) + " · " + modelData.fstype
                        frac: popup.usedFrac(modelData)
                        ringColor: driveTile.frac >= 0.95 ? popup.errorColor : Theme.accent
                        ringText: driveTile.frac >= 0
                                  ? Math.round(driveTile.frac * 100) + "<font size=\"1\">%</font>"
                                  : popup.kindGlyph(modelData.kind)
                        ringTextColor: driveTile.frac >= 0 ? Theme.text : Theme.dimText
                        ringTextLarge: driveTile.frac < 0
                        chipLabel: popup.chipText(modelData)
                        chipOn: driveTile.mounted
                        chipError: driveTile.chipLabel === "error"
                        onClicked: popup.run(["open", modelData.path], "Opening " + modelData.path + "…", modelData.path)

                        IconButton {
                            text: String.fromCodePoint(0xf018d) // md-console
                            onTriggered: popup.run(["open", driveTile.modelData.path], "Opening " + driveTile.modelData.path + "…", driveTile.modelData.path)
                        }
                        IconButton {
                            visible: driveTile.mounted && driveTile.modelData.removable
                            text: String.fromCodePoint(0xf0338) // md-link_off
                            onTriggered: popup.run(["unmount", driveTile.modelData.path], "Unmounting…", driveTile.modelData.path)
                        }
                        IconButton {
                            visible: driveTile.modelData.removable
                            danger: true
                            text: String.fromCodePoint(0xf01ea) // md-eject
                            onTriggered: popup.run(["eject", driveTile.modelData.disk], "Ejecting " + driveTile.modelData.disk + "…", driveTile.modelData.disk)
                        }
                    }
                }

                Repeater {
                    model: popup.phones
                    delegate: Tile {
                        id: phoneTile
                        required property var modelData

                        width: tileGrid.tileWidth
                        title: modelData.name || "Phone"
                        meta: "MTP"
                        ringText: String.fromCodePoint(0xf011c) // md-cellphone
                        ringTextColor: Theme.accent
                        ringTextLarge: true
                        chipLabel: popup.busy && popup.busyPath === "phone" ? "working…" : popup.phoneMounted ? "mounted" : "connected"
                        chipOn: popup.phoneMounted
                        chipError: popup.errorPath === "phone"
                        onClicked: popup.run(["open-phone"], "Mounting phone…", "phone")

                        IconButton {
                            text: String.fromCodePoint(0xf0770) // md-folder_open
                            onTriggered: popup.run(["gui-phone"], "Opening Android File Transfer…", "phone")
                        }
                        IconButton {
                            text: String.fromCodePoint(0xf0989) // md-monitor_cellphone
                            onTriggered: popup.run(["scrcpy"], "Starting scrcpy…", "phone")
                        }
                        IconButton {
                            visible: popup.phoneMounted
                            text: String.fromCodePoint(0xf0338) // md-link_off
                            onTriggered: popup.run(["unmount-phone"], "Unmounting phone…", "phone")
                        }
                    }
                }
            }

            Text {
                visible: popup.drives.length === 0 && popup.phones.length === 0
                width: parent.width
                text: "No drives found"
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Text {
                visible: popup.status.length > 0
                width: parent.width
                text: popup.status
                color: popup.busy ? Theme.dimText : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.Wrap
            }
        }

        // ── Floating: storage map + handset ──────────────────────────────
        Row {
            id: floatLayout
            visible: popup.floating
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 16
            spacing: 20

            Column {
                id: mapColumn
                width: card.width - 32 - floatLayout.spacing - handset.width
                spacing: 14

                Row {
                    spacing: 10
                    Text {
                        id: mapTitle
                        text: "Storage"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    Text {
                        anchors.baseline: mapTitle.baseline
                        text: {
                            const removable = popup.disks.filter(d => d.removable).length;
                            return popup.disks.length + (popup.disks.length === 1 ? " disk" : " disks")
                                   + " · " + removable + " removable";
                        }
                        color: Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 4
                    }
                }

                Repeater {
                    model: popup.disks
                    delegate: Column {
                        id: diskBlock
                        required property var modelData
                        readonly property var widths: popup.segWidths(modelData.parts, mapColumn.width)

                        width: mapColumn.width
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 24

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: popup.kindGlyph(diskBlock.modelData.kind)
                                    color: Theme.dimText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                                Text {
                                    id: diskModel
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: diskBlock.modelData.model || diskBlock.modelData.path.replace("/dev/", "")
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: true
                                }
                                Text {
                                    anchors.baseline: diskModel.baseline
                                    text: diskBlock.modelData.path + " · " + popup.fmtBytes(diskBlock.modelData.size)
                                          + (diskBlock.modelData.removable ? "" : " · internal")
                                    color: Theme.dimText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 4
                                }
                            }

                            TextButton {
                                visible: diskBlock.modelData.removable
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                danger: true
                                icon: String.fromCodePoint(0xf01ea) // md-eject
                                label: "Eject"
                                onTriggered: popup.run(["eject", diskBlock.modelData.path], "Ejecting " + diskBlock.modelData.path + "…", diskBlock.modelData.path)
                            }
                        }

                        Row {
                            spacing: 4

                            Repeater {
                                model: diskBlock.modelData.parts
                                delegate: Rectangle {
                                    id: seg
                                    required property var modelData
                                    required property int index
                                    readonly property bool mounted: modelData.mountpoint.length > 0
                                    readonly property real frac: popup.usedFrac(modelData)
                                    readonly property string chip: popup.chipText(modelData)

                                    width: diskBlock.widths[index] ?? 84
                                    height: 56
                                    radius: 6
                                    clip: true
                                    color: seg.mounted ? Theme.withAlpha(Theme.accent, 0.08) : "transparent"
                                    border.width: 1
                                    border.color: seg.chip === "error" ? Theme.withAlpha(popup.errorColor, 0.7)
                                                  : seg.mounted ? Theme.withAlpha(Theme.accent, 0.45)
                                                  : Theme.withAlpha(Theme.foreground, 0.15)

                                    // Unmounted: hatched, like free space in GParted.
                                    Canvas {
                                        visible: !seg.mounted
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        onWidthChanged: requestPaint()
                                        onPaint: {
                                            const ctx = getContext("2d");
                                            ctx.reset();
                                            ctx.strokeStyle = popup.trackColor;
                                            ctx.lineWidth = 3.5;
                                            for (let x = -height; x < width; x += 10) {
                                                ctx.beginPath();
                                                ctx.moveTo(x, height);
                                                ctx.lineTo(x + height, 0);
                                                ctx.stroke();
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: seg.frac > 0
                                        x: 1
                                        y: 1
                                        width: (seg.width - 2) * Math.max(0, seg.frac)
                                        height: seg.height - 2
                                        radius: 5
                                        color: seg.frac >= 0.95 ? Theme.withAlpha(popup.errorColor, 0.3) : Theme.withAlpha(Theme.accent, 0.22)
                                    }

                                    HoverHandler {
                                        id: segHover
                                    }
                                    MouseArea {
                                        id: segMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: popup.run(["open", seg.modelData.path], "Opening " + seg.modelData.path + "…", seg.modelData.path)
                                    }

                                    Column {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 8
                                        anchors.topMargin: 7
                                        spacing: 2

                                        Text {
                                            width: parent.width
                                            textFormat: Text.StyledText
                                            text: popup.displayName(seg.modelData)
                                                  + "  <font color=\"" + Theme.dimText + "\">" + seg.modelData.fstype + "</font>"
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 3
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            text: seg.chip === "working…" ? "working…"
                                                  : seg.frac >= 0 ? popup.fmtBytes(seg.modelData.fsused) + " / " + popup.fmtBytes(seg.modelData.fssize)
                                                  : seg.mounted ? popup.fmtBytes(seg.modelData.size)
                                                  : popup.fmtBytes(seg.modelData.size) + " · not mounted"
                                            color: Theme.dimText
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 5
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: seg.mounted && segHover.hovered === false
                                            width: parent.width
                                            text: seg.modelData.mountpoint
                                            color: Theme.dimText
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 5
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    Row {
                                        visible: segHover.hovered
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 6
                                        height: 16
                                        spacing: 10

                                        IconButton {
                                            text: String.fromCodePoint(0xf018d) // md-console
                                            onTriggered: popup.run(["open", seg.modelData.path], "Opening " + seg.modelData.path + "…", seg.modelData.path)
                                        }
                                        IconButton {
                                            visible: seg.mounted && seg.modelData.removable
                                            text: String.fromCodePoint(0xf0338) // md-link_off
                                            onTriggered: popup.run(["unmount", seg.modelData.path], "Unmounting…", seg.modelData.path)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: popup.status.length > 0
                    width: parent.width
                    text: popup.status
                    color: popup.busy ? Theme.dimText : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    wrapMode: Text.Wrap
                }
            }

            // The phone as a handset: outline (dashed while absent), notch,
            // home bar, and its actions on the "screen".
            Item {
                id: handset
                width: 150
                height: Math.max(300, mapColumn.height)

                Shape {
                    id: body
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: 150
                    height: 300
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: popup.phone ? (popup.phoneMounted ? Theme.accent : Theme.withAlpha(Theme.accent, 0.6)) : Theme.dimText
                        strokeWidth: 1.5
                        strokeStyle: popup.phone ? ShapePath.SolidLine : ShapePath.DashLine
                        dashPattern: [3, 3]
                        fillColor: popup.phone ? Theme.withAlpha(Theme.accent, 0.05) : "transparent"
                        PathRectangle {
                            x: 1
                            y: 1
                            width: body.width - 2
                            height: body.height - 2
                            radius: 22
                        }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: body.horizontalCenter
                    y: body.y + 11
                    width: 34
                    height: 6
                    radius: 3
                    color: popup.phone ? Theme.withAlpha(Theme.accent, 0.45) : Theme.withAlpha(Theme.foreground, 0.12)
                }
                Rectangle {
                    anchors.horizontalCenter: body.horizontalCenter
                    y: body.y + body.height - 14
                    width: 44
                    height: 4
                    radius: 2
                    color: popup.phone ? Theme.withAlpha(Theme.accent, 0.45) : Theme.withAlpha(Theme.foreground, 0.12)
                }

                Column {
                    anchors.horizontalCenter: body.horizontalCenter
                    y: body.y + 32
                    width: body.width - 24
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String.fromCodePoint(0xf0032) // md-android
                        color: popup.phone ? Theme.accent : Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 8
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: popup.phone ? (popup.phone.name || "Phone") : "No phone"
                        color: popup.phone ? Theme.text : Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Chip {
                        visible: popup.phone !== null
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: popup.busy && popup.busyPath === "phone" ? "working…" : popup.phoneMounted ? "MTP · mounted" : "MTP · not mounted"
                        on: popup.phoneMounted
                        error: popup.errorPath === "phone"
                    }
                    Text {
                        visible: popup.phone === null
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "plug in and pick\nFile transfer"
                        color: Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 5
                    }
                    Item {
                        width: 1
                        height: 6
                    }

                    Repeater {
                        model: popup.phone === null ? [] : [
                            { icon: 0xf018d, label: popup.phoneMounted ? "Open" : "Mount & open", args: ["open-phone"], msg: "Mounting phone…" },
                            { icon: 0xf0770, label: "File transfer", args: ["gui-phone"], msg: "Opening Android File Transfer…" },
                            { icon: 0xf0989, label: "Mirror (scrcpy)", args: ["scrcpy"], msg: "Starting scrcpy…" }
                        ].concat(popup.phoneMounted ? [{ icon: 0xf0338, label: "Unmount", args: ["unmount-phone"], msg: "Unmounting phone…" }] : [])
                        delegate: TextButton {
                            required property var modelData
                            width: parent.width
                            icon: String.fromCodePoint(modelData.icon)
                            label: modelData.label
                            onTriggered: popup.run(modelData.args, modelData.msg, "phone")
                        }
                    }
                }
            }
        }
    }
}
