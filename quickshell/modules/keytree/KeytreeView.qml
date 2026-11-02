import QtQuick

// Base of every keytree representation (RingView, HexView, HangView,
// BranchView). KeytreePanel owns navigation, input and launching; a view
// only shows the current level and animates between levels. The panel
// picks one by KeytreeConfig.layout.type and binds the inputs below.
//
// Adding a view: extend this, set the outputs, add it to the panel's
// `views` map.
Item {
    // ── Inputs (bound by KeytreePanel) ────────────────────────────────────
    // Current level: [{ key, label, icon, isLeaf, cmd, shiftCmd }].
    property var items: []
    // How this level was reached, set just before `items` changes:
    // { kind: "open" } | { kind: "enter", key } (the folder picked from the
    // previous level) | { kind: "back", key } (the folder just left).
    property var nav: ({ kind: "open", key: "" })
    property string centerLabel: ""
    property bool atRoot: true
    // Set when the panel is about to tear down: play the exit, then the
    // panel waits closeWaitMs before destroying the view.
    property bool closing: false
    property real fontScale: 1
    property real nodeScale: 1
    // KeytreeConfig.layout / .spokes.
    property var layoutConfig: ({})
    property var spokes: ({ style: "radial" })

    // ── Outputs ───────────────────────────────────────────────────────────
    // true: the view gets the whole screen; false: a centered square of
    // preferredSize px.
    property bool fullscreen: false
    property real preferredSize: 540
    // Whether the panel draws its frosted halo disc behind the view.
    property bool halo: false
    property int totalAnimMs: 300
    property int centerAnimDuration: 140
    property int closeWaitMs: 300
    // View-local point bolts treat as the hub.
    property point center: Qt.point(width / 2, height / 2)

    // Window-local center of the node for `key` where it is now, or null.
    function nodeCenter(key) {
        return null;
    }
    // View-local center of node `index` once its entrance finishes, or null.
    function nodeFinalCenter(index) {
        return null;
    }
    // Whether a click at view-local (x, y) is on the menu (else it closes).
    function menuContains(x, y) {
        return x >= 0 && y >= 0 && x <= width && y <= height;
    }
}
