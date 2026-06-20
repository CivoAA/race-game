extends Control
## Eigenständiges Motorhaube-Tuning-Panel (Backpack-Battles-Stil) für den Werkstatt-Untertab.
## Baut Kopfzeile (Rastergröße-Badge + Upgrade-Knopf), die gerahmte Motorhauben-Platte mit dem
## Drag&Drop-Raster und die Bauteil-Schublade unten.
##
## UX:
##  • Bauteil aus der Schublade auf eine freie, passende Stelle ziehen → platzieren.
##  • Platziertes Bauteil verschieben (innerhalb der Platte) bzw. neben die Platte ziehen → entfernen.
##  • Beim Ziehen wird ALLES außer der Platte abgedunkelt (Fokus) und die Ziel-Zelle grün/rot markiert.
##  • Zellengröße schrumpft automatisch, damit auch das 4×4-Raster sauber passt.
## Bauteile haben aktuell KEINEN Spieleffekt (Platzhalter, bis Pixel-Assets existieren).

const DragTile := preload("res://scripts/MotorhaubeDragTile.gd")

signal items_changed(items: Array)
signal upgrade_requested()

# ── Layout ──
const PAD            := 18.0   # Außenrand
const HEADER_H       := 40.0   # Höhe der Kopfzeile (Badge / Upgrade-Knopf)
const PLATE_PAD      := 26.0   # Rand der Platte ums Raster
const MIN_CELL       := 26
const RADIUS         := 14.0
# Bauteil-Schublade: kurzer, horizontal scrollbarer Streifen unten (Platte = Hauptfokus → groß).
const STRIP_ITEM_MAX := 54     # max. Kantenlänge einer Palette-Vorschau (große Teile werden skaliert)
const PAL_CELL       := 30     # Wunsch-Feldgröße der Palette-Vorschau (≤ STRIP_ITEM_MAX/Größe)
const STRIP_TITLE_H  := 22.0
const STRIP_PAD      := 12.0
const SCROLL_STEP    := 80.0

# ── Farben ──
const C_TEXT      := Color(0.86, 0.87, 0.88)
const C_DIM       := Color(0.60, 0.63, 0.67)
const C_PLATE     := Color(0.165, 0.175, 0.20)
const C_PLATE_BRD := Color(0.34, 0.36, 0.41)
const C_CELL      := Color(0.105, 0.115, 0.135)
const C_CELL_BRD  := Color(0.29, 0.31, 0.36)
const C_TOOL      := Color(0.96, 0.55, 0.26)   # Werkstatt-Orange
const C_TOOL_BG   := Color(0.30, 0.16, 0.07)
const C_SURFACE   := Color(0.169, 0.176, 0.192)
const C_TRAY      := Color(0.135, 0.145, 0.165)
const C_TRAY_BRD  := Color(0.27, 0.29, 0.33)
const C_LINE      := Color(0.247, 0.255, 0.278)
const C_OK        := Color(0.36, 0.80, 0.46)
const C_BAD       := Color(0.92, 0.34, 0.34)

# ── Zustand ──
var cols := 1
var rows := 2
var base_cell := 64
var cell := 64
var items: Array = []                # [{id:String, x:int, y:int}]
var item_defs: Array = []            # geordnete Vorlagenliste (für die Palette)
var defs_by_id: Dictionary = {}      # id → def

var _size_text := ""
var _upgrade_text := ""
var _upgrade_enabled := false
var _maxed := false

var _grid_origin := Vector2.ZERO     # linke obere Ecke des Rasters (lokal)
var _plate_rect := Rect2()           # gerahmte Haubenplatte
var _placed_tiles: Array = []
var _chrome: Control                 # Kopfzeile + Schublade (beim Ziehen abgedunkelt)
var _trash: Label                    # Mülleimer (nur beim Ziehen eines platzierten Teils, über dem Dimmer)
var _tray_h := 100.0                  # Höhe der Schublade (kurzer Streifen)
var _pal_cells: Array = []           # Palette-Layout: [{def, x:float, w:float, h:float}]
var _pal_content_w := 0.0            # Gesamtbreite aller Vorlagen (für Scroll-Grenze)
var _pal_row_h := 0.0
var _pal_tiles: Array = []           # [{tile, base_x}] – für horizontales Scrollen
var _pal_scroll := 0.0
var _pal_max_scroll := 0.0
var _tray_rect := Rect2()            # Schubladen-Rechteck (lokal) – Treffer-Test fürs Mausrad

