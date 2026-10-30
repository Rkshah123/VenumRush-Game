class_name PlayerSnake
extends Snake
## Player-controlled snake: steer toward pointer, WASD/arrow keys, or the
## PUBG-style virtual joystick. Boost via Space / Left Mouse / a second finger.
## Android touch: the joystick (bottom-left) steers; a drag anywhere else steers
## toward the finger (relative to screen center, same projection as the mouse);
## a SECOND finger anywhere = boost.

var _keys_dir := Vector2.ZERO   # WASD/arrows, screen space (x right, y up)
var _keys_held := {}            # keycode -> true (avoids press/release cancels)
var _key_mode := false          # desktop: keys OWN steering until the next key
var autopilot := false        # dev autoplay: seek food, avoid walls, live long

# autopilot anti-loop watchdog (QA harness only — real players never steer here)
var _ap_loop_t := 0.0
var _ap_loop_x := Vector3.INF
var _ap_loop_turn := 0.0
var _ap_loop_h := 0.0
var _ap_kick := 0.0
var _ap_kick_sign := 1.0
var ap_loops := 0             # QA counter

# --- touch state (mobile) ---
var touch_sim := false        # dev --touch-test: force the touch code path on desktop
var _is_mobile := false
var _touch_pos := Vector2.ZERO
var _touch_has := false
var _touch_ids := {}          # touch index -> alive (second finger = boost)
var _idle_t := 0.0            # time since the last steering input
var joy_active := false       # virtual joystick currently held
var joy_vec := Vector2.ZERO   # joystick direction (screen space, y up)
var no_idle_drift := false    # virtual joystick is active — player steers
var keyboard_only := false    # dev QA: ignore pointer/touch, keys only

func _ready() -> void:
	is_player = true
	_is_mobile = OS.has_feature("android") or OS.has_feature("ios") or touch_sim
	super._ready()

func _input(event: InputEvent) -> void:
	# Keyboard direction keys (WASD + arrows) are captured in the RAW input
	# phase so focused UI controls can never swallow them — this is why
	# Up/Down used to "do nothing" after clicking through the menus.
	if autopilot or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if _key_dir_for(k.keycode) == Vector2.ZERO:
		return
	if _text_field_focused():
		return          # never steer while the player is typing somewhere
	_key_input(event)
	if k.pressed:
		get_viewport().set_input_as_handled()   # no scrolling / focus moves

## True when a text-entry control owns the keyboard (defensive: no text fields
## in the game today, but movement keys must never fight typing).
func _text_field_focused() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is CodeEdit

func _unhandled_input(event: InputEvent) -> void:
	if autopilot:
		return
	# Keyboard direction keys work in BOTH desktop and mobile layouts (and on
	# a connected keyboard on Android) — handled before the touch branch.
	if event is InputEventKey:
		_key_input(event)
		if event.is_pressed() and (event as InputEventKey).keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D]:
			get_viewport().set_input_as_handled()   # never scroll / move focus
		return
	if not _is_mobile:
		return
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_touch_ids[(event as InputEventScreenTouch).index] = true
			_touch_pos = (event as InputEventScreenTouch).position
			_touch_has = true
			_idle_t = 0.0
		else:
			_touch_ids.erase((event as InputEventScreenTouch).index)
			if _touch_ids.is_empty():
				_touch_has = false
	elif event is InputEventScreenDrag:
		_touch_pos = (event as InputEventScreenDrag).position
		_touch_has = true
		_idle_t = 0.0

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
		_autopilot_steer(delta)
		return
	var cam := get_viewport().get_camera_3d()
	var keys := _keys_dir

	if _is_mobile and keys == Vector2.ZERO and not keyboard_only:
		# PUBG-style virtual joystick (mobile 2D): while a finger holds the
		# stick it steers; otherwise the classic drag-steer path runs. A
		# SECOND finger anywhere still boosts (spec section 2).
		var off := _steer_offset_from(_touch_pos, cam) if _touch_has and cam else Vector2.ZERO
		if joy_active and cam:
			if joy_vec == Vector2.ZERO:
				desired_dir = Vector3(sin(heading), 0.0, cos(heading))
			else:
				desired_dir = _screen_offset_to_dir(Vector2(joy_vec.x, -joy_vec.y), cam)
		elif cam and off != Vector2.ZERO:
			desired_dir = _screen_offset_to_dir(off, cam)
		elif cam:
			# Idle drift: carve a wide arena-safe arc so an untouched phone
			# never drives straight into a wall. Never while the virtual
			# joystick is available - there the player is in charge and an
			# auto-arc would fight them (and looked like "circling").
			_idle_t += delta
			if _idle_t > 1.2 and not no_idle_drift:
				desired_dir = _idle_drift_dir(delta)
				input_boost = _touch_ids.size() >= 2
				return
			desired_dir = Vector3(sin(heading), 0.0, cos(heading))
		input_boost = _touch_ids.size() >= 2
		return

	# --- desktop (or a keyboard on a phone): pointer OR direction keys ---
	# KEYBOARD PERSISTENCE (desktop fix): once a direction key is used, keys
	# OWN the steering — releasing the key keeps the snake crawling in the
	# chosen direction until ANOTHER direction key is pressed. Before this
	# fix, releasing a key fell through to the mouse-pointer branch, so the
	# snake snapped back toward wherever the cursor was ("moved briefly, then
	# crawled straight again"). The mouse still steers if it is used BEFORE
	# any key; a key press always takes priority from then on. Mobile touch
	# steering is untouched (its own branch above).
	var desired := Vector3.ZERO
	var off := Vector2.ZERO
	if cam and not keyboard_only:
		off = _steer_offset_from(get_viewport().get_mouse_position(), cam)

	# Direction keys are ABSOLUTE screen-relative directions (never a relative
	# yaw offset - that made the snake circle forever). W/Up = up-screen,
	# S/Down = down-screen, A/Left = left, D/Right = right.
	if keys != Vector2.ZERO:
		_key_mode = true
		if cam:
			desired = _screen_offset_to_dir(Vector2(keys.x, -keys.y) * 0.5, cam)
		else:
			desired = Vector3(keys.x, 0.0, -keys.y)
	elif _key_mode:
		pass   # persist the last chosen direction — desired_dir stays as-is
	elif cam and off != Vector2.ZERO:
		desired = _screen_offset_to_dir(off, cam)

	if desired != Vector3.ZERO:
		desired_dir = desired if desired.length_squared() > 0.9 else desired.normalized()

	if _is_mobile:
		input_boost = _touch_ids.size() >= 2
	else:
		input_boost = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

