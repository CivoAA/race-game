extends Node2D

const GRID_SIZE = 4
const TILE_SIZE = 120

const SCENE_STRAIGHT  = "res://scenes/tiles2d/Straight2D.tscn"
const SCENE_CURVE     = "res://scenes/tiles2d/Curve2D.tscn"
const SCENE_CURVE_ALT = "res://scenes/tiles2d/Curve2D_alt.tscn"

const SHOP_TYPES      = ["straight", "curve", "curve_alt"]
const SHOP_SLOT_COUNT = 5
const SHOP_COST       = 2
const REROLL_COST     = 1
const SELL_VALUE      = 1

# Grid state
var last_placed_row: int = -1
var last_placed_col: int = -1
var grid: Array = []

# Grid tile selection
var selected_grid_row: int = -1
var selected_grid_col: int = -1
var _grid_highlight: Node2D = null

# Shop / sell state
var shop_slots:         Array = []
var selected_shop_slot: int   = -1
var sell_mode:          bool  = false

# UI nodes (created programmatically)
var _currency_label: Label = null
var _shop_panels:    Array = []
var _sell_panel:     Panel = null
var _flash_tween:    Tween = null

@onready var grid_node:    Node2D = $Grid
@onready var tile_selector         = $TileSelector


func _ready() -> void:
	_init_grid()
	_draw_grid_background()
	_place_start_tile()
	_setup_grid_highlight()
	_setup_shop_ui()

	if Engine.has_meta("saved_grid_state"):
		_restore_grid(Engine.get_meta("saved_grid_state"))
		Engine.remove_meta("saved_grid_state")

	_fill_shop()


# ── Grid init ──────────────────────────────────────────────────────────────────

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


# ── Grid highlight ─────────────────────────────────────────────────────────────

func _setup_grid_highlight() -> void:
	_grid_highlight = Node2D.new()
	_grid_highlight.visible = false
	_grid_highlight.z_index = 10
	var bw  = 3
	var col = Color(1.0, 0.85, 0.0, 0.9)
	for i in range(4):
		var r = ColorRect.new()
		r.color = col
		match i:
			0: r.position = Vector2(0, 0);               r.size = Vector2(TILE_SIZE, bw)
			1: r.position = Vector2(0, TILE_SIZE - bw);  r.size = Vector2(TILE_SIZE, bw)
			2: r.position = Vector2(0, 0);               r.size = Vector2(bw, TILE_SIZE)
			3: r.position = Vector2(TILE_SIZE - bw, 0);  r.size = Vector2(bw, TILE_SIZE)
		_grid_highlight.add_child(r)
	grid_node.add_child(_grid_highlight)


func _update_grid_highlight() -> void:
	if selected_grid_row < 0:
		_grid_highlight.visible = false
	else:
		_grid_highlight.position = _grid_to_world(selected_grid_row, selected_grid_col)
		_grid_highlight.visible  = true


# ── Shop UI ────────────────────────────────────────────────────────────────────

func _setup_shop_ui() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)

	# Currency label – top right (grid right edge = screen x 580, viewport = 700)
	_currency_label = Label.new()
	_currency_label.position = Vector2(592, 10)
	_currency_label.size = Vector2(100, 28)
	_currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_currency_label.add_theme_font_size_override("font_size", 18)
	_currency_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	layer.add_child(_currency_label)
	_update_currency_label()

	# Shop bar – below grid (grid bottom at screen y 540)
	var shop_y = 543
	var shop_x = 100
	var slot_w = 78
	var slot_h = 56
	var gap    = 4

	for i in range(SHOP_SLOT_COUNT):
		var panel = Panel.new()
		panel.position = Vector2(shop_x + i * (slot_w + gap), shop_y)
		panel.size = Vector2(slot_w, slot_h)
		var lbl = Label.new()
		lbl.name = "TypeLabel"
		lbl.size = Vector2(slot_w, slot_h)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		panel.add_child(lbl)
		var idx = i
		panel.gui_input.connect(func(e): _on_shop_slot_gui_input(e, idx))
		layer.add_child(panel)
		_shop_panels.append(panel)

	# Reroll button (right of slots)
	var reroll_x = shop_x + SHOP_SLOT_COUNT * (slot_w + gap) + 4
	var reroll = Button.new()
	reroll.position = Vector2(reroll_x, shop_y)
	reroll.size = Vector2(78, slot_h)
	reroll.text = "🎲 Neu\n(%d💰)" % REROLL_COST
	reroll.pressed.connect(_on_reroll_pressed)
	layer.add_child(reroll)

	# Sell button (right of reroll)
	var sell_x = reroll_x + 78 + 4
	_sell_panel = Panel.new()
	_sell_panel.position = Vector2(sell_x, shop_y)
	_sell_panel.size = Vector2(78, slot_h)
	var sell_lbl = Label.new()
	sell_lbl.name = "SellLabel"
	sell_lbl.text = "💰\nVerkaufen"
	sell_lbl.size = Vector2(78, slot_h)
	sell_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	sell_lbl.add_theme_font_size_override("font_size", 12)
	_sell_panel.add_child(sell_lbl)
	_sell_panel.gui_input.connect(_on_sell_panel_gui_input)
	layer.add_child(_sell_panel)
	_update_sell_panel_style()


