#version 440

// Glass shatter. The frame breaks into Voronoi cells from `origin`, and
// each falls away as a shard - drifting off the impact, tumbling and
// shrinking, rim lit - with the live video behind it. Shards are drawn by inverse mapping: for each
// nearby cell, undo that shard's motion and check the pixel lands back
// inside it. Coordinates are in px; progress runs 0 -> 1.

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

// A shard's rim is lit in edgeColor only while it's in flight, fading over
// the first RIM_FADE of its fall. Run backwards: the rim trails each shard
// in and is gone the moment it lands - no lines on settled glass.
const float RIM_FADE = 0.3;
// Impact flash: rises over [0, FLASH_PEAK], gone by FLASH_END - zero at
// both ends, so neither the first nor the last frame pops.
const float FLASH_PEAK = 0.10;
const float FLASH_END = 0.40;
const float FALL_START = 0.10;  // first shard (at the impact) lets go
const float FALL_SPREAD = 0.48; // farthest shard lets go this much later
const float FALL_TIME = 0.36;   // one shard's fall; all gone by 1.0

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453 + seed);
}

// Jittered site of cell c, px.
vec2 site(vec2 c) {
    return (c + 0.1 + 0.8 * hash2(c)) * cellSize;
}

// xy: cell owning p; z: distance from p to that cell's edge, px.
vec3 voronoi(vec2 p) {
    vec2 base = floor(p / cellSize);
    float d1 = 1e9;
    float d2 = 1e9;
    vec2 best = base;
    vec2 bestSite = vec2(0.0);
    vec2 secondSite = vec2(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 c = base + vec2(x, y);
            vec2 s = site(c);
            float d = distance(p, s);
            if (d < d1) {
                d2 = d1;
                secondSite = bestSite;
                d1 = d;
                best = c;
                bestSite = s;
            } else if (d < d2) {
                d2 = d;
                secondSite = s;
            }
        }
    }
    // Distance to the bisector between the two nearest sites.
    float edge = (d2 * d2 - d1 * d1) / (2.0 * max(distance(bestSite, secondSite), 1e-3));
    return vec3(best, edge);
}

mat2 rot(float a) {
    float c = cos(a);
    float s = sin(a);
    return mat2(c, s, -s, c);
}

void main() {
    vec2 q = qt_TexCoord0 * resolution;
    vec2 far = max(origin, resolution - origin);
    float maxDist = length(far);

    // Own cell first: until it falls (most pixels, most of the time) that's
    // the only lookup needed.
    vec2 home = voronoi(q).xy;

    for (int i = 0; i < 10; i++) {
        vec2 c = home + (i == 0 ? vec2(0.0) : vec2(float((i - 1) % 3) - 1.0, float((i - 1) / 3) - 1.0));
        if (i == 5)
            continue; // (0,0) again - already tried first
        vec2 s = site(c);
        vec2 r = hash2(c + 17.31);
        float d = distance(s, origin) / maxDist;
        float t = clamp((progress - FALL_START - FALL_SPREAD * d - 0.05 * r.x) / FALL_TIME, 0.0, 1.0);
        float scale = 1.0 - t;
        if (scale < 0.01)
            continue;

        vec2 away = normalize(s - origin + vec2(1e-3));
        vec2 drift = (away * (0.45 + 0.4 * r.y) + vec2(0.0, 0.55)) * cellSize * t * t;
        float angle = (r.x - 0.5) * 3.0 * t;
        vec2 p = s + rot(-angle) * (q - s - drift) / scale;

        vec3 v = voronoi(p);
        if (v.xy != c)
            continue;

        vec3 col = texture(source, p / resolution).rgb;
        float lit = smoothstep(0.0, RIM_FADE, t);
        float line = (1.0 - smoothstep(0.6, 1.8, v.z * scale)) * lit;
        col *= 1.0 - 0.35 * t;
        col = mix(col, edgeColor.rgb, line * (0.85 - 0.4 * t));
        // Impact flash.
        float flash = exp(-distance(q, origin) / (cellSize * 0.6)) * smoothstep(0.0, FLASH_PEAK, progress) * (1.0 - smoothstep(FLASH_PEAK, FLASH_END, progress));
        col += edgeColor.rgb * flash * 0.6;

        float alpha = 1.0 - smoothstep(0.75, 1.0, t);
        fragColor = vec4(col * alpha, alpha) * qt_Opacity;
        return;
    }
    fragColor = vec4(0.0);
}
