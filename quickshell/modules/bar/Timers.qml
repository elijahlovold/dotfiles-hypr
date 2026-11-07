pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// Countdown timers (TimersState). Shows the soonest running one's time
// left, plus how many more there are; dimmed while every timer is paused.
// Hover or right-click opens TimersPreview (left-click: floating) to start,
// pause and cancel them.
Item {
    id: root

    readonly property string icon: String.fromCharCode(0xf252) // fa-hourglass-half
    property bool previewOpen: false

    readonly property var soonest: TimersState.soonest
    readonly property int count: TimersState.timers.length

    implicitWidth: contentRow.width
    implicitHeight: contentRow.height
    width: implicitWidth
    height: implicitHeight

    Row {
        id: contentRow
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.soonest ? Theme.accent : root.count > 0 ? Theme.dimText : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Text {
            visible: root.count > 0
            anchors.verticalCenter: parent.verticalCenter
            text: (root.soonest ? TimersState.format(TimersState.remaining(root.soonest)) : "paused") + (root.count > 1 ? " +" + (root.count - 1) : "")
            color: root.soonest ? Theme.text : Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onPositionChanged: mouse => opener.hoverMoved(mapToItem(null, mouse.x, mouse.y))
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                opener.toggle();
            else
                opener.toggleFloating();
        }
    }

    PopupOpener {
        id: opener
        widget: root
        name: "timers"
        popup: TimersPreview {
            anchorItem: root
        }
    }
}
