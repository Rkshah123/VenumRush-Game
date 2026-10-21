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
var _preview_env: Environment = null
var _preview_yaw := 0.0
var _arena_label: Label
var _arena_sub: Label
var _theme_sub: Label
var _pause_btn: Button = null
var _quit_panel: PanelContainer = null
var _pause_settings := false
var _joystick: TouchJoystick = null
var _minimap: ArenaMinimap = null
var _boost_panel: PanelContainer = null
var _menu_column: VBoxContainer = null
var _safe_tick := -1
# Display insets (left, top, right, bottom) in viewport pixels. The gameplay
# HUD stays inside these; the MENU is allowed to bleed to the true screen
# edge and only its interactive column gets the insets back.
var _safe_insets := Vector4.ZERO
# Base breathing margins of the menu column (before safe-area insets).
var _menu_margin_side := 18.0
var _menu_margin_top := 14.0
var _menu_margin_bottom := 14.0
# On-device perf probe (dev): tiny fps/count line revealed by perf_probe(),
# positioned clear of the pause button, radar and joystick.
var _perf_probe: Label = null
var _perf_world = null
var _opt_selected: Button = null
var _page := "main"
var _menu_land := true            # cached orientation of the last menu build
var _play_btn: Button = null      # hero action: gentle live pulse
var _rec_best_lab: Label = null   # personal records in the brand block
var _rec_len_lab: Label = null
var _pause_panel: PanelContainer
var _over_panel: PanelContainer
var _over_title: Label
var _over_lines: Label

# Theme palettes live in UiTheme (BEIGE / DARK). Static role accessors keep
# external callers (match_world popups) theme-aware.
static func role_color(role: String) -> Color:
	return UiTheme.c(role)

var _tl: Array = []            # [Label, role] — re-tinted on theme switch
var _tb: Array = []            # [Button] — restyled on theme switch
var _topt: Array = []          # option/selector buttons (settings)
var _tsliders: Array = []      # [HSlider] — track/grabber re-tinted
var _tchecks: Array = []       # [CheckBox] — check icons re-tinted
var _tpanels: Array = []       # panel StyleBoxFlats
var _tbars: Array = []         # bar background StyleBoxFlats
var _tfills: Array = []        # [ProgressBar, role] — fill colors
var _scrims: Array = []        # [ColorRect, role, alpha]
var _menu_scrim: TextureRect = null
var _menu_title: Label = null
var _menu_logo: TextureRect = null
var _menu_help: VBoxContainer = null
var _ui_s := 1.0               # menu scale factor (set on build / resize)

func _ready() -> void:
	layer = 10
	_ui_s = _ui_scale()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_safe_area()

	_build_gameplay()
	_build_joystick()
	_build_menu()
	_build_pause()
	_build_gameover()
	_build_quit_confirm()
	_build_pause_button()
	show_menu(true)
	set_gameplay_visible(false)
	overlay_group.visible = false
	# sound toggle state
	AudioServer.set_bus_mute(0, int(SaveMgr.get_value("muted", 0)) == 1)
	# restore the saved theme across menus, HUD, panels and scrims
	apply_theme(int(SaveMgr.get_value("theme", UiTheme.LIGHT)))

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
	# dev perf probe (hidden by default): fps + entity counts for the build
	# probe APK; revealed only by perf_probe() from Game.start_play. Attached
	# to root so it stays observable across the pause/death overlays.
	_perf_probe = _mk_label("", 20, "dim", root)
	_perf_probe.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_perf_probe.position = Vector2(16, 116)
	_perf_probe.visible = false

	# whole-arena radar, top-right (reference-frame idea: the whole board at a
	# glance). Lives in the gameplay layer; pause button moved to the top-left.
	_minimap = ArenaMinimap.new()
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	gameplay_group.add_child(_minimap)

	# kill feed — under the radar so the two never overlap
	var feed_panel := VBoxContainer.new()
	feed_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed_panel.anchor_left = 1.0
	feed_panel.anchor_right = 1.0
	feed_panel.offset_left = -330
	feed_panel.offset_right = -14
	feed_panel.offset_top = 186
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
	_boost_panel = boost_panel

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
	if _pause_btn != null:
		_pause_btn.visible = v
		_pause_btn.text = "❚❚"
	if _minimap != null:
		_minimap.live = v
	if _joystick != null:
		_refresh_joystick(v)

func set_paused(paused: bool) -> void:
	# HUD play/pause button mirrors the pause state (spec §3)
	if _pause_btn != null:
		_pause_btn.text = "▶" if paused else "❚❚"
	if _minimap != null:
		_minimap.live = not paused and gameplay_group.visible

# ---------------------------------------------------------------- joystick

func _build_joystick() -> void:
	# Mobile touch stick: floats to wherever the first finger lands (so "drag
	# anywhere" works) and never steals a tap that belongs to a HUD control.
	_joystick = TouchJoystick.new()
	_joystick.name = "Joystick"
	_joystick.ui_blocker = blocks_touch
	gameplay_group.add_child(_joystick)
	_refresh_joystick(false)

## True when a HUD control owns this screen point. The stick consults this so a
## tap on the pause button (or a dialog button) reaches the UI instead.
func blocks_touch(p: Vector2) -> bool:
	if root == null:
		return false
	return _control_owns(root, p)

func _control_owns(n: Node, p: Vector2) -> bool:
	for c in n.get_children():
		if c is Control:
			var cc := c as Control
			if cc == _joystick or not cc.is_visible_in_tree():
				continue
			# Only real widgets own a tap. Layout containers default to STOP but
			# cover the screen (the centre "announce" VBox does), and blocking
			# those would make half the board dead to the stick.
			if cc is BaseButton and cc.mouse_filter == Control.MOUSE_FILTER_STOP \
					and cc.get_global_rect().has_point(p):
				return true
			if _control_owns(cc, p):
				return true
	return false

func minimap() -> ArenaMinimap:
	return _minimap

func joystick() -> TouchJoystick:
	return _joystick

func _is_touch_device() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")

func _refresh_joystick(in_gameplay: bool) -> void:
	if _joystick == null:
		return
	# Touch devices get the floating stick in BOTH 2D and 3D so the control
	# scheme is identical everywhere; the stick follows the finger, so it is a
	# readout of "drag anywhere", not a fixed on-screen widget.
	var want := in_gameplay and (_is_touch_device() or force_joystick_dev())
	_joystick.enabled = want
	if not want:
		_joystick.force_release()
	_move_hud_for_joystick(want)
	_refresh_joystick_layout()

func force_joystick_dev() -> bool:
	return _joystick != null and _joystick.force_joystick_dev

