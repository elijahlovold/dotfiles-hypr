import QtQuick

// Open L-shaped line brackets at each corner - Halo's "targeting reticle"
// frame motif, shared between PopupFrame.qml and Pill.qml (was two
// independently-drifting copies of the same 8 Rectangles before this was
// extracted). Deliberately just the four corner marks - callers add their
// own base fill/border and top accent rule around this, since those vary
// (PopupFrame draws a full accent-rule top edge; Pill's is thinner).
Item {
    id: root

    anchors.fill: parent
    property real bracketLen: 10
    property real bracketThick: 1.5
    property color markColor: "white"

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        width: root.bracketLen
        height: root.bracketThick
        color: root.markColor
    }
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        width: root.bracketThick
        height: root.bracketLen
        color: root.markColor
    }
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        width: root.bracketLen
        height: root.bracketThick
        color: root.markColor
    }
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        width: root.bracketThick
        height: root.bracketLen
        color: root.markColor
    }
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: root.bracketLen
        height: root.bracketThick
        color: root.markColor
    }
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: root.bracketThick
        height: root.bracketLen
        color: root.markColor
    }
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.bracketLen
        height: root.bracketThick
        color: root.markColor
    }
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.bracketThick
        height: root.bracketLen
        color: root.markColor
    }
}
