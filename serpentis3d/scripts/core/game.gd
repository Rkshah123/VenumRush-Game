extends Node3D
## Game orchestrator: menu/demo/play states, camera rig, pause flow,
## game-over flow, dev harness (autoplay screenshots).

enum State { MENU, PLAYING, PAUSED, OVER }

var hud: GameHud
var match_world: MatchWorld = null   # built lazily on the first Play (menu boot cost)
var menu_world: MenuWorld            # dedicated home-screen scene (never the arena)
var cam: Camera3D
var state := State.MENU
var _arena_key := "valley"
var _cam_angle := 0.0
var _cam_pos := Vector3(0, 18, 38)
var _gfx_mode := 1               # 0 = 2D top-down, 1 = 3D TPS (settings)
var _cam_2d_h := 27.0            # smoothed 2D camera height (zoom easing)
var _theme_id := 0               # UiTheme.LIGHT / DARK (main-menu + HUD theme)
var _topdown_dist := 0.0        # fixed camera distance fitting the whole arena
var _topdown_dirty := true
var _cam_look := Vector3.ZERO
var _player_last_head := Vector3.ZERO

# dev harness
var _autoplay := false
var _closeup := false
var _shot_menu := false
var _shot_skins := false
var _shot_settings := false
var _theme_test := false
var _uix_test := false
var _mode_test := false
var _joy_test := false
var _dir_test := false
var _ctrl_test := false
var _touchlog := false   # on-device diagnostics: log incoming input events
var _joy_dev := false
var _shot_game := false
var _quit_at := -1.0
var _no_death_dev := false
var _solo_dev := false
var _skip_hud_dev := false
var _onscreen_test := false
var _arena_test := false
var _touch_test := false
var _spawntest := false
var _powertest := false
var _eat_test := false
var _skins_test := false
var _body_test := false
var _climb_test := false
var _video_test := false
var _villain_test := false
var _turn_test := false
var _ai_loop := false
var _drop_test := false
var _tap_test := false
var _turn_probe := 0
var _skin_dev := -1
var _diag_t := 0.0

func _ready() -> void:
	randomize()
	# dev args FIRST so biome overrides land before the world builds
	var args := _collect_dev_args()
	if "--autoplay" in args:
		_autoplay = true
	var arena_dev := ""
	for a in args:
		if a.begins_with("--shot="):
			_autoplay = true
			_shot_game = true
			_quit_at = float(a.substr(7))
		if a.begins_with("--quit") and a.find("=") > 0:
			_quit_at = float(a.substr(a.find("=") + 1))
		if a == "--closeup" or a.begins_with("--closeup="):
			_autoplay = true
			_closeup = true
		if a == "--no-death":
			_autoplay = true
			_no_death_dev = true
		if a == "--solo":
			_autoplay = true
			_solo_dev = true
		if a == "--hud-off":
			_autoplay = true
			_skip_hud_dev = true
		if a == "--onscreen-test":
			_onscreen_test = true
		if a.begins_with("--arena="):
			arena_dev = a.substr(8)
		if a.begins_with("--skin="):
			_skin_dev = int(a.substr(7))
		if a == "--arena-test":
			_autoplay = true
			_arena_test = true
		if a == "--touch-test":
			_autoplay = true
			_touch_test = true
			_solo_dev = true
		if a == "--spawntest":
			_autoplay = true
			_spawntest = true
		if a == "--powertest":
			_autoplay = true
			_powertest = true
			_solo_dev = true      # no AI kills -> the score rate measures food only
			_no_death_dev = true
		if a == "--eat-test":
			_autoplay = true
			_eat_test = true
			_solo_dev = true      # deterministic fruit/eat QA, no rivals stealing fruit
			_no_death_dev = true
		if a == "--skins-test":
			_autoplay = true
			_skins_test = true
		if a == "--body-test":
			_autoplay = true
			_body_test = true
			_solo_dev = true
			_no_death_dev = true
		if a == "--climb-test":
			_autoplay = true
			_climb_test = true
			_solo_dev = true
			_no_death_dev = true
		if a == "--bg-test":
			_autoplay = true
			_video_test = true
		if a == "--villain-test":
			_autoplay = true
			_villain_test = true
		if a == "--ai-loop":
			_autoplay = true
			_ai_loop = true
		if a == "--drop-test":
			_autoplay = true
			_drop_test = true
		if a == "--turn-test":
			_autoplay = true
			_turn_test = true
			_no_death_dev = true
		if a == "--tap-test":
			_autoplay = true
			_tap_test = true
		if a == "--theme-test":
			_autoplay = true
			_theme_test = true
		if a == "--uix-test":
			_autoplay = true
			_uix_test = true
		if a == "--mode-test":
			_autoplay = true
			_mode_test = true
		if a == "--joystick":
			_joy_dev = true
		if a == "--joy-test":
			_autoplay = true
			_joy_test = true
		if a == "--dir-test":
			_autoplay = true
			_dir_test = true
			_no_death_dev = true
			_solo_dev = true
		if a == "--ctrl-test":
			_autoplay = true
			_ctrl_test = true
			_no_death_dev = true
			_solo_dev = true
		if a == "--touchlog":
			_touchlog = true
	_arena_key = str(SaveMgr.get_value("arena", "valley"))
	if arena_dev != "" and ArenaPresets.ALL.has(arena_dev):
		_arena_key = arena_dev
	elif not ArenaPresets.ALL.has(_arena_key):
		_arena_key = "valley"
	_gfx_mode = int(SaveMgr.get_value("gfx_mode", 1))
	_theme_id = int(SaveMgr.get_value("theme", UiTheme.LIGHT))
	hud = GameHud.new()
	add_child(hud)
	# The home-screen backdrop is its own cinematic scene, never the arena.
	menu_world = MenuWorld.new()
	menu_world.dark = _theme_id == UiTheme.DARK
	add_child(menu_world)
	if hud.menu_back_active():
		_show_menu_scene()   # storm background is live: keep the 3D demo world dormant
	# The gameplay world is built LAZILY on the first Play — boot cost and
	# memory are spent on the menu, and the arena can never leak behind it.
	match_world = null
	hud.set_arena(_arena_key)
	hud.arena_shift.connect(_on_arena_shift)
	hud.theme_changed.connect(_on_theme_changed)
	hud.mode_changed.connect(_on_mode_changed)
	_bind_joystick()   # single connection; the handler resolves the player live
	if _autoplay:
		print("DEV: boot theme=%d mode=%d" % [UiTheme.current_id, _gfx_mode])
	if _touchlog:
		_touchlog_dump.call_deferred()

	cam = Camera3D.new()
	cam.fov = 55.0
	cam.current = true
	add_child(cam)
	cam.position = _cam_pos
	cam.look_at_from_position(_cam_pos, Vector3.ZERO, Vector3.UP)
	# Fixed top-down arena camera (spec §1): recompute the fit whenever the
	# window/aspect changes so the WHOLE playable circle stays in frame.
	get_viewport().size_changed.connect(func(): _topdown_dirty = true)

	hud.play_pressed.connect(func(): _start_play())
	hud.quit_pressed.connect(func(): hud.show_quit_confirm(true))
	hud.quit_confirmed.connect(_quit_nicely)
	hud.pause_pressed.connect(_toggle_pause)
	hud.resume_pressed.connect(func(): _resume())
	hud.restart_pressed.connect(func(): _restart())
	hud.tomenu_pressed.connect(func(): _to_menu())

	if _autoplay:
		# Automated checks must never disturb the player: mute all audio for
		# this session only (saved volume settings are untouched) and push the
		# window far off-screen so it doesn't pop up over their work. Vsync is
		# disabled because fully off-screen windows can have their swap-chain
		# stalled by the compositor, which would freeze the whole game loop.
		AudioServer.set_bus_mute(0, true)
		if not _onscreen_test:
			DisplayServer.window_set_position(Vector2i(-3200, -3200))
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_dev_sequence()

	get_tree().set_auto_accept_quit(true)

# Dev flags are accepted both after `--` (user args) and as raw engine args.
func _collect_dev_args() -> Array[String]:
	var out: Array[String] = []
	var allow := ["--autoplay", "--no-death", "--solo", "--hud-off", "--onscreen-test", "--shot-menu", "--shot-skins", "--shot-settings", "--arena-test", "--touch-test", "--touchlog", "--spawntest", "--powertest", "--eat-test", "--skins-test", "--body-test", "--climb-test", "--bg-test", "--villain-test", "--turn-test", "--ai-loop", "--drop-test", "--tap-test", "--theme-test", "--uix-test", "--mode-test", "--joystick", "--joy-test", "--dir-test", "--ctrl-test"]
	for src in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var keep := false
		if allow.has(src):
			keep = true
			if src == "--shot-menu":
				_shot_menu = true
			if src == "--shot-skins":
				_shot_skins = true
			if src == "--shot-settings":
				_shot_settings = true
		elif src.begins_with("--arena="):
			keep = true
			var k := src.substr(8)
			if ArenaPresets.ALL.has(k):
				_arena_key = k
		elif src.begins_with("--skin="):
			keep = true
			_skin_dev = clampi(int(src.substr(7)), 0, SkinCatalog.count() - 1)
		elif src.begins_with("--theme="):
			keep = true
			_theme_id = clampi(int(src.substr(8)), 0, UiTheme.NAMES.size() - 1)
			SaveMgr.set_value("theme", _theme_id)
		elif src == "--mode=2d" or src.begins_with("--mode=2"):
			keep = true
			_gfx_mode = 0
			SaveMgr.set_value("gfx_mode", 0)
		elif src == "--mode=3d" or src.begins_with("--mode=3"):
			keep = true
			_gfx_mode = 1
			SaveMgr.set_value("gfx_mode", 1)
		elif src == "--closeup" or src.begins_with("--closeup="):
			keep = true
		elif src.begins_with("--shot="):
			keep = true
		elif src.begins_with("--quit") and src.find("=") > 0:
			keep = true
		if keep and not out.has(src):
			out.append(src)
	print("DEVARGS: ", out)
	return out

func _dev_sequence() -> void:
	# menu breathing room, then a real match, optional screenshot & quit
	await get_tree().create_timer(1.0).timeout
	if _arena_test:
		# exercises the same signal the arrow buttons emit: cycle 3 times with
		# a shot each, verifying the selector + save persistence, then START a
		# real match in the selected arena so the choice is proven in gameplay.
		var arena0 := str(SaveMgr.get_value("arena", "valley"))
		var cycle_ok := true
		for i in 3:
			hud.arena_shift.emit(1)
			await get_tree().create_timer(1.4).timeout
			await _snap("shot_arena%d.png" % (i + 1))
			var saved := str(SaveMgr.get_value("arena", "valley"))
			var shown := str(hud._arena_label.text) if hud._arena_label != null else ""
			var preset_name := str(ArenaPresets.get_preset(saved).get("name", ""))
			print("ARENA-TEST now=%s saved=%s label=%s" % [saved, _arena_key, shown])
			if saved != _arena_key or shown != preset_name:
				cycle_ok = false
		_start_play()
		match_world.no_death = true
		await _frames(40)
		var world_key := str(match_world.arena_key)
		var obstacles: int = match_world.obstacles.size()
		var in_arena: bool = match_world.player != null \
			and match_world.player.head_pos.length() < 58.0
		var gameplay_ok: bool = world_key == str(SaveMgr.get_value("arena", "valley")) \
			and obstacles > 0 and in_arena and is_instance_valid(match_world)
		print("ARENA-TEST gameplay arena=%s obstacles=%d player_inside=%s %s" % [
			world_key, obstacles, str(in_arena), "PASS" if gameplay_ok else "FAIL"])
		await _snap("shot_arena_play.png")
		print("ARENA-TEST done — %s" % ("PASS" if cycle_ok and gameplay_ok else "FAIL"))
		# leave the user's own arena choice untouched
		SaveMgr.set_value("arena", arena0)
		_arena_key = arena0
		hud.set_arena(arena0)
		_quit_nicely()
		return
	if _skins_test:
		# skins screen QA: menu-page switch, live preview, unlock gates, persistence
		await _skins_test_run()
		return
	if _theme_test:
		await _theme_test_run()
		return
	if _shot_menu:
		await _snap("shot_menu.png")
	if _shot_skins:
		# visual QA of the SNAKES page: switch to it, shot, then quit
		hud._menu_page("skins")
		await get_tree().create_timer(1.2).timeout
		await _snap("shot_skins.png")
		_quit_nicely()
		return
	if _shot_settings:
		hud._menu_page("settings")
		await get_tree().create_timer(0.8).timeout
		await _snap("shot_settings.png")
		_quit_nicely()
		return
	if _video_test:
		# home background QA (Back.html recreation): shader rect must exist,
		# be visible on the menu, animate over time, spawn lightning bolts,
		# and shut down when a match starts (runs before _start_play).
		await get_tree().create_timer(2.2).timeout
		var rect_ok: bool = hud.menu_back_active()
		var bolts: int = hud._light_bolts.size()
		var flash_a: float = hud._flash_a
		var intensity: float = 1.0
		if hud._back_mat != null:
			intensity = hud._back_mat.get_shader_parameter("u_intensity")
		hud.show_menu(false)   # entering a match must shut the storm down
		var off: bool = not hud.menu_back_active() and not hud._light_active
		print("BGTEST rect=%s bolts>0=%s flash=%.2f intensity=%.2f off_in_match=%s %s" % [
			rect_ok, bolts > 0 or flash_a > 0.0, flash_a, intensity, off,
			"PASS" if rect_ok and off and intensity > 0.0 else "FAIL"])
		_quit_nicely()
		return
	await get_tree().create_timer(0.6).timeout
	_start_play()
	print("DEV: play started")
	if _body_test:
		await _body_test_run()
		return
	if _climb_test:
		await _climb_test_run()
		return
	if _villain_test:
		await _villain_test_run()
		return
	if _turn_test:
		await _turn_test_run()
		return
	if _ai_loop:
		await _ai_loop_test_run()
		return
	if _tap_test:
		await _tap_test_run()
		return
	if _uix_test:
		await _uix_test_run()
		return
	if _mode_test:
		await _mode_test_run()
		return
	if _drop_test:
		await _drop_test_run()
		return
	if _joy_test:
		await _joy_test_run()
		return
	if _dir_test:
		await _dir_test_run()
		return
	if _ctrl_test:
		await _ctrl_test_run()
		return
	if _touch_test:
		await _touch_test_run()
		return
	if _spawntest:
		match_world.no_death = true
		await get_tree().create_timer(7.0).timeout
		print("SPAWNTEST done — survives=", match_world.player != null and match_world.player.alive)
		_quit_nicely()
		return
	if _eat_test:
		await _eat_test_run()
		return
	if _powertest:
		await _powertest_run()
		return
	if _quit_at > 0.0:
		await get_tree().create_timer(_quit_at * 0.5).timeout
		print("DEV: mid timer fired")
		await _snap("shot_mid.png")
		await get_tree().create_timer(_quit_at * 0.5).timeout
		print("DEV: end timer fired")
	if _shot_game:
		await _snap("shot_game.png")
	_quit_nicely()
	# ---------------------------------------------------------------- death drops

## DROPTEST: death-drop QA (§ user report 3). Kills REAL snakes and measures:
## 1. A killed serpent leaves collectible orbs ALONG ITS CORPSE, at ~0.8 m
##    spacing (no one overlapping blob).
## 2. Drops still appear when the court sits AT the hard cap — the spawner
##    retires a far-away passive orb to make room for the drop.
func _drop_test_run() -> void:
	if match_world == null or match_world.player == null:
		print("DROPTEST FAIL no match")
		_quit_nicely()
		return
	match_world.no_death = false
	await _frames(10)
	var food = match_world.food
	var cap: int = food.hard_cap
	var ok := true
	# every alive rec gets a persistent ID tag → a rec IDENTITY is "new" iff
	# it carries no tag (content-hashing would break on harmless rec mutations)
	var dd_id := 0
	for kind in food._slots.size():
		for pool: Dictionary in food._slots[kind]:
			for idx in (pool["alive"] as Dictionary).keys():
				(pool["alive"] as Dictionary)[idx]["dd_id"] = dd_id
				dd_id += 1

	# --- case 1: a real kill leaves a spread corpse trail -------------------
	var victim: Snake = null
	for s in match_world.snakes:
		if s is AISnake and s.alive:
			victim = s
			break
	if victim == null:
		print("DROPTEST FAIL no AI victim")
		_quit_nicely()
		return
	var corpse: PackedVector3Array = victim.coll_pos
	print("DROPTEST case1 victim=%s len=%.1f court_alive=%d cap=%d" % [
		victim.display_name, victim.length, food.count_alive(), cap])
	food.qa_freeze_respawn = true   # only drops can add during the measurement
	match_world._kill(victim, null, "QA")
	await _frames(3)
	var rich := _drop_diff(food)
	food.qa_freeze_respawn = false
	var gained := rich.size()
	var corps_ok := true
	var min_pair := INF
	for rec in rich:
		var p: Vector3 = rec["pos"]
		var best := INF
		for st in corpse:
			best = minf(best, Vector2(p.x - st.x, p.z - st.z).length())
		if best > 2.5:
			corps_ok = false
	for a in rich.size():
		for b in range(a + 1, rich.size()):
			min_pair = minf(min_pair, (rich[a]["pos"] as Vector3).distance_to(rich[b]["pos"] as Vector3))
	var case_ok := gained > 0 and corps_ok and min_pair > 0.35
	ok = ok and case_ok
	print("DROPTEST case1 drops=%d on_corpse=%s min_gap=%.2f %s" % [
		gained, str(corps_ok), min_pair, "PASS" if case_ok else "FAIL"])

	# --- case 2: drops survive a court AT the hard cap -----------------------
	food.qa_freeze_respawn = true
	var guard := 0
	while food._total < cap and guard < 400:
		food._spawn_orb(0)
		guard += 1
	var dd2 := 1000000
	for kind in food._slots.size():
		for pool: Dictionary in food._slots[kind]:
			for idx in (pool["alive"] as Dictionary).keys():
				(pool["alive"] as Dictionary)[idx]["dd_id"] = dd2
				dd2 += 1
	# another victim
	var victim2: Snake = null
	for s in match_world.snakes:
		if s is AISnake and s.alive:
			victim2 = s
			break
	var corpse2 := victim2.coll_pos if victim2 != null else corpse
	print("DROPTEST case2 court_alive=%d cap=%d victim=%s len=%.1f" % [
		food.count_alive(), cap, victim2.display_name if victim2 != null else "none",
		victim2.length if victim2 != null else 0.0])
	if victim2 != null:
		match_world._kill(victim2, null, "QA")
		await _frames(3)
		var rich2 := _drop_diff(food)
		food.qa_freeze_respawn = false
		var gained2 := rich2.size()
		var under: bool = food._total <= cap
		var near_ok := true
		for rec in rich2:
			var p: Vector3 = rec["pos"]
			var best := INF
			for st in corpse2:
				best = minf(best, Vector2(p.x - st.x, p.z - st.z).length())
			if best > 2.5:
				near_ok = false
		var count_ok := gained2 >= 10
		var case2_ok: bool = count_ok and under and near_ok
		ok = ok and case2_ok
		print("DROPTEST case2 drops_at_cap=%d under_cap=%s on_corpse=%s court_after=%d %s" % [
			gained2, str(under), str(near_ok), food.count_alive(),
			"PASS" if case2_ok else "FAIL"])
	else:
		ok = false
		print("DROPTEST case2 drops_at_cap=0 FAIL no AI victim left")
	print("DROPTEST done — %s" % ("PASS" if ok else "FAIL"))
	_quit_nicely()