func _move_hud_for_joystick(on: bool) -> void:
	# the stick owns the bottom-left corner: shift boost/ability panels to the
	# bottom-right so nothing overlaps (spec sections 2 and 7)
	var w := 268.0
	if on:
		for p in [_boost_panel, _ability_panel]:
			if p == null or not is_instance_valid(p):
				continue
			p.anchor_left = 1.0
			p.anchor_right = 1.0
			p.offset_left = -w - 18.0
			p.offset_right = -18.0
			p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	else:
		for p in [_boost_panel, _ability_panel]:
			if p == null or not is_instance_valid(p):
				continue
			p.anchor_left = 0.0
			p.anchor_right = 0.0
			p.offset_left = 18.0
			p.offset_right = w
			p.grow_horizontal = Control.GROW_DIRECTION_END

func _refresh_joystick_layout() -> void:
	if _joystick == null:
		return
	var screen := Vector2(DisplayServer.screen_get_size())
	var vs := get_viewport().get_visible_rect().size
	var sl := 0.0
	var sb := 0.0
	var sr := 0.0
	if screen.x > 1.0 and screen.y > 1.0:
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		if safe.size.x > 1 and safe.size.y > 1:
			sl = maxf(0.0, float(safe.position.x)) * (vs.x / screen.x)
			sb = maxf(0.0, float(screen.y - (safe.position.y + safe.size.y))) * (vs.y / screen.y)
			sr = maxf(0.0, float(screen.x - (safe.position.x + safe.size.x))) * (vs.x / screen.x)
	var s := clampf(vs.y / 900.0, 0.8, 1.5)
	_joystick.configure(s, sl + root.offset_left, sb + root.offset_bottom)
	if _minimap != null:
		_minimap.configure(s, _minimap.radius)
		var mm := _minimap.size
		# top-right, inside the safe area (notch / rounded corners)
		_minimap.offset_left = -mm.x - 14.0 - sr
		_minimap.offset_right = -14.0 - sr
		_minimap.offset_top = 14.0
		_minimap.offset_bottom = 14.0 + mm.y

func set_joystick_mode(_is_2d: bool) -> void:
	# graphics mode changed: the stick is available in both modes, but refresh
	# so the boost/ability panels re-flow if the layout changed
	_refresh_joystick(gameplay_group.visible)

