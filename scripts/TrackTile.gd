extends Node2D
## Basis-Skript für alle Streckenabschnitte.
## Jeder Tile definiert:
##   - connections: welche Seiten verbunden sind (N/E/S/W)
##   - draw_path():  zeichnet die Strecke via draw_*()-Calls

# Welche Seiten dieses Tiles offen sind (für spätere Verbindungsprüfung)
# true = offen, false = geschlossen
var connections = {
	"N": false,  # Norden  (oben)
	"E": false,  # Osten   (rechts)
	"S": false,  # Süden   (unten)
	"W": false,  # Westen  (links)
}

const TILE_SIZE = 120
const TRACK_WIDTH = 28.0
const TRACK_COLOR = Color(0.25, 0.25, 0.28)
const ROAD_COLOR  = Color(0.55, 0.55, 0.58)
const LINE_COLOR  = Color(0.95, 0.85, 0.2, 0.85)  # gelbe Mittellinie


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_path()


## Überschreibe diese Methode in jeder Tile-Subklasse
func draw_path() -> void:
	pass


# ── Hilfsmethoden für das Zeichnen ────────────────────────────────────────────

## Zeichnet eine gerade Strecke zwischen zwei Punkten
func draw_straight(from: Vector2, to: Vector2) -> void:
	var dir = (to - from).normalized()
	var perp = Vector2(-dir.y, dir.x)

	# Asphalt
	var half = TRACK_WIDTH / 2.0
	var poly = PackedVector2Array([
		from + perp * (half + 3), to + perp * (half + 3),
		to - perp * (half + 3),   from - perp * (half + 3),
	])
	draw_colored_polygon(poly, TRACK_COLOR)

	var road_poly = PackedVector2Array([
		from + perp * half, to + perp * half,
		to - perp * half,   from - perp * half,
	])
	draw_colored_polygon(road_poly, ROAD_COLOR)

	# Mittellinie (gestrichelt)
	var segments = 6
	var seg_len = from.distance_to(to) / (segments * 2 - 1)
	for i in range(segments):
		var t_start = (i * 2) * seg_len / from.distance_to(to)
		var t_end   = (i * 2 + 1) * seg_len / from.distance_to(to)
		draw_line(from.lerp(to, t_start), from.lerp(to, t_end), LINE_COLOR, 2.0)


## Zeichnet eine Kurve (Kreisbogen) zwischen from_angle und to_angle
## center: Mittelpunkt des Bogens, radius: Radius
func draw_curve(center: Vector2, radius: float, from_angle: float, to_angle: float) -> void:
	var steps = 32
	var outer_r = radius + TRACK_WIDTH / 2.0 + 3
	var inner_r = radius - TRACK_WIDTH / 2.0 - 3
	var road_outer = radius + TRACK_WIDTH / 2.0
	var road_inner = radius - TRACK_WIDTH / 2.0

	var outer_pts = PackedVector2Array()
	var inner_pts = PackedVector2Array()
	var road_outer_pts = PackedVector2Array()
	var road_inner_pts = PackedVector2Array()

	for i in range(steps + 1):
		var t = float(i) / steps
		var angle = lerp(from_angle, to_angle, t)
		outer_pts.append(center + Vector2(cos(angle), sin(angle)) * outer_r)
		inner_pts.append(center + Vector2(cos(angle), sin(angle)) * inner_r)
		road_outer_pts.append(center + Vector2(cos(angle), sin(angle)) * road_outer)
		road_inner_pts.append(center + Vector2(cos(angle), sin(angle)) * road_inner)

	# Asphalt-Rand
	var border_poly = PackedVector2Array()
	for p in outer_pts: border_poly.append(p)
	for i in range(inner_pts.size() - 1, -1, -1): border_poly.append(inner_pts[i])
	draw_colored_polygon(border_poly, TRACK_COLOR)

	# Fahrbahn
	var road_poly = PackedVector2Array()
	for p in road_outer_pts: road_poly.append(p)
	for i in range(road_inner_pts.size() - 1, -1, -1): road_poly.append(road_inner_pts[i])
	draw_colored_polygon(road_poly, ROAD_COLOR)

	# Mittellinie (gestrichelt)
	var mid_pts = []
	for i in range(steps + 1):
		var t = float(i) / steps
		var angle = lerp(from_angle, to_angle, t)
		mid_pts.append(center + Vector2(cos(angle), sin(angle)) * radius)

	var skip = false
	for i in range(0, mid_pts.size() - 1, 2):
		if not skip and i + 1 < mid_pts.size():
			draw_line(mid_pts[i], mid_pts[i + 1], LINE_COLOR, 2.0)
		skip = not skip
