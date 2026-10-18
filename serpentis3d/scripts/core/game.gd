extends Node3D
## Game orchestrator: menu/demo/play states, camera rig, pause flow,
## game-over flow, dev harness (autoplay screenshots).

enum State { MENU, PLAYING, PAUSED, OVER }

var hud: GameHud
var match_world: MatchWorld
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
	_arena_key = str(SaveMgr.get_value("arena", "valley"))
	if arena_dev != "" and ArenaPresets.ALL.has(arena_dev):
		_arena_key = arena_dev
	elif not ArenaPresets.ALL.has(_arena_key):
		_arena_key = "valley"
	_gfx_mode = int(SaveMgr.get_value("gfx_mode", 1))
	_theme_id = int(SaveMgr.get_value("theme", UiTheme.CLASSIC))
	hud = GameHud.new()
	add_child(hud)
	match_world = MatchWorld.new()
	match_world.hud = hud
	match_world.arena_key = _arena_key
	match_world.gfx_mode = _gfx_mode
	match_world.dark = _theme_id == UiTheme.DARK
	add_child(match_world)
	match_world.match_event.connect(hud.push_feed)
	match_world.player_died.connect(_on_player_died)
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
	var allow := ["--autoplay", "--no-death", "--solo", "--hud-off", "--onscreen-test", "--shot-menu", "--shot-skins", "--shot-settings", "--arena-test", "--touch-test", "--spawntest", "--powertest", "--skins-test", "--theme-test", "--uix-test", "--mode-test", "--joystick", "--joy-test", "--dir-test"]
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
		# exercises the same signal the ◄ ► buttons emit: cycle 3 times with
		# a shot each, verifying world rebuilds + save persistence
		for i in 3:
			hud.arena_shift.emit(1)
			await get_tree().create_timer(2.2).timeout
			await _snap("shot_arena%d.png" % (i + 1))
			print("ARENA-TEST now=", _arena_key, " saved=", SaveMgr.get_value("arena"))
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
	await get_tree().create_timer(0.5).timeout
	var h0: float = p.heading
	# 1) finger down right of center → steering rotation
	_touch_tap(0, true, Vector2(vs.x * 0.72, vs.y * 0.5))
	await get_tree().create_timer(0.85).timeout
	var t1: float = wrap.call(p.heading, h0)
	print("TOUCHTEST steer dt=%.3f %s" % [t1, "PASS" if t1 > 0.10 else "FAIL"])
	var td := p.desired_dir
	print("TOUCHTEST intent len=%.2f %s" % [td.length(), "PASS" if td.length() > 0.05 else "FAIL"])
	# 2) dead zone: second drag near center → desired_dir releases to center
	var hz: float = p.heading
	_touch_drag(0, Vector2(vs.x * 0.52, vs.y * 0.52))
	await get_tree().create_timer(0.4).timeout
	var drift: float = wrap.call(p.heading, hz)
	print("TOUCHTEST deadzone drift=%.3f %s" % [drift, "PASS" if drift < 0.06 else "FAIL"])
	# 3) second finger → boost
	_touch_tap(1, true, Vector2(vs.x * 0.22, vs.y * 0.72))
	await get_tree().create_timer(0.35).timeout
	print("TOUCHTEST boost %s" % ("PASS" if p.input_boost else "FAIL"))
	# 4) release second finger → boost off
	_touch_tap(1, false, Vector2(vs.x * 0.22, vs.y * 0.72))
	await get_tree().create_timer(0.35).timeout
	print("TOUCHTEST boost-off %s" % ("PASS" if not p.input_boost else "FAIL"))
	# 5) steer the other side → rotation continues (nonzero, opposite sign)
	_touch_drag(0, Vector2(vs.x * 0.28, vs.y * 0.5))
	await get_tree().create_timer(0.85).timeout
	var t5: float = wrapf(p.heading - h0, -PI, PI)
	print("TOUCHTEST steer-back dt=%.3f %s" % [absf(t5), "PASS" if absf(t5) > 0.10 else "FAIL"])
	# cleanup + quit
	_touch_tap(0, false, Vector2(vs.x * 0.28, vs.y * 0.5))
	await get_tree().create_timer(0.2).timeout
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
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
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
		var active_ok := str(btn.text).contains("ACTIVE")
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
	for t in 2:
		SaveMgr.set_value("theme", t)
		hud.apply_theme(t)
		await get_tree().process_frame
		print("THEMETEST applied=%s accent=%s" % [UiTheme.theme_name(t), str(UiTheme.c("accent"))])
		if not is_equal_approx(UiTheme.c("accent").get_luminance(), UiTheme.c("accent").get_luminance()):
			print("THEMETEST FAIL accent")
			_quit_nicely()
			return
	for m in 2:
		hud.mode_changed.emit(m)
		await get_tree().process_frame
		print("THEMETEST mode=%d cam_tilt_dirty=%s saved=%d" % [m, str(_topdown_dirty), int(SaveMgr.get_value("gfx_mode", 1))])
	hud.theme_changed.emit(UiTheme.DARK)
	await get_tree().process_frame
	print("THEMETEST dark-world=%s rim=%.2f" % [str(match_world.dark), match_world._rim_for()])
	# restore defaults so QA never leaves the player's save dirty
	SaveMgr.set_value("theme", UiTheme.CLASSIC)
	SaveMgr.set_value("gfx_mode", 1)
	hud.apply_theme(UiTheme.CLASSIC)
	print("THEMETEST done — PASS")
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

