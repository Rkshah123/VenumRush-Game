class_name EnvironmentBuilder
extends Node3D
## SERPENTIS 3D — natural 3D environment around the playable court.
## Builds the flat gameplay disc, rolling terrace hills, distant mountain
## ranges, a river + lake (with waterfall), instanced trees / grass / bushes /
## rocks / flowers, animated water, sky, sun and atmosphere. Vegetation stays
## OUT of the court so snakes and food remain readable; boulders placed inside
## the court are real gameplay cover (obstacles), trees near the rim cover the
## edge outside the kill radius.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const FALLS_SHADER := preload("res://shaders/waterfall.gdshader")

var _p: Dictionary
var _arena_r: float = 55.0
var _seed: int = 101
var _rng := RandomNumberGenerator.new()
var _obstacles: Array = []            # [{pos: Vector3, r: float}]
var _water_level: float = -0.85
var _has_water := false
# waterway layout (shared between terrain shaping and placement rejection)
var _river_angle := 0.0
var _river_r := 92.0
var _river_half := 5.0
var _river_span := 1.9
var _lake_pos := Vector3.ZERO
var _lake_r := 13.0

var _ember_mat: StandardMaterial3D
var _tier := 1
var _skip := 0
var _dark := false                # Dark Theme arena pass
var _mode_2d := false             # 2D top-down presentation pass

# quality-tier counts [low, mid, high]
const C_GRASS := [4500, 8000, 14000]
const C_TREES := [46, 82, 116]
const C_ROCKS := [13, 22, 30]
const C_BUSHES := [22, 36, 52]
const C_FLOWERS := [140, 260, 420]
const C_LEAVES_P := [34, 62, 96]
const C_FIREFLY := [90, 130, 170]
const C_DUST := [70, 110, 150]

# ---------------------------------------------------------------- lifecycle

func setup(preset: Dictionary, arena_r: float, mode_2d: bool = false, dark: bool = false) -> void:
	_p = preset
	_arena_r = arena_r
	_seed = int(preset.get("seed", 101))
	_rng.seed = _seed
	_has_water = bool(preset.get("water", false))
	_river_angle = _rng.randf() * TAU
	var lake_a := wrapf(_river_angle + PI, 0.0, TAU)
	_lake_pos = Vector3(sin(lake_a) * (_river_r + 12.0), 0.0, cos(lake_a) * (_river_r + 12.0))
	_lake_r = 13.0 + _rng.randf() * 4.0
	_tier = _pick_tier()
	_mode_2d = mode_2d
	_dark = dark

func obtain_obstacles() -> Array:
	return _obstacles

## Dark Theme color transform: deep, cool-shifted tones that keep hue identity
## so the court stays readable while the world recedes.
func _dk(c: Color, f: float = 0.52) -> Color:
	if not _dark:
		return c
	var dark := Color(c.r * f, c.g * f * 1.02, c.b * f * 1.15)
	return dark.lerp(Color(0.030, 0.042, 0.075), 0.30)

func _ready() -> void:
	# perf bisect switch (dev): ENV_SKIP=1 court+sky, 2 +terrain rings,
	# 3 +water, 4 +vegetation, 0/unset = everything
	_skip = int(OS.get_environment("ENV_SKIP"))
	_build_sky_and_lights()
	_build_court()
	if _skip < 2:
		_build_terrace()
		_build_far_range()
		_build_rim_stones()
	if _has_water and _skip < 3:
		_build_river()
		_build_lake()
		_build_waterfall()
	if _skip < 4:
		_build_trees()
		_build_grass()
		_build_rocks()
		_build_bushes_and_flowers()
	_build_atmosphere()
	_contrast_pass()

## Theme visibility audit pass: every decor object (trees, stumps, rocks,
## bushes, flowers, rim stones) keeps a lit rim and enough albedo contrast to
## stay readable on the darkened courts — Dark Theme never swallows objects.
func _contrast_pass() -> void:
	if not _dark and not _mode_2d:
		return
	var rim := 0.45 if _dark else 0.22
	var dim := 0.58 if _dark else 1.0
	var seen := {}   # decor materials are shared across instances — tint once
	var stack: Array[Node] = get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		var mat := mi.material_override
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			var key := sm.get_instance_id()
			if seen.has(key):
				continue
			seen[key] = true
			if sm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and sm != _ember_mat:
				sm.albedo_color = sm.albedo_color * dim
				sm.rim_enabled = true
				sm.rim = rim
				sm.rim_tint = 0.6

func _process(delta: float) -> void:
	if _ember_mat != null:
		_ember_mat.emission_energy_multiplier = 0.85 + 0.30 * sin(Time.get_ticks_msec() * 0.0022)

func _pick_tier() -> int:
	var os_name := OS.get_name()
	if os_name == "Android" or os_name == "iOS":
		return 0
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	if gpu.contains("intel") and (gpu.contains("uhd") or gpu.contains("hd")):
		return 1
	return 2

func _tiered(arr: Array) -> int:
	return int(arr[clampi(_tier, 0, 2)])

# ---------------------------------------------------------------- noise

func _hash01(x: int, z: int) -> float:
	var n := x * 374761393 + z * 668265263 + _seed * 1911520717
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0

func _noise2(x: float, z: float, cell := 3.7) -> float:
	var xg := floorf(x / cell)
	var zg := floorf(z / cell)
	var xf := x / cell - xg
	var zf := z / cell - zg
	var i0 := int(xg)
	var i1 := int(zg)
	var h00 := _hash01(i0, i1)
	var h10 := _hash01(i0 + 1, i1)
	var h01 := _hash01(i0, i1 + 1)
	var h11 := _hash01(i0 + 1, i1 + 1)
	xf = xf * xf * (3.0 - 2.0 * xf)
	zf = zf * zf * (3.0 - 2.0 * zf)
	return lerpf(lerpf(h00, h10, xf), lerpf(h01, h11, xf), zf)

