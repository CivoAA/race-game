extends Node2D

# Grid-Dimensionen: variabel, werden in _ready aus Economy (Upgrade) gesetzt
var GRID_ROWS: int = 5
var GRID_COLS: int = 6
const TILE_SIZE = 100

var CurrencyHudScript = load(Paths.SCRIPT_CURRENCY_HUD)
var UpgradeMenuScript  = load(Paths.SCRIPT_UPGRADE_MENU)

const SHOP_TYPES = ["straight", "curve"]

# Tiles haben keine eigenen Boni mehr: eine uniforme Variante (Ertrag = +1 pro
# überfahrenem Tile, im CarController berechnet – unabhängig vom Tile).
const TILE_VARIANTS = [
	{"points": 0.0, "multiplier": 1.0, "price": 3, "variant_label": ""},
]

const SHOP_SLOT_COUNT = 5
const SELL_VALUE      = 1
const RAMP_PRICE      = 6   # Preis für ein Rampen-Paar

# Upgrade-Tabellen: points/multiplier pro combine_level (0–4)
const POINT_UPGRADE_DATA = {
	"+1":  {"points": [1.0,  3.0,  6.0,  10.0,  15.0],  "labels": ["+1",  "+3",  "+6",  "+10",  "+15"]},
	"+5":  {"points": [5.0,  12.0, 22.0, 35.0,  50.0],  "labels": ["+5",  "+12", "+22", "+35",  "+50"]},
	"+10": {"points": [10.0, 25.0, 45.0, 70.0,  100.0], "labels": ["+10", "+25", "+45", "+70",  "+100"]},
}
# self_modulate-Tönung pro combine_level (trifft nur Road-Zeichnung, nicht Kind-Labels)
const COMBINE_TINTS = [
	Color(1.0, 1.0,  1.0),   # 0 – normal
	Color(1.0, 0.97, 0.78),  # 1 – warm creme
	Color(1.0, 0.88, 0.48),  # 2 – gold
	Color(1.0, 0.72, 0.20),  # 3 – orange-gold
	Color(1.0, 0.50, 0.05),  # 4 – Feuer-gold
]

# Grid state
var last_placed_row: int = -1
var last_placed_col: int = -1
var grid: Array = []

# Bonusfelder (zellenbasiert, unabhängig von den Tiles)
var bonus_grid: Array = []            # [r][c] = null oder {label, points, mult}
var _bonus_marker_nodes: Array = []   # gezeichnete Marker-Nodes
var _bonus_sig_on_open: String = ""   # Bonus-Signatur beim Öffnen des Upgrade-Menüs

# Grid tile selection
var selected_grid_row: int = -1
var selected_grid_col: int = -1
var _grid_highlight: Node2D = null

# Shop / sell state
var shop_slots:         Array = []   # Array of {type,points,multiplier,price,variant_label} or null
var selected_shop_slot: int   = -1
var sell_mode:          bool  = false
var ramp_preview_rot:   int   = 0     # Aktuelle Richtung für das nächste Rampen-Paar

# UI nodes (created programmatically)
var _currency_hud           = null   # CurrencyHud-Instanz
var _shop_panels:    Array = []
var _sell_panel:     Panel = null
var _upgrade_menu           = null   # UpgradeMenu-Instanz
var _menu_open:      bool = false

@onready var grid_node:    Node2D = $Grid
@onready var tile_selector         = $TileSelector


func _ready() -> void:
	GRID_ROWS = Economy.get_grid_rows()
	GRID_COLS = Economy.get_grid_cols()
	_init_grid()
	_draw_grid_background()
	_place_start_tile()
	_setup_grid_highlight()
	_setup_shop_ui()

	if Engine.has_meta("saved_grid_state"):
		_restore_grid(Engine.get_meta("saved_grid_state"))
		Engine.remove_meta("saved_grid_state")
	elif Economy.has_track():
		_restore_grid(Economy.get_track())

	_fill_shop()
	_roll_bonus_fields()


# ── Grid init ──────────────────────────────────────────────────────────────────

