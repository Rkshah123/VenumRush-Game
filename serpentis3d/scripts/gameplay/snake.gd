class_name Snake
extends Node3D
## One living snake — kinematic head simulation, path-history spine,
## GPU-deformed continuous tube body and a procedural head.
## Subclasses provide steering via _steer().

signal died(snake: Snake, killer_name: String)
signal ate(snake: Snake, kind: int, score_value: int)

const SPACING := 0.075          # polyline sampling spacing (m)
const RING_COUNT := 384         # body stations (tube rings); texel = 1/384
const RING_TEXEL := 1.0 / float(RING_COUNT)
const HIST_MAX := 1024
const MIN_LENGTH := 3.5
const GROWTH_RATE := 3.4        # visual growth speed (m/s toward target length)
const TURN_RATE_BASE := 3.6
const MIN_TURN_RADIUS := 1.05   # curvature guard: no tube self-intersection
const BASE_SPEED := 4.6
const BOOST_MULT := 1.6
const BOOST_MAX := 3.2
const BOOST_REGEN := 0.55

var id := 0
var display_name := "Serpent"
var is_player := false
var is_boss := false
var dorsal := Color(0.06, 0.52, 0.44)
var accent := Color(0.95, 0.24, 0.6)
var belly := Color(0.86, 0.78, 0.58)
var skin_seed := 0.5
var pattern := 0                  # 0 plain, 1 bands, 2 blotches, 3 zigzag, 4 stripes
var rim := 0.0                   # fresnel edge light (dark theme / 2D mode visibility pass)
var initial_length := 7.0
var max_length := 58.0

var alive := true
var score := 0
var kills := 0
var spawn_ms := 0
var spawn_match_time := 0.0

var length := 7.0
var target_length := 7.0
var heading := 0.0
var head_pos := Vector3.ZERO
var wave_phase := 0.0
var wave_phase_off := 0.0
var speed_cur := 0.0
var _head_rot := Basis.IDENTITY    # smoothed pure-rotation basis of the head

var boost_active := false
var boost_meter := BOOST_MAX

# --- power-orb abilities (Magnet Pulse / Shield) ---
const ABILITY_DUR := {"magnet": 5.0, "shield": 4.0}
var ability := ""
var ability_left := 0.0
var _ability_dur := 1.0
var _halo: MeshInstance3D
var _skin_mats: Array = []   # [StandardMaterial3D, snout_flavor: bool] — head parts that recolor on apply_skin

# Steering contract for subclasses:
var desired_dir := Vector3(0, 0, 1)
var input_boost := false
var hold_heading := -999.0   # dev: lock steering straight (closeup diagnosis)

# World refs (set by MatchWorld)
var match_world = null

# Body rendering
var body_mi: MeshInstance3D
var _mat: ShaderMaterial
var _tex: ImageTexture
var _spine := PackedFloat32Array()   # RING_COUNT*4 floats
var _raw := PackedVector3Array()     # RING_COUNT station source points
var _perp := PackedVector3Array()    # lateral direction per station

# Collision stations (updated per physics frame)
var coll_pos := PackedVector3Array()
var coll_r := PackedFloat32Array()
var coll_stride := 2

# Head visuals
var head_root: Node3D
var _jaw: Node3D
var _tongue: Node3D
var _mouth_open := 0.0
var _flick_timer := 0.0
var _flick_phase := 0.0
var _lunge := 0.0                 # eating animation: quick head snap (0..1)
var _pulse := 0.0                 # growth response: brief body thickening (0..1)
var _eye_mats: Array[StandardMaterial3D] = []   # eyes — theme rim pass
var head_vel := Vector3(0, 0, 1)     # world velocity of head (for AI prediction)

# polyline ring buffer
var _hist := PackedVector3Array()
var _hist_write := 0
var _hist_count := 0
var _last_sample := Vector3(1e9, 1e9, 1e9)

static var _shader: Shader = null
static var _scale_albedo: Texture2D = null      # shared procedural scale texture
static var _scale_normal: Texture2D = null      # matching relief normal map