## Court rec dicts WITHOUT the ID tag = orbs that appeared after tagging.
func _drop_diff(food) -> Array:
	var out: Array = []
	for kind in food._slots.size():
		for pool: Dictionary in food._slots[kind]:
			for idx in (pool["alive"] as Dictionary).keys():
				var rec: Dictionary = (pool["alive"] as Dictionary)[idx]
				if not rec.has("dd_id"):
					out.append(rec)
	return out

# ---------------------------------------------------------------- touch QA

# On Windows the Godot touch emulator turns a raw `InputEventScreenTouch`
# into a mouse button FIRST, so the synthetic desktop rig uses mouse input to
# feed the joystick; Android keeps real multi-touch events.

func _window_pos(pos: Vector2) -> Vector2:
	# Godot's touch/mouse `InputEvent.position` for a synthetic event in the
	# test rig is interpreted as **window coordinates**, not viewport coords.
	# Headless/low-res windows therefore make the same logical point inflate by
	# the content scale factor (we saw 20x). Map the caller's logical
	# coordinates into exact window coordinates first, so the actual game sees
	# the intended screen point on both desktop and Android.
	var vvs: Vector2 = get_viewport().get_visible_rect().size
	if vvs.x < 1.0 or vvs.y < 1.0 or not is_instance_valid(get_tree().root):
		return pos
	var w: Vector2 = Vector2(get_tree().root.size)
	if w.x < 1.0 or w.y < 1.0:
		return pos
	return Vector2(pos.x * w.x / vvs.x, pos.y * w.y / vvs.y)

