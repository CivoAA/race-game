extends Node2D

const GRID_ROWS = 5
const GRID_COLS = 6
const TILE_SIZE = 100

const SCENE_STRAIGHT  = "res://scenes/tiles2d/Straight2D.tscn"
const SCENE_CURVE     = "res://scenes/tiles2d/Curve2D.tscn"
const SCENE_CURVE_ALT = "res://scenes/tiles2d/Curve2D_alt.tscn"

const SHOP_TYPES = ["straight", "curve"]

# 5 Varianten pro Tile-Typ: Punkte oder Multiplikator
const TILE_VARIANTS = [
	{"points": 1.0,  "multiplier": 1.0, "price": 2,  "variant_label": "+1"},
	{"points": 5.0,  "multiplier": 1.0, "price": 5,  "variant_label": "+5"},
	{"points": 10.0, "multiplier": 1.0, "price": 10, "variant_label": "+10"},
	{"points": 0.0,  "multiplier": 1.5, "price": 8,  "variant_label": "×1.5"},
	{"points": 0.0,  "multiplier": 1.0, "price": 1,  "variant_label": "+0"},
]

const SHOP_SLOT_COUNT = 5
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
var shop_slots:         Array = []   # Array of {type,points,multiplier,price,variant_label} or null
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
	for row in range(GRID_ROWS):
		var cols = []
		for col in range(GRID_COLS):
			cols.append(null)
		grid.append(cols)


func _draw_grid_background() -> void:
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
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
	var data = {
		"type": "straight", "rotation": 0, "flipped": false, "is_start": true,
		"points": 0.0, "multiplier": 1.0, "variant_label": "",
	}
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

	# Currency label – rechts neben dem Grid (Grid endet bei Bildschirm-x=720, Viewport=800)
	_currency_label = Label.new()
	_currency_label.position = Vector2(724, 10)
	_currency_label.size = Vector2(70, 28)
	_currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_currency_label.add_theme_font_size_override("font_size", 18)
	_currency_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	layer.add_child(_currency_label)
	_update_currency_label()

	# Shop-Bar – unterhalb des Grids (Grid-Unterkante bei Bildschirm-y=540)
	var shop_y = 545
	var shop_x = 120
	var slot_w = 74
	var slot_h = 68
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

	# Reroll-Button
	var reroll_x = shop_x + SHOP_SLOT_COUNT * (slot_w + gap) + 4
	var reroll = Button.new()
	reroll.position = Vector2(reroll_x, shop_y)
	reroll.size = Vector2(80, slot_h)
	reroll.text = "🎲 Neu\n(1💰)"
	reroll.pressed.connect(_on_reroll_pressed)
	layer.add_child(reroll)

	# Verkaufen-Panel
	var sell_x = reroll_x + 80 + 4
	_sell_panel = Panel.new()
	_sell_panel.position = Vector2(sell_x, shop_y)
	_sell_panel.size = Vector2(80, slot_h)
	var sell_lbl = Label.new()
	sell_lbl.name = "SellLabel"
	sell_lbl.text = "💰\nVerkaufen"
	sell_lbl.size = Vector2(80, slot_h)
	sell_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	sell_lbl.add_theme_font_size_override("font_size", 12)
	_sell_panel.add_child(sell_lbl)
	_sell_panel.gui_input.connect(_on_sell_panel_gui_input)
	layer.add_child(_sell_panel)
	_update_sell_panel_style()


func _random_shop_item() -> Dictionary:
	var type    = SHOP_TYPES[randi() % SHOP_TYPES.size()]
	var variant = TILE_VARIANTS[randi() % TILE_VARIANTS.size()]
	return {
		"type":          type,
		"points":        variant["points"],
		"multiplier":    variant["multiplier"],
		"price":         variant["price"],
		"variant_label": variant["variant_label"],
	}


func _fill_shop() -> void:
	shop_slots.clear()
	for i in range(SHOP_SLOT_COUNT):
		shop_slots.append(_random_shop_item())
	_update_shop_ui()


func _update_currency_label() -> void:
	_currency_label.text = "💰 %d" % Economy.get_currency()