func _fbm2(x: float, z: float, octaves := 4, cell := 5.4) -> float:
	var v := 0.0
	var amp := 0.55
	var c := cell
	for i in octaves:
		v += amp * _noise2(x, z, c)
		amp *= 0.5
		c *= 2.03
	return v

# ---------------------------------------------------------------- terrain field

func _height_base(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var t := smoothstep(_arena_r + 2.0, _arena_r + 20.0, r)
	var rolling := (_fbm2(x, z, 4, 7.0) - 0.45) * 10.5
	var detail := (_fbm2(x, z, 3, 2.1) - 0.5) * 2.2
	var ridge := (_fbm2(x * 1.7, z * 1.7, 3, 16.0) - 0.5) * 6.0
	var h := (rolling + detail + ridge) * t
	var mount := pow(clampf(smoothstep(120.0, 300.0, r), 0.0, 1.0), 1.4)
	h += mount * (pow(_fbm2(x, z, 5, 34.0), 1.6) * 90.0 + 8.0)
	return h

func _river_dist(x: float, z: float, r: float, ang: float) -> float:
	var d_signed := wrapf(ang - _river_angle, -PI, PI)
	if absf(d_signed) > _river_span:
		var end_a := _river_angle + _river_span * signf(d_signed)
		var ex := sin(end_a) * _river_r
		var ez := cos(end_a) * _river_r
		return sqrt((x - ex) * (x - ex) + (z - ez) * (z - ez))
	return absf(r - _river_r)

func _height(x: float, z: float) -> float:
	var h := _height_base(x, z)
	if not _has_water:
		return h
	var r := sqrt(x * x + z * z)
	var d := _river_dist(x, z, r, atan2(x, z))
	var t := 1.0 - smoothstep(_river_half + 0.5, _river_half + 4.8, d)
	h = lerpf(h, _water_level - 0.8, clampf(t, 0.0, 1.0))
	var dl := Vector2(x, z).distance_to(Vector2(_lake_pos.x, _lake_pos.z))
	var tl := 1.0 - smoothstep(_lake_r + 0.5, _lake_r + 6.5, dl)
	h = lerpf(h, _water_level - 0.8, clampf(tl, 0.0, 1.0))
	return h

func _in_water(x: float, z: float, pad := 2.5) -> bool:
	if not _has_water:
		return false
	var r := sqrt(x * x + z * z)
	var a := atan2(x, z)
	if _river_dist(x, z, r, a) < _river_half + pad:
		return true
	var dl := Vector2(x, z).distance_to(Vector2(_lake_pos.x, _lake_pos.z))
	return dl < _lake_r + pad

# ---------------------------------------------------------------- colors

func _terrain_color(x: float, z: float, ny: float) -> Color:
	# fg cells must exceed vertex spacing (~3 m) to avoid quilt banding
	var col := _dk(Color(_p["grass_a"])).lerp(_dk(Color(_p["grass_b"])), _fbm2(x, z, 3, 11.0))
	var dirtiness := clampf(_fbm2(x + 40.0, z - 17.0, 3, 15.0) * 1.4 - 0.6, 0.0, 1.0)
	col = col.lerp(_dk(Color(_p["dirt"])), dirtiness * 0.55)
	var rocky := clampf(pow(1.0 - ny, 1.8) * 2.2, 0.0, 1.0)
	col = col.lerp(_dk(Color(_p["rock"])), rocky * 0.75)
	var h := _height(x, z)
	var snowline := 34.0 + _fbm2(x, z, 2, 13.0) * 10.0
	if h > snowline:
		col = col.lerp(_dk(Color(0.86, 0.88, 0.92), 0.62), clampf((h - snowline) / 6.0, 0.0, 0.85))
	elif h > 18.0:
		col = col.lerp(_dk(Color(_p["rock"]).lightened(0.25)), clampf((h - 18.0) / 14.0, 0.0, 0.7))
	if _has_water:
		var wet := 1.0 - clampf((h - _water_level) / 1.9, 0.0, 1.0)
		col = col.lerp(_dk(Color(_p["cliff"]).darkened(0.25)), clampf(wet * 0.8, 0.0, 0.8))
	return col

func _court_color(x: float, z: float) -> Color:
	var g_a := _dk(Color(_p["grass_a"]))
	var g_b := _dk(Color(_p["grass_b"]))
	var d := sqrt(x * x + z * z)
	var t := clampf(d / _arena_r, 0.0, 1.0)
	# fg cells must be LARGER than vertex spacing (~2 m) or per-vertex colors
	# read as a checkered quilt; fine detail lives in the fragment mottle.
	# Diagonal mow bands (stadium turf) read as a designed modern arena.
	var band := 0.5 + 0.5 * cos((x + z) * 0.42)
	var col := g_a.lerp(g_b * 1.04, _fbm2(x, z, 3, 11.0))
	col = col.lerp(g_b.lightened(0.09), 0.22 * band)
	col = col.lerp(col.darkened(0.09), 0.26 * (1.0 - band))
	var wear := clampf(_fbm2(x + 91.0, z - 53.0, 3, 13.0) * 1.5 - 0.75, 0.0, 1.0)
	col = col.lerp(_dk(Color(_p["dirt"])), wear * 0.40)
	col = col.lerp(col.darkened(0.38), smoothstep(0.84, 1.0, t) * 0.55)
	return col

# ---------------------------------------------------------------- radial mesh

func _radial_mesh(r0: float, r1: float, segs: int, rings: int, flat: bool) -> ArrayMesh:
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var nws := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	pts.resize(segs * (rings + 1))
	uvs.resize(segs * (rings + 1))
	nws.resize(segs * (rings + 1))
	cols.resize(segs * (rings + 1))
	var step := TAU / float(segs)
	for j in rings + 1:
		var rl := lerpf(r0, r1, float(j) / float(rings))
		for i in segs:
			var ang := float(i) * step
			var x := sin(ang) * rl
			var z := cos(ang) * rl
			var y := 0.0 if flat else _height(x, z)
			pts[j * segs + i] = Vector3(x, y, z)
			uvs[j * segs + i] = Vector2(float(i) / float(segs), float(j) / float(rings))
	for j in rings + 1:
		for i in segs:
			var here := pts[j * segs + i]
			var p_ip := pts[j * segs + ((i + 1) % segs)]
			var p_im := pts[j * segs + ((i - 1 + segs) % segs)]
			var p_up := here
			var p_dn := here
			if j < rings:
				p_up = pts[(j + 1) * segs + i]
			if j > 0:
				p_dn = pts[(j - 1) * segs + i]
			if j == rings:
				p_up = here + (here - p_dn)
			if j == 0:
				p_dn = here + (here - p_up)
			var t_i := p_ip - p_im
			var t_j := p_up - p_dn
			var n := t_j.cross(t_i)
			if n.length() > 0.0001:
				n = n.normalized()
			if n.y < 0.0:
				n = -n
			nws[j * segs + i] = n
			var c := _court_color(here.x, here.z) if flat else _terrain_color(here.x, here.z, n.y)
			cols[j * segs + i] = c
	for j in rings:
		for i in segs:
			var i0 := j * segs + i
			var i1 := j * segs + ((i + 1) % segs)
			var i2 := (j + 1) * segs + i
			var i3 := (j + 1) * segs + ((i + 1) % segs)
			# Godot meshes face CW-from-outside; outer-inner order flips visibility
			idx.append_array([i0, i1, i2, i1, i3, i2])
	var arm := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	arrays[Mesh.ARRAY_NORMAL] = nws
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	arm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arm

func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter("u_court_r", _arena_r)
	return m

# ---------------------------------------------------------------- sky & sun

func _build_sky_and_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = _dk(Color(_p["sun_color"]), 0.72).lerp(Color(0.72, 0.80, 1.0), 0.35) if _dark else Color(_p["sun_color"])
	var sun_e := float(_p["sun_energy"]) * (0.62 if _dark else 1.0) * (0.88 if _mode_2d else 1.0)
	sun.light_energy = sun_e
	var yaw := float(_p["sun_yaw"])
	var pitch := float(_p["sun_pitch"])
	sun.rotation_degrees = Vector3(-pitch, yaw, 0.0)
	sun.shadow_enabled = _tier >= 1   # Android tier skips the shadow pass entirely
	sun.directional_shadow_max_distance = 120.0 if _tier >= 1 else 80.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.04
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skym := ShaderMaterial.new()
	skym.shader = SKY_SHADER
	var sky_top: Color = _dk(Color(_p["sky_top"]), 0.30) if _dark else Color(_p["sky_top"])
	var sky_hz: Color = _dk(Color(_p["sky_hz"]), 0.34) if _dark else Color(_p["sky_hz"])
	if _dark:
		# deep indigo night-sky gradient — dark but never flat black
		sky_top = Color(0.020, 0.030, 0.085)
		sky_hz = Color(0.070, 0.075, 0.170)
	skym.set_shader_parameter("u_top", sky_top)
	skym.set_shader_parameter("u_horizon", sky_hz)
	skym.set_shader_parameter("u_sun_color", sun.light_color)
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	var sun_dir := Vector3(sin(yr), cos(yr) * sin(pr), cos(yr) * cos(pr)).normalized()
	skym.set_shader_parameter("u_sun_dir", sun_dir)
	var night := bool(_p.get("night", false)) or _dark
	skym.set_shader_parameter("u_cloud", 0.55 if night else 1.0)
	sky.sky_material = skym
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if _dark:
		env.ambient_light_color = Color(0.24, 0.30, 0.48)
		env.ambient_light_energy = float(_p["ambient_energy"]) * 0.85
	else:
		env.ambient_light_color = _p["ambient"]
		env.ambient_light_energy = _p["ambient_energy"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08 if night else 1.0
	if _dark:
		env.tonemap_exposure = 1.22   # lift shadows so nothing sinks to pure black
	env.fog_enabled = false
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = _dk(Color(_p["fog_color"]), 0.4) if _dark else Color(_p["fog_color"])
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 300.0
	env.fog_depth_curve = 1.15
	env.fog_sky_affect = 0.05
	env.glow_enabled = night
	env.glow_intensity = 0.9 if _dark else 0.6
	env.glow_bloom = 0.12 if _dark else 0.08
	env.glow_hdr_threshold = 0.95 if _dark else 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# ---------------------------------------------------------------- terrain pieces

func _build_court() -> void:
	var m := MeshInstance3D.new()
	m.mesh = _radial_mesh(0.0, _arena_r, 160, 30, true)
	m.material_override = _terrain_material()
	add_child(m)

func _build_terrace() -> void:
	var m := MeshInstance3D.new()
	m.mesh = _radial_mesh(_arena_r + 0.3, 122.0, 76, 26, false)
	m.material_override = _terrain_material()
	add_child(m)

func _build_far_range() -> void:
	var m := MeshInstance3D.new()
	m.mesh = _radial_mesh(121.0, 305.0, 96, 30, false)
	m.material_override = _terrain_material()
	add_child(m)

func _build_rim_stones() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(_p["rock"]).lightened(0.12)
	stone.roughness = 0.95
	# continuous under-rim torus keeps the valley floor meeting the court
	var base := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = _arena_r + 0.55
	torus.outer_radius = _arena_r + 1.45
	torus.rings = 80
	torus.ring_segments = 8
	base.mesh = torus
	base.material_override = stone
	base.position.y = -0.28
	add_child(base)
	for i in 34:
		var ang := TAU * float(i) / 34.0 + _rng.randf() * 0.05
		var r := _arena_r + 0.95 + _rng.randf() * 0.5
		var pos := Vector3(sin(ang) * r, 0.05, cos(ang) * r)
		var rock := MeshInstance3D.new()
		rock.mesh = _mid_rock_mesh()
		rock.material_override = stone
		rock.position = pos
		rock.scale = Vector3(0.7 + _rng.randf() * 0.25, 0.42 + _rng.randf() * 0.3, 0.7 + _rng.randf() * 0.25)
		rock.rotation.y = _rng.randf() * TAU
		add_child(rock)
	# ember boundary ring — gameplay readability at the kill radius
	# (brighter/thicker under Dark Theme so the wall never gets lost)
	var ember := MeshInstance3D.new()
	var et := TorusMesh.new()
	var ring_w := 0.20 if _dark else 0.10
	et.inner_radius = _arena_r - ring_w
	et.outer_radius = _arena_r + ring_w
	et.rings = 72
	et.ring_segments = 3
	ember.mesh = et
	_ember_mat = StandardMaterial3D.new()
	_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ember_mat.albedo_color = Color(1.0, 0.38, 0.14, 0.85 if _dark else 0.6)
	_ember_mat.emission_enabled = true
	_ember_mat.emission = Color(1.0, 0.32, 0.08) if not _dark else Color(1.0, 0.45, 0.16)
	_ember_mat.emission_energy_multiplier = 1.0
	ember.material_override = _ember_mat
	ember.position.y = 0.10
	add_child(ember)

# ---------------------------------------------------------------- water

func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("u_shallow", _p["water_color"])
	m.set_shader_parameter("u_deep", _p["water_depth_color"])
	m.set_shader_parameter("u_alpha", 0.88)
	var tint := Color(_p["sky_hz"])
	m.set_shader_parameter("u_sky_tint", Vector3(tint.r, tint.g, tint.b))
	return m

func _build_river() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 46
	for s in segs + 1:
		var tt := float(s) / float(segs)
		var ang := _river_angle + _river_span * tt
		var x0 := sin(ang) * _river_r
		var z0 := cos(ang) * _river_r
		var taper := clampf(float(s) / 3.0, 0.0, 1.0) * clampf(float(segs - s) / 3.0, 0.0, 1.0)
		var w := _river_half * clampf(taper, 0.4, 1.0)
		var dir := Vector3(cos(ang), 0.0, -sin(ang))
		# 3 stations per ring: left bank (uv.x=0), center (uv.x=1), right bank (0)
		for k in 3:
			var lateral := w * (float(k) - 1.0)
			var pos := Vector3(x0 + dir.x * lateral, _water_level, z0 + dir.z * lateral)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(float(k == 1), tt))
			st.add_vertex(pos)
	for s in segs:
		var L := s * 3
		var C := s * 3 + 1
		var R := s * 3 + 2
		var L2 := (s + 1) * 3
		var C2 := (s + 1) * 3 + 1
		var R2 := (s + 1) * 3 + 2
		st.add_index(L)
		st.add_index(L2)
		st.add_index(C)
		st.add_index(C)
		st.add_index(L2)
		st.add_index(C2)
		st.add_index(C)
		st.add_index(C2)
		st.add_index(R)
		st.add_index(R)
		st.add_index(C2)
		st.add_index(R2)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _water_material()
	add_child(mi)

func _build_lake() -> void:
	var mesh := _radial_mesh(0.0, _lake_r, 36, 6, true)
	var mds := mesh.surface_get_arrays(0)
	var pts: PackedVector3Array = mds[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = mds[Mesh.ARRAY_TEX_UV]
	for k in pts.size():
		var d := Vector2(pts[k].x, pts[k].z).length()
		pts[k] = Vector3(pts[k].x, _water_level, pts[k].z)
		var t := 1.0 - clampf(d / _lake_r, 0.0, 1.0)
		uvs[k] = Vector2(t * t * 0.9 + 0.05, 0.5)
	mds[Mesh.ARRAY_VERTEX] = pts
	mds[Mesh.ARRAY_TEX_UV] = uvs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mds)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.position = _lake_pos
	mi.material_override = _water_material()
	add_child(mi)

func _build_waterfall() -> void:
	# cliff of rocks at the hillside behind the lake, water spilling over
	var lake_a := atan2(_lake_pos.x, _lake_pos.z)
	var outward := Vector3(sin(lake_a), 0.0, cos(lake_a)).normalized()
	var cliff_pos := _lake_pos + outward * (_lake_r + 4.5)
	var top_y := _height(cliff_pos.x, cliff_pos.z)
	if top_y - _water_level < 3.2:
		top_y = _water_level + 3.2 + _rng.randf() * 1.5
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(_p["rock"]).darkened(0.15)
	stone.roughness = 0.95
	for i in 3:
		var rock := MeshInstance3D.new()
		rock.mesh = _mid_rock_mesh()
		rock.material_override = stone
		rock.position = cliff_pos + outward * (float(i) * 1.1) + Vector3(
			_rng.randf() * 1.5 - 0.75,
			_water_level + top_y * 0.45,
			_rng.randf() * 1.5 - 0.75)
		rock.scale = Vector3(2.6 - i * 0.4, top_y * 0.62, 1.9 - i * 0.3)
		rock.rotation.y = _rng.randf() * TAU
		add_child(rock)
	var falls := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(5.4, top_y - _water_level - 0.7)
	falls.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = FALLS_SHADER
	mat.set_shader_parameter("u_tint", _p["water_color"])
	mat.set_shader_parameter("u_foam", Color(0.93, 0.97, 1.0))
	falls.material_override = mat
	var inward := -outward
	var yaw := atan2(inward.x, inward.z)
	falls.position = cliff_pos - outward * 0.55 + Vector3(0.0, _water_level + q.size.y * 0.5 + 0.4, 0.0)
	falls.rotation_degrees = Vector3(5.0, rad_to_deg(yaw), 0.0)
	add_child(falls)
	# mist at the plunge pool
	var splash := CPUParticles3D.new()
	splash.amount = 30
	splash.lifetime = 1.6
	splash.mesh = _mote_mesh(Color(0.92, 0.96, 1.0, 0.42), 0.13, false)
	splash.direction = Vector3(-outward.x, 0.5, -outward.z)
	splash.spread = 26.0
	splash.initial_velocity_min = 1.0
	splash.initial_velocity_max = 2.4
	splash.gravity = Vector3(0, -4.2, 0)
	splash.scale_amount_min = 0.7
	splash.scale_amount_max = 1.6
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	splash.emission_box_extents = Vector3(2.4, 0.4, 0.6)
	splash.position = cliff_pos - outward * 1.4 + Vector3(0.0, _water_level + 1.4, 0.0)
	splash.rotation.y = yaw
	add_child(splash)

# ---------------------------------------------------------------- shared meshes

func _mote_mesh(color: Color, size: float, emissive: bool) -> Mesh:
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2.0
	s.radial_segments = 6
	s.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = false
	mat.albedo_color = color
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.2
	s.material = mat
	return s

func _mid_rock_mesh() -> ArrayMesh:
	# low-poly irregular boulder: jittered radial ball, flattened base
	var segs := 9
	var rings := 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := TAU / float(segs)
	var rjit := []
	for j in rings + 1:
		var rowm := []
		for i in segs:
			rowm.append(_rng.randf() * 0.4 + 0.8)
		rjit.append(rowm)
	for j in rings + 1:
		var vy := lerpf(-0.5, 0.62, float(j) / float(rings))
		if vy < -0.25:
			vy = -0.25
		for i in segs:
			var ang := float(i) * step
			var rad: float = rjit[j][i] * (1.0 if vy > -0.2 else 0.8)
			var x := sin(ang) * rad
			var z := cos(ang) * rad
			var y := vy
			var cc := Color(0.86, 0.83, 0.78)
			if y < -0.05:
				cc = Color(0.55, 0.52, 0.5)
			st.set_color(_jit_col(cc, 0.08))
			st.set_normal(Vector3(x, 0.55, z).normalized())
			st.add_vertex(Vector3(x, y, z))
	for j in rings:
		for i in segs:
			var i0 := j * segs + i
			var i1 := j * segs + ((i + 1) % segs)
			var i2 := (j + 1) * segs + i
			var i3 := (j + 1) * segs + ((i + 1) % segs)
			# top cap fan handled implicitly by ring wrap
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	# pole caps — row vertices count is known: (rings + 1) * segs
	var top_row := rings * segs
	var centert: int = (rings + 1) * segs
	st.set_color(Color(0.9, 0.88, 0.85))
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(0, 0.62, 0))
	var centeri: int = centert + 1
	for i in segs:
		st.add_index(centeri)
		st.add_index(top_row + i)
		st.add_index(top_row + ((i + 1) % segs))
	var centerb: int = centert + 1
	st.set_color(Color(0.5, 0.47, 0.45))
	st.set_normal(Vector3.DOWN)
	st.add_vertex(Vector3(0, -0.25, 0))
	for i in segs:
		st.add_index(centerb)
		st.add_index((i + 1) % segs)
		st.add_index(i)
	return st.commit()

