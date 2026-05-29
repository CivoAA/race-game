extends "res://scripts/TrackTile.gd"
## Horizontale Gerade: verbindet West ↔ Ost

func _ready() -> void:
	connections["W"] = true
	connections["E"] = true
	super._ready()


func draw_path() -> void:
	var half = TILE_SIZE / 2.0
	draw_straight(Vector2(-half, 0), Vector2(half, 0))
