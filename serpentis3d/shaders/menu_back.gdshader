shader_type canvas_item;

// SERPENTIS — home-page animated background (faithful recreation of the
// project's Back.html storm scene, which Godot cannot render directly).
// Layers, matching Back.html:
//   1. base vertical gradient  #050711 -> #11111a (48%) -> #090609
//   2. drifting colour glows: blue (0,72,180) at 22%/38%, fire (255,111,0) at 82%/39%
//   3. blurred storm-cloud roll (noise, two layers)
//   4. rising embers — cool blue + fire orange (grid-hash sparks)
//   5. ground band with pulsing fissure lines + energy arcs
//   6. vignette
// Lightning bolts + white flash are CPU-driven (hud.gd) on top of this rect.

uniform float u_intensity : hint_range(0.0, 2.0) = 1.0; // mobile tier can dial this down

// --- hash / value noise (cheap, no textures) ---
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	return 0.65 * vnoise(p) + 0.35 * vnoise(p * 2.13 + 7.7);
}

// soft radial glow
float glow(vec2 uv, vec2 at, float radius) {
	return exp(-dot(uv - at, uv - at) / (radius * radius));
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;

	// ---- 1. base vertical gradient (Back.html :root stack) ----
	vec3 col = mix(vec3(0.020, 0.027, 0.067), vec3(0.067, 0.067, 0.102),
		smoothstep(0.0, 0.48, uv.y));
	col = mix(col, vec3(0.035, 0.023, 0.035), smoothstep(0.48, 1.0, uv.y));

	// ---- 2. drifting blue / fire glows ----
	vec2 blue_at = vec2(0.22 + 0.05 * sin(t * 0.11), 0.38 + 0.03 * sin(t * 0.17));
	vec2 fire_at = vec2(0.82 + 0.04 * sin(t * 0.13 + 2.0), 0.39 + 0.03 * cos(t * 0.09));
	col += vec3(0.0, 0.28, 0.71) * 0.25 * glow(uv, blue_at, 0.44) * u_intensity;
	col += vec3(1.0, 0.435, 0.0) * 0.24 * glow(uv, fire_at, 0.42) * u_intensity;

	// ---- 3. storm cloud roll (blurred radial blobs in Back.html) ----
	float cl = fbm2(uv * vec2(2.6, 4.2) + vec2(t * 0.055, -t * 0.021));
	float cl2 = fbm2(uv * vec2(4.1, 6.0) + vec2(-t * 0.042, t * 0.030) + 19.0);
	float clouds = (0.65 * cl + 0.35 * cl2);
	col = mix(col, col * 1.9 + vec3(0.02, 0.05, 0.10),
		0.34 * smoothstep(0.35, 0.85, clouds) * u_intensity);
	// dark core between the two glows (the .storm dark centre blob)
	col *= 1.0 - 0.30 * glow(uv, vec2(0.48, 0.50), 0.48);

	// ---- 4. rising embers (blue + fire) ----
	// grid-hash sparks: each cell owns one ember with a random phase/colour.
	vec2 eg = uv * vec2(10.0, 7.0);
	vec2 cell = floor(eg);
	vec2 f = fract(eg);
	float h = hash21(cell);
	float h2 = hash21(cell + 3.1);
	// ember rises through its cell; loops with a random phase
	float ph = fract(h * 9.0 + t * (0.05 + 0.10 * h2));
	vec2 epos = vec2(0.15 + 0.7 * h2 + 0.08 * sin(t * 1.3 + h * 40.0), 1.0 - ph);
	float d = length(f - epos);
	float spark = exp(-d * d * 90.0) * smoothstep(0.0, 0.15, ph) * smoothstep(1.0, 0.75, ph);
	// 70% fire sparks, 30% cool blue (Back.html palette)
	vec3 ecol = mix(vec3(1.0, 0.45, 0.10), vec3(0.25, 0.55, 1.0), step(0.70, h));
	col += ecol * spark * 0.55 * u_intensity;

	// ---- 5. ground band: fissures + energy arcs ----
	float ground = smoothstep(0.66, 0.78, uv.y);
	// fissure lines: horizontal noise cracks that pulse
	float fx = uv.x * 3.0;
	float crack_n = vnoise(vec2(fx, uv.y * 26.0));
	float crack = smoothstep(0.48, 0.5, abs(fract(fx * 0.5 + crack_n * 2.0) - 0.5) * 2.0);
	crack = 1.0 - crack;                       // thin bright line where fract ~ edge
	crack *= step(0.495, crack_n) * smoothstep(0.66, 0.85, uv.y);
	float pulse = 0.55 + 0.45 * sin(t * 2.1 + uv.x * 6.0 + crack_n * 12.0);
	col += mix(vec3(1.0, 0.35, 0.05), vec3(0.15, 0.45, 1.0), crack_n) *
		crack * pulse * 0.22 * u_intensity;
	// ground reads darker + faintly warm near the very bottom
	col = mix(col, col * vec3(1.05, 0.82, 0.62) * 0.42, ground);

	// ---- 6. vignette ----
	float vig = smoothstep(1.25, 0.35, length((uv - 0.5) * vec2(1.05, 1.25)));
	col *= 0.55 + 0.45 * vig;

	COLOR = vec4(col, 1.0);
}
