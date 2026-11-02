.pragma library

// Node placement for RadialView, kept apart from both the panel (window
// sizing, navigation) and the view (drawing), so a new arrangement only
// has to produce the same output shape:
//
//   { kind, nodes: [{ i, x, y, a, d, step, ring }] }
//
//   x, y   final node center, view-local px
//   a, d   polar angle (rad, 0 = +x, clockwise on screen) and distance
//          from the view center - what spoke styles route along
//   step   angular pitch to this node's neighbours on its ring
//   ring   0 = innermost; spoke styles use it to find neighbours
//
// `cfg` is KeytreeConfig.layout. Same ring math as the original keytree
// port.

// Node (and hub card) diameter in px.
function nodeDiameter(nodeScale) {
    return Math.round(64 * nodeScale);
}

// "rings" (two) at/over ringThreshold items, else "ring".
function pick(n, cfg) {
    return n >= cfg.ringThreshold ? "rings" : "ring";
}

// Window side length in px for n items (the view is square).
function windowSize(n, cfg) {
    return Math.round((pick(n, cfg) === "rings" ? 680 : 540) * cfg.ringScale);
}

function compute(n, width, height, cfg) {
    const kind = pick(n, cfg);
    if (n === 0 || width < 10 || height < 10)
        return { kind: kind, nodes: [] };
    return rings(n, width, height, kind === "rings");
}

// One ring, or two (inner gets floor(n/2)). With both counts even the
// outer ring is rotated half a pitch so its nodes sit between the inner
// ones.
function rings(n, width, height, two) {
    const size = Math.min(width, height);
    const cx = width / 2, cy = height / 2;
    const innerCount = two ? Math.floor(n / 2) : n;
    const outerCount = n - innerCount;
    const outerOffset = (two && innerCount % 2 === 0 && outerCount % 2 === 0) ? Math.PI / outerCount : 0;
    const innerR = size * (two ? 0.29 : 0.40);
    const outerR = size * 0.44;

    const nodes = [];
    for (let i = 0; i < n; i++) {
        const inner = !two || i < innerCount;
        const idx = inner ? i : i - innerCount;
        const count = inner ? innerCount : outerCount;
        const d = inner ? innerR : outerR;
        const a = count === 1 ? -Math.PI / 2 : -Math.PI / 2 + idx / count * 2 * Math.PI + (inner ? 0 : outerOffset);
        nodes.push({
            i: i, a: a, d: d,
            x: cx + d * Math.cos(a),
            y: cy + d * Math.sin(a),
            step: 2 * Math.PI / count,
            ring: inner ? 0 : 1
        });
    }
    return { kind: two ? "rings" : "ring", nodes: nodes };
}