func _ready() -> void:
	if not is_inside_tree():
		return
	_hist.resize(HIST_MAX)
	_spine.resize(RING_COUNT * 4)
	_raw.resize(RING_COUNT)
	_perp.resize(RING_COUNT)
	_build_body()
	_build_head()
	# shield halo: emissive shell around the head, shown while Shield is up
	var hm := SphereMesh.new()
	hm.radius = 0.62
	hm.height = 1.24
	hm.radial_segments = 14
	hm.rings = 7
	_halo = MeshInstance3D.new()
	_halo.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.45, 0.95, 1.0, 0.30)
	hmat.emission_enabled = true
	hmat.emission = Color(0.45, 0.95, 1.0)
	hmat.emission_energy_multiplier = 1.3
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo.material_override = hmat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.visible = false
	add_child(_halo)

# ------------------------------------------------------------------ lifecycle

func spawn(pos: Vector3, dir: Vector3, body_len: float) -> void:
	global_position = pos
	alive = true
	target_length = clampf(body_len, MIN_LENGTH, max_length)
	length = target_length
	heading = atan2(dir.x, dir.z)
	head_pos = pos
	wave_phase = randf() * TAU
	wave_phase_off = randf() * TAU
	speed_cur = BASE_SPEED
	boost_meter = BOOST_MAX
	spawn_ms = Time.get_ticks_msec()
	spawn_match_time = match_world.match_time if match_world != null else 0.0

	# Fill polyline with a straight tail extending backwards so the body exists immediately.
	var back := -Vector3(dir.x, 0.0, dir.z).normalized()
	var n := mini(HIST_MAX, int(length / SPACING) + 4)
	for i in n:
		_hist[i] = pos + back * (float(i) * SPACING)
	_hist_write = n
	_hist_count = n
	_last_sample = pos
	_hist_write %= HIST_MAX

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_steer(delta)
	if hold_heading > -900.0:
		desired_dir = Vector3(sin(hold_heading), 0.0, cos(hold_heading))
		input_boost = false

	# --- power ability timer ---
	if ability_left > 0.0:
		ability_left = maxf(0.0, ability_left - delta)
		if ability_left <= 0.0:
			ability = ""
	_halo.visible = ability_active("shield")

	# --- boost ---
	if input_boost and boost_meter > 0.05:
		boost_active = true
	if boost_active:
		boost_meter = maxf(0.0, boost_meter - delta)
		if boost_meter <= 0.0:
			boost_active = false
	else:
		boost_meter = minf(BOOST_MAX, boost_meter + delta * BOOST_REGEN)

	# --- steering: limited angular rate keeps the tube self-consistent ---
	var target_h := atan2(desired_dir.x, desired_dir.z)
	var speed_target := BASE_SPEED * (1.0 + clampf((length - 8.0) / 50.0, 0.0, 0.12))
	if boost_active:
		speed_target *= BOOST_MULT
	var max_rate := speed_target / MIN_TURN_RADIUS
	var rate := clampf(TURN_RATE_BASE * (0.8 if boost_active else 1.0), 0.5, max_rate)
	var dh := wrapf(target_h - heading, -PI, PI)
	heading += clampf(dh, -rate * delta, rate * delta)

	# --- accelerate & move ---
	speed_cur = move_toward(speed_cur, speed_target, (14.0 if boost_active else 7.0) * delta)
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	head_vel = fwd * speed_cur
	head_pos += head_vel * delta

	# --- record path ---
	if head_pos.distance_to(_last_sample) >= SPACING:
		_hist[_hist_write % HIST_MAX] = head_pos
		_hist_write += 1
		_hist_count = mini(_hist_count + 1, HIST_MAX)
		_last_sample = head_pos

	wave_phase += speed_cur * delta * 0.95

	_update_spine(delta)
	_length_animate(delta)
	_update_head(delta)

# ------------------------------------------------------------------ steering

func _steer(_delta: float) -> void:
	pass  # subclasses fill desired_dir / input_boost

# ------------------------------------------------------------------ abilities