func _init_grid() -> void:
	grid = []
	bonus_grid = []
	for row in range(GRID_ROWS):
		var cols = []
		var bcols = []
		for col in range(GRID_COLS):
			cols.append(null)
			bcols.append(null)
		grid.append(cols)
		bonus_grid.append(bcols)


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

	# Gemeinsame Währungs-HUD (oben mittig, identisch in 2D- und 3D-View)
	_currency_hud = CurrencyHudScript.new()
	add_child(_currency_hud)

	# Rechte Seitenleiste: x=752 bis x=956 (204px), volle Höhe
	# Grid endet bei x=148+600=748; 4px Abstand → Panel bei 752
	const PANEL_X  = 752
	const PANEL_W  = 204
	const SLOT_W   = 188   # PANEL_W - 16 (8px Padding je Seite)
	const SLOT_H   = 74
	const SLOT_GAP = 4
	const START_Y  = 42   # unterhalb der CurrencyHUD

	# Hintergrund-Panel
	var shop_bg = Panel.new()
	shop_bg.position = Vector2(PANEL_X, 0)
	shop_bg.size     = Vector2(PANEL_W, 540)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color          = Color(0.09, 0.10, 0.14)
	bg_style.border_width_left = 1
	bg_style.border_color      = Color(0.20, 0.23, 0.32)
	shop_bg.add_theme_stylebox_override("panel", bg_style)
	layer.add_child(shop_bg)

	# "SHOP" Header
	var shop_header = Label.new()
	shop_header.text = "SHOP"
	shop_header.position = Vector2(PANEL_X, 8)
	shop_header.size = Vector2(PANEL_W, 28)
	shop_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_header.add_theme_font_size_override("font_size", 11)
	shop_header.add_theme_color_override("font_color", Color(0.32, 0.37, 0.52))
	layer.add_child(shop_header)

	# Shop-Slots (vertikal gestapelt)
	for i in range(SHOP_SLOT_COUNT):
		var panel = Panel.new()
		panel.position = Vector2(PANEL_X + 8, START_Y + i * (SLOT_H + SLOT_GAP))
		panel.size = Vector2(SLOT_W, SLOT_H)

		# Slot-Nummer (oben links, sehr klein, gedimmt)
		var num_lbl = Label.new()
		num_lbl.name = "NumLabel"
		num_lbl.text = "%d" % (i + 1)
		num_lbl.position = Vector2(5, 3)
		num_lbl.size = Vector2(18, 14)
		num_lbl.add_theme_font_size_override("font_size", 9)
		num_lbl.add_theme_color_override("font_color", Color(0.26, 0.30, 0.42))
		panel.add_child(num_lbl)

		# Haupt-Label (Typ + Preis)
		var lbl = Label.new()
		lbl.name = "TypeLabel"
		lbl.size = Vector2(SLOT_W, SLOT_H)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		panel.add_child(lbl)

		var idx = i
		panel.gui_input.connect(func(e): _on_shop_slot_gui_input(e, idx))
		layer.add_child(panel)
		_shop_panels.append(panel)

	# Position nach den Slots
	var after_y = START_Y + SHOP_SLOT_COUNT * (SLOT_H + SLOT_GAP) + 6

	# Trennlinie
	var sep = ColorRect.new()
	sep.position = Vector2(PANEL_X + 8, after_y)
	sep.size = Vector2(SLOT_W, 1)
	sep.color = Color(0.20, 0.23, 0.32)
	layer.add_child(sep)

	# Reroll-Button
	var reroll = Button.new()
	reroll.position = Vector2(PANEL_X + 8, after_y + 6)
	reroll.size = Vector2(SLOT_W, 44)
	reroll.text = "🎲  Neu würfeln  (1💰)"
	reroll.pressed.connect(_on_reroll_pressed)
	_style_shop_action_btn(reroll, Color(0.22, 0.27, 0.42))
	layer.add_child(reroll)

	# Verkaufen-Panel
	_sell_panel = Panel.new()
	_sell_panel.position = Vector2(PANEL_X + 8, after_y + 56)
	_sell_panel.size = Vector2(SLOT_W, 44)
	var sell_lbl = Label.new()
	sell_lbl.name = "SellLabel"
	sell_lbl.text = "💰  Verkaufen"
	sell_lbl.size = Vector2(SLOT_W, 44)
	sell_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	sell_lbl.add_theme_font_size_override("font_size", 12)
	_sell_panel.add_child(sell_lbl)
	_sell_panel.gui_input.connect(_on_sell_panel_gui_input)
	layer.add_child(_sell_panel)
	_update_sell_panel_style()


func _style_shop_action_btn(btn: Button, accent: Color) -> void:
	var C_S  = Color(0.13, 0.15, 0.21)
	var C_S2 = Color(0.09, 0.10, 0.14)
	var C_T  = Color(0.82, 0.85, 0.90)
	var _mk = func(bg: Color, bc: Color) -> StyleBoxFlat:
		var sb = StyleBoxFlat.new()
		sb.bg_color = bg; sb.border_width_left = 3; sb.border_color = bc
		sb.set_corner_radius_all(4)
		sb.content_margin_top = 6; sb.content_margin_bottom = 6
		return sb
	btn.add_theme_stylebox_override("normal",  _mk.call(C_S,                 accent.darkened(0.5)))
	btn.add_theme_stylebox_override("hover",   _mk.call(C_S.lightened(0.07), accent))
	btn.add_theme_stylebox_override("pressed", _mk.call(C_S2,                accent))
	btn.add_theme_stylebox_override("focus",   _mk.call(C_S,                 accent.darkened(0.5)))
	btn.add_theme_color_override("font_color", C_T)
	btn.add_theme_font_size_override("font_size", 12)


func _random_shop_item() -> Dictionary:
	if randf() < 0.18:  # ~18 % Chance auf Rampe
		return {"type": "ramp", "points": 0.0, "multiplier": 1.0,
				"price": RAMP_PRICE, "variant_label": ""}
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
	# Die CurrencyHud aktualisiert sich selbst jeden Frame – nichts zu tun.
	pass


func _update_shop_ui() -> void:
	for i in range(SHOP_SLOT_COUNT):
		var panel = _shop_panels[i]
		var lbl   = panel.get_node("TypeLabel") as Label
		var slot  = shop_slots[i]

		if slot == null:
			lbl.text = "—"
		else:
			if slot["type"] == "ramp":
				var dirs = ["→", "↓", "←", "↑"]
				lbl.text = "⛰ %s\nRampe\n%d💰" % [dirs[ramp_preview_rot / 90], slot["price"]]
			else:
				var icon = ""
				match slot["type"]:
					"straight":  icon = "━━"
					"curve":     icon = "╰"
					"curve_alt": icon = "╯"
				if slot["variant_label"] == "":
					lbl.text = "%s\n%d💰" % [icon, slot["price"]]
				else:
					lbl.text = "%s\n%s\n%d💰" % [icon, slot["variant_label"], slot["price"]]

		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(5)
		if i == selected_shop_slot and slot != null:
			style.bg_color     = Color(0.22, 0.18, 0.05)
			style.border_color = Color(1.0, 0.80, 0.0)
			style.border_width_left  = 3
			style.border_width_right = 1
			style.border_width_top   = 1
			style.border_width_bottom = 1
		elif slot == null:
			style.bg_color     = Color(0.10, 0.11, 0.15)
			style.border_color = Color(0.18, 0.20, 0.28)
			style.set_border_width_all(1)
		else:
			style.bg_color     = Color(0.14, 0.16, 0.22)
			style.border_color = Color(0.28, 0.32, 0.46)
			style.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", style)

		# TypeLabel-Farbe: gedimmt wenn leer, normal sonst
		var lbl2 = panel.get_node_or_null("TypeLabel") as Label
		if lbl2 != null:
			if slot == null:
				lbl2.add_theme_color_override("font_color", Color(0.28, 0.32, 0.42))
			elif i == selected_shop_slot:
				lbl2.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
			else:
				lbl2.add_theme_color_override("font_color", Color(0.82, 0.85, 0.90))


