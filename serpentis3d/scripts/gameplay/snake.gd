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
# Path history must cover the longest supported body with margin. 1440 samples
# × 0.075 m = 108 m: the boss can reach 92 m and still renders its tail.
const HIST_MAX := 1440
const MIN_LENGTH := 3.5
const GROWTH_RATE := 3.4        # visual growth speed (m/s toward target length)
const TURN_RATE_BASE := 3.6
const MIN_TURN_RADIUS := 1.05   # curvature guard: no tube self-intersection
const TURN_ACCEL := 55.0        # rad/s² of angular inertia: smooth S-curves, no snap
const BASE_SPEED := 4.6
# Fruit-driven speed progression. The speed rises smoothly from BASE_SPEED at
# spawn to SPEED_MAX by SPEED_RAMP_END metres, then NEVER rises again: eating
# past the cap only adds length + score (spec: balanced progression). Boost is
# the intentional temporary sprint mechanic and is applied on top afterwards.
const SPEED_MAX := 6.2
const SPEED_RAMP_START := 8.0
const SPEED_RAMP_END := 46.0
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
var max_length := 76.0

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
var _turn_vel := 0.0              # smoothed angular velocity (rad/s)
var _head_rot := Basis.IDENTITY    # smoothed pure-rotation basis of the head

# Mouth (world space). `mouth_pos` is refreshed with the head rig, `mouth_prev`
# is the previous eat-check sample: fruit collision sweeps the segment between
# them, so contact is judged at the jaws and a fast head can never skip a fruit.
var mouth_pos := Vector3.ZERO
var mouth_prev := Vector3.ZERO

var boost_active := false
var boost_meter := BOOST_MAX
var gulp_count := 0    # QA: visible swallow() count (one per landed fruit)

# --- power-orb abilities (Magnet Pulse / Shield) ---
const ABILITY_DUR := {"magnet": 5.0, "shield": 4.0}
var ability := ""
var ability_left := 0.0
var _ability_dur := 1.0
var _halo: MeshInstance3D
var _skin_mats: Array = []   # [StandardMaterial3D, snout_flavor: bool] — head parts that recolor on apply_skin
var _dark_mats: Array[StandardMaterial3D] = []   # crown/dorsal-darker parts, retinted with darkened dorsal

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
var _spine_img: Image = null   # reused upload buffer (allocated once)
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
var _bite_hold := 0.0             # jaw stays open while the fruit flies in
var _pulse := 0.0                 # growth response: brief body thickening (0..1)
var _lean := 0.0                  # roll into turns (body bank)
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
	speed_cur = base_speed()
	_turn_vel = 0.0
	boost_meter = BOOST_MAX
	spawn_ms = Time.get_ticks_msec()
	spawn_match_time = match_world.match_time if match_world != null else 0.0
	desired_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	if desired_dir.length_squared() < 0.1:
		desired_dir = Vector3(sin(heading), 0.0, cos(heading))

	# Fill the polyline with a straight tail extending BACKWARDS from the head.
	# The buffer's newest sample must be the head (index n-1): _hist_at(0)
	# walks back from there. The old head-at-index-0 fill made the whole tube
	# grow AHEAD of the snake and scrambled the tail until the ring wrapped.
	var back := -Vector3(dir.x, 0.0, dir.z).normalized()
	var n := mini(HIST_MAX, int(length / SPACING) + 4)
	for i in n:
		_hist[n - 1 - i] = pos + back * (float(i) * SPACING)
	_hist_write = n
	_hist_count = n
	_hist_write %= HIST_MAX
	_last_sample = pos
	mouth_pos = pos + Vector3(dir.x, 0.0, dir.z).normalized() * 0.55
	mouth_prev = mouth_pos

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
	var speed_target := base_speed()
	if boost_active:
		speed_target *= BOOST_MULT
	var max_rate := speed_target / MIN_TURN_RADIUS
	var rate := clampf(TURN_RATE_BASE * (0.82 if boost_active else 1.0), 0.5, max_rate)
	var dh := wrapf(target_h - heading, -PI, PI)
	# Angular inertia instead of an instant heading snap: small corrections are
	# proportional, hard turns saturate, and reversals roll through the body
	# as a real serpent's S-curve rather than a robotic pivot.
	var want_rate := clampf(dh * 8.0, -rate, rate)
	_turn_vel = move_toward(_turn_vel, want_rate, TURN_ACCEL * delta)
	var turn_step := _turn_vel * delta
	heading += turn_step
	# body roll into turns: snakes bank into corners (spec §3)
	_lean = lerpf(_lean, clampf(-_turn_vel * 0.10, -0.5, 0.5), 1.0 - exp(-8.0 * delta))

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

	_spine_tick += 1
	if spine_stride > 1 and not spine_full_rate and _spine_tick % spine_stride != 0:
		return
	# Off-player serpents on the phone tier rebuild+upload the spine tube at
	# half rate (the rebuild is the single largest sim cost); the trail history
	# and steering stay at the full rate so gameplay behavior is unchanged.
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
	# A body can never be sampled past the path it has actually travelled.
	# Normally movement outruns growth; the fallback keeps the tube intact if a
	# long snake is created/resized (boss spawn, dev harness, future modes).
	_ensure_history_path(length + SPACING * 2.0)
	var ds := length / float(RING_COUNT - 1)
	var head := _hist_at(0)
	# Walk the recorded polyline from the head backwards, spacing stations by ds.
	# The walk is bounded by the VALID sample count, never by the array size —
	# reading unwritten ring slots produced zero-length spikes and ate the tail.
	var seg_limit := maxi(0, _hist_count - 2)
	var idx_seg := 0
	var seg_a := head
	var seg_b := _hist_at(1)
	var seg_used := 0.0
	_raw[0] = head
	for i in range(1, RING_COUNT):
		var need := ds * float(i)
		var guard := 0
		while seg_used + SPACING < need and idx_seg < seg_limit and guard < 4096:
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
	# bank the body into turns (roll around the spine axis) for natural motion
	if body_mi != null:
		body_mi.rotation.z = _lean * 0.30

	# upload to GPU — stations map along WIDTH (x), sampled as vec2(t, 0.5)
	# The Image + texture are allocated once; set_data overwrite keeps a
	# single reused buffer (10 serpents × 6 KB per frame otherwise churns GC).
	var bytes := _spine.to_byte_array()
	if _spine_img == null:
		_spine_img = Image.create_from_data(RING_COUNT, 1, false, Image.FORMAT_RGBAF, bytes)
	else:
		_spine_img.set_data(RING_COUNT, 1, false, Image.FORMAT_RGBAF, bytes)
	if _tex == null:
		_tex = ImageTexture.create_from_image(_spine_img)
		_mat.set_shader_parameter(&"u_spine", _tex)
	else:
		_tex.update(_spine_img)

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