func _pointer_event(index: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = _window_pos(pos)
	t.pressed = pressed
	Input.parse_input_event(t)

func _pointer_drag(index: int, pos: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = _window_pos(pos)
	Input.parse_input_event(d)


func _touch_tap(index: int, pressed: bool, pos: Vector2) -> void:
	_pointer_event(index, pos, pressed)

func _touch_drag(index: int, pos: Vector2) -> void:
	_pointer_drag(index, pos)

func _touch_event(index: int, pos: Vector2, pressed: bool) -> void:
	_pointer_event(index, pos, pressed)

func _drag_event(index: int, pos: Vector2) -> void:
	_pointer_drag(index, pos)

func _touch_test_run() -> void:
	# Synthetic touch QA on desktop: verify drag-steering, dead zone and the
	# second-finger boost on the exact same code path Android uses.
	var p: PlayerSnake = match_world.player
	if p == null:
		print("TOUCHTEST FAIL no player")
		_quit_nicely()
		return
	var vs := get_viewport().get_visible_rect().size
	var wrap := func(a: float, b: float) -> float: return absf(wrapf(a - b, -PI, PI))
	# All waits are sim time (physics frames): the offscreen dev window can
	# hitch for hundreds of ms on startup, and wall-clock windows measured a
	# fraction of the intended steering time (flaky test, not a control bug).
	await _frames(30)
	var h0: float = p.heading
	# 1) finger down right of center → steering rotation
	_touch_tap(0, true, Vector2(vs.x * 0.72, vs.y * 0.5))
	await _frames(51)
	var t1: float = wrap.call(p.heading, h0)
	print("TOUCHTEST steer dt=%.3f %s" % [t1, "PASS" if t1 > 0.10 else "FAIL"])
	var td := p.desired_dir
	print("TOUCHTEST intent len=%.2f %s" % [td.length(), "PASS" if td.length() > 0.05 else "FAIL"])
	# 2) dead zone: second drag near center → desired_dir releases to center
	var hz: float = p.heading
	_touch_drag(0, Vector2(vs.x * 0.52, vs.y * 0.52))
	await _frames(24)
	var drift: float = wrap.call(p.heading, hz)
	print("TOUCHTEST deadzone drift=%.3f %s" % [drift, "PASS" if drift < 0.06 else "FAIL"])
	# 3) second finger → boost
	_touch_tap(1, true, Vector2(vs.x * 0.22, vs.y * 0.72))
	await _frames(21)
	print("TOUCHTEST boost %s" % ("PASS" if p.input_boost else "FAIL"))
	# 4) release second finger → boost off
	_touch_tap(1, false, Vector2(vs.x * 0.22, vs.y * 0.72))
	await _frames(21)
	print("TOUCHTEST boost-off %s" % ("PASS" if not p.input_boost else "FAIL"))
	# 5) steer the other side → rotation resumes in the new direction. Measured
	#    from the drag itself: at full sim speed a reversal can swing back
	#    through the original heading, cancelling a start-to-end delta.
	var h5: float = p.heading
	_touch_drag(0, Vector2(vs.x * 0.28, vs.y * 0.5))
	await _frames(51)
	var t5: float = wrap.call(p.heading, h5)
	print("TOUCHTEST steer-back dt=%.3f %s" % [absf(t5), "PASS" if absf(t5) > 0.10 else "FAIL"])
	# cleanup + quit
	_touch_tap(0, false, Vector2(vs.x * 0.28, vs.y * 0.5))
	await _frames(12)
	_quit_nicely()

# ---------------------------------------------------------------- skins QA

func _skins_test_run() -> void:
	# stays in the MENU: page switch, live preview render, unlock gates, persistence
	print("SKINTEST count %s" % ("PASS" if SkinCatalog.count() >= 11 else "FAIL"))
	print("SKINTEST unlock0 %s" % ("PASS" if SkinCatalog.unlocked(0, 0) else "FAIL"))
	print("SKINTEST lock5 %s" % ("PASS" if not SkinCatalog.unlocked(5, 600) else "FAIL"))
	print("SKINTEST clamp %s" % ("PASS" if SkinCatalog.get_skin(99).has("name") and SkinCatalog.get_skin(-2).has("name") else "FAIL"))
	var before := int(SaveMgr.get_value("skin", 0))
	var best := int(SaveMgr.get_value("best_score", 0))
	hud._menu_page("skins")
	await get_tree().create_timer(1.4).timeout
	await _snap("shot_skins.png")
	# equip the first unlocked skin different from the current one
	var free := before
	for i in SkinCatalog.count():
		if SkinCatalog.unlocked(i, best):
			free = i
			break
	hud._pick_skin(free)
	print("SKINTEST pick=%d %s" % [free, "PASS" if int(SaveMgr.get_value("skin", 0)) == free else "FAIL"])
	SaveMgr.save()
	SaveMgr._load()
	print("SKINTEST persist %s" % ("PASS" if int(SaveMgr.get_value("skin", 0)) == free else "FAIL"))
	# lock gate: highest skin must stay unequipped at current best
	var locked := SkinCatalog.count() - 1
	hud._pick_skin(locked)
	var gate_ok := int(SaveMgr.get_value("skin", 0)) != locked or SkinCatalog.unlocked(locked, best)
	print("SKINTEST lock-gate %s" % ("PASS" if gate_ok else "FAIL"))
	await get_tree().create_timer(0.6).timeout
	await _snap("shot_skins2.png")
	# restore the original choice
	SaveMgr.set_value("skin", before)
	SaveMgr.save()
	print("SKINTEST restored now=%d" % int(SaveMgr.get_value("skin", 0)))
	_quit_nicely()

# ---------------------------------------------------------------- joystick QA

func _joy_test_run() -> void:
	# Virtual joystick QA (spec section 2): visibility rules, direction ->
	# heading mapping in all 8 directions, deadzone, and knob release.
	SaveMgr.set_value("gfx_mode", 0)
	_gfx_mode = 0                # the joystick is a 2D-mode control: camera too
	match_world.gfx_mode = 0
	_joy_dev = true
	_start_play()
	match_world.no_death = true
	await get_tree().create_timer(1.2).timeout
	var joy: TouchJoystick = hud.joystick()
	var p: PlayerSnake = match_world.player
	p._is_mobile = true   # exercise the mobile joystick path on desktop
	p.autopilot = false   # dev autopilot would otherwise overwrite steering
	print("JOYTEST visible=%s mobile_path=%s" % [str(joy.enabled), str(p._is_mobile)])
	print("JOYTEST idle-hidden %s (alpha=%.2f)" % [
		"PASS" if joy.alpha() <= 0.01 else "FAIL", joy.alpha()])
	await get_tree().process_frame
	# 2D top-down camera: screen-right = world +X, screen-up = world -Z
	var dirs := {
		"RIGHT": Vector2(1, 0), "LEFT": Vector2(-1, 0),
		"UP": Vector2(0, 1), "DOWN": Vector2(0, -1),
		"UP-RIGHT": Vector2(0.707, 0.707), "DOWN-LEFT": Vector2(-0.707, -0.707),
	}
	for name in dirs.keys():
		joy.force_value(dirs[name])
		for i in 30:
			await get_tree().physics_frame
		var want: Vector2 = dirs[name]
		# expected world dir: screen +x -> +X ; screen +y -> -Z
		var wx: float = want.x
		var wz: float = -want.y
		var d := Vector2(p.desired_dir.x, p.desired_dir.z)
		var ok: bool = absf(d.normalized().dot(Vector2(wx, wz).normalized())) > 0.98 if d.length() > 0.1 else false
		print("JOYTEST %s joy=%s active=%s dir=(%.2f,%.2f) want=(%.2f,%.2f) %s" % [name, str(p.joy_vec), str(p.joy_active), d.x, d.y, wx, wz, "PASS" if ok else "FAIL"])
	# deadzone + release
	joy.force_value(Vector2(0.05, 0.0))
	for i in 10:
		await get_tree().physics_frame
	print("JOYTEST held-visible %s (alpha=%.2f)" % [
		"PASS" if joy.active and joy.alpha() > 0.9 else "FAIL", joy.alpha()])
	print("JOYTEST deadzone %s" % ["PASS" if joy.value == Vector2.ZERO else "FAIL"])
	joy.force_release()
	for i in 40:
		await get_tree().process_frame
	print("JOYTEST release %s (value=%s knob=%.2f alpha=%.2f)" % [
		"PASS" if joy.value == Vector2.ZERO and joy.alpha() <= 0.01 else "FAIL",
		str(joy.value), joy._knob.length(), joy.alpha()])
	await _snap("shot_joystick.png")
	_quit_nicely()

# ---------------------------------------------------------------- dir QA

## Directional-control QA (spec sections 1-4). Injects REAL key events through
## the engine input queue (the same path a keyboard uses) and measures how the
## head actually travels, in BOTH 2D and 3D mode.
const DIR_KEYS := [
	{"code": KEY_W, "name": "W", "screen": Vector2(0, 1)},
	{"code": KEY_UP, "name": "UP", "screen": Vector2(0, 1)},
	{"code": KEY_S, "name": "S", "screen": Vector2(0, -1)},
	{"code": KEY_DOWN, "name": "DOWN", "screen": Vector2(0, -1)},
	{"code": KEY_A, "name": "A", "screen": Vector2(-1, 0)},
	{"code": KEY_LEFT, "name": "LEFT", "screen": Vector2(-1, 0)},
	{"code": KEY_D, "name": "D", "screen": Vector2(1, 0)},
	{"code": KEY_RIGHT, "name": "RIGHT", "screen": Vector2(1, 0)},
]

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

# ---------------------------------------------------------------- body QA

## Measure the rendered spine: station spacing vs the ideal arc step, vertical
## spread, and whether the first station still starts at the head.
func _body_metrics(s: Snake) -> Dictionary:
	var ds := s.length / float(Snake.RING_COUNT - 1)
	var sp: PackedFloat32Array = s._spine
	var max_err := 0.0
	var min_gap := 1e9
	var max_gap := 0.0
	var y_min := 1e9
	var y_max := -1e9
	var worst_i := 0
	for i in range(1, Snake.RING_COUNT):
		var o0 := (i - 1) * 4
		var o1 := i * 4
		var gap := Vector2(sp[o1] - sp[o0], sp[o1 + 2] - sp[o0 + 2]).length()
		min_gap = minf(min_gap, gap)
		if gap > max_gap:
			max_gap = gap
			worst_i = i
		var e := absf(gap - ds) / maxf(ds, 0.0001)
		max_err = maxf(max_err, e)
		y_min = minf(y_min, sp[o1 + 1])
		y_max = maxf(y_max, sp[o1 + 1])
	var raw_min := 1e9
	var raw_max := 0.0
	for i in range(1, Snake.RING_COUNT):
		var rg := s._raw[i].distance_to(s._raw[i - 1])
		raw_min = minf(raw_min, rg)
		raw_max = maxf(raw_max, rg)
	var hist_len := float(maxi(s._hist_count - 1, 0)) * Snake.SPACING
	return {
		"raw_min": raw_min,
		"raw_max": raw_max,
		"worst_i": worst_i,
		"ds": ds,
		"max_err": max_err,
		"min_gap": min_gap,
		"max_gap": max_gap,
		"y_min": y_min,
		"y_max": y_max,
		"y_span": y_max - y_min,
		"hist_len": hist_len,
		"head_xz": Vector2(sp[0], sp[2]).length(),
		"lift": s.body_lift,
		"root_y": s.global_position.y,
	}

func _body_test_run() -> void:
	var p: PlayerSnake = match_world.player if match_world != null else null
	if p == null:
		print("BODYTEST FAIL no player")
		_quit_nicely()
		return
	match_world.no_death = true
	# CLIMBTEST owns terrain-following QA; BODYTEST measures the FLAT-court
	# spine contract (the y_span == 0 guarantee), so level the climbable
	# height fields for this run. Snake-vs-boulder climbing is measured
	# separately by --climb-test.
	for ob in match_world.obstacles:
		ob["h"] = 0.0
	if match_world.arena != null and match_world.arena.env != null:
		match_world.arena.env.invalidate_climb_cache()   # zeroing above only takes effect on the next cache rebuild
	p.autopilot = false
	p.keyboard_only = true
	p.clear_keys()
	p.input_boost = false
	# Long body: exercises both the long-spawn history extension and the
	# tightest curves the real steering can make.
	p.length = 70.0
	p.target_length = 70.0
	await _frames(12)
	var fail := 0
	var turns: Array[float] = [0.0, PI * 0.5, -PI * 0.5, PI, PI * 0.5, -PI * 0.75]
	for mode in 2:
		hud.mode_changed.emit(mode)
		await _frames(16)
		for ti in turns.size():
			var fwd := Vector3(sin(p.heading), 0.0, cos(p.heading))
			p.desired_dir = fwd.rotated(Vector3.UP, turns[ti])
			await _frames(18)
			var m := _body_metrics(p)
			var ok: bool = m["max_err"] < 0.02 and m["y_span"] < 0.01 \
				and m["hist_len"] + 0.01 >= p.length and m["head_xz"] < 0.001 \
				and m["root_y"] == 0.0 and m["lift"] > 0.20
			if not ok:
				fail += 1
			print("BODYTEST mode=%d turn=%d gap=%.3f..%.3f err=%.3f yspan=%.4f hist=%.1f/%.1f lift=%.2f %s" % [
				mode, ti, m["min_gap"], m["max_gap"], m["max_err"], m["y_span"],
				m["hist_len"], p.length, m["lift"], "PASS" if ok else "FAIL"])
	# Turn-continuity: between consecutive physics frames during a hard turn,
	# no body station may move more than the head's own travel (+ tube-roll
	# noise). The old whole-mesh bank levered far-away stations by metres the
	# moment a turn started or ended — the classic mid-turn "pop".
	p.desired_dir = Vector3(sin(p.heading), 0, cos(p.heading)).rotated(Vector3.UP, PI)
	await get_tree().physics_frame
	var snap_a := {}
	for s in match_world.snakes:
		if is_instance_valid(s) and s.alive and s._raw.size() == Snake.RING_COUNT:
			snap_a[s.id] = (s._raw.duplicate())
	await get_tree().physics_frame
	var pop := 0.0
	var pop_who := ""
	for s in match_world.snakes:
		if is_instance_valid(s) and s.alive and snap_a.has(s.id) and s._raw.size() == Snake.RING_COUNT:
			var arr: PackedVector3Array = snap_a[s.id]
			var travel: float = s.speed_cur / 60.0 + 0.03
			for i in Snake.RING_COUNT:
				var d := arr[i].distance_to(s._raw[i]) - travel
				if d > pop:
					pop = d
					pop_who = s.name
	var pop_ok: bool = pop < 0.05
	print("BODYTEST continuity worst=%s pop=%.4f %s" % [
		pop_who, pop, "PASS" if pop_ok else "FAIL"])
	if not pop_ok:
		fail += 1
	# Frame-rate independence: the exact arc-length history must produce the
	# same station spacing at 30 Hz and 90 Hz (the old code did not).
	var fps_err: Array[float] = []
	for hz in [30, 90]:
		Engine.physics_ticks_per_second = hz
		await _frames(6)
		var fwd2 := Vector3(sin(p.heading), 0.0, cos(p.heading))
		p.desired_dir = fwd2.rotated(Vector3.UP, PI * 0.5)
		await _frames(30 if hz == 30 else 90)
		var m2 := _body_metrics(p)
		fps_err.append(float(m2["max_err"]))
		var ok2: bool = m2["max_err"] < 0.02 and m2["y_span"] < 0.01
		if not ok2:
			fail += 1
		print("BODYTEST fps=%d gap_err=%.3f yspan=%.4f %s" % [
			hz, m2["max_err"], m2["y_span"], "PASS" if ok2 else "FAIL"])
	Engine.physics_ticks_per_second = 60
	var fps_ok: bool = fps_err.size() == 2 and absf(fps_err[0] - fps_err[1]) < 0.20
	if not fps_ok:
		fail += 1
	print("BODYTEST fps-independence delta=%.3f %s" % [
		absf(fps_err[0] - fps_err[1]) if fps_err.size() == 2 else -1.0,
		"PASS" if fps_ok else "FAIL"])
	print("BODYTEST done — %s" % ("PASS" if fail == 0 else "FAIL"))
	_quit_nicely()

# ---------------------------------------------------------------- climbing QA

## Terrain-following QA: drive the player dead-center over the tallest court
## boulder and measure the ride. The head must track the climbable height
## field tightly (no sinking through, no floating), every body station must
## hug the field (head, mid and tail all follow the stone's surface), the
## per-frame vertical motion must stay smooth, and the snake must come down
## the far side to the flat court — a real crawl over the stone, no pass-
## through and no death (boulders are climbable cover, not walls).
func _climb_test_run() -> void:
	var p: PlayerSnake = match_world.player if match_world != null else null
	if p == null:
		print("CLIMBTEST FAIL no player")
		_quit_nicely()
		return
	match_world.no_death = true
	p.autopilot = false
	p.keyboard_only = true
	p.clear_keys()
	p.input_boost = false
	# pick the tallest climbable court boulder
	var best := {}
	for ob in match_world.obstacles:
		if float(ob.get("h", 0.0)) > float(best.get("h", 0.0)):
			best = ob
	if best.is_empty() or float(best["h"]) <= 0.0:
		print("CLIMBTEST FAIL no climbable boulder registered")
		_quit_nicely()
		return
	var bpos: Vector3 = best["pos"]
	var bh: float = float(best["h"])
	var br: float = float(best["cr"])
	var dir := -Vector3(bpos.x, 0.0, bpos.z).normalized()
	var start := bpos - dir * (br + 7.0)
	p.spawn(start, dir, 7.0)
	await _frames(4)
	var max_head_err := 0.0
	var max_station_err := 0.0
	var max_dy := 0.0
	var peak_y := -1.0
	var min_head_err_on_top := 99.0
	var prev_y := p.head_pos.y
	var prev := start
	var crossed := false
	var prelift_ok := true     # JUMP ARC: lift must begin BEFORE the stone
	var prelift_min := 99.0
	for f in 420:
		await get_tree().physics_frame
		var hp: Vector3 = p.head_pos
		var jr := p.speed_cur * 0.45 + 1.2
		var gy: float = match_world.ground_height_at(
			hp.x, hp.z, sin(p.heading), cos(p.heading), jr)
		# head must never sink meaningfully under the surface nor float above it
		max_head_err = maxf(max_head_err, absf(hp.y - gy))
		if gy > bh * 0.5:
			min_head_err_on_top = minf(min_head_err_on_top, absf(hp.y - gy))
		peak_y = maxf(peak_y, hp.y)
		max_dy = maxf(max_dy, absf(hp.y - prev_y))
		max_dy = maxf(max_dy, hp.distance_to(prev) - p.speed_cur / 60.0)  # horizontal sanity
		prev_y = hp.y
		prev = hp
		# JUMP ARC anticipation: while the head is still short of the edge
		# (inside the ramp zone) it must already be climbing — no "reach the
		# stone flat, then pop" — and must NOT already be at full leap height
		# far away from the stone.
		var d_edge := (bpos - hp).dot(dir) - br
		if d_edge > 0.0 and d_edge < jr * 0.5:
			prelift_min = minf(prelift_min, hp.y)
			if hp.y < bh * 0.2:
				prelift_ok = false
		# body stations must sit ON the field (jump arc included) while
		# over/near the stone
		for i in range(1, Snake.RING_COUNT, 6):
			var st: Vector3 = p._raw[i]
			var o4s := i * 4
			var sg: float = match_world.ground_height_at(st.x, st.z,
				-p._tan[o4s], -p._tan[o4s + 2], jr)
			if sg > 0.05 or st.y > 0.05:
				max_station_err = maxf(max_station_err, absf(st.y - sg))
		# done once we are past the boulder and back on the flat court
		var prog := (hp - start).dot(dir)
		if prog > br + 9.0 and hp.y <= 0.02:
			crossed = true
			break
	var climb_ok := peak_y >= bh * 0.85
	var track_ok := max_head_err < 0.20 and min_head_err_on_top < 0.12 and max_station_err < 0.03
	var smooth_ok := max_dy < 0.5
	print("CLIMBTEST boulder h=%.2f r=%.2f peak=%.2f head_err=%.3f top_err=%.3f station_err=%.3f dy=%.3f crossed=%s" % [
		bh, br, peak_y, max_head_err, min_head_err_on_top, max_station_err, max_dy, crossed])
	print("CLIMBTEST prelift min_y_at_half_ramp=%.3f (want > %.3f) %s" % [
		prelift_min, bh * 0.2, "ok" if prelift_ok else "TOO LATE"])
	var alive_ok: bool = p.alive or match_world.no_death
	print("CLIMBTEST done — %s" % ("PASS" if climb_ok and track_ok and smooth_ok and crossed and prelift_ok and alive_ok else "FAIL"))

	# ---- phase 2: 2D top-down — the climb must stay VISIBLE via fake depth ----
	# The 2D camera is orthographic straight down (world-Y projects to
	# nothing), so the tube is shifted up-screen by each station's climb
	# height: the shader shift (relative to the head) + the ROOT shift (the
	# head's own climb). Assert wiring + the resulting screen offsets.
	if not crossed or not track_ok:
		return   # phase 1 already failed
	hud.mode_changed.emit(0)
	await _frames(10)
	var best2 := {}
	for ob in match_world.obstacles:
		if float(ob.get("h", 0.0)) > float(best2.get("h", 0.0)):
			best2 = ob
	if best2.is_empty() or float(best2["h"]) <= 0.0:
		print("CLIMBTEST2D FAIL no climbable boulder after mode switch")
		_quit_nicely()
		return
	var bpos2: Vector3 = best2["pos"]
	var br2: float = float(best2["cr"])
	var dir2 := -Vector3(bpos2.x, 0.0, bpos2.z).normalized()
	var start2: Vector3 = bpos2 - dir2 * (br2 + 7.0)
	start2.y = 0.0
	p.spawn(start2, dir2, 7.0)
	await _frames(6)
	var fd_ok: bool = p._fake_depth == 1.0
	var mat_fd: float = p._mat.get_shader_parameter("u_fake_depth") if p._mat != null else 0.0
	var rest_lift: float = p._mat.get_shader_parameter("u_rest_lift") if p._mat != null else 0.0
	var root_err := 0.0
	var max_head_err2 := 0.0
	var peak_y2 := -1.0
	for f in 420:
		await get_tree().physics_frame
		var hp: Vector3 = p.head_pos
		var jr2 := p.speed_cur * 0.45 + 1.2
		var gy: float = match_world.ground_height_at(
			hp.x, hp.z, sin(p.heading), cos(p.heading), jr2)
		max_head_err2 = maxf(max_head_err2, absf(hp.y - gy))
		peak_y2 = maxf(peak_y2, hp.y)
		# ROOT z-shift: up-screen by exactly the head's climb height, never
		# including the resting lift (resting look stays identical)
		if gy > 0.05:
			root_err = maxf(root_err, absf(p.global_position.z - (hp.z - hp.y)))
		var prog2 := (hp - start2).dot(dir2)
		if prog2 > br2 + 9.0 and hp.y <= 0.02:
			break
	var fd_all_ok: bool = fd_ok and mat_fd == 1.0 and root_err < 0.05 \
		and max_head_err2 < 0.20 and peak_y2 >= float(best2["h"]) * 0.85
	print("CLIMBTEST2D fake_depth=%s mat=%.1f rest_lift=%.2f root_err=%.3f head_err=%.3f peak=%.2f %s" % [
		fd_ok, mat_fd, rest_lift, root_err, max_head_err2, peak_y2,
		"PASS" if fd_all_ok else "FAIL"])
	_quit_nicely()

# ---------------------------------------------------------------- turning QA

## Turning-quality QA for EVERY snake (spec item 8): the tube ring frame must
## never flip (the "snake hops onto its own back" bug), body stations must
## stay near the recorded path in the tightest scripted S/U-turn barrage,
## half-rate serpents must keep root + head anchored every tick, and in 2D
## top-down mode the whole-body roll must stay 0 (the "squash + pop" bug)
## while banking measurably continues in 3D.
func _turn_test_run() -> void:
	print("TURNTEST start — hard-turn barrage on the full roster")
	match_world.no_death = true
	# Deterministic starting mode: this harness must measure banking in 3D
	# phase 1 regardless of the mode a previous test saved.
	hud.mode_changed.emit(1)
	await _frames(8)
	var worst := {"flip_min": 2.0, "path_off": 0.0, "lag_ratio": 0.0, "roll3": 0.0, "roll2": 0.0, "tan_size": 1 << 20, "zero_norm": 0}
	_turn_probe = 1
	# ---- phase 1: 3D — alternating ±99° jinks and full 180° reversals ----
	for cycle in 4:
		var target := float(cycle) * (99.0 if cycle % 2 == 0 else -99.0) * PI / 180.0
		for s in match_world.snakes:
			if is_instance_valid(s) and s.alive:
				s.hold_heading = target
		for t in 36:
			await get_tree().physics_frame
			if t % 6 != 0:
				continue
			for s in match_world.snakes:
				if is_instance_valid(s) and s.alive:
					_turn_sample(s, worst)
	# 180° hard reversal, held long enough for the whole body to swing through
	var p: PlayerSnake = match_world.player
	if p != null:
		p.hold_heading = p.heading + PI
	for t in 30:
		await get_tree().physics_frame
		if t % 6 != 0:
			continue
		for s in match_world.snakes:
			if is_instance_valid(s) and s.alive:
				_turn_sample(s, worst)
	# ---- phase 2: 2D — same barrage, body roll must stay zero ----
	hud.mode_changed.emit(0)
	await _frames(8)
	for cycle in 3:
		var target2 := float(cycle) * (110.0 if cycle % 2 == 0 else -110.0) * PI / 180.0
		for s in match_world.snakes:
			if is_instance_valid(s) and s.alive:
				s.hold_heading = target2
		for t2 in 36:
			await get_tree().physics_frame
			if t2 % 6 != 0:
				continue
			for s in match_world.snakes:
				if is_instance_valid(s) and s.alive:
					_turn_sample(s, worst)
	print("TURNTEST diag flip_min=%.4f tan_size_min=%d zero_norm_max=%d" % [
		float(worst["flip_min"]), int(worst["tan_size"]), int(worst["zero_norm"])])
	print("TURNTEST frame-flip min_dot=%.4f %s" % [worst["flip_min"],
		"PASS" if float(worst["flip_min"]) > 0.5 else "FAIL"])
	print("TURNTEST path-offset max=%.3f %s" % [worst["path_off"],
		"PASS" if float(worst["path_off"]) < 0.85 else "FAIL"])
	print("TURNTEST root-lag ratio=%.3f %s" % [worst["lag_ratio"],
		"PASS" if float(worst["lag_ratio"]) < 1.0 else "FAIL"])
	print("TURNTEST bank roll 3D=%.3f 2D=%.4f %s" % [worst["roll3"], worst["roll2"],
		"PASS" if float(worst["roll2"]) < 0.002 and float(worst["roll3"]) > 0.02 else "FAIL"])
	var ok_turn: bool = float(worst["flip_min"]) > 0.5 and float(worst["path_off"]) < 0.85 \
		and float(worst["lag_ratio"]) < 1.0 and float(worst["roll2"]) < 0.002 \
		and float(worst["roll3"]) > 0.02
	print("TURNTEST done — %s" % ("PASS" if ok_turn else "FAIL"))
	hud.mode_changed.emit(1)  # leave the session in the default 3D mode for saves
	await _frames(4)
	_quit_nicely()

func _tap_test_run() -> void:
	# Settings-page option-pill QA. Headless cannot deliver synthetic GUI
	# events to Buttons (verified: parse_input_event + flush_buffered_events
	# and Window.push_input both no-op in the headless DisplayServer), so this
	# harness checks the widget layer structurally and the press handlers:
	#  1) the deepest visible control at each pill center must be that pill
	#     (nothing overlays or occludes it);
	#  2) emitting `pressed` must flip the saved value (handler wiring intact);
	#  3) BACK must really swap to the main page.
	# Desktop QA save values are restored afterwards. Real-finger behaviour was
	# verified separately on device (2026-10-23): SOUND/BACK/DARK/PLAY taps all
	# landed; an earlier "dead pill" report was tap-coordinate misreading, not
	# a code defect.
	hud.show_menu(true)
	hud._menu_page("settings")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var gfx: Button = _find_opt("gfx_mode", 0)
	var them: Button = _find_opt("theme", 0)
	var mute: Button = _find_opt("muted", 1)
	var failed := 0
	var g_before := int(SaveMgr.get_value("gfx_mode", 1))
	var t_before := int(SaveMgr.get_value("theme", 0))
	var m_before := int(SaveMgr.get_value("muted", 0))
	for pair in [[gfx, "gfx 2D pill", "gfx_mode", 0], [them, "theme BEIGE pill", "theme", 0], [mute, "sound OFF pill", "muted", 1]]:
		var b: Button = pair[0]
		if b == null or not b.is_visible_in_tree():
			print("TAPTEST %s missing/invisible FAIL" % pair[1])
			failed += 1
			continue
		var c: Vector2 = b.get_global_rect().get_center()
		var deep: Control = _cover_top(c)
		if deep != b:
			print("TAPTEST %s covered by %s FAIL" % [pair[1], str(deep.get_class()) if deep != null else "nothing"])
			failed += 1
			continue
		b.pressed.emit()
		await get_tree().process_frame
		var got: int = int(SaveMgr.get_value(pair[2], -99))
		var ok: bool = got == int(pair[3])
		print("TAPTEST %s center=(%.0f,%.0f) save=%d %s" % [pair[1], c.x, c.y, got, "PASS" if ok else "FAIL"])
		if not ok:
			failed += 1
	var back: Button = null
	for c2 in hud._menu_settings.get_children():
		if c2 is Button and (c2 as Button).text == "BACK":
			back = c2
	if back == null or not back.is_visible_in_tree():
		print("TAPTEST back missing FAIL")
		failed += 1
	else:
		back.pressed.emit()
		await get_tree().process_frame
		var page_ok: bool = hud.current_page() == "main"
		print("TAPTEST back press %s" % ("PASS" if page_ok else "FAIL"))
		if not page_ok:
			failed += 1
	SaveMgr.set_value("gfx_mode", g_before)
	SaveMgr.set_value("theme", t_before)
	SaveMgr.set_value("muted", m_before)
	print("TAPTEST done — %s" % ("PASS" if failed == 0 else "FAIL %d" % failed))
	_quit_nicely()

func _find_opt(group: String, value: int) -> Button:
	for b in hud._topt:
		if is_instance_valid(b) and str(b.get_meta("opt_group")) == group \
				and int(b.get_meta("opt_value")) == value and b.is_visible_in_tree():
			return b
	return null

## Deepest visible Control whose global rect contains `pos`, walking down from
## the menu tree — validates that a pill is the top-most interactive control
## at its own center (nothing overlays or occludes it).
func _cover_top(pos: Vector2, node: Node = null) -> Control:
	if node == null:
		node = hud.menu_group
	var deep: Control = null
	for c in node.get_children():
		if c is Control:
			var ctl := c as Control
			if not ctl.is_visible_in_tree() or not ctl.get_global_rect().has_point(pos):
				continue
			var sub := _cover_top(pos, ctl)
			deep = sub if sub != null else ctl
	return deep
## Per-snake turn-quality sample: shortest consecutive-ring-tangent dot
## (ring-frame continuity), plus a one-shot probe dump of raw `_tan` values
## so zeroed slots are distinguishable from genuine flips.
func _turn_sample(s: Snake, acc: Dictionary) -> void:
	var tan: PackedFloat32Array = s._tan
	acc["tan_size"] = mini(int(acc["tan_size"]), tan.size())
	var zero_norm := 0
	for i in Snake.RING_COUNT:
		var j := i * 4
		if tan[j] * tan[j] + tan[j + 2] * tan[j + 2] < 0.25:
			zero_norm += 1
	acc["zero_norm"] = maxi(int(acc["zero_norm"]), zero_norm)
	for i in Snake.RING_COUNT - 1:
		var a := i * 4
		var b := a + 4
		var d: float = tan[a] * tan[b] + tan[a + 2] * tan[b + 2]
		acc["flip_min"] = minf(float(acc["flip_min"]), d)
		if d < 0.5 and int(acc.get("dumped", 0)) == 0:
			acc["dumped"] = 1
			print("TURNTEST badpair %s i=%d norms=(%.3f,%.3f) tanA=(%.3f,%.3f) tanB=(%.3f,%.3f)" % [
				s.name, i,
				sqrt(tan[a] * tan[a] + tan[a + 2] * tan[a + 2]),
				sqrt(tan[b] * tan[b] + tan[b + 2] * tan[b + 2]),
				tan[a], tan[a + 2], tan[b], tan[b + 2]])
	acc["path_off"] = maxf(float(acc["path_off"]), _turn_path_offset(s))
	var step_bound: float = s.speed_cur / 60.0 + 0.03
	# Compare the root against its DESIGNED anchor: in 2D fake-depth the root
	# is deliberately displaced by the head's climb height (climb visibility),
	# so a snake standing on a boulder legitimately sits `y*sqrt(2)` away from
	# head_pos. Measuring raw root-vs-head distance would flag that intended
	# offset as lag; subtracting the designed shift isolates real lag only.
	var anchor := s.head_pos + Vector3(0.0, 0.0, -s.head_pos.y * s._fake_depth)
	acc["lag_ratio"] = maxf(float(acc["lag_ratio"]),
		(s.global_position - anchor).length() / maxf(step_bound, 0.02))
	# Bank moved INTO the ring frame (u_bank · t progressive ring roll). The
	# old body_mi.rotation.z levered stations by their distance from the head
	# and made long tails whip sideways on turn start/end; the quantity
	# measured here is the peak roll a ring can reach.
	if s._mat != null:
		var ub: float = absf(float(s._mat.get_shader_parameter(&"u_bank")))
		if match_world.gfx_mode == 1:
			acc["roll3"] = maxf(float(acc["roll3"]), ub)
		else:
			acc["roll2"] = maxf(float(acc["roll2"]), ub)
	if _turn_probe > 0:
		_turn_probe -= 1
		var r := Snake.RING_COUNT * 4 - 4
		print("TURNTEST probe %s tan_size=%d head=(%.2f,%.2f) next=(%.2f,%.2f) mid=(%.2f,%.2f) tailp2=(%.2f,%.2f) tail=(%.2f,%.2f)" % [
			s.name, tan.size(), tan[0], tan[2], tan[4], tan[6],
			tan[768], tan[770], tan[r - 4], tan[r - 2], tan[r], tan[r + 2]])

## Furthest lateral (XZ) distance of any sampled body station from the
## recorded head-path polyline. The sway rides ~0.5 m at most; a station far
## beyond that means the tube has crawled off its own swept path.
func _turn_path_offset(s: Snake) -> float:
	var hist_n: int = s._hist_count
	if hist_n < 8:
		return 0.0
	var root := s.global_position
	# Undo the DESIGNED 2D fake-depth shift before comparing against the
	# sim-space head path: world stations = sim stations + (0,0,-head.y*fd),
	# so adding head.y*fd back recovers the sim-space XZ the path was
	# recorded in. Without this, an elevated head (resting lift or a boulder
	# arc) reads as a uniform lateral offset that is presentation, not drift.
	root.z += s.head_pos.y * s._fake_depth
	var worst := 0.0
	for o in range(0, Snake.RING_COUNT, 24):
		var w: Vector3 = root + Vector3(s._spine[o], s._spine[o + 1], s._spine[o + 2])
		var steps := 8
		var best := 999.0
		while steps <= hist_n + 6:
			var a: Vector3 = s._hist_at(mini(steps, hist_n - 1))
			var b: Vector3 = s._hist_at(mini(steps + 8, hist_n - 1))
			best = minf(best, _seg_dist_xz(w, a, b))
			steps += 8
		worst = maxf(worst, best)
	return worst

func _seg_dist_xz(p: Vector3, a: Vector3, b: Vector3) -> float:
	var asx := p.x - a.x
	var asz := p.z - a.z
	var bsx := b.x - a.x
	var bsz := b.z - a.z
	var denom := bsx * bsx + bsz * bsz
	var t := 0.0
	if denom > 0.000001:
		t = clampf((asx * bsx + asz * bsz) / denom, 0.0, 1.0)
	var dx := asx - bsx * t
	var dz := asz - bsz * t
	return sqrt(dx * dx + dz * dz)

# ---------------------------------------------------------------- villain QA

func _villain_test_run() -> void:
	if match_world == null or match_world.player == null:
		print("VILLAINTEST FAIL no match")
		_quit_nicely()
		return
	match_world.no_death = true
	await _frames(4)
	var ais: Array = []
	for s in match_world.snakes:
		if s != match_world.player and s is AISnake and s.alive:
			ais.append(s)
	var names := {}
	var presets := {}
	var colors := {}
	var min_head := 1e9
	var min_body := 1e9
	var obstacle_ok := true
	for s in match_world.snakes:
		if not is_instance_valid(s) or not s.alive:
			continue
		for ob in match_world.obstacles:
			if s.head_pos.distance_to(ob["pos"] as Vector3) < float(ob["r"]) + 0.25:
				obstacle_ok = false
		for s2 in match_world.snakes:
			if s2 == s or not is_instance_valid(s2) or not s2.alive:
				continue
			min_head = minf(min_head, s.head_pos.distance_to(s2.head_pos))
			var n1: int = s.coll_pos.size()
			var n2: int = s2.coll_pos.size()
			if n1 > 0 and n2 > 0:
				var st1: int = maxi(1, int(n1 / 18.0))
				var st2: int = maxi(1, int(n2 / 18.0))
				for i in range(0, n1, st1):
					for j in range(0, n2, st2):
						min_body = minf(min_body, s.coll_pos[i].distance_to(s2.coll_pos[j]))
	for s in ais:
		names[s.display_name] = true
		presets[s.preset] = true
		colors[str(s.dorsal)] = true
	var count_ok: bool = ais.size() == MatchWorld.AI_TARGET
	var distinct_ok: bool = names.size() == ais.size() and presets.size() == ais.size() \
		and colors.size() == ais.size()
	var spawn_ok: bool = min_head > 6.0 and min_body > 0.9 and obstacle_ok
	var mobile_pool: Array = MatchWorld.PERSONALITY_POOL.slice(0, MatchWorld.MOBILE_AI_TARGET)
	var mobile_new_ok := true
	for n in ["cobra", "anaconda", "raptor"]:
		if not mobile_pool.has(n):
			mobile_new_ok = false
	print("VILLAINTEST mobile-roster size=%d new-villains=%s %s" % [
		mobile_pool.size(), str(mobile_new_ok), "PASS" if mobile_new_ok else "FAIL"])
	print("VILLAINTEST roster=%d names=%d presets=%d colors=%d min_head=%.1f min_body=%.1f obstacles=%s %s" % [
		ais.size(), names.size(), presets.size(), colors.size(), min_head, min_body,
		str(obstacle_ok), "PASS" if count_ok and distinct_ok and spawn_ok else "FAIL"])

	var start_pos: Array[Vector3] = []
	var start_head: Array[float] = []
	for s in ais:
		start_pos.append(s.head_pos)
		start_head.append(s.heading)
	await _frames(180)
	var moved := 0
	var turned := 0
	var body_ok := true
	var inside := true
	var worst_err := 0.0
	var worst_y := 0.0
	for i in ais.size():
		var s: AISnake = ais[i]
		if not is_instance_valid(s) or not s.alive:
			body_ok = false
			continue
		if s.head_pos.distance_to(start_pos[i]) > 0.6:
			moved += 1
		if absf(wrapf(s.heading - start_head[i], -PI, PI)) > 0.12:
			turned += 1
		if s.head_pos.length() > match_world.arena_radius + 2.0:
			inside = false
		var m := _body_metrics(s)
		worst_err = maxf(worst_err, float(m["max_err"]))
		worst_y = maxf(worst_y, float(m["y_span"]))
		if float(m["max_err"]) >= 0.30:
			var wi: int = int(m["worst_i"])
			var w0 := (wi - 1) * 4
			var w1 := wi * 4
			print("VILLAINTEST body %s len=%.1f hist=%.1f gap=%.3f..%.3f raw=%.3f..%.3f err=%.3f wi=%d sp0=(%.3f,%.3f) sp1=(%.3f,%.3f) stride=%d tick=%d head=(%.1f,%.1f)" % [
				s.display_name, s.length, m["hist_len"], m["min_gap"], m["max_gap"],
				m["raw_min"], m["raw_max"], m["max_err"], wi,
				s._spine[w0], s._spine[w0 + 2], s._spine[w1], s._spine[w1 + 2],
				s.spine_stride, s._spine_tick, s.head_pos.x, s.head_pos.z])
		# Flatness (y_span) is only guaranteed for snakes that CANNOT reach a
		# climbable boulder: the climbing sim (round A/C) legitimately lifts
		# body stations onto boulder surfaces (y_span == boulder height) when
		# a body crosses one. Path tracking (max_err) is asserted for ALL.
		var can_climb: bool = s.grounded and match_world.climb_near(s.head_pos, s.length + 1.0)
		if not s.grounded or s.body_lift < 0.20 or m["max_err"] >= 0.30 \
				or (m["y_span"] >= 0.01 and not can_climb):
			body_ok = false
	var ai_ok: bool = moved == ais.size() and turned >= maxi(1, ais.size() - 2) \
		and body_ok and inside
	print("VILLAINTEST live moved=%d/%d turned=%d/%d inside=%s body=%s worst_gap=%.3f yspan=%.4f fps=%d %s" % [
		moved, ais.size(), turned, ais.size(), str(inside), str(body_ok), worst_err, worst_y,
		Engine.get_frames_per_second(), "PASS" if ai_ok else "FAIL"])
	print("VILLAINTEST done — %s" % ("PASS" if count_ok and distinct_ok and spawn_ok and ai_ok and mobile_new_ok else "FAIL"))
	_quit_nicely()

## AILOOP: anti-loop watchdog QA. Let a FULL live roster play ~70 s of real
## match, sample every living snake at 1 Hz, then flag per snake:
## - ORBIT events: 3 s windows with heavy spin (> 0.75 turn accumulated)
##   while the real displacement stays below ~35% of the expected path —
##   the exact signature of a stuck circling/axe-tie serpent.
## - BEACHED stretches: ≥8 consecutive s under 1.5 m/s (stuck against a
##   wall/boulder with no recovery).
## PASS = total orbit events ≤ 2 and no beached snake.
func _ai_loop_test_run() -> void:
	if match_world == null or match_world.player == null:
		print("AILOOP FAIL no match")
		_quit_nicely()
		return
	print("AILOOP start dur=70s roster=%d" % match_world.snake_count())
	var hist := {}   # id -> {name, p[], h[], sp[], path[], kicks}
	var t := 0.0
	while t < 70.0:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
		if match_world == null:
			break
		for s in match_world.snakes:
			if not is_instance_valid(s) or not s.alive:
				continue
			var h: Dictionary = hist.get(s.id, {})
			if h.is_empty():
				h = {"name": s.display_name, "p": [], "h": [], "sp": [], "path": [], "kicks": 0}
				hist[s.id] = h
			var ps: Array = h["p"]
			var walked := 0.0
			if not ps.is_empty():
				walked = float(h["path"].back()) + s.head_pos.distance_to(ps.back())
			(h["p"] as Array).append(s.head_pos)
			(h["h"] as Array).append(s.heading)
			(h["sp"] as Array).append(s.speed_cur)
			(h["path"] as Array).append(walked)
			if "stuck_kicks" in s:
				h["kicks"] = int(s.stuck_kicks)
			elif "ap_loops" in s:
				h["kicks"] = int(s.ap_loops)
	var total_orbit := 0
	var total_kicks := 0
	var total_pocket := 0
	var beached := {}
	var pocketed := {}
	var engaged := 0
	var lines: Array[String] = []
	for id in hist:
		var h: Dictionary = hist[id]
		var ps: Array = h["p"]
		var hs: Array = h["h"]
		var sps: Array = h["sp"]
		var paths: Array = h["path"]
		var n := ps.size()
		var ev := 0
		var dead_air := 0
		var worst_dead := 0
		for i in range(6, n):
			var disp: float = ps[i].distance_to(ps[i - 6])
			var path_amt: float = float(paths[i]) - float(paths[i - 6])
			var turn := 0.0
			for j in range(i - 5, i + 1):
				turn += absf(wrapf(float(hs[j]) - float(hs[j - 1]), -PI, PI))
			if turn > TAU * 1.3 and path_amt > 1.0 and disp < path_amt * 0.25:
				ev += 1
			var mean_spd := (float(sps[i]) + float(sps[i - 1]) + float(sps[i - 2]) + float(sps[i - 3])) * 0.25
			if mean_spd < 1.5:
				dead_air += 1
				worst_dead = maxi(worst_dead, dead_air)
			else:
				dead_air = 0
		var mean_all := 0.0
		for v in sps:
			mean_all += float(v)
		mean_all /= maxf(1.0, float(sps.size()))
		var kicks := int(h["kicks"])
		total_kicks += kicks
		# pocket residency: non-overlapping 20 s blocks whose whole trace
		# fits inside a 16 m disc — the "stuck circling the same corner"
		# signature. Continuous running + wandering never triggers this.
		var pocket_blocks := 0
		var b0 := 0
		while b0 + 20 <= n:
			var bb_w := 0.0
			var minx := INF
			var maxx := -INF
			var minz := INF
			var maxz := -INF
			for i in range(b0, b0 + 20):
				var q: Vector3 = ps[i]
				minx = minf(minx, q.x)
				maxx = maxf(maxx, q.x)
				minz = minf(minz, q.z)
				maxz = maxf(maxz, q.z)
			bb_w = (maxx - minx) + (maxz - minz)
			if bb_w < 22.0:
				pocket_blocks += 1
			b0 += 20
		total_orbit += ev
		total_pocket += pocket_blocks
		if mean_all > 1.5:
			engaged += 1
		if worst_dead >= 8:
			beached[str(h["name"])] = worst_dead
		if pocket_blocks > 0:
			pocketed[str(h["name"])] = pocket_blocks
		lines.append("AILOOP %-22s n=%d spd=%.1f orbit_ev=%d kicks=%d pocket=%d dead_air=%d" % [
			h["name"], sps.size(), mean_all, ev, kicks, pocket_blocks, worst_dead])
	for l in lines:
		print(l)
	var ok := total_pocket <= 4 and beached.is_empty() and engaged >= 2
	print("AILOOP orbit_events=%d sustained_pocket=%d watchdog_kicks=%d beached=%s engaged=%d/%d %s" % [
		total_orbit, total_pocket, total_kicks, str(beached.keys()), engaged, hist.size(),
		"PASS" if ok else "FAIL"])
	print("AILOOP done — %s" % ("PASS" if ok else "FAIL"))
	_quit_nicely()

func _key_event(code: int, pressed: bool) -> void:
	_key_event_mod(code, pressed, false)

func _key_event_mod(code: int, pressed: bool, shift: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.shift_pressed = shift
	e.pressed = pressed
	Input.parse_input_event(e)

## Independent screen->world derivation straight from the CAMERA basis (the
## QA oracle, deliberately not the steering code path): screen right/up on the
## ground plane, whichever way the active camera is pointing.
func _screen_dir_to_world(screen: Vector2) -> Vector3:
	var b := cam.global_transform.basis
	var right := b.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3(1, 0, 0)
	var up := -b.z
	if absf(b.z.y) > 0.9:
		up = b.y                 # straight-down camera: screen-up is the cam's Y axis
	up.y = 0.0
	up = up.normalized() if up.length_squared() > 0.001 else Vector3(0, 0, -1)
	var d := right * screen.x + up * screen.y
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.001 else Vector3.ZERO

func _dir_test_run() -> void:
	_joy_dev = true
	_solo_dev = true
	_no_death_dev = true
	var fails := 0
	for mode in [0, 1]:
		hud.mode_changed.emit(mode)      # real selector path (env + camera + save)
		_start_play()
		await get_tree().create_timer(0.9).timeout
		match_world.no_death = true
		var p: PlayerSnake = match_world.player
		p.autopilot = false              # dev brain would overwrite steering
		p._is_mobile = false
		p.keyboard_only = true           # isolate keys from the offscreen pointer
		Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5)
		await _frames(30)
		print("DIRTEST === mode=%d (%s) camera=%.0f,%.0f,%.0f proj=%d ===" % [
			mode, "2D top-down" if mode == 0 else "3D chase",
			cam.global_position.x, cam.global_position.y, cam.global_position.z, cam.projection])
		for k in DIR_KEYS:
			await _frames(3)
			p.head_pos = Vector3.ZERO       # known start: arena center, heading +Z
			p.heading = 0.0
			p.clear_keys()
			await _frames(2)
			_key_event(k["code"], true)
			await _frames(70)               # let the turn rate settle on the key
			var before: Vector3 = p.head_pos
			await _frames(20)
			var moved: Vector3 = p.head_pos - before
			moved.y = 0.0
			var want := _screen_dir_to_world(k["screen"])
			var moved_n: Vector3 = moved.normalized() if moved.length() > 0.001 else Vector3.ZERO
			var dot := moved_n.dot(want)
			var travelled := moved.length()
			# holding the key must NOT keep rotating the snake: that relative
			# yaw bug is exactly what made it "move in circles"
			var h0 := p.heading
			await _frames(30)
			var spin := absf(wrapf(p.heading - h0, -PI, PI))
			# releasing must not reset the direction: the steering target
			# stays on the key direction and the snake keeps its line
			_key_event(k["code"], false)
			await _frames(3)
			var keep := p.desired_dir
			var h1 := p.heading
			await _frames(24)
			var hold := absf(wrapf(p.heading - h1, -PI, PI))
			var keeps_dir: bool = absf(keep.normalized().dot(want)) > 0.9
			var ok := travelled > 0.8 and dot > 0.93 and spin < 0.10 and keeps_dir and hold < 0.12
			print("DIRTEST mode=%d %-5s moved=(%.1f,%.1f) want=(%.2f,%.2f) dot=%.2f spin=%.3f keep=%.3f hold=%.3f %s" % [
				mode, k["name"], moved.x, moved.z, want.x, want.z, dot, spin,
				keep.normalized().dot(want), hold, "PASS" if ok else "FAIL"])
			if not ok:
				fails += 1
			p.clear_keys()
		# 180 degree switch: must settle on the new key, never spin
		await _frames(3)
		p.head_pos = Vector3.ZERO
		p.heading = 0.0
		_key_event(KEY_D, true)
		await _frames(70)
		_key_event(KEY_D, false)
		_key_event(KEY_A, true)
		await _frames(70)
		var before2: Vector3 = p.head_pos
		await _frames(20)
		var m2: Vector3 = p.head_pos - before2
		m2.y = 0.0
		var want2 := _screen_dir_to_world(Vector2(-1, 0))
		var d2: Vector3 = m2.normalized() if m2.length() > 0.001 else Vector3.ZERO
		var ok2: bool = m2.length() > 0.8 and d2.dot(want2) > 0.93
		print("DIRTEST mode=%d 180-switch dot=%.2f %s" % [mode, d2.dot(want2), "PASS" if ok2 else "FAIL"])
		if not ok2:
			fails += 1
		_key_event(KEY_A, false)
		p.clear_keys()
		await _frames(6)
	fails += await _dir_joy_test()
	print("DIRTEST RESULT %s" % ["PASS - every direction key steers the way it is pressed" if fails == 0 else "FAIL (%d checks)" % fails])
	await _snap("shot_dirtest.png")
	_quit_nicely()

# ---------------------------------------------------------------- ctrl QA

## Control QA: 360-degree mobile steering, release-keeps-going, touch anywhere
## (never stealing a HUD tap), and desktop keys surviving pause/restart.
func _ctrl_test_run() -> void:
	_joy_dev = true
	_solo_dev = true
	_no_death_dev = true
	hud.mode_changed.emit(0)          # the stick lives in 2D mode
	_start_play()
	await get_tree().create_timer(0.9).timeout
	match_world.no_death = true
	var p: PlayerSnake = match_world.player
	var joy: TouchJoystick = hud.joystick()
	p.autopilot = false
	p._is_mobile = true
	await _frames(30)
	var fails := 0
	var bad := 0
	# --- 1. every 15 degrees around the circle must steer that way ---
	for deg in range(0, 360, 15):
		var a := deg_to_rad(float(deg))
		var v := Vector2(cos(a), sin(a))
		p.head_pos = Vector3.ZERO
		p.heading = 0.0
		joy.force_value(v)
		await _frames(70)             # let the turn rate settle
		var before: Vector3 = p.head_pos
		await _frames(18)
		var moved: Vector3 = p.head_pos - before
		moved.y = 0.0
		var want := _screen_dir_to_world(v)
		var mn: Vector3 = moved.normalized() if moved.length() > 0.001 else Vector3.ZERO
		var dot := mn.dot(want)
		if not (moved.length() > 0.6 and dot > 0.96):
			bad += 1
			print("CTRLTEST angle %3d deg dot=%.3f moved=%.2f FAIL" % [deg, dot, moved.length()])
	joy.force_release()
	print("CTRLTEST 360 sweep %d angles %s" % [24,
		"PASS" if bad == 0 else "FAIL (%d)" % bad])
	if bad > 0:
		fails += bad
	# --- 1b. same behavior in 3D mode (the stick is available in both) ---
	hud.mode_changed.emit(1)
	await _frames(60)
	var bad3 := 0
	for deg in [15, 30, 45, 60, 75, 135, 225, 315]:
		var a3 := deg_to_rad(float(deg))
		var v3 := Vector2(cos(a3), sin(a3))
		p.head_pos = Vector3.ZERO
		p.heading = 0.0
		joy.force_value(v3)
		await _frames(70)
		var b3: Vector3 = p.head_pos
		await _frames(18)
		var m3: Vector3 = p.head_pos - b3
		m3.y = 0.0
		var w3 := _screen_dir_to_world(v3)
		var n3: Vector3 = m3.normalized() if m3.length() > 0.001 else Vector3.ZERO
		if not (m3.length() > 0.6 and n3.dot(w3) > 0.96):
			bad3 += 1
			print("CTRLTEST 3D angle %3d deg dot=%.3f FAIL" % [deg, n3.dot(w3)])
	joy.force_release()
	print("CTRLTEST 3D sweep 8 angles %s" % ["PASS" if bad3 == 0 else "FAIL (%d)" % bad3])
	if bad3 > 0:
		fails += bad3
	hud.mode_changed.emit(0)
	await _frames(40)
	# --- 2. release keeps the last direction, snake never stops ---
	p.head_pos = Vector3.ZERO
	p.heading = 0.0
	joy.force_value(Vector2(0.0, 1.0))
	await _frames(70)
	joy.force_release()
	var h0 := p.heading
	var pos0: Vector3 = p.head_pos
	await _frames(90)
	var drift := absf(wrapf(p.heading - h0, -PI, PI))
	var rolled := p.head_pos.distance_to(pos0)
	var kept: bool = drift < 0.05 and rolled > 4.0 and joy.last_dir == Vector2(0, 1)
	print("CTRLTEST release keeps heading drift=%.3f travelled=%.1fm last_dir=%s %s" % [
		drift, rolled, str(joy.last_dir), "PASS" if kept else "FAIL"])
	if not kept:
		fails += 1
	# --- 3. a touch ANYWHERE grabs the stick (not just the left zone) ---
	var vs := get_viewport().get_visible_rect().size
	var far_spot := Vector2(vs.x * 0.78, vs.y * 0.45)
	_touch_event(0, far_spot, true)
	await _frames(3)
	var grabbed: bool = joy.active and joy.center().distance_to(far_spot) < 3.0
	_drag_event(0, far_spot + Vector2(0.0, -joy.radius() * 0.8))
	await _frames(6)
	var up_val: Vector2 = joy.value
	_touch_event(0, far_spot + Vector2(0.0, -joy.radius() * 0.8), false)
	await _frames(3)
	var any_ok: bool = grabbed and up_val.y > 0.6
	print("CTRLTEST touch-anywhere spot=(%.0f,%.0f) active=%s base_moved=%s value=%s %s" % [
		far_spot.x, far_spot.y, str(joy.active), str(grabbed), str(up_val),
		"PASS" if any_ok else "FAIL"])
	if not any_ok:
		fails += 1
	# --- 4. the stick never steals a tap that belongs to a HUD control ---
	var pb: Button = hud._pause_btn
	var prect := pb.get_global_rect()
	var pspot := prect.get_center()
	# the live board must be free to steer BEFORE the modal pause card opens
	var center_free: bool = not hud.blocks_touch(vs * 0.5)
	_touch_event(0, pspot, true)
	await _frames(3)
	var stolen: bool = joy.active
	var pause_fired: bool = get_tree().paused
	_touch_event(0, pspot, false)
	await _frames(3)
	# Opening the pause card is a valid outcome of tapping PAUSE (UIX covers
	# it); what matters here is that the stick never captures the tap and the
	# live board centre was steerable first.
	var ui_ok: bool = not stolen and hud.blocks_touch(pspot) and center_free
	print("CTRLTEST ui-block pause_rect=%s stick_stole=%s pause_fired=%s center_free=%s %s" % [
		str(prect.size.round()), str(stolen), str(pause_fired), str(center_free),
		"PASS" if ui_ok else "FAIL"])
	if not ui_ok:
		fails += 1
	# leave the match live for the pause/resume keyboard check below
	if get_tree().paused:
		_resume()
		await _frames(3)
	# --- 5. keys still work after pause/resume and after a restart ---
	p.keyboard_only = true
	_pause()
	await _frames(4)
	_resume()
	await _frames(10)
	_key_event(KEY_D, true)
	await _frames(4)
	var after_pause := p.desired_dir
	_key_event(KEY_D, false)
	_restart()
	await get_tree().create_timer(0.7).timeout
	var p2: PlayerSnake = match_world.player
	p2.autopilot = false
	p2.keyboard_only = true
	await _frames(10)
	_key_event(KEY_W, true)
	await _frames(4)
	var after_restart := p2.desired_dir
	_key_event(KEY_W, false)
	var key_ok: bool = after_pause.normalized().dot(_screen_dir_to_world(Vector2(1, 0))) > 0.95 \
		and after_restart.normalized().dot(_screen_dir_to_world(Vector2(0, 1))) > 0.95
	print("CTRLTEST keys after pause/resume=%s after restart=%s %s" % [
		str(after_pause), str(after_restart), "PASS" if key_ok else "FAIL"])
	if not key_ok:
		fails += 1
	# --- 6. SHIFT+W (uppercase) still steers up, and WASD/arrows mix freely ---
	p2.clear_keys()
	_key_event_mod(KEY_W, true, true)    # SHIFT+W = uppercase W
	await _frames(3)
	var shifted: Vector2 = p2._keys_dir
	_key_event(KEY_UP, true)          # same direction from the other scheme
	await _frames(3)
	var both: Vector2 = p2._keys_dir
	_key_event(KEY_W, false)          # release one of the two
	await _frames(3)
	var still_up: Vector2 = p2._keys_dir
	_key_event(KEY_A, true)           # add a second direction -> diagonal
	await _frames(3)
	var diag: Vector2 = p2._keys_dir
	_key_event(KEY_UP, false)
	_key_event(KEY_A, false)
	await _frames(3)
	var cleared: Vector2 = p2._keys_dir
	var mix_ok: bool = shifted == Vector2(0, 1) and both == Vector2(0, 1) \
		and still_up == Vector2(0, 1) \
		and diag.normalized().dot(Vector2(-0.707, 0.707)) > 0.99 \
		and cleared == Vector2.ZERO
	print("CTRLTEST shift/mix w=%s w+up=%s after-release-w=%s w+a=%s cleared=%s %s" % [
		str(shifted), str(both), str(still_up), str(diag), str(cleared),
		"PASS" if mix_ok else "FAIL"])
	if not mix_ok:
		fails += 1
	print("CTRLTEST RESULT %s" % ["PASS" if fails == 0 else "FAIL (%d)" % fails])
	await _snap("shot_ctrl.png")
	_quit_nicely()

## Mobile stick QA: a touch anywhere in the left zone grabs the stick (the
## circling bug), drags steer, and an untouched stick holds the heading instead
## of auto-arc circles.
func _dir_joy_test() -> int:
	var fails := 0
	hud.mode_changed.emit(0)          # the stick is a 2D-mode control
	_start_play()
	await get_tree().create_timer(0.9).timeout
	match_world.no_death = true
	var p: PlayerSnake = match_world.player
	var joy: TouchJoystick = hud.joystick()
	p.autopilot = false
	p._is_mobile = true
	await _frames(30)
	var vs := get_viewport().get_visible_rect().size
	var spot := Vector2(vs.x * 0.36, vs.y * 0.52)
	var far := joy.center().distance_to(spot) > joy.radius() * 1.3
	_touch_event(0, spot, true)
	await _frames(3)
	var grabbed := joy.active and joy.center().distance_to(spot) < 3.0
	print("DIRTEST joy zone-grab (%.0f px from ring)=%s active=%s base_moved=%s %s" % [
		joy.center().distance_to(spot), str(far), str(joy.active),
		str(grabbed), "PASS" if grabbed else "FAIL"])
	if not grabbed:
		fails += 1
	# drag up on the (re-centered) stick -> snake must travel up-screen
	p.head_pos = Vector3.ZERO
	p.heading = 0.0
	_drag_event(0, spot - Vector2(0.0, joy.radius() * 0.8))
	await _frames(80)
	print("DIRTEST joy state touch_id=%d base=%s value=%s" % [
		joy._touch_id, str(joy.center()), str(joy.value)])
	var before: Vector3 = p.head_pos
	await _frames(20)
	var moved: Vector3 = p.head_pos - before
	moved.y = 0.0
	var want := _screen_dir_to_world(Vector2(0, 1))
	var mn: Vector3 = moved.normalized() if moved.length() > 0.001 else Vector3.ZERO
	var dot := mn.dot(want)
	var ok_drag: bool = moved.length() > 0.8 and dot > 0.93
	print("DIRTEST joy drag-up joy_vec=%s moved=(%.1f,%.1f) want=(%.2f,%.2f) dot=%.2f %s" % [
		str(p.joy_vec), moved.x, moved.z, want.x, want.z, dot, "PASS" if ok_drag else "FAIL"])
	if not ok_drag:
		fails += 1
	# let go: heading must be held, no idle circles
	_touch_event(0, spot - Vector2(0.0, joy.radius() * 0.8), false)
	await _frames(4)
	var h0 := p.heading
	await _frames(90)
	var spin := absf(wrapf(p.heading - h0, -PI, PI))
	var ok_idle := spin < 0.12 and p.joy_vec == Vector2.ZERO and not p.no_idle_drift == false
	print("DIRTEST joy idle no_drift=%s joy_vec=%s heading_drift=%.3f %s" % [
		str(p.no_idle_drift), str(p.joy_vec), spin, "PASS" if ok_idle else "FAIL"])
	if not ok_idle:
		fails += 1
	return fails

# ---------------------------------------------------------------- mode QA

func _mode_test_run() -> void:
	# Drives the REAL selector buttons (spec §1): press 2D, verify the game is
	# in 2D mode, the world camera is top-down, the save matches and the button
	# shows ACTIVE; then the same for 3D TPS.
	await get_tree().create_timer(1.2).timeout
	_start_play()
	match_world.no_death = true
	await get_tree().create_timer(1.5).timeout
	for want in [0, 1]:
		var btn: Button = null
		for b in hud._topt:
			if str(b.get_meta("opt_group")) == "gfx_mode" and int(b.get_meta("opt_value")) == want:
				btn = b
				break
		if btn == null:
			print("MODETEST FAIL no button for ", want)
			_quit_nicely()
			return
		btn.emit_signal("pressed")
		for i in 40:
			await get_tree().physics_frame
		var is_2d := _gfx_mode == 0
		var cam_ok := false
		if want == 0:
			# flat orthographic board, camera straight above
			cam_ok = cam.projection == Camera3D.PROJECTION_ORTHOGONAL \
				and cam.global_position.y > 15.0 and absf(cam.global_transform.basis.z.y - 1.0) < 0.01
		else:
			# perspective 3D view: elevated, NOT straight down
			cam_ok = cam.projection == Camera3D.PROJECTION_PERSPECTIVE \
				and cam.global_position.y > 6.0 and absf(cam.global_transform.basis.z.y) < 0.95
		var saved_ok: bool = int(SaveMgr.get_value("gfx_mode", -1)) == want
		var active_ok := str(btn.text).contains("●")
		print("MODETEST want=%d mode=%d cam_topdown_ok=%s saved=%s active_mark=%s %s" % [
			want, _gfx_mode, str(cam_ok), str(saved_ok), str(active_ok),
			"PASS" if (is_2d == (want == 0) and cam_ok and saved_ok and active_ok) else "FAIL"])
	await _snap("shot_mode_%d.png" % _gfx_mode)
	_quit_nicely()

# ---------------------------------------------------------------- UI QA

func _uix_test_run() -> void:
	# pause button / resume / quit-confirm behavior through the real signal
	# paths (spec sections 3 and 6)
	await get_tree().create_timer(2.0).timeout
	match_world.no_death = true
	print("UIXTEST playing=%s btn=%s" % [str(state == State.PLAYING), hud._pause_btn.text])
	_pause()
	await get_tree().process_frame
	var paused_ok := state == State.PAUSED and get_tree().paused and hud._pause_btn.text == "▶"
	print("UIXTEST paused %s (tree.paused=%s glyph=%s)" % ["PASS" if paused_ok else "FAIL", str(get_tree().paused), hud._pause_btn.text])
	await _snap("shot_pause.png")
	_resume()
	await get_tree().process_frame
	print("UIXTEST resumed %s (time=%.1f)" % ["PASS" if state == State.PLAYING and not get_tree().paused else "FAIL", match_world.match_time])
	hud.show_quit_confirm(true)
	await get_tree().process_frame
	var quit_ok := hud._quit_panel.visible and hud.overlay_group.visible
	print("UIXTEST quit-dialog %s" % ["PASS" if quit_ok else "FAIL"])
	await _snap("shot_quit.png")
	hud.show_quit_confirm(false)
	await get_tree().process_frame
	# CANCEL (No) must restore the screen the dialog was opened from —
	# mid-match that means NO scrim left behind (an invisible scrim was the
	# mobile quit-freeze: it blocked every touch after "No")
	var cancel_live_ok: bool = not hud._quit_panel.visible \
		and not hud.overlay_group.visible and state == State.PLAYING \
		and not get_tree().paused
	print("UIXTEST quit-cancel %s" % ["PASS" if cancel_live_ok else "FAIL"])
	# CANCEL from the PAUSE screen: pause panel must come back, tree still
	# paused (No cancels the quit, it does not resume the match)
	_pause()
	await get_tree().process_frame
	hud.show_quit_confirm(true)
	await get_tree().process_frame
	hud.show_quit_confirm(false)
	await get_tree().process_frame
	var cancel_pause_ok: bool = not hud._quit_panel.visible \
		and hud._pause_panel.visible and hud.overlay_group.visible \
		and get_tree().paused and state == State.PAUSED
	print("UIXTEST quit-cancel-pause %s" % ["PASS" if cancel_pause_ok else "FAIL"])
	# ... and the paused game must still resume cleanly afterwards
	_resume()
	await get_tree().process_frame
	var resume_after_ok: bool = state == State.PLAYING and not get_tree().paused
	print("UIXTEST resume-after-cancel %s" % ["PASS" if resume_after_ok else "FAIL"])
	# CANCEL from the HOME MENU (the real mobile flow — the Quit button lives
	# there): back to the interactive menu, zero scrim, nothing paused
	hud.tomenu_pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	hud.show_quit_confirm(true)
	await get_tree().process_frame
	hud.show_quit_confirm(false)
	await get_tree().process_frame
	var cancel_menu_ok: bool = not hud._quit_panel.visible \
		and not hud.overlay_group.visible and hud.menu_group.visible
	print("UIXTEST quit-cancel-menu %s" % ["PASS" if cancel_menu_ok else "FAIL"])
	# repeated quit attempts keep working (no residue builds up)
	hud.show_quit_confirm(true)
	await get_tree().process_frame
	var repeat_ok: bool = hud._quit_panel.visible and hud.overlay_group.visible
	hud.show_quit_confirm(false)
	await get_tree().process_frame
	repeat_ok = repeat_ok and not hud._quit_panel.visible and not hud.overlay_group.visible
	print("UIXTEST quit-repeat %s" % ["PASS" if repeat_ok else "FAIL"])
	# Full-bleed menu regression: with a simulated device cutout the themed
	# menu must still cover the whole viewport, but its interactive column must
	# start inside the safe area. This checks the actual camera-side fix.
	hud.show_menu(true)
	hud._menu_page("main")
	await get_tree().process_frame
	# Structural check first, deterministically: read the column offsets in the
	# same frame the fake insets are applied. Waiting before the read lets a
	# stray headless size_changed event call _apply_safe_area() (zero insets in
	# headless) in-between — an event-pump race of the test rig, not of the
	# menu (a late real-insets application re-applies the bleed correctly on
	# device).
	var old_insets: Vector4 = hud._safe_insets
	hud._safe_insets = Vector4(60.0, 10.0, 5.0, 20.0)
	hud._apply_menu_bleed()
	var exp_left: float = hud._menu_margin_side
	var exp_top: float = hud._menu_margin_top + 10.0
	var exp_right: float = -hud._menu_margin_side
	var exp_bottom: float = -(hud._menu_margin_bottom + 20.0)
	var column_safe: bool = hud._menu_column.offset_left >= exp_left - 0.1 \
		and hud._menu_column.offset_top >= exp_top - 0.1 \
		and hud._menu_column.offset_right <= exp_right + 0.1 \
		and hud._menu_column.offset_bottom <= exp_bottom + 0.1
	print("UIXTEST safe-column %s offsets=(%.0f,%.0f,%.0f,%.0f) expected=(%.0f,%.0f,%.0f,%.0f)" % [
		"PASS" if column_safe else "FAIL", hud._menu_column.offset_left,
		hud._menu_column.offset_top, hud._menu_column.offset_right, hud._menu_column.offset_bottom,
		exp_left, exp_top, exp_right, exp_bottom])
	hud._apply_menu_bleed()
	await get_tree().process_frame
	await get_tree().process_frame
	var vr := get_viewport().get_visible_rect().size
	var menu_rect: Rect2 = hud.menu_group.get_global_rect()
	var menu_covered: bool = menu_rect.position.x <= 0.01 \
		and menu_rect.position.y <= 0.01 \
		and menu_rect.position.x + menu_rect.size.x >= vr.x - 0.01 \
		and menu_rect.position.y + menu_rect.size.y >= vr.y - 0.01
	print("UIXTEST full-bleed-menu %s rect=(%.0f,%.0f)+%.0fx%.0f viewport=%.0fx%.0f" % [
		"PASS" if menu_covered else "FAIL", menu_rect.position.x, menu_rect.position.y,
		menu_rect.size.x, menu_rect.size.y, vr.x, vr.y])
	# Stray-panel probe: every visible painted Control touching the left edge
	# (x < 40 px) that is NOT an intended full-screen layer — catches off-screen
	# panel slivers leaking into the view.
	var strays: Array[String] = []
	_dump_painted_below_x(hud.menu_group, 40.0, strays)
	for s in strays:
		print("UIXTEST stray-x %s" % s)
	print("UIXTEST stray-count=%d %s" % [strays.size(),
		"PASS" if strays.is_empty() else "INFO"])
	# Page-row geometry dump: brand | gap | card positions so a layout bug
	# shows up as hard numbers instead of a screenshot guess.
	var page: HBoxContainer = null
	for c in hud._menu_column.get_children():
		if c is HBoxContainer:
			page = c
			break
	if page != null:
		var vr2 := get_viewport().get_visible_rect().size
		print("UIXTEST pagemeta vs=%v col=(%.0f..%.0f) page=(%.0f..%.0f) sep=%d" % [
			vr2, hud._menu_column.get_global_rect().position.x,
			hud._menu_column.get_global_rect().position.x + hud._menu_column.size.x,
			page.get_global_rect().position.x,
			page.get_global_rect().position.x + page.size.x,
			page.get_theme_constant("separation")])
		for c3 in page.get_children():
			var cc3 := c3 as Control
			if cc3 != null:
				var r3 := cc3.get_global_rect()
				print("UIXTEST pagerow %s<%s> min_x=%.0f rect=(%.0f..%.0f) w=%.0f" % [
					cc3.name, cc3.get_class(),
					cc3.custom_minimum_size.x, r3.position.x,
					r3.position.x + r3.size.x, r3.size.x])
	hud._safe_insets = old_insets
	hud._apply_menu_bleed()
	_quit_nicely()

## Recursive walk recording visible painted Controls currently left of `x`.
func _dump_painted_below_x(n: Node, x: float, out: Array[String]) -> void:
	for c in n.get_children():
		var cc := c as Control
		if cc != null and cc.is_visible_in_tree():
			var r := cc.get_global_rect()
			if r.size.x > 4.0 and r.size.y > 4.0 and r.position.x < x \
					and (cc.is_class("PanelContainer") or cc.is_class("Panel") \
						or cc.is_class("TextureRect") or cc.is_class("ColorRect")):
				out.append("%s<%s> path=%s rect=(%.0f,%.0f)+%.0fx%.0f" % [
					cc.name, cc.get_class(), _node_path_short(cc), r.position.x,
					r.position.y, r.size.x, r.size.y])
		_dump_painted_below_x(c, x, out)

func _node_path_short(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	while cur != null and parts.size() < 5:
		parts.append(cur.name)
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)

# ---------------------------------------------------------------- theme QA

func _theme_test_run() -> void:
	# BEIGE/DARK menu QA: palette truth, live switch through the REAL menu
	# pills, independence from ARENA, and arena night-pass independence.
	print(UiTheme.theme_report())
	var arena0 := str(SaveMgr.get_value("arena", "valley"))
	var theme0 := int(SaveMgr.get_value("theme", UiTheme.LIGHT))
	var mode0 := int(SaveMgr.get_value("gfx_mode", 1))

	# 1) The palettes themselves must actually be light/dark, not two navies.
	# The beige palette must also be visibly warm (r > g > b), never pure white
	# and never the old pale-sage panel.
	UiTheme.set_theme(UiTheme.LIGHT)
	var lp := UiTheme.c("panel_bg")
	var lb := UiTheme.c("btn_bg")
	var lt := UiTheme.c("text")
	var light_contrast := UiTheme.contrast(lt, lp)
	UiTheme.set_theme(UiTheme.DARK)
	var dp := UiTheme.c("panel_bg")
	var dt := UiTheme.c("text")
	var dark_contrast := UiTheme.contrast(dt, dp)
	var palette_ok: bool = lp.get_luminance() > 0.60 and dp.get_luminance() < 0.20 \
		and light_contrast >= 4.5 and dark_contrast >= 4.5 \
		and lp.r > lp.g and lp.g > lp.b and lp.b < 0.92 \
		and lb.r > lb.g and lb.g > lb.b and lb.b < 0.96
	print("THEMETEST palette beige_lum=%.2f dark_lum=%.2f contrast=%.1f/%.1f %s" % [
		lp.get_luminance(), dp.get_luminance(), light_contrast, dark_contrast,
		"PASS" if palette_ok else "FAIL"])
	if not palette_ok:
		_quit_nicely()
		return

	# 2) Drive the real selector pills. Both the UI palette and the dedicated
	# menu backdrop must change; the arena must not.
	var beige_btn: Button = null
	var dark_btn: Button = null
	for b in hud._topt:
		if not is_instance_valid(b) or str(b.get_meta("opt_group")) != "theme":
			continue
		if int(b.get_meta("opt_value")) == UiTheme.LIGHT:
			beige_btn = b
		elif int(b.get_meta("opt_value")) == UiTheme.DARK:
			dark_btn = b
	if beige_btn == null or dark_btn == null:
		print("THEMETEST FAIL missing main-menu theme pills")
		_quit_nicely()
		return

	beige_btn.emit_signal("pressed")
	await get_tree().process_frame
	var light_bg := menu_world.menu_bg_color()
	var light_menu_ok: bool = not menu_world.dark and light_bg.get_luminance() > 0.60 \
		and str(SaveMgr.get_value("arena", "valley")) == arena0
	print("THEMETEST beige-menu bg_lum=%.2f arena_same=%s %s" % [
		light_bg.get_luminance(),
		str(str(SaveMgr.get_value("arena", "valley")) == arena0),
		"PASS" if light_menu_ok else "FAIL"])

	dark_btn.emit_signal("pressed")
	await get_tree().process_frame
	var dark_bg := menu_world.menu_bg_color()
	var dark_menu_ok: bool = menu_world.dark and dark_bg.get_luminance() < 0.20
	print("THEMETEST dark-menu bg_lum=%.2f %s" % [
		dark_bg.get_luminance(),
		"PASS" if dark_menu_ok else "FAIL"])

	# 3) Arena switch must never override the selected menu theme.
	hud.arena_shift.emit(1)
	await get_tree().process_frame
	var arena1 := str(SaveMgr.get_value("arena", "valley"))
	var arena_name := str(ArenaPresets.get_preset(arena1).get("name", ""))
	var arena_label_ok: bool = hud._arena_label != null and is_instance_valid(hud._arena_label) \
		and hud._arena_label.text == arena_name
	var theme_kept: bool = int(SaveMgr.get_value("theme", 0)) == UiTheme.DARK \
		and menu_world.dark
	print("THEMETEST arena-section arena=%s theme_same=%s label=%s %s" % [
		arena1, str(theme_kept), str(arena_label_ok),
		"PASS" if arena1 != arena0 and theme_kept and arena_label_ok else "FAIL"])

	# 4) Theme switch must never change the arena.
	var arena_before_theme := arena1
	beige_btn.emit_signal("pressed")
	await get_tree().process_frame
	var arena_after_beige := str(SaveMgr.get_value("arena", "valley"))
	dark_btn.emit_signal("pressed")
	await get_tree().process_frame
	var arena_after_dark := str(SaveMgr.get_value("arena", "valley"))
	print("THEMETEST arena-independent beige_same=%s dark_same=%s %s" % [
		str(arena_after_beige == arena_before_theme), str(arena_after_dark == arena_before_theme),
		"PASS" if arena_after_beige == arena_before_theme and arena_after_dark == arena_before_theme else "FAIL"])

	for m in 2:
		hud.mode_changed.emit(m)
		await get_tree().process_frame
		print("THEMETEST mode=%d cam_tilt_dirty=%s saved=%d" % [m, str(_topdown_dirty), int(SaveMgr.get_value("gfx_mode", 1))])

	# 5) Start a real match with DARK selected but a non-night arena. The
	# arena must use its OWN palette, proving the UI theme is decoupled.
	var arena_night := bool(ArenaPresets.get_preset(arena1).get("night", false))
	_start_play()
	if match_world != null:
		match_world.no_death = true
	await _frames(30)
	var play_ok: bool = match_world != null and match_world.arena_key == arena1 \
		and match_world.gfx_mode == 1 and match_world.dark == arena_night \
		and int(SaveMgr.get_value("theme", 0)) == UiTheme.DARK
	print("THEMETEST gameplay theme=DARK arena=%s arena_night=%s world_night=%s mode=%d %s" % [
		arena1, str(arena_night), str(match_world.dark) if match_world != null else "null",
		match_world.gfx_mode if match_world != null else -1,
		"PASS" if play_ok else "FAIL"])

	# restore the player's choices so QA never leaves the save dirty
	SaveMgr.set_value("arena", arena0)
	SaveMgr.set_value("theme", theme0)
	SaveMgr.set_value("gfx_mode", mode0)
	_arena_key = arena0
	_theme_id = theme0
	hud.set_arena(arena0)
	hud.apply_theme(theme0)
	menu_world.set_dark(theme0 == UiTheme.DARK)
	print("THEMETEST done — PASS")
	_quit_nicely()

# ---------------------------------------------------------------- eat QA

## Clear, obstacle-free anchor with a straight +Z runway for the eat test.
func _eat_anchor(food) -> Vector3:
	var cands: Array = [Vector3.ZERO]
	for ring in 2:
		for k in 8:
			var ang := TAU * float(k) / 8.0
			var rad := 10.0 + 9.0 * float(ring)
			cands.append(Vector3(sin(ang) * rad, 0.0, cos(ang) * rad))
	for c in cands:
		var pos: Vector3 = c
		var clear := true
		for d in 8:
			var q: Vector3 = pos + Vector3(0, 0, float(d))
			if q.length() > float(food.arena_radius) - 8.0 \
					or not food._clear_of_obstacles(q, 1.4):
				clear = false
				break
		if clear:
			return pos
	return Vector3.ZERO

func _eat_find(food, kind: int, at: Vector3) -> Dictionary:
	for s in food._slots[kind]:
		var alive: Dictionary = s["alive"]
		for idx in alive.keys():
			var rec: Dictionary = alive[idx]
			if rec.has("fly"):
				continue
			if (rec["pos"] as Vector3).distance_to(at) < 0.05:
				return {"slot": s, "idx": int(idx), "rec": rec}
	return {}

func _eat_in_pool(food, qa_id: int) -> bool:
	for kind in food._slots.size():
		for s: Dictionary in food._slots[kind]:
			var alive: Dictionary = s["alive"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if int(rec.get("qa", -1)) == qa_id:
					return true
	return false

## Every passive fruit must be inside the safe ring, clear of obstacles and
## separated from every other fruit. Returns the number of violations.
func _eat_validate_court(food) -> int:
	var bad := 0
	var pts: Array = []
	var gap: float = float(FoodSpawner.FRUIT_GAP) - 0.05
	for kind in food._slots.size():
		var rad: float = float(FoodSpawner.KIND_RADIUS[kind])
		for s: Dictionary in food._slots[kind]:
			var alive: Dictionary = s["alive"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if rec.has("fly"):
					continue
				var pos: Vector3 = rec["pos"]
				if pos.length() > float(food.arena_radius) - float(FoodSpawner.SPAWN_EDGE) + 0.05:
					bad += 1
				if not food._clear_of_obstacles(pos, rad):
					bad += 1
				for o in pts:
					if pos.distance_squared_to(o) < gap * gap:
						bad += 1
				pts.append(pos)
	return bad

## Standalone long-body check (also covers the 90 m boss, longer than the
## player's 76 m cap): the spine's tail must be a full body length BEHIND the
## head and keep a visible radius.
func _eat_long_probe(len_m: float, max_len: float) -> bool:
	var s := Snake.new()
	s.max_length = max_len
	match_world.add_child(s)
	s.spawn(Vector3.ZERO, Vector3(0, 0, 1), len_m)
	s._update_spine(0.016)
	var o := (Snake.RING_COUNT - 1) * 4
	var head := Vector3(s._spine[0], s._spine[1], s._spine[2])
	var tail := Vector3(s._spine[o], s._spine[o + 1], s._spine[o + 2])
	var dist := Vector2(tail.x - head.x, tail.z - head.z).length()
	var rad := float(s._spine[o + 3])
	var behind: bool = (tail - head).dot(Vector3(0, 0, -1)) > 0.0
	var ok: bool = behind and dist > len_m * 0.9 and dist < len_m * 1.1 and rad > 0.02
	print("EATTEST long-probe len=%.0f tail=%.2f radius=%.3f behind=%s %s" % [
		len_m, dist, rad, str(behind), "PASS" if ok else "FAIL"])
	s.queue_free()
	return ok

## One controlled eat case. The lane is cleared of natural fruit and respawns
## are frozen while the exact score/growth/gulp/flight are measured.
func _eat_phase(p, food, length: float, kind: int, count: int, label: String,
		check_respawn: bool) -> bool:
	food.qa_freeze_respawn = true
	var anchor := _eat_anchor(food)
	p.spawn(anchor, Vector3(0, 0, 1), length)
	await _frames(2)
	# A magnet granted by an EARLIER case (its timer outlives spawn()) keeps
	# vacuuming ambient orbs for the whole next case (reach x4.5 ~= 4+ m) and
	# inflates its gulp count. Each case must measure only its own fruit, so
	# start every case ability-clean. (The shield halo recomputes from
	# ability_active every tick, so a direct clear leaves no stale visuals.)
	p.ability = ""
	p.ability_left = 0.0
	food.reset()
	await _frames(1)
	var mouth: Vector3 = p.mouth_pos
	var fwd: Vector3 = Vector3(sin(p.heading), 0.0, cos(p.heading))
	# Clear the reset's fruit off the ENTIRE test corridor: the player travels
	# ~30 m during the claim window, so anything ahead of the lane (ambient
	# power orbs score 0 — the exact "extra gulp, score unchanged" signature)
	# must go, not just a disc around the mouth. Bury = freeze keeps it gone.
	# Width 6.0: the MAGNET ability (granted by this case's own power orb 50%
	# of the time) multiplies the head/mouth sweep reach x4.5 to ~4.5 m, so a
	# 4.0 m clear left ambient orbs inside vacuum range — legit gameplay ate
	# them mid-window and inflated the gulp count. 6.0 covers the max
	# magnetised sweep radius with margin. Records ALREADY IN FLIGHT are
	# buried too (no "fly" exemption): a claim
	# from the frames between reset() and this clear would otherwise fly
	# straight through the case and swallow INSIDE the gulp window — the
	# exact cross-case pollution this harness kept flaking on. reset() does
	# the same to every flying record, so mid-flight burial is proven safe.
	for k in food._slots.size():
		for s: Dictionary in food._slots[k]:
			var alive: Dictionary = s["alive"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				var fp: Vector3 = rec["pos"]
				var rel := Vector2(fp.x - mouth.x, fp.z - mouth.z)
				var along := rel.dot(Vector2(fwd.x, fwd.z))
				if along > -2.0 and along < 40.0 \
						and (rel - Vector2(fwd.x, fwd.z) * along).length() < 6.0:
					food._bury_idx(s, idx, k)
	food._deficit.fill(0)
	var made: Array = []
	var qa_base := 1000 + int(Time.get_ticks_msec() % 1000) * 10
	print("EATTEST setup@%s mouth=%.3v fwd=%.3v anchor=%v" % [label, mouth, fwd, _eat_anchor(food)])
	for i in count:
		var at: Vector3 = Vector3(mouth.x, 0.0, mouth.z) + fwd * (0.45 + float(i))
		if not food._spawn_orb(kind, at):
			print("EATTEST %s FAIL could not place fruit %d" % [label, i])
			food.qa_freeze_respawn = false
			return false
		var info := _eat_find(food, kind, at)
		if info.is_empty():
			print("EATTEST %s FAIL could not find fruit %d" % [label, i])
			food.qa_freeze_respawn = false
			return false
		var irec: Dictionary = info["rec"]
		print("EATTEST placed@%s #%d at=%.3v rec_pos=%.3v" % [label, i, at, irec["pos"]])
		irec["qa"] = qa_base + i
		made.append(info)
	var n0: int = food.count_alive()
	var s0: int = p.score
	var t0: float = p.target_length
	var g0: int = p.gulp_count
	var claimed := {}
	var claim_ms := {}
	var eat_log: Array = []
	var eat_hook := func(snake, kind_e: int, sc: int):
		# flake diagnostics: WHICH record was just claimed (its flight
		# carries the orb's original ground position + tier) + where the
		# eater's head was at claim time
		var dbg := ""
		var best_ms := -1
		for s2 in food._slots[kind_e]:
			for idx2 in (s2["alive"] as Dictionary).keys():
				var r2: Dictionary = (s2["alive"] as Dictionary)[idx2]
				if r2.has("fly") and (r2["fly"] as Dictionary).get("snake") == snake:
					var ms := int((r2["fly"] as Dictionary).get("start_ms", 0))
					if ms > best_ms:
						best_ms = ms
						dbg = " pos=%.3v from=%.3v tier=%s" % [
							r2["pos"], (r2["fly"] as Dictionary)["from"],
							str(r2.get("tier", "-"))]
		eat_log.append("eat kind=%d score=%d t=%.2f head=%.2v%s" % [
			kind_e, sc, match_world.match_time, snake.head_pos, dbg])
	p.ate.connect(eat_hook)
	# WINDOW-OPEN STATE: any flight already airborne (its swallow will land
	# INSIDE this case's gulp window — a claim from a previous case) and any
	# orb still standing inside the strip the clear was supposed to empty.
	var airborne: Array = []
	var strip: Array = []
	for kd in food._slots.size():
		for s2 in food._slots[kd]:
			for idx2 in (s2["alive"] as Dictionary).keys():
				var r2: Dictionary = (s2["alive"] as Dictionary)[idx2]
				if r2.has("fly"):
					airborne.append("k%d t=%s snake=%s" % [kd, str(r2.get("tier", "-")),
						str((r2["fly"] as Dictionary).get("snake", null))])
					continue
				var fp: Vector3 = r2["pos"]
				var rel2 := Vector2(fp.x - mouth.x, fp.z - mouth.z)
				var along2 := rel2.dot(Vector2(fwd.x, fwd.z))
				var lat2 := (rel2 - Vector2(fwd.x, fwd.z) * along2).length()
				if along2 > -2.5 and along2 < 40.5 and lat2 < 6.5:
					strip.append("k%d t%s a=%.1f l=%.1f" % [kd, str(r2.get("tier", "-")), along2, lat2])
	print("EATTEST strip@%s in_strip=%d airborne=%d [%s][%s]" % [
		label, strip.size(), airborne.size(), " | ".join(airborne), " | ".join(strip)])
	for f in 300:
		await get_tree().physics_frame
		for i in made.size():
			if claimed.has(i):
				continue
			var rec: Dictionary = made[i]["rec"]
			if rec.has("fly"):
				claimed[i] = true
				claim_ms[i] = Time.get_ticks_msec()
		if claimed.size() == made.size():
			break
	var ds: int = p.score - s0
	var dt: float = p.target_length - t0
	var want_score := 0
	var want_growth := 0.0
	if kind < 3:
		# tier-aware: each spawned record carries its own S/M/L growth+score
		for m in made:
			var erec: Dictionary = m["rec"]
			want_score += int(erec.get("score", FoodSpawner.KIND_SCORE[kind]))
			want_growth += float(erec.get("growth", FoodSpawner.KIND_GROWTH[kind]))
	var claimed_ok: bool = claimed.size() == made.size()
	var score_ok: bool = ds == want_score
	var growth_ok: bool = absf(dt - want_growth) < 0.001
	var power_ok := true
	if kind == 3:
		power_ok = p.ability != "" and p.ability_left > 0.0
	var buried := {}
	var burial_ms := {}
	for f in 300:
		await get_tree().physics_frame
		for i in made.size():
			if buried.has(i):
				continue
			var qid: int = int((made[i]["rec"] as Dictionary).get("qa", -1))
			if not _eat_in_pool(food, qid):
				buried[i] = true
				burial_ms[i] = Time.get_ticks_msec()
		if buried.size() == made.size():
			break
	var gulp_ok: bool = p.gulp_count - g0 == count
	var flight_ok := true
	var transform_ok := true
	for i in made.size():
		if not buried.has(i) or not claim_ms.has(i):
			flight_ok = false
			continue
		var fly: Dictionary = (made[i]["rec"] as Dictionary).get("fly", {})
		var start_ms: int = int(fly.get("start_ms", claim_ms[i]))
		var elapsed: int = int(burial_ms[i]) - start_ms
		if elapsed < 80:
			flight_ok = false
		var slot: Dictionary = made[i]["slot"]
		var idx: int = int(made[i]["idx"])
		var mm: MultiMesh = slot["mm"]
		var ty: float = mm.get_instance_transform(idx).origin.y
		# In headless mode the dummy renderer discards MultiMesh instance
		# data (probe: set+read of any idx returns identity), so the burial
		# READ is unusable — skip only that visual probe; the burial itself
		# is separately proven by the record leaving the live pool. On a
		# windowed build the check stays fully active.
		if DisplayServer.get_name() != "headless" and ty > -10.0:
			transform_ok = false
	# After the claims the lane is clear and respawn is frozen, so any extra
	# $10 would be exactly the double-count bug this check exists to catch.
	await _frames(20)
	var no_double: bool = p.score - s0 == ds \
		and absf((p.target_length - t0) - dt) < 0.001
	# Snapshot BEFORE the respawn window opens: with the freeze lifted the
	# spawner legitimately refills the court anywhere, and the live player
	# may eat a refill orb — those eats are environment, not the case under
	# test (the score/double checks above are the double-count guard).
	var gulp_case: int = p.gulp_count - g0
	var respawn_ok := true
	var court_bad := 0
	if check_respawn:
		food.qa_freeze_respawn = false
		var gen0: int = food._gen
		var seen := false
		for f in 240:
			await get_tree().physics_frame
			if food._gen >= gen0 + made.size() or food.count_alive() >= n0:
				seen = true
				break
		respawn_ok = seen
		court_bad = _eat_validate_court(food)
		food.qa_freeze_respawn = true
	else:
		respawn_ok = food.count_alive() == n0 - made.size()
	var ok: bool = claimed_ok and score_ok and growth_ok \
		and power_ok and gulp_ok and flight_ok and transform_ok and no_double \
		and respawn_ok and court_bad == 0
	if p.ate.is_connected(eat_hook):
		p.ate.disconnect(eat_hook)
	for e in eat_log:
		print("EATTEST log %s %s" % [label, e])
	print("EATTEST %s len=%.0f kind=%d n=%d ds=%d/%d dt=%.2f/%.2f gulp=%d/%d claim=%s fly=%s xform=%s double=%s respawn=%s court=%d %s" % [
		label, length, kind, count, ds, want_score, dt, want_growth,
		gulp_case, count, str(claimed_ok), str(flight_ok), str(transform_ok),
		str(no_double), str(respawn_ok), court_bad, "PASS" if ok else "FAIL"])
	return ok

func _eat_test_run() -> void:
	print("EATTEST start")
	var mode0 := _gfx_mode
	_start_play()
	match_world.no_death = true
	if _gfx_mode != 1:
		hud.mode_changed.emit(1)   # the "3D" cases must really run in 3D
		await _frames(6)
	var p = match_world.player
	var food = match_world.food
	p.autopilot = false
	p.touch_sim = false
	p.keyboard_only = true
	p.no_idle_drift = true
	await _frames(10)
	var pass_all := true
	# growth-driven speed: smooth, monotonic, capped at 46 m / 6.2 m/s
	var last := -1.0
	var speed_ok := true
	for L in [8.0, 12.0, 20.0, 30.0, 40.0, 46.0, 50.0, 64.0, 76.0]:
		p.spawn(Vector3.ZERO, Vector3(0, 0, 1), L)
		var v: float = p.base_speed()
		print("EATTEST speed L=%.0f v=%.3f" % [L, v])
		if v < last - 0.0001 or v > Snake.SPEED_MAX + 0.0001:
			speed_ok = false
		if L >= 46.0 and absf(v - Snake.SPEED_MAX) > 0.002:
			speed_ok = false
		last = v
	print("EATTEST speed-curve %s" % ("PASS" if speed_ok else "FAIL"))
	# tail integrity in both the live 3D/2D worlds and at the 90 m boss length
	pass_all = pass_all and speed_ok
	pass_all = pass_all and _eat_long_probe(90.0, 90.0)
	# basic / rare / golden / power orb, normal length
	var r1: bool = await _eat_phase(p, food, 12.0, 0, 1, "basic-3d", true)
	var r2: bool = await _eat_phase(p, food, 12.0, 1, 1, "rare-3d", false)
	var r3: bool = await _eat_phase(p, food, 20.0, 2, 1, "golden-3d", false)
	var r4: bool = await _eat_phase(p, food, 20.0, 3, 1, "power-3d", false)
	# large/fast body: three basic fruit in one pass, exact 30 / +1.5
	var r5: bool = await _eat_phase(p, food, 50.0, 0, 3, "multi-fast", false)
	pass_all = pass_all and r1 and r2 and r3 and r4 and r5
	# live 76 m tail, 3D
	p.spawn(_eat_anchor(food), Vector3(0, 0, 1), 76.0)
	await _frames(2)
	var o := (Snake.RING_COUNT - 1) * 4
	var head := Vector3(p._spine[0], p._spine[1], p._spine[2])
	var tail := Vector3(p._spine[o], p._spine[o + 1], p._spine[o + 2])
	var live_dist := Vector2(tail.x - head.x, tail.z - head.z).length()
	var live_rad := float(p._spine[o + 3])
	var live_ok: bool = live_dist > 76.0 * 0.9 and live_rad > 0.02
	print("EATTEST live-tail-3d len=%.1f tail=%.2f radius=%.3f %s" % [
		p.length, live_dist, live_rad, "PASS" if live_ok else "FAIL"])
	pass_all = pass_all and live_ok
	# actual 2D switch: existing fruit must still be valid + one more eat
	hud.mode_changed.emit(0)
	await _frames(10)
	var court_before := _eat_validate_court(food)
	print("EATTEST 2d-switch court-invalid=%d %s" % [
		court_before, "PASS" if court_before == 0 else "FAIL"])
	pass_all = pass_all and court_before == 0
	var r6: bool = await _eat_phase(p, food, 20.0, 0, 1, "basic-2d", false)
	pass_all = pass_all and r6
	p.spawn(_eat_anchor(food), Vector3(0, 0, 1), 76.0)
	await _frames(2)
	var head2 := Vector3(p._spine[0], p._spine[1], p._spine[2])
	var tail2 := Vector3(p._spine[o], p._spine[o + 1], p._spine[o + 2])
	var live2 := Vector2(tail2.x - head2.x, tail2.z - head2.z).length()
	var live2_ok: bool = live2 > 76.0 * 0.9 and float(p._spine[o + 3]) > 0.02
	print("EATTEST live-tail-2d len=%.1f tail=%.2f radius=%.3f %s" % [
		p.length, live2, float(p._spine[o + 3]), "PASS" if live2_ok else "FAIL"])
	pass_all = pass_all and live2_ok
	# final fresh court: every natural spawn valid + reachable
	food.qa_freeze_respawn = false
	food.reset()
	await _frames(60)
	var court_final := _eat_validate_court(food)
	var n_final: int = food.count_alive()
	print("EATTEST final-court invalid=%d count=%d %s" % [
		court_final, n_final, "PASS" if court_final == 0 and n_final >= 40 else "FAIL"])
	pass_all = pass_all and court_final == 0 and n_final >= 40
	hud.mode_changed.emit(mode0)
	await get_tree().process_frame
	print("EATTEST done — %s" % ("PASS" if pass_all else "FAIL"))
	_quit_nicely()

# ---------------------------------------------------------------- power QA

func _powertest_run() -> void:
	# Power-orb QA: magnet vacuums fruit (score rate), timed expiry works,
	# shield toggles cleanly. Ability bar visibility checked via screenshot.
	# QA isolates the POWER mechanics — snake survival is not under test here.
	# Timed in PHYSICS FRAMES, not wall clock: the dev window runs off-screen
	# and can render slowly, so timer-based windows measured a fraction of the
	# intended game time (which made this test flaky, not the magnet).
	match_world.no_death = true
	var p: PlayerSnake = match_world.player
	if p == null:
		print("POWERTEST FAIL no player")
		_quit_nicely()
		return
	await _frames(60)                       # 1 s of settle
	p.apply_ability("magnet", 6.0)          # 6 s = 360 frames, outlives both slices
	print("POWERTEST magnet-on %s" % ("PASS" if p.ability_active("magnet") else "FAIL"))
	var s0: int = p.score
	await _frames(180)                      # 3 s baseline slice
	var base_gain: int = p.score - s0
	await _snap("shot_power.png")
	await _frames(180)                      # next 3 s, magnet still on
	var gained: int = p.score - s0
	var rate_ok: bool = base_gain == 0 or float(gained - base_gain) > float(base_gain) * 0.10
	print("POWERTEST magnet-gain=%d (baseline %d) %s" % [gained, base_gain,
		"PASS" if gained >= base_gain and rate_ok else "FAIL"])
	# expiry: watch the timer actually run out (eating another orb mid-wait
	# re-arms the ability, so a single "is it off now?" check would race it)
	var mag_expired := await _wait_expired(p, "magnet", 420)
	print("POWERTEST magnet-off %s" % ("PASS" if mag_expired else "FAIL"))
	p.apply_ability("shield")
	print("POWERTEST shield-on %s" % ("PASS" if p.ability_active("shield") else "FAIL"))
	var sh_expired := await _wait_expired(p, "shield", 360)
	print("POWERTEST shield-off %s" % ("PASS" if sh_expired else "FAIL"))
	print("POWERTEST alive %s" % ("PASS" if p.alive else "FAIL"))
	_quit_nicely()

## Waits (in physics frames) until `id` is no longer active; true if it expired.
func _wait_expired(p: PlayerSnake, id: String, max_frames: int) -> bool:
	for i in max_frames:
		await get_tree().physics_frame
		if not p.ability_active(id):
			return true
	return false

func _snap(fname: String) -> void:
	# Headless has no viewport texture; the rig also pollutes timing QA.
	if DisplayServer.get_name() == "headless":
		print("DEVSHOT headless-skip ", fname)
		return
	print("SNAP-START ", fname)
	# Prefer the post-draw signal, but never hinge quitting on it.
	var done := false
	RenderingServer.frame_post_draw.connect(func(): done = true, CONNECT_ONE_SHOT)
	for i in 12:
		await get_tree().process_frame
		if done:
			break
	print("DEV: snap waited frames")
	var img := get_viewport().get_texture().get_image()
	print("DEV: snap image ", img.get_width(), "x", img.get_height())
	img.save_png("user://" + fname)
	print("DEVSHOT ", fname)

# ---------------------------------------------------------------- state flow

# ------------------------------------------------------------ scene switching

## Arena preset's own night/visibility pass. Deliberately separate from the
## main-menu Light/Dark theme so switching either axis never changes the other.
func _arena_is_night(key: String = "") -> bool:
	var k := key if key != "" else _arena_key
	return bool(ArenaPresets.get_preset(k).get("night", false))

## Build the gameplay world on demand (menu boot never pays for the arena).
func _create_match_world() -> void:
	match_world = MatchWorld.new()
	match_world.hud = hud
	match_world.arena_key = _arena_key
	match_world.gfx_mode = _gfx_mode
	# Arena night/visibility pass is an ARENA property, not a UI theme. The
	# Light/Dark menu selection must never repaint the arena.
	match_world.dark = _arena_is_night()
	add_child(match_world)
	hud.minimap().world = match_world   # arena radar reads the live world
	match_world.match_event.connect(hud.push_feed)
	match_world.player_died.connect(_on_player_died)

## Home screen active: menu world awake, gameplay world fully dormant.
func _show_menu_scene() -> void:
	if hud.menu_back_active():
		# The home-page storm background is opaque and live: the 3D demo
		# world stays fully dormant (invisible AND zero CPU) behind it.
		menu_world.process_mode = Node.PROCESS_MODE_DISABLED
		menu_world.visible = false
	else:
		menu_world.visible = true
		menu_world.process_mode = Node.PROCESS_MODE_INHERIT
		menu_world.ensure_life()
		menu_world.set_dark(_theme_id == UiTheme.DARK)
	if match_world != null:
		match_world.visible = false
		match_world.process_mode = Node.PROCESS_MODE_DISABLED

## Gameplay view: menu scene fully shut down (zero CPU), match world live.
func _show_game_scene() -> void:
	menu_world.process_mode = Node.PROCESS_MODE_DISABLED
	menu_world.visible = false
	if match_world == null:
		_create_match_world()
	elif match_world.arena_key != _arena_key:
		# arena changed while the player was in the menu: rebuild now
		_recreate_world()
	elif match_world.dark != _arena_is_night() \
			or match_world.gfx_mode != _gfx_mode:
		# The menu is mode/theme-agnostic, so a VIEW change made there must be
		# applied to a reused world. The arena's own night pass is independent
		# of the main-menu Light/Dark theme.
		match_world.restyle(_arena_is_night(), _gfx_mode == 0)
	match_world.visible = true
	match_world.process_mode = Node.PROCESS_MODE_INHERIT

func _start_play() -> void:
	state = State.PLAYING
	_show_game_scene()
	hud.show_menu(false)
	hud.show_pause(false)
	hud.show_gameover_hidden()
	hud.set_paused(false)
	if _joy_dev and hud.joystick() != null:
		hud.joystick().force_joystick_dev = true
	hud.set_gameplay_visible(true)
	get_tree().paused = false
	Engine.time_scale = 1.0
	# dev flags must be applied BEFORE the match spawns anything
	match_world.no_death = _no_death_dev or _closeup
	match_world.solo_dev = _solo_dev
	match_world.skip_hud_dev = _skip_hud_dev
	match_world.verbose = _autoplay
	match_world.start_match()
	if _autoplay and match_world.player != null:
		match_world.player.autopilot = true
	if _touch_test and match_world.player != null:
		# synthetic-touch QA: disable the dev brain, enable the touch path
		match_world.player.autopilot = false
		match_world.player.touch_sim = true
		match_world.player._is_mobile = true
	if _spawntest and match_world.player != null:
		# unsteered straight-line baseline (what an idle mobile player does)
		match_world.player.autopilot = false
	if match_world.player != null:
		var skin_idx := _skin_dev if _skin_dev >= 0 else int(SaveMgr.get_value("skin", 0))
		var sk := SkinCatalog.get_skin(skin_idx)
		match_world.player.apply_skin(sk["dorsal"], sk["accent"], sk["belly"], sk["seed"], int(sk["pattern"]))
		print("SKIN apply=", sk["name"], " idx=", skin_idx)
	AudioMgr.play("spawn")
	hud.announce("SURVIVE", "COLLECT ORBS — GROW — ELIMINATE RIVALS")
	# AFTER the spawn: the stick flag belongs to THIS match's player snake
	_sync_joystick_flags()
	if _closeup and match_world.player != null:
		match_world.player.hold_heading = match_world.player.heading
		match_world.no_death = true

## Wire the HUD virtual joystick to the player snake (mobile 2D steering).
func _bind_joystick() -> void:
	var joy: TouchJoystick = hud.joystick()
	if joy == null:
		return
	joy.vector_changed.connect(func(v: Vector2):
		if match_world == null:
			return
		var p := match_world.player
		if p is PlayerSnake:
			p.joy_vec = v
			p.joy_active = joy.active or v != Vector2.ZERO)

## The stick owns steering in mobile 2D, so the snake must NOT auto-arc while
## idle underneath it (that idle circle read as "it only moves in circles").
func _sync_joystick_flags() -> void:
	if match_world == null:
		return   # no live match yet (menu): nothing to sync
	var p := match_world.player
	if p is PlayerSnake:
		var joy: TouchJoystick = hud.joystick()
		p.no_idle_drift = joy != null and joy.enabled

func _restart() -> void:
	_start_play()

func _on_arena_shift(dir: int) -> void:
	# menu ARENA selector: just remember the choice — the playable arena is
	# built fresh at Play time, and the menu backdrop is never the arena
	if state != State.MENU:
		return
	var nk := ArenaPresets.next_key(_arena_key) if dir >= 0 else ArenaPresets.prev_key(_arena_key)
	_arena_key = nk
	SaveMgr.set_value("arena", nk)
	SaveMgr.save()
	hud.set_arena(nk)

func _on_theme_changed(id: int) -> void:
	# Main-menu/HUD theme only. The arena keeps its own preset palette; this
	# is what makes LIGHT/DARK independent of ARENA selection.
	_theme_id = id
	SaveMgr.set_value("theme", id)
	if state == State.MENU:
		menu_world.set_dark(id == UiTheme.DARK)

func _on_mode_changed(id: int) -> void:
	# Graphics mode: 0 = 2D top-down, 1 = 3D / 2.5D. Persisted by the HUD.
	_gfx_mode = id
	SaveMgr.set_value("gfx_mode", id)
	_topdown_dirty = true
	hud.set_joystick_mode(id == 0)
	_sync_joystick_flags()
	if state == State.MENU:
		return   # menu is mode-agnostic; the match world is built at Play
	if match_world != null:
		match_world.gfx_mode = id
		match_world.restyle(match_world.dark, id == 0)

func _rebuild_world() -> void:
	if is_instance_valid(match_world):
		match_world.queue_free()
	match_world = null
	_show_game_scene()   # recreates with the current arena/mode/theme

## Recreate the gameplay world (kept separate for clarity at the call sites).
func _recreate_world() -> void:
	if is_instance_valid(match_world):
		match_world.queue_free()
	match_world = null
	_create_match_world()

func _to_menu() -> void:
	state = State.MENU
	get_tree().paused = false
	Engine.time_scale = 1.0
	hud.show_menu(true)
	hud.show_pause(false)
	hud.show_gameover_hidden()
	hud.set_gameplay_visible(false)
	_show_menu_scene()
	# restore the boot camera pose so the menu drift starts sane
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE

func _on_player_died() -> void:
	if _autoplay:
		print("DEV: player died — ", match_world.last_kill_text)
	state = State.OVER
	hud.set_paused(false)
	hud.set_gameplay_visible(false)
	# capture stats immediately (player node is freed right after this signal)
	var stats := {
		"score": player_score(),
		"length": player_length(),
		"time": match_world.match_time,
		"kills": player_kills(),
		"rank": player_rank(),
		"total": maxi(1, match_world.get_alive_snakes().size() + 1),
	}
	# slow-motion beat, then results
	Engine.time_scale = 0.30
	await get_tree().create_timer(0.75, true, false, true).timeout
	Engine.time_scale = 1.0
	var is_best: bool = SaveMgr.record_run(stats["score"], stats["length"], stats["kills"])
	SaveMgr.save()   # death is the only reliable save moment on mobile
	stats["is_best"] = is_best
	stats["cause"] = match_world.player_cause if match_world.player_cause != "" else "unknown"
	stats["best"] = SaveMgr.get_value("best_score", 0)
	if is_best:
		stats["title"] = "NEW PERSONAL BEST"
	hud.show_gameover(stats)

func player_score() -> int:
	return match_world.player.score
func player_length() -> float:
	return match_world.player.length
func player_kills() -> int:
	return match_world.player.kills
func player_rank() -> int:
	if not player_alive():
		# already eliminated — place by score against the survivors
		var r := 1
		for s in match_world.get_alive_snakes():
			if s.score > player_score():
				r += 1
		return r
	return match_world.rank_of_live(match_world.player)
func player_alive() -> bool:
	return match_world.player != null and is_instance_valid(match_world.player) and match_world.player.alive

# ---------------------------------------------------------------- pause

func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	hud.show_pause(true)
	hud.set_paused(true)

func _resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	get_tree().paused = false
	hud.show_pause(false)
	hud.set_paused(false)

func _toggle_pause() -> void:
	# HUD play/pause button (spec §3)
	match state:
		State.PLAYING:
			_pause()
		State.PAUSED:
			_resume()
		_:
			pass

func _input(event: InputEvent) -> void:
	if _touchlog and (event is InputEventScreenTouch or event is InputEventScreenDrag
			or event is InputEventMouseButton or event is InputEventMouseMotion):
		print("TOUCHLOG evt ", event.as_text(), " | vp_visible=", get_viewport().get_visible_rect(),
			" | vp_xform=", get_viewport().get_final_transform())
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			match state:
				State.PLAYING:
					_pause()
				State.PAUSED:
					_resume()
				_:
					pass
	elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_BACK):
		# Android BACK: sub-page (skins/settings) = back to main menu, pause in a
		# match, resume in pause menu or game over = menu, on main menu = quit.
		if state == State.MENU and hud.current_page() != "main":
			get_viewport().set_input_as_handled()
			hud._menu_page("main")
			return
		match state:
			State.PLAYING:
				get_viewport().set_input_as_handled()
				_pause()
			State.PAUSED:
				get_viewport().set_input_as_handled()
				# BACK inside settings-from-pause returns to the pause overlay
				if hud.current_page() != "main":
					hud._swap_menu(true)
				else:
					_resume()
			State.OVER:
				_to_menu()
			_:
				pass

# ---------------------------------------------------------------- camera

var prof_game_us := 0
var prof_mw_us := 0

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	match state:
		State.MENU:
			# The dedicated menu scene carries the visuals while the match
			# world (if any) sleeps dormant behind it.
			if menu_world != null:
				menu_world.update_cameras(cam, delta)
		_:
			if match_world != null and match_world.player != null and is_instance_valid(match_world.player):
				if _closeup:
					var p := match_world.player
					var fwd := Vector3(sin(p.heading), 0.0, cos(p.heading))
					cam.global_position = p.head_pos - fwd * 4.0 + Vector3.UP * 6.5
					cam.look_at(p.head_pos + fwd * 2.0 + Vector3.UP * 0.2, Vector3.UP)
					_diag_t += delta
					if _diag_t > 3.0:
						_diag_t = 0.0
						print("DIAG ", p.debug_state())
				else:
					_topdown_camera(delta)
			elif not _quit_at > 0.0 and state == State.OVER:
				if _gfx_mode == 0:
					# 2D mode stays FLAT for the results view too — never drop
					# back to a perspective orbit (that read as "3D in 2D mode")
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = lerpf(cam.size if cam.size > 0.1 else 34.0, 34.0, 1.0 - exp(-2.0 * delta))
					var b := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
					cam.global_transform = Transform3D(b, Vector3(_player_last_head.x, 80.0, _player_last_head.z))
				else:
					# gentle orbit during results
					_cam_angle += delta * 0.05
					var focus := _player_last_head
					var pos := focus + Vector3(cos(_cam_angle) * 16.0, 9.0, sin(_cam_angle) * 16.0)
					_cam_pos = _cam_pos.lerp(pos, 1.0 - exp(-1.4 * delta))
					_cam_look = _cam_look.lerp(focus, 1.0 - exp(-1.4 * delta))
					cam.global_position = _cam_pos
					cam.look_at(_cam_look, Vector3.UP)
	if match_world != null:
		match_world.prof_game_us += Time.get_ticks_usec() - t0

func _topdown_camera(delta: float) -> void:
	# Graph mode dispatcher (spec §1): 2D = genuine flat top-down board
	# (orthographic, no perspective), 3D = third-person chase (PUBG-style).
	if _gfx_mode == 0:
		_camera_2d_topdown(delta)
	else:
		_camera_3d_tps(delta)

func _camera_2d_topdown(delta: float) -> void:
	# TRUE 2D: ORTHOGRAPHIC camera straight above the player, world north
	# fixed up-screen, smooth follow. Orthographic = zero perspective
	# convergence, so the arena reads as a flat 2D board while snakes and
	# fruit stay lit 3D models. cam.size is the visible world height in
	# meters and eases with boost / growth for reaction room (spec §2).
	var p := match_world.player
	if p == null or not is_instance_valid(p):
		return
	_player_last_head = p.head_pos
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var vp := get_viewport()
	var aspect := 1.6
	if vp != null and vp.get_visible_rect().size.y > 0.0:
		aspect = vp.get_visible_rect().size.x / vp.get_visible_rect().size.y
	# Gameplay camera distance (spec §9): the board was framed 30 m tall —
	# snakes read as confetti at that scale. Per-platform base: phones sit
	# closer (≈55 px/m on a 1080p-landscape panel — the physical screen is
	# smaller, so fruit/snake detail needs the extra scale); desktop keeps a
	# slightly wider tactical frame. Portrait gets a multiplier so the narrow
	# screen still fills without starving horizontal visibility.
	var mobile := OS.get_name() == "Android" or OS.get_name() == "iOS"
	var span := (19.5 if mobile else 20.5) * clampf(1.30 / maxf(aspect, 0.62), 1.0, 1.22)
	# Boost is the EXCESS over this snake's growth-driven cruise speed, not over
	# the base constant: otherwise a long (already faster) snake fakes a boost
	# kick on every frame. Length itself only widens the frame a little.
	var cruise: float = maxf(p.base_speed(), 0.1)
	var boost_k := clampf((p.speed_cur - cruise) / (cruise * maxf(Snake.BOOST_MULT - 1.0, 0.1)), 0.0, 1.0)
	var length_k := clampf((p.length - 8.0) / 56.0, 0.0, 1.0)
	span *= 1.0 + 0.08 * boost_k + 0.12 * length_k
	cam.size = lerpf(cam.size if cam.size > 0.1 else span, span, 1.0 - exp(-2.5 * delta))
	# follow the head with a touch of look-ahead. The camera may wander only
	# ~72% of a half-screen past the arena edge, so the board keeps filling the
	# frame (no slab of dark apron) while the head stays well inside the view.
	var fwd := Vector3(sin(p.heading), 0.0, cos(p.heading))
	var want := p.head_pos + fwd * 3.0
	var edge := match_world.arena_radius + 1.0
	var mx: float = maxf(0.0, edge - span * 0.5 * aspect * 0.72)
	var mz: float = maxf(0.0, edge - span * 0.5 * 0.72)
	want.x = clampf(want.x, -mx, mx)
	want.z = clampf(want.z, -mz, mz)
	_cam_pos = _cam_pos.lerp(Vector3(want.x, 80.0, want.z), 1.0 - exp(-6.0 * delta))
	_cam_look = _cam_look.lerp(want, 1.0 - exp(-6.0 * delta))
	# straight-down orientation (fixed world basis; -Z is up-screen)
	var b := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	cam.global_transform = Transform3D(b, _cam_pos)

func _camera_3d_tps(delta: float) -> void:
	# Third-person 3D view (spec §3): perspective camera above and behind the
	# snake with perspective convergence, a boost FOV kick and smooth follow.
	#
	# The view direction is a FIXED compass heading, deliberately NOT locked to
	# the snake's heading. A heading-locked chase camera feeds the snake's own
	# turn straight back into the steering frame, so the "down-screen" target
	# kept rotating with the snake: holding Down then turned the snake at max
	# rate forever (it orbited instead of travelling down the screen) and the
	# direction keys felt random. With a fixed orientation every key always
	# means the same screen direction in both 2D and 3D mode.
	var p := match_world.player
	if p == null or not is_instance_valid(p):
		return
	var head := p.head_pos
	_player_last_head = head
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var cruise: float = maxf(p.base_speed(), 0.1)
	var boost_k := clampf((p.speed_cur - cruise) / (cruise * (Snake.BOOST_MULT - 1.0)), 0.0, 1.0)
	var len_k := clampf((p.length - 8.0) / 56.0, 0.0, 1.0)
	# pull back with growth so the trailing body stays in frame longer; a 76 m
	# serpent is still a close chase, just with enough context to read its tail.
	var dist := 12.6 + len_k * 4.2
	# low cinematic chase: ~22° pitch behind the serpent — the court stretches
	# into a visible horizon with a sky band, objects occlude each other and
	# the coiled body shows real volume. The compass yaw stays FIXED (see the
	# orientation note above), so key/touch mapping is identical to 2D.
	var back := Vector3(2.2, dist * 0.52, dist * 0.96)
	# a short lead along the travel direction keeps the frame alive (it moves
	# the look point, not the orientation, so key mapping stays exact)
	var lead := Vector3(sin(p.heading), 0.0, cos(p.heading)) * minf(p.speed_cur * 0.20, 2.4)
	var focus := head + Vector3.UP * 0.9
	_cam_pos = _cam_pos.lerp(focus + back, 1.0 - exp(-6.0 * delta))
	var look := focus + Vector3(0.0, 0.55, -3.2) + lead
	_cam_look = _cam_look.lerp(look, 1.0 - exp(-6.0 * delta))
	cam.global_position = _cam_pos
	cam.look_at(_cam_look, Vector3.UP)
	cam.fov = lerpf(cam.fov, 62.0 + boost_k * 8.0, 1.0 - exp(-6.0 * delta))

func _topdown_fit() -> void:
	# 2D board height for the current aspect — the follow camera needs no
	# full-arena fit (3D TPS frames the snake), so this just caches a height
	# hint used by dev tooling.
	_topdown_dist = 48.0
	_topdown_dirty = false

# ---------------------------------------------------------------- app defaults

func _quit_nicely() -> void:
	SaveMgr.save()
	get_tree().quit()

## On-device diagnostics: dump the viewport geometry and EVERY HUD button's
## actual global rect, so a "button visually here but tap lands elsewhere"
## layout/rotation mismatch becomes directly visible in logcat.
func _touchlog_dump() -> void:
	await get_tree().create_timer(2.0).timeout
	var vp := get_viewport()
	print("TOUCHLOG boot visible_rect=", vp.get_visible_rect().size,
		" final_xform=", vp.get_final_transform(),
		" attach_xform=", vp.get_screen_transform(),
		" ds_size=", DisplayServer.window_get_size(),
		" screen_size=", DisplayServer.screen_get_size(),
		" window_pos=", DisplayServer.window_get_position())
	for b in hud._tb:
		if is_instance_valid(b):
			print("TOUCHLOG btn '%s' rect=%s vis=%s" % [b.text, b.get_global_rect(), b.is_visible_in_tree()])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_nicely()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		# backgrounded (phone app switch / screen off): never let the match
		# keep running unattended — auto-pause and show the overlay (spec §3).
		# Dev harness windows run parked offscreen and randomly receive
		# focus-out events; freezing the sim mid-QA produced false failures.
		if state == State.PLAYING and not _autoplay:
			_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android BACK (quit_on_go_back=false): pause in a match, otherwise
		# hand the usual resume / menu paths (never hard-quit mid-run)
		match state:
			State.PLAYING:
				_pause()
			State.PAUSED:
				_resume()
			State.OVER:
				_to_menu()
			State.MENU:
				# Confirm before closing: an accidental BACK no longer kills the
				# app instantly; the same dialog the QUIT button opens handles it.
				hud.show_quit_confirm(true)
			_:
				pass

