extends Node3D
## Game orchestrator: menu/demo/play states, camera rig, pause flow,
## game-over flow, dev harness (autoplay screenshots).

enum State { MENU, PLAYING, PAUSED, OVER }

var hud: GameHud
var match_world: MatchWorld
var cam: Camera3D
var state := State.MENU
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
var _diag_t := 0.0

func _ready() -> void:
	randomize()
	hud = GameHud.new()
	add_child(hud)
	match_world = MatchWorld.new()
	match_world.hud = hud
	add_child(match_world)
	match_world.match_event.connect(hud.push_feed)
	match_world.player_died.connect(_on_player_died)

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

	# dev args: `godot --path proj -- --autoplay --shot=8 --quit=9`
	var args := _collect_dev_args()
	if "--autoplay" in args:
		_autoplay = true
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
	if _autoplay:
		# Automated checks must never disturb the player: mute all audio for
		# this session only (saved volume settings are untouched) and push the
		# window far off-screen so it doesn't pop up over their work.
		AudioServer.set_bus_mute(0, true)
		DisplayServer.window_set_position(Vector2i(-3200, -3200))
		_dev_sequence()

	get_tree().set_auto_accept_quit(true)

# Dev flags are accepted both after `--` (user args) and as raw engine args.
func _collect_dev_args() -> Array[String]:
	var out: Array[String] = []
	for src in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for a in src:
			if a == "--autoplay" or a.begins_with("--shot=") or a.begins_with("--quit") or a == "--closeup" or a.begins_with("--closeup="):
				if not out.has(a):
					out.append(a)
	print("DEVARGS: ", out)
	return out

func _dev_sequence() -> void:
	# menu breathing room, then a real match, optional screenshot & quit
	await get_tree().create_timer(1.0).timeout
	if _shot_menu:
		await _snap("shot_menu.png")
	await get_tree().create_timer(0.6).timeout
	_start_play()
	print("DEV: play started")
	if _quit_at > 0.0:
		await get_tree().create_timer(_quit_at * 0.5).timeout
		await _snap("shot_mid.png")
		await get_tree().create_timer(_quit_at * 0.5).timeout
		if _shot_game:
			await _snap("shot_game.png")
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
	var img := get_viewport().get_texture().get_image()
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
	match_world.start_match()
	AudioMgr.play("spawn")
	hud.announce("SURVIVE", "COLLECT ORBS — GROW — ELIMINATE RIVALS")
	if _closeup and match_world.player != null:
		match_world.player.hold_heading = match_world.player.heading
		match_world.no_death = true

func _restart() -> void:
	_start_play()

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
	stats["is_best"] = is_best
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
	return match_world.rank_of_live(match_world.player) if player_alive() else 99
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
	var len_extra := clampf(p.length * 0.045, 0.0, 2.6)
	var dist := 8.5 + len_extra + (1.4 if p.boost_active else 0.0)
	var height := 4.4 + len_extra * 0.7
	var desired := head - fwd * dist + Vector3.UP * height
	_cam_pos = _cam_pos.lerp(desired, 1.0 - exp(-5.5 * delta))
	var look_target := head + fwd * 4.2 + Vector3.UP * 1.0
	_cam_look = _cam_look.lerp(look_target, 1.0 - exp(-7.0 * delta))
	cam.global_position = _cam_pos
	cam.look_at(_cam_look, Vector3.UP)

# ---------------------------------------------------------------- app defaults

func _quit_nicely() -> void:
	SaveMgr.save()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_nicely()

# HUD signal alias fixups (declared after use for readability)
func _hud_wiring_check() -> void:
	pass
