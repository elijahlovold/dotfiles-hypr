pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Homelab services (Portainer's docker containers), Syncthing and local
// tailscale status, shared by both bars and HomelabPreview. Configured from
// the shell's environment:
//   Portainer: $PORTAINER / $TOKEN / $ENV_ID (same shape as the curl in
//              portainer-rest.txt)
//   Syncthing: $SYNCTHING_URL / $SYNCTHING_API_KEY, plus $SYNCTHING_DEVICE_ID
//              / $SYNCTHING_FOLDER_ID for the bar's sync glyph (the remote
//              device's completion of that folder)
//
// Event-driven rather than polled, except tailscale (no stable watch API):
//   - Docker: one long-lived `curl -N` on Portainer's /docker/events stream;
//     a container lifecycle/health event re-fetches the container list.
//   - Syncthing: a /rest/events long-poll loop (each request parks on the
//     server until something happens, or 60s); events patch the state in
//     place. Only the per-device traffic counters have no event, so the
//     panel refreshes those itself while open.
// For the floating panel it also keeps history (uptime beads per container,
// an activity feed of container/peer/folder events) in the shell's cache
// dir, so it survives reloads.
// One-shot requests go through XMLHttpRequest (no process per request); the
// docker stream stays on curl because QML's XHR only reports a streaming
// body once. API keys never go on a command line: XHR sends them as headers
// in-process, and curl reads its header from stdin (`-K -`).
Singleton {
    id: root

    readonly property string portainerUrl: Quickshell.env("PORTAINER") ?? ""
    readonly property string token: Quickshell.env("TOKEN") ?? ""
    readonly property string envId: Quickshell.env("ENV_ID") ?? ""
    readonly property bool configured: portainerUrl.length > 0 && token.length > 0 && envId.length > 0
    readonly property string dockerApi: portainerUrl + "/api/endpoints/" + envId + "/docker"

    // [{ id, name, image, state, status, health, exitCode }], sorted by name.
    property var containers: []
    property string servicesError: ""
    // Up = running and not failing its healthcheck.
    readonly property int upCount: containers.filter(c => root.isUp(c)).length
    readonly property int totalCount: containers.length

    // "Running", "Stopped", "NeedsLogin", ... or "Unavailable" when
    // tailscaled can't be reached.
    property string tsState: ""
    property var tsSelf: null
    // [{ id, hostName, dnsName, ip, os, kind, online, lastSeen, exitNode,
    //    exitOption, via }], online first. `via` is "direct" when tailscale
    // has a direct endpoint (CurAddr), else the DERP region it relays
    // through ("nyc"), "" when unknown/offline. kind: server, laptop,
    // phone or tablet (for the topology icon).
    property var tsPeers: []
    property string tsTailnet: ""

    // ---- History (for the floating panel) ----

    // Uptime beads: one bead per `beadMs` per container, the worst state
    // (ok < off < err) seen during that slot - so a crash between two
    // samples still shows. State changes arrive by event (fetchContainers
    // after a docker event folds into the open slot); the Timer only closes
    // slots, which is what gives the strip a time axis.
    // beads: { containerId: ["ok" | "off" | "err" | "", ...] } oldest first,
    // "" = no data (shell wasn't running / container didn't exist).
    readonly property int beadCount: 40
    readonly property int beadMs: 75000
    property var beads: ({})
    property var beadSlot: ({})
    property real beadClosedAt: 0

    // Activity feed, newest first: { time (ms), source: "docker" | "peer" |
    // "sync", sev: "ok" | "off" | "err" | "busy", title, detail }.
    // Syncthing file changes aren't copied in - activityFeed merges
    // stChanges at read time.
    readonly property int maxActivity: 50
    property var activity: []
    readonly property var activityFeed: {
        const sync = root.stChanges.map(c => ({
            time: Date.parse(c.time),
            source: "sync",
            sev: "ok",
            title: c.folder + "  ·  " + c.path,
            detail: (c.remote ? "↓ " : "↑ ") + c.action
        }));
        return root.activity.concat(sync).sort((a, b) => b.time - a.time).slice(0, root.maxActivity);
    }

    readonly property string stUrl: Quickshell.env("SYNCTHING_URL") ?? ""
    readonly property string stKey: Quickshell.env("SYNCTHING_API_KEY") ?? ""
    readonly property string stDevice: Quickshell.env("SYNCTHING_DEVICE_ID") ?? ""
    readonly property string stFolder: Quickshell.env("SYNCTHING_FOLDER_ID") ?? ""
    readonly property bool stConfigured: stUrl.length > 0 && stKey.length > 0

    // Bar summary: whether any device is connected, and the watched
    // device/folder's sync state - "synced", "almost" (>= 99.5%, tiny
    // drift) or "syncing"; "" until the first answer / when unreachable.
    property bool stReachable: false
    // Last-known device state is stale once Syncthing stops answering.
    readonly property bool stConnected: stReachable && stDevices.some(d => d.connected)
    property string stSync: ""

    // folders: [{ id, label, path, paused, state, globalFiles, globalBytes,
    //             localFiles, needFiles, needBytes, inSyncBytes, errors,
    //             lastFile, lastFileAt }]
    // devices: [{ id, name, connected, paused, address, type, inBytes, outBytes,
    //             clientVersion }] (remote devices only)
    // changes: [{ time, remote, action, kind, path, folder }], newest first
    property var stFolders: []
    property var stDevices: []
    property var stChanges: []
    property var stTotals: null
    property string stError: ""

    readonly property int maxChanges: 15
    readonly property string stEventMask: [
        "StateChanged", "FolderSummary", "FolderCompletion", "FolderErrors",
        "FolderPaused", "FolderResumed", "DeviceConnected", "DeviceDisconnected",
        "DevicePaused", "DeviceResumed", "ConfigSaved",
        "LocalChangeDetected", "RemoteChangeDetected"
    ].join(",")

    function isUp(c) {
        return c.state === "running" && c.health !== "unhealthy";
    }

    // "ok" up, "err" broken (unhealthy, crashed, restart-looping), "off"
    // deliberately not running (exited 0, created, paused).
    function containerSeverity(c) {
        if (root.isUp(c))
            return "ok";
        if (c.health === "unhealthy" || c.state === "restarting" || c.state === "dead"
                || (c.state === "exited" && c.exitCode !== 0))
            return "err";
        return "off";
    }

    readonly property var sevRank: ({ "": 0, ok: 1, off: 2, err: 3 })

    function pushActivity(entry) {
        root.activity = [entry].concat(root.activity).slice(0, root.maxActivity);
        historySave.restart();
    }

    // Only reassign list properties when their content changed, so the
    // popup's Repeaters don't rebuild (and drop per-row state like ping
    // results) on every update.
    function setIfChanged(prop, value) {
        if (JSON.stringify(root[prop]) !== JSON.stringify(value))
            root[prop] = value;
    }

    // Called when the panel opens: everything it shows is fresh, including
    // the "Up 48 minutes" strings, which no event updates.
    function refresh() {
        root.fetchContainers();
        root.stRefreshConnections();
        if (!tsProc.running)
            tsProc.running = true;
    }

    function fmtBytes(n) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        n = n ?? 0;
        while (n >= 1024 && i < units.length - 1) {
            n /= 1024;
            i++;
        }
        return (i === 0 ? n : n.toFixed(n < 10 ? 1 : 0)) + " " + units[i];
    }

    // `when`: an ISO string or ms timestamp. Pass `now` from a ticking
    // property to make a binding re-evaluate.
    function ago(when, now) {
        const t = typeof when === "number" ? when : Date.parse(when);
        if (isNaN(t) || t <= 0)
            return "";
        const s = Math.max(0, ((now ?? Date.now()) - t) / 1000);
        if (s < 60) return Math.floor(s) + "s ago";
        if (s < 3600) return Math.floor(s / 60) + "m ago";
        if (s < 86400) return Math.floor(s / 3600) + "h ago";
        return Math.floor(s / 86400) + "d ago";
    }

    // curl config line for `-K -`, so the key reaches curl on stdin.
    function curlHeader(key) {
        return 'header = "X-API-Key: ' + key.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"\n';
    }

    // ---- HTTP ----

    // GET `url` with the API key; cb(json, error) - exactly one of them is
    // null/"". QML's XHR has no timeout, so a Timer aborts it instead.
    function getJson(url, key, timeoutMs, cb) {
        return root.request("GET", url, key, timeoutMs, cb);
    }

    // Same for other methods; an empty 2xx body (docker's 204) gives {}.
    function request(method, url, key, timeoutMs, cb) {
        const xhr = new XMLHttpRequest();
        let guard = abortTimer.createObject(root, { interval: timeoutMs, xhr: xhr });
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            const timedOut = guard?.fired ?? false;
            guard?.destroy();
            guard = null;
            if (xhr.status >= 200 && xhr.status < 300) {
                let data = {};
                try {
                    if (xhr.responseText.length > 0)
                        data = JSON.parse(xhr.responseText);
                } catch (e) {
                    return cb(null, "Bad JSON from " + url.split("?")[0]);
                }
                cb(data, "");
            } else {
                cb(null, timedOut ? "Timed out" : xhr.status === 0 ? "Unreachable" : "HTTP " + xhr.status);
            }
        };
        xhr.open(method, url);
        xhr.setRequestHeader("X-API-Key", key);
        xhr.send();
        guard.start();
        return xhr;
    }

    Component {
        id: abortTimer
        Timer {
            property var xhr
            property bool fired: false
            onTriggered: {
                fired = true;
                xhr.abort();
            }
        }
    }

    // ---- Docker (via Portainer) ----

    function fetchContainers() {
        if (!root.configured)
            return;
        root.getJson(root.dockerApi + "/containers/json?all=true", root.token, 8000, (data, err) => {
            if (err) {
                root.servicesError = err + " (" + root.portainerUrl + ")";
                root.containers = [];
                return;
            }
            root.servicesError = "";
            root.setIfChanged("containers", data.map(c => ({
                id: c.Id,
                name: (c.Names?.[0] ?? c.Id.slice(0, 12)).replace(/^\//, ""),
                image: c.Image,
                state: c.State,
                status: c.Status,
                health: c.Health?.Status ?? "none",
                // The list API has no exit code; the status string does.
                exitCode: parseInt((c.Status ?? "").match(/^Exited \((-?\d+)\)/)?.[1] ?? "0")
            })).sort((a, b) => a.name.localeCompare(b.name)));
            root.foldBeads();
        });
    }

    // POST /containers/{id}/start through Portainer; cb(error) with "" on
    // success. The start event re-fetches the list by itself.
    function startContainer(id, cb) {
        root.request("POST", root.dockerApi + "/containers/" + id + "/start", root.token, 15000, (data, err) => {
            // 304: already running - fine.
            cb(err === "HTTP 304" ? "" : err);
        });
    }

    // Fold the current container states into the open bead slot.
    function foldBeads() {
        const slot = Object.assign({}, root.beadSlot);
        for (const c of root.containers) {
            const sev = root.containerSeverity(c);
            if ((root.sevRank[sev] ?? 0) > (root.sevRank[slot[c.id] ?? ""] ?? 0))
                slot[c.id] = sev;
        }
        root.beadSlot = slot;
    }

    // Close the open slot: push it onto every strip, start the next one
    // from the current states. Containers that are gone keep their strip
    // until it has scrolled out entirely.
    function closeBeadSlot() {
        const next = {};
        const ids = Object.keys(root.beads).concat(root.containers.map(c => c.id));
        for (const id of ids) {
            if (next[id])
                continue;
            const strip = (root.beads[id] ?? []).concat([root.beadSlot[id] ?? ""]).slice(-root.beadCount);
            if (strip.some(b => b !== ""))
                next[id] = strip;
        }
        root.beads = next;
        root.beadSlot = {};
        root.beadClosedAt = Date.now();
        root.foldBeads();
        historySave.restart();
    }

    // Open slot shown as the strip's newest bead, so a change shows at once.
    function beadsFor(id) {
        const strip = (root.beads[id] ?? []).concat([root.beadSlot[id] ?? ""]).slice(-root.beadCount);
        const pad = [];
        for (let i = strip.length; i < root.beadCount; i++)
            pad.push("");
        return pad.concat(strip);
    }

    Timer {
        interval: root.beadMs
        running: root.configured
        repeat: true
        onTriggered: root.closeBeadSlot()
    }

    // Beads + feed survive shell reloads/restarts; the time the shell
    // wasn't running comes back as empty beads.
    property bool historyReady: false

    FileView {
        id: historyFile
        path: Quickshell.cachePath("homelab-history.json")
        printErrors: false
        onLoaded: {
            try {
                const h = JSON.parse(historyFile.text());
                const missed = Math.min(root.beadCount, Math.floor((Date.now() - (h.beadClosedAt ?? 0)) / root.beadMs));
                const beads = {};
                for (const id in h.beads ?? {}) {
                    const strip = h.beads[id].slice();
                    for (let i = 0; i < missed; i++)
                        strip.push("");
                    beads[id] = strip.slice(-root.beadCount);
                }
                root.beads = beads;
                root.beadClosedAt = h.beadClosedAt ?? 0;
                root.activity = (h.activity ?? []).concat(root.activity)
                    .sort((a, b) => b.time - a.time).slice(0, root.maxActivity);
            } catch (e) {}
            root.historyReady = true;
        }
        onLoadFailed: root.historyReady = true
    }

    Timer {
        id: historySave
        interval: 2000
        onTriggered: {
            if (!root.historyReady)
                return historySave.restart();
            historyFile.setText(JSON.stringify({ beads: root.beads, beadClosedAt: root.beadClosedAt, activity: root.activity }));
        }
    }

    // Docker event -> feed entry, for the transitions worth reading later
    // (stop/kill/destroy all come with a die).
    function dockerActivity(ev) {
        const action = ev.Action ?? ev.status ?? "";
        const attrs = ev.Actor?.Attributes ?? {};
        const name = attrs.name ?? (ev.Actor?.ID ?? ev.id ?? "").slice(0, 12);
        const time = ev.timeNano ? Math.floor(ev.timeNano / 1e6) : (ev.time ?? 0) * 1000 || Date.now();
        let sev, detail;
        if (action === "start") {
            sev = "ok";
            detail = "started";
        } else if (action === "die") {
            const code = parseInt(attrs.exitCode ?? "0");
            sev = code === 0 ? "off" : "err";
            detail = "exited (" + code + ")";
        } else if (action === "oom") {
            sev = "err";
            detail = "out of memory";
        } else if (action.startsWith("health_status")) {
            const h = action.split(":").pop().trim();
            sev = h === "healthy" ? "ok" : "err";
            detail = h;
        } else if (action === "destroy") {
            sev = "off";
            detail = "removed";
        } else {
            return;
        }
        root.pushActivity({ time: time, source: "docker", sev: sev, title: name, detail: detail });
    }

    // Container events that change what the list shows. Healthchecks also
    // emit exec_create/exec_start/exec_die every interval - ignored here.
    readonly property var relevantDockerEvent: /^(create|start|restart|stop|die|destroy|pause|unpause|rename|update|oom|health_status)/

    Process {
        id: dockerEvents
        property int failures: 0
        property real startedAt: 0

        command: ["curl", "-fsSN", "--keepalive-time", "20", "-K", "-",
            root.dockerApi + "/events?filters=" + encodeURIComponent('{"type":["container"]}')]
        running: root.configured
        stdinEnabled: true
        onStarted: {
            dockerEvents.write(root.curlHeader(root.token));
            dockerEvents.stdinEnabled = false;
            dockerEvents.startedAt = Date.now();
            // Anything that happened while disconnected was missed.
            root.fetchContainers();
        }
        stdout: SplitParser {
            onRead: line => {
                let ev;
                try {
                    ev = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (root.relevantDockerEvent.test(ev.Action ?? ev.status ?? "")) {
                    root.dockerActivity(ev);
                    dockerDebounce.restart();
                }
            }
        }
        // Stream dropped (Portainer restart, network): reconnect with backoff.
        // A connection that held for a while was healthy (e.g. an idle
        // timeout somewhere cut it), so that resets the backoff - only
        // back-to-back failures to connect grow it.
        onExited: {
            dockerEvents.stdinEnabled = true;
            if (Date.now() - dockerEvents.startedAt > 30000)
                dockerEvents.failures = 0;
            else
                dockerEvents.failures++;
            dockerReconnect.interval = Math.min(60000, 2000 * Math.pow(2, Math.min(dockerEvents.failures, 5)));
            if (root.configured)
                dockerReconnect.restart();
        }
    }

    // `docker compose up` fires a burst of events; re-list once.
    Timer {
        id: dockerDebounce
        interval: 300
        onTriggered: root.fetchContainers()
    }

    Timer {
        id: dockerReconnect
        onTriggered: dockerEvents.running = true
    }

    // ---- Syncthing ----

    // Bumped on every resync so callbacks from an older generation (an
    // in-flight long-poll, a slow fetch) drop their results.
    property int stGeneration: 0
    property int stSince: 0
    property int stFailures: 0
    property var stPollXhr: null

    function stGet(path, cb, timeoutMs) {
        const gen = root.stGeneration;
        return root.getJson(root.stUrl + path, root.stKey, timeoutMs ?? 8000, (data, err) => {
            if (gen === root.stGeneration)
                cb(data, err);
        });
    }

    function stFail(err) {
        root.stReachable = false;
        root.stSync = "";
        root.stError = err + " (" + root.stUrl + ")";
        root.stFailures++;
        stRetry.interval = Math.min(60000, 2000 * Math.pow(2, Math.min(root.stFailures, 5)));
        stRetry.restart();
    }

    // Full state from REST, then hand over to the event loop. Runs at
    // startup, after any failure, and on ConfigSaved.
    function stResync() {
        if (!root.stConfigured)
            return;
        root.stGeneration++;
        root.stPollXhr?.abort();
        root.stGet("/rest/config", (cfg, err) => {
            if (err)
                return root.stFail(err);
            root.stError = "";
            const folders = cfg.folders ?? [];
            root.setIfChanged("stFolders", folders.map(f => {
                const old = root.stFolders.find(o => o.id === f.id);
                return {
                    id: f.id,
                    label: f.label || f.id,
                    path: f.path,
                    paused: f.paused ?? false,
                    state: old?.state ?? "unknown",
                    globalFiles: old?.globalFiles ?? 0,
                    globalBytes: old?.globalBytes ?? 0,
                    localFiles: old?.localFiles ?? 0,
                    needFiles: old?.needFiles ?? 0,
                    needBytes: old?.needBytes ?? 0,
                    inSyncBytes: old?.inSyncBytes ?? 0,
                    errors: old?.errors ?? 0,
                    lastFile: old?.lastFile ?? "",
                    lastFileAt: old?.lastFileAt ?? ""
                };
            }).sort((a, b) => a.label.localeCompare(b.label)));
            // (Qt's JS engine has no Object.fromEntries.)
            const names = {}, paused = {};
            for (const d of cfg.devices ?? []) {
                names[d.deviceID] = d.name || d.deviceID.slice(0, 7);
                paused[d.deviceID] = d.paused ?? false;
            }
            root.stDeviceNames = names;
            root.stDevicePaused = paused;

            for (const f of folders) {
                root.stGet("/rest/db/status?folder=" + encodeURIComponent(f.id), (s, e) => {
                    if (s)
                        root.stApplySummary(f.id, s);
                });
            }
            root.stGet("/rest/stats/folder", (stats, e) => {
                if (!stats)
                    return;
                root.stPatchFolders(f => stats[f.id]?.lastFile?.filename
                    ? { lastFile: stats[f.id].lastFile.filename, lastFileAt: stats[f.id].lastFile.at } : null);
            });
            root.stGet("/rest/events/disk?limit=" + root.maxChanges + "&timeout=1", (evs, e) => {
                if (evs)
                    root.setIfChanged("stChanges", evs.slice().reverse().map(root.stChange));
            }, 5000);
            if (root.stDevice.length > 0 && root.stFolder.length > 0) {
                root.stGet("/rest/db/completion?device=" + encodeURIComponent(root.stDevice)
                           + "&folder=" + encodeURIComponent(root.stFolder), (c, e) => {
                    if (c)
                        root.stApplyCompletion(c);
                });
            }
            root.stRefreshConnections();

            // Event ids count per event mask, so find where this mask's
            // stream is now (a fresh mask has none yet: start from 0).
            root.stGet("/rest/events?events=" + root.stEventMask + "&limit=1&timeout=1", (evs, e) => {
                if (e)
                    return root.stFail(e);
                root.stSince = evs.length > 0 ? evs[evs.length - 1].id : 0;
                root.stReachable = true;
                root.stFailures = 0;
                root.stPoll();
            }, 5000);
        });
    }

    // Long-poll: Syncthing holds the request until events arrive or its 60s
    // timeout passes, then we immediately ask again from the last id.
    function stPoll() {
        root.stPollXhr = root.stGet("/rest/events?events=" + root.stEventMask + "&since=" + root.stSince + "&timeout=60",
            (evs, err) => {
                root.stPollXhr = null;
                if (err)
                    return root.stFail(err);
                for (const ev of evs) {
                    root.stSince = Math.max(root.stSince, ev.id);
                    root.stApplyEvent(ev);
                }
                root.stPoll();
            }, 75000);
    }

    function stApplyEvent(ev) {
        const d = ev.data ?? {};
        switch (ev.type) {
        case "FolderSummary":
            return root.stApplySummary(d.folder, d.summary ?? {});
        case "StateChanged":
            return root.stPatchFolders(f => f.id === d.folder ? { state: d.to } : null);
        case "FolderErrors": {
            const n = (d.errors ?? []).length;
            const f = root.stFolders.find(x => x.id === d.folder);
            if (n > 0 && f && f.errors === 0)
                root.pushActivity({ time: Date.parse(ev.time) || Date.now(), source: "sync", sev: "err",
                                    title: f.label + "  ·  " + n + " pull errors",
                                    detail: d.errors[0]?.path ?? "" });
            return root.stPatchFolders(f => f.id === d.folder ? { errors: n } : null);
        }
        case "FolderPaused":
        case "FolderResumed":
            return root.stPatchFolders(f => f.id === d.id ? { paused: ev.type === "FolderPaused" } : null);
        case "FolderCompletion":
            return root.stApplyCompletion(d);
        case "DeviceConnected":
            return root.stPatchDevice(d.id, { connected: true, address: d.addr ?? "", type: d.type ?? "",
                                              clientVersion: d.clientVersion ?? "" });
        case "DeviceDisconnected":
            return root.stPatchDevice(d.id, { connected: false });
        case "DevicePaused":
        case "DeviceResumed":
            return root.stPatchDevice(d.device, { paused: ev.type === "DevicePaused" });
        case "ConfigSaved":
            return Qt.callLater(root.stResync);
        case "LocalChangeDetected":
        case "RemoteChangeDetected": {
            const c = root.stChange(ev);
            root.stChanges = [c].concat(root.stChanges).slice(0, root.maxChanges);
            if (c.kind === "file" && c.action !== "deleted") {
                const folderId = d.folderID ?? d.folder;
                root.stPatchFolders(f => f.id === folderId ? { lastFile: c.path, lastFileAt: c.time } : null);
            }
            return;
        }
        }
    }

    property var stDeviceNames: ({})
    property var stDevicePaused: ({})

    function stChange(e) {
        const d = e.data ?? {};
        const folderId = d.folderID ?? d.folder;
        return {
            time: e.time,
            remote: e.type === "RemoteChangeDetected",
            action: d.action ?? "",
            kind: d.type ?? "",
            path: d.path ?? "",
            folder: d.label || root.stFolders.find(f => f.id === folderId)?.label || folderId || ""
        };
    }

    // patch(folder) returns the fields to change, or null to leave it.
    function stPatchFolders(patch) {
        let changed = false;
        const next = root.stFolders.map(f => {
            const p = patch(f);
            if (!p)
                return f;
            changed = true;
            return Object.assign({}, f, p);
        });
        if (changed)
            root.setIfChanged("stFolders", next);
    }

    function stApplySummary(folderId, s) {
        root.stPatchFolders(f => f.id !== folderId ? null : {
            state: s.state ?? f.state,
            globalFiles: s.globalFiles ?? 0,
            globalBytes: s.globalBytes ?? 0,
            localFiles: s.localFiles ?? 0,
            needFiles: (s.needFiles ?? 0) + (s.needDeletes ?? 0) + (s.needSymlinks ?? 0),
            needBytes: s.needBytes ?? 0,
            inSyncBytes: s.inSyncBytes ?? 0,
            errors: (s.errors ?? 0) + (s.pullErrors ?? 0)
        });
    }

    // Same mapping as the old script, for the watched device/folder only
    // (FolderCompletion fires for every pair).
    function stApplyCompletion(c) {
        if ((c.device && c.device !== root.stDevice) || (c.folder && c.folder !== root.stFolder))
            return;
        if ((c.needItems ?? 0) === 0 && (c.needBytes ?? 0) === 0)
            root.stSync = "synced";
        else if ((c.completion ?? 0) >= 99.5)
            root.stSync = "almost";
        else
            root.stSync = "syncing";
    }

    function stPatchDevice(id, fields) {
        const i = root.stDevices.findIndex(d => d.id === id);
        if (i < 0) {
            // Not seen in connections yet - pick it up properly.
            root.stRefreshConnections();
            return;
        }
        const next = root.stDevices.slice();
        next[i] = Object.assign({}, next[i], fields);
        root.setIfChanged("stDevices", root.stSortDevices(next));
    }

    function stSortDevices(list) {
        return list.sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name));
    }

    // Connections + traffic counters. Counters have no event, so the panel
    // calls this on a timer while it's open; the bar never needs them.
    function stRefreshConnections() {
        if (!root.stConfigured)
            return;
        root.stGet("/rest/system/connections", (data, err) => {
            if (err)
                return;
            const conns = data.connections ?? {};
            root.setIfChanged("stDevices", root.stSortDevices(Object.keys(conns).map(id => {
                const c = conns[id];
                return {
                    id: id,
                    name: root.stDeviceNames[id] ?? id.slice(0, 7),
                    connected: c.connected ?? false,
                    paused: c.paused ?? root.stDevicePaused[id] ?? false,
                    address: c.address ?? "",
                    type: c.type ?? "",
                    inBytes: c.inBytesTotal ?? 0,
                    outBytes: c.outBytesTotal ?? 0,
                    clientVersion: c.clientVersion ?? ""
                };
            })));
            root.stTotals = data.total
                ? { inBytes: data.total.inBytesTotal ?? 0, outBytes: data.total.outBytesTotal ?? 0 } : null;
        });
    }

    Timer {
        id: stRetry
        onTriggered: root.stResync()
    }

    Component.onCompleted: {
        root.fetchContainers();
        root.stResync();
    }

    // ---- Tailscale (polled) ----

    Process {
        id: tsProc
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            id: tsOut
            onStreamFinished: {
                try {
                    const data = JSON.parse(tsOut.text);
                    const peer = p => {
                        const os = p.OS ?? "";
                        const host = p.HostName ?? "";
                        return {
                            id: p.ID ?? p.PublicKey ?? host,
                            hostName: host,
                            dnsName: (p.DNSName ?? "").replace(/\.$/, ""),
                            ip: p.TailscaleIPs?.[0] ?? "",
                            os: os,
                            kind: /ipad|tablet/i.test(host) ? "tablet"
                                  : os === "iOS" || os === "android" ? "phone"
                                  : os === "macOS" || os === "windows" ? "laptop" : "server",
                            online: p.Online ?? false,
                            lastSeen: p.LastSeen ?? "",
                            exitNode: p.ExitNode ?? false,
                            exitOption: p.ExitNodeOption ?? false,
                            via: !(p.Online ?? false) ? "" : (p.CurAddr ?? "").length > 0 ? "direct" : (p.Relay ?? "")
                        };
                    };
                    root.tsState = data.BackendState ?? "";
                    root.tsSelf = data.Self ? peer(data.Self) : null;
                    root.tsTailnet = data.CurrentTailnet?.Name ?? "";
                    const peers = Object.values(data.Peer ?? {}).map(peer).sort((a, b) =>
                        (b.online - a.online) || a.hostName.localeCompare(b.hostName));
                    // On/offline transitions into the feed (not on the first
                    // load - that's state, not news).
                    if (root.tsLoaded) {
                        for (const p of peers) {
                            const old = root.tsPeers.find(o => o.id === p.id);
                            if (old && old.online !== p.online)
                                root.pushActivity({ time: Date.now(), source: "peer", sev: p.online ? "ok" : "off",
                                                    title: p.hostName, detail: p.online ? "came online" : "went offline" });
                        }
                    }
                    root.tsLoaded = true;
                    root.setIfChanged("tsPeers", peers);
                } catch (e) {
                    root.tsState = "Unavailable";
                    root.tsSelf = null;
                    root.tsPeers = [];
                }
            }
        }
    }

    property bool tsLoaded: false

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!tsProc.running) tsProc.running = true
    }
}
