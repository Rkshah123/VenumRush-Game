extends Node
## SaveMgr — persistent local settings & progress (versioned JSON, safe defaults).

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
				data[k] = parsed[k]
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
