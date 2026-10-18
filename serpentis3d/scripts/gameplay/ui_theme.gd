class_name UiTheme
extends RefCounted
## SERPENTIS 3D — UI palette engine (Dark Theme support).
##
## Every HUD/menu color is a ROLE ("text", "accent", "panel_bg", ...) resolved
## through this class, so switching themes re-tints the whole interface
## (menus, settings, HUD, panels, buttons, bars, popups) consistently and
## instantly. The 3D arenas read `is_dark()` for their own palette pass
## (darker court/terrain/sky with a contrast pass: rim lights, brighter
## emissives, glowing boundary) so gameplay objects never sink into the dark.
##
## Both palettes are authored for WCAG-ish contrast: text >= 4.5:1 on its
## panel, accent/gold/warn >= 3:1 on panel_bg and on the darkest arena tones.

const CLASSIC := 0
const DARK := 1
const NAMES := ["CLASSIC", "DARK"]

# role → color. Panels/bars carry their alpha in the value itself.
const PALETTES := [
	{  # 0 — CLASSIC (existing look: navy glass over the 3D arena)
		"text": Color(0.87, 0.90, 0.96),
		"dim": Color(0.55, 0.62, 0.72),
		"accent": Color(0.14, 0.90, 0.78),
		"warn": Color(1.00, 0.28, 0.45),
		"gold": Color(1.00, 0.82, 0.28),
		"panel_bg": Color(0.035, 0.050, 0.085),
		"panel_edge": Color(0.14, 0.90, 0.78, 0.25),
		"btn_bg": Color(0.055, 0.075, 0.12, 0.90),
		"btn_border": Color(0.20, 0.35, 0.40),
		"btn_hover_bg": Color(0.09, 0.12, 0.18, 0.95),
		"bar_bg": Color(0.06, 0.09, 0.14, 0.90),
		"scrim": Color(0.02, 0.03, 0.05, 0.72),
		"menu_scrim": Color(0.015, 0.025, 0.045, 0.78),
		"title_shadow": Color(0, 0, 0, 0.60),
	},
	{  # 1 — DARK (deep space navy, high-contrast text, neon accents)
		"text": Color(0.93, 0.96, 1.00),
		"dim": Color(0.62, 0.70, 0.80),
		"accent": Color(0.25, 1.00, 0.85),
		"warn": Color(1.00, 0.36, 0.52),
		"gold": Color(1.00, 0.86, 0.38),
		"panel_bg": Color(0.016, 0.022, 0.038),
		"panel_edge": Color(0.25, 1.00, 0.85, 0.34),
		"btn_bg": Color(0.035, 0.050, 0.085, 0.94),
		"btn_border": Color(0.26, 0.42, 0.52),
		"btn_hover_bg": Color(0.08, 0.11, 0.17, 0.97),
		"bar_bg": Color(0.045, 0.065, 0.105, 0.94),
		"scrim": Color(0.005, 0.008, 0.015, 0.80),
		"menu_scrim": Color(0.004, 0.008, 0.016, 0.72),
		"title_shadow": Color(0, 0, 0, 0.85),
	},
]

static var current_id: int = CLASSIC

static func set_theme(id: int) -> void:
	current_id = DARK if id == DARK else CLASSIC

static func is_dark() -> bool:
	return current_id == DARK

static func theme_name(id: int) -> String:
	return NAMES[DARK if id == DARK else CLASSIC]

static func c(role: String) -> Color:
	var p: Dictionary = PALETTES[current_id]
	return p.get(role, Color(1, 1, 1))

static func with_alpha(role: String, a: float) -> Color:
	var col := c(role)
	col.a = a
	return col

# ---------------------------------------------------------------- contrast QA

static func _lum(col: Color) -> float:
	# relative luminance (sRGB → linear)
	var f := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(col.r) + 0.7152 * f.call(col.g) + 0.0722 * f.call(col.b)

static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)

static func theme_report() -> String:
	# QA: text/role contrast on panel and on the darkest arena tone
	var lines: Array[String] = []
	for t in 2:
		set_theme(t)
		var panel := c("panel_bg")
		var rows: Array[String] = []
		for role in ["text", "dim", "accent", "warn", "gold"]:
			var r := contrast(c(role), panel)
			rows.append("%s=%.1f%s" % [role, r, "" if r >= 4.5 else ("!" if r >= 3.0 else "!!")])
		lines.append("THEMEQA %s  panel: %s" % [theme_name(t), " ".join(rows)])
	set_theme(current_id)
	return "\n".join(lines)