func set_score(v: int) -> void:
	if score_label.text == str(v):
		return
	score_label.text = str(v)
	# punchy score feedback (spec §7)
	score_label.pivot_offset = score_label.size * 0.5
	score_label.scale = Vector2(1.18, 1.18)
	var tw := score_label.create_tween()
	tw.tween_property(score_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.custom_minimum_size = Vector2(300, 0)
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
	# FULL-SCREEN mobile-first menu (no centered card): the whole viewport is
	# the title screen over the dedicated MenuWorld cinematic scene — the
	# gameplay arena is never behind it. Brand block up top, big tappable
	# actions anchored low (portrait) or brand-left / actions-right
	# (landscape + desktop). A top→bottom scrim keeps labels readable.
	if menu_group != null and is_instance_valid(menu_group):
		menu_group.queue_free()
	menu_group = null
	_menu_main = null
	_menu_settings = null
	_menu_skins = null
	_menu_help = null
	_menu_logo = null
	_menu_title = null
	_menu_column = null
	_play_btn = null
	_rec_best_lab = null
	_rec_len_lab = null
	_arena_label = null
	_arena_sub = null
	_theme_sub = null

	_ui_s = _ui_scale()
	var vs := get_viewport().get_visible_rect().size
	var land: bool = vs.x >= vs.y
	_menu_land = land

	menu_group = Control.new()
	menu_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu_group)

	_menu_scrim = TextureRect.new()
	_menu_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_menu_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_group.add_child(_menu_scrim)
	_rebuild_menu_scrim()

	# One full-bleed page column with breathing margins from the safe area.
	# The group itself extends past the HUD safe root for the screen edge; the
	# interactive column below adds the display insets back.
	_menu_column = VBoxContainer.new()
	_menu_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_column.add_theme_constant_override("separation", int(6 * _ui_s))
	_menu_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_group.add_child(_menu_column)
	_menu_margin_side = maxf(18.0, vs.x * (0.075 if land else 0.06))
	_menu_margin_top = maxf(14.0, vs.y * (0.03 if land else 0.04))
	# Negative = inset from the bottom edge. The old positive value pushed the
	# card INTO the device safe-area/taskbar strip and left only ~8 px of air.
	_menu_margin_bottom = maxf(14.0, vs.y * (0.045 if land else 0.05))
	_apply_menu_bleed()

	# ---------------------------------------------------------- brand block
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", int(6 * _ui_s))
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	var logo := TextureRect.new()
	logo.texture = load("res://icon.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var logo_px := (120.0 if land else 140.0) * _ui_s
	logo.custom_minimum_size = Vector2(logo_px, logo_px)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_child(logo)
	_menu_logo = logo
	var title := _mk_label("VENOMRUSH", int((48 if land else 52) * _ui_s), "accent", brand)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", UiTheme.c("title_shadow"))
	title.add_theme_constant_override("shadow_offset_y", 4)
	_menu_title = title
	var tag := _mk_label("Evolve. Hunt. Dominate.", int(18 * _ui_s), "dim", brand)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# personal records: quiet identity line under the tagline
	var rec := HBoxContainer.new()
	rec.alignment = BoxContainer.ALIGNMENT_CENTER
	rec.add_theme_constant_override("separation", 14)
	brand.add_child(rec)
	_rec_best_lab = _mk_label("", int(15 * _ui_s), "accent", rec)
	_rec_len_lab = _mk_label("", int(15 * _ui_s), "dim", rec)
	_refresh_records()

	# ---------------------------------------------------------- action stack
	var act := VBoxContainer.new()
	act.add_theme_constant_override("separation", int(10 * _ui_s))
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_main = VBoxContainer.new()
	_menu_main.add_theme_constant_override("separation", int(10 * _ui_s))
	act.add_child(_menu_main)
	# One dominant primary action, then full-width secondary actions: every
	# label keeps a huge, easy-to-hit slab instead of shrinking into a grid.
	_play_btn = _menu_button(_menu_main, "PLAY", func(): play_pressed.emit(), true)
	_menu_button(_menu_main, "SNAKES", func(): _menu_page("skins"))
	_menu_button(_menu_main, "HOW TO PLAY", func(): _menu_page("help"))
	_menu_button(_menu_main, "SETTINGS", func(): _swap_menu(false))
	_menu_button(_menu_main, "QUIT", func(): quit_pressed.emit())

	# ------------------------------------------------ arena + theme sections
	# Two SEPARATE labelled panels, each with its own controls and selected
	# state. They never touch each other's save key: switching theme cannot
	# reset the arena and switching arena cannot reset the theme.
	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", int(10 * _ui_s))
	sel_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_main.add_child(sel_row)
	_build_arena_section(sel_row)
	_build_theme_section(sel_row)

	var hint := _mk_label("", int(13 * _ui_s), "dim", _menu_main)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "mouse steers, LMB boosts" if not _is_touch_device() else "drag steers, 2nd finger boosts"
	hint.text = "OFFLINE BUILD v1.1 - " + hint.text

	# ---------------------------------------------------------- orientation
	# The action column sits on a soft themed card so every page — SNAKES, HOW
	# TO PLAY, SETTINGS included — stays readable while the animated scene
	# runs behind, and the main stack gains a clean slab look.
	var act_card := PanelContainer.new()
	var act_sb := _panel_style(0.55)
	act_sb.set_corner_radius_all(18)
	act_sb.content_margin_left = 20 * _ui_s
	act_sb.content_margin_right = 20 * _ui_s
	act_sb.content_margin_top = 16 * _ui_s
	act_sb.content_margin_bottom = 16 * _ui_s
	act_card.add_theme_stylebox_override("panel", act_sb)
	if not _tpanels.has(act_sb):
		_tpanels.append(act_sb)
		act_sb.set_meta("alpha", 0.55)
	act_card.add_child(act)

	if land:
		var page := HBoxContainer.new()
		page.add_theme_constant_override("separation", int(24 * _ui_s))
		_menu_column.add_child(page)
		brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		brand.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.add_child(brand)
		page.add_child(act_card)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		act_card.custom_minimum_size = Vector2(clampf(vs.x * 0.52, 420.0 * _ui_s, 980.0 * _ui_s), 0.0)
		act_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		_menu_column.add_child(brand)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu_column.add_child(spacer)
		_menu_column.add_child(act_card)

	_build_settings_page(act)
	_build_help_menu(act)
	_build_skins_menu(act)
	_menu_skins.visible = false
	_menu_page(_page)
	_refresh_options()
	call_deferred("_animate_menu_intro")

func _build_settings_page(act: Container) -> void:
	_menu_settings = VBoxContainer.new()
	_menu_settings.add_theme_constant_override("separation", int(9 * _ui_s))
	act.add_child(_menu_settings)
	_menu_settings.visible = false
	var head := _mk_label("SETTINGS", int(30 * _ui_s), "accent", _menu_settings)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _mk_label("AUDIO  ·  LOOK  ·  CONTROL", int(12 * _ui_s), "dim", _menu_settings)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, int(4 * _ui_s))
	_menu_settings.add_child(gap)
	var svl := _mk_label("MASTER VOLUME", int(15 * _ui_s), "dim", _menu_settings)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(SaveMgr.get_value("master_volume", 0.85))
	slider.custom_minimum_size = Vector2(0, int(34 * _ui_s))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): AudioMgr.set_master_volume(v))
	_style_slider(slider)
	_menu_settings.add_child(slider)
	if not _is_touch_device():
		var full := CheckBox.new()
		full.text = "FULLSCREEN"
		full.button_pressed = bool(SaveMgr.get_value("fullscreen", false))
		_style_button(full)
		_style_checkbox(full)
		full.add_theme_font_size_override("font_size", int(16 * _ui_s))
		full.pressed.connect(func():
			var on := not bool(SaveMgr.get_value("fullscreen", false))
			SaveMgr.set_value("fullscreen", on)
			if on:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		)
		_menu_settings.add_child(full)
	var thl := _mk_label("THEME", int(15 * _ui_s), "dim", _menu_settings)
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 8)
	_menu_settings.add_child(trow)
	for t in UiTheme.NAMES.size():
		var tid := t
		_option_button(trow, str(UiTheme.NAMES[tid]), "theme", tid, func(): _set_theme(tid))
	var gml := _mk_label("GRAPHICS MODE", int(15 * _ui_s), "dim", _menu_settings)
	var grow := HBoxContainer.new()
	grow.alignment = BoxContainer.ALIGNMENT_CENTER
	grow.add_theme_constant_override("separation", 8)
	_menu_settings.add_child(grow)
	_option_button(grow, "2D TOP-DOWN", "gfx_mode", 0, func(): _set_mode(0))
	_option_button(grow, "3D TPS", "gfx_mode", 1, func(): _set_mode(1))
	# Sound lives here now that the main menu is reserved for the two big
	# selection sections. Same save key / same bus mute as before.
	var sndl := _mk_label("SOUND", int(15 * _ui_s), "dim", _menu_settings)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 8)
	_menu_settings.add_child(srow)
	_option_button(srow, "SOUND ON", "muted", 0, func(): _set_muted(0))
	_option_button(srow, "SOUND OFF", "muted", 1, func(): _set_muted(1))
	_menu_button(_menu_settings, "BACK", func(): _swap_menu(true))

## A labelled selector slab used by the main menu. The accent dot makes the
## section readable as a distinct control group at a glance; every panel owns
## its own value/state, so the two selections never bleed into each other.
func _selector_panel(parent: Container, title: String) -> Dictionary:
	var panel := PanelContainer.new()
	var sb := _panel_style(0.40)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14 * _ui_s
	sb.content_margin_right = 14 * _ui_s
	sb.content_margin_top = 10 * _ui_s
	sb.content_margin_bottom = 10 * _ui_s
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(5 * _ui_s))
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(7 * _ui_s))
	v.add_child(head)
	var dot := _mk_label("●", int(12 * _ui_s), "accent", head)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tl := _mk_label(title, int(14 * _ui_s), "dim", head)
	tl.add_theme_constant_override("outline_size", 0)
	return {"panel": panel, "vbox": v}

func _build_arena_section(parent: Container) -> void:
	# ARENA SELECTION: pager over the four real biome presets.
	var rec := _selector_panel(parent, "ARENA SELECTION")
	var v: VBoxContainer = rec["vbox"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(5 * _ui_s))
	v.add_child(row)
	var prev_b := _nav_button("◄")
	prev_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prev_b.pressed.connect(func(): AudioMgr.play("click"); arena_shift.emit(-1))
	row.add_child(prev_b)
	_arena_label = _mk_label("VERDANT VALLEY", int(19 * _ui_s), "accent", row)
	_arena_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arena_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_arena_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_arena_label.custom_minimum_size = Vector2(0, 48 * _ui_s)
	var next_b := _nav_button("►")
	next_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next_b.pressed.connect(func(): AudioMgr.play("click"); arena_shift.emit(1))
	row.add_child(next_b)
	_arena_sub = _mk_label("", int(12 * _ui_s), "dim", v)
	_arena_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_arena_chrome()

