#version 440

// The portrait monitor's wallpaper: portrait-base.png recoloured with the
// palette. Each pixel keeps its own Oklab lightness and takes hue/chroma
// from the palette: each of the source's colour families (ANCHOR_*) stands
// in for a palette role, pixels blend between anchors by distance, and
// chroma scales with the pixel's own relative to its anchor so faint
// things stay faint. Roles come in as accent (color13), second (most
// chromatic colour of clearly different hue) and light (lightest of the
// chromatic ones) for the field and waves, and logoA/logoB - the two
// palette colours furthest apart in colour - for the logo, whose coral ->
// yellow gradient spans them. PortraitWindow picks them. field, when its
// alpha is 1, is the colour along the main wallpaper's edge beside this
// screen: the field takes its hue (at the chroma it would have had anyway)
// so the two screens meet in one colour.
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
    vec4 logoA;
    vec4 logoB;
    vec4 field;
};
layout(binding = 1) uniform sampler2D source;

const int N = 6;
// Anchor match falloff in Oklab, and lightness's weight in the distance
// (low: the waves differ from the field mostly in hue, not lightness).
const float SIGMA = 0.06;
const float L_WEIGHT = 0.6;
// Ceiling on chroma relative to the anchor.
const float MAX_RATIO = 1.5;
// The field's lightness relative to the source's.
const float FIELD_L = 0.9;

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

// Halfway between two colours in Oklch, the short way round the hue
// circle; a near-grey end takes the other's hue so it doesn't sweep.
vec3 mixLch(vec3 x, vec3 y) {
    float cx = length(x.yz), cy = length(y.yz);
    float hx = atan(x.z, x.y), hy = atan(y.z, y.y);
    if (cx < 0.02) hx = hy;
    if (cy < 0.02) hy = hx;
    float dh = mod(hy - hx + 3.14159265, 6.2831853) - 3.14159265;
    float h = hx + dh * 0.5, c = (cx + cy) * 0.5;
    return vec3((x.x + y.x) * 0.5, c * cos(h), c * sin(h));
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
    vec3 la = oklab(logoA.rgb);
    vec3 lb = oklab(logoB.rgb);
    // The field, toned down; with an edge colour, its hue at the same
    // chroma, fading to grey when the edge itself is grey.
    vec2 fieldAB = 0.6 * (a.yz + s.yz) / 2.0;
    if (field.a > 0.5) {
        vec2 f = oklab(field.rgb).yz;
        float fc = length(f);
        fieldAB = length(fieldAB) * smoothstep(0.005, 0.02, fc) * f / max(fc, 1e-6);
    }
    // What each anchor becomes; only its a/b (hue, chroma) is used.
    vec2 targets[N] = vec2[N](
        fieldAB,
        s.yz,
        a.yz,
        la.yz,
        mixLch(la, lb).yz,
        lb.yz);

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
    float L = 0.0;
    float total = 0.0;
    for (int i = 0; i < N; i++) {
        float w = exp(-(d[i] - dMin) / (2.0 * SIGMA * SIGMA));
        // The logo takes its ends' chroma outright: a faint end would
        // otherwise fade the gradient into the field.
        float ratio = i < 3 ? clamp(chroma / length(anchors[i].yz), 0.0, MAX_RATIO) : 1.0;
        ab += w * ratio * targets[i];
        L += w * (i == 0 ? FIELD_L * src.x : src.x);
        total += w;
    }

    fragColor = vec4(fromOklab(vec3(L / total, ab / total)), 1.0) * qt_Opacity;
}
