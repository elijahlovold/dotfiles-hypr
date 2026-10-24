pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.modules.theme
import qs.modules.overlay

// Resource monitor opened from SysMon.qml (the GPU | CPU | Mem pill):
// CPU, GPU, memory/swap, network and per-disk graphs. Everything is read
// straight from /proc and /sys with FileViews, and every reader, timer and
// history buffer lives in this popup - nothing samples while it's closed,
// and the graphs start empty on each open. The one subprocess is lsblk
// (disk models + filesystem usage need statvfs), run on open and every 30s.
//
// The FileViews use blockAllReads, so text() right after reload() returns
// this tick's content (they're tiny kernel-generated files) instead of the
// previous tick's - see the note in AmdGpu.qml.
//
// Every section has a fixed height and the popup stays hidden until the
// first lsblk result has fixed the disk list, so the card drops open at its
// final size instead of jumping taller (see SoundPreview).
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height
    visible: popup.disksLoaded

    readonly property int historyLength: 60 // samples = seconds
    readonly property int sampleInterval: 1000

    function pushed(history, value) {
        return history.concat([value]).slice(-popup.historyLength);
    }

    function fmtBytes(b) {
        const units = ["B", "K", "M", "G", "T"];
        let i = 0;
        while (b >= 1024 && i < units.length - 1) {
            b /= 1024;
            i++;
        }
        return (i === 0 || b >= 100 ? Math.round(b).toString() : b.toFixed(1)) + units[i];
    }

    function fmtBits(bytesPerSec) {
        let v = bytesPerSec * 8 / 1000;
        if (v < 1000)
            return (v < 10 ? v.toFixed(1) : Math.round(v)) + " Kbps";
        v /= 1000;
        if (v < 1000)
            return (v < 10 ? v.toFixed(1) : Math.round(v)) + " Mbps";
        return (v / 1000).toFixed(2) + " Gbps";
    }

    // ---- Discovery (once per open, synchronous) ----

    property string cpuModel: ""
    property string cpuTempPath: ""
    property string gpuPath: "" // the amdgpu PCI device dir
    property string gpuHwmonPath: ""

    FileView {
        id: probe
        blockAllReads: true
        printErrors: false
    }

    function readProbe(path) {
        probe.path = path;
        return probe.text().trim();
    }

    function discover() {
        let bestVram = -1;
        for (let i = 0; i < 16; i++) {
            const dir = "/sys/class/hwmon/hwmon" + i;
            const name = popup.readProbe(dir + "/name");
            if (!popup.cpuTempPath && ["k10temp", "zenpower", "coretemp", "cpu_thermal"].includes(name))
                popup.cpuTempPath = dir + "/temp1_input";
            // hwmonN/device is the GPU's PCI device dir, where amdgpu
            // keeps gpu_busy_percent etc. Largest VRAM wins over an iGPU.
            if (name === "amdgpu") {
                const vram = Number(popup.readProbe(dir + "/device/mem_info_vram_total")) || 0;
                if (vram > bestVram) {
                    bestVram = vram;
                    popup.gpuPath = dir + "/device";
                    popup.gpuHwmonPath = dir;
                }
            }
        }
        popup.coreCount = (popup.readProbe("/proc/stat").match(/^cpu\d+\s/gm) ?? []).length;
        const model = popup.readProbe("/proc/cpuinfo").match(/^model name\s*:\s*(.+)$/m)?.[1] ?? "";
        popup.cpuModel = model.replace(/\((R|TM)\)/g, "").replace(/\s+(\d+-Core\s+)?Processor.*$/, "").replace(/\s+/g, " ").trim();
    }

    // ---- Samplers ----

    FileView {
        id: statFile
        path: "/proc/stat"
        blockAllReads: true
    }
    FileView {
        id: cpuinfoFile
        path: "/proc/cpuinfo"
        blockAllReads: true
    }
    FileView {
        id: cpuTempFile
        path: popup.cpuTempPath
        blockAllReads: true
        printErrors: false
    }
    FileView {
        id: meminfoFile
        path: "/proc/meminfo"
        blockAllReads: true
    }
    FileView {
        id: gpuBusyFile
        path: popup.gpuPath ? popup.gpuPath + "/gpu_busy_percent" : ""
        blockAllReads: true
        printErrors: false
    }
    FileView {
        id: gpuVramUsedFile
        path: popup.gpuPath ? popup.gpuPath + "/mem_info_vram_used" : ""
        blockAllReads: true
        printErrors: false
    }
    FileView {
        id: gpuVramTotalFile
        path: popup.gpuPath ? popup.gpuPath + "/mem_info_vram_total" : ""
        blockAllReads: true
        printErrors: false
    }
    FileView {
        id: gpuTempFile
        path: popup.gpuHwmonPath ? popup.gpuHwmonPath + "/temp1_input" : ""
        blockAllReads: true
        printErrors: false
    }
    FileView {
        id: gpuPowerFile
        path: popup.gpuHwmonPath ? popup.gpuHwmonPath + "/power1_average" : ""
        blockAllReads: true
        printErrors: false
    }
    FileView {
        id: routeFile
        path: "/proc/net/route"
        blockAllReads: true
    }
    FileView {
        id: netDevFile
        path: "/proc/net/dev"
        blockAllReads: true
    }
    FileView {
        id: diskstatsFile
        path: "/proc/diskstats"
        blockAllReads: true
    }

    // CPU
    property real cpuUsage: 0
    property var coreUsages: []
    property var coreHistory: [] // per core, newest last
    // Fixed at open (from /proc/stat in discover()) - the legend's row
    // count sets the popup height, which can't change after mapping.
    property int coreCount: 0
    property var prevCpu: null
    property var prevCores: []
    property real cpuAvgMhz: 0
    property real cpuMaxMhz: 0
    property real cpuTemp: -1

    function sampleCpu() {
        const cores = [];
        let agg = null;
        for (const line of statFile.text().split("\n")) {
            const m = line.match(/^cpu(\d*)\s+(.+)$/);
            if (!m)
                continue;
            const f = m[2].trim().split(/\s+/).map(Number);
            // user nice system idle iowait irq softirq steal
            const total = f.slice(0, 8).reduce((a, b) => a + b, 0);
            const s = {
                total,
                idle: f[3] + f[4]
            };
            if (m[1] === "")
                agg = s;
            else
                cores.push(s);
        }
        const busy = (cur, prev) => {
            const dt = cur.total - prev.total;
            return dt > 0 ? Math.max(0, Math.min(1, 1 - (cur.idle - prev.idle) / dt)) : 0;
        };
        if (agg && popup.prevCpu)
            popup.cpuUsage = busy(agg, popup.prevCpu);
        if (popup.prevCores.length === cores.length) {
            popup.coreUsages = cores.map((c, i) => busy(c, popup.prevCores[i]));
            popup.coreHistory = popup.coreUsages.map((u, i) => popup.pushed(popup.coreHistory[i] ?? [], u));
        }
        popup.prevCpu = agg;
        popup.prevCores = cores;
    }

    function sampleCpuFreq() {
        // No String.matchAll in Qt's JS engine.
        const mhz = (cpuinfoFile.text().match(/^cpu MHz\s*:\s*[\d.]+/gm) ?? []).map(l => Number(l.split(":")[1]));
        if (mhz.length === 0)
            return;
        popup.cpuAvgMhz = mhz.reduce((a, b) => a + b, 0) / mhz.length;
        popup.cpuMaxMhz = Math.max(...mhz);
    }

    // Memory
    property real memTotal: 0
    property real memUsed: 0
    property real memCached: 0
    property real swapTotal: 0
    property real swapUsed: 0
    property var memHistory: []

    function sampleMem() {
        const text = meminfoFile.text();
        const kb = key => Number(text.match(new RegExp("^" + key + ":\\s+(\\d+)", "m"))?.[1] ?? 0) * 1024;
        popup.memTotal = kb("MemTotal");
        popup.memUsed = popup.memTotal - kb("MemAvailable");
        popup.memCached = kb("Cached") + kb("Buffers");
        popup.swapTotal = kb("SwapTotal");
        popup.swapUsed = popup.swapTotal - kb("SwapFree");
        popup.memHistory = popup.pushed(popup.memHistory, popup.memTotal > 0 ? popup.memUsed / popup.memTotal : 0);
    }

    // GPU
    readonly property bool hasGpu: popup.gpuPath.length > 0
    property real gpuBusy: 0
    property real gpuVramUsed: 0
    property real gpuVramTotal: 0
    property real gpuTemp: -1
    property real gpuPower: -1
    property var gpuHistory: []

    function sampleGpu() {
        popup.gpuBusy = (Number(gpuBusyFile.text().trim()) || 0) / 100;
        popup.gpuVramUsed = Number(gpuVramUsedFile.text().trim()) || 0;
        popup.gpuVramTotal = Number(gpuVramTotalFile.text().trim()) || 0;
        const t = gpuTempFile.text().trim();
        popup.gpuTemp = t ? Number(t) / 1000 : -1;
        const p = gpuPowerFile.text().trim();
        popup.gpuPower = p ? Number(p) / 1e6 : -1;
        popup.gpuHistory = popup.pushed(popup.gpuHistory, popup.gpuBusy);
    }

    // Network - the default-route interface, else the busiest non-lo one.
    property string netIface: ""
    property real netDown: 0
    property real netUp: 0
    property var netDownHistory: []
    property var netUpHistory: []
    property var prevNet: null

    function defaultIface() {
        let best = "", bestMetric = Infinity;
        for (const line of routeFile.text().split("\n").slice(1)) {
            const f = line.trim().split(/\s+/);
            // Iface Destination Gateway Flags RefCnt Use Metric ...
            if (f.length > 6 && f[1] === "00000000" && Number(f[6]) < bestMetric) {
                best = f[0];
                bestMetric = Number(f[6]);
            }
        }
        return best;
    }

    function sampleNet() {
        const now = Date.now();
        const counters = {};
        for (const line of netDevFile.text().split("\n").slice(2)) {
            const i = line.indexOf(":");
            if (i < 0)
                continue;
            const f = line.slice(i + 1).trim().split(/\s+/).map(Number);
            counters[line.slice(0, i).trim()] = {
                rx: f[0],
                tx: f[8]
            };
        }
        let iface = popup.defaultIface();
        if (!counters[iface]) {
            iface = Object.keys(counters).filter(n => n !== "lo").sort((a, b) => counters[b].rx - counters[a].rx)[0] ?? "";
        }
        const cur = counters[iface];
        const prev = popup.prevNet;
        if (cur && prev && prev.iface === iface && now > prev.time) {
            const secs = (now - prev.time) / 1000;
            popup.netDown = Math.max(0, cur.rx - prev.rx) / secs;
            popup.netUp = Math.max(0, cur.tx - prev.tx) / secs;
            popup.netDownHistory = popup.pushed(popup.netDownHistory, popup.netDown);
            popup.netUpHistory = popup.pushed(popup.netUpHistory, popup.netUp);
        }
        popup.netIface = iface;
        popup.prevNet = cur ? {
            iface,
            time: now,
            rx: cur.rx,
            tx: cur.tx
        } : null;
    }

    // Disks - the set comes from the first lsblk run and stays fixed while
    // open (fixed popup height); later runs only refresh usage. Empty
    // card-reader slots report size 0 and are skipped.
    property bool disksLoaded: false
    property var disks: [] // [{ name, model, size, used, fsSize, mounted }]
    property var diskRates: ({}) // name -> { read, write } bytes/s
    property var prevDiskstats: null

    function parseLsblk(json) {
        let devices = [];
        try {
            devices = JSON.parse(json).blockdevices ?? [];
        } catch (e) {
            return [];
        }
        // Filesystem usage summed over every mounted descendant
        // (partitions, LUKS, LVM...), once per filesystem.
        const usage = (node, acc) => {
            if (node.mountpoint && node.fssize && !acc.seen.has(node.name)) {
                acc.seen.add(node.name);
                acc.used += Number(node.fsused) || 0;
                acc.size += Number(node.fssize) || 0;
            }
            for (const c of node.children ?? [])
                usage(c, acc);
            return acc;
        };
        return devices.filter(d => d.type === "disk" && Number(d.size) > 0 && !/^(zram|loop|ram)/.test(d.name)).map(d => {
            const u = usage(d, {
                used: 0,
                size: 0,
                seen: new Set()
            });
            return {
                name: d.name,
                model: (d.model ?? "").trim(),
                size: Number(d.size) || 0,
                used: u.used,
                fsSize: u.size,
                mounted: u.size > 0
            };
        });
    }

    Process {
        id: lsblkProc
        command: ["lsblk", "-J", "-b", "-o", "NAME,TYPE,MODEL,SIZE,FSUSED,FSSIZE,MOUNTPOINT"]
        running: true
        stdout: StdioCollector {
            id: lsblkOut
            onStreamFinished: {
                const fresh = popup.parseLsblk(lsblkOut.text);
                if (!popup.disksLoaded) {
                    popup.disks = fresh;
                } else {
                    popup.disks = popup.disks.map(d => fresh.find(f => f.name === d.name) ?? d);
                }
                popup.disksLoaded = true;
            }
        }
        // A failed run still has to release the popup (a successful one
        // does so from onStreamFinished, which may land after the exit).
        onExited: code => {
            if (code !== 0)
                popup.disksLoaded = true;
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: lsblkProc.running = true
    }

    function sampleDisks() {
        const now = Date.now();
        const stats = {};
        for (const line of diskstatsFile.text().split("\n")) {
            const f = line.trim().split(/\s+/);
            // major minor name rd_ios rd_merges rd_sectors rd_ticks wr_ios wr_merges wr_sectors
            if (f.length > 9)
                stats[f[2]] = {
                    read: Number(f[5]) * 512,
                    write: Number(f[9]) * 512
                };
        }
        const prev = popup.prevDiskstats;
        if (prev && now > prev.time) {
            const secs = (now - prev.time) / 1000;
            const rates = {};
            for (const d of popup.disks) {
                const c = stats[d.name], p = prev.stats[d.name];
                if (c && p)
                    rates[d.name] = {
                        read: Math.max(0, c.read - p.read) / secs,
                        write: Math.max(0, c.write - p.write) / secs
                    };
            }
            popup.diskRates = rates;
        }
        popup.prevDiskstats = {
            time: now,
            stats
        };
    }

    property int tick: 0

    Timer {
        interval: popup.sampleInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            meminfoFile.reload();
            routeFile.reload();
            netDevFile.reload();
            diskstatsFile.reload();
            popup.sampleCpu();
            popup.sampleMem();
            popup.sampleNet();
            popup.sampleDisks();
            if (popup.hasGpu) {
                gpuBusyFile.reload();
                gpuVramUsedFile.reload();
                gpuVramTotalFile.reload();
                gpuTempFile.reload();
                gpuPowerFile.reload();
                popup.sampleGpu();
            }
            // Slower-moving / pricier reads every other tick (/proc/cpuinfo
            // makes the kernel sample every core's clock).
            if (popup.tick % 2 === 0) {
                cpuinfoFile.reload();
                popup.sampleCpuFreq();
                if (popup.cpuTempPath) {
                    cpuTempFile.reload();
                    const t = cpuTempFile.text().trim();
                    popup.cpuTemp = t ? Number(t) / 1000 : -1;
                }
            }
            popup.tick++;
        }
    }

    Component.onCompleted: popup.discover()

    // ---- Presentation ----

    // Scrolling area graph, newest sample at the right edge. `values` are
    // 0..1, or raw with `peak` > 0; `mirrorValues` (optional) are drawn
    // downward from the midline in `mirrorColor` (download up, upload down).
    component Graph: Item {
        id: graph

        property var values: []
        property var mirrorValues: null
        property real peak: 1
        property color color: Theme.accent
        property color mirrorColor: Theme.color7
        required property int capacity

        height: 44

        onValuesChanged: canvas.requestPaint()
        onMirrorValuesChanged: canvas.requestPaint()
        onPeakChanged: canvas.requestPaint()

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Theme.hoverBg
        }
        Rectangle {
            visible: graph.mirrorValues !== null
            y: Math.round(graph.height / 2)
            width: graph.width
            height: 1
            color: Theme.withAlpha(Theme.dimText, 0.35)
        }

        Canvas {
            id: canvas
            anchors.fill: parent
            anchors.margins: 1

            function trace(ctx, vals, base, span, dir, color) {
                if (vals.length < 2)
                    return;
                const step = width / (graph.capacity - 1);
                const xAt = i => width - (vals.length - 1 - i) * step;
                const yAt = i => base + dir * Math.min(1, Math.max(0, vals[i] / graph.peak)) * span;
                ctx.beginPath();
                ctx.moveTo(xAt(0), base);
                for (let i = 0; i < vals.length; i++)
                    ctx.lineTo(xAt(i), yAt(i));
                ctx.lineTo(width, base);
                ctx.closePath();
                ctx.fillStyle = Theme.withAlpha(color, 0.3);
                ctx.fill();
                ctx.beginPath();
                ctx.moveTo(xAt(0), yAt(0));
                for (let i = 1; i < vals.length; i++)
                    ctx.lineTo(xAt(i), yAt(i));
                ctx.strokeStyle = color;
                ctx.lineWidth = 1;
                ctx.stroke();
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                if (graph.mirrorValues !== null) {
                    const mid = height / 2;
                    trace(ctx, graph.values, mid, mid, -1, graph.color);
                    trace(ctx, graph.mirrorValues, mid, mid, 1, graph.mirrorColor);
                } else {
                    trace(ctx, graph.values, height, height, -1, graph.color);
                }
            }
        }
    }

    // One line per core on a single canvas, like GNOME System Monitor's
    // CPU graph. Hues are spread evenly around the wheel starting at the
    // theme accent, so core 1 is always the accent colour.
    function coreColor(i) {
        // hslHue is -1 for a grey accent.
        const h = (Math.max(0, Theme.accent.hslHue) + i / Math.max(1, popup.coreCount)) % 1;
        return Qt.hsla(h, 0.65, 0.62, 1);
    }

    component CoreGraph: Item {
        id: coreGraph

        property var series: [] // per core, 0..1 values, newest last
        required property int capacity

        height: 72

        onSeriesChanged: coreCanvas.requestPaint()

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Theme.hoverBg
        }
        // 50% guide.
        Rectangle {
            y: Math.round(coreGraph.height / 2)
            width: coreGraph.width
            height: 1
            color: Theme.withAlpha(Theme.dimText, 0.2)
        }

        Canvas {
            id: coreCanvas
            anchors.fill: parent
            anchors.margins: 1
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const step = width / (coreGraph.capacity - 1);
                ctx.lineWidth = 1.5;
                ctx.lineJoin = "round";
                for (let c = 0; c < coreGraph.series.length; c++) {
                    const vals = coreGraph.series[c];
                    if (vals.length < 2)
                        continue;
                    ctx.beginPath();
                    for (let i = 0; i < vals.length; i++) {
                        const x = width - (vals.length - 1 - i) * step;
                        const y = height - Math.min(1, Math.max(0, vals[i])) * (height - 1);
                        if (i === 0)
                            ctx.moveTo(x, y);
                        else
                            ctx.lineTo(x, y);
                    }
                    ctx.strokeStyle = popup.coreColor(c);
                    ctx.stroke();
                }
            }
        }
    }

    // Thin usage track, same look as SoundPreview's level meters.
    component UsageBar: Item {
        id: usageBar
        property real fraction: 0
        property color color: Theme.accent
        height: 4

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.withAlpha(Theme.dimText, 0.35)
        }
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, usageBar.fraction))
            height: parent.height
            radius: height / 2
            color: usageBar.color
        }
    }

    // Title (bold), dim detail, value on the right.
    component Header: Item {
        id: header
        property string title
        property string detail
        property string value

        width: parent?.width ?? 0
        height: headerTitle.implicitHeight

        Text {
            id: headerTitle
            text: header.title
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
        Text {
            anchors.left: headerTitle.right
            anchors.leftMargin: 8
            anchors.right: headerValue.left
            anchors.rightMargin: 8
            anchors.baseline: headerTitle.baseline
            text: header.detail
            color: Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
            elide: Text.ElideRight
        }
        Text {
            id: headerValue
            anchors.right: parent.right
            anchors.baseline: headerTitle.baseline
            text: header.value
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }

    component Info: Text {
        width: parent?.width ?? 0
        color: Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 4
        elide: Text.ElideRight
    }

    component Section: Column {
        width: parent?.width ?? 0
        spacing: 4
    }

    Item {
        id: card
        width: 400
        height: layout.implicitHeight + 32

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 12

            Section {
                Header {
                    title: "CPU"
                    detail: popup.cpuModel
                    value: Math.round(popup.cpuUsage * 100) + "%"
                }
                CoreGraph {
                    width: parent.width
                    capacity: popup.historyLength
                    series: popup.coreHistory
                }
                // Legend: swatch, core number, current usage.
                Grid {
                    id: coreLegend
                    readonly property int cellWidth: Math.floor((width - (columns - 1) * columnSpacing) / columns)
                    width: parent.width
                    columns: 6
                    columnSpacing: 6
                    rowSpacing: 2

                    Repeater {
                        model: popup.coreCount
                        delegate: Item {
                            id: legendCell
                            required property int index
                            width: coreLegend.cellWidth
                            height: legendText.implicitHeight

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 2
                                color: popup.coreColor(legendCell.index)
                            }
                            Text {
                                id: legendText
                                x: 12
                                text: (legendCell.index + 1) + " " + Math.round((popup.coreUsages[legendCell.index] ?? 0) * 100).toString().padStart(3, " ") + "%"
                                color: Theme.dimText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                    }
                }
                Info {
                    text: {
                        const parts = [];
                        if (popup.cpuAvgMhz > 0)
                            parts.push((popup.cpuAvgMhz / 1000).toFixed(2) + " GHz avg", (popup.cpuMaxMhz / 1000).toFixed(2) + " GHz max");
                        if (popup.cpuTemp >= 0)
                            parts.push(Math.round(popup.cpuTemp) + "°C");
                        parts.push(popup.coreCount + " threads");
                        return parts.join("  ·  ");
                    }
                }
            }

            Section {
                visible: popup.hasGpu
                Header {
                    title: "GPU"
                    value: Math.round(popup.gpuBusy * 100) + "%"
                }
                Graph {
                    width: parent.width
                    capacity: popup.historyLength
                    values: popup.gpuHistory
                }
                Info {
                    text: {
                        const parts = ["VRAM " + popup.fmtBytes(popup.gpuVramUsed) + " / " + popup.fmtBytes(popup.gpuVramTotal)];
                        if (popup.gpuTemp >= 0)
                            parts.push(Math.round(popup.gpuTemp) + "°C");
                        if (popup.gpuPower >= 0)
                            parts.push(Math.round(popup.gpuPower) + " W");
                        return parts.join("  ·  ");
                    }
                }
            }

            Section {
                Header {
                    title: "Memory"
                    value: popup.fmtBytes(popup.memUsed) + " / " + popup.fmtBytes(popup.memTotal)
                }
                Graph {
                    width: parent.width
                    capacity: popup.historyLength
                    values: popup.memHistory
                }
                Info {
                    text: Math.round(100 * popup.memUsed / Math.max(1, popup.memTotal)) + "% used  ·  " + popup.fmtBytes(popup.memCached) + " cache"
                }
                Item {
                    width: parent.width
                    height: swapLabel.implicitHeight

                    Info {
                        id: swapLabel
                        width: implicitWidth
                        text: "Swap"
                    }
                    UsageBar {
                        anchors.left: swapLabel.right
                        anchors.leftMargin: 8
                        anchors.right: swapValue.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        fraction: popup.swapTotal > 0 ? popup.swapUsed / popup.swapTotal : 0
                        color: Theme.color7
                    }
                    Info {
                        id: swapValue
                        anchors.right: parent.right
                        width: implicitWidth
                        text: popup.swapTotal > 0 ? popup.fmtBytes(popup.swapUsed) + " / " + popup.fmtBytes(popup.swapTotal) : "none"
                    }
                }
            }

            Section {
                id: netSection
                // Graph scale: the peak in view, floored at 1 Mbps so an
                // idle link doesn't magnify noise to full height.
                readonly property real netScale: Math.max(125000, ...popup.netDownHistory, ...popup.netUpHistory)

                Header {
                    title: "Network"
                    detail: popup.netIface
                    value: "↓ " + popup.fmtBits(popup.netDown) + "  ↑ " + popup.fmtBits(popup.netUp)
                }
                Graph {
                    width: parent.width
                    capacity: popup.historyLength
                    values: popup.netDownHistory
                    mirrorValues: popup.netUpHistory
                    peak: netSection.netScale
                }
                Info {
                    text: "scale " + popup.fmtBits(netSection.netScale)
                }
            }

            Section {
                spacing: 8

                Header {
                    title: "Disks"
                }

                Info {
                    visible: popup.disks.length === 0
                    text: "No disks found"
                }

                Repeater {
                    model: popup.disks
                    // Two lines: name, model, R/W rate; then the usage bar
                    // with used / total beside it (same shape as Swap).
                    delegate: Column {
                        id: diskRow
                        required property var modelData
                        readonly property var rate: popup.diskRates[diskRow.modelData.name] ?? {
                            read: 0,
                            write: 0
                        }

                        width: parent.width
                        spacing: 2

                        Item {
                            width: parent.width
                            height: diskName.implicitHeight

                            Text {
                                id: diskName
                                text: diskRow.modelData.name
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                            Text {
                                anchors.left: diskName.right
                                anchors.leftMargin: 8
                                anchors.right: diskRates.left
                                anchors.rightMargin: 8
                                anchors.baseline: diskName.baseline
                                text: diskRow.modelData.model
                                color: Theme.dimText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4
                                elide: Text.ElideRight
                            }
                            Text {
                                id: diskRates
                                anchors.right: parent.right
                                anchors.baseline: diskName.baseline
                                text: "R " + popup.fmtBytes(diskRow.rate.read) + "/s  W " + popup.fmtBytes(diskRow.rate.write) + "/s"
                                color: diskRow.rate.read + diskRow.rate.write > 0 ? Theme.text : Theme.dimText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                        Item {
                            width: parent.width
                            height: diskUsage.implicitHeight

                            UsageBar {
                                anchors.left: parent.left
                                anchors.right: diskUsage.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                fraction: diskRow.modelData.mounted ? diskRow.modelData.used / diskRow.modelData.fsSize : 0
                            }
                            Info {
                                id: diskUsage
                                anchors.right: parent.right
                                width: implicitWidth
                                text: diskRow.modelData.mounted
                                    ? popup.fmtBytes(diskRow.modelData.used) + " / " + popup.fmtBytes(diskRow.modelData.fsSize)
                                    : popup.fmtBytes(diskRow.modelData.size) + " · not mounted"
                            }
                        }
                    }
                }
            }
        }
    }
}
