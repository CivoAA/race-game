extends CanvasLayer
## Fullscreen-Modal: Shop | Errungenschaften | Werkstatt.
## Autoload "GlobalModal" (layer 25, über GameHUD).
## process_mode ALWAYS damit es auch bei Pause funktioniert.

const VW = 960
const VH = 540
const TAB_BAR_H = 48

const C_BG        := Color(0.10, 0.11, 0.16)
const C_SURFACE   := Color(0.17, 0.19, 0.26)
const C_SURFACE2  := Color(0.22, 0.25, 0.34)
const C_ACCENT    := Color(1.00, 0.52, 0.05)
const C_ACCENT_MU := Color(0.22, 0.30, 0.50)
const C_ACCENT_RD := Color(0.80, 0.18, 0.12)
const C_TEXT      := Color(0.93, 0.95, 1.00)
const C_TEXT_DIM  := Color(0.50, 0.56, 0.70)
const C_LINE      := Color(0.21, 0.24, 0.34)

const SHOP_CATS = [
	{"id": "tiles",    "name": "Streckenteile", "icon": "🏎"},
	{"id": "tires",    "name": "Reifen",        "icon": "⚙"},
	{"id": "cars",     "name": "Autos",         "icon": "🚗"},
	{"id": "paint",    "name": "Lackierung",    "icon": "🎨"},
	{"id": "upgrades", "name": "Upgrades",      "icon": "⬆"},
]
const MODAL_TABS = ["Shop", "Archivments", "Werkstatt"]

var _active_modal_tab: int = 0
var _active_shop_cat:  int = 0

var _modal_tab_btns:    Array[Button] = []
var _shop_sidebar_btns: Array[Button] = []

# Inhaltsbereiche (je ein Control, visible-Switching)
var _tab_panels:  Array[Control] = []
var _shop_cats:   Array[Control] = []


func _ready() -> void:
	layer        = 25
	visible      = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_modal()
	GameHUD.shop_requested.connect(open)


func open() -> void:
	visible = true
	_refresh_werkstatt()


