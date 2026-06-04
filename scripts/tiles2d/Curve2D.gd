extends Node2D
## Kurve bei rot=0: N+E offen (Bogen oben-rechts)
## Mittelpunkt unten-rechts (+half, +half), Bogen 180°→270°
## Kein Richtungspfeil mehr – die Fahrtrichtung ergibt sich automatisch aus dem Streckenfluss.

const TILE_SIZE  = 100.0
const TRACK_W    = 42.0
const ROAD_COL   = Color(0.25, 0.25, 0.28)
const ASPH_COL   = Color(0.55, 0.55, 0.58)
const LINE_COL   = Color(0.95, 0.85, 0.2, 0.9)

# Beibehalten für Kompatibilität (wird beim Spawn ggf. gesetzt), aber visuell ungenutzt.
var direction: int = 1

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var half    = TILE_SIZE / 2.0
	var radius  = half
	var center  = Vector2(half, half)   # unten-rechts
	var a_start = deg_to_rad(180)       # links vom Zentrum = Norden des Tiles
	var a_end   = deg_to_rad(270)       # oben vom Zentrum  = Osten des Tiles

	# Rand-Band
	_draw_arc_band(center, radius, a_start, a_end, TRACK_W, ROAD_COL, 3.0)
	# Asphalt-Band
	_draw_arc_band(center, radius, a_start, a_end, TRACK_W, ASPH_COL, 0.0)

	# Gestrichelte Mittellinie
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
