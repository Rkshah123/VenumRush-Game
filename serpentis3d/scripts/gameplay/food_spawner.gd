class_name FoodSpawner
extends Node3D
## Collectible REAL FOOD (basic / rare / golden) + power orbs + fallen-snake
## drops (spec §5). Each kind carries SEVERAL real-food variants chosen randomly
## per spawn (fruits AND snack foods: apple / burger / sushi / donut …), so the
## court always shows variety while every kind keeps its score/growth identity.
## All variants render through SHARED per-variant MultiMeshes (one draw call
## each) with per-slot transforms updated in _process — cheap on any device.
##
## 3D mode renders the textured low-poly models; 2D top-down mode renders the
## matching polished flat-sprite ICON of the same food (a dedicated unshaded
## ground-aligned quad — crisp, always readable, no artificial tint).
##
## Eating animation (spec §4): the eaten food FLYS INTO the snake's mouth
## (eased flight + spin + smooth shrink), then a sparkle burst pops where the
## bite landed. Growth/score stay handled by MatchWorld (counted once).

const KIND_TARGETS := [100, 10, 6, 3]
const KIND_TARGETS_MOBILE := [64, 7, 4, 2]
const KIND_GROWTH := [0.5, 0.95, 1.4, 0.4]
const KIND_SCORE := [10, 30, 75, 15]
const KIND_COLORS := [Color(0.92, 0.16, 0.12), Color(0.55, 0.25, 0.75), Color(1.0, 0.78, 0.25), Color(0.42, 0.92, 1.0)]
const KIND_RADIUS := [0.3, 0.34, 0.4, 0.35]

# absolute food budget — death drops respect this cap. Phones keep a leaner
# court (see _ready): fewer alive orbs means a smaller eat-check/hash and
# MultiMesh churn every tick. 200 ≈ targets (119) + massed death drops.
const HARD_CAP := 200
const MOBILE_HARD_CAP := 132

## --- S/M/L size tiers -------------------------------------------------------
## Every real-food orb rolls a tier on spawn: SMALL / MEDIUM / LARGE. The tier
## multiplies the variant's VISUAL scale, its growth reward and its score
## TOGETHER, so a large cake always looks like the bigger snack it is and a
## small egg never feeds more than a golden burger. Kind 3 (power orbs) is
## exempt — it grants an ability, not mass.
const TIER_SCALE := [0.80, 1.15, 1.50]   # visual scale of sprite / model
const TIER_GROW := [0.70, 1.00, 1.75]    # × the kind's growth value
const TIER_SCORE := [0.7, 1.0, 2.0]      # × the kind's score value
const TIER_NAMES := ["S", "M", "L"]
const TIER_WEIGHTS := [0.55, 0.35, 0.10]        # natural court mix (sums to 1)
const DROP_TIER_WEIGHTS := [0.18, 0.44, 0.38]   # death drops favor meaty tiers
const FRUIT_TILT := 0.60  # ~34° camera-facing lean: silhouette readable top-down
const BOB_BASE := [0.34, 0.34, 0.34, 0.52]
const BOB_AMP := [0.07, 0.07, 0.07, 0.13]
const BOB_SPD := [2.0, 2.0, 2.0, 3.4]
const FLY_TIME := 0.18  # min seconds of the eat-flight into the mouth
const FLY_TIME_MAX := 0.55
const SPAWN_EDGE := 4.5   # keep food comfortably inside the death barrier
const FRUIT_GAP := 1.05   # minimum centre distance between two foods
var _bob_frame := 0       # transform-refresh counter for the throttled bob pass

