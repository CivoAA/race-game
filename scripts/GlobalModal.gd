extends CanvasLayer
## Fullscreen-Modal: Shop | Errungenschaften | Werkstatt.
## Autoload "GlobalModal" (layer 25, über GameHUD).
## process_mode ALWAYS damit es auch bei Pause funktioniert.

const VW = 960
const VH = 540
const TAB_BAR_H = 48

const C_BG        := Color(0.07, 0.13, 0.15)
const C_SURFACE   := Color(0.11, 0.20, 0.23)
const C_SURFACE2  := Color(0.17, 0.29, 0.33)
const C_ACCENT    := Color(0.16, 0.66, 0.87)
const C_ACCENT_MU := Color(0.16, 0.37, 0.54)
const C_ACCENT_RD := Color(0.97, 0.41, 0.43)
const C_TEXT      := Color(0.90, 0.97, 0.96)
const C_TEXT_DIM  := Color(0.48, 0.64, 0.65)
const C_LINE      := Color(0.17, 0.29, 0.32)

# Reifen/Autos/Lackierung sind vorerst ausgeblendet (Platzhalter, noch nicht spielbar).
const SHOP_CATS = [
	{"id": "tiles",    "name": "Streckenteile", "icon": "🏎"},
	{"id": "upgrades", "name": "Upgrades",      "icon": "⬆"},
]
const MODAL_TABS = ["Shop", "Archivments", "Werkstatt", "Prestige"]
const PRESTIGE_TAB = 3

var _active_modal_tab: int = 0
var _active_shop_cat:  int = 0

var _modal_tab_btns:    Array[Button] = []
var _shop_sidebar_btns: Array[Button] = []
var _modal_money_lbl:   Label         = null   # Geldstand oben rechts in der Tab-Leiste

# Inhaltsbereiche (je ein Control, visible-Switching)
var _tab_panels:  Array[Control] = []
var _shop_cats:   Array[Control] = []

# Streckenteile-Tab: rotierende 3D-Vorschauen + Karten-Raster (für Neuaufbau nach Freischalten)
var _tile_preview_pivots: Array         = []   # Node3D-Pivots, drehen sich wenn der Tab sichtbar ist
var _tiles_grid:          GridContainer = null
# true = das Karten-Raster muss neu gebaut werden (z. B. nach Speicherstand-Wechsel),
# weil dieser Autoload Szenenwechsel überlebt und Freischaltungen pro Slot gelten.
var _tiles_dirty:         bool          = false
# Freischalt-/Kauf-Buttons (nur noch nicht erworbene) für günstiges Nachfärben bei Geldänderung.
var _tile_buttons:        Array         = []   # je {btn, key}
var _tile_upgrade_buttons: Array        = []   # je {btn, id} – Upgrade-Buttons freigeschalteter Tiles
var _upgrade_buttons:     Array         = []   # je {btn, id}
var _last_currency_seen:  int           = -1

# ── Prestige-Tab ────────────────────────────────────────────────────────────────
var _prestige_tree_box:   HBoxContainer = null   # Knoten-Karten (links → rechts), für Neuaufbau
var _prestige_points_lbl: Label         = null
var _prestige_earned_lbl: Label         = null
var _prestige_btn:        Button        = null   # „PRESTIGE → +N ⭐"
var _prestige_confirm:    Control       = null   # Bestätigungs-Overlay
var _prestige_confirm_lbl: Label        = null


func _ready() -> void:
	layer        = 25
	visible      = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_modal()
	GameHUD.shop_requested.connect(open)
	# Beim Wechsel des Speicherstands gelten andere Freischaltungen → Raster neu aufbauen.
	Economy.slot_changed.connect(_on_slot_changed)
	# Prestige-Punkte/Knoten geändert → Prestige-Tab aktualisieren.
	Economy.prestige_changed.connect(_rebuild_prestige)


func _on_slot_changed(_slot: int) -> void:
	_tiles_dirty = true


func open() -> void:
	# Streckenteile-Status ist slot-abhängig; nach einem Slot-Wechsel hier neu aufbauen.
	if _tiles_dirty:
		_populate_tiles_grid()
		_tiles_dirty = false
	# Button-Optik (Streckenteile + Upgrades) an den aktuellen Geldstand anpassen.
	_last_currency_seen = Economy.get_currency()
	# Upgrade-Zeilen immer neu aufbauen → nach einem Prestige stimmen Stufen & Preise sofort
	# (sonst stünden bis zur ersten Interaktion die alten Werte da). Billig (kein 3D).
	_rebuild_shop_upgrades()
	_refresh_affordability()
	_rebuild_prestige()   # Punkte/Knoten könnten sich seit dem letzten Öffnen geändert haben
	_refresh_modal_money()
	visible = true


# Aktuellen Geldstand in der Tab-Leiste (oben rechts) aktualisieren.
func _refresh_modal_money() -> void:
	if _modal_money_lbl != null:
		_modal_money_lbl.text = "💰  %s" % Economy.format_currency(Economy.get_currency())


# Färbt alle noch kaufbaren Buttons (Streckenteile + Upgrades) nach dem aktuellen Geldstand.
func _refresh_affordability() -> void:
	_refresh_tile_buttons()
	_refresh_upgrade_buttons()


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	# Vorschau-Auto langsam drehen, solange die Werkstatt sichtbar ist
	if _active_modal_tab == 2 and _preview_pivot != null:
		_preview_pivot.rotate_y(delta * 0.6)
	# Streckenteil-Vorschauen drehen, solange der Streckenteile-Tab sichtbar ist
	elif _active_modal_tab == 0 and _active_shop_cat == 0:
		for p in _tile_preview_pivots:
			if is_instance_valid(p):
				p.rotate_y(delta * 0.6)

	# Kauf-Buttons (Streckenteile + Upgrades) live nachfärben, sobald sich der Geldstand
	# ändert. Läuft nur, solange das Upgrade-Center offen ist (oben steht `if not visible:
	# return`) und färbt nur um – daher kein Lag im normalen Spiel.
	var cur := Economy.get_currency()
	if cur != _last_currency_seen:
		_last_currency_seen = cur
		_refresh_affordability()
		_refresh_modal_money()

	# Prestige-Tab: Vorschau-Zahl („+N ⭐") live mitziehen, während im Hintergrund Geld reinkommt.
	if _active_modal_tab == PRESTIGE_TAB:
		_refresh_prestige_action()


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
	_build_prestige_panel(panel,       CONTENT_Y, CONTENT_H)

	_build_prestige_confirm(panel)

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

	# Tab-Buttons (zentriert) – Breite dynamisch aus der Tab-Anzahl.
	const TAB_W = 120
	const TAB_GAP = 4
	var total_tabs_w = MODAL_TABS.size() * TAB_W + (MODAL_TABS.size() - 1) * TAB_GAP
	var tabs_x = (VW - total_tabs_w) / 2.0
	for i in MODAL_TABS.size():
		var btn := Button.new()
		btn.text     = MODAL_TABS[i]
		btn.position = Vector2(tabs_x + i * (TAB_W + TAB_GAP), 6)
		btn.size     = Vector2(TAB_W, TAB_BAR_H - 12)
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

	# Aktueller Geldstand – gerahmtes Kästchen links neben dem Schließen-✕ (live in _process).
	const MONEY_W = 144
	const MONEY_H = 30
	var money_box := Panel.new()
	money_box.position = Vector2(VW - 46 - 28 - MONEY_W, (TAB_BAR_H - MONEY_H) / 2.0)
	money_box.size     = Vector2(MONEY_W, MONEY_H)
	var money_sb := StyleBoxFlat.new()
	money_sb.bg_color     = C_SURFACE
	money_sb.set_border_width_all(1)
	money_sb.border_color = C_ACCENT
	money_sb.set_corner_radius_all(10)
	money_box.add_theme_stylebox_override("panel", money_sb)
	parent.add_child(money_box)

	_modal_money_lbl = Label.new()
	_modal_money_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_money_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_modal_money_lbl.add_theme_font_size_override("font_size", 16)
	_modal_money_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22))
	money_box.add_child(_modal_money_lbl)


