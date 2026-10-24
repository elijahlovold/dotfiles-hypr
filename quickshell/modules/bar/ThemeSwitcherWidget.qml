pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

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
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onClicked: opener.toggle()
    }

    PopupOpener {
        id: opener
        widget: root
        name: "theme"
        popup: ThemeSwitcherPreview {
            anchorItem: root
        }
    }
}
