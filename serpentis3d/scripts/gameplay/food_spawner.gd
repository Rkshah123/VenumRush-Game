class_name FoodSpawner
extends Node3D
## Collectible REAL FRUITS (basic / rare / golden) + power orbs + fallen-snake
## drops (spec §5). Each kind may have SEVERAL real-food variants (apple /
## strawberry / watermelon for basic; cherries for rare; lemon / banana for
## golden) chosen RANDOMLY per spawn so the court always shows variety.
## All variants render through SHARED per-variant MultiMeshes (a handful of
## draw calls total) with per-slot transforms updated in _process (bob +
## sway) — cheap on integrated GPUs regardless of fruit count.
##
## Eating animation (spec §4): the eaten fruit FLYS INTO the snake's mouth
## (short eased flight + shrink + spin), then the sparkle burst pops where the
## fruit disappeared. Growth/score stay handled by MatchWorld (counted once).

const KIND_TARGETS := [40, 6, 2, 2]
const KIND_GROWTH := [0.5, 0.95, 1.4, 0.4]
const KIND_SCORE := [10, 30, 75, 15]
const KIND_COLORS := [Color(0.92, 0.16, 0.12), Color(0.55, 0.25, 0.75), Color(1.0, 0.78, 0.25), Color(0.42, 0.92, 1.0)]
const KIND_RADIUS := [0.3, 0.34, 0.4, 0.35]
# absolute fruit budget - death drops respect this cap. Phones keep a leaner
# court (see _ready): fewer alive orbs means smaller eat-check, hash and
# MultiMesh work every tick, and density past ~110 was never surface-visible
const HARD_CAP := 178
const FRUIT_TILT := 0.60  # ~34° camera-facing lean: silhouette readable top-down
const BOB_BASE := [0.34, 0.34, 0.34, 0.52]
const BOB_AMP := [0.07, 0.07, 0.07, 0.13]
const BOB_SPD := [2.0, 2.0, 2.0, 3.4]
const FLY_TIME := 0.13  # min seconds of the eat-flight into the mouth
const FLY_TIME_MAX := 0.5
const SPAWN_EDGE := 4.5   # keep fruit comfortably inside the death barrier
const FRUIT_GAP := 0.9    # minimum centre distance between two fruits
var _bob_frame := 0     # transform-refresh counter for the throttled bob pass

# Variant table per kind. For real foods: path + pool capacity + spawn weight
# + normalized height + emissive boost. Named surfaces ("surface_map") get
# dedicated colors; everything else is tinted with the kind color so the
# gameplay color coding stays readable at distance (spec §5).
const SURFACE_COLORS := {
	"rind_green": Color(0.11, 0.44, 0.15),
	"rind_lime": Color(0.60, 0.77, 0.35),
	"seed_dark": Color(0.03, 0.03, 0.03),
	"fruit_inner": Color(0.95, 0.87, 0.55),
	"spore_light": Color(0.92, 0.90, 0.84),
}
const VAR_TABLE := [
	[
		{"path": "res://models/food/apple.obj", "cap": 90, "w": 0.40, "h": 0.98, "emit": 0.45},
		{"path": "res://models/food/strawberry.obj", "cap": 45, "w": 0.28, "h": 0.82, "emit": 0.50},
		{"path": "res://models/food/watermelon_slice.obj", "cap": 45, "w": 0.32, "h": 0.85, "emit": 0.35,
			"surface_map": {"rind": "rind_green", "rindw": "rind_lime", "black": "seed_dark"}},
	],
	[
		{"path": "res://models/food/cherries.obj", "cap": 20, "w": 0.58, "h": 0.78, "emit": 0.55},
		{"path": "res://models/food/mushroom.obj", "cap": 14, "w": 0.42, "h": 0.75, "emit": 0.55,
			"surface_map": {"white": "spore_light"}},
	],
	[
		{"path": "res://models/food/lemon.obj", "cap": 10, "w": 0.36, "h": 0.94, "emit": 0.60},
		{"path": "res://models/food/banana.obj", "cap": 8, "w": 0.32, "h": 0.88, "emit": 0.60,
			"surface_map": {"banana2": "seed_dark", "seed": "fruit_inner"}},
		{"path": "res://models/food/carrot.obj", "cap": 7, "w": 0.32, "h": 1.05, "emit": 0.60},
	],
	[
		{"path": "", "cap": 8, "w": 1.0, "h": 0.6, "emit": 1.0, "power": true},
	],
]

