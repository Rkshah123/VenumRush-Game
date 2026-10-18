class_name MatchWorld
extends Node3D
## Authoritative offline match: spawning, spatial-hash collisions, food, kills,
## respawns, feed events. Demo mode (menu background) reuses the same systems.

signal match_event(kind: String, text: String)
signal player_died

const ARENA_R := 55.0
const AI_TARGET := 7
const PERSONALITY_POOL := ["hunter", "scav", "survivor", "speedy", "territor", "elite"]
const BOSS_LENGTH := 34.0

var arena_radius := ARENA_R
var obstacles: Array = []
var snakes: Array = []
var player: Snake = null
var food: FoodSpawner
var arena: ArenaBuilder
var hud = null
var match_time := 0.0
var _hb := 0.0
var last_kill_text := ""
var running := false
var demo_mode := false
var no_death := false
var solo_dev := false
var skip_hud_dev := false
var verbose := false
var boss_scheduled := false

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
	arena = ArenaBuilder.new()
	add_child(arena)
	obstacles = arena.obstacles
	food = FoodSpawner.new()
	food.arena_radius = arena_radius
	food.obstacles = obstacles
	add_child(food)

# ------------------------------------------------------------------ lifecycle

func start_match() -> void:
	_clear()
	demo_mode = false
	running = true
	# player
	var p: PlayerSnake = PlayerSnake.new()
	_attach(p, true, 7.0)
	player = p
	match_event.emit("info", "STEER WITH THE POINTER — HOLD LMB/SPACE TO BOOST")
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
	s.max_length = 90.0
	s.display_name = "BOSS SERPENT"
	_attach(s, false, BOSS_LENGTH)
	match_event.emit("warn", "A BOSS SERPENT HAS ENTERED THE ARENA")

func _attach(s: Snake, is_player: bool, start_len: float) -> void:
	s.id = _next_id
	_next_id += 1
	s.name = "Snake%d" % s.id
	s.match_world = self
	if demo_mode:
		start_len = randf_range(8.0, 14.0)
	var ang := randf() * TAU
	var rad := arena_radius * randf_range(0.35, 0.72)
	var pos := Vector3(sin(ang) * rad, 0.0, cos(ang) * rad)
	# spawn separation: never materialize inside an existing snake's neighborhood
	for attempt in 12:
		ang = randf() * TAU
		rad = arena_radius * randf_range(0.35, 0.72)
		pos = Vector3(sin(ang) * rad, 0.0, cos(ang) * rad)
		var clear := true
		for o in snakes:
			if is_instance_valid(o) and o.alive and o.head_pos.distance_to(pos) < 12.0:
				clear = false
				break
		if clear:
			break
	var tape := ang + PI * 0.5 + randf_range(-0.4, 0.4)
	var dir := Vector3(sin(tape), 0.0, cos(tape))
	add_child(s)
	_id_map[s.id] = s
	s.spawn(pos, dir, start_len)
	snakes.append(s)
	s.died.connect(_on_died)
	AudioMgr.play("spawn", -6.0)

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
	if _hb > 5.0 and verbose:
		_hb = 0.0
		print("HB t=%.1f snakes=%d orbs=%d" % [match_time, snake_count(), food._orbs.size()])

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

		# boundary barrier
		if s.head_pos.length() > arena_radius - 0.52:
			_kill(s, null, "the barrier")
			continue

		# other snakes' bodies
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
	last_kill_text = "%s <- %s (pos=%.1v rad=%.0f)" % [victim.display_name, cause, victim.head_pos, victim.head_pos.length()]
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
	var orbs: Array = food._orbs.duplicate()
	for s in snakes:
		if not is_instance_valid(s) or not s.alive:
			continue
		var reach: float = s.head_radius() + 0.55
		for i in range(orbs.size() - 1, -1, -1):
			var o: Dictionary = orbs[i]
			var idx := food._orbs.find(o)
			if idx < 0:
				continue
			var op: Vector3 = o["pos"] + Vector3.UP * 0.55
			if s.head_pos.distance_to(op) < reach + float(o["kind"]) * 0.03 + FoodSpawner.KIND_RADIUS[int(o["kind"])] * 0.5:
				if s.is_player:
					AudioMgr.play("eat" if int(o["kind"]) == 0 else ("eat_rare" if int(o["kind"]) == 1 else "eat_gold"))
					var sv := int(FoodSpawner.KIND_SCORE[int(o["kind"])])
					match_event.emit("eat", "+%d" % sv)
					if hud != null and is_instance_valid(hud):
						hud.push_score_popup("+%d" % sv, GameHud.COL_GOLD if int(o["kind"]) == 2 else GameHud.COL_ACCENT)
				s.eat(int(o["kind"]), FoodSpawner.KIND_GROWTH[int(o["kind"])], FoodSpawner.KIND_SCORE[int(o["kind"])])
				food.remove_orb_by_index(idx)
				orbs.remove_at(i)

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
