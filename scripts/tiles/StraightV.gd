extends "res://scripts/TrackTile.gd"
## Vertikale Gerade: verbindet Nord ↔ Süd

func _ready() -> void:
	connections["N"] = true
	connections["S"] = true
	super._ready()


func draw_path() -> void:
	var half = TILE_SIZE / 2.0
	draw_straight(Vector2(0, -half), Vector2(0, half))
