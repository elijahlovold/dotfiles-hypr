// Sparks + heat: the screen shimmers over the heat at the bottom while
// sparks and smoke rise through it. Only the screen behind is distorted;
// the sparks are in the hot air, not behind it.

#include "lib/heat.glsl"
#include "lib/sparks.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(sparks(fragCoord, heat(fragCoord)), 1.0);
}
