extends "res://scripts/TrackTile.gd"
## Kurve Nord-Ost: verbindet Nord ↔ Ost
## Der Bogen liegt in der unteren-linken Ecke des Tiles.

func _ready() -> void:
	connections["N"] = true
	connections["E"] = true
	super._ready()


func draw_path() -> void:
	# Bogenmittelpunkt ist unten-links vom Tile-Center
	var half = TILE_SIZE / 2.0
	var center = Vector2(half, -half)
	# Radius = TILE_SIZE damit die Enden genau an den Kanten sitzen
	var radius = TILE_SIZE / 2
	# Von 270° (oben = N) bis 0° (rechts = E)
	draw_curve(center, radius, deg_to_rad(90), deg_to_rad(180))
