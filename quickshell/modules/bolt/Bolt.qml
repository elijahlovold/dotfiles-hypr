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
            // Calls queued while the window is still being created.
            property var pending: []

            function contains(p) {
                const s = perScreen.modelData;
                return p.x >= s.x && p.x < s.x + s.width && p.y >= s.y && p.y < s.y + s.height;
            }

            function run(call) {
                lingerTimer.stop();
                if (boltLoader.item) {
                    call(boltLoader.item);
                } else {
                    perScreen.pending.push(call);
                    boltLoader.active = true;
                }
            }

            Connections {
                target: Bolts
                function onRequested(from, to, style, path) {
                    const s = perScreen.modelData;
                    if (!perScreen.contains(to))
                        return;
                    const spec = {
                        from: from ? Qt.point(from.x - s.x, from.y - s.y) : null,
                        path: path ? path.map(p => Qt.point(p.x - s.x, p.y - s.y)) : null,
                        to: Qt.point(to.x - s.x, to.y - s.y),
                        style: BoltConfig.styles[style]
                    };
                    perScreen.run(w => w.strike(spec));
                }
                function onDrawPoint(p) {
                    if (!perScreen.contains(p))
                        return;
                    const s = perScreen.modelData;
                    const local = Qt.point(p.x - s.x, p.y - s.y);
                    perScreen.run(w => w.drawPoint(local));
                }
                function onDrawEnded() {
                    // A quick click can end before the window finished
                    // loading - queue it so the trail isn't left open.
                    if (boltLoader.item)
                        boltLoader.item.drawEnd();
                    else if (perScreen.pending.length > 0)
                        perScreen.pending.push(w => w.drawEnd());
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
                    const calls = perScreen.pending;
                    perScreen.pending = [];
                    for (const call of calls)
                        call(boltLoader.item);
                }
            }

            Timer {
                id: lingerTimer
                interval: BoltConfig.lingerMs
                onTriggered: {
                    if (!(boltLoader.item?.busy ?? false))
                        boltLoader.active = false;
                }
            }
        }
    }
}
