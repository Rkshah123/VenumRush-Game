shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

// SERPENTIS 3D — foliage wind. INSTANCE_CUSTOM.x carries a per-instance sway
// phase, .y a sway strength, .z a color/shape jitter; grass blades and tree
// leaves both use this so whole fields breathe together yet stay individual.
// Geometry convention: pivot at local origin, +Y is up; vertex COLOR holds
// the base color per blade/leaf.

uniform float u_wind_strength = 0.30;
uniform vec2 u_wind_dir = vec2(0.84, 0.54);
uniform vec3 u_tint = vec3(1.0, 1.0, 1.0);

varying vec3 v_col;
varying float v_height01;
varying float v_jit;

vec2 jittered_wind_dir(float j) {
	return normalize(u_wind_dir + vec2(j * 0.24 - 0.12, -j * 0.18 + 0.09));
}

void vertex() {
	// primitive-built meshes (leaf blobs, trunks) carry no COLOR attribute and
	// default to zero — treat zero as "use the tint color at full strength".
	vec3 base = COLOR.rgb;
	if (dot(base, base) < 0.0005) {
		base = vec3(1.0);
	}
	v_col = base * u_tint;
	v_jit = INSTANCE_CUSTOM.z;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = INSTANCE_CUSTOM.x;
	float sway = INSTANCE_CUSTOM.y;
	float j = INSTANCE_CUSTOM.z;

	float w1 = sin(dot(wpos.xz, u_wind_dir) * 0.09 + TIME * 1.35 + ph);
	float w2 = sin((wpos.x - wpos.z) * 0.05 - TIME * 0.9 + ph * 2.1 + wpos.y * 0.05);
	float h01 = clamp(VERTEX.y / 1.6, 0.0, 1.0);
	float bend = (w1 * 0.7 + w2 * 0.3) * u_wind_strength * sway;

	h01 = pow(h01, 1.35);
	vec2 wd = jittered_wind_dir(j);
	VERTEX.xz += wd * bend * h01 * h01;
	VERTEX.y -= bend * bend * 0.22 * h01 * h01 * h01;
	v_height01 = h01;
}

void fragment() {
	vec3 col = v_col * (0.82 + v_jit * 0.30);
	// saturation bias keeps foliage lush under bright light
	col *= vec3(0.92, 1.06, 0.80);
	float tip = smoothstep(0.35, 1.0, v_height01);
	float root = 1.0 - smoothstep(0.0, 0.42, v_height01);
	col += vec3(0.12, 0.11, 0.02) * tip * 0.22;
	col *= 1.0 - root * 0.30;

	ALBEDO = clamp(col, vec3(0.02), vec3(0.95));
	ROUGHNESS = 0.66;
	SPECULAR = 0.22;
	EMISSION = clamp(vec3(0.20, 0.34, 0.10) * tip * 0.10, vec3(0.0), vec3(0.08));
}
