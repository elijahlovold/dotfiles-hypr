pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Entry point for lightning strikes: Bolts.strike(from, to, style) draws a
// bolt from `from` to `to` (global logical coords, `from` null = a random
// point on the bottom edge) using BoltConfig.styles[style]. Bolt.qml does
// the drawing on whichever screen `to` is on, so a source on another
// monitor just enters from that screen's edge.
//
// Also turns the Hyprland-side triggers into strikes: hypr/hyprland/bolt.lua
// emits `custom>>bolt:focus ...` / `custom>>bolt:open ...` on socket2, which
// arrive here through Hyprland.rawEvent - nothing polls or spawns.
Singleton {
    id: root

    // Runtime copy of the master switch so `qs ipc call bolt toggle` can
    // flip it without editing BoltConfig.
    property bool enabled: BoltConfig.enabled

    signal requested(var from, var to, string style)

    function active(trigger) {
        return root.enabled && (BoltConfig[trigger]?.enabled ?? false);
    }

    function strike(from, to, style) {
        if (!root.enabled || !to)
            return;
        if (from && Math.hypot(to.x - from.x, to.y - from.y) < 1)
            return;
        root.requested(from, to, style in BoltConfig.styles ? style : "popup");
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

    // ── Hyprland triggers ────────────────────────────────────────────────────
    function rect(parts, i) {
        return { x: Number(parts[i]), y: Number(parts[i + 1]), w: Number(parts[i + 2]), h: Number(parts[i + 3]) };
    }

    // Points just inside two rects along the line between their centers:
    // each one's edge facing the other, pulled `inset` of the way back
    // toward its center.
    function facingPoints(a, b, inset) {
        const ax = a.x + a.w / 2, ay = a.y + a.h / 2;
        const bx = b.x + b.w / 2, by = b.y + b.h / 2;
        const dx = bx - ax, dy = by - ay;
        if (Math.abs(dx) < 1 && Math.abs(dy) < 1)
            return null;
        const exitA = Math.min(a.w / 2 / Math.abs(dx), a.h / 2 / Math.abs(dy));
        const enterB = Math.min(b.w / 2 / Math.abs(dx), b.h / 2 / Math.abs(dy));
        // Overlapping (floating) windows - no gap to jump, go center to center.
        const ta = exitA + enterB < 1 ? exitA * (1 - inset) : 0;
        const tb = exitA + enterB < 1 ? enterB * (1 - inset) : 0;
        return [Qt.point(ax + dx * ta, ay + dy * ta), Qt.point(bx - dx * tb, by - dy * tb)];
    }

    function handleCustom(data) {
        const parts = data.split(" ");
        if (parts[0] === "bolt:focus" && parts.length >= 9) {
            if (!root.active("focus"))
                return;
            const pts = root.facingPoints(root.rect(parts, 1), root.rect(parts, 5), BoltConfig.focus.inset);
            if (pts)
                root.strike(pts[0], pts[1], "focus");
        } else if (parts[0] === "bolt:open" && parts.length >= 6) {
            if (!root.active("open"))
                return;
            const r = root.rect(parts, 1);
            const cls = parts.slice(5).join(" ");
            const app = BoltConfig.open.apps[cls];
            if ((!app && !BoltConfig.open.allApps) || r.w <= 0 || r.h <= 0)
                return;
            const from = root.takeOrigin() ?? root.resolveFrom(app?.from ?? BoltConfig.open.defaultFrom);
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
