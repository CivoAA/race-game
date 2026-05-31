extends Node
## Punkte-System für die 3D-Fahrphase.
## Liest grid_state (mit points/multiplier) aus Engine-Meta bevor World3D.gd es entfernt.
## Erkennt per Auto-Position welches Tile gerade befahren wird und aktualisiert den Score.

const TILE_SIZE_3D = 1.2

var _score:      float   = 0.0
var _last_cell:  Vector2i = Vector2i(-1, -1)
var _grid_state: Array   = []
var _car_node:   Node3D  = null
var _score_label: Label  = null


func _ready() -> void:
	# ScoreDisplay._ready() läuft vor World3D._ready() (Kinder vor Eltern),
	# deshalb ist pending_grid_state hier noch vorhanden.
	if Engine.has_meta("pending_grid_state"):
		_grid_state = Engine.get_meta("pending_grid_state")

	_build_ui()


func _build_ui() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	_score_label = Label.new()
	_score_label.text = "⭐ 0 Punkte"
	_score_label.position = Vector2(0, 12)
	_score_label.size = Vector2(800, 55)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 30)
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.15))
	_score_label.add_theme_constant_override("outline_size", 5)
	_score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	layer.add_child(_score_label)


func _process(_delta: float) -> void:
	if _car_node == null or not is_instance_valid(_car_node):
		_find_car()
		return

	var pos      = _car_node.global_position
	var grid_col = int(pos.x / TILE_SIZE_3D)
	var grid_row = int(pos.z / TILE_SIZE_3D)
	var cell     = Vector2i(grid_row, grid_col)

	if cell == _last_cell:
		return
	if grid_row < 0 or grid_col < 0:
		return
	if grid_row >= _grid_state.size():
		return
	var row_arr = _grid_state[grid_row]
	if grid_col >= row_arr.size():
		return

	_last_cell = cell
	var tile = row_arr[grid_col]
	if typeof(tile) != TYPE_DICTIONARY:
		return

	var pts  = tile.get("points", 0.0)
	var mult = tile.get("multiplier", 1.0)

	if mult != 1.0:
		_score *= mult
	elif pts != 0.0:
		_score += pts
	else:
		return  # start tile or empty – no label update needed

	_score_label.text = "⭐ %d Punkte" % roundi(_score)


func _find_car() -> void:
	# CarRoot > CarController-Node > Car-Node
	var car_root = get_parent().get_node_or_null("CarRoot")
	if car_root == null or car_root.get_child_count() == 0:
		return
	var ctrl = car_root.get_child(0)
	if ctrl == null or ctrl.get_child_count() == 0:
		return
	_car_node = ctrl.get_child(0) as Node3D
