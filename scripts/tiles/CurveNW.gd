extends "res://scripts/TrackTile.gd"
## Kurve Nord-West: verbindet Nord ↔ West
## Der Bogen liegt in der unteren-rechten Ecke.

func _ready() -> void:
	connections["N"] = true
	connections["W"] = true
	super._ready()


func draw_path() -> void:
	var half = TILE_SIZE / 2.0
	var center = Vector2(-half, -half)
	var radius = TILE_SIZE / 2
	# Von 180° (links = W) bis 270° (oben = N)
	draw_curve(center, radius, deg_to_rad(0), deg_to_rad(90))
