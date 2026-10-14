import QtQuick
import Quickshell

// Names its parent as a bolt source/target, e.g. inside the bar's Cpu widget:
//   BoltAnchor { name: "cpu" }
// then BoltConfig can say `from: "anchor:cpu"`. The point used is the
// parent's bottom-center (where a bolt from the bar would leave it).
Item {
    id: anchor

    required property string name
    readonly property Item target: anchor.parent
    readonly property ShellScreen screen: QsWindow.window?.screen ?? null
    readonly property string screenName: anchor.screen?.name ?? ""
    readonly property bool usable: !!anchor.target && anchor.target.visible && anchor.target.width > 0

    visible: false

    function globalPoint() {
        const p = anchor.target.mapToItem(null, anchor.target.width / 2, anchor.target.height);
        return Qt.point(p.x + (anchor.screen?.x ?? 0), p.y + (anchor.screen?.y ?? 0));
    }

    Component.onCompleted: Bolts.registerAnchor(anchor)
    Component.onDestruction: Bolts.unregisterAnchor(anchor)
}
