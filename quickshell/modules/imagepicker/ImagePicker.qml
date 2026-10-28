import QtQuick
import Quickshell
import Quickshell.Io

// Entry point: instantiate once from shell.qml.
//   qs ipc call imagepicker toggle
Scope {
    id: root

    property bool open: false

    // Where the picker reopens: the last wallpaper it was on, kept here
    // because the panel itself is destroyed on close. Survives config
    // reloads; until the first move it's the playing wallpaper's still.
    PersistentProperties {
        id: persist
        reloadableId: "imagepicker"

        property string lastPath
    }

    // quickshell-wall's record of the playing video (or stream URL); the
    // picker lists the stills beside the videos.
    property string currentStill
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/current_wallpaper"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.currentStill = text().trim().replace(/\.[^./]+$/, ".png")
    }

    function toggle() {
        root.open = !root.open;
    }

    IpcHandler {
        target: "imagepicker"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.open = true;
        }
        function close(): void {
            root.open = false;
        }
    }

    Loader {
        active: root.open
        sourceComponent: ImagePickerPanel {
            startPath: persist.lastPath || root.currentStill
            onDismissed: root.open = false
            onMoved: path => persist.lastPath = path
        }
    }
}
