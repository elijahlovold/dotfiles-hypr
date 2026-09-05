import QtQuick
import qs.modules.theme

// Clock's time/date divider - extracted out of ClockWeatherCard.qml so
// that file's own "token tier, no Loader/Component duplication" claim
// stays literally true. This one sub-element is the deliberate exception
// (the HollowKnight blade silhouette genuinely needs a tapered Canvas
// shape, not just a token swap), isolated behind its own component
// boundary the same way HudCornerBrackets.qml was pulled out of
// PopupFrame.qml/Pill.qml, rather than living inline in a file that
// documents itself as not doing this.
Item {
    id: root

    required property real contentScale

    readonly property real _baseWidth: Math.max(1, Math.round(2 * root.contentScale))
    width: {
        switch (ThemeManager.activeTheme) {
        case "Halo":
            return 6;
        case "HollowKnight":
            return 8;
        default:
            return root._baseWidth;
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (ThemeManager.activeTheme) {
            case "Halo":
                return haloSkin;
            case "HollowKnight":
                return hollowKnightSkin;
            default:
                return plainSkin;
            }
        }
    }

    Component {
        id: plainSkin

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(1, 1, 1, 0.35)
        }
    }

    // Thin HUD line with short bracket caps at each end, echoing
    // HudCornerBrackets.qml's open-frame vocabulary used elsewhere in this
    // shell's Halo skins.
    Component {
        id: haloSkin

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1.5
                color: Theme.accent
                opacity: 0.7
            }
            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: 1.5
                color: Theme.accent
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: 1.5
                color: Theme.accent
            }
        }
    }

    // A thin-thick-thin blade silhouette (the "nail" motif) - Canvas-drawn
    // since Rectangle can't taper.
    Component {
        id: hollowKnightSkin

        Canvas {
            anchors.fill: parent

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const w = width, h = height;
                ctx.beginPath();
                ctx.moveTo(w / 2, 0);
                ctx.lineTo(w, h * 0.18);
                ctx.lineTo(w * 0.62, h / 2);
                ctx.lineTo(w, h * 0.82);
                ctx.lineTo(w / 2, h);
                ctx.lineTo(0, h * 0.82);
                ctx.lineTo(w * 0.38, h / 2);
                ctx.lineTo(0, h * 0.18);
                ctx.closePath();
                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.35);
                ctx.fill();
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }
}