func _update_sell_panel_style() -> void:
	if _sell_panel == null:
		return
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(5)
	if sell_mode:
		style.bg_color       = Color(0.32, 0.12, 0.05)
		style.border_color   = Color(1.0, 0.55, 0.08)
		style.border_width_left   = 3
		style.border_width_right  = 1
		style.border_width_top    = 1
		style.border_width_bottom = 1
	else:
		style.bg_color     = Color(0.16, 0.10, 0.10)
		style.border_color = Color(0.42, 0.22, 0.22)
		style.set_border_width_all(1)
	_sell_panel.add_theme_stylebox_override("panel", style)

	var lbl = _sell_panel.get_node_or_null("SellLabel") as Label
	if lbl != null:
		lbl.add_theme_color_override("font_color",
			Color(1.0, 0.65, 0.35) if sell_mode else Color(0.65, 0.40, 0.38))


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
	if _currency_hud != null:
		_currency_hud.flash()


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

	# Rampen-Tiles: programmatisch gezeichnet, keine Szene
	if data["type"] in ["ramp_start", "ramp_end"]:
		var node = _create_ramp_node(data)
		node.position = _grid_to_world(row, col) + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)
		node.rotation_degrees = data["rotation"]
		node.name = "Tile_%d_%d" % [row, col]
		grid_node.add_child(node)
		data["node"] = node
		grid[row][col] = data
		return

	var scene_path: String
	match data["type"]:
		"straight":  scene_path = Paths.SCENE_TILE_STRAIGHT_2D
		"curve_alt": scene_path = Paths.SCENE_TILE_CURVE_ALT_2D
		_:           scene_path = Paths.SCENE_TILE_CURVE_2D
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
		# Dreck-Pfad: grüne Gras-Tönung, nicht interaktiv, gibt +0.1 statt +1
		node.modulate = Color(0.42, 0.70, 0.25)
		var dlbl = Label.new()
		dlbl.text = "+0.1"
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

	# Kombinations-Visuell: self_modulate trifft nur _draw des Tile-Nodes, nicht Kind-Labels
	var clvl = data.get("combine_level", 0)
	if clvl > 0 and not data.get("is_dirt", false) and not data.get("is_start", false):
		node.self_modulate = COMBINE_TINTS[clvl]
		var rot_rad  = deg_to_rad(data.get("rotation", 0))
		var slbl     = Label.new()
		slbl.name    = "StarLabel"
		slbl.text    = "★".repeat(clvl)
		slbl.position = Vector2(0.0, TILE_SIZE / 2.0 - 14.0).rotated(-rot_rad)
		slbl.rotation_degrees = -data.get("rotation", 0)
		slbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
		slbl.add_theme_font_size_override("font_size", 11)
		slbl.add_theme_constant_override("outline_size", 2)
		slbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		node.add_child(slbl)

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

	# +0.1 Badge – position gegen Rotation kompensiert, immer lesbar
	var lbl = Label.new()
	lbl.text             = "+0.1"
	lbl.position         = Vector2(-half + 2.0, -half + 2.0).rotated(-rot_rad)
	lbl.rotation_degrees = -rot
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	node.add_child(lbl)

	return node


# Rampen-Tile-Node (programmatisch, top-down Ansicht)
# rot=0 Basislage: Eingang von links (W), Ausgang nach rechts (E).
# Die Node-Rotation dreht das visuelle in die richtige Weltrichtung.
func _create_ramp_node(data: Dictionary) -> Node2D:
	var node      = Node2D.new()
	var half      = TILE_SIZE / 2.0
	var pw        = 42.0
	var is_start  = data["type"] == "ramp_start"
	var rot       = data.get("rotation", 0)
	var rot_rad   = deg_to_rad(rot)

	var road_col  = Color(0.25, 0.25, 0.28)
	var asph_col  = Color(0.55, 0.55, 0.58)
	var ramp_col  = Color(0.95, 0.55, 0.08)   # Orange für Rampen-Bereich

	# Äußerer Rahmen
	var outer = ColorRect.new()
	outer.size     = Vector2(TILE_SIZE, pw + 6)
	outer.position = Vector2(-half, -(pw + 6) / 2.0)
	outer.color    = road_col
	node.add_child(outer)

	if is_start:
		# Linke Hälfte: normaler Asphalt (Einfahrt)
		var asp = ColorRect.new()
		asp.size     = Vector2(half, pw)
		asp.position = Vector2(-half, -pw / 2.0)
		asp.color    = asph_col
		node.add_child(asp)
		# Rechte Hälfte: oranger Rampenbereich (Absprung)
		var ramp = ColorRect.new()
		ramp.size     = Vector2(half, pw)
		ramp.position = Vector2(0.0, -pw / 2.0)
		ramp.color    = ramp_col
		node.add_child(ramp)
		# Dreieck-Pfeil am Absprungpunkt
		var tri = Polygon2D.new()
		tri.polygon = PackedVector2Array([
			Vector2(half - 3, 0), Vector2(half - 17, -13), Vector2(half - 17, 13)
		])
		tri.color = Color(1, 1, 1, 0.95)
		node.add_child(tri)
	else:
		# Linke Hälfte: oranger Bereich (Landung)
		var ramp = ColorRect.new()
		ramp.size     = Vector2(half, pw)
		ramp.position = Vector2(-half, -pw / 2.0)
		ramp.color    = ramp_col
		node.add_child(ramp)
		# Rechte Hälfte: normaler Asphalt (Ausfahrt)
		var asp = ColorRect.new()
		asp.size     = Vector2(half, pw)
		asp.position = Vector2(0.0, -pw / 2.0)
		asp.color    = asph_col
		node.add_child(asp)
		# Dreieck-Pfeil am Landepunkt
		var tri = Polygon2D.new()
		tri.polygon = PackedVector2Array([
			Vector2(-half + 3, 0), Vector2(-half + 17, -13), Vector2(-half + 17, 13)
		])
		tri.color = Color(1, 1, 1, 0.95)
		node.add_child(tri)

	# Etikett (gegen Rotation kompensiert)
	var lbl = Label.new()
	lbl.name             = "VarLabel"
	lbl.text             = "⛰↑" if is_start else "⛰↓"
	lbl.position         = Vector2(-half + 2, -half + 2).rotated(-rot_rad)
	lbl.rotation_degrees = -rot
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	node.add_child(lbl)

	return node