var arena_radius := 56.0
var obstacles: Array = []     # [{pos, r}] for placement rejection
var dark_theme := false       # Dark Theme: brighter emissives + rim so fruit pops
var mode_2d := false          # 2D top-down mode: same contrast treatment

var _slots: Array = []        # per kind: Array of pool dicts {mm, free, alive}
var _var_caps: Array = []     # per kind: Array of capacities (deficit bookkeeping)
var _total := 0
var _deficit: Array = []

var _pop_mesh: SphereMesh              # shared, pre-built: zero alloc per pop
var _pop_pool: Array = []              # [{node, mesh}] reused round-robin
var _pop_next := 0
var _pop_hits := 0

# ---------------------------------------------------------------- lifecycle

var hard_cap := HARD_CAP   # effective budget; phones run ~2/3 of it
var qa_freeze_respawn := false   # dev harness: isolate one eat case

func _ready() -> void:
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		hard_cap = 112
	for kind in VAR_TABLE.size():
		var pools: Array = []
		var caps: Array = []
		for cfg: Dictionary in VAR_TABLE[kind]:
			pools.append(_make_pool(_variant_mesh(kind, cfg), int(cfg["cap"])))
			caps.append(int(cfg["cap"]))
		_slots.append(pools)
		_var_caps.append(caps)
	_pop_mesh = SphereMesh.new()
	_pop_mesh.radius = 0.10
	_pop_mesh.height = 0.2
	_pop_mesh.radial_segments = 5
	_pop_mesh.rings = 3
	for i in 14:
		var pop := Node3D.new()
		pop.visible = false
		add_child(pop)
		var m := MeshInstance3D.new()
		m.mesh = _pop_mesh
		var pmat := StandardMaterial3D.new()   # per-node material → safe per-pop tween
		pmat.albedo_color = Color(KIND_COLORS[i % 3], 0.9)
		pmat.emission_enabled = true
		pmat.emission = KIND_COLORS[i % 3]
		pmat.emission_energy_multiplier = 2.2
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.material_override = pmat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pop.add_child(m)
		_pop_pool.append(pop)

func set_style(dark: bool, two_d: bool) -> void:
	# live theme / graphics-mode switch: swap the variant meshes (instances,
	# scores and slots untouched) so emissives + rims match the new look
	dark_theme = dark
	mode_2d = two_d
	if not is_inside_tree() or _slots.is_empty():
		return
	for kind in _slots.size():
		var pools: Array = _slots[kind]
		for vi in pools.size():
			var cfg: Dictionary = VAR_TABLE[kind][vi]
			var mm: MultiMesh = (pools[vi]["mm"] as MultiMesh)
			mm.mesh = _variant_mesh(kind, cfg)

func _variant_mesh(kind: int, cfg: Dictionary) -> Mesh:
	if bool(cfg.get("power", false)):
		return _power_mesh()
	return _real_fruit_mesh(cfg["path"], float(cfg["h"]), float(cfg["emit"]), cfg.get("surface_map", {}), kind)

func _make_pool(mesh: Mesh, cap: int) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = cap
	var bury := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0.0, -50.0, 0.0))
	for i in cap:
		mm.set_instance_transform(i, bury)
	var free: Array[int] = []
	free.resize(cap)
	for i in cap:
		free[i] = cap - 1 - i
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# camera-facing lean compensation: a tilted fruit sinks one half into the
	# floor, so the spawn float gets the sink back (real silhouette from above)
	var sink := 0.0
	if mesh != null:
		var bb := mesh.get_aabb()
		sink = sin(FRUIT_TILT) * bb.size.y * 0.5
	return {"mm": mm, "free": free, "alive": {}, "sink": sink}

func reset() -> void:
	for kind in _slots.size():
		for s: Dictionary in _slots[kind]:
			var alive: Dictionary = s["alive"]
			var free: Array[int] = s["free"]
			var mm: MultiMesh = s["mm"]
			for idx in alive.keys():
				mm.set_instance_transform(idx, _bury())
				free.append(int(idx))
			alive.clear()
	_total = 0
	_deficit = []
	_deficit.resize(KIND_TARGETS.size())
	for kind in KIND_TARGETS.size():
		_deficit[kind] = 0
		for i in KIND_TARGETS[kind]:
			if not _spawn_orb(kind):
				_deficit[kind] += 1

