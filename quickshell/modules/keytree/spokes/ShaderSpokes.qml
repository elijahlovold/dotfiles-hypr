import QtQuick
import qs.modules.keytree.spokes

// An animated spoke style drawn by a fragment shader (shaders/, compiled
// with shaders/build.sh). The CPU side is only uniforms: the ring layouts
// are regular, so instead of a node list the shader gets each ring as
// (count, radius, angle of its first node) and finds the nearest spoke per
// pixel itself. `time` only advances `fps` times a second while shown,
// and the effect only re-renders when a uniform changes. Anchored layouts
// get one small effect per node instead, covering just its spoke, with
// that node as a one-node ring around its own origin.
//
// Uniform block every spoke shader declares (shaders/common.glsl):
//   vec2 size, origin (hub position in the item); vec4 color;
//   float time, reveal, lineWidth;
//   vec4 ring0, ring1;   count, radius, first angle, 0 (count 0 = unused)
//   vec4 radii;          hub radius, node radius, cut gap, -
SpokeStyle {
    id: root

    property url shader
    property int fps: 60

    // Per ring: node count, radius and the angle of its first node.
    function ring(k) {
        const nodes = (root.layout.nodes ?? []).filter(n => n.ring === k);
        return nodes.length === 0 ? Qt.vector4d(0, 0, 0, 0) : Qt.vector4d(nodes.length, nodes[0].d, nodes[0].a, 0);
    }

    property real time: 0

    FrameAnimation {
        running: root.shown && root.fps > 0
        onTriggered: {
            const t = Math.floor(elapsedTime * root.fps) / root.fps;
            if (t !== root.time)
                root.time = t;
        }
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: root.shown && !root.anchored
        fragmentShader: root.shader

        property vector2d size: Qt.vector2d(width, height)
        property vector2d origin: Qt.vector2d(width / 2, height / 2)
        property color color: root.color
        property real time: root.time
        property real reveal: Math.min(1, root.reveal)
        property real lineWidth: root.lineWidth
        property vector4d ring0: root.ring(0)
        property vector4d ring1: root.ring(1)
        property vector4d radii: Qt.vector4d(root.hubR, root.nodeR, root.cutGap, 0)
    }

    // Anchored: one effect per node, sized to the box around its spoke
    // (plus room for the style's sideways swing and the node itself).
    Repeater {
        model: root.anchored && root.shown ? (root.layout.nodes ?? []).length : 0

        ShaderEffect {
            required property int index
            readonly property var n: root.layout.nodes[index] ?? ({ x: 0, y: 0, ox: 0, oy: 0, a: 0, d: 0 })
            readonly property real margin: root.nodeR * 1.2

            x: Math.min(n.ox, n.x) - margin
            y: Math.min(n.oy, n.y) - margin
            width: Math.abs(n.x - n.ox) + 2 * margin
            height: Math.abs(n.y - n.oy) + 2 * margin
            fragmentShader: root.shader

            property vector2d size: Qt.vector2d(width, height)
            property vector2d origin: Qt.vector2d(n.ox - x, n.oy - y)
            property color color: root.color
            property real time: root.time
            property real reveal: Math.min(1, root.reveal)
            property real lineWidth: root.lineWidth
            property vector4d ring0: Qt.vector4d(1, n.d, n.a, 0)
            property vector4d ring1: Qt.vector4d(0, 0, 0, 0)
            property vector4d radii: Qt.vector4d(root.hubR, root.nodeR, root.cutGap, 0)
        }
    }
}
