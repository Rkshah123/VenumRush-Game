class_name FoodSpawner
extends Node3D
## Collectible orbs (basic / rare / golden) + consumed-death drops.
## All visuals procedural: emissive sphere + additive billboard halo (free license).

const KIND_TARGETS := [46, 7, 3]
const KIND_GROWTH := [0.5, 0.95, 1.4]
const KIND_SCORE := [10, 30, 75]
const KIND_COLORS := [Color(0.2, 0.95, 0.75), Color(0.75, 0.35, 1.0), Color(1.0, 0.82, 0.28)]
const KIND_RADIUS := [0.3, 0.34, 0.4]

var arena_radius := 55.0
var obstacles: Array = []
var active := true

var _orbs: Array = []      # {node, halo, kind, pos: Vector3, alive: bool, phase}
var _deficit := [0, 0, 0]
var _halo_tex: GradientTexture2D
var _sphere := SphereMesh.new()
var _quad := QuadMesh.new()

func _ready() -> void:
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 14
	_sphere.rings = 8
	_quad.size = Vector2(2, 2)

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	_halo_tex = GradientTexture2D.new()
	_halo_tex.gradient = g
	_halo_tex.width = 64
	_halo_tex.height = 64
	_halo_tex.fill = GradientTexture2D.FILL_RADIAL
	_halo_tex.fill_from = Vector2(0.5, 0.5)
	_halo_tex.fill_to = Vector2(1.0, 0.5)

func reset() -> void:
	for o in _orbs:
		var node = o["node"]
		if is_instance_valid(node):
			node.queue_free()
	_orbs.clear()
	_deficit = [0, 0, 0]
	for kind in 3:
		for i in KIND_TARGETS[kind]:
			_spawn_orb(kind)

func _spawn_orb(kind: int, at: Vector3 = Vector3.INF) -> void:
	var r: float = KIND_RADIUS[kind]
	var pos := at
	if pos == Vector3.INF:
		for attempt in 5:
			var ang := randf() * TAU
			var rad := sqrt(randf()) * (arena_radius - 4.0)
			pos = Vector3(sin(ang) * rad, 0, cos(ang) * rad)
			if _clear_of_obstacles(pos, r):
				break

	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var m := MeshInstance3D.new()
	var s := _sphere.duplicate() as SphereMesh
	s.radius = r
	s.height = r * 2.0
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = KIND_COLORS[kind]
	mat.emission_enabled = true
	mat.emission = KIND_COLORS[kind]
	mat.emission_energy_multiplier = 1.5 + kind * 0.4
	mat.roughness = 0.3
	m.material_override = mat
	root.add_child(m)

	var halo := MeshInstance3D.new()
	var q := _quad.duplicate() as QuadMesh
	q.size = Vector2(r * 4.2, r * 4.2)
	halo.mesh = q
	var hmat := StandardMaterial3D.new()
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hmat.billboard_keep_scale = true
	hmat.albedo_texture = _halo_tex
	hmat.albedo_color = Color(KIND_COLORS[kind], 0.55)
	hmat.no_depth_test = false
	halo.material_override = hmat
	halo.position.y = r * 1.4
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)

	_orbs.append({"node": root, "kind": kind, "pos": pos, "alive": true, "phase": randf() * TAU, "mesh": m})

func _clear_of_obstacles(pos: Vector3, r: float) -> bool:
	for ob in obstacles:
		if pos.distance_to(ob["pos"]) < (float(ob["r"]) + r + 1.5):
			return false
	return true

func alive_positions() -> Array:
	var out: Array = []
	out.resize(_orbs.size())
	var i := 0
	for o in _orbs:
		out[i] = (o as Dictionary)["pos"]
		i += 1
	return out

func remove_orb_by_index(i: int) -> void:
	var o: Dictionary = _orbs[i]
	o["alive"] = false
	var node: Node3D = o["node"]
	if is_instance_valid(node):
		node.queue_free()
	_deficit[o["kind"]] += 1
	_orbs.remove_at(i)
	pop_at(o["pos"], KIND_COLORS[o["kind"]])

func pop_at(pos: Vector3, color: Color) -> void:
	# tiny consumed pop
	var pop := Node3D.new()
	pop.position = pos + Vector3.UP * 0.4
	add_child(pop)
	var m := MeshInstance3D.new()
	m.mesh = _sphere.duplicate() as SphereMesh
	m.scale = Vector3(0.3, 0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	pop.add_child(m)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(0.9, 0.9, 0.9), 0.18)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.chain().tween_callback(pop.queue_free)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for o in _orbs:
		var node: Node3D = o["node"]
		if not is_instance_valid(node):
			continue
		var ph: float = o["phase"]
		node.position.y = 0.55 + sin(t * 2.0 + ph) * 0.09
		node.rotation.y += delta * (1.1 + ph * 0.05)
	# trickle respawn (1 per frame max, staggered)
	for kind in 3:
		if _deficit[kind] > 0:
			_deficit[kind] -= 1
			_spawn_orb(kind)
			break
