pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

// Free-text prompt for a node whose command has a `{{query}}` placeholder
// (see KeytreePanel.runPrompt). Same look as SearchView: the node's label
// as the title, one input line under it, and past entries that match
// (PromptHistory) listed below.
Item {
    id: root
    anchors.fill: parent

    property real fontScale: 1.0
    property string title: ""
    property string icon: ""
    property string text: ""
    property var suggestions: []
    property int selection: -1

    readonly property real rowH: 37

    Rectangle {
        id: panel
        // Top pinned a little above center, so the title and input stay
        // put while the list below grows and shrinks.
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height / 2 - 90)
        width: 420
        height: layout.implicitHeight + 24
        radius: 12
        color: Theme.searchBg
        border.color: Theme.searchBorder
        border.width: 1

        Column {
            id: layout
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 12
            }
            spacing: 8

            Text {
                width: parent.width
                text: (root.icon + root.title).trim()
                color: Theme.keyText
                font.pixelSize: Math.round(17 * root.fontScale)
                font.bold: true
                elide: Text.ElideRight
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.searchBorder
                opacity: 0.5
            }

            // Input line, scrolled so the cursor end stays in view.
            Item {
                width: parent.width
                height: Math.round(32 * root.fontScale)
                clip: true

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.min(0, parent.width - width - 4)
                    spacing: 2

                    Text {
                        text: root.text
                        color: "white"
                        font.pixelSize: Math.round(17 * root.fontScale)
                        font.family: "monospace"
                    }

                    Rectangle {
                        width: 2
                        height: Math.round(19 * root.fontScale)
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.keyText

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 500 }
                            NumberAnimation { to: 1; duration: 100 }
                        }
                    }
                }
            }

            Rectangle {
                visible: root.suggestions.length > 0
                width: parent.width
                height: 1
                color: Theme.searchBorder
                opacity: 0.5
            }

            Column {
                width: parent.width
                visible: root.suggestions.length > 0

                Repeater {
                    model: root.suggestions

                    delegate: Rectangle {
                        id: row
                        required property string modelData
                        required property int index
                        readonly property bool selected: row.index === root.selection

                        width: parent.width
                        height: root.rowH
                        radius: 5
                        color: row.selected ? Theme.searchSelection : "transparent"

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            text: row.modelData
                            color: row.selected ? "white" : Theme.searchText
                            font.pixelSize: Math.round(15 * root.fontScale)
                            font.family: "monospace"
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
