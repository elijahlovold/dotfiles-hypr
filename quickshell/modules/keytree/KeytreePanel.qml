pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.overlay
import qs.modules.bolt
import qs.modules.common

// QML/quickshell port of keytree's C++ KeyTreeModel + Main.qml. A modal
// OverlaySurface covering the focused screen (modules/overlay): while it's
// interactive the overlay host holds Exclusive keyboard focus, so Hyprland
// refuses focus to every window (follow_mouse, refocus on unmap, newly
// mapped apps) until it lets go - nothing has to notice focus loss and win
// it back. Dismissal is explicit instead: Escape, a launch, a click on
// `backdrop`, or another surface taking the keyboard. Emits `dismissed`
// once the close animation has played.
OverlaySurface {
    id: root

    required property string configName

    // Reject (Escape/back-at-root/outside click) and launch both go through
    // this instead of emitting `dismissed` directly, so RadialView's node
    // animations get a chance to play in reverse before the panel (and
    // everything in it) actually gets torn down by Keytree.qml's Loader.
    // Search mode has no entrance animation to reverse, so it still closes
    // immediately.
    property bool closing: false

    function requestClose() {
        if (root.closing)
            return;
        if (root.searchMode) {
            root.dismissed();
            return;
        }
        root.closing = true;
        closeTimer.start();
    }

    // Cancel a close in progress and start over at the root level of
    // `configName`, keeping this surface rather than mapping a fresh one
    // over it while it unmaps. Clearing `closing`/`launched` makes it
    // `interactive` again, taking exclusive keyboard focus back.
    function reopen() {
        closeTimer.stop();
        root.launched = false;
        if (root.searchMode)
            root.exitSearch();
        // Before the level reset, so new node delegates animate in rather
        // than with the closing timings.
        root.closing = false;
        root.stack = [];
        root.backBolts = [];
        root.current = root.virtualRoot;
        Qt.callLater(root.openingSwirl);
    }

    function dismiss() {
        root.requestClose();
    }

    Timer {
        id: closeTimer
        interval: radialView.closeWaitMs
        onTriggered: root.dismissed()
    }

    // Keyboard and input are dropped as soon as the menu starts closing,
    // so neither keys nor clicks are swallowed while the close animation
    // plays - and a launched app maps with nothing holding focus.
    readonly property bool interactive: !root.closing && !root.launched
    modal: root.interactive
    // Above the bar popups.
    z: 1

    // Set when a node/search result runs its command. Gives up keyboard
    // focus immediately (search mode skips the close animation, so this
    // can land without `closing`): an app that maps while the menu still
    // holds focus would otherwise open unfocused.
    property bool launched: false

    function launch(cmd) {
        root.launched = true;
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    // Click-catcher for the rest of the screen: a press anywhere off the
    // content square closes the menu (what clicking outside did before).
    // Below contentItem, so presses on the menu itself only land here if
    // nothing in it took them - those are ignored.
    MouseArea {
        id: backdrop
        anchors.fill: parent
        enabled: root.interactive
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            if (contentItem.contains(mapToItem(contentItem, mouse.x, mouse.y)))
                mouse.accepted = false;
            else
                root.requestClose();
        }
    }

    // // (Stale: from when keytree was its own layer surface - it now shares
    // // the overlay host's window, so this would blur through its window.)
    // // Real compositor-side blur behind the disc, matched by the
    // // `hl.layer_rule` for namespace "quickshell:keytree" in
    // // ~/hypr/hyprland/rules.lua (blur + ignore_alpha - without ignore_alpha
    // // Hyprland renders the mostly-transparent tint circle below as a solid
    // // fallback square instead of actually blurring through it). Ellipse
    // // shape sourced straight from contentItem so the blurred region always
    // // matches the visible disc exactly, hollowing out whatever windows are
    // // behind it rather than just tinting them.
    // BackgroundEffect.blurRegion: Region {
    //     shape: RegionShape.Ellipse
    //     item: contentItem
    // }

    // No manual DPI scaling here - unlike the original X11 app, Hyprland's
    // per-monitor `scale` (see hypr/hyprland/monitors.lua) already scales
    // this surface's logical pixels automatically. fontScale/nodeScale here
    // are purely the config-driven knobs (KeytreeConfig.layout.*).
    readonly property real fontScale: KeytreeConfig.layout.fontScale
    readonly property real nodeScale: KeytreeConfig.layout.nodeScale

    // ── Tree navigation (mirrors KeyTreeModel) ────────────────────────────────
    readonly property var virtualRoot: ({
        label: "",
        children: KeytreeConfig.trees[root.configName] ?? {}
    })
    property var current: root.virtualRoot
    property var stack: []
    // Parallel to stack: each entry bolt's channel, reversed, so going back
    // runs the same path from that folder's node to the center (null if no
    // bolt was drawn going in).
    property var backBolts: []

    readonly property var currentChildren: root.current.children ?? {}
    readonly property string currentLabel: root.current.label ?? ""
    readonly property bool atRoot: root.stack.length === 0

    readonly property var items: {
        const list = [];
        const children = root.currentChildren;
        for (const key in children) {
            const node = children[key];
            list.push({
                key: key,
                label: node.label ?? "",
                icon: (node.icon ?? "").slice(0, 5),
                isLeaf: !node.children,
                cmd: node.cmd ?? ""
            });
        }
        return list;
    }

    function pressKey(key) {
        if (!key)
            return;
        const k = key.toLowerCase();
        const node = root.currentChildren[k];
        if (!node)
            return;
        if (node.children) {
            // Aim at the picked node before the level swaps out from under it.
            const picked = root.menuPoint(radialView.nodeFinalCenter(root.items.findIndex(it => it.key === k)));
            root.stack = [...root.stack, root.current];
            root.current = node;
            const struck = picked && root.menuBolt("enter", root.menuPoint(radialView.center), picked);
            root.backBolts = [...root.backBolts, struck ? menuBoltItem.geometry(true) : null];
        } else if (node.cmd) {
            // The picked node becomes the origin of the next bolt (bar
            // popup / app window opening) - see modules/bolt/Bolts.qml.
            const p = radialView.nodeCenter(k);
            if (p)
                Bolts.setOrigin(Qt.point(p.x + root.screen.x, p.y + root.screen.y));
            // Bar popups are summoned in-process rather than round-tripping
            // through `qs ipc`, so the bolt leaves the node immediately.
            const popup = node.cmd.match(/^qs ipc call barpopup open (\S+)$/);
            if (popup)
                BarPopups.summon(popup[1]);
            else
                root.launch(node.cmd);
            root.requestClose();
        }
    }

    function back() {
        if (root.stack.length > 0) {
            root.current = root.stack[root.stack.length - 1];
            root.stack = root.stack.slice(0, -1);
            const replay = root.backBolts[root.backBolts.length - 1];
            root.backBolts = root.backBolts.slice(0, -1);
            if (replay) {
                root.menuBolt("back", null, null, replay);
                return;
            }
            // No entry bolt to retrace: from a random node of the parent
            // level, deferred so its nodes exist to start from.
            Qt.callLater(() => {
                const from = root.menuPoint(radialView.nodeFinalCenter(Math.floor(Math.random() * root.items.length)));
                if (from)
                    root.menuBolt("back", from, root.menuPoint(radialView.center));
            });
        } else {
            root.requestClose();
        }
    }

    // ── Lightning (see modules/bolt, BoltConfig.keytree) ──────────────────────
    // Drawn by a BoltItem inside this window, so it's always above the menu.
    // RadialView points are mapped into menuBoltItem's center-relative frame
    // as they're read, before any level change can resize contentItem.
    function menuPoint(p) {
        return p ? radialView.mapToItem(menuBoltItem, p.x, p.y) : null;
    }

    // Whether it struck. `replay`: a channel from menuBoltItem.geometry().
    function menuBolt(kind, from, to, replay) {
        if (root.closing || root.searchMode || !Bolts.active("keytree") || !BoltConfig.keytree[kind])
            return false;
        if (kind === "swirl")
            menuBoltItem.strike({ path: Bolts.spiralPath(from, to, BoltConfig.keytree.swirlTurns), style: BoltConfig.styles.swirl });
        else if (replay)
            menuBoltItem.strike({ replay: replay, style: BoltConfig.styles.keytree });
        else
            menuBoltItem.strike({ from: from, to: to, style: BoltConfig.styles.keytree });
        return true;
    }

    function openingSwirl() {
        const target = root.menuPoint(radialView.nodeFinalCenter(Math.floor(Math.random() * root.items.length)));
        if (target)
            root.menuBolt("swirl", root.menuPoint(radialView.center), target);
    }

    // ── Window sizing (mirrors Main.qml's baseSize/spiralWindowSize) ─────────
    readonly property bool isSpiral: KeytreeConfig.layout.type === "spiral" && root.items.length >= KeytreeConfig.layout.spiralThreshold
    readonly property bool twoRings: KeytreeConfig.layout.type === "ring" && root.items.length >= KeytreeConfig.layout.ringThreshold

    function spiralWindowSize(n) {
        const ringScale = KeytreeConfig.layout.ringScale;
        if (n <= 1)
            return 540 * ringScale;
        const isCircle = KeytreeConfig.layout.shape === "circle";
        const w = (isCircle ? 64 : 76) * KeytreeConfig.layout.nodeScale;
        const h = (isCircle ? 64 : 56) * KeytreeConfig.layout.nodeScale;
        const gap = KeytreeConfig.layout.gapPixels;
        const b = isCircle ? (w + gap) / (2 * Math.PI) : (Math.sqrt(w * w + h * h) + gap) / (2 * Math.PI);
        const hw = w / 2;
        const a = 0.25 - 0.13 * 0.13;
        const arc = 2 * b * n * (w + gap);
        const disc = hw * hw * (1 - 4 * a) + 4 * a * arc;
        return Math.max(540 * ringScale, Math.ceil((hw + Math.sqrt(disc)) / (2 * a) / 10) * 10);
    }

    readonly property real baseSize: root.isSpiral ? root.spiralWindowSize(root.items.length) : (root.twoRings ? 680 * KeytreeConfig.layout.ringScale : 540 * KeytreeConfig.layout.ringScale)
    readonly property real winSize: Math.round(root.baseSize)

    // ── Search mode (mirrors KeyTreeModel's PATH-scan search) ─────────────────
    readonly property int maxSearchResults: 10

    property bool searchMode: false
    property string searchText: ""
    property int searchSelection: 0
    property var searchResults: []
    property var allBins: []
    property bool binsReady: false

    function updateSearchResults() {
        const query = root.searchText.toLowerCase();
        let results;
        if (query.length === 0) {
            results = root.allBins.slice(0, root.maxSearchResults);
        } else {
            const prefix = root.allBins.filter(b => b.toLowerCase().startsWith(query));
            const substr = root.allBins.filter(b => !b.toLowerCase().startsWith(query) && b.toLowerCase().includes(query));
            results = prefix.concat(substr).slice(0, root.maxSearchResults);
        }
        root.searchResults = results;
        root.searchSelection = 0;
    }

    function enterSearch() {
        root.searchMode = true;
        root.searchText = "";
        if (root.binsReady)
            root.updateSearchResults();
        else
            root.searchResults = [];
    }

    function exitSearch() {
        root.searchMode = false;
        root.searchText = "";
        root.searchResults = [];
        root.searchSelection = 0;
    }

    function appendSearch(ch) {
        root.searchText += ch;
        root.updateSearchResults();
    }

    function backspaceSearch() {
        if (root.searchText.length === 0) {
            root.exitSearch();
            return;
        }
        root.searchText = root.searchText.slice(0, -1);
        root.updateSearchResults();
    }

    function navigateSearch(delta) {
        const n = root.searchResults.length;
        if (n === 0)
            return;
        root.searchSelection = ((root.searchSelection + delta) % n + n) % n;
    }

    function confirmSearch() {
        if (root.searchSelection < root.searchResults.length) {
            root.launch(root.searchResults[root.searchSelection]);
            root.requestClose();
        }
    }

    // Scan PATH once, in the background, starting the moment the window
    // opens - same "hide it behind startup time" idea as the original's
    // std::async scan kicked off from the KeyTreeModel constructor.
    Process {
        id: pathScanProc
        running: true
        command: ["bash", "-c", 'IFS=: read -ra dirs <<< "$PATH"; for d in "${dirs[@]}"; do [ -d "$d" ] || continue; find "$d" -maxdepth 1 -not -type d -perm /111 -printf "%f\\n" 2>/dev/null; done | grep -v "^\\." | sort -u']
        stdout: StdioCollector {
            id: pathScanCollector
            onStreamFinished: {
                root.allBins = pathScanCollector.text.split("\n").filter(s => s.length > 0);
                root.binsReady = true;
                if (root.searchMode)
                    root.updateSearchResults();
            }
        }
    }

    // ── Input + view hosting (mirrors Main.qml) ───────────────────────────────
    Item {
        id: contentItem
        anchors.centerIn: parent
        width: root.winSize
        height: root.winSize
        focus: true

        // Circular tint behind the content, lined up with BackgroundEffect
        // .blurRegion above so blur + tint read as one frosted-glass disc.
        // Derived from Theme.groupBg's own RGB (own alpha discarded, tint
        // alpha set here instead) rather than a dedicated Theme property -
        // groupBg is a plain QML binding computed from the wallust palette,
        // so it follows palette changes without a palette entry of its own.
        //
        // A radial gradient (center -> fully transparent edge) painted via
        // Canvas rather than Rectangle.gradient, which in QtQuick is
        // linear-only - no built-in radial gradient primitive. Sized larger
        // than contentItem (parent here) so the fade bleeds out past the
        // outermost node bubbles instead of stopping flush at their edge;
        // this is purely a visual halo - backdrop's click-outside test and blurRegion
        // above stay tied to contentItem's own tighter bounds.
        Canvas {
            id: haloCanvas
            anchors.centerIn: parent
            readonly property real haloRadius: parent.width * 0.8
            width: haloRadius * 2
            height: haloRadius * 2

            // Scaled via a transform, not by redrawing at a different pixel
            // size - a radial gradient scales losslessly, so this is a free
            // GPU transform instead of an extra Canvas rasterization pass.
            // One shot, not replayed per submenu navigation like the nodes/
            // connectors - a steady backdrop while individual levels refresh
            // reads calmer than the whole halo pulsing on every keystroke.
            property real haloScale: 0
            scale: haloScale

            Behavior on haloScale {
                SequentialAnimation {
                    // Same center-first lead-in as the nodes/connector lines.
                    PauseAnimation {
                        duration: root.closing ? radialView.centerAnimDuration : 0
                    }
                    NumberAnimation {
                        duration: radialView.totalAnimMs
                        easing.type: root.closing ? Easing.InCubic : Easing.OutBack
                    }
                }
            }

            Component.onCompleted: haloCanvas.haloScale = 1

            Connections {
                target: root
                function onClosingChanged() {
                    haloCanvas.haloScale = root.closing ? 0 : 1;
                }
            }

            property color haloColor: Theme.groupBg
            onHaloColorChanged: requestPaint()
            onHaloRadiusChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const r = haloRadius;
                const gradient = ctx.createRadialGradient(r, r, 0, r, r, r);
                gradient.addColorStop(0, Qt.rgba(haloColor.r, haloColor.g, haloColor.b, 1));
                gradient.addColorStop(1, Qt.rgba(haloColor.r, haloColor.g, haloColor.b, 0));
                ctx.fillStyle = gradient;
                ctx.beginPath();
                ctx.arc(r, r, r, 0, Math.PI * 2);
                ctx.fill();
            }
        }

        function keyMatches(event, binding) {
            switch (binding) {
            case "Escape":
            case "Esc":
                return event.key === Qt.Key_Escape;
            case "Return":
            case "Enter":
                return event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
            case "Backspace":
                return event.key === Qt.Key_Backspace;
            case "Tab":
                return event.key === Qt.Key_Tab;
            default:
                return binding.length === 1 && event.text === binding;
            }
        }

        Keys.onPressed: event => {
            const kb = KeytreeConfig.keybindings;
            if (root.searchMode) {
                if (contentItem.keyMatches(event, kb.back))
                    root.exitSearch();
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    root.confirmSearch();
                else if (event.key === Qt.Key_Backspace)
                    root.backspaceSearch();
                else if (event.key === Qt.Key_Up)
                    root.navigateSearch(-1);
                else if (event.key === Qt.Key_Down)
                    root.navigateSearch(1);
                else if (event.text.length > 0)
                    root.appendSearch(event.text);
                event.accepted = true;
                return;
            }

            if (contentItem.keyMatches(event, kb.quit)) {
                root.requestClose();
                event.accepted = true;
                return;
            }
            if (contentItem.keyMatches(event, kb.back)) {
                root.back();
                event.accepted = true;
                return;
            }
            if (contentItem.keyMatches(event, kb.search)) {
                root.enterSearch();
                event.accepted = true;
                return;
            }
            if (event.text.length > 0) {
                root.pressKey(event.text);
                event.accepted = true;
            }
        }

        RadialView {
            id: radialView
            anchors.fill: parent
            items: root.items
            fontScale: root.fontScale
            nodeScale: root.nodeScale
            centerLabel: root.currentLabel
            atRoot: root.atRoot
            layoutType: KeytreeConfig.layout.type
            nodeShape: KeytreeConfig.layout.shape
            ringThreshold: KeytreeConfig.layout.ringThreshold
            spiralThreshold: KeytreeConfig.layout.spiralThreshold
            spiralGapPixels: KeytreeConfig.layout.gapPixels
            closing: root.closing
            visible: !root.searchMode
        }

        SearchView {
            fontScale: root.fontScale
            searchText: root.searchText
            searchResults: root.searchResults
            searchSelection: root.searchSelection
            visible: root.searchMode
        }
    }

    // Fixed-size and centered on the window, like contentItem - so bolt
    // points are effectively relative to the menu's center. That holds no
    // matter when the layer surface gets its real size from the compositor
    // (it isn't known yet when the opening swirl is computed) or how
    // contentItem resizes between levels.
    BoltItem {
        id: menuBoltItem
        anchors.centerIn: parent
        width: 4000
        height: 4000
        visible: !root.searchMode
    }

    // Placed on its screen's overlay host (OverlaySurface).
    onHostChanged: {
        // host.screen, not `screen`: that binding may not have caught up yet.
        const s = root.host?.screen;
        if (!s)
            return;
        // Start the pointer on the menu's center so it's ready for mouse
        // use. Cosmetic only - focus doesn't depend on where the cursor is.
        Quickshell.execDetached(["hyprctl", "dispatch", "movecursor",
            String(Math.round(s.x + s.width / 2)),
            String(Math.round(s.y + s.height / 2))]);
        // After the first frame's layout, so the nodes it aims at exist.
        Qt.callLater(root.openingSwirl);
    }
}