# ── Modal-Tab-Switching ────────────────────────────────────────────────────────

func _on_modal_tab(idx: int) -> void:
	_active_modal_tab = idx
	for i in _modal_tab_btns.size():
		_style_modal_tab(_modal_tab_btns[i], i == idx)
	_show_modal_tab(idx)
	_refresh_affordability()
	if idx == PRESTIGE_TAB:
		_rebuild_prestige()


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

	# Nur Streckenteile (0) + Upgrades (1). Reifen/Autos/Lackierung sind ausgeblendet.
	_build_cat_tiles(container, CAT_X, ch, CAT_W)
	_build_cat_upgrades(container, CAT_X, ch, CAT_W)

	_show_shop_cat(0)


func _on_shop_cat(idx: int) -> void:
	_active_shop_cat = idx
	for i in _shop_sidebar_btns.size():
		_style_sidebar_btn(_shop_sidebar_btns[i], i == idx)
	_show_shop_cat(idx)
	_refresh_affordability()


func _show_shop_cat(idx: int) -> void:
	for cat in _shop_cats:
		cat.visible = false
	if idx < _shop_cats.size():
		_shop_cats[idx].visible = true


# ── Streckenteile-Katalog ───────────────────────────────────────────────────────
# Werkstatt-Stil: pro Tile eine rotierende 3D-Vorschau + Freischalt-Button darunter.
# key/cost werden aus Economy.TILE_UNLOCK_COST gezogen (gemeinsame Quelle mit Main.gd).
#   key ""       → kostenlos/immer freigeschaltet (Dreck-Tiles)
#   model ""     → noch kein eigenes 3D-Modell → Default-Strecke unter schwarzem Film
#   film true    → Modell vorhanden, aber als Platzhalter abgedunkelt
#   coming true  → noch nicht verfügbar (Button deaktiviert)
func _tile_entries() -> Array:
	return [
		{"name": "Dreck-Gerade", "key": "",            "model": Paths.MODEL_TRACK_STRAIGHT_DIRT,    "desc": "+1 Ertrag · frei", "upgrade": "dirtstraightbonus", "field_earn_base": 1},
		{"name": "Dreck-Kurve",  "key": "",            "model": Paths.MODEL_TRACK_CURVE_DEFAULT,    "desc": "+1 Ertrag · frei", "film": true, "upgrade": "dirtcurvebonus", "field_earn_base": 1},
		{"name": "Gerade",       "key": "def_straight","model": Paths.MODEL_TRACK_STRAIGHT_DEFAULT, "desc": "+50 Ertrag · ×1.2", "upgrade": "straightbonus", "field_earn_base": 50},
		{"name": "Kurve",        "key": "def_curve",   "model": Paths.MODEL_TRACK_CURVE_DEFAULT,    "desc": "+50 Ertrag · ×1.2", "upgrade": "curvebonus", "field_earn_base": 50},
		{"name": "Eisgerade",    "key": "ice",         "model": Paths.MODEL_TRACK_STRAIGHT_ICE,     "desc": "Speed-Boost · kein Geld", "upgrade": "icebonus", "field_earn_base": 0},
		{"name": "Rampe",        "key": "ramp",        "model": "",                                 "desc": "Sprung ×2 · Kreuzung", "upgrade": "rampbonus", "field_earn_base": int(Economy.RAMP_BASE_EARN)},
		{"name": "Schikane",     "key": "coming",      "model": "", "desc": "Bald verfügbar", "coming": true},
		{"name": "Steilkurve",   "key": "coming",      "model": "", "desc": "Bald verfügbar", "coming": true},
		{"name": "Boost-Feld",   "key": "coming",      "model": "", "desc": "Bald verfügbar", "coming": true},
		{"name": "Tunnel",       "key": "coming",      "model": "", "desc": "Bald verfügbar", "coming": true},
	]


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
	info.text = "Schalte neue Streckenteile frei. Freigeschaltete Teile stehen danach im Baumodus (Hammer-Button) zur Verfügung."
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", C_TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.custom_minimum_size = Vector2(w - 32, 0)
	var ipad := HBoxContainer.new()
	ipad.add_child(_hpad(16)); ipad.add_child(info)
	vbox.add_child(ipad)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(pad)

	# Karten-Raster (4 Spalten); füllt 2 Reihen sichtbar, Rest scrollbar.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	vbox.add_child(margin)

	_tiles_grid = GridContainer.new()
	_tiles_grid.columns = 4
	_tiles_grid.add_theme_constant_override("h_separation", 12)
	_tiles_grid.add_theme_constant_override("v_separation", 12)
	margin.add_child(_tiles_grid)

	_populate_tiles_grid()


func _populate_tiles_grid() -> void:
	if _tiles_grid == null:
		return
	_tile_preview_pivots.clear()
	_tile_buttons.clear()
	_tile_upgrade_buttons.clear()
	for c in _tiles_grid.get_children():
		c.queue_free()
	for entry in _tile_entries():
		var card := _make_tile_card(entry)
		_tiles_grid.add_child(card)
		# Vorschau erst NACH dem Einhängen aufbauen, damit global_transform/Kamera gültig sind.
		_attach_tile_preview(card, entry)


const CARD_PREV_POS = Vector2(7, 7)
const CARD_PREV_SZ  = Vector2(160, 110)