func _jit_col(c: Color, amt: float) -> Color:
	var j := (_rng.randf() - 0.5) * amt
	return Color(c.r + j, c.g + j, c.b + j, c.a)

# ---------------------------------------------------------------- trees

func _tree_transforms(count: float, r_min: float, r_max: float) -> Array:
	var out: Array = []
	var placed: Array[Vector3] = []
	var target := int(count)
	var tries := 0
	while out.size() < target and tries < target * 8:
		tries += 1
		var ang := _rng.randf() * TAU
		var r := r_min + _rng.randf() * (r_max - r_min)
		var x := sin(ang) * r
		var z := cos(ang) * r
		if _in_water(x, z, 4.0):
			continue
		var clear := true
		for p in placed:
			if Vector2(x - p.x, z - p.z).length() < 5.2:
				clear = false
				break
		if not clear:
			continue
		placed.append(Vector3(x, 0.0, z))
		var y := _height(x, z)
		var s := 0.75 + _rng.randf() * 0.5
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * (0.85 + _rng.randf() * 0.45), s))
		out.append(Transform3D(basis, Vector3(x, y, z)))
	return out

func _build_trees() -> void:
	var note := String(_p.get("designer_note", ""))
	var types: Array = ["broad", "broad", "pine"]
	if note.contains("acacia"):
		types = ["acacia"]
	elif bool(_p.get("night", false)):
		types = ["pine", "pine", "broad"]
	var tree_scale := float(_p.get("tree_count", 1.0))
	var transforms_by_type := {}
	for t in types:
		if not transforms_by_type.has(t):
			transforms_by_type[t] = []
	for t in transforms_by_type.keys():
		transforms_by_type[t] = _tree_transforms(tree_scale * _tiered(C_TREES) / float(types.size()) + 4.0, 60.5, 168.0)
	for t in transforms_by_type.keys():
		var parts := _tree_meshes(t)
		_add_foliage_multimesh(parts["leaf"], transforms_by_type[t], 0.9, Color(_p["leaf_a"]).lerp(Color(_p["leaf_b"]), 0.5))
		_add_foliage_multimesh(parts["trunk"], transforms_by_type[t], 0.10, Color(_p["trunk"]).lightened(0.34))
	# trees near the court provide solid cover: register trunk obstacles
	for t in transforms_by_type.keys():
		for xf in transforms_by_type[t]:
			var org: Vector3 = xf.origin
			if Vector2(org.x, org.z).length() < 74.0:
				_post_obstacle(org, 0.55)

