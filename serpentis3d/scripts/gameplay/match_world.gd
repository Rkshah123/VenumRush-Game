class_name MatchWorld
extends Node3D
## Authoritative offline match: spawning, spatial-hash collisions, food, kills,
## respawns, feed events. Demo mode (menu background) reuses the same systems.

signal match_event(kind: String, text: String)
signal player_died

const ARENA_R := 55.0
const AI_TARGET := 13                 # desktop: full roster
const MOBILE_AI_TARGET := 10          # phone: keep 40+ FPS; new villains lead the pool
const PERSONALITY_POOL := ["cobra", "anaconda", "raptor", "hunter", "scav", "survivor", "speedy", "territor", "elite", "python", "viper", "mamba", "sidewinder"]
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
var _hud_tick := 0    # HUD feed gate (15 Hz)
var _eat_tick := 0    # eat-check gate (30 Hz)
var boss_scheduled := false
var _boss_retry_at := 0.0
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
var ai_target := AI_TARGET

func _ready() -> void:
	# Mobile GPUs pay for every live serpent; 10 AI still includes Cobra,
	# Anaconda and Raptor (they lead PERSONALITY_POOL) while desktop keeps 13.
	ai_target = MOBILE_AI_TARGET if OS.get_name() == "Android" or OS.get_name() == "iOS" else AI_TARGET
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
	# The new arena may have different obstacles: never leave a fruit buried
	# in one after a live 2D/3D or theme switch.
	food.revalidate_spawns()
	for s in snakes:
		if is_instance_valid(s) and s.alive:
			s.set_rim(_rim_for())
			# 2D top-down: no whole-body roll — the straight-down camera reads
			# a banked tube as the snake squashing flat and popping back up
			s.bank = gfx_mode == 1

# ------------------------------------------------------------------ lifecycle

func start_match() -> void:
	_clear()
	demo_mode = false
	running = true
	_spawn_base_ang = randf() * TAU
	_ring_idx = 0
	# player (must exist even in a pathological obstacle layout)
	var p: PlayerSnake = PlayerSnake.new()
	if not _attach(p, true, 7.0):
		p.queue_free()
		player = null
		match_event.emit("warn", "NO CLEAR PLAYER SPAWN")
		return
	player = p
	var touch: bool = OS.has_feature("android") or OS.has_feature("ios")
	match_event.emit("info",
		"DRAG ANYWHERE TO STEER — HOLD A 2ND FINGER TO BOOST" if touch
		else "STEER WITH THE POINTER OR WASD / ARROWS — HOLD LMB/SPACE TO BOOST")
	# AI roster (skippable in dev-solo runs)
	var want_ai: int = ai_target if not solo_dev else 0
	for i in want_ai:
		if not _spawn_ai():
			_respawn_queue.append({"at": 1.0 + 0.25 * float(i)})
	# Boss appears mid-match
	boss_scheduled = false
	_boss_retry_at = 0.0

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

func _spawn_ai() -> bool:
	var pers: String = PERSONALITY_POOL[_pers_cycle % PERSONALITY_POOL.size()]
	_pers_cycle += 1
	var s := AISnake.new()
	s.configure(pers, self)
	s.spine_stride = 2   # phone tier: AI serpents rebuild the tube at 30 Hz
	# 14 opening seats need bodies short enough that one tail never reaches
	# the next head. Growth in-match is unchanged.
	var start_len := randf_range(5.0, 11.5)
	return _attach(s, false, start_len)

func _spawn_boss() -> bool:
	var s := AISnake.new()
	s.configure("hunter", self)
	s.spine_stride = 2
	s.is_boss = true
	s.pattern = 1   # broad dark saddle bands — reads as "elite apex" from above
	s.max_length = 90.0
	s.display_name = "BOSS SERPENT"
	var ok := _attach(s, false, BOSS_LENGTH)
	if ok:
		match_event.emit("warn", "A BOSS SERPENT HAS ENTERED THE ARENA")
	return ok

