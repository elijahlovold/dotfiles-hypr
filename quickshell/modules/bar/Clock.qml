pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.theme
import qs.modules.common

Item {
    id: root

    property bool full: true
    property bool previewOpen: false

    readonly property string clockIcon: String.fromCharCode(0xf017) // fa-clock-o
    readonly property string calendarIcon: String.fromCharCode(0xf073) // fa-calendar

    implicitWidth: contentRow.width
    implicitHeight: contentRow.height
    width: implicitWidth
    height: implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: contentRow
        spacing: 10

        Text {
            text: root.clockIcon + "  " + Qt.formatDateTime(clock.date, root.full ? "hh:mm" : "hh:mm | MM/dd/yy")
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Text {
            id: calendarText
            visible: root.full
            text: root.calendarIcon + "  " + Qt.formatDateTime(clock.date, "ddd, MM/dd/yy")
            color: Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize

            // Left-click opens today's daily note directly - same command
            // CalendarPreview.qml's openDailyNote() runs for a clicked day,
            // just always today's date instead of whichever cell was clicked.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const date = Qt.formatDateTime(clock.date, "yyyy-MM-dd");
                    Quickshell.execDetached(["alacritty", "-e", "sh", "-c", 'nvim "$(todays-notes "$1")"', "sh", date]);
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        hoverEnabled: true
        onClicked: opener.toggle()
    }

    PopupOpener {
        id: opener
        widget: root
        name: "calendar"
        popup: CalendarPreview {
            anchorItem: root
        }
    }
}
