pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell.Io
import qs.modules.theme
import qs.modules.overlay

// Resource monitor opened from SysMon.qml (the GPU | CPU | Mem pill).
// Docked it's a bento grid of tiles (CPU hero with a per-core equaliser,
// GPU and memory rings, network graph, disk bars); floating it's a
// Mission Center style split - a resource sidebar with live sparklines and
// the selected resource in depth on the right (CPU: every core plotted,
// with buttons to single one out). Everything is read
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

    // Floating: a wider card with much taller traces, at the shared
    // floating zoom (shrunk to fit if it would overflow the screen).

    // Sampled twice a second and scrolled continuously: each graph is drawn
    // one sample behind and slides left over the sample interval, so the
    // line is interpolated between samples and moves smoothly, at the cost
    // of showing everything 0.5s late (see Graph).
    readonly property int sampleInterval: 500
    readonly property int historyLength: 30 // samples = 15s

    function pushed(history, value) {
        // One extra point so the oldest is off the left edge, not inside it.
        return history.concat([value]).slice(-(popup.historyLength + 1));
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

    // Appends a smooth curve through the points to the current canvas path,
    // starting from (xs[0], ys[0]) - a monotone cubic (Fritsch-Carlson), so
    // it flows like GNOME/Ubuntu's system monitor but never overshoots a
    // peak or dips below zero between samples.
    function curveThrough(ctx, xs, ys) {
        const n = xs.length;
        if (n < 2)
            return;
        const d = [];
        for (let i = 0; i < n - 1; i++)
            d.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
        const m = [d[0]];
        for (let i = 1; i < n - 1; i++)
            m.push(d[i - 1] * d[i] <= 0 ? 0 : Math.sign(d[i]) * Math.min((Math.abs(d[i - 1]) + Math.abs(d[i])) / 2, 3 * Math.min(Math.abs(d[i - 1]), Math.abs(d[i]))));
        m.push(d[n - 2]);
        for (let i = 0; i < n - 1; i++) {
            const h = (xs[i + 1] - xs[i]) / 3;
            ctx.bezierCurveTo(xs[i] + h, ys[i] + m[i] * h, xs[i + 1] - h, ys[i + 1] - m[i + 1] * h, xs[i + 1], ys[i + 1]);
        }
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
    property var cpuHistory: []
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
        if (agg && popup.prevCpu) {
            popup.cpuUsage = busy(agg, popup.prevCpu);
            popup.cpuHistory = popup.pushed(popup.cpuHistory, popup.cpuUsage);
        }
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
    property var diskHistory: ({}) // name -> { read: [], write: [] }
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
            const history = {};
            for (const d of popup.disks) {
                const r = rates[d.name] ?? {
                    read: 0,
                    write: 0
                };
                const h = popup.diskHistory[d.name] ?? {
                    read: [],
                    write: []
                };
                history[d.name] = {
                    read: popup.pushed(h.read, r.read),
                    write: popup.pushed(h.write, r.write)
                };
            }
            popup.diskHistory = history;
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
            // Slower-moving / pricier reads once a second (/proc/cpuinfo
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

    // Floating view: the selected sidebar resource ("cpu", "gpu", "mem",
    // "net" or "disk:<name>") and the core singled out on the CPU page
    // (-1 = all equally).
    property string selected: "cpu"
    property int focusCore: -1
    readonly property var selectedDisk: popup.disks.find(d => "disk:" + d.name === popup.selected) ?? null

    // Graph scales: the peak in view, floored so an idle link or disk
    // doesn't magnify noise to full height (1 Mbps / 1 MB/s).
    readonly property real netScale: Math.max(125000, ...popup.netDownHistory, ...popup.netUpHistory)
    function diskScale(name) {
        const h = popup.diskHistory[name];
        return h ? Math.max(1048576, ...h.read, ...h.write) : 1048576;
    }

    // Core colours cycle through the theme's palette slots: the accent
    // first, then the rest brightest first. Slots too dark to read on the
    // card are lifted to a legible lightness, keeping their hue.
    readonly property var corePalette: {
        const slots = [Theme.color1, Theme.color2, Theme.color3, Theme.color4, Theme.color5, Theme.color6, Theme.color7, Theme.color8, Theme.color9, Theme.color10, Theme.color11, Theme.color12, Theme.color14, Theme.color15];
        const lift = c => c.hslLightness >= 0.5 ? c : Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, 0.55 + 0.15 * c.hslLightness, 1);
        return [Theme.accent].concat(slots.slice().sort((a, b) => b.hslLightness - a.hslLightness)).map(lift);
    }
    function coreColor(i) {
        return popup.corePalette[i % popup.corePalette.length];
    }

    function pct(f) {
        return Math.round(f * 100) + "%";
    }

    // Sidebar entries for the floating view.
    readonly property var resources: {
        const r = [{
                key: "cpu",
                label: "CPU",
                icon: String.fromCharCode(0xf2db) // fa-microchip
            }];
        if (popup.hasGpu)
            r.push({
                key: "gpu",
                label: "GPU",
                icon: String.fromCharCode(0xf108) // fa-desktop
            });
        r.push({
            key: "mem",
            label: "Memory",
            icon: String.fromCharCode(0xf1c0) // fa-database
        }, {
            key: "net",
            label: "Network",
            icon: String.fromCharCode(0xf0ec) // fa-exchange
        });
        for (const d of popup.disks)
            r.push({
                key: "disk:" + d.name,
                label: d.name,
                icon: String.fromCharCode(0xf0a0) // fa-hdd-o
            });
        return r;
    }

    function resourceValue(key) {
        if (key === "cpu")
            return popup.pct(popup.cpuUsage);
        if (key === "gpu")
            return popup.pct(popup.gpuBusy);
        if (key === "mem")
            return popup.fmtBytes(popup.memUsed) + " / " + popup.fmtBytes(popup.memTotal);
        if (key === "net")
            return "↓" + popup.fmtBits(popup.netDown).replace(" ", "") + "  ↑" + popup.fmtBits(popup.netUp).replace(" ", "");
        const r = popup.diskRates[key.slice(5)] ?? {
            read: 0,
            write: 0
        };
        return "R " + popup.fmtBytes(r.read) + "/s  W " + popup.fmtBytes(r.write) + "/s";
    }

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
        property real lineWidth: 1.25
        required property int capacity

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

        // The canvas is one step wider than the view and slides left by that
        // step over each sample interval; a new sample repaints it with the
        // newest point one step beyond the edge and snaps it back (onPainted
        // restarts the slide), so the motion is continuous.
        Item {
            id: view
            anchors.fill: parent
            anchors.margins: 1
            clip: true
            readonly property real step: width / (graph.capacity - 1)

        Canvas {
            id: canvas
            width: view.width + view.step
            height: view.height

            NumberAnimation on x {
                id: slide
                running: false
                from: 0
                to: -view.step
                duration: popup.sampleInterval
            }
            onPainted: slide.restart()

            function trace(ctx, vals, base, span, dir, color) {
                if (vals.length < 2)
                    return;
                const step = view.step;
                const xs = vals.map((v, i) => width - (vals.length - 1 - i) * step);
                const ys = vals.map(v => base + dir * Math.min(1, Math.max(0, v / graph.peak)) * span);
                ctx.beginPath();
                ctx.moveTo(xs[0], base);
                ctx.lineTo(xs[0], ys[0]);
                popup.curveThrough(ctx, xs, ys);
                ctx.lineTo(width, base);
                ctx.closePath();
                ctx.fillStyle = Theme.withAlpha(color, 0.3);
                ctx.fill();
                ctx.beginPath();
                ctx.moveTo(xs[0], ys[0]);
                popup.curveThrough(ctx, xs, ys);
                ctx.strokeStyle = color;
                ctx.lineWidth = graph.lineWidth;
                ctx.lineJoin = "round";
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
    }

    // One line per core on a single canvas, like GNOME System Monitor's
    // CPU graph, coloured by coreColor(). With `highlight` set, that core
    // is drawn bold and filled on top and the others fade to faint context.
    component CoreGraph: Item {
        id: coreGraph

        property var series: [] // per core, 0..1 values, newest last
        property int highlight: -1
        required property int capacity

        onSeriesChanged: coreCanvas.requestPaint()
        onHighlightChanged: coreCanvas.requestPaint()

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Theme.hoverBg
        }
        // 25/50/75% guides.
        Repeater {
            model: 3
            delegate: Rectangle {
                required property int index
                y: Math.round(coreGraph.height * (index + 1) / 4)
                width: coreGraph.width
                height: 1
                color: Theme.withAlpha(Theme.dimText, 0.15)
            }
        }

        // Slides like Graph's canvas (see there).
        Item {
            id: coreView
            anchors.fill: parent
            anchors.margins: 1
            clip: true
            readonly property real step: width / (coreGraph.capacity - 1)

        Canvas {
            id: coreCanvas
            width: coreView.width + coreView.step
            height: coreView.height

            NumberAnimation on x {
                id: coreSlide
                running: false
                from: 0
                to: -coreView.step
                duration: popup.sampleInterval
            }
            onPainted: coreSlide.restart()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const step = coreView.step;
                const hl = coreGraph.highlight;
                ctx.lineJoin = "round";
                const line = (c, alpha, lw, fill) => {
                    const vals = coreGraph.series[c] ?? [];
                    if (vals.length < 2)
                        return;
                    const xs = vals.map((v, i) => width - (vals.length - 1 - i) * step);
                    const ys = vals.map(v => height - Math.min(1, Math.max(0, v)) * (height - 1));
                    const color = popup.coreColor(c);
                    if (fill) {
                        ctx.beginPath();
                        ctx.moveTo(xs[0], height);
                        ctx.lineTo(xs[0], ys[0]);
                        popup.curveThrough(ctx, xs, ys);
                        ctx.lineTo(width, height);
                        ctx.closePath();
                        ctx.fillStyle = Theme.withAlpha(color, 0.2);
                        ctx.fill();
                    }
                    ctx.beginPath();
                    ctx.moveTo(xs[0], ys[0]);
                    popup.curveThrough(ctx, xs, ys);
                    ctx.strokeStyle = Theme.withAlpha(color, alpha);
                    ctx.lineWidth = lw;
                    ctx.stroke();
                };
                for (let c = 0; c < coreGraph.series.length; c++) {
                    if (c !== hl)
                        line(c, hl < 0 ? 1 : 0.15, 1.5, false);
                }
                if (hl >= 0)
                    line(hl, 1, 2.25, true);
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

    // Usage ring: a full faint track with the used fraction swept over it
    // clockwise from 12 o'clock, and a label in the middle.
    component Ring: Item {
        id: ring
        property real fraction: 0
        property real thickness: 5
        property color color: Theme.accent
        property string label

        width: 52
        height: width

        Behavior on fraction {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Theme.withAlpha(Theme.dimText, 0.3)
                strokeWidth: ring.thickness
                fillColor: "transparent"
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: (ring.width - ring.thickness) / 2
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: 360
                }
            }
            ShapePath {
                strokeColor: ring.color
                strokeWidth: ring.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: (ring.width - ring.thickness) / 2
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0.001, Math.min(1, ring.fraction))
                }
            }
        }
        Text {
            anchors.centerIn: parent
            text: ring.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            font.bold: true
        }
    }

    // Bento tile: faint raised card with a padded column inside.
    component Tile: Rectangle {
        id: tile
        default property alias content: tileBody.data
        property alias spacing: tileBody.spacing

        radius: 8
        color: Theme.withAlpha(Theme.foreground, 0.05)
        border.width: 1
        border.color: Theme.withAlpha(Theme.foreground, 0.08)
        implicitHeight: tileBody.implicitHeight + 20

        Column {
            id: tileBody
            x: 10
            y: 10
            width: tile.width - 20
            spacing: 6
        }
    }

    // Small spaced-out uppercase label (tile and stat captions).
    component Cap: Text {
        color: Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 5
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
    }

    // Title (bold), dim detail, value on the right (`big` for page heads).
    component Header: Item {
        id: header
        property string title
        property string detail
        property string value
        property bool big: false

        width: parent?.width ?? 0
        height: Math.max(headerTitle.implicitHeight, headerValue.implicitHeight)

        Text {
            id: headerTitle
            anchors.baseline: headerValue.baseline
            text: header.title
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: header.big ? Theme.fontSize + 1 : Theme.fontSize
            font.bold: true
        }
        Text {
            anchors.left: headerTitle.right
            anchors.leftMargin: 8
            anchors.right: headerValue.left
            anchors.rightMargin: 8
            anchors.baseline: headerValue.baseline
            text: header.detail
            color: Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
            elide: Text.ElideRight
        }
        Text {
            id: headerValue
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: header.value
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: header.big ? Theme.fontSize + 8 : Theme.fontSize - 2
            font.bold: header.big
        }
    }

    component Info: Text {
        width: parent?.width ?? 0
        color: Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 4
        elide: Text.ElideRight
    }

    // Caption over a value, for the floating pages' stat rows.
    component Stat: Column {
        property alias label: statLabel.text
        property alias value: statValue.text
        property alias valueColor: statValue.color
        spacing: 2
        Cap {
            id: statLabel
        }
        Text {
            id: statValue
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }

    // "label ─────── value" with a usage bar between (swap, VRAM...).
    component BarLine: Item {
        id: barLine
        property string label
        property string value
        property real fraction
        property color color: Theme.accent

        width: parent?.width ?? 0
        height: barLineLabel.implicitHeight

        Info {
            id: barLineLabel
            width: implicitWidth
            text: barLine.label
        }
        UsageBar {
            anchors.left: barLineLabel.right
            anchors.leftMargin: 8
            anchors.right: barLineValue.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            fraction: barLine.fraction
            color: barLine.color
        }
        Info {
            id: barLineValue
            anchors.right: parent.right
            width: implicitWidth
            text: barLine.value
        }
    }

    readonly property string cpuInfoText: {
        const parts = [];
        if (popup.cpuTemp >= 0)
            parts.push(Math.round(popup.cpuTemp) + "°C");
        if (popup.cpuAvgMhz > 0)
            parts.push((popup.cpuAvgMhz / 1000).toFixed(2) + " GHz avg", (popup.cpuMaxMhz / 1000).toFixed(2) + " GHz max");
        parts.push(popup.coreCount + " threads");
        return parts.join("  ·  ");
    }

    Item {
        id: card
        width: popup.floating ? 720 : 420
        height: ((popup.floating ? floatingLoader.item?.implicitHeight : dockedLoader.item?.implicitHeight) ?? 0) + 32

        Loader {
            id: dockedLoader
            active: !popup.floating
            x: 16
            y: 16
            width: card.width - 32
            sourceComponent: docked
        }
        Loader {
            id: floatingLoader
            active: popup.floating
            x: 16
            y: 16
            width: card.width - 32
            sourceComponent: floatingView
        }
    }

    // ---- Docked: bento tiles ----

    Component {
        id: docked

        Column {
            id: bento
            spacing: 8

            // CPU hero: total graph beside a live per-core equaliser.
            Tile {
                width: bento.width

                Header {
                    title: "CPU"
                    detail: popup.cpuModel
                    value: popup.pct(popup.cpuUsage)
                    big: true
                }
                Item {
                    width: parent.width
                    height: 56

                    Graph {
                        anchors.left: parent.left
                        anchors.right: equaliser.left
                        anchors.rightMargin: 10
                        height: parent.height
                        capacity: popup.historyLength
                        values: popup.cpuHistory
                    }
                    Row {
                        id: equaliser
                        anchors.right: parent.right
                        width: 110
                        height: parent.height
                        spacing: 2

                        Repeater {
                            model: popup.coreCount
                            delegate: Item {
                                id: eqBar
                                required property int index
                                width: (equaliser.width - (popup.coreCount - 1) * equaliser.spacing) / Math.max(1, popup.coreCount)
                                height: equaliser.height

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 1.5
                                    color: Theme.withAlpha(Theme.dimText, 0.15)
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, parent.height * (popup.coreUsages[eqBar.index] ?? 0))
                                    radius: 1.5
                                    color: Theme.accent
                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 400
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Info {
                    text: popup.cpuInfoText
                }
            }

            // GPU + memory rings side by side (memory alone without a GPU).
            Row {
                width: bento.width
                spacing: 8

                Tile {
                    visible: popup.hasGpu
                    width: (bento.width - 8) / 2

                    Row {
                        spacing: 10
                        Ring {
                            fraction: popup.gpuBusy
                            label: popup.pct(popup.gpuBusy)
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Cap {
                                text: "GPU"
                            }
                            Info {
                                width: implicitWidth
                                text: [popup.gpuTemp >= 0 ? Math.round(popup.gpuTemp) + "°C" : "", popup.gpuPower >= 0 ? Math.round(popup.gpuPower) + " W" : ""].filter(s => s).join(" · ")
                            }
                        }
                    }
                    BarLine {
                        label: "VRAM"
                        value: popup.fmtBytes(popup.gpuVramUsed) + " / " + popup.fmtBytes(popup.gpuVramTotal)
                        fraction: popup.gpuVramTotal > 0 ? popup.gpuVramUsed / popup.gpuVramTotal : 0
                    }
                }
                Tile {
                    width: popup.hasGpu ? (bento.width - 8) / 2 : bento.width

                    Row {
                        spacing: 10
                        Ring {
                            fraction: popup.memTotal > 0 ? popup.memUsed / popup.memTotal : 0
                            label: popup.pct(popup.memTotal > 0 ? popup.memUsed / popup.memTotal : 0)
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Cap {
                                text: "Memory"
                            }
                            Info {
                                width: implicitWidth
                                text: popup.fmtBytes(popup.memUsed) + " / " + popup.fmtBytes(popup.memTotal)
                            }
                            Info {
                                width: implicitWidth
                                text: popup.fmtBytes(popup.memCached) + " cache"
                            }
                        }
                    }
                    BarLine {
                        label: "Swap"
                        value: popup.swapTotal > 0 ? popup.fmtBytes(popup.swapUsed) + " / " + popup.fmtBytes(popup.swapTotal) : "none"
                        fraction: popup.swapTotal > 0 ? popup.swapUsed / popup.swapTotal : 0
                        color: Theme.color7
                    }
                }
            }

            Tile {
                width: bento.width

                Header {
                    title: "Net"
                    detail: popup.netIface
                    value: "↓ " + popup.fmtBits(popup.netDown) + "   ↑ " + popup.fmtBits(popup.netUp)
                }
                Graph {
                    width: parent.width
                    height: 40
                    capacity: popup.historyLength
                    values: popup.netDownHistory
                    mirrorValues: popup.netUpHistory
                    peak: popup.netScale
                }
            }

            // One line per disk: name, usage bar, R/W rate, used / total.
            Tile {
                width: bento.width
                spacing: 5

                Cap {
                    text: "Disks"
                }
                Info {
                    visible: popup.disks.length === 0
                    text: "No disks found"
                }
                Repeater {
                    model: popup.disks
                    delegate: Item {
                        id: diskRow
                        required property var modelData
                        readonly property var rate: popup.diskRates[diskRow.modelData.name] ?? {
                            read: 0,
                            write: 0
                        }

                        width: parent.width
                        height: diskName.implicitHeight

                        Text {
                            id: diskName
                            width: 64
                            text: diskRow.modelData.name
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            elide: Text.ElideRight
                        }
                        UsageBar {
                            anchors.left: diskName.right
                            anchors.leftMargin: 8
                            anchors.right: diskIo.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            fraction: diskRow.modelData.mounted ? diskRow.modelData.used / diskRow.modelData.fsSize : 0
                        }
                        Info {
                            id: diskIo
                            anchors.right: diskUsage.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 96
                            horizontalAlignment: Text.AlignRight
                            text: "R " + popup.fmtBytes(diskRow.rate.read) + " W " + popup.fmtBytes(diskRow.rate.write)
                            color: diskRow.rate.read + diskRow.rate.write > 0 ? Theme.text : Theme.dimText
                        }
                        Info {
                            id: diskUsage
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 84
                            horizontalAlignment: Text.AlignRight
                            text: diskRow.modelData.mounted ? popup.fmtBytes(diskRow.modelData.used) + " / " + popup.fmtBytes(diskRow.modelData.fsSize) : popup.fmtBytes(diskRow.modelData.size) + " · off"
                        }
                    }
                }
            }
        }
    }

    // ---- Floating: resource sidebar + detail ----

    Component {
        id: floatingView

        Row {
            id: split
            spacing: 16
            // Fixed for the whole open (the disk list is fixed once shown),
            // so switching pages never resizes the window.
            readonly property real pageHeight: Math.max(390, sidebar.implicitHeight)

            Column {
                id: sidebar
                width: 210
                spacing: 3

                Cap {
                    leftPadding: 10
                    bottomPadding: 3
                    text: "Resources"
                }
                Repeater {
                    model: popup.resources
                    delegate: Rectangle {
                        id: res
                        required property var modelData
                        readonly property bool current: popup.selected === res.modelData.key
                        readonly property string diskName: res.modelData.key.startsWith("disk:") ? res.modelData.key.slice(5) : ""

                        width: sidebar.width
                        height: 48
                        radius: 8
                        color: res.current || resMa.containsMouse ? Theme.hoverBg : "transparent"

                        Rectangle {
                            visible: res.current
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: parent.height - 16
                            radius: 1
                            color: Theme.accent
                        }
                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: resGraph.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Row {
                                spacing: 7
                                Text {
                                    text: res.modelData.icon
                                    color: res.current ? Theme.accent : Theme.dimText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }
                                Text {
                                    text: res.modelData.label
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }
                            }
                            Info {
                                text: popup.resourceValue(res.modelData.key)
                            }
                        }
                        Graph {
                            id: resGraph
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            height: 30
                            lineWidth: 1
                            capacity: popup.historyLength
                            values: {
                                switch (res.modelData.key) {
                                case "cpu":
                                    return popup.cpuHistory;
                                case "gpu":
                                    return popup.gpuHistory;
                                case "mem":
                                    return popup.memHistory;
                                case "net":
                                    return popup.netDownHistory;
                                default:
                                    return popup.diskHistory[res.diskName]?.read ?? [];
                                }
                            }
                            mirrorValues: res.modelData.key === "net" ? popup.netUpHistory : res.diskName ? (popup.diskHistory[res.diskName]?.write ?? []) : null
                            peak: res.modelData.key === "net" ? popup.netScale : res.diskName ? popup.diskScale(res.diskName) : 1
                        }
                        MouseArea {
                            id: resMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.selected = res.modelData.key
                        }
                    }
                }
            }

            // Only the selected page exists, so only its graphs paint.
            Loader {
                width: split.width - sidebar.width - split.spacing
                height: split.pageHeight
                sourceComponent: popup.selected === "cpu" ? cpuPage : popup.selected === "gpu" ? gpuPage : popup.selected === "mem" ? memPage : popup.selected === "net" ? netPage : diskPage
            }
        }
    }

    Component {
        id: cpuPage

        Column {
            id: cpuCol
            spacing: 10

            Header {
                title: "CPU"
                detail: popup.cpuModel
                value: popup.pct(popup.cpuUsage)
                big: true
            }
            CoreGraph {
                width: cpuCol.width
                height: 200
                capacity: popup.historyLength
                series: popup.coreHistory
                highlight: popup.focusCore
            }
            // Core picker doubling as the legend: All, then each core's
            // swatch, number and live usage. Clicking a core singles it out
            // in the graph; clicking it again (or All) shows every core.
            Grid {
                id: corePicker
                readonly property int cellWidth: Math.floor((width - (columns - 1) * columnSpacing) / columns)
                width: cpuCol.width
                columns: 9
                columnSpacing: 4
                rowSpacing: 4

                Repeater {
                    model: popup.coreCount + 1
                    delegate: Rectangle {
                        id: coreButton
                        required property int index
                        readonly property int core: index - 1
                        readonly property bool current: popup.focusCore === coreButton.core
                        readonly property color swatch: coreButton.core < 0 ? Theme.accent : popup.coreColor(coreButton.core)

                        width: corePicker.cellWidth
                        height: 34
                        radius: 6
                        color: coreButton.current ? Theme.withAlpha(coreButton.swatch, 0.18) : coreMa.containsMouse ? Theme.hoverBg : "transparent"
                        border.width: 1
                        border.color: coreButton.current ? coreButton.swatch : Theme.withAlpha(Theme.foreground, 0.1)

                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 4
                                Rectangle {
                                    visible: coreButton.core >= 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 7
                                    height: 7
                                    radius: 2
                                    color: coreButton.swatch
                                }
                                Text {
                                    text: coreButton.core < 0 ? "All" : (coreButton.core + 1).toString()
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    font.bold: coreButton.current
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: popup.pct(coreButton.core < 0 ? popup.cpuUsage : popup.coreUsages[coreButton.core] ?? 0)
                                color: Theme.dimText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 5
                            }
                        }
                        MouseArea {
                            id: coreMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.focusCore = coreButton.current ? -1 : coreButton.core
                        }
                    }
                }
            }
            Row {
                spacing: 28
                Stat {
                    label: "speed"
                    value: popup.cpuAvgMhz > 0 ? (popup.cpuAvgMhz / 1000).toFixed(2) + " GHz" : "–"
                }
                Stat {
                    label: "max"
                    value: popup.cpuMaxMhz > 0 ? (popup.cpuMaxMhz / 1000).toFixed(2) + " GHz" : "–"
                }
                Stat {
                    label: "temp"
                    value: popup.cpuTemp >= 0 ? Math.round(popup.cpuTemp) + "°C" : "–"
                }
                Stat {
                    label: "threads"
                    value: popup.coreCount.toString()
                }
            }
        }
    }

    Component {
        id: gpuPage

        Column {
            id: gpuCol
            spacing: 10

            Header {
                title: "GPU"
                detail: "amdgpu"
                value: popup.pct(popup.gpuBusy)
                big: true
            }
            Graph {
                width: gpuCol.width
                height: 220
                capacity: popup.historyLength
                values: popup.gpuHistory
            }
            BarLine {
                label: "VRAM"
                value: popup.fmtBytes(popup.gpuVramUsed) + " / " + popup.fmtBytes(popup.gpuVramTotal)
                fraction: popup.gpuVramTotal > 0 ? popup.gpuVramUsed / popup.gpuVramTotal : 0
            }
            Row {
                spacing: 28
                Stat {
                    label: "temp"
                    value: popup.gpuTemp >= 0 ? Math.round(popup.gpuTemp) + "°C" : "–"
                }
                Stat {
                    label: "power"
                    value: popup.gpuPower >= 0 ? Math.round(popup.gpuPower) + " W" : "–"
                }
                Stat {
                    label: "busy"
                    value: popup.pct(popup.gpuBusy)
                }
            }
        }
    }

    Component {
        id: memPage

        Column {
            id: memCol
            spacing: 10

            readonly property real usedFrac: popup.memTotal > 0 ? popup.memUsed / popup.memTotal : 0
            readonly property real cacheFrac: popup.memTotal > 0 ? Math.min(popup.memCached, popup.memTotal - popup.memUsed) / popup.memTotal : 0

            Header {
                title: "Memory"
                detail: popup.fmtBytes(popup.memTotal) + " total"
                value: popup.fmtBytes(popup.memUsed)
                big: true
            }
            Graph {
                width: memCol.width
                height: 190
                capacity: popup.historyLength
                values: popup.memHistory
            }
            Cap {
                text: "Composition"
            }
            // used | cache | free, proportional.
            Row {
                width: memCol.width
                height: 14
                spacing: 2
                Rectangle {
                    width: (memCol.width - 4) * memCol.usedFrac
                    height: parent.height
                    radius: 3
                    color: Theme.accent
                }
                Rectangle {
                    width: (memCol.width - 4) * memCol.cacheFrac
                    height: parent.height
                    radius: 3
                    color: Theme.withAlpha(Theme.accent, 0.4)
                }
                Rectangle {
                    width: Math.max(0, (memCol.width - 4) * (1 - memCol.usedFrac - memCol.cacheFrac))
                    height: parent.height
                    radius: 3
                    color: Theme.withAlpha(Theme.dimText, 0.25)
                }
            }
            Row {
                spacing: 16
                Repeater {
                    model: [
                        {
                            color: Theme.accent,
                            text: "used " + popup.fmtBytes(popup.memUsed)
                        },
                        {
                            color: Theme.withAlpha(Theme.accent, 0.4),
                            text: "cache " + popup.fmtBytes(popup.memCached)
                        },
                        {
                            color: Theme.withAlpha(Theme.dimText, 0.25),
                            text: "free " + popup.fmtBytes(Math.max(0, popup.memTotal - popup.memUsed - popup.memCached))
                        }
                    ]
                    delegate: Row {
                        id: legendItem
                        required property var modelData
                        spacing: 5
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 2
                            color: legendItem.modelData.color
                        }
                        Info {
                            width: implicitWidth
                            text: legendItem.modelData.text
                        }
                    }
                }
            }
            BarLine {
                label: "Swap"
                value: popup.swapTotal > 0 ? popup.fmtBytes(popup.swapUsed) + " / " + popup.fmtBytes(popup.swapTotal) : "none"
                fraction: popup.swapTotal > 0 ? popup.swapUsed / popup.swapTotal : 0
                color: Theme.color7
            }
        }
    }

    Component {
        id: netPage

        Column {
            id: netCol
            spacing: 10

            Header {
                title: "Network"
                detail: popup.netIface + (popup.netIface === popup.defaultIface() ? " · default route" : "")
                big: true
            }
            Graph {
                width: netCol.width
                height: 240
                capacity: popup.historyLength
                values: popup.netDownHistory
                mirrorValues: popup.netUpHistory
                peak: popup.netScale
            }
            Row {
                spacing: 28
                Stat {
                    label: "↓ down"
                    value: popup.fmtBits(popup.netDown)
                }
                Stat {
                    label: "↑ up"
                    value: popup.fmtBits(popup.netUp)
                    valueColor: Theme.color7
                }
                Stat {
                    label: "scale"
                    value: popup.fmtBits(popup.netScale)
                }
            }
        }
    }

    Component {
        id: diskPage

        Column {
            id: diskCol
            readonly property var disk: popup.selectedDisk ?? {
                name: "",
                model: "",
                size: 0,
                used: 0,
                fsSize: 0,
                mounted: false
            }
            readonly property var rate: popup.diskRates[diskCol.disk.name] ?? {
                read: 0,
                write: 0
            }
            spacing: 10

            Header {
                title: diskCol.disk.name
                detail: diskCol.disk.model
                value: diskCol.disk.mounted ? popup.pct(diskCol.disk.used / diskCol.disk.fsSize) : ""
                big: true
            }
            Graph {
                width: diskCol.width
                height: 220
                capacity: popup.historyLength
                values: popup.diskHistory[diskCol.disk.name]?.read ?? []
                mirrorValues: popup.diskHistory[diskCol.disk.name]?.write ?? []
                peak: popup.diskScale(diskCol.disk.name)
            }
            BarLine {
                label: "Used"
                value: diskCol.disk.mounted ? popup.fmtBytes(diskCol.disk.used) + " / " + popup.fmtBytes(diskCol.disk.fsSize) : popup.fmtBytes(diskCol.disk.size) + " · not mounted"
                fraction: diskCol.disk.mounted ? diskCol.disk.used / diskCol.disk.fsSize : 0
            }
            Row {
                spacing: 28
                Stat {
                    label: "read"
                    value: popup.fmtBytes(diskCol.rate.read) + "/s"
                }
                Stat {
                    label: "write"
                    value: popup.fmtBytes(diskCol.rate.write) + "/s"
                    valueColor: Theme.color7
                }
                Stat {
                    label: "scale"
                    value: popup.fmtBytes(popup.diskScale(diskCol.disk.name)) + "/s"
                }
            }
        }
    }
}
