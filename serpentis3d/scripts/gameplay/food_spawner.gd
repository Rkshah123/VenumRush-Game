class_name FoodSpawner
extends Node3D
## Collectible REAL FRUITS (basic / rare / golden) + fallen-snake drops.
## basic = apple, rare = wild berry cluster, golden = golden mango.
## All fruits render through SHARED MultiMeshes (3 draw calls total) with
## per-slot transforms updated in _process (bob + sway). This keeps the
## draw-call count tiny on integrated GPUs regardless of fruit count.
##
## Slot layout per kind (pool capacity, includes death-drop head-room):
##   apple pool 150, berries pool 30, mango pool 20  (sum >= HARD_CAP)

const KIND_TARGETS := [40, 6, 2]
const KIND_GROWTH := [0.5, 0.95, 1.4]
const KIND_SCORE := [10, 30, 75]
const KIND_COLORS := [Color(0.92, 0.16, 0.12), Color(0.55, 0.25, 0.75), Color(1.0, 0.78, 0.25)]
const KIND_RADIUS := [0.3, 0.34, 0.4]
const KIND_POOL := [150, 30, 20]
const HARD_CAP := 170   # absolute fruit budget — death drops respect this cap

var arena_radius := 55.0
var obstacles: Array = []
var active := true

var _slots: Array = []       # per kind: {mm, free: Array[int], alive: Array}
var _deficit := [0, 0, 0]
var _total := 0
var _pop_mesh: SphereMesh              # shared, pre-built: zero alloc per pop
var _pop_pool: Array = []              # [{node, mesh}] reused round-robin
var _pop_next := 0
var _pop_hits := 0

# ---------------------------------------------------------------- lifecycle

func _ready() -> void:
	_slots = [_make_pool(0, _apple_mesh()), _make_pool(1, _berries_mesh()), _make_pool(2, _mango_mesh())]
	_pop_mesh = SphereMesh.new()
	_pop_mesh.radius = 0.09
	_pop_mesh.height = 0.18
	_pop_mesh.radial_segments = 5
	_pop_mesh.rings = 3
	for i in 12:
		var pop := Node3D.new()
		pop.visible = false
		add_child(pop)
		var m := MeshInstance3D.new()
		m.mesh = _pop_mesh
		var pmat := StandardMaterial3D.new()   # per-node material → safe per-pop tween
		pmat.albedo_color = Color(KIND_COLORS[i % 3], 0.9)
		pmat.emission_enabled = true
		pmat.emission = KIND_COLORS[i % 3]
		pmat.emission_energy_multiplier = 1.8
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.material_override = pmat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pop.add_child(m)
		_pop_pool.append(pop)

func _make_pool(kind: int, mesh: Mesh) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var cap: int = KIND_POOL[kind]
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
	return {"mm": mm, "free": free, "alive": {}}

func reset() -> void:
	for s in _slots:
		var alive: Dictionary = s["alive"]
		var free: Array[int] = s["free"]
		var mm: MultiMesh = s["mm"]
		var bury := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0.0, -50.0, 0.0))
		for idx in alive.keys():
			mm.set_instance_transform(idx, bury)
			free.append(int(idx))
		alive.clear()
	_total = 0
	_deficit = [0, 0, 0]
	for kind in 3:
		for i in KIND_TARGETS[kind]:
			_spawn_orb(kind)

func count_alive() -> int:
	return _total

# ---------------------------------------------------------------- spawn/remove

func drop_orb(kind: int, pos: Vector3) -> void:
	if _total >= HARD_CAP:
		return
	_spawn_orb(kind, pos)

func _spawn_orb(kind: int, at: Vector3 = Vector3.INF) -> void:
	var s: Dictionary = _slots[kind]
	var free: Array[int] = s["free"]
	if free.is_empty():
		return
	var r: float = KIND_RADIUS[kind]
	var pos := at
	if pos == Vector3.INF:
		for attempt in 5:
			var ang := randf() * TAU
			var rad := sqrt(randf()) * (arena_radius - 4.0)
			pos = Vector3(sin(ang) * rad, 0, cos(ang) * rad)
			if _clear_of_obstacles(pos, r):
				break
	var idx: int = free.pop_back()
	(s["alive"] as Dictionary)[idx] = {"pos": pos, "phase": randf() * TAU, "kind": kind}
	_total += 1

