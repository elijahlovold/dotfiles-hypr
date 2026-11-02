// Sparks from a fire over the screen (lib/sparks.glsl).

#include "lib/sparks.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec3 col = texture(iChannel0, fragCoord / iResolution.xy).rgb;
    fragColor = vec4(sparks(fragCoord, col), 1.0);
}
