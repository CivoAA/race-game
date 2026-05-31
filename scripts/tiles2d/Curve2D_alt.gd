extends Node2D
## Kurve 2: gleicher Bogen wie Curve2D (SE-Ecke, S+E offen)
## aber Pfeil zeigt E→S statt S→E (auto fährt andersherum)

const TILE_SIZE  = 100.0
const TRACK_W    = 42.0
const ROAD_COL   = Color(0.25, 0.25, 0.28)
const ASPH_COL   = Color(0.55, 0.55, 0.58)
const LINE_COL   = Color(0.95, 0.85, 0.2, 0.9)
const ARROW_COL  = Color(0.2, 0.6, 1.0, 0.95)  # blau – visuell unterscheidbar

var direction: int = -1   # fest E→S

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var half    = TILE_SIZE / 2.0
	var radius  = half
	var center  = Vector2(half, half)
	var a_start = deg_to_rad(180)
	var a_end   = deg_to_rad(270)

	_draw_arc_band(center, radius, a_start, a_end, TRACK_W, ROAD_COL, 3.0)
	_draw_arc_band(center, radius, a_start, a_end, TRACK_W, ASPH_COL, 0.0)

	var steps = 12
	for i in range(steps):
		if i % 2 == 0:
			var a0 = lerp(a_start, a_end, float(i) / steps)
			var a1 = lerp(a_start, a_end, float(i + 1) / steps)
			draw_line(
				center + Vector2(cos(a0), sin(a0)) * radius,
				center + Vector2(cos(a1), sin(a1)) * radius,
				LINE_COL, 2.5
			)

	var a_mid     = (a_start + a_end) / 2.0
	var arrow_pos = center + Vector2(cos(a_mid), sin(a_mid)) * radius
	var tangent   = a_mid + PI / 2.0 * direction
	_draw_arrow(arrow_pos, tangent)


func _draw_arc_band(center: Vector2, radius: float, a_from: float, a_to: float,
					width: float, color: Color, extra: float) -> void:
	var steps = 24
	var outer = radius + width / 2.0 + extra
	var inner = radius - width / 2.0 - extra
	var pts   = PackedVector2Array()
	for i in range(steps + 1):
		var a = lerp(a_from, a_to, float(i) / steps)
		pts.append(center + Vector2(cos(a), sin(a)) * outer)
	for i in range(steps + 1):
		var a = lerp(a_from, a_to, float(steps - i) / steps)
		pts.append(center + Vector2(cos(a), sin(a)) * inner)
	draw_colored_polygon(pts, color)


func _draw_arrow(pos: Vector2, angle: float) -> void:
	var s     = 10.0
	var tip   = pos + Vector2(cos(angle), sin(angle)) * s
	var left  = pos + Vector2(cos(angle + 2.4), sin(angle + 2.4)) * s * 0.6
	var right = pos + Vector2(cos(angle - 2.4), sin(angle - 2.4)) * s * 0.6
	draw_colored_polygon(PackedVector2Array([tip, left, right]), ARROW_COL)