# Fügt die rotierende 3D-Vorschau (+ optionalen schwarzen Film) in eine bereits
# im Baum hängende Karte ein.
func _attach_tile_preview(card: Panel, entry: Dictionary) -> void:
	var coming: bool   = entry.get("coming", false)
	var model:  String = entry.get("model", "")
	var film:   bool   = coming or model == "" or entry.get("film", false)
	var show_model = model if model != "" else Paths.MODEL_TRACK_STRAIGHT_DEFAULT

	_build_tile_preview(card, CARD_PREV_POS, CARD_PREV_SZ, show_model)

	if film:
		var veil := ColorRect.new()
		veil.position = CARD_PREV_POS
		veil.size     = CARD_PREV_SZ
		veil.color    = Color(0, 0, 0, 0.74)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(veil)

		var veil_lbl := Label.new()
		veil_lbl.position = Vector2(CARD_PREV_POS.x, CARD_PREV_POS.y + CARD_PREV_SZ.y / 2.0 - 11)
		veil_lbl.size     = Vector2(CARD_PREV_SZ.x, 22)
		veil_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		veil_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		veil_lbl.add_theme_font_size_override("font_size", 12)
		veil_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		veil_lbl.text = "BALD" if coming else "VORSCHAU FOLGT"
		veil_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(veil_lbl)


func _make_tile_card(entry: Dictionary) -> Panel:
	const CARD_W = 174
	const CARD_H = 214

	var key:    String = entry.get("key", "")
	var coming: bool   = entry.get("coming", false)
	var owned:  bool   = (not coming) and Economy.is_tile_unlocked(key)
	# Freigeschaltete Tiles mit zugehörigem Upgrade lassen sich hier direkt steigern.
	var upg_id: String = entry.get("upgrade", "")
	var has_upg: bool  = owned and upg_id != ""

	var card := Panel.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var csb := StyleBoxFlat.new()
	csb.bg_color = C_SURFACE
	csb.border_color = C_ACCENT if owned else C_LINE
	csb.set_border_width_all(2 if owned else 1)
	csb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", csb)

	# Name
	var name_lbl := Label.new()
	name_lbl.position = Vector2(0, 122)
	name_lbl.size     = Vector2(CARD_W, 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", C_TEXT if not coming else C_TEXT_DIM)
	name_lbl.text = entry.get("name", "?")
	card.add_child(name_lbl)

	# Beschreibung
	var desc_lbl := Label.new()
	desc_lbl.position = Vector2(0, 143)
	desc_lbl.size     = Vector2(CARD_W, 16)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	if has_upg and upg_id == "icebonus":
		# Eisgerade: Speed-Boost (Tempo-Stufen) + Reichweite statt Geld-Ertrag.
		var ice_lv := Economy.get_upgrade_level(upg_id)
		var max_tag := " (MAX)" if Economy.is_maxed(upg_id) else ""
		desc_lbl.text = "❄ +%.1f Lvl · %d Felder%s" % [Economy.get_ice_boost_levels(ice_lv), Economy.get_ice_range(ice_lv), max_tag]
	elif has_upg:
		# Aktuellen Ertrag pro Feld zeigen, bei nicht-maxed mit "von → zu".
		var base_e := int(entry.get("field_earn_base", 0))
		var lv     := Economy.get_upgrade_level(upg_id)
		var cur    := base_e + int(round(Economy.get_effect(upg_id, lv)))
		if Economy.is_maxed(upg_id):
			desc_lbl.text = "Ertrag/Feld: +%d (MAX)" % cur
		else:
			var nxt := base_e + int(round(Economy.get_effect(upg_id, lv + 1)))
			desc_lbl.text = "Ertrag/Feld: +%d → +%d" % [cur, nxt]
		# Rampe: zusätzlich den Sprung-Multiplikator (steigt je 5 Stufen) statt "Feld" zeigen.
		if upg_id == "rampbonus":
			var suffix := " (MAX)" if Economy.is_maxed(upg_id) else " → +%d" % (base_e + int(round(Economy.get_effect(upg_id, lv + 1))))
			desc_lbl.text = "+%d%s · ×%.1f" % [cur, suffix, Economy.get_ramp_jump_mult()]
	else:
		desc_lbl.text = entry.get("desc", "")
	card.add_child(desc_lbl)

	# Aktions-/Freischalt-Button
	var btn := Button.new()
	btn.position = Vector2(10, 168)
	btn.size     = Vector2(CARD_W - 20, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 12)
	if has_upg:
		_setup_tile_upgrade_btn(btn, upg_id)
	elif owned:
		btn.text     = "✓ Freigeschaltet"
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(Color(0.10, 0.26, 0.15), Color(0.30, 0.75, 0.42)))
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.95, 0.65))
	elif coming:
		btn.text     = "Bald verfügbar"
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
		btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	else:
		btn.text = "🔒 %s 💰" % Economy.format_currency(Economy.get_tile_unlock_cost(key))
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_unlock_btn(btn, Economy.get_currency() >= Economy.get_tile_unlock_cost(key))
		btn.pressed.connect(_on_tile_unlock.bind(key))
		_tile_buttons.append({"btn": btn, "key": key})
	card.add_child(btn)

	return card


# Färbt einen Freischalt-Button: leistbar = helleres Blau, sonst gedämpft.
func _style_unlock_btn(btn: Button, can: bool) -> void:
	if can:
		btn.add_theme_stylebox_override("normal",  _sbf(C_ACCENT_MU.darkened(0.2), C_ACCENT))
		btn.add_theme_stylebox_override("hover",   _sbf(C_ACCENT_MU, C_ACCENT))
		btn.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_ACCENT))
	else:
		var sb := _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5))
		btn.add_theme_stylebox_override("normal",  sb)
		btn.add_theme_stylebox_override("hover",   sb)
		btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", C_TEXT if can else C_TEXT_DIM)


# Aktualisiert nur die Button-Optik (leistbar/nicht leistbar) ohne Neuaufbau der Vorschauen.
func _refresh_tile_buttons() -> void:
	for e in _tile_buttons:
		var btn = e["btn"]
		if not is_instance_valid(btn):
			continue
		var key: String = e["key"]
		if Economy.is_tile_unlocked(key):
			continue
		_style_unlock_btn(btn, Economy.get_currency() >= Economy.get_tile_unlock_cost(key))
	# Upgrade-Buttons freigeschalteter Tiles ebenfalls nach Geldstand nachfärben.
	for e in _tile_upgrade_buttons:
		var ub = e["btn"]
		if not is_instance_valid(ub):
			continue
		var uid: String = e["id"]
		if Economy.is_maxed(uid):
			continue
		_style_upgrade_btn(ub, Economy.can_buy(uid))


func _on_tile_unlock(key: String) -> void:
	if Economy.is_tile_unlocked(key):
		return
	var cost := Economy.get_tile_unlock_cost(key)
	if Economy.spend(cost):
		Economy.unlock_tile(key)   # → Signal tile_unlocked: Bau-Leiste in Main aktualisiert sich
		_populate_tiles_grid()     # Karte auf "✓ Freigeschaltet" umstellen


# Macht den Karten-Button einer freigeschalteten Tile zum Upgrade-Button (Kosten/Stufe).
func _setup_tile_upgrade_btn(btn: Button, id: String) -> void:
	if Economy.is_maxed(id):
		btn.text     = "✓ MAX (Stufe %d)" % Economy.get_upgrade_level(id)
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(Color(0.10, 0.26, 0.15), Color(0.30, 0.75, 0.42)))
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.95, 0.65))
		return
	btn.text = "⬆ Stufe %d  ·  %s 💰" % [Economy.get_upgrade_level(id) + 1, Economy.format_currency(Economy.get_upgrade_cost(id))]
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_upgrade_btn(btn, Economy.can_buy(id))
	btn.pressed.connect(_on_buy_tile_upgrade.bind(id))
	_tile_upgrade_buttons.append({"btn": btn, "id": id})


