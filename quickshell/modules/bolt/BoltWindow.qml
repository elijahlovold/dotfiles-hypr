import QtQuick
import Quickshell
import Quickshell.Wayland

// Click-through fullscreen overlay hosting one BoltItem, for Bolts.strike().
// Bolt.qml creates it on demand and tears it down shortly after the last
// strike. BarPopups opens a pill's popup on impact (style travelMs), so the
// bolt is still crackling while the popup drops open.
//
// Needs a Hyprland layer rule disabling animations for the
// "quickshell:bolt" namespace (hypr/hyprland/rules.lua) - otherwise the
// compositor's own layersIn fade eats most of the bolt's lifetime.
PanelWindow {
    id: root

    signal finished

    function strike(spec) {
        bolt.strike(spec);
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:bolt"
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    mask: Region {}

    BoltItem {
        id: bolt
        anchors.fill: parent
        onFinished: root.finished()
    }
}
