class_name PlayerSnake
extends Snake
## Player-controlled snake: steer toward pointer (or keys), boost via Space/Left Mouse.

var _key_yaw := 0.0
var autopilot := false        # dev autoplay: seek food, avoid walls, live long

func _ready() -> void:
	is_player = true
	super._ready()

func _steer(delta: float) -> void:
	if autopilot:
		_autopilot_steer()
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d()

	# --- pointer steering (mouse or emulated touch) ---
	var off := Vector2.ZERO
	if cam:
		var mp := vp.get_mouse_position()
		var vs := vp.get_visible_rect().size
		var center := vs * 0.5
		off = (mp - center) / vs.y
		off.x = clampf(off.x, -0.5, 0.5)
		off.y = clampf(off.y, -0.5, 0.5)
		if off.length() < 0.065:
			off = Vector2.ZERO

	var desired := Vector3.ZERO
	if cam and off != Vector2.ZERO:
		var basis := cam.global_transform.basis
		var right := basis.x
		right.y = 0.0
		right = right.normalized()
		var fwd := -basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		desired = (right * off.x + fwd * (-off.y))
		desired.y = 0.0
		desired = desired.normalized()
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
		if desired.length_squared() < 0.01:
			var fwd := Vector3(sin(heading), 0.0, cos(heading))
			desired = fwd.rotated(Vector3.UP, 0.1)
		input_boost = false
		desired_dir = Vector3(desired.x, 0.0, desired.z).normalized()
