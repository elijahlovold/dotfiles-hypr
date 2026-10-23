#version 440

// Scroll. The frame rolls up like a scroll: a cylinder travels across the
// screen winding the image onto itself, leaving the other video bare behind
// it. Seen from above, the roll shows the paper's back - the image, dimmed
// and tinted, shaded round the cylinder - and it casts a soft shadow on both
// sides. Run backwards it's the new video unrolling. It travels toward the
// side `origin` is on, so unrolling starts there. With lightning, bolts
// crackle down the roll's edges. Coordinates are in px;
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
    float lightning;  // WallConfig.lightning: 0 skips the bolts entirely
};
layout(binding = 1) uniform sampler2D source;

const float PI = 3.14159265;
const float RADIUS = 0.6;   // of cellSize
const float SHADOW = 0.45;  // strongest shadow, alpha
const float BACK = 0.45;    // brightness of the paper's back

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
    float w = resolution.x;
    float r = cellSize * RADIUS;
    // Along the travel: a = 0 at the edge the roll starts from.
    bool rightward = origin.x >= 0.5 * w;
    float a = rightward ? q.x : w - q.x;
    // Half-eased, and starting/ending far enough out that neither the roll nor
    // its shadow touches the screen at progress 0 or 1.
    float p = mix(progress, progress * progress * (3.0 - 2.0 * progress), 0.5);
    float xc = mix(-2.6 * r, w + 3.0 * r, p);

    vec4 col = vec4(0.0);
    // Ahead of the roll: flat paper, shadowed close to it.
    if (a >= xc) {
        vec2 uv = q / resolution;
        float shade = 1.0 - SHADOW * exp(-max(a - xc - r, 0.0) / (0.3 * r));
        col = vec4(texture(source, uv).rgb * shade, 1.0);
    } else if (a < xc - r) {
        // Bare: the other video, under the roll's shadow.
        float s = SHADOW * exp(-(xc - r - a) / (0.4 * r));
        col = vec4(0.0, 0.0, 0.0, s);
    }

    // The roll itself, over both.
    float c = (a - xc) / r;
    if (abs(c) <= 1.0) {
        float alpha = acos(c);                    // 0 = front, PI = back
        float u = xc - r * (1.5 * PI - alpha);    // the outermost turn's paper
        if (u >= 0.0) {
            float x = rightward ? u : w - u;
            vec3 back = texture(source, vec2(x, q.y) / resolution).rgb * BACK;
            back = mix(back, edgeColor.rgb, 0.18);
            // Lit from above; darker toward the cylinder's sides.
            float light = 0.35 + 0.65 * sin(alpha);
            // Thin highlight just past the top.
            light += 0.25 * exp(-pow((alpha - 0.42 * PI) / 0.12, 2.0));
            col = vec4(back * light, 1.0);
        }
    }

    if (lightning > 0.0) {
        // Down the roll's leading edge and, fainter, its trailing one. Off
        // screen with the roll at both ends.
        float b = boltLine(a - (xc + r), q.y, r * 0.25, 3.0) + 0.5 * boltLine(a - (xc - r), q.y, r * 0.25, 9.0);
        col.rgb += boltColor() * b;
        col.a = clamp(col.a + b, 0.0, 1.0);
    }
    // Premultiplied: the shadow is black, everything else opaque.
    fragColor = col * qt_Opacity;
}