func apply_ability(id: String, dur: float = -1.0) -> void:
	if not ABILITY_DUR.has(id):
		return
	ability = id
	_ability_dur = dur if dur > 0.0 else ABILITY_DUR[id]
	ability_left = _ability_dur

func ability_active(id: String) -> bool:
	return ability == id and ability_left > 0.0

func ability_frac() -> float:
	return clampf(ability_left / maxf(_ability_dur, 0.01), 0.0, 1.0) if ability != "" else 0.0

# ------------------------------------------------------------------ body sim

func _update_spine(delta: float) -> void:
	# decay the growth-response pulse (drives the body-radius bump in _radius_at)
	_pulse = maxf(0.0, _pulse - delta * 2.1)
	var ds := length / float(RING_COUNT - 1)
	var head := _hist_at(0)
	# Walk the recorded polyline from the head backwards, spacing stations by ds.
	var idx_seg := 0
	var seg_a := head
	var seg_b := _hist_at(1)
	var seg_used := 0.0
	_raw[0] = head
	for i in range(1, RING_COUNT):
		var need := ds * float(i)
		var guard := 0
		while seg_used + SPACING < need and idx_seg + 2 < HIST_MAX and guard < 4096:
			seg_used += SPACING
			idx_seg += 1
			seg_a = seg_b
			seg_b = _hist_at(idx_seg + 1)
			guard += 1
		var f := clampf((need - seg_used) / SPACING, 0.0, 1.0)
		_raw[i] = seg_a.lerp(seg_b, f)

	var body_r := _body_radius()
	var motion := clampf(speed_cur / BASE_SPEED, 0.10, 1.35)
	var k_wave := TAU / 5.2  # ~5.2 m serpentine wavelength

	for i in RING_COUNT:
		var i_a := maxi(i - 1, 0)
		var i_b := mini(i + 1, RING_COUNT - 1)
		var d3 := _raw[i_b] - _raw[i_a]
		d3.y = 0.0
		var dir_i := d3.normalized() if d3.length_squared() > 1e-8 else Vector3(0, 0, 1)
		var perp := Vector3(-dir_i.z, 0.0, dir_i.x)  # lateral
		_perp[i] = perp
		var t := float(i) / float(RING_COUNT - 1)
		# Traveling wave, head to tail. Amplitude grows toward the tail (real snakes).
		var amp := clampf(0.42 * pow(t, 1.18), 0.0, 0.5)
		var ph := wave_phase + wave_phase_off
		var sway := sin(float(i) * ds * k_wave - ph)
		# micro vertical ripple for organic feel
		var vsway := 0.05 * amp * sin(float(i) * ds * k_wave * 2.0 - ph * 0.6)
		var p := _raw[i] + perp * (amp * sway * motion) + Vector3.UP * vsway

		var r := _radius_at(i, body_r)
		var o := i * 4
		# Store head-relative (root-local) coordinates: the tube mesh hangs in
		# root-local space with the root anchored at the head.
		_spine[o] = p.x - head.x
		_spine[o + 1] = p.y - head.y
		_spine[o + 2] = p.z - head.z
		_spine[o + 3] = r

	# Root carries the mesh: anchor the local tube at the head position.
	global_position = head_pos

	# upload to GPU — stations map along WIDTH (x), sampled as vec2(t, 0.5)
	var bytes := _spine.to_byte_array()
	var img := Image.create_from_data(RING_COUNT, 1, false, Image.FORMAT_RGBAF, bytes)
	if _tex == null:
		_spine_img_cache = img
		_tex = ImageTexture.create_from_image(img)
		_mat.set_shader_parameter(&"u_spine", _tex)
	else:
		_tex.update(img)

	# driving uniforms
	_mat.set_shader_parameter(&"u_ds", ds)
	_mat.set_shader_parameter(&"u_len", length)
	_mat.set_shader_parameter(&"u_motion", motion)

	# collision stations (every `coll_stride`) — kept in WORLD space for the
	# match's spatial hash; convert back from local by adding the head position.
	coll_pos.clear()
	coll_r.clear()
	for i in range(0, RING_COUNT, coll_stride):
		var o := i * 4
		coll_pos.append(Vector3(
			_spine[o] + head.x,
			_spine[o + 1] + head.y,
			_spine[o + 2] + head.z))
		coll_r.append(_spine[o + 3] * 0.86)

