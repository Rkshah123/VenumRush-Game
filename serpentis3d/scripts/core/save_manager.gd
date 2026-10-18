extends Node
## SaveMgr: persistent local settings and progress (versioned JSON, safe defaults).
## JSON numbers come back as float, so int/float keys are coerced on load --
## without that, the type guard below silently resets every numeric setting
## (theme, gfx_mode, best_score, ...) to its default on each restart.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const DEFAULTS := {
	"version": SAVE_VERSION,
	"best_score": 0,
	"best_length": 0.0,
	"total_runs": 0,
	"total_kills": 0,
	"master_volume": 0.85,
	"fullscreen": false,
	"tutorial_seen": false,
	"skin": 0,
	"theme": 0,
	"gfx_mode": 1,   # 0 = 2D top-down, 1 = 3D/2.5D (default keeps the 3D look)
}

var data: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	data = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f == null:
			return
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY:
			for k: String in parsed.keys():
				var pv: Variant = parsed[k]
				if DEFAULTS.has(k):
					var dt := typeof(DEFAULTS[k])
					if dt == TYPE_INT and typeof(pv) == TYPE_FLOAT:
						pv = int(pv)
					elif dt == TYPE_FLOAT and typeof(pv) == TYPE_INT:
						pv = float(pv)
				data[k] = pv
	# Reassert defaults for missing keys, drop unknown types defensively.
	for k: String in DEFAULTS.keys():
		if not data.has(k) or typeof(data[k]) != typeof(DEFAULTS[k]):
			data[k] = DEFAULTS[k]

func save() -> void:
	data["version"] = SAVE_VERSION
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveMgr: cannot open save file for writing.")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func get_value(key: String, def: Variant = null) -> Variant:
	if data.has(key):
		return data[key]
	return def

func set_value(key: String, value: Variant) -> void:
	data[key] = value
	save()

func record_run(score: int, length: float, kills: int) -> bool:
	var is_best: bool = score > int(data.get("best_score", 0))
	data["best_score"] = maxi(int(data.get("best_score", 0)), score)
	data["best_length"] = maxf(float(data.get("best_length", 0.0)), length)
	data["total_runs"] = int(data.get("total_runs", 0)) + 1
	data["total_kills"] = int(data.get("total_kills", 0)) + kills
	save()
	return is_best
