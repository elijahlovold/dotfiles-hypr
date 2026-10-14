pragma Singleton
import QtQuick
import Quickshell

// Every lightning-bolt knob in one place. Saving this file hot-reloads
// quickshell, so toggles take effect immediately. `qs ipc call bolt toggle`
// flips `enabled` at runtime too, without editing the file (resets on reload).
//
// Triggers (all event-driven - nothing here polls):
//   popup  - keyboard-opened bar popups (BarPopups.summon). From the keytree
//            node that was picked if there is one, else the bottom edge.
//   focus  - Super+hjkl/arrows/Tab/O focus moves. The Hyprland Lua bind
//            (hypr/hyprland/bolt.lua) sends both windows' geometry as a
//            custom socket2 event, so no process is spawned per keypress.
//   open   - new windows (Hyprland's window.open, same Lua route). Only the
//            classes in `open.apps` unless `open.allApps` is set.
Singleton {
    id: root

    // Master switch. When off, nothing is drawn and bar popups open
    // instantly instead of waiting for the bolt to land.
    readonly property bool enabled: true

    readonly property var popup: ({
        enabled: true
    })

    readonly property var focus: ({
        enabled: true,
        // Each end lands at a random point on the window edge facing the
        // other window. maxInset caps how far inside the window it may
        // sit (fraction of the window's size along the jump - 0.125 = at
        // most 1/8 in); edgeBias > 1 skews that toward the edge itself
        // (depth = maxInset * random^edgeBias).
        maxInset: 0.125,
        edgeBias: 2,
        // Steepest the bolt may run when the windows line up: the offset
        // along the edges stays within maxSlope x the distance across the
        // gap (1.0 = never steeper than 45 degrees).
        maxSlope: 1.0
    })

    // Wallpaper picker: jumps from the old selection to the new one, placed
    // like focus jumps (same meaning for maxInset/edgeBias/maxSlope).
    readonly property var picker: ({
        enabled: true,
        maxInset: 0.125,
        edgeBias: 2,
        maxSlope: 1.0
    })

    // Bolts inside the keytree menu itself (drawn in its own window).
    readonly property var keytree: ({
        enabled: true,
        swirl: true,       // on open: spiral out from the center onto a random node
        swirlTurns: 1.5,
        enter: true,       // opening a submenu: center -> the picked node
        back: true         // going back up: a random node -> center
    })

    readonly property var open: ({
        enabled: true,
        allApps: false,
        // Any window that opens within originMaxAgeMs of a keytree launch
        // gets a bolt from that node, whatever its class.
        fromKeytree: true,
        // Where a bolt comes from when no keytree node launched the app:
        //   "edge"          - random point on the bottom edge
        //   "anchor:<name>" - a BoltAnchor { name: ... } in the bar
        defaultFrom: "edge",
        // Window class -> { from } (from: same values as defaultFrom).
        apps: {
            "btop": { from: "anchor:cpu" }
        }
    })

    // How long a keytree node stays the origin for the next strike. Covers
    // slow-starting apps; popups consume it straight away.
    readonly property int originMaxAgeMs: 3000

    // Keep the overlay surface alive this long after a strike so rapid
    // follow-ups (holding focus keys) reuse it instead of recreating a
    // fullscreen layer every time.
    readonly property int lingerMs: 800

    // Look + timing per trigger.
    //   totalMs   - whole strike, including the flicker-out after landing
    //   travelMs  - time to reach the target (bar popups open on impact)
    //   levels    - midpoint-displacement subdivisions (2^levels segments)
    //   spread    - sideways displacement, as a fraction of bolt length
    //   spreadJitter - per-strike random +/- on spread (0.4 = 60%..140%)
    //   forks     - [min, max] branch count
    //   width     - stroke width multiplier
    //   opacity   - overall opacity
    //   flash     - impact flash radius in px (0 = none)
    //   tail      - draw only this fraction of the path behind the head
    //               while travelling (comet look; 0/absent = whole channel)
    // For waypoint paths (the keytree swirl) `levels` is per leg.
    readonly property var styles: ({
        popup: { totalMs: 320, travelMs: 90, levels: 6, spread: 0.16, forks: [2, 3], width: 1.0, opacity: 1.0, flash: 40 },
        focus: { totalMs: 190, travelMs: 60, levels: 4, spread: 0.12, spreadJitter: 0.5, forks: [0, 1], width: 0.55, opacity: 0.75, flash: 14 },
        open:  { totalMs: 360, travelMs: 110, levels: 6, spread: 0.14, forks: [1, 3], width: 0.8, opacity: 0.9, flash: 56 },
        swirl: { totalMs: 520, travelMs: 380, levels: 2, spread: 0.45, spreadJitter: 0.3, forks: [0, 0], width: 0.7, opacity: 0.9, flash: 34, tail: 0.3 },
        picker: { totalMs: 190, travelMs: 60, levels: 4, spread: 0.12, spreadJitter: 0.5, forks: [0, 1], width: 0.55, opacity: 0.85, flash: 14 },
        keytree: { totalMs: 230, travelMs: 70, levels: 4, spread: 0.16, spreadJitter: 0.5, forks: [0, 1], width: 0.6, opacity: 0.85, flash: 22 }
    })
}
