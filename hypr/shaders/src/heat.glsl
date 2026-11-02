// Heat shimmer over the bottom of the screen (lib/heat.glsl).

#include "lib/heat.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(heat(fragCoord), 1.0);
}
