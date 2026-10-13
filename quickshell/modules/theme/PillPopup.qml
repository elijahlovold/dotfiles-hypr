pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import qs.modules.theme

// Popup that grows out of the bottom of its Pill as one continuous shape -
// the pill's side walls flare out through concave fillets into the card
// below, no gap or second border:
//
//            ╭──────────╮          <- Pill (bar surface), bottom edge
//         ╭──╯          ╰───╮         dropped while expanded
//         │                 │      <- this popup (own surface), drawn
//         ╰─────────────────╯         from y=0 = the pill's bottom edge
//
// The two halves live on different Wayland surfaces, so the seam is made
// by geometry rather than one big shape: the popup is placed with
// adjustment None (the compositor must not slide it, or the fillets would
// stop lining up with the pill walls) and its x is clamped/snapped here
// instead. Pill.qml swaps to an open-bottomed outline while openPopups > 0,
// and both halves draw fill + 1px stroke the same way (QtQuick.Shapes,
// stroke centred on half-pixel lines) so the walls meet pixel-exactly.
//
// Usage - content sizes itself, the popup frames it:
//   PillPopup {
//       id: popup
//       anchorItem: root          // the widget inside the pill
//       cardWidth: card.width
//       cardHeight: card.height
//       Item { id: card; width: 300; height: layout.implicitHeight + 32; ... }
//   }
//
// Keyboard: the popup takes keyboard focus (HyprlandFocusGrab) when it is
// opened from the keyboard (BarPopups / Super+P) or clicked anywhere
// inside. While focused it stays open regardless of hover; Escape, or a
// click outside it, closes it. Keys go through VimKeys and arrive as
//   onVimAction: (name, count) => { ... }   // "down", "top", "select", ...
// TextInputs that want to keep some keys for navigation can forward them
// with popup.handleKey(event).
PopupWindow {
    id: popup

    required property Item anchorItem
    property real cardWidth: 0
    property real cardHeight: 0
    default property alias content: body.data

    // "Keep me open" for the owning widget's hover-close timer - also true
    // while the popup holds keyboard focus.
    readonly property bool hovered: hoverHandler.hovered || popup.keyboardActive

    property bool keyboardActive: false
    signal vimAction(string name, int count)
    signal keyboardActivated

    // Window that had focus before this popup took the keyboard - handed
    // back on Escape. Not on a click outside (the click already chose where
    // focus goes), and not when an action launches its own window (pass
    // restoreFocus = false, e.g. Calendar opening a note in a new terminal -
    // Hyprland focuses that window when it maps).
    property string restoreAddress: ""
    property bool closing: false

    function close(restoreFocus) {
        if (popup.closing)
            return;
        popup.closing = true;
        if (restoreFocus !== false && popup.keyboardActive && popup.restoreAddress.length > 0)
            popup.refocus(popup.restoreAddress);
        popup.keyboardActive = false;
        if (popup.anchorItem && popup.anchorItem.previewOpen !== undefined)
            popup.anchorItem.previewOpen = false;
    }

    // Detached + short delay: the popup (and its focus grab) is torn down
    // right after this, and the refocus has to land after the grab release
    // or Hyprland drops focus again. The process outlives the popup.
    function refocus(address) {
        const addr = address.startsWith("0x") ? address : "0x" + address;
        Quickshell.execDetached(["sh", "-c", 'sleep 0.05; hyprctl dispatch "$1"', "sh",
            `hl.dsp.focus({ window = "address:${addr}" })`]);
    }

    function activateKeyboard() {
        if (popup.closing)
            return;
        if (!popup.keyboardActive) {
            popup.restoreAddress = Hyprland.activeToplevel?.address ?? "";
            popup.keyboardActive = true;
            popup.keyboardActivated();
        }
        // A FocusScope keeps its own focused child (e.g. a clicked
        // TextInput), so this only lands on the scope itself when nothing
        // inside has asked for focus yet.
        if (!frame.activeFocus)
            frame.forceActiveFocus();
    }

    function handleKey(event) {
        event.accepted = vim.feed(event);
    }

    VimKeys {
        id: vim
        onAction: (name, count) => {
            if (name === "escape")
                popup.close();
            else
                popup.vimAction(name, count);
        }
    }

    // Wayland only hands a popup surface the keyboard through a grab;
    // Hyprland's focus grab can be taken after mapping (unlike an xdg_popup
    // grab) and is cleared by a click anywhere outside the listed windows.
    HyprlandFocusGrab {
        windows: [popup]
        active: popup.keyboardActive && popup.visible
        onCleared: {
            if (popup.keyboardActive)
                popup.close(false);
        }
    }

    // The enclosing Pill (see bar/Pill.qml's isPill) - the "tab" the card hangs
    // from. Falls back to the widget itself outside a pill.
    readonly property Item pill: {
        for (let p = popup.anchorItem; p; p = p.parent)
            if (p.isPill === true)
                return p;
        return popup.anchorItem;
    }

    readonly property real fillet: 8
    readonly property real cornerRadius: 8
    readonly property real screenMargin: 4
    // Card top edge sits one fillet below the pill; +0.5 puts its stroke on
    // a pixel centre (see buildPath).
    readonly property real neck: popup.fillet + 0.5
    // Always wide enough for a fillet + corner on both sides of the tab.
    readonly property real frameWidth: Math.max(popup.cardWidth, (popup.pill?.width ?? 0) + 2 * (popup.fillet + popup.cornerRadius + 1))
    readonly property real frameHeight: popup.neck + popup.cardHeight

    // Written by layout(): frame x relative to the pill, tab edges relative
    // to the frame, and whether a side runs straight down (no room for a
    // fillet, e.g. the rightmost pill against the screen edge).
    property real frameX: 0
    property real tabLeft: 0
    property real tabRight: 0
    property bool flushLeft: false
    property bool flushRight: false

    function layout() {
        if (!popup.pill)
            return;
        const pos = popup.pill.mapToItem(null, 0, 0);
        const winW = popup.pill.Window.width;
        const tabL = pos.x;
        const tabR = pos.x + popup.pill.width;
        const w = popup.frameWidth;
        // +1: the fillet ends on a .5 line, needs a hair of straight edge.
        const need = popup.fillet + popup.cornerRadius + 1;

        let x = (tabL + tabR - w) / 2;
        x = Math.max(popup.screenMargin, Math.min(x, winW - popup.screenMargin - w));
        if (tabL - x < need)
            x = tabL;
        if (x + w - tabR < need)
            x = tabR - w;

        popup.flushLeft = Math.abs(x - tabL) < 0.01;
        popup.flushRight = Math.abs(x + w - tabR) < 0.01;
        popup.frameX = x - pos.x;
        popup.tabLeft = tabL - x;
        popup.tabRight = tabR - x;
    }

    // Outline in frame coordinates, counter-clockwise from the tab's left
    // wall. Strokes are 1px centred on .5 lines so they cover exactly the
    // pixel column/row the pill's own border uses. Convex corners sweep 0,
    // the concave fillets sweep 1. `closed` adds the (unstroked) top edge
    // along the pill's bottom for the fill.
    function buildPath(h, closed) {
        const W = popup.frameWidth, r = popup.neck, R = popup.cornerRadius;
        const left = 0.5, right = W - 0.5, bottom = h - 0.5;
        const tl = popup.tabLeft + 0.5, tr = popup.tabRight - 0.5;
        let d;
        if (popup.flushLeft)
            d = `M ${left} 0 L ${left} ${bottom - R}`;
        else
            d = `M ${tl} 0 A ${r} ${r} 0 0 1 ${tl - r} ${r} L ${left + R} ${r} A ${R} ${R} 0 0 0 ${left} ${r + R} L ${left} ${bottom - R}`;
        d += ` A ${R} ${R} 0 0 0 ${left + R} ${bottom} L ${right - R} ${bottom} A ${R} ${R} 0 0 0 ${right} ${bottom - R}`;
        if (popup.flushRight)
            d += ` L ${right} 0`;
        else
            d += ` L ${right} ${r + R} A ${R} ${R} 0 0 0 ${right - R} ${r} L ${tr + r} ${r} A ${r} ${r} 0 0 1 ${tr} 0`;
        return closed ? d + " Z" : d;
    }

    anchor {
        item: popup.pill
        rect.x: popup.frameX
        rect.y: popup.pill?.height ?? 0
        rect.width: 1
        rect.height: 1
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        adjustment: PopupAdjustment.None
        // mapToItem() isn't reactive - recompute right before every
        // placement (Quickshell's documented hook for exactly this).
        onAnchoring: popup.layout()
    }

    // Re-place if the pill moves/resizes underneath an open popup (e.g. a
    // neighbouring widget's text changing width).
    Connections {
        target: popup.pill
        function onWidthChanged() {
            popup.anchor.updateAnchor();
        }
        function onXChanged() {
            popup.anchor.updateAnchor();
        }
    }
    Connections {
        target: popup.pill?.parent ?? null
        function onXChanged() {
            popup.anchor.updateAnchor();
        }
    }

    Component.onCompleted: {
        if (popup.pill?.isPill)
            popup.pill.openPopups++;
        popup.takeSummon();
    }
    Component.onDestruction: {
        if (popup.pill?.isPill) {
            popup.pill.openPopups = Math.max(0, popup.pill.openPopups - 1);
            popup.pill.summoned = false;
        }
    }

    // Opened from the keyboard (BarPopups / Super+P) -> take focus straight
    // away; the flag is consumed so a later hover-open doesn't grab focus.
    readonly property bool summoned: popup.pill?.summoned ?? false
    function takeSummon() {
        if (!popup.summoned)
            return;
        popup.pill.summoned = false;
        popup.activateKeyboard();
    }
    onSummonedChanged: popup.takeSummon()

    visible: true
    // Popups that map late (StatorPreview waits for its content) still
    // get the drop-down instead of having finished it while hidden.
    onVisibleChanged: {
        if (popup.visible)
            revealAnim.restart();
    }
    implicitWidth: popup.frameWidth
    implicitHeight: popup.frameHeight
    color: "transparent"

    FocusScope {
        id: frame
        width: popup.frameWidth
        height: popup.frameHeight

        // Keys bubble here from whatever inside has focus (or arrive
        // directly when nothing more specific does).
        Keys.onPressed: event => popup.handleKey(event)

        // 0 -> 1 on open: the card drops down out of the pill.
        property real reveal: 0
        NumberAnimation on reveal {
            id: revealAnim
            from: 0
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
        readonly property real minHeight: popup.neck + 2 * popup.cornerRadius + 1
        readonly property real drawnHeight: frame.minHeight + Math.max(0, popup.frameHeight - frame.minHeight) * frame.reveal

        HoverHandler {
            id: hoverHandler
            onPointChanged: {
                if (frame.clickArmed && point.pressedButtons === 0)
                    frame.takeClickFocus();
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: Theme.pillBg
                PathSvg {
                    path: popup.buildPath(frame.drawnHeight, true)
                }
            }
            ShapePath {
                strokeWidth: 1
                strokeColor: Theme.pillBorder
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathSvg {
                    path: popup.buildPath(frame.drawnHeight, false)
                }
            }
        }

        Item {
            x: (popup.frameWidth - popup.cardWidth) / 2
            y: popup.neck
            width: popup.cardWidth
            height: Math.max(0, frame.drawnHeight - popup.neck)
            clip: frame.reveal < 1
            opacity: frame.reveal

            Item {
                id: body
                width: popup.cardWidth
                height: popup.cardHeight
            }
        }

        // Click anywhere inside -> take keyboard focus.
        //
        // Pointer mechanics (verified with qmltestrunner): a TapHandler in an
        // overlay on top of the content takes the press and the MouseArea
        // underneath never gets its click, and a handler on this parent never
        // even sees presses that a child MouseArea accepts. So: an overlay
        // MouseArea that notes the press and then *declines* it
        // (accepted = false) - the press, hover, wheel and drags all continue
        // to the real control underneath. It never sees the release, so
        // focus is taken when the HoverHandler reports the next pointer
        // update with no buttons held, or 400ms after the press if the
        // pointer sits perfectly still - keeping the grab off the middle of
        // an ordinary click.
        property bool clickArmed: false

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => {
                frame.clickArmed = true;
                clickFallback.restart();
                mouse.accepted = false;
            }
        }
        Timer {
            id: clickFallback
            interval: 400
            onTriggered: frame.takeClickFocus()
        }
        function takeClickFocus() {
            if (!frame.clickArmed)
                return;
            frame.clickArmed = false;
            clickFallback.stop();
            popup.activateKeyboard();
        }
    }
}