var _dragging := false
var _drag_from_grid := false         # stammt das aktuell gezogene Teil aus dem Raster?
var _hover_cell := Vector2i(-1, -1)
var _hover_size := Vector2i.ZERO
var _hover_ok := false


func setup(cfg: Dictionary) -> void:
	cols      = int(cfg.get("cols", 1))
	rows      = int(cfg.get("rows", 2))
	base_cell = int(cfg.get("base_cell", 64))
	var its: Array = cfg.get("items", [])
	items     = its.duplicate(true)
	item_defs = cfg.get("item_defs", [])
	defs_by_id = {}
	for d in item_defs:
		defs_by_id[String(d["id"])] = d
	_size_text       = String(cfg.get("size_text", ""))
	_upgrade_text    = String(cfg.get("upgrade_text", ""))
	_upgrade_enabled = bool(cfg.get("upgrade_enabled", false))
	_maxed           = bool(cfg.get("maxed", false))
	_rebuild()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			_dragging = true
			_drag_from_grid = false
			if _chrome != null:
				_chrome.modulate = Color(0.42, 0.42, 0.42)
			queue_redraw()
		NOTIFICATION_DRAG_END:
			_dragging = false
			_drag_from_grid = false
			_hover_cell = Vector2i(-1, -1)
			if _chrome != null:
				_chrome.modulate = Color.WHITE
			if _trash != null:
				_trash.visible = false
			queue_redraw()
		NOTIFICATION_RESIZED:
			if not item_defs.is_empty():
				_rebuild()


func _size_of(id: String) -> Vector2i:
	var d: Dictionary = defs_by_id.get(id, {})
	return d.get("size", Vector2i(1, 1)) if not d.is_empty() else Vector2i(1, 1)


func _color_of(id: String) -> Color:
	var d: Dictionary = defs_by_id.get(id, {})
	return d.get("color", Color.WHITE) if not d.is_empty() else Color.WHITE


func _name_of(id: String) -> String:
	var d: Dictionary = defs_by_id.get(id, {})
	return String(d.get("name", id)) if not d.is_empty() else id


# ── Aufbau ──────────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_placed_tiles.clear()
	_compute_layout()

	# Chrome zuerst → Dimmer (im _draw) und platzierte Kacheln liegen darüber.
	_chrome = Control.new()
	_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chrome)
	_build_header()
	_build_tray()

	_build_placed_tiles()
	_build_trash()   # zuletzt → liegt über Dimmer und Kacheln
	queue_redraw()


# Erst die (mehrzeilige) Palette ausmessen → _tray_h, dann die Zellengröße an den Restplatz
# anpassen und das Raster mittig ins Band zwischen Kopfzeile und Schublade legen.
func _compute_layout() -> void:
	_layout_palette()
	var avail_w := maxf(1.0, size.x - PAD * 2.0 - PLATE_PAD * 2.0)
	var top := PAD + HEADER_H + 12.0
	var tray_top := size.y - PAD - _tray_h
	var band_h := maxf(1.0, (tray_top - 12.0 - top) - PLATE_PAD * 2.0)

	var fit := minf(float(base_cell), minf(avail_w / float(cols), band_h / float(rows)))
	cell = clampi(int(floor(fit)), MIN_CELL, base_cell)

	var gw := cols * cell
	var gh := rows * cell
	_grid_origin = Vector2(
		round((size.x - gw) * 0.5),
		round(top + PLATE_PAD + maxf(0.0, (band_h - gh) * 0.5)))
	_plate_rect = Rect2(_grid_origin - Vector2(PLATE_PAD, PLATE_PAD),
		Vector2(gw + PLATE_PAD * 2.0, gh + PLATE_PAD * 2.0))