var _spine_img_cache: Image = null

func _hist_at(steps_back: int) -> Vector3:
	return _hist[(_hist_write - 1 - steps_back + 2 * HIST_MAX) % HIST_MAX]

func _body_radius() -> float:
	# chunkier bodies read much better from the fixed top-down camera (§1)
	var r := clampf(0.56 + length * 0.0020, 0.56, 0.72)
	if is_boss:
		r *= 1.9
	return r

func _radius_at(i: int, body_r: float) -> float:
	var t := float(i) / float(RING_COUNT - 1)
	var neck := 0.72 + 0.28 * smoothstep(0.0, 0.06, t)   # slim behind head
	var r := body_r * neck
	# eating response: a brief thickening that starts at the head and rides back
	r *= 1.0 + 0.085 * _pulse * smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.55, 0.95, t))
	r *= 1.0 - 0.94 * smoothstep(0.80, 1.0, t)           # tail taper
	return maxf(r, 0.004)

func _length_animate(delta: float) -> void:
	length = move_toward(length, target_length, GROWTH_RATE * delta)

# ------------------------------------------------------------------ gameplay

func eat(kind: int, growth: float, score_value: int) -> void:
	score += score_value
	target_length = minf(max_length, target_length + growth)
	_mouth_open = 1.0
	_pulse = 1.0
	# Chaining orbs rewards a small boost refill — organic pacing incentive.
	boost_meter = minf(BOOST_MAX, boost_meter + 0.6)
	ate.emit(self, kind, score_value)

func eat_bite() -> void:
	# Eating animation (spec §4): quick head lunge + jaw snap. Called together
	# with the real eat event so the fruit vanishes into the bite.
	_lunge = 1.0
	_mouth_open = maxf(_mouth_open, 1.0)

func die(killer_name: String = "") -> void:
	if not alive:
		return
	alive = false
	died.emit(self, killer_name)

func head_fatal_grace_active() -> bool:
	# gameplay-clock based: on slow devices match_time runs slower than wall
	# time, so the spawn shield must expire in MATCH seconds, not wall seconds
	if match_world != null:
		return match_world.match_time - spawn_match_time < 2.5
	return Time.get_ticks_msec() - spawn_ms < 2500

func kill_count_add() -> void:
	kills += 1

func head_radius() -> float:
	return _body_radius() * 0.66

func debug_state() -> String:
	var mid := RING_COUNT / 2
	var tail := RING_COUNT - 1
	var s := "len=%.2f ds=%.4f " % [length, length / float(RING_COUNT - 1)]
	s += "st0=%s r0=%.3f " % [Vector3(_spine[0], _spine[1], _spine[2]), _spine[3]]
	s += "stmid=%s rmid=%.3f " % [Vector3(_spine[mid * 4], _spine[mid * 4 + 1], _spine[mid * 4 + 2]), _spine[mid * 4 + 3]]
	s += "sttail=%s rtail=%.3f " % [Vector3(_spine[tail * 4], _spine[tail * 4 + 1], _spine[tail * 4 + 2]), _spine[tail * 4 + 3]]
	var rmin := 99.0
	var rmax := 0.0
	for i in RING_COUNT:
		var r := _spine[i * 4 + 3]
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
	s += "rmin=%.3f rmax=%.3f hist=%d" % [rmin, rmax, _hist_count]
	return s

# ------------------------------------------------------------------ visuals