## Key events -> absolute screen-space direction (x right, y up). Event-based
## so it works regardless of focus quirks and can be driven by QA tests.
func _key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or _text_field_focused():
		return
	var k := event as InputEventKey
	var d := _key_dir_for(k.keycode)
	if d == Vector2.ZERO:
		return
	if k.echo:
		return
	_key_set(k.keycode, k.pressed)

func _key_dir_for(code: int) -> Vector2:
	match code:
		KEY_A, KEY_LEFT:
			return Vector2(-1, 0)
		KEY_D, KEY_RIGHT:
			return Vector2(1, 0)
		KEY_W, KEY_UP:
			return Vector2(0, 1)
		KEY_S, KEY_DOWN:
			return Vector2(0, -1)
	return Vector2.ZERO

func _key_set(code: int, down: bool) -> void:
	var d := _key_dir_for(code)
	if d == Vector2.ZERO:
		return
	# Per-key state, not accumulation: holding A and Left together and
	# releasing one must not cancel the other.
	if down:
		_keys_held[code] = true
		_idle_t = 0.0
	else:
		_keys_held.erase(code)
	var sum := Vector2.ZERO
	for c in _keys_held:
		sum += _key_dir_for(c)
	_keys_dir = sum.limit_length(1.0)

## QA hook: press/release a key by code through the real input path.
func press_key(code: int, down: bool = true) -> void:
	_key_set(code, down)

func clear_keys() -> void:
	_keys_held.clear()
	_keys_dir = Vector2.ZERO
	_key_mode = false          # dev harness / respawn: steering ownership resets

func spawn(pos: Vector3, dir: Vector3, body_len: float) -> void:
	# fresh life: the last life's key direction must not leak into this one
	_key_mode = false
	super.spawn(pos, dir, body_len)

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
	# Screen-offset -> world direction. off.y < 0 = pointer BELOW center =
	# steer toward camera-forward (snake moves down-screen); drag up = steer
	# away from the camera (toward the horizon). The straight-down 2D camera
	# has a degenerate view vector (looking straight down), so fall back to
	# the camera's screen-up axis for the "forward" ground direction.
	var basis := cam.global_transform.basis
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	var fwd := -basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = basis.y          # top-down: screen-up axis on the ground plane
		fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3(0, 0, 1)
	var d := right * off.x + fwd * (-off.y)
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.9 else d

func _autopilot_steer(delta: float) -> void:
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
		_input_loop_guard(delta, desired)
		if _ap_kick > 0.0:
			_ap_kick -= delta
			var fwd := Vector3(sin(heading), 0.0, cos(heading))
			desired = fwd.rotated(Vector3.UP, _ap_kick_sign * 1.15) * 1.5 + desired * 0.4
		input_boost = false
		desired_dir = Vector3(desired.x, 0.0, desired.z).normalized()

## Same anti-orbit cure as AISnake, for the QA autopilot brain only.
func _input_loop_guard(delta: float, desired: Vector3) -> void:
	if _ap_loop_x == Vector3.INF:
		_ap_loop_x = head_pos
		_ap_loop_h = heading
		return
	_ap_loop_t += delta
	_ap_loop_turn += absf(wrapf(heading - _ap_loop_h, -PI, PI))
	_ap_loop_h = heading
	if _ap_loop_t < 3.0:
		return
	var moved := head_pos.distance_to(_ap_loop_x)
	var expected := maxf(speed_cur, base_speed()) * _ap_loop_t
	var spinning := _ap_loop_turn > TAU * 0.75
	var beached := moved < expected * 0.12
	_ap_loop_t = 0.0
	_ap_loop_x = head_pos
	_ap_loop_turn = 0.0
	if _ap_kick > 0.0:
		return
	if (spinning and moved < expected * 0.35) or beached:
		_ap_kick = 1.6
		_ap_kick_sign = 1.0 if randf() < 0.5 else -1.0
		ap_loops += 1
