// Snow over the screen (lib/snow.glsl).

#include "lib/snow.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec3 col = texture(iChannel0, fragCoord / iResolution.xy).rgb;
    fragColor = vec4(col + snow(fragCoord), 1.0);
}
