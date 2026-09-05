pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.theme

// Colorspace breakdown popup, opened from ColorPicker.qml right after a
// hyprpicker sample. Each row copies its value to the clipboard via
// wl-copy on click, with a brief "Copied" swap instead of the value.
PopupWindow {
    id: popup

    required property Item anchorItem
    required property string hex

    readonly property alias hovered: cardHoverHandler.hovered

    property string copiedField: ""

    function hexToRgb(h) {
        const n = parseInt(h.slice(1), 16);
        return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
    }
    function rgbToHsl(r, g, b) {
        r /= 255; g /= 255; b /= 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        let h = 0, s = 0;
        const l = (max + min) / 2;
        const d = max - min;
        if (d !== 0) {
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            switch (max) {
            case r: h = (g - b) / d + (g < b ? 6 : 0); break;
            case g: h = (b - r) / d + 2; break;
            default: h = (r - g) / d + 4; break;
            }
            h /= 6;
        }
        return { h: Math.round(h * 360), s: Math.round(s * 100), l: Math.round(l * 100) };
    }
    function rgbToHsv(r, g, b) {
        r /= 255; g /= 255; b /= 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        let h = 0;
        const v = max;
        const d = max - min;
        const s = max === 0 ? 0 : d / max;
        if (d !== 0) {
            switch (max) {
            case r: h = (g - b) / d + (g < b ? 6 : 0); break;
            case g: h = (b - r) / d + 2; break;
            default: h = (r - g) / d + 4; break;
            }
            h /= 6;
        }
        return { h: Math.round(h * 360), s: Math.round(s * 100), v: Math.round(v * 100) };
    }

    readonly property var rgb: popup.hex.length > 0 ? hexToRgb(popup.hex) : ({ r: 0, g: 0, b: 0 })
    readonly property var hsl: rgbToHsl(popup.rgb.r, popup.rgb.g, popup.rgb.b)
    readonly property var hsv: rgbToHsv(popup.rgb.r, popup.rgb.g, popup.rgb.b)

    readonly property var rows: [
        { label: "HEX", value: popup.hex.toUpperCase() },
        { label: "RGB", value: "rgb(" + popup.rgb.r + ", " + popup.rgb.g + ", " + popup.rgb.b + ")" },
        { label: "HSL", value: "hsl(" + popup.hsl.h + ", " + popup.hsl.s + "%, " + popup.hsl.l + "%)" },
        { label: "HSV", value: "hsv(" + popup.hsv.h + ", " + popup.hsv.s + "%, " + popup.hsv.v + "%)" }
    ]

    function copy(field, value) {
        Quickshell.execDetached(["wl-copy", value]);
        popup.copiedField = field;
        copiedTimer.restart();
    }

    Timer {
        id: copiedTimer
        interval: 900
        onTriggered: popup.copiedField = ""
    }

    anchor {
        item: popup.anchorItem
        edges: Edges.Bottom
        gravity: Edges.Bottom
        margins.top: 0
    }

    visible: true
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"

    PopupFrame {
        id: card
        width: 220
        height: layout.implicitHeight + 32

        HoverHandler { id: cardHoverHandler }

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 10

            Rectangle {
                width: parent.width
                height: 36
                radius: 6
                color: popup.hex.length > 0 ? popup.hex : "transparent"
                border.color: Theme.pillBorder
                border.width: 1
            }

            Repeater {
                model: popup.rows
                delegate: Rectangle {
                    required property var modelData
                    width: layout.width
                    height: 24
                    radius: 4
                    color: rowMa.containsMouse ? Theme.hoverBg : "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8

                        Text {
                            width: 34
                            text: modelData.label
                            color: Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: true
                        }
                        Text {
                            text: popup.copiedField === modelData.label ? "Copied ✓" : modelData.value
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.copy(modelData.label, modelData.value)
                    }
                }
            }
        }
    }
}
