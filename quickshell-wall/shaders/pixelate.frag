#version 440

// Pixelate. The frame coarsens into ever bigger blocks (doubling in size),
// then the blocks shrink away, outward from `origin` with some scatter,
// each rimmed in edgeColor as it goes. Run backwards the new video
// assembles from blocks and sharpens. Coordinates are in px; progress runs
// 0 -> 1.

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

const float MAX_BLOCK = 0.25;  // of cellSize: the coarsest block
const float COARSEN_END = 0.45; // blocks are biggest from here
const float SPREAD = 0.33;     // the farthest block goes this much later
const float SCATTER = 0.1;
const float SHRINK = 0.12;     // one block's exit

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453 + seed);
}

void main() {
    vec2 q = qt_TexCoord0 * resolution;
    float levels = log2(max(cellSize * MAX_BLOCK, 1.0));
    float b = exp2(floor(levels * smoothstep(0.0, COARSEN_END, progress) + 1e-4));
    vec2 cell = floor(q / b);
    vec2 center = (cell + 0.5) * b;

    vec2 far = max(origin, resolution - origin);
    float d = distance(center, origin) / length(far);
    float go = COARSEN_END + SHRINK + SPREAD * d + SCATTER * hash(cell);
    float size = 1.0 - smoothstep(go - SHRINK, go, progress);
    vec2 local = abs(q - center) / (0.5 * b);
    float m = max(local.x, local.y);
    if (m > size) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 col = texture(source, center / resolution).rgb;
    float leaving = 1.0 - size;
    float rim = smoothstep(size - 2.0 / b * 2.0, size, m) * step(0.001, leaving);
    col = mix(col, edgeColor.rgb, rim * 0.8 * (1.0 - leaving));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
