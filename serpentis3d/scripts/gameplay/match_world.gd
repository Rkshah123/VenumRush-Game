class_name MatchWorld
extends Node3D
## Authoritative offline match: spawning, spatial-hash collisions, food, kills,
## respawns, feed events. Demo mode (menu background) reuses the same systems.

signal match_event(kind: String, text: String)
signal player_died

const ARENA_R := 55.0
const AI_TARGET := 10
const PERSONALITY_POOL := ["hunter", "scav", "survivor", "speedy", "territor", "elite", "python", "viper", "mamba", "sidewinder"]
const BOSS_LENGTH := 34.0

var arena_radius := ARENA_R
var arena_key := "valley"
var obstacles: Array = []
var snakes: Array = []
var player: Snake = null
var food: FoodSpawner
var arena: ArenaBuilder
var hud = null
var match_time := 0.0
var _hb := 0.0
var last_kill_text := ""
var player_cause := ""
var running := false
var demo_mode := false
var gfx_mode := 1        # 0 = 2D top-down presentation, 1 = 3D / 2.5D
var dark := false        # Dark Theme world pass (set by Game from settings)
var no_death := false
var solo_dev := false
var skip_hud_dev := false
var verbose := false
var boss_scheduled := false
var _worst_dt := 0.0
var _spawn_base_ang := 0.0
var _ring_idx := 0

var _next_id := 1
var _respawn_queue: Array = []
var _cell := 3.0
var _hash := {}
var _px := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _pr := PackedFloat32Array()
var _po := PackedInt32Array()
var _id_map := {}
var _milestones := {}
var _pers_cycle := 0

func _ready() -> void:
	_build_arena()
	food = FoodSpawner.new()
	food.arena_radius = arena_radius
	food.obstacles = obstacles
	food.dark_theme = dark
	food.mode_2d = gfx_mode == 0
	add_child(food)

func _build_arena() -> void:
	arena = ArenaBuilder.new()
	arena.arena_key = arena_key
	arena.gfx_mode = gfx_mode
	arena.dark = dark
	add_child(arena)
	obstacles = arena.obstacles

func _rim_for() -> float:
	# Theme visibility: edge light on snakes — strong on dark arenas, a touch
	# more in the flat 2D board view.
	return (0.55 if dark else 0.12) + (0.22 if gfx_mode == 0 else 0.0)

func restyle(dark_v: bool, mode_2d: bool) -> void:
	# live theme / graphics-mode switch (settings during a session)
	dark = dark_v
	gfx_mode = 0 if mode_2d else 1
	if is_instance_valid(arena):
		arena.queue_free()
	_build_arena()
	food.obstacles = obstacles
	food.set_style(dark, mode_2d)
	for s in snakes:
		if is_instance_valid(s) and s.alive:
			s.set_rim(_rim_for())

# ------------------------------------------------------------------ lifecycle

func start_match() -> void:
	_clear()
	demo_mode = false
	running = true
	_spawn_base_ang = randf() * TAU
	_ring_idx = 0
	# player
	var p: PlayerSnake = PlayerSnake.new()
	_attach(p, true, 7.0)
	player = p
	var touch: bool = OS.has_feature("android") or OS.has_feature("ios")
	match_event.emit("info",
		"DRAG ANYWHERE TO STEER — HOLD A 2ND FINGER TO BOOST" if touch
		else "STEER WITH THE POINTER OR WASD / ARROWS — HOLD LMB/SPACE TO BOOST")
	# AI roster (skippable in dev-solo runs)
	var ai_target: int = AI_TARGET if not solo_dev else 0
	for i in ai_target:
		_spawn_ai()
	# Boss appears mid-match
	boss_scheduled = false

func start_demo() -> void:
	_clear()
	demo_mode = true
	running = true
	for i in 5:
		_spawn_ai()

func _clear() -> void:
	for s in snakes:
		if is_instance_valid(s):
			s.queue_free()
	snakes.clear()
	player = null
	if is_instance_valid(food):
		food.reset()
	match_time = 0.0
	_respawn_queue.clear()
	_hash.clear()
	_milestones.clear()
	_id_map.clear()
	_spawn_base_ang = randf() * TAU
	_ring_idx = 0
	player_cause = ""
	last_kill_text = ""

func _spawn_ai() -> void:
	var pers: String = PERSONALITY_POOL[_pers_cycle % PERSONALITY_POOL.size()]
	_pers_cycle += 1
	var s := AISnake.new()
	s.configure(pers, self)
	var start_len := randf_range(5.0, 20.0)
	_attach(s, false, start_len)

