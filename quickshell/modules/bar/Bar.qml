pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.theme
import qs.modules.common
import Quickshell.Io
import Qt5Compat.GraphicalEffects

Scope {
    // Show/hide every bar: Super+Ctrl+Space sends `custom>>bar:toggle` from
    // the Hyprland bind (no process spawned); `qs ipc call bar toggle` works
    // too. Hidden bars are unmapped, not destroyed - widgets keep their
    // state, and their exclusive zone goes away so windows take the space.
    IpcHandler {
        target: "bar"

        function toggle(): void {
            BarPopups.barShown = !BarPopups.barShown;
        }
        function show(): void {
            BarPopups.barShown = true;
        }
        function hide(): void {
            BarPopups.barShown = false;
        }
    }

    // Quickshell's incremental Hyprland state tracking misses workspace-
    // altering actions that don't change global focus - e.g. win+N
    // (movecurrentworkspacetomonitor) fires Hyprland's moveworkspacev2
    // event, but the workspace that was displaced on the destination
    // monitor keeps reporting stale active/focused flags until some
    // unrelated workspace-focus event forces a resync. Force one directly
    // on the event that's known to fall through. Single Connections here
    // (Scope is instantiated once, unlike the per-monitor Variants below).
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent) {
            if (event.name === "custom" && event.data === "bar:toggle") {
                BarPopups.barShown = !BarPopups.barShown;
                return;
            }
            if (event.name === "moveworkspacev2" || event.name === "moveworkspace") {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barRoot

            required property ShellScreen modelData
            screen: barRoot.modelData
            visible: BarPopups.barShown

            // Mirrors the old i3 bar {} blocks: the primary monitor got the full
            // i3status-rust config + tray, the portrait one the short config.
            // Roles go by orientation (see MonitorRoles), so every landscape
            // screen gets the full bar without naming any output.
            readonly property bool full: !MonitorRoles.isSecondary(barRoot.modelData)
            readonly property bool showTray: barRoot.full

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: Theme.barHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Auto
            WlrLayershell.namespace: "quickshell:bar"
            // Never takes the keyboard: popups that need it live in the
            // overlay host (modules/overlay), which owns keyboard focus.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Workspaces {
                id: workspacesItem
                screen: barRoot.modelData
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.bottom: parent.bottom
                // anchors.verticalCenter: parent.verticalCenter
            }

            // Everything past the workspace pill. RightCluster hugs the
            // right edge so the clock and tray always show; on a monitor too
            // narrow for all of it, the overflow runs off this area's left
            // edge (clipped, never over Workspaces) and the cut-off side
            // fades out. The fade masks the whole area at once rather than
            // touching any widget, and only exists while something is cut.
            Item {
                id: rightArea

                readonly property bool overflowing: rightCluster.width > rightArea.width
                readonly property int fadeWidth: 48

                anchors.left: workspacesItem.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                clip: true

                layer.enabled: rightArea.overflowing
                layer.effect: OpacityMask {
                    maskSource: fadeMask
                }

                RightCluster {
                    id: rightCluster
                    full: barRoot.full
                    showTray: barRoot.showTray
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }

            // Widgets kept off the bar but still openable from the keytree.
            // On every bar, so their popups open on whichever monitor has
            // focus (BarPopups.summon picks the focused screen's instance).
            OffBarWidgets {}

            // Mask for rightArea: transparent at its left edge, opaque
            // fadeWidth px in.
            Rectangle {
                id: fadeMask
                width: rightArea.width
                height: rightArea.height
                visible: false
                layer.enabled: rightArea.overflowing
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: Math.min(1, rightArea.fadeWidth / Math.max(1, rightArea.width))
                        color: "black"
                    }
                }
            }
        }
    }
}