func _on_buy_tile_upgrade(id: String) -> void:
	if Economy.buy_upgrade(id):
		_populate_tiles_grid()   # Stufe/Kosten/„von→zu" der Karte aktualisieren


# Baut eine kleine 3D-Vorschau (eigene SubViewport-Welt) auf und merkt sich den
# rotierenden Pivot. Kamera rahmt das Modell automatisch über sein AABB.
func _build_tile_preview(parent: Control, pos: Vector2, sz: Vector2, model_path: String) -> void:
	var svc := SubViewportContainer.new()
	svc.position     = pos
	svc.size         = sz
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(svc)

	var sv := SubViewport.new()
	sv.size          = Vector2i(int(sz.x), int(sz.y))
	sv.own_world_3d   = true
	sv.transparent_bg = false
	sv.msaa_3d        = Viewport.MSAA_DISABLED
	svc.add_child(sv)

	var world := Node3D.new()
	sv.add_child(world)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode      = Environment.BG_COLOR
	env.background_color     = Color(0.12, 0.13, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.55, 0.60, 0.70)
	env.ambient_light_energy = 0.7
	env_node.environment = env
	world.add_child(env_node)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-55, -40, 0)
	key_light.light_energy     = 1.3
	world.add_child(key_light)

	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)

	var pivot := Node3D.new()
	world.add_child(pivot)
	_tile_preview_pivots.append(pivot)

	var model: Node3D = null
	if model_path != "" and ResourceLoader.exists(model_path):
		model = (load(model_path) as PackedScene).instantiate()
	else:
		model = Node3D.new()
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.2, 3.0)
		mi.mesh  = box
		model.add_child(mi)
	pivot.add_child(model)

	# Kamera leicht von schräg oben auf das gerahmte Modell ausrichten.
	var aabb := _calc_aabb(pivot)
	if aabb.size == Vector3.ZERO:
		cam.position = Vector3(2.0, 1.6, 3.2)
		cam.look_at(Vector3.ZERO, Vector3.UP)
		return
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	var radius := aabb.size.length() * 0.5
	var dist := radius / tan(deg_to_rad(cam.fov * 0.5)) * 1.15
	cam.position = Vector3(dist * 0.35, radius * 0.85, dist)
	cam.look_at(Vector3.ZERO, Vector3.UP)


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


# ── Werkstatt (Auto-Konfiguration) ─────────────────────────────────────────────
# Unter-Tabs: Form · Lackierung · Muster · Reifen · Fähigkeit. Darunter eine
# 3D-Live-Vorschau (SubViewport). UI-Gerüst: Auswahl wird im Speicher gehalten;
# nur die Lackierung wird derzeit direkt auf das Vorschau-Modell angewandt.

const WS_TABS = [
	{"id": "form",    "name": "Form",      "icon": "🚗"},
	{"id": "paint",   "name": "Lackierung","icon": "🎨"},
	{"id": "pattern", "name": "Muster",    "icon": "🏁"},
	{"id": "tires",   "name": "Reifen",    "icon": "⚙"},
	{"id": "ability", "name": "Fähigkeit", "icon": "✦"},
]

var _ws_active_tab:  int           = 0
var _ws_sel:         Dictionary    = {"form": 0, "paint": 0, "pattern": 0, "tires": 0, "ability": 0}
var _ws_tab_btns:    Array[Button] = []
var _ws_options_box: Control       = null
var _ws_summary_lbl: Label         = null

# 3D-Vorschau
var _preview_pivot:  Node3D    = null
var _preview_model:  Node3D    = null
var _preview_cam:    Camera3D  = null
var _preview_meshes: Array     = []


func _ws_options(id: String) -> Array:
	match id:
		"form":
			return [
				{"name": "Standard", "icon": "🚗"},
				{"name": "Sport",    "icon": "🏎"},
				{"name": "Kompakt",  "icon": "🚙"},
				{"name": "Truck",    "icon": "🚚"},
			]
		"paint":
			return [
				{"name": "Original", "icon": "🚗"},
				{"name": "Rot",      "color": Color(0.85, 0.15, 0.12)},
				{"name": "Blau",     "color": Color(0.13, 0.40, 0.85)},
				{"name": "Grün",     "color": Color(0.15, 0.65, 0.30)},
				{"name": "Gelb",     "color": Color(0.95, 0.80, 0.15)},
				{"name": "Schwarz",  "color": Color(0.08, 0.08, 0.10)},
				{"name": "Weiß",     "color": Color(0.92, 0.93, 0.96)},
			]
		"pattern":
			return [
				{"name": "Keins",    "icon": "▭"},
				{"name": "Streifen", "icon": "≡"},
				{"name": "Flammen",  "icon": "🔥"},
				{"name": "Karo",     "icon": "🏁"},
			]
		"tires":
			return [
				{"name": "Standard", "icon": "⚙"},
				{"name": "Slicks",   "icon": "●"},
				{"name": "Offroad",  "icon": "◉"},
				{"name": "Winter",   "icon": "❄"},
			]
		"ability":
			return [
				{"name": "Keine",  "icon": "∅"},
				{"name": "Boost",  "icon": "🚀"},
				{"name": "Magnet", "icon": "🧲"},
				{"name": "Schild", "icon": "🛡"},
			]
	return []


func _build_werkstatt_panel(parent: Control, cy: int, ch: int) -> void:
	var container := Control.new()
	container.position = Vector2(0, cy)
	container.size     = Vector2(VW, ch)
	parent.add_child(container)
	_tab_panels.append(container)

	# Unter-Tab-Leiste
	const SUB_W   = 168
	const SUB_GAP = 8
	var total_w = WS_TABS.size() * SUB_W + (WS_TABS.size() - 1) * SUB_GAP
	var sx = (VW - total_w) / 2.0
	_ws_tab_btns.clear()
	for i in WS_TABS.size():
		var t = WS_TABS[i]
		var btn := Button.new()
		btn.text     = "%s  %s" % [t.icon, t.name]
		btn.position = Vector2(sx + i * (SUB_W + SUB_GAP), 12)
		btn.size     = Vector2(SUB_W, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_ws_tab(btn, i == 0)
		btn.pressed.connect(_on_ws_tab.bind(i))
		container.add_child(btn)
		_ws_tab_btns.append(btn)

	# Optionsraster (wird pro Kategorie neu aufgebaut)
	_ws_options_box = Control.new()
	_ws_options_box.position = Vector2(0, 58)
	_ws_options_box.size     = Vector2(VW, 92)
	container.add_child(_ws_options_box)

	# Vorschau-Rahmen + 3D-Viewport
	const PREV_W = 560
	const PREV_H = 290
	var px = (VW - PREV_W) / 2.0
	var py = 158

	var frame := Panel.new()
	frame.position = Vector2(px - 3, py - 3)
	frame.size     = Vector2(PREV_W + 6, PREV_H + 6)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color     = C_SURFACE
	fsb.border_color = C_LINE
	fsb.set_border_width_all(1)
	fsb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fsb)
	container.add_child(frame)

	# Zusammenfassung der aktuellen Auswahl
	_ws_summary_lbl = Label.new()
	_ws_summary_lbl.position = Vector2(px, py + PREV_H + 6)
	_ws_summary_lbl.size     = Vector2(PREV_W, 22)
	_ws_summary_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ws_summary_lbl.add_theme_font_size_override("font_size", 11)
	_ws_summary_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	container.add_child(_ws_summary_lbl)

	_sync_paint_selection_from_economy()
	_build_preview_viewport(container, Vector2(px, py), Vector2(PREV_W, PREV_H))
	_rebuild_ws_options()