func _tree_meshes(kind: String) -> Dictionary:
	var leaf := SurfaceTool.new()
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_m := CylinderMesh.new()
	trunk_m.top_radius = 0.12
	trunk_m.bottom_radius = 0.26
	trunk_m.height = 3.2
	trunk_m.radial_segments = 7
	if kind == "broad":
		trunk.append_from(trunk_m, 0, Transform3D(Basis(), Vector3(0, 1.6, 0)))
		var blob := SphereMesh.new()
		blob.radius = 1.35
		blob.height = 2.0
		blob.radial_segments = 9
		blob.rings = 6
		leaf.append_from(blob, 0, Transform3D(Basis().scaled(Vector3(1.15, 0.8, 1.15)), Vector3(0, 3.5, 0)))
		leaf.append_from(blob, 0, Transform3D(Basis().scaled(Vector3(0.85, 0.7, 0.85)), Vector3(0.85, 4.15, 0.3)))
		leaf.append_from(blob, 0, Transform3D(Basis().scaled(Vector3(0.75, 0.65, 0.75)), Vector3(-0.7, 4.3, -0.4)))
		leaf.append_from(blob, 0, Transform3D(Basis().scaled(Vector3(0.8, 0.75, 0.8)), Vector3(0.1, 4.75, 0.05)))
	elif kind == "pine":
		trunk_m.height = 3.6
		trunk.append_from(trunk_m, 0, Transform3D(Basis(), Vector3(0, 1.8, 0)))
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.radial_segments = 9
		cone.rings = 1
		var levels := [
			[1.5, 2.6, 2.6],   # radius_bottom, height, y
			[1.15, 2.3, 3.9],
			[0.8, 2.1, 5.1],
			[0.42, 1.8, 6.2],
		]
		for lv in levels:
			cone.bottom_radius = lv[0]
			cone.height = lv[1]
			leaf.append_from(cone, 0, Transform3D(Basis(), Vector3(0, lv[2], 0)))
	else: # acacia — slender trunk + wide flat canopy
		trunk_m.height = 4.4
		trunk.append_from(trunk_m, 0, Transform3D(Basis().rotated(Vector3(1, 0, 0.3).normalized(), 0.12), Vector3(0.25, 2.2, 0)))
		var disc := CylinderMesh.new()
		disc.top_radius = 2.9
		disc.bottom_radius = 2.1
		disc.height = 0.85
		disc.radial_segments = 14
		leaf.append_from(disc, 0, Transform3D(Basis().scaled(Vector3(1.0, 0.45, 1.0)), Vector3(0.2, 4.5, 0)))
	var leaf_mesh := leaf.commit()
	var trunk_mesh := trunk.commit()
	leaf_mesh.surface_set_name(0, "leaves")
	trunk_mesh.surface_set_name(0, "trunk")
	return {"leaf": leaf_mesh, "trunk": trunk_mesh}

