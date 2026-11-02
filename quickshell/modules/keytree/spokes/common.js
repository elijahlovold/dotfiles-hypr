.pragma library

// Geometry + drawing helpers shared by the spoke styles. Everything works
// on the frame `S` that CanvasSpokes hands each painter (documented there).

var TAU = Math.PI * 2;

function clamp(v, lo, hi) {
    return Math.min(hi === undefined ? 1 : hi, Math.max(lo === undefined ? 0 : lo, v));
}

function lerp(a, b, u) {
    return a + (b - a) * u;
}

// Local 0..1 progress of a sub-step running from t0 to t1 of the reveal.
function stage(t, t0, t1) {
    return clamp((t - t0) / (t1 - t0));
}

// Point at radius r, angle a around the view center.
function polar(S, r, a) {
    return [S.cx + r * Math.cos(a), S.cy + r * Math.sin(a)];
}

// Point a fraction u of the way from the hub rim to node n, on its axis.
function along(S, n, u) {
    return polar(S, lerp(S.h, n.d, u), n.a);
}

// Unit vector 90° clockwise of angle a.
function perp(a) {
    return [-Math.sin(a), Math.cos(a)];
}

// f(u) sampled at u = 0, 1/N, ..., 1.
function sample(N, f) {
    const out = [];
    for (let i = 0; i <= N; i++)
        out.push(f(i / N));
    return out;
}

function quad(p0, c, p1, N) {
    return sample(N || 24, u => {
        const v = 1 - u;
        return [v * v * p0[0] + 2 * v * u * c[0] + u * u * p1[0],
                v * v * p0[1] + 2 * v * u * c[1] + u * u * p1[1]];
    });
}

// Seeded PRNG (mulberry32), so jittered styles stay stable between paints
// until they choose to change the seed.
function rng(seed) {
    let s = seed >>> 0;
    return () => {
        s += 0x6D2B79F5;
        let t = s;
        t = Math.imul(t ^ t >>> 15, t | 1);
        t ^= t + Math.imul(t ^ t >>> 7, t | 61);
        return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
}

// Leading fraction f of a polyline, by arc length - how strokes grow
// outward during the reveal.
function partial(pts, f) {
    if (f >= 1)
        return pts;
    if (f <= 0 || pts.length < 2)
        return [];
    const seg = [];
    let total = 0;
    for (let i = 1; i < pts.length; i++) {
        const d = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
        seg.push(d);
        total += d;
    }
    let left = f * total;
    const out = [pts[0]];
    for (let i = 1; i < pts.length; i++) {
        if (left <= seg[i - 1]) {
            const u = seg[i - 1] ? left / seg[i - 1] : 0;
            out.push([lerp(pts[i - 1][0], pts[i][0], u), lerp(pts[i - 1][1], pts[i][1], u)]);
            return out;
        }
        left -= seg[i - 1];
        out.push(pts[i]);
    }
    return out;
}

function path(ctx, pts) {
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++)
        ctx.lineTo(pts[i][0], pts[i][1]);
}

// Stroke the first fraction f of pts. o: { w: width, a: alpha }; color is
// S.color unless o.c is given.
function stroke(ctx, S, pts, f, o) {
    const q = partial(pts, f);
    if (q.length < 2)
        return;
    path(ctx, q);
    ctx.globalAlpha = o.a === undefined ? 1 : o.a;
    ctx.lineWidth = o.w;
    ctx.strokeStyle = o.c || S.color;
    ctx.stroke();
    ctx.globalAlpha = 1;
}

// Filled band along pts, width tapering w0 -> w1, cut at fraction f of its
// samples (pts should be evenly sampled).
function ribbon(ctx, S, pts, f, w0, w1, alpha) {
    const n = Math.round(pts.length * clamp(f));
    if (n < 2)
        return;
    const left = [], right = [];
    for (let i = 0; i < n; i++) {
        const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)];
        let nx = -(b[1] - a[1]), ny = b[0] - a[0];
        const m = Math.hypot(nx, ny) || 1;
        nx /= m;
        ny /= m;
        const w = lerp(w0, w1, i / (pts.length - 1)) / 2;
        left.push([pts[i][0] + nx * w, pts[i][1] + ny * w]);
        right.push([pts[i][0] - nx * w, pts[i][1] - ny * w]);
    }
    path(ctx, left.concat(right.reverse()));
    ctx.closePath();
    ctx.globalAlpha = alpha;
    ctx.fillStyle = S.color;
    ctx.fill();
    ctx.globalAlpha = 1;
}
