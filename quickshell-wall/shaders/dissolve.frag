#version 440

// Burn-away dissolve. A noise field, biased by distance from `origin` so it
// spreads out from there, sets when each pixel goes: it chars, flares in
// edgeColor along the burning front, then shows the live video. Coordinates
// are in px; progress runs 0 -> 1.

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

const float CHAR = 0.08;  // darkening ahead of the front
const float BAND = 0.05;  // glowing front width

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453 + seed);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p *= 2.03;
        a *= 0.5;
    }
    return v / 0.96875;
}

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

void main() {
    vec2 q = qt_TexCoord0 * resolution;
    float maxDist = length(max(origin, resolution - origin));

    // fbm bunches up mid-range; spread it to 0..1 so the start isn't dead air.
    float n = smoothstep(0.2, 0.8, fbm(q / cellSize * 1.5));
    float when = 0.6 * n + 0.4 * distance(q, origin) / maxDist;
    // Front sweeps from below 0 to past 1 + BAND, so both ends are clean.
    float k = progress * (1.0 + CHAR + 2.0 * BAND) - CHAR - when;

    vec3 col = texture(source, qt_TexCoord0).rgb;
    col *= 1.0 - 0.7 * smoothstep(-CHAR, 0.0, k);
    float glow = smoothstep(0.0, BAND, k);
    col = mix(col, edgeColor.rgb * 1.6, glow);
    float alpha = 1.0 - smoothstep(BAND, 2.0 * BAND, k);
    col *= alpha;

    if (lightning > 0.0) {
        // On the front only (zero at both ends of the sweep): ridged noise
        // gives thin branching veins, re-rolled each step so they crackle.
        float front = smoothstep(-0.5 * CHAR, BAND, k) * (1.0 - smoothstep(BAND, 2.0 * BAND, k));
        if (front > 0.0) {
            vec2 shift = vec2(floor(progress * 14.0) * 7.31, 0.0);
            float r1 = 1.0 - abs(2.0 * noise(q / (cellSize * 0.35) + shift) - 1.0);
            float r2 = 1.0 - abs(2.0 * noise(q / (cellSize * 0.12) + shift * 1.7) - 1.0);
            float veins = pow(r1, 24.0) + 0.6 * pow(r2, 30.0);
            float b = veins * front * 2.0;
            col += boltColor() * b;
            alpha = clamp(alpha + b, 0.0, 1.0);
        }
    }
    fragColor = vec4(col, alpha) * qt_Opacity;
}
