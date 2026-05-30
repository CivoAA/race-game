extends Node3D

const TILE_SIZE = 1.2

const SCENE_STRAIGHT = "res://scenes/tiles3d/Straight3D.tscn"
const SCENE_CURVE    = "res://scenes/tiles3d/Curve3D.tscn"


func generate(grid_state: Array) -> void:
	for child in get_children():
		child.queue_free()

	var grid_rows = grid_state.size()
	var grid_cols = grid_state[0].size() if grid_rows > 0 else 0

	for row in range(grid_rows):
		for col in range(grid_cols):
			var d = grid_state[row][col]
			if typeof(d) != TYPE_DICTIONARY:
				continue

			# curve_alt hat dieselbe 3D-Form wie curve
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
			node.rotation_degrees.y = -d["rotation"]
			add_child(node)