func _build_theme_section(parent: Container) -> void:
	# THEME SELECTION: its own segmented control + palette preview. The shared
	# option group ("theme") is refreshed with the Settings pills, so both
	# entry points always show one truthful active state.
	var rec := _selector_panel(parent, "THEME SELECTION")
	var v: VBoxContainer = rec["vbox"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * _ui_s))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	for t in UiTheme.NAMES.size():
		var tid := t
		var b := _option_button(row, str(UiTheme.NAMES[tid]), "theme", tid, func(): _set_theme(tid))
		b.custom_minimum_size = Vector2(0, (60 if _is_touch_device() else 54) * _ui_s)
		b.add_theme_font_size_override("font_size", int(18 * _ui_s))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_theme_sub = _mk_label("", int(12 * _ui_s), "dim", v)
	_theme_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_theme_chrome()

func _refresh_arena_chrome() -> void:
	if _arena_label == null or not is_instance_valid(_arena_label):
		return
	var key := str(SaveMgr.get_value("arena", "valley"))
	var preset := ArenaPresets.get_preset(key)
	_arena_label.text = str(preset.get("name", "VERDANT VALLEY"))
	if _arena_sub != null and is_instance_valid(_arena_sub):
		var idx: int = ArenaPresets.ORDER.find(key)
		_arena_sub.text = "BIOME %d OF %d  ·  ARENA AFFECTS THE MATCH" % [
			(idx + 1) if idx >= 0 else 1, ArenaPresets.ORDER.size()]

func _refresh_theme_chrome() -> void:
	var id := int(SaveMgr.get_value("theme", UiTheme.LIGHT))
	if _theme_sub != null and is_instance_valid(_theme_sub):
		_theme_sub.text = "%s PALETTE  ·  MENU + HUD" % UiTheme.NAMES[clampi(id, 0, UiTheme.NAMES.size() - 1)]
func _refresh_records() -> void:
	# identity line under the tagline: personal bests from the save file
	if _rec_best_lab == null or not is_instance_valid(_rec_best_lab):
		return
	var best := int(SaveMgr.get_value("best_score", 0))
	var blen := float(SaveMgr.get_value("best_length", 0.0))
	if best <= 0:
		_rec_best_lab.text = ""
		_rec_len_lab.text = ""
	else:
		_rec_best_lab.text = "BEST %d" % best
		_rec_len_lab.text = "TOP LENGTH %d" % int(round(blen))

func _ensure_menu_layout() -> void:
	# rotations happen while hidden (in-game); rebuild the page for the new
	# orientation the moment the menu comes back (or while visible)
	if menu_group == null or not is_instance_valid(menu_group) or not menu_group.visible:
		return
	var vs := get_viewport().get_visible_rect().size
	if (vs.x >= vs.y) != _menu_land:
		_build_menu()   # rebuild keeps the active page and replays the intro

func _set_theme(id: int) -> void:
	SaveMgr.set_value("theme", id)
	apply_theme(id)
	AudioMgr.play("click")
	theme_changed.emit(id)

func _set_mode(id: int) -> void:
	# Direct selection (never a toggle). Re-selecting the active mode just
	# re-affirms the highlight — no pointless world rebuild.
	if int(SaveMgr.get_value("gfx_mode", 1)) != id:
		SaveMgr.set_value("gfx_mode", id)
		AudioMgr.play("click")
		_refresh_options()
		mode_changed.emit(id)
	else:
		AudioMgr.play("click")
		_refresh_options()

func _set_muted(on_off: int) -> void:
	# 0 = sound on, 1 = sound off (title-screen quick toggle)
	SaveMgr.set_value("muted", on_off)
	AudioServer.set_bus_mute(0, on_off == 1)
	AudioMgr.play("click")
	_refresh_options()

# ---------------------------------------------------------------- how to play

func _build_help_menu(vroot: Container) -> void:
	_menu_help = VBoxContainer.new()
	_menu_help.add_theme_constant_override("separation", int(10 * _ui_s))
	_menu_help.custom_minimum_size = Vector2(0, 0)
	vroot.add_child(_menu_help)
	_menu_help.visible = false
	var h := _mk_label("HOW TO PLAY", int(30 * _ui_s), "accent", _menu_help)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rows := [
		["GOAL", "Eat fruit to grow. Cut rivals by ramming their body."],
		["POWER ORBS", "Magnet Pulse vacuums fruit; Shield blocks body hits."],
		["GROW", "Every fruit adds length. Long snakes score faster."],
	]
	if OS.has_feature("android"):
		rows.append(["CONTROLS", "Drag anywhere to steer. Lift to go straight."])
		rows.append(["BOOST", "Hold a second finger to sprint."])
	else:
		rows.append(["CONTROLS", "Move the mouse to steer - the snake follows it."])
		rows.append(["BOOST", "Hold Left Mouse or SPACE to sprint."])
	for r in rows:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _panel_style(0.35))
		var line := _mk_label("%s   %s" % [r[0], r[1]], int(17 * _ui_s), "dim", panel)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_menu_help.add_child(panel)
	_menu_button(_menu_help, "BACK", func(): _menu_page("main"))

# ---------------------------------------------------------------- intro anim

func _animate_menu_intro() -> void:
	# logo pops in, then the menu items stagger in (spec §5/§9)
	if _menu_logo != null and is_instance_valid(_menu_logo):
		_menu_logo.pivot_offset = _menu_logo.custom_minimum_size * 0.5
		_menu_logo.scale = Vector2(0.62, 0.62)
		_menu_logo.modulate.a = 0.0
		var tw := _menu_logo.create_tween()
		tw.set_parallel(true)
		tw.tween_property(_menu_logo, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_menu_logo, "modulate:a", 1.0, 0.4)
	var items: Array = []
	if _menu_title != null:
		items.append(_menu_title)
	if _menu_main != null:
		items.append(_menu_main)
	for i in items.size():
		var c: CanvasItem = items[i]
		if not is_instance_valid(c):
			continue
		c.modulate.a = 0.0
		var tw2 := c.create_tween()
		tw2.tween_interval(0.22 + 0.09 * float(i))
		tw2.tween_property(c, "modulate:a", 1.0, 0.28)

func _swap_menu(show_main: bool) -> void:
	if _pause_settings:
		# returning from settings opened mid-match -> back to the PAUSE overlay
		_pause_settings = false
		show_menu(false)
		_menu_page("main")
		show_pause(true)
		return
	_menu_page("main" if show_main else "settings")

func current_page() -> String:
	return _page

