shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, blend_mix;

// SERPENTIS 3D — animated water surface: layered ripples, fresnel sky tint
// and a shallow-to-deep gradient. Cheap enough for gl_compatibility.

uniform vec3 u_shallow = vec3(0.16, 0.42, 0.48);
uniform vec3 u_deep = vec3(0.04, 0.16, 0.28);
uniform float u_alpha = 0.86;
uniform vec3 u_sky_tint = vec3(0.55, 0.68, 0.78);
uniform float u_disp = 1.0; // goo factor for dev

varying vec3 v_world;
varying vec3 v_wave_n;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 0.9;
	float w =
		sin(v_world.x * 0.55 + t * 1.20) * 0.030
		+ sin(v_world.z * 0.72 - t * 0.85) * 0.026
		+ sin((v_world.x + v_world.z) * 0.34 + t * 1.7) * 0.036;
	VERTEX.y += w * u_disp;
	// cheap derivative normal
	float dx = cos(v_world.x * 0.55 + t * 1.20) * 0.55 * 0.030 + cos((v_world.x + v_world.z) * 0.34 + t * 1.7) * 0.34 * 0.036;
	float dz = cos(v_world.z * 0.72 - t * 0.85) * 0.72 * 0.026 + cos((v_world.x + v_world.z) * 0.34 + t * 1.7) * 0.34 * 0.036;
	v_wave_n = normalize(vec3(-dx * 4.0, 1.0, -dz * 4.0));
}

void fragment() {
	vec3 n = normalize(v_wave_n);
	vec3 view = normalize(CAMERA_POSITION_WORLD - v_world);

	float fres = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 3.2);
	float depth_band = UV.x; // authored: 0 at shore, 1 toward middle
	vec3 body = mix(u_shallow, u_deep, depth_band * 0.6 + fres * 0.1);
	body = mix(body, u_sky_tint, fres * 0.55);
	// sparkle
	float glint = pow(max(dot(n, normalize(vec3(0.2, 0.9, 0.1))), 0.0), 60.0) * 0.6;
	body += glint;

	ALBEDO = clamp(body, vec3(0.02), vec3(1.0));
	ROUGHNESS = 0.13;
	SPECULAR = 0.9;
	ALPHA = u_alpha;
	EMISSION = clamp(u_sky_tint * (glint * 0.25 + fres * 0.04), vec3(0.0), vec3(0.3));
}
