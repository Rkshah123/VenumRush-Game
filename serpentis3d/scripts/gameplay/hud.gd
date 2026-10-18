class_name GameHud
extends CanvasLayer
## Complete HUD + menu + pause + game-over UI, built in code (original style,
## no external assets or fonts).

signal play_pressed
signal quit_pressed
signal arena_shift(dir: int)

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
var ability_bar: ProgressBar
var ab_label: Label
var _ability_panel: PanelContainer
var announce_label: Label
var announce_sub: Label
var feed_box: VBoxContainer
var _pop_layer: Control

var _menu_main: VBoxContainer
var _menu_settings: VBoxContainer
var _menu_skins: VBoxContainer
var _skin_buttons: Array[Button] = []
var _preview_snake: Node3D = null
var _preview_vp: SubViewport = null
var _preview_cam: Camera3D = null
var _preview_yaw := 0.0
var _arena_label: Label
var _pause_panel: PanelContainer
var _over_panel: PanelContainer
var _over_title: Label
var _over_lines: Label

# Theme palettes live in UiTheme (CLASSIC / DARK). Static role accessors keep
# external callers (match_world popups) theme-aware.
static func role_color(role: String) -> Color:
	return UiTheme.c(role)

var _tl: Array = []            # [Label, role] — re-tinted on theme switch
var _tb: Array = []            # [Button] — restyled on theme switch
var _topt: Array = []          # option/selector buttons (settings)
var _tpanels: Array = []       # panel StyleBoxFlats
var _tbars: Array = []         # bar background StyleBoxFlats
var _tfills: Array = []        # [ProgressBar, role] — fill colors
var _scrims: Array = []        # [ColorRect, role, alpha]
var _menu_scrim: TextureRect = null
var _menu_title: Label = null
var _ui_s := 1.0               # menu scale factor (set on build / resize)

func _ready() -> void:
	layer = 10
	_ui_s = _ui_scale()
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
	# restore the saved theme across menus, HUD, panels and scrims
	apply_theme(int(SaveMgr.get_value("theme", UiTheme.CLASSIC)))

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
	score_label = _mk_label("0", 40, "accent", tv)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hrow := HBoxContainer.new()
	hrow.alignment = BoxContainer.ALIGNMENT_CENTER
	hrow.add_theme_constant_override("separation", 14)
	tv.add_child(hrow)
	length_label = _mk_label("LENGTH 7 M", 15, "text", hrow)
	rank_label = _mk_label("RANK 8/8", 15, "dim", hrow)
	timer_label = _mk_label("0:00", 15, "dim", hrow)
	kills_label = _mk_label("KILLS 0", 15, "text", hrow)
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
	_mk_label("BOOST  [SPACE / LMB]" if not OS.has_feature("android") else "BOOST  [2ND FINGER]", 13, "dim", bv)
	boost_bar = ProgressBar.new()
	boost_bar.min_value = 0
	boost_bar.max_value = 1.0
	boost_bar.value = 1.0
	boost_bar.custom_minimum_size = Vector2(240, 16)
	boost_bar.show_percentage = false
	boost_bar.add_theme_stylebox_override("background", _bar_bg())
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.c("accent")
	fill.set_corner_radius_all(4)
	boost_bar.add_theme_stylebox_override("fill", fill)
	_tfills.append([boost_bar, "accent"])
	bv.add_child(boost_bar)
	gameplay_group.add_child(boost_panel)

	# ability bar (Magnet Pulse / Shield) — hidden unless an ability is active
	var ab_panel := PanelContainer.new()
	ab_panel.add_theme_stylebox_override("panel", _panel_style())
	ab_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ab_panel.offset_left = 18
	ab_panel.offset_top = -130
	ab_panel.offset_bottom = -78
	var av2 := VBoxContainer.new()
	ab_panel.add_child(av2)
	ab_label = _mk_label("MAGNET PULSE", 13, "warn", av2)
	ability_bar = ProgressBar.new()
	ability_bar.min_value = 0
	ability_bar.max_value = 1.0
	ability_bar.value = 1.0
	ability_bar.custom_minimum_size = Vector2(240, 10)
	ability_bar.show_percentage = false
	ability_bar.add_theme_stylebox_override("background", _bar_bg())
	var afill := StyleBoxFlat.new()
	afill.bg_color = UiTheme.c("warn")
	afill.set_corner_radius_all(4)
	ability_bar.add_theme_stylebox_override("fill", afill)
	_tfills.append([ability_bar, "warn"])
	av2.add_child(ability_bar)
	gameplay_group.add_child(ab_panel)
	ab_panel.visible = false
	_ability_panel = ab_panel

	# center announce
	var av := VBoxContainer.new()
	av.set_anchors_preset(Control.PRESET_CENTER)
	av.alignment = BoxContainer.ALIGNMENT_CENTER
	av.grow_horizontal = Control.GROW_DIRECTION_BOTH
	av.grow_vertical = Control.GROW_DIRECTION_BOTH
	announce_label = _mk_label("", 46, "text", av)
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_sub = _mk_label("", 20, "accent", av)
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

