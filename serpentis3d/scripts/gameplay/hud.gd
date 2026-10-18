class_name GameHud
extends CanvasLayer
## Complete HUD + menu + pause + game-over UI, built in code (original style,
## no external assets or fonts).

signal play_pressed
signal quit_pressed

var root: Control
var gameplay_group: Control
var menu_group: Control
var overlay_group: Control

var score_label: Label
var length_label: Label
var rank_label: Label
var timer_label: Label
var kills_label: Label
var boost_bar: ProgressBar
var announce_label: Label
var announce_sub: Label
var feed_box: VBoxContainer
var _pop_layer: Control

var _menu_main: VBoxContainer
var _menu_settings: VBoxContainer
var _pause_panel: PanelContainer
var _over_panel: PanelContainer
var _over_title: Label
var _over_lines: Label

const COL_TEXT := Color(0.87, 0.9, 0.96)
const COL_DIM := Color(0.55, 0.62, 0.72)
const COL_ACCENT := Color(0.14, 0.9, 0.78)
const COL_WARN := Color(1.0, 0.28, 0.45)
const COL_GOLD := Color(1.0, 0.82, 0.28)

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_gameplay()
	_build_menu()
	_build_pause()
	_build_gameover()
	show_menu(true)
	set_gameplay_visible(false)
	overlay_group.visible = false

# ---------------------------------------------------------------- gameplay

func _build_gameplay() -> void:
	gameplay_group = Control.new()
	gameplay_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameplay_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gameplay_group)

	# full-screen layer for floating score popups
	_pop_layer = Control.new()
	_pop_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gameplay_group.add_child(_pop_layer)

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style())
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position.y = 10
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	top.add_child(tv)
	score_label = _mk_label("0", 40, COL_ACCENT, tv)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hrow := HBoxContainer.new()
	hrow.alignment = BoxContainer.ALIGNMENT_CENTER
	hrow.add_theme_constant_override("separation", 14)
	tv.add_child(hrow)
	length_label = _mk_label("LENGTH 7 M", 15, COL_TEXT, hrow)
	rank_label = _mk_label("RANK 8/8", 15, COL_DIM, hrow)
	timer_label = _mk_label("0:00", 15, COL_DIM, hrow)
	kills_label = _mk_label("KILLS 0", 15, COL_TEXT, hrow)
	gameplay_group.add_child(top)

	# kill feed
	var feed_panel := VBoxContainer.new()
	feed_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed_panel.position = Vector2(-40, 74)   # offset handled below via alignment
	feed_panel.anchor_left = 1.0
	feed_panel.anchor_right = 1.0
	feed_panel.offset_left = -330
	feed_panel.offset_right = -14
	feed_panel.offset_top = 78
	feed_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	feed_box = VBoxContainer.new()
	feed_box.add_theme_constant_override("separation", 4)
	feed_box.alignment = BoxContainer.ALIGNMENT_END
	feed_panel.add_child(feed_box)
	gameplay_group.add_child(feed_panel)

	# boost bar
	var boost_panel := PanelContainer.new()
	boost_panel.add_theme_stylebox_override("panel", _panel_style())
	boost_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	boost_panel.offset_left = 18
	boost_panel.offset_top = -74
	boost_panel.offset_bottom = -16
	var bv := VBoxContainer.new()
	boost_panel.add_child(bv)
	_mk_label("BOOST  [SPACE / LMB]", 13, COL_DIM, bv)
	boost_bar = ProgressBar.new()
	boost_bar.min_value = 0
	boost_bar.max_value = 1.0
	boost_bar.value = 1.0
	boost_bar.custom_minimum_size = Vector2(240, 16)
	boost_bar.show_percentage = false
	boost_bar.add_theme_stylebox_override("background", _bar_bg())
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_ACCENT
	fill.set_corner_radius_all(4)
	boost_bar.add_theme_stylebox_override("fill", fill)
	bv.add_child(boost_bar)
	gameplay_group.add_child(boost_panel)

	# center announce
	var av := VBoxContainer.new()
	av.set_anchors_preset(Control.PRESET_CENTER)
	av.alignment = BoxContainer.ALIGNMENT_CENTER
	av.grow_horizontal = Control.GROW_DIRECTION_BOTH
	av.grow_vertical = Control.GROW_DIRECTION_BOTH
	announce_label = _mk_label("", 46, COL_TEXT, av)
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_sub = _mk_label("", 20, COL_ACCENT, av)
	announce_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.position -= av.size * 0.5
	gameplay_group.add_child(av)

func set_gameplay_visible(v: bool) -> void:
	gameplay_group.visible = v

func set_score(v: int) -> void:
	score_label.text = str(v)

