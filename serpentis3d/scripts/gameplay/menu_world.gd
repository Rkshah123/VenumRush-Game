class_name MenuWorld
extends Node3D
## SERPENTIS 3D — dedicated home-screen scene.
##
## The living cinematic backdrop the main menu plays over: real snakes gliding
## on curved wander paths (the SAME Snake class as gameplay, so the menu and
## the match look identical), drifting dust motes, glowing orbs, and a void
## stage with a soft radial glow. It has its OWN WorldEnvironment and ground —
## the gameplay arena is never rendered behind the menu.
##
## Game toggles it: menu = awake (visible + running), gameplay = fully dormant
## (invisible AND process-disabled), so none of this costs anything in a match.

@export var dark := false   # Dark Theme pass (set by Game at boot / theme change)

var tier := 2
var snakes: Array = []      # living menu serpents
var _t := 0.0

var _env: Environment              # this scene's sky / ambient / glow
var _stage_mat: ShaderMaterial     # radial glow stage shader
var _orb_nodes: Array = []
var _orb_seed: Array = []          # [phase, speed, base_y, base_x, base_z]
var _rng := RandomNumberGenerator.new()
var _cam_angle := 0.0

func _ready() -> void:
	_rng.randomize()
	# perf tier (same rule the arena builder uses)
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		tier = 0
	else:
		var gpu := RenderingServer.get_video_adapter_name().to_lower()
		tier = 1 if (gpu.contains("intel") and (gpu.contains("uhd") or gpu.contains("hd"))) else 2
	_build_environment()
	_build_stage()
	_build_motes()
	_build_snakes()
	_build_orbs()
	_cam_angle = _rng.randf() * TAU

# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var amb := WorldEnvironment.new()
	_env = Environment.new()
	_apply_env_colors()
	amb.environment = _env
	add_child(amb)
	# soft key light from high front-left: models out of the void
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -34, 0)
	sun.light_energy = 1.30
	sun.light_color = Color(0.82, 0.92, 1.0) if dark else Color(0.90, 0.95, 1.0)
	sun.light_indirect_energy = 0.40
	# contact shadows ground the serpents on the stage — desktop tier only,
	# phones (tier 0) keep the free no-shadow menu pass
	sun.shadow_enabled = tier >= 1
	if sun.shadow_enabled:
		sun.directional_shadow_max_distance = 90.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	# faint cool fill from the other side for readable silhouette edges
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38, 128, 0)
	fill.light_energy = 0.22
	fill.light_color = Color(0.35, 0.55, 0.75)
	add_child(fill)

func _apply_env_colors() -> void:
	# BG_COLOR + ambient color: the cheapest atmospheric backdrop — a deep navy
	# void matching the stage plane's edge tone so there is no horizon seam.
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.010, 0.018, 0.030) if dark else Color(0.030, 0.040, 0.052)
	var amb_c := Color(0.15, 0.21, 0.30) if dark else Color(0.22, 0.27, 0.34)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = amb_c
	_env.ambient_light_energy = 0.38 if dark else 0.32
	_env.glow_enabled = tier >= 1
	_env.glow_intensity = 0.7 if dark else 0.45
	_env.glow_bloom = 0.10 if dark else 0.06
	_env.glow_hdr_threshold = 0.92 if dark else 1.0
	_env.fog_enabled = false
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.12 if dark else 1.02

func set_dark(v: bool) -> void:
	dark = v
	_apply_env_colors()
	_apply_stage_colors()
	for s in snakes:
		if is_instance_valid(s):
			s.set_rim(0.42 if dark else 0.16)

# ---------------------------------------------------------------- stage

func _build_stage() -> void:
	# Ground of the menu world: a soft radial glow disc. Deliberately NOT the
	# gameplay court — no mow bands, no arena geometry. Oversized so the plane
	# edge can never cut across the camera frustum at menu angles.
	var m := MeshInstance3D.new()
	var plane := 420.0
	# plane edge tone == bg color, so seam never shows
	var pmx := PlaneMesh.new()
	pmx.size = Vector2(plane, plane)
	m.mesh = pmx
	m.position.y = -1.35
	_stage_mat = ShaderMaterial.new()
	_stage_mat.shader = load("res://shaders/menu_stage.gdshader")
	_stage_mat.set_shader_parameter(&"u_size", 420.0)
	_apply_stage_colors()
	m.material_override = _stage_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	# faint contact disc that visually anchors the snakes
	var disc := MeshInstance3D.new()
	var dm := PlaneMesh.new()
	dm.size = Vector2(84, 84)
	disc.mesh = dm
	disc.position.y = -1.31
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.02, 0.032, 0.044, 0.8)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.roughness = 1.0
	disc.material_override = dmat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)

