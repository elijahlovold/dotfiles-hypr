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
    // Caption (t in the window). n cycles the fonts, v the variants, -/= the
    // sizes; the first of each is the default. family is a fontconfig name;
    // fc is the fontconfig style the export resolves, weight/italic how the
    // preview draws it. A variant a font lacks falls back the same way in both.
    readonly property var captionFonts: [
        { name: "Sans", family: "Noto Sans" },
        { name: "Serif", family: "Noto Serif" },
        { name: "Mono", family: "Liberation Mono" }
    ]
    readonly property var captionVariants: [
        { name: "Bold", fc: "bold", weight: 700, italic: false },
        { name: "Black", fc: "black", weight: 900, italic: false },
        { name: "Regular", fc: "regular", weight: 400, italic: false },
        { name: "Italic", fc: "italic", weight: 400, italic: true },
        { name: "Bold Italic", fc: "bold:italic", weight: 700, italic: true }
    ]
    // Font size as a fraction of the GIF's height.
    readonly property var captionSizes: [
        { name: "M", scale: 0.08 },
        { name: "L", scale: 0.11 },
        { name: "XL", scale: 0.15 },
        { name: "S", scale: 0.06 }
    ]
}