# Natural per-surface colors for the models that ship flat colors. Named
# surfaces get a dedicated color; unmapped surfaces of "tint" variants keep the
# kind color coding, unmapped "keep" surfaces reuse the model's own material.
const SURFACE_COLORS := {
	"rind_green": Color(0.11, 0.44, 0.15),
	"rind_lime": Color(0.60, 0.77, 0.35),
	"seed_dark": Color(0.03, 0.03, 0.03),
	"fruit_inner": Color(0.95, 0.87, 0.55),
	"spore_light": Color(0.92, 0.90, 0.84),
	# --- burger ---
	"bun": Color(0.89, 0.62, 0.24),
	"bun_top": Color(0.96, 0.74, 0.34),
	"patty": Color(0.44, 0.22, 0.08),
	"cheese": Color(0.97, 0.71, 0.10),
	"lettuce": Color(0.28, 0.56, 0.09),
	"tomato": Color(0.88, 0.24, 0.10),
	"sesame": Color(0.93, 0.84, 0.72),
	# --- ice cream cone ---
	"cone": Color(0.87, 0.63, 0.32),
	"grabelt": Color(0.55, 0.90, 0.74),
	"mint": Color(0.72, 0.94, 0.82),
	"icing": Color(0.96, 0.92, 0.95),
	"cream": Color(0.97, 0.93, 0.90),
	# --- donut ---
	"dough": Color(0.88, 0.66, 0.38),
	"frosting_pink": Color(0.96, 0.52, 0.72),
	"frosting_choc": Color(0.38, 0.21, 0.10),
	"drizzle": Color(0.96, 0.93, 0.97),
	"choc_chip": Color(0.24, 0.13, 0.07),
	"sprinkle_r": Color(0.94, 0.30, 0.36),
	"sprinkle_g": Color(0.35, 0.86, 0.45),
	"sprinkle_b": Color(0.38, 0.62, 0.95),
	"sprinkle_y": Color(0.98, 0.86, 0.30),
	# --- cake / croissant / cupcake / cookie ---
	"sponge": Color(0.94, 0.80, 0.58),
	"straw_field": Color(0.90, 0.24, 0.28),
	"wrapper": Color(0.90, 0.84, 0.78),
	"cookie_dough": Color(0.90, 0.70, 0.42),
	"choc": Color(0.28, 0.15, 0.08),
	"crust": Color(0.87, 0.58, 0.28),
	"crust_dark": Color(0.68, 0.40, 0.16),
	# --- sushi / eggs / melon ---
	"nori": Color(0.08, 0.16, 0.11),
	"rice": Color(0.94, 0.93, 0.90),
	"salmon_flesh": Color(0.95, 0.48, 0.36),
	"cucumber_flesh": Color(0.82, 0.92, 0.55),
	"eggshell": Color(0.96, 0.95, 0.92),
	"egg_white": Color(0.97, 0.97, 0.95),
	"yolk": Color(0.98, 0.72, 0.10),
	# --- fruit bodies ---
	"pear_body": Color(0.74, 0.82, 0.28),
	"green_body": Color(0.62, 0.76, 0.26),
	"chip_dark": Color(0.18, 0.10, 0.05),
}

