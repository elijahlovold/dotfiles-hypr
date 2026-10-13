pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common

// Lightning strikes for BarPopups.summon() - one short-lived BoltWindow on
// whichever screen the target pill is on. Instantiate once from shell.qml.
// The overlay surface only exists during a strike, so there's no idle
// fullscreen layer sitting over everything (and blocking direct scanout).
Scope {
    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen

            required property ShellScreen modelData
            property real targetX: 0
            property real targetY: 0

            Connections {
                target: BarPopups
                function onStrike(screenName, x, y) {
                    if (screenName !== perScreen.modelData.name)
                        return;
                    perScreen.targetX = x;
                    perScreen.targetY = y;
                    // Restart cleanly if a strike is still on screen.
                    boltLoader.active = false;
                    boltLoader.active = true;
                }
            }

            Loader {
                id: boltLoader
                active: false
                sourceComponent: BoltWindow {
                    screen: perScreen.modelData
                    targetX: perScreen.targetX
                    targetY: perScreen.targetY
                    // Deferred - don't destroy the window from inside its own signal.
                    onFinished: Qt.callLater(() => boltLoader.active = false)
                }
            }
        }
    }
}