func close() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _build_modal() -> void:
	# ── Hintergrund (Abdunkelung + Panel) ──────────────────────────────────────
	var dim := ColorRect.new()
	dim.position     = Vector2(0, 0)
	dim.size         = Vector2(VW, VH)
	dim.color        = Color(0, 0, 0, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(0, 0)
	panel.size     = Vector2(VW, VH)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_BG
	ps.set_border_width_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	# ── Tab-Leiste (oben, Höhe TAB_BAR_H) ─────────────────────────────────────
	_build_tab_bar(panel)

	# Trennlinie
	var line := ColorRect.new()
	line.position = Vector2(0, TAB_BAR_H)
	line.size     = Vector2(VW, 1)
	line.color    = C_LINE
	panel.add_child(line)

	# ── Inhaltsbereiche (y = TAB_BAR_H+1, h = VH-TAB_BAR_H-1) ────────────────
	const CONTENT_Y = TAB_BAR_H + 1
	const CONTENT_H = VH - TAB_BAR_H - 1

	_build_shop_panel(panel,           CONTENT_Y, CONTENT_H)
	_build_achievements_panel(panel,   CONTENT_Y, CONTENT_H)
	_build_werkstatt_panel(panel,      CONTENT_Y, CONTENT_H)

	_show_modal_tab(0)


func _build_tab_bar(parent: Control) -> void:
	# Linkes Padding + Titel
	var title := Label.new()
	title.position = Vector2(16, 0)
	title.size     = Vector2(90, TAB_BAR_H)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", C_ACCENT)
	title.text = "MENÜ"
	parent.add_child(title)

	# Tab-Buttons (zentriert)
	const TOTAL_TABS_W = 3 * 120 + 2 * 4  # 360+8=368
	var tabs_x = (VW - TOTAL_TABS_W) / 2.0
	for i in MODAL_TABS.size():
		var btn := Button.new()
		btn.text     = MODAL_TABS[i]
		btn.position = Vector2(tabs_x + i * 124, 6)
		btn.size     = Vector2(120, TAB_BAR_H - 12)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_modal_tab(btn, i == 0)
		btn.pressed.connect(_on_modal_tab.bind(i))
		parent.add_child(btn)
		_modal_tab_btns.append(btn)

	# Schließen-Button
	var close_btn := Button.new()
	close_btn.text     = "✕"
	close_btn.position = Vector2(VW - 46, 7)
	close_btn.size     = Vector2(38, TAB_BAR_H - 14)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.add_theme_stylebox_override("normal",  _sbf(C_SURFACE,              C_ACCENT_RD.darkened(0.4)))
	close_btn.add_theme_stylebox_override("hover",   _sbf(C_ACCENT_RD.darkened(0.3), C_ACCENT_RD))
	close_btn.add_theme_stylebox_override("pressed", _sbf(C_SURFACE,              C_ACCENT_RD))
	close_btn.add_theme_stylebox_override("focus",   _sbf(C_SURFACE,              C_ACCENT_RD.darkened(0.4)))
	close_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(close)
	parent.add_child(close_btn)


# ── Modal-Tab-Switching ────────────────────────────────────────────────────────

func _on_modal_tab(idx: int) -> void:
	_active_modal_tab = idx
	for i in _modal_tab_btns.size():
		_style_modal_tab(_modal_tab_btns[i], i == idx)
	_show_modal_tab(idx)
	if idx == 2:
		_refresh_werkstatt()


func _show_modal_tab(idx: int) -> void:
	for i in _tab_panels.size():
		_tab_panels[i].visible = (i == idx)


# ── Shop ──────────────────────────────────────────────────────────────────────

func _build_shop_panel(parent: Control, cy: int, ch: int) -> void:
	var container := Control.new()
	container.position = Vector2(0, cy)
	container.size     = Vector2(VW, ch)
	parent.add_child(container)
	_tab_panels.append(container)

	const SIDEBAR_W = 158

	# Sidebar-Hintergrund
	var sidebar_bg := ColorRect.new()
	sidebar_bg.position = Vector2(0, 0)
	sidebar_bg.size     = Vector2(SIDEBAR_W, ch)
	sidebar_bg.color    = C_SURFACE
	container.add_child(sidebar_bg)

	# Sidebar-Trennlinie
	var sline := ColorRect.new()
	sline.position = Vector2(SIDEBAR_W, 0)
	sline.size     = Vector2(1, ch)
	sline.color    = C_LINE
	container.add_child(sline)

	# Sidebar-Buttons
	for i in SHOP_CATS.size():
		var cat  = SHOP_CATS[i]
		var btn  := Button.new()
		btn.text = "%s  %s" % [cat.icon, cat.name]
		btn.position = Vector2(0, i * 50 + 8)
		btn.size     = Vector2(SIDEBAR_W, 44)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_sidebar_btn(btn, i == 0)
		btn.pressed.connect(_on_shop_cat.bind(i))
		container.add_child(btn)
		_shop_sidebar_btns.append(btn)

	# Inhaltsbereiche für jede Kategorie
	const CAT_X = SIDEBAR_W + 1
	const CAT_W = VW - CAT_X

	_build_cat_tiles(container, CAT_X, ch, CAT_W)
	_build_cat_placeholder(container, CAT_X, ch, CAT_W,
		"Reifen", "Verschiedene Reifen für unterschiedliche\nFahrstile. Kommt bald!")
	_build_cat_placeholder(container, CAT_X, ch, CAT_W,
		"Autos", "Schalte neue Fahrzeuge frei.\nKommt bald!")
	_build_cat_placeholder(container, CAT_X, ch, CAT_W,
		"Lackierung", "Individualisiere dein Auto.\nKommt bald!")
	_build_cat_upgrades(container, CAT_X, ch, CAT_W)

	_show_shop_cat(0)


func _on_shop_cat(idx: int) -> void:
	_active_shop_cat = idx
	for i in _shop_sidebar_btns.size():
		_style_sidebar_btn(_shop_sidebar_btns[i], i == idx)
	_show_shop_cat(idx)


func _show_shop_cat(idx: int) -> void:
	for cat in _shop_cats:
		cat.visible = false
	if idx < _shop_cats.size():
		_shop_cats[idx].visible = true


func _build_cat_tiles(parent: Control, x: int, h: int, w: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x, 0)
	scroll.size     = Vector2(w, h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_shop_cats.append(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(w - 20, 0)
	vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(vbox)

	_add_cat_header(vbox, "STRECKENTEILE")

	var info := Label.new()
	info.text = "Die Streckenteile werden im Baumodus über den\nHammer-Button am linken Bildschirmrand angezeigt\nund ausgewählt. Hier kannst du neue Tiles freischalten."
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", C_TEXT)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	var ipad := HBoxContainer.new()
	ipad.add_child(_hpad(16)); ipad.add_child(info)
	vbox.add_child(ipad)


func _build_cat_placeholder(parent: Control, x: int, h: int, w: int,
		title: String, desc: String) -> void:
	var container := Control.new()
	container.position = Vector2(x, 0)
	container.size     = Vector2(w, h)
	parent.add_child(container)
	_shop_cats.append(container)

	var center_y  = h / 2.0 - 60
	var icon_lbl := Label.new()
	icon_lbl.text     = "🔒"
	icon_lbl.position = Vector2(0, center_y)
	icon_lbl.size     = Vector2(w, 40)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 32)
	container.add_child(icon_lbl)

	var t_lbl := Label.new()
	t_lbl.text     = title.to_upper()
	t_lbl.position = Vector2(0, center_y + 44)
	t_lbl.size     = Vector2(w, 28)
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_lbl.add_theme_font_size_override("font_size", 16)
	t_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	container.add_child(t_lbl)

	var d_lbl := Label.new()
	d_lbl.text     = desc
	d_lbl.position = Vector2(w / 2.0 - 200, center_y + 76)
	d_lbl.size     = Vector2(400, 50)
	d_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d_lbl.add_theme_font_size_override("font_size", 12)
	d_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	container.add_child(d_lbl)


func _build_cat_upgrades(parent: Control, x: int, h: int, w: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x, 0)
	scroll.size     = Vector2(w, h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_shop_cats.append(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(w - 20, 0)
	vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(vbox)
	_add_upgrade_rows(vbox, w - 20)


# ── Errungenschaften ──────────────────────────────────────────────────────────

func _build_achievements_panel(parent: Control, cy: int, ch: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, cy)
	scroll.size     = Vector2(VW, ch)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_tab_panels.append(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(VW - 20, 0)
	vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(vbox)

	_add_cat_header(vbox, "ERRUNGENSCHAFTEN")

	var achievements := [
		["Erster Start",       "Starte dein erstes Rennen",            false],
		["Schnellster Fahrer", "Beende ein Rennen unter 60 Sekunden",  false],
		["Streckenbauer",      "Erstelle 10 verschiedene Strecken",    false],
		["Unaufhaltsam",       "Gewinne 5 Rennen in Folge",            false],
		["Vollgas",            "Erreiche die maximale Geschwindigkeit", false],
	]

	for ach in achievements:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 54)
		row.add_theme_constant_override("separation", 12)

		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(3, 0)
		bar.color               = C_ACCENT if ach[2] else C_ACCENT_MU
		bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(bar)

		row.add_child(_hpad(16))

		var star := Label.new()
		star.text = "★" if ach[2] else "☆"
		star.custom_minimum_size = Vector2(24, 0)
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		star.add_theme_font_size_override("font_size", 20)
		star.add_theme_color_override("font_color", C_ACCENT if ach[2] else C_TEXT_DIM)
		row.add_child(star)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)

		var n_lbl := Label.new()
		n_lbl.text = (ach[0] as String).to_upper()
		n_lbl.add_theme_font_size_override("font_size", 13)
		n_lbl.add_theme_color_override("font_color", C_TEXT)
		info.add_child(n_lbl)

		var d_lbl := Label.new()
		d_lbl.text = ach[1]
		d_lbl.add_theme_font_size_override("font_size", 11)
		d_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		info.add_child(d_lbl)

		vbox.add_child(row)

		var sep := ColorRect.new()
		sep.custom_minimum_size = Vector2(0, 1)
		sep.color = C_LINE
		vbox.add_child(sep)


# ── Werkstatt ─────────────────────────────────────────────────────────────────

var _werkstatt_vbox: VBoxContainer = null

func _build_werkstatt_panel(parent: Control, cy: int, ch: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, cy)
	scroll.size     = Vector2(VW, ch)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_tab_panels.append(scroll)

	_werkstatt_vbox = VBoxContainer.new()
	_werkstatt_vbox.custom_minimum_size = Vector2(VW - 20, 0)
	_werkstatt_vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(_werkstatt_vbox)

	_add_cat_header(_werkstatt_vbox, "WERKSTATT  ·  UPGRADES")
	_add_upgrade_rows(_werkstatt_vbox, VW - 20)


func _refresh_werkstatt() -> void:
	if _werkstatt_vbox == null:
		return
	for c in _werkstatt_vbox.get_children():
		c.queue_free()
	_add_cat_header(_werkstatt_vbox, "WERKSTATT  ·  UPGRADES")
	_add_upgrade_rows(_werkstatt_vbox, VW - 20)


# ── Upgrade-Reihen ────────────────────────────────────────────────────────────

func _add_upgrade_rows(vbox: VBoxContainer, row_w: float) -> void:
	var ids = ["speed", "drive_time", "car_count", "endmult", "tilebonus",
			   "bonus_plus5", "bonus_plus10", "bonus_mult15"]
	for id in ids:
		if Economy.UPGRADES[id].get("category", "") == "hidden":
			continue
		vbox.add_child(_make_upgrade_row(id, row_w))
		var sep := ColorRect.new()
		sep.custom_minimum_size = Vector2(0, 1)
		sep.color = C_LINE
		vbox.add_child(sep)


func _make_upgrade_row(id: String, row_w: float) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(row_w, 56)
	row.add_theme_constant_override("separation", 0)
	row.add_child(_hpad(16))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical   = Control.SIZE_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var n_lbl := Label.new()
	n_lbl.text = Economy.get_upgrade_name(id).to_upper()
	n_lbl.add_theme_font_size_override("font_size", 13)
	n_lbl.add_theme_color_override("font_color", C_TEXT)
	info.add_child(n_lbl)

	var lv  = Economy.get_upgrade_level(id)
	var mx  = Economy.get_max_level(id)
	var l_lbl := Label.new()
	l_lbl.text = "Stufe %d / %d   →  %s" % [lv, mx, Economy.effect_text(id, lv)]
	l_lbl.add_theme_font_size_override("font_size", 11)
	l_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	info.add_child(l_lbl)

	row.add_child(_hpad(12))

	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(130, 40)
	buy_btn.focus_mode = Control.FOCUS_NONE
	buy_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	if Economy.is_maxed(id):
		buy_btn.text     = "MAX"
		buy_btn.disabled = true
		buy_btn.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
		buy_btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	else:
		var cost = Economy.get_upgrade_cost(id)
		buy_btn.text = "⬆  %s 💰" % Economy.format_currency(cost)
		var can = Economy.can_buy(id)
		if can:
			buy_btn.add_theme_stylebox_override("normal",  _sbf(C_ACCENT_MU.darkened(0.2), C_ACCENT))
			buy_btn.add_theme_stylebox_override("hover",   _sbf(C_ACCENT_MU, C_ACCENT))
			buy_btn.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_ACCENT))
		else:
			buy_btn.add_theme_stylebox_override("normal",   _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
			buy_btn.add_theme_stylebox_override("hover",    _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
			buy_btn.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
		buy_btn.add_theme_color_override("font_color",          C_TEXT if can else C_TEXT_DIM)
		buy_btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	buy_btn.add_theme_font_size_override("font_size", 12)
	buy_btn.pressed.connect(_on_buy_upgrade.bind(id))
	row.add_child(buy_btn)
	row.add_child(_hpad(16))
	return row


func _on_buy_upgrade(id: String) -> void:
	if Economy.buy_upgrade(id):
		_refresh_werkstatt()
		# Auch im Shop-Tab Upgrades aktualisieren
		if _active_modal_tab == 0 and _active_shop_cat == 4:
			_rebuild_shop_upgrades()


func _rebuild_shop_upgrades() -> void:
	if _shop_cats.size() <= 4:
		return
	var scroll = _shop_cats[4]
	if not scroll is ScrollContainer:
		return
	var vbox = scroll.get_child(0) as VBoxContainer
	if vbox == null:
		return
	for c in vbox.get_children():
		c.queue_free()
	_add_upgrade_rows(vbox, scroll.size.x - 20)


# ── UI-Hilfsfunktionen ────────────────────────────────────────────────────────

func _add_cat_header(vbox: VBoxContainer, title: String) -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(pad)

	var row := HBoxContainer.new()
	row.add_child(_hpad(16))
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	row.add_child(lbl)
	vbox.add_child(row)

	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = C_LINE
	vbox.add_child(line)

	var pad2 := Control.new()
	pad2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(pad2)


func _style_modal_tab(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color            = C_SURFACE if active else C_BG
	sb.border_width_bottom = 3
	sb.border_color        = C_ACCENT if active else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10; sb.content_margin_right  = 10
	sb.content_margin_top  = 4;  sb.content_margin_bottom = 4
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 14)


func _style_sidebar_btn(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color        = C_SURFACE2 if active else C_SURFACE
	sb.border_width_left = 3
	sb.border_color    = C_ACCENT if active else Color(0, 0, 0, 0)
	sb.content_margin_left = 12; sb.content_margin_right  = 8
	sb.content_margin_top  = 8;  sb.content_margin_bottom = 8
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 13)


func _sbf(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color          = bg
	sb.border_width_left = 3
	sb.border_color      = border
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8; sb.content_margin_right  = 8
	sb.content_margin_top  = 5; sb.content_margin_bottom = 5
	return sb


func _hpad(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c
