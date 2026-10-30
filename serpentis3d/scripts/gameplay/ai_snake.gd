class_name AISnake
extends Snake
## AI snake with personality-driven behavior:
## FSM (wander / seek / chase / flee) + weighted steering, wall & obstacle
## avoidance, cut-ahead interception and honest, risk-limited boost use.

enum Mode { WANDER, SEEK, CHASE, FLEE }

# body pattern mode per personality (see snake_body.gdshader u_pattern)
const PERSONALITY_PATTERN := {"hunter": 3, "scav": 1, "survivor": 2, "speedy": 4, "territor": 1, "elite": 0, "python": 2, "viper": 3, "mamba": 4, "sidewinder": 1, "cobra": 3, "anaconda": 2, "raptor": 4}

const PERSONALITIES := {
	"hunter":   {"n": "Hunter",    "aggr": 0.95, "caution": 0.25, "range": 22.0, "boost_use": 0.6, "colors": [Color(0.72, 0.12, 0.1), Color(1.0, 0.45, 0.1)]},
	"scav":     {"n": "Scavenger","aggr": 0.25, "caution": 0.55, "range": 26.0, "boost_use": 0.25, "colors": [Color(0.16, 0.45, 0.7), Color(0.3, 0.9, 1.0)]},
	"survivor": {"n": "Survivor", "aggr": 0.1,  "caution": 0.85, "range": 18.0, "boost_use": 0.35, "colors": [Color(0.35, 0.42, 0.22), Color(0.8, 0.8, 0.35)]},
	"speedy":   {"n": "Racer",    "aggr": 0.5,  "caution": 0.35, "range": 24.0, "boost_use": 0.85, "colors": [Color(0.55, 0.1, 0.65), Color(1.0, 0.3, 0.8)]},
	"territor": {"n": "Guardian", "aggr": 0.6,  "caution": 0.45, "range": 20.0, "boost_use": 0.2,  "colors": [Color(0.1, 0.35, 0.3), Color(0.2, 1.0, 0.85)]},
	"elite":    {"n": "Phantom",  "aggr": 0.8,  "caution": 0.5,  "range": 28.0, "boost_use": 0.5,  "colors": [Color(0.06, 0.08, 0.14), Color(0.7, 0.85, 1.0)]},
	"python":   {"n": "Python",   "aggr": 0.35, "caution": 0.7,  "range": 32.0, "boost_use": 0.12, "colors": [Color(0.13, 0.28, 0.12), Color(0.55, 0.75, 0.35)]},
	"viper":    {"n": "Viper",    "aggr": 0.7,  "caution": 0.3,  "range": 26.0, "boost_use": 0.75, "colors": [Color(0.5, 0.08, 0.3), Color(0.95, 0.5, 0.9)]},
	"mamba":    {"n": "Mamba",    "aggr": 0.9,  "caution": 0.35, "range": 30.0, "boost_use": 0.85, "colors": [Color(0.05, 0.3, 0.15), Color(0.4, 1.0, 0.6)]},
	"sidewinder": {"n": "Sidewinder", "aggr": 0.45, "caution": 0.4, "range": 24.0, "boost_use": 0.5, "colors": [Color(0.55, 0.4, 0.15), Color(0.95, 0.8, 0.5)]},
	# --- the three extra villains: independent personalities + palettes ---
	"cobra":    {"n": "Cobra",    "aggr": 0.65, "caution": 0.4,  "range": 27.0, "boost_use": 0.45, "colors": [Color(0.24, 0.15, 0.05), Color(1.0, 0.74, 0.16)], "belly": Color(0.92, 0.80, 0.50), "seed": 0.18},
	"anaconda": {"n": "Anaconda", "aggr": 0.5,  "caution": 0.6,  "range": 31.0, "boost_use": 0.2,  "colors": [Color(0.08, 0.24, 0.18), Color(0.34, 0.95, 0.64)], "belly": Color(0.72, 0.82, 0.56), "seed": 0.63},
	"raptor":   {"n": "Raptor",   "aggr": 0.85, "caution": 0.3,  "range": 25.0, "boost_use": 0.7,  "colors": [Color(0.32, 0.06, 0.10), Color(1.0, 0.30, 0.22)], "belly": Color(0.88, 0.62, 0.50), "seed": 0.41},
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

# --- anti-loop watchdog (orbit/repeat-path recovery) -------------------------
var _stuck_t := 0.0           # watchdog window timer
var _stuck_x := Vector3.INF   # window start position
var _stuck_turn := 0.0        # |Δheading| accumulated over the window
var _stuck_prev_h := 0.0
var _stuck_kick := 0.0        # > 0: forced escape steering is active
var _stuck_sign := 1.0        # kick direction, FIXED for the whole kick
var stuck_kicks := 0          # QA counter: watchdog triggers on this snake
# --- chase timeout ---
var _chase_t := 0.0           # seconds spent chasing the CURRENT prey
var _chase_ban := 0.0         # cooldown after a chase timeout
# --- obstacle slide (stable side, no orbit flip-flop) ---
var _obst_sign := 0.0

var _prey: Snake = null
var _predator: Snake = null
var _prey_d := INF
var _pred_d := INF
var _food_pos := Vector3.INF
var _frame_counter := 0.0
var _weave_t := 0.0
var _steer_tick := 0

func configure(personality: String, world) -> void:
	preset = personality
	match_world = world
	var p: Dictionary = PERSONALITIES[personality]
	display_name = str(p["n"])
	dorsal = Color(p["colors"][0])
	accent = Color(p["colors"][1])
	belly = Color(p.get("belly", Color(0.86, 0.78, 0.58)))
	skin_seed = float(p.get("seed", randf()))
	pattern = int(PERSONALITY_PATTERN.get(personality, 0))
	aggression = float(p["aggr"])
	caution = float(p["caution"])
	detect_range = float(p["range"])
	boost_use = float(p["boost_use"])

func _ready() -> void:
	super._ready()

static var prof_steer_us := 0   # dev profiler: cumulative AI steer µs

func _steer(delta: float) -> void:
	var prof_t0 := Time.get_ticks_usec()
	_steer_impl(delta)
	AISnake.prof_steer_us += Time.get_ticks_usec() - prof_t0

func _steer_impl(delta: float) -> void:
	if match_world == null:
		desired_dir = Vector3.FORWARD
		return

	# --- 30 Hz steering throttle ---
	# The full composition (FSM, obstacle/wall loops, dodges, watchdog) runs
	# every OTHER physics tick; on the skipped tick the previous desired_dir
	# simply persists, so the angular-inertia steering in the base snake
	# stays perfectly smooth (heading still integrates at 60 Hz). Timers run
	# with a doubled delta so all durations stay in game-time. Measured: this
	# alone removes ~40% of the per-tick AI CPU for 13 serpents.
	_steer_tick += 1
	if _steer_tick % 2 == 0:
		return
	delta *= 2.0

	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = randf_range(0.10, 0.20)
		_rethink()

	# chase timeout: a long unproductive chase always degenerates into an
	# escort loop behind the prey. Give up, explore elsewhere for a while.
	_chase_ban = maxf(0.0, _chase_ban - delta)
	if mode == Mode.CHASE:
		_chase_t += delta
		if _chase_t > 7.0:
			mode = Mode.WANDER
			_prey = null
			_chase_t = 0.0
			_chase_ban = 5.0
			_think_cd = 0.4
	else:
		_chase_t = 0.0

	_orbit_watchdog(delta)

	# --- weighted steering composition ---
	# opening relax: every snake explores straight for the first ~2.4 s so the
	# field spreads instead of funneling the whole roster onto one apple
	var relax: bool = match_world != null and float(match_world.match_time) < 2.4

	var want := Vector3.ZERO

	match (Mode.WANDER if relax else mode):
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
				# ALWAYS slide a little toward the arena interior: a pure
				# away-vector against an approaching predator produces the
				# classic two-serpent point-symmetric orbit around empty space
				var inward := -head_pos
				inward.y = 0.0
				if inward.length_squared() > 1.0:
					want += inward.normalized() * 0.55
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

	# sidewinder signature: a steady slithering weave across the heading
	if preset == "sidewinder":
		_weave_t += delta * 2.3
		var right := Vector3(cos(heading), 0.0, -sin(heading))
		want += right * sin(_weave_t) * 0.85
	elif _weave_t != 0.0:
		_weave_t = 0.0

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
	# A pure radial push made serpents ORBIT boulders forever: push in, slide
	# sideways off the push line, push in again. Now the push keeps its brake
	# and a STABLE-SIDE tangential slide steers AROUND the obstacle — the
	# slide side comes from which side of the heading the obstacle sits on
	# (same convention as the _body_on_course dodge) and persists across
	# frames so it can never flip-flop into an orbit.
	var probe := head_pos + head_vel * 1.4
	var slide := 0.0
	for ob in match_world.obstacles:
		var o: Dictionary = ob
		var d := probe - (o["pos"] as Vector3)
		d.y = 0.0
		var r: float = float(o["r"]) + 1.6
		if d.length() < r:
			want += d.normalized() * (1.0 + (r - d.length()) * 0.5)
			want -= fwd_now * 0.4
			var rel := (o["pos"] as Vector3) - head_pos
			var cy := rel.x * fwd_now.z - rel.z * fwd_now.x   # = cross(fwd, rel).y
			if absf(cy) > 0.2:
				slide = signf(cy)
			elif slide == 0.0:
				slide = _obst_sign   # dead-ahead: keep the last stable side
	if slide != 0.0:
		_obst_sign = slide
		# slide AROUND: rotate away from the obstacle's side (positive
		# rotation = the same "turn right away from a left obstacle" rule the
		# body-dodge above already uses)
		want += fwd_now.rotated(Vector3.UP, -slide * (0.55 + caution * 0.30)) * 1.1

	# --- immediate crash course: dodge enemy bodies near our path ---
	var obstacle_pos := _body_on_course()
	if obstacle_pos != Vector3.INF:
		var side := _side_of(obstacle_pos)
		var dodge := fwd_now.rotated(Vector3.UP, _signf(float(side)) * (0.7 + 1.8 * caution))
		want += dodge * 1.7

	if want.length_squared() < 0.001:
		want = fwd_now.rotated(Vector3.UP, 0.05)

	# anti-orbit escape kick: dominates the composition while it lasts (the
	# wall/obstacle pushes inside `want` still weigh in, so the kick can never
	# steer straight into the barrier)
	if _stuck_kick > 0.0:
		_stuck_kick -= delta
		want = fwd_now.rotated(Vector3.UP, _stuck_sign * 1.15) * 1.5 + want * 0.4

	desired_dir = Vector3(want.x, 0.0, want.z).normalized()

	# --- boost usage: honest short bursts, rate-limited by personality ---
	input_boost = false
	var wants_speed: bool = \
		(mode == Mode.CHASE and aggression > 0.6 and _prey_d < 14.0) or \
		(mode == Mode.FLEE and _pred_d < 9.0 and caution > 0.25) or \
		(mode == Mode.SEEK and _food_pos != Vector3.INF and head_pos.distance_to(_food_pos) < 9.0 and radial < R - 12.0) or \
		radial > R - 4.5
	if _stuck_kick <= 0.0 and wants_speed and boost_meter > Snake.BOOST_MAX * 0.45 and randf() < boost_use * delta * 8.0:
		input_boost = true

## Anti-orbit watchdog. Over a 3 s window compare the REAL displacement with
## what this serpent should have covered at its current speed, plus how far
## it spun. Heavy spin + almost no displacement = circling (wander re-rolls
## cancelling a defense push, a flee standoff, a boulder orbit…). Recover by
## abandoning the current mode and a strong, stable-sign escape kick that
## steers out of the loop for ~1.6 s.
func _orbit_watchdog(delta: float) -> void:
	if _stuck_x == Vector3.INF:
		_stuck_x = head_pos
		_stuck_prev_h = heading
		return
	_stuck_t += delta
	_stuck_turn += absf(wrapf(heading - _stuck_prev_h, -PI, PI))
	_stuck_prev_h = heading
	if _stuck_t < 3.0:
		return
	var moved := head_pos.distance_to(_stuck_x)
	var expected := maxf(speed_cur, base_speed()) * _stuck_t
	var spinning := _stuck_turn > TAU * 0.75
	var beached := moved < expected * 0.12
	# window reset
	_stuck_t = 0.0
	_stuck_x = head_pos
	_stuck_turn = 0.0
	if _stuck_kick > 0.0:
		return   # already recovering; do not re-trigger mid-kick
	if (spinning and moved < expected * 0.35) or beached:
		mode = Mode.WANDER
		_prey = null
		_food_pos = Vector3.INF
		_stuck_kick = 1.6
		_stuck_sign = 1.0 if randf() < 0.5 else -1.0
		_think_cd = 0.4
		stuck_kicks += 1

# ------------------------------------------------------------------ helpers

func _rethink() -> void:
	mode = Mode.WANDER
	var prev_prey: Snake = _prey
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
		elif mode != Mode.FLEE and _chase_ban <= 0.0 \
				and s.length < length * 0.78 and d < detect_range and aggression > 0.45:
			if d < _prey_d:
				_prey_d = d
				_prey = s
				mode = Mode.CHASE

	# a NEW chase resets its timeout; re-locking onto the same prey keeps it
	if _prey != prev_prey:
		_chase_t = 0.0

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
