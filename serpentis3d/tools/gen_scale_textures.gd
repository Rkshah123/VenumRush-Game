extends SceneTree
## DEV TOOL — generate the shared snake scale textures (albedo + normal map).
## Run: godot --headless --script tools/gen_scale_textures.gd
## Writes res://textures/snake_scales_albedo.png / snake_scales_normal.png.
## The tiles wrap seamlessly: 1 horizontal repeat = AROUND_T meters around the
## body, 1 vertical repeat = ALONG_T meters along the body (keep in sync with
## snake_body.gdshader uniforms u_tile).

const W := 512
const H := 512
const COLS := 8.0    # scale cells per around tile
const ROWS := 12.0   # scale rows per along tile
const K_NORM := 2.6  # normal bump strength

# fract(sin(...)*big) hash — same style as our shaders, tileable enough here
static func _h01(x: float, y: float, salt: float) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7 + salt * 74.3) * 43758.5453, 1.0)

static func _dome(px: float, py: float) -> float:
	# height field of the scale dome, 1 at cell center -> 0 at cell borders
	var u := px * COLS
	var v := py * ROWS
	var row := floorf(v)
	var vc := v - row
	var uc := u + fmod(row, 2.0) * 0.5   # staggered rows (snake-like overlap)
	var col := floorf(uc)
	var fcx: float = (uc - col - 0.5)
	var fcy: float = (vc - 0.5) * 1.30          # cells slightly taller than wide
	var d: float = sqrt(fcx * fcx + fcy * fcy)
	return 1.0 - _smoothstep(0.20, 0.50, d)

static func _smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _init() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var nimg := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		var fy := (float(y) + 0.5) / float(H)
		for x in W:
			var fx := (float(x) + 0.5) / float(W)
			var row := floorf(fy * ROWS)
			var jitter := _h01(floorf(fx * COLS + fmod(row, 2.0) * 0.5), row - floorf(fx * COLS) * 0.0, 1.0)
			# cleaner per-cell jitter: hash by cell center coordinates
			var cell_u := fx * COLS + fmod(row, 2.0) * 0.5
			var col_idx := floorf(cell_u)
			jitter = _h01(col_idx + 0.5, row + 0.5, 0.0)
			var dome := _dome(fx, fy)
			var grain := 0.96 + 0.07 * _h01(fx * 61.0, fy * 61.0, 7.0)
			var val: float = clampf((0.60 + 0.40 * jitter) * (0.50 + 0.50 * dome) * grain, 0.0, 1.0)
			img.set_pixel(x, y, Color(val, val, val))
			# --- normal from central differences of the same height field ---
			var e := 1.5 / float(W)
			var dhx: float = _dome(fx - e, fy) - _dome(fx + e, fy)
			var dhy: float = ( _dome(fx, fy - e) - _dome(fx, fy + e) )
			var nx: float = dhx * K_NORM
			var ny: float = dhy * K_NORM
			var nz := 1.0
			var nl: float = sqrt(nx * nx + ny * ny + nz * nz)
			nimg.set_pixel(x, y, Color(
				(nx / nl * 0.5 + 0.5),
				(ny / nl * 0.5 + 0.5),
				(nz / nl * 0.5 + 0.5)))
	var dir := "res://textures"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + "/snake_scales_albedo.png")
	nimg.save_png(dir + "/snake_scales_normal.png")
	print("GENSCALES wrote textures/snake_scales_albedo.png + snake_scales_normal.png")
	quit()
