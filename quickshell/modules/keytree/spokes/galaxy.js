.pragma library
.import "common.js" as C

// Logarithmic spiral arms (galaxy arms, nautilus): r = h·(d/h)^u,
// θ = a − 1.25(1−u), so every arm keeps the same pitch angle at any scale.
// A fainter, more swept dust lane trails each arm, with a few seeded dust
// specks between the two.
var SWEEP = 1.25;
var LANE = 1.9;

function draw(ctx, S) {
    for (const n of S.nodes) {
        const k = n.d / S.h;
        const at = (u, w) => C.polar(S, S.h * Math.pow(k, u), n.a - w * (1 - u));
        C.stroke(ctx, S, C.sample(40, u => at(u, LANE)), S.t, { w: S.lw * 0.7, a: 0.25 });
        C.stroke(ctx, S, C.sample(40, u => at(u, SWEEP)), S.t, { w: S.lw * 1.3, a: 0.85 });

        const r = C.rng(n.i * 31 + 5);
        ctx.fillStyle = S.color;
        ctx.globalAlpha = 0.4;
        for (let j = 0; j < 9; j++) {
            const u = 0.15 + r() * 0.8;
            const p = at(u, C.lerp(SWEEP, LANE, r()));
            const jx = (r() - 0.5) * 4, jy = (r() - 0.5) * 4;
            if (u > S.t)
                continue;
            ctx.beginPath();
            ctx.arc(p[0] + jx, p[1] + jy, S.lw * 0.8, 0, C.TAU);
            ctx.fill();
        }
        ctx.globalAlpha = 1;
    }
}
