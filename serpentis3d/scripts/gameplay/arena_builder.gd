class_name ArenaBuilder
extends Node3D
## Builds the whole arena presentation: environment, lights, floor with danger
## ring, boundary halo, crystal formations and rocks (MultiMesh), drifting dust.
## Also returns collision obstacle descriptors used by snakes/AI.

const ARENA_R := 55.0

var obstacles: Array = []   # [{pos: Vector3, r: float}]

func _ready() -> void:
	_build_environment()
	_build_lights()
	_build_floor()
	_build_boundary()
	_build_crystals()
	_build_rocks()
	_build_dust()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.045, 0.075)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.34, 0.5)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.02
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.12, 0.2)
	env.fog_density = 0.0045
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 1.15
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(28.0), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.3, 0.45, 0.85)
	rim.light_energy = 0.42
	rim.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(-150.0), 0)
	add_child(rim)

func _build_floor() -> void:
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ARENA_R * 2.0 + 8.0, ARENA_R * 2.0 + 8.0)
	plane.subdivide_depth = 24
	plane.subdivide_width = 24
	floor_mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/floor.gdshader")
	mat.set_shader_parameter("u_size", ARENA_R * 2.0 + 8.0)
	mat.set_shader_parameter("u_arena", ARENA_R)
	floor_mi.material_override = mat
	floor_mi.position.y = 0.0
	add_child(floor_mi)

func _build_boundary() -> void:
	var wall := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ARENA_R - 0.45
	torus.outer_radius = ARENA_R + 0.55
	torus.rings = 96
	torus.ring_segments = 10
	wall.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.06, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.12, 0.08)
	mat.emission_energy_multiplier = 1.8
	mat.roughness = 0.5
	wall.material_override = mat
	wall.position = Vector3(0, 0.42, 0)
	add_child(wall)

func _crystal_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.55
	m.height = 1.1
	m.radial_segments = 6      # angular crystal look
	m.rings = 3
	return m

func _build_crystals() -> void:
	var count := 26
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _crystal_mesh()
	mm.instance_count = count
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.6, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.85, 1.0)
	mat.emission_energy_multiplier = 1.1
	mat.roughness = 0.15
	mat.metallic = 0.4
	mm.mesh.surface_set_material(0, mat)

	var locations: Array = []
	var i := 0
	while i < count:
		var ang := randf() * TAU
		var rad := randf_range(10.0, ARENA_R - 9.0)
		var pos := Vector3(sin(ang) * rad, 0, cos(ang) * rad)
		var ok := true
		for other in locations:
			if pos.distance_to(other) < 9.0:
				ok = false
				break
		if not ok:
			continue
		locations.append(pos)
		var scale := randf_range(1.4, 3.2)
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, scale * 1.9, 1.0)).rotated(Vector3.UP, randf() * TAU), pos)
		t.basis = t.basis.rotated(Vector3(randf() - 0.5, 0, randf() - 0.5).normalized(), randf_range(-0.16, 0.16))
		mm.set_instance_transform(i, t)
		obstacles.append({"pos": pos, "r": 0.66 * scale})
		i += 1

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)

func _build_rocks() -> void:
	var count := 16
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := SphereMesh.new()
	mesh.radius = 0.8
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 6
	mm.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.2, 0.24)
	mat.roughness = 0.9
	mm.mesh.surface_set_material(0, mat)
	mm.instance_count = count
	for i in count:
		var ang := randf() * TAU
		var rad := randf_range(9.0, ARENA_R - 7.0)
		var pos := Vector3(sin(ang) * rad, -0.25, cos(ang) * rad)
		var s := randf_range(0.8, 1.9)
		var t := Transform3D(
			Basis.from_scale(Vector3(s * randf_range(1.0, 1.5), s * 0.55, s * randf_range(1.0, 1.5))).rotated(Vector3.UP, randf() * TAU),
			pos)
		mm.set_instance_transform(i, t)
		obstacles.append({"pos": pos, "r": 0.85 * s})
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

func _build_dust() -> void:
	var p := GPUParticles3D.new()
	p.amount = 170
	p.lifetime = 9.0
	p.visibility_aabb = AABB(Vector3(-70, -2, -70), Vector3(140, 24, 140))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(ARENA_R + 4, 6, ARENA_R + 4)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.gravity = Vector3(0, 0.06, 0)
	mat.initial_velocity_min = 0.15
	mat.initial_velocity_max = 0.5
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	p.process_material = mat
	var dr := QuadMesh.new()
	dr.size = Vector2(0.16, 0.16)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dmat.albedo_color = Color(0.55, 0.85, 1.0, 0.22)
	dr.material = dmat
	p.draw_pass_1 = dr
	p.position = Vector3(0, 4, 0)
	add_child(p)