func count_alive() -> int:
	# ground truth: sum of live slot records across every variant pool
	var n := 0
	for kind in _slots.size():
		for s: Dictionary in _slots[kind]:
			n += (s["alive"] as Dictionary).size()
	return n

func debug_state() -> String:
	var parts: Array[String] = []
	for kind in KIND_TARGETS.size():
		var nav := 0
		var nfly := 0
		var free_n := 0
		for s: Dictionary in _slots[kind]:
			for rec: Dictionary in (s["alive"] as Dictionary).values():
				if rec.has("fly"):
					nfly += 1
				else:
					nav += 1
			free_n += (s["free"] as Array).size()
		parts.append("k%d alive=%d(fly %d) free=%d def=%d" % [kind, nav, nfly, free_n, _deficit[kind]])
	return "total=%d " % _total + " ".join(parts)

# ---------------------------------------------------------------- spawn/remove

func drop_orb(kind: int, pos: Vector3) -> void:
	if _total >= hard_cap:
		return
	# Death drops originate on a body station: keep them inside the playable
	# disc and push them out of boulders/trees. A fruit hidden INSIDE a rock is
	# the classic "left behind, cannot be eaten" report.
	var p := Vector3(pos.x, 0.0, pos.z).limit_length(arena_radius - SPAWN_EDGE)
	var drop_ok := _clear_of_obstacles(p, KIND_RADIUS[kind])
	for attempt in 7:
		if drop_ok:
			break
		var inward := -p.normalized() if p.length_squared() > 0.01 else Vector3.FORWARD
		p += inward * 1.4
		p = p.limit_length(arena_radius - SPAWN_EDGE)
		drop_ok = _clear_of_obstacles(p, KIND_RADIUS[kind])
	if not drop_ok:
		return
	_spawn_orb(kind, p)

## Weighted pick among variants that still have a free instance. The old pick
## could land on a full pool and silently lose the respawn entirely.
func _pick_variant(kind: int, pools: Array) -> int:
	var table: Array = VAR_TABLE[kind]
	var total_w := 0.0
	for i in table.size():
		if not (pools[i]["free"] as Array).is_empty():
			total_w += float(table[i]["w"])
	if total_w <= 0.0:
		return -1
	var roll := randf() * total_w
	var acc := 0.0
	for i in table.size():
		if (pools[i]["free"] as Array).is_empty():
			continue
		acc += float(table[i]["w"])
		if roll <= acc:
			return i
	return -1

func _spawn_orb(kind: int, at: Vector3 = Vector3.INF) -> bool:
	if _total >= hard_cap:
		return false
	var pools: Array = _slots[kind]
	var vi := _pick_variant(kind, pools)
	if vi < 0:
		return false
	var s: Dictionary = pools[vi]
	var free: Array[int] = s["free"]
	if free.is_empty():
		return false
	var r: float = KIND_RADIUS[kind]
	var pos := at
	if pos == Vector3.INF:
		pos = _pick_spawn_pos(r)
		if pos == Vector3.INF:
			return false
	else:
		pos.y = 0.0
		if not _clear_of_obstacles(pos, r) or pos.length() > arena_radius - 2.0:
			return false
	var idx: int = free.pop_back()
	(s["alive"] as Dictionary)[idx] = {
		"pos": pos, "phase": randf() * TAU, "kind": kind, "born": t_now()}
	_total += 1
	return true

## Random disc sampling with a guaranteed-clear fallback scan. A rejected
## candidate never becomes fruit: every orb the player sees is on open ground,
## inside the arena, and separated from other orbs.
func _pick_spawn_pos(r: float) -> Vector3:
	var best := Vector3.INF
	var best_clear := -999.0
	for attempt in 14:
		var ang := randf() * TAU
		var rad := sqrt(randf()) * (arena_radius - SPAWN_EDGE)
		var pos := Vector3(sin(ang) * rad, 0.0, cos(ang) * rad)
		var cl := _obstacle_clearance(pos, r)
		if cl > best_clear:
			best_clear = cl
			best = pos
		if cl >= 1.0 and _clear_of_fruits(pos, r):
			return pos
	# spiral fallback: deterministic open bands, no infinite retry loop
	for ring in 5:
		var rad: float = arena_radius * (0.22 + 0.145 * float(ring))
		var steps := 20 + ring * 8
		var off := randf() * TAU
		for k in steps:
			var ang := off + TAU * float(k) / float(steps)
			var pos := Vector3(sin(ang) * rad, 0.0, cos(ang) * rad)
			if _obstacle_clearance(pos, r) >= 1.0 and _clear_of_fruits(pos, r):
				return pos
	return Vector3.INF

