// Lightning strikes every 3-5 s over the screen (lib/lightning.glsl).

#include "lib/lightning.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec3 col = texture(iChannel0, fragCoord / iResolution.xy).rgb;
    fragColor = vec4(lightning(fragCoord, col), 1.0);
}