func _build_body() -> void:
	body_mi = MeshInstance3D.new()
	body_mi.name = "Body"
	var mesh := ArrayMesh.new()
	var sides := 15  # ring verts including duplicated seam — smoother silhouette
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	# Template tube authored in ROOT-LOCAL space, trailing +Z (behind the head;
	# the head rig is authored facing -Z). Real positions keep the mesh drawable
	# and sane; the vertex shader reshapes every ring along the live spine.
	var step := 0.03
	for i in RING_COUNT:
		for j in sides:
			var th: float = TAU * float(j) / float(sides - 1)
			var r := 0.38 - 0.28 * (float(i) / float(RING_COUNT))
			var n := Vector3(cos(th), sin(th) * 0.86, 0.0).normalized()
			verts.append(Vector3(n.x * r, n.y * r, float(i) * step))
			norms.append(n)
			uvs.append(Vector2(float(j) / float(sides - 1), float(i) * RING_TEXEL))
	for i in RING_COUNT - 1:
		for j in sides - 1:
			var a := i * sides + j
			var b := a + 1
			var c := (i + 1) * sides + j
			var d := c + 1
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# A long snake can curl anywhere around its head, so the cull volume must
	# cover the maximum body envelope (coarse but correct).
	mesh.custom_aabb = AABB(Vector3(-70.0, -4.0, -70.0), Vector3(140.0, 8.0, 140.0))

	if _shader == null:
		_shader = load("res://shaders/snake_body.gdshader")
		_scale_albedo = load("res://textures/snake_scales_albedo.png")
		_scale_normal = load("res://textures/snake_scales_normal.png")
	if _scale_albedo == null or _scale_normal == null:
		push_warning("Snake scale textures missing — falling back to flat shading")
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter(&"u_dorsal", dorsal)
	_mat.set_shader_parameter(&"u_accent", accent)
	_mat.set_shader_parameter(&"u_belly", belly)
	_mat.set_shader_parameter(&"u_seed", skin_seed)
	_mat.set_shader_parameter(&"u_pattern", float(pattern))
	_mat.set_shader_parameter(&"u_len", length)
	_mat.set_shader_parameter(&"u_rings", float(RING_COUNT))
	_mat.set_shader_parameter(&"u_texel", RING_TEXEL)
	# keep scale sizes believable as the body thickens (boss snakes use ×1.9)
	_mat.set_shader_parameter(&"u_rep_ar", 5.0 * (_body_radius() / 0.56))
	_mat.set_shader_parameter(&"u_tile_al", 0.62 * (_body_radius() / 0.56))
	_mat.set_shader_parameter(&"u_scale", _scale_albedo)
	_mat.set_shader_parameter(&"u_scale_n", _scale_normal)
	_mat.set_shader_parameter(&"u_rim", rim)
	_mat.set_shader_parameter(&"u_glow", 0.25 if is_boss else 0.0)
	body_mi.mesh = mesh
	body_mi.material_override = _mat
	body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Local-space child: the root itself follows the head each frame, so the
	# tube rides along with its anchor.
	body_mi.top_level = false
	body_mi.extra_cull_margin = 24.0
	add_child(body_mi)
	body_mi.global_transform = Transform3D.IDENTITY