func _obstacle_clearance(pos: Vector3, r: float) -> float:
	var cl := 99.0
	for ob in obstacles:
		var d := pos.distance_to(ob["pos"] as Vector3) - float(ob["r"]) - r - 1.5
		cl = minf(cl, d)
	return cl

func _clear_of_obstacles(pos: Vector3, r: float) -> bool:
	return _obstacle_clearance(pos, r) >= 0.0

func _clear_of_fruits(pos: Vector3, _r: float) -> bool:
	var gap2 := FRUIT_GAP * FRUIT_GAP
	for kind in _slots.size():
		for s: Dictionary in _slots[kind]:
			var alive: Dictionary = s["alive"]
			for idx in alive.keys():
				if (alive[idx]["pos"] as Vector3).distance_squared_to(pos) < gap2:
					return false
	return true

func t_now() -> float:
	return Time.get_ticks_msec() * 0.001

## A live theme/mode switch rebuilds the arena, so the obstacle list can change
## under fruit that was already on the ground. Re-check every passive fruit
## against the NEW obstacles/arena and retire any that is now buried in a rock
## or outside the safe ring; the normal deficit logic respawns it on open
## ground. Flying fruit is already claimed and is left alone.
func revalidate_spawns() -> void:
	for kind in _slots.size():
		for s: Dictionary in _slots[kind]:
			var alive: Dictionary = s["alive"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if rec.has("fly"):
					continue
				var pos: Vector3 = rec["pos"]
				if pos.length() > arena_radius - SPAWN_EDGE \
						or not _clear_of_obstacles(pos, KIND_RADIUS[kind]):
					_bury_idx(s, idx, kind)

func alive_positions() -> Array:
	var out: Array = []
	for kind in _slots.size():
		for s: Dictionary in _slots[kind]:
			var alive: Dictionary = s["alive"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if not rec.has("fly"):
					out.append(rec["pos"])
	return out

## All edible fruits whose GROUND position is within `reach` of the swept
## segment from -> to (the snake's mouth at the previous/current eat tick).
## Sweeping is what lets a fast head (and a 30 Hz eat tick) collect every fruit
## it visibly crosses. Returns the actual pool records: MatchWorld hands them
## straight back to fly_rec(), so there is no position lookup that could pick
## the wrong fruit or double-count one.
func eat_hits_sweep(from: Vector3, to: Vector3, reach: float) -> Array:
	var out: Array = []
	var sx := to.x - from.x
	var sz := to.z - from.z
	var seg_len2 := sx * sx + sz * sz
	for kind in _slots.size():
		for s: Dictionary in _slots[kind]:
			var alive: Dictionary = s["alive"]
			var rr: float = reach + float(kind) * 0.03 + KIND_RADIUS[kind] * 0.5
			var rr2 := rr * rr
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if rec.has("fly"):
					continue
				var p: Vector3 = rec["pos"]
				var qx := from.x
				var qz := from.z
				if seg_len2 > 0.000001:
					var t := clampf(((p.x - from.x) * sx + (p.z - from.z) * sz) / seg_len2, 0.0, 1.0)
					qx = from.x + sx * t
					qz = from.z + sz * t
				# Degenerate segment (a freshly spawned/settled mouth): test the
				# POINT from, never each fruit against itself. The old fallback
				# turned every fruit in the arena into a hit on a spawn frame.
				var dx := p.x - qx
				var dz := p.z - qz
				if dx * dx + dz * dz < rr2:
					out.append({"rec": rec, "pos": p, "kind": kind})
	return out

func remove_orb_at_pos(kind: int, pos: Vector3) -> bool:
	# removes ONE fruit of this kind at pos (kept for dev tooling).
	var pools: Array = _slots[kind]
	for s: Dictionary in pools:
		var alive: Dictionary = s["alive"]
		for idx in alive.keys():
			var rec: Dictionary = alive[idx]
			if not rec.has("fly") and (rec["pos"] as Vector3).distance_squared_to(pos) < 0.02:
				_bury_idx(s, idx, kind)
				pop_at(pos, kind)
				return true
	return false

## Start the eat-flight for an EXACT record returned by eat_hits_sweep. The
## flight starts at the fruit's current rendered position and ends at the
## eater's live mouth, so the hand-off is seamless (no "fruit teleports to a
## point above the head" artefact) and the bite happens where the player sees it.
func fly_rec(rec: Dictionary, eater: Node3D) -> bool:
	if rec.has("fly"):
		return false
	var kind := int(rec["kind"])
	var from: Vector3 = rec.get("vis", (rec["pos"] as Vector3) + Vector3.UP * (BOB_BASE[kind] + 0.18))
	rec["fly"] = {"t": 0.0, "from": from, "snake": eater,
		"dur": clampf(from.distance_to(_mouth_of(eater)) * 0.085, FLY_TIME, FLY_TIME_MAX)}
	return true

func _mouth_of(snake) -> Vector3:
	if snake != null and is_instance_valid(snake):
		return Vector3(snake.mouth_pos) + Vector3.UP * 0.18
	return Vector3.ZERO

func _bury_idx(s: Dictionary, idx: int, kind: int) -> void:
	var alive: Dictionary = s["alive"]
	var free: Array[int] = s["free"]
	alive.erase(idx)
	s["mm"].set_instance_transform(idx, _bury())
	free.append(int(idx))
	_total -= 1
	_deficit[kind] += 1

func _bury() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0.0, -50.0, 0.0))

