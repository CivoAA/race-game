extends Node3D
## Lädt 3D-Tile-Szenen und rotiert sie – kein Mathe mehr!

const TILE_SIZE = 1.2

const SCENE_STRAIGHT = "res://scenes/tiles3d/Straight3D.tscn"
const SCENE_CURVE    = "res://scenes/tiles3d/Curve3D.tscn"


func generate(grid_state: Array) -> void:
	for child in get_children():
		child.queue_free()

	for row in range(4):
		for col in range(4):
			var d = grid_state[row][col]
			if typeof(d) != TYPE_DICTIONARY:
				continue

			var scene_path = SCENE_STRAIGHT if d["type"] == "straight" else SCENE_CURVE
			var scene = load(scene_path)
			if scene == null:
				push_error("3D-Tile-Szene nicht gefunden: " + scene_path)
				continue

			var node = scene.instantiate()
			node.position = Vector3(
				col * TILE_SIZE + TILE_SIZE / 2.0,
				0.0,
				row * TILE_SIZE + TILE_SIZE / 2.0
			)

			# Rotation direkt aus Grid-State übernehmen
			# Y-Achse in 3D entspricht Z-Rotation in 2D (von oben)
			# 2D rotation_degrees clockwise = 3D rotation_degrees Y-Achse negativ
			node.rotation_degrees.y = -d["rotation"]

			add_child(node)