func _update_shop_ui() -> void:
	for i in range(SHOP_SLOT_COUNT):
		var panel = _shop_panels[i]
		var lbl   = panel.get_node("TypeLabel") as Label
		var slot  = shop_slots[i]

		if slot == null:
			lbl.text = "—"
		else:
			var icon = ""
			match slot["type"]:
				"straight":  icon = "━━"
				"curve":     icon = "╰"
				"curve_alt": icon = "╯"
			lbl.text = "%s\n%s\n%d💰" % [icon, slot["variant_label"], slot["price"]]

		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(3)
		if i == selected_shop_slot and slot != null:
			style.bg_color     = Color(0.28, 0.24, 0.08)
			style.border_color = Color(1.0, 0.85, 0.0)
			style.set_border_width_all(2)
		elif slot == null:
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
	if not Economy.spend(1):
		_flash_currency()
		return
	for i in range(SHOP_SLOT_COUNT):
		shop_slots[i] = _random_shop_item()
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
	if data.get("is_dirt", false):
		var node = _create_dirt_node(data)
		node.position = _grid_to_world(row, col) + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)
		node.rotation_degrees = data["rotation"]
		node.name = "Tile_%d_%d" % [row, col]
		grid_node.add_child(node)
		data["node"] = node
		grid[row][col] = data
		return

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
	elif data.get("is_dirt", false):
		# Dreck-Pfad: grüne Gras-Tönung, nicht interaktiv, gibt ×0.5
		node.modulate = Color(0.42, 0.70, 0.25)
		var dlbl = Label.new()
		dlbl.text = "×0.5"
		dlbl.position = Vector2(-TILE_SIZE / 2 + 2, -TILE_SIZE / 2 + 2)
		dlbl.add_theme_color_override("font_color", Color(0.9, 1.0, 0.4))
		dlbl.add_theme_font_size_override("font_size", 10)
		dlbl.add_theme_constant_override("outline_size", 2)
		dlbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		node.add_child(dlbl)
	elif data.get("variant_label", "") != "":
		var rot_rad = deg_to_rad(data.get("rotation", 0))
		var vlbl = Label.new()
		vlbl.name = "VarLabel"
		vlbl.text = data["variant_label"]
		vlbl.position = Vector2(-TILE_SIZE / 2 + 2, -TILE_SIZE / 2 + 2).rotated(-rot_rad)
		vlbl.rotation_degrees = -data.get("rotation", 0)
		vlbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		vlbl.add_theme_font_size_override("font_size", 14)
		vlbl.add_theme_constant_override("outline_size", 3)
		vlbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		node.add_child(vlbl)

	grid_node.add_child(node)
	data["node"] = node
	grid[row][col] = data


# Erzeugt einen Dirt-Tile-Node mit Gras-Hintergrund und Dreck-Pfad (kein Tile-Scene-Load).
func _create_dirt_node(data: Dictionary) -> Node2D:
	var node  = Node2D.new()
	var half  = TILE_SIZE / 2.0
	var pw    = 20.0          # schmalerer Dreck-Pfad
	var bg_col = Color(0.15, 0.18, 0.15)   # gleiche Hintergrundfarbe wie Grid-Zellen
	var soil   = Color(0.48, 0.30, 0.11)
	var rot    = data.get("rotation", 0)
	var rot_rad = deg_to_rad(rot)

	# Hintergrund (wie normale Grid-Zellen)
	var bg = ColorRect.new()
	bg.size     = Vector2(TILE_SIZE, TILE_SIZE)
	bg.position = Vector2(-half, -half)
	bg.color    = bg_col
	node.add_child(bg)

	if data["type"] == "straight":
		# Schmaler Dreck-Streifen (rotiert mit Node → Weltrichtung automatisch korrekt)
		var road = ColorRect.new()
		road.size     = Vector2(TILE_SIZE, pw)
		road.position = Vector2(-half, -pw / 2.0)
		road.color    = soil
		node.add_child(road)
		# Richtungspfeil dreht sich mit dem Tile (zeigt so immer die richtige Weltrichtung)
		var dir = data.get("direction", 1)
		var arr = Label.new()
		arr.text     = "→" if dir == 1 else "←"
		arr.position = Vector2(-9.0, -12.0)
		arr.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
		arr.add_theme_font_size_override("font_size", 20)
		arr.add_theme_constant_override("outline_size", 2)
		arr.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0, 0.7))
		node.add_child(arr)
	else:
		# Kurven-Dreck-Pfad: schmaler Bogen als Polygon (Basislage rot=0 → S+E)
		var center = Vector2(half, half)
		var r_out  = half + pw * 0.5
		var r_in   = half - pw * 0.5
		var pts    = PackedVector2Array()
		var steps  = 14
		for i in range(steps + 1):
			var a = lerp(PI, PI * 1.5, float(i) / steps)
			pts.append(center + Vector2(cos(a), sin(a)) * r_out)
		for i in range(steps + 1):
			var a = lerp(PI * 1.5, PI, float(i) / steps)
			pts.append(center + Vector2(cos(a), sin(a)) * r_in)
		var arc = Polygon2D.new()
		arc.polygon = pts
		arc.color   = soil
		node.add_child(arc)

	# ×0.5 Badge – position gegen Rotation kompensiert, immer lesbar
	var lbl = Label.new()
	lbl.text             = "×0.5"
	lbl.position         = Vector2(-half + 2.0, -half + 2.0).rotated(-rot_rad)
	lbl.rotation_degrees = -rot
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	node.add_child(lbl)

	return node


