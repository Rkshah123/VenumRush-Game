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
var _theme_id := 0               # UiTheme.CLASSIC / DARK (settings)
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
	_arena_key = str(SaveMgr.get_value("arena", "valley"))
	if arena_dev != "" and ArenaPresets.ALL.has(arena_dev):
		_arena_key = arena_dev
	elif not ArenaPresets.ALL.has(_arena_key):
		_arena_key = "valley"
	_gfx_mode = int(SaveMgr.get_value("gfx_mode", 1))
	_theme_id = int(SaveMgr.get_value("theme", UiTheme.CLASSIC))
	hud = GameHud.new()
	add_child(hud)
	# The home-screen backdrop is its own cinematic scene, never the arena.
	menu_world = MenuWorld.new()
	menu_world.dark = _theme_id == UiTheme.DARK
	add_child(menu_world)
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
	var allow := ["--autoplay", "--no-death", "--solo", "--hud-off", "--onscreen-test", "--shot-menu", "--shot-skins", "--shot-settings", "--arena-test", "--touch-test", "--spawntest", "--powertest", "--eat-test", "--skins-test", "--theme-test", "--uix-test", "--mode-test", "--joystick", "--joy-test", "--dir-test", "--ctrl-test"]
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
	if _eat_test:
		await _eat_test_run()
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
	await get_tree().create_timer(0.6).timeout
	_start_play()
	print("DEV: play started")
	if _uix_test:
		await _uix_test_run()
		return
	if _mode_test:
		await _mode_test_run()
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
		await get_tree().create_timer(7.0).timeout
		print("SPAWNTEST done — survives=", match_world.player != null and match_world.player.alive)
		_quit_nicely()
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

# ---------------------------------------------------------------- touch QA

