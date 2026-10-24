pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The portrait monitor's wallpaper: portrait-base.png (made once by
// make-portrait-base.py) recoloured on the GPU by shaders/portrait.frag
// from three palette roles. A palette change - whoever ran wallust: a video
// switch, `wallpaper clear`, the main shell's theme switcher - just
// animates those three colours; no process, no file.
PanelWindow {
    id: root

    // Picked from the palette by pickRoles(); animated into the shader.
    property color accent
    property color second
    property color light
    // false until the palette has loaded: the base shows uncoloured.
    property bool themed: false

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

    Behavior on accent {
        enabled: root.themed
        ColorAnimation {
            duration: WallConfig.durationMs
            easing.type: Easing.InOutQuad
        }
    }
    Behavior on second {
        enabled: root.themed
        ColorAnimation {
            duration: WallConfig.durationMs
            easing.type: Easing.InOutQuad
        }
    }
    Behavior on light {
        enabled: root.themed
        ColorAnimation {
            duration: WallConfig.durationMs
            easing.type: Easing.InOutQuad
        }
    }

    // Oklab [L, a, b] of an sRGB colour.
    function oklab(c) {
        const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        const r = lin(c.r), g = lin(c.g), b = lin(c.b);
        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
    }

    // accent: color13, the shell's accent. second: the most chromatic
    // colour whose hue is >25deg from it (else just the most chromatic).
    // light: the lightest of the five most chromatic.
    function pickRoles() {
        const names = [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14].map(i => "color" + i);
        const info = {};
        for (const n of names) {
            const [L, a, b] = root.oklab(pal[n]);
            info[n] = {
                L: L,
                chroma: Math.hypot(a, b),
                hue: Math.atan2(b, a)
            };
        }
        const hueGap = (x, y) => Math.abs(((info[x].hue - info[y].hue + 3 * Math.PI) % (2 * Math.PI)) - Math.PI);
        const others = names.filter(n => n !== "color13").sort((x, y) => info[y].chroma - info[x].chroma);
        const second = others.find(n => hueGap(n, "color13") > 25 * Math.PI / 180) ?? others[0];
        const light = others.slice(0, 5).reduce((best, n) => info[n].L > info[best].L ? n : best);
        root.accent = pal.color13;
        root.second = pal[second];
        root.light = pal[light];
        root.themed = true;
    }

    FileView {
        path: WallConfig.paletteFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.pickRoles()

        JsonAdapter {
            id: pal

            property color color1
            property color color2
            property color color3
            property color color4
            property color color5
            property color color6
            property color color9
            property color color10
            property color color11
            property color color12
            property color color13
            property color color14
        }
    }

    Image {
        id: base
        anchors.fill: parent
        source: Qt.resolvedUrl("portrait-base.png")
        fillMode: Image.PreserveAspectCrop
        // Only the shader shows once themed.
        visible: !root.themed
    }

    ShaderEffect {
        anchors.fill: parent
        visible: root.themed && base.status === Image.Ready

        property variant source: base
        property color accent: root.accent
        property color second: root.second
        property color light: root.light

        fragmentShader: Qt.resolvedUrl("shaders/portrait.frag.qsb")
    }
}
