shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

// SERPENTIS 3D — realistic continuous snake body (LOCAL-space pipeline).
// The tube template hangs in root-local space anchored at the head; the vertex
// shader reshapes it along a spine stored in a per-snake data texture
// (RGBA32F: xyz = station pos relative to the head, w = station radius).
// Undulation, growth and turning are baked into the spine on the CPU.
//
// Fragment: shared grayscale scale texture (Texture/snake_scales_*) tinted by
// the snake's palette, a derived normal map for scale relief, and one of five
// lengthwise pattern modes selected per skin (0 plain, 1 saddle bands,
// 2 light blotches, 3 viper zigzag, 4 accent stripes).

uniform sampler2D u_spine : filter_linear, repeat_disable;
uniform float u_texel = 0.0026041667; // 1 / RING_COUNT (keep in sync with GDScript)
uniform float u_rings = 384.0;
uniform float u_ds = 0.026;           // meters per station (updated per frame)
uniform float u_len = 10.0;           // body length in meters
uniform vec4 u_dorsal = vec4(0.05, 0.5, 0.42, 1.0);
uniform vec4 u_accent = vec4(0.9, 0.2, 0.55, 1.0);
uniform vec4 u_belly = vec4(0.85, 0.76, 0.55, 1.0);
uniform float u_seed = 0.3;
uniform float u_pattern = 0.0;        // 0..4 — see header
uniform sampler2D u_scale : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D u_scale_n : filter_linear_mipmap, repeat_enable;
uniform float u_rep_ar = 5.0;         // texture repeats around the circumference
uniform float u_tile_al = 0.62;       // meters along the body per texture tile
uniform float u_motion = 1.0;         // 0..1.3 — movement energy
uniform float u_glow = 0.0;
uniform float u_rim = 0.0;             // fresnel edge light — keeps snakes
                                      // readable on dark arenas (theme pass)
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
	float pr1 = fract(u_seed * 7.31);
	float pr2 = fract(u_seed * 3.77 + 0.41);

	// --- Shared scale texture (grayscale, tinted per snake) ---
	vec2 suv = vec2(UV.x * u_rep_ar, s_m / u_tile_al);
	float sv = texture(u_scale, suv).r;

	// --- Pattern layer (lengthwise, seeded per snake) ---
	float pat_m = 0.0;
	vec3 pat_col = u_dorsal.rgb;
	float pat = u_pattern;
	if (pat > 0.5 && pat < 1.5) {
		// dark saddle bands (banded colubrids / coral kin)
		float period = 1.9 + 1.3 * pr1;
		float w = fract(s_m / period + u_seed);
		pat_m = smoothstep(0.30, 0.48, w) * smoothstep(0.70, 0.52, w);
		pat_col = u_dorsal.rgb * 0.34;
	} else if (pat > 1.5 && pat < 2.5) {
		// light blotches with darker rims (python)
		float dy = fract(s_m / 2.6 + pr2) - 0.5;
		float dx = fract(UV.x * 3.0 + pr2 * 9.1) - 0.5;
		float bd = length(vec2(dx * 0.55, dy));
		pat_m = smoothstep(0.30, 0.16, bd) * (1.0 - belly_f * 0.85);
		pat_col = (u_dorsal.rgb * 0.42 + u_belly.rgb * 0.58);
	} else if (pat > 2.5 && pat < 3.5) {
		// viper zigzag ribbon along the spine
		float tri = abs(fract(s_m / 1.05 + pr1) - 0.5) * 2.0;
		float xx = mix(0.30, 0.70, tri);
		pat_m = smoothstep(0.115, 0.05, abs(UV.x - xx)) * (1.0 - belly_f * 0.85);
		pat_col = mix(u_dorsal.rgb, vec3(0.085, 0.075, 0.045), 0.72);
	} else if (pat > 3.5) {
		// twin accent stripes + soft dorsal line
		float s1 = smoothstep(0.085, 0.03, abs(UV.x - 0.27));
		float s2 = smoothstep(0.085, 0.03, abs(UV.x - 0.73));
		float s0 = smoothstep(0.07, 0.02, abs(UV.x - 0.5));
		pat_m = clamp(s1 + s2 + s0 * 0.55, 0.0, 1.0) * (1.0 - belly_f * 0.9);
		pat_col = mix(u_dorsal.rgb, u_accent.rgb, 0.50);
	}
	pat_m *= smoothstep(0.10, 0.55, s_m); // let the head zone stay clean

	// --- Base color assembly ---
	vec3 col = u_dorsal.rgb * (0.58 + 0.62 * sv);           // textured scales
	col = mix(col, pat_col * (0.72 + 0.42 * sv), pat_m);    // pattern over scales
	// Dorsal line accent along the spine (many colubrids have one)
	float dorsal_line = smoothstep(0.16, 0.0, topness) * (1.0 - belly_f);
	col = mix(col, mix(u_dorsal.rgb, u_accent.rgb, 0.38), dorsal_line * 0.20);
	// Belly plate: light, smoother, faint scale
	col = mix(col, u_belly.rgb * (0.86 + 0.22 * sv), belly_f);
	// Skin tone eases from the head's own tint into the body pattern
	float head_fade = smoothstep(0.18, 0.85, s_m);
	col = mix(u_dorsal.rgb * 0.88, col, head_fade);

	// --- Normal from the shared relief map ---
	vec3 N = NORMAL;
	if (!FRONT_FACING) N = -N;
	vec3 T = normalize(cross(v_axis, N) + vec3(0.0001));
	vec3 Bt = normalize(cross(N, T));
	vec2 nt = texture(u_scale_n, suv).rg * 2.0 - 1.0;
	float nstr = 1.05 * (1.0 - belly_f * 0.65) * head_fade;
	N = normalize(N + T * nt.x * nstr + Bt * nt.y * nstr * 0.75);
	NORMAL = N;

	ALBEDO = col;
	// wetter, glossier skin so scales catch the sun like the reference snakes
	ROUGHNESS = clamp(0.26 + 0.28 * (1.0 - sv) + 0.14 * belly_f + 0.10 * pat_m, 0.16, 0.80);
	SPECULAR = 0.58;
	// Theme visibility pass: fresnel edge light in the snake's accent color so
	// bodies never merge into dark arenas / 2D backgrounds.
	float fres = pow(1.0 - abs(dot(normalize(N), normalize(VIEW))), 3.0);
	EMISSION = u_accent.rgb * (u_glow * (0.25 + 0.4 * dorsal_line + pat_m * 0.2))
		+ mix(u_accent.rgb, vec3(1.0), 0.35) * u_rim * fres * 0.9;
}