func _add_foliage_multimesh(mesh: Mesh, transforms: Array, sway: float, tint: Color) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		var ph := _rng.randf() * TAU
		mm.set_instance_custom_data(i, Color(ph, sway, _rng.randf(), 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE_SHADER
	mat.set_shader_parameter("u_tint", tint)
	mat.set_shader_parameter("u_wind_strength", 0.30)
	if sway < 0.3:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = mat
	add_child(mmi)

# ---------------------------------------------------------------- grass

func _grass_blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_c := Color(_p["grass_b"]).darkened(0.34)
	var tip_c := Color(_p["grass_b"]).lightened(0.18)
	var rows := [
		[0.0, 0.045, 0.0, root_c],
		[0.30, 0.034, 0.03, root_c.lerp(tip_c, 0.35)],
		[0.62, 0.020, 0.075, root_c.lerp(tip_c, 0.75)],
		[0.95, 0.004, 0.14, tip_c],
	]
	for row in rows:
		var y: float = row[0]
		var w: float = row[1]
		var zf: float = row[2]
		var c: Color = row[3]
		for side in 2:
			var sx := w if side == 1 else -w
			st.set_color(c)
			st.set_normal(Vector3(sx * 3.0, 0.5, 0.3).normalized())
			st.set_uv(Vector2(float(side), y / 0.95))
			st.add_vertex(Vector3(sx, y, zf))
	for r in 3:
		var a := r * 2
		var b := r * 2 + 1
		var c2 := (r + 1) * 2
		var d := (r + 1) * 2 + 1
		st.add_index(a)
		st.add_index(b)
		st.add_index(c2)
		st.add_index(b)
		st.add_index(d)
		st.add_index(c2)
	return st.commit()

func _build_grass() -> void:
	var blade := _grass_blade_mesh()
	var count := _tiered(C_GRASS)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = blade
	mm.instance_count = count
	for i in count:
		var ang := _rng.randf() * TAU
		var r := _arena_r + 1.6 + 112.0 * pow(_rng.randf(), 1.35)
		var x := sin(ang) * r
		var z := cos(ang) * r
		var y := _height(x, z)
		var s := (0.7 + _rng.randf() * 1.1)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * (0.8 + _rng.randf() * 0.6), s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
		mm.set_instance_custom_data(i, Color(_rng.randf() * TAU, 0.55 + _rng.randf() * 0.35, _rng.randf(), 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE_SHADER
	mat.set_shader_parameter("u_tint", Color(_p.get("blade_tint", Color(0.62, 0.9, 0.55))))
	mat.set_shader_parameter("u_wind_strength", 0.30)
	mmi.material_override = mat
	add_child(mmi)

# ---------------------------------------------------------------- rocks / bushes / flowers

func _build_rocks() -> void:
	var rock_mesh := _mid_rock_mesh()
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(_p["rock"]).lightened(0.06)
	stone.roughness = 0.95
	stone.vertex_color_use_as_albedo = true
	# gameplay boulders INSIDE the court (real cover, replaces old crystals)
	var placed: Array[Vector3] = []
	var guard := 0
	while placed.size() < 9 and guard < 90:
		guard += 1
		var ang := _rng.randf() * TAU
		var r := 13.0 + _rng.randf() * 33.0
		var p := Vector3(sin(ang) * r, 0.0, cos(ang) * r)
		var clear := true
		for q in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < 15.0:
				clear = false
				break
		if not clear:
			continue
		placed.append(p)
		var s := 1.15 + _rng.randf() * 0.75
		var mi := MeshInstance3D.new()
		mi.mesh = rock_mesh
		mi.material_override = stone
		mi.position = p + Vector3(0.0, 0.35 * s, 0.0)
		mi.scale = Vector3(s, s * 0.8, s * (0.8 + _rng.randf() * 0.35))
		mi.rotation.y = _rng.randf() * TAU
		add_child(mi)
		_post_obstacle(p, s * 0.78)
	# scenic rocks in the terraces
	var target := _tiered(C_ROCKS)
	var g2 := 0
	var extra := 0
	while extra < target and g2 < target * 5:
		g2 += 1
		var ang := _rng.randf() * TAU
		var r := 63.0 + _rng.randf() * 105.0
		var x := sin(ang) * r
		var z := cos(ang) * r
		if _in_water(x, z, 2.0):
			continue
		extra += 1
		var s := 0.55 + _rng.randf() * 1.1
		var mi := MeshInstance3D.new()
		mi.mesh = rock_mesh
		mi.material_override = stone
		mi.position = Vector3(x, _height(x, z) - 0.2 * s, z)
		mi.scale = Vector3(s, s * 1.05, s * (0.85 + _rng.randf() * 0.4))
		mi.rotation.y = _rng.randf() * TAU
		add_child(mi)

func _build_bushes_and_flowers() -> void:
	var bush_st := SurfaceTool.new()
	bush_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 0.8
	blob.radial_segments = 8
	blob.rings = 4
	bush_st.append_from(blob, 0, Transform3D(Basis().scaled(Vector3(1.1, 0.75, 1.1)), Vector3(0, 0.3, 0)))
	bush_st.append_from(blob, 0, Transform3D(Basis().scaled(Vector3(0.8, 0.6, 0.8)), Vector3(0.4, 0.42, 0.25)))
	bush_st.append_from(blob, 0, Transform3D(Basis().scaled(Vector3(0.7, 0.55, 0.7)), Vector3(-0.35, 0.4, -0.2)))
	var bush_mesh := bush_st.commit()
	var bush_count := _tiered(C_BUSHES)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = bush_mesh
	mm.instance_count = bush_count
	for i in bush_count:
		var ang := _rng.randf() * TAU
		var r := 62.0 + _rng.randf() * 88.0
		var x := sin(ang) * r
		var z := cos(ang) * r
		var y := _height(x, z)
		if _in_water(x, z, 1.5):
			mm.set_instance_transform(i, Transform3D())
			continue
		var s := 0.7 + _rng.randf() * 1.1
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.9, s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
		mm.set_instance_custom_data(i, Color(_rng.randf() * TAU, 0.7, _rng.randf(), 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bmat := ShaderMaterial.new()
	bmat.shader = FOLIAGE_SHADER
	bmat.set_shader_parameter("u_tint", Color(_p["leaf_a"]).lerp(Color(_p["leaf_b"]), 0.35))
	bmat.set_shader_parameter("u_wind_strength", 0.22)
	mmi.material_override = bmat
	add_child(mmi)

	# flowers — three hue variants as tiny crossed petals
	var palette := [
		Color(0.96, 0.94, 0.88),
		Color(0.95, 0.55, 0.72),
		Color(1.0, 0.82, 0.30),
	]
	if bool(_p.get("night", false)):
		palette = [
			Color(0.55, 0.75, 0.85),
			Color(0.45, 0.55, 0.9),
			Color(0.7, 0.6, 0.95),
		]
	for pi in palette.size():
		var fmesh := _flower_mesh(palette[pi])
		var fcount := _tiered(C_FLOWERS) / 3
		var fmm := MultiMesh.new()
		fmm.transform_format = MultiMesh.TRANSFORM_3D
		fmm.use_custom_data = true
		fmm.mesh = fmesh
		fmm.instance_count = fcount
		for i in fcount:
			var ang := _rng.randf() * TAU
			var r := _arena_r + 2.5 + 45.0 * pow(_rng.randf(), 1.4)
			var x := sin(ang) * r
			var z := cos(ang) * r
			var y := _height(x, z)
			if _in_water(x, z, 1.5):
				fmm.set_instance_transform(i, Transform3D())
				continue
			var s := 0.6 + _rng.randf() * 0.9
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
			fmm.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
			fmm.set_instance_custom_data(i, Color(_rng.randf() * TAU, 0.45, _rng.randf(), 0.0))
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fmm
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fmat := ShaderMaterial.new()
		fmat.shader = FOLIAGE_SHADER
		fmat.set_shader_parameter("u_tint", Color(1, 1, 1))
		fmat.set_shader_parameter("u_wind_strength", 0.30)
		fmi.material_override = fmat
		add_child(fmi)

func _flower_mesh(petal: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_c := Color(_p["grass_b"]).darkened(0.2)
	# stem: two thin crossed quads
	for k in 2:
		var yawk := k * PI * 0.5
		var dx := cos(yawk)
		var dz := sin(yawk)
		st.set_color(stem_c)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(-dx * 0.012, 0.0, -dz * 0.012))
		st.add_vertex(Vector3(dx * 0.012, 0.0, dz * 0.012))
		st.add_vertex(Vector3(-dx * 0.012, 0.28, -dz * 0.012))
		st.add_vertex(Vector3(dx * 0.012, 0.28, dz * 0.012))
		var b := k * 4
		st.add_index(b)
		st.add_index(b + 1)
		st.add_index(b + 2)
		st.add_index(b + 1)
		st.add_index(b + 3)
		st.add_index(b + 2)
	# petals: one crossed pair of small quads at the top, colored
	var pc := _jit_col(petal, 0.06)
	for k in 2:
		var yawk := k * PI * 0.5 + 0.4
		var dx := cos(yawk)
		var dz := sin(yawk)
		st.set_color(pc)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(-dx * 0.075, 0.26, -dz * 0.075))
		st.add_vertex(Vector3(dx * 0.075, 0.26, dz * 0.075))
		st.add_vertex(Vector3(-dx * 0.075, 0.42, -dz * 0.075))
		st.add_vertex(Vector3(dx * 0.075, 0.42, dz * 0.075))
		var b := k * 4
		st.add_index(b)
		st.add_index(b + 1)
		st.add_index(b + 2)
		st.add_index(b + 1)
		st.add_index(b + 3)
		st.add_index(b + 2)
	# center dot
	st.set_color(pc.lightened(0.4))
	st.set_normal(Vector3.UP)
	var near0 := 0.30
	var near1 := 0.44
	st.add_vertex(Vector3(-0.03, near0, -0.03))
	st.add_vertex(Vector3(0.03, near0, 0.03))
	st.add_vertex(Vector3(-0.03, near1, -0.03))
	st.add_vertex(Vector3(0.03, near1, 0.03))
	var b := 8
	st.add_index(b)
	st.add_index(b + 1)
	st.add_index(b + 2)
	st.add_index(b + 1)
	st.add_index(b + 3)
	st.add_index(b + 2)
	return st.commit()

# ---------------------------------------------------------------- atmosphere

func _build_atmosphere() -> void:
	_drifting_leaves()
	if bool(_p.get("night", false)):
		_fireflies()
	_dust_motes()

func _drifting_leaves() -> void:
	var p := CPUParticles3D.new()
	p.amount = _tiered(C_LEAVES_P)
	p.lifetime = 9.0
	preprocess_override(p, 8.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 84.0
	p.emission_ring_inner_radius = 62.0
	p.emission_ring_height = 6.0
	p.position.y = 6.0
	p.direction = Vector3(0.6, 0.15, 0.4)
	p.spread = 60.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0.3, -1.4, 0.2)
	p.angular_velocity_min = 90.0
	p.angular_velocity_max = 480.0
	p.scale_amount_min = 0.75
	p.scale_amount_max = 1.35
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.16, 0.12)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(_p["leaf_b"]).lightened(0.1)
	lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lmat.roughness = 0.85
	quad.material = lmat
	p.mesh = quad
	add_child(p)

func _fireflies() -> void:
	var p := CPUParticles3D.new()
	p.amount = _tiered(C_FIREFLY)
	p.lifetime = 7.0
	preprocess_override(p, 6.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 66.0
	p.position.y = 4.0
	p.direction = Vector3(0.2, 0.25, 0.2)
	p.spread = 90.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var glow := Color(1.0, 0.92, 0.45)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = 3.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mote := SphereMesh.new()
	mote.radius = 0.045
	mote.height = 0.09
	mote.radial_segments = 5
	mote.rings = 2
	mote.material = mat
	p.mesh = mote
	add_child(p)

func _dust_motes() -> void:
	var p := CPUParticles3D.new()
	p.amount = _tiered(C_DUST)
	p.lifetime = 10.0
	preprocess_override(p, 9.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 50.0
	p.position.y = 3.0
	p.direction = Vector3(0.4, 0.12, 0.3)
	p.spread = 80.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.6
	p.gravity = Vector3.ZERO
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.95, 0.9, 0.16)
	if bool(_p.get("night", false)):
		mat.albedo_color = Color(0.7, 0.8, 1.0, 0.10)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mote := SphereMesh.new()
	mote.radius = 0.05
	mote.height = 0.1
	mote.radial_segments = 4
	mote.rings = 2
	mote.material = mat
	p.mesh = mote
	add_child(p)

func preprocess_override(p: CPUParticles3D, secs: float) -> void:
	p.preprocess = secs

# ---------------------------------------------------------------- obstacles

func _post_obstacle(pos: Vector3, r: float) -> void:
	_obstacles.append({"pos": pos, "r": r})
