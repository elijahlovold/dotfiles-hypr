.pragma library

// Honeycomb placement for HexView: pointy-top tiles in rings around a hub
// tile at (0, 0) - 6 in the first ring, 12 in the second, 6k in ring k. A
// partial ring takes evenly spaced slots so it stays balanced. Each slot
// also names its parent (the nearest slot one ring in, or the hub), which
// is where it grows out of.
//
// R is the tile circumradius, gap the space between tile edges, both px.

var SQ3 = Math.sqrt(3);

// Center-to-center distance between neighbours, over √3.
function pitch(R, gap) {
    return R + gap / SQ3;
}

// [{ x, y, k (ring), j (index in ring), m (tiles in ring), px, py }],
// clockwise from the top within each ring.
function slots(n, R, gap) {
    const S = pitch(R, gap);
    const dirs = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]];
    const out = [];
    let left = n;
    for (let k = 1; left > 0; k++) {
        const ring = [];
        let q = -k, r = k;
        for (let i = 0; i < 6; i++) {
            for (let j = 0; j < k; j++) {
                const x = S * SQ3 * (q + r / 2), y = S * 1.5 * r;
                ring.push({ x: x, y: y, ang: ((Math.atan2(y, x) + Math.PI / 2) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI) });
                q += dirs[i][0];
                r += dirs[i][1];
            }
        }
        ring.sort((a, b) => a.ang - b.ang);
        const m = Math.min(left, ring.length);
        const inner = out.filter(s => s.k === k - 1);
        for (let j = 0; j < m; j++) {
            const s = ring[Math.round(j * ring.length / m) % ring.length];
            let par = { x: 0, y: 0 }, best = Infinity;
            for (const o of inner) {
                const d = Math.hypot(o.x - s.x, o.y - s.y);
                if (d < best) {
                    best = d;
                    par = o;
                }
            }
            out.push({ x: s.x, y: s.y, k: k, j: j, m: m, px: par.x, py: par.y });
        }
        left -= m;
    }
    return out;
}

// Distance from the hub center to the farthest tile edge.
function extent(n, R, gap) {
    let e = R;
    for (const s of slots(n, R, gap))
        e = Math.max(e, Math.hypot(s.x, s.y) + R);
    return e;
}
