import QtQml
import Quickshell
import qs.modules.bar
import qs.modules.keytree
import qs.modules.imagepicker
import qs.modules.keybinds
import qs.modules.desktop
import qs.modules.theme
import qs.modules.reticle
import qs.modules.draw
import qs.modules.notifications
import qs.modules.clipboard
import qs.modules.bolt
import qs.modules.gif
import qs.modules.screens

ShellRoot {
    Connections {
        target: Quickshell

        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();
            Quickshell.execDetached(["notify-send", "-t", "1000", "-u", "low", "-a", "Quickshell", "Quickshell", "Reloaded"]);
        }

        function onReloadFailed(errorString) {
            Quickshell.inhibitReloadPopup();
            // Category tags it for NotificationCard's click-to-copy.
            Quickshell.execDetached(["notify-send", "-u", "critical", "-c", "quickshell.error", "-a", "Quickshell", "Quickshell", "Reload failed: " + errorString]);
        }
    }

    Bar {}
    Keytree {}
    ImagePicker {}
    Keybinds {}
    Desktop {}
    ThemeSwitcher {}
    Reticle {}
    Draw {}
    Notifications {}
    Clipboard {}
    Bolt {}
    Gif {}
    Screens {}
}
