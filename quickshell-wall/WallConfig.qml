pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheDir: Quickshell.env("XDG_CACHE_HOME") || root.home + "/.cache"

    // ---- Paths ----
    // Wallpapers are <name>.mp4 videos, each with a <name>.png still beside
    // it - the still is what the image picker shows and what wallust themes
    // from. Searched recursively.
    readonly property string videoDir: root.home + "/vids/wallpapers"
    // The playing video's path or URL, rewritten on every switch. Read back
    // when startup is "last".
    readonly property string stateFile: root.cacheDir + "/current_wallpaper"
    // wallust's output for the main shell's Theme (see
    // quickshell/modules/theme/Theme.qml) - transitions take their edge
    // colour from it.
    readonly property string paletteFile: root.cacheDir + "/quickshell/palette.json"
    // `qs ipc call wallpaper stream` - the Stevens Pass cam.
    readonly property string streamUrl: "https://streamer8.brownrice.com/stevenspassjupiter/stevenspassjupiter.stream/main_playlist.m3u8"

    // ---- Commands ----
    // Run with the new video's still appended, once that video is playing.
    readonly property var themeCommand: ["wallust", "run"]
    // `qs ipc call wallpaper clear` - back to the default theme.
    readonly property var clearThemeCommand: ["wallust", "cs", "default"]

    // ---- Playback ----
    // Output the wallpaper plays on. While it's disconnected or disabled
    // (hypr-toggle-monitors' solo mode) nothing plays.
    readonly property string screen: "DP-2"
    // On launch: "random" picks a new one, "last" resumes stateFile's.
    readonly property string startup: "random"
    // Pause while the screen's workspace has a fullscreen window (what
    // mpvpaper's -p did).
    readonly property bool pauseOnFullscreen: true

    // ---- Transitions ----
    // One of effects, or "random". Switchable live, until the next start:
    //   qs -p <this dir> ipc call wallpaper effect <name>
    readonly property string effect: "pixelate"
    // Each but fade is shaders/<name>.frag.qsb.
    readonly property var effects: ["shatter", "dissolve", "scroll", "ripple", "blinds", "pixelate", "fade"]
    // "in": the effect brings the new video in over the old one (shaders
    // run backwards). "out": it takes the old one away, revealing the new.
    readonly property string direction: "in"
    readonly property int durationMs: 700
    // Effect scale, as a fraction of the screen height: shatter's shard
    // size, and the others' roll radius, wave, slat and block sizes scale
    // with it.
    readonly property real cellSize: 0.13
    // Lightning effects for variosu shaders
    readonly property bool lightning: true

    // WALL_STATS=1: log fps / frame gaps / loops every 5s (Stats.qml).
    readonly property bool stats: Quickshell.env("WALL_STATS") === "1"
}