func _build_head() -> void:
	var body_r := _body_radius()
	head_root = Node3D.new()
	head_root.name = "Head"
	add_child(head_root)

	# -- skull (elongated ellipsoid; authored facing -Z --
	var skull := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 18
	sm.rings = 10
	skull.mesh = sm
	skull.scale = Vector3(1.32, 0.95, 1.52)
	skull.position = Vector3(0, 0.02, 0.52)
	skull.material_override = _skin_mat(false, Vector2(3.0, 2.2))
	head_root.add_child(skull)

	# -- snout (tapered muzzle) --
	var snout := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = 0.5
	sm2.height = 1.0
	sm2.radial_segments = 16
	sm2.rings = 8
	snout.mesh = sm2
	snout.scale = Vector3(0.74, 0.60, 1.05)
	snout.position = Vector3(0, -0.05, -0.44)
	snout.material_override = _skin_mat(true, Vector2(3.4, 2.6))
	head_root.add_child(snout)

	# -- jaw (lower plate, pivots open when eating) --
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, -0.14, 0.26)
	head_root.add_child(_jaw)
	var jaw_m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.58, 0.14, 0.85)
	jaw_m.mesh = bm
	jaw_m.position = Vector3(0, 0.04, -0.40)
	jaw_m.material_override = _skin_mat(true, Vector2(2.8, 2.0))
	_jaw.add_child(jaw_m)

	# -- eyes: flush against the skull like a real snake, vertical slit pupils --
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.125
		em.height = 0.25
		em.radial_segments = 12
		em.rings = 8
		eye.mesh = em
		eye.position = Vector3(side * 0.26, 0.10, -0.44)
		eye.scale = Vector3(1.0, 0.9, 0.7)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.90, 0.60, 0.14)
		mat.metallic = 0.35
		mat.roughness = 0.12
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.22, 0.05)
		mat.emission_energy_multiplier = 0.5
		eye.material_override = mat
		_eye_mats.append(mat)
		head_root.add_child(eye)

		# vertical slit pupil (viper-like) — a squashed ellipsoid over the eye
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.055
		pm.height = 0.11
		pupil.mesh = pm
		pupil.position = Vector3(side * 0.305, 0.10, -0.525)
		pupil.scale = Vector3(0.55, 1.30, 0.42)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.02, 0.02, 0.03)
		pmat.roughness = 0.25
		pupil.material_override = pmat
		head_root.add_child(pupil)

		# specular glint
		var glint := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.018
		gm.height = 0.036
		glint.mesh = gm
		glint.position = Vector3(side * 0.30, 0.10, -0.475)
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(1, 1, 1)
		gmat.emission_enabled = true
		gmat.emission = Color(1, 1, 1)
		gmat.emission_energy_multiplier = 1.6
		glint.material_override = gmat
		head_root.add_child(glint)

		# nostrils
		var nostril := MeshInstance3D.new()
		var nm := SphereMesh.new()
		nm.radius = 0.03
		nm.height = 0.06
		nostril.mesh = nm
		nostril.position = Vector3(side * 0.15, 0.07, -1.02)
		var nmat := StandardMaterial3D.new()
		nmat.albedo_color = Color(0.05, 0.05, 0.06)
		nostril.material_override = nmat
		head_root.add_child(nostril)

	# -- forked tongue --
	_tongue = Node3D.new()
	_tongue.position = Vector3(0, -0.10, -1.02)
	head_root.add_child(_tongue)
	for side in [-1.0, 1.0]:
		var fork := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008
		cm.bottom_radius = 0.016
		cm.height = 0.55
		fork.mesh = cm
		fork.rotation = Vector3(PI / 2.0 + side * 0.10, side * 0.10, 0)
		fork.position = Vector3(side * 0.035, 0, -0.26)
		fork.scale = Vector3(1, 1, 1)
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.75, 0.12, 0.18)
		tmat.roughness = 0.5
		fork.material_override = tmat
		_tongue.add_child(fork)
	_tongue.scale = Vector3(1, 1, 0.01)

	sync_head_params(body_r)
	_flick_timer = randf_range(1.0, 4.0)

func _skin_mat(snout_flavor: bool, uv_cells: Vector2 = Vector2(2.6, 2.0)) -> StandardMaterial3D:
	# Head skin: SAME shared scale texture as the body, tinted by the head
	# gradient so the head-to-neck transition stays seamless (spec §2).
	var m := StandardMaterial3D.new()
	m.albedo_color = _head_tint(snout_flavor)
	if _scale_albedo != null:
		m.albedo_texture = _scale_albedo
		m.uv1_scale = Vector3(uv_cells.x, uv_cells.y, 1.0)
		if _scale_normal != null:
			m.normal_enabled = true
			m.normal_texture = _scale_normal
			m.normal_scale = 0.9
	m.roughness = 0.34
	m.metallic = 0.05
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim * 0.8
		m.rim_tint = 0.5
	_skin_mats.append([m, snout_flavor])
	return m

