pragma Singleton
import QtQuick

// Shared Canvas path builders for structural-theme skins. Pure geometry
// only - never touches fillStyle/strokeStyle/lineDash/color, since which
// colors/dashes a given skin uses is the one part that legitimately
// differs per call site (see PopupFrame.qml/Pill.qml's hollowKnightSkin,
// BarEdgeDecoration.qml's hollowKnightSkin). Extracted after the first two
// independent copies of facetedPath started drifting - see PopupFrame.qml/
// Pill.qml's git history - rather than pre-built, per CLAUDE.md's general
// bias against speculative abstraction.
QtObject {
    // Corner-cut ("chitin plate") outline - HollowKnight's signature shape.
    // `inset` lets a caller draw both an outer solid outline and a smaller
    // inner dashed "stitch" line with one function.
    function facetedPath(ctx, w, h, inset, cut) {
        ctx.beginPath();
        ctx.moveTo(inset + cut, inset);
        ctx.lineTo(w - inset - cut, inset);
        ctx.lineTo(w - inset, inset + cut);
        ctx.lineTo(w - inset, h - inset - cut);
        ctx.lineTo(w - inset - cut, h - inset);
        ctx.lineTo(inset + cut, h - inset);
        ctx.lineTo(inset, h - inset - cut);
        ctx.lineTo(inset, inset + cut);
        ctx.closePath();
    }

    // Slow sine "thread" line - HollowKnight's organic-motion counterpart
    // to Halo's crisp straight rules.
    function wavyPath(ctx, w, h, amplitude, period) {
        const mid = h / 2;
        ctx.beginPath();
        ctx.moveTo(0, mid);
        for (let x = 0; x <= w; x += 4)
            ctx.lineTo(x, mid + Math.sin(x / period) * amplitude);
    }
}
