import QtQuick
// Not used by name here: it makes quickshell index spokes/, which the
// styles need to find their base types when loaded by URL.
import qs.modules.keytree.spokes

// Hub-to-node connectors for the views that have them (RingView, and
// HangView's strings). Loads the style named by `style`
// from spokes/ ("helix" -> spokes/Helix.qml) and hands it this item as its
// `host`; everything a style draws from is the properties below. See
// spokes/SpokeStyle.qml for how to add one.
Item {
    id: root

    property string style: "radial"
    // Node geometry - see spokes/SpokeStyle.qml `layout`.
    property var layout: ({ kind: "ring", nodes: [] })
    property real reveal: 0
    property color color: "white"
    property real lineWidth: 1
    // Clearance kept between a spoke and the outline it ends on.
    property real gap: 4

    // Diameters of the circles the strokes are cut back to.
    property real nodeD: 0
    property real hubD: 0

    // A style name with no spokes/*.qml, remembered so the source binding
    // can fall back to radial without being overwritten.
    property string missingStyle: ""

    function styleUrl(name) {
        return Qt.resolvedUrl("spokes/" + name.charAt(0).toUpperCase() + name.slice(1) + ".qml");
    }

    Loader {
        id: loader
        anchors.fill: parent
        source: root.styleUrl(!root.style || root.style === root.missingStyle ? "radial" : root.style)
        onLoaded: item.host = root
        onStatusChanged: {
            if (status === Loader.Error && root.style !== root.missingStyle) {
                const name = root.style;
                console.warn("keytree: no spoke style \"" + name + "\" (spokes/*.qml), using radial");
                // Deferred: switching source from inside its own status
                // change is a binding loop.
                Qt.callLater(() => root.missingStyle = name);
            }
        }
    }
}
