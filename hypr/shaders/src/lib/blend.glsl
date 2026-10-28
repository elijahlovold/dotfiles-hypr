// Screen blend: lightens base wherever fx is bright and leaves it alone
// where fx is black. For effects ported from Ghostty, which instead replace
// every dark pixel (meant for a terminal's black background, but on a
// desktop it punches holes in dark wallpaper and windows).
vec3 screenBlend(vec3 base, vec3 fx) {
    return 1.0 - (1.0 - base) * (1.0 - clamp(fx, 0.0, 1.0));
}
