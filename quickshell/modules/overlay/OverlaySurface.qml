import QtQuick
import Quickshell

// Base for everything shown in an OverlayHost (see Overlays.qml): create it
// anywhere - usually from a Loader in the module that owns it - and it moves
// itself into the host window of `screenName` when it completes.
//
//   OverlaySurface {
//       modal: true              // hold the keyboard while open
//       inputItem: card          // pointer input while not modal
//       onDismissed: owner.open = false
//   }
//
// While `modal`, the host takes Exclusive keyboard focus and the whole
// screen's input; this item gets active focus, a press outside every
// surface calls dismiss(), and so does another surface claiming the
// keyboard. Override dismiss() to add a closing animation; it must end up
// destroying the surface or clearing `modal`.
FocusScope {
    id: surface

    // Screen to show on. Empty = the focused monitor at creation.
    property string screenName: ""
    property bool modal: false
    // The surface's own area: its pointer input while not modal, and where
    // presses no control took are swallowed instead of counting as outside
    // while modal. The surface itself or a direct child (null = none).
    property Item inputItem: null
    // Fill the host's screen (panels) instead of placing itself (popups).
    property bool fill: true

    property QtObject host: null // OverlayHost window
    readonly property ShellScreen screen: surface.host?.screen ?? null

    // Movable with Super+drag (OverlayHost routes the cursor samples):
    // once moved it keeps its place instead of being laid out again.
    property bool draggable: false
    property bool moved: false
    property point dragOffset

    signal dismissed

    // `p` in host coordinates. False if it isn't a grab on this surface.
    function dragStart(p) {
        if (!surface.draggable || p.x < surface.x || p.y < surface.y || p.x > surface.x + surface.width || p.y > surface.y + surface.height)
            return false;
        surface.dragOffset = Qt.point(p.x - surface.x, p.y - surface.y);
        return true;
    }

    function dragMove(p) {
        const pw = surface.parent?.width ?? 0, ph = surface.parent?.height ?? 0;
        surface.moved = true;
        surface.x = Math.max(0, Math.min(p.x - surface.dragOffset.x, pw - surface.width));
        surface.y = Math.max(0, Math.min(p.y - surface.dragOffset.y, ph - surface.height));
    }

    function dismiss() {
        surface.dismissed();
    }

    readonly property Region inputRegion: Region {
        item: surface.visible && !surface.modal ? surface.inputItem : null
    }

    anchors.fill: surface.fill ? parent : undefined

    // First child, so below everything a derived surface declares.
    MouseArea {
        readonly property Item target: surface.inputItem
        x: !target || target === surface ? 0 : target.x
        y: !target || target === surface ? 0 : target.y
        width: target?.width ?? 0
        height: target?.height ?? 0
        enabled: target !== null
        acceptedButtons: Qt.AllButtons
    }

    function syncModal() {
        if (!surface.host)
            return;
        if (surface.modal) {
            Overlays.claim(surface);
            surface.forceActiveFocus();
        } else {
            Overlays.release(surface);
        }
    }

    onModalChanged: surface.syncModal()

    Component.onCompleted: {
        surface.host = Overlays.hostFor(surface.screenName || Overlays.focusedScreenName());
        if (!surface.host)
            return;
        surface.screenName = surface.host.screenName;
        surface.host.attach(surface);
        surface.syncModal();
    }

    Component.onDestruction: {
        Overlays.release(surface);
        surface.host?.detach(surface);
    }
}