## Spawn placement is validated against the arena boundary, every obstacle,
## and all existing snake bodies. It never relies on a fixed random guess:
## opening seats use equal-angle ring slots, mid-match entries use random
## candidates plus a deterministic spiral fallback.
func _attach(s: Snake, is_player: bool, start_len: float) -> bool:
	if demo_mode:
		start_len = randf_range(8.0, 14.0)
	var total_for_ring := 1 if solo_dev else (ai_target + 1)
	var ring_slot := -1
	if not demo_mode and match_time < 0.5 and _ring_idx < total_for_ring:
		ring_slot = _ring_idx
		_ring_idx += 1
	var min_dist := clampf(start_len * 0.8, 11.0, 24.0)
	var pos := _find_spawn_pos(ring_slot, total_for_ring, min_dist)
	if pos == Vector3.INF:
		if is_player:
			pos = _emergency_spawn_pos()
		if pos == Vector3.INF:
			if verbose:
				print("SPAWN FAILED %s (no clear seat)" % ("PLAYER" if is_player else s.display_name))
			return false
	var ang := atan2(pos.x, pos.z)
	# Ring seats move TANGENTIALLY (all same direction); scattered entries keep
	# the old tangent-jitter heading.
	var tape := ang + PI * 0.5 + (0.0 if ring_slot >= 0 else randf_range(-0.4, 0.4))
	var dir := Vector3(sin(tape), 0.0, cos(tape))
	s.id = _next_id
	_next_id += 1
	s.name = "Snake%d" % s.id
	s.match_world = self
	s.rim = _rim_for()
	s.bank = gfx_mode == 1     # 2D mode: no body roll (top-down camera squashes it)
	s.grounded = true          # ride the arena surface, no vertical bob
	s.vertical_wave = false
	add_child(s)
	_id_map[s.id] = s
	s.spawn(pos, dir, start_len)
	snakes.append(s)
	s.died.connect(_on_died)
	AudioMgr.play("spawn", -6.0)
	if verbose:
		var who := "PLAYER" if is_player else s.display_name
		print("SPAWN %s slot=%d pos=(%.1f,%.1f) rad=%.1f dir=(%.2f,%.2f) len=%.1f" % [
			who, ring_slot, pos.x, pos.z, pos.length(), dir.x, dir.z, start_len])
	return true

func _find_spawn_pos(ring_slot: int, total_for_ring: int, min_dist: float) -> Vector3:
	if ring_slot >= 0:
		var ang := _spawn_base_ang + TAU * ring_slot / float(maxi(total_for_ring, 1))
		# One shared circle preserves equal angular gaps. Small radial seat
		# drift only avoids boulders; it never changes the theme/arena state.
		var base_r := arena_radius * 0.62
		for attempt in 18:
			var step: float = arena_radius * (0.018 + 0.010 * float(attempt))
			var rr: float = clampf(base_r + (step if attempt % 2 == 0 else -step),
				arena_radius * 0.30, arena_radius * 0.82)
			var p := Vector3(sin(ang) * rr, 0.0, cos(ang) * rr)
			if _spawn_clear(p, min_dist):
				return p
	# Mid-match / fallback: random candidates on open ground.
	for attempt in 48:
		var ang2 := randf() * TAU
		var rad2 := arena_radius * randf_range(0.30, 0.80)
		var p2 := Vector3(sin(ang2) * rad2, 0.0, cos(ang2) * rad2)
		if _spawn_clear(p2, min_dist):
			return p2
	# Deterministic spiral fallback: guarantees a seat even after a crowded
	# respawn wave, without an unbounded retry loop.
	for ring in 8:
		var rr2: float = arena_radius * (0.20 + 0.075 * float(ring))
		var steps := 28 + ring * 8
		var off := randf() * TAU
		for k in steps:
			var a := off + TAU * float(k) / float(steps)
			var p3 := Vector3(sin(a) * rr2, 0.0, cos(a) * rr2)
			if _spawn_clear(p3, min_dist):
				return p3
	return Vector3.INF

func _emergency_spawn_pos() -> Vector3:
	# Last-resort player seat: obstacle/boundary clean, snake separation waived.
	for ring in 10:
		var rr: float = arena_radius * (0.12 + 0.075 * float(ring))
		var steps := 24 + ring * 8
		for k in steps:
			var a := TAU * float(k) / float(steps)
			var p := Vector3(sin(a) * rr, 0.0, cos(a) * rr)
			var clean := true
			for ob in obstacles:
				if p.distance_to(ob["pos"] as Vector3) < float(ob["r"]) + 2.0:
					clean = false
					break
			if clean:
				return p
	return Vector3.INF

