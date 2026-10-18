class_name TouchJoystick
extends Control
## SERPENTIS 3D — PUBG-style virtual movement joystick (spec section 2).
## Shown bottom-left on MOBILE 2D mode only. Translucent outer ring + drag
## knob that returns to neutral on release. `value` actually steers the
## snake (PlayerSnake reads it); existing drag-steer and two-finger boost
## keep working while the stick is idle.
##
## Touch handling runs in `_input` with an explicit hit-test (reliable on
## Android) and marks events handled so drags never leak into the steering
## path or the OS gesture layer. The control itself is full-rect; the stick
## is drawn bottom-left inside the safe area.

signal vector_changed(v: Vector2)

const BASE_RADIUS := 104.0     # px at scale 1 (outer ring)
const KNOB_RADIUS := 44.0      # px at scale 1
const DEAD := 0.14             # below this magnitude the snake holds heading
const MARGIN := 26.0

var value := Vector2.ZERO      # normalized steering direction (magnitude 0..1)
var active := false
var enabled := false
var force_joystick_dev := false   # dev/QA: show the stick on desktop too
var ui_scale := 1.0

var _touch_id := -99           # -99 = free, >=0 touch index, -2 mouse
var _knob := Vector2.ZERO      # knob offset from center (px)
var _safe_left := 0.0
var _safe_bottom := 0.0
var _base_center := Vector2.ZERO   # stick base (moves to the finger on zone grabs)

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
	_base_center = Vector2(safe_left + r + MARGIN * ui_scale,
		vs.y - safe_bottom - r - MARGIN * ui_scale)
	queue_redraw()

func radius() -> float:
	return BASE_RADIUS * ui_scale

func center() -> Vector2:
	return _base_center

## A touch that starts outside the ring but inside the left activation zone
## re-centers the stick under the finger (PUBG-like forgiveness): the player
## never has to hit the small ring exactly, so a drag next to the stick
## always steers instead of letting the snake idle in circles.
func _in_activation_zone(local: Vector2) -> bool:
	var vs := size
	if vs.y < 1.0:
		vs = get_viewport_rect().size
	return local.x < vs.x * 0.62 and local.y > vs.y * 0.22

func _grab(local: Vector2) -> void:
	if local.distance_to(center()) <= radius() * 1.3:
		_update_from(local)          # inside the ring: fixed base
	else:
		_base_center = local        # zone touch: stick jumps under the finger
		_knob = Vector2.ZERO
		value = Vector2.ZERO
		_update_from(local)

func _to_local(p: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * p

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_id == -99:
			var local := _to_local(t.position)
			if local.distance_to(center()) <= radius() * 1.3 or _in_activation_zone(local):
				_touch_id = t.index
				active = true
				_grab(local)
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
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _touch_id == -99:
				var local := _to_local(mb.position)
				if local.distance_to(center()) <= radius() * 1.3 or _in_activation_zone(local):
					_touch_id = -2
					active = true
					_grab(local)
			elif not mb.pressed and _touch_id == -2:
				_release()
	elif event is InputEventMouseMotion and _touch_id == -2 and active:
		_update_from(_to_local((event as InputEventMouseMotion).position))
		get_viewport().set_input_as_handled()

func _update_from(local: Vector2) -> void:
	var maxr := radius() * 0.82
	var off := local - center()
	if off.length() > maxr:
		off = off.normalized() * maxr
	_knob = off
	# screen coords are y-DOWN but the steering value is y-UP (same
	# convention as WASD / drag-steer), so pushing the stick up really does
	# drive the snake up-screen
	var v := Vector2(off.x, -off.y) / maxr
	value = Vector2.ZERO if v.length() < DEAD else v.limit_length(1.0)
	vector_changed.emit(value)
	queue_redraw()

func _release() -> void:
	_touch_id = -99
	active = false
	value = Vector2.ZERO
	configure(ui_scale, _safe_left, _safe_bottom)   # ring returns to its resting spot
	vector_changed.emit(value)
	queue_redraw()

## Test/QA hook: drive the stick directly (no touch device needed).
## Simulates a HELD stick so the value does not decay.
func force_value(v: Vector2) -> void:
	active = true
	_knob = Vector2(v.x, -v.y).limit_length(1.0) * (radius() * 0.82)
	value = Vector2.ZERO if v.length() < DEAD else v.limit_length(1.0)
	vector_changed.emit(value)
	queue_redraw()

func force_release() -> void:
	_release()

func _process(_delta: float) -> void:
	if not enabled:
		return
	if not active:
		_knob = _knob.lerp(Vector2.ZERO, 0.25)
		if value != Vector2.ZERO:
			value = value.lerp(Vector2.ZERO, 0.35)
			if value.length() < 0.01:
				value = Vector2.ZERO
			vector_changed.emit(value)
		queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	var c := center()
	var r := radius()
	var kr := KNOB_RADIUS * ui_scale
	# translucent outer disc + soft edge
	draw_circle(c, r, Color(0.02, 0.04, 0.07, 0.36))
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.22), 2.5 * ui_scale, true)
	for i in 4:
		var a := TAU * float(i) / 4.0
		draw_line(c + Vector2(cos(a), sin(a)) * (r * 0.72),
			c + Vector2(cos(a), sin(a)) * (r * 0.86),
			Color(1, 1, 1, 0.10), 1.5 * ui_scale, true)
	# knob
	var kc := c + _knob
	draw_circle(kc, kr, Color(0.15, 0.85, 0.78, 0.30))
	draw_arc(kc, kr, 0.0, TAU, 32, Color(0.45, 1.0, 0.9, 0.85), 2.5 * ui_scale, true)
	draw_circle(kc, kr * 0.34, Color(0.75, 1.0, 0.95, 0.5))
