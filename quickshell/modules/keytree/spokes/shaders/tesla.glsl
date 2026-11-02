// Plasma-globe discharge: each spoke is bent by octaves of piecewise-
// linear noise (the shader version of midpoint displacement), pinned at
// both ends, with an exponential glow around the core. The noise seed
// comes from the spoke and the current strike (time is quantized to the
// strike rate in Tesla.qml), so every spoke re-strikes together. The
// neighbouring spokes are checked too, since an arc can swing toward them.

const float STRIKES = 14.0;
const int OCTAVES = 5;

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// Piecewise-linear value noise in -1..1 - straight segments with sharp
// corners, which is what makes it read as lightning rather than smoke.
float lnoise(float x, float seed) {
    float i = floor(x);
    return mix(hash(i * 1.731 + seed), hash((i + 1.0) * 1.731 + seed), fract(x)) * 2.0 - 1.0;
}

// Sideways displacement as a fraction of spoke length.
float bolt(float u, float seed) {
    float o = 0.0, amp = 0.1;
    for (int k = 0; k < OCTAVES; k++) {
        o += amp * lnoise(u * exp2(float(k) + 1.0), seed + float(k) * 3.7);
        amp *= 0.5;
    }
    return o * clamp(min(u, 1.0 - u) * 6.0, 0.0, 1.0);
}

void main() {
    vec2 p = fragPos();
    float th = atan(p.y, p.x);
    float h = hubRadius();
    float strike = floor(time * STRIKES + 0.5);
    float core = 0.0, glow = 0.0;

    for (int k = 0; k < 2; k++) {
        vec4 ring = ringAt(k);
        if (ring.x < 0.5)
            continue;
        float nearest = nearestNode(ring, th);
        for (float di = -1.0; di <= 1.0; di += 1.0) {
            float i = nearest + di;
            float a = nodeAngle(ring, i);
            vec2 er = vec2(cos(a), sin(a));
            vec2 et = vec2(-er.y, er.x);
            float along = dot(p, er), across = dot(p, et);
            float L = ring.y - h;
            float u = (along - h) / L;
            if (u < 0.0 || u > 1.0)
                continue;
            float id = mod(i, ring.x) + float(k) * 64.0;
            float seed = id * 13.17 + strike * 7.73;
            float e = 0.5 / L;
            float slope = (bolt(u + e, seed) - bolt(u - e, seed)) / (2.0 * e);
            float d = abs(across - bolt(u, seed) * L) / sqrt(1.0 + slope * slope);
            float r = revealCov(u, L);
            core = max(core, lineCov(d, lineWidth * 1.1) * 0.9 * r);
            glow = max(glow, exp(-d / (lineWidth * 2.5)) * 0.22 * r);
        }
    }
    writeCoverage(max(core, glow) * cutMask(p));
}