func set_ability(id: String, frac: float) -> void:
	if _ability_panel == null:
		return
	var on := id != "" and frac > 0.0
	_ability_panel.visible = on
	if on:
		ab_label.text = id
		ability_bar.value = clampf(frac, 0, 1)

func set_boosting(on: bool) -> void:
	var fill := boost_bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		(fill as StyleBoxFlat).bg_color = UiTheme.c("gold") if on else UiTheme.c("accent")

func push_feed(kind: String, text: String) -> void:
	if feed_box == null:
		return
	var role := "text"
	match kind:
		"kill":
			role = "warn"
		"eat":
			role = "accent"
		"warn":
			role = "gold"
	var lab := _mk_label(text, 14, role, null)
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

func push_score_popup(text: String, color: Color = Color(0.14, 0.9, 0.78)) -> void:
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

func push_score_popup_at(text: String, color: Color, world_pos: Vector3) -> void:
	# Floating "+N" anchored to the eaten fruit's projected screen position
	# (spec §4). Falls back to the lower-center popup when projection fails.
	var cam := get_viewport().get_camera_3d()
	if _pop_layer == null or cam == null or cam.is_position_behind(world_pos):
		push_score_popup(text, color)
		return
	var sp: Vector2 = cam.unproject_position(world_pos + Vector3.UP * 0.9)
	var vs := get_viewport().get_visible_rect().size
	if sp.x < -60 or sp.y < -60 or sp.x > vs.x + 60 or sp.y > vs.y + 60:
		push_score_popup(text, color)
		return
	var lab := _mk_label(text, 22, color, _pop_layer)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.position = sp + Vector2(-40, -30)
	var tw := lab.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "position:y", lab.position.y - 46.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lab, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
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

	_ui_s = _ui_scale()

	# FULL-SCREEN menu backdrop: gradient scrim over the live 3D arena; the
	# right side stays open so the world animates behind the menu.
	_menu_scrim = TextureRect.new()
	_menu_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_menu_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_group.add_child(_menu_scrim)
	_rebuild_menu_scrim()

	# Hero column: left rail, fixed width, vertically centered, scaled to the
	# screen — the rest of the screen stays a live window into the 3D arena.
	var hero_wrap := Control.new()
	hero_wrap.anchor_left = 0.0
	hero_wrap.anchor_right = 0.0
	hero_wrap.anchor_top = 0.0
	hero_wrap.anchor_bottom = 1.0
	hero_wrap.offset_left = int(40 * _ui_s)
	hero_wrap.offset_right = int(40 * _ui_s + 392 * _ui_s)
	hero_wrap.offset_top = 0
	hero_wrap.offset_bottom = 0
	hero_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_group.add_child(hero_wrap)
	var vroot := VBoxContainer.new()
	vroot.set_anchors_preset(Control.PRESET_FULL_RECT)
	vroot.alignment = BoxContainer.ALIGNMENT_CENTER
	vroot.add_theme_constant_override("separation", int(11 * _ui_s))
	vroot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_wrap.add_child(vroot)

	_menu_title = _mk_label("SERPENTIS 3D", int(66 * _ui_s), "accent", vroot)
	_menu_title.add_theme_color_override("font_shadow_color", UiTheme.c("title_shadow"))
	_menu_title.add_theme_constant_override("shadow_offset_y", 4)
	var tag := _mk_label("Evolve. Hunt. Dominate.", int(17 * _ui_s), "dim", vroot)
	tag.text = "  Evolve. Hunt. Dominate."

	_menu_main = VBoxContainer.new()
	_menu_main.add_theme_constant_override("separation", int(9 * _ui_s))
	vroot.add_child(_menu_main)
	# ARENA selector — live-swaps the 3D world behind the menu
	var arena_tag := _mk_label("ARENA", int(12 * _ui_s), "dim", _menu_main)
	arena_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var arow := HBoxContainer.new()
	arow.alignment = BoxContainer.ALIGNMENT_CENTER
	arow.add_theme_constant_override("separation", 6)
	_menu_main.add_child(arow)
	var prev_b := _nav_button("◄")
	prev_b.pressed.connect(func(): AudioMgr.play("click"); arena_shift.emit(-1))
	arow.add_child(prev_b)
	_arena_label = _mk_label("VERDANT VALLEY", int(15 * _ui_s), "accent", arow)
	_arena_label.custom_minimum_size = Vector2(200 * _ui_s, 40 * _ui_s)
	_arena_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arena_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var next_b := _nav_button("►")
	next_b.pressed.connect(func(): AudioMgr.play("click"); arena_shift.emit(1))
	arow.add_child(next_b)
	_menu_button(_menu_main, "PLAY", func(): play_pressed.emit(), true)
	_menu_button(_menu_main, "SNAKES", func(): _menu_page("skins"))
	_menu_button(_menu_main, "SETTINGS", func(): _swap_menu(false))
	_menu_button(_menu_main, "QUIT", func(): quit_pressed.emit())
	var hint := _mk_label("", int(12 * _ui_s), "dim", vroot)
	hint.text = "mouse steers, LMB boosts" if not OS.has_feature("android") else "drag steers, 2nd finger boosts"
	hint.text = "   OFFLINE BUILD v0.1 — " + hint.text

	_menu_settings = VBoxContainer.new()
	_menu_settings.add_theme_constant_override("separation", int(9 * _ui_s))
	vroot.add_child(_menu_settings)
	_menu_settings.visible = false
	var svl := _mk_label("MASTER VOLUME", int(13 * _ui_s), "dim", _menu_settings)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(SaveMgr.get_value("master_volume", 0.85))
	slider.custom_minimum_size = Vector2(300 * _ui_s, 20 * _ui_s)
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

	# THEME selector (Dark Theme) — applies instantly across UI + arenas
	_mk_label("THEME", int(13 * _ui_s), "dim", _menu_settings)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	_menu_settings.add_child(trow)
	for t in UiTheme.NAMES.size():
		_option_button(trow, str(UiTheme.NAMES[t]), "theme", t, func(): _set_theme(int(SaveMgr.get_value("theme", 0)) ^ 1))

	# GRAPHICS MODE selector — 2D top-down vs 3D/2.5D
	_mk_label("GRAPHICS MODE", int(13 * _ui_s), "dim", _menu_settings)
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 8)
	_menu_settings.add_child(grow)
	_option_button(grow, "2D TOP-DOWN", "gfx_mode", 0, func(): _set_mode(int(SaveMgr.get_value("gfx_mode", 1))))
	_option_button(grow, "3D  2.5D", "gfx_mode", 1, func(): _set_mode((int(SaveMgr.get_value("gfx_mode", 1)) + 1) % 2))

	_menu_button(_menu_settings, "BACK", func(): _swap_menu(true))
	_build_skins_menu(vroot)
	_menu_skins.visible = false