# Setzt die markierte Lackierungs-Karte passend zum gespeicherten Economy-Zustand.
func _sync_paint_selection_from_economy() -> void:
	if not Economy.is_car_paint_on():
		_ws_sel["paint"] = 0
		return
	var target := Economy.get_car_paint_color()
	var opts = _ws_options("paint")
	for i in opts.size():
		var c = opts[i].get("color", null)
		if c != null and (c as Color).is_equal_approx(target):
			_ws_sel["paint"] = i
			return
	_ws_sel["paint"] = 0


func _on_ws_tab(idx: int) -> void:
	_ws_active_tab = idx
	for i in _ws_tab_btns.size():
		_style_ws_tab(_ws_tab_btns[i], i == idx)
	_rebuild_ws_options()


func _rebuild_ws_options() -> void:
	if _ws_options_box == null:
		return
	for c in _ws_options_box.get_children():
		c.queue_free()

	var id   = WS_TABS[_ws_active_tab].id
	var opts = _ws_options(id)
	const OPT_W = 120
	const OPT_H = 80
	const GAP   = 10
	var total_w = opts.size() * OPT_W + max(0, opts.size() - 1) * GAP
	var sx = (VW - total_w) / 2.0
	var sel = int(_ws_sel.get(id, 0))
	for i in opts.size():
		var card := _make_ws_option(id, opts[i], i, i == sel)
		card.position = Vector2(sx + i * (OPT_W + GAP), 6)
		card.size     = Vector2(OPT_W, OPT_H)
		_ws_options_box.add_child(card)

	_update_ws_summary()


func _make_ws_option(cat: String, opt: Dictionary, idx: int, selected: bool) -> Panel:
	var card := Panel.new()
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE2 if selected else C_SURFACE
	sb.set_border_width_all(2 if selected else 1)
	sb.border_color = C_ACCENT if selected else C_LINE
	sb.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", sb)

	if cat == "paint" and opt.has("color"):
		var sw := ColorRect.new()
		sw.position = Vector2(12, 10)
		sw.size     = Vector2(96, 38)
		sw.color    = opt.color
		card.add_child(sw)
	else:
		var icon := Label.new()
		icon.position = Vector2(0, 8)
		icon.size     = Vector2(120, 40)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 26)
		icon.text = opt.get("icon", "◆")
		card.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.position = Vector2(2, 52)
	name_lbl.size     = Vector2(116, 22)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", C_TEXT if selected else C_TEXT_DIM)
	name_lbl.text = opt.name
	card.add_child(name_lbl)

	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_ws_option_selected(cat, idx)
	)
	return card


func _on_ws_option_selected(cat: String, idx: int) -> void:
	_ws_sel[cat] = idx
	# Lackierung persistent merken → 3D-Autos (Vorschau wie ingame) übernehmen die Farbe.
	if cat == "paint":
		var opts = _ws_options("paint")
		var col = opts[idx].get("color", null) if idx >= 0 and idx < opts.size() else null
		Economy.set_car_paint(col != null, col if col != null else Economy.get_car_paint_color())
	_rebuild_ws_options()
	_apply_ws_config()


func _update_ws_summary() -> void:
	if _ws_summary_lbl == null:
		return
	var parts: Array = []
	for t in WS_TABS:
		var opts = _ws_options(t.id)
		var i = int(_ws_sel.get(t.id, 0))
		var nm = String(opts[i].name) if i < opts.size() else "?"
		parts.append("%s: %s" % [t.name, nm])
	_ws_summary_lbl.text = "  ·  ".join(parts)


func _style_ws_tab(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color            = C_SURFACE2 if active else C_SURFACE
	sb.border_width_bottom = 3
	sb.border_color        = C_ACCENT if active else C_LINE
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8; sb.content_margin_right  = 8
	sb.content_margin_top  = 4; sb.content_margin_bottom = 4
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 13)


# ── 3D-Vorschau ─────────────────────────────────────────────────────────────────

func _build_preview_viewport(parent: Control, pos: Vector2, sz: Vector2) -> void:
	var svc := SubViewportContainer.new()
	svc.position     = pos
	svc.size         = sz
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(svc)

	var sv := SubViewport.new()
	sv.size           = Vector2i(int(sz.x), int(sz.y))
	sv.own_world_3d    = true
	sv.transparent_bg  = false
	sv.msaa_3d         = Viewport.MSAA_2X
	svc.add_child(sv)

	var world := Node3D.new()
	sv.add_child(world)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode       = Environment.BG_COLOR
	env.background_color      = Color(0.12, 0.13, 0.18)
	env.ambient_light_source  = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color   = Color(0.55, 0.60, 0.70)
	env.ambient_light_energy  = 0.7
	env_node.environment = env
	world.add_child(env_node)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy     = 1.3
	world.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy     = 0.4
	world.add_child(fill)

	_preview_cam = Camera3D.new()
	_preview_cam.fov = 40
	world.add_child(_preview_cam)

	_preview_pivot = Node3D.new()
	world.add_child(_preview_pivot)

	_load_preview_model()
	_frame_preview_camera()
	_apply_ws_config()


func _load_preview_model() -> void:
	_preview_meshes.clear()
	var model: Node3D = null
	# Vorerst das Test-Auto (mit Umfärb-Maske) statt default_car laden.
	if ResourceLoader.exists(Paths.MODEL_TEST_CAR):
		model = (load(Paths.MODEL_TEST_CAR) as PackedScene).instantiate()
	else:
		# Platzhalter-Box falls kein Modell vorhanden
		model = Node3D.new()
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.15, 0.5)
		mi.mesh  = box
		model.add_child(mi)
	_preview_pivot.add_child(model)
	_preview_model = model
	_collect_meshes(model)


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_preview_meshes.append(node)
	for c in node.get_children():
		_collect_meshes(c)


# Kombiniertes AABB aller VisualInstance3D unterhalb von root (im root-lokalen Raum).
func _calc_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has := false
	var inv := root.global_transform.affine_inverse()
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is VisualInstance3D:
			var a: AABB = (n as VisualInstance3D).get_aabb()
			a = (inv * (n as Node3D).global_transform) * a
			if has:
				result = result.merge(a)
			else:
				result = a
				has = true
		for c in n.get_children():
			stack.append(c)
	return result