## Variant table per kind. Real foods: path + pool capacity + spawn weight +
## normalized size ("h" = normalized gameplay HEIGHT like the original 8, or
## "size" = the model's longest world dimension — natural for flat/huge shapes)
## + explicit collect radius "r" (collision matches the visible footprint)
## + emissive lift + 2D-icon sprite path. "surface_map" colors named surfaces;
## "keep_mat" (Kenney colormap-textured kit models) preserves the imported
## texture/material instead of flat tinting.
const VAR_TABLE := [
	# ------------------------------------------------------------- kind 0 — basic
	[
		{"path": "res://models/food/apple.obj", "cap": 110, "w": 0.20, "h": 0.98, "r": 0.30, "emit": 0.45,
			"sprite": "res://textures/food2d/apple.png"},
		{"path": "res://models/food/strawberry.obj", "cap": 70, "w": 0.13, "h": 0.82, "r": 0.30, "emit": 0.50,
			"leaf_top": true,
			"sprite": "res://textures/food2d/strawberry.png"},
		{"path": "res://models/food/watermelon_slice.obj", "cap": 70, "w": 0.13, "h": 0.85, "r": 0.30, "emit": 0.35,
			"surface_map": {"rind": "rind_green", "rindw": "rind_lime", "black": "seed_dark"},
			"sprite": "res://textures/food2d/watermelon.png"},
		{"path": "res://models/food/pear.obj", "cap": 55, "w": 0.10, "size": 0.95, "r": 0.36,
			"emit": 0.30, "surface_map": {"pear": "pear_body"},
			"sprite": "res://textures/food2d/pear.png"},
		{"path": "res://models/food_kit/orange.obj", "cap": 55, "w": 0.10, "size": 0.90, "r": 0.36,
			"emit": 0.25, "keep_mat": true, "leaf_top": true,
			"sprite": "res://textures/food2d/orange.png"},
		{"path": "res://models/food/donut.obj", "cap": 45, "w": 0.08, "size": 0.88, "r": 0.42,
			"emit": 0.35, "surface_map": {"dough": "dough", "icing": "frosting_pink", "white": "drizzle",
				"sprinkle1": "sprinkle_r", "sprinkle2": "sprinkle_g", "sprinkle3": "sprinkle_b"},
			"sprite": "res://textures/food2d/donut.png"},
		{"path": "res://models/food/cupcake.obj", "cap": 40, "w": 0.07, "size": 0.95, "r": 0.38,
			"emit": 0.40, "surface_map": {"paper": "wrapper", "icing": "frosting_pink", "apple": "straw_field",
				"white": "cream",
				"sprinkle1": "sprinkle_r", "sprinkle2": "sprinkle_g", "sprinkle3": "sprinkle_y"},
			"sprite": "res://textures/food2d/cupcake.png"},
		{"path": "res://models/food/cookie.obj", "cap": 40, "w": 0.07, "size": 0.70, "r": 0.30,
			"emit": 0.25, "surface_map": {"dough": "cookie_dough", "choc": "choc"},
			"sprite": "res://textures/food2d/cookie.png"},
		{"path": "res://models/food/croissant.obj", "cap": 50, "w": 0.08, "size": 1.00, "r": 0.38,
			"emit": 0.35, "surface_map": {"dough": "bun_top", "crust2": "crust_dark"},
			"sprite": "res://textures/food2d/croissant.png"},
	],
	# ------------------------------------------------------------- kind 1 — rare
	[
		{"path": "res://models/food/cherries.obj", "cap": 30, "w": 0.26, "h": 0.78, "r": 0.34, "emit": 0.55,
			"sprite": "res://textures/food2d/cherries.png"},
		{"path": "res://models/food/mushroom.obj", "cap": 20, "w": 0.15, "h": 0.75, "r": 0.34, "emit": 0.55,
			"surface_map": {"white": "spore_light"},
			"sprite": "res://textures/food2d/mushroom.png"},
		{"path": "res://models/food_kit/grapes.obj", "cap": 22, "w": 0.18, "size": 0.95, "r": 0.38,
			"emit": 0.45, "keep_mat": true,
			"sprite": "res://textures/food2d/grapes.png"},
		{"path": "res://models/food/sushi_maki.obj", "cap": 14, "w": 0.12, "size": 0.85, "r": 0.34,
			"emit": 0.30, "surface_map": {"nori": "nori", "rice": "rice", "salmon": "salmon_flesh",
				"cucumber": "cucumber_flesh"},
			"sprite": "res://textures/food2d/maki-salmon.png"},
		{"path": "res://models/food/egg.obj", "cap": 14, "w": 0.12, "size": 0.70, "r": 0.28,
			"emit": 0.30, "surface_map": {"eggshell": "eggshell"},
			"sprite": "res://textures/food2d/egg.png"},
		{"path": "res://models/food/fried_egg.obj", "cap": 20, "w": 0.17, "size": 0.80, "r": 0.34,
			"emit": 0.35, "surface_map": {"eggw": "egg_white", "yolk": "yolk"},
			"sprite": "res://textures/food2d/egg-cooked.png"},
	],
	# ------------------------------------------------------------ kind 2 — golden
	[
		{"path": "res://models/food/lemon.obj", "cap": 10, "w": 0.18, "h": 0.94, "r": 0.40, "emit": 0.60,
			"leaf_top": true,
			"sprite": "res://textures/food2d/lemon.png"},
		{"path": "res://models/food/banana.obj", "cap": 8, "w": 0.15, "h": 0.88, "r": 0.40, "emit": 0.60,
			"surface_map": {"banana2": "seed_dark", "seed": "fruit_inner"}, "leaf_top": true,
			"sprite": "res://textures/food2d/banana.png"},
		{"path": "res://models/food/carrot.obj", "cap": 8, "w": 0.13, "h": 1.05, "r": 0.40, "emit": 0.60,
			"leaf_top": true,
			"sprite": "res://textures/food2d/carrot.png"},
		{"path": "res://models/food_kit/pineapple.obj", "cap": 10, "w": 0.16, "size": 1.30, "r": 0.46,
			"emit": 0.35, "keep_mat": true,
			"sprite": "res://textures/food2d/pineapple.png"},
		{"path": "res://models/food/burger.obj", "cap": 10, "w": 0.15, "size": 1.05, "r": 0.48,
			"emit": 0.30, "surface_map": {"crust": "bun", "patty": "patty", "cheese": "cheese",
				"lettuce": "lettuce", "tomato": "tomato", "sesame": "sesame"},
			"sprite": "res://textures/food2d/burger.png"},
		{"path": "res://models/food/cake_slice.obj", "cap": 8, "w": 0.11, "size": 0.95, "r": 0.36,
			"emit": 0.40, "surface_map": {"sponge": "sponge", "cream": "cream", "straw": "straw_field"},
			"sprite": "res://textures/food2d/cake.png"},
		{"path": "res://models/food/ice_cream_cone.obj", "cap": 10, "w": 0.12, "size": 1.10, "r": 0.38,
			"emit": 0.45, "surface_map": {"cone": "cone", "mint": "mint", "icing": "icing"},
			"sprite": "res://textures/food2d/ice-cream-cne.png"},
	],
	# ---------------------------------------------------------- kind 3 — power orb
	[
		{"path": "", "cap": 8, "w": 1.0, "h": 0.6, "r": 0.35, "emit": 1.0, "power": true},
	],
]

var arena_radius := 56.0
var obstacles: Array = []     # [{pos, r}] for placement rejection
var dark_theme := false       # Dark Theme: brighter emissives + rim so food pops
var mode_2d := false          # 2D top-down mode: crisp flat-sprite icons

var _slots: Array = []        # per kind: Array of pool dicts {mm, free, alive, r, sprite}
var _var_caps: Array = []     # per kind: Array of capacities (deficit bookkeeping)
var _kind_r: Array = []       # per kind: max variant radius (death-drop clearance)
var _targets: Array = []      # effective per-kind alive targets (mobile-scaled)
var _total := 0
var _deficit: Array = []

var _pop_mesh: SphereMesh              # shared, pre-built: zero alloc per pop
var _pop_pool: Array = []              # [{node, mesh}] reused round-robin
var _pop_next := 0
var _pop_hits := 0