func _menu_page(page: String) -> void:
	_page = page
	_menu_main.visible = page == "main"
	_menu_settings.visible = page == "settings"
	_menu_skins.visible = page == "skins"
	if _menu_help != null:
		_menu_help.visible = page == "help"
	if _preview_snake != null:
		_preview_snake.set_physics_process(page == "skins")
	if _preview_vp != null:
		# render every frame only on the skins page; keep a last-frame image elsewhere
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if page == "skins" else SubViewport.UPDATE_ONCE
	call_deferred("_fit_menu_column")
	AudioMgr.play("click")

# ---------------------------------------------------------------- skins (spec §11)

func _build_skins_menu(vroot: Container) -> void:
	_menu_skins = VBoxContainer.new()
	_menu_skins.add_theme_constant_override("separation", 10)
	vroot.add_child(_menu_skins)
	var st := _mk_label("CHOOSE YOUR SERPENT", int(26 * _ui_s), "accent", _menu_skins)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# live 3D preview: a real Snake slithering in a small viewport — full
	# menu column width and tall enough to read the head + scale detail
	var pv := SubViewportContainer.new()
	pv.stretch = true
	pv.custom_minimum_size = Vector2(0, 240 * _ui_s)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	env.background_color = Color(0.03, 0.05, 0.08, 1.0) if UiTheme.is_dark() \
		else Color(0.96, 0.91, 0.82, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.62) if UiTheme.is_dark() \
		else Color(0.72, 0.64, 0.52)
	env.ambient_light_energy = 1.2 if UiTheme.is_dark() else 0.95
	amb.environment = env
	_preview_env = env
	vp.add_child(amb)
	_preview_cam = Camera3D.new()
	_preview_cam.position = Vector3(0, 2.4, 4.6)
	vp.add_child(_preview_cam)
	_preview_snake = _PreviewSnake.new()
	vp.add_child(_preview_snake)
	_preview_snake.spawn(Vector3.ZERO, Vector3(0, 0, 1), 6.0)
	_preview_snake.set_physics_process(false)   # starts when the skins page opens
	var cur := int(SaveMgr.get_value("skin", 0))
	var sk0 := SkinCatalog.get_skin(cur)
	_preview_snake.apply_skin(sk0["dorsal"], sk0["accent"], sk0["belly"], sk0["seed"], int(sk0["pattern"]))

	# grid of skin buttons
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	_menu_skins.add_child(grid)
	for i in SkinCatalog.count():
		var b := _menu_button(grid, "", func(): _pick_skin(i))
		b.custom_minimum_size = Vector2(296 * _ui_s, 52 * _ui_s)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", int(18 * _ui_s))
		_skin_buttons.append(b)
	_refresh_skin_buttons()
	_menu_button(_menu_skins, "BACK", func(): _swap_menu(true))

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
	# keep the HUD inside the mobile safe area across rotations / resizes
	if int(Time.get_ticks_msec() / 500) != _safe_tick:
		_safe_tick = int(Time.get_ticks_msec() / 500)
		_apply_safe_area()
	# gentle pulse on the ACTIVE mode/theme button so the current selection is
	# obvious at a glance (spec §1)
	if _opt_selected != null and is_instance_valid(_opt_selected) and menu_group != null and menu_group.visible:
		var pulse := 0.88 + 0.12 * sin(Time.get_ticks_msec() * 0.004)
		_opt_selected.modulate.a = pulse
	# slow breathing pulse on the menu title (ambient life on the start screen)
	if menu_group != null and menu_group.visible and _menu_title != null and is_instance_valid(_menu_title):
		_menu_title.modulate.a = 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.0016)
	# hero PLAY action: gentle alpha heartbeat (no transform churn)
	if menu_group != null and menu_group.visible and _play_btn != null and is_instance_valid(_play_btn):
		_play_btn.self_modulate.a = 0.94 + 0.06 * sin(Time.get_ticks_msec() * 0.0042)
	if _menu_skins != null and _menu_skins.visible and _preview_snake != null and _preview_vp != null:
		var target: Vector3 = _preview_snake.head_pos + Vector3.UP * 0.9
		_preview_yaw += delta * 0.7
		_preview_cam.position = target + Vector3(sin(_preview_yaw) * 3.7, 2.4, cos(_preview_yaw) * 3.7)
		_preview_cam.look_at(target)
	# on-device perf readout (probe builds only): read every 0.5 s
	if _perf_probe != null and _perf_probe.visible:
		if is_instance_valid(_perf_world):
			if _safe_tick != _perf_probe.get_meta("tick", -1):
				_perf_probe.set_meta("tick", _safe_tick)
				var txt := "fps %d · phy %.1f · proc %.1f" % [
					Engine.get_frames_per_second(),
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]
				if "food" in _perf_world:
					txt += " · sn %d · orbs %d" % [
						_perf_world.snake_count(), _perf_world.food.count_alive()]
				else:
					txt += " · menu"
				_perf_probe.text = txt
		else:
			_perf_probe.visible = false

## Reveal/refresh the on-device perf probe (probe APK only).
func perf_probe(on: bool, world) -> void:
	if _perf_probe == null:
		return
	_perf_world = world
	_perf_probe.visible = on
	if not on:
		_perf_world = null

class _PreviewSnake extends Snake:
	# menu preview: glides in a continuous circle so the skin reads from all sides
	func _steer(_delta: float) -> void:
		desired_dir = Vector3(sin(heading + 0.55), 0.0, cos(heading + 0.55)).normalized()

func set_arena(key: String) -> void:
	# keep the labelled ARENA SELECTION panel truthful without touching theme
	if _arena_label == null or not is_instance_valid(_arena_label):
		return
	var preset := ArenaPresets.get_preset(key)
	_arena_label.text = str(preset.get("name", "VALLEY"))
	if _arena_sub != null and is_instance_valid(_arena_sub):
		var idx: int = ArenaPresets.ORDER.find(key)
		_arena_sub.text = "BIOME %d OF %d  ·  ARENA AFFECTS THE MATCH" % [
			(idx + 1) if idx >= 0 else 1, ArenaPresets.ORDER.size()]

func show_menu(v: bool) -> void:
	menu_group.visible = v
	overlay_group.visible = false if v else overlay_group.visible
	if v:
		_refresh_records()
		_ensure_menu_layout()   # orientation may have flipped while hidden
		call_deferred("_fit_menu_column")

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
	p.custom_minimum_size = Vector2(460 * _ui_scale(), 0)   # wide tappable rows
	_pause_panel.add_child(p)
	_mk_label("PAUSED", int(40 * _ui_scale()), "text", p)
	_menu_button(p, "RESUME", func(): resume_pressed.emit())
	_menu_button(p, "RESTART MATCH", func(): restart_pressed.emit())
	_menu_button(p, "SETTINGS", func(): _open_settings_from_pause())
	_menu_button(p, "MAIN MENU", func(): tomenu_pressed.emit())
	var hint := _mk_label("ESC TO RESUME" if not OS.has_feature("android") else "BACK / TAP RESUME", 13, "dim", p)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _open_settings_from_pause() -> void:
	# settings opened mid-match: keep the world frozen, remember where to go back
	_pause_settings = true
	overlay_group.visible = false
	show_menu(true)
	_menu_page("settings")

