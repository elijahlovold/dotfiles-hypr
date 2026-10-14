import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.bolt

// Entry point: instantiate once from shell.qml. Toggled from the bar
// (DesktopWidgetToggle.qml) or via IPC, same pattern as Keytree/ImagePicker:
//   qs ipc call desktop toggle
//   qs ipc call desktop edit
Scope {
    id: root

    // Bolt from the bar's toggle to the card on show/hide (BoltConfig.desktop).
    // Deferred so a freshly shown card has been created and reported its rect.
    Connections {
        target: DesktopOverlayStore
        function onToggled(shown) {
            Qt.callLater(() => {
                const r = DesktopOverlayStore.cardRect;
                if (r && r.w > 0 && Bolts.active("desktop"))
                    Bolts.strike(Bolts.anchorPoint("desktop"), Qt.point(r.x + r.w / 2, r.y + r.h / 2), "desktop");
            });
        }
    }

    IpcHandler {
        target: "desktop"

        function toggle(): void {
            DesktopOverlayStore.toggleVisible();
        }
        function show(): void {
            DesktopOverlayStore.setVisible(true);
        }
        function hide(): void {
            DesktopOverlayStore.setVisible(false);
        }
        function edit(): void {
            DesktopOverlayStore.toggleEditMode();
        }
    }

    // Stays instantiated (just internally invisible) across editMode
    // toggles, so the typewriter animation/weather fetch state don't reset
    // every time you open the edit overlay - see its own `visible` binding.
    Loader {
        active: DesktopOverlayStore.visible
        sourceComponent: DesktopOverlayWindow {}
    }

    Loader {
        active: DesktopOverlayStore.editMode
        sourceComponent: DesktopEditOverlay {}
    }
}