func _frame_preview_camera() -> void:
	if _preview_pivot == null or _preview_cam == null:
		return
	var aabb := _calc_aabb(_preview_pivot)
	if aabb.size == Vector3.ZERO:
		_preview_cam.position = Vector3(0.5, 0.4, 1.5)
		_preview_cam.look_at(Vector3.ZERO, Vector3.UP)
		return
	# Modell so verschieben, dass sein Mittelpunkt im Pivot-Ursprung liegt
	var center := aabb.position + aabb.size * 0.5
	if _preview_model != null:
		_preview_model.position -= center
	var radius := aabb.size.length() * 0.5
	var dist := radius / tan(deg_to_rad(_preview_cam.fov * 0.5)) * 1.25
	_preview_cam.position = Vector3(dist * 0.35, radius * 0.7, dist)
	_preview_cam.look_at(Vector3.ZERO, Vector3.UP)


# Wendet die Lackierung live auf das Vorschau-Modell an. "Original" entfernt den
# Override und zeigt das Originalmaterial. Bei einer Farbe wird ein Masken-Shader
# gelegt: nur die roten Maskenbereiche (Karosserie) werden umgefärbt, die
# Hell-Dunkel-Verläufe der Originaltextur bleiben erhalten.
func _apply_ws_config() -> void:
	var opts = _ws_options("paint")
	var pi = int(_ws_sel.get("paint", 0))
	var col = null
	if pi >= 0 and pi < opts.size():
		col = opts[pi].get("color", null)
	for m in _preview_meshes:
		if not is_instance_valid(m):
			continue
		if col == null:
			(m as MeshInstance3D).material_override = null
		else:
			(m as MeshInstance3D).material_override = _make_paint_material(col)
	_update_ws_summary()


# Shader-Material für die Maskenlackierung (Albedo + Maske gecacht).
var _paint_shader: Shader = null

func _make_paint_material(col: Color) -> ShaderMaterial:
	if _paint_shader == null and ResourceLoader.exists(Paths.SHADER_CAR_PAINT):
		_paint_shader = load(Paths.SHADER_CAR_PAINT)
	var mat := ShaderMaterial.new()
	mat.shader = _paint_shader
	if ResourceLoader.exists(Paths.TEX_CAR_ALBEDO):
		mat.set_shader_parameter("albedo_tex", load(Paths.TEX_CAR_ALBEDO))
	if ResourceLoader.exists(Paths.TEX_CAR_MASK):
		mat.set_shader_parameter("mask_tex", load(Paths.TEX_CAR_MASK))
	mat.set_shader_parameter("paint_color", col)
	return mat


# ── Upgrade-Reihen ────────────────────────────────────────────────────────────

func _add_upgrade_rows(vbox: VBoxContainer, row_w: float) -> void:
	_upgrade_buttons.clear()
	# Feste Reihenfolge nach STARTPREIS aufsteigend (niedrigster oben). Hartkodiert – sortiert
	# sich NICHT bei jeder Preisänderung neu. base_cost: tilebonus 10, speed 50, endmult 500,
	# drive_time 1000, bonus_plus5 2000, bonus_plus10 4000, bonus_mult15 200k, car_count 1M.
	var ids = ["tilebonus", "speed", "endmult", "drive_time",
			   "bonus_plus5", "bonus_plus10", "bonus_mult15", "car_count"]
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
	# "von → zu"-Wert anzeigen, wo es Sinn ergibt (Anzahl/Multiplikator/Zeit/Tile-Werte).
	# Bei Tempo bringt die Zahl nichts → nur die aktuelle Stufe.
	if id != "speed" and not Economy.is_maxed(id):
		l_lbl.text = "Stufe %d / %d   ·  %s → %s" % [lv, mx, Economy.effect_text(id, lv), Economy.effect_text(id, lv + 1)]
	else:
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
		buy_btn.text = "⬆  %s 💰" % Economy.format_currency(Economy.get_upgrade_cost(id))
		_style_upgrade_btn(buy_btn, Economy.can_buy(id))
		_upgrade_buttons.append({"btn": buy_btn, "id": id})
	buy_btn.add_theme_font_size_override("font_size", 12)
	buy_btn.pressed.connect(_on_buy_upgrade.bind(id))
	row.add_child(buy_btn)
	row.add_child(_hpad(16))
	return row


func _on_buy_upgrade(id: String) -> void:
	if Economy.buy_upgrade(id):
		# Upgrades leben jetzt nur noch im Shop-Tab (Kategorie-Index 1)
		if _active_modal_tab == 0 and _active_shop_cat == 1:
			_rebuild_shop_upgrades()


# Stil eines Upgrade-Kauf-Buttons (nicht maxed): leistbar = helleres Blau, sonst gedämpft.
func _style_upgrade_btn(btn: Button, can: bool) -> void:
	if can:
		btn.add_theme_stylebox_override("normal",  _sbf(C_ACCENT_MU.darkened(0.2), C_ACCENT))
		btn.add_theme_stylebox_override("hover",   _sbf(C_ACCENT_MU, C_ACCENT))
		btn.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_ACCENT))
	else:
		var sb := _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5))
		btn.add_theme_stylebox_override("normal",   sb)
		btn.add_theme_stylebox_override("hover",    sb)
		btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_color_override("font_color",          C_TEXT if can else C_TEXT_DIM)
	btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)


# Aktualisiert nur die Upgrade-Button-Optik (leistbar/nicht) ohne Zeilen-Neuaufbau.
func _refresh_upgrade_buttons() -> void:
	for e in _upgrade_buttons:
		var btn = e["btn"]
		if not is_instance_valid(btn):
			continue
		var id: String = e["id"]
		if Economy.is_maxed(id):
			continue
		_style_upgrade_btn(btn, Economy.can_buy(id))


func _rebuild_shop_upgrades() -> void:
	if _shop_cats.size() <= 1:
		return
	var scroll = _shop_cats[1]
	if not scroll is ScrollContainer:
		return
	var vbox = scroll.get_child(0) as VBoxContainer
	if vbox == null:
		return
	for c in vbox.get_children():
		c.queue_free()
	_add_upgrade_rows(vbox, scroll.size.x - 20)


# ── Prestige ────────────────────────────────────────────────────────────────────
# Eigener Top-Level-Tab: oben ein Kopfbereich (⭐-Punkte + großer „PRESTIGE → +N"-Knopf),
# darunter der horizontal scrollbare Tech-Baum (Knoten links → rechts, Pfeile dazwischen).

const C_STAR := Color(1.00, 0.82, 0.20)   # Gold für Prestige-Punkte

