extends SceneTree
## one-off asset inspector: prints surface names + AABB of each food model.

func _init() -> void:
	var paths := [
		"res://models/food/apple.obj", "res://models/food/strawberry.obj",
		"res://models/food/watermelon_slice.obj", "res://models/food/cherries.obj",
		"res://models/food/mushroom.obj", "res://models/food/lemon.obj",
		"res://models/food/banana.obj", "res://models/food/carrot.obj",
		"res://models/food/burger.obj", "res://models/food/ice_cream_cone.obj",
		"res://models/food/donut.obj", "res://models/food/cupcake.obj",
		"res://models/food/cookie.obj", "res://models/food/croissant.obj",
		"res://models/food/cake_slice.obj", "res://models/food/sushi_maki.obj",
		"res://models/food/egg.obj", "res://models/food/fried_egg.obj",
		"res://models/food/pear.obj",
		"res://models/food_kit/orange.obj", "res://models/food_kit/grapes.obj",
		"res://models/food_kit/pineapple.obj",
	]
	for p: String in paths:
		var m: Mesh = load(p) as Mesh
		if m == null:
			print("DUMP_FAIL ", p)
			continue
		var names: Array[String] = []
		var am := m as ArrayMesh
		if am != null:
			for i in am.get_surface_count():
				names.append(am.surface_get_name(i))
		var mats: Array[String] = []
		if am != null:
			for i in am.get_surface_count():
				var mm := am.surface_get_material(i) as StandardMaterial3D
				var tex := "<none>"
				if mm != null and mm.albedo_texture != null:
					tex = "%s" % mm.albedo_texture.resource_path.get_file()
				var alb := mm.albedo_color if mm != null else Color.MAGENTA
				mats.append("%s tex=%s alb=%s" % [names[min(i, names.size() - 1)], tex,
					"%.2f,%.2f,%.2f" % [alb.r, alb.g, alb.b]])
		print("DUMP ", p.get_file(), " surfaces=", names, " aabb=", m.get_aabb())
		if p.contains("food_kit") or names.has("crust") or names.has("pear"):
			for s: String in mats:
				print("      ", s)
	quit()
