shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// SERPENTIS 3D — natural terrain. Vertex colors carry the biome pass, the
// fragment stage adds procedural detail: grass/dirt patching, slope rock,
// moisture darkening in valleys and height fog toward distant ranges.

varying vec3 v_world_pos;
varying vec3 v_col;

uniform float u_court_r = 56.0;   // playable circle radius — diagonal turf bands live inside it
uniform float u_tier = 2.0;       // perf tier: <0.5 = phone fragment budget (2 noise octaves only)

void vertex() {
	v_col = COLOR.rgb;
	v_world_pos = VERTEX;
}

float hash2(vec2 p) {
	// precision-safe cell hash: the classic fract(sin(...)*43758) form degrades
	// to visible square blocks once the sin argument grows past a few thousand
	// radians (mediump fragment precision), which happens fast at world scale.
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 f = fract(p);
	vec2 i = floor(p);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise(p);
		p *= 2.02;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// vertex colors carry the whole biome pass; fragment adds cheap detail only
	// Multi-octave detail so the court still reads as ground when the 2D
	// camera sits close to the snake (spec §6). All detail terms are SMOOTH
	// value noise — raw cell-hash blocks shimmer into ugly pixel squares at
	// close zoom, so no floor() lattices down here.
	//
	// Tier budget: mottle+fine always run; micro + patch (fbm = ~16 extra
	// hash evals per pixel — the dominant fill cost on phones) are desktop
	// tier only. Uniform-bound branch: no divergence in practice.
	float mottle = vnoise(v_world_pos.xz * 1.35);
	float fine = vnoise(v_world_pos.xz * 4.4);
	vec3 col = v_col;
	float det = 0.22 * mottle + 0.08 * fine;
	float patch_mult = 1.0;
	if (u_tier > 0.5) {
		float micro = vnoise(v_world_pos.xz * 9.1);
		float patch = fbm(v_world_pos.xz * 0.11);
		det += 0.04 * micro;
		patch_mult = 0.94 + 0.12 * patch;
	}
	col *= 0.88 + det;
	col *= patch_mult;
	// gentle hue drift on top of the brightness patching: keeps large court
	// regions from reading as one flat painted slab on any tier
	col.g += (mottle - 0.5) * 0.035;
	col.b += (patch_mult - 1.0) * 0.10;

	// Stadium-style diagonal mow bands inside the playable circle. A slow sine
	// warp curves the stripes so they read as gently irregular hay lines
	// instead of ruler-straight bands, and the tint is kept quiet so the top-
	// down camera sees organic turf, not a painted pitch.
	float d_court = length(v_world_pos.xz);
	float warp = sin(v_world_pos.x * 0.13) * cos(v_world_pos.z * 0.11);
	float band = 0.5 + 0.5 * cos((v_world_pos.x + v_world_pos.z + 2.4 * warp) * 0.42);
	float band_w = smoothstep(0.18, 0.35, band) * (1.0 - smoothstep(0.65, 0.82, band));
	float court_f = (1.0 - smoothstep(u_court_r * 0.94, u_court_r + 2.0, d_court))
		* smoothstep(2.0, 6.0, d_court);
	col *= 1.0 + (band_w - 0.5) * 0.135 * court_f;
	col += band_w * court_f * 0.024;
	col = clamp(col, vec3(0.02), vec3(0.95));

	ALBEDO = col;
	ROUGHNESS = 0.86;
	SPECULAR = 0.18;
}