# --- food spatial grid (eat sweep acceleration) ------------------------------
# eat_hits_sweep used to test EVERY alive orb (~119-200) for EVERY living
# snake at 30 Hz. Now a coarse grid of passive orbs (rebuilt at ≤6.7 Hz)
# pre-filters the candidates; the per-orb sweep predicate itself is untouched
# and still exact. Entries carry [rec, kind, slot, idx]; a buried/flying orb
# is filtered by the LIVE alive-dict check, so the candidate set never uses
# stale positions.
const GRID_CELL := 3.0
const GRID_OFF := 128   # cell key offset: arena ±56 m → ±20 cells, plenty
var _grid := {}         # int cell key -> Array of [rec, kind, slot, idx]
var _grid_ms := -100000
var _gen := 0           # court mutation counter (spawn/bury/reset)
var _grid_gen := -1     # generation the grid was built from

func _grid_rebuild() -> void:
	_grid.clear()
	for kind in _slots.size():
		for s: Dictionary in _slots[kind]:
			var alive: Dictionary = s["alive"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if rec.has("fly"):
					continue
				var p: Vector3 = rec["pos"]
				var key := (int(floor(p.x / GRID_CELL)) + GRID_OFF) * 512 \
					+ (int(floor(p.z / GRID_CELL)) + GRID_OFF)
				if not _grid.has(key):
					_grid[key] = []
				(_grid[key] as Array).append([rec, kind, s, idx])
	_grid_ms = Time.get_ticks_msec()
	_grid_gen = _gen

# ---------------------------------------------------------------- lifecycle

var hard_cap := HARD_CAP   # effective budget; phones run a leaner one
var qa_freeze_respawn := false   # dev harness: isolate one eat case

func _ready() -> void:
	var mobile := OS.get_name() == "Android" or OS.get_name() == "iOS"
	hard_cap = MOBILE_HARD_CAP if mobile else HARD_CAP
	_targets = KIND_TARGETS_MOBILE if mobile else KIND_TARGETS
	for kind in VAR_TABLE.size():
		var pools: Array = []
		var caps: Array = []
		var rmax := 0.0
		for cfg: Dictionary in VAR_TABLE[kind]:
			pools.append(_make_pool(_variant_mesh(kind, cfg), int(cfg["cap"]), cfg))
			caps.append(int(cfg["cap"]))
			rmax = maxf(rmax, float(cfg.get("r", KIND_RADIUS[kind])))
		_slots.append(pools)
		_var_caps.append(caps)
		_kind_r.append(rmax)
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
	# scores and slots untouched) so the court always shows the right artwork
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
			# pool flags must follow the artwork: 2D icon pools never tilt
			# (no sink, no bob) while 3D pools keep the camera-facing lean
			pools[vi]["sprite"] = (not bool(cfg.get("power", false))) and mode_2d
			pools[vi]["sink"] = _pool_sink(mm.mesh)

func _variant_mesh(kind: int, cfg: Dictionary) -> Mesh:
	if bool(cfg.get("power", false)):
		return _power_mesh()
	if mode_2d and cfg.has("sprite"):
		var size := float(cfg.get("size", float(cfg.get("h", 0.9))))
		# 2D icons render at ×1.5: the flat sprite reads far too small next to
		# the chunky snake bodies under the fixed top-down camera, even though
		# the 3D model of the same food reads fine at its natural scale.
		size *= 1.5
		return _sprite_mesh(String(cfg["sprite"]), size, kind)
	return _real_fruit_mesh(kind, cfg)

func _pool_sink(mesh: Mesh) -> float:
	# camera-facing lean compensation: a tilted 3D food sinks one half into the
	# floor, so the spawn float gets the sink back (real silhouette from above)
	if mesh == null:
		return 0.0
	var bb := mesh.get_aabb()
	return sin(FRUIT_TILT) * bb.size.y * 0.5

func _make_pool(mesh: Mesh, cap: int, cfg: Dictionary) -> Dictionary:
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
	var sprite := (not bool(cfg.get("power", false))) and mode_2d
	# Flat 2D sprite icons never tilt — they carry no sink.
	var sink := 0.0
	if mesh != null and not sprite:
		var bb := mesh.get_aabb()
		sink = sin(FRUIT_TILT) * bb.size.y * 0.5
	return {"mm": mm, "free": free, "alive": {}, "sink": sink,
		"r": float(cfg.get("r", 0.35)), "sprite": sprite}

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
	_gen += 1
	_grid.clear()   # no stale rec references may survive a court reset
	_grid_ms = -100000
	_deficit = []
	_deficit.resize(_targets.size())
	for kind in _targets.size():
		_deficit[kind] = 0
		for i in _targets[kind]:
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
	for kind in _targets.size():
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

func drop_orb(kind: int, pos: Vector3, heads: Array = []) -> void:
	# Death drops ALWAYS appear: when the court sits at the hard cap, retire
	# one passive orb far from every living head (basic first → rare → golden)
	# and give its slot to the fresh drop. The old version silently dropped
	# nothing exactly when the court was busiest — a pile-up death.
	if _total >= hard_cap and not _evict_for_drop(heads):
		return
	# Death drops originate on a body station: keep them inside the playable
	# disc and push them out of boulders/trees. A food hidden INSIDE a rock is
	# the classic "left behind, cannot be eaten" report.
	var r: float = _kind_r[kind]
	var p := Vector3(pos.x, 0.0, pos.z).limit_length(arena_radius - SPAWN_EDGE)
	var drop_ok := _clear_of_obstacles(p, r)
	for attempt in 7:
		if drop_ok:
			break
		var inward := -p.normalized() if p.length_squared() > 0.01 else Vector3.FORWARD
		p += inward * 1.4
		p = p.limit_length(arena_radius - SPAWN_EDGE)
		drop_ok = _clear_of_obstacles(p, r)
	if not drop_ok:
		return
	_spawn_orb(kind, p, DROP_TIER_WEIGHTS)

## Free one court slot for a death drop: retire the FARTHEST passive orb of
## the lowest kinds first (small snacks go before golden loot), and never an
## orb close to a living head (that food is still playable). `heads` = living
## snakes' head positions.
func _evict_for_drop(heads: Array) -> bool:
	for kind in [0, 1, 2]:
		var best_s: Dictionary = {}
		var best_idx := -1
		var best_d := 2.0        # drop-clearance floor: nothing closer qualifies
		for s: Dictionary in _slots[kind]:
			var alive: Dictionary = s["alive"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if rec.has("fly"):
					continue
				var p: Vector3 = rec["pos"]
				var dmin := INF
				for h in heads:
					dmin = minf(dmin, p.distance_to(h))
				if dmin > best_d:
					best_d = dmin
					best_s = s
					best_idx = idx
		if best_idx >= 0:
			_bury_idx(best_s, best_idx, kind)
			return true
	return false

## Weighted tier roll from a weights array (entries sum to 1.0).
func _pick_tier(weights: Array) -> int:
	var roll := randf()
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if roll <= acc:
			return i
	return 1

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

func _spawn_orb(kind: int, at: Vector3 = Vector3.INF, tier_w: Array = TIER_WEIGHTS) -> bool:
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
	var r: float = s["r"]
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
	var rec := {
		"pos": pos, "phase": randf() * TAU, "kind": kind, "born": t_now(),
		"size": float(VAR_TABLE[kind][vi].get("size", float(VAR_TABLE[kind][vi].get("h", 0.9)))),
	}
	if kind < 3:
		# roll the S/M/L tier: visual scale, growth and score move TOGETHER so
		# the reward always matches what the orb visibly is
		var tier := _pick_tier(tier_w)
		var tscale: float = TIER_SCALE[tier]
		rec["tier"] = tier
		rec["scale"] = tscale
		rec["growth"] = float(KIND_GROWTH[kind]) * float(TIER_GROW[tier])
		rec["score"] = int(round(float(KIND_SCORE[kind]) * float(TIER_SCORE[tier])))
		rec["size"] = float(rec["size"]) * tscale
	(s["alive"] as Dictionary)[idx] = rec
	_total += 1
	_gen += 1
	return true

## Random disc sampling with a guaranteed-clear fallback scan. A rejected
## candidate never becomes food: every orb the player sees is on open ground,
## inside the arena, and separated from other orbs.
func _pick_spawn_pos(r: float) -> Vector3:
	var best := Vector3.INF
	var best_clear := -999.0
	for attempt in 22:
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
	for ring in 6:
		var rad: float = arena_radius * (0.20 + 0.125 * float(ring))
		var steps := 24 + ring * 8
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
## under food that was already on the ground. Re-check every passive orb
## against the NEW obstacles/arena and retire any that is now buried in a rock
## or outside the safe ring; the normal deficit logic respawns it on open
## ground. Flying food is already claimed and is left alone.
func revalidate_spawns() -> void:
	for kind in _slots.size():
		for s: Dictionary in _slots[kind]:
			var alive: Dictionary = s["alive"]
			var pr: float = s["r"]
			for idx in alive.keys():
				var rec: Dictionary = alive[idx]
				if rec.has("fly"):
					continue
				var pos: Vector3 = rec["pos"]
				if pos.length() > arena_radius - SPAWN_EDGE \
						or not _clear_of_obstacles(pos, pr):
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

## All edible foods whose GROUND position is within `reach` of the swept
## segment from -> to (the snake's mouth at the previous/current eat tick).
## Sweeping is what lets a fast head (and a 30 Hz eat tick) collect every food
## it visibly crosses. Returns the actual pool records: MatchWorld hands them
## straight back to fly_rec(), so there is no position lookup that could pick
## the wrong orb or double-count one. Reach scales with each variant's OWN
## collect radius (and an orb's S/M/L tier scale), so big burgers are
## gatherable around their full footprint and tiny eggs still need a real
## mouth contact. A coarse spatial grid pre-filters candidates (O(court) scan
## → only nearby cells); every surviving candidate is then tested with the
## EXACT same swept-distance predicate as before, and validated against the
## live pool, so the result set is identical.
func eat_hits_sweep(from: Vector3, to: Vector3, reach: float) -> Array:
	if Time.get_ticks_msec() - _grid_ms > 150 or _gen != _grid_gen:
		_grid_rebuild()
	var out: Array = []
	var sx := to.x - from.x
	var sz := to.z - from.z
	var seg_len2 := sx * sx + sz * sz
	# padded AABB of the segment in cell space: orbs in these cells can be
	# within reach; everything outside this box can never pass the test
	var pad := reach + 0.85
	var cx0 := int(floor((minf(from.x, to.x) - pad) / GRID_CELL))
	var cx1 := int(floor((maxf(from.x, to.x) + pad) / GRID_CELL))
	var cz0 := int(floor((minf(from.z, to.z) - pad) / GRID_CELL))
	var cz1 := int(floor((maxf(from.z, to.z) + pad) / GRID_CELL))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var cell: Array = _grid.get((cx + GRID_OFF) * 512 + (cz + GRID_OFF), [])
			for cand in cell:
				var rec: Dictionary = cand[0]
				var kind: int = cand[1]
				var s: Dictionary = cand[2]
				# live validation: bury/bury-flight between rebuilds must not
				# resurrect a claimed orb; identity match also guards against
				# a slot idx being RECYCLED to a new orb between rebuilds
				if rec.has("fly") or (s["alive"] as Dictionary).get(cand[3]) != rec:
					continue
				var p: Vector3 = rec["pos"]
				var sr: float = float(s["r"])
				var rr: float = reach + float(kind) * 0.03 + sr * 0.5 \
					+ (float(rec.get("scale", 1.0)) - 1.0) * sr * 0.5
				var rr2 := rr * rr
				var qx := from.x
				var qz := from.z
				if seg_len2 > 0.000001:
					var t := clampf(((p.x - from.x) * sx + (p.z - from.z) * sz) / seg_len2, 0.0, 1.0)
					qx = from.x + sx * t
					qz = from.z + sz * t
				# Degenerate segment (a freshly spawned/settled mouth): test the
				# POINT from, never each orb against itself.
				var dx := p.x - qx
				var dz := p.z - qz
				if dx * dx + dz * dz < rr2:
					out.append({"rec": rec, "pos": p, "kind": kind})
	return out

func remove_orb_at_pos(kind: int, pos: Vector3) -> bool:
	# removes ONE orb of this kind at pos (kept for dev tooling).
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
## flight starts at the orb's current rendered position and ends at the
## eater's live mouth, so the hand-off is seamless (no "food teleports to a
## point above the head" artefact) and the bite happens where the player sees
## it. Bigger food flies slower and stays readable the whole way in.
func fly_rec(rec: Dictionary, eater: Node3D) -> bool:
	if rec.has("fly"):
		return false
	var kind := int(rec["kind"])
	var from: Vector3 = rec.get("vis", (rec["pos"] as Vector3) + Vector3.UP * (BOB_BASE[kind] + 0.18))
	var dur := clampf(from.distance_to(_mouth_of(eater)) * 0.085 + float(rec.get("size", 0.9)) * 0.045, FLY_TIME, FLY_TIME_MAX)
	rec["fly"] = {"t": 0.0, "from": from, "snake": eater,
		"start_ms": Time.get_ticks_msec(), "dur": dur}
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
	_gen += 1

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
	# per-frame MultiMesh churn (≈119 instances) to a third on weak devices.
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
					# hold full size while it is visibly flying, shrink into the jaws
					var sc := float(rec.get("scale", 1.0)) * (1.0 - 0.92 * smoothstep(0.55, 1.0, q))
					mm.set_instance_transform(idx, Transform3D(
						Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), p))
					if q >= 1.0:
						_bury_idx(s, idx, kind)
						pop_at(target - Vector3.UP * 0.16, kind)
						# visible gulp AFTER the orb lands, not on first touch
						if snake.has_method("swallow"):
							snake.swallow(float(rec.get("size", 0.9)))
					continue
				if not bob_tick:
					continue   # passive orb: transform refresh at the throttled rate
				var ph: float = rec["phase"]
				var p: Vector3 = rec["pos"]
				var yaw := sin(t * 0.7 + ph) * 0.28 + (t * 2.2 if kind == 3 else 0.0)
				# S/M/L tier scale: the orb's real size lives here, on top of
				# the variant mesh's own baked scale
				var sc := float(rec.get("scale", 1.0))
				var age: float = t - float(rec.get("born", t))
				# spawn pop-in: elastic scale-up over the first 0.3 s (spec §4)
				var yy: float
				if bool(s["sprite"]):
					# 2D icon sprites lie FLAT on the court: no tilt, no sink,
					# no bob — the shadow stays glued to the ground and the
					# icon is always fully readable from the top-down camera.
					yy = 0.0
					if age < 0.3:
						var k := age / 0.3
						sc += sc * 0.45 * sin(k * PI) * (1.0 - k) - sc * 0.45 * k * (1.0 - k)
						sc = maxf(sc, 0.05)
					var vis := p + Vector3(0.0, 0.16, 0.0)
					rec["vis"] = vis
					mm.set_instance_transform(idx, Transform3D(
						Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), vis))
				else:
					# 3D model: fixed camera-facing lean (side profile + stem)
					basis3d(p, kind, ph, yaw, sc, age, s, idx, t, rec, mm)
	# trickle respawn (top: 1 per frame) — also respects the global budget.
	# Only consume the deficit when a valid spot was actually found; otherwise
	# the count could silently fall below the target forever.
	for kind in _targets.size():
		if _deficit[kind] > 0 and _total < hard_cap and not qa_freeze_respawn:
			if _spawn_orb(kind):
				_deficit[kind] -= 1
			break