func _start_play() -> void:
	state = State.PLAYING
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
		var p := match_world.player
		if p is PlayerSnake:
			p.joy_vec = v
			p.joy_active = joy.active or v != Vector2.ZERO)

## The stick owns steering in mobile 2D, so the snake must NOT auto-arc while
## idle underneath it (that idle circle read as "it only moves in circles").
func _sync_joystick_flags() -> void:
	var p := match_world.player
	if p is PlayerSnake:
		var joy: TouchJoystick = hud.joystick()
		p.no_idle_drift = joy != null and joy.enabled

func _restart() -> void:
	_start_play()

func _on_arena_shift(dir: int) -> void:
	# only meaningful in the menu; swaps the live demo backdrop
	if state != State.MENU:
		return
	var nk := ArenaPresets.next_key(_arena_key) if dir >= 0 else ArenaPresets.prev_key(_arena_key)
	_arena_key = nk
	SaveMgr.set_value("arena", nk)
	SaveMgr.save()
	hud.set_arena(nk)
	_rebuild_world()
	match_world.start_demo()

func _on_theme_changed(id: int) -> void:
	# Dark Theme: retint the running world instantly (UI already applied by
	# the HUD). Rebuilding re-bakes court/terrain/sky/decor for the palette.
	_theme_id = id
	SaveMgr.set_value("theme", id)
	match_world.dark = id == UiTheme.DARK
	if state == State.MENU:
		_rebuild_world()
		match_world.start_demo()
	else:
		match_world.restyle(id == UiTheme.DARK, _gfx_mode == 0)

func _on_mode_changed(id: int) -> void:
	# Graphics mode: 0 = 2D top-down, 1 = 3D / 2.5D. Persisted by the HUD.
	_gfx_mode = id
	SaveMgr.set_value("gfx_mode", id)
	_topdown_dirty = true
	match_world.gfx_mode = id
	hud.set_joystick_mode(id == 0)
	_sync_joystick_flags()
	if state == State.MENU:
		_rebuild_world()
		match_world.start_demo()
	else:
		match_world.restyle(match_world.dark, id == 0)

func _rebuild_world() -> void:
	if is_instance_valid(match_world):
		match_world.queue_free()
	match_world = MatchWorld.new()
	match_world.hud = hud
	match_world.arena_key = _arena_key
	match_world.gfx_mode = _gfx_mode
	match_world.dark = _theme_id == UiTheme.DARK
	add_child(match_world)
	match_world.match_event.connect(hud.push_feed)
	match_world.player_died.connect(_on_player_died)