# ── Input ──────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var local_pos = grid_node.to_local(event.position)
		if local_pos.x < 0 or local_pos.y < 0 or local_pos.x >= GRID_COLS * TILE_SIZE or local_pos.y >= GRID_ROWS * TILE_SIZE:
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

	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_flip_curve_active()


func _handle_grid_left_click(row: int, col: int) -> void:
	var cell_data = grid[row][col]
	var is_start  = (cell_data != null and cell_data.get("is_start", false))

	if is_start:
		return

	# Dirt-Tiles können durch Shop-Tiles oder verschobene Tiles überschrieben werden
	if cell_data != null and cell_data.get("is_dirt", false):
		if selected_shop_slot >= 0:
			cell_data["node"].queue_free()
			grid[row][col] = null
			_place_shop_tile(row, col)
		elif selected_grid_row >= 0:
			cell_data["node"].queue_free()
			grid[row][col] = null
			_move_selected_tile_to(row, col)
		return

	if cell_data != null:
		if sell_mode:
			_sell_grid_tile(row, col)
		elif selected_grid_row == row and selected_grid_col == col:
			selected_grid_row = -1
			selected_grid_col = -1
			_update_grid_highlight()
			tile_selector.deselect()
		else:
			_select_grid_tile(row, col)
		return

	# Leere Zelle
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
		"type":          data["type"],
		"rotation":      data["rotation"],
		"flipped":       data.get("flipped", false),
		"direction":     data.get("direction", 1),
		"points":        data.get("points", 0.0),
		"multiplier":    data.get("multiplier", 1.0),
		"variant_label": data.get("variant_label", ""),
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
	_invalidate_track()


func _place_shop_tile(row: int, col: int) -> void:
	var slot = shop_slots[selected_shop_slot]
	if slot == null:
		return
	if not Economy.spend(slot["price"]):
		_flash_currency()
		return
	var data = {
		"type":          slot["type"],
		"rotation":      0,
		"flipped":       false,
		"direction":     1,
		"points":        slot["points"],
		"multiplier":    slot["multiplier"],
		"variant_label": slot["variant_label"],
	}
	_spawn_tile(row, col, data)
	last_placed_row = row
	last_placed_col = col
	shop_slots[selected_shop_slot] = null
	selected_shop_slot = -1
	_update_currency_label()
	_update_shop_ui()
	_check_shop_auto_reroll()
	_invalidate_track()


func _remove_tile(row: int, col: int) -> void:
	if grid[row][col] != null:
		if grid[row][col].get("is_start", false) or grid[row][col].get("is_dirt", false):
			return
		grid[row][col]["node"].queue_free()
		grid[row][col] = null
		if last_placed_row == row and last_placed_col == col:
			last_placed_row = -1
			last_placed_col = -1
	_invalidate_track()


# ── Rotation ───────────────────────────────────────────────────────────────────