func basis3d(p: Vector3, kind: int, ph: float, yaw: float, sc: float, age: float, pool: Dictionary, idx: int, t: float, rec: Dictionary, mm: MultiMesh) -> void:
	var yy: float = BOB_BASE[kind] + sin(t * BOB_SPD[kind] + ph) * BOB_AMP[kind]
	if age < 0.3:
		var k := age / 0.3
		sc += sc * 0.45 * sin(k * PI) * (1.0 - k) - sc * 0.45 * k * (1.0 - k)
		sc = maxf(sc, 0.05)
		yy -= 0.5 * (1.0 - k)
	var basis: Basis
	if kind == 3:
		basis = Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))   # power ring stays level
	else:
		# fixed camera-facing lean: a real food silhouette (side profile +
		# stem/leaf) instead of a top-view circle
		basis = (Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), FRUIT_TILT)) \
			.scaled(Vector3(sc, sc, sc))
		yy += float(pool["sink"])
	var vis := p + Vector3(0.0, yy, 0.0)
	rec["vis"] = vis
	mm.set_instance_transform(idx, Transform3D(basis, vis))

# ---------------------------------------------------------------- food meshes
# Foods use the user-provided low-poly packs (LowPolyFoodPack OBJ variants and
# the colormap-textured Kenney kit models), normalized to natural gameplay
# size. Each final mesh = model surfaces (+ halo for rare/golden) + ground
# shadow blob → ONE mesh, so the whole court is a handful of draw calls.
# 2D top-down mode instead draws the matching polished ICON sprite.