func _clear_of_obstacles(pos: Vector3, r: float) -> bool:
	for ob in obstacles:
		if pos.distance_to(ob["pos"]) < (float(ob["r"]) + r + 1.5):
			return false
	return true

func alive_positions() -> Array:
	var out: Array = []
	for s in _slots:
		var alive: Dictionary = s["alive"]
		for idx in alive.keys():
			out.append((alive[idx] as Dictionary)["pos"])
	return out

func eat_hits(head_pos: Vector3, reach: float) -> Array:
	# All fruits in reach of a snake head: [{pos: Vector3, kind: int}]
	var out: Array = []
	for kind in 3:
		var alive: Dictionary = _slots[kind]["alive"]
		var rr: float = reach + float(kind) * 0.03 + KIND_RADIUS[kind] * 0.5
		for idx in alive.keys():
			var rec: Dictionary = alive[idx]
			var op: Vector3 = (rec["pos"] as Vector3) + Vector3.UP * 0.55
			if head_pos.distance_to(op) < rr:
				out.append({"pos": rec["pos"], "kind": kind})
	return out

func remove_orb_at_pos(kind: int, pos: Vector3) -> bool:
	# removes ONE fruit of this kind nearest/found at pos (match_world does
	# exact lookups; here we walk the kind's alive table)
	var s: Dictionary = _slots[kind]
	var alive: Dictionary = s["alive"]
	var free: Array[int] = s["free"]
	var mm: MultiMesh = s["mm"]
	for idx in alive.keys():
		var rec: Dictionary = alive[idx]
		if (rec["pos"] as Vector3).distance_squared_to(pos) < 0.02:
			alive.erase(idx)
			mm.set_instance_transform(idx, _bury())
			# remap: keep alive table tidy by reusing the slot later
			free.append(int(idx))
			_total -= 1
			_deficit[kind] += 1
			pop_at(pos, kind)
			return true
	return false

func _bury() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0.0, -50.0, 0.0))

func pop_at(pos: Vector3, kind: int) -> void:
	# reused pooled node: zero allocations, zero shader compilation churn
	if _pop_pool.is_empty():
		return
	var pop: Node3D = _pop_pool[_pop_next % _pop_pool.size()]
	_pop_next += 1
	_pop_hits += 1
	pop.position = pos + Vector3.UP * 0.4
	var m: MeshInstance3D = pop.get_child(0)
	var pm: StandardMaterial3D = m.material_override
	pm.albedo_color = Color(KIND_COLORS[kind], 0.9)
	pm.emission = KIND_COLORS[kind]
	m.scale = Vector3(0.5, 0.5, 0.5)
	pop.visible = true
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3(1.3, 1.3, 1.3), 0.16)
	tw.tween_property(pm, "albedo_color:a", 0.0, 0.16)
	tw.chain().tween_callback(func(): pop.visible = false)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for kind in 3:
		var s: Dictionary = _slots[kind]
		var alive: Dictionary = s["alive"]
		var mm: MultiMesh = s["mm"]
		for idx in alive.keys():
			var rec: Dictionary = alive[idx]
			var ph: float = rec["phase"]
			var p: Vector3 = rec["pos"]
			var yaw := sin(t * 0.7 + ph) * 0.28
			var yy := 0.34 + sin(t * 2.0 + ph) * 0.07
			var basis := Basis(Vector3.UP, yaw)
			mm.set_instance_transform(idx, Transform3D(basis, p + Vector3(0.0, yy, 0.0)))
	# trickle respawn (1 per frame top)
	for kind in 3:
		if _deficit[kind] > 0:
			_deficit[kind] -= 1
			_spawn_orb(kind)
			break

# ---------------------------------------------------------------- fruit meshes
# Each fruit merges: body + stem/leaf + ground shadow blob → ONE mesh, shared.

