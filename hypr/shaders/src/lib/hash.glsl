// Integer hashes. Hash integer cell/slot ids with these, never a float
// formula on the coordinates: those are smooth in the input, so
// neighbouring cells get related values and patterns line up (the old
// just-snow hash put whole rows of flakes at the same height).

// PCG3D (Jarzynski & Olano 2020, "Hash Functions for GPU Rendering").
uvec3 pcg3d(uvec3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return v;
}

// Three independent values in [0, 1]. Mixed with the monitor id
// (wl_output, from hypr-shader-port's header), so each monitor gets its own
// random drops, strikes and flakes instead of a copy of the same pattern.
vec3 hash3(ivec3 p) {
    uvec3 v = uvec3(p);
    v.z += uint(wl_output) * 0x9E3779B9u;
    return vec3(pcg3d(v)) * (1.0 / 4294967295.0);
}
vec3 hash3(ivec2 p, int seed) { return hash3(ivec3(p, seed)); }
vec3 hash3(int a, int seed) { return hash3(ivec3(a, seed, 0x5eed)); }

// Cheaper: two values in [0, 1] at 16-bit precision, from one lowbias32
// hash (Chris Wellons) of the cell, seed and monitor folded together.
// About a quarter of hash3's work, for loops that hash dozens of times
// per pixel and only need two numbers.
vec2 hash2(ivec2 p, int seed) {
    uint x = uint(p.x) * 0x8da6b343u ^ uint(p.y) * 0xd8163841u
           ^ uint(seed) * 0xcb1ab31fu ^ uint(wl_output) * 0x9E3779B9u;
    x ^= x >> 16u; x *= 0x7feb352du;
    x ^= x >> 15u; x *= 0x846ca68bu;
    x ^= x >> 16u;
    return vec2(uvec2(x & 0xffffu, x >> 16u)) * (1.0 / 65535.0);
}

// Smooth 2D value noise in [0, 1].
float vnoise(vec2 p, int seed) {
    vec2 i = floor(p), f = fract(p);
    ivec2 c = ivec2(i);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash3(c, seed).x;
    float b = hash3(c + ivec2(1, 0), seed).x;
    float d = hash3(c + ivec2(0, 1), seed).x;
    float e = hash3(c + ivec2(1, 1), seed).x;
    return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

float fbm(vec2 p, int seed, int octaves) {
    float v = 0.0, amp = 0.5;
    for (int o = 0; o < octaves; o++) {
        v += amp * vnoise(p, seed + o);
        p = p * 2.03 + vec2(17.1, 9.3);
        amp *= 0.5;
    }
    return v;
}