func _build_pause_button() -> void:
	# Always-visible play/pause control (spec section 3) - TOP-LEFT of the HUD
	# in both 2D and 3D modes (the top-right corner belongs to the arena radar);
	# lives on `root` so it stays tappable while paused
	_pause_btn = Button.new()
	_pause_btn.text = "||"
	_pause_btn.tooltip_text = "PAUSE / RESUME"
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_pause_btn.offset_left = 16
	_pause_btn.offset_right = 76
	_pause_btn.offset_top = 14
	_pause_btn.offset_bottom = 74
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_style_button(_pause_btn, true)
	_pause_btn.add_theme_font_size_override("font_size", 24)
	_pause_btn.add_theme_color_override("font_color", UiTheme.c("panel_bg"))
	_pause_btn.pressed.connect(func(): AudioMgr.play("click"); pause_pressed.emit())
	root.add_child(_pause_btn)
	_pause_btn.visible = false

func show_pause(v: bool) -> void:
	_pause_panel.visible = v
	overlay_group.visible = v or (_quit_panel != null and _quit_panel.visible)
	# the stick is only for live play (spec section 2)
	_refresh_joystick(not v and gameplay_group.visible)

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
	p.custom_minimum_size = Vector2(460 * _ui_scale(), 0)   # wide tappable rows
	_over_panel.add_child(p)
	_over_title = _mk_label("ELIMINATED", int(44 * _ui_scale()), "warn", p)
	_over_lines = _mk_label("", int(17 * _ui_scale()), "text", p)
	_menu_button(p, "RESTART", func(): restart_pressed.emit())
	_menu_button(p, "MAIN MENU", func(): tomenu_pressed.emit())

func show_gameover_hidden() -> void:
	overlay_group.visible = false
	_over_panel.visible = false
	_pause_panel.visible = false
	if _quit_panel != null:
		_quit_panel.visible = false

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
	if _quit_panel != null:
		_quit_panel.visible = false

# ---------------------------------------------------------------- quit confirm

func _build_quit_confirm() -> void:
	# "Do you want to close the game?" - themed, full-screen dialog (spec
	# section 6). Cancel returns to the current screen without interrupting.
	_quit_panel = PanelContainer.new()
	_quit_panel.add_theme_stylebox_override("panel", _panel_style(0.96))
	_quit_panel.set_anchors_preset(Control.PRESET_CENTER)
	_quit_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_quit_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_quit_panel.visible = false
	overlay_group.add_child(_quit_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(14 * _ui_s))
	v.custom_minimum_size = Vector2(340 * _ui_s, 0)
	_quit_panel.add_child(v)
	var msg := _mk_label("Do you want to close the game?", int(19 * _ui_s), "text", v)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var yes := _menu_button(v, "YES, QUIT", func(): quit_confirmed.emit())
	yes.set_meta("btn_role", "warn")
	yes.add_theme_color_override("font_color", UiTheme.c("warn"))
	_menu_button(v, "CANCEL", func(): show_quit_confirm(false))

func show_quit_confirm(v: bool) -> void:
	if _quit_panel == null:
		return
	_quit_panel.visible = v
	if v:
		_pause_panel.visible = false
		_over_panel.visible = false
		overlay_group.visible = true
		AudioMgr.play("click")

# ---------------------------------------------------------------- signals (pause/gameover)

signal resume_pressed
signal restart_pressed
signal tomenu_pressed
signal theme_changed(id: int)
signal mode_changed(id: int)
signal pause_pressed
signal quit_confirmed

# ---------------------------------------------------------------- helpers

func _apply_safe_area() -> void:
	# The gameplay HUD stays clear of notches / system bars on mobile. The menu
	# is intentionally different: it expands past this safe root so its themed
	# background covers the camera cutout too, and only its interactive column
	# gets the inset back. No-op on desktop.
	if root == null or not is_inside_tree():
		return
	var screen := Vector2(DisplayServer.screen_get_size())
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return
	var left := 0.0
	var top := 0.0
	var right := 0.0
	var bottom := 0.0
	if screen.x > 1.0 and screen.y > 1.0:
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		if safe.size.x > 1 and safe.size.y > 1:
			var sx := vs.x / screen.x
			var sy := vs.y / screen.y
			left = maxf(0.0, float(safe.position.x) * sx)
			top = maxf(0.0, float(safe.position.y) * sy)
			right = maxf(0.0, float(screen.x - (safe.position.x + safe.size.x)) * sx)
			bottom = maxf(0.0, float(screen.y - (safe.position.y + safe.size.y)) * sy)
	# keep insets sane: never eat more than 8% of a screen edge
	_safe_insets = Vector4(minf(left, vs.x * 0.08), minf(top, vs.y * 0.08),
		minf(right, vs.x * 0.08), minf(bottom, vs.y * 0.08))
	root.offset_left = _safe_insets.x
	root.offset_top = _safe_insets.y
	root.offset_right = -_safe_insets.z
	root.offset_bottom = -_safe_insets.w
	_refresh_joystick_layout()
	_ensure_menu_layout()   # portrait <-> landscape flips rebuild the page
	_apply_menu_bleed()
	call_deferred("_fit_menu_column")

## Let the menu (especially its full-screen scrim) draw over the display
## cutout while keeping every interactive row inside the safe viewport.
func _apply_menu_bleed() -> void:
	if menu_group == null or not is_instance_valid(menu_group):
		return
	menu_group.offset_left = -_safe_insets.x
	menu_group.offset_top = -_safe_insets.y
	menu_group.offset_right = _safe_insets.z
	menu_group.offset_bottom = _safe_insets.w
	if _menu_column != null and is_instance_valid(_menu_column):
		_menu_column.offset_left = _menu_margin_side + _safe_insets.x
		_menu_column.offset_top = _menu_margin_top + _safe_insets.y
		_menu_column.offset_right = -(_menu_margin_side + _safe_insets.z)
		_menu_column.offset_bottom = -(_menu_margin_bottom + _safe_insets.w)

