class_name ArenaMinimap
extends Control
## Whole-arena radar for the HUD: a small square panel showing every fruit,
## every rival and the player inside the arena circle.
##
## Design was taken as an idea only from the reference frame the user sent
## (flat square panel, dots for pickups, one highlighted player marker) — the
## drawing, colors and layout here are this project's own.

const MARGIN := 16.0

var world = null            # MatchWorld (weakly used; resolved per refresh)
var radius := 34.0          # arena radius in meters
var ui_scale := 1.0
var live := true            # false while paused / on menus

var _food: PackedVector3Array = PackedVector3Array()
var _snakes: Array = []     # [[pos: Vector3, color: Color], ...]
var _player_pos := Vector3.ZERO
var _player_col := Color(0.2, 0.95, 0.85)
var _has_player := false
var _refresh_t := 0.0
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(168, 168)
	size = custom_minimum_size

func configure(s: float, arena_r: float) -> void:
	ui_scale = clampf(s, 0.8, 1.6)
	radius = maxf(1.0, arena_r)
	custom_minimum_size = Vector2(168, 168) * ui_scale
	size = custom_minimum_size
	queue_redraw()

## Arena-space -> panel space.
func _to_panel(p: Vector3) -> Vector2:
	var half := size * 0.5
	var k := (half.x - 5.0) / radius
	return half + Vector2(p.x, p.z) * k

func _process(delta: float) -> void:
	_t += delta
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		# 12 Hz: data refresh AND redraw together. A Control that redraws every
		# frame is wasted work on a phone battery for something this small.
		_refresh_t = 0.08
		_refresh()
		queue_redraw()

func _refresh() -> void:
	if world == null or not is_instance_valid(world):
		_food.clear()
		_snakes.clear()
		_has_player = false
		return
	radius = maxf(1.0, world.arena_radius)
	_food.clear()
	var food = world.food
	if food != null and is_instance_valid(food):
		for p in food.alive_positions():
			_food.append(p)
	_snakes.clear()
	_has_player = false
	var pl = world.player
	for s in world.get_alive_snakes():
		if not is_instance_valid(s) or not s.alive:
			continue
		var c: Color = s.dorsal
		c = c.lightened(0.18)
		if s == pl:
			_player_pos = s.head_pos
			_player_col = c
			_has_player = true
		else:
			_snakes.append([s.head_pos, c])

func _draw() -> void:
	if not live:
		return
	var a := 0.88 if _has_player else 0.7
	var panel := Rect2(Vector2.ZERO, size)
	# panel body + hairline border, both menus/HUD themed
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.with_alpha("panel_bg", 0.55 * a)
	sb.border_color = UiTheme.with_alpha("panel_edge", 0.80 * a)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(6 * ui_scale))
	draw_style_box(sb, panel)
	var half := size * 0.5
	# playable circle
	draw_arc(half, half.x - 5.0, 0.0, TAU, 48, UiTheme.with_alpha("dim", 0.30 * a), 1.5, true)
	# fruit: quiet dots (they read as "supplies", not clutter)
	for p in _food:
		draw_circle(_to_panel(p), maxf(1.4, 2.1 * ui_scale), UiTheme.with_alpha("gold", 0.55 * a))
	# rivals
	for e in _snakes:
		draw_circle(_to_panel(e[0]), maxf(1.8, 2.6 * ui_scale), Color(e[1].r, e[1].g, e[1].b, 0.75 * a))
	# player: bright dot inside a pulsing ring so it is impossible to lose
	if _has_player:
		var pp := _to_panel(_player_pos)
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		draw_circle(pp, maxf(5.0, 7.5 * ui_scale) + pulse * 2.0, Color(_player_col.r, _player_col.g, _player_col.b, 0.22 * a))
		draw_circle(pp, maxf(3.0, 4.2 * ui_scale), Color(_player_col.r, _player_col.g, _player_col.b, 0.95 * a))
		draw_arc(pp, maxf(5.0, 7.0 * ui_scale) + pulse * 2.5, 0.0, TAU, 24,
			UiTheme.with_alpha("text", 0.45 * a), 1.5, true)