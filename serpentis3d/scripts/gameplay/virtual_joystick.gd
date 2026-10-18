class_name TouchJoystick
extends Control
## SERPENTIS 3D — mobile touch steering stick (spec: continuous 360° heading).
##
## Behaviour the spec asks for, all of it steering the EXISTING heading system
## (the snake never teleports, it turns toward the stick at its normal rate):
##   * 360° continuous — the direction is the raw vector from the stick center,
##     so 15°, 30°, 45°, 60°, 75° and every in-between angle work; nothing is
##     snapped to 4 or 8 directions.
##   * Touch ANYWHERE — the first finger down floats the stick to that point
##     (a resting ring is drawn bottom-left as a thumb hint), which is the same
##     "drag anywhere on the play area" control without adding buttons.
##   * Release keeps going — on release the stick returns to neutral but
##     `last_dir` is kept, and PlayerSnake simply holds its current heading, so
##     the snake never stops and never snaps back to a default direction.
##   * UI-safe — taps that land on a HUD control (pause button, dialogs) are
##     left to the UI via the `ui_blocker` callback.
##
## Look: a thin ring with a solid round knob and a soft tint, so it stays out
## of the way of the board (inspired by the reference frame, not copied).

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
var _rest_center := Vector2.ZERO   # resting ring (bottom-left, inside safe area)
var _base_center := Vector2.ZERO   # active base — follows the finger
var _alpha := 0.0              # 0 hidden -> 1 fully visible
var _t := 0.0
var _last_idle_draw := 0.0

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
		# desktop parity (dev / touchpad): left button drives the stick
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
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
## floating stick), so players never have to hit the small resting ring.
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
	# fade in when first shown, fade out when hidden; the resting ring breathes
	# gently so the player can see where the stick lives
	var target := 1.0
	if _alpha != target:
		_alpha = clampf(_alpha + (target - _alpha) * minf(1.0, delta * 6.0), 0.0, 1.0)
		queue_redraw()
	elif active:
		queue_redraw()          # the knob follows the finger: redraw every frame
	elif _t - _last_idle_draw > 0.05:
		# idle breathing only needs ~20 Hz: saves a Control redraw per frame on
		# phones (and keeps the compositor quiet when the window is occluded)
		_last_idle_draw = _t
		queue_redraw()

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
	var inner := Color(0.03, 0.05, 0.09, 0.22 * a)
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
	draw_arc(kc, kr, 0.0, TAU, 28, Color(1, 1, 1, 0.55 * a), maxf(1.5, 2.0 * ui_scale), true)
	draw_circle(kc, kr * 0.30, Color(1, 1, 1, 0.75 * a))