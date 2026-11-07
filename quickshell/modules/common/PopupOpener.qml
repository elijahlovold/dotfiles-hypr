import QtQuick
import qs.modules.overlay

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
//       onPositionChanged: mouse => opener.hoverMoved(mapToItem(null, mouse.x, mouse.y))
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
        if (Overlays.hoverSuppressed?.widget === opener.widget)
            return;
        hoverOpenTimer.restart();
    }

    // Cursor moved over the widget, `pos` in screen coordinates (the
    // widget's MouseArea: mapToItem(null, mouse.x, mouse.y)).
    function hoverMoved(pos) {
        const s = Overlays.hoverSuppressed;
        if (s?.widget === opener.widget && Math.hypot(pos.x - s.pos.x, pos.y - s.pos.y) > 2)
            Overlays.hoverSuppressed = null;
    }

    function hoverExited() {
        hoverOpenTimer.stop();
        closeTimer.restart();
    }

    function toggle() {
        opener.widget.previewOpen = !opener.widget.previewOpen;
    }

    // Open as the centred floating window (see PillPopup), or close it if
    // it's already floating. A docked popup that's open from the hover is
    // reopened floating, the same hand-off as BarPopups.land().
    function toggleFloating() {
        const w = opener.widget;
        // The click usually lands within the hover dwell; don't let that
        // reopen it docked straight after.
        hoverOpenTimer.stop();
        closeTimer.stop();
        if (w.previewOpen && Overlays.isFloating(w)) {
            w.previewOpen = false;
            return;
        }
        if (w.previewOpen)
            w.previewOpen = false;
        Overlays.floatingAnchor = w;
        w.previewOpen = true;
    }

    // Short dwell so sweeping the cursor across the bar doesn't flash every
    // popup on the way past.
    Timer {
        id: hoverOpenTimer
        interval: 50
        onTriggered: {
            if (!opener.widget.previewOpen)
                opener.widget.previewOpen = true;
        }
    }

    // Grace period for crossing from the pill into the popup below it.
    Timer {
        id: closeTimer
        interval: 250
        onTriggered: {
            // Floating popups aren't hung from the pill, so leaving the
            // pill doesn't close them.
            if (!Overlays.isFloating(opener.widget) && !(loader.item?.hovered ?? false))
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