func _fill_shop() -> void:
	shop_slots.clear()
	for i in range(SHOP_SLOT_COUNT):
		shop_slots.append(SHOP_TYPES[randi() % SHOP_TYPES.size()])
	_update_shop_ui()


func _update_currency_label() -> void:
	_currency_label.text = "💰 %d" % Economy.get_currency()


func _update_shop_ui() -> void:
	for i in range(SHOP_SLOT_COUNT):
		var panel = _shop_panels[i]
		var lbl   = panel.get_node("TypeLabel") as Label
		var typ   = shop_slots[i]

		if typ == null:
			lbl.text = "—"
		else:
			match typ:
				"straight":  lbl.text = "━━\nGerade"
				"curve":     lbl.text = "╰\nKurve"
				"curve_alt": lbl.text = "╯\nKurve 2"

		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(3)
		if i == selected_shop_slot and typ != null:
			style.bg_color     = Color(0.28, 0.24, 0.08)
			style.border_color = Color(1.0, 0.85, 0.0)
			style.set_border_width_all(2)
		elif typ == null:
			style.bg_color     = Color(0.12, 0.12, 0.14)
			style.border_color = Color(0.25, 0.25, 0.28)
			style.set_border_width_all(1)
		else:
			style.bg_color     = Color(0.20, 0.20, 0.24)
			style.border_color = Color(0.40, 0.40, 0.45)
			style.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", style)


func _update_sell_panel_style() -> void:
	if _sell_panel == null:
		return
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	if sell_mode:
		style.bg_color     = Color(0.35, 0.15, 0.05)
		style.border_color = Color(1.0, 0.6, 0.0)
		style.set_border_width_all(2)
	else:
		style.bg_color     = Color(0.18, 0.10, 0.10)
		style.border_color = Color(0.45, 0.25, 0.25)
		style.set_border_width_all(1)
	_sell_panel.add_theme_stylebox_override("panel", style)


func _on_shop_slot_gui_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if shop_slots[idx] == null:
		return
	if selected_shop_slot == idx:
		selected_shop_slot = -1
	else:
		selected_shop_slot  = idx
		selected_grid_row   = -1
		selected_grid_col   = -1
		sell_mode           = false
		_update_grid_highlight()
		_update_sell_panel_style()
		tile_selector.deselect()
	_update_shop_ui()


func _on_sell_panel_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if selected_grid_row >= 0:
		_sell_grid_tile(selected_grid_row, selected_grid_col)
	elif selected_shop_slot >= 0:
		selected_shop_slot = -1
		_update_shop_ui()
	else:
		sell_mode = not sell_mode
		tile_selector.set_status("Verkauf-Modus" if sell_mode else "")
		_update_sell_panel_style()


func _on_reroll_pressed() -> void:
	if not Economy.spend(REROLL_COST):
		_flash_currency()
		return
	for i in range(SHOP_SLOT_COUNT):
		shop_slots[i] = SHOP_TYPES[randi() % SHOP_TYPES.size()]
	_update_currency_label()
	_update_shop_ui()


func _sell_grid_tile(row: int, col: int) -> void:
	_remove_tile(row, col)
	Economy.add(SELL_VALUE)
	_update_currency_label()
	selected_grid_row = -1
	selected_grid_col = -1
	_update_grid_highlight()
	sell_mode = false
	_update_sell_panel_style()
	tile_selector.deselect()


func _check_shop_auto_reroll() -> void:
	for s in shop_slots:
		if s != null:
			return
	_fill_shop()


func _flash_currency() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_currency_label, "modulate", Color(1, 0.2, 0.2), 0.1)
	_flash_tween.tween_property(_currency_label, "modulate", Color(1, 1, 1), 0.35)


# ── Tile spawnen ───────────────────────────────────────────────────────────────

func _spawn_tile(row: int, col: int, data: Dictionary) -> void:
	var scene_path: String
	match data["type"]:
		"straight":  scene_path = SCENE_STRAIGHT
		"curve_alt": scene_path = SCENE_CURVE_ALT
		_:           scene_path = SCENE_CURVE
	var scene = load(scene_path)
	if scene == null:
		push_error("Szene nicht gefunden: " + scene_path)
		return

	var node = scene.instantiate()
	node.position = _grid_to_world(row, col) + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)
	node.rotation_degrees = data["rotation"]
	node.name = "Tile_%d_%d" % [row, col]

	var dir = data.get("direction", 1)
	if "direction" in node:
		node.direction = dir
		node.queue_redraw()

	if data.get("is_start", false):
		var bg = ColorRect.new()
		bg.size = Vector2(TILE_SIZE, TILE_SIZE)
		bg.position = Vector2(-TILE_SIZE / 2, -TILE_SIZE / 2)
		bg.color = Color(0.1, 0.6, 0.2, 0.3)
		bg.z_index = -1
		node.add_child(bg)
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
		if not _is_valid_cell(cell):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_grid_left_click(cell.x, cell.y)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if selected_grid_row >= 0:
				selected_grid_row = -1
				selected_grid_col = -1
				_update_grid_highlight()
				tile_selector.deselect()

	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_rotate_active(90)


