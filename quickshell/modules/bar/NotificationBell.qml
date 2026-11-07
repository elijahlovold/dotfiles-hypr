pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common
import qs.modules.notifications

// Hover opens the inbox preview (missed/timed-out notifications, see
// NotificationsStore), left-click opens it floating; right-click clears it
// outright. Same opener-widget shape as Music.qml/Clock.qml.
Item {
    id: root

    readonly property string icon: String.fromCharCode(0xf0f3) // fa-bell
    property bool previewOpen: false

    implicitWidth: contentRow.width
    implicitHeight: contentRow.height
    width: implicitWidth
    height: implicitHeight

    Row {
        id: contentRow
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: NotificationsStore.inbox.length > 0
            text: NotificationsStore.inbox.length
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            font.bold: true
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
                NotificationsStore.clearInbox();
            else
                opener.toggleFloating();
        }
    }

    PopupOpener {
        id: opener
        widget: root
        name: "notifications"
        popup: NotificationInboxPreview {
            anchorItem: root
        }
    }
}