func _set_theme(id: int) -> void:
	SaveMgr.set_value("theme", id)
	apply_theme(id)
	AudioMgr.play("click")
	theme_changed.emit(id)

func _set_mode(id: int) -> void:
	SaveMgr.set_value("gfx_mode", id)
	AudioMgr.play("click")
	mode_changed.emit(id)

func _swap_menu(show_main: bool) -> void:
	_menu_page("main" if show_main else "settings")

func _menu_page(page: String) -> void:
	_menu_main.visible = page == "main"
	_menu_settings.visible = page == "settings"
	_menu_skins.visible = page == "skins"
	if _preview_snake != null:
		_preview_snake.set_physics_process(page == "skins")
	if _preview_vp != null:
		# render every frame only on the skins page; keep a last-frame image elsewhere
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if page == "skins" else SubViewport.UPDATE_ONCE
	AudioMgr.play("click")

# ---------------------------------------------------------------- skins (spec §11)

func _build_skins_menu(vroot: Container) -> void:
	_menu_skins = VBoxContainer.new()
	_menu_skins.add_theme_constant_override("separation", 8)
	vroot.add_child(_menu_skins)
	_mk_label("CHOOSE YOUR SERPENT", 20, "accent", _menu_skins)

	# live 3D preview: a real Snake slithering in a small viewport
	var pv := SubViewportContainer.new()
	pv.stretch = true
	pv.custom_minimum_size = Vector2(360, 190)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_style(0.55))
	frame.add_child(pv)
	_menu_skins.add_child(frame)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pv.add_child(vp)
	_preview_vp = vp
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_energy = 1.7
	vp.add_child(sun)
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.05, 0.08, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.62)
	env.ambient_light_energy = 1.2
	amb.environment = env
	vp.add_child(amb)
	_preview_cam = Camera3D.new()
	_preview_cam.position = Vector3(0, 2.4, 4.6)
	vp.add_child(_preview_cam)
	_preview_snake = _PreviewSnake.new()
	vp.add_child(_preview_snake)
	_preview_snake.spawn(Vector3.ZERO, Vector3(0, 0, 1), 9.0)
	_preview_snake.set_physics_process(false)   # starts when the skins page opens
	var cur := int(SaveMgr.get_value("skin", 0))
	var sk0 := SkinCatalog.get_skin(cur)
	_preview_snake.apply_skin(sk0["dorsal"], sk0["accent"], sk0["belly"], sk0["seed"], int(sk0["pattern"]))

	# grid of skin buttons
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_menu_skins.add_child(grid)
	for i in SkinCatalog.count():
		var b := _menu_button(grid, "", func(): _pick_skin(i))
		b.custom_minimum_size = Vector2(225, 38)
		b.add_theme_font_size_override("font_size", 15)
		_skin_buttons.append(b)
	_refresh_skin_buttons()

