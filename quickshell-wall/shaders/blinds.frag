#version 440

// Blinds. The frame is cut into horizontal slats that each turn edge-on
// about their own axis, shading as they turn. They go in a wave outward
// from `origin`, nearest slats first. Run backwards the slats turn the new
// video in. With lightning, bolts run along the opening gaps between slats,
// outward from `origin`. Coordinates are in px; progress runs 0 -> 1.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    vec2 resolution;
    vec2 origin;
    float cellSize;
    float seed;
    vec4 edgeColor;
    float lightning;  // WallConfig.lightning: 0 skips the bolts entirely
};
layout(binding = 1) uniform sampler2D source;

const float PI = 3.14159265;
const float SLAT = 0.6;     // of cellSize: slat height
const float STAGGER = 0.5;  // the farthest slat starts this much later

// ---- Lightning (only when `lightning` is on) ----
float lhash(float x) {
    return fract(sin(x * 127.1) * 43758.5453 + seed);
}

float lnoise(float x) {
    float i = floor(x);
    float f = fract(x);
    return mix(lhash(i), lhash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// A jagged bolt along a line: x px across it, s px along it, `size` its
// wander. Re-jags every 1/14 of the transition, so it crackles. Thin core
// plus halo; 0 far from it.
float boltLine(float x, float s, float size, float salt) {
    float shape = floor(progress * 14.0) * 13.7 + salt;
    float jag = (lnoise(s / (size * 2.5) + shape) - 0.5) * size
              + (lnoise(s / (size * 0.6) + shape * 3.1) - 0.5) * size * 0.35;
    float d = abs(x - jag);
    float lw = max(1.0, resolution.y / 1440.0);
    return (1.0 - smoothstep(0.5 * lw, 1.8 * lw, d)) + 0.5 * exp(-d / (size * 0.35));
}

vec3 boltColor() {
    return mix(edgeColor.rgb, vec3(1.0), 0.6);
}

// How far slat k (centred at yc) has turned, eased: 0 flat, 1 edge-on.
float slatTurn(float yc, vec2 far) {
    float dy = abs(yc - origin.y) / far.y;
    float t = clamp((progress - STAGGER * dy) / (1.0 - STAGGER), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

void main() {
    vec2 q = qt_TexCoord0 * resolution;
    float h = cellSize * SLAT;
    float yc = (floor(q.y / h) + 0.5) * h;
    vec2 far = max(origin, resolution - origin);
    float t = slatTurn(yc, far);
    float angle = t * 0.5 * PI;
    float scale = cos(angle);
    // Back to the slat's own height: past its edge (or edge-on) it's gone.
    float ly = (q.y - yc) / max(scale, 1e-4);
    vec4 col = vec4(0.0);
    if (scale >= 1e-3 && abs(ly) <= 0.5 * h) {
        vec3 c = texture(source, vec2(q.x, yc + ly) / resolution).rgb;
        float turn = sin(angle);
        // Darker as it turns away, the far half more than the near one.
        c *= (1.0 - 0.55 * turn) * (1.0 - 0.3 * turn * ly / (0.5 * h));
        // A glint along the leading edge.
        c += edgeColor.rgb * turn * scale * 1.2 * smoothstep(0.38 * h, 0.5 * h, -ly);
        col = vec4(c, 1.0);
    }

    if (lightning > 0.0) {
        // The nearest gap, between the slats above and below it.
        float gy = floor(q.y / h + 0.5) * h;
        float tg = 0.5 * (slatTurn(gy - 0.5 * h, far) + slatTurn(gy + 0.5 * h, far));
        // Grows along the gap from origin's side while it opens; gone once
        // both slats are flat or edge-on, so both ends stay clean.
        float reach = tg * 1.4;
        float dx = abs(q.x - origin.x) / far.x;
        float b = boltLine(q.y - gy, q.x, cellSize * 0.12, gy * 0.37)
                * sin(PI * tg) * smoothstep(reach, reach - 0.08, dx);
        col.rgb += boltColor() * b;
        col.a = clamp(col.a + b, 0.0, 1.0);
    }
    // Premultiplied: slats are opaque, bolts in the gaps add light.
    fragColor = col * qt_Opacity;
}
