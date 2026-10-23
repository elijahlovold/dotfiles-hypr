pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The portrait monitor's wallpaper: a still from WallConfig.portraitCommand,
// re-rendered each time wallust rewrites the palette - whoever ran it (a
// video switch, `wallpaper clear`, the main shell's theme switcher). The new
// render fades in over the old one.
PanelWindow {
    id: root

    // Bumped per finished render; part of the image URL so Qt re-reads the
    // file instead of serving its cached copy.
    property int revision: 0
    // Image currently on top; the other one holds the previous render.
    property Image front: imageA

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "black"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell:wallpaper-portrait"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    function render() {
        // A change mid-render: run again once this one exits.
        if (renderer.running) {
            renderer.pending = true;
            return;
        }
        renderer.running = true;
    }

    function showLatest() {
        const back = root.front === imageA ? imageB : imageA;
        back.source = "file://" + WallConfig.portraitFile + "?" + (++root.revision);
    }

    Process {
        id: renderer

        property bool pending: false

        command: WallConfig.portraitCommand
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text)
                    console.warn("wallpaper: portrait:", this.text.trim());
            }
        }
        onExited: code => {
            if (code === 0)
                root.showLatest();
            if (renderer.pending) {
                renderer.pending = false;
                renderer.running = true;
            }
        }
    }

    FileView {
        path: WallConfig.paletteFile
        printErrors: false
        watchChanges: true
        // A single wallust run can write it more than once; render() folds
        // those into at most one extra run.
        onFileChanged: root.render()
    }

    Component.onCompleted: root.render()

    component Still: Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: 0
        Behavior on opacity {
            NumberAnimation {
                duration: WallConfig.durationMs
                easing.type: Easing.InOutQuad
            }
        }
        // Swap to the front only once decoded, so the fade never starts
        // from a blank frame.
        onStatusChanged: {
            if (status !== Image.Ready)
                return;
            const old = root.front;
            root.front = this;
            z = 1;
            old.z = 0;
            opacity = 1;
        }
        // The one underneath stays opaque until the new one has covered it.
        onOpacityChanged: {
            if (opacity === 1 && root.front === this)
                (this === imageA ? imageB : imageA).opacity = 0;
        }
    }

    Still {
        id: imageA
    }

    Still {
        id: imageB
    }
}