func _ui_scale() -> float:
	# Menu/HUD scale. Width matters as much as height: a portrait phone must
	# never overflow horizontally and a landscape one must never overflow
	# vertically (the column is auto-fit on top of this, spec sections 3/4).
	var vs := Vector2(1280, 720)
	if is_inside_tree():
		vs = get_viewport().get_visible_rect().size
	return clampf(minf(vs.y / 900.0, vs.x / 640.0), 0.72, 1.5)

func _fit_menu_column() -> void:
	# Guarantee the menu column always fits the safe viewport: if it is taller
	# than the screen (short landscape phone), scale the whole column about
	# its center so every button stays visible and tappable — no scrolling,
	# no clipping (spec section 3).
	var v: VBoxContainer = _menu_column
	if v == null or not is_instance_valid(v):
		return
	var vs := get_viewport().get_visible_rect().size
	var avail := vs.y - _safe_insets.y - _safe_insets.w - 8.0
	var need := v.get_combined_minimum_size().y
	v.pivot_offset = v.size * 0.5
	var s := 1.0
	if need > avail and need > 1.0:
		s = clampf(avail / need, 0.5, 1.0)
	v.scale = Vector2(s, s)

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
	b.custom_minimum_size = Vector2(56 * _ui_s, 56 * _ui_s)
	_style_button(b)
	b.add_theme_font_size_override("font_size", int(24 * _ui_s))
	b.add_theme_color_override("font_color", UiTheme.c("text"))
	b.add_theme_color_override("font_hover_color", UiTheme.c("accent"))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

func _menu_button(parent: Node, text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	# never take keyboard focus: focused buttons swallow arrow keys during play
	b.focus_mode = Control.FOCUS_NONE
	# Big, confident game-menu targets. Hero PLAY is ~104 px on a phone and
	# ~88 px on desktop; secondaries stay comfortably above the 48 px touch
	# minimum on every display. Buttons stretch across their column.
	var mob := _is_touch_device()
	var row_h := (104 if primary else 82) if mob else (88 if primary else 70)
	var fs := (34 if mob else 30) if primary else (26 if mob else 23)
	b.custom_minimum_size = Vector2(0, row_h * _ui_s)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b, primary)
	b.add_theme_font_size_override("font_size", int(fs * _ui_s))
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
	b.pivot_offset = b.custom_minimum_size * 0.5
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	# micro hover / press motion (spec §5/§9)
	b.mouse_entered.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.03, 1.03), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	b.mouse_exited.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD))
	b.button_down.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.96, 0.96), 0.06))
	b.button_up.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.03, 1.03), 0.10))
	return b

func _option_button(parent: Node, text: String, group: String, value: int, on_press: Callable) -> Button:
	# settings/title selector button; tapping ALWAYS selects THIS value (never
	# a toggle) and the active one is marked with a pulsing check (spec §1)
	var b := _menu_button(parent, text, on_press)
	b.custom_minimum_size = Vector2((190 if _is_touch_device() else 172) * _ui_s, (58 if _is_touch_device() else 50) * _ui_s)
	b.add_theme_font_size_override("font_size", int(17 * _ui_s))
	b.set_meta("opt_group", group)
	b.set_meta("opt_value", value)
	b.set_meta("opt_text", text)
	_topt.append(b)
	return b

func _refresh_options() -> void:
	_opt_selected = null
	for b: Button in _topt:
		if not is_instance_valid(b):
			continue
		var sel: bool = int(SaveMgr.get_value(str(b.get_meta("opt_group")), -1)) == int(b.get_meta("opt_value"))
		var accent := UiTheme.c("accent")
		var normal := StyleBoxFlat.new()
		normal.bg_color = accent if sel else UiTheme.with_alpha("btn_bg", 0.94)
		normal.border_color = accent
		normal.set_border_width_all(2 if sel else 1)
		normal.set_corner_radius_all(9)
		normal.content_margin_left = 10
		normal.content_margin_right = 10
		normal.content_margin_top = 6
		normal.content_margin_bottom = 6
		normal.shadow_color = Color(accent.r, accent.g, accent.b, 0.16) if sel else Color(0, 0, 0, 0.30)
		normal.shadow_size = 5 if sel else 4
		normal.shadow_offset = Vector2(0, 2)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.shadow_size = 7
		hover.shadow_offset = Vector2(0, 3)
		hover.bg_color = accent.lightened(0.10) if sel else UiTheme.c("btn_hover_bg")
		_add_sheen(b)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.add_theme_stylebox_override("focus", hover)
		b.add_theme_color_override("font_color", UiTheme.c("panel_bg") if sel else UiTheme.c("text"))
		b.add_theme_color_override("font_hover_color", UiTheme.c("panel_bg") if sel else UiTheme.c("accent"))
		b.add_theme_color_override("font_pressed_color", UiTheme.c("panel_bg") if sel else UiTheme.c("accent"))
		b.text = str(b.get_meta("opt_text")) + ("  ●" if sel else "")
		b.scale = Vector2.ONE
		if sel and _opt_selected == null:
			_opt_selected = b

func _style_button(b: Control, primary: bool = false) -> void:
	var accent := UiTheme.c("accent")
	# Themed button "material" (spec §4): one restrained corner radius, a
	# thin border, and a soft drop shadow so the button reads as a solid
	# physical piece seated in the UI. Primary actions glow with the accent
	# tint; secondary actions cast a neutral shadow. Hover lifts the shadow,
	# pressed sinks it — tactile without any texture assets.
	var make := func(bg: Color, border: Color, shadow: Color, blur: int, drop: int) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		sb.shadow_color = shadow
		sb.shadow_size = blur
		sb.shadow_offset = Vector2(0, drop)
		return sb
	if primary:
		var glow := Color(accent.r, accent.g, accent.b, 0.20)
		var glow_hi := Color(accent.r, accent.g, accent.b, 0.30)
		b.add_theme_stylebox_override("normal", make.call(accent, accent, glow, 7, 3))
		b.add_theme_stylebox_override("hover", make.call(accent.lightened(0.08), accent.lightened(0.18), glow_hi, 10, 4))
		b.add_theme_stylebox_override("pressed", make.call(accent.darkened(0.10), accent, glow, 3, 1))
		b.add_theme_stylebox_override("focus", make.call(accent.lightened(0.04), accent.lightened(0.12), glow_hi, 9, 4))
	else:
		var dark := Color(0.0, 0.0, 0.0, 0.38)
		b.add_theme_stylebox_override("normal", make.call(UiTheme.with_alpha("btn_bg", 0.90), UiTheme.c("btn_border"), dark, 6, 3))
		b.add_theme_stylebox_override("hover", make.call(UiTheme.with_alpha("btn_hover_bg", 0.95), accent, dark, 9, 4))
		b.add_theme_stylebox_override("pressed", make.call(UiTheme.with_alpha("btn_hover_bg", 0.95), accent, dark, 2, 1))
		b.add_theme_stylebox_override("focus", make.call(UiTheme.with_alpha("btn_hover_bg", 0.95), accent, dark, 8, 4))
	# locked / disabled buttons keep a visible, dim slab (skins gate grid)
	if b is Button:
		var dis: StyleBoxFlat = make.call(UiTheme.with_alpha("btn_bg", 0.42), UiTheme.c("panel_edge"), Color(0, 0, 0, 0.0), 0, 0)
		(b as Button).add_theme_stylebox_override("disabled", dis)
	_add_sheen(b)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if b is Button and not _tb.has(b):
		_tb.append(b)
		(b as Button).set_meta("primary", primary)

