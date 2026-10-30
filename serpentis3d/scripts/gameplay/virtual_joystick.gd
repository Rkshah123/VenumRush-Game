class_name TouchJoystick
extends Control
## VenomRush — mobile touch steering stick (spec: continuous 360° heading).
##
## Behaviour the spec asks for, all of it steering the EXISTING heading system
## (the snake never teleports, it turns toward the stick at its normal rate):
##   * 360° continuous — the direction is the raw vector from the stick center,
##     so 15°, 30°, 45°, 60°, 75° and every in-between angle work; nothing is
##     snapped to 4 or 8 directions.
##   * Touch ANYWHERE — the first finger down materializes the stick at that
##     point. The screen stays clean while steering is not needed; there is no
##     fixed bottom-left resting ring.
##   * Release keeps going — on release the stick disappears and `last_dir` is
##     kept. PlayerSnake simply holds its current heading, so the snake never
##     stops and never snaps back to a default direction.
##   * UI-safe — taps that land on a HUD control (pause button, dialogs) are
##     left to the UI via the `ui_blocker` callback.
##
## Look: a thin ring with a solid round knob and a soft tint, drawn only while
## the finger is down, so the game board stays readable when the stick is not
## in use (inspired by the reference frame, not copied).

signal vector_changed(v: Vector2)

const BASE_RADIUS := 108.0      # px at scale 1 (outer ring)
const KNOB_RADIUS := 40.0       # px at scale 1
const DEAD := 0.12              # below this magnitude the heading is simply held
const MARGIN := 26.0

var value := Vector2.ZERO      # live stick direction (y UP, magnitude 0..1)
var last_dir := Vector2.ZERO   # last valid direction — kept after release
var active := false
var enabled := false
var force_joystick_dev := false   # dev/QA: show the stick on desktop too
var ui_scale := 1.0
var ui_blocker := Callable()      # HUD: blocks_touch(global_pos) -> bool

var _touch_id := -99           # -99 = free, >=0 touch index, -2 mouse
var _knob := Vector2.ZERO      # knob offset from the active base (px)
var _safe_left := 0.0
var _safe_bottom := 0.0
var _rest_center := Vector2.ZERO   # fallback base when no finger is down
var _base_center := Vector2.ZERO   # active base — follows the finger
var _alpha := 0.0              # 0 hidden -> 1 fully visible
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # manual hit-testing
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	queue_redraw()

func configure(scale_px: float, safe_left: float, safe_bottom: float) -> void:
	ui_scale = clampf(scale_px, 0.8, 1.9)
	_safe_left = safe_left
	_safe_bottom = safe_bottom
	var r := BASE_RADIUS * ui_scale
	var vs := size
	if vs.y < 1.0:
		vs = get_viewport_rect().size
	_rest_center = Vector2(safe_left + r + MARGIN * ui_scale,
		vs.y - safe_bottom - r - MARGIN * ui_scale)
	if not active:
		_base_center = _rest_center
	queue_redraw()

func radius() -> float:
	return BASE_RADIUS * ui_scale

func center() -> Vector2:
	return _base_center if active or _base_center != Vector2.ZERO else _rest_center

## Heading the player asked for, even after the finger is gone: the live value
## while held, otherwise the last non-deadzone direction.
func held_dir() -> Vector2:
	return value if value != Vector2.ZERO else last_dir