func _build_prestige_panel(parent: Control, cy: int, ch: int) -> void:
	var container := Control.new()
	container.position = Vector2(0, cy)
	container.size     = Vector2(VW, ch)
	parent.add_child(container)
	_tab_panels.append(container)

	# ── Kopfbereich ──────────────────────────────────────────────────────────
	_prestige_points_lbl = Label.new()
	_prestige_points_lbl.position = Vector2(24, 14)
	_prestige_points_lbl.size     = Vector2(420, 30)
	_prestige_points_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prestige_points_lbl.add_theme_font_size_override("font_size", 22)
	_prestige_points_lbl.add_theme_color_override("font_color", C_STAR)
	container.add_child(_prestige_points_lbl)

	_prestige_earned_lbl = Label.new()
	_prestige_earned_lbl.position = Vector2(24, 46)
	_prestige_earned_lbl.size     = Vector2(560, 22)
	_prestige_earned_lbl.add_theme_font_size_override("font_size", 12)
	_prestige_earned_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	container.add_child(_prestige_earned_lbl)

	# Großer Prestige-Auslöser rechts oben.
	_prestige_btn = Button.new()
	_prestige_btn.position = Vector2(VW - 24 - 360, 12)
	_prestige_btn.size     = Vector2(360, 56)
	_prestige_btn.focus_mode = Control.FOCUS_NONE
	_prestige_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_prestige_btn.add_theme_font_size_override("font_size", 16)
	_prestige_btn.pressed.connect(_on_prestige_pressed)
	container.add_child(_prestige_btn)

	# Trennlinie
	var line := ColorRect.new()
	line.position = Vector2(0, 80)
	line.size     = Vector2(VW, 1)
	line.color    = C_LINE
	container.add_child(line)

	# ── Tech-Baum (horizontal scrollbar) ─────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 88)
	scroll.size     = Vector2(VW, ch - 88)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	scroll.add_child(margin)

	_prestige_tree_box = HBoxContainer.new()
	_prestige_tree_box.add_theme_constant_override("separation", 0)
	_prestige_tree_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(_prestige_tree_box)

	_rebuild_prestige()


# Kopf-Labels + Knopf + Knoten-Karten neu aufbauen (nach Kauf / Prestige / Tab-Öffnen).
func _rebuild_prestige() -> void:
	_refresh_prestige_action()
	_populate_prestige_tree()


# Nur Kopfbereich (Punkte, verdient, Prestige-Knopf) aktualisieren – günstig, läuft im _process.
func _refresh_prestige_action() -> void:
	if _prestige_points_lbl == null:
		return
	_prestige_points_lbl.text = "⭐ %d Prestige-Punkte" % Economy.get_prestige_points()
	var pending := Economy.prestige_pending_points()
	_prestige_earned_lbl.text = "Seit letztem Prestige verdient: %s 💰   ·   ×-Bonus aktiv: ×%d" % [
		Economy.format_currency(Economy.get_prestige_earned()), int(Economy.get_prestige_mult())]

	if pending >= 1:
		_prestige_btn.text     = "♻  PRESTIGE  →  +%d ⭐" % pending
		_prestige_btn.disabled = false
		_prestige_btn.add_theme_stylebox_override("normal",  _sbf(Color(0.30, 0.24, 0.05), C_STAR))
		_prestige_btn.add_theme_stylebox_override("hover",   _sbf(Color(0.40, 0.32, 0.07), C_STAR))
		_prestige_btn.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_STAR))
		_prestige_btn.add_theme_color_override("font_color", C_STAR)
	else:
		_prestige_btn.text     = "♻  Noch zu früh für Prestige"
		_prestige_btn.disabled = true
		var sb := _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5))
		_prestige_btn.add_theme_stylebox_override("normal",   sb)
		_prestige_btn.add_theme_stylebox_override("disabled", sb)
		_prestige_btn.add_theme_color_override("font_color",          C_TEXT_DIM)
		_prestige_btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)


func _populate_prestige_tree() -> void:
	if _prestige_tree_box == null:
		return
	for c in _prestige_tree_box.get_children():
		c.queue_free()
	var order: Array = Economy.PRESTIGE_ORDER
	for i in order.size():
		var id: String = order[i]
		_prestige_tree_box.add_child(_make_prestige_card(id))
		if i < order.size() - 1:
			# Pfeil-Verbinder: akzentuiert, wenn der nächste Knoten freigeschaltet ist.
			var next_unlocked := Economy.is_prestige_node_unlocked(order[i + 1])
			var arrow := Label.new()
			arrow.custom_minimum_size = Vector2(44, 0)
			arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			arrow.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			arrow.add_theme_font_size_override("font_size", 26)
			arrow.add_theme_color_override("font_color", C_ACCENT if next_unlocked else C_LINE)
			arrow.text = "→"
			_prestige_tree_box.add_child(arrow)


func _make_prestige_card(id: String) -> Panel:
	const CARD_W = 200
	const CARD_H = 300

	var defn:      Dictionary = Economy.PRESTIGE_NODES[id]
	var level:     int  = Economy.get_prestige_node_level(id)
	var maxed:     bool = Economy.is_prestige_node_maxed(id)
	var coming:    bool = Economy.is_prestige_node_coming(id)
	var unlocked:  bool = Economy.is_prestige_node_unlocked(id)
	var active:    bool = unlocked and not coming
	var has_level: bool = level > 0

	var card := Panel.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var csb := StyleBoxFlat.new()
	csb.bg_color     = C_SURFACE
	csb.border_color = C_ACCENT if has_level else (C_LINE if active else C_ACCENT_MU.darkened(0.4))
	csb.set_border_width_all(2 if has_level else 1)
	csb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", csb)

	# Icon
	var icon := Label.new()
	icon.position = Vector2(0, 18)
	icon.size     = Vector2(CARD_W, 46)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 38)
	icon.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	icon.text = String(defn.get("icon", "◆"))
	card.add_child(icon)

	# Name
	var name_lbl := Label.new()
	name_lbl.position = Vector2(6, 74)
	name_lbl.size     = Vector2(CARD_W - 12, 22)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	name_lbl.text = String(defn.get("name", id))
	card.add_child(name_lbl)

	# Stufe
	var lv_lbl := Label.new()
	lv_lbl.position = Vector2(6, 98)
	lv_lbl.size     = Vector2(CARD_W - 12, 18)
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.add_theme_font_size_override("font_size", 11)
	lv_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lv_lbl.text = "Stufe %d / %d" % [level, Economy.get_prestige_node_max(id)]
	card.add_child(lv_lbl)

	# Effekt (von → zu, bzw. nur aktuell wenn maxed)
	var eff_lbl := Label.new()
	eff_lbl.position = Vector2(6, 120)
	eff_lbl.size     = Vector2(CARD_W - 12, 22)
	eff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eff_lbl.add_theme_font_size_override("font_size", 14)
	eff_lbl.add_theme_color_override("font_color", Color(0.70, 0.85, 1.0))
	if maxed:
		eff_lbl.text = Economy.prestige_node_effect_text(id, level)
	else:
		eff_lbl.text = "%s → %s" % [Economy.prestige_node_effect_text(id, level),
			Economy.prestige_node_effect_text(id, level + 1)]
	card.add_child(eff_lbl)

	# Beschreibung
	var desc_lbl := Label.new()
	desc_lbl.position = Vector2(12, 150)
	desc_lbl.size     = Vector2(CARD_W - 24, 80)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.text = String(defn.get("desc", ""))
	card.add_child(desc_lbl)

	# Aktions-Knopf
	var btn := Button.new()
	btn.position = Vector2(12, CARD_H - 50)
	btn.size     = Vector2(CARD_W - 24, 38)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 12)
	if coming:
		btn.text     = "Bald verfügbar"
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
		btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	elif not unlocked:
		btn.text     = "🔒 " + _prestige_prereq_text(id)
		btn.disabled = true
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
		btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	elif maxed:
		btn.text     = "✓ MAX (Stufe %d)" % level
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(Color(0.10, 0.26, 0.15), Color(0.30, 0.75, 0.42)))
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.95, 0.65))
	else:
		var cost := Economy.get_prestige_node_cost(id)
		btn.text = "%d ⭐" % cost
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_prestige_buy_btn(btn, Economy.can_buy_prestige_node(id))
		btn.pressed.connect(_on_buy_prestige_node.bind(id))
	card.add_child(btn)

	return card