func set_rim(v: float) -> void:
	# live theme visibility pass: fresnel edge light on body + head
	rim = v
	if _mat != null:
		_mat.set_shader_parameter(&"u_rim", v)
	for rec in _skin_mats:
		var m: StandardMaterial3D = rec[0]
		m.rim_enabled = v > 0.0
		m.rim = v * 0.8
		m.rim_tint = 0.5
	for m2 in _eye_mats:
		m2.rim_enabled = v > 0.0
		m2.rim = v * 0.6
		m2.rim_tint = 0.6

func _head_tint(snout_flavor: bool) -> Color:
	# head matches the body base so the neck seam disappears from above
	return dorsal.lightened(0.06) if snout_flavor else dorsal

func apply_skin(d: Color, a: Color, b: Color, seed: float, pat: int = -1) -> void:
	# Live reskin: body shader params + stored head materials recolor in place.
	dorsal = d
	accent = a
	belly = b
	skin_seed = seed
	if pat >= 0:
		pattern = clampi(pat, 0, 4)
	if _mat != null:
		_mat.set_shader_parameter(&"u_dorsal", dorsal)
		_mat.set_shader_parameter(&"u_accent", accent)
		_mat.set_shader_parameter(&"u_belly", belly)
		_mat.set_shader_parameter(&"u_seed", skin_seed)
		_mat.set_shader_parameter(&"u_pattern", float(pattern))
	for rec in _skin_mats:
		(rec[0] as StandardMaterial3D).albedo_color = _head_tint(bool(rec[1]))

func sync_head_params(body_r: float) -> void:
	# Scale entire head rig with body radius so proportions stay believable
	# while growing. 0.82 factor keeps the skull width believable vs the neck.
	var s: float = (body_r / 0.56) * 0.82
	if head_root:
		head_root.scale = Vector3(s, s, s)
	# head cap elasticity handled in _update_head

func _update_head(delta: float) -> void:
	var body_r := _body_radius()
	sync_head_params(body_r)

	# Position & orient the head on the front of the spine.
	var p0 := Vector3(_spine[0], _spine[1], _spine[2])
	var p1 := Vector3(_spine[4], _spine[5], _spine[6])
	var fwd := (p0 - p1)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3(sin(heading), 0, cos(heading))
	var target_basis := Basis.looking_at(fwd, Vector3.UP)
	# subtle living head bob & breathing tilt (aligned with the traveling wave)
	var bob_yaw := sin(wave_phase * 0.5 + wave_phase_off) * 0.07
	var breathe := sin(Time.get_ticks_msec() * 0.0035 + wave_phase_off) * 0.022
	target_basis = target_basis.rotated(Vector3.UP, bob_yaw)
	target_basis = target_basis.rotated(target_basis.x, breathe)
	# Smooth ROTATION only (scale kept separate — Basis.slerp needs pure rotation).
	_head_rot = _head_rot.slerp(target_basis, clampf(13.0 * delta, 0.0, 1.0))
	var s: float = (body_r / 0.56) * 0.82
	var b := _head_rot.scaled(Vector3(s, s, s))
	# eat animation: quick forward lunge + jaw snap while the fruit flies in
	_lunge = maxf(0.0, _lunge - delta * 3.3)
	var lunge_q := 1.0 - _lunge
	var lunge_amt := sin(minf(lunge_q, 1.0) * PI) if _lunge > 0.0 else 0.0
	head_root.transform = Transform3D(b, p0 + fwd * (body_r * 0.22) + fwd * lunge_amt * body_r * 0.9)

	# mouth open/close (lunge adds a quick extra snap)
	if _mouth_open > 0.0:
		_mouth_open = maxf(0.0, _mouth_open - delta * 2.4)
	if _jaw:
		_jaw.rotation.x = _mouth_open * 0.62 + lunge_amt * 0.35

	# tongue flick cycle
	_flick_timer -= delta
	if _flick_timer <= 0.0:
		_flick_timer = randf_range(1.6, 4.5)
		_flick_phase = 0.0
	if _flick_phase >= 0.0:
		_flick_phase += delta * 6.0
		var ext := sin(minf(_flick_phase, PI))
		if _tongue:
			_tongue.scale = Vector3(1, 1, maxf(0.01, ext))
		if _flick_phase > PI:
			_flick_phase = -1.0