func _food_scale(aabb: AABB, cfg: Dictionary) -> float:
	# "h": the ORIGINAL height-normalized code path for the classic 8 variants
	# (pixel-identical scale to v1.1). "size": upscale the LONGEST AABB
	# dimension to the target — proportional shapes for flat cookies/donuts and
	# tall pineapples alike; base stays glued to y=0 (lift below).
	if not cfg.has("size"):
		return float(cfg["h"]) / maxf(aabb.size.y, 0.001)
	return float(cfg["size"]) / maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)

func _real_fruit_mesh(kind: int, cfg: Dictionary) -> Mesh:
	var path := String(cfg["path"])
	var keep := bool(cfg.get("keep_mat", false))
	var src: Mesh = load(path) as Mesh
	var am := ArrayMesh.new()
	if src == null:
		push_warning("Food model missing: %s — packing empty mesh" % path)
		return am
	# Dark Theme / 2D mode: a modest emissive lift keeps food edge-readable
	# on the darkened courts — but heavy glow washes the models flat, so the
	# saturations stay low and readability comes from the (bigger) silhouette.
	var emit: float = float(cfg.get("emit", 0.4))
	var emit_b := emit * (0.55 if dark_theme else (0.38 if mode_2d else 0.0))
	var bb := src.get_aabb()
	var sc: float = _food_scale(bb, cfg)
	var lift: float = -bb.position.y * sc
	var surface_map: Dictionary = cfg.get("surface_map", {})
	for i in src.get_surface_count():
		var nm: String = ""
		if src is ArrayMesh:
			nm = (src as ArrayMesh).surface_get_name(i)
		var st := SurfaceTool.new()
		st.append_from(src, i, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), Vector3(0.0, lift, 0.0)))
		if keep:
			# colormap-textured kit models: keep the imported texture material
			# (duplicate so per-theme rim edits never leak into other users)
			st.set_material(_import_mat(src.surface_get_material(i), emit_b))
		elif nm.contains("leaf"):
			st.set_material(_leaf_mat())
		elif nm.contains("trunk") or nm.contains("stalk") or nm.contains("stem"):
			st.set_material(_stem_mat())
		elif surface_map.has(nm):
			st.set_material(_mapped_mat(surface_map[nm]))
		else:
			st.set_material(_fruit_base_mat(KIND_COLORS[kind], emit_b, 0.52))
		st.commit(am)
	# rare / golden food sits in a soft additive glow halo so it reads as a
	# special pickup from the top-down camera (spec §4)
	if kind >= 1:
		var halo_r := 1.35 + float(cfg.get("size", 0.0)) * 0.45
		var sh := SurfaceTool.new()
		var halo := _halo_surface(KIND_COLORS[kind], halo_r)
		sh.append_from(halo, 0, Transform3D(Basis(), Vector3(0.0, 0.02, 0.0)))
		sh.set_material(halo.material)
		sh.commit(am)
	# round fruits without their own stem/leaf geometry get a tiny top stem +
	# leaf so the top-down silhouette still says "fruit" (a lemon from directly
	# above is otherwise just a yellow circle). Snack foods (burger / sushi /
	# donut…) and models that bake in their own details never get one — the
	# variant's "leaf_top" flag preserves v1.1's auto-leaf sets exactly.
	if bool(cfg.get("leaf_top", false)):
		_append_top_leaf(am, _target_height(cfg))
	var sbl := SurfaceTool.new()
	_blob_surface(sbl, _target_height(cfg))
	sbl.commit(am)
	return am

