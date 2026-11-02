import QtQuick
import qs.modules.theme

// The round node card every circle-based view shows: key (with icon) and
// label, styled as an app (leaf) or a folder; `hub` turns it into the
// labeled folder card at the center of a level. `plain` drops the circle
// so another shape (HexView's tiles) can carry the same text.
Item {
    id: root

    property var item: ({ key: "", label: "", icon: "", isLeaf: true })
    property real fontScale: 1
    property real nodeScale: 1
    property bool hub: false
    property string hubLabel: ""
    property bool plain: false

    Rectangle {
        visible: !root.plain
        anchors.fill: parent
        radius: width / 2
        color: root.hub || !root.item.isLeaf ? Theme.groupBg : Theme.leafBg
        border.color: root.hub ? Theme.centerDot : root.item.isLeaf ? Theme.leafBorder : Theme.groupBorder
        border.width: root.item.isLeaf && !root.hub ? 2 : 1
    }

    Text {
        visible: root.hub
        anchors.centerIn: parent
        width: parent.width - 8
        text: root.hubLabel
        color: Theme.labelText
        font.pixelSize: Math.round(14 * root.fontScale)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    Column {
        visible: !root.hub
        anchors.centerIn: parent
        spacing: 3

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3

            Text {
                visible: (root.item.icon ?? "").length > 0
                text: root.item.icon ?? ""
                color: Theme.keyText
                font.pixelSize: Math.round(20 * root.fontScale)
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.item.key
                color: Theme.keyText
                font.pixelSize: Math.round(25 * root.fontScale)
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.item.label
            color: Theme.labelText
            font.pixelSize: Math.round(13 * root.fontScale)
            width: Math.round(88 * root.nodeScale)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