# Bauteile in EINE Zeile legen (horizontal scrollbar). Große Teile werden so skaliert, dass die
# Schublade kurz bleibt (Platte = Hauptfokus). Füllt _pal_cells + Maße für das Scrollen.
func _layout_palette() -> void:
	_pal_cells.clear()
	const GAP := 12.0
	var x := 0.0
	var row_h := 0.0
	for d in item_defs:
		var s: Vector2i = d["size"]
		var pc := floori(minf(float(PAL_CELL), float(STRIP_ITEM_MAX) / float(maxi(s.x, s.y))))
		pc = maxi(pc, 14)
		var w := float(s.x * pc)
		var h := float(s.y * pc)
		_pal_cells.append({"def": d, "x": x, "w": w, "h": h})
		x += w + GAP
		row_h = maxf(row_h, h)
	_pal_content_w = maxf(0.0, x - GAP)
	_pal_row_h = row_h
	_tray_h = STRIP_TITLE_H + row_h + STRIP_PAD * 2.0


func _build_header() -> void:
	# Größen-Badge links.
	var badge := Panel.new()
	badge.position = Vector2(PAD, PAD)
	badge.size     = Vector2(132, HEADER_H)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _box(C_SURFACE, C_LINE, 1, RADIUS))
	_chrome.add_child(badge)

	var blbl := Label.new()
	blbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	blbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	blbl.add_theme_font_size_override("font_size", 15)
	blbl.add_theme_color_override("font_color", C_TEXT)
	blbl.text = _size_text
	badge.add_child(blbl)

	# Upgrade-Knopf rechts.
	var bw := 320.0
	var up := Button.new()
	up.position = Vector2(size.x - PAD - bw, PAD)
	up.size     = Vector2(bw, HEADER_H)
	up.text     = _upgrade_text
	up.focus_mode = Control.FOCUS_NONE
	var on := _upgrade_enabled and not _maxed
	up.disabled = not on
	up.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	var bg := C_TOOL_BG if on else C_SURFACE
	var brd := C_TOOL if on else C_LINE
	var sb := _box(bg, brd, 2, RADIUS)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		up.add_theme_stylebox_override(st, sb)
	up.add_theme_color_override("font_color", C_TEXT if on else C_DIM)
	up.add_theme_color_override("font_color_disabled", C_DIM)
	up.add_theme_font_size_override("font_size", 14)
	if not _maxed:
		up.pressed.connect(func() -> void: emit_signal("upgrade_requested"))
	_chrome.add_child(up)