func _to_local(p: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * p

func _blocked(global_pos: Vector2) -> bool:
	return ui_blocker.is_valid() and bool(ui_blocker.call(global_pos))

# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_id == -99:
			if _blocked(t.position):
				return                       # that tap belongs to a HUD control
			_touch_id = t.index
			_grab(_to_local(t.position))
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _touch_id:
			_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if active and d.index == _touch_id:
			_update_from(_to_local(d.position))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not OS.has_feature("android"):
		# desktop parity (dev / touchpad): left button drives the stick. Godot
		# turns a synthetic touch into a mouse event first, and in the headless
		# test rig that mouse event lands FAR outside the viewport; ignoring
		# those keeps --touch-test/--dir-test exercising the real touch path.
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.position.x >= 0.0 \
				and mb.position.y >= 0.0 \
				and mb.position.x <= get_viewport_rect().size.x \
				and mb.position.y <= get_viewport_rect().size.y:
			if mb.pressed and _touch_id == -99:
				if _blocked(mb.position):
					return
				_touch_id = -2
				_grab(_to_local(mb.position))
			elif not mb.pressed and _touch_id == -2:
				_release()
	elif event is InputEventMouseMotion and _touch_id == -2 and active:
		_update_from(_to_local((event as InputEventMouseMotion).position))
		get_viewport().set_input_as_handled()

## The stick materializes under the finger wherever that is (PUBG-style
## floating stick), so players never have to reach for a persistent ring.
## The screen remains free of controls until this first finger lands.
func _grab(local: Vector2) -> void:
	_base_center = local
	_knob = Vector2.ZERO
	value = Vector2.ZERO
	active = true
	_alpha = 1.0
	_update_from(local)
	queue_redraw()

## Screen point -> steering direction. Y is flipped here because screen space
## grows downward while steering space (and WASD) grows upward.
func _update_from(local: Vector2) -> void:
	var maxr := radius() * 0.80
	var off := local - center()
	if off.length() > maxr:
		off = off.normalized() * maxr
	_knob = off
	var v := Vector2(off.x, -off.y) / maxr
	var mag := v.length()
	if mag < DEAD:
		value = Vector2.ZERO          # inside the deadzone: keep last_dir
	else:
		value = v.limit_length(1.0)
		last_dir = value.normalized()
	vector_changed.emit(value)
	queue_redraw()

func _release() -> void:
	_touch_id = -99
	active = false
	value = Vector2.ZERO           # last_dir survives: the heading is kept
	_base_center = _rest_center
	_knob = Vector2.ZERO
	_alpha = 0.0                   # no idle residual stick: release hides it
	vector_changed.emit(value)
	queue_redraw()

# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_t += delta
	if not enabled:
		if _alpha > 0.0:
			_alpha = maxf(0.0, _alpha - delta * 3.0)
			queue_redraw()
		return
	# The stick only exists while a finger is down. Idle/left-alone gameplay is
	# completely clean; releasing materializes the previous base offscreen and
	# immediately hides it.
	var target := 0.0 if not active else 1.0
	if _alpha != target:
		_alpha = clampf(_alpha + (target - _alpha) * minf(1.0, delta * 6.0), 0.0, 1.0)
		queue_redraw()
	elif active:
		queue_redraw()          # the knob follows the finger: redraw every frame

## Resting-ring alpha (used by QA to confirm the stick is on screen).
func alpha() -> float:
	return _alpha

# ---------------------------------------------------------------- QA hooks

## Drive the stick directly (no touch device needed). Simulates a HELD stick so
## the value does not decay.
func force_value(v: Vector2) -> void:
	active = true
	_alpha = 1.0
	_knob = Vector2(v.x, -v.y).limit_length(1.0) * (radius() * 0.80)
	value = Vector2.ZERO if v.length() < DEAD else v.limit_length(1.0)
	if value != Vector2.ZERO:
		last_dir = value.normalized()
	vector_changed.emit(value)
	queue_redraw()

func force_release() -> void:
	_release()

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if _alpha <= 0.01:
		return
	var c := center()
	var r := radius()
	var kr := KNOB_RADIUS * ui_scale
	var breathe := 1.0 if active else 0.86 + 0.05 * sin(_t * 2.2)
	var a := _alpha * breathe
	var accent := UiTheme.c("accent")
	var ring := Color(accent.r, accent.g, accent.b, 0.55 * a)
	# the resting disc resolves through the theme palette so both palettes
	# (BEIGE / DARK) get the right tone with zero hardcoded literals
	var pb := UiTheme.c("panel_bg")
	var inner := Color(pb.r, pb.g, pb.b, (0.24 if UiTheme.is_dark() else 0.34) * a)
	# translucent disc + thin ring outline (stays out of the way of the board)
	draw_circle(c, r, inner)
	draw_arc(c, r, 0.0, TAU, 56, ring, maxf(2.0, 2.6 * ui_scale), true)
	# cardinal ticks
	for i in 4:
		var ang := TAU * float(i) / 4.0
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * (r * 0.78), c + d * (r * 0.92),
			Color(ring.r, ring.g, ring.b, 0.30 * a), maxf(1.0, 1.6 * ui_scale), true)
	# knob: solid disc with a soft halo so the finger can see the grip
	var kc := c + _knob
	draw_circle(kc, kr * 1.35, Color(accent.r, accent.g, accent.b, 0.16 * a))
	draw_circle(kc, kr, Color(accent.r, accent.g, accent.b, 0.80 * a))
	draw_arc(kc, kr, 0.0, TAU, 28, UiTheme.with_alpha("panel_bg", 0.70 * a), maxf(1.5, 2.0 * ui_scale), true)
	draw_circle(kc, kr * 0.30, UiTheme.with_alpha("panel_bg", 0.85 * a))