func pop_at(pos: Vector3, kind: int) -> void:
	# reused pooled node: zero allocations, zero shader compilation churn
	# (spec §4 sparkle burst: quick inflate + upward drift + colored flash)
	if _pop_pool.is_empty():
		return
	var pop: Node3D = _pop_pool[_pop_next % _pop_pool.size()]
	_pop_next += 1
	_pop_hits += 1
	pop.position = pos + Vector3.UP * 0.4
	var m: MeshInstance3D = pop.get_child(0)
	var pm: StandardMaterial3D = m.material_override
	pm.albedo_color = Color(KIND_COLORS[kind], 1.0)
	pm.emission = KIND_COLORS[kind]
	m.scale = Vector3(0.4, 0.4, 0.4)
	pop.visible = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(1.55, 1.55, 1.55), 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pop, "position:y", pop.position.y + 0.8, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pm, "albedo_color:a", 0.0, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): pop.visible = false)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	# passive orbs re-write their (static-ish) transforms at ~20 Hz: the bob
	# waves are 0.3-0.5 Hz, so 1/3 rate is visually identical and cuts the
	# per-frame MultiMesh churn (178 instances) to a third on weak devices.
	_bob_frame += 1
	var bob_tick: bool = _bob_frame % 3 == 0
	for kind in _slots.size():
		var pools: Array = _slots[kind]
		for s: Dictionary in pools:
			var alive: Dictionary = s["alive"]
			var mm: MultiMesh = s["mm"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if rec.has("fly"):
					# --- eat-flight: drawn into the live MOUTH, then gulp ---
					var fly: Dictionary = rec["fly"]
					var snake = fly["snake"]   # untyped: may already be freed
					fly["t"] = float(fly["t"]) + delta
					var dur: float = maxf(float(fly.get("dur", FLY_TIME)), 0.05)
					var q: float = clampf(float(fly["t"]) / dur, 0.0, 1.0)
					if not is_instance_valid(snake):
						_bury_idx(s, idx, kind)
						continue
					var target: Vector3 = _mouth_of(snake)
					var from: Vector3 = fly["from"]
					var e := smoothstep(0.0, 1.0, q)   # snap toward the jaws
					var p := from.lerp(target, e)
					p += Vector3.UP * (0.28 * sin(q * PI))
					var yaw := q * 5.0 + float(rec["phase"])
					# hold full size until it reaches the mouth, then vanish
					var sc := 1.0 - 0.90 * smoothstep(0.45, 1.0, q)
					mm.set_instance_transform(idx, Transform3D(
						Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), p))
					if q >= 1.0:
						_bury_idx(s, idx, kind)
						pop_at(target - Vector3.UP * 0.16, kind)
						# visible gulp AFTER the fruit lands, not on first touch
						if snake.has_method("swallow"):
							snake.swallow()
					continue
				if not bob_tick:
					continue   # passive orb: transform refresh at the throttled rate
				var ph: float = rec["phase"]
				var p: Vector3 = rec["pos"]
				var yaw := sin(t * 0.7 + ph) * 0.28 + (t * 2.2 if kind == 3 else 0.0)
				var yy: float = BOB_BASE[kind] + sin(t * BOB_SPD[kind] + ph) * BOB_AMP[kind]
				# spawn pop-in: elastic scale-up over the first 0.3 s (spec §4)
				var sc := 1.0
				var age: float = t - float(rec.get("born", t))
				if age < 0.3:
					var k := age / 0.3
					sc = 1.0 + 0.45 * sin(k * PI) * (1.0 - k) - 0.45 * k * (1.0 - k)
					sc = maxf(sc, 0.05)
					yy -= 0.5 * (1.0 - k)
				var basis: Basis
				if kind == 3:
					basis = Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))   # power ring stays level
				else:
					# fixed camera-facing lean: a real fruit silhouette (side
					# profile + stem/leaf) instead of a top-view circle
					basis = (Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), FRUIT_TILT)) \
						.scaled(Vector3(sc, sc, sc))
					yy += float(s["sink"])
				var vis := p + Vector3(0.0, yy, 0.0)
				rec["vis"] = vis
				mm.set_instance_transform(idx, Transform3D(basis, vis))
	# trickle respawn (top: 1 per frame) — also respects the global budget.
	# Only consume the deficit when a valid spot was actually found; otherwise
	# the count could silently fall below the target forever.
	for kind in KIND_TARGETS.size():
		if _deficit[kind] > 0 and _total < hard_cap and not qa_freeze_respawn:
			if _spawn_orb(kind):
				_deficit[kind] -= 1
			break