func _spawn_boss() -> void:
	var s := AISnake.new()
	s.configure("hunter", self)
	s.is_boss = true
	s.pattern = 1   # broad dark saddle bands — reads as "elite apex" from above
	s.max_length = 90.0
	s.display_name = "BOSS SERPENT"
	_attach(s, false, BOSS_LENGTH)
	match_event.emit("warn", "A BOSS SERPENT HAS ENTERED THE ARENA")

func _attach(s: Snake, is_player: bool, start_len: float) -> void:
	s.id = _next_id
	_next_id += 1
	s.name = "Snake%d" % s.id
	s.match_world = self
	s.rim = _rim_for()
	if demo_mode:
		start_len = randf_range(8.0, 14.0)
	# Opening fill (real matches): seat everyone on a tangent ring — equal
	# spacing, identical rotation direction — so no snake spawns facing or
	# converging on another. Mid-match entries (respawns / boss) scatter.
	var total_for_ring := 1 if solo_dev else (AI_TARGET + 1)
	var ring_slot := -1
	if not demo_mode and match_time < 0.5 and _ring_idx < total_for_ring:
		ring_slot = _ring_idx
		_ring_idx += 1
	var ang: float
	var rad: float
	if ring_slot >= 0:
		ang = _spawn_base_ang + TAU * ring_slot / float(total_for_ring)
		# Ring seats all share ONE circle: equal-speed tangential motion then
		# preserves the angular gaps (different radius bands converge and
		# cross lanes). Seat drift below keeps boulders out of the seat.
		var rr: float = arena_radius * 0.58
		var good := false
		for attempt in 14:
			var probe := Vector3(sin(ang) * rr, 0.0, cos(ang) * rr)
			var clean := true
			for ob in obstacles:
				if probe.distance_to(ob["pos"] as Vector3) < float(ob["r"]) + 3.8:
					clean = false
					break
			if clean:
				good = true
				break
			var step: float = arena_radius * (0.025 + 0.012 * float(attempt))
			rr = clampf(rr + (step if attempt % 2 == 0 else -step), arena_radius * 0.16, arena_radius * 0.86)
		if good:
			rad = rr
	else:
		ang = randf() * TAU
		rad = arena_radius * randf_range(0.35, 0.72)
	var pos := Vector3(sin(ang) * rad, 0.0, cos(ang) * rad)
	# spawn separation: never materialize inside an existing snake's neighborhood
	for attempt in 12:
		ang = randf() * TAU
		rad = arena_radius * randf_range(0.35, 0.72)
		pos = Vector3(sin(ang) * rad, 0.0, cos(ang) * rad)
		var clear := true
		for o in snakes:
			if is_instance_valid(o) and o.alive and o.head_pos.distance_to(pos) < 16.0:
				clear = false
				break
		if clear:
			break
	# ring seats move TANGENTIALLY (all same direction); scattered entries
	# keep the old tangent-jitter heading
	var tape := ang + PI * 0.5 + randf_range(-0.4, 0.4) if ring_slot < 0 else ang + PI * 0.5
	var dir := Vector3(sin(tape), 0.0, cos(tape))
	add_child(s)
	_id_map[s.id] = s
	s.spawn(pos, dir, start_len)
	snakes.append(s)
	s.died.connect(_on_died)
	AudioMgr.play("spawn", -6.0)
	if verbose:
		var who := "PLAYER" if is_player else s.display_name
		print("SPAWN %s slot=%d pos=(%.1f,%.1f) rad=%.1f dir=(%.2f,%.2f)" % [who, ring_slot, pos.x, pos.z, pos.length(), dir.x, dir.z])

func is_boss_alive() -> bool:
	for s in snakes:
		if s.is_boss and s.alive:
			return true
	return false

# ------------------------------------------------------------------ per-frame

func _physics_process(delta: float) -> void:
	if not running:
		return
	match_time += delta
	_hb += delta
	if delta > _worst_dt:
		_worst_dt = delta
	if _hb > 5.0 and verbose:
		_hb = 0.0
		print("HB t=%.1f snakes=%d orbs=%d fps=%d worst_dt=%.0fms | %s" % [match_time, snake_count(), food.count_alive(), Engine.get_frames_per_second(), _worst_dt * 1000.0, food.debug_state()])
		_worst_dt = 0.0

	# boss appears in real matches after 60 s
	if not demo_mode and not boss_scheduled and match_time > 60.0 and snake_count() > 2:
		boss_scheduled = true
		_spawn_boss()
	elif demo_mode and not boss_scheduled and match_time > 30.0:
		boss_scheduled = true  # no boss in demo; just latch

	# AI respawn trickle
	if not _respawn_queue.is_empty():
		var due_int := false
		for r in _respawn_queue.duplicate():
			if match_time >= float(r["at"]):
				_respawn_queue.erase(r)
				if snake_count() < AI_TARGET + 1:
					_spawn_ai()
					due_int = true
					break
		# only one respawn per frame

	_build_hash()
	_head_collisions()
	_eat_checks()

	if not demo_mode and player != null and is_instance_valid(player) and player.alive:
		_update_hud()
		if not skip_hud_dev:
			_check_milestones()