func _to_menu() -> void:
	state = State.MENU
	get_tree().paused = false
	Engine.time_scale = 1.0
	hud.show_menu(true)
	hud.show_pause(false)
	hud.show_gameover_hidden()
	hud.set_gameplay_visible(false)
	match_world.start_demo()

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
			if match_world.running and match_world.get_alive_snakes().size() > 0:
				# cinematic menu orbit around arena action (steeper in 2D mode
				# so the backdrop reads as the top-down board)
				var focus := _demo_focus()
				_cam_angle += delta * 0.08
				if _gfx_mode == 0:
					# 2D mode: flat orthographic board backdrop with a slow drift
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					var vpm := get_viewport().get_visible_rect().size
					var m_aspect := 1.6
					if vpm.y > 1.0:
						m_aspect = vpm.x / vpm.y
					# fit the whole board across the short axis of the screen
					var msize: float = clampf((match_world.arena_radius * 2.0 + 7.0) / maxf(m_aspect, 0.4), 34.0, 132.0)
					cam.size = lerpf(cam.size if cam.size > 0.1 else msize, msize, 1.0 - exp(-2.0 * delta))
					var boff := Vector3(cos(_cam_angle) * 7.0, 0.0, sin(_cam_angle) * 7.0)
					cam.global_transform = Transform3D(
						Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
						focus + Vector3(0.0, 80.0, 0.0) + boff)
				else:
					cam.projection = Camera3D.PROJECTION_PERSPECTIVE   # menu in 3D mode
					var pos := focus + Vector3(cos(_cam_angle) * 46.0, 31.0, sin(_cam_angle) * 46.0)
					var look := focus + Vector3.UP * 2.0
					_cam_pos = _cam_pos.lerp(pos, 1.0 - exp(-2.2 * delta))
					_cam_look = _cam_look.lerp(look, 1.0 - exp(-2.2 * delta))
					cam.global_position = _cam_pos
					cam.look_at(_cam_look, Vector3.UP)
			else:
				_start_demo_if_needed()
		_:
			if match_world.player != null and is_instance_valid(match_world.player):
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

func _start_demo_if_needed() -> void:
	if not match_world.running:
		match_world.start_demo()

func _demo_focus() -> Vector3:
	var alive := match_world.get_alive_snakes()
	if alive.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for s in alive:
		c += Vector3(s.head_pos.x, 0, s.head_pos.z)
	return c / float(alive.size())

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
	var span := 30.0 * clampf(1.45 / maxf(aspect, 0.62), 1.0, 1.35)
	var boost_k := clampf((p.speed_cur - Snake.BASE_SPEED) / (Snake.BASE_SPEED * maxf(Snake.BOOST_MULT - 1.0, 0.1)), 0.0, 1.0)
	var length_k := clampf((p.length - 8.0) / 42.0, 0.0, 1.0)
	span *= 1.0 + 0.08 * boost_k + 0.07 * length_k
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
	var boost_k := clampf((p.speed_cur - Snake.BASE_SPEED) / (Snake.BASE_SPEED * (Snake.BOOST_MULT - 1.0)), 0.0, 1.0)
	var len_k := clampf((p.length - 8.0) / 42.0, 0.0, 1.0)
	var dist := 13.5 + len_k * 2.6
	# camera sits south-east and high: a 3/4 view with real perspective depth
	var back := Vector3(2.4, dist * 0.94, dist * 0.86)
	# a short lead along the travel direction keeps the frame alive (it moves
	# the look point, not the orientation, so key mapping stays exact)
	var lead := Vector3(sin(p.heading), 0.0, cos(p.heading)) * minf(p.speed_cur * 0.20, 2.4)
	var focus := head + Vector3.UP * 0.9
	_cam_pos = _cam_pos.lerp(focus + back, 1.0 - exp(-6.0 * delta))
	var look := focus + Vector3(0.0, 0.0, -2.4) + lead
	_cam_look = _cam_look.lerp(look, 1.0 - exp(-6.0 * delta))
	cam.global_position = _cam_pos
	cam.look_at(_cam_look, Vector3.UP)
	cam.fov = lerpf(cam.fov, 60.0 + boost_k * 8.0, 1.0 - exp(-6.0 * delta))

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
		# keep running unattended — auto-pause and show the overlay (spec §3)
		if state == State.PLAYING:
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
