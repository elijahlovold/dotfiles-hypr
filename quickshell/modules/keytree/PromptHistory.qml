pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Past entries for keytree's text prompts (KeytreePanel's prompt mode),
// one list per prompt, keyed by its menu path plus "+shift" when it was
// the shift_cmd that prompted - e.g. "default/b/g+shift".
//
// The whole file is read once at startup and kept in memory: typing in a
// prompt only filters an in-memory list (at most `maxEntries` short
// strings), never touches the disk. It's written once per launch, after
// the command has been started.
//
// Each entry is { t: text, n: times used, at: last used (epoch ms) }.
Singleton {
    id: root

    readonly property int maxEntries: 200
    readonly property int maxShown: 8
    // Uses older than this count for half as much in the ranking.
    readonly property real halfLifeDays: 14

    property var lists: ({})
    property bool loaded: false

    function score(e, now) {
        return e.n * Math.pow(0.5, (now - e.at) / (root.halfLifeDays * 86400000));
    }

    // Best entries for `text` in `key`'s list: prefix matches before
    // substring ones, each ranked by frecency. With no text, the most
    // recent ones.
    function suggest(key, text) {
        const list = root.lists[key];
        if (!list || list.length === 0)
            return [];
        if (text.length === 0)
            return list.slice().sort((a, b) => b.at - a.at).slice(0, root.maxShown).map(e => e.t);
        const q = text.toLowerCase();
        const now = Date.now();
        const prefix = [];
        const substr = [];
        for (const e of list) {
            const t = e.t.toLowerCase();
            if (t.startsWith(q))
                prefix.push(e);
            else if (t.includes(q))
                substr.push(e);
        }
        const byScore = (a, b) => root.score(b, now) - root.score(a, now);
        return prefix.sort(byScore).concat(substr.sort(byScore)).slice(0, root.maxShown).map(e => e.t);
    }

    function record(key, text) {
        const t = text.trim();
        if (!key || t.length === 0)
            return;
        const now = Date.now();
        const list = (root.lists[key] ?? []).slice();
        const hit = list.find(e => e.t === t);
        if (hit) {
            hit.n += 1;
            hit.at = now;
        } else {
            list.push({ t: t, n: 1, at: now });
        }
        // Over the cap: drop the lowest-ranked.
        if (list.length > root.maxEntries) {
            list.sort((a, b) => root.score(b, now) - root.score(a, now));
            list.length = root.maxEntries;
        }
        root.put(key, list);
    }

    function forget(key, text) {
        const list = root.lists[key];
        if (!list)
            return;
        root.put(key, list.filter(e => e.t !== text));
    }

    // Reassigned rather than mutated, so bindings on `lists` (the
    // prompt's suggestions) re-evaluate.
    function put(key, list) {
        const next = Object.assign({}, root.lists);
        next[key] = list;
        root.lists = next;
        root.save();
    }

    function save() {
        if (root.loaded)
            store.setText(JSON.stringify(root.lists));
    }

    FileView {
        id: store
        path: Quickshell.statePath("keytree-history.json")
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(store.text());
                if (saved && typeof saved === "object")
                    root.lists = saved;
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }
}