func _target_height(cfg: Dictionary) -> float:
	var src: Mesh = load(String(cfg["path"])) as Mesh
	if src == null:
		return float(cfg.get("h", float(cfg.get("size", 0.9))))
	var bb := src.get_aabb()
	return bb.size.y * _food_scale(bb, cfg)

func _append_top_leaf(am: ArrayMesh, height: float) -> void:
	if height <= 0.02:
		return
	var stem := CylinderMesh.new()
	stem.top_radius = 0.012
	stem.bottom_radius = 0.028
	stem.height = maxf(height * 0.10, 0.03)
	var st := SurfaceTool.new()
	st.append_from(stem, 0, Transform3D(Basis(), Vector3(0.0, height - stem.height * 0.42, 0.0)))
	st.set_material(_stem_mat())
	st.commit(am)
	var leaf := PlaneMesh.new()
	leaf.size = Vector2(height * 0.26 + 0.05, height * 0.13 + 0.03)
	var st2 := SurfaceTool.new()
	var tb := Basis(Vector3(1, 0, 0), -0.14) * Basis(Vector3(0, 1, 0), 0.5)
	st2.append_from(leaf, 0, Transform3D(tb, Vector3(height * 0.10, height - stem.height * 0.80, height * 0.04)))
	st2.set_material(_leaf_mat())
	st2.commit(am)

