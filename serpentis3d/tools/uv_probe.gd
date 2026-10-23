extends SceneTree
## QA: dump QuadMesh FACE_Y vertex/UV layout to verify sprite orientation
## in the 2D top-down view (spec: icons must read right-side-up in 2D).

func _init() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	q.orientation = PlaneMesh.FACE_Y
	var arrays := q.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	print("FACE_Y verts/uvs:")
	for i in verts.size():
		print("  v%s pos=(%.2f, %.2f, %.2f) uv=(%.2f, %.2f)" % [i, verts[i].x, verts[i].y, verts[i].z, uvs[i].x, uvs[i].y])
	# Also the FACE_Z default for comparison (fallback worlds)
	var q2 := QuadMesh.new()
	q2.size = Vector2(2.0, 2.0)
	var a2 := q2.get_mesh_arrays()
	var v2: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
	var u2: PackedVector2Array = a2[Mesh.ARRAY_TEX_UV]
	print("FACE_Z verts/uvs:")
	for i in v2.size():
		print("  v%s pos=(%.2f, %.2f, %.2f) uv=(%.2f, %.2f)" % [i, v2[i].x, v2[i].y, v2[i].z, u2[i].x, u2[i].y])
	quit(0)