func _handle_grid_left_click(row: int, col: int) -> void:
	var cell_data = grid[row][col]
	var is_start  = (cell_data != null and cell_data.get("is_start", false))

	if is_start:
		return

	if cell_data != null:
		if sell_mode:
			_sell_grid_tile(row, col)
		elif selected_grid_row == row and selected_grid_col == col:
			# Click same tile again → deselect
			selected_grid_row = -1
			selected_grid_col = -1
			_update_grid_highlight()
			tile_selector.deselect()
		else:
			_select_grid_tile(row, col)
		return

	# Empty cell
	if selected_grid_row >= 0:
		_move_selected_tile_to(row, col)
	elif selected_shop_slot >= 0:
		_place_shop_tile(row, col)


func _select_grid_tile(row: int, col: int) -> void:
	selected_shop_slot = -1
	sell_mode          = false
	_update_shop_ui()
	_update_sell_panel_style()
	selected_grid_row = row
	selected_grid_col = col
	last_placed_row   = row
	last_placed_col   = col
	_update_grid_highlight()
	tile_selector.set_status(_type_display_name(grid[row][col]["type"]))


func _move_selected_tile_to(new_row: int, new_col: int) -> void:
	var old_row = selected_grid_row
	var old_col = selected_grid_col
	var data    = grid[old_row][old_col]
	if data == null:
		selected_grid_row = -1
		selected_grid_col = -1
		_update_grid_highlight()
		return

	var move_data = {
		"type":      data["type"],
		"rotation":  data["rotation"],
		"flipped":   data.get("flipped", false),
		"direction": data.get("direction", 1),
	}
	data["node"].queue_free()
	grid[old_row][old_col] = null

	_spawn_tile(new_row, new_col, move_data)
	last_placed_row   = new_row
	last_placed_col   = new_col
	selected_grid_row = -1
	selected_grid_col = -1
	_update_grid_highlight()
	tile_selector.deselect()


func _place_shop_tile(row: int, col: int) -> void:
	var typ = shop_slots[selected_shop_slot]
	if typ == null:
		return
	if not Economy.spend(SHOP_COST):
		_flash_currency()
		return
	var data = {"type": typ, "rotation": 0, "flipped": false, "direction": 1}
	_spawn_tile(row, col, data)
	last_placed_row = row
	last_placed_col = col
	shop_slots[selected_shop_slot] = null
	selected_shop_slot = -1
	_update_currency_label()
	_update_shop_ui()
	_check_shop_auto_reroll()


func _remove_tile(row: int, col: int) -> void:
	if grid[row][col] != null:
		if grid[row][col].get("is_start", false):
			return
		grid[row][col]["node"].queue_free()
		grid[row][col] = null
		if last_placed_row == row and last_placed_col == col:
			last_placed_row = -1
			last_placed_col = -1


# ── Rotation ───────────────────────────────────────────────────────────────────

func _rotate_active(degrees: int) -> void:
	# Rotate selected grid tile; fall back to last placed
	var row = selected_grid_row if selected_grid_row >= 0 else last_placed_row
	var col = selected_grid_col if selected_grid_row >= 0 else last_placed_col
	if row < 0:
		return
	var data = grid[row][col]
	if data == null:
		return
	data["rotation"] = (data["rotation"] + degrees) % 360
	data["node"].rotation_degrees = data["rotation"]


# ── Hilfsfunktionen ────────────────────────────────────────────────────────────

func _type_display_name(typ: String) -> String:
	match typ:
		"straight":  return "Gerade"
		"curve":     return "Kurve"
		"curve_alt": return "Kurve 2"
	return typ

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


func _restore_grid(state: Array) -> void:
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if row == 1 and col == 1:
				continue  # start tile already placed
			var d = state[row][col]
			if typeof(d) != TYPE_DICTIONARY:
				continue
			if d.get("is_start", false):
				continue
			_spawn_tile(row, col, d.duplicate())
	last_placed_row = -1
	last_placed_col = -1


func _on_fahren_pressed() -> void:
	var state = get_grid_state()
	Engine.set_meta("pending_grid_state", state)
	Engine.set_meta("saved_grid_state", state)
	var world_scene = load("res://scenes/World3D.tscn")
	if world_scene:
		get_tree().change_scene_to_packed(world_scene)
