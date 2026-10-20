pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Sticky key assignments for keytree's directory levels ("<dir>" nodes),
// persisted to ~/.local/state/quickshell/keytree-dirs.json:
//
//   { "dirs":  { "/abs/dir": { "keys": { "c": "cadence-fw", "x": "cadence-fw/tools/x/" },
//                              "gone": { "b": "old-thing" } } },
//     "usage": { "/abs/dir/cadence-fw": [count, lastUnixSeconds] } }
//
// A key, once given, never moves on its own:
//   - new entries only take free keys - mnemonic first (first letter, then
//     word starts, then any letter of the name), then any free key;
//   - an entry that disappears parks its key in `gone`, and gets the same
//     key back if it reappears (remounted drive, re-cloned repo). Parked
//     keys are only handed to something else once no free key is left;
//   - only pin() (search mode, Tab) evicts.
// Entries without a key are reachable through search only.
//
// keys values are entry names in that dir. A deeper relative path
// ("a/b/c", trailing "/" for a directory) also works if hand-written into
// the file - search only pins the dir's own entries - and is never parked.
//
// JSON rather than anything binary: it's a few KB, read once and kept in
// memory, and stays hand-editable.
Singleton {
    id: root

    // 25 slots: a-z minus the quit key.
    readonly property var slots: "abcdefghijklmnopqrstuvwxyz".split("").filter(k => k !== KeytreeConfig.keybindings.quit)

    readonly property string _dir: Quickshell.env("HOME") + "/.local/state/quickshell"
    readonly property string _path: root._dir + "/keytree-dirs.json"

    property var _state: ({ dirs: {}, usage: {} })

    // Most recently used first, decaying by half every 30 days; never-used
    // entries fall back to modification time (`mtime`, ms since epoch).
    function _score(absPath, mtime) {
        const u = root._state.usage[absPath];
        const now = Date.now() / 1000;
        if (!u)
            return mtime / 1000 / now - 1;  // always below any used entry's score
        return u[0] * Math.pow(0.5, (now - u[1]) / (30 * 86400));
    }

    // Keys this name would like, best first: its first letter, letters
    // starting a word (after - _ . space, or a camelCase hump), then the
    // rest of its letters.
    function _candidates(name) {
        const base = name.replace(/^\.+/, "").replace(/\/$/, "");
        const first = [], starts = [], rest = [];
        for (let i = 0; i < base.length; i++) {
            const c = base[i].toLowerCase();
            if (c < "a" || c > "z")
                continue;
            if (i === 0)
                first.push(c);
            else if (/[-_. ]/.test(base[i - 1]) || (base[i] !== c && base[i - 1] === base[i - 1].toLowerCase()))
                starts.push(c);
            else
                rest.push(c);
        }
        return [...new Set([...first, ...starts, ...rest])];
    }

    function _pick(name, pool) {
        return root._candidates(name).find(k => pool.includes(k)) ?? pool[0];
    }

    function _dirState(dir) {
        let d = root._state.dirs[dir];
        if (!d) {
            d = { keys: {}, gone: {} };
            root._state.dirs[dir] = d;
        }
        return d;
    }

    // entries: [{ name, isDir, mtime }] - the dir's current listing.
    // filesEqual: rank files alongside dirs instead of after them.
    // Returns { keys: { key: rel }, overflow: n } and saves if anything moved.
    function assign(dir, entries, filesEqual) {
        const d = root._dirState(dir);
        const present = new Set(entries.map(e => e.name));
        let changed = false;

        for (const k in d.keys) {
            const rel = d.keys[k];
            if (!rel.includes("/") && !present.has(rel)) {
                d.gone[k] = rel;
                delete d.keys[k];
                changed = true;
            }
        }
        for (const k in d.gone) {
            if (present.has(d.gone[k]) && !(k in d.keys)) {
                d.keys[k] = d.gone[k];
                delete d.gone[k];
                changed = true;
            }
        }

        const bound = new Set(Object.values(d.keys));
        const pending = entries.filter(e => !bound.has(e.name));
        pending.sort((a, b) => {
            if (!filesEqual && a.isDir !== b.isDir)
                return a.isDir ? -1 : 1;
            return root._score(dir + "/" + b.name, b.mtime) - root._score(dir + "/" + a.name, a.mtime);
        });

        let overflow = 0;
        for (const e of pending) {
            const free = root.slots.filter(k => !(k in d.keys) && !(k in d.gone));
            let k;
            if (free.length > 0) {
                k = root._pick(e.name, free);
            } else {
                const parked = root.slots.filter(s => s in d.gone);
                if (parked.length === 0) {
                    overflow++;
                    continue;
                }
                k = root._pick(e.name, parked);
                delete d.gone[k];
            }
            d.keys[k] = e.name;
            changed = true;
        }

        if (changed)
            root._save();
        return { keys: Object.assign({}, d.keys), overflow: overflow };
    }

    // Bind `rel` (relative to dir, trailing "/" for a directory) to `key`,
    // evicting whatever had it. Any other key already pointing at the same
    // entry is freed, so it never shows up twice.
    function pin(dir, key, rel) {
        const d = root._dirState(dir);
        const plain = rel.replace(/\/$/, "");
        for (const k in d.keys)
            if (d.keys[k].replace(/\/$/, "") === plain)
                delete d.keys[k];
        delete d.gone[key];
        d.keys[key] = plain.includes("/") ? rel : plain;
        root._save();
    }

    // Key bound to `rel` at `dir`, or "".
    function keyFor(dir, rel) {
        const plain = rel.replace(/\/$/, "");
        const keys = root._state.dirs[dir]?.keys ?? {};
        for (const k in keys)
            if (keys[k].replace(/\/$/, "") === plain)
                return k;
        return "";
    }

    function recordUse(absPath) {
        const u = root._state.usage[absPath];
        root._state.usage[absPath] = [(u ? u[0] : 0) + 1, Math.floor(Date.now() / 1000)];
        root._save();
    }

    // Coalesced: assign() and recordUse() often run back to back.
    function _save() {
        Qt.callLater(root._write);
    }

    function _write() {
        stateFile.setText(JSON.stringify(root._state));
    }

    function _load(text) {
        if (!text)
            return;
        try {
            const obj = JSON.parse(text) || {};
            root._state = { dirs: obj.dirs ?? {}, usage: obj.usage ?? {} };
        } catch (_) {}
    }

    // FileView.setText() doesn't create missing parent directories.
    Process {
        command: ["mkdir", "-p", root._dir]
        running: true
    }

    FileView {
        id: stateFile
        path: root._path
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: root._load(stateFile.text())
}
