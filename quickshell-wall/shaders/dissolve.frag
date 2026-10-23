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
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
