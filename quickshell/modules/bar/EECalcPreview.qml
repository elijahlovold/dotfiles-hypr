pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.overlay

// EE calculators, opened from EECalc.qml - pure JS (EEMath), no process:
//   Divider  - fill any three of Vin/R1/R2/Vout and the fourth is solved;
//              a solved resistor also gets its nearest E24/E96 values and
//              the Vout they'd actually give.
//   LED      - series resistor for a supply, forward voltage and current,
//              rounded up to E24 (never more current than asked for).
//   E-series - nearest E12/E24/E96 values to a resistance.
//   Colors   - a resistance's 4-band and 5-band colour code.
// Values take SI prefixes and RKM codes: 4.7k, 4k7, 1R5, 100n, 20m.
// Tab / Shift+Tab move between fields, Ctrl+H / Ctrl+L switch tabs;
// Escape isn't taken, so it bubbles up to PillPopup and closes.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    readonly property var tabs: ["Divider", "LED", "E-series", "Colors"]
    property int tab: 0

    readonly property var tabFields: [[vinField, r1Field, r2Field, voutField], [vsField, vfField, ifField], [seriesField], [colorField]]
    readonly property var fields: popup.tabFields[popup.tab]

    function switchTab(t) {
        popup.tab = (t + popup.tabs.length) % popup.tabs.length;
        Qt.callLater(() => popup.fields[0].forceActiveFocus());
    }

    function fieldKey(event, field) {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            const i = popup.fields.indexOf(field);
            const step = event.key === Qt.Key_Backtab ? -1 : 1;
            popup.fields[(i + step + popup.fields.length) % popup.fields.length].forceActiveFocus();
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && (event.key === Qt.Key_H || event.key === Qt.Key_L)) {
            popup.switchTab(popup.tab + (event.key === Qt.Key_L ? 1 : -1));
            event.accepted = true;
        }
    }

    onKeyboardActivated: Qt.callLater(() => {
        if (!popup.fields.some(f => f.activeFocus))
            popup.fields[0].forceActiveFocus();
    })

    // ---- Divider ----
    readonly property var divider: {
        const vin = EEMath.parse(vinField.text), r1 = EEMath.parse(r1Field.text), r2 = EEMath.parse(r2Field.text), vout = EEMath.parse(voutField.text);
        const given = [vin, r1, r2, vout].filter(isFinite).length;
        if (given < 3)
            return null;
        // Solve whichever is blank; with all four filled, Vout is the answer.
        if (!isFinite(vin))
            return { solved: "Vin", value: vout * (r1 + r2) / r2, unit: "V", current: vout / r2 };
        if (!isFinite(r1) && vout < vin)
            return popup.solvedResistor("R1", r2 * (vin - vout) / vout, r => vin * r2 / (r + r2), vin);
        if (!isFinite(r2) && vout < vin)
            return popup.solvedResistor("R2", r1 * vout / (vin - vout), r => vin * r / (r1 + r), vin);
        if (isFinite(r1) && isFinite(r2))
            return { solved: "Vout", value: vin * r2 / (r1 + r2), unit: "V", current: vin / (r1 + r2) };
        return { error: "Vout must be below Vin" };
    }

    // A solved divider resistor, with what its E24/E96 neighbours give.
    function solvedResistor(name, r, voutFor, vin) {
        const options = ["E24", "E96"].map(s => {
            const e = EEMath.nearest(r, s, "nearest");
            return { series: s, value: e, vout: voutFor(e) };
        });
        return { solved: name, value: r, unit: "Ω", options: options, current: vin / (r + (name === "R1" ? EEMath.parse(r2Field.text) : EEMath.parse(r1Field.text))) };
    }

    // ---- LED ----
    readonly property var led: {
        const vs = EEMath.parse(vsField.text), vf = EEMath.parse(vfField.text), ma = parseFloat(ifField.text);
        if (![vs, vf, ma].every(isFinite) || ma <= 0)
            return null;
        if (vf >= vs)
            return { error: "Vf must be below the supply" };
        const i = ma / 1000;
        const r = (vs - vf) / i;
        const e = EEMath.nearest(r, "E24", "up");
        const actual = (vs - vf) / e;
        const p = actual * actual * e;
        const rating = [[0.0625, "1/16 W"], [0.125, "1/8 W"], [0.25, "1/4 W"], [0.5, "1/2 W"], [1, "1 W"], [2, "2 W"]].find(r => r[0] >= p * 2)?.[1];
        return { r: r, e24: e, current: actual, power: p, rating: rating };
    }

    // ---- E-series / Colors ----
    readonly property real seriesValue: EEMath.parse(seriesField.text)
    readonly property real colorValue: EEMath.parse(colorField.text)

    component Field: Row {
        id: fieldRow

        property alias input: input
        property string label
        property string unit
        property string placeholder

        width: layout.width
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            text: fieldRow.label
            color: Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }

        Rectangle {
            width: parent.width - 36 - 28 - 16
            height: 26
            radius: 4
            color: Theme.hoverBg
            border.color: input.text.trim().length > 0 && !isFinite(fieldRow.unit === "mA" ? parseFloat(input.text) : EEMath.parse(input.text)) ? popup.errorColor : Theme.pillBorder
            border.width: 1

            TextInput {
                id: input
                anchors.fill: parent
                anchors.margins: 6
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                selectByMouse: true
                Keys.onPressed: event => popup.fieldKey(event, input)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: fieldRow.placeholder
                    color: Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            text: fieldRow.unit
            color: Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }
    }

    component Line: Text {
        width: layout.width
        wrapMode: Text.WordWrap
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
    }

    component DimLine: Line {
        color: Theme.dimText
        font.pixelSize: Theme.fontSize - 4
    }

    // Fixed red, as in ScreenRec - wallust palettes are often too muted
    // for any slot to read as an error.
    readonly property color errorColor: "#ff4d4d"

    Item {
        id: card
        width: 300
        height: layout.implicitHeight + 32

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 8

            Row {
                spacing: 12
                bottomPadding: 4

                Repeater {
                    model: popup.tabs
                    delegate: Text {
                        required property string modelData
                        required property int index
                        text: modelData
                        color: popup.tab === index ? Theme.accent : Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: popup.tab === index

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.switchTab(index)
                        }
                    }
                }
            }

            // ---- Divider ----
            Column {
                visible: popup.tab === 0
                width: parent.width
                spacing: 6

                DimLine {
                    text: "Fill three, leave one blank to solve it."
                }
                Field {
                    id: vinRow
                    label: "Vin"
                    unit: "V"
                    placeholder: "5"
                }
                Field {
                    id: r1Row
                    label: "R1"
                    unit: "Ω"
                    placeholder: "top"
                }
                Field {
                    id: r2Row
                    label: "R2"
                    unit: "Ω"
                    placeholder: "bottom"
                }
                Field {
                    id: voutRow
                    label: "Vout"
                    unit: "V"
                    placeholder: "3.3"
                }

                Line {
                    topPadding: 4
                    visible: popup.divider !== null
                    color: popup.divider?.error ? popup.errorColor : Theme.accent
                    font.bold: true
                    text: popup.divider?.error ?? (popup.divider ? popup.divider.solved + " = " + EEMath.format(popup.divider.value, popup.divider.unit) : "")
                }
                Repeater {
                    model: popup.divider?.options ?? []
                    delegate: Line {
                        required property var modelData
                        text: modelData.series + "  " + EEMath.format(modelData.value, "Ω") + "  →  Vout " + EEMath.format(modelData.vout, "V")
                    }
                }
                DimLine {
                    visible: isFinite(popup.divider?.current ?? NaN)
                    text: "Divider current " + EEMath.format(popup.divider?.current ?? 0, "A")
                }
            }

            // ---- LED ----
            Column {
                visible: popup.tab === 1
                width: parent.width
                spacing: 6

                Field {
                    id: vsRow
                    label: "Vs"
                    unit: "V"
                    placeholder: "5"
                }
                Field {
                    id: vfRow
                    label: "Vf"
                    unit: "V"
                    placeholder: "2.0 red · 3.0 blue/white"
                }
                Field {
                    id: ifRow
                    label: "If"
                    unit: "mA"
                    placeholder: "10"
                }

                Line {
                    topPadding: 4
                    visible: popup.led !== null
                    color: popup.led?.error ? popup.errorColor : Theme.accent
                    font.bold: true
                    text: popup.led?.error ?? (popup.led ? "R = " + EEMath.format(popup.led.e24, "Ω") + "  (E24, exact " + EEMath.format(popup.led.r, "Ω") + ")" : "")
                }
                Line {
                    visible: popup.led !== null && !popup.led.error
                    text: popup.led && !popup.led.error ? "If " + EEMath.format(popup.led.current, "A") + " · R dissipates " + EEMath.format(popup.led.power, "W") : ""
                }
                DimLine {
                    visible: popup.led !== null && !popup.led.error
                    text: popup.led?.rating ? "Use a ≥ " + popup.led.rating + " resistor (2× margin)" : "Over 2 W - reconsider (2× margin)"
                }
            }

            // ---- E-series ----
            Column {
                visible: popup.tab === 2
                width: parent.width
                spacing: 6

                Field {
                    id: seriesRow
                    label: "R"
                    unit: "Ω"
                    placeholder: "4.6k"
                }

                Repeater {
                    model: isFinite(popup.seriesValue) && popup.seriesValue > 0 ? ["E12", "E24", "E96"] : []
                    delegate: Row {
                        id: seriesLine
                        required property string modelData
                        readonly property real near: EEMath.nearest(popup.seriesValue, modelData, "nearest")
                        readonly property real down: EEMath.nearest(popup.seriesValue, modelData, "down")
                        readonly property real up: EEMath.nearest(popup.seriesValue, modelData, "up")
                        spacing: 8

                        Text {
                            width: 36
                            text: seriesLine.modelData
                            color: Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                        Text {
                            width: 110
                            text: EEMath.format(seriesLine.near, "Ω") + "  " + EEMath.errorPct(seriesLine.near, popup.seriesValue)
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: true
                        }
                        Text {
                            text: EEMath.format(seriesLine.down, "").replace(" ", "") + " – " + EEMath.format(seriesLine.up, "").replace(" ", "")
                            color: Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 4
                        }
                    }
                }
            }

            // ---- Colors ----
            Column {
                visible: popup.tab === 3
                width: parent.width
                spacing: 8

                Field {
                    id: colorRow
                    label: "R"
                    unit: "Ω"
                    placeholder: "4k7"
                }

                Repeater {
                    model: isFinite(popup.colorValue) && popup.colorValue > 0 ? [2, 3] : []
                    delegate: Column {
                        id: code
                        required property int modelData
                        readonly property var result: EEMath.bands(popup.colorValue, modelData)
                        spacing: 4

                        Text {
                            text: (code.modelData === 2 ? "4-band 5%" : "5-band 1%") + (code.result && !code.result.exact ? "  · reads " + EEMath.format(code.result.value, "Ω") : "")
                            color: Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 4
                        }

                        // Resistor body with its bands; tolerance band set
                        // apart at the right end.
                        Rectangle {
                            visible: code.result !== null
                            width: layout.width
                            height: 22
                            radius: 8
                            color: "#d8c7a0"

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 18
                                spacing: 9

                                Repeater {
                                    model: code.result ? code.result.bands.slice(0, -1) : []
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 10
                                        height: 22
                                        color: modelData.color
                                    }
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 18
                                width: 10
                                height: 22
                                color: code.result ? code.result.bands[code.result.bands.length - 1].color : "transparent"
                            }
                        }

                        Text {
                            width: layout.width
                            wrapMode: Text.WordWrap
                            text: code.result ? code.result.bands.map(b => b.name).join(" · ") : "Out of range"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 4
                        }
                    }
                }
            }
        }
    }

    // The TextInputs inside the Field rows, for the logic above.
    property alias vinField: vinRow.input
    property alias r1Field: r1Row.input
    property alias r2Field: r2Row.input
    property alias voutField: voutRow.input
    property alias vsField: vsRow.input
    property alias vfField: vfRow.input
    property alias ifField: ifRow.input
    property alias seriesField: seriesRow.input
    property alias colorField: colorRow.input
}
