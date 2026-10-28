// Storm: rain on the glass plus lightning outside it.

#include "lib/raindrops.glsl"
#include "lib/lightning.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(lightning(fragCoord, rainOnGlass(fragCoord)), 1.0);
}
