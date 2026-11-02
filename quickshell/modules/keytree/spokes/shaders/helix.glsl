// DNA ladder: two strands twist around each spoke's axis half a turn
// apart, with rungs between them. Amplitude is enveloped by sin(πu) so
// they pinch shut at hub and node; `time` turns the twist. Per pixel:
// nearest spoke on each ring, then distance to each strand (corrected for
// its slope) and to the nearest rung.

const float TWISTS = 2.2;   // strand turns per spoke
const float SPIN = 2.4;     // rad/s
const float RUNGS = 12.0;

float strandOffset(float u, float k, float amp) {
    return amp * sin(PI * u) * sin(TAU * TWISTS * u + time * SPIN + k * PI);
}

float strandCov(float u, float k, float amp, float L, float across, float w) {
    float ph = TAU * TWISTS * u + time * SPIN + k * PI;
    float o = amp * sin(PI * u) * sin(ph);
    float slope = amp * (PI * cos(PI * u) * sin(ph) + sin(PI * u) * TAU * TWISTS * cos(ph)) / L;
    return lineCov(abs(across - o) / sqrt(1.0 + slope * slope), w);
}

void main() {
    vec2 p = fragPos();
    float th = atan(p.y, p.x);
    float h = hubRadius();
    float nr = nodeRadius();
    float cov = 0.0;

    for (int k = 0; k < 2; k++) {
        vec4 ring = ringAt(k);
        if (ring.x < 0.5)
            continue;
        float a = nodeAngle(ring, nearestNode(ring, th));
        vec2 er = vec2(cos(a), sin(a));
        vec2 et = vec2(-er.y, er.x);
        float along = dot(p, er), across = dot(p, et);
        float L = ring.y - h;
        float u = (along - h) / L;
        if (u < 0.0 || u > 1.0)
            continue;
        float amp = min(nr * 0.42, ring.y * TAU / ring.x * 0.17);

        float c = max(strandCov(u, 0.0, amp, L, across, lineWidth * 1.1) * 0.85,
                      strandCov(u, 1.0, amp, L, across, lineWidth * 0.8) * 0.45);
        c *= revealCov(u, L);

        float j = floor(u * RUNGS + 0.5);
        if (j >= 1.0 && j < RUNGS) {
            float uj = j / RUNGS;
            float o0 = strandOffset(uj, 0.0, amp), o1 = strandOffset(uj, 1.0, amp);
            float dAcross = max(max(min(o0, o1) - across, across - max(o0, o1)), 0.0);
            float d = length(vec2(along - (h + uj * L), dAcross));
            c = max(c, lineCov(d, lineWidth * 0.6) * 0.28 * step(uj, reveal));
        }
        cov = max(cov, c);
    }
    writeCoverage(cov * cutMask(p));
}
