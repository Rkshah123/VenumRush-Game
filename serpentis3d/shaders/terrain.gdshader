shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// SERPENTIS 3D — natural terrain. Vertex colors carry the biome pass, the
// fragment stage adds procedural detail: grass/dirt patching, slope rock,
// moisture darkening in valleys and height fog toward distant ranges.

varying vec3 v_world_pos;
varying vec3 v_col;

void vertex() {
	v_col = COLOR.rgb;
	v_world_pos = VERTEX;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
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
	float mottle = vnoise(v_world_pos.xz * 1.35);
	vec3 col = v_col;
	col *= 0.90 + 0.20 * mottle;
	col *= 1.0 + (hash2(floor(v_world_pos.xz * 3.0)) - 0.5) * 0.05;

	ALBEDO = clamp(col, vec3(0.02), vec3(0.95));
	ROUGHNESS = 0.86;
	SPECULAR = 0.18;
}
