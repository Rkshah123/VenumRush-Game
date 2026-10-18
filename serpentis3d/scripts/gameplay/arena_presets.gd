class_name ArenaPresets
extends RefCounted
## Biome definitions for the 3D snake arena. Each preset steers terrain colors,
## lighting, fog, sky, water and vegetation so the match world reads like a
## natural environment rather than a flat board. All fields are plain data.

const ALL := {
	"valley": {
		"name": "VERDANT VALLEY",
		"seed": 101,
		"sun_color": Color(1.0, 0.95, 0.85), "sun_energy": 1.0,
		"sun_yaw": 32.0, "sun_pitch": 54.0,
		"ambient": Color(0.42, 0.47, 0.42), "ambient_energy": 0.6,
		"designer_note": "lush greens, river + lake, blue summer sky",
		"sky_top": Color(0.16, 0.38, 0.66),
		"sky_hz": Color(0.62, 0.78, 0.90),
		"fog_color": Color(0.60, 0.72, 0.78), "fog_density": 0.0035,
		"grass_a": Color(0.22, 0.42, 0.16),
		"grass_b": Color(0.34, 0.55, 0.18),
		"dirt": Color(0.32, 0.25, 0.16),
		"rock": Color(0.38, 0.37, 0.34),
		"cliff": Color(0.28, 0.26, 0.24),
		"leaf_a": Color(0.20, 0.48, 0.16),
		"leaf_b": Color(0.32, 0.60, 0.20),
		"trunk": Color(0.30, 0.22, 0.14),
		"water": true,
		"water_color": Color(0.16, 0.42, 0.48, 0.86),
		"water_depth_color": Color(0.04, 0.18, 0.30),
		"tree_count": 1.0, "grass_count": 1.0,
		"blade_tint": Color(0.62, 0.9, 0.55),
		"fireflies": false,
		"night": false,
	},
	"autumn": {
		"name": "AUTUMN HILLS",
		"seed": 207,
		"sun_color": Color(1.0, 0.87, 0.66), "sun_energy": 0.95,
		"sun_yaw": 205.0, "sun_pitch": 38.0,
		"ambient": Color(0.48, 0.40, 0.34), "ambient_energy": 0.65,
		"designer_note": "amber meadows, maple canopies, golden hour haze",
		"sky_top": Color(0.28, 0.40, 0.62),
		"sky_hz": Color(0.93, 0.66, 0.44),
		"fog_color": Color(0.85, 0.60, 0.42), "fog_density": 0.0055,
		"grass_a": Color(0.42, 0.36, 0.12),
		"grass_b": Color(0.58, 0.48, 0.16),
		"dirt": Color(0.36, 0.27, 0.17),
		"rock": Color(0.42, 0.36, 0.31),
		"cliff": Color(0.32, 0.25, 0.21),
		"leaf_a": Color(0.68, 0.28, 0.08),
		"leaf_b": Color(0.86, 0.52, 0.10),
		"trunk": Color(0.28, 0.19, 0.12),
		"water": false,
		"water_color": Color(0.30, 0.40, 0.46, 0.9),
		"water_depth_color": Color(0.10, 0.18, 0.26),
		"tree_count": 1.15, "grass_count": 1.25,
		"blade_tint": Color(1.05, 0.78, 0.42),
		"fireflies": false,
		"night": false,
	},
	"savanna": {
		"name": "GOLDEN SAVANNA",
		"seed": 333,
		"sun_color": Color(1.0, 0.80, 0.55), "sun_energy": 0.9,
		"sun_yaw": 118.0, "sun_pitch": 22.0,
		"ambient": Color(0.52, 0.40, 0.26), "ambient_energy": 0.7,
		"designer_note": "dry grass, flat-top acacias, low sun and heat haze",
		"sky_top": Color(0.42, 0.30, 0.52),
		"sky_hz": Color(0.96, 0.62, 0.36),
		"fog_color": Color(0.82, 0.55, 0.35), "fog_density": 0.0075,
		"grass_a": Color(0.52, 0.42, 0.14),
		"grass_b": Color(0.68, 0.56, 0.18),
		"dirt": Color(0.44, 0.32, 0.18),
		"rock": Color(0.47, 0.40, 0.33),
		"cliff": Color(0.35, 0.28, 0.22),
		"leaf_a": Color(0.46, 0.48, 0.14),
		"leaf_b": Color(0.58, 0.55, 0.16),
		"trunk": Color(0.38, 0.28, 0.18),
		"water": true,
		"water_color": Color(0.24, 0.44, 0.50, 0.9),
		"water_depth_color": Color(0.08, 0.20, 0.26),
		"tree_count": 0.45, "grass_count": 0.8,
		"blade_tint": Color(0.95, 0.68, 0.3),
		"fireflies": false,
		"night": false,
	},
	"night": {
		"name": "MIDNIGHT GROVE",
		"seed": 777,
		"sun_color": Color(0.55, 0.65, 0.95), "sun_energy": 0.7,
		"sun_yaw": 250.0, "sun_pitch": 60.0,
		"ambient": Color(0.30, 0.36, 0.55), "ambient_energy": 1.0,
		"designer_note": "moonlight, fireflies, dark forest and glowing waterways",
		"sky_top": Color(0.02, 0.03, 0.09),
		"sky_hz": Color(0.10, 0.14, 0.28),
		"fog_color": Color(0.07, 0.10, 0.20), "fog_density": 0.0055,
		"grass_a": Color(0.08, 0.20, 0.14),
		"grass_b": Color(0.12, 0.28, 0.17),
		"dirt": Color(0.16, 0.14, 0.12),
		"rock": Color(0.20, 0.22, 0.26),
		"cliff": Color(0.14, 0.15, 0.19),
		"leaf_a": Color(0.10, 0.30, 0.18),
		"leaf_b": Color(0.16, 0.40, 0.24),
		"trunk": Color(0.20, 0.14, 0.10),
		"water": true,
		"water_color": Color(0.06, 0.28, 0.34, 0.88),
		"water_depth_color": Color(0.01, 0.10, 0.18),
		"tree_count": 1.2, "grass_count": 0.9,
		"blade_tint": Color(0.55, 0.85, 0.75),
		"fireflies": true,
		"night": true,
	},
}

const ORDER := ["valley", "autumn", "savanna", "night"]

static func get_preset(key: String) -> Dictionary:
	return ALL.get(key, ALL["valley"])

static func next_key(key: String) -> String:
	var i: int = ORDER.find(key)
	i = (i + 1) % ORDER.size()
	return ORDER[i]

static func prev_key(key: String) -> String:
	var i: int = ORDER.find(key)
	i = (i - 1 + ORDER.size()) % ORDER.size()
	return ORDER[i]
