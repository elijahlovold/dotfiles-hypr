// Lightning: a jagged forked bolt every 3-5 s, plus a flash over the screen.
//
// Screen shaders keep no state between frames, so everything is a function
// of time: time is cut into LIGHTNING_SLOT-second slots, each with one
// strike starting at a hashed offset inside its first LIGHTNING_JITTER
// seconds. Strikes are therefore SLOT +/- JITTER apart. Outside a strike the
// function returns the colour unchanged without doing any bolt math.

#include "hash.glsl"

#define LIGHTNING_SLOT 4.0
#define LIGHTNING_JITTER 1.0
#define LIGHTNING_LENGTH 0.6    // seconds a strike stays visible
#define LIGHTNING_FLASH 0.22    // whole-screen brightening at the peak
#define LIGHTNING_BRANCHES 3
#define LIGHTNING_LEADER 0.07   // seconds the bolt takes to grow before it flashes

// The bolt's sideways offset is octaves of piecewise-linear noise, each
// exactly twice the frequency of the last, so the bolt is a polyline with
// its corners on the finest octave's grid. The sharp core uses all
// BOLT_OCTAVES; the wide glow follows a smoother BOLT_GLOW_OCTAVES version,
// whose longer segments let the same few-segment search cover the glow.
#define BOLT_FREQ 9.0
#define BOLT_OCTAVES 5
#define BOLT_GLOW_OCTAVES 3

// Piecewise-linear 1D noise in [-1, 1]: straight segments with sharp
// corners, which is what makes the bolt look like lightning, not a rope.
float boltNoise(float x, int seed) {
    float i = floor(x);
    float a = hash3(ivec3(int(i), seed, 77)).x;
    float b = hash3(ivec3(int(i) + 1, seed, 77)).x;
    return mix(a, b, fract(x)) * 2.0 - 1.0;
}

// Sideways offset of the bolt at s (0..1 along it), pinned to 0 at s = 0.
float boltOffset(float s, float len, int seed, int octaves) {
    float v = 0.0, amp = 1.0, x = s * len * BOLT_FREQ;
    for (int o = 0; o < octaves; o++) {
        v += amp * (boltNoise(x, seed + o * 13) - boltNoise(0.0, seed + o * 13));
        x *= 2.0;
        amp *= 0.5;
    }
    return v * 0.05 * len;
}

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a, ap = p - a;
    return length(ap - ab * clamp(dot(ap, ab) / max(dot(ab, ab), 1e-12), 0.0, 1.0));
}

// Exact distance from p to the bolt's polyline (from a to b, `octaves`
// detail), checking the 8 segments around p's position along it.
float boltPolyDist(vec2 p, vec2 a, vec2 b, int seed, int octaves, float s) {
    vec2 ab = b - a;
    float len = length(ab);
    vec2 dir = ab / len, nrm = vec2(-dir.y, dir.x);
    float n = len * BOLT_FREQ * exp2(float(octaves - 1));
    float i0 = floor(clamp(s, 0.0, 1.0) * n);
    float d = 1e9;
    vec2 prev = a;
    for (int j = -4; j <= 4; j++) {
        float sj = clamp((i0 + float(j)) / n, 0.0, 1.0);
        vec2 q = a + dir * sj * len + nrm * boltOffset(sj, len, seed, octaves);
        if (j > -4) d = min(d, segDist(p, prev, q));
        prev = q;
    }
    return d;
}

// Distances from p to the bolt from a to b: x = sharp core, y = glow.
// sOut = how far along the bolt p lies (0..1), to reveal it as it grows
// and fade branches.
vec2 boltDist(vec2 p, vec2 a, vec2 b, int seed, out float sOut) {
    vec2 ab = b - a;
    sOut = dot(p - a, ab) / dot(ab, ab);
    return vec2(boltPolyDist(p, a, b, seed, BOLT_OCTAVES, sOut),
                boltPolyDist(p, a, b, seed, BOLT_GLOW_OCTAVES, sOut));
}

