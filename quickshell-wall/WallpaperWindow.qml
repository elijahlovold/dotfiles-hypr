pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// The wallpaper surface: two Slots, one on screen. A switch loads the other
// slot underneath/hidden; once its first frame is decoded the effect runs
// between the two live videos, then the old slot is unloaded. Nothing waits
// on a timer - each step is a player frame, a player error or the animation
// ending.
//
// The shaders are written as "take the image away" (progress 0 = intact,
// 1 = gone). Direction "in" draws the new slot on top through them, fed
// 1 - progress so they run backwards; "out" draws the old slot on top.
// Compile after editing a .frag, from shaders/, then restart this instance
// (Qt caches loaded shaders for the life of the process, reloads included):
//   /usr/lib/qt6/bin/qsb --qt6 -o shatter.frag.qsb shatter.frag
// All of them share one uniform block, so an effect is just a file.
PanelWindow {
    id: root

    // The video on screen (or loading as the first one).
    signal switched(string path)
    // A switch to path failed; the window stays on what it had.
    signal failed(string path)

    property Slot shown: slotA
    // The slot being transitioned to, or null.
    property Slot incoming: null
    // Latest switch asked for mid-transition; runs when this one ends.
    property var queued: null
    // WallConfig.effect, or what `ipc call wallpaper effect` set.
    required property string effectSetting
    // This transition's effect.
    property string effect: "fade"
    property point origin
    // 0 -> 1 over a transition.
    property real progress: 0

    readonly property bool transitioning: root.incoming !== null && root.incoming.ready
    readonly property Slot top: root.incoming === null ? null : WallConfig.direction === "in" ? root.incoming : root.shown
    readonly property bool covered: WallConfig.pauseOnFullscreen && (Hyprland.monitorFor(root.screen)?.activeWorkspace?.hasFullscreen ?? false)

    function switchTo(path, origin) {
        if (root.incoming) {
            root.queued = {
                path: path,
                origin: origin
            };
            return;
        }
        if (path === root.shown.path)
            return;
        // Nothing to transition from.
        if (!root.shown.path) {
            root.shown.load(path);
            return;
        }
        const fx = root.effectSetting;
        const all = WallConfig.effects;
        root.effect = fx === "random" ? all[Math.floor(Math.random() * all.length)] : fx;
        root.origin = root.localOrigin(origin);
        root.incoming = root.shown === slotA ? slotB : slotA;
        console.info("wallpaper: loading", path, "-", root.effect, "from", root.origin);
        root.incoming.load(path);
    }

    // Global "x,y" -> local to this screen; its center if missing or on
    // another screen (picker opened on the portrait monitor).
    function localOrigin(str) {
        const s = root.screen;
        const m = /^(-?[\d.]+),(-?[\d.]+)$/.exec(str ?? "");
        if (m) {
            const x = Number(m[1]) - s.x;
            const y = Number(m[2]) - s.y;
            if (x >= 0 && x < s.width && y >= 0 && y < s.height)
                return Qt.point(x, y);
        }
        return Qt.point(s.width / 2, s.height / 2);
    }

    function onSlotLoaded(slot) {
        if (slot === root.incoming) {
            root.switched(slot.path);
            anim.start();
        } else if (slot === root.shown) {
            root.switched(slot.path);
        }
    }

    function onSlotFailed(slot, reason) {
        const path = slot.path;
        console.warn("wallpaper: can't play", path, "-", reason);
        if (slot === root.incoming) {
            anim.stop();
            slot.unload();
            root.incoming = null;
            root.progress = 0;
            root.failed(path);
            root.dequeue();
        } else if (slot === root.shown) {
            // Nothing to stay on: black, and the next switch starts fresh.
            slot.unload();
            root.failed(path);
        }
    }

    function finish() {
        const old = root.shown;
        root.shown = root.incoming;
        root.incoming = null;
        old.unload();
        root.progress = 0;
        console.info("wallpaper: transition done");
        root.dequeue();
    }

    function dequeue() {
        if (root.queued) {
            const q = root.queued;
            root.queued = null;
            root.switchTo(q.path, q.origin);
        }
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "black"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell:wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    NumberAnimation {
        id: anim
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: WallConfig.durationMs
        // The shaders pace their own phases; only the fade wants easing.
        easing.type: root.effect === "fade" ? Easing.InOutQuad : Easing.Linear
        onFinished: root.finish()
    }

    component WallSlot: Slot {
        id: slot

        anchors.fill: parent
        // The incoming slot stays hidden until it has a frame to show.
        visible: slot === root.shown || (slot === root.incoming && slot.ready)
        z: root.transitioning && slot === root.top ? 1 : 0
        opacity: root.transitioning && slot === root.top && root.effect === "fade" ? (WallConfig.direction === "in" ? root.progress : 1 - root.progress) : 1
        paused: root.covered && slot === root.shown && root.incoming === null

        onLoaded: root.onSlotLoaded(slot)
        onFailed: reason => root.onSlotFailed(slot, reason)
    }

    WallSlot {
        id: slotA
    }

    WallSlot {
        id: slotB
    }

    ShaderEffectSource {
        id: topTex
        sourceItem: root.transitioning && root.effect !== "fade" ? root.top : null
        hideSource: true
    }

    ShaderEffect {
        anchors.fill: parent
        z: 2
        visible: topTex.sourceItem !== null

        property variant source: topTex
        property real progress: WallConfig.direction === "in" ? 1 - root.progress : root.progress
        property vector2d resolution: Qt.vector2d(width, height)
        property vector2d origin: Qt.vector2d(root.origin.x, root.origin.y)
        property real cellSize: height * WallConfig.cellSize
        property real seed: 0
        property color edgeColor: pal.color13

        fragmentShader: root.effect === "fade" ? "" : Qt.resolvedUrl("shaders/" + root.effect + ".frag.qsb")

        // A new shard/noise pattern per transition.
        onVisibleChanged: {
            if (visible)
                seed = Math.random() * 100;
        }
    }

    FileView {
        path: WallConfig.paletteFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: pal
            // The main shell's accent, used until wallust has written a palette.
            property color color13: "#4D88DD"
        }
    }
}
