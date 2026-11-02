.pragma library
.import "common.js" as C

// Whirlpool: Archimedean arms (r linear) that wind 0.8 of a turn before
// reaching their node. All arms share one winding, so they never cross.
// Folders get the heavier arm.
var TURNS = 0.8;

function draw(ctx, S) {
    for (const n of S.nodes) {
        const pts = C.sample(64, u => C.polar(S, C.lerp(S.h, n.d, u), n.a - TURNS * C.TAU * (1 - u)));
        C.stroke(ctx, S, pts, S.t, n.isLeaf ? { w: S.lw * 0.9, a: 0.55 } : { w: S.lw * 1.3, a: 0.85 });
    }
}
