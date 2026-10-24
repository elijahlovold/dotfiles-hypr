import QtQuick

// Opens and closes a bar widget's PillPopup (overlay/PillPopup.qml) - the
// hover/click/keyboard plumbing every popup-owning widget shares. The widget
// keeps its own MouseArea (buttons and clicks differ per widget) and
// forwards hover:
//
//   property bool previewOpen: false
//   MouseArea {
//       hoverEnabled: true
//       onEntered: opener.hoverEntered()
//       onExited: opener.hoverExited()
//       onClicked: opener.toggle()
//   }
//   PopupOpener {
//       id: opener
//       widget: root
//       name: "sound"           // keyboard/IPC: qs ipc call barpopup open sound
//       popup: SoundPreview {
//           anchorItem: root
//       }
//   }
//
// The popup is created fresh on every open (nothing it samples runs while
// closed) and destroyed on close; `widget.previewOpen` is the open state,
// which PillPopup.close() and BarPopups also write.
Item {
    id: opener

    required property Item widget
    // PopupTarget name; empty = not openable from the keyboard.
    property string name: ""
    property Component popup
    // Extra condition for the popup to exist (e.g. a player to show).
    property bool available: true

    visible: false

    function hoverEntered() {
        closeTimer.stop();
        hoverOpenTimer.restart();
    }

    function hoverExited() {
        hoverOpenTimer.stop();
        closeTimer.restart();
    }

    function toggle() {
        opener.widget.previewOpen = !opener.widget.previewOpen;
    }

    // Short dwell so sweeping the cursor across the bar doesn't flash every
    // popup on the way past.
    Timer {
        id: hoverOpenTimer
        interval: 50
        onTriggered: opener.widget.previewOpen = true
    }

    // Grace period for crossing from the pill into the popup below it.
    Timer {
        id: closeTimer
        interval: 250
        onTriggered: {
            if (!(loader.item?.hovered ?? false))
                opener.widget.previewOpen = false;
        }
    }

    PopupTarget {
        name: opener.name
        widget: opener.widget
    }

    Loader {
        id: loader
        active: opener.widget.previewOpen && opener.available
        sourceComponent: opener.popup
    }

    Connections {
        target: loader.item
        function onHoveredChanged() {
            if (loader.item.hovered)
                closeTimer.stop();
            else
                closeTimer.restart();
        }
    }
}