## 2D top-down icon sprite: a polished flat image of the exact food, drawn as
## an unshaded ground-aligned quad (screen-up stays image-up), with the same
## rarity halo + soft contact shadow baked around it. Alpha-scissor keeps it
## crisp and blend order-safe on any arena.
func _sprite_mesh(path: String, size: float, kind: int) -> Mesh:
	var am := ArrayMesh.new()
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		push_warning("Food sprite missing: %s — packing empty mesh" % path)
		return am
	var img: Image = tex.get_image()
	var px := img.get_size()
	var aspect := px.x / maxf(float(px.y), 1.0)
	var wd := size
	var ln := size
	if aspect >= 1.0:
		ln = size / aspect
	else:
		wd = size * aspect
	var q := QuadMesh.new()
	q.size = Vector2(wd, ln)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if dark_theme:
		m.albedo_color = Color(0.94, 0.93, 0.92)  # soft lift against dark courts
	q.material = m
	var st := SurfaceTool.new()
	# rarity halo + contact shadow under the icon, then the icon itself top
	if kind >= 1:
		var halo_r := (maxf(wd, ln) * 1.05 + 0.45)
		var halo := _halo_surface(KIND_COLORS[kind], halo_r)
		st.append_from(halo, 0, Transform3D(Basis(), Vector3(0.0, 0.014, 0.0)))
		st.set_material(halo.material)
		st.commit(am)
	var stl := SurfaceTool.new()
	_blob_surface(stl, maxf(wd, ln), 0.010)
	stl.commit(am)
	var stq := SurfaceTool.new()
	stq.append_from(q, 0, Transform3D(Basis(), Vector3(0.0, 0.022, 0.0)))
	stq.set_material(q.material)
	stq.commit(am)
	return am

func _halo_surface(tint: Color, radius: float = 1.7) -> QuadMesh:
	var q := QuadMesh.new()
	var sz := radius
	q.size = Vector2(sz, sz)
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

## Reuse an IMPORTED model material (Kenney colormap kit / LowPack MTL colors):
## preserve the natural look, add a light emission lift in dark/2D, and a rim
## edge so textured food stays readable on dark courts.
func _import_mat(base: Material, emit_lift: float) -> StandardMaterial3D:
	var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
	if emit_lift > 0.0:
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = clampf(emit_lift * 0.5, 0.15, 0.6)
	if dark_theme or mode_2d:
		m.rim_enabled = true
		m.rim = 0.30
		m.rim_tint = 0.55
	m.roughness = minf(m.roughness, 0.72) if m.roughness > 0.0 else 0.55
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
	_blob_surface(sbl, 0.5)
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

func _blob_surface(st: SurfaceTool, height: float, at_y: float = 0.03) -> void:
	# soft contact shadow: a dark quad under the food, sized to its footprint
	var q := _blob_mesh(maxf(minf(maxf(height, 0.35), 1.75), 0.6))
	st.append_from(q, 0, Transform3D(Basis(), Vector3(0.0, at_y, 0.0)))
	st.set_material(q.material)

func _blob_mesh(spread: float = 0.95) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(spread, spread)
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
