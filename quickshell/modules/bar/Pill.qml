import QtQuick
import QtQuick.Shapes
import qs.modules.theme

// Generic rounded-pill container for grouping related bar widgets. Content
// is placed directly inside `Pill { ... }` (reparented into the inner Row
// via the default-property alias, same pattern as ii's ContentSection.qml
// etc). Collapses to zero width/invisible on its own if every child inside
// happens to be invisible (e.g. Music with nothing playing), since Row
// excludes invisible children from its own implicit size.
//
// Sets both implicitWidth/Height and width/height: a plain Item/Rectangle
// never auto-binds width to implicitWidth, but RowLayout (used for the
// evenly-spread bar layout) sizes non-stretching children FROM
// implicitWidth/Layout.preferredWidth - so Pill needs to satisfy both a
// plain Row (reads width) and a RowLayout (reads implicitWidth) depending
// on where it's used.
//
// While a PillPopup hangs off this pill (openPopups > 0) the plain
// Rectangle chrome is swapped for an open-bottomed Shape outline, drawn the
// same way as PillPopup's (fill + half-pixel 1px stroke) so the two
// surfaces' walls meet seamlessly - see PillPopup.qml.
Rectangle {
    id: root

    default property alias content: innerRow.data
    property int spacing: 10
    property int horizontalPadding: 10

    // Marker + open-popup count, found/maintained by PillPopup.
    readonly property bool isPill: true
    property int openPopups: 0
    readonly property bool expanded: root.openPopups > 0

    radius: 8
    color: root.expanded ? "transparent" : Theme.pillBg
    border.width: root.expanded ? 0 : 1
    border.color: Theme.pillBorder
    implicitWidth: innerRow.width > 0 ? innerRow.width + root.horizontalPadding * 2 : 0
    implicitHeight: 22
    width: implicitWidth
    height: implicitHeight
    visible: root.width > 0

    Shape {
        id: outlineShape
        visible: root.expanded
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        readonly property real l: 0.5
        readonly property real r: root.width - 0.5
        readonly property real t: 0.5
        readonly property real b: root.height
        readonly property real rad: root.radius - 0.5
        // Up the left wall, across the top, down the right wall - the
        // bottom stays open where the popup continues.
        readonly property string outline: {
            const l = outlineShape.l, r = outlineShape.r, t = outlineShape.t, b = outlineShape.b, rad = outlineShape.rad;
            return `M ${l} ${b} L ${l} ${t + rad} A ${rad} ${rad} 0 0 1 ${l + rad} ${t} L ${r - rad} ${t} A ${rad} ${rad} 0 0 1 ${r} ${t + rad} L ${r} ${b}`;
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Theme.pillBg
            PathSvg {
                path: outlineShape.outline + " Z"
            }
        }
        ShapePath {
            strokeWidth: 1
            strokeColor: Theme.pillBorder
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg {
                path: outlineShape.outline
            }
        }
    }

    Row {
        id: innerRow
        anchors.centerIn: parent
        spacing: root.spacing
    }
}
