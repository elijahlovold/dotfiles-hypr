pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.bolt
import qs.modules.overlay

// Grid-tile wallpaper picker, replacing an nsxiv-based flow. Directory
// listing via FolderListModel (native, no subprocess). Thumbnails are
// generated once via vipsthumbnail into a persistent disk cache keyed by
// filename (single flat directory, so basenames are already unique) and
// reused on every subsequent open - only new/changed files regenerate.
// A modal OverlaySurface (modules/overlay) centered on the focused screen,
// like KeytreePanel.qml.
OverlaySurface {
    id: root

    modal: true
    inputItem: contentItem
    z: 1

    // ── Panel geometry ─────────────────────────────────────────────────────────
    // The panel is sized to a whole number of tile columns/rows rather than
    // an arbitrary screen fraction, so the grid fills exactly to its last
    // full tile with no leftover partial-cell gap on the right or bottom.
    // ~72%/78% of the screen is the target size; columns/rows round to
    // whatever whole tile count lands closest to that, then the panel
    // shrinks to exactly fit them (clamped so it can never exceed the
    // actual screen even if rounding would overshoot).
    readonly property int cellW: ImagePickerConfig.tileSize + 10
    readonly property int cellH: ImagePickerConfig.tileSize + 10
    readonly property int panelMargin: 18
    readonly property int chrome: panelMargin * 2

    readonly property int screenWidth: root.screen?.width ?? 0
    readonly property int screenHeight: root.screen?.height ?? 0
    readonly property int columns: Math.max(1, Math.min(Math.round((root.screenWidth * 0.72 - chrome) / cellW), Math.floor((root.screenWidth - chrome) / cellW)))
    readonly property int rows: Math.max(1, Math.min(Math.round((root.screenHeight * 0.78 - chrome) / cellH), Math.floor((root.screenHeight - chrome) / cellH)))

    // ── Directory listing ─────────────────────────────────────────────────────
    FolderListModel {
        id: folderModel
        folder: Qt.resolvedUrl("file://" + ImagePickerConfig.directory)
        nameFilters: [...ImagePickerConfig.imageExtensions, ...ImagePickerConfig.videoExtensions].map(ext => "*." + ext)
        sortField: FolderListModel.Name
        sortReversed: false
        showDirs: false
        showFiles: true
        caseSensitive: false
        // Deferred, so a listing that lands in several count steps rebuilds
        // once.
        onCountChanged: Qt.callLater(root.rebuildImages)
    }

    property var images: []
    property int currentIndex: 0

    // The wallpaper to open on (ImagePicker keeps it across opens); moved
    // reports each new position back. Not while a listing resets the grid.
    property string startPath
    signal moved(string path)
    property bool rebuilding: false

    // ── Lightning between selections (modules/bolt, BoltConfig.picker) ───────
    // Same edge-to-edge jump as window focus moves (Bolts.facingPoints), in
    // the grid's content coordinates - so it scrolls along with the view.
    property int lastIndex: 0

    function tileRect(i) {
        return {
            x: (i % root.columns) * root.cellW + 5,
            y: Math.floor(i / root.columns) * root.cellH + 5,
            w: ImagePickerConfig.tileSize,
            h: ImagePickerConfig.tileSize
        };
    }

    onCurrentIndexChanged: {
        if (!root.rebuilding && root.images[root.currentIndex])
            root.moved(root.images[root.currentIndex].path);
        const from = root.lastIndex;
        root.lastIndex = root.currentIndex;
        if (from < 0 || from >= root.images.length || from === root.currentIndex || !Bolts.active("picker"))
            return;
        const pts = Bolts.facingPoints(root.tileRect(from), root.tileRect(root.currentIndex), BoltConfig.picker);
        if (pts)
            pickerBolt.strike({ from: pts[0], to: pts[1], style: BoltConfig.styles.picker });
    }

    function rebuildImages() {
        const list = [];
        for (let i = 0; i < folderModel.count; i++) {
            const path = folderModel.get(i, "filePath");
            if (!path)
                continue;
            list.push({
                path: path,
                thumbPath: root.thumbFor(path),
                ready: false
            });
        }
        const start = Math.max(0, list.findIndex(img => img.path === root.startPath));
        root.rebuilding = true;
        root.images = list;
        // -1 while resetting so the reset itself doesn't strike, then set
        // directly, as the change handler doesn't run when currentIndex
        // already had that value.
        root.lastIndex = -1;
        root.currentIndex = start;
        root.lastIndex = start;
        root.rebuilding = false;
        Qt.callLater(() => grid.positionViewAtIndex(root.currentIndex, GridView.Center));
        root.startThumbnailGeneration();
    }

    // ── Thumbnail generation (vipsthumbnail for images, ffmpeg frame-grab
    // for videos, both batched, both disk-cached) ─────────────────────────────
    property bool generating: false

    // First loop marks already-cached files ready immediately (fast path -
    // just filesystem stat calls, no image/video processing) so a warm
    // cache shows the whole grid almost instantly; only truly new/changed
    // files get regenerated, split by extension into images (batched
    // through vipsthumbnail, chunks of 24 - it takes many inputs per call)
    // and videos (ffmpeg only takes one input per call, so those run in a
    // per-file loop instead - still fine since video wallpapers are
    // typically a much smaller set than image ones).
    readonly property string genScript: [
        'set -uo pipefail',
        'shopt -s nocasematch',
        'cachedir="$1"; shift',
        'size="$1"; shift',
        'videoext="$1"; shift',
        'mkdir -p "$cachedir"',
        'chunk=24',
        'video_re="\\.(${videoext})$"',
        'image_stale=()',
        'video_stale=()',
        'for f in "$@"; do',
        '    b="${f##*/}"',
        '    thumb="$cachedir/${b%.*}.png"',
        '    if [ ! -f "$thumb" ] || [ "$f" -nt "$thumb" ]; then',
        '        if [[ "$f" =~ $video_re ]]; then',
        '            video_stale+=("$f")',
        '        else',
        '            image_stale+=("$f")',
        '        fi',
        '    else',
        '        echo "FILE $f"',
        '    fi',
        'done',
        'n=${#image_stale[@]}',
        'i=0',
        'while [ "$i" -lt "$n" ]; do',
        '    batch=("${image_stale[@]:$i:$chunk}")',
        '    vipsthumbnail "${batch[@]}" -s "$size" --path="$cachedir/%s.png" 2>/dev/null',
        '    for f in "${batch[@]}"; do',
        '        echo "FILE $f"',
        '    done',
        '    i=$((i + chunk))',
        'done',
        'for f in "${video_stale[@]}"; do',
        '    b="${f##*/}"',
        '    thumb="$cachedir/${b%.*}.png"',
        '    ffmpeg -y -ss 1 -i "$f" -vframes 1 -vf "scale=${size}:-1" "$thumb" >/dev/null 2>&1',
        '    echo "FILE $f"',
        'done',
        'echo "GENDONE"'
    ].join("\n")

    function startThumbnailGeneration() {
        if (root.images.length === 0)
            return;
        genProc.command = ["bash", "-c", root.genScript, "imagepicker-thumbgen",
            ImagePickerConfig.cacheDir, String(ImagePickerConfig.thumbnailSize),
            ImagePickerConfig.videoExtensions.join("|"),
            ...root.images.map(img => img.path)];
        root.generating = true;
        genProc.running = true;
    }

    function thumbFor(path) {
        const b = path.split("/").pop();
        const dot = b.lastIndexOf(".");
        return ImagePickerConfig.cacheDir + "/" + (dot > 0 ? b.slice(0, dot) : b) + ".png";
    }

    // Each reassignment of `images` resets the whole GridView (every tile
    // delegate and its Image rebuilt), so "ready" lines are collected and
    // applied once per batch the script's output arrives in - not once per
    // file, which was 90 resets per open with a warm cache.
    property var pendingReady: ({})

    function markReady(path) {
        root.pendingReady[path] = true;
        Qt.callLater(root.flushReady);
    }

    function flushReady() {
        const done = root.pendingReady;
        root.pendingReady = {};
        // A new model array resets the view to the top; keep it where it was.
        const y = grid.contentY;
        root.images = root.images.map(img => done[img.path] ? {
            path: img.path,
            thumbPath: img.thumbPath,
            ready: true
        } : img);
        grid.contentY = y;
    }

    Process {
        id: genProc
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line === "GENDONE") {
                    root.generating = false;
                    return;
                }
                const m = line.match(/^FILE (.+)$/);
                if (m)
                    root.markReady(m[1]);
            }
        }
    }

    // ── Vim-style grid navigation ─────────────────────────────────────────────
    // Rows are treated as vim "lines": 0/$ jump to row start/end, gg/G jump to
    // the very first/last tile, gm jumps to the row's middle tile.
    function rowStart(i) {
        return Math.floor(i / root.columns) * root.columns;
    }
    function rowEnd(i) {
        return Math.min(root.images.length - 1, root.rowStart(i) + root.columns - 1);
    }
    function rowMiddle(i) {
        const start = root.rowStart(i);
        const end = root.rowEnd(i);
        return start + Math.floor((end - start) / 2);
    }

    // ── Selection ──────────────────────────────────────────────────────────────
    function selectIndex(i) {
        if (i < 0 || i >= root.images.length)
            return;
        // The picked tile's center (global px) is where the wallpaper
        // transition starts from - see quickshell-wall.
        const tile = grid.itemAtIndex(i);
        const p = tile ? tile.mapToItem(null, tile.width / 2, tile.height / 2) : null;
        const origin = p ? Math.round(p.x + root.screen.x) + "," + Math.round(p.y + root.screen.y) : "";
        Quickshell.execDetached(["qs", "-p", ImagePickerConfig.wallpaperShell, "ipc", "call", "wallpaper", "set", root.images[i].path, origin]);
        root.dismissed();
    }

    Item {
        id: contentItem
        anchors.centerIn: parent
        width: root.columns * root.cellW + root.chrome
        height: root.rows * root.cellH + root.chrome
        focus: true

        // Set by a bare "g" press, consumed by the following "g"/"m" to form
        // the gg/gm two-key sequences; cleared on timeout or any other key.
        property bool pendingG: false

        Timer {
            id: gTimer
            interval: 600
            onTriggered: contentItem.pendingG = false
        }

        Keys.onPressed: event => {
            if (contentItem.pendingG) {
                contentItem.pendingG = false;
                gTimer.stop();
                if (event.text === "g") {
                    root.currentIndex = 0;
                    event.accepted = true;
                    return;
                } else if (event.text === "m") {
                    root.currentIndex = root.rowMiddle(root.currentIndex);
                    event.accepted = true;
                    return;
                }
            }

            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                root.dismissed();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.selectIndex(root.currentIndex);
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                root.currentIndex = Math.max(0, root.currentIndex - 1);
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                root.currentIndex = Math.min(root.images.length - 1, root.currentIndex + 1);
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                root.currentIndex = Math.max(0, root.currentIndex - root.columns);
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                root.currentIndex = Math.min(root.images.length - 1, root.currentIndex + root.columns);
            } else if (event.text === "g") {
                contentItem.pendingG = true;
                gTimer.restart();
            } else if (event.text === "G") {
                root.currentIndex = root.images.length - 1;
            } else if (event.text === "$") {
                root.currentIndex = root.rowEnd(root.currentIndex);
            } else if (event.text === "0") {
                root.currentIndex = root.rowStart(root.currentIndex);
            } else {
                return;
            }
            event.accepted = true;
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: 16
            color: Theme.pillBg
            border.color: Theme.pillBorder
            border.width: 1

            Item {
                anchors.fill: parent
                anchors.margins: root.panelMargin

                GridView {
                    id: grid
                    anchors.fill: parent
                    cellWidth: root.cellW
                    cellHeight: root.cellH
                    cacheBuffer: ImagePickerConfig.tileSize * 4
                    clip: true
                    model: root.images
                    currentIndex: root.currentIndex

                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            id: card
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 8
                            color: Theme.hoverBg
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: tile.modelData.ready ? Qt.resolvedUrl(tile.modelData.thumbPath) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }

                            // Selection frame: black ring against the image itself
                            // (works regardless of the image's own colors) plus a
                            // brighter outer ring against the dark panel behind it.
                            // Overlaid rather than baked into `card`'s own border so
                            // the image's layout never shifts on selection change.
                            Rectangle {
                                visible: tile.index === root.currentIndex
                                anchors.fill: parent
                                radius: parent.radius
                                color: "transparent"
                                border.width: 3
                                border.color: "black"
                            }
                            Rectangle {
                                visible: tile.index === root.currentIndex
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: Math.max(0, parent.radius - 3)
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.accent
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentIndex = tile.index;
                                root.selectIndex(tile.index);
                            }
                        }
                    }
                }

                // Bolt layer over the grid, clipped like it and moved with its
                // scrolling contentItem, so bolt points share the delegates'
                // content coordinates (see root.tileRect). Not a child of the
                // GridView - it keeps declared children on the view itself,
                // not in contentItem, even with an explicit parent.
                Item {
                    anchors.fill: grid
                    clip: true
                    z: 1

                    BoltItem {
                        id: pickerBolt
                        x: grid.contentItem.x
                        y: grid.contentItem.y
                        width: grid.width
                        height: Math.max(grid.height, grid.contentHeight)
                    }
                }
            }
        }
    }
}
