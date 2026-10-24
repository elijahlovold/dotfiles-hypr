pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // f / w in the window cycle through these; the first is the default.
    readonly property var fpsOptions: [15, 10, 24, 30]
    // Output width in px, never upscaled; 0 = the source's own width.
    readonly property var widthOptions: [720, 480, 960, 0]
    // How many recordings (hypr-screenrec recent) the source list shows.
    readonly property int recentCount: 12
    // Where exports go, as <video name>.gif; "" = beside the source video.
    readonly property string outDir: Quickshell.env("HOME") + "/pix/gifs"
}
