extends "res://scripts/TrackTile.gd"
## Kurve Süd-West: verbindet Süd ↔ West
## Der Bogen liegt in der oberen-rechten Ecke.

func _ready() -> void:
	connections["S"] = true
	connections["W"] = true
	super._ready()


func draw_path() -> void:
	var half = TILE_SIZE / 2.0
	var center = Vector2(-half, half)
	var radius = TILE_SIZE / 2
	# Von 90° (unten = S) bis 180° (links = W)
	draw_curve(center, radius, deg_to_rad(270), deg_to_rad(360))
