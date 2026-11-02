import QtQuick

// Base of every spoke style. SpokeLayer loads spokes/<Name>.qml for
// KeytreeConfig.spokes.style "name" and points `host` at itself; a style
// reads everything it draws from through the properties below and fills
// its own bounds (the whole view).
//
// Adding a style:
//   - static: a CanvasSpokes with a painter function from a spokes/*.js
//     file (see CanvasSpokes.qml for the frame it gets).
//   - animated: a ShaderSpokes with a fragment shader from shaders/ (see
//     ShaderSpokes.qml). Canvas rasterizes on the CPU and re-uploads the
//     whole view every frame, so moving styles belong on the GPU.
//   - anything else (Shape, particles, ...): extend this directly.
Item {
    id: root

    property Item host: null

    // { nodes: [{ i, x, y, a, d, step, ring, isLeaf }], anchored? }. With
    // `anchored`, every node has its own origin (ox, oy) - its spoke runs
    // from there instead of from the view center, and a/d are measured
    // from it (HangView's strings). Otherwise nodes sit on rings around the
    // center (layouts/ring.js).
    readonly property var    layout:    host ? host.layout : ({ kind: "ring", nodes: [] })
    readonly property bool   anchored:  layout.anchored === true
    // 0..1 entrance progress shared by all spokes.
    readonly property real   reveal:    host ? host.reveal : 0
    readonly property color  color:     host ? host.color : "white"
    readonly property real   lineWidth: host ? host.lineWidth : 1
    readonly property real   gap:       host ? host.gap : 4
    // Spokes start on the hub circle and end at node centers.
    readonly property real   hubR:      host ? host.hubD / 2 : 0
    readonly property real   nodeR:     host ? host.nodeD / 2 : 0

    // How far outside the hub/node circles strokes are cut back. A style
    // that draws right up to the circles sets this just negative, so the
    // cut stays under the card borders.
    property real cutGap: gap

    // Something to draw and somewhere to show it - animated styles only
    // tick while this holds.
    readonly property bool shown: visible && reveal > 0 && (layout.nodes ?? []).length > 0
}
