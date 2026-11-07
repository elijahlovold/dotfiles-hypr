pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

// UnitToolsPreview's "Base" tab: one 32-bit unsigned value shown as hex,
// dec and bin (edit any, the others follow) and as a clickable bit grid,
// plus a register-field reader - type "7:4" (or a single bit, "3") to read
// those bits out and highlight them in the grid. Plain Number math rather
// than JS bitwise ops, which are signed 32-bit.
Column {
    id: root

    // j/k navigation order, read by UnitToolsPreview.
    readonly property var fields: [hexField, decField, binField, rangeField]
    // UnitToolsPreview's j/k handler, given (event, index into fields).
    property var fieldKey: null

    property real value: 0
    readonly property real max: 4294967295

    // Bits [hi, lo] from rangeField, or null.
    readonly property var range: {
        const m = /^\s*(\d+)\s*(?::\s*(\d+))?\s*$/.exec(rangeField.text);
        if (!m)
            return null;
        const a = Number(m[1]), b = m[2] === undefined ? a : Number(m[2]);
        const hi = Math.max(a, b), lo = Math.min(a, b);
        return hi > 31 ? null : { hi: hi, lo: lo };
    }
    readonly property real extracted: root.range ? Math.floor(root.value / Math.pow(2, root.range.lo)) % Math.pow(2, root.range.hi - root.range.lo + 1) : 0

    function bit(i) {
        return Math.floor(root.value / Math.pow(2, i)) % 2;
    }

    function toggleBit(i) {
        root.setValue(root.value + (root.bit(i) ? -1 : 1) * Math.pow(2, i), null);
    }

    // Writes every field but `source` (the one being typed in).
    function setValue(v, source) {
        root.value = v;
        if (source !== hexField)
            hexField.text = v.toString(16).toUpperCase();
        if (source !== decField)
            decField.text = v.toString(10);
        if (source !== binField)
            binField.text = v.toString(2);
    }

    function edited(field, base) {
        const t = field.text.replace(/[\s_]/g, "").replace(/^0[xb]/i, "");
        const v = t.length === 0 ? 0 : parseInt(t, base);
        if (!isNaN(v) && v <= root.max)
            root.setValue(v, field);
    }

    function inRange(i) {
        return root.range !== null && i <= root.range.hi && i >= root.range.lo;
    }

    width: parent.width
    spacing: 6

    Component.onCompleted: root.setValue(0, null)

    component Field: Rectangle {
        id: fieldBox

        property alias input: input
        property string prefix
        property var validator
        property int index

        width: parent.width
        height: 26
        radius: 4
        color: Theme.hoverBg
        border.color: Theme.pillBorder
        border.width: 1

        Text {
            id: prefixText
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            text: fieldBox.prefix
            color: Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
        }

        TextInput {
            id: input
            anchors.left: prefixText.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 6
            anchors.leftMargin: 4
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            validator: fieldBox.validator
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            selectByMouse: true
            Keys.onPressed: event => root.fieldKey?.(event, fieldBox.index)
        }
    }

    Field {
        id: hexBox
        prefix: "hex"
        index: 0
        validator: RegularExpressionValidator {
            regularExpression: /^(0[xX])?[0-9a-fA-F_ ]{0,9}$/
        }
        input.onTextEdited: root.edited(hexField, 16)
    }
    Field {
        id: decBox
        prefix: "dec"
        index: 1
        validator: RegularExpressionValidator {
            regularExpression: /^\d{0,10}$/
        }
        input.onTextEdited: root.edited(decField, 10)
    }
    Field {
        id: binBox
        prefix: "bin"
        index: 2
        validator: RegularExpressionValidator {
            regularExpression: /^(0[bB])?[01_ ]{0,39}$/
        }
        input.onTextEdited: root.edited(binField, 2)
    }

    // Aliases for the inner TextInputs, so the functions above read plainly.
    property alias hexField: hexBox.input
    property alias decField: decBox.input
    property alias binField: binBox.input

    // Bit grid: bytes 3..0 top to bottom, bit 31 at the top left. Click a
    // bit to flip it.
    Column {
        spacing: 3
        topPadding: 2

        Repeater {
            model: 4
            delegate: Row {
                id: byteRow
                required property int index
                readonly property int topBit: (3 - byteRow.index) * 8 + 7
                spacing: 3

                Text {
                    width: 36
                    anchors.verticalCenter: parent.verticalCenter
                    text: byteRow.topBit + ":" + (byteRow.topBit - 7)
                    color: Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 5
                }

                Repeater {
                    model: 8
                    delegate: Rectangle {
                        id: cell
                        required property int index
                        readonly property int bitIndex: byteRow.topBit - cell.index
                        readonly property bool set: root.bit(cell.bitIndex) === 1

                        width: 20
                        height: 18
                        radius: 3
                        color: cell.set ? Theme.accent : root.inRange(cell.bitIndex) ? Theme.hoverBg : "transparent"
                        border.color: root.inRange(cell.bitIndex) ? Theme.accent : Theme.pillBorder
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: cell.set ? "1" : "0"
                            color: cell.set ? Theme.onAccentText : Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 5
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleBit(cell.bitIndex)
                        }
                    }
                }
            }
        }
    }

    // Field reader
    Row {
        width: parent.width
        spacing: 8

        Rectangle {
            width: 70
            height: 26
            radius: 4
            color: Theme.hoverBg
            border.color: Theme.pillBorder
            border.width: 1

            TextInput {
                id: rangeField
                anchors.fill: parent
                anchors.margins: 6
                verticalAlignment: TextInput.AlignVCenter
                validator: RegularExpressionValidator {
                    regularExpression: /^\d{0,2}(:\d{0,2})?$/
                }
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                selectByMouse: true
                Keys.onPressed: event => root.fieldKey?.(event, 3)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: rangeField.text.length === 0
                    text: "7:4"
                    color: Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.range ? "= 0x" + root.extracted.toString(16).toUpperCase() + "  (" + root.extracted + ")" : "bits hi:lo"
            color: root.range ? Theme.text : Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }
    }
}
