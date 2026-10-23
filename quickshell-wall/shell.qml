//@ pragma Env QT_QPA_PLATFORM=wayland
//@ pragma Env QSG_RHI_BACKEND=opengl
//@ pragma Env QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// The video wallpaper, played by Quickshell (Qt Multimedia) instead of
// mpvpaper, so a switch can run an effect between two live videos. Its own
// instance, separate from ../quickshell, so that config's hot reloads never
// restart the wallpaper. Started by hypr/hyprland/start.lua:
//   qs -p ~/.config/dotfiles-hypr/quickshell-wall -n
// and driven over IPC (keybinds.lua, the main shell's image picker):
//   qs -p <that dir> ipc call wallpaper <function> [args]
// Paths and behaviour live in WallConfig.qml.
//
// A reload (any .qml here changing) restarts the players but keeps the
// current video, effect and theme - see persist. Shader edits need a
// restart (WallpaperWindow).
//
// Hardware path: Qt's ffmpeg backend decodes on VAAPI and imports the
// decoded surfaces into GL as EGLImages (VAAPITextureConverter) - no copy
// through system memory, measured at mpvpaper's CPU/GPU cost. That import
// needs the OpenGL RHI and an EGL display from the platform: Wayland has
// one, xcb doesn't (and Qt picked xcb here when left to choose), and then
// every decoded frame is copied back through system memory - ~10x the CPU.
// Hence the first two pragmas; the last keeps ffmpeg to VAAPI.
ShellRoot {
    id: root

    // Video path or stream URL playing; "" before the first one starts.
    property string current: ""
    // The latest one asked for - current, or one still loading.
    property string target: ""
    // Still last passed to wallust, so re-showing the same video (screen
    // re-enabled, a reload) doesn't re-theme.
    property alias themed: persist.themed
    // `ipc call wallpaper effect` wins until WallConfig.effect is edited.
    readonly property string effect: persist.effectOverride || WallConfig.effect

    readonly property ShellScreen screen: Quickshell.screens.find(s => s.name === WallConfig.screen) ?? null

    // path: a video, a stream URL, or a video's .png still (what the image
    // picker lists). origin: "x,y" in global px for the effect to start
    // from, or "" for the screen centre.
    function show(path, origin) {
        const video = path.replace(/\.png$/, ".mp4");
        root.target = video;
        windowLoader.item?.switchTo(video, origin);
    }

    // Once the new video is actually playing: theme from its still and
    // record it - a file that fails to play changes neither.
    function onSwitched(path) {
        console.info("wallpaper: playing", path);
        root.current = path;
        stateFile.setText(path + "\n");
        const still = /^\/.*\.[^./]+$/.test(path) ? path.replace(/\.[^./]+$/, ".png") : "";
        if (still && still !== root.themed) {
            root.themed = still;
            Quickshell.execDetached(WallConfig.themeCommand.concat([still]));
        }
    }

    // The window stays on (or falls back to black from) whatever it had.
    function onFailed(path) {
        if (root.current === path)
            root.current = "";
        if (root.target === path)
            root.target = root.current;
    }

    function random(origin) {
        finder.origin = origin;
        finder.running = true;
    }

    function stop() {
        root.current = "";
        root.target = "";
    }

    // A random video with a still beside it, other than the current one.
    Process {
        id: finder

        property string origin: ""

        command: ["find", WallConfig.videoDir, "-type", "f", "(", "-name", "*.mp4", "-o", "-name", "*.png", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                const files = new Set(this.text.split("\n"));
                const videos = [...files].filter(f => f.endsWith(".mp4") && files.has(f.replace(/\.mp4$/, ".png")) && f !== root.target);
                if (videos.length === 0) {
                    console.warn("wallpaper: no <name>.mp4 + <name>.png pairs in", WallConfig.videoDir);
                    return;
                }
                root.show(videos[Math.floor(Math.random() * videos.length)], finder.origin);
            }
        }
    }

    FileView {
        id: stateFile
        path: WallConfig.stateFile
        blockLoading: true
        printErrors: false
    }

    Loader {
        id: windowLoader
        // Unloading releases both players; a screen coming back reloads
        // the current video without a transition.
        active: root.screen !== null && root.target !== ""
        sourceComponent: WallpaperWindow {
            screen: root.screen
            effectSetting: root.effect
            onSwitched: path => root.onSwitched(path)
            onFailed: path => root.onFailed(path)
            Component.onCompleted: switchTo(root.target, "")
        }
    }

    onCurrentChanged: persist.current = root.current

    // No reload popup over the desktop - same handling as the main shell.
    Connections {
        target: Quickshell

        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();
            console.info("wallpaper: reloaded");
        }

        function onReloadFailed(errorString) {
            Quickshell.inhibitReloadPopup();
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell", "Wallpaper", "Reload failed: " + errorString]);
        }
    }

    // Carried across reloads.
    PersistentProperties {
        id: persist
        reloadableId: "wallpaper"

        property bool started: false
        property string current: ""
        property string themed: ""
        // Set by `ipc call wallpaper effect`; "" = use WallConfig.effect.
        property string effectOverride: ""
        // WallConfig.effect as of the last load, to spot an edit to it.
        property string configEffect: WallConfig.effect

        onLoaded: {
            // Editing WallConfig.effect (which reloads) beats an earlier
            // IPC choice - otherwise the edit would do nothing.
            if (persist.configEffect !== WallConfig.effect)
                persist.effectOverride = "";
            persist.configEffect = WallConfig.effect;
            if (persist.started) {
                // A reload: back to what was playing (nothing, if stopped).
                if (persist.current)
                    root.show(persist.current, "");
                return;
            }
            persist.started = true;
            const last = stateFile.text().trim();
            if (WallConfig.startup === "last" && last)
                root.show(last, "");
            else
                root.random("");
        }
    }

    IpcHandler {
        target: "wallpaper"

        // A video, stream URL or a video's .png still; origin "x,y" global
        // px or "".
        function set(path: string, origin: string): void {
            root.show(path, origin);
        }
        function random(): void {
            root.random("");
        }
        function stream(): void {
            root.show(WallConfig.streamUrl, "");
        }
        // Unloads the players and the surface; any set/random/stream resumes.
        function stop(): void {
            root.stop();
        }
        // stop, and back to the default theme.
        function clear(): void {
            root.stop();
            root.themed = "";
            Quickshell.execDetached(WallConfig.clearThemeCommand);
        }
        // One of WallConfig.effects or "random", for the next switches.
        function effect(name: string): string {
            if (name !== "random" && !WallConfig.effects.includes(name))
                return "unknown effect - one of: random " + WallConfig.effects.join(" ");
            persist.effectOverride = name;
            return name;
        }
        function current(): string {
            return root.current;
        }
    }
}
