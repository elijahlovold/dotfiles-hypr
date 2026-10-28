// Falling rain: thin wind-slanted streaks in parallax layers, near ones
// longer, brighter and faster. Like just-snow's layers, but each layer is
// laid out in a frame tilted by the wind, so streaks fall along their own
// slant.

#include "hash.glsl"

#define RAINFALL_LAYERS 10
#define RAINFALL_WIND 0.2       // slant, radians (positive = falls to the right)
#define RAINFALL_SPEED 2.4      // nearest layer, screen heights per second
#define RAINFALL_DENSITY 0.17   // share of cells holding a streak
#define RAINFALL_DIM 0.9        // overcast: screen brightness under the rain
// Each layer's pattern repeats every RAINFALL_WRAP cells vertically. The
// scroll offset is wrapped at that period too, so it stays small (precise)
// however large `time` gets, with no visible seam.
#define RAINFALL_WRAP 64

vec3 rainfall(vec2 fragCoord, vec3 col) {
    vec2 P = fragCoord / iResolution.y;
    float c = cos(RAINFALL_WIND), s = sin(RAINFALL_WIND);
    vec2 R = mat2(c, -s, s, c) * P;   // streaks run along R.y
    float acc = 0.0;
    for (int i = 0; i < RAINFALL_LAYERS; i++) {
        float fi = float(i);
        float z = 1.0 + fi * 0.45;
        vec2 cell = vec2(0.06, 0.6) / z;             // P units
        float speed = RAINFALL_SPEED / sqrt(z) / cell.y;   // cells per second
        float scroll = mod(iTime * speed, float(RAINFALL_WRAP));
        vec2 q = R / cell + vec2(fi * 0.37, scroll);
        ivec2 id = ivec2(floor(q));
        id.y = id.y - RAINFALL_WRAP * int(floor(float(id.y) / float(RAINFALL_WRAP)));
        vec3 h = hash3(id, i);
        if (h.z > RAINFALL_DENSITY) continue;
        vec2 f = fract(q);
        float len = mix(0.35, 0.6, h.y);
        float y0 = h.x * (1.0 - len);
        float x0 = 0.15 + 0.7 * fract(h.x * 7.31 + h.y * 3.17);
        float v = (f.y - y0) / len;                  // 0 = head (bottom), 1 = tail
        if (v < 0.0 || v > 1.0) continue;
        float dpx = abs(f.x - x0) * cell.x * iResolution.y;
        float width = mix(2.2, 1.1, fi / float(RAINFALL_LAYERS));   // half-width, px
        float a = smoothstep(width, width * 0.25, dpx) * smoothstep(0.0, 0.1, v) * (1.0 - v);
        acc += a * 0.5 / sqrt(z);
    }
    return col * RAINFALL_DIM + vec3(0.72, 0.78, 0.88) * min(acc, 1.0);
}
