pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Entry point for lightning strikes: Bolts.strike(from, to, style) draws a
// bolt from `from` to `to` (global logical coords, `from` null = a random
// point on the bottom edge) using BoltConfig.styles[style]. The OverlayHost
// (modules/overlay) of whichever screen `to` is on does the drawing, so a
// source on another monitor just enters from that screen's edge.
//
// Also turns the Hyprland-side triggers into strikes: hypr/hyprland/bolt.lua
// emits `custom>>bolt:focus ...` / `custom>>bolt:open ...` on socket2, which
// arrive here through Hyprland.rawEvent - nothing polls or spawns.
Singleton {
    id: root

    // Runtime copy of the master switch so `qs ipc call bolt toggle` can
    // flip it without editing BoltConfig.
    property bool enabled: BoltConfig.enabled

    // `path` (optional) is an explicit waypoint run ending at `to` - see
    // strikePath.
    signal requested(var from, var to, string style, var path)
    // Super+Ctrl+drag (bolt.lua): live cursor samples, then the end.
    signal drawPoint(var p)
    signal drawEnded

    function active(trigger) {
        return root.enabled && (BoltConfig[trigger]?.enabled ?? false);
    }

    function strike(from, to, style) {
        if (!root.enabled || !to)
            return;
        if (from && Math.hypot(to.x - from.x, to.y - from.y) < 1)
            return;
        root.requested(from, to, style in BoltConfig.styles ? style : "popup", null);
    }

    // Bolt along explicit waypoints (global coords), e.g. a spiralPath.
    function strikePath(path, style) {
        if (!root.enabled || !path || path.length < 2)
            return;
        root.requested(null, path[path.length - 1], style in BoltConfig.styles ? style : "popup", path);
    }

    function screenByName(name) {
        return Quickshell.screens.find(s => s.name === name) ?? null;
    }

    // Screen-local -> global.
    function toGlobal(screenName, x, y) {
        const s = root.screenByName(screenName);
        return Qt.point(x + (s?.x ?? 0), y + (s?.y ?? 0));
    }

    // ── Origin hint ──────────────────────────────────────────────────────────
    // Keytree records the node it launched from; the next popup/app-open
    // strike starts there instead of its default source.
    property var origin: null

    function setOrigin(p) {
        root.origin = p ? { x: p.x, y: p.y, time: Date.now() } : null;
    }

    function takeOrigin() {
        const o = root.origin;
        root.origin = null;
        return o && Date.now() - o.time <= BoltConfig.originMaxAgeMs ? Qt.point(o.x, o.y) : null;
    }

    // ── Direct launches (bolt.exec binds) ────────────────────────────────────
    // When the launch happened; the next window's open event carries where
    // it came from, honoured only if that launch is recent enough.
    property real launchTime: 0

    // Small spiral settling onto the middle of rect r.
    function launchSpiral(r) {
        const cfg = BoltConfig.launch;
        const radius = Math.min(cfg.spiralMaxPx, cfg.spiralRadius * Math.min(r.w, r.h));
        const center = Qt.point(r.x + r.w / 2, r.y + r.h / 2);
        const a = Math.random() * 2 * Math.PI;
        const target = Qt.point(center.x + radius * Math.cos(a), center.y + radius * Math.sin(a));
        root.strikePath(root.spiralPath(center, target, cfg.spiralTurns), "launchSwirl");
    }

    // ── Find the cursor (Super+Ctrl) ────────────────────────────────────────
    // A spiral from out at `radius` winding in onto the cursor - the
    // keytree's outward spiral, reversed.
    function cursorSpiral(p) {
        const cfg = BoltConfig.cursor;
        const a = Math.random() * 2 * Math.PI;
        const outer = Qt.point(p.x + cfg.radius * Math.cos(a), p.y + cfg.radius * Math.sin(a));
        root.strikePath(root.spiralPath(p, outer, cfg.turns).reverse(), "cursor");
    }

    // ── Named anchors (BoltAnchor) ───────────────────────────────────────────
    property var anchorItems: []

    function registerAnchor(a) {
        root.anchorItems = root.anchorItems.concat([a]);
    }

    function unregisterAnchor(a) {
        root.anchorItems = root.anchorItems.filter(x => x !== a);
    }

    // Prefers the instance on the focused monitor (there's one bar per screen).
    function anchorPoint(name) {
        const focused = Hyprland.focusedMonitor?.name ?? "";
        const candidates = root.anchorItems.filter(a => a.name === name && a.usable);
        const a = candidates.find(c => c.screenName === focused) ?? candidates[0];
        return a ? a.globalPoint() : null;
    }

    // "edge" / "anchor:<name>" -> point or null (null = bottom edge).
    function resolveFrom(spec) {
        if (typeof spec === "string" && spec.startsWith("anchor:"))
            return root.anchorPoint(spec.slice(7));
        return null;
    }

    // Waypoints spiralling out from `center` and ending exactly on `target`,
    // `turns` times around (direction random). For BoltItem's { path }.
    function spiralPath(center, target, turns) {
        const dx = target.x - center.x, dy = target.y - center.y;
        const R = Math.hypot(dx, dy), end = Math.atan2(dy, dx);
        const dir = Math.random() < 0.5 ? -1 : 1;
        const steps = Math.max(8, Math.round(turns * 20));
        const pts = [];
        for (let i = 0; i <= steps; i++) {
            const k = i / steps;
            const theta = end - dir * turns * 2 * Math.PI * (1 - k);
            const r = R * Math.pow(k, 0.7);
            pts.push(Qt.point(center.x + r * Math.cos(theta), center.y + r * Math.sin(theta)));
        }
        return pts;
    }

    // ── Hyprland triggers ────────────────────────────────────────────────────
    function rect(parts, i) {
        return { x: Number(parts[i]), y: Number(parts[i + 1]), w: Number(parts[i + 2]), h: Number(parts[i + 3]) };
    }

    // Whether a line from r's center along (dx, dy) leaves through its
    // left/right side rather than top/bottom.
    function exitsSideways(r, dx, dy) {
        return r.w * Math.abs(dy) < r.h * Math.abs(dx);
    }

    // Shared stretch of two ranges, trimmed 10% each end - null if they
    // barely overlap.
    function overlap(a0, a1, b0, b1) {
        const lo = Math.max(a0, b0), hi = Math.min(a1, b1), pad = (hi - lo) * 0.1;
        return hi - lo >= 40 ? [lo + pad, hi - pad] : null;
    }

    // Midpoint displacement from (x0, y0) to (x1, y1): each segment's
    // midpoint pushed sideways by up to `spread`, shrinking every level.
    // Shared by BoltItem and BoltTrail.
    function displace(x0, y0, x1, y1, levels, spread) {
        let pts = [{ x: x0, y: y0 }, { x: x1, y: y1 }];
        let d = spread;
        for (let l = 0; l < levels; l++) {
            const next = [pts[0]];
            for (let i = 1; i < pts.length; i++) {
                const a = pts[i - 1], b = pts[i];
                const dx = b.x - a.x, dy = b.y - a.y;
                const len = Math.hypot(dx, dy) || 1;
                const off = (Math.random() * 2 - 1) * d;
                next.push({ x: (a.x + b.x) / 2 - dy / len * off, y: (a.y + b.y) / 2 + dx / len * off });
                next.push(b);
            }
            pts = next;
            d *= 0.55;
        }
        return pts;
    }

    function rand(lo, hi) {
        return lo + (hi - lo) * Math.random();
    }

    // Position across the gap: on r's side facing `dir` (+1/-1) along the
    // jump axis, at most cfg.maxInset of the window's depth inside, biased
    // toward the edge.
    function edgeDepth(lo, size, dir, cfg) {
        const depth = cfg.maxInset * Math.pow(Math.random(), cfg.edgeBias);
        return dir > 0 ? lo + size * (1 - depth) : lo + size * depth;
    }

    // Start/end points for a jump from window a to window b, on their facing
    // edges. Works in jump-axis terms ("across" the gap, "along" the edges -
    // x/y for side-by-side windows, y/x for stacked ones):
    //   1. both ends' across positions (random depth near each edge)
    //   2. a random along position for one end (which one is random too)
    //   3. the other end's along within +/- the across distance * maxSlope,
    //      so the bolt never runs steeper than that
    // When the windows don't line up (no shared stretch, or they face each
    // other on different axes) step 3 has nothing to stay inside, so each end
    // just takes its own random spot along its edge.
    function facingPoints(a, b, cfg) {
        const ax = a.x + a.w / 2, ay = a.y + a.h / 2;
        const bx = b.x + b.w / 2, by = b.y + b.h / 2;
        const dx = bx - ax, dy = by - ay;
        if (Math.abs(dx) < 1 && Math.abs(dy) < 1)
            return null;
        // Overlapping (floating) windows - no gap to jump, go center to center.
        const exitA = Math.min(a.w / 2 / Math.abs(dx), a.h / 2 / Math.abs(dy));
        const enterB = Math.min(b.w / 2 / Math.abs(dx), b.h / 2 / Math.abs(dy));
        if (exitA + enterB >= 1)
            return [Qt.point(ax, ay), Qt.point(bx, by)];

        const sideA = root.exitsSideways(a, dx, dy), sideB = root.exitsSideways(b, -dx, -dy);
        // Per window: across-axis [start, size, direction toward the other],
        // along-axis [lo, hi] (10% in from the corners).
        const axes = (r, sideways, dir) => sideways
            ? { across: [r.x, r.w, Math.sign(dir.x)], along: [r.y + r.h * 0.1, r.y + r.h * 0.9] }
            : { across: [r.y, r.h, Math.sign(dir.y)], along: [r.x + r.w * 0.1, r.x + r.w * 0.9] };
        const A = axes(a, sideA, { x: dx, y: dy }), B = axes(b, sideB, { x: -dx, y: -dy });
        const acrossA = root.edgeDepth(...A.across, cfg), acrossB = root.edgeDepth(...B.across, cfg);

        const span = sideA !== sideB ? null : sideA ? root.overlap(a.y, a.y + a.h, b.y, b.y + b.h) : root.overlap(a.x, a.x + a.w, b.x, b.x + b.w);
        let alongA, alongB;
        if (span) {
            const reach = Math.abs(acrossB - acrossA) * cfg.maxSlope;
            const first = root.rand(...span);
            const second = Math.max(span[0], Math.min(span[1], first + root.rand(-reach, reach)));
            [alongA, alongB] = Math.random() < 0.5 ? [first, second] : [second, first];
        } else {
            alongA = root.rand(...A.along);
            alongB = root.rand(...B.along);
        }
        const pt = (sideways, across, along) => sideways ? Qt.point(across, along) : Qt.point(along, across);
        return [pt(sideA, acrossA, alongA), pt(sideB, acrossB, alongB)];
    }

    function handleCustom(data) {
        const parts = data.split(" ");
        if (parts[0] === "bolt:focus" && parts.length >= 9) {
            if (!root.active("focus"))
                return;
            const pts = root.facingPoints(root.rect(parts, 1), root.rect(parts, 5), BoltConfig.focus);
            if (pts)
                root.strike(pts[0], pts[1], "focus");
        } else if (parts[0] === "bolt:cursor" && parts.length >= 3) {
            if (root.active("cursor"))
                root.cursorSpiral(Qt.point(Number(parts[1]), Number(parts[2])));
        } else if (parts[0] === "bolt:draw" && parts.length >= 3) {
            if (root.active("draw"))
                root.drawPoint(Qt.point(Number(parts[1]), Number(parts[2])));
        } else if (parts[0] === "bolt:drawend") {
            root.drawEnded();
        } else if (parts[0] === "bolt:launch") {
            root.launchTime = Date.now();
        } else if (parts[0] === "bolt:open" && parts.length >= 6) {
            const r = root.rect(parts, 1);
            if (r.w <= 0 || r.h <= 0)
                return;
            // bolt.lua: parts[5] = launch source ("x,y,w,h" / "spiral" / "-").
            const src = parts[5];
            const cls = parts.slice(6).join(" ");
            const launched = src !== "-" && Date.now() - root.launchTime <= BoltConfig.launch.maxAgeMs;
            if (launched) {
                root.launchTime = 0;
                if (!root.active("launch"))
                    return;
                if (src === "spiral") {
                    if (BoltConfig.launch.spiral)
                        root.launchSpiral(r);
                } else if (BoltConfig.launch.fromWindow) {
                    const n = src.split(",").map(Number);
                    const pts = root.facingPoints({ x: n[0], y: n[1], w: n[2], h: n[3] }, r, BoltConfig.launch);
                    if (pts)
                        root.strike(pts[0], pts[1], "launch");
                }
                return;
            }
            if (!root.active("open"))
                return;
            const app = BoltConfig.open.apps[cls];
            const origin = app || BoltConfig.open.allApps || BoltConfig.open.fromKeytree ? root.takeOrigin() : null;
            if (!app && !BoltConfig.open.allApps && !origin)
                return;
            const from = origin ?? root.resolveFrom(app?.from ?? BoltConfig.open.defaultFrom);
            root.strike(from, Qt.point(r.x + r.w / 2, r.y + r.h / 2), "open");
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "custom" && event.data.startsWith("bolt:"))
                root.handleCustom(event.data);
        }
    }

    IpcHandler {
        target: "bolt"

        function toggle(): string {
            root.enabled = !root.enabled;
            return root.enabled ? "on" : "off";
        }
        // Strike the focused monitor's center, e.g. `qs ipc call bolt test focus`.
        function test(style: string): void {
            const s = root.screenByName(Hyprland.focusedMonitor?.name ?? "") ?? Quickshell.screens[0];
            if (s)
                root.strike(null, Qt.point(s.x + s.width / 2, s.y + s.height / 2), style);
        }
    }
}
