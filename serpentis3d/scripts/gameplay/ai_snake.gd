class_name AISnake
extends Snake
## AI snake with personality-driven behavior:
## FSM (wander / seek / chase / flee) + weighted steering, wall & obstacle
## avoidance, cut-ahead interception and honest, risk-limited boost use.

enum Mode { WANDER, SEEK, CHASE, FLEE }

const PERSONALITIES := {
	"hunter":   {"n": "Hunter",    "aggr": 0.95, "caution": 0.25, "range": 22.0, "boost_use": 0.6, "colors": [Color(0.72, 0.12, 0.1), Color(1.0, 0.45, 0.1)]},
	"scav":     {"n": "Scavenger","aggr": 0.25, "caution": 0.55, "range": 26.0, "boost_use": 0.25, "colors": [Color(0.16, 0.45, 0.7), Color(0.3, 0.9, 1.0)]},
	"survivor": {"n": "Survivor", "aggr": 0.1,  "caution": 0.85, "range": 18.0, "boost_use": 0.35, "colors": [Color(0.35, 0.42, 0.22), Color(0.8, 0.8, 0.35)]},
	"speedy":   {"n": "Racer",    "aggr": 0.5,  "caution": 0.35, "range": 24.0, "boost_use": 0.85, "colors": [Color(0.55, 0.1, 0.65), Color(1.0, 0.3, 0.8)]},
	"territor": {"n": "Guardian", "aggr": 0.6,  "caution": 0.45, "range": 20.0, "boost_use": 0.2,  "colors": [Color(0.1, 0.35, 0.3), Color(0.2, 1.0, 0.85)]},
	"elite":    {"n": "Phantom",  "aggr": 0.8,  "caution": 0.5,  "range": 28.0, "boost_use": 0.5,  "colors": [Color(0.06, 0.08, 0.14), Color(0.7, 0.85, 1.0)]},
}

var preset := "scav"
var home := Vector3.ZERO
var mode := Mode.WANDER
var aggression := 0.4
var caution := 0.5
var detect_range := 24.0
var boost_use := 0.3

var _think_cd := 0.0
var _wander_angle := 0.0
var _wander_timer := 0.0

var _prey: Snake = null
var _predator: Snake = null
var _prey_d := INF
var _pred_d := INF
var _food_pos := Vector3.INF
var _frame_counter := 0.0

func configure(personality: String, world) -> void:
	preset = personality
	match_world = world
	var p: Dictionary = PERSONALITIES[personality]
	display_name = str(p["n"])
	dorsal = Color(p["colors"][0])
	accent = Color(p["colors"][1])
	aggression = float(p["aggr"])
	caution = float(p["caution"])
	detect_range = float(p["range"])
	boost_use = float(p["boost_use"])

func _ready() -> void:
	super._ready()

