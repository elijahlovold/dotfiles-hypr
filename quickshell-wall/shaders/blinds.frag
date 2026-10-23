#version 440

// Blinds. The frame is cut into horizontal slats that each turn edge-on
// about their own axis, shading as they turn. They go in a wave outward
// from `origin`, nearest slats first. Run backwards the slats turn the new
// video in. Coordinates are in px; progress runs 0 -> 1.

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
const float SLAT = 0.6;     // of cellSize: slat height
const float STAGGER = 0.5;  // the farthest slat starts this much later

void main() {
    vec2 q = qt_TexCoord0 * resolution;
    float h = cellSize * SLAT;
    float yc = (floor(q.y / h) + 0.5) * h;
    vec2 far = max(origin, resolution - origin);
    float dy = abs(yc - origin.y) / far.y;
    float t = clamp((progress - STAGGER * dy) / (1.0 - STAGGER), 0.0, 1.0);
    t = t * t * (3.0 - 2.0 * t);
    float angle = t * 0.5 * PI;
    float scale = cos(angle);
    // Back to the slat's own height: past its edge (or edge-on) it's gone.
    float ly = (q.y - yc) / max(scale, 1e-4);
    if (scale < 1e-3 || abs(ly) > 0.5 * h) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 col = texture(source, vec2(q.x, yc + ly) / resolution).rgb;
    float turn = sin(angle);
    // Darker as it turns away, the far half more than the near one.
    col *= (1.0 - 0.55 * turn) * (1.0 - 0.3 * turn * ly / (0.5 * h));
    // A glint along the leading edge.
    col += edgeColor.rgb * turn * scale * 1.2 * smoothstep(0.38 * h, 0.5 * h, -ly);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
