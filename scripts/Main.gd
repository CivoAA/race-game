extends Node2D

const GRID_SIZE = 4
const TILE_SIZE = 120

const TILE_SCENES = {
	"straight_h": "res://scenes/tiles/StraightH.tscn",
	"straight_v": "res://scenes/tiles/StraightV.tscn",
	"curve_ne":   "res://scenes/tiles/CurveNE.tscn",
	"curve_nw":   "res://scenes/tiles/CurveNW.tscn",
	"curve_se":   "res://scenes/tiles/CurveSE.tscn",
	"curve_sw":   "res://scenes/tiles/CurveSW.tscn",
}

var grid: Array = []
var selected_tile_type: String = "straight_h"

@onready var grid_node: Node2D = $Grid
@onready var tile_selector = $TileSelector


func _ready() -> void:
	_init_grid()
	_draw_grid_background()


func _init_grid() -> void:
	grid = []
	for row in range(GRID_SIZE):
		var cols = []
		for col in range(GRID_SIZE):
			cols.append(null)
		grid.append(cols)


func _draw_grid_background() -> void:
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var border = ColorRect.new()
			border.size = Vector2(TILE_SIZE, TILE_SIZE)
			border.position = _grid_to_world(row, col)
			border.color = Color(0.3, 0.35, 0.3)
			border.z_index = -1
			grid_node.add_child(border)

			var cell_bg = ColorRect.new()
			cell_bg.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
			cell_bg.position = _grid_to_world(row, col) + Vector2(1, 1)
			cell_bg.color = Color(0.15, 0.18, 0.15)
			grid_node.add_child(cell_bg)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var local_pos = grid_node.to_local(event.position)

		var grid_pixel_size = GRID_SIZE * TILE_SIZE
		if local_pos.x < 0 or local_pos.y < 0 or local_pos.x >= grid_pixel_size or local_pos.y >= grid_pixel_size:
			return

		var cell = _world_to_grid(local_pos)

		if _is_valid_cell(cell):
			if event.button_index == MOUSE_BUTTON_LEFT:
				_place_tile(cell.x, cell.y)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_remove_tile(cell.x, cell.y)


func _place_tile(row: int, col: int) -> void:
	_remove_tile(row, col)

	if selected_tile_type == "delete":
		return

	var scene_path = TILE_SCENES.get(selected_tile_type, "")
	if scene_path == "":
		return

	var scene = load(scene_path)
	if scene == null:
		return

	var tile_instance = scene.instantiate()
	tile_instance.position = _grid_to_world(row, col) + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)
	tile_instance.name = "Tile_%d_%d" % [row, col]
	tile_instance.set_meta("grid_row", row)
	tile_instance.set_meta("grid_col", col)
	tile_instance.set_meta("tile_type", selected_tile_type)

	grid_node.add_child(tile_instance)
	grid[row][col] = tile_instance


func _remove_tile(row: int, col: int) -> void:
	if grid[row][col] != null:
		grid[row][col].queue_free()
		grid[row][col] = null


func _grid_to_world(row: int, col: int) -> Vector2:
	return Vector2(col * TILE_SIZE, row * TILE_SIZE)


func _world_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.y / TILE_SIZE), int(pos.x / TILE_SIZE))


func _is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_SIZE and cell.y >= 0 and cell.y < GRID_SIZE


func get_tile_type(row: int, col: int) -> String:
	if grid[row][col] == null:
		return ""
	return grid[row][col].get_meta("tile_type", "")


func get_grid_state() -> Array:
	var state = []
	for row in range(GRID_SIZE):
		var row_data = []
		for col in range(GRID_SIZE):
			row_data.append(get_tile_type(row, col))
		state.append(row_data)
	return state


func set_selected_tile(type: String) -> void:
	selected_tile_type = type


# ── Fahren-Button ──────────────────────────────────────────────────────────────

func _on_fahren_pressed() -> void:
	var grid_state = get_grid_state()

	# World3D-Szene laden und Grid-State als Metadata übergeben
	var world_scene = load("res://scenes/World3D.tscn")
	if world_scene == null:
		push_error("World3D.tscn nicht gefunden!")
		return

	# Grid-State zwischenspeichern damit World3D ihn lesen kann
	# Wir nutzen ein Autoload-Singleton oder einfach ProjectSettings metadata
	Engine.set_meta("pending_grid_state", grid_state)

	get_tree().change_scene_to_packed(world_scene)