func _rotate_active(degrees: int) -> void:
	var row = selected_grid_row if selected_grid_row >= 0 else last_placed_row
	var col = selected_grid_col if selected_grid_row >= 0 else last_placed_col
	if row < 0:
		return
	var data = grid[row][col]
	if data == null:
		return
	data["rotation"] = (data["rotation"] + degrees) % 360
	data["node"].rotation_degrees = data["rotation"]
	var vl = data["node"].get_node_or_null("VarLabel")
	if vl is Label:
		var r = deg_to_rad(data["rotation"])
		vl.rotation_degrees = -data["rotation"]
		vl.position = Vector2(-TILE_SIZE / 2 + 2, -TILE_SIZE / 2 + 2).rotated(-r)
	_invalidate_track()


# ── Kurventyp umschalten (F) ───────────────────────────────────────────────────

func _flip_curve_active() -> void:
	var row = selected_grid_row if selected_grid_row >= 0 else last_placed_row
	var col = selected_grid_col if selected_grid_row >= 0 else last_placed_col
	if row < 0:
		return
	var data = grid[row][col]
	if data == null or data.get("is_start", false):
		return
	var t = data["type"]
	if t != "curve" and t != "curve_alt":
		return

	var new_type = "curve_alt" if t == "curve" else "curve"
	var new_data = {
		"type":          new_type,
		"rotation":      data["rotation"],
		"flipped":       data.get("flipped", false),
		"direction":     -1 if new_type == "curve_alt" else 1,
		"points":        data.get("points", 0.0),
		"multiplier":    data.get("multiplier", 1.0),
		"variant_label": data.get("variant_label", ""),
		"is_start":      false,
	}
	data["node"].queue_free()
	grid[row][col] = null
	_spawn_tile(row, col, new_data)

	if selected_grid_row >= 0:
		tile_selector.set_status(_type_display_name(new_type))


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
	return cell.x >= 0 and cell.x < GRID_ROWS and cell.y >= 0 and cell.y < GRID_COLS


# ── API ────────────────────────────────────────────────────────────────────────

func get_grid_state() -> Array:
	var state = []
	for row in range(GRID_ROWS):
		var row_data = []
		for col in range(GRID_COLS):
			var d = grid[row][col]
			if d == null:
				row_data.append("")
			else:
				row_data.append({
					"type":          d["type"],
					"rotation":      d["rotation"],
					"flipped":       d.get("flipped", false),
					"direction":     d.get("direction", 1),
					"is_start":      d.get("is_start", false),
					"is_dirt":       d.get("is_dirt", false),
					"points":        d.get("points", 0.0),
					"multiplier":    d.get("multiplier", 1.0),
					"variant_label": d.get("variant_label", ""),
				})
		state.append(row_data)
	return state


func _restore_grid(state: Array) -> void:
	for row in range(GRID_ROWS):
		if row >= state.size():
			break
		for col in range(GRID_COLS):
			if row == 1 and col == 1:
				continue  # Start-Tile bereits gesetzt
			if col >= state[row].size():
				break
			var d = state[row][col]
			if typeof(d) != TYPE_DICTIONARY:
				continue
			if d.get("is_start", false):
				continue
			_spawn_tile(row, col, d.duplicate())
	last_placed_row = -1
	last_placed_col = -1


func _on_pruefen_pressed() -> void:
	_auto_complete_track()
	if _is_track_valid():
		tile_selector.set_fahren_enabled(true)
		tile_selector.set_status("✓ Strecke fertig!")
	else:
		tile_selector.set_fahren_enabled(false)
		tile_selector.set_status("Keine vollständige Runde möglich")


func _on_fahren_pressed() -> void:
	if not _is_track_valid():
		return
	var state = get_grid_state()
	Engine.set_meta("pending_grid_state", state)
	Engine.set_meta("saved_grid_state",   state)
	var world_scene = load("res://scenes/World3D.tscn")
	if world_scene:
		get_tree().change_scene_to_packed(world_scene)


# ── Strecken-Validierung ────────────────────────────────────────────────────────

# Prüft ob die Strecke eine geschlossene Runde mit korrekter Fahrtrichtung ist.
func _is_track_valid() -> bool:
	var row = 1; var col = 1; var exit_dir = "E"
	var visited: Dictionary = {}
	for _i in range(GRID_ROWS * GRID_COLS * 2):
		var key = "%d_%d" % [row, col]
		if key in visited:
			return (row == 1 and col == 1)
		visited[key] = true
		var nxt = _ac_step(row, col, exit_dir)
		if not _ac_in_bounds(nxt): return false
		var nxt_data = grid[nxt.x][nxt.y]
		if nxt_data == null: return false
		var entry = _ac_opp(exit_dir)
		var nxt_exit = _ac_through(nxt_data, entry)
		if nxt_exit == "": return false
		var t = nxt_data.get("type", "")
		if (t == "curve" or t == "curve_alt") and not _is_curve_dir_ok(nxt_data, entry):
			return false
		row = nxt.x; col = nxt.y; exit_dir = nxt_exit
	return false


