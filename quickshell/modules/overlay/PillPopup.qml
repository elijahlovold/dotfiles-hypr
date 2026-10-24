pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.modules.theme

// Popup that grows out of the bottom of its Pill as one continuous shape -
// the pill's side walls flare out through concave fillets into the card
// below, no gap or second border:
//
//            ╭──────────╮          <- Pill (bar surface), bottom edge
//         ╭──╯          ╰───╮         dropped while expanded
//         │                 │      <- this popup (overlay host), drawn
//         ╰─────────────────╯         from y=0 = the pill's bottom edge
//
// The two halves live on different surfaces (bar window, OverlayHost), so
// the seam is made by geometry rather than one big shape: layout() places
// the frame at the pill's position - the bar and the host both sit at the
// screen's top-left, so bar coordinates are host coordinates - clamping and
// snapping x so the fillets line up with the pill walls. Pill.qml swaps to
// an open-bottomed outline while openPopups > 0, and both halves draw fill
// + 1px stroke the same way (QtQuick.Shapes, stroke centred on half-pixel
// lines) so the walls meet pixel-exactly.
//
// Usage - content sizes itself, the popup frames it:
//   PillPopup {
//       id: popup
//       anchorItem: root          // the widget inside the pill
//       cardWidth: card.width
//       cardHeight: card.height
//       Item { id: card; width: 300; height: layout.implicitHeight + 32; ... }
//   }
// Owning widgets open it through a PopupOpener (bar/PopupOpener.qml).
//
// Keyboard: the popup becomes the modal OverlaySurface (Exclusive keyboard
// focus) when it's opened from the keyboard (BarPopups / Super+P) or clicked
// anywhere inside. While focused it stays open regardless of hover; Escape,
// a click outside it, or another surface taking the keyboard closes it, and
// Hyprland hands focus back to the previous window by itself. Keys go
// through VimKeys and arrive as
//   onVimAction: (name, count) => { ... }   // "down", "top", "select", ...
// TextInputs that want to keep some keys for navigation can forward them
// with popup.handleKey(event).
OverlaySurface {
    id: popup

    required property Item anchorItem
    property real cardWidth: 0
    property real cardHeight: 0
    default property alias content: body.data

    // "Keep me open" for the owning widget's hover-close timer - also true
    // while the popup holds the keyboard.
    readonly property bool hovered: hoverHandler.hovered || popup.keyboardActive

    property bool keyboardActive: false
    signal vimAction(string name, int count)
    signal keyboardActivated

    screenName: popup.anchorItem.QsWindow.window?.screen?.name ?? ""
    fill: false
    modal: popup.keyboardActive
    inputItem: popup
    width: popup.frameWidth
    height: popup.frameHeight

    function close() {
        if (popup.anchorItem && popup.anchorItem.previewOpen !== undefined)
            popup.anchorItem.previewOpen = false;
    }

    function dismiss() {
        popup.close();
    }

    // Run `command` (an execDetached argv) in place of the popup, e.g. a
    // terminal - closing first drops the keyboard, so the new window gets
    // focus when it maps.
    function launch(command) {
        popup.close();
        Quickshell.execDetached(command);
    }

    function activateKeyboard() {
        if (!popup.keyboardActive) {
            popup.keyboardActive = true;
            popup.keyboardActivated();
        } else if (!popup.activeFocus) {
            // Hand keys back to the scope (e.g. after a TextInput let go).
            popup.forceActiveFocus();
        }
    }

    function handleKey(event) {
        event.accepted = vim.feed(event);
    }

    Keys.onPressed: event => popup.handleKey(event)

    VimKeys {
        id: vim
        onAction: (name, count) => {
            if (name === "escape")
                popup.close();
            else
                popup.vimAction(name, count);
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

    // Written by layout(): tab edges relative to the frame, and whether a
    // side runs straight down (no room for a fillet, e.g. the rightmost pill
    // against the screen edge).
    property real tabLeft: 0
    property real tabRight: 0
    property bool flushLeft: false
    property bool flushRight: false

    function layout() {
        if (!popup.pill)
            return;
        const pos = popup.pill.mapToItem(null, 0, 0);
        const winW = popup.host?.screen?.width ?? popup.pill.Window.width;
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
        popup.tabLeft = tabL - x;
        popup.tabRight = tabR - x;
        popup.x = x;
        popup.y = pos.y + popup.pill.height;
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

    // mapToItem() isn't reactive - re-place whenever the pill moves or
    // resizes underneath an open popup (e.g. a neighbouring widget's text
    // changing width), or the frame changes size.
    onHostChanged: popup.layout()
    onFrameWidthChanged: popup.layout()
    Connections {
        target: popup.pill
        function onWidthChanged() {
            popup.layout();
        }
        function onXChanged() {
            popup.layout();
        }
    }
    Connections {
        target: popup.pill?.parent ?? null
        function onXChanged() {
            popup.layout();
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
    function takeSummon() {
        if (!(popup.pill?.summoned ?? false))
            return;
        popup.pill.summoned = false;
        popup.activateKeyboard();
    }
    Connections {
        target: popup.pill
        ignoreUnknownSignals: true // no pill -> anchorItem has no `summoned`
        function onSummonedChanged() {
            popup.takeSummon();
        }
    }

    // Hangs from the bar, so it goes when the bar does (Super+Ctrl+Space).
    readonly property bool barShown: popup.anchorItem.QsWindow.window?.visible ?? true
    onBarShownChanged: {
        if (!popup.barShown)
            popup.close();
    }

    // Popups that show late (SysMonPreview waits for its disk list) still
    // get the drop-down instead of having finished it while hidden.
    onVisibleChanged: {
        if (popup.visible)
            revealAnim.restart();
    }

    Item {
        id: frame
        width: popup.frameWidth
        height: popup.frameHeight

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
        // pointer sits perfectly still. Taking Exclusive focus mid-click
        // would make Hyprland release the button under the control.
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
