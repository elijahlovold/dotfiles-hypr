import QtQuick
import qs.modules.theme

// Shared themed replacement for the `Rectangle { id: card; radius: 8;
// color: Theme.pillBg; border.width: 1; border.color: Theme.pillBorder }`
// card shell that every bar/Keytree popup used to hand-roll independently.
// PopupFrame owns only the *frame* (background/border/corner treatment,
// switched by ThemeManager.activeTheme) - sizing stays fully caller-driven,
// exactly like a plain Rectangle would be (set width/height explicitly at
// the call site), since popup sizing logic varies widget to widget (fixed
// panel width, content-driven height, etc) and isn't this component's
// concern. Content is placed directly inside `PopupFrame { ... }` via the
// default property, same as Pill.qml's `content` alias - existing
// `anchors.centerIn: parent` / `anchors.top: parent.top` bindings inside
// each popup's content keep working unchanged since `parent` still
// resolves to this root Item at the same size the old Rectangle was.
//
// bgColor/borderColor/minimalRadius default to the usual pill chrome
// tokens/8px radius, but are overridable per call site - Keytree's
// SearchView.qml panel used Theme.searchBg/searchBorder at radius 12
// before this component existed, and Minimal must stay byte-for-byte
// identical to that, not silently drift onto the generic pill tokens.
// Every skin below (not just Minimal) reads bgColor/borderColor for its
// base fill/border, so a caller's color identity carries through every
// theme; only the accent decorations (brackets, seals, stitching) use the
// shared Theme.accent/foreground tokens, since those are new geometry with
// no prior per-caller color to preserve.
//
// Every decoration here stays fully inside `anchors.fill: parent` (no
// negative-margin "overflow" halos) - the PopupWindow surfaces these cards
// live in are sized exactly to the card's own width/height (see e.g.
// CalendarPreview.qml's `implicitHeight: card.height`), so anything drawn
// outside root's own bounds has no surface to render into and is silently
// clipped away.
//
// Shared corner-bracket/faceted-path geometry lives in
// HudCornerBrackets.qml/ThemeGeometry.qml (used by Pill.qml too) - only
// extracted once a second independent copy of the same shapes showed up,
// per this codebase's general bias against speculative abstraction.
//
// ClipboardPanel.qml is NOT ported to this - it's a bigger, bespoke
// picker window with its own bigger per-theme skins (scroll+chains for
// Medieval, etc) that predate this component and don't fit the small-popup
// card shape this exists for.
Item {
    id: root

    property color bgColor: Theme.pillBg
    property color borderColor: Theme.pillBorder
    property real minimalRadius: 8

    // No explicit `default property` redeclaration needed here (unlike
    // Pill.qml redirecting into an inner Row) - Item already treats `data`
    // as its default property, so usage-site content is appended straight
    // into this root's own `data` alongside the Loader below, in
    // declaration order (Loader first = painted behind content).

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (ThemeManager.activeTheme) {
            case "Cyber":
                return cyberSkin;
            case "Glass":
                return glassSkin;
            case "Medieval":
                return medievalSkin;
            case "Halo":
                return haloSkin;
            case "HollowKnight":
                return hollowKnightSkin;
            default:
                return minimalSkin;
            }
        }
    }

    // ── Minimal (default/fallback) ───────────────────────────────────────
    // Byte-for-byte the original hand-rolled Rectangle every popup used.
    Component {
        id: minimalSkin

        Rectangle {
            anchors.fill: parent
            radius: root.minimalRadius
            color: root.bgColor
            border.width: 1
            border.color: root.borderColor
        }
    }

    // ── Cyber ─────────────────────────────────────────────────────────────
    // Sharp-cornered double border (outer solid, inner accent-tinted) plus
    // small filled "rivet" squares at each corner - a socketed HUD panel,
    // distinct from Halo's open line-bracket frame below.
    Component {
        id: cyberSkin

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                radius: 2
                color: root.bgColor
                border.width: 1
                border.color: root.borderColor
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                color: "transparent"
                border.width: 1
                border.color: Theme.withAlpha(Theme.accent, 0.45)
            }
            Rectangle {
                width: 4
                height: 4
                color: Theme.accent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: 1
            }
            Rectangle {
                width: 4
                height: 4
                color: Theme.accent
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 1
            }
            Rectangle {
                width: 4
                height: 4
                color: Theme.accent
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 1
            }
            Rectangle {
                width: 4
                height: 4
                color: Theme.accent
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 1
            }
        }
    }

    // ── Glass ─────────────────────────────────────────────────────────────
    // Fully rounded, more translucent than Minimal, with a soft halo ring
    // standing in for real blur (MultiEffect-based glow/masking isn't
    // reliable in this environment, see CLAUDE.md). The halo sits INSET
    // within root's own bounds (not expanded past them via negative
    // margins) - see the file-level comment on why overflow gets clipped.
    Component {
        id: glassSkin

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                radius: 14
                color: "transparent"
                border.width: 6
                border.color: Theme.withAlpha(Theme.foreground, 0.06)
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: 12
                color: Theme.withAlpha(root.bgColor, 0.55)
                border.width: 1
                border.color: Theme.withAlpha(Theme.foreground, 0.18)
            }
        }
    }

    // ── Medieval ──────────────────────────────────────────────────────────
    // Thicker parchment-binding border plus small "wax seal" dots at the
    // top corners - the same visual vocabulary as ClipboardPanel.qml's
    // Medieval scroll skin, scaled down for a small popup card rather than
    // a full scroll surface.
    Component {
        id: medievalSkin

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: root.bgColor
                border.width: 2
                border.color: root.borderColor
            }
            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: Theme.withAlpha(Theme.accent, 0.6)
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: 4
            }
            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: Theme.withAlpha(Theme.accent, 0.6)
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 4
            }
        }
    }

    // ── Halo ──────────────────────────────────────────────────────────────
    // UNSC tactical HUD: sharp corners, a thin accent rule along the top
    // edge ("active panel" tell), and HudCornerBrackets' open line-bracket
    // corners rather than Cyber's filled rivets - reads as a targeting
    // reticle frame, not a physical panel.
    Component {
        id: haloSkin

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                radius: 2
                color: root.bgColor
                border.width: 1
                border.color: Theme.withAlpha(Theme.foreground, 0.15)
            }
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 2
                color: Theme.accent
            }
            HudCornerBrackets {
                bracketLen: 10
                bracketThick: 1.5
                markColor: Theme.accent
            }
        }
    }

    // ── HollowKnight ──────────────────────────────────────────────────────
    // Faceted (corner-cut) chitin-plate silhouette instead of a rounded
    // rect, plus a dashed inset "stitched" line echoing the Hunter's
    // Journal's leather binding - both Canvas-drawn since Rectangle can't
    // do cut corners or dashed borders natively.
    Component {
        id: hollowKnightSkin

        Canvas {
            anchors.fill: parent
            readonly property real cut: 10

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                ThemeGeometry.facetedPath(ctx, width, height, 0, cut);
                ctx.fillStyle = root.bgColor;
                ctx.fill();
                ctx.setLineDash([]);
                ctx.lineWidth = 1;
                ctx.strokeStyle = root.borderColor;
                ctx.stroke();

                ThemeGeometry.facetedPath(ctx, width, height, 5, cut);
                ctx.setLineDash([3, 3]);
                ctx.lineWidth = 1;
                ctx.strokeStyle = Theme.withAlpha(Theme.foreground, 0.35);
                ctx.stroke();
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }
}