## Hairline "light catch" along the top edge — the cheapest convincing bevel:
## reads as a polished material edge, never as a border. Idempotent because
## apply_theme() re-styles every themed button on every theme switch.
func _add_sheen(b: Control) -> void:
	var line: ColorRect = b.get_node_or_null("Sheen") as ColorRect
	if line == null:
		line = ColorRect.new()
		line.name = "Sheen"
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.anchor_right = 1.0
		line.offset_left = 11
		line.offset_right = -11
		line.offset_top = 2
		line.offset_bottom = 3
		b.add_child(line)
	# Beige theme: a dark hairline reads as an edge; on dark theme a white
	# hairline reads as a light catch. Re-applied on every theme switch.
	line.color = Color(0.0, 0.0, 0.0, 0.07) if not UiTheme.is_dark() \
		else Color(1.0, 1.0, 1.0, 0.07)

## Theme an HSlider so its groove/grabber never fall back to Godot's default
## light-gray control chrome in either palette.
func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = UiTheme.c("bar_bg")
	track.border_color = UiTheme.c("panel_edge")
	track.set_border_width_all(1)
	track.set_corner_radius_all(5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.c("accent")
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	var grab := _slider_grabber()
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", grab)
	s.add_theme_icon_override("grabber_highlight", grab)
	if not _tsliders.has(s):
		_tsliders.append(s)

## A round accent knob with a soft edge; rebuilt on theme switches because
## Godot HSlider grabbers are Texture2Ds, not StyleBoxFlats.
func _slider_grabber() -> Texture2D:
	var accent := UiTheme.c("accent")
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.66, 1.0])
	g.colors = PackedColorArray([accent, accent,
		Color(accent.r, accent.g, accent.b, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 28
	t.height = 28
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t

## Theme a CheckBox (square + check + label) with the current palette icons.
func _style_checkbox(c: CheckBox) -> void:
	var checked := _checkbox_icon(true)
	var unchecked := _checkbox_icon(false)
	c.add_theme_icon_override("checked", checked)
	c.add_theme_icon_override("checked_disabled", checked)
	c.add_theme_icon_override("unchecked", unchecked)
	c.add_theme_icon_override("unchecked_disabled", unchecked)
	if not _tchecks.has(c):
		_tchecks.append(c)

func _checkbox_icon(on: bool) -> Texture2D:
	var col := UiTheme.c("accent").to_html(false)
	var mark := ""
	if on:
		mark = '<path d="M6 12 L10 16 L18 7" fill="none" stroke="#%s" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" />' % col
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect x="3" y="3" width="18" height="18" rx="5" fill="none" stroke="#%s" stroke-width="2"/>%s</svg>' % [col, mark]
	var img := Image.new()
	if img.load_svg_from_string(svg, 2.0) != OK:
		# Remap loading is disabled in some minimal builds: a tiny solid disc is
		# still a visible control state rather than the light default theme.
		var fallback := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		fallback.fill(UiTheme.c("accent"))
		img = fallback
	img.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)

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
		var role := str(b.get_meta("btn_role", "")) if b.has_meta("btn_role") else ""
		var font: Color = UiTheme.c(role) if role != "" else (UiTheme.c("panel_bg") if prim else UiTheme.c("text"))
		var hover: Color = font if role != "" else (UiTheme.c("panel_bg") if prim else UiTheme.c("accent"))
		b.add_theme_color_override("font_color", font)
		b.add_theme_color_override("font_hover_color", hover)
		b.add_theme_color_override("font_pressed_color", hover)
	for sb: StyleBoxFlat in _tpanels:
		if is_instance_valid(sb):
			sb.bg_color = UiTheme.with_alpha("panel_bg", float(sb.get_meta("alpha", 0.7)))
			sb.border_color = UiTheme.c("panel_edge")
	for sb: StyleBoxFlat in _tbars:
		if is_instance_valid(sb):
			sb.bg_color = UiTheme.with_alpha("bar_bg", float(sb.get_meta("alpha", 0.9)))
	for s: HSlider in _tsliders:
		if is_instance_valid(s):
			_style_slider(s)
	for ck: CheckBox in _tchecks:
		if is_instance_valid(ck):
			_style_checkbox(ck)
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
	_refresh_arena_chrome()
	_refresh_theme_chrome()
	_refresh_skin_buttons()
	if _menu_title != null and is_instance_valid(_menu_title):
		_menu_title.add_theme_color_override("font_shadow_color", UiTheme.c("title_shadow"))
	if _preview_env != null and is_instance_valid(_preview_env):
		_preview_env.ambient_light_color = Color(0.50, 0.55, 0.62) if UiTheme.is_dark() \
			else Color(0.72, 0.64, 0.52)
		_preview_env.ambient_light_energy = 1.20 if UiTheme.is_dark() else 0.95
		_preview_env.background_color = Color(0.03, 0.05, 0.08, 1.0) if UiTheme.is_dark() \
			else Color(0.96, 0.91, 0.82, 1.0)
	if _preview_snake != null and is_instance_valid(_preview_snake):
		_preview_snake.set_rim(0.55 if UiTheme.is_dark() else 0.12)
	if _minimap != null and is_instance_valid(_minimap):
		_minimap.queue_redraw()

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
	# FULL-SCREEN menu scrim: a vertical gradient that lets the cinematic
	# snake scene shine in the upper half while deepening toward the bottom
	# so the big action buttons keep strong contrast in every theme.
	if _menu_scrim == null or not is_instance_valid(_menu_scrim):
		return
	var base := UiTheme.c("menu_scrim")
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.72, 1.0])
	g.colors = PackedColorArray([
		UiTheme.with_alpha("menu_scrim", base.a * 0.34),
		UiTheme.with_alpha("menu_scrim", base.a * 0.55),
		UiTheme.with_alpha("menu_scrim", base.a * 0.74),
		UiTheme.with_alpha("menu_scrim", base.a * 0.92)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 512
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	_menu_scrim.texture = tex