# ---------------------------------------------------------------- fruit meshes
# Fruits use the LowPolyFoodPack models (user-provided OBJ, flat colors) when
# available, normalized to gameplay size with our vivid color-coding + emission
# so each kind stays readable at distance; procedural builders are no longer
# needed — the pack carries every variant. Each final mesh = model surfaces +
# ground shadow blob → ONE mesh.

func _real_fruit_mesh(path: String, height: float, emit: float, surface_map: Dictionary, kind: int) -> Mesh:
	var src: Mesh = load(path) as Mesh
	var am := ArrayMesh.new()
	if src == null:
		push_warning("Food model missing: %s — packing empty mesh" % path)
		return am
	# Dark Theme / 2D mode: a modest emissive lift keeps fruit edge-readable
	# on the darkened courts — but heavy glow washes the models flat, so the
	# saturations stay low and readability comes from the (now bigger) shape.
	var emit_b := emit * (0.55 if dark_theme else (0.38 if mode_2d else 0.0))
	var bb := src.get_aabb()
	var sc: float = height / maxf(bb.size.y, 0.001)
	var lift: float = -bb.position.y * sc
	for i in src.get_surface_count():
		var nm: String = ""
		if src is ArrayMesh:
			nm = (src as ArrayMesh).surface_get_name(i)
		var st := SurfaceTool.new()
		st.append_from(src, i, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), Vector3(0.0, lift, 0.0)))
		if nm.contains("leaf"):
			st.set_material(_leaf_mat())
		elif nm.contains("trunk") or nm.contains("stalk") or nm.contains("stem"):
			st.set_material(_stem_mat())
		elif surface_map.has(nm):
			st.set_material(_mapped_mat(surface_map[nm]))
		else:
			st.set_material(_fruit_base_mat(KIND_COLORS[kind], emit_b, 0.52))
		st.commit(am)
	# rare / golden fruit sit in a soft additive glow halo so they read as
	# special pickups from the top-down camera (spec §4)
	if kind >= 1:
		var sh := SurfaceTool.new()
		var halo := _halo_surface(KIND_COLORS[kind])
		sh.append_from(halo, 0, Transform3D(Basis(), Vector3(0.0, 0.02, 0.0)))
		sh.set_material(halo.material)
		sh.commit(am)
	# produce shapes without a leaf/stem surface in the OBJ get a tiny top
	# stem + leaf so the top-down silhouette still says "fruit" (an apple from
	# directly above is otherwise just a red circle)
	if src is ArrayMesh:
		var lm := src as ArrayMesh
		var shaped := false
		for i in lm.get_surface_count():
			var snm := lm.surface_get_name(i)
			if snm.contains("leaf") or snm.contains("stem") or snm.contains("rind"):
				shaped = true
				break
		if not shaped:
			_append_top_leaf(am, height)
	var sbl := SurfaceTool.new()
	_blob_surface(sbl)
	sbl.commit(am)
	return am