// Brightness of the strike over its lifetime: a dim leader while the bolt
// grows, then 2-3 quick return strokes and a fading afterglow. 0 outside.
float strikeLevel(float lt, vec3 h) {
    if (lt < 0.0 || lt > LIGHTNING_LENGTH) return 0.0;
    if (lt < LIGHTNING_LEADER) return 0.3;
    lt -= LIGHTNING_LEADER;
    float p1 = 0.07 + 0.04 * h.x, p2 = 0.18 + 0.1 * h.y;
    float v = exp(-lt / 0.035);
    v = max(v, step(p1, lt) * 0.8 * exp(-(lt - p1) / 0.03));
    if (h.z > 0.35) v = max(v, step(p2, lt) * 0.9 * exp(-(lt - p2) / 0.05));
    v = max(v, 0.25 * exp(-lt / 0.2));
    return v * smoothstep(LIGHTNING_LENGTH - LIGHTNING_LEADER, (LIGHTNING_LENGTH - LIGHTNING_LEADER) * 0.7, lt);
}

vec3 lightning(vec2 fragCoord, vec3 col) {
    float slot = floor(iTime / LIGHTNING_SLOT);
    int k = int(slot);
    vec3 h = hash3(k, 1);
    float lt = iTime - slot * LIGHTNING_SLOT - h.x * LIGHTNING_JITTER;
    float level = strikeLevel(lt, hash3(k, 2));
    if (level <= 0.0) return col;

    // Aspect-correct space: y in 0..1, x in 0..aspect.
    float aspect = iResolution.x / iResolution.y;
    vec2 p = fragCoord / iResolution.y;
    vec3 g = hash3(k, 3);
    vec2 a, b;
    if (g.x < 0.3) {
        // Cloud-to-cloud: across the screen from one side to the other.
        bool ltr = g.y < 0.5;
        a = vec2(ltr ? -0.05 : aspect + 0.05, mix(0.6, 0.95, g.z));
        b = vec2(ltr ? aspect + 0.05 : -0.05, mix(0.45, 0.9, h.y));
    } else {
        // Top down to somewhere in the lower half.
        a = vec2(mix(0.1, 0.9, g.y) * aspect, 1.05);
        b = vec2(a.x + (g.z - 0.5) * 0.9, mix(-0.05, 0.45, h.z));
    }
    int seed = k * 7 + 11;

    float grow = clamp(lt / LIGHTNING_LEADER, 0.0, 1.0);
    float px = 1.0 / iResolution.y;
    float s;
    vec2 d = boltDist(p, a, b, seed, s);
    float reveal = step(s, grow);
    float core = smoothstep(2.2 * px, 0.5 * px, d.x) * reveal;
    float glow = exp(-d.y / (0.012 + 0.01 * level)) * reveal;

    vec2 ab = b - a;
    float len = length(ab);
    vec2 dir = ab / len, nrm = vec2(-dir.y, dir.x);
    for (int i = 0; i < LIGHTNING_BRANCHES; i++) {
        vec3 r = hash3(k, 10 + i);
        if (r.x < 0.25) continue;
        float s0 = mix(0.15, 0.7, r.y);
        if (grow < s0) continue;
        vec2 start = a + dir * s0 * len + nrm * boltOffset(s0, len, seed, BOLT_OCTAVES);
        float ang = (r.z < 0.5 ? -1.0 : 1.0) * mix(0.35, 0.8, fract(r.z * 7.0));
        vec2 bdir = mat2(cos(ang), sin(ang), -sin(ang), cos(ang)) * dir;
        vec2 end = start + bdir * min(len * mix(0.15, 0.35, r.x), 0.3);
        float bs;
        vec2 bd = boltDist(p, start, end, seed + 100 + i, bs);
        float fade = (1.0 - clamp(bs, 0.0, 1.0)) * step(bs, (grow - s0) / (1.0 - s0) * 1.5);
        core += smoothstep(1.6 * px, 0.4 * px, bd.x) * fade * 0.8;
        glow += exp(-bd.y / 0.008) * fade * 0.5;
    }

    vec3 boltCol = vec3(0.85, 0.88, 1.0);
    vec3 glowCol = vec3(0.55, 0.5, 1.0);
    // Flash: the whole screen lights up, more towards the top.
    float flash = LIGHTNING_FLASH * level * step(LIGHTNING_LEADER, lt) * (0.6 + 0.4 * fragCoord.y / iResolution.y);
    col += col * flash + vec3(0.75, 0.78, 0.95) * flash * 0.35;
    col += boltCol * min(core, 1.0) * level * 1.6 + glowCol * glow * level * 0.45;
    return col;
}
