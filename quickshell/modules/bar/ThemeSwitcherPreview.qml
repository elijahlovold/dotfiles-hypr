pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.theme

// Dropdown list, opened from ThemeSwitcherWidget.qml. Reads
// ThemeManager.themes directly so adding a theme name there is the only
// change needed for it to show up here too.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    Item {
        id: card
        width: 160
        height: layout.implicitHeight + 20

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 20
            spacing: 4

            Repeater {
                model: ThemeManager.themes
                delegate: Rectangle {
                    id: row
                    required property string modelData
                    readonly property bool active: row.modelData === ThemeManager.activeTheme

                    width: layout.width
                    height: 26
                    radius: 5
                    color: row.active || rowMa.containsMouse ? Theme.hoverBg : "transparent"
                    border.width: row.active ? 1 : 0
                    border.color: Theme.accent

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData
                        color: row.active ? Theme.accent : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: row.active
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ThemeManager.setTheme(row.modelData);
                            popup.anchorItem.previewOpen = false;
                        }
                    }
                }
            }
        }
    }
}
