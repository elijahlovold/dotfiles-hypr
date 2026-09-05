pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

// Bar button + dropdown for ThemeManager's structural theme (Minimal/
// Cyber/Glass - shapes/motion, not the wallust palette). Same click-toggle-
// popup shape as ColorPicker.qml/UnitTools.qml. Distinct from
// ThemeSwitcher.qml, which is the IPC entry point (`qs ipc call theme
// set/next/list`) - this is just another way to reach ThemeManager.setTheme.
Item {
    id: root

    readonly property string icon: String.fromCharCode(0xf042) // fa-adjust
    property bool previewOpen: false

    implicitWidth: label.width
    implicitHeight: label.height
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label
        text: root.icon + "  " + ThemeManager.activeTheme
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: closeTimer.stop()
        onExited: closeTimer.restart()
        onClicked: root.previewOpen = !root.previewOpen
    }

    Timer {
        id: closeTimer
        interval: 250
        onTriggered: {
            if (!(previewLoader.item?.hovered ?? false))
                root.previewOpen = false;
        }
    }

    Loader {
        id: previewLoader
        active: root.previewOpen
        sourceComponent: ThemeSwitcherPreview {
            anchorItem: root
        }
    }

    Connections {
        target: previewLoader.item
        function onHoveredChanged() {
            if (previewLoader.item.hovered)
                closeTimer.stop();
            else
                closeTimer.restart();
        }
    }
}