# curve/curve_alt: prüft ob das Tile in die richtige Richtung zeigt.
# Jede Rotation hat genau einen korrekten Eintritt pro Kurventyp.
func _is_curve_dir_ok(data: Dictionary, entry: String) -> bool:
	var rot = int(data.get("rotation", 0)) % 360
	var t   = data["type"]
	match rot:
		0:   return (t == "curve" and entry == "S") or (t == "curve_alt" and entry == "E")
		90:  return (t == "curve" and entry == "W") or (t == "curve_alt" and entry == "S")
		180: return (t == "curve" and entry == "N") or (t == "curve_alt" and entry == "W")
		270: return (t == "curve" and entry == "E") or (t == "curve_alt" and entry == "N")
	return false


func _invalidate_track() -> void:
	tile_selector.set_fahren_enabled(false)
	tile_selector.set_status("")


# ── Auto-Vervollständigung ──────────────────────────────────────────────────────

func _remove_all_dirt_tiles() -> void:
	for r in range(GRID_ROWS):
		for c in range(GRID_COLS):
			if grid[r][c] != null and grid[r][c].get("is_dirt", false):
				grid[r][c]["node"].queue_free()
				grid[r][c] = null


func _auto_complete_track() -> void:
	_remove_all_dirt_tiles()
	var path = _build_completion_path()
	for p in path:
		if grid[p["r"]][p["c"]] != null:
			continue
		_spawn_tile(p["r"], p["c"], {
			"type":          p["type"],
			"rotation":      p["rot"],
			"flipped":       false,
			"direction":     p.get("dir", 1),
			"points":        0.0,
			"multiplier":    0.5,
			"variant_label": "",
			"is_start":      false,
			"is_dirt":       true,
		})


# BFS: findet den kürzesten Weg vom offenen Streckenende zurück zu Start [1,1].
# Gibt leeres Array zurück wenn kein Pfad gefunden oder Strecke bereits geschlossen.
func _build_completion_path() -> Array:
	# Schritt 1: Strecke verfolgen bis zum offenen Ende
	var row = 1; var col = 1; var exit_dir = "E"
	var visited: Dictionary = {}
	var open_row = -1; var open_col = -1; var open_exit = ""

	for _i in range(GRID_ROWS * GRID_COLS * 2):
		var key = "%d_%d" % [row, col]
		if key in visited:
			return []  # Strecke ist bereits geschlossen
		visited[key] = true
		var nxt = _ac_step(row, col, exit_dir)
		if not _ac_in_bounds(nxt):
			open_row = row; open_col = col; open_exit = exit_dir; break
		var nxt_data = grid[nxt.x][nxt.y]
		if nxt_data == null:
			open_row = row; open_col = col; open_exit = exit_dir; break
		var nxt_exit = _ac_through(nxt_data, _ac_opp(exit_dir))
		if nxt_exit == "":
			open_row = row; open_col = col; open_exit = exit_dir; break
		row = nxt.x; col = nxt.y; exit_dir = nxt_exit

	if open_row < 0:
		return []

	# Schritt 2: BFS vom offenen Ende zurück zu Start (Eintritt von West)
	var bfs_start = _ac_step(open_row, open_col, open_exit)
	if not _ac_in_bounds(bfs_start):
		return []
	var bfs_entry = _ac_opp(open_exit)
	var start_key = "%d_%d_%s" % [bfs_start.x, bfs_start.y, bfs_entry]

	var queue: Array = [{"r": bfs_start.x, "c": bfs_start.y, "e": bfs_entry}]
	var came_from: Dictionary = {start_key: null}
	var goal_key = ""

	while not queue.is_empty():
		var s = queue.pop_front()
		var sr = s["r"]; var sc = s["c"]; var se = s["e"]
		var sk = "%d_%d_%s" % [sr, sc, se]

		if sr == 1 and sc == 1 and se == "W":
			goal_key = sk; break

		if not (sr == 1 and sc == 1):
			if grid[sr][sc] != null:
				continue

		for opt in _ac_tile_options(se):
			var nc = _ac_step(sr, sc, opt["exit"])
			if not _ac_in_bounds(nc):
				continue
			var nk = "%d_%d_%s" % [nc.x, nc.y, _ac_opp(opt["exit"])]
			if nk in came_from:
				continue
			came_from[nk] = {"prev": sk, "type": opt["type"], "rot": opt["rot"], "dir": opt.get("dir", 1), "r": sr, "c": sc}
			queue.append({"r": nc.x, "c": nc.y, "e": _ac_opp(opt["exit"])})

	if goal_key == "":
		return []

	# Schritt 3: Pfad rekonstruieren
	var path: Array = []
	var cur = goal_key
	while cur != null and came_from.has(cur):
		var cf = came_from[cur]
		if cf == null: break
		path.append(cf)
		cur = cf["prev"]
	path.reverse()
	return path