# ── Input ──────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _menu_open:
		return   # Upgrade-Menü offen: Grid-/Tasten-Eingaben ignorieren
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
		# Wenn eine Rampe im Shop ausgewählt ist: Richtung der Rampe drehen
		if selected_shop_slot >= 0 and shop_slots[selected_shop_slot] != null \
				and shop_slots[selected_shop_slot]["type"] == "ramp":
			ramp_preview_rot = (ramp_preview_rot + 90) % 360
			_update_shop_ui()
		else:
			_rotate_active(90)

	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_flip_active()


func _handle_grid_left_click(row: int, col: int) -> void:
	var cell_data = grid[row][col]
	var is_start  = (cell_data != null and cell_data.get("is_start", false))

	if is_start:
		return

	# Dirt-Tiles können durch Shop-Tiles oder verschobene Tiles überschrieben werden
	if cell_data != null and cell_data.get("is_dirt", false):
		if selected_shop_slot >= 0:
			var slot = shop_slots[selected_shop_slot]
			if slot != null and slot["type"] == "ramp":
				# Rampe braucht 2 Felder; _place_ramp überschreibt Dreck-Tiles selbst
				_place_ramp(row, col)
			else:
				cell_data["node"].queue_free()
				grid[row][col] = null
				_place_shop_tile(row, col)
		elif selected_grid_row >= 0:
			cell_data["node"].queue_free()
			grid[row][col] = null
			_move_selected_tile_to(row, col)
		return

	# Rampen-Tiles: verkaufen oder ramp_start auswählen (für R-Drehen)
	if cell_data != null and cell_data.get("type", "") in ["ramp_start", "ramp_end"]:
		if sell_mode:
			_sell_grid_tile(row, col)
			return
		# Bei ramp_end → zum ramp_start-Partner wechseln
		var target_r = row; var target_c = col
		if cell_data.get("type", "") == "ramp_end":
			target_r = cell_data.get("ramp_partner_row", row)
			target_c = cell_data.get("ramp_partner_col", col)
		if selected_grid_row == target_r and selected_grid_col == target_c:
			selected_grid_row = -1; selected_grid_col = -1
			_update_grid_highlight(); tile_selector.deselect()
		else:
			selected_shop_slot = -1; sell_mode = false
			_update_shop_ui(); _update_sell_panel_style()
			selected_grid_row = target_r; selected_grid_col = target_c
			_update_grid_highlight()
			tile_selector.set_status("Rampe  [R] drehen")
		return

	# Kombinations-Check: Shop-Tile auf passendes Grid-Tile → Upgrade
	if cell_data != null and selected_shop_slot >= 0 and not sell_mode:
		var slot = shop_slots[selected_shop_slot]
		if slot != null and _can_combine(slot, cell_data):
			_do_combine(row, col, slot)
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
		var slot = shop_slots[selected_shop_slot]
		if slot != null and slot["type"] == "ramp":
			_place_ramp(row, col)
		else:
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
	# Rampen-Paar verschieben: beide Tiles zusammen an neue Position
	if data.get("type", "") == "ramp_start":
		var rot     = data["rotation"]
		var new_end = _ramp_end_pos(new_row, new_col, rot)
		var end_ok  = _ac_in_bounds(new_end) and (
			grid[new_end.x][new_end.y] == null or
			grid[new_end.x][new_end.y].get("type", "") == "ramp_end"
		)
		if not end_ok:
			tile_selector.set_status("Kein Platz für Rampe")
			selected_grid_row = -1; selected_grid_col = -1
			_update_grid_highlight(); tile_selector.deselect()
			return
		# Altes Paar entfernen
		var old_pr = data.get("ramp_partner_row", -1)
		var old_pc = data.get("ramp_partner_col", -1)
		if old_pr >= 0 and old_pc >= 0 and grid[old_pr][old_pc] != null:
			grid[old_pr][old_pc]["node"].queue_free()
			grid[old_pr][old_pc] = null
		data["node"].queue_free()
		grid[old_row][old_col] = null
		# Neues Paar platzieren
		_spawn_tile(new_row, new_col, {
			"type": "ramp_start", "rotation": rot, "flipped": false,
			"direction": 1, "points": 0.0, "multiplier": 1.0,
			"variant_label": "", "series": "", "combine_level": 0,
			"is_start": false, "is_dirt": false,
			"ramp_partner_row": new_end.x, "ramp_partner_col": new_end.y,
		})
		_spawn_tile(new_end.x, new_end.y, {
			"type": "ramp_end", "rotation": rot, "flipped": false,
			"direction": 1, "points": 0.0, "multiplier": 1.0,
			"variant_label": "", "series": "", "combine_level": 0,
			"is_start": false, "is_dirt": false,
			"ramp_partner_row": new_row, "ramp_partner_col": new_col,
		})
		last_placed_row = new_row; last_placed_col = new_col
		selected_grid_row = -1; selected_grid_col = -1
		_update_grid_highlight(); tile_selector.deselect()
		_invalidate_track()
		return

	var move_data = {
		"type":          data["type"],
		"rotation":      data["rotation"],
		"flipped":       data.get("flipped", false),
		"direction":     data.get("direction", 1),
		"points":        data.get("points", 0.0),
		"multiplier":    data.get("multiplier", 1.0),
		"variant_label": data.get("variant_label", ""),
		"series":        data.get("series", ""),
		"combine_level": data.get("combine_level", 0),
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
		"series":        slot["variant_label"],
		"combine_level": 0,
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
		# Rampen-Paar: Partner mitlöschen
		var rtype = grid[row][col].get("type", "")
		if rtype == "ramp_start" or rtype == "ramp_end":
			var pr = grid[row][col].get("ramp_partner_row", -1)
			var pc = grid[row][col].get("ramp_partner_col", -1)
			if pr >= 0 and pc >= 0 and grid[pr][pc] != null:
				grid[pr][pc]["node"].queue_free()
				grid[pr][pc] = null
		grid[row][col]["node"].queue_free()
		grid[row][col] = null
		if last_placed_row == row and last_placed_col == col:
			last_placed_row = -1
			last_placed_col = -1
	_invalidate_track()


# ── Rampe ──────────────────────────────────────────────────────────────────────

func _ramp_end_pos(row: int, col: int, rot: int) -> Vector2i:
	match rot:
		0:   return Vector2i(row,     col + 2)
		90:  return Vector2i(row + 2, col    )
		180: return Vector2i(row,     col - 2)
		270: return Vector2i(row - 2, col    )
	return Vector2i(-1, -1)


# Ein Feld ist für eine Rampe nutzbar, wenn es leer oder ein Dreck-Tile ist.
func _ramp_cell_free(row: int, col: int) -> bool:
	var d = grid[row][col]
	return d == null or d.get("is_dirt", false)


# Entfernt ein automatisch generiertes Dreck-Tile an dieser Stelle (falls vorhanden).
func _clear_dirt_cell(row: int, col: int) -> void:
	var d = grid[row][col]
	if d != null and d.get("is_dirt", false):
		d["node"].queue_free()
		grid[row][col] = null


func _place_ramp(row: int, col: int) -> void:
	# Versucht alle 4 Rotationen beginnend mit ramp_preview_rot
	var rot = ramp_preview_rot
	for _attempt in range(4):
		var end = _ramp_end_pos(row, col, rot)
		if _ac_in_bounds(end) and _ramp_cell_free(row, col) and _ramp_cell_free(end.x, end.y):
			if not Economy.spend(RAMP_PRICE):
				_flash_currency()
				return
			# Automatisch generierte Dreck-Tiles unter der Rampe entfernen
			_clear_dirt_cell(row, col)
			_clear_dirt_cell(end.x, end.y)
			_spawn_tile(row, col, {
				"type": "ramp_start", "rotation": rot, "flipped": false,
				"direction": 1, "points": 0.0, "multiplier": 1.0,
				"variant_label": "", "series": "", "combine_level": 0,
				"is_start": false, "is_dirt": false,
				"ramp_partner_row": end.x, "ramp_partner_col": end.y,
			})
			_spawn_tile(end.x, end.y, {
				"type": "ramp_end", "rotation": rot, "flipped": false,
				"direction": 1, "points": 0.0, "multiplier": 1.0,
				"variant_label": "", "series": "", "combine_level": 0,
				"is_start": false, "is_dirt": false,
				"ramp_partner_row": row, "ramp_partner_col": col,
			})
			ramp_preview_rot = rot
			shop_slots[selected_shop_slot] = null
			selected_shop_slot = -1
			_update_currency_label()
			_update_shop_ui()
			_check_shop_auto_reroll()
			_invalidate_track()
			return
		rot = (rot + 90) % 360
	tile_selector.set_status("Kein Platz für Rampe (2 freie Felder in einer Richtung nötig)")


# ── Tile-Kombination ───────────────────────────────────────────────────────────

func _can_combine(shop_data: Dictionary, grid_data: Dictionary) -> bool:
	if grid_data.get("is_start", false) or grid_data.get("is_dirt", false):
		return false
	if shop_data["type"] != grid_data["type"]:
		return false
	var series = grid_data.get("series", "")
	if series == "" or series == "+0":
		return false
	if shop_data.get("variant_label", "") != grid_data.get("series", ""):
		return false
	return grid_data.get("combine_level", 0) < 4


func _do_combine(row: int, col: int, shop_data: Dictionary) -> void:
	if not Economy.spend(shop_data["price"]):
		_flash_currency()
		return

	var grid_data  = grid[row][col]
	var series     = grid_data.get("series", "")
	var new_level  = grid_data.get("combine_level", 0) + 1
	var new_points = grid_data.get("points", 0.0)
	var new_mult   = grid_data.get("multiplier", 1.0)
	var new_label  = grid_data.get("variant_label", "")

	if series in POINT_UPGRADE_DATA:
		var tbl    = POINT_UPGRADE_DATA[series]
		new_points = tbl["points"][new_level]
		new_mult   = 1.0
		new_label  = tbl["labels"][new_level]

	grid_data["node"].queue_free()
	grid[row][col] = null

	_spawn_tile(row, col, {
		"type":          grid_data["type"],
		"rotation":      grid_data["rotation"],
		"flipped":       grid_data.get("flipped", false),
		"direction":     grid_data.get("direction", 1),
		"points":        new_points,
		"multiplier":    new_mult,
		"variant_label": new_label,
		"series":        series,
		"combine_level": new_level,
		"is_start":      false,
	})

	shop_slots[selected_shop_slot] = null
	selected_shop_slot = -1
	_update_currency_label()
	_update_shop_ui()
	_check_shop_auto_reroll()
	_invalidate_track()


# ── Rotation ───────────────────────────────────────────────────────────────────

func _rotate_active(degrees: int) -> void:
	var row = selected_grid_row if selected_grid_row >= 0 else last_placed_row
	var col = selected_grid_col if selected_grid_row >= 0 else last_placed_col
	if row < 0:
		return
	var data = grid[row][col]
	if data == null or data.get("is_start", false):
		return
	# Rampen-Rotation: End-Tile neu platzieren
	if data.get("type", "") == "ramp_start":
		_rotate_ramp(row, col, degrees)
		return
	data["rotation"] = (data["rotation"] + degrees) % 360
	data["node"].rotation_degrees = data["rotation"]
	_update_node_labels(data["node"], data["rotation"])
	_invalidate_track()


# Dreht ein Rampen-Paar: End-Tile wird entfernt und in neuer Richtung neu gesetzt.
func _rotate_ramp(row: int, col: int, degrees: int) -> void:
	var data    = grid[row][col]
	var new_rot = (data["rotation"] + degrees) % 360
	# Alle 4 Richtungen durchprobieren ab new_rot
	for _attempt in range(4):
		var new_end = _ramp_end_pos(row, col, new_rot)
		var end_free = _ac_in_bounds(new_end) and (
			grid[new_end.x][new_end.y] == null or
			grid[new_end.x][new_end.y].get("type", "") == "ramp_end"
		)
		if end_free:
			# Altes End-Tile entfernen
			var old_pr = data.get("ramp_partner_row", -1)
			var old_pc = data.get("ramp_partner_col", -1)
			if old_pr >= 0 and old_pc >= 0 and grid[old_pr][old_pc] != null:
				grid[old_pr][old_pc]["node"].queue_free()
				grid[old_pr][old_pc] = null
			# Ramp-Start neu spawnen (neue Rotation)
			data["node"].queue_free()
			grid[row][col] = null
			_spawn_tile(row, col, {
				"type": "ramp_start", "rotation": new_rot, "flipped": false,
				"direction": 1, "points": 0.0, "multiplier": 1.0,
				"variant_label": "", "series": "", "combine_level": 0,
				"is_start": false, "is_dirt": false,
				"ramp_partner_row": new_end.x, "ramp_partner_col": new_end.y,
			})
			# Neues End-Tile spawnen
			_spawn_tile(new_end.x, new_end.y, {
				"type": "ramp_end", "rotation": new_rot, "flipped": false,
				"direction": 1, "points": 0.0, "multiplier": 1.0,
				"variant_label": "", "series": "", "combine_level": 0,
				"is_start": false, "is_dirt": false,
				"ramp_partner_row": row, "ramp_partner_col": col,
			})
			# Selektion beibehalten
			selected_grid_row = row; selected_grid_col = col
			_update_grid_highlight()
			tile_selector.set_status("Rampe  [R] drehen")
			_invalidate_track()
			return
		new_rot = (new_rot + 90) % 360
	tile_selector.set_status("Keine gültige Position für Rampen-Drehung")


func _update_node_labels(node: Node2D, rot_deg: int) -> void:
	var r = deg_to_rad(rot_deg)
	var vl = node.get_node_or_null("VarLabel")
	if vl is Label:
		vl.rotation_degrees = -rot_deg
		vl.position = Vector2(-TILE_SIZE / 2 + 2, -TILE_SIZE / 2 + 2).rotated(-r)
	var sl = node.get_node_or_null("StarLabel")
	if sl is Label:
		sl.rotation_degrees = -rot_deg
		sl.position = Vector2(0.0, TILE_SIZE / 2.0 - 14.0).rotated(-r)


# ── F-Taste: Kurve flippen / Gerade umkehren / Rampe tauschen ─────────────────

func _flip_active() -> void:
	var row = selected_grid_row if selected_grid_row >= 0 else last_placed_row
	var col = selected_grid_col if selected_grid_row >= 0 else last_placed_col
	if row < 0:
		return
	var data = grid[row][col]
	if data == null or data.get("is_start", false):
		return
	var t = data["type"]

	# Kurventyp wechseln
	if t == "curve" or t == "curve_alt":
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
		return

	# Gerade: Fahrtrichtung umkehren
	if t == "straight":
		var new_dir = -1 if data.get("direction", 1) == 1 else 1
		data["node"].queue_free()
		grid[row][col] = null
		_spawn_tile(row, col, {
			"type":          "straight",
			"rotation":      data["rotation"],
			"flipped":       data.get("flipped", false),
			"direction":     new_dir,
			"points":        data.get("points", 0.0),
			"multiplier":    data.get("multiplier", 1.0),
			"variant_label": data.get("variant_label", ""),
			"series":        data.get("series", ""),
			"combine_level": data.get("combine_level", 0),
			"is_start":      false,
		})
		_invalidate_track()
		return

	# Rampe: Start und Ende tauschen
	if t == "ramp_start" or t == "ramp_end":
		var s_row: int; var s_col: int; var e_row: int; var e_col: int
		if t == "ramp_start":
			s_row = row; s_col = col
			e_row = data.get("ramp_partner_row", -1)
			e_col = data.get("ramp_partner_col", -1)
		else:
			e_row = row; e_col = col
			s_row = data.get("ramp_partner_row", -1)
			s_col = data.get("ramp_partner_col", -1)
		if s_row < 0 or e_row < 0:
			return
		var rot = grid[s_row][s_col]["rotation"]
		grid[s_row][s_col]["node"].queue_free()
		grid[s_row][s_col] = null
		if grid[e_row][e_col] != null:
			grid[e_row][e_col]["node"].queue_free()
			grid[e_row][e_col] = null
		# Tauschen: altes Ende wird Start, altes Start wird Ende
		_spawn_tile(e_row, e_col, {
			"type": "ramp_start", "rotation": rot, "flipped": false,
			"direction": 1, "points": 0.0, "multiplier": 1.0,
			"variant_label": "", "series": "", "combine_level": 0,
			"is_start": false, "is_dirt": false,
			"ramp_partner_row": s_row, "ramp_partner_col": s_col,
		})
		_spawn_tile(s_row, s_col, {
			"type": "ramp_end", "rotation": rot, "flipped": false,
			"direction": 1, "points": 0.0, "multiplier": 1.0,
			"variant_label": "", "series": "", "combine_level": 0,
			"is_start": false, "is_dirt": false,
			"ramp_partner_row": e_row, "ramp_partner_col": e_col,
		})
		selected_grid_row = e_row; selected_grid_col = e_col
		_update_grid_highlight()
		tile_selector.set_status("Rampe  [R] drehen  [F] tauschen")
		_invalidate_track()


# ── Hilfsfunktionen ────────────────────────────────────────────────────────────

func _type_display_name(typ: String) -> String:
	match typ:
		"straight":   return "Gerade"
		"curve":      return "Kurve"
		"curve_alt":  return "Kurve 2"
		"ramp_start": return "Rampe  [R] drehen"
		"ramp_end":   return "Rampe (Ende)"
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
					"series":           d.get("series", ""),
					"combine_level":    d.get("combine_level", 0),
					"ramp_partner_row": d.get("ramp_partner_row", -1),
					"ramp_partner_col": d.get("ramp_partner_col", -1),
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


func _on_upgrades_pressed() -> void:
	if _menu_open:
		return
	_menu_open = true
	_bonus_sig_on_open = _bonus_signature()
	_upgrade_menu = UpgradeMenuScript.new()
	_upgrade_menu.closed.connect(_on_upgrade_menu_closed)
	add_child(_upgrade_menu)


func _on_upgrade_menu_closed() -> void:
	_menu_open = false
	_upgrade_menu = null
	# Grid-Größe könnte sich geändert haben → ggf. neu aufbauen (löscht auch Bonus-Marker)
	var size_changed = (Economy.get_grid_rows() != GRID_ROWS or Economy.get_grid_cols() != GRID_COLS)
	_rebuild_grid_for_size()
	# Bonusfelder neu würfeln, wenn Grid neu gebaut wurde oder Bonus-Upgrades sich änderten
	if size_changed or _bonus_signature() != _bonus_sig_on_open:
		_roll_bonus_fields()


# Baut das Grid in der aktuellen Economy-Größe neu auf, falls sie sich geändert hat.
# Das Grid wächst nur (Origin oben-links bleibt fix), daher bleiben platzierte
# Tiles an ihrer Position erhalten.
func _rebuild_grid_for_size() -> void:
	var new_rows = Economy.get_grid_rows()
	var new_cols = Economy.get_grid_cols()
	if new_rows == GRID_ROWS and new_cols == GRID_COLS:
		return

	_remove_all_dirt_tiles()
	var saved = get_grid_state()   # alte Dimensionen

	for c in grid_node.get_children():
		c.queue_free()

	GRID_ROWS = new_rows
	GRID_COLS = new_cols
	_init_grid()
	_draw_grid_background()
	_setup_grid_highlight()
	_place_start_tile()
	_restore_grid(saved)

	selected_grid_row  = -1
	selected_grid_col  = -1
	selected_shop_slot = -1
	sell_mode          = false
	_update_grid_highlight()
	_update_shop_ui()
	_update_sell_panel_style()
	tile_selector.deselect()
	_invalidate_track()


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
	_persist_track()
	# Fahr-Zustand: Tiles auf Bonusfeldern bekommen den Effekt mitgegeben.
	Engine.set_meta("pending_grid_state", _build_drive_state())
	Engine.set_meta("saved_grid_state",   get_grid_state())
	var world_scene = load(Paths.SCENE_WORLD3D)
	if world_scene:
		get_tree().change_scene_to_packed(world_scene)


# Kopie des Grid-States, in der Tiles auf einem Bonusfeld bonus_points/bonus_mult tragen.
func _build_drive_state() -> Array:
	var state = get_grid_state()
	for r in range(GRID_ROWS):
		for c in range(GRID_COLS):
			if bonus_grid[r][c] != null and typeof(state[r][c]) == TYPE_DICTIONARY:
				state[r][c]["bonus_points"] = bonus_grid[r][c]["points"]
				state[r][c]["bonus_mult"]   = bonus_grid[r][c]["mult"]
	return state


# ── Bonusfelder ─────────────────────────────────────────────────────────────────

# Kurzkennung des Bonus-Upgrade-Zustands (zum Erkennen von Änderungen im Menü).
func _bonus_signature() -> String:
	return "%d%d%d_%d" % [
		int(Economy.is_bonus_unlocked("plus5")),
		int(Economy.is_bonus_unlocked("plus10")),
		int(Economy.is_bonus_unlocked("mult15")),
		Economy.get_bonus_extra_count(),
	]


# Würfelt die Bonusfelder neu (auf leere Zellen, ohne sich gegenseitig zu überschreiben).
func _roll_bonus_fields() -> void:
	for n in _bonus_marker_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_bonus_marker_nodes.clear()
	for r in range(GRID_ROWS):
		for c in range(GRID_COLS):
			bonus_grid[r][c] = null

	var types = Economy.get_unlocked_bonus_types()
	if types.is_empty():
		return

	# Kandidaten: leere Zellen (Start-Tile + belegte Zellen sind dadurch ausgenommen)
	var cells: Array = []
	for r in range(GRID_ROWS):
		for c in range(GRID_COLS):
			if grid[r][c] == null:
				cells.append(Vector2i(r, c))
	cells.shuffle()

	# Je 1 Feld pro freigeschaltetem Typ + Extra-Felder in fester Reihenfolge
	# (+5, dann +10, dann ×1.5, dann wieder +5 …; types ist bereits in dieser Reihenfolge).
	var to_place: Array = []
	for t in types:
		to_place.append(t)
	for i in range(Economy.get_bonus_extra_count()):
		to_place.append(types[i % types.size()])

	var idx = 0
	for eff in to_place:
		if idx >= cells.size():
			break
		var cell = cells[idx]; idx += 1
		bonus_grid[cell.x][cell.y] = {
			"label": eff["label"], "points": eff["points"], "mult": eff["mult"],
		}
		var marker = _make_bonus_marker(eff)
		marker.position = _grid_to_world(cell.x, cell.y)
		marker.z_index  = 6
		grid_node.add_child(marker)
		_bonus_marker_nodes.append(marker)


func _make_bonus_marker(eff: Dictionary) -> Node2D:
	var node = Node2D.new()
	var col  = Color(0.3, 0.9, 0.3)
	match eff["label"]:
		"+5":   col = Color(0.3, 0.9, 0.3)
		"+10":  col = Color(1.0, 0.82, 0.2)
		"×1.5": col = Color(0.75, 0.45, 1.0)
	var bw = 3
	for i in range(4):
		var r = ColorRect.new()
		r.color = col
		match i:
			0: r.position = Vector2(0, 0);              r.size = Vector2(TILE_SIZE, bw)
			1: r.position = Vector2(0, TILE_SIZE - bw); r.size = Vector2(TILE_SIZE, bw)
			2: r.position = Vector2(0, 0);              r.size = Vector2(bw, TILE_SIZE)
			3: r.position = Vector2(TILE_SIZE - bw, 0); r.size = Vector2(bw, TILE_SIZE)
		node.add_child(r)
	var lbl = Label.new()
	lbl.text = eff["label"]
	lbl.position = Vector2(4, 2)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	node.add_child(lbl)
	return node


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
		# ramp_start: Mittelfeld überspringen → direkt zur ramp_end
		if grid[row][col] != null and grid[row][col].get("type", "") == "ramp_start":
			if _ac_in_bounds(nxt): nxt = _ac_step(nxt.x, nxt.y, exit_dir)
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
	_persist_track()


# Speichert die aktuelle Strecke dauerhaft (ohne Dreck-Tiles, die per Prüfen neu entstehen).
func _persist_track() -> void:
	var st = get_grid_state()
	for r in range(st.size()):
		for c in range(st[r].size()):
			var d = st[r][c]
			if typeof(d) == TYPE_DICTIONARY and d.get("is_dirt", false):
				st[r][c] = ""
	Economy.save_track(st)


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
			"multiplier":    0.1,
			"variant_label": "",
			"is_start":      false,
			"is_dirt":       true,
		})