func _fruit_base_mat(albedo: Color, emit: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.emission_enabled = emit > 0.0
	if emit > 0.0:
		m.emission = albedo
		m.emission_energy_multiplier = emit
	return m

func _stem_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.21, 0.11)
	m.roughness = 0.92
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

func _apple_mesh() -> Mesh:
	var am := ArrayMesh.new()
	# body
	var sb := SurfaceTool.new()
	var body := SphereMesh.new()
	body.radius = 0.30
	body.height = 0.52
	body.radial_segments = 14
	body.rings = 9
	sb.append_from(body, 0, Transform3D())
	sb.set_material(_fruit_base_mat(Color(0.87, 0.13, 0.08), 0.35, 0.34))
	sb.commit(am)
	# stem + leaf
	var sbits := SurfaceTool.new()
	var stem := CylinderMesh.new()
	stem.top_radius = 0.016
	stem.bottom_radius = 0.024
	stem.height = 0.14
	stem.radial_segments = 6
	sbits.append_from(stem, 0, Transform3D(Basis(Vector3(0, 0, 1), 0.22), Vector3(0.0, 0.3, 0.02)))
	var leaf := PlaneMesh.new()
	leaf.size = Vector2(0.15, 0.085)
	var lb := Basis(Vector3(1, 0, 0), -0.35).rotated(Vector3.UP, 0.7)
	sbits.append_from(leaf, 0, Transform3D(lb, Vector3(0.09, 0.3, 0.03)))
	sbits.set_material(_leaf_mat())
	sbits.commit(am)
	# ground blob
	var sbl := SurfaceTool.new()
	_blob_surface(sbl)
	sbl.commit(am)
	return am

func _berries_mesh() -> Mesh:
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	var blob := SphereMesh.new()
	blob.radius = 0.115
	blob.height = 0.22
	blob.radial_segments = 9
	blob.rings = 6
	var stops := [Vector3(0, 0.16, 0), Vector3(0.105, 0.21, 0.05), Vector3(-0.075, 0.20, -0.06), Vector3(0.03, 0.24, -0.085)]
	for p in stops:
		st.append_from(blob, 0, Transform3D(Basis(), p))
	st.set_material(_fruit_base_mat(Color(0.42, 0.20, 0.62), 0.45, 0.3))
	st.commit(am)
	var ss := SurfaceTool.new()
	var stem := CylinderMesh.new()
	stem.top_radius = 0.014
	stem.bottom_radius = 0.02
	stem.height = 0.10
	stem.radial_segments = 6
	ss.append_from(stem, 0, Transform3D(Basis(), Vector3(0, 0.02, 0)))
	ss.set_material(_stem_mat())
	ss.commit(am)
	var sbl := SurfaceTool.new()
	_blob_surface(sbl)
	sbl.commit(am)
	return am

func _mango_mesh() -> Mesh:
	var am := ArrayMesh.new()
	var sb := SurfaceTool.new()
	var body := SphereMesh.new()
	body.radius = 0.24
	body.height = 0.5
	body.radial_segments = 14
	body.rings = 9
	var gently := Basis(Vector3(0, 0, 1), 0.55).scaled(Vector3(0.86, 1.07, 0.92))
	sb.append_from(body, 0, Transform3D(gently, Vector3(0.02, 0.28, 0)))
	sb.set_material(_fruit_base_mat(Color(1.0, 0.76, 0.16), 0.5, 0.42))
	sb.commit(am)
	var sl := SurfaceTool.new()
	var leaf := PlaneMesh.new()
	leaf.size = Vector2(0.16, 0.09)
	var lb := Basis(Vector3(1, 0, 0), -0.25).rotated(Vector3.UP, 2.1)
	sl.append_from(leaf, 0, Transform3D(lb, Vector3(-0.03, 0.5, 0.0)))
	sl.set_material(_leaf_mat(Color(0.32, 0.62, 0.2)))
	sl.commit(am)
	var sbl := SurfaceTool.new()
	_blob_surface(sbl)
	sbl.commit(am)
	return am