func _apply_stage_colors() -> void:
	if _stage_mat == null or _stage_mat.shader == null:
		return
	if dark:
		_stage_mat.set_shader_parameter(&"u_a", Color(0.010, 0.018, 0.030))
		_stage_mat.set_shader_parameter(&"u_b", Color(0.018, 0.052, 0.058))
		_stage_mat.set_shader_parameter(&"u_glow", Color(0.16, 0.85, 0.72))
	else:
		_stage_mat.set_shader_parameter(&"u_a", Color(0.030, 0.040, 0.052))
		_stage_mat.set_shader_parameter(&"u_b", Color(0.052, 0.086, 0.094))
		_stage_mat.set_shader_parameter(&"u_glow", Color(0.14, 0.80, 0.68))

# ---------------------------------------------------------------- ambience

func _build_motes() -> void:
	var p := GPUParticles3D.new()
	p.amount = [90, 150, 220][clampi(tier, 0, 2)]
	p.lifetime = 9.0
	p.randomness = 1.0
	p.visibility_aabb = AABB(Vector3(-46, -1, -46), Vector3(92, 34, 92))
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.55, 0.95, 0.90, 0.5)
	mm.emission_enabled = true
	mm.emission = Color(0.35, 0.9, 0.82)
	mm.emission_energy_multiplier = 0.85
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mm
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(44, 14, 44)
	pm.direction = Vector3(0.06, 1.0, 0.0)
	pm.spread = 24.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 1.05
	pm.scale_min = 0.55
	pm.scale_max = 1.6
	pm.color = Color(0.6, 1.0, 0.92, 0.42)
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.position = Vector3(0, 10, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

func _build_orbs() -> void:
	_orb_nodes.clear()
	_orb_seed.clear()
	var count: int = [7, 9, 12][clampi(tier, 0, 2)]
	for i in count:
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		sm.radial_segments = 12
		sm.rings = 6
		orb.mesh = sm
		var om := StandardMaterial3D.new()
		om.albedo_color = Color(0.2, 0.9, 0.75)
		om.emission_enabled = true
		om.emission = Color(0.25, 1.0, 0.83)
		om.emission_energy_multiplier = 1.5
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		orb.material_override = om
		var sc := _t_rng()
		orb.scale = Vector3(sc, sc, sc)
		orb.position = Vector3(_rng.randf_range(-28, 28), _rng.randf_range(0.4, 8.0), _rng.randf_range(-28, 28))
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(orb)
		_orb_nodes.append(orb)
		_orb_seed.append([_rng.randf() * TAU, _rng.randf_range(0.25, 0.6),
			orb.position.y, orb.position.x, orb.position.z])

func _t_rng() -> float:
	return _rng.randf_range(0.55, 1.6)

# ---------------------------------------------------------------- serpents

class _MenuSnake extends Snake:
	## Wander steering: the orbit advances on a wobbly ellipse, so the snake
	## constantly changes direction in gentle sweeping arcs — never a fixed
	## circle. All the natural slither/undulation comes from Snake itself.
	var tick := 0.0
	var home := Vector3.ZERO
	var phase := 0.0
	var orbit_r := 16.0
	var orbit_speed := 0.16
	var drift := 3.0
	var dir_flip := 1.0

	func _steer(_delta: float) -> void:
		var a := tick * orbit_speed * dir_flip + phase
		var target := home + Vector3(
			cos(a) * (orbit_r + sin(tick * 0.21 + phase * 3.1) * drift),
			0.0,
			sin(a * 0.92) * (orbit_r * 0.8 + cos(tick * 0.17 + phase * 2.3) * drift))
		var want := (target - head_pos)
		want.y = 0.0
		desired_dir = want.normalized() if want.length() > 0.6 \
			else Vector3(sin(heading), 0.0, cos(heading))
		input_boost = false

func _build_snakes() -> void:
	snakes.clear()
	# Depth layers: far silhouettes -> mid-serpents -> near hero. Counts per
	# layer, then apparent-distance scale + a dimmed shader for the far ones.
	# Girth is slimmed so the cinematic serpents read as snakes, not pool noodles.
	var defs := [
		[3, 24.0, 13.0, 1.45, true],    # far: dim, big
		[3, 15.5, 10.0, 1.05, false],                       # mid
		[1, 5.5, 8.0, 0.82, false],                         # near hero (hugs the center: the
	]                                                   # camera orbit stays far from it)
	# saturated skins read best on the dark stage (skip the pale FROSTBITE)
	var bag := [0, 1, 2, 4, 5, 6, 7, 8, 0, 5, 2]
	var sk_off := int(_rng.randf() * float(bag.size()))
	for layer: Array in defs:
		for i in int(layer[0]):
			var s := _MenuSnake.new()
			var sk := SkinCatalog.get_skin(bag[(sk_off + snakes.size()) % bag.size()])
			s.apply_skin(sk["dorsal"], sk["accent"], sk["belly"], sk["seed"], int(sk["pattern"]))
			s.id = 900 + snakes.size()
			s.display_name = "menu"
			s.max_length = 30.0
			add_child(s)
			s.set_rim(0.42 if dark else 0.16)
			s.girth = 0.62
			s.spine_stride = 2 if tier == 0 else 1   # phones: tube refresh at 30 Hz
			s.scale = Vector3.ONE * float(layer[3])           # apparent distance
			if bool(layer[4]):
				_dim_snake(s)
			var s_len := float(layer[2]) * _rng.randf_range(0.85, 1.2)
			s.spawn(Vector3(_rng.randf_range(-12, 12), 0.0, _rng.randf_range(-12, 12)),
				Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized(), s_len)
			s.home = Vector3.ZERO
			s.phase = _rng.randf() * TAU
			s.orbit_r = float(layer[1]) + _rng.randf_range(-3.0, 3.5)
			s.orbit_speed = _rng.randf_range(0.10, 0.19)
			s.dir_flip = 1.0 if _rng.randf() > 0.3 else -1.0
			s.drift = _rng.randf_range(2.0, 4.5)
			snakes.append(s)

## Far-layer snakes are dimmed so they sit back in the scene (depth cue).
func _dim_snake(s: Snake) -> void:
	var m := s.get_body_material()
	if m != null:
		var to_dark := Color(0.13, 0.20, 0.27) if dark else Color(0.24, 0.30, 0.36)
		m.set_shader_parameter(&"u_dorsal", to_dark)
		m.set_shader_parameter(&"u_accent", to_dark.lightened(0.10))
		m.set_shader_parameter(&"u_belly", to_dark.lightened(0.06))
		m.set_shader_parameter(&"u_rim", 0.03)
		m.set_shader_parameter(&"u_glow", 0.0)

func ensure_life() -> void:
	# menus never kill snakes; rebuild only if the layer was cleared
	if snakes.is_empty():
		_build_snakes()

# ---------------------------------------------------------------- frame

func _physics_process(delta: float) -> void:
	_t += delta
	for i in snakes.size():
		var s: _MenuSnake = snakes[i]
		if is_instance_valid(s):
			s.tick = _t
	for i in _orb_nodes.size():
		var o: Node3D = _orb_nodes[i]
		if is_instance_valid(o):
			var sd: Array = _orb_seed[i]
			o.position.y = float(sd[2]) + sin(_t * float(sd[1]) + float(sd[0])) * 1.4
			o.position.x = float(sd[3]) + cos(_t * 0.07 + float(sd[0])) * 2.2

## Cinematic camera drift around the serpent cluster. Driven by Game in MENU.
func update_cameras(cam: Camera3D, delta: float) -> void:
	_cam_angle += delta * 0.05
	# every serpent orbits the world origin, so an origin-locked orbit keeps a
	# stable, always-populated composition (a running mean of heads skews the
	# framing and lets the lower frame go empty)
	var r := 29.0 - 3.5 * sin(_t * 0.06)
	var h := 9.0 + 1.9 * sin(_t * 0.10 + 1.3)
	var pos := Vector3(cos(_cam_angle) * r, h, sin(_cam_angle) * r)
	var look := Vector3(0.0, 1.1 + 0.5 * sin(_t * 0.07), 0.0)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 50.0
	var p_new := cam.global_position.lerp(pos, 1.0 - exp(-1.9 * delta))
	cam.look_at_from_position(p_new, look, Vector3.UP)

# ---------------------------------------------------------------- state

## Fully active: visible, processes, cameras usable.
func awake() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	ensure_life()

## Dormant in gameplay: invisible to all cameras AND zero CPU.
func dormant() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
