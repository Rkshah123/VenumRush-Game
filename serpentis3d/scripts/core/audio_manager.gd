extends Node
## AudioMgr — fully procedural audio (no external assets, licensing-safe).
## Generates short PCM effects at startup and plays them through a small voice pool.

const RATE := 22050

var _pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}

func _ready() -> void:
	_streams["eat"] = _gen_eat()
	_streams["eat_rare"] = _gen_rare()
	_streams["eat_gold"] = _gen_gold()
	_streams["death"] = _gen_death()
	_streams["kill"] = _gen_kill()
	_streams["boost"] = _gen_boost()
	_streams["click"] = _gen_click()
	_streams["spawn"] = _gen_spawn()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_pool.append(p)
	_apply_volume()

func _apply_volume() -> void:
	var vol := float(SaveMgr.get_value("master_volume", 0.85))
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(vol, 0.0, 1.0)))

func set_master_volume(v: float) -> void:
	SaveMgr.set_value("master_volume", clampf(v, 0.0, 1.0))
	_apply_volume()

func play(name: String, db_offset: float = 0.0) -> void:
	if not _streams.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = db_offset
			p.pitch_scale = randf_range(0.94, 1.08)
			p.play()
			return

# --- PCM generation helpers -------------------------------------------------

func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s

func _gen_eat() -> AudioStreamWAV:
	var n := int(RATE * 0.09)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 520.0 + 340.0 * (float(i) / n)
		var env := exp(-9.0 * float(i) / n)
		s[i] = sin(TAU * f * t) * 0.35 * env
	return _to_wav(s)

func _gen_rare() -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-5.5 * float(i) / n) * (1.0 if fmod(float(i), RATE * 0.06) > RATE * 0.008 else 0.25)
		var f := 660.0 if float(i) / n < 0.45 else 990.0
		s[i] = sin(TAU * f * t) * 0.3 * env
	return _to_wav(s)

func _gen_gold() -> AudioStreamWAV:
	var n := int(RATE * 0.26)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-4.0 * float(i) / n)
		var v := 0.0
		for f in [523.0, 659.0, 784.0]:
			v += sin(TAU * f * t) * 0.11
		s[i] = v * env
	return _to_wav(s)

func _gen_death() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / RATE
		var env := exp(-3.2 * float(i) / n)
		var sweep := 320.0 - 200.0 * (float(i) / n)
		s[i] = (sin(TAU * sweep * t) * 0.32 + rng.randf_range(-1, 1) * 0.28 * env) * env
	return _to_wav(s)

func _gen_kill() -> AudioStreamWAV:
	var n := int(RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-6.0 * float(i) / n)
		var val := sin(TAU * (180.0 + 520.0 * (float(i) / n)) * t) * 0.3
		var th := 0.0
		if float(i) / n < 0.08:
			th = randf_range(-0.6, 0.6)
		s[i] = (val + th) * env
	return _to_wav(s)

func _gen_boost() -> AudioStreamWAV:
	var n := int(RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var prev := 0.0
	for i in n:
		var x := float(i) / n
		var env := sin(x * PI)
		var white := rng.randf_range(-1, 1)
		prev = prev * 0.92 + white * 0.22   # cheap lowpass noise -> whoosh
		s[i] = prev * env
	return _to_wav(s)

func _gen_click() -> AudioStreamWAV:
	var n := int(RATE * 0.035)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * 1500.0 * t) * 0.25 * exp(-30.0 * float(i) / n)
	return _to_wav(s)

func _gen_spawn() -> AudioStreamWAV:
	var n := int(RATE * 0.2)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-5.0 * float(i) / n)
		var f := 240.0 + 240.0 * (float(i) / n)
		s[i] = sin(TAU * f * t) * 0.22 * env
	return _to_wav(s)
