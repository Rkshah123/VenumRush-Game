shader_type sky;

// SERPENTIS 3D — procedural sky: zenith-to-horizon gradient, sun disc with
// warm corona, soft drifting cloud bands and atmospheric bottom haze.

uniform vec3 u_top = vec3(0.16, 0.38, 0.66);
uniform vec3 u_horizon = vec3(0.62, 0.78, 0.90);
uniform vec3 u_sun_color = vec3(1.0, 0.95, 0.85);
uniform vec3 u_sun_dir = vec3(0.3, 0.7, 0.5);
uniform float u_cloud = 1.0;

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
	float amp = 0.6;
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.52;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = clamp(dir.y, -0.05, 1.0);
	vec3 col = mix(u_horizon, u_top, pow(clamp(h * 1.22, 0.0, 1.0), 0.72));

	// sun disc + corona
	vec3 sd = normalize(u_sun_dir);
	float cosang = clamp(dot(dir, sd), 0.0, 1.0);
	float disc = smoothstep(0.99965, 0.99992, cosang);
	float corona = pow(cosang, 240.0) * 0.55 + pow(cosang, 18.0) * 0.16;
	col += u_sun_color * (disc * 2.4 + corona);

	// drifting clouds projected on a virtual dome
	vec2 cuv = dir.xz / max(dir.y + 0.28, 0.04);
	cuv *= 0.36 + 0.05 * cos(TIME * 0.05);
	float t = TIME * 0.008;
	float c1 = fbm(cuv * 3.0 + vec2(t * 18.0, t * 6.0));
	float band = smoothstep(0.34, 0.46, c1) * smoothstep(-0.02, 0.16, dir.y);
	float shade = smoothstep(0.42, 0.62, c1);
	vec3 cloud_white = mix(vec3(0.86, 0.88, 0.9), vec3(0.98, 0.97, 0.94), 1.0 - shade);
	col = mix(col, cloud_white, band * 0.72 * u_cloud);

	// horizon warm haze
	col = mix(col, u_horizon * 0.94, smoothstep(0.16, -0.02, dir.y) * 0.35);

	COLOR = clamp(col, vec3(0.0), vec3(2.2));
}
