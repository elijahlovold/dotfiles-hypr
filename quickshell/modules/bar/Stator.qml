pragma ComponentBehavior: Bound
import QtQuick

PollingLabel {
    id: statorLabel

    command: ["stator-rs", "--get-state"]
    interval: 1000
    prefix: "󱇯  "
    popupName: "stator"
    leftClickCommand: ["qs", "ipc", "call", "keytree", "toggle", "stator"]
    popupComponent: Component {
        StatorPreview {
            anchorItem: statorLabel
        }
    }
}
