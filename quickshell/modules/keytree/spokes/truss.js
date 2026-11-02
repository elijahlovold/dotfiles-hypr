.pragma library
.import "common.js" as C

// Warren truss (crane boom, space frame): two chords tapering toward the
// node with a zigzag web between them. Panel count follows spoke length,
// so the web is equally dense on both rings.
function draw(ctx, S) {
    for (const n of S.nodes) {
        const pp = C.perp(n.a);
        const half = u => C.lerp(S.nr * 0.34, S.nr * 0.14, u);
        const side = (u, s) => {
            const b = C.along(S, n, u);
            return [b[0] + pp[0] * half(u) * s, b[1] + pp[1] * half(u) * s];
        };
        C.stroke(ctx, S, [side(0, 1), side(1, 1)], S.t, { w: S.lw, a: 0.85 });
        C.stroke(ctx, S, [side(0, -1), side(1, -1)], S.t, { w: S.lw, a: 0.85 });

        const panels = Math.max(4, Math.round((n.d - S.h) / (S.nr * 0.5)));
        const web = C.sample(panels, u => side(u, Math.round(u * panels) % 2 ? 1 : -1));
        C.stroke(ctx, S, web, S.t, { w: S.lw * 0.7, a: 0.5 });
    }
}
