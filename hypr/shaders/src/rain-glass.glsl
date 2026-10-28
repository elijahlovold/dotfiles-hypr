// Rain on a misted window over the screen (lib/raindrops.glsl).

#include "lib/raindrops.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(rainOnGlass(fragCoord), 1.0);
}
