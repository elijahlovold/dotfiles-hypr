pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Singleton: callable directly from the shell (keytree actions). shell.qml
// touches it at startup so the IpcHandler below registers. Trim a screen recording
// (scripts/hypr-screenrec's newest, by default) and export it as a GIF.
//   qs ipc call gif toggle
//   qs ipc call gif open <video>      start on a specific file
//
// The ffmpeg export lives here rather than in GifPanel so closing the
// window mid-export doesn't kill it; the window only shows its progress.
Singleton {
    id: root

    property bool open: false
    // A file to start on instead of the newest recording; "" = newest.
    property string initialFile: ""

    // ── Export ─────────────────────────────────────────────────────────────
    readonly property bool exporting: exportProc.running
    property real progress: 0 // 0..1 of the trimmed duration
    property string outFile: ""
    property real exportDuration: 0 // seconds

    function outPathFor(source) {
        const name = source.split("/").pop().replace(/\.[^.]+$/, "") + ".gif";
        const dir = GifConfig.outDir || source.slice(0, source.lastIndexOf("/"));
        return dir + "/" + name;
    }

    // Single pass: palettegen + paletteuse on a split stream, so the
    // palette is built from exactly the trimmed, scaled frames.
    // stats_mode=diff + diff_mode=rectangle favour what moves, which is
    // most of what a screen recording is about.
    //
    // caption: null, or { text, top, font (fontconfig pattern), scale
    // (fraction of the GIF's height) }. The text goes in through a textfile
    // (with expansion off) and the font as a file fc-match resolves, symlinked
    // to a fixed path - drawtext's font= ignores styles, and neither needs
    // filtergraph escaping this way. It's drawn after scaling so its size is
    // relative to the GIF, and before palettegen so its colours are in the
    // palette.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string captionFile: root.runtimeDir + "/qs-gif-caption.txt"
    readonly property string captionFontFile: root.runtimeDir + "/qs-gif-caption-font"

    function startExport(source, startSec, endSec, fps, width, caption) {
        if (exportProc.running)
            return;
        const scale = width > 0 ? "scale=w='min(" + width + ",iw)':h=-2:flags=lanczos," : "";
        const text = caption ? "drawtext=textfile=" + root.captionFile + ":expansion=none:fontfile=" + root.captionFontFile +
            ":fontcolor=white:borderw=3:bordercolor=black:fontsize=h*" + caption.scale.toFixed(4) +
            ":x=(w-text_w)/2:y=" + (caption.top ? "h/20" : "h-text_h-h/20") + "," : "";
        const filter = "fps=" + fps + "," + scale + text + "split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle";
        root.outFile = root.outPathFor(source);
        root.exportDuration = endSec - startSec;
        root.progress = 0;
        // ffmpeg won't create the output directory itself.
        exportProc.command = ["sh", "-c", 'mkdir -p "$0" && { [ -z "$CAPTION" ] || { printf %s "$CAPTION" > "$CAPTION_FILE" && ' +
            'ln -sf "$(fc-match -f %{file} "$CAPTION_FONT")" "$CAPTION_FONT_FILE"; }; } && exec "$@"', root.outFile.slice(0, root.outFile.lastIndexOf("/")),
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostats", "-progress", "pipe:1", "-y",
            "-ss", startSec.toFixed(3), "-t", (endSec - startSec).toFixed(3), "-i", source,
            "-filter_complex", filter, "-loop", "0", root.outFile];
        exportProc.environment = {
            CAPTION: caption ? caption.text : "",
            CAPTION_FILE: root.captionFile,
            CAPTION_FONT: caption ? caption.font : "",
            CAPTION_FONT_FILE: root.captionFontFile
        };
        exportProc.running = true;
    }

    function cancelExport() {
        if (!exportProc.running)
            return;
        exportProc.cancelled = true;
        exportProc.signal(15);
    }

    Process {
        id: exportProc

        property bool cancelled: false

        onStarted: exportProc.cancelled = false
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/^out_time_us=(\d+)/);
                if (m && root.exportDuration > 0)
                    root.progress = Math.min(1, Number(m[1]) / 1e6 / root.exportDuration);
            }
        }
        stderr: StdioCollector {
            id: exportErr
        }
        onExited: code => {
            if (code === 0) {
                root.progress = 1;
                root.open = false;
                // Same copy-as-file + Open action as hypr-screenrec.
                Quickshell.execDetached(["sh", "-c", 'printf "file://%s\\n" "$1" | wl-copy -t text/uri-list; ' +
                    'size=$(du -h "$1" | cut -f1); ' +
                    'action=$(notify-send -a Quickshell -t 6000 -A open=Open "GIF saved" "$(basename "$1") · $size (copied)"); ' +
                    '[ "$action" = open ] && xdg-open "$1"', "sh", root.outFile]);
            } else if (exportProc.cancelled) {
                Quickshell.execDetached(["rm", "-f", root.outFile]);
            } else {
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-u", "critical", "GIF export failed",
                    exportErr.text.trim().split("\n").slice(-3).join("\n") || "ffmpeg exited " + code]);
            }
        }
    }

    // ── Custom file ────────────────────────────────────────────────────────
    // The window closes first: zenity is an ordinary toplevel, and the
    // overlay window both covers it and dismisses itself on focus loss.
    function browse() {
        root.open = false;
        browseProc.running = true;
    }

    Process {
        id: browseProc
        command: ["zenity", "--file-selection", "--title=GIF source",
            "--file-filter=Videos | *.mp4 *.mkv *.webm *.mov *.avi", "--file-filter=All files | *"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = this.text.trim();
                if (path)
                    root.openFile(path);
            }
        }
    }

    function openFile(path) {
        root.initialFile = path;
        root.open = true;
    }

    function toggle() {
        if (!root.open)
            root.initialFile = "";
        root.open = !root.open;
    }

    IpcHandler {
        target: "gif"

        function toggle(): void {
            root.toggle();
        }
        function open(path: string): void {
            root.openFile(path);
        }
        function close(): void {
            root.open = false;
        }
    }

    Loader {
        active: root.open
        sourceComponent: GifPanel {
            exporter: root
            initialFile: root.initialFile
            onDismissed: root.open = false
        }
    }
}