# ── BFS-Hilfsfunktionen ────────────────────────────────────────────────────────

# Mögliche Tiles pro Eintrittseite – Typ, Rotation, Ausgang und Pfeil-Richtung.
func _ac_tile_options(entry: String) -> Array:
	match entry:
		"N": return [  # Auto fährt Richtung Süd
			{"type": "straight",  "rot": 90,  "exit": "S", "dir":  1},
			{"type": "curve",     "rot": 180, "exit": "W", "dir":  1},
			{"type": "curve_alt", "rot": 270, "exit": "E", "dir": -1},
		]
		"S": return [  # Auto fährt Richtung Nord
			{"type": "straight",  "rot": 90,  "exit": "N", "dir": -1},
			{"type": "curve",     "rot": 0,   "exit": "E", "dir":  1},
			{"type": "curve_alt", "rot": 90,  "exit": "W", "dir": -1},
		]
		"E": return [  # Auto fährt Richtung West
			{"type": "straight",  "rot": 0,   "exit": "W", "dir": -1},
			{"type": "curve",     "rot": 270, "exit": "N", "dir":  1},
			{"type": "curve_alt", "rot": 0,   "exit": "S", "dir": -1},
		]
		"W": return [  # Auto fährt Richtung Ost
			{"type": "straight",  "rot": 0,   "exit": "E", "dir":  1},
			{"type": "curve",     "rot": 90,  "exit": "S", "dir":  1},
			{"type": "curve_alt", "rot": 180, "exit": "N", "dir": -1},
		]
	return []


func _ac_through(data: Dictionary, entry: String) -> String:
	var t   = data.get("type", "")
	var rot = int(data.get("rotation", 0)) % 360
	var conns: Dictionary
	if t == "straight":
		var bn = false; var be = true; var bs = false; var bw = true
		var steps = (rot / 90) % 4
		for _i in range(steps):
			var tn = bw; var te = bn; var ts = be; var tw = bs
			bn = tn; be = te; bs = ts; bw = tw
		conns = {"N": bn, "E": be, "S": bs, "W": bw}
	elif t == "curve" or t == "curve_alt":
		match rot:
			0:   conns = {"N": false, "E": true,  "S": true,  "W": false}
			90:  conns = {"N": false, "E": false, "S": true,  "W": true}
			180: conns = {"N": true,  "E": false, "S": false, "W": true}
			270: conns = {"N": true,  "E": true,  "S": false, "W": false}
			_:   conns = {}
	else:
		return ""
	for d in ["N", "E", "S", "W"]:
		if conns.get(d, false) and d != entry:
			return d
	return ""


func _ac_step(row: int, col: int, dir: String) -> Vector2i:
	match dir:
		"N": return Vector2i(row - 1, col)
		"S": return Vector2i(row + 1, col)
		"E": return Vector2i(row, col + 1)
		"W": return Vector2i(row, col - 1)
	return Vector2i(-1, -1)


func _ac_opp(dir: String) -> String:
	match dir:
		"N": return "S"
		"S": return "N"
		"E": return "W"
		"W": return "E"
	return ""


func _ac_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_ROWS and cell.y >= 0 and cell.y < GRID_COLS