func set_length(v: float) -> void:
	length_label.text = "LENGTH %d M" % int(round(v))

func set_rank(r: int, n: int) -> void:
	rank_label.text = "RANK %d/%d" % [r, n]

func set_timer(t: float) -> void:
	timer_label.text = "%d:%02d" % [int(t) / 60, int(t) % 60]

func set_kills(k: int) -> void:
	kills_label.text = "KILLS %d" % k

func set_boost(v: float) -> void:
	boost_bar.value = clampf(v, 0, 1)

func set_boosting(on: bool) -> void:
	var fill := boost_bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		(fill as StyleBoxFlat).bg_color = COL_GOLD if on else COL_ACCENT

func push_feed(kind: String, text: String) -> void:
	if feed_box == null:
		return
	var col := COL_TEXT
	match kind:
		"kill":
			col = COL_WARN
		"eat":
			col = COL_ACCENT
		"warn":
			col = COL_GOLD
		_:
			col = COL_TEXT
	var lab := _mk_label(text, 14, col, null)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lab.modulate.a = 0.0
	feed_box.add_child(lab)
	if feed_box.get_child_count() > 6:
		var oldest := feed_box.get_child(0)
		feed_box.remove_child(oldest)
		oldest.queue_free()
	var tw := lab.create_tween()
	tw.tween_property(lab, "modulate:a", 1.0, 0.15)
	tw.tween_interval(3.6)
	tw.tween_property(lab, "modulate:a", 0.0, 0.7)
	tw.tween_callback(lab.queue_free)

func push_score_popup(text: String, color: Color = COL_ACCENT) -> void:
	# Floating "+N" that rises from lower-center and fades — eaten value feedback.
	if _pop_layer == null:
		return
	var lab := _mk_label(text, 24, color, _pop_layer)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vs := _pop_layer.get_viewport_rect().size
	lab.position = Vector2(vs.x * 0.5 - 60.0 + randf_range(-30.0, 30.0), vs.y * 0.64)
	var tw := lab.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "position:y", lab.position.y - 52.0, 0.85).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lab, "modulate:a", 0.0, 0.85).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(lab.queue_free)

func announce(title: String, sub: String = "") -> void:
	if announce_label == null:
		return
	announce_label.text = title
	announce_sub.text = sub
	announce_label.modulate.a = 0.0
	announce_sub.modulate.a = 0.0
	var tw := announce_label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(announce_label, "modulate:a", 1.0, 0.2)
	tw.tween_property(announce_sub, "modulate:a", 1.0, 0.2)
	tw.chain().tween_interval(1.4)
	tw.chain().tween_property(announce_label, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(announce_sub, "modulate:a", 0.0, 0.5)

# ---------------------------------------------------------------- menu

func _build_menu() -> void:
	menu_group = Control.new()
	menu_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu_group)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(0.82))
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.anchor_left = 0.08
	panel.anchor_right = 0.08
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu_group.add_child(panel)

	var vroot := VBoxContainer.new()
	vroot.add_theme_constant_override("separation", 14)
	vroot.custom_minimum_size = Vector2(360, 0)
	panel.add_child(vroot)

	var title := _mk_label("SERPENTIS 3D", 64, COL_ACCENT, vroot)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	var tag := _mk_label("Evolve. Hunt. Dominate.", 17, COL_DIM, vroot)
	tag.text = "  Evolve. Hunt. Dominate."

	_menu_main = VBoxContainer.new()
	_menu_main.add_theme_constant_override("separation", 10)
	vroot.add_child(_menu_main)
	_menu_button(_menu_main, "PLAY", func(): play_pressed.emit())
	_menu_button(_menu_main, "SETTINGS", func(): _swap_menu(false))
	_menu_button(_menu_main, "QUIT", func(): quit_pressed.emit())
	var hint := _mk_label("ORIGINAL OFFLINE BUILD v0.1 — GODOT 4.7", 12, COL_DIM, vroot)
	hint.text = "   OFFLINE BUILD v0.1 — mouse steers, LMB boosts"

	_menu_settings = VBoxContainer.new()
	_menu_settings.add_theme_constant_override("separation", 10)
	vroot.add_child(_menu_settings)
	_menu_settings.visible = false
	var svl := _mk_label("MASTER VOLUME", 14, COL_TEXT, _menu_settings)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(SaveMgr.get_value("master_volume", 0.85))
	slider.custom_minimum_size = Vector2(300, 20)
	slider.value_changed.connect(func(v): AudioMgr.set_master_volume(v))
	_menu_settings.add_child(slider)
	var full := CheckBox.new()
	full.text = "FULLSCREEN"
	full.button_pressed = bool(SaveMgr.get_value("fullscreen", false))
	_style_button(full)
	full.pressed.connect(func():
		var on := not bool(SaveMgr.get_value("fullscreen", false))
		SaveMgr.set_value("fullscreen", on)
		var ds := DisplayServer.window_get_current_screen()
		if on:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	)
	_menu_settings.add_child(full)
	_menu_button(_menu_settings, "BACK", func(): _swap_menu(true))

