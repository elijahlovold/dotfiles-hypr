#version 440

// Ripple. A ring spreads from `origin`; inside it the frame is gone, and
// ahead of it the frame is refracted by a decaying wave, with the front lit
// in edgeColor. Run backwards the ring closes in on the impact, the new
// video rippling in behind it. With lightning the front is a jagged arc.
// Coordinates are in px; progress runs 0 -> 1.

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
const float BAND = 0.9;       // of cellSize: how far ahead the wave reaches
const float WAVELENGTH = 0.35; // of cellSize
const float AMPLITUDE = 0.12;  // of cellSize: strongest displacement
const float SOFT = 0.06;       // of cellSize: the front's edge

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
    vec2 far = max(origin, resolution - origin);
    float maxDist = length(far);
    float band = cellSize * BAND;
    float soft = cellSize * SOFT;
    // Zero at both ends, so the first and last frames are untouched.
    float env = sin(PI * progress);
    float ring = mix(-band, maxDist + 2.0 * soft, progress);

    vec2 dir = q - origin;
    float d = length(dir);
    dir /= max(d, 1e-3);
    float ahead = d - ring;

    float alpha = smoothstep(-soft, soft, ahead);
    vec3 bolt = vec3(0.0);
    float b = 0.0;
    if (lightning > 0.0) {
        // Along the ring (s = arc length), twice over for a tangled arc.
        float s = atan(dir.y, dir.x) * max(ring, 1.0);
        b = (boltLine(ahead, s, cellSize * 0.1, 1.0) + 0.6 * boltLine(ahead, s, cellSize * 0.16, 7.0)) * env;
        bolt = boltColor() * b;
    }
    if (alpha <= 0.0) {
        fragColor = vec4(bolt, clamp(b, 0.0, 1.0)) * qt_Opacity;
        return;
    }
    float decay = exp(-max(ahead, 0.0) / band * 3.0);
    float phase = ahead / (cellSize * WAVELENGTH) * 2.0 * PI;
    float wave = sin(phase) * decay * env;
    vec2 p = q + dir * wave * cellSize * AMPLITUDE;
    vec3 col = texture(source, clamp(p / resolution, 0.0, 1.0)).rgb;
    // Light the wave's slopes, and the front itself.
    col *= 1.0 + 0.18 * cos(phase) * decay * env;
    col += edgeColor.rgb * exp(-pow(ahead / (2.0 * soft), 2.0)) * 0.7 * env;
    fragColor = vec4(col * alpha + bolt, clamp(alpha + b, 0.0, 1.0)) * qt_Opacity;
}
