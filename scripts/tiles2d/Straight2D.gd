extends Node2D

const TILE_SIZE  = 100.0
const TRACK_W    = 42.0
const ROAD_COL   = Color(0.25, 0.25, 0.28)
const ASPH_COL   = Color(0.55, 0.55, 0.58)
const LINE_COL   = Color(0.95, 0.85, 0.2, 0.9)

var direction: int = 1   # 1 = vorwärts (→), -1 = rückwärts (←)

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var half = TILE_SIZE / 2.0
	var tw   = TRACK_W / 2.0

	# Rand
	draw_rect(Rect2(Vector2(-half, -tw - 3), Vector2(TILE_SIZE, TRACK_W + 6)), ROAD_COL)
	# Asphalt
	draw_rect(Rect2(Vector2(-half, -tw), Vector2(TILE_SIZE, TRACK_W)), ASPH_COL)

	# Gestrichelte Mittellinie
	var seg = half / 4.0
	for i in range(4):
		var x = -half + i * seg * 2 + seg * 0.2
		draw_line(Vector2(x, 0), Vector2(x + seg * 0.6, 0), LINE_COL, 2.5)
	# Kein Richtungspfeil mehr: Geraden sind in beide Richtungen befahrbar.
