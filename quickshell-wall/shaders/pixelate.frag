#version 440

// Pixelate. The frame coarsens into ever bigger blocks (x1.4 a step)
// while, overlapping the end of that, tiles of the coarsest grid shrink
// away, outward from `origin` with some scatter, each rimmed in edgeColor
// as it goes. Run backwards the new video's tiles assemble and it's
// already sharpening as the last ones arrive. Coordinates are in px;
// progress runs 0 -> 1.

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

const float MAX_BLOCK = 0.25;   // of cellSize: the coarsest block
const float COARSEN_END = 0.6;  // blocks are biggest from here (even steps)
const float STEPS_PER_DOUBLING = 2.0;
const float LEAVE_START = 0.3;  // first tile starts leaving
const float SPREAD = 0.48;      // the farthest tile goes this much later
const float SCATTER = 0.1;
const float SHRINK = 0.12;      // one tile's exit; the last is gone by 1.0

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453 + seed);
}

void main() {
    vec2 q = qt_TexCoord0 * resolution;
    float levels = floor(log2(max(cellSize * MAX_BLOCK, 1.0)));
    // Colour: blocks of the current size, growing x1.4 at even steps - twice
    // the steps of plain doubling, so the visible sizes aren't rushed.
    float x = clamp(progress / COARSEN_END, 0.0, 1.0);
    float b = max(1.0, floor(exp2(floor(levels * STEPS_PER_DOUBLING * x + 1e-4) / STEPS_PER_DOUBLING)));
    vec2 center = (floor(q / b) + 0.5) * b;

    // Shape: tiles of the coarsest grid, fixed throughout, so a tile keeps
    // its timing while the blocks inside it change size.
    float tb = exp2(levels);
    vec2 tile = floor(q / tb);
    vec2 tileCenter = (tile + 0.5) * tb;
    vec2 far = max(origin, resolution - origin);
    float d = distance(tileCenter, origin) / length(far);
    float go = LEAVE_START + SHRINK + SPREAD * d + SCATTER * hash(tile);
    float size = 1.0 - smoothstep(go - SHRINK, go, progress);
    vec2 local = abs(q - tileCenter) / (0.5 * tb);
    float m = max(local.x, local.y);
    if (m > size) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 col = texture(source, center / resolution).rgb;
    float leaving = 1.0 - size;
    float rim = smoothstep(size - 4.0 / tb, size, m) * step(0.001, leaving);
    col = mix(col, edgeColor.rgb, rim * 0.8 * (1.0 - leaving));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
