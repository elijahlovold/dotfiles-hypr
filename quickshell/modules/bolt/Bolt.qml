pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// Draws Bolts.strike() requests - one BoltWindow per screen, created on
// demand. Instantiate once from shell.qml. The overlay surface only exists
// while bolts are on screen (plus BoltConfig.lingerMs so rapid follow-ups
// reuse it), so there's no idle fullscreen layer sitting over everything
// (and blocking direct scanout).
Scope {
    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen

            required property ShellScreen modelData
            property var pending: null

            Connections {
                target: Bolts
                function onRequested(from, to, style, path) {
                    const s = perScreen.modelData;
                    if (to.x < s.x || to.x >= s.x + s.width || to.y < s.y || to.y >= s.y + s.height)
                        return;
                    const spec = {
                        from: from ? Qt.point(from.x - s.x, from.y - s.y) : null,
                        path: path ? path.map(p => Qt.point(p.x - s.x, p.y - s.y)) : null,
                        to: Qt.point(to.x - s.x, to.y - s.y),
                        style: BoltConfig.styles[style]
                    };
                    lingerTimer.stop();
                    if (boltLoader.item) {
                        boltLoader.item.strike(spec);
                    } else {
                        perScreen.pending = spec;
                        boltLoader.active = true;
                    }
                }
            }

            Loader {
                id: boltLoader
                active: false
                sourceComponent: BoltWindow {
                    screen: perScreen.modelData
                    onFinished: lingerTimer.restart()
                }
                onLoaded: {
                    boltLoader.item.strike(perScreen.pending);
                    perScreen.pending = null;
                }
            }

            Timer {
                id: lingerTimer
                interval: BoltConfig.lingerMs
                onTriggered: boltLoader.active = false
            }
        }
    }
}
