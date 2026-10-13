import QtQuick
import Quickshell

// Registers a bar widget's popup with BarPopups under `name`, so it can be
// opened from the keyboard (`qs ipc call barpopup open <name>`). Drop one
// inside the widget:
//   PopupTarget { name: "sound"; widget: root }
// `widget` must expose `previewOpen` (the established bar popup pattern).
// Being a child item is what lets it resolve which screen's bar it's on.
Item {
    id: target

    required property string name
    required property Item widget
    readonly property string screenName: QsWindow.window?.screen?.name ?? ""

    visible: false

    Component.onCompleted: {
        if (target.name.length > 0)
            BarPopups.register(target);
    }
    Component.onDestruction: BarPopups.unregister(target)
}