# Bauteil-Schublade unten: kurzer, horizontal scrollbarer Streifen (Mausrad zum Scrollen).
# Positionen aus _pal_cells (_layout_palette). Vorlagen werden geklippt → nur der Streifen ist sichtbar.
func _build_tray() -> void:
	_pal_tiles.clear()
	var tray := Panel.new()
	tray.position = Vector2(PAD, size.y - PAD - _tray_h)
	tray.size     = Vector2(size.x - PAD * 2.0, _tray_h)
	tray.clip_contents = true
	# IGNORE (statt STOP): sonst bricht das Panel die Drop-Weiterleitung ans Raster ab
	# (Entfernen über der Schublade ginge nicht). Mausrad-Scroll fängt _gui_input der Wurzel ab.
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_theme_stylebox_override("panel", _box(C_TRAY, C_TRAY_BRD, 1, RADIUS))
	_chrome.add_child(tray)
	_tray_rect = Rect2(tray.position, tray.size)

	var title := Label.new()
	title.position = Vector2(14, 5)
	title.size     = Vector2(tray.size.x - 28, 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", C_DIM)
	title.text = tr("Bauteile")
	tray.add_child(title)

	const INNER_X := 14.0
	var inner_w := tray.size.x - INNER_X * 2.0
	_pal_max_scroll = maxf(0.0, _pal_content_w - inner_w)
	_pal_scroll = clampf(_pal_scroll, 0.0, _pal_max_scroll)
	# Passt alles rein → zentrieren; sonst links beginnen und scrollen.
	var start_x := INNER_X + maxf(0.0, (inner_w - _pal_content_w) * 0.5)
	var row_top := STRIP_TITLE_H

	for e in _pal_cells:
		var d: Dictionary = e["def"]
		var s: Vector2i = d["size"]
		var base_x := start_x + float(e["x"])
		var tile := Panel.new()
		tile.set_script(DragTile)
		tile.size     = Vector2(e["w"], e["h"])
		tile.position = Vector2(base_x - _pal_scroll, row_top + (_pal_row_h - float(e["h"])) * 0.5)
		tile.mouse_filter = Control.MOUSE_FILTER_PASS
		tile.mouse_default_cursor_shape = Control.CURSOR_DRAG
		tile.add_theme_stylebox_override("panel", _item_box(d["color"]))
		tile.drag_data = {"mh": true, "id": String(d["id"]), "size": s, "from_grid": false, "index": -1}
		tile.preview_color = d["color"]
		tile.preview_px = Vector2(s.x * cell, s.y * cell)
		tray.add_child(tile)
		_item_label(tile, _name_of(String(d["id"])), 9)
		_pal_tiles.append({"tile": tile, "base_x": base_x})


# Mausrad über der Schublade → horizontal scrollen.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _pal_max_scroll > 0.0:
		if _tray_rect.has_point(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
				_set_pal_scroll(_pal_scroll + SCROLL_STEP)
				accept_event()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
				_set_pal_scroll(_pal_scroll - SCROLL_STEP)
				accept_event()


func _set_pal_scroll(v: float) -> void:
	_pal_scroll = clampf(v, 0.0, _pal_max_scroll)
	for e in _pal_tiles:
		var t: Control = e["tile"]
		if is_instance_valid(t):
			t.position.x = float(e["base_x"]) - _pal_scroll


# Mülleimer: erscheint beim Ziehen eines PLATZIERTEN Teils über dem Dimmer und signalisiert
# „hier ablegen = entfernen". Liegt über allem, fängt aber keine Maus ab.
func _build_trash() -> void:
	_trash = Label.new()
	_trash.visible = false
	_trash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trash.size = Vector2(120, 120)
	_trash.position = Vector2(size.x * 0.5 - 60.0, (size.y - PAD - _tray_h) + (_tray_h - 120.0) * 0.5)
	_trash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trash.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	Icons.apply(_trash, Icons.TRASH, 72, C_DIM)
	add_child(_trash)


func _build_placed_tiles() -> void:
	for i in items.size():
		var it: Dictionary = items[i]
		var id := String(it.get("id", ""))
		var sz := _size_of(id)
		var tile := Panel.new()
		tile.set_script(DragTile)
		tile.position = _grid_origin + Vector2(int(it.get("x", 0)) * cell, int(it.get("y", 0)) * cell)
		tile.size     = Vector2(sz.x * cell, sz.y * cell)
		# PASS → Drops über dieser Kachel werden ans Raster (Eltern) weitergereicht.
		tile.mouse_filter = Control.MOUSE_FILTER_PASS
		tile.mouse_default_cursor_shape = Control.CURSOR_MOVE
		tile.add_theme_stylebox_override("panel", _item_box(_color_of(id)))
		tile.drag_data = {"mh": true, "id": id, "size": sz, "from_grid": true, "index": i}
		tile.preview_color = _color_of(id)
		tile.preview_px = tile.size
		add_child(tile)
		_placed_tiles.append(tile)
		_item_label(tile, _name_of(id), 11)


# ── Zeichnen ────────────────────────────────────────────────────────────────────
func _draw() -> void:
	# Beim Ziehen alles abdunkeln; die Platte (samt Rastern/Kacheln) wird danach hell darüber
	# gezeichnet → Fokus aufs Raster.
	if _dragging:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55), true)

	draw_style_box(_box(C_PLATE, C_TOOL if _dragging else C_PLATE_BRD, 2, RADIUS), _plate_rect)

	for cx in cols:
		for cy in rows:
			var r := Rect2(_grid_origin + Vector2(cx * cell, cy * cell), Vector2(cell, cell))
			draw_rect(Rect2(r.position + Vector2.ONE, r.size - Vector2(2, 2)), C_CELL, true)
			draw_rect(r, C_CELL_BRD, false, 1.0)

	if _dragging and _hover_cell.x >= 0:
		var hr := Rect2(_grid_origin + Vector2(_hover_cell) * cell, Vector2(_hover_size) * cell)
		var col := C_OK if _hover_ok else C_BAD
		hr = Rect2(hr.position + Vector2(2, 2), hr.size - Vector2(4, 4))
		draw_rect(hr, Color(col.r, col.g, col.b, 0.28), true)
		draw_rect(hr, Color(col.r, col.g, col.b, 0.95), false, 2.0)