func snake_count() -> int:
	var c := 0
	for s in snakes:
		if is_instance_valid(s) and s.alive:
			c += 1
	return c

func food_positions() -> Array:
	return food.alive_positions()

func get_alive_snakes() -> Array:
	var out: Array = []
	for s in snakes:
		if is_instance_valid(s) and s.alive:
			out.append(s)
	return out

func nearby_stations(point: Vector3, reach: float, exclude_id: int) -> Array:
	var out: Array = []
	var bx := int(floor(point.x / _cell))
	var bz := int(floor(point.z / _cell))
	var cr := int(ceil(reach / _cell))
	for dx in range(-cr, cr + 1):
		for dz in range(-cr, cr + 1):
			var arr: Array = _hash.get(Vector2i(bx + dx, bz + dz), [])
			for idx in arr:
				if _po[idx] == exclude_id:
					continue
				var p := Vector3(_px[idx], 0.0, _pz[idx])
				if point.distance_to(p) < reach + _pr[idx]:
					out.append({"pos": p, "r": _pr[idx]})
	return out

# ------------------------------------------------------------------ spatial hash

func _build_hash() -> void:
	_hash.clear()
	_px.clear()
	_pz.clear()
	_pr.clear()
	_po.clear()
	_id_map.clear()
	_hash.clear()
	_id_map.clear()
	for s in snakes:
		if not is_instance_valid(s) or not s.alive:
			continue
		_id_map[s.id] = s
		var cpos: PackedVector3Array = s.coll_pos
		var cr: PackedFloat32Array = s.coll_r
		for i in cpos.size():
			var p := cpos[i]
			var ii := _px.size()
			_px.append(p.x)
			_pz.append(p.z)
			_pr.append(cr[i])
			_po.append(s.id)
			var key := Vector2i(int(floor(p.x / _cell)), int(floor(p.z / _cell)))
			var arr: Array = _hash.get(key, [])
			if arr.is_empty():
				_hash[key] = arr
			arr.append(ii)

# ------------------------------------------------------------------ collisions

func _head_collisions() -> void:
	# no_death = diagnostic/inspection mode (closeup dev harness)
	if no_death:
		return
	for s in snakes.duplicate():
		if not is_instance_valid(s) or not s.alive:
			continue
		if s.head_fatal_grace_active():
			continue

		# boundary barrier (Shield does not protect against the barrier)
		if s.head_pos.length() > arena_radius - 0.52:
			_kill(s, null, "the barrier")
			continue

		# other snakes' bodies (Shield absorbs body hits while active)
		if s.ability_active("shield"):
			continue
		var hr: float = s.head_radius()
		var bx := int(floor(s.head_pos.x / _cell))
		var bz := int(floor(s.head_pos.z / _cell))
		var deadly := false
		for dx in range(-1, 2):
			if deadly:
				break
			for dz in range(-1, 2):
				var arr: Array = _hash.get(Vector2i(bx + dx, bz + dz), [])
				for idx in arr:
					var oid: int = _po[idx]
					if oid == s.id:
						continue
					var other = _id_map.get(oid)
					if other == null or not is_instance_valid(other) or not other.alive:
						continue
					var ddx: float = s.head_pos.x - _px[idx]
					var ddz: float = s.head_pos.z - _pz[idx]
					var rr: float = hr + _pr[idx]
					if ddx * ddx + ddz * ddz < rr * rr:
						_kill(s, other, other.display_name)
						deadly = true
						break
				if deadly:
					break

