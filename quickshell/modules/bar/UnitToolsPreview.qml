pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.theme
import qs.modules.overlay

// Two independent pure-QML/JS tools in one popup, opened from
// UnitTools.qml: a live bidirectional unit converter (length/weight/temp -
// the pairs that come up most doing embedded/3D-print/PCB work) and a
// timestamp reader (paste an epoch or date string, read it back both
// ways). No process/service involved - everything below is local JS math.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    property string copiedField: ""
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

    // ---- Unit converter ----
    property int categoryIndex: 0
    readonly property var categories: [
        { name: "Length", unitA: "mm", unitB: "in", aToB: v => v / 25.4, bToA: v => v * 25.4 },
        { name: "Weight", unitA: "g", unitB: "oz", aToB: v => v / 28.3495, bToA: v => v * 28.3495 },
        { name: "Temp", unitA: "°C", unitB: "°F", aToB: v => v * 9 / 5 + 32, bToA: v => (v - 32) * 5 / 9 }
    ]
    readonly property var category: popup.categories[popup.categoryIndex]
    property bool convGuard: false

    function round3(v) {
        return Math.round(v * 1000) / 1000;
    }
    function onFieldAEdited(text) {
        if (popup.convGuard)
            return;
        const v = parseFloat(text);
        popup.convGuard = true;
        fieldB.text = isNaN(v) ? "" : popup.round3(popup.category.aToB(v)).toString();
        popup.convGuard = false;
    }
    function onFieldBEdited(text) {
        if (popup.convGuard)
            return;
        const v = parseFloat(text);
        popup.convGuard = true;
        fieldA.text = isNaN(v) ? "" : popup.round3(popup.category.bToA(v)).toString();
        popup.convGuard = false;
    }

    // ---- Timestamp reader ----
    property string tsInput: ""
    readonly property var parsedDate: {
        const t = popup.tsInput.trim();
        if (t.length === 0)
            return null;
        if (/^-?\d+$/.test(t)) {
            const n = parseInt(t, 10);
            const ms = Math.abs(n).toString().length >= 13 ? n : n * 1000;
            return new Date(ms);
        }
        const parsed = Date.parse(t);
        return isNaN(parsed) ? null : new Date(parsed);
    }

    property double nowTick: Date.now()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: popup.nowTick = Date.now()
    }

    // Keyboard: j/k move between the three fields (wrapping); everything
    // else types into the field. Escape isn't taken here, so it bubbles up
    // to PillPopup and closes. Once the popup takes keyboard focus (Super+P
    // or a click), the first field gets it unless a click already picked one
    // - deferred so that click's own focus change lands first.
    readonly property var fields: [fieldA, fieldB, tsField]

    function fieldKey(event, index) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return;
        const step = event.text === "j" ? 1 : event.text === "k" ? -1 : 0;
        if (step === 0)
            return;
        popup.fields[(index + step + popup.fields.length) % popup.fields.length].forceActiveFocus();
        event.accepted = true;
    }

    onKeyboardActivated: Qt.callLater(() => {
        if (!popup.fields.some(f => f.focus))
            fieldA.forceActiveFocus();
    })

    Item {
        id: card
        width: 260
        height: layout.implicitHeight + 32

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 14

            // Unit converter
            Column {
                width: parent.width
                spacing: 6

                Row {
                    spacing: 10
                    Repeater {
                        model: popup.categories
                        delegate: Text {
                            required property var modelData
                            required property int index
                            text: modelData.name
                            color: popup.categoryIndex === index ? Theme.accent : Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: popup.categoryIndex === index

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    popup.categoryIndex = index;
                                    fieldA.text = "";
                                    fieldB.text = "";
                                }
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 40) / 2
                        height: 26
                        radius: 4
                        color: Theme.hoverBg
                        border.color: Theme.pillBorder
                        border.width: 1

                        TextInput {
                            id: fieldA
                            // Numbers and a decimal point only (plus a leading minus, so
                            // sub-zero temperatures still work).
                            validator: RegularExpressionValidator {
                                regularExpression: /^-?\d*\.?\d*$/
                            }
                            Keys.onPressed: event => popup.fieldKey(event, 0)
                            anchors.fill: parent
                            anchors.margins: 6
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            selectByMouse: true
                            onTextEdited: popup.onFieldAEdited(text)
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        text: popup.category.unitA
                        color: Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 40) / 2
                        height: 26
                        radius: 4
                        color: Theme.hoverBg
                        border.color: Theme.pillBorder
                        border.width: 1

                        TextInput {
                            id: fieldB
                            // Numbers and a decimal point only (plus a leading minus, so
                            // sub-zero temperatures still work).
                            validator: RegularExpressionValidator {
                                regularExpression: /^-?\d*\.?\d*$/
                            }
                            Keys.onPressed: event => popup.fieldKey(event, 1)
                            anchors.fill: parent
                            anchors.margins: 6
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            selectByMouse: true
                            onTextEdited: popup.onFieldBEdited(text)
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        text: popup.category.unitB
                        color: Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.pillBorder
            }

            // Timestamp reader
            Column {
                width: parent.width
                spacing: 6

                Text {
                    text: "Timestamp"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                }

                Rectangle {
                    width: parent.width
                    height: 26
                    radius: 4
                    color: Theme.hoverBg
                    border.color: Theme.pillBorder
                    border.width: 1

                    TextInput {
                        id: tsField
                        Keys.onPressed: event => popup.fieldKey(event, 2)
                        anchors.fill: parent
                        anchors.margins: 6
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        selectByMouse: true
                        onTextEdited: popup.tsInput = text

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: tsField.text.length === 0
                            text: "epoch or date…"
                            color: Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: popup.parsedDate ? Qt.formatDateTime(popup.parsedDate, "yyyy-MM-dd hh:mm:ss") : "—"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3

                    MouseArea {
                        anchors.fill: parent
                        enabled: popup.parsedDate !== null
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.copy("local", Qt.formatDateTime(popup.parsedDate, "yyyy-MM-dd hh:mm:ss"))
                    }
                }
                Text {
                    width: parent.width
                    text: popup.parsedDate ? "epoch " + Math.floor(popup.parsedDate.getTime() / 1000) : ""
                    color: Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 4

                    MouseArea {
                        anchors.fill: parent
                        enabled: popup.parsedDate !== null
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.copy("epoch", Math.floor(popup.parsedDate.getTime() / 1000).toString())
                    }
                }

                Text {
                    text: "now " + Math.floor(popup.nowTick / 1000) + (popup.copiedField === "now" ? "  Copied ✓" : "")
                    color: Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 4

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.copy("now", Math.floor(popup.nowTick / 1000).toString())
                    }
                }
            }
        }
    }
}
