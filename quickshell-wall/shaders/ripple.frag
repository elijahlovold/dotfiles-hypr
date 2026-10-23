#version 440

// Ripple. A ring spreads from `origin`; inside it the frame is gone, and
// ahead of it the frame is refracted by a decaying wave, with the front lit
// in edgeColor. Run backwards the ring closes in on the impact, the new
// video rippling in behind it. Coordinates are in px; progress runs 0 -> 1.

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

const float PI = 3.14159265;
const float BAND = 0.9;       // of cellSize: how far ahead the wave reaches
const float WAVELENGTH = 0.35; // of cellSize
const float AMPLITUDE = 0.12;  // of cellSize: strongest displacement
const float SOFT = 0.06;       // of cellSize: the front's edge

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
    if (alpha <= 0.0) {
        fragColor = vec4(0.0);
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
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
