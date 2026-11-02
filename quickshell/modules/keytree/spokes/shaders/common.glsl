#version 440
// Shared prelude for spoke shaders; build.sh prepends it to each
// <name>.glsl. Uniforms match ShaderSpokes.qml's ShaderEffect properties.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // item size, px
    vec2 origin;        // hub center within the item, px
    vec4 color;
    float time;         // seconds, quantized to the style's fps
    float reveal;       // 0..1 entrance progress
    float lineWidth;
    vec4 ring0;         // node count, radius, angle of first node, -
    vec4 ring1;         // count 0 = no second ring
    vec4 radii;         // hub radius, node radius, cut gap, -
};

const float PI = 3.14159265;
const float TAU = 6.28318531;

// Fragment position relative to the hub, px (y down).
vec2 fragPos() {
    return qt_TexCoord0 * size - origin;
}

vec4 ringAt(int k) {
    return k == 0 ? ring0 : ring1;
}

// Angle of node i on a ring, counting from its first node.
float nodeAngle(vec4 ring, float i) {
    return ring.z + i * TAU / ring.x;
}

// Index of the node on a ring closest in angle to th.
float nearestNode(vec4 ring, float th) {
    return floor((th - ring.z) / (TAU / ring.x) + 0.5);
}

float hubRadius() {
    return radii.x;
}

float nodeRadius() {
    return radii.y;
}

// 0 inside the hub and every node (grown by the cut gap), 1 elsewhere.
float cutMask(vec2 p) {
    float g = radii.z;
    float m = smoothstep(g - 0.5, g + 0.5, length(p) - radii.x);
    float th = atan(p.y, p.x);
    for (int k = 0; k < 2; k++) {
        vec4 ring = ringAt(k);
        if (ring.x < 0.5)
            continue;
        float a = nodeAngle(ring, nearestNode(ring, th));
        vec2 c = ring.y * vec2(cos(a), sin(a));
        m *= smoothstep(g - 0.5, g + 0.5, length(p - c) - radii.y);
    }
    return m;
}

// Coverage of a line of width w at distance dist, 1px antialiased.
float lineCov(float dist, float w) {
    return clamp(0.5 * w + 0.5 - dist, 0.0, 1.0);
}

// Coverage of the revealed part of a spoke: everything up to `reveal` of
// the way out, antialiased over a pixel of spoke length L.
float revealCov(float u, float L) {
    return clamp((reveal - u) * L + 0.5, 0.0, 1.0);
}

void writeCoverage(float cov) {
    fragColor = vec4(color.rgb, 1.0) * color.a * cov * qt_Opacity;
}
