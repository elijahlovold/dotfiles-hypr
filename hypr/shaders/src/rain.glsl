// Falling rain streaks over the screen (lib/rainfall.glsl).

#include "lib/rainfall.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec3 col = texture(iChannel0, fragCoord / iResolution.xy).rgb;
    fragColor = vec4(rainfall(fragCoord, col), 1.0);
}