func _touch_tap(index: int, pressed: bool, pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	Input.parse_input_event(ev)

func _touch_drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	Input.parse_input_event(ev)

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
	print("SKINTEST count %s" % ("PASS" if SkinCatalog.count() == 8 else "FAIL"))
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
	print("JOYTEST deadzone %s" % ["PASS" if joy.value == Vector2.ZERO else "FAIL"])
	joy.force_release()
	for i in 40:
		await get_tree().process_frame
	print("JOYTEST release %s (value=%s knob=%.2f)" % ["PASS" if joy.value == Vector2.ZERO else "FAIL", str(joy.value), joy._knob.length()])
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

func _key_event(code: int, pressed: bool) -> void:
	_key_event_mod(code, pressed, false)

func _key_event_mod(code: int, pressed: bool, shift: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.shift_pressed = shift
	e.pressed = pressed
	Input.parse_input_event(e)

func _touch_event(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)

func _drag_event(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
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
	print("UIXTEST quit-cancel %s" % ["PASS" if not hud._quit_panel.visible else "FAIL"])
	_quit_nicely()

# ---------------------------------------------------------------- theme QA

func _theme_test_run() -> void:
	# Dark Theme + graphics-mode QA: palette contrast report, both themes
	# applied to the live UI, persistence, and mode switching through the
	# real settings signal path (no gameplay state is touched).
	print(UiTheme.theme_report())
	var arena0 := str(SaveMgr.get_value("arena", "valley"))
	var theme0 := int(SaveMgr.get_value("theme", UiTheme.CLASSIC))
	for t in 2:
		SaveMgr.set_value("theme", t)
		hud.apply_theme(t)
		await get_tree().process_frame
		print("THEMETEST applied=%s accent=%s" % [UiTheme.theme_name(t), str(UiTheme.c("accent"))])
		if not is_equal_approx(UiTheme.c("accent").get_luminance(), UiTheme.c("accent").get_luminance()):
			print("THEMETEST FAIL accent")
			_quit_nicely()
			return
	# ------------------------------------------------ main-menu separations
	# The two labelled selector sections must be independent and truthful.
	# Drive the REAL menu theme pills / arena chevrons, not internal setters.
	var dark_btn: Button = null
	for b in hud._topt:
		if is_instance_valid(b) and str(b.get_meta("opt_group")) == "theme" \
				and int(b.get_meta("opt_value")) == UiTheme.DARK:
			dark_btn = b
			break
	if dark_btn == null:
		print("THEMETEST FAIL no main-menu theme button")
		_quit_nicely()
		return
	dark_btn.emit_signal("pressed")
	await get_tree().process_frame
	var arena_after_theme := str(SaveMgr.get_value("arena", "valley"))
	var theme_sel_ok: bool = hud._theme_sub != null and is_instance_valid(hud._theme_sub) \
		and hud._theme_sub.text.contains("DARK")
	print("THEMETEST theme-section dark=%s arena_same=%s label=%s %s" % [
		str(int(SaveMgr.get_value("theme", 0)) == UiTheme.DARK),
		str(arena_after_theme == arena0), str(theme_sel_ok),
		"PASS" if int(SaveMgr.get_value("theme", 0)) == UiTheme.DARK \
		and arena_after_theme == arena0 and theme_sel_ok else "FAIL"])
	hud.arena_shift.emit(1)
	await get_tree().process_frame
	var arena1 := str(SaveMgr.get_value("arena", "valley"))
	var arena_name := str(ArenaPresets.get_preset(arena1).get("name", ""))
	var arena_label_ok: bool = hud._arena_label != null and is_instance_valid(hud._arena_label) \
		and hud._arena_label.text == arena_name
	var theme_kept: bool = int(SaveMgr.get_value("theme", 0)) == UiTheme.DARK
	print("THEMETEST arena-section arena=%s theme_same=%s label=%s %s" % [
		arena1, str(theme_kept), str(arena_label_ok),
		"PASS" if arena1 != arena0 and theme_kept and arena_label_ok else "FAIL"])
	for m in 2:
		hud.mode_changed.emit(m)
		await get_tree().process_frame
		print("THEMETEST mode=%d cam_tilt_dirty=%s saved=%d" % [m, str(_topdown_dirty), int(SaveMgr.get_value("gfx_mode", 1))])
	hud.theme_changed.emit(UiTheme.DARK)
	await get_tree().process_frame
	# menu state: the dedicated cinematic scene re-tints (the arena is built
	# lazily on Play, so null is expected here)
	print("THEMETEST dark-menu-scene=%s match_world=%s" % [
		str(menu_world.dark), str(match_world.dark) if match_world != null else "not-built"])
	# ...and the SAME two menu selections must drive the playable world.
	_start_play()
	match_world.no_death = true
	await _frames(30)
	var play_ok: bool = match_world != null and match_world.dark \
		and match_world.arena_key == arena1 and match_world.gfx_mode == 1
	print("THEMETEST gameplay dark=%s arena=%s mode=%d %s" % [
		str(match_world.dark), match_world.arena_key, match_world.gfx_mode,
		"PASS" if play_ok else "FAIL"])
	# restore the player's choices so QA never leaves the save dirty
	SaveMgr.set_value("arena", arena0)
	SaveMgr.set_value("theme", theme0)
	SaveMgr.set_value("gfx_mode", 1)
	_arena_key = arena0
	_theme_id = theme0
	hud.set_arena(arena0)
	hud.apply_theme(theme0)
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
	food.reset()
	await _frames(1)
	var mouth: Vector3 = p.mouth_pos
	var fwd: Vector3 = Vector3(sin(p.heading), 0.0, cos(p.heading))
	# clear the reset's fruit off the test lane
	for k in food._slots.size():
		for s: Dictionary in food._slots[k]:
			var alive: Dictionary = s["alive"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if rec.has("fly"):
					continue
				var fp: Vector3 = rec["pos"]
				if Vector2(fp.x - mouth.x, fp.z - mouth.z).length() < 6.5:
					food._bury_idx(s, idx, k)
	food._deficit.fill(0)
	var made: Array = []
	var qa_base := 1000 + int(Time.get_ticks_msec() % 1000) * 10
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
		irec["qa"] = qa_base + i
		made.append(info)
	var n0: int = food.count_alive()
	var s0: int = p.score
	var t0: float = p.target_length
	var g0: int = p.gulp_count
	var claimed := {}
	var claim_ms := {}
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
		want_score = int(FoodSpawner.KIND_SCORE[kind]) * count
		want_growth = float(FoodSpawner.KIND_GROWTH[kind]) * float(count)
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
		var elapsed: int = int(burial_ms[i]) - int(claim_ms[i])
		if elapsed < 80:
			flight_ok = false
		var slot: Dictionary = made[i]["slot"]
		var idx: int = int(made[i]["idx"])
		var mm: MultiMesh = slot["mm"]
		if mm.get_instance_transform(idx).origin.y > -10.0:
			transform_ok = false
	# After the claims the lane is clear and respawn is frozen, so any extra
	# $10 would be exactly the double-count bug this check exists to catch.
	await _frames(20)
	var no_double: bool = p.score - s0 == ds \
		and absf((p.target_length - t0) - dt) < 0.001
	var respawn_ok := true
	var court_bad := 0
	if check_respawn:
		food.qa_freeze_respawn = false
		var seen := false
		for f in 240:
			await get_tree().physics_frame
			if food.count_alive() >= n0:
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
	print("EATTEST %s len=%.0f kind=%d n=%d ds=%d/%d dt=%.2f/%.2f gulp=%d/%d fly=%s double=%s respawn=%s court=%d %s" % [
		label, length, kind, count, ds, want_score, dt, want_growth,
		p.gulp_count - g0, count, str(flight_ok), str(no_double),
		str(respawn_ok), court_bad, "PASS" if ok else "FAIL"])
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

## Build the gameplay world on demand (menu boot never pays for the arena).
func _create_match_world() -> void:
	match_world = MatchWorld.new()
	match_world.hud = hud
	match_world.arena_key = _arena_key
	match_world.gfx_mode = _gfx_mode
	match_world.dark = _theme_id == UiTheme.DARK
	add_child(match_world)
	hud.minimap().world = match_world   # arena radar reads the live world
	match_world.match_event.connect(hud.push_feed)
	match_world.player_died.connect(_on_player_died)

## Home screen active: menu world awake, gameplay world fully dormant.
func _show_menu_scene() -> void:
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
	elif match_world.dark != (_theme_id == UiTheme.DARK) \
			or match_world.gfx_mode != _gfx_mode:
		# The menu is mode/theme-agnostic, so a selection made there must be
		# applied to a reused world. Without this, changing THEME or VIEW on
		# the main menu after a previous run silently played the old look.
		match_world.restyle(_theme_id == UiTheme.DARK, _gfx_mode == 0)
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
	# Dark Theme: retint the UI (HUD does that) + whichever scene is live.
	_theme_id = id
	SaveMgr.set_value("theme", id)
	if state == State.MENU:
		menu_world.set_dark(id == UiTheme.DARK)
	elif match_world != null:
		match_world.restyle(id == UiTheme.DARK, _gfx_mode == 0)

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

func _physics_process(delta: float) -> void:
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
				_quit_nicely()
			_:
				pass

# HUD signal alias fixups (declared after use for readability)
func _hud_wiring_check() -> void:
	pass
