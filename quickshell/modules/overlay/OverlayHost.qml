pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.bolt

// One overlay-layer window per screen hosting every OverlaySurface and the
// bolts (see Overlays.qml). Instantiate once from shell.qml.
//
// Mapped only while it has something on it (plus BoltConfig.lingerMs so
// rapid follow-ups reuse the surface), so there's no idle fullscreen layer
// sitting over everything and blocking direct scanout. Unmapping is safe:
// it never holds the keyboard by then, and with focus owned through
// Exclusive interactivity no other layer's unmap can steal it.
//
// Needs a Hyprland layer rule disabling animations for the
// "quickshell:overlay" namespace (hypr/hyprland/rules.lua) - otherwise the
// compositor's layersIn fade eats most of a bolt and fades every popup in.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: host

            required property ShellScreen modelData
            readonly property string screenName: host.modelData.name

            property var surfaces: []
            readonly property bool modal: Overlays.modalScreen === host.screenName
            readonly property bool busy: host.surfaces.length > 0 || host.modal || bolt.striking || trail.busy

            function attach(surface) {
                surface.parent = layer;
                host.surfaces = host.surfaces.concat([surface]);
            }

            function detach(surface) {
                host.surfaces = host.surfaces.filter(s => s !== surface);
            }

            screen: host.modelData
            visible: host.busy || linger.running
            onBusyChanged: {
                if (host.busy)
                    linger.stop();
                else
                    linger.restart();
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:overlay"
            // Exclusive while something here owns the keyboard: Hyprland
            // then refuses focus to every window (follow_mouse, refocus on
            // unmap, newly mapped apps) and sends all pointer input here.
            // Dropping back to None hands focus to the last window.
            WlrLayershell.keyboardFocus: host.modal ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // Modal: the whole screen, so `backdrop` sees outside presses.
            // Otherwise only the surfaces' own input items.
            mask: host.modal ? null : inputMask

            Region {
                id: inputMask
                regions: host.surfaces.map(s => s.inputRegion)
            }

            Component.onCompleted: Overlays.registerHost(host)
            Component.onDestruction: Overlays.unregisterHost(host)

            Timer {
                id: linger
                interval: BoltConfig.lingerMs
            }

            // Below the surfaces, so it only gets presses none of them took.
            MouseArea {
                id: backdrop
                anchors.fill: parent
                enabled: host.modal
                acceptedButtons: Qt.AllButtons
                onPressed: Overlays.outsidePressed()
            }

            Item {
                id: layer
                anchors.fill: parent
            }

            BoltItem {
                id: bolt
                anchors.fill: parent
            }

            BoltTrail {
                id: trail
                anchors.fill: parent
            }

            // Bolts.strike() requests landing on this screen, in global
            // coordinates.
            Connections {
                id: boltRouter
                target: Bolts

                function toLocal(p) {
                    return Qt.point(p.x - host.modelData.x, p.y - host.modelData.y);
                }

                function contains(p) {
                    const s = host.modelData;
                    return p.x >= s.x && p.x < s.x + s.width && p.y >= s.y && p.y < s.y + s.height;
                }

                function onRequested(from, to, style, path) {
                    if (!boltRouter.contains(to))
                        return;
                    bolt.strike({
                        from: from ? boltRouter.toLocal(from) : null,
                        path: path ? path.map(p => boltRouter.toLocal(p)) : null,
                        to: boltRouter.toLocal(to),
                        style: BoltConfig.styles[style]
                    });
                }
                function onDrawPoint(p) {
                    if (boltRouter.contains(p))
                        trail.addPoint(boltRouter.toLocal(p));
                }
                function onDrawEnded() {
                    trail.end();
                }
            }
        }
    }
}
