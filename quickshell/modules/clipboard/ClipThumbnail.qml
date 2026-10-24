import QtQuick
import qs.modules.theme

// Shared cliphist image-entry thumbnail box, used by every ClipboardPanel
// skin (previously 6 independent copies of the same Image block). `cache:
// false` is load-bearing, not cosmetic - a cliphist thumbnail file gets
// rewritten in place under a stable id as the clipboard history rotates
// (see ClipboardPanel.qml's genScript), so a cached pixmap would go stale
// without it. Extracted specifically so no future skin can silently drop
// that line. Sizing/radius/border/fill color stay per-skin, set as normal
// Rectangle properties at the call site - only the entry->Image wiring is
// shared.
Rectangle {
    id: root

    required property var entry

    width: 32
    height: 32
    color: Theme.hoverBg
    visible: root.entry.isImage
    clip: true

    Image {
        anchors.fill: parent
        source: root.entry.ready ? Qt.resolvedUrl(root.entry.thumbPath) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }
}
