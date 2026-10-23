class_name SkinCatalog
extends Object
## Data-driven snake skin presets (spec §11). Unlock by personal best score.
## Each skin = body/head colors + pattern seed; visible on the real snake mesh.

const SKINS := [
	{"name": "VERDANT", "dorsal": Color(0.06, 0.52, 0.44), "accent": Color(0.95, 0.24, 0.60), "belly": Color(0.86, 0.78, 0.58), "seed": 0.50, "pattern": 4, "unlock": 0},
	{"name": "NEON CIRCUIT", "dorsal": Color(0.02, 0.10, 0.16), "accent": Color(0.20, 1.00, 0.90), "belly": Color(0.75, 0.95, 0.95), "seed": 0.15, "pattern": 2, "unlock": 50},
	{"name": "SOLAR SERPENT", "dorsal": Color(0.85, 0.35, 0.05), "accent": Color(1.00, 0.80, 0.20), "belly": Color(1.00, 0.92, 0.60), "seed": 0.80, "pattern": 1, "unlock": 120},
	{"name": "FROSTBITE", "dorsal": Color(0.45, 0.68, 0.95), "accent": Color(0.85, 0.95, 1.00), "belly": Color(0.92, 0.97, 1.00), "seed": 0.35, "pattern": 2, "unlock": 250},
	{"name": "CRIMSON INFERNO", "dorsal": Color(0.45, 0.02, 0.02), "accent": Color(1.00, 0.25, 0.05), "belly": Color(0.95, 0.70, 0.40), "seed": 0.65, "pattern": 3, "unlock": 450},
	{"name": "SHADOW VENOM", "dorsal": Color(0.03, 0.05, 0.03), "accent": Color(0.35, 1.00, 0.30), "belly": Color(0.55, 0.80, 0.45), "seed": 0.25, "pattern": 4, "unlock": 700},
	{"name": "GOLDEN MONARCH", "dorsal": Color(0.75, 0.55, 0.10), "accent": Color(1.00, 0.95, 0.55), "belly": Color(1.00, 0.98, 0.80), "seed": 0.90, "pattern": 1, "unlock": 1000},
	{"name": "COSMIC WARDEN", "dorsal": Color(0.08, 0.03, 0.18), "accent": Color(0.60, 0.40, 1.00), "belly": Color(0.85, 0.75, 1.00), "seed": 0.45, "pattern": 2, "unlock": 1500},
	{"name": "ELECTRA", "dorsal": Color(0.42, 0.08, 0.55), "accent": Color(1.00, 0.41, 0.85), "belly": Color(0.98, 0.90, 0.82), "seed": 0.55, "pattern": 3, "unlock": 60},
	{"name": "TOXIC BLOOM", "dorsal": Color(0.05, 0.14, 0.02), "accent": Color(0.65, 0.95, 0.18), "belly": Color(0.62, 0.72, 0.30), "seed": 0.72, "pattern": 4, "unlock": 2000},
	{"name": "IVORY FANG", "dorsal": Color(0.88, 0.86, 0.80), "accent": Color(0.95, 0.55, 0.05), "belly": Color(0.97, 0.95, 0.88), "seed": 0.95, "pattern": 3, "unlock": 2400},
]

static func count() -> int:
	return SKINS.size()

static func get_skin(i: int) -> Dictionary:
	return SKINS[clampi(i, 0, SKINS.size() - 1)]

static func unlocked(i: int, best: int) -> bool:
	return best >= int(SKINS[clampi(i, 0, SKINS.size() - 1)].get("unlock", 0))
