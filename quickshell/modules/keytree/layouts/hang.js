.pragma library

// Strings for HangView: every node hangs from an anchor on a rail along the
// top edge. Strings are longer toward the middle (`centerDrop`); when the
// row is too tight for one line they alternate short/long so neighbours
// clear. A node drops from above the screen, catches with a spring bounce
// and swings to rest - all closed-form in time, so the view just samples
// state(node, t) each frame.
//
// cfg: KeytreeConfig.layout.hang { length, centerDrop, swing, bounce }.

var GRAVITY = 0.0045;     // px/ms²
var REEL = 0.006;         // px/ms², pulling up

// [{ ax, L, order, swing }] for n nodes on a rail of width railW centered
// at cx. `order` is distance from the middle (drops go center-out).
function strings(keys, cx, railW, nodeD, cfg) {
    const n = keys.length;
    const sp = Math.min(nodeD * 1.55, railW / Math.max(1, n));
    const tiers = sp < nodeD * 1.15;
    return keys.map((key, i) => {
        const u = n === 1 ? 0 : 2 * i / (n - 1) - 1;
        const h = hash(key);
        return {
            ax: cx + (i - (n - 1) / 2) * sp,
            L: cfg.length + cfg.centerDrop * (1 - u * u) + (tiers && i % 2 ? nodeD * 1.1 : 0),
            order: Math.abs(i - (n - 1) / 2),
            swing: (h % 2 ? -1 : 1) * cfg.swing * (0.6 + 0.4 * ((h >> 3) % 100) / 100)
        };
    });
}

// Node center relative to its anchor at time t (ms), or null once reeled
// off the top. s: { L, swing, t0 (drop start), rise (reel-up start or
// -1) }; nodeR to know when it's out of sight.
function state(s, t, nodeR, bounce) {
    const y0 = -nodeR * 2.4;
    const fall = s.L - y0, tf = Math.sqrt(2 * fall / GRAVITY);
    const tt = t - s.t0;
    if (tt < 0)
        return null;
    let len, th = 0;
    if (tt < tf) {
        len = y0 + 0.5 * GRAVITY * tt * tt;
    } else {
        const k = tt - tf;
        len = s.L + bounce * GRAVITY * tf * 26 * Math.exp(-k / 160) * Math.sin(k / 38);
        th = s.swing * Math.exp(-k / 700) * Math.sin(k / 260);
    }
    if (s.rise >= 0 && t > s.rise)
        len -= 0.5 * REEL * (t - s.rise) * (t - s.rise);
    if (len < -nodeR * 2.5)
        return null;
    return { x: Math.max(0, len) * Math.sin(th), y: len * Math.cos(th) };
}

// Whether s is still moving visibly at t (drop + bounce + swing settle).
function moving(s, t) {
    return s.rise >= 0 || t - s.t0 < 4500;
}

function hash(k) {
    let h = 7;
    for (let i = 0; i < k.length; i++)
        h = (h * 31 + k.charCodeAt(i)) >>> 0;
    return h;
}