func _hist_at(steps_back: int) -> Vector3:
	return _hist[(_hist_write - 1 - steps_back + 2 * HIST_MAX) % HIST_MAX]

## Extend the straight tail sample chain when a body is longer than the path
## already recorded (long spawns, boss growth, dev length changes). Samples are
## appended behind the OLDEST point along its incoming direction, so the
## rendered tail keeps the correct length and spacing instead of reading zeros.
func _ensure_history_path(need_path: float) -> void:
	if _hist_count < 2:
		return
	var have := float(_hist_count - 1) * SPACING
	if have >= need_path:
		return
	var oldest := _hist_at(_hist_count - 1)
	var older := _hist_at(_hist_count - 2)
	var back := oldest - older
	back.y = 0.0
	if back.length_squared() < 1e-8:
		back = Vector3(-sin(heading), 0.0, -cos(heading))
	back = back.normalized()
	var edge := oldest
	var guard := 0
	while have + 0.0001 < need_path and _hist_count < HIST_MAX and guard < (HIST_MAX * 2):
		edge += back * SPACING
		_hist[_hist_write % HIST_MAX] = edge
		_hist_write += 1
		_hist_count += 1
		have += SPACING
		guard += 1

## Optional per-instance girth multiplier (menu serpents slim down; gameplay
## keeps the chunky top-down proportions). 1.0 = untouched game behavior.
var girth := 1.0
# Spine-rebuild stride: 1 = every physics tick (players + close serpents);
# >1 = every Nth tick (phone-tier AI serpents — halves the biggest sim cost).
var spine_stride := 1
var spine_full_rate := false
var _spine_tick := 0

func _body_radius() -> float:
	# chunkier bodies read much better from the fixed top-down camera (§1)
	var r := clampf(0.56 + length * 0.0020, 0.56, 0.72) * girth
	if is_boss:
		r *= 1.9
	return r

## Fruit-driven cruise speed. Smooth, capped, frame-rate independent: the ramp
## is a function of LENGTH (which itself grows smoothly), never of frames.
func base_speed() -> float:
	var t := smoothstep(SPEED_RAMP_START, SPEED_RAMP_END, length)
	return lerpf(BASE_SPEED, SPEED_MAX, t)

func _radius_at(i: int, body_r: float) -> float:
	var t := float(i) / float(RING_COUNT - 1)
	# slim only right behind the skull (a FIXED fraction, not 6% of a 76 m body)
	var neck := 0.86 + 0.14 * smoothstep(0.0, 0.022, t)
	var r := body_r * neck
	# eating response: a brief thickening that starts at the head and rides back
	r *= 1.0 + 0.085 * _pulse * smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.55, 0.95, t))
	# Tail taper: the last 12% of the body narrows, but the tip keeps a real,
	# visible girth. The old 20%-long taper down to 6% made a very long snake's
	# tail fade to ~1 px from the top-down camera and read as "missing".
	r *= 1.0 - 0.88 * smoothstep(0.88, 1.0, t)
	return maxf(r, body_r * 0.10)

func _length_animate(delta: float) -> void:
	length = move_toward(length, target_length, GROWTH_RATE * delta)

# ------------------------------------------------------------------ gameplay

func eat(kind: int, growth: float, score_value: int) -> void:
	score += score_value
	target_length = minf(max_length, target_length + growth)
	# Chaining orbs rewards a small boost refill — organic pacing incentive.
	boost_meter = minf(BOOST_MAX, boost_meter + 0.6)
	ate.emit(self, kind, score_value)

