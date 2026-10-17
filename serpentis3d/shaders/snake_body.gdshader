shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

// SERPENTIS 3D — realistic continuous snake body (LOCAL-space pipeline).
// The tube template hangs in root-local space anchored at the head; the vertex
// shader reshapes it along a spine stored in a per-snake data texture
// (RGBA32F: xyz = station pos relative to the head, w = station radius).
// Undulation, growth and turning are baked into the spine on the CPU.

uniform sampler2D u_spine : filter_linear, repeat_disable;
uniform float u_texel = 0.0026041667; // 1 / RING_COUNT (keep in sync with GDScript)
uniform float u_rings = 384.0;
uniform float u_ds = 0.026;           // meters per station (updated per frame)
uniform float u_len = 10.0;           // body length in meters
uniform vec4 u_dorsal = vec4(0.05, 0.5, 0.42, 1.0);
uniform vec4 u_accent = vec4(0.9, 0.2, 0.55, 1.0);
uniform vec4 u_belly = vec4(0.85, 0.76, 0.55, 1.0);
uniform float u_seed = 0.3;
uniform float u_motion = 1.0;         // 0..1.3 — movement energy
uniform float u_glow = 0.0;
uniform float u_dbg = 0.0;            // dev: flat ribbon diagnostic (bypasses spine texture)

varying vec3 v_axis;

void vertex() {
	float th = UV.x * 6.28318530718;
	float cs = cos(th);
	float sn = sin(th);

	if (u_dbg > 0.5) {
		// dev: flat ribbon diagnostic (bypasses the spine texture)
		vec3 P = vec3(-30.0 + UV.y * 60.0, 0.45, 0.0);
		vec3 D = vec3(1.0, 0.0, 0.0);
		v_axis = D;
		vec3 S = normalize(cross(vec3(0.0, 1.0, 0.0), D));
		vec3 U = cross(D, S);
		VERTEX = P + S * cs * 0.41 + U * sn * 0.41 * 0.86;
		NORMAL = normalize(S * cs + U * sn * 1.16);
	} else {
		float st = clamp(UV.y / u_texel, 0.0, u_rings - 1.0);
		float i0 = floor(st);
		float f = st - i0;
		float t0 = clamp((i0 + 0.5) * u_texel, 0.0, 1.0);
		float t1 = clamp(t0 + u_texel, 0.0, 1.0);
		float tp = clamp(t0 - u_texel, 0.0, 1.0);

		vec4 A = texture(u_spine, vec2(t0, 0.5));
		vec4 B = texture(u_spine, vec2(t1, 0.5));
		vec4 P0 = texture(u_spine, vec2(tp, 0.5));

		vec3 P = mix(A.xyz, B.xyz, f);
		float r = mix(A.w, B.w, f);

		vec3 D = normalize(B.xyz - P0.xyz + vec3(0.0001, 0.0, 0.0));
		v_axis = D;
		vec3 S = normalize(cross(vec3(0.0, 1.0, 0.0), D));
		vec3 U = cross(D, S);

		// Slightly flattened cross-section (real snake bodies are not perfect cylinders)
		VERTEX = P + S * cs * r + U * sn * r * 0.86;
		NORMAL = normalize(S * cs + U * sn * 1.16);
	}
}

void fragment() {
	float topness = sin(UV.x * 6.28318530718); // +1 = spine top, -1 = belly
	float belly_f = smoothstep(0.30, -0.30, topness);

	float s_m = UV.y * (u_rings - 1.0) * u_ds; // meters along the body

	// --- Scales: staggered diamond cells, physically aligned with body flow ---
	float row = floor(s_m / 0.16);
	float alt = mod(row, 2.0);
	float uc = fract(UV.x * 9.0 + alt * 0.5);
	float vc = fract(s_m / 0.16);
	vec2 cell = (vec2(uc, vc) - 0.5) * vec2(1.0, 1.12);
	float d = length(cell);
	float scale_center = smoothstep(0.46, 0.24, d); // 1 center, 0 in gaps
	float scale_edge   = smoothstep(0.30, 0.44, d);

	// --- Lengthwise pattern: soft bands seeded per snake ---
	float band_period = 1.25 + 0.6 * fract(u_seed * 17.3);
	float band = smoothstep(0.35, 0.62, abs(fract(s_m / band_period + u_seed) - 0.5) * 2.0);

	// --- Spots: subtle accent diamonds ---
	float spot = smoothstep(0.16, 0.03,
		abs(abs(fract(uc * 2.7 + s_m / 2.9 + u_seed * 0.7) - 0.5)
		  + abs(fract(s_m / 2.2 + u_seed * 0.13) - 0.5) - 0.44));

	vec4 dorsal = u_dorsal;
	// Saddle bands + spots stay in the same hue family as the base skin (real
	// snakes read as tonal variation, not sticker contrast).
	vec3 accent_warm = mix(u_dorsal.rgb, u_accent.rgb, 0.38);
	dorsal.rgb = mix(u_dorsal.rgb, accent_warm, band * 0.42 + spot * 0.30);
	// Dorsal line accent along the spine (many colubrids have one)
	float dorsal_line = smoothstep(0.16, 0.0, topness) * (1.0 - belly_f);
	dorsal.rgb = mix(dorsal.rgb, accent_warm, dorsal_line * 0.22);

	vec3 col = mix(dorsal.rgb, u_belly.rgb, belly_f);

	// Skin tone eases from the head's own tint into the body pattern so the
	// head-to-neck transition has no visible seam.
	float head_fade = smoothstep(0.18, 0.85, s_m);
	col = mix(u_dorsal.rgb * 0.86, col, head_fade);
	col *= 0.84 + 0.22 * scale_center * head_fade;

	// --- Micro-normal from scale relief ---
	vec3 N = NORMAL;
	if (!FRONT_FACING) N = -N;
	vec3 T = normalize(cross(v_axis, N) + vec3(0.0001));
	vec3 Bt = normalize(cross(N, T));
	float bu = (uc - 0.5) * scale_center * 0.5;
	float bv = (vc - 0.5) * scale_center * 0.5;
	N = normalize(N + T * bu * 0.42 + Bt * bv * 0.42);
	NORMAL = N;

	ALBEDO = col;
	ROUGHNESS = 0.36 + 0.26 * scale_edge + 0.18 * belly_f;
	SPECULAR = 0.45;
	EMISSION = u_accent.rgb * (u_glow * (0.25 + 0.4 * dorsal_line + band * 0.2));
}
