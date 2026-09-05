pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

// Themed chrome along the bar's own bottom edge - the "decorators around
// the primary bar" counterpart to Pill.qml's per-pill chrome. Purely
// decorative (no interaction), instantiated once per monitor by Bar.qml,
// declared before Workspaces/RightCluster there so it always paints behind
// them. Minimal renders nothing, matching every other "no skin = untouched
// baseline" fallback in this shell. Each skin below deliberately echoes the
// same per-theme vocabulary Pill.qml/PopupFrame.qml use (Cyber = solid
// rule + filled rivet squares, Halo = accent rule + HudCornerBrackets,
// Medieval/HollowKnight = dashed Canvas lines) rather than inventing new
// unrelated line art, so cycling themes reads as one coherent identity
// across the whole bar, not just within each pill.
Item {
    id: root

    height: 3

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
                return null;
            }
        }
    }

    // ── Cyber ─────────────────────────────────────────────────────────────
    // Solid accent rule bookended by filled squares, echoing Pill.qml's
    // cyberSkin rivet corners rather than the tick-ruler this used to draw.
    Component {
        id: cyberSkin

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Theme.withAlpha(Theme.accent, 0.4)
            }
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 3
                color: Theme.accent
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 3
                color: Theme.accent
            }
        }
    }

    // ── Glass ─────────────────────────────────────────────────────────────
    // A soft, wide, very-low-alpha band - the same halo language Pill.qml/
    // PopupFrame.qml use for Glass, here spanning the whole bar edge
    // instead of ringing a single card.
    Component {
        id: glassSkin

        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.foreground, 0.08)
        }
    }

    // ── Medieval ──────────────────────────────────────────────────────────
    // A stitched rope line, drawn as a dashed Canvas curve along the edge -
    // same dash vocabulary as PopupFrame.qml's Medieval/HollowKnight
    // stitching.
    Component {
        id: medievalSkin

        Canvas {
            anchors.fill: parent

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.beginPath();
                ctx.moveTo(0, height / 2);
                ctx.lineTo(width, height / 2);
                ctx.setLineDash([5, 4]);
                ctx.lineWidth = 1.5;
                ctx.strokeStyle = Theme.withAlpha(Theme.pillBorder, 0.7);
                ctx.stroke();
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    // ── Halo ──────────────────────────────────────────────────────────────
    // A crisp accent baseline with HudCornerBrackets-style short marks at
    // each end of the bar, echoing the HUD frame used on Pill.qml/
    // PopupFrame.qml.
    Component {
        id: haloSkin

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.withAlpha(Theme.accent, 0.5)
            }
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: 24
                height: 2
                color: Theme.accent
            }
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 24
                height: 2
                color: Theme.accent
            }
        }
    }

    // ── HollowKnight ──────────────────────────────────────────────────────
    // A slow, organic dashed thread line instead of a straight rule - the
    // hand-inked opposite of Halo's crisp baseline above, using the same
    // ThemeGeometry.wavyPath as any other widget that wants this motif and
    // the same dash vocabulary as the Medieval/PopupFrame stitching.
    Component {
        id: hollowKnightSkin

        Canvas {
            anchors.fill: parent

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ThemeGeometry.wavyPath(ctx, width, height, height / 2, 28);
                ctx.setLineDash([4, 3]);
                ctx.lineWidth = 1;
                ctx.strokeStyle = Theme.withAlpha(Theme.foreground, 0.3);
                ctx.stroke();
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }
}
