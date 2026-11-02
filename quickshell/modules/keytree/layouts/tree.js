.pragma library

// Branches for TreeView. Leaves sit in a rounded cluster (a loose circle,
// open where the branch comes in); branches come from recursively
// splitting the leaves - in order around the cluster - into two groups,
// forking `fork` of the way toward each group's centroid. Branch width
// follows Leonardo's rule (w ∝ √leaves carried). Times are in growth
// steps: a segment at depth d grows during step d, a leaf blooms when its
// last segment is done.
//
// cfg: KeytreeConfig.layout.tree { trunk, canopy, thickness, fork }.

// Leaf positions around (0, 0): an arc covering all but `gapAng` around
// angle `gapDir`, two interleaved rings when crowded, slightly irregular,
// grown until every pair of leaves clears by a fifth of a node.
function cluster(n, R, gapDir, gapAng, nodeD, seed) {
    const two = n > 7;
    const a0 = gapDir + gapAng / 2, a1 = gapDir + 2 * Math.PI - gapAng / 2;
    const jitter = [];
    let s = seed >>> 0;
    for (let i = 0; i < n; i++) {
        s = (s * 1103515245 + 12345) >>> 0;
        jitter.push(1 + ((s >>> 8) % 1000 / 1000 - 0.5) * 0.12);
    }
    const place = r => {
        const out = [];
        for (let i = 0; i < n; i++) {
            const a = n === 1 ? gapDir + Math.PI : a0 + (a1 - a0) * i / (n - 1);
            const k = (two && i % 2 ? 0.6 : 1) * jitter[i];
            out.push({ x: r * k * 1.12 * Math.cos(a), y: r * k * Math.sin(a) });
        }
        return out;
    };
    const tight = ls => {
        for (let i = 0; i < ls.length; i++)
            for (let j = i + 1; j < ls.length; j++)
                if (Math.hypot(ls[i].x - ls[j].x, ls[i].y - ls[j].y) < nodeD * 1.2)
                    return true;
        return false;
    };
    let r = R, ls = place(r);
    while (tight(ls) && r < R * 6) {
        r *= 1.05;
        ls = place(r);
    }
    return { leaves: ls, r: r };
}

function width(cfg, n) {
    return cfg.thickness * Math.sqrt(n) * 1.25;
}

function segment(A, dir, B, w0, w1, depth) {
    const len = Math.hypot(B[0] - A[0], B[1] - A[1]);
    return {
        A: A, B: B, w0: w0, w1: w1, depth: depth,
        C: [A[0] + Math.cos(dir) * len * 0.45, A[1] + Math.sin(dir) * len * 0.45],
        seed: Math.round(A[0] * 7 + B[1] * 13) >>> 0
    };
}

// Segments from A (heading `dir`) to every leaf in `leaves` (each { i, x,
// y }); sets leaf.dir (arrival heading) and leaf.depth (bloom step).
function branch(A, dir, leaves, depth, segs, cfg) {
    if (leaves.length === 1) {
        const L = leaves[0];
        segs.push(segment(A, dir, [L.x, L.y], width(cfg, 1) * 1.15, width(cfg, 1), depth));
        L.dir = Math.atan2(L.y - A[1], L.x - A[0]);
        L.depth = depth + 1;
        return;
    }
    let cx = 0, cy = 0;
    for (const l of leaves) {
        cx += l.x / leaves.length;
        cy += l.y / leaves.length;
    }
    let J = [A[0] + (cx - A[0]) * cfg.fork, A[1] + (cy - A[1]) * cfg.fork];
    if (Math.hypot(J[0] - A[0], J[1] - A[1]) < 30)
        J = [A[0] + Math.cos(dir) * 30, A[1] + Math.sin(dir) * 30];
    segs.push(segment(A, dir, J, width(cfg, leaves.length), width(cfg, leaves.length) * 0.92, depth));
    const nd = Math.atan2(J[1] - A[1], J[0] - A[0]), h = Math.ceil(leaves.length / 2);
    branch(J, nd, leaves.slice(0, h), depth + 1, segs, cfg);
    branch(J, nd, leaves.slice(h), depth + 1, segs, cfg);
}

function finish(segs, leaves, nodeR, hub) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    const grow = (x, y, m) => {
        x0 = Math.min(x0, x - m); y0 = Math.min(y0, y - m);
        x1 = Math.max(x1, x + m); y1 = Math.max(y1, y + m);
    };
    for (const s of segs) {
        grow(s.A[0], s.A[1], s.w0 + 30);
        grow(s.B[0], s.B[1], s.w1 + 30);
        grow(s.C[0], s.C[1], s.w0 + 30);
    }
    let depth = 0;
    for (const l of leaves) {
        grow(l.x, l.y, nodeR + 4);
        depth = Math.max(depth, l.depth);
    }
    return { segs: segs, leaves: leaves, hub: hub, depth: depth, box: { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } };
}

// The root level: trunk up from (baseX, groundY), canopy above it.
function root(n, baseX, groundY, nodeD, cfg) {
    const top = [baseX, groundY - cfg.trunk];
    const c = cluster(n, cfg.canopy * 0.55, Math.PI / 2, 1.25, nodeD, 17);
    const cy = top[1] - c.r * 0.8;
    const leaves = c.leaves.map((p, i) => ({ i: i, x: baseX + p.x, y: cy + p.y }));
    const segs = [segment([baseX, groundY], -Math.PI / 2, top, width(cfg, n) * 1.5, width(cfg, n), 0)];
    branch(top, -Math.PI / 2, leaves, 1, segs, cfg);
    return finish(segs, leaves, nodeD / 2, top);
}

// A folder level sprouting from leaf `from` ({ x, y, dir }): a cluster
// ahead of it, turned partway toward straight up.
function folder(n, from, nodeD, cfg) {
    const head = from.dir + (-Math.PI / 2 - from.dir) * 0.35;
    const c = cluster(n, nodeD * 1.4, head + Math.PI, 1.4, nodeD, Math.round(from.x * 3 + from.y) >>> 0);
    const dist = c.r + nodeD * 0.9;
    const cx = from.x + Math.cos(head) * dist, cy = from.y + Math.sin(head) * dist;
    const leaves = c.leaves.map((p, i) => ({ i: i, x: cx + p.x, y: cy + p.y }));
    const start = [from.x + Math.cos(from.dir) * nodeD / 2, from.y + Math.sin(from.dir) * nodeD / 2];
    const segs = [];
    branch(start, from.dir, leaves, 0, segs, cfg);
    return finish(segs, leaves, nodeD / 2, [from.x, from.y]);
}