func _refresh_skin_buttons() -> void:
	var best := int(SaveMgr.get_value("best_score", 0))
	var cur := int(SaveMgr.get_value("skin", 0))
	for i in _skin_buttons.size():
		var b := _skin_buttons[i]
		var sk := SkinCatalog.get_skin(i)
		if not SkinCatalog.unlocked(i, best):
			b.text = "LOCKED %d" % int(sk["unlock"])
			b.disabled = true
		else:
			b.disabled = false
			b.text = ("► %s" % sk["name"]) if i == cur else sk["name"]

func _pick_skin(i: int) -> void:
	var best := int(SaveMgr.get_value("best_score", 0))
	if not SkinCatalog.unlocked(i, best):
		return
	SaveMgr.set_value("skin", i)
	SaveMgr.save()
	_refresh_skin_buttons()
	var sk := SkinCatalog.get_skin(i)
	if _preview_snake != null:
		_preview_snake.apply_skin(sk["dorsal"], sk["accent"], sk["belly"], sk["seed"], int(sk["pattern"]))

func _process(delta: float) -> void:
	# slow breathing pulse on the menu title (ambient life on the start screen)
	if menu_group != null and menu_group.visible and _menu_title != null and is_instance_valid(_menu_title):
		_menu_title.modulate.a = 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.0016)
	if _menu_skins != null and _menu_skins.visible and _preview_snake != null and _preview_vp != null:
		var target: Vector3 = _preview_snake.head_pos + Vector3.UP * 0.6
		_preview_yaw += delta * 0.7
		_preview_cam.position = target + Vector3(sin(_preview_yaw) * 4.4, 2.2, cos(_preview_yaw) * 4.4)
		_preview_cam.look_at(target)

class _PreviewSnake extends Snake:
	# menu preview: glides in a continuous circle so the skin reads from all sides
	func _steer(_delta: float) -> void:
		desired_dir = Vector3(sin(heading + 0.55), 0.0, cos(heading + 0.55)).normalized()

func set_arena(key: String) -> void:
	if _arena_label == null:
		return
	_arena_label.text = str(ArenaPresets.get_preset(key).get("name", "VALLEY"))

func show_menu(v: bool) -> void:
	menu_group.visible = v
	overlay_group.visible = false if v else overlay_group.visible

# ---------------------------------------------------------------- pause