func _steer(delta: float) -> void:
	if match_world == null:
		desired_dir = Vector3.FORWARD
		return

	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = randf_range(0.10, 0.20)
		_rethink()

	# --- weighted steering composition ---
	var want := Vector3.ZERO

	match mode:
		Mode.SEEK:
			if _food_pos != Vector3.INF:
				var to_food := (_food_pos - head_pos)
				to_food.y = 0.0
				want += to_food.normalized() * 1.1
			else:
				mode = Mode.WANDER
		Mode.CHASE:
			if _prey != null and is_instance_valid(_prey) and _prey.alive:
				# cut ahead of the prey's head (intercept point)
				var lead: Vector3 = _prey.head_pos + _prey.head_vel * 0.75
				var cut := lead - head_pos
				cut.y = 0.0
				want += cut.normalized() * (0.9 + aggression * 0.5)
			else:
				mode = Mode.WANDER
		Mode.FLEE:
			if _predator != null and is_instance_valid(_predator) and _predator.alive:
				var away := head_pos - _predator.head_pos
				away.y = 0.0
				if away.length_squared() < 4.0:
					away = Vector3(sin(heading) + 0.3, 0.0, cos(heading))
				want += away.normalized() * (1.2 + caution * 0.4)
			else:
				mode = Mode.WANDER
		_:
			_wander_timer -= delta
			if _wander_timer <= 0.0:
				_wander_timer = randf_range(1.4, 3.2)
				_wander_angle = randf_range(-0.9, 0.9) * (1.0 - caution * 0.5)
			var fwd := Vector3(sin(heading), 0.0, cos(heading))
			want += fwd.rotated(Vector3.UP, _wander_angle) * 0.6

	# home bias for territorial types
	if preset == "territor":
		var back := home - head_pos
		back.y = 0.0
		if back.length() > 18.0:
			want += back.normalized() * 0.9

	# --- wall avoidance: steer inside before it becomes fatal ---
	var to_center := -head_pos
	to_center.y = 0.0
	var radial := head_pos.length()
	var R: float = match_world.arena_radius
	var fwd_now := Vector3(sin(heading), 0.0, cos(heading))
	if radial > R - 8.0:
		var urgency := clampf((radial - (R - 8.0)) / 7.0, 0.0, 1.0)
		want += to_center.normalized() * (0.6 + urgency * 2.2)
		want -= head_pos.normalized() * urgency * 1.4 * clampf(fwd_now.dot(head_pos.normalized()) + 0.5, 0.0, 1.5)

	# --- obstacle avoidance ---
	var probe := head_pos + head_vel * 1.4
	for ob in match_world.obstacles:
		var o: Dictionary = ob
		var d := probe - (o["pos"] as Vector3)
		d.y = 0.0
		var r: float = float(o["r"]) + 1.6
		if d.length() < r:
			want += d.normalized() * (1.0 + (r - d.length()) * 0.5)
			want -= fwd_now * 0.4

	# --- immediate crash course: dodge enemy bodies near our path ---
	var obstacle_pos := _body_on_course()
	if obstacle_pos != Vector3.INF:
		var side := _side_of(obstacle_pos)
		var dodge := fwd_now.rotated(Vector3.UP, _signf(float(side)) * (0.7 + 1.8 * caution))
		want += dodge * 1.7

	if want.length_squared() < 0.001:
		want = fwd_now.rotated(Vector3.UP, 0.05)
	desired_dir = Vector3(want.x, 0.0, want.z).normalized()

	# --- boost usage: honest short bursts, rate-limited by personality ---
	input_boost = false
	var wants_speed: bool = \
		(mode == Mode.CHASE and aggression > 0.6 and _prey_d < 14.0) or \
		(mode == Mode.FLEE and _pred_d < 9.0 and caution > 0.25) or \
		(mode == Mode.SEEK and _food_pos != Vector3.INF and head_pos.distance_to(_food_pos) < 9.0 and radial < R - 12.0) or \
		radial > R - 4.5
	if wants_speed and boost_meter > Snake.BOOST_MAX * 0.45 and randf() < boost_use * delta * 8.0:
		input_boost = true

# ------------------------------------------------------------------ helpers

func _rethink() -> void:
	mode = Mode.WANDER
	_prey = null
	_predator = null
	_prey_d = INF
	_pred_d = INF
	_food_pos = Vector3.INF

	if match_world == null:
		return

	# nearest food
	var best_d := detect_range * 1.3
	for f in match_world.food_positions():
		var d: float = head_pos.distance_to(f)
		if d < best_d:
			best_d = d
			_food_pos = f

	var snakes = match_world.get_alive_snakes()
	for s in snakes:
		if s == self or not is_instance_valid(s) or not s.alive:
			continue
		var d: float = head_pos.distance_to(s.head_pos)
		if s.length > length * 1.22 + 1.0 and d < (10.0 + caution * 10.0):
			if d < _pred_d:
				_pred_d = d
				_predator = s
				mode = Mode.FLEE
		elif mode != Mode.FLEE and s.length < length * 0.78 and d < detect_range and aggression > 0.45:
			if d < _prey_d:
				_prey_d = d
				_prey = s
				mode = Mode.CHASE

func _body_on_course() -> Vector3:
	# Sample our predicted path; if an enemy body station sits within lethal
	# reach in the next ~1.1 s of travel, return its position.
	var f := Vector3(sin(heading), 0, cos(heading))
	var look := speed_cur * 1.1 + 2.0
	var probe := head_pos + f * (look * 0.75)
	var candidates: Array = match_world.nearby_stations(probe, look * 0.55 + 2.0, id)
	var best := Vector3.INF
	var best_t := 1.15
	for c in candidates:
		var rel: Vector3 = c["pos"] - head_pos
		var along := rel.dot(f)
		if along < 0.2 or along > speed_cur * best_t + 2.0:
			continue
		var lateral := (rel - f * along).length()
		if lateral < float(c["r"]) + 0.9:
			best_t = along / maxf(speed_cur, 0.1)
			best = c["pos"]
	return best

func _side_of(p: Vector3) -> int:
	var f := Vector3(sin(heading), 0, cos(heading))
	var right := Vector3(f.z, 0, -f.x)  # 90° CW horizontally
	return 1 if (p - head_pos).dot(right) < 0.0 else -1

func _signf(x: float) -> float:
	return 1.0 if x >= 0.0 else -1.0
