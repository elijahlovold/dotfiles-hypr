import QtQuick
import qs.modules.keytree.spokes

// Re-struck 14 times a second; nothing in between needs a frame.
ShaderSpokes {
    shader: Qt.resolvedUrl("shaders/tesla.frag.qsb")
    fps: 14
}
