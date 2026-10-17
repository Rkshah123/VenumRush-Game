shader_type spatial;

// SERPENTIS 3D arena floor: radial tech-grid, subtle noise vignette,
// animated red danger band near the boundary.

uniform float u_size = 118.0;
uniform float u_arena = 55.0;

void fragment() {
	vec2 pos = (UV - 0.5) * u_size;
	float d = length(pos);
	float base_n = smoothstep(u_arena, 0.0, d); // 1 center -> 0 edge
	float ring = smoothstep(0.955, 0.995, abs(fract(d / 2.75) - 0.5) * 2.0);
	float danger = smoothstep(u_arena - 4.5, u_arena - 0.5, d);
	float spoke = smoothstep(0.94, 0.99, abs(fract(atan(pos.x, pos.y) * 12.2026 / 6.28318530718) - 0.5) * 2.0);

	vec3 col = vec3(0.070, 0.094, 0.150);
	col += 0.045 * ring + 0.028 * spoke;
	col *= 0.96 + 0.10 * fract(sin(dot(floor(pos * 5.0), vec2(127.1, 311.7))) * 43758.5453);
	col *= 1.02 - 0.34 * pow(d / u_arena, 2.0);

	ALBEDO = col;
	ROUGHNESS = 0.62;
	SPECULAR = 0.25;
	EMISSION = vec3(1.0, 0.15, 0.1) * danger * (0.42 + 0.28 * sin(TIME * 2.4));
}