func _append_top_leaf(am: ArrayMesh, height: float) -> void:
	var stem := CylinderMesh.new()
	stem.top_radius = 0.012
	stem.bottom_radius = 0.028
	stem.height = height * 0.10
	var st := SurfaceTool.new()
	st.append_from(stem, 0, Transform3D(Basis(), Vector3(0.0, height - stem.height * 0.42, 0.0)))
	st.set_material(_stem_mat())
	st.commit(am)
	var leaf := PlaneMesh.new()
	leaf.size = Vector2(height * 0.26, height * 0.13)
	var st2 := SurfaceTool.new()
	var tb := Basis(Vector3(1, 0, 0), -0.14) * Basis(Vector3(0, 1, 0), 0.5)
	st2.append_from(leaf, 0, Transform3D(tb, Vector3(height * 0.10, height - stem.height * 0.80, height * 0.04)))
	st2.set_material(_leaf_mat())
	st2.commit(am)

func _halo_surface(tint: Color) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.7, 1.7)
	q.orientation = PlaneMesh.FACE_Y
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(tint.r, tint.g, tint.b, 0.5), Color(tint.r, tint.g, tint.b, 0.22), Color(tint.r, tint.g, tint.b, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = tex
	m.albedo_color = tint
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	return q

func _mapped_mat(name_key: String) -> StandardMaterial3D:
	var col: Color = SURFACE_COLORS.get(name_key, Color(0.8, 0.8, 0.8))
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.5
	if name_key == "fruit_inner":
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.25
	return m

func _power_mesh() -> Mesh:
	# power orb: bright emissive core + spinning cyan ring + shadow blob
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	var core := SphereMesh.new()
	core.radius = 0.16
	core.height = 0.32
	core.radial_segments = 12
	core.rings = 8
	st.append_from(core, 0, Transform3D())
	st.set_material(_fruit_base_mat(Color(0.82, 0.99, 1.0), 1.5, 0.2))
	st.commit(am)
	var sr := SurfaceTool.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.28
	ring.rings = 22
	ring.ring_segments = 8
	sr.append_from(ring, 0, Transform3D())
	sr.set_material(_fruit_base_mat(Color(0.42, 0.92, 1.0), 1.0, 0.25))
	sr.commit(am)
	var sbl := SurfaceTool.new()
	_blob_surface(sbl)
	sbl.commit(am)
	return am

func _fruit_base_mat(albedo: Color, emit: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.emission_enabled = emit > 0.0
	if emit > 0.0:
		m.emission = albedo
		m.emission_energy_multiplier = emit
	if dark_theme or mode_2d:
		m.rim_enabled = true
		m.rim = 0.22
		m.rim_tint = 0.6
	return m

func _stem_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.21, 0.11)
	m.roughness = 0.92
	if dark_theme or mode_2d:
		m.rim_enabled = true
		m.rim = 0.35
		m.rim_tint = 0.6
	return m

func _leaf_mat(bright: Color = Color(0.26, 0.52, 0.18)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = bright
	m.roughness = 0.68
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = bright
	m.emission_energy_multiplier = 0.18
	return m

func _blob_surface(st: SurfaceTool) -> void:
	# soft contact shadow: small dark quad under the fruit
	var q := _blob_mesh()
	st.append_from(q, 0, Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)))
	st.set_material(q.material)

func _blob_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.95, 0.95)
	q.orientation = PlaneMesh.FACE_Y
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.38), Color(0, 0, 0, 0.16), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	q.material = m
	return q
