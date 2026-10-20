extends SceneTree
## DEV TOOL — generate the shared snake scale textures (albedo + normal map).
## Run: godot --headless --script tools/gen_scale_textures.gd
## Writes res://textures/snake_scales_albedo.png / snake_scales_normal.png.
## The tiles wrap seamlessly: 1 horizontal repeat = AROUND_T meters around the
## body, 1 vertical repeat = ALONG_T meters along the body (keep in sync with
## snake_body.gdshader uniforms u_tile).
##
## The scale grid is a staggered brick of rounded DIAMOND scales (real snake
## dorsal scales are diamond plates that overlap toward the tail): hard edge
## where the plate meets the next one, contact shading on the overlap edge,
## 3 interior rib arcs and a soft dome per scale. Albedo is tinted by the
## body shader, so keep it grayscale with strong value structure.

const W := 512
const H := 512
const COLS := 8.0    # scale cells per around tile
const ROWS := 14.0   # scale rows per along tile
const K_NORM := 4.6  # normal bump strength

# fract(sin(...)*big) hash — same style as our shaders, tileable enough here
static func _h01(x: float, y: float, salt: float) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7 + salt * 74.3) * 43758.5453, 1.0)

static func _smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Height field of one scale cell (1 = plate top, 0 = seam/edge).
## u,v are the STAGGERED cell-local coords in [-0.5..0.5].
static func _height(u: float, v: float, cell_salt: float) -> float:
	# rounded diamond distance: |u|^p + |v|^p, elongated along the "around"
	# axis (scales read wider than tall). fcy slightly wider -> diamond look.
	var p := 1.75
	var d := pow(pow(absf(u) * 1.18, p) + pow(absf(v) * 1.42, p), 1.0 / p)
	# hard plate edge: full height inside, drops at the diamond border
	var edge := 1.0 - _smoothstep(0.325, 0.445, d)
	# contact shading: the following plate casts a soft shadow on the lower
	# half of every scale (overlap direction = +v toward the tail)
	var contact := 1.0 - 0.42 * _smoothstep(-0.02, 0.40, v) * edge
	# interior rib arcs: 3 curved ridges that follow the scale's leading edge
	var ribs := 0.10 * sin((u * 14.0 + v * 7.0) + cell_salt * 6.28)
	# gentle dome + center ridge highlight
	var dome := 0.05 * maxf(1.0 - d * d, 0.0) + 0.10 * maxf(1.0 - absf(u) * 2.6, 0.0)
	return clampf(edge * contact + ribs + dome, 0.0, 1.0)

func _init() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var nimg := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		var fy := (float(y) + 0.5) / float(H)
		for x in W:
			var fx := (float(x) + 0.5) / float(W)
			var row := floorf(fy * ROWS)
			# staggered brick: every second row shifted half a cell sideways
			var cell_u := fx * COLS + fmod(row, 2.0) * 0.5
			var col_idx := floorf(cell_u)
			var cell_salt := _h01(col_idx + 0.5, row + 0.5, 0.0)
			var jitter := _h01(col_idx + 0.5, row + 0.5, 3.0)
			var u := fposmod(cell_u, 1.0) - 0.5
			var v := fposmod(fy * ROWS, 1.0) - 0.5
			var hgt := _height(u, v, cell_salt)
			# per-scale value jitter (snakes have lighter/darker plates) +
			# fine grain and the plate shadow term
			var grain := 0.96 + 0.08 * _h01(fx * 61.0, fy * 61.0, 7.0)
			var slope := 0.72 + 0.28 * jitter
			var val: float = clampf(slope * (0.30 + 0.70 * hgt) * grain, 0.0, 1.0)
			img.set_pixel(x, y, Color(val, val, val))
			# --- normal from central differences of the same height field ---
			var e := 1.4 / float(W)
			var hu := (fx * COLS + fmod(row, 2.0) * 0.5)
			var vu := fy * ROWS
			var hx := _height(fposmod(hu + e / COLS, 1.0) - 0.5, fposmod(vu, 1.0) - 0.5, cell_salt) \
				- _height(fposmod(hu - e / COLS, 1.0) - 0.5, fposmod(vu, 1.0) - 0.5, cell_salt)
			var hy := _height(u, fposmod(vu + e, 1.0) - 0.5, cell_salt) \
				- _height(u, fposmod(vu - e, 1.0) - 0.5, cell_salt)
			var nx: float = clampf(hx * K_NORM, -1.0, 1.0)
			var ny: float = clampf(hy * K_NORM, -1.0, 1.0)
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