# 0-1-BFS: vorhandene Tiles kostenlos verfolgen (Kosten 0),
# neue Dreck-Tiles setzen kostet 1. Findet die minimale Ergänzung
# auch bei mehreren Lücken oder halb gebauten Strecken.
func _build_completion_path() -> Array:
	var INF = GRID_ROWS * GRID_COLS + 1

	var dist: Dictionary      = {}
	var came_from: Dictionary = {}

	# Bucket-Queue für 0-1-BFS: buckets[k] = alle Zustände mit Kosten k
	var buckets: Array = []
	for _i in range(INF + 2):
		buckets.append([])

	# Startpunkt: [1,1] verlässt nach Ost → erste zu prüfende Zelle ist [1,2]
	var bfs0 = _ac_step(1, 1, "E")
	if not _ac_in_bounds(bfs0):
		return []

	var s0 = "%d_%d_W" % [bfs0.x, bfs0.y]
	dist[s0]      = 0
	came_from[s0] = null
	buckets[0].append({"r": bfs0.x, "c": bfs0.y, "e": "W", "k": 0})

	var goal_key = ""
	var found    = false

	for cur_k in range(INF + 1):
		if found: break
		while not buckets[cur_k].is_empty():
			var s  = buckets[cur_k].pop_back()
			var sr = s["r"]; var sc = s["c"]; var se = s["e"]
			var sk = "%d_%d_%s" % [sr, sc, se]

			if s["k"] > dist.get(sk, INF):
				continue  # Veralteter Eintrag, überspringen

			# Ziel: Start-Tile [1,1] von Westen betreten
			if sr == 1 and sc == 1 and se == "W":
				goal_key = sk; found = true; break

			# Start-Tile aus falscher Richtung → Sackgasse
			if sr == 1 and sc == 1:
				continue

			if not _ac_in_bounds(Vector2i(sr, sc)):
				continue

			var cell = grid[sr][sc]
			var is_user_tile = (cell != null
				and not cell.get("is_dirt", false)
				and not cell.get("is_start", false))

			if is_user_tile:
				# Vorhandenes User-Tile kostenlos verfolgen (wenn Richtung stimmt)
				var exit_dir = _ac_through(cell, se)
				if exit_dir != "":
					var nc  = _ac_step(sr, sc, exit_dir)
					# ramp_start: Mittelfeld überspringen
					if cell.get("type", "") == "ramp_start" and _ac_in_bounds(nc):
						nc = _ac_step(nc.x, nc.y, exit_dir)
					if _ac_in_bounds(nc):
						var ne  = _ac_opp(exit_dir)
						var nk  = "%d_%d_%s" % [nc.x, nc.y, ne]
						if cur_k < dist.get(nk, INF):
							dist[nk]      = cur_k
							came_from[nk] = {"prev": sk, "type": null, "r": sr, "c": sc}
							buckets[cur_k].append({"r": nc.x, "c": nc.y, "e": ne, "k": cur_k})
			else:
				# Leere Zelle: Dreck-Tile setzen (Kosten +1)
				var next_k = cur_k + 1
				if next_k > INF:
					continue
				for opt in _ac_tile_options(se):
					var nc = _ac_step(sr, sc, opt["exit"])
					if not _ac_in_bounds(nc):
						continue
					var ne = _ac_opp(opt["exit"])
					var nk = "%d_%d_%s" % [nc.x, nc.y, ne]
					if next_k < dist.get(nk, INF):
						dist[nk]      = next_k
						came_from[nk] = {
							"prev": sk, "type": opt["type"],
							"rot":  opt["rot"], "dir": opt.get("dir", 1),
							"r":    sr, "c": sc
						}
						buckets[next_k].append({"r": nc.x, "c": nc.y, "e": ne, "k": next_k})

	if goal_key == "":
		return []

	# Pfad rekonstruieren: nur Dreck-Tile-Platzierungen (type != null) sammeln
	var path: Array = []
	var cur = goal_key
	while cur != null and came_from.has(cur):
		var cf = came_from[cur]
		if cf == null: break
		if cf.get("type", null) != null:
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
	if t == "straight" or t == "ramp_start" or t == "ramp_end":
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
