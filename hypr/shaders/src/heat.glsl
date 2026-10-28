// Heat shimmer: the screen wavers as if seen over hot asphalt, strongest at
// the bottom and fading out towards the top.

#include "lib/hash.glsl"

#define HEAT_STRENGTH 4.0   // max displacement at the bottom, pixels
#define HEAT_HEIGHT 0.65    // fades out by this fraction of the screen height
#define HEAT_RISE 0.35      // how fast the waves rise, screen heights per second

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 P = fragCoord / iResolution.y;
    float amount = smoothstep(HEAT_HEIGHT, 0.0, uv.y);
    if (amount <= 0.0) {
        fragColor = vec4(texture(iChannel0, uv).rgb, 1.0);
        return;
    }
    // Rising, slowly churning turbulence: wide in x, tight in y like real
    // heat haze. The second sample drifts the other way so it never just
    // scrolls.
    float t = iTime * HEAT_RISE;
    vec2 q = vec2(P.x * 7.0, (P.y - t) * 22.0);
    float nx = fbm(q + vec2(0.0, iTime * 0.3), 41, 3) - 0.5;
    float ny = fbm(q * 0.8 + vec2(5.2, -iTime * 0.25), 43, 3) - 0.5;
    vec2 off = vec2(nx, ny * 0.6) * 2.0 * HEAT_STRENGTH * amount / iResolution.xy;
    fragColor = vec4(texture(iChannel0, uv + off).rgb, 1.0);
}
