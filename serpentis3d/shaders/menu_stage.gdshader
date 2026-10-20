shader_type spatial;
render_mode cull_back, unshaded;

// SERPENTIS 3D — home-screen void stage: a soft radial glow on a dark plane.
// Cheap (one plane, no lights involved) — the menu scene must always animate
// smoothly, even mid-tier phones.

uniform vec4 u_a : source_color = vec4(0.03, 0.04, 0.052, 1.0); // edge tone
uniform vec4 u_b : source_color = vec4(0.052, 0.088, 0.096, 1.0); // inner tone
uniform vec4 u_glow : source_color = vec4(0.14, 0.8, 0.68, 1.0);
uniform float u_size = 320.0;   // plane world size (matches PlaneMesh.size)
uniform float u_core_r = 30.0;  // radius of the brightest core

void fragment() {
	vec2 p = (UV - 0.5) * u_size;
	float d = length(p);

	// radial falloff: curved so the luminous core is wide and the rim eases
	// into the flat background tone (t=1 must equal the BG color exactly,
	// otherwise the oversized plane reads a false horizon line)
	float t = clamp(d / (u_size * 0.5), 0.0, 1.0);
	float tt = pow(t, 1.35);

	// two very slow "breathing" rings give the void ambient life — masked to
	// the inner floor so no ring arc ever sweeps the rim like a horizon band
	float r1 = sin(d * 0.22 - TIME * 0.22);
	float r2 = sin(d * 0.11 + TIME * 0.13);
	float ring_mask = 1.0 - smoothstep(0.25, 0.72, t);
	float breathing = 0.030 * smoothstep(0.86, 1.0, r1) + 0.018 * smoothstep(0.90, 1.0, r2);

	float core = smoothstep(u_core_r * 1.9, 0.0, d) * 0.55;
	vec3 col = mix(u_b.rgb, u_a.rgb, tt);
	col = mix(col, u_glow.rgb * 0.14, core * (0.35 + 0.20 * sin(TIME * 0.4)));
	col += u_glow.rgb * (breathing * ring_mask);

	ALBEDO = col;
}
