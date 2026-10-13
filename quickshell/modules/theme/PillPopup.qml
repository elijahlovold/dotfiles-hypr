pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell

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
PopupWindow {
    id: popup

    required property Item anchorItem
    property real cardWidth: 0
    property real cardHeight: 0
    default property alias content: body.data

    readonly property alias hovered: hoverHandler.hovered

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
    }
    Component.onDestruction: {
        if (popup.pill?.isPill)
            popup.pill.openPopups = Math.max(0, popup.pill.openPopups - 1);
    }

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
    }
}
