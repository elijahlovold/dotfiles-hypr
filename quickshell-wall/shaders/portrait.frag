#version 440

// The portrait monitor's wallpaper: portrait-base.png recoloured with the
// palette. Each pixel keeps its own Oklab lightness and takes hue/chroma
// from the palette: each of the source's colour families (ANCHOR_*) stands
// in for a palette role, pixels blend between anchors by distance, and
// chroma scales with the pixel's own relative to its anchor so faint
// things stay faint. Roles come in as accent (color13), second (most
// chromatic colour of clearly different hue) and light (lightest of the
// chromatic ones) - PortraitWindow picks them.
//
// The source carries its picture in hue more than lightness (the logo's
// yellow -> coral gradient, pink/violet waves at the field's lightness),
// which is why a grey ramp flattened it.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 accent;
    vec4 second;
    vec4 light;
};
layout(binding = 1) uniform sampler2D source;

const int N = 6;
// Anchor match falloff in Oklab, and lightness's weight in the distance
// (low: the waves differ from the field mostly in hue, not lightness).
const float SIGMA = 0.06;
const float L_WEIGHT = 0.6;
// Ceiling on chroma relative to the anchor.
const float MAX_RATIO = 1.5;

vec3 toLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 toSrgb(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

vec3 oklab(vec3 srgb) {
    vec3 c = toLinear(srgb);
    vec3 lms = vec3(
        0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
        0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
        0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
    lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    return vec3(
        0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
        1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
        0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}

vec3 fromOklab(vec3 lab) {
    vec3 lms = vec3(
        lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z,
        lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z,
        lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z);
    lms = lms * lms * lms;
    return toSrgb(vec3(
        4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
        -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
        -0.0041960863 * lms.x - 0.7034133289 * lms.y + 1.7076127010 * lms.z));
}

void main() {
    vec3 src = oklab(texture(source, qt_TexCoord0).rgb);

    // Source colour families (Oklab of the hex in each comment).
    vec3 anchors[N] = vec3[N](
        oklab(vec3(0x1E, 0x0A, 0x23) / 255.0),  // dark purple field
        oklab(vec3(0x2A, 0x14, 0x50) / 255.0),  // violet waves
        oklab(vec3(0x5A, 0x22, 0x38) / 255.0),  // rose waves, haze
        oklab(vec3(0xF9, 0x6A, 0x5E) / 255.0),  // logo: coral
        oklab(vec3(0xFC, 0x9A, 0x56) / 255.0),  // logo: orange
        oklab(vec3(0xFC, 0xCE, 0x4B) / 255.0)); // logo: yellow
    vec3 a = oklab(accent.rgb);
    vec3 s = oklab(second.rgb);
    vec3 l = oklab(light.rgb);
    // What each anchor becomes; only its a/b (hue, chroma) is used.
    vec2 targets[N] = vec2[N](
        0.6 * (a.yz + s.yz) / 2.0,  // the field, toned down
        s.yz,
        a.yz,
        a.yz,
        (a.yz + l.yz) / 2.0,
        l.yz);

    float d[N];
    float dMin = 1e9;
    for (int i = 0; i < N; i++) {
        vec3 diff = (src - anchors[i]) * vec3(L_WEIGHT, 1.0, 1.0);
        d[i] = dot(diff, diff);
        dMin = min(dMin, d[i]);
    }
    // Weights relative to the nearest anchor, so far-off pixels can't
    // underflow every weight to zero.
    float chroma = length(src.yz);
    vec2 ab = vec2(0.0);
    float total = 0.0;
    for (int i = 0; i < N; i++) {
        float w = exp(-(d[i] - dMin) / (2.0 * SIGMA * SIGMA));
        float ratio = clamp(chroma / length(anchors[i].yz), 0.0, MAX_RATIO);
        ab += w * ratio * targets[i];
        total += w;
    }

    fragColor = vec4(fromOklab(vec3(src.x, ab / total)), 1.0) * qt_Opacity;
}
