class_name ArenaBuilder
extends Node3D
## Gameplay-facing arena shell. Hosts the natural EnvironmentBuilder, which
## paints the whole 3D world (terrain, water, vegetation, sky, atmosphere),
## and exposes the environment's hazards as gameplay obstacle descriptors.
## The visual style is chosen with `arena_key` (an ArenaPreset) — set it
## BEFORE this node enters the tree. `gfx_mode` (0 = 2D top-down, 1 = 3D)
## and `dark` (Dark Theme) must also be set before _ready.

const ARENA_R := 55.0

var arena_key := "valley"
var gfx_mode := 1              # 0 = 2D top-down presentation, 1 = 3D / 2.5D
var dark := false              # Dark Theme arena pass
var obstacles: Array = []   # [{pos: Vector3, r: float}] — trees/boulders cover
var env: EnvironmentBuilder = null

func _ready() -> void:
	env = EnvironmentBuilder.new()
	env.setup(ArenaPresets.get_preset(arena_key), ARENA_R, gfx_mode == 0, dark)
	add_child(env)
	obstacles = env.obtain_obstacles()

## Walkable surface height (climbable boulder domes) for the snake sim. The
## optional travel direction + reach add the JUMP ARC — see environment_builder.gd.
func ground_height_at(x: float, z: float, fx := 0.0, fz := 0.0, jump_reach := 0.0) -> float:
	return env.ground_height_at(x, z, fx, fz, jump_reach) if env != null else 0.0
