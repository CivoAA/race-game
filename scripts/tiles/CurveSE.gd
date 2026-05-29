extends "res://scripts/TrackTile.gd"
## Kurve Süd-Ost: verbindet Süd ↔ Ost
## Der Bogen liegt in der oberen-linken Ecke.

func _ready() -> void:
	connections["S"] = true
	connections["E"] = true
	super._ready()


func draw_path() -> void:
	var half = TILE_SIZE / 2.0
	var center = Vector2(half, half)
	var radius = TILE_SIZE / 2
	# Von 0° (rechts = E) bis 90° (unten = S)
	draw_curve(center, radius, deg_to_rad(180), deg_to_rad(270))