# ── Drag & Drop ──────────────────────────────────────────────────────────────────
func _can_drop_data(pos: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.get("mh", false):
		return false
	var from_grid: bool = data.get("from_grid", false)
	var sz: Vector2i = data.get("size", Vector2i(1, 1))
	var src := int(data.get("index", -1)) if from_grid else -1
	var gc := _cell_at(pos, sz)
	var inside := _in_grid(gc, sz)
	if inside:
		_hover_cell = gc
		_hover_size = sz
		_hover_ok = _fits(gc.x, gc.y, sz, src)
	else:
		_hover_cell = Vector2i(-1, -1)

	# Mülleimer nur beim Ziehen eines platzierten Teils; rot, wenn das Ablegen es löschen würde.
	_drag_from_grid = from_grid
	if _trash != null:
		_trash.visible = _dragging and from_grid
		Icons.apply(_trash, Icons.TRASH, 72, C_BAD if not inside else C_DIM)
	queue_redraw()
	return true


func _drop_data(pos: Vector2, data: Variant) -> void:
	var sz: Vector2i = data.get("size", Vector2i(1, 1))
	var from_grid: bool = data.get("from_grid", false)
	var src := int(data.get("index", -1))
	var id := String(data.get("id", ""))
	var gc := _cell_at(pos, sz)

	if _in_grid(gc, sz) and _fits(gc.x, gc.y, sz, src if from_grid else -1):
		if from_grid and src >= 0 and src < items.size():
			items[src]["x"] = gc.x
			items[src]["y"] = gc.y
		elif not from_grid:
			items.append({"id": id, "x": gc.x, "y": gc.y})
		else:
			return
	else:
		# Außerhalb / kein Platz: platziertes Bauteil entfernen, Palette-Bauteil ignorieren.
		if from_grid and src >= 0 and src < items.size():
			items.remove_at(src)
		else:
			return

	emit_signal("items_changed", items.duplicate(true))
	_rebuild()


func _cell_at(pos: Vector2, sz: Vector2i) -> Vector2i:
	# Cursor zeigt auf die Item-Mitte → halbe Größe abziehen, dann auf Zellen runden.
	var local := pos - _grid_origin - Vector2(sz) * cell * 0.5 + Vector2(cell, cell) * 0.5
	return Vector2i(int(floor(local.x / cell)), int(floor(local.y / cell)))


func _in_grid(gc: Vector2i, sz: Vector2i) -> bool:
	return gc.x >= 0 and gc.y >= 0 and gc.x + sz.x <= cols and gc.y + sz.y <= rows


# Passt sz mit Ecke (gx,gy) ins Raster, ohne mit anderen (außer ignore_index) zu überlappen?
func _fits(gx: int, gy: int, sz: Vector2i, ignore_index: int) -> bool:
	if gx < 0 or gy < 0 or gx + sz.x > cols or gy + sz.y > rows:
		return false
	for i in items.size():
		if i == ignore_index:
			continue
		var it: Dictionary = items[i]
		var isz := _size_of(String(it.get("id", "")))
		var ix := int(it.get("x", 0))
		var iy := int(it.get("y", 0))
		if gx < ix + isz.x and gx + sz.x > ix and gy < iy + isz.y and gy + sz.y > iy:
			return false
	return true


# ── Stil-Helfer ──────────────────────────────────────────────────────────────────
func _box(bg: Color, border: Color, bw: int, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(bw)
	sb.border_color = border
	sb.set_corner_radius_all(int(radius))
	return sb


func _item_box(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(0, 0, 0, 0.35)
	return sb


func _item_label(tile: Control, txt: String, fs: int) -> void:
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", Color(0, 0, 0, 0.82))
	lbl.text = txt
	tile.add_child(lbl)
