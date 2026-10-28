// "Just snow" - Copyright (c) 2013 Andrew Baldwin (twitter: baldand, www: http://thndl.com)
// License = Attribution-NonCommercial-ShareAlike (http://creativecommons.org/licenses/by-nc-sa/3.0/deed.en_US)
//
// Simple (but not cheap) snow made from multiple parallax layers with randomly positioned
// flakes and directions. Also includes a DoF effect.
//
// Changed from the original: flakes are placed with an integer hash
// (lowbias32, see hash2) instead of fract((31415.9 + m) / fract(p * m)), m = cell * 1e-5. That one
// is smooth in the cell coordinates, so a row's flakes sat at nearly the
// same height and lined up into horizontal bands with gaps between. And
// for speed: pixels clear of a layer's flake skip its shape (same image),
// and the far layers are merged (see SNOW_MERGE).

#include "hash.glsl"

#define LIGHT_SNOW // Comment this out for a blizzard

#ifdef LIGHT_SNOW
	#define SNOW_LAYERS 50
	#define SNOW_DEPTH .5
	#define SNOW_WIDTH .3
	#define SNOW_SPEED .6
#else // BLIZZARD
	#define SNOW_LAYERS 200
	#define SNOW_DEPTH .1
	#define SNOW_WIDTH .8
	#define SNOW_SPEED 1.5
#endif

// Each pixel checks one flake per layer, so the cost goes with the number
// of layers, not flakes. Past the nearest SNOW_NEAR, layers are nearly the
// same depth, so they're drawn SNOW_MERGE at a time: one pass at the
// group's middle depth on a grid sqrt(SNOW_MERGE) times finer (so the same
// number of flakes), with the flake shape measured in a single layer's
// cell units (so the same flake size on screen). (SNOW_LAYERS - SNOW_NEAR)
// must divide by SNOW_MERGE.
#define SNOW_NEAR 10
#define SNOW_MERGE 5

// Brightness of the flakes over this pixel.
float snow(vec2 fragCoord)
{
	vec2 uv = fragCoord.xy / iResolution.xy;

	float acc = 0.0;
	float dof = 5.0 * sin(iTime * 0.1);
	for (int i = 0; i < SNOW_NEAR + (SNOW_LAYERS - SNOW_NEAR) / SNOW_MERGE; i++) {
		bool merged = i >= SNOW_NEAR;
		float m = merged ? float(SNOW_MERGE) : 1.0;
		float fi = merged ? float(SNOW_NEAR + (i - SNOW_NEAR) * SNOW_MERGE) + 0.5 * (m - 1.0) : float(i);
		vec2 q =-uv*(1.0 + fi * SNOW_DEPTH);
		q += vec2(q.y * (SNOW_WIDTH * mod(fi * 7.238917, 1.0) - SNOW_WIDTH * 0.5), -SNOW_SPEED * iTime / (1.0 + fi * SNOW_DEPTH * 0.03));
		float k = sqrt(m);
		vec2 r = hash2(ivec2(floor(q * k)), i);
		vec2 s = abs(fract(q * k) - 0.5 + 0.9 * r.xy - 0.45) / k;
		// d below is at least max(s) - 0.01 and the flake shows only where
		// d < edge, so pixels further from it skip the shape (same image).
		float edge = 0.005 + 0.05 * min(0.5 * abs(fi - 5.0 - dof), 1.0);
		if (max(s.x, s.y) - 0.01 >= edge)
			continue;
		s += 0.01 * abs(2.0 * fract(10.0 * q.yx) - 1.0);
		float d = 0.6 * max(s.x - s.y, s.x + s.y) + max(s.x, s.y) - 0.01;
		acc += smoothstep(edge, -edge, d) * (r.x / (1.0 + 0.02 * fi * SNOW_DEPTH));
	}
	return acc;
}