func _kill(victim: Snake, killer, cause_name: String) -> void:
	if not victim.alive:
		return
	var cause := cause_name
	if killer != null and is_instance_valid(killer):
		killer.kills += 1
		killer.score += int(30.0 + victim.length * 1.2)
		cause = killer.display_name
		match_event.emit("kill", "%s was cut down by %s" % [victim.display_name, killer.display_name])
	else:
		match_event.emit("kill", "%s crashed into %s" % [victim.display_name, cause_name])
	last_kill_text = "%s <- %s (pos=%.1v rad=%.0f t=%.1f age=%.1f)" % [victim.display_name, cause, victim.head_pos, victim.head_pos.length(), match_time, (Time.get_ticks_msec() - victim.spawn_ms) * 0.001]
	if victim.is_player:
		player_cause = cause_name
	if verbose:
		print("KILL:", last_kill_text)
	victim.die(cause if killer == null or not is_instance_valid(killer) else killer.display_name)

func _on_died(s: Snake, killer_name: String) -> void:
	# drop mass into collectible orbs (bounded)
	var stride := maxi(1, int(s.coll_pos.size() / 70.0))
	var count := 0
	for i in range(0, s.coll_pos.size(), stride):
		if count >= 85:
			break
		var kind := 0
		if s.is_boss and count % 4 == 0:
			kind = 2
		elif count % 6 == 3:
			kind = 1
		var jit := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		food.drop_orb(kind, s.coll_pos[i] + jit)
		count += 1

	if s.is_player:
		AudioMgr.play("death")
		player_died.emit()
	else:
		AudioMgr.play("kill", -4.0)
		if not demo_mode:
			_respawn_queue.append({"at": match_time + 3.0 + randf() * 2.0})
	snakes.erase(s)
	s.queue_free()

# ------------------------------------------------------------------ food

func _eat_checks() -> void:
	for s in snakes:
		if not is_instance_valid(s) or not s.alive:
			continue
		var reach: float = s.head_radius() + 0.55
		if s.ability_active("magnet"):
			reach *= 4.5
		var hits: Array = food.eat_hits(s.head_pos, reach)
		for h in hits:
			var k := int(h["kind"])
			if k == 3:
				# POWER ORB: activates a random ability on the eater
				food.fly_orb_at_pos(k, h["pos"], s)
				var ab := "magnet" if randf() < 0.5 else "shield"
				s.apply_ability(ab)
				if verbose:
					print("POWER: %s -> %s (%.1fs)" % [s.display_name, ab, s.ability_left])
				if s.is_player:
					AudioMgr.play("eat_gold")
					match_event.emit("eat", "MAGNET PULSE" if ab == "magnet" else "SHIELD")
					if hud != null and is_instance_valid(hud):
						hud.push_score_popup_at("MAGNET PULSE" if ab == "magnet" else "SHIELD UP", GameHud.role_color("warn"), h["pos"])
				s.eat_bite()
				continue
			if s.is_player:
				AudioMgr.play("eat" if k == 0 else ("eat_rare" if k == 1 else "eat_gold"))
				var sv := int(FoodSpawner.KIND_SCORE[k])
				match_event.emit("eat", "+%d" % sv)
				if hud != null and is_instance_valid(hud):
					hud.push_score_popup_at("+%d" % sv, GameHud.role_color("gold") if k == 2 else GameHud.role_color("accent"), h["pos"])
			s.eat(k, FoodSpawner.KIND_GROWTH[k], FoodSpawner.KIND_SCORE[k])
			# fruit flies into the mouth; bite + burst are part of the event
			food.fly_orb_at_pos(k, h["pos"], s)
			s.eat_bite()

# ------------------------------------------------------------------ HUD feed

func _update_hud() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	if skip_hud_dev:
		return
	var alive := get_alive_snakes()
	alive.sort_custom(func(a, b): return a.score > b.score)
	var rank := alive.size()
	for i in alive.size():
		if alive[i] == player:
			rank = i + 1
			break
	hud.set_score(player.score)
	hud.set_length(player.length)
	hud.set_rank(rank, alive.size())
	hud.set_boost(player.boost_meter / Snake.BOOST_MAX)
	hud.set_boosting(player.boost_active)
	if player.ability != "" and player.ability_left > 0.0:
		hud.set_ability("MAGNET PULSE" if player.ability == "magnet" else "SHIELD", player.ability_frac())
	else:
		hud.set_ability("", 0.0)
	hud.set_timer(match_time)
	hud.set_kills(player.kills)

func _check_milestones() -> void:
	for m in [12.0, 20.0, 30.0, 45.0]:
		if player.length >= m and not _milestones.has(m):
			_milestones[m] = true
			hud.announce("MILESTONE", "LENGTH %d M" % int(m))

func rank_of_live(snake: Snake) -> int:
	var alive := get_alive_snakes()
	alive.sort_custom(func(a, b): return a.score > b.score)
	for i in alive.size():
		if alive[i] == snake:
			return i + 1
	return alive.size()