func _swap_menu(show_main: bool) -> void:
	_menu_main.visible = show_main
	_menu_settings.visible = not show_main
	AudioMgr.play("click")

func show_menu(v: bool) -> void:
	menu_group.visible = v
	overlay_group.visible = false if v else overlay_group.visible

# ---------------------------------------------------------------- pause

func _build_pause() -> void:
	overlay_group = Control.new()
	overlay_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay_group)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_group.add_child(dim)

	_pause_panel = PanelContainer.new()
	_pause_panel.add_theme_stylebox_override("panel", _panel_style(0.92))
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay_group.add_child(_pause_panel)
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(p)
	_mk_label("PAUSED", 44, COL_TEXT, p)
	_menu_button(p, "RESUME", func(): resume_pressed.emit())
	_menu_button(p, "RESTART MATCH", func(): restart_pressed.emit())
	_menu_button(p, "MAIN MENU", func(): tomenu_pressed.emit())
	var hint := _mk_label("ESC TO RESUME", 13, COL_DIM, p)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func show_pause(v: bool) -> void:
	_pause_panel.visible = v
	overlay_group.visible = v

# ---------------------------------------------------------------- game over

func _build_gameover() -> void:
	_over_panel = PanelContainer.new()
	_over_panel.add_theme_stylebox_override("panel", _panel_style(0.92))
	_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	_over_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_over_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_over_panel.visible = false
	overlay_group.add_child(_over_panel)
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 10)
	_over_panel.add_child(p)
	_over_title = _mk_label("ELIMINATED", 52, COL_WARN, p)
	_over_lines = _mk_label("", 18, COL_TEXT, p)
	_menu_button(p, "RESTART", func(): restart_pressed.emit())
	_menu_button(p, "MAIN MENU", func(): tomenu_pressed.emit())

func show_gameover_hidden() -> void:
	overlay_group.visible = false
	_over_panel.visible = false
	_pause_panel.visible = false

func show_gameover(stats: Dictionary) -> void:
	_over_title.text = str(stats.get("title", "ELIMINATED"))
	var lines := "\n".join(PackedStringArray([
		"SCORE      %s%s" % [stats.get("score", 0), "   [NEW BEST]" if bool(stats.get("is_best", false)) else ""],
		"LENGTH     %d M" % int(stats.get("length", 0.0)),
		"SURVIVED   %d:%02d" % [int(stats.get("time", 0.0)) / 60, int(stats.get("time", 0.0)) % 60],
		"ELIMINATIONS %d" % int(stats.get("kills", 0)),
		"RANK       %d / %d" % [stats.get("rank", 1), stats.get("total", 1)],
		"BEST SCORE %s" % stats.get("best", 0),
	]))
	_over_lines.text = lines
	overlay_group.visible = true
	_pause_panel.visible = false
	_over_panel.visible = true

# ---------------------------------------------------------------- signals (pause/gameover)

signal resume_pressed
signal restart_pressed
signal tomenu_pressed

# ---------------------------------------------------------------- helpers

func _mk_label(text: String, size: int, color: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if parent:
		parent.add_child(l)
	return l

func _menu_button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 44)
	_style_button(b)
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_ACCENT)
	b.add_theme_color_override("font_pressed_color", COL_ACCENT)
	b.pressed.connect(func():
		AudioMgr.play("click")
		on_press.call())
	parent.add_child(b)
	return b

func _style_button(b: Control) -> void:
	var make := func(bg: Color, border: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		return sb
	b.add_theme_stylebox_override("normal", make.call(Color(0.055, 0.075, 0.12, 0.9), Color(0.2, 0.35, 0.4)))
	b.add_theme_stylebox_override("hover", make.call(Color(0.09, 0.12, 0.18, 0.95), COL_ACCENT))
	b.add_theme_stylebox_override("pressed", make.call(Color(0.13, 0.2, 0.26, 0.95), COL_ACCENT))
	b.add_theme_stylebox_override("focus", make.call(Color(0.09, 0.12, 0.18, 0.95), COL_ACCENT))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _panel_style(alpha: float = 0.7) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.05, 0.085, alpha)
	sb.border_color = Color(0.14, 0.9, 0.78, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	return sb

func _bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.14, 0.9)
	sb.set_corner_radius_all(4)
	return sb
