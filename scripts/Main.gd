extends Node2D

# Grid-Konfiguration
const GRID_SIZE = 4          # 4x4 Felder
const TILE_SIZE = 120        # Pixel pro Feld

# Pfad zu den Tile-Szenen
const TILE_SCENES = {
	"straight_h": "res://scenes/tiles/StraightH.tscn",
	"straight_v": "res://scenes/tiles/StraightV.tscn",
	"curve_ne":   "res://scenes/tiles/CurveNE.tscn",
	"curve_nw":   "res://scenes/tiles/CurveNW.tscn",
	"curve_se":   "res://scenes/tiles/CurveSE.tscn",
	"curve_sw":   "res://scenes/tiles/CurveSW.tscn",
}

# 2D-Array: grid[row][col] = aktuell platzierter Tile-Node (oder null)
var grid: Array = []

# Welcher Tile-Typ gerade im Selector aktiv ist
var selected_tile_type: String = "straight_h"

# Referenz auf den Grid-Node (Kinder-Nodes werden darunter gehängt)
@onready var grid_node: Node2D = $Grid
@onready var tile_selector = $TileSelector


func _ready() -> void:
	_init_grid()
	_draw_grid_background()


# ── Grid initialisieren ────────────────────────────────────────────────────────

func _init_grid() -> void:
	grid = []
	for row in range(GRID_SIZE):
		var cols = []
		for col in range(GRID_SIZE):
			cols.append(null)
		grid.append(cols)


# ── Hintergrund-Grid zeichnen (StaticBody2D + ColorRect pro Zelle) ─────────────

func _draw_grid_background() -> void:
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var cell_bg = ColorRect.new()
			cell_bg.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
			cell_bg.position = _grid_to_world(row, col) + Vector2(1, 1)
			cell_bg.color = Color(0.15, 0.18, 0.15)
			cell_bg.name = "BG_%d_%d" % [row, col]
			grid_node.add_child(cell_bg)

			# Rahmen
			var border = ColorRect.new()
			border.size = Vector2(TILE_SIZE, TILE_SIZE)
			border.position = _grid_to_world(row, col)
			border.color = Color(0.3, 0.35, 0.3)
			border.z_index = -1
			grid_node.add_child(border)


# ── Eingabe ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var local_pos = grid_node.to_local(event.position)

		# Nur reagieren wenn Klick wirklich im Grid-Bereich liegt
		var grid_pixel_size = GRID_SIZE * TILE_SIZE
		if local_pos.x < 0 or local_pos.y < 0 or local_pos.x >= grid_pixel_size or local_pos.y >= grid_pixel_size:
			return

		var cell = _world_to_grid(local_pos)

		if _is_valid_cell(cell):
			if event.button_index == MOUSE_BUTTON_LEFT:
				_place_tile(cell.x, cell.y)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_remove_tile(cell.x, cell.y)


# ── Tile platzieren ────────────────────────────────────────────────────────────

func _place_tile(row: int, col: int) -> void:
	# Zuerst alten Tile entfernen
	_remove_tile(row, col)

	if selected_tile_type == "delete":
		return

	var scene_path = TILE_SCENES.get(selected_tile_type, "")
	if scene_path == "":
		push_warning("Unbekannter Tile-Typ: %s" % selected_tile_type)
		return

	var scene = load(scene_path)
	if scene == null:
		push_error("Szene nicht gefunden: %s" % scene_path)
		return

	var tile_instance = scene.instantiate()
	tile_instance.position = _grid_to_world(row, col) + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)
	tile_instance.name = "Tile_%d_%d" % [row, col]

	# Metadaten speichern für spätere Abfrage (z.B. Autopilot)
	tile_instance.set_meta("grid_row", row)
	tile_instance.set_meta("grid_col", col)
	tile_instance.set_meta("tile_type", selected_tile_type)

	grid_node.add_child(tile_instance)
	grid[row][col] = tile_instance

	print("Tile '%s' bei [%d,%d] platziert." % [selected_tile_type, row, col])


func _remove_tile(row: int, col: int) -> void:
	if grid[row][col] != null:
		grid[row][col].queue_free()
		grid[row][col] = null


# ── Hilfsfunktionen ────────────────────────────────────────────────────────────

func _grid_to_world(row: int, col: int) -> Vector2:
	return Vector2(col * TILE_SIZE, row * TILE_SIZE)


func _world_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.y / TILE_SIZE), int(pos.x / TILE_SIZE))


func _is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_SIZE and cell.y >= 0 and cell.y < GRID_SIZE


# ── Öffentliche API für andere Systeme (z.B. Auto, Shop) ──────────────────────

## Gibt den Tile-Typ an einer Zelle zurück ("" wenn leer)
func get_tile_type(row: int, col: int) -> String:
	if grid[row][col] == null:
		return ""
	return grid[row][col].get_meta("tile_type", "")


## Gibt das komplette Grid als 2D-Array von Typen zurück
func get_grid_state() -> Array:
	var state = []
	for row in range(GRID_SIZE):
		var row_data = []
		for col in range(GRID_SIZE):
			row_data.append(get_tile_type(row, col))
		state.append(row_data)
	return state


## Setzt den aktiv ausgewählten Tile-Typ (wird von TileSelector aufgerufen)
func set_selected_tile(type: String) -> void:
	selected_tile_type = type
