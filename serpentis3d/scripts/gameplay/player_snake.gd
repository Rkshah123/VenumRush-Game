class_name PlayerSnake
extends Snake
## Player-controlled snake: steer toward pointer (or keys), boost via Space/Left Mouse.
## Android touch: ONE finger drag steers toward the finger (relative to screen
## center, same projection as the mouse); a SECOND finger anywhere = boost.

var _key_yaw := 0.0
var autopilot := false        # dev autoplay: seek food, avoid walls, live long

# --- touch state (mobile) ---
var touch_sim := false        # dev --touch-test: force the touch code path on desktop
var _is_mobile := false
var _touch_pos := Vector2.ZERO
var _touch_has := false
var _touch_ids := {}          # touch index -> alive (second finger = boost)
var _idle_t := 0.0            # time since the last steering input

func _ready() -> void:
	is_player = true
	_is_mobile = OS.has_feature("android") or OS.has_feature("ios") or touch_sim
	super._ready()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_mobile or autopilot:
		return
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_touch_ids[(event as InputEventScreenTouch).index] = true
			_touch_pos = (event as InputEventScreenTouch).position
			_touch_has = true
		else:
			_touch_ids.erase((event as InputEventScreenTouch).index)
			if _touch_ids.is_empty():
				_touch_has = false
	elif event is InputEventScreenDrag:
		_touch_pos = (event as InputEventScreenDrag).position
		_touch_has = true

func _steer_offset_from(p: Vector2, cam: Camera3D) -> Vector2:
	# Shared projection: screen offset from center, clamped, dead-zoned.
	var vs := get_viewport().get_visible_rect().size
	var off := (p - vs * 0.5) / vs.y
	off.x = clampf(off.x, -0.5, 0.5)
	off.y = clampf(off.y, -0.5, 0.5)
	if off.length() < 0.065:
		return Vector2.ZERO
	return off

func _steer(delta: float) -> void:
	if autopilot:
		_autopilot_steer()
		return
	var cam := get_viewport().get_camera_3d()

	# --- steering ---
	var desired := Vector3.ZERO
	if _is_mobile:
		# touch steering: finger position is the pointer; no finger or dead
		# zone = hold straight ahead (keeps the snake from fishing the last
		# command forever)
		var off := _steer_offset_from(_touch_pos, cam) if _touch_has and cam else Vector2.ZERO
		if off != Vector2.ZERO:
			_idle_t = 0.0
			desired_dir = _screen_offset_to_dir(off, cam)
		else:
			# Idle drift: while the fingers have not found the screen yet, carve
			# a wide arena-safe arc (curving toward the center near the wall)
			# instead of driving a straight line into the snake ahead.
			_idle_t += delta
			if _idle_t > 1.2:
				desired_dir = _idle_drift_dir(delta)
				input_boost = _touch_ids.size() >= 2
				return
			desired_dir = Vector3(sin(heading), 0.0, cos(heading))
		input_boost = _touch_ids.size() >= 2
		return

	var off := Vector2.ZERO
	if cam:
		off = _steer_offset_from(get_viewport().get_mouse_position(), cam)

	if cam and off != Vector2.ZERO:
		desired = _screen_offset_to_dir(off, cam)
	else:
		# keyboard fallback (A/D) if no camera or pointer centered
		var k := 0.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			k -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			k += 1.0
		_key_yaw = wrapf(_key_yaw - k * 2.4 * delta, -PI, PI)
		desired = Vector3(sin(heading + _key_yaw), 0.0, cos(heading + _key_yaw))

	if desired != Vector3.ZERO:
		desired_dir = desired if desired.length_squared() > 0.9 else desired.normalized()

	input_boost = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _idle_drift_dir(delta: float) -> Vector3:
	# Wide, gentle arc that mostly follows the spawn flow (everyone slides
	# tangentially, so a parallel arc keeps a constant gap); the curve leans
	# toward the arena center as the wall closes in.
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var radial := head_pos.length()
	var turn := 0.4
	if match_world != null and radial > match_world.arena_radius * 0.55:
		var inward := -head_pos
		inward.y = 0.0
		if inward.length_squared() > 0.01:
			inward = inward.normalized()
			var cross_y := fwd.x * inward.z - fwd.z * inward.x
			turn = 0.7 * (1.0 if cross_y >= 0.0 else -1.0)
	return fwd.rotated(Vector3.UP, turn * delta)

func _screen_offset_to_dir(off: Vector2, cam: Camera3D) -> Vector3:
	# Screen-offset → world direction. off.y < 0 = pointer BELOW center =
	# steer toward camera-forward (snake moves down-screen); drag up = steer
	# away from the camera (toward the horizon).
	var basis := cam.global_transform.basis
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var d := right * off.x + fwd * (-off.y)
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.9 else d

func _autopilot_steer() -> void:
	# Dev-brain for automated QA runs: nearest food, wall urgency, gentle rallies.
	var desired := Vector3.ZERO
	if match_world != null:
		var best := Vector3.INF
		var best_d := 34.0
		for f in match_world.food_positions():
			var d := head_pos.distance_to(f)
			if d < best_d:
				best_d = d
				best = f
		if best != Vector3.INF:
			desired = best - head_pos
		var R: float = match_world.arena_radius
		var radial := head_pos.length()
		if radial > R - 7.5:
			desired += (-head_pos).normalized() * (1.0 + clampf((radial - (R - 7.5)) / 6.0, 0.0, 1.0) * 2.4)
		# boulders are real cover now — steer around them
		var probe := head_pos + Vector3(sin(heading), 0.0, cos(heading)) * (speed_cur * 1.2 + 2.5)
		for ob in match_world.obstacles:
			var d: Vector3 = probe - (ob["pos"] as Vector3)
			d.y = 0.0
			var rr: float = float(ob["r"]) + 2.2
			if d.length_squared() < rr * rr:
				if d.length_squared() < 0.02:
					d = probe * -1.0
				desired += d.normalized() * (1.2 + (rr - d.length()) * 0.55)
		# other snakes' bodies are lethal — dodge nearby stations
		if match_world != null:
			for st in match_world.nearby_stations(head_pos, 7.0, id):
				var sd: Vector3 = head_pos - (st["pos"] as Vector3)
				sd.y = 0.0
				var dd := sd.length()
				if dd < 0.05:
					sd = -probe
					dd = 1.0
				desired += sd.normalized() * (2.2 + (7.0 - dd) * 0.5)
		if desired.length_squared() < 0.01:
			var fwd := Vector3(sin(heading), 0.0, cos(heading))
			desired = fwd.rotated(Vector3.UP, 0.1)
		input_boost = false
		desired_dir = Vector3(desired.x, 0.0, desired.z).normalized()