# Voraussetzungs-Text eines Knotens ("benötigt ×-Einkommen Lv3").
func _prestige_prereq_text(id: String) -> String:
	var prereq: Dictionary = Economy.PRESTIGE_NODES[id].get("prereq", {})
	for req_id in prereq:
		var nm := String(Economy.PRESTIGE_NODES[req_id].get("name", req_id))
		return "%s Lv%d" % [nm, int(prereq[req_id])]
	return "gesperrt"


# Stil eines Prestige-Kauf-Knopfs (leistbar = Gold, sonst gedämpft).
func _style_prestige_buy_btn(btn: Button, can: bool) -> void:
	if can:
		btn.add_theme_stylebox_override("normal",  _sbf(Color(0.30, 0.24, 0.05), C_STAR))
		btn.add_theme_stylebox_override("hover",   _sbf(Color(0.40, 0.32, 0.07), C_STAR))
		btn.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_STAR))
		btn.add_theme_color_override("font_color", C_STAR)
	else:
		var sb := _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5))
		btn.add_theme_stylebox_override("normal",  sb)
		btn.add_theme_stylebox_override("hover",   sb)
		btn.add_theme_color_override("font_color", C_TEXT_DIM)


func _on_buy_prestige_node(id: String) -> void:
	if Economy.buy_prestige_node(id):
		_rebuild_prestige()


# ── Prestige ausführen (mit Bestätigung) ───────────────────────────────────────

func _on_prestige_pressed() -> void:
	if not Economy.can_prestige():
		return
	_prestige_confirm_lbl.text = "Du erhältst %d ⭐.\n\nGeld, Upgrades, freigeschaltete Teile und ALLE\nStrecken werden zurückgesetzt. Prestige-Boni bleiben." % Economy.prestige_pending_points()
	_prestige_confirm.visible = true


func _build_prestige_confirm(parent: Control) -> void:
	_prestige_confirm = Control.new()
	_prestige_confirm.position = Vector2(0, 0)
	_prestige_confirm.size     = Vector2(VW, VH)
	_prestige_confirm.visible  = false
	parent.add_child(_prestige_confirm)

	var dim := ColorRect.new()
	dim.position     = Vector2(0, 0)
	dim.size         = Vector2(VW, VH)
	dim.color        = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_prestige_confirm.add_child(dim)

	const PW = 460
	const PH = 280
	var panel := Panel.new()
	panel.position = Vector2((VW - PW) / 2.0, (VH - PH) / 2.0)
	panel.size     = Vector2(PW, PH)
	var psb := StyleBoxFlat.new()
	psb.bg_color = C_BG
	psb.border_color = C_STAR
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", psb)
	_prestige_confirm.add_child(panel)

	var title := Label.new()
	title.position = Vector2(0, 22)
	title.size     = Vector2(PW, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_STAR)
	title.text = "PRESTIGE?"
	panel.add_child(title)

	_prestige_confirm_lbl = Label.new()
	_prestige_confirm_lbl.position = Vector2(24, 66)
	_prestige_confirm_lbl.size     = Vector2(PW - 48, 120)
	_prestige_confirm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prestige_confirm_lbl.add_theme_font_size_override("font_size", 13)
	_prestige_confirm_lbl.add_theme_color_override("font_color", C_TEXT)
	panel.add_child(_prestige_confirm_lbl)

	var yes := Button.new()
	yes.position = Vector2(24, PH - 58)
	yes.size     = Vector2((PW - 60) / 2.0, 40)
	yes.focus_mode = Control.FOCUS_NONE
	yes.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	yes.add_theme_font_size_override("font_size", 14)
	yes.text = "♻  Prestige"
	yes.add_theme_stylebox_override("normal",  _sbf(Color(0.30, 0.24, 0.05), C_STAR))
	yes.add_theme_stylebox_override("hover",   _sbf(Color(0.40, 0.32, 0.07), C_STAR))
	yes.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_STAR))
	yes.add_theme_color_override("font_color", C_STAR)
	yes.pressed.connect(_on_prestige_confirmed)
	panel.add_child(yes)

	var no := Button.new()
	no.position = Vector2(36 + (PW - 60) / 2.0, PH - 58)
	no.size     = Vector2((PW - 60) / 2.0, 40)
	no.focus_mode = Control.FOCUS_NONE
	no.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	no.add_theme_font_size_override("font_size", 14)
	no.text = "Abbrechen"
	no.add_theme_stylebox_override("normal",  _sbf(C_SURFACE, C_ACCENT_MU))
	no.add_theme_stylebox_override("hover",   _sbf(C_SURFACE2, C_ACCENT))
	no.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_ACCENT))
	no.add_theme_color_override("font_color", C_TEXT)
	no.pressed.connect(func(): _prestige_confirm.visible = false)
	panel.add_child(no)


func _on_prestige_confirmed() -> void:
	var gained := Economy.do_prestige()
	_prestige_confirm.visible = false
	if gained <= 0:
		return
	# Streckenteile-Raster beim nächsten Öffnen neu aufbauen (Freischaltungen wurden zurückgesetzt).
	# Die Upgrade-Zeilen frischt open() ohnehin neu auf.
	_tiles_dirty = true
	# Alles ist zurückgesetzt → zurück auf Strecke 1 im 2D-Bauplan (frische, leere Strecken).
	GameHUD.reset_after_prestige()
	get_tree().change_scene_to_file(Paths.SCENE_BUILDER)
	# Modal NICHT schließen, sondern auf dem Prestige-Tab offen lassen: so sieht man direkt
	# die frisch erhaltenen ⭐-Punkte und versteht, dass man sie jetzt im Tech-Baum ausgeben kann.
	open()
	_on_modal_tab(PRESTIGE_TAB)


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
	sb.set_corner_radius_all(8)
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
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8; sb.content_margin_right  = 8
	sb.content_margin_top  = 5; sb.content_margin_bottom = 5
	return sb


func _hpad(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c
