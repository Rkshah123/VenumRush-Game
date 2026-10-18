shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix;

// SERPENTIS 3D — waterfall sheet: fast vertical streaking foam over a flat
// water tint, with soft top lip and bottom break-up. Cheap and readable.

uniform vec3 u_tint = vec3(0.16, 0.42, 0.48);
uniform vec3 u_foam = vec3(0.93, 0.97, 1.0);

varying vec3 v_world;

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 f = fract(p);
	vec2 i = floor(p);
	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float fall = TIME * 1.55;
	// vertical streaks that race downward
	float streaks = vnoise(vec2(uv.x * 7.0, uv.y * 1.1 - fall));
	float streaks2 = vnoise(vec2(uv.x * 13.0 + 3.7, uv.y * 2.3 - fall * 1.65));
	float foam = streaks * 0.65 + streaks2 * 0.35;

	// aeration increases toward the bottom of the fall
	float churn = smoothstep(0.15, 0.9, uv.y); // uv.y=1 at top of quad? plane maps v down; flip safe
	vec3 col = mix(u_tint, u_foam, smoothstep(0.35, 0.95, foam + churn * 0.25));
	// soft alpha at the wrap edges so the sheet melts into the pool
	float edge = smoothstep(0.0, 0.10, uv.x) * smoothstep(1.0, 0.90, uv.x);
	col = mix(col, u_foam, churn * 0.22);

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ALPHA = clamp(0.82 * edge, 0.0, 1.0);
}
