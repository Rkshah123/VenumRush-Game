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
var _cam_look := Vector3.ZERO
var _player_last_head := Vector3.ZERO

# dev harness
var _autoplay := false
var _closeup := false
var _shot_menu := false
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
		if a == "--skins-test":
			_autoplay = true
			_skins_test = true
	_arena_key = str(SaveMgr.get_value("arena", "valley"))
	if arena_dev != "" and ArenaPresets.ALL.has(arena_dev):
		_arena_key = arena_dev
	elif not ArenaPresets.ALL.has(_arena_key):
		_arena_key = "valley"
	hud = GameHud.new()
	add_child(hud)
	match_world = MatchWorld.new()
	match_world.hud = hud
	match_world.arena_key = _arena_key
	add_child(match_world)
	match_world.match_event.connect(hud.push_feed)
	match_world.player_died.connect(_on_player_died)
	hud.set_arena(_arena_key)
	hud.arena_shift.connect(_on_arena_shift)

	cam = Camera3D.new()
	cam.fov = 55.0
	cam.current = true
	add_child(cam)
	cam.position = _cam_pos
	cam.look_at_from_position(_cam_pos, Vector3.ZERO, Vector3.UP)

	hud.play_pressed.connect(func(): _start_play())
	hud.quit_pressed.connect(func(): _quit_nicely())
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
	var allow := ["--autoplay", "--no-death", "--solo", "--hud-off", "--onscreen-test", "--shot-menu", "--arena-test", "--touch-test", "--spawntest", "--powertest", "--skins-test"]
	for src in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var keep := false
		if allow.has(src):
			keep = true
			if src == "--shot-menu":
				_shot_menu = true
		elif src.begins_with("--arena="):
			keep = true
			var k := src.substr(8)
			if ArenaPresets.ALL.has(k):
				_arena_key = k
		elif src.begins_with("--skin="):
			keep = true
			_skin_dev = clampi(int(src.substr(7)), 0, SkinCatalog.count() - 1)
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
	if _shot_menu:
		await _snap("shot_menu.png")
	await get_tree().create_timer(0.6).timeout
	_start_play()
	print("DEV: play started")
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

# ---------------------------------------------------------------- power QA

func _powertest_run() -> void:
	# Power-orb QA: magnet vacuums fruit (score rate), timed expiry works,
	# shield toggles cleanly. Ability bar visibility checked via screenshot.
	var p: PlayerSnake = match_world.player
	if p == null:
		print("POWERTEST FAIL no player")
		_quit_nicely()
		return
	await get_tree().create_timer(1.0).timeout
	p.apply_ability("magnet")
	print("POWERTEST magnet-on %s" % ("PASS" if p.ability_active("magnet") else "FAIL"))
	var s0: int = p.score
	await get_tree().create_timer(2.0).timeout
	await _snap("shot_power.png")
	await get_tree().create_timer(3.4).timeout
	var gained: int = p.score - s0
	print("POWERTEST magnet-gain=%d %s" % [gained, "PASS" if gained >= 25 else "FAIL"])
	print("POWERTEST magnet-off %s" % ("PASS" if not p.ability_active("magnet") else "FAIL"))
	p.apply_ability("shield")
	print("POWERTEST shield-on %s" % ("PASS" if p.ability_active("shield") else "FAIL"))
	await get_tree().create_timer(4.2).timeout
	print("POWERTEST shield-off %s" % ("PASS" if not p.ability_active("shield") else "FAIL"))
	print("POWERTEST alive %s" % ("PASS" if p.alive else "FAIL"))
	_quit_nicely()

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
		match_world.player.apply_skin(sk["dorsal"], sk["accent"], sk["belly"], sk["seed"])
		print("SKIN apply=", sk["name"], " idx=", skin_idx)
	AudioMgr.play("spawn")
	hud.announce("SURVIVE", "COLLECT ORBS — GROW — ELIMINATE RIVALS")
	if _closeup and match_world.player != null:
		match_world.player.hold_heading = match_world.player.heading
		match_world.no_death = true

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

func _rebuild_world() -> void:
	if is_instance_valid(match_world):
		match_world.queue_free()
	match_world = MatchWorld.new()
	match_world.hud = hud
	match_world.arena_key = _arena_key
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

func _resume() -> void:
	state = State.PLAYING
	get_tree().paused = false
	hud.show_pause(false)

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
		# Android BACK: pause in a match, in pause menu or game over = menu,
		# in settings = main menu, on main menu = allow quit via system default
		match state:
			State.PLAYING:
				get_viewport().set_input_as_handled()
				_pause()
			State.PAUSED:
				get_viewport().set_input_as_handled()
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
				# cinematic menu orbit around arena action
				var focus := _demo_focus()
				_cam_angle += delta * 0.08
				var pos := focus + Vector3(cos(_cam_angle) * 30.0, 15.0, sin(_cam_angle) * 30.0)
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
					_chase_camera(delta)
			elif not _quit_at > 0.0 and state == State.OVER:
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

func _chase_camera(delta: float) -> void:
	var p := match_world.player
	if p == null or not is_instance_valid(p):
		return
	var head := p.head_pos
	_player_last_head = head
	var fwd := Vector3(sin(p.heading), 0.0, cos(p.heading))
	# boost speed-kick: FOV widens and the camera looks further ahead while boosting
	var boost_k := clampf((p.speed_cur - Snake.BASE_SPEED) / (Snake.BASE_SPEED * (Snake.BOOST_MULT - 1.0)), 0.0, 1.0)
	var len_extra := clampf(p.length * 0.045, 0.0, 2.6)
	var dist := 8.5 + len_extra + (1.4 if p.boost_active else 0.0)
	var height := 4.4 + len_extra * 0.7
	var desired := head - fwd * dist + Vector3.UP * height
	_cam_pos = _cam_pos.lerp(desired, 1.0 - exp(-5.5 * delta))
	var look_target := head + fwd * (4.2 + boost_k * 2.4) + Vector3.UP * 1.0
	_cam_look = _cam_look.lerp(look_target, 1.0 - exp(-7.0 * delta))
	cam.global_position = _cam_pos
	cam.look_at(_cam_look, Vector3.UP)
	cam.fov = lerpf(cam.fov, 70.0 + boost_k * 10.0, 1.0 - exp(-6.0 * delta))

# ---------------------------------------------------------------- app defaults

func _quit_nicely() -> void:
	SaveMgr.save()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_nicely()
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
