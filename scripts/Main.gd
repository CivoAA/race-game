extends Node2D

const GRID_SIZE = 4
const TILE_SIZE = 120

const SCENE_STRAIGHT = "res://scenes/tiles2d/Straight2D.tscn"
const SCENE_CURVE    = "res://scenes/tiles2d/Curve2D.tscn"

var selected_type: String = "straight"
var last_placed_row: int = -1
var last_placed_col: int = -1
var grid: Array = []

@onready var grid_node: Node2D = $Grid
@onready var tile_selector    = $TileSelector


func _ready() -> void:
	_init_grid()
	_draw_grid_background()
	_place_start_tile()


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
			var bg = ColorRect.new()
			bg.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
			bg.position = _grid_to_world(row, col) + Vector2(1, 1)
			bg.color = Color(0.15, 0.18, 0.15)
			grid_node.add_child(bg)


func _place_start_tile() -> void:
	var row = 1; var col = 1
	var data = {"type": "straight", "rotation": 0, "flipped": false, "is_start": true}
	_spawn_tile(row, col, data)
	last_placed_row = row
	last_placed_col = col


# ── Tile spawnen ───────────────────────────────────────────────────────────────

func _spawn_tile(row: int, col: int, data: Dictionary) -> void:
	var scene_path = SCENE_STRAIGHT if data["type"] == "straight" else SCENE_CURVE
	var scene = load(scene_path)
	if scene == null:
		push_error("Szene nicht gefunden: " + scene_path)
		return

	var node = scene.instantiate()
	node.position = _grid_to_world(row, col) + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)
	node.rotation_degrees = data["rotation"]
	node.name = "Tile_%d_%d" % [row, col]

	# Direction auf den Node setzen (Curve2D/Straight2D haben direction direkt)
	var dir = data.get("direction", 1)
	if "direction" in node:
		node.direction = dir
		node.queue_redraw()

	# Start-Tile: grüner Hintergrund dahinter
	if data.get("is_start", false):
		var bg = ColorRect.new()
		bg.size = Vector2(TILE_SIZE, TILE_SIZE)
		bg.position = Vector2(-TILE_SIZE / 2, -TILE_SIZE / 2)
		bg.color = Color(0.1, 0.6, 0.2, 0.3)
		bg.z_index = -1
		node.add_child(bg)
		# START-Label
		var lbl = Label.new()
		lbl.text = "START"
		lbl.position = Vector2(-20, -TILE_SIZE / 2 + 4)
		lbl.add_theme_color_override("font_color", Color(0.1, 0.9, 0.3))
		lbl.add_theme_font_size_override("font_size", 11)
		node.add_child(lbl)

	grid_node.add_child(node)
	data["node"] = node
	grid[row][col] = data


# ── Input ──────────────────────────────────────────────────────────────────────

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

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R: _rotate_last(90)
			KEY_F: _flip_last()


func _place_tile(row: int, col: int) -> void:
	if grid[row][col] != null and grid[row][col].get("is_start", false):
		return
	_remove_tile(row, col)
	if selected_type == "delete":
		return
	var data = {"type": selected_type, "rotation": 0, "flipped": false, "direction": 1}
	_spawn_tile(row, col, data)
	last_placed_row = row
	last_placed_col = col


func _remove_tile(row: int, col: int) -> void:
	if grid[row][col] != null:
		if grid[row][col].get("is_start", false):
			return
		grid[row][col]["node"].queue_free()
		grid[row][col] = null
		if last_placed_row == row and last_placed_col == col:
			last_placed_row = -1
			last_placed_col = -1


# ── Rotation & Flip ────────────────────────────────────────────────────────────

func _rotate_last(degrees: int) -> void:
	if last_placed_row < 0:
		return
	var data = grid[last_placed_row][last_placed_col]
	if data == null:
		return
	data["rotation"] = (data["rotation"] + degrees) % 360
	# Einfach Node rotieren – kein Neuzeichnen nötig!
	data["node"].rotation_degrees = data["rotation"]


func _flip_last() -> void:
	if last_placed_row < 0:
		return
	var data = grid[last_placed_row][last_placed_col]
	if data == null:
		return
	# F = Pfeil/Fahrtrichtung umkehren ohne die Form zu ändern
	data["direction"] = -data.get("direction", 1)
	var node = data["node"]
	if "direction" in node:
		node.direction = data["direction"]
		node.queue_redraw()


# ── Hilfsfunktionen ────────────────────────────────────────────────────────────

func _grid_to_world(row: int, col: int) -> Vector2:
	return Vector2(col * TILE_SIZE, row * TILE_SIZE)

func _world_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.y / TILE_SIZE), int(pos.x / TILE_SIZE))

func _is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_SIZE and cell.y >= 0 and cell.y < GRID_SIZE


# ── API ────────────────────────────────────────────────────────────────────────

func get_grid_state() -> Array:
	var state = []
	for row in range(GRID_SIZE):
		var row_data = []
		for col in range(GRID_SIZE):
			var d = grid[row][col]
			if d == null:
				row_data.append("")
			else:
				row_data.append({
					"type":      d["type"],
					"rotation":  d["rotation"],
					"flipped":   d["flipped"],
					"direction": d.get("direction", 1),
					"is_start":  d.get("is_start", false),
				})
		state.append(row_data)
	return state


func set_selected_type(type: String) -> void:
	selected_type = type


func _on_fahren_pressed() -> void:
	Engine.set_meta("pending_grid_state", get_grid_state())
	var world_scene = load("res://scenes/World3D.tscn")
	if world_scene:
		get_tree().change_scene_to_packed(world_scene)