func _build_pause() -> void:
	overlay_group = Control.new()
	overlay_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay_group)
	var dim := ColorRect.new()
	dim.color = UiTheme.with_alpha("scrim", 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_group.add_child(dim)
	_scrims.append([dim, "scrim", 0.72])

	_pause_panel = PanelContainer.new()
	_pause_panel.add_theme_stylebox_override("panel", _panel_style(0.92))
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay_group.add_child(_pause_panel)
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(p)
	_mk_label("PAUSED", 44, "text", p)
	_menu_button(p, "RESUME", func(): resume_pressed.emit())
	_menu_button(p, "RESTART MATCH", func(): restart_pressed.emit())
	_menu_button(p, "MAIN MENU", func(): tomenu_pressed.emit())
	var hint := _mk_label("ESC TO RESUME" if not OS.has_feature("android") else "BACK / TAP RESUME", 13, "dim", p)
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
	_over_title = _mk_label("ELIMINATED", 52, "warn", p)
	_over_lines = _mk_label("", 18, "text", p)
	_menu_button(p, "RESTART", func(): restart_pressed.emit())
	_menu_button(p, "MAIN MENU", func(): tomenu_pressed.emit())

func show_gameover_hidden() -> void:
	overlay_group.visible = false
	_over_panel.visible = false
	_pause_panel.visible = false

func show_gameover(stats: Dictionary) -> void:
	_over_title.text = str(stats.get("title", "ELIMINATED"))
	var lines := "\n".join(PackedStringArray([
		"CAUSE      %s" % str(stats.get("cause", "unknown")),
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
signal theme_changed(id: int)
signal mode_changed(id: int)

# ---------------------------------------------------------------- helpers

func _ui_scale() -> float:
	# Menu scale: comfortable on 720p desktops up to tall phone screens.
	var vs := Vector2(1280, 720)
	if is_inside_tree():
		vs = get_viewport().get_visible_rect().size
	return clampf(vs.y / 900.0, 0.72, 1.45)

func _mk_label(text: String, size: int, role_or_color: Variant, parent: Node = null) -> Label:
	# role_or_color: String = theme role (auto re-tints on theme switch),
	# Color = literal (popups / computed feed colors)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if role_or_color is String:
		var role: String = role_or_color
		l.add_theme_color_override("font_color", UiTheme.c(role))
		_tl.append([l, role])
	else:
		l.add_theme_color_override("font_color", role_or_color as Color)
	if parent:
		parent.add_child(l)
	return l

func _nav_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(44 * _ui_s, 40 * _ui_s)
	_style_button(b)
	b.add_theme_font_size_override("font_size", int(20 * _ui_s))
	b.add_theme_color_override("font_color", UiTheme.c("text"))
	b.add_theme_color_override("font_hover_color", UiTheme.c("accent"))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

func _menu_button(parent: Node, text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320 * _ui_s, (62 if primary else 44) * _ui_s)
	_style_button(b, primary)
	b.add_theme_font_size_override("font_size", int((26 if primary else 20) * _ui_s))
	b.add_theme_color_override("font_color", UiTheme.c("panel_bg") if primary else UiTheme.c("text"))
	b.add_theme_color_override("font_hover_color", UiTheme.c("panel_bg") if primary else UiTheme.c("accent"))
	b.add_theme_color_override("font_pressed_color", UiTheme.c("panel_bg") if primary else UiTheme.c("accent"))
	b.pressed.connect(func():
		AudioMgr.play("click")
		on_press.call())
	parent.add_child(b)
	if not _tb.has(b):
		_tb.append(b)
		b.set_meta("primary", primary)
	return b

func _option_button(parent: Node, text: String, group: String, value: int, on_press: Callable) -> Button:
	# settings selector button; selection state refreshed by _refresh_options
	var b := _menu_button(parent, text, on_press)
	b.custom_minimum_size = Vector2(152 * _ui_s, 38 * _ui_s)
	b.add_theme_font_size_override("font_size", int(15 * _ui_s))
	b.set_meta("opt_group", group)
	b.set_meta("opt_value", value)
	_topt.append(b)
	return b

func _refresh_options() -> void:
	for b: Button in _topt:
		if not is_instance_valid(b):
			continue
		var sel: bool = int(SaveMgr.get_value(str(b.get_meta("opt_group")), -1)) == int(b.get_meta("opt_value"))
		var accent := UiTheme.c("accent")
		var normal := StyleBoxFlat.new()
		normal.bg_color = accent if sel else UiTheme.with_alpha("btn_bg", 0.94)
		normal.border_color = accent
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(8)
		normal.content_margin_left = 10
		normal.content_margin_right = 10
		normal.content_margin_top = 6
		normal.content_margin_bottom = 6
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = accent.lightened(0.08) if sel else UiTheme.c("btn_hover_bg")
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.add_theme_stylebox_override("focus", hover)
		b.add_theme_color_override("font_color", UiTheme.c("panel_bg") if sel else UiTheme.c("text"))
		b.add_theme_color_override("font_hover_color", UiTheme.c("panel_bg") if sel else UiTheme.c("accent"))
		b.add_theme_color_override("font_pressed_color", UiTheme.c("panel_bg") if sel else UiTheme.c("accent"))

func _style_button(b: Control, primary: bool = false) -> void:
	var accent := UiTheme.c("accent")
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
	if primary:
		b.add_theme_stylebox_override("normal", make.call(accent, accent))
		b.add_theme_stylebox_override("hover", make.call(accent.lightened(0.10), accent))
		b.add_theme_stylebox_override("pressed", make.call(accent.darkened(0.10), accent))
		b.add_theme_stylebox_override("focus", make.call(accent.lightened(0.05), accent))
	else:
		b.add_theme_stylebox_override("normal", make.call(UiTheme.with_alpha("btn_bg", 0.90), UiTheme.c("btn_border")))
		b.add_theme_stylebox_override("hover", make.call(UiTheme.with_alpha("btn_hover_bg", 0.95), accent))
		b.add_theme_stylebox_override("pressed", make.call(UiTheme.with_alpha("btn_hover_bg", 0.95), accent))
		b.add_theme_stylebox_override("focus", make.call(UiTheme.with_alpha("btn_hover_bg", 0.95), accent))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if b is Button and not _tb.has(b):
		_tb.append(b)
		(b as Button).set_meta("primary", primary)

## Apply a theme to EVERY themed control (menus, settings, HUD, panels,
## buttons, bars, popups, scrims). Called on boot and when the player switches
## theme in Settings; instant, allocation-free, gameplay unaffected.
func apply_theme(id: int) -> void:
	UiTheme.set_theme(id)
	for rec in _tl:
		var l: Label = rec[0]
		if is_instance_valid(l):
			l.add_theme_color_override("font_color", UiTheme.c(str(rec[1])))
	for b: Button in _tb:
		if not is_instance_valid(b):
			continue
		var prim := bool(b.get_meta("primary"))
		_style_button(b, prim)
		b.add_theme_color_override("font_color", UiTheme.c("panel_bg") if prim else UiTheme.c("text"))
		b.add_theme_color_override("font_hover_color", UiTheme.c("panel_bg") if prim else UiTheme.c("accent"))
		b.add_theme_color_override("font_pressed_color", UiTheme.c("panel_bg") if prim else UiTheme.c("accent"))
	for sb: StyleBoxFlat in _tpanels:
		if is_instance_valid(sb):
			sb.bg_color = UiTheme.with_alpha("panel_bg", float(sb.get_meta("alpha", 0.7)))
			sb.border_color = UiTheme.c("panel_edge")
	for sb: StyleBoxFlat in _tbars:
		if is_instance_valid(sb):
			sb.bg_color = UiTheme.with_alpha("bar_bg", float(sb.get_meta("alpha", 0.9)))
	for rec in _tfills:
		var pb: ProgressBar = rec[0]
		if is_instance_valid(pb):
			var f := pb.get_theme_stylebox("fill")
			if f is StyleBoxFlat:
				(f as StyleBoxFlat).bg_color = UiTheme.c(str(rec[1]))
	for rec in _scrims:
		var cr: ColorRect = rec[0]
		if is_instance_valid(cr):
			cr.color = UiTheme.with_alpha(str(rec[1]), float(rec[2]))
	_rebuild_menu_scrim()
	_refresh_options()
	_refresh_skin_buttons()
	if _preview_snake != null and is_instance_valid(_preview_snake):
		_preview_snake.set_rim(0.55 if UiTheme.is_dark() else 0.12)

func _panel_style(alpha: float = 0.7) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.with_alpha("panel_bg", alpha)
	sb.border_color = UiTheme.c("panel_edge")
	sb.set_meta("alpha", alpha)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18 * _ui_s
	sb.content_margin_right = 18 * _ui_s
	sb.content_margin_top = 12 * _ui_s
	sb.content_margin_bottom = 14 * _ui_s
	_tpanels.append(sb)
	return sb

func _bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.with_alpha("bar_bg", 0.9)
	sb.set_meta("alpha", 0.9)
	sb.set_corner_radius_all(4)
	_tbars.append(sb)
	return sb

func _rebuild_menu_scrim() -> void:
	# full-screen menu backdrop: horizontal gradient scrim — the live 3D arena
	# stays visible on the right while the hero column stays readable
	if _menu_scrim == null or not is_instance_valid(_menu_scrim):
		return
	var base := UiTheme.c("menu_scrim")
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.85, 1.0])
	g.colors = PackedColorArray([base, base, UiTheme.with_alpha("menu_scrim", base.a * 0.35), Color(base.r, base.g, base.b, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 8
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	_menu_scrim.texture = tex