func _spawn_clear(pos: Vector3, min_dist: float) -> bool:
	if pos.length() > arena_radius - 4.0:
		return false
	for ob in obstacles:
		var op: Vector3 = ob["pos"]
		if pos.distance_to(op) < float(ob["r"]) + 3.0:
			return false
	for o in snakes:
		if not is_instance_valid(o) or not o.alive:
			continue
		if o.head_pos.distance_to(pos) < min_dist:
			return false
		# Body separation even before the first spine tick: estimate the tail
		# from the live heading, then use real stations once available.
		var fwd: Vector3 = Vector3(sin(float(o.heading)), 0.0, cos(float(o.heading)))
		var body_len: float = maxf(float(o.length), float(o.target_length))
		var tail: Vector3 = o.head_pos - fwd * body_len
		if pos.distance_to(tail) < min_dist * 0.60:
			return false
		var n: int = o.coll_pos.size()
		if n > 0:
			var step_i: int = maxi(1, int(n / 10.0))
			for j in range(0, n, step_i):
				if pos.distance_to(o.coll_pos[j]) < min_dist * 0.50:
					return false
	return true

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
		# Profile line: scene stats (draw calls / objects / prims / VRAM) +
		# frame timings, straight from the RenderingServer so numbers are
		# measured not guessed; dev-tool only, zero cost without --autoplay.
		var rs_c := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var rs_o := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var rs_p := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var rs_v := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
		var pt: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var pr: float = Performance.get_monitor(Performance.TIME_PROCESS)
		print("HB t=%.1f snakes=%d orbs=%d fps=%d worst_dt=%.0fms | %s | dc=%d objs=%d prims=%.1fk vram=%.0fMB phy=%.1fms proc=%.1fms" % [
			match_time, snake_count(), food.count_alive(), Engine.get_frames_per_second(),
			_worst_dt * 1000.0, food.debug_state(), rs_c, rs_o, rs_p / 1000.0,
			rs_v / (1024.0 * 1024.0), float(pt) * 1000.0, float(pr) * 1000.0])
		_worst_dt = 0.0

	# boss appears in real matches after 60 s; retry if the arena is crowded
	if not demo_mode and not boss_scheduled and match_time > 60.0 \
			and snake_count() > 2 and match_time >= _boss_retry_at:
		if _spawn_boss():
			boss_scheduled = true
		else:
			_boss_retry_at = match_time + 1.5
	elif demo_mode and not boss_scheduled and match_time > 30.0:
		boss_scheduled = true  # no boss in demo; just latch

	# AI respawn trickle
	if not _respawn_queue.is_empty():
		for r in _respawn_queue.duplicate():
			if match_time >= float(r["at"]):
				_respawn_queue.erase(r)
				if snake_count() < ai_target + 1:
					if not _spawn_ai():
						r["at"] = match_time + 1.0
						_respawn_queue.append(r)
					break
		# only one respawn per frame

	_build_hash()
	_head_collisions()
	# eat checks tick at 30 Hz: an eat starting one tick late is invisible and
	# the check is a real share of the phone physics budget (orbs × heads)
	_eat_tick += 1
	if _eat_tick % 2 == 0:
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
			var arr = _hash.get(key)   # untyped: null means "new cell" (no per-call array alloc)
			if arr == null:
				arr = []
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
		# Contact is measured at the JAWS and swept over the whole eat-tick
		# window: a fast (or boosting, or magnetised) head cannot tunnel past a
		# fruit, and a fruit no longer vanishes a body-length before the bite.
		var reach: float = s.mouth_reach()
		if s.ability_active("magnet"):
			reach *= 4.5
		var mouth: Vector3 = s.mouth_pos
		# Two swept capsules per eat tick: the JAWS (front bite) and the HEAD
		# CENTRE (a fruit the skull visibly covers but the tiny mouth point can
		# miss, especially in a sharp turn). fly_rec() still claims each fruit
		# exactly once, so overlapping hits can never double-score.
		var hits: Array = food.eat_hits_sweep(s.mouth_prev, mouth, reach)
		var head_reach: float = s.head_radius() * 1.25
		if s.ability_active("magnet"):
			head_reach *= 4.5
		hits.append_array(food.eat_hits_sweep(s.head_prev, s.head_pos, head_reach))
		s.mouth_prev = mouth
		s.head_prev = s.head_pos
		for h in hits:
			var k := int(h["kind"])
			var rec: Dictionary = h["rec"]
			# Claim the fruit first. fly_rec() rejects a record another snake
			# already claimed in this tick, so score/growth/effects can never be
			# applied twice for one fruit.
			if not food.fly_rec(rec, s):
				continue
			if k == 3:
				# POWER ORB: activates a random ability on the eater
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
			# fruit is drawn into the mouth; the gulp fires when it lands
			s.eat_bite()

# ------------------------------------------------------------------ HUD feed

func _update_hud() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	if skip_hud_dev:
		return
	# was per-tick: a fresh 11-entry array + sort + eight label writes at 60 Hz
	# is real CPU on phones — the live readout updates at 15 Hz instead (the
	# boost bar glides at that rate without any visible difference)
	_hud_tick += 1
	if _hud_tick % 4 != 0:
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