func eat_bite() -> void:
	# Bite animation, played at the exact contact frame: head lunges, jaws open
	# and stay open while the fruit is drawn in, then snap shut in _update_head.
	_lunge = 1.0
	_bite_hold = 0.11
	_mouth_open = 1.0

func swallow() -> void:
	# Called when the fruit actually lands in the mouth (not at first contact):
	# the visible gulp travels down the neck and the jaw settles.
	_pulse = 1.0
	_lunge = maxf(_lunge, 0.30)
	gulp_count += 1

## Radius around the MOUTH at which a fruit counts as bitten. Scaled with the
## head so big serpents don't swallow fruit with the back of their skull.
func mouth_reach() -> float:
	return 0.24 + head_radius() * 0.35

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
	# cover the maximum body envelope (1440 samples = 108 m of maximum body).
	mesh.custom_aabb = AABB(Vector3(-112.0, -5.0, -112.0), Vector3(224.0, 10.0, 224.0))

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
	skull.scale = Vector3(1.42, 0.95, 1.52)
	skull.position = Vector3(0, 0.02, 0.52)
	skull.material_override = _skin_mat(false, Vector2(3.0, 2.2))
	head_root.add_child(skull)

	# -- crown plate: the darker scaled top of the head, what a top-down
	#    camera actually sees; separates the head from the neck seam
	var crown := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.5
	cm.height = 1.0
	cm.radial_segments = 14
	cm.rings = 7
	crown.mesh = cm
	crown.scale = Vector3(1.10, 0.34, 1.34)
	crown.position = Vector3(0, 0.30, 0.10)
	var cm_mat := _skin_mat(false, Vector2(2.2, 1.6))
	cm_mat.albedo_color = dorsal.darkened(0.42)
	_dark_mats.append(cm_mat)
	crown.material_override = cm_mat
	head_root.add_child(crown)

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
		em.radius = 0.165
		em.height = 0.33
		em.radial_segments = 12
		em.rings = 8
		eye.mesh = em
		# higher and wider: eyes must be visible from the top-down camera
		eye.position = Vector3(side * 0.30, 0.16, -0.44)
		eye.scale = Vector3(1.0, 0.9, 0.55)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.90, 0.60, 0.14)
		mat.metallic = 0.35
		mat.roughness = 0.12
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.22, 0.05)
		mat.emission_energy_multiplier = 0.7
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
		var fm := CylinderMesh.new()
		fm.top_radius = 0.008
		fm.bottom_radius = 0.016
		fm.height = 0.55
		fork.mesh = fm
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

## Raw body shader material (used by the menu scene to dim distant serpents).
func get_body_material() -> ShaderMaterial:
	return _mat

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
	for dm in _dark_mats:
		dm.albedo_color = dorsal.darkened(0.42)

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
	var bob_yaw := sin(wave_phase * 0.5 + wave_phase_off) * 0.05
	# head leads slightly into the turn: snakes look where they are going
	bob_yaw += clampf(_turn_vel * 0.045, -0.16, 0.16)
	var breathe := sin(Time.get_ticks_msec() * 0.0035 + wave_phase_off) * 0.022
	target_basis = target_basis.rotated(Vector3.UP, bob_yaw)
	target_basis = target_basis.rotated(target_basis.x, breathe)
	# Smooth ROTATION only (scale kept separate — Basis.slerp needs pure rotation).
	_head_rot = _head_rot.slerp(target_basis, clampf(13.0 * delta, 0.0, 1.0))
	var s: float = (body_r / 0.56) * 0.82
	# bank the head into turns (roll around its own forward axis)
	var hb := _head_rot.rotated(Vector3(0, 0, -1), _lean * 0.35)
	var b := hb.scaled(Vector3(s, s, s))
	# eat animation: quick forward lunge + jaw snap while the fruit flies in
	_lunge = maxf(0.0, _lunge - delta * 3.3)
	var lunge_q := 1.0 - _lunge
	var lunge_amt := sin(minf(lunge_q, 1.0) * PI) if _lunge > 0.0 else 0.0
	head_root.transform = Transform3D(b, p0 + fwd * (body_r * 0.22) + fwd * lunge_amt * body_r * 0.9)
	# Mouth anchor = the front of the jaw in world space. Eat collision is
	# measured HERE, not at the head origin (which sits under the skull).
	mouth_pos = head_root.global_transform * Vector3(0.0, -0.06, -0.82)

	# Jaw: hold open while the fruit flies in, then snap shut quickly. The old
	# decay started closing the instant the fruit was touched and kept it open
	# afterwards, which read as chewing thin air.
	if _bite_hold > 0.0:
		_bite_hold = maxf(0.0, _bite_hold - delta)
		_mouth_open = maxf(_mouth_open, 0.92)
	elif _mouth_open > 0.0:
		_mouth_open = maxf(0.0, _mouth_open - delta * 7.0)
	if _jaw:
		_jaw.rotation.x = _mouth_open * 0.58 + lunge_amt * 0.22

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
