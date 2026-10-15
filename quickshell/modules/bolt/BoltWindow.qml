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

    // A strike or a Super+Ctrl drawing still on screen - Bolt.qml keeps
    // the window until neither is.
    readonly property bool busy: bolt.striking || trail.busy

    function strike(spec) {
        bolt.strike(spec);
    }

    function drawPoint(p) {
        trail.addPoint(p);
    }

    function drawEnd() {
        trail.end();
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

    BoltTrail {
        id: trail
        anchors.fill: parent
        onFinished: root.finished()
    }
}
