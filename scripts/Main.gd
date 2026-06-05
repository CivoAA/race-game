extends Node2D

# Grid-Dimensionen: variabel, werden in _ready aus Economy (Upgrade) gesetzt
var GRID_ROWS: int = 5
var GRID_COLS: int = 6
const TILE_SIZE = 100

# Farben (neue Palette)
const C_BG       := Color(0.09, 0.16, 0.18)
const C_SURFACE  := Color(0.13, 0.23, 0.26)
const C_SURFACE2 := Color(0.18, 0.31, 0.35)
const C_ACCENT   := Color(0.16, 0.66, 0.87)
const C_ACCENT_MU := Color(0.16, 0.37, 0.54)
const C_ACCENT_RD := Color(0.97, 0.41, 0.43)
const C_TEXT     := Color(0.90, 0.97, 0.96)
const C_TEXT_DIM := Color(0.48, 0.64, 0.65)
const C_LINE     := Color(0.17, 0.29, 0.32)

# Build-Panel-Konstanten – vertikales, scrollbares Panel am LINKEN Rand
const BUILD_PANEL_X   = 0
const BUILD_PANEL_W   = 168
const BUILD_PANEL_TOP = 50                       # bündig an der Top-Nav (0–50)
# Untere Werkzeug-Buttons (Hammer = Baumenü öffnen, Papierkorb = löschen).
# Gleiche Größe; sitzen über der 42px-Run-Bar.
const BOTTOM_BTN_W    = 56
const BOTTOM_BTN_H    = 72
const BOTTOM_BTN_Y    = 540 - 42 - 4 - BOTTOM_BTN_H   # = 422
const BUILD_PANEL_BOT = 540 - 42                     # = 498 (Panel reicht bis zum Footer/Run-Bar)
const PAN_BORDER      = 150   # px jenseits des Grid-Rands für Kamera-Pan

# Shop: feste, vertikale Liste kaufbarer Tile-Typen (scrollbar angelegt).
#   tier "dirt"    = kostenlos (Ertrag +1 pro Feld, per Dreck-Ertrag-Upgrade steigerbar)
#   tier "default" = Idle-Preis (steigt je platziertem Tile dieses Typs),
#                    Ertrag +50 UND ×1.2 pro überfahrenem Feld
#   tier "ramp"    = Sprung-Paar; verdoppelt den Ertrag eines Tiles im übersprungenen Feld
#                    (Kreuzung: eine zweite Strecke darunter bringt doppeltes Geld)
# Reihenfolge oben→unten: Dreck-Kurve, Dreck-Gerade, Default-Gerade, Default-Kurve, Rampe.
# key/unlock: Default-Tiles & Rampe müssen einmalig freigeschaltet werden (unlock-Preis);
# der Kaufpreis startet danach bei 20 % des Freischaltpreises (base_price) und skaliert idle.
const SHOP_ITEMS = [
	{"tier": "dirt",    "type": "curve",    "name": "Dreck-Kurve",  "key": "",            "unlock": 0,     "base_price": 0,     "growth": 1.0, "upgrade": "dirtcurvebonus"},
	{"tier": "dirt",    "type": "straight", "name": "Dreck-Gerade", "key": "",            "unlock": 0,     "base_price": 0,     "growth": 1.0, "upgrade": "dirtstraightbonus"},
	{"tier": "default", "type": "straight", "name": "Gerade",       "key": "def_straight","unlock": 15000,  "base_price": 3000,   "growth": 4.0, "upgrade": "straightbonus"},
	{"tier": "default", "type": "curve",    "name": "Kurve",        "key": "def_curve",   "unlock": 30000,  "base_price": 6000,   "growth": 4.0, "upgrade": "curvebonus"},
	{"tier": "ramp",    "type": "ramp",     "name": "Rampe",        "key": "ramp",        "unlock": 500000, "base_price": 100000, "growth": 5.0},
]

const SHOP_SLOT_COUNT = 5   # = SHOP_ITEMS.size()
const JUMP_MULT       = 2.0 # Ertrags-Faktor für ein Tile im übersprungenen Feld einer Rampe

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
var _bonus_sig_on_open: String = ""

# Sprung-Felder (Mittelfeld jeder Rampe) – dort gibt ein Tile × JUMP_MULT Ertrag
var _jump_marker_nodes: Array = []

# Grid tile selection
var selected_grid_row: int = -1
var selected_grid_col: int = -1
var _grid_highlight: Node2D = null

# Shop / Lösch-Zustand
var selected_shop_slot: int   = -1    # Index in SHOP_ITEMS, -1 = nichts gewählt
var ramp_preview_rot:   int   = 0     # (Alt-Rampen)

# Platzierungs-Modus: "quick" (Klick) oder "slow" (Ziehen & Ablegen). Kommt aus den Einstellungen.
var placement_mode: String = "slow"

# Drag-&-Drop-Zustand (nur im "slow"-Modus aktiv)
var _drag_ghost:        Node2D  = null   # mitlaufende Tile-Vorschau am Cursor
var _drag_data:    Dictionary = {}       # aktuelle Daten der Vorschau (Typ/Rotation/Richtung) – via [R]/[F] änderbar
var _drag_orig:    Dictionary = {}       # Originaldaten des gezogenen Grid-Tiles (für Snap-back / Werterhalt)
var _drag_source:       String  = ""     # "shop" | "grid"
var _drag_shop_idx:     int     = -1
var _drag_grid_row:     int     = -1
var _drag_grid_col:     int     = -1
var _grid_drag_pending: bool    = false  # Maustaste auf Tile gedrückt, noch nicht über Schwelle bewegt
var _grid_press_pos:    Vector2 = Vector2.ZERO
var _drag_active:       bool    = false
const DRAG_THRESHOLD := 6.0              # Pixel-Schwelle: Klick (Auswahl) vs. Ziehen

# Build-Panel-Nodes
var _build_layer:   CanvasLayer = null
var _status_lbl:    Label       = null
var _hint_lbl:      Label       = null
var _fahren_btn:    Button      = null
var _build_cards:   Array       = []
var _trash_panel:   Panel       = null   # Papierkorb (nur Slow-Modus)
var _hammer_btn:    Button      = null   # Baumenü-Umschalter (persistent, unten links)

# Persistenter Run-Bar (Layer 4, immer sichtbar: Track-Status + Fahren-Button)
var _run_bar:          CanvasLayer = null
var _run_bar_status:   Label       = null
var _run_bar_btn:      Button      = null
var _track_valid:      bool        = false

# Kamera-Pan (mittlere Maustaste)
var _panning:         bool    = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_cam:   Vector2 = Vector2.ZERO

# Aktuell angezeigter Track-Index (unabhängig von Economy.get_active_track(),
# damit _on_tab_changed den ALTEN Track korrekt speichert)
var _current_track_idx: int = 0

# TileSelector-Shim (ersetzt die entfernte Sidebar, bewahrt alle Aufrufe)
var tile_selector = null

@onready var grid_node:  Node2D   = $Grid
@onready var camera_2d:  Camera2D = $Camera2D


func _ready() -> void:
	GRID_ROWS = Economy.get_grid_rows()
	GRID_COLS = Economy.get_grid_cols()
	_init_grid()
	_draw_grid_background()
	_place_start_tile()
	_setup_grid_highlight()
	_setup_camera()
	_setup_run_bar()
	_setup_build_panel()
	_setup_build_toggle_btn()

	# TileSelector-Shim aufsetzen NACH Build-Panel (Nodes already created)
	var shim := _TileSelectorShim.new()
	shim._status = _status_lbl
	shim._hint   = _hint_lbl
	shim._fahren = _fahren_btn
	shim._main   = self
	tile_selector = shim

	_current_track_idx = Economy.get_active_track()
	var active_idx := _current_track_idx
	# Jede Strecke ist eigenständig → IMMER aus dem Per-Track-Grid laden. Vor jedem Wechsel in
	# die 3D-Ansicht wird die Strecke nach Economy persistiert (_persist_track_for_current);
	# Legacy-Einzelstrecken migriert load_game_from_slot nach Strecke 1. KEIN streckenüber-
	# greifender Fallback (sonst übernähme eine leere Strecke den Bauplan einer anderen).
	var saved_tg := Economy.get_track_grid(active_idx)
	if saved_tg.size() > 0:
		_restore_grid(saved_tg)

	_update_build_ui()
	_roll_bonus_fields()
	_refresh_jump_markers()

	placement_mode = _load_placement_mode()
	_track_valid = _is_track_valid()
	_update_hint_label()

	GameHUD.build_mode_toggled.connect(_on_build_mode_toggled)
	GameHUD.tab_changed.connect(_on_tab_changed)
	GameHUD.view_changed_to_3d.connect(_on_view_3d_requested)
	GameHUD.set_view_3d(false)

	Economy.run_ended.connect(_on_run_ended_background)
	# Im Shop (Streckenteile) freigeschaltete Tiles sofort in der Bau-Leiste spiegeln.
	Economy.tile_unlocked.connect(_on_tile_unlocked)
	# Tile-Upgrade gekauft → Ertragswert in der Bau-Leiste sofort aktualisieren;
	# Bonusfeld-Kauf zeigt das neue Feld sofort auf dem Grid (nicht erst nach einer Runde).
	Economy.upgrade_purchased.connect(_on_upgrade_purchased)

	# Das Lauf-Ende-Popup erscheint nur in der 3D-Ansicht (World3D), nie im 2D-Bauplan.
	if Economy.is_run_active(_current_track_idx):
		GameHUD.set_build_active(false)
	_refresh_run_bar()


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
	# Explizit gewähltes Tile hat Vorrang; sonst standardmäßig das zuletzt platzierte
	# Tile markieren (= aktuelles Ziel für [R]/[F]). Start-Tile wird nie markiert.
	var hr = selected_grid_row
	var hc = selected_grid_col
	if hr < 0 and last_placed_row >= 0:
		var d = grid[last_placed_row][last_placed_col]
		if d != null and not d.get("is_start", false):
			hr = last_placed_row
			hc = last_placed_col
	if hr < 0:
		_grid_highlight.visible = false
	else:
		_grid_highlight.position = _grid_to_world(hr, hc)
		_grid_highlight.visible  = true


# Auswahl bewusst aufheben (zweiter Klick aufs ausgewählte Feld / Rechtsklick ins Leere).
# Blendet den gelben Rahmen direkt aus – _update_grid_highlight würde sonst auf das zuletzt
# platzierte Tile zurückfallen und der Rahmen bliebe sichtbar, obwohl das Baumenü abwählt.
# last_placed bleibt absichtlich erhalten (weiterhin Ziel-Fallback für [R]/[F]/[D]).
func _clear_grid_selection() -> void:
	selected_grid_row = -1
	selected_grid_col = -1
	if _grid_highlight != null:
		_grid_highlight.visible = false
	tile_selector.deselect()


# ── Shop UI ────────────────────────────────────────────────────────────────────

func _setup_camera() -> void:
	# Kamera auf Grid-Mitte setzen; Offset nach oben damit das Grid unterhalb der HUD-Leiste beginnt.
	# offset.y = -(viewport_center_y - hud_height - grid_start_margin)
	# = -(270 - 50 - 15) = -205 → camera.center.y = 250 - 45 = 205
	# → Grid-Oberkante (world y=0) erscheint bei screen y = 270 + (0-205) = 65
	camera_2d.position = Vector2(GRID_COLS * TILE_SIZE / 2.0, GRID_ROWS * TILE_SIZE / 2.0)
	camera_2d.offset   = Vector2(0, -45)
	_update_camera_limits()


func _update_camera_limits() -> void:
	camera_2d.limit_left   = -PAN_BORDER
	camera_2d.limit_right  = GRID_COLS * TILE_SIZE + PAN_BORDER
	camera_2d.limit_top    = -PAN_BORDER
	camera_2d.limit_bottom = GRID_ROWS * TILE_SIZE + PAN_BORDER


const RUN_BAR_H = 42
const RUN_BAR_Y = 540 - RUN_BAR_H

func _setup_run_bar() -> void:
	_run_bar        = CanvasLayer.new()
	_run_bar.layer  = 4
	add_child(_run_bar)

	var bg := ColorRect.new()
	bg.position = Vector2(0, RUN_BAR_Y)
	bg.size     = Vector2(960, RUN_BAR_H)
	bg.color    = Color(0.08, 0.09, 0.13)
	_run_bar.add_child(bg)

	var top_line := ColorRect.new()
	top_line.position = Vector2(0, RUN_BAR_Y)
	top_line.size     = Vector2(960, 1)
	top_line.color    = C_LINE
	_run_bar.add_child(top_line)

	_run_bar_status = Label.new()
	_run_bar_status.position = Vector2(12, RUN_BAR_Y)
	_run_bar_status.size     = Vector2(700, RUN_BAR_H)
	_run_bar_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_run_bar_status.add_theme_font_size_override("font_size", 12)
	_run_bar_status.add_theme_color_override("font_color", C_TEXT_DIM)
	_run_bar.add_child(_run_bar_status)

	_run_bar_btn = Button.new()
	_run_bar_btn.position = Vector2(720, RUN_BAR_Y + 4)
	_run_bar_btn.size     = Vector2(228, RUN_BAR_H - 8)
	_run_bar_btn.focus_mode = Control.FOCUS_NONE
	_run_bar_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_run_bar_btn.pressed.connect(_on_fahren_pressed)
	_run_bar.add_child(_run_bar_btn)
	_refresh_run_bar()


func _refresh_run_bar() -> void:
	if _run_bar_status == null or _run_bar_btn == null:
		return
	var run_active := Economy.is_run_active(_current_track_idx)
	if run_active:
		# Run läuft im Hintergrund → Button wechselt zurück in die 3D-Ansicht
		# (ersetzt den entfernten 3D-Button der Top-Nav).
		_run_bar_status.text = "Runde läuft für Strecke %d" % (_current_track_idx + 1)
		_run_bar_status.add_theme_color_override("font_color", Color(0.25, 0.90, 0.45))
		_set_run_bar_btn_style("🎥  3D-Ansicht", Color(0.08, 0.26, 0.14), Color(0.30, 0.90, 0.50), Color(0.55, 1.0, 0.65))
	elif _track_valid:
		_run_bar_status.text = "✓ Strecke fertig — bereit zum Fahren"
		_run_bar_status.add_theme_color_override("font_color", Color(0.35, 0.90, 0.45))
		_set_run_bar_btn_style("▶  Fahren!", Color(0.08, 0.26, 0.14), Color(0.30, 0.90, 0.50), Color(0.55, 1.0, 0.65))
	else:
		_run_bar_status.text = "Strecke bauen und Runde prüfen"
		_run_bar_status.add_theme_color_override("font_color", C_TEXT_DIM)
		_set_run_bar_btn_style("▶  Fahren!", C_SURFACE, C_ACCENT_MU.darkened(0.4), C_TEXT_DIM)
		_run_bar_btn.disabled = not _track_valid


func _set_run_bar_btn_style(text: String, bg: Color, border: Color, fc: Color) -> void:
	_run_bar_btn.text     = text
	_run_bar_btn.disabled = false
	var sb := StyleBoxFlat.new()
	sb.bg_color          = bg
	sb.border_width_left = 3
	sb.border_color      = border
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8; sb.content_margin_right  = 8
	sb.content_margin_top  = 4; sb.content_margin_bottom = 4
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = bg.lightened(0.08)
	_run_bar_btn.add_theme_stylebox_override("normal",   sb)
	_run_bar_btn.add_theme_stylebox_override("hover",    sb_h)
	_run_bar_btn.add_theme_stylebox_override("pressed",  sb)
	_run_bar_btn.add_theme_stylebox_override("focus",    sb)
	_run_bar_btn.add_theme_stylebox_override("disabled", sb)
	_run_bar_btn.add_theme_color_override("font_color",          fc)
	_run_bar_btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	_run_bar_btn.add_theme_font_size_override("font_size", 13)


func _setup_build_panel() -> void:
	_build_layer = CanvasLayer.new()
	_build_layer.layer   = 5
	_build_layer.visible = false
	add_child(_build_layer)

	var panel_h := BUILD_PANEL_BOT - BUILD_PANEL_TOP

	# Hintergrund – vertikales Panel am linken Rand
	var bg := Panel.new()
	bg.position = Vector2(BUILD_PANEL_X, BUILD_PANEL_TOP)
	bg.size     = Vector2(BUILD_PANEL_W, panel_h)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color            = C_BG
	bg_sb.border_width_right  = 1
	bg_sb.border_color        = C_LINE
	bg_sb.set_corner_radius_all(0)
	bg.add_theme_stylebox_override("panel", bg_sb)
	_build_layer.add_child(bg)

	# ── Kopfzeile mit flachem, eckigem ✕ oben rechts ────────────────────────────
	var mode_lbl := Label.new()
	mode_lbl.text = "🔨  BAUMODUS"
	mode_lbl.position = Vector2(12, BUILD_PANEL_TOP + 9)
	mode_lbl.size = Vector2(BUILD_PANEL_W - 48, 22)
	mode_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_lbl.add_theme_font_size_override("font_size", 13)
	mode_lbl.add_theme_color_override("font_color", C_ACCENT)
	_build_layer.add_child(mode_lbl)

	# Flacher, eckiger ✕-Button im Panel (ragt nicht heraus, kompakt)
	const X_SZ = 24
	var close_btn := Button.new()
	close_btn.position = Vector2(BUILD_PANEL_W - X_SZ - 8, BUILD_PANEL_TOP + 8)
	close_btn.size     = Vector2(X_SZ, X_SZ)
	close_btn.text     = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.tooltip_text = "Baumenü schließen"
	close_btn.add_theme_font_size_override("font_size", 13)
	var x_n := StyleBoxFlat.new()
	x_n.bg_color = C_SURFACE2
	x_n.set_corner_radius_all(8)
	var x_h := x_n.duplicate() as StyleBoxFlat
	x_h.bg_color = C_ACCENT_RD
	close_btn.add_theme_stylebox_override("normal",  x_n)
	close_btn.add_theme_stylebox_override("hover",   x_h)
	close_btn.add_theme_stylebox_override("pressed", x_h)
	close_btn.add_theme_stylebox_override("focus",   x_n)
	close_btn.add_theme_color_override("font_color",       C_TEXT_DIM)
	close_btn.add_theme_color_override("font_hover_color", C_TEXT)
	close_btn.pressed.connect(func(): GameHUD.request_build_toggle())
	_build_layer.add_child(close_btn)

	var hdr_line := ColorRect.new()
	hdr_line.position = Vector2(8, BUILD_PANEL_TOP + 36)
	hdr_line.size     = Vector2(BUILD_PANEL_W - 16, 1)
	hdr_line.color    = C_LINE
	_build_layer.add_child(hdr_line)

	# _fahren_btn als Dummy damit der Shim nicht nullt (echter Button ist im Run-Bar)
	_fahren_btn = Button.new()
	_fahren_btn.visible = false
	_build_layer.add_child(_fahren_btn)

	# ── Fußbereich (eigene Box): Auswahl-Status + dauerhafte Steuerungs-Hinweise ─
	# Oben der aktuelle Status, darunter dauerhaft die Tastenkürzel (Drehen/Wenden).
	# Damit es nicht doppelt steht, zeigt die Ziehen-Statuszeile selbst keine Kürzel.
	const FOOTER_H  = 90
	var footer_top := BUILD_PANEL_BOT - FOOTER_H
	var footer := Panel.new()
	footer.position = Vector2(6, footer_top)
	footer.size     = Vector2(BUILD_PANEL_W - 12, FOOTER_H - 6)
	var foot_sb := StyleBoxFlat.new()
	foot_sb.bg_color     = C_SURFACE
	foot_sb.border_color = C_LINE
	foot_sb.set_border_width_all(1)
	foot_sb.set_corner_radius_all(10)
	footer.add_theme_stylebox_override("panel", foot_sb)
	_build_layer.add_child(footer)

	var foot_inner_w := BUILD_PANEL_W - 12 - 16

	_status_lbl = Label.new()
	_status_lbl.position = Vector2(8, 6)
	_status_lbl.size     = Vector2(foot_inner_w, 32)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.add_theme_color_override("font_color", C_ACCENT)
	footer.add_child(_status_lbl)

	var foot_div := ColorRect.new()
	foot_div.position = Vector2(8, 41)
	foot_div.size     = Vector2(foot_inner_w, 1)
	foot_div.color    = C_LINE
	footer.add_child(foot_div)

	_hint_lbl = Label.new()
	_hint_lbl.position = Vector2(8, 45)
	_hint_lbl.size     = Vector2(foot_inner_w, 38)
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_hint_lbl.add_theme_font_size_override("font_size", 9)
	_hint_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	footer.add_child(_hint_lbl)

	# ── Vertikaler Scroll für Tile-Karten (zwischen Kopf und Fußbox) ────────────
	var scroll_top := BUILD_PANEL_TOP + 44
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, scroll_top)
	scroll.size     = Vector2(BUILD_PANEL_W - 12, footer_top - 6 - scroll_top)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_build_layer.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 7)
	scroll.add_child(vbox)

	for i in range(SHOP_SLOT_COUNT):
		var card := _make_build_card(i)
		vbox.add_child(card)
		_build_cards.append(card)

	# Papierkorb – unten rechts über der Run-Bar (nur Slow-Modus)
	_trash_panel = _make_trash_card()
	_build_layer.add_child(_trash_panel)
	_update_trash_visibility()


# Persistenter Hammer-Button unten links (öffnet/schließt das Baumenü).
func _setup_build_toggle_btn() -> void:
	_hammer_btn = Button.new()
	_hammer_btn.position = Vector2(8, BOTTOM_BTN_Y)
	_hammer_btn.size     = Vector2(BOTTOM_BTN_W, BOTTOM_BTN_H)
	_hammer_btn.text     = "🔨"
	_hammer_btn.focus_mode = Control.FOCUS_NONE
	_hammer_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hammer_btn.tooltip_text = "Baumenü öffnen/schließen"
	_hammer_btn.add_theme_font_size_override("font_size", 28)
	_hammer_btn.pressed.connect(func(): GameHUD.request_build_toggle())
	_run_bar.add_child(_hammer_btn)
	_refresh_hammer_btn()


func _refresh_hammer_btn() -> void:
	if _hammer_btn == null:
		return
	var active := GameHUD.is_build_active()
	var bg     := C_ACCENT if active else C_SURFACE
	var border := C_ACCENT.lightened(0.3) if active else C_ACCENT_MU
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(8)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = bg.lightened(0.08)
	for state in ["normal", "pressed", "focus"]:
		_hammer_btn.add_theme_stylebox_override(state, sb)
	_hammer_btn.add_theme_stylebox_override("hover", sb_h)
	_hammer_btn.add_theme_color_override("font_color", Color(0.10, 0.07, 0.02) if active else C_TEXT)


func _make_header_action_btn(txt: String, pos: Vector2, w: float) -> Button:
	var btn := Button.new()
	btn.text     = txt
	btn.position = pos
	btn.size     = Vector2(w, 28)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE
	sb.border_width_bottom = 2
	sb.border_color = C_ACCENT_MU
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.border_color = C_ACCENT
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb_h)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus",   sb)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 12)
	return btn


func _apply_fahren_style(btn: Button, enabled: bool) -> void:
	var sb := StyleBoxFlat.new()
	if enabled:
		sb.bg_color = Color(0.09, 0.30, 0.16)
		sb.border_width_bottom = 2
		sb.border_color = Color(0.30, 0.95, 0.50)
	else:
		sb.bg_color = C_SURFACE
		sb.border_width_bottom = 2
		sb.border_color = C_ACCENT_MU.darkened(0.5)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal",   sb)
	btn.add_theme_stylebox_override("hover",    sb)
	btn.add_theme_stylebox_override("pressed",  sb)
	btn.add_theme_stylebox_override("focus",    sb)
	btn.add_theme_stylebox_override("disabled", sb)
	var fc := Color(0.50, 1.00, 0.65) if enabled else C_TEXT_DIM
	btn.add_theme_color_override("font_color",          fc)
	btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)


const CARD_H = 58

func _make_build_card(idx: int) -> Panel:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Farbiger Icon-Chip links
	var chip := Panel.new()
	chip.name = "Chip"
	chip.position = Vector2(8, 8)
	chip.size     = Vector2(40, CARD_H - 16)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(chip)

	var icon := Label.new()
	icon.name = "Icon"
	icon.position = Vector2(8, 8)
	icon.size     = Vector2(40, CARD_H - 16)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 20)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)

	# Name (oben), Wert (Mitte), Preis/Status (unten) – rechts neben dem Chip
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.anchor_right = 1.0
	name_lbl.offset_left = 54; name_lbl.offset_right = -10
	name_lbl.offset_top  = 6;  name_lbl.offset_bottom = 24
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.name = "Value"
	val_lbl.anchor_right = 1.0
	val_lbl.offset_left = 54; val_lbl.offset_right = -10
	val_lbl.offset_top  = 24; val_lbl.offset_bottom = 39
	val_lbl.clip_text = true
	val_lbl.add_theme_font_size_override("font_size", 9)
	val_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(val_lbl)

	var price_lbl := Label.new()
	price_lbl.name = "Price"
	price_lbl.anchor_right = 1.0
	price_lbl.offset_left = 54; price_lbl.offset_right = -10
	price_lbl.offset_top  = 38; price_lbl.offset_bottom = 53
	price_lbl.clip_text = true
	price_lbl.add_theme_font_size_override("font_size", 10)
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(price_lbl)

	card.gui_input.connect(func(e): _on_shop_slot_gui_input(e, idx))
	return card


func _make_trash_card() -> Panel:
	const TW  = BOTTOM_BTN_W
	const TH  = BOTTOM_BTN_H
	const TX  = 960 - 8 - TW          # unten rechts
	const TY  = BOTTOM_BTN_Y          # gleiche Höhe wie der Hammer-Button
	var card := Panel.new()
	card.position = Vector2(TX, TY)
	card.size     = Vector2(TW, TH)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color(0.25, 0.08, 0.08)
	sb_n.border_width_left = 2; sb_n.border_color = C_ACCENT_RD.darkened(0.3)
	sb_n.set_corner_radius_all(8)
	var sb_h := sb_n.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.38, 0.10, 0.10)
	sb_h.border_color = C_ACCENT_RD
	card.add_theme_stylebox_override("panel", sb_n)

	var lbl := Label.new()
	lbl.text = "🗑"
	lbl.size = Vector2(TW, TH)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.32, 0.28))   # hellrot
	card.add_child(lbl)
	return card


func _update_trash_visibility() -> void:
	if _trash_panel == null:
		return
	_trash_panel.visible = (placement_mode == "slow")


func _is_over_trash(screen_pos: Vector2) -> bool:
	if _trash_panel == null or not _trash_panel.visible:
		return false
	var r := Rect2(_trash_panel.position, _trash_panel.size)
	return r.has_point(screen_pos)


func _on_build_mode_toggled(active: bool) -> void:
	if _build_layer != null:
		_build_layer.visible = active
	# Hammer-Button verschwindet, sobald das Baumenü offen ist (Schließen via Leiste oben)
	if _hammer_btn != null:
		_hammer_btn.visible = not active
	_update_trash_visibility()
	_refresh_hammer_btn()


func _on_tab_changed(idx: int) -> void:
	# Aktuellen Track mit dem ALTEN Index speichern, BEVOR der Index wechselt
	Economy.set_track_grid(_current_track_idx, get_grid_state())
	Economy.save_game()

	# Ist die Zielstrecke in der 3D-Ansicht? Dann Szene wechseln statt im 2D-Bauplan zu bleiben.
	if GameHUD.is_track_3d(idx):
		GameHUD.goto_world3d(idx)
		return

	_current_track_idx = idx

	# Grid des neuen Tabs laden
	var new_grid := Economy.get_track_grid(idx)
	for c in grid_node.get_children():
		c.queue_free()
	_init_grid()
	_draw_grid_background()
	_place_start_tile()
	_setup_grid_highlight()
	if new_grid.size() > 0:
		_restore_grid(new_grid)
	_update_build_ui()
	_roll_bonus_fields()
	_refresh_jump_markers()
	selected_grid_row  = -1
	selected_grid_col  = -1
	selected_shop_slot = -1
	_update_grid_highlight()
	tile_selector.deselect()

	_track_valid = _is_track_valid()
	_refresh_run_bar()

	# Lauf-Ende-Popup nur in der 3D-Ansicht – beim Tab-Wechsel im 2D-Bauplan nichts zeigen.
	if Economy.is_run_active(idx):
		tile_selector.set_status("")
		GameHUD.set_build_active(false)

	# Baupanel-Sichtbarkeit an den (maßgeblichen) GameHUD-Zustand angleichen. Ohne diese
	# Synchronisierung bliebe das Panel nach einem Streckenwechsel sichtbar, obwohl GameHUD
	# es als geschlossen führt → der Schließen-Knopf würde erst beim zweiten Klick wirken.
	_on_build_mode_toggled(GameHUD.is_build_active())


func _on_view_3d_requested() -> void:
	if not Economy.is_run_active(_current_track_idx):
		return  # Button ist unsichtbar wenn kein Run läuft – Signal trotzdem ignorieren
	_switch_to_3d_view()


func _persist_track_for_current() -> void:
	var state := get_grid_state()
	Economy.set_track_grid(_current_track_idx, state)
	Economy.save_track(state)


# Anzahl platzierter Default-Tiles dieses Typs in EINEM Grid (Kurve zählt curve+curve_alt).
# Akzeptiert sowohl das Live-Grid (leer = null) als auch ein gespeichertes Track-Grid (leer = "").
func _count_paid_tiles_in(g: Array, type: String) -> int:
	var n = 0
	for r in range(g.size()):
		var row = g[r]
		for c in range(row.size()):
			var d = row[c]
			if typeof(d) != TYPE_DICTIONARY or d.get("is_dirt", false) or d.get("is_start", false):
				continue
			var t = d.get("type", "")
			if type == "ramp":
				if t == "ramp_start":   # ein Paar = ein ramp_start
					n += 1
			elif type == "curve":
				if t == "curve" or t == "curve_alt":
					n += 1
			elif t == type:
				n += 1
	return n


# Anzahl bereits platzierter Default-Tiles dieses Typs über ALLE Strecken.
# Die Idle-Preise steigen streckenübergreifend: jede Strecke hat denselben Preis, sodass man
# sich entscheiden muss, auf welcher Strecke man wie viele Tiles baut (kein billiger Neustart
# je Strecke). Aktuelle Strecke aus dem Live-Grid, übrige aus den gespeicherten Track-Grids.
func _count_paid_tiles(type: String) -> int:
	var total = 0
	for ti in range(Economy.TRACK_COUNT):
		if ti == _current_track_idx:
			total += _count_paid_tiles_in(grid, type)
		else:
			total += _count_paid_tiles_in(Economy.get_track_grid(ti), type)
	return total


# Aktueller Preis eines Shop-Items (Dreck = 0, Default/Rampe = idle-skalierend).
func _tile_price(item: Dictionary) -> int:
	if item["tier"] == "dirt":
		return 0
	var n = _count_paid_tiles(item["type"])
	return int(round(float(item["base_price"]) * pow(float(item["growth"]), n)))


# Aktueller Ertrag pro Feld dieses Tile-Typs inkl. gekaufter Tile-Upgrades (für die Bau-Leiste).
# Dreck-Grundwert 1, Default-Grundwert 50; das zugehörige Upgrade addiert seinen Live-Effekt.
func _tile_field_earn(item: Dictionary) -> int:
	# Dreck-Grundwert 1, Default-Grundwert 50; das zugehörige Upgrade addiert seinen Live-Effekt.
	var base := 1 if item.get("tier", "") == "dirt" else 50
	return base + int(round(Economy.get_effect(item.get("upgrade", ""))))


# Shop-Item (Default/Rampe) zu einem Tile-Typ; curve_alt→Kurve, ramp_*→Rampe. Leer falls keins.
func _shop_item_for_type(type: String) -> Dictionary:
	var key: String
	if type == "curve" or type == "curve_alt":
		key = "curve"
	elif type == "ramp_start" or type == "ramp_end":
		key = "ramp"
	else:
		key = type
	for item in SHOP_ITEMS:
		if item["tier"] != "dirt" and item["type"] == key:
			return item
	return {}


# Rückerstattung für ein Tile, das gerade noch im Grid liegt (Dreck/Start = 0).
# Default-/Rampen-Tile: erstattet den "marginalen" Preis (base*growth^(Anzahl-1)).
# Bei Rampen zählt das ramp_start-Feld – Überschreiben/Löschen einer beliebigen Seite erstattet.
func _tile_refund_for(data) -> int:
	if data == null or data.get("is_dirt", false) or data.get("is_start", false):
		return 0
	var t = data.get("type", "")
	if not (t in ["straight", "curve", "curve_alt", "ramp_start", "ramp_end"]):
		return 0
	var item = _shop_item_for_type(t)
	if item.is_empty():
		return 0
	var n = _count_paid_tiles(item["type"])   # inkl. dieses Tile (Rampe: zählt ramp_start)
	if n <= 0:
		return 0
	return int(round(float(item["base_price"]) * pow(float(item["growth"]), n - 1)))


func _update_currency_label() -> void:
	pass  # GameHUD aktualisiert sich selbst jeden Frame


func _update_build_ui() -> void:
	if _build_cards.is_empty():
		return
	for i in range(SHOP_SLOT_COUNT):
		var card  = _build_cards[i]
		var item  = SHOP_ITEMS[i]
		var locked   = not Economy.is_tile_unlocked(item["key"])
		var selected = (i == selected_shop_slot)

		# Gesperrte Tiles (Default-Strecken & Rampe) direkt in der Bau-Leiste anzeigen,
		# damit sie dort per Klick einmalig freigeschaltet werden können.
		card.visible = true

		var chip      = card.get_node("Chip")  as Panel
		var icon_lbl  = card.get_node("Icon")  as Label
		var name_lbl  = card.get_node("Name")  as Label
		var val_lbl   = card.get_node("Value") as Label
		var price_lbl = card.get_node("Price") as Label

		icon_lbl.text = "╰" if item["type"] == "curve" else ("⛰" if item["tier"] == "ramp" else "━")
		name_lbl.text = item["name"]

		# Chip-Farbe je Tier (gesperrt = gedämpft)
		var chip_bg: Color
		var chip_fg: Color
		match item["tier"]:
			"dirt":
				chip_bg = Color(0.26, 0.31, 0.19); chip_fg = Color(0.72, 0.90, 0.56)
			"ramp":
				chip_bg = Color(0.40, 0.25, 0.06); chip_fg = Color(1.00, 0.78, 0.36)
			_:
				chip_bg = C_ACCENT_MU.darkened(0.05); chip_fg = Color(0.74, 0.84, 1.00)
		if locked:
			chip_bg = Color(0.20, 0.18, 0.16); chip_fg = Color(0.58, 0.47, 0.36)
		var chip_sb := StyleBoxFlat.new()
		chip_sb.bg_color = chip_bg
		chip_sb.set_corner_radius_all(8)
		chip.add_theme_stylebox_override("panel", chip_sb)
		icon_lbl.add_theme_color_override("font_color", chip_fg)

		# Wert- + Preiszeile je Zustand
		if locked:
			val_lbl.text   = "Im Shop freischalten"
			price_lbl.text = "🔒 Gesperrt"
			price_lbl.add_theme_color_override("font_color", Color(0.80, 0.64, 0.46))
		elif item["tier"] == "dirt":
			val_lbl.text   = "+%d pro Feld" % _tile_field_earn(item)
			price_lbl.text = "Kostenlos"
			price_lbl.add_theme_color_override("font_color", Color(0.64, 0.84, 0.52))
		elif item["tier"] == "ramp":
			var dirs = ["→", "↓", "←", "↑"]
			val_lbl.text   = "Sprung %s  ·  ×2" % dirs[ramp_preview_rot / 90]
			price_lbl.text = "%s 💰" % Economy.format_currency(_tile_price(item))
			price_lbl.add_theme_color_override("font_color", C_ACCENT)
		else:
			val_lbl.text   = "+%d  ·  ×1.2 pro Feld" % _tile_field_earn(item)
			price_lbl.text = "%s 💰" % Economy.format_currency(_tile_price(item))
			price_lbl.add_theme_color_override("font_color", C_ACCENT)

		# Karten-Rahmen je Zustand
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		if selected:
			style.bg_color     = Color(0.26, 0.19, 0.05)
			style.border_color = C_ACCENT
			style.set_border_width_all(2)
		elif locked:
			style.bg_color     = C_SURFACE
			style.border_color = Color(0.40, 0.28, 0.18)
			style.set_border_width_all(1)
		else:
			style.bg_color     = C_SURFACE2
			style.border_color = C_LINE
			style.set_border_width_all(1)
		card.add_theme_stylebox_override("panel", style)

		var name_col := C_TEXT
		if selected:
			name_col = Color(1.00, 0.92, 0.60)
		elif locked:
			name_col = Color(0.82, 0.66, 0.50)
		name_lbl.add_theme_color_override("font_color", name_col)

func _update_delete_panel_style() -> void:
	pass  # Kein separater Delete-Panel mehr


# Reaktion auf eine Freischaltung im Shop (Streckenteile): Bau-Leiste auffrischen.
func _on_tile_unlocked(_key: String) -> void:
	_update_build_ui()
	_update_trash_visibility()


# Reaktion auf einen Upgrade-Kauf: Bau-Leiste auffrischen; bei Bonusfeldern (im Shop gekauft)
# sofort neu würfeln, damit das gekaufte Feld unmittelbar auf einem bebauten Tile erscheint.
func _on_upgrade_purchased(id: String) -> void:
	_update_build_ui()
	if id.begins_with("bonus_"):
		_roll_bonus_fields()
	# Prestige-Knoten „Streckengröße" meldet sich als grid_size → Grid live nachwachsen lassen.
	elif id == "grid_size":
		_rebuild_grid_for_size()


func _on_shop_slot_gui_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var item = SHOP_ITEMS[idx]
	if not Economy.is_tile_unlocked(item["key"]):
		# Freischalten passiert jetzt im Shop → Streckenteile, nicht mehr hier.
		tile_selector.set_status("🔒 %s im Shop → Streckenteile freischalten" % item["name"])
		return
	if placement_mode == "slow":
		_begin_shop_drag(idx)
		_update_build_ui()
		return
	if selected_shop_slot == idx:
		selected_shop_slot = -1
	else:
		selected_shop_slot = idx
		selected_grid_row  = -1
		selected_grid_col  = -1
		_update_grid_highlight()
		tile_selector.deselect()
	_update_build_ui()


func _delete_tile_at(row: int, col: int) -> void:
	var refund = _tile_refund_for(grid[row][col])
	if refund > 0:
		Economy.add(refund)
	_remove_tile(row, col)
	if selected_grid_row == row and selected_grid_col == col:
		selected_grid_row = -1
		selected_grid_col = -1
	_update_grid_highlight()
	_update_build_ui()
	tile_selector.deselect()


func _flash_currency() -> void:
	GameHUD.flash_currency()


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
	# Default-Tiles (straight/curve) zeigen bewusst KEINE Ertrags-Badge mehr.

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

	# Hintergrund: 1px kleiner je Seite, damit der Rasterrahmen (darunter gezeichnet)
	# sichtbar bleibt – sonst wirken Dreck-Tiles randlos/größer als leere Zellen.
	var bg = ColorRect.new()
	bg.size     = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
	bg.position = Vector2(-half + 1, -half + 1)
	bg.color    = bg_col
	node.add_child(bg)

	if data["type"] == "straight":
		# Schmaler Dreck-Streifen (rotiert mit Node → Weltrichtung automatisch korrekt)
		var road = ColorRect.new()
		road.size     = Vector2(TILE_SIZE, pw)
		road.position = Vector2(-half, -pw / 2.0)
		road.color    = soil
		node.add_child(road)
		# Kein Richtungspfeil mehr: Geraden sind in beide Richtungen befahrbar.
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
		# Kein Richtungspfeil mehr – die Fahrtrichtung ergibt sich automatisch aus dem Streckenfluss.

	# Dreck-Tiles zeigen bewusst KEINE Ertrags-Badge mehr.

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

func _process(_delta: float) -> void:
	# Sicherheitsnetz gegen "hängende" Ghost-Tiles: Geht ein Maus-Loslassen verloren
	# (z. B. weil es über dem Baumenü/Shop statt über dem Grid passiert), bliebe das
	# gezogene Tile sonst außerhalb des Grids liegen und ließe sich nicht mehr greifen.
	# Ist ein Drag aktiv, die linke Maustaste aber nicht mehr gedrückt, behandeln wir
	# das wie ein reguläres Loslassen → außerhalb des Grids verschwindet das Tile.
	if (_drag_active or _grid_drag_pending) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_slow_left_release(get_global_mouse_position())


func _input(event: InputEvent) -> void:
	# Mittlere Maustaste: Kamera-Pan (in 2D immer aktiv, unabhängig vom Baumodus)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_panning          = true
				_pan_start_mouse  = event.position
				_pan_start_cam    = camera_2d.position
			else:
				_panning = false
			return
	if _panning and event is InputEventMouseMotion:
		camera_2d.position = _pan_start_cam - event.position + _pan_start_mouse
		return

	# Bearbeitungssperre während ein Run läuft (erst pausieren)
	if Economy.is_run_active(Economy.get_active_track()):
		return

	# Build-Modus nicht aktiv: nur Kamera-Pan erlaubt
	if _build_layer != null and not _build_layer.visible:
		return

	# Maus-Eingaben je nach Platzierungs-Modus
	if placement_mode == "slow":
		_input_slow_mouse(event)
	elif event is InputEventMouseButton and event.pressed:
		# get_global_mouse_position() liefert Weltkoordinaten (Camera2D-bereinigt)
		var local_pos = grid_node.to_local(get_global_mouse_position())
		if local_pos.x < 0 or local_pos.y < 0 or local_pos.x >= GRID_COLS * TILE_SIZE or local_pos.y >= GRID_ROWS * TILE_SIZE:
			return
		var cell = _world_to_grid(local_pos)
		if not _is_valid_cell(cell):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_grid_left_click(cell.x, cell.y)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Rechtsklick auf ein platziertes Tile = löschen (mit Rückerstattung)
			var rc = grid[cell.x][cell.y]
			if rc != null and not rc.get("is_start", false):
				_delete_tile_at(cell.x, cell.y)
			elif selected_grid_row >= 0:
				_clear_grid_selection()

	# Beim Ziehen (Shop oder Grid) verändern [R]/[F] das gezogene Teil selbst „in der Hand"
	# – nicht das auf dem Feld liegende/markierte. Wirkt erst beim Ablegen aufs Grid.
	if _drag_active and event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			_drag_rotate()
			return
		if event.keycode == KEY_F:
			_drag_flip()
			return

	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if selected_shop_slot >= 0 and SHOP_ITEMS[selected_shop_slot]["tier"] == "ramp":
			ramp_preview_rot = (ramp_preview_rot + 90) % 360
			_update_build_ui()
		else:
			_rotate_active(90)

	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_flip_active()

	# D-Taste: ausgewähltes Tile löschen (Quick-Modus)
	if event is InputEventKey and event.pressed and event.keycode == KEY_D:
		var del_row = selected_grid_row if selected_grid_row >= 0 else last_placed_row
		var del_col = selected_grid_col if selected_grid_row >= 0 else last_placed_col
		if del_row >= 0 and _is_valid_cell(Vector2i(del_row, del_col)):
			var dd = grid[del_row][del_col]
			if dd != null and not dd.get("is_start", false):
				_delete_tile_at(del_row, del_col)


# ── Drag & Drop (Slow-Modus) ─────────────────────────────────────────────────────

# Maus-Handling im "slow"-Modus: Ziehen aus dem Shop und Verschieben platzierter Tiles.
# Der Shop-Press wird in _on_shop_slot_gui_input begonnen (kennt den Slot-Index);
# hier laufen Bewegung und Loslassen für beide Quellen zusammen.
func _input_slow_mouse(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _grid_drag_pending and not _drag_active:
			# Schwellen-Check in Weltkoordinaten (Zoom=1 → gleiche Pixeldistanz)
			if get_global_mouse_position().distance_to(_grid_press_pos) > DRAG_THRESHOLD:
				_begin_grid_drag()
		if _drag_active and _drag_ghost != null:
			_drag_ghost.position = _ghost_pos_for(get_global_mouse_position())
		elif not _drag_active and not _grid_drag_pending:
			# Nichts „in der Hand" → das Tile unter der Maus automatisch auswählen, damit es
			# direkt per [R]/[F] gedreht/gewendet werden kann (kein Linksklick zum Auswählen nötig).
			_update_hover_selection(get_global_mouse_position())
		return

	if not (event is InputEventMouseButton):
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_slow_right_click(get_global_mouse_position())
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		_slow_left_press(get_global_mouse_position())
	else:
		_slow_left_release(get_global_mouse_position())


func _slow_left_press(global_pos: Vector2) -> void:
	# Shop-Bereich wird über _on_shop_slot_gui_input behandelt → hier nur das Grid.
	var local = grid_node.to_local(global_pos)
	if local.x < 0 or local.y < 0 or local.x >= GRID_COLS * TILE_SIZE or local.y >= GRID_ROWS * TILE_SIZE:
		return
	var cell = _world_to_grid(local)
	if not _is_valid_cell(cell):
		return
	var d = grid[cell.x][cell.y]

	# Leere Zelle oder Start-Tile: nichts zu greifen.
	if d == null or d.get("is_start", false):
		return

	# ramp_end greift immer das ramp_start-Feld (das Paar wird als Ganzes bewegt).
	var grab_row = cell.x
	var grab_col = cell.y
	if d.get("type", "") == "ramp_end":
		grab_row = d.get("ramp_partner_row", cell.x)
		grab_col = d.get("ramp_partner_col", cell.y)

	_grid_drag_pending = true
	_grid_press_pos    = global_pos
	_drag_grid_row     = grab_row
	_drag_grid_col     = grab_col


func _slow_left_release(global_pos: Vector2) -> void:
	# Papierkorb-Drop (Screen-Koordinaten prüfen)
	if _drag_active:
		var screen_pos := get_viewport().get_mouse_position()
		if _is_over_trash(screen_pos):
			if _drag_source == "grid":
				_delete_tile_at(_drag_grid_row, _drag_grid_col)
			# Shop-Drag auf Papierkorb: einfach abbrechen (nichts löschen)
			_reset_drag()
			return

	if _drag_active and _drag_source == "shop":
		_drop_shop_drag(global_pos)
	elif _drag_active and _drag_source == "grid":
		_drop_grid_drag(global_pos)
	elif _grid_drag_pending:
		_slow_click_select(_drag_grid_row, _drag_grid_col)
	_reset_drag()


func _slow_right_click(global_pos: Vector2) -> void:
	var local = grid_node.to_local(global_pos)
	if local.x < 0 or local.y < 0 or local.x >= GRID_COLS * TILE_SIZE or local.y >= GRID_ROWS * TILE_SIZE:
		return
	var cell = _world_to_grid(local)
	if not _is_valid_cell(cell):
		return
	var rc = grid[cell.x][cell.y]
	if rc != null and not rc.get("is_start", false):
		_delete_tile_at(cell.x, cell.y)
	elif selected_grid_row >= 0:
		_clear_grid_selection()


# Klick (ohne Ziehen) auf ein platziertes Tile → Auswahl umschalten.
func _slow_click_select(row: int, col: int) -> void:
	if not _is_valid_cell(Vector2i(row, col)):
		return
	var d = grid[row][col]
	if d == null or d.get("is_start", false):
		return
	if selected_grid_row == row and selected_grid_col == col:
		_clear_grid_selection()
	else:
		_select_grid_tile(row, col)


# Slow-Modus: Highlight dem Feld unter der Maus folgen lassen (Hover-Auswahl). Bewusst
# leichtgewichtig – setzt nur die Auswahl, das Highlight und den Status, ohne last_placed
# oder die Bau-Leiste anzufassen (würde sonst bei jeder Mausbewegung neu aufgebaut).
# Auch leere Zellen und das Start-Tile bekommen den gelben Rahmen (rein visuell – Drehen/
# Verschieben/Löschen sind dort ohnehin gesperrt). Nur außerhalb des Grids → Auswahl weg.
func _update_hover_selection(global_pos: Vector2) -> void:
	var row := -1
	var col := -1
	var local := grid_node.to_local(global_pos)
	if local.x >= 0 and local.y >= 0 and local.x < GRID_COLS * TILE_SIZE and local.y < GRID_ROWS * TILE_SIZE:
		var cell := _world_to_grid(local)
		if _is_valid_cell(cell):
			row = cell.x
			col = cell.y
	if row == selected_grid_row and col == selected_grid_col:
		return  # keine Änderung – nichts neu zeichnen
	selected_grid_row = row
	selected_grid_col = col
	if row < 0:
		# Über keinem Feld (außerhalb des Grids) → gar kein Highlight. Im Slow-Modus folgt der
		# Rahmen strikt der Maus, KEIN Rückfall auf das zuletzt platzierte Tile (den nähme sonst
		# _update_grid_highlight vor).
		if _grid_highlight != null:
			_grid_highlight.visible = false
		tile_selector.deselect()
		return
	_update_grid_highlight()
	var d = grid[row][col]
	if d == null:
		tile_selector.set_status("Leer")
	elif d.get("is_start", false):
		tile_selector.set_status("Start-Tile")
	else:
		tile_selector.set_status(_type_display_name(d["type"]))


func _begin_shop_drag(idx: int) -> void:
	_reset_drag()
	# Andere Werkzeug-/Auswahlzustände aufheben, damit nur das Ziehen aktiv ist.
	selected_shop_slot = -1
	selected_grid_row  = -1
	selected_grid_col  = -1
	_update_grid_highlight()
	_update_delete_panel_style()

	_drag_active   = true
	_drag_source   = "shop"
	_drag_shop_idx = idx
	_drag_data     = _shop_drag_data(SHOP_ITEMS[idx])
	_drag_ghost    = _make_ghost(_drag_data)
	grid_node.add_child(_drag_ghost)
	_drag_ghost.position = _ghost_pos_for(get_global_mouse_position())
	tile_selector.set_status("Ziehen…")


func _begin_grid_drag() -> void:
	var d = grid[_drag_grid_row][_drag_grid_col]
	if d == null:
		_grid_drag_pending = false
		return
	_drag_active = true
	_drag_source = "grid"
	selected_shop_slot = -1
	# Originaldaten merken (für Snap-back & Werterhalt); Vorschau-Transform separat – via [R]/[F] änderbar.
	_drag_orig = d.duplicate()
	_drag_data = {
		"type":      String(d.get("type", "")),
		"rotation":  int(d.get("rotation", 0)),
		"direction": int(d.get("direction", 1)),
		"is_dirt":   d.get("is_dirt", false),
	}
	_drag_ghost  = _make_ghost(_drag_data)
	grid_node.add_child(_drag_ghost)
	_drag_ghost.position = _ghost_pos_for(get_global_mouse_position())
	# Original-Node (inkl. Rampen-Partner) während des Ziehens ausblenden.
	_set_drag_source_visible(false)
	tile_selector.set_status("Ziehen…")


func _drop_shop_drag(global_pos: Vector2) -> void:
	var local = grid_node.to_local(global_pos)
	if local.x < 0 or local.y < 0 or local.x >= GRID_COLS * TILE_SIZE or local.y >= GRID_ROWS * TILE_SIZE:
		return   # außerhalb des Grids → abbrechen
	var cell = _world_to_grid(local)
	if not _is_valid_cell(cell):
		return
	# Platzieren über die bestehende Shop-Logik (Preis, Rampe, Überschreiben, Start-Schutz).
	# Das gezogene Teil trägt seine per [R]/[F] geänderte Ausrichtung (_drag_data) mit.
	selected_shop_slot = _drag_shop_idx
	_place_shop_tile(cell.x, cell.y, _drag_data)
	selected_shop_slot = -1
	# Aus dem Shop gezogenes & abgelegtes Tile direkt auswählen (Name im Baumenü +
	# gelbe Markierung), sofern die Platzierung geklappt hat und es kein Start-Feld ist.
	if grid[cell.x][cell.y] != null and not grid[cell.x][cell.y].get("is_start", false):
		_select_grid_tile(cell.x, cell.y)
	_update_build_ui()


func _drop_grid_drag(global_pos: Vector2) -> void:
	var local = grid_node.to_local(global_pos)
	var inside = local.x >= 0 and local.y >= 0 and local.x < GRID_COLS * TILE_SIZE and local.y < GRID_ROWS * TILE_SIZE
	var ok = false
	if inside:
		var cell = _world_to_grid(local)
		if _is_valid_cell(cell):
			ok = _place_dragged_grid_tile(cell)
	if not ok:
		# Snap-back: passt nicht / außerhalb → Original (inkl. ursprünglicher Drehung) zurück.
		_set_drag_source_visible(true)
		_clear_grid_selection()


# Legt das gezogene Grid-Tile mit seiner „in der Hand" geänderten Ausrichtung (_drag_data) ab.
# Gibt false zurück, wenn die Zielposition nicht passt (→ Snap-back).
func _place_dragged_grid_tile(target: Vector2i) -> bool:
	var t = String(_drag_data.get("type", ""))
	if t == "ramp_start" or t == "ramp_end":
		return _drop_grid_ramp(target, int(_drag_data.get("rotation", 0)))
	return _drop_grid_normal(target)


func _drop_grid_normal(target: Vector2i) -> bool:
	var src = Vector2i(_drag_grid_row, _drag_grid_col)
	var dd  = grid[target.x][target.y]
	# Nur auf leeres Feld (oder zurück aufs eigene Feld = reine Drehung) ablegen.
	if not (dd == null or target == src):
		return false
	# Originalwerte (Punkte/Combine/…) erhalten, nur Transform aus _drag_data übernehmen.
	var nd = _drag_orig.duplicate()
	nd.erase("node")
	nd["type"]      = String(_drag_data.get("type", nd.get("type", "")))
	nd["rotation"]  = int(_drag_data.get("rotation", nd.get("rotation", 0)))
	nd["direction"] = int(_drag_data.get("direction", nd.get("direction", 1)))
	_free_tile_node(src.x, src.y)
	_spawn_tile(target.x, target.y, nd)
	last_placed_row = target.x
	last_placed_col = target.y
	_invalidate_track()
	# Verschobenes Tile bleibt ausgewählt (Name im Baumenü + gelbe Markierung).
	_select_grid_tile(target.x, target.y)
	return true


func _drop_grid_ramp(target: Vector2i, rot: int) -> bool:
	var src_s = Vector2i(_drag_grid_row, _drag_grid_col)
	var sdata = grid[src_s.x][src_s.y]
	if sdata == null:
		return false
	var src_e = Vector2i(int(sdata.get("ramp_partner_row", -1)), int(sdata.get("ramp_partner_col", -1)))
	var tgt_e = _ramp_end_pos(target.x, target.y, rot)
	if not (_ac_in_bounds(target) and _ac_in_bounds(tgt_e)):
		return false
	# Start- & End-Feld müssen frei (oder Dreck) sein – die eigenen alten Felder zählen als frei.
	for c in [target, tgt_e]:
		var cd = grid[c.x][c.y]
		var own = (c == src_s or c == src_e)
		if not (cd == null or cd.get("is_dirt", false) or own):
			return false
	# Altes Paar entfernen (inkl. Partner), evtl. Dreck auf den Zielfeldern räumen.
	_free_tile_node(src_s.x, src_s.y)
	_clear_dirt_cell(target.x, target.y)
	_clear_dirt_cell(tgt_e.x, tgt_e.y)
	_spawn_tile(target.x, target.y, {
		"type": "ramp_start", "rotation": rot, "flipped": false,
		"direction": 1, "points": 0.0, "multiplier": 1.0,
		"variant_label": "", "series": "", "combine_level": 0,
		"is_start": false, "is_dirt": false,
		"ramp_partner_row": tgt_e.x, "ramp_partner_col": tgt_e.y,
	})
	_spawn_tile(tgt_e.x, tgt_e.y, {
		"type": "ramp_end", "rotation": rot, "flipped": false,
		"direction": 1, "points": 0.0, "multiplier": 1.0,
		"variant_label": "", "series": "", "combine_level": 0,
		"is_start": false, "is_dirt": false,
		"ramp_partner_row": target.x, "ramp_partner_col": target.y,
	})
	last_placed_row = target.x
	last_placed_col = target.y
	_invalidate_track()
	# Verschobene Rampe bleibt ausgewählt (Name im Baumenü + gelbe Markierung).
	_select_grid_tile(target.x, target.y)
	return true


func _reset_drag() -> void:
	if _drag_ghost != null and is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	# Sicherheit: evtl. ausgeblendete Quell-Tiles wieder zeigen.
	if _drag_source == "grid":
		_set_drag_source_visible(true)
	_drag_ghost        = null
	_drag_data         = {}
	_drag_orig         = {}
	_drag_active       = false
	_drag_source       = ""
	_drag_shop_idx     = -1
	_drag_grid_row     = -1
	_drag_grid_col     = -1
	_grid_drag_pending = false


# Blendet das gezogene Grid-Tile (inkl. Rampen-Partner) aus bzw. wieder ein.
func _set_drag_source_visible(vis: bool) -> void:
	if not _is_valid_cell(Vector2i(_drag_grid_row, _drag_grid_col)):
		return
	var d = grid[_drag_grid_row][_drag_grid_col]
	if d == null:
		return
	if d.get("node") != null and is_instance_valid(d["node"]):
		d["node"].visible = vis
	if d.get("type", "") in ["ramp_start", "ramp_end"]:
		var pr = d.get("ramp_partner_row", -1)
		var pc = d.get("ramp_partner_col", -1)
		if pr >= 0 and pc >= 0 and _is_valid_cell(Vector2i(pr, pc)):
			var pd = grid[pr][pc]
			if pd != null and pd.get("node") != null and is_instance_valid(pd["node"]):
				pd["node"].visible = vis


# Minimal-Datensatz für die Ziehen-Vorschau eines Shop-Items.
func _shop_drag_data(item: Dictionary) -> Dictionary:
	if item["tier"] == "ramp":
		return {"type": "ramp_start", "rotation": ramp_preview_rot, "direction": 1, "is_dirt": false}
	return {
		"type":      item["type"],
		"rotation":  0,
		"direction": -1 if item["type"] == "curve_alt" else 1,
		"is_dirt":   item["tier"] == "dirt",
	}


# Halbtransparente Ziehen-Vorschau. Der Wurzel-Node hält die Umrisse aller belegten
# Felder (Footprint) plus die einzelnen Tile-Grafiken – so lassen sich auch mehrfeldrige
# Teile (Rampe = 3×1, später z. B. größere Strecken-Stücke) korrekt darstellen.
func _make_ghost(data: Dictionary) -> Node2D:
	var root = Node2D.new()
	root.z_index = 50
	# Footprint-Umrisse (zeigt die gesamte belegte Struktur, auch >1 Feld)
	for cell_off in _ghost_footprint_cells(data):
		root.add_child(_make_footprint_outline(cell_off))
	# Tile-Grafiken an ihren relativen Positionen
	for part in _ghost_parts(data):
		var n = _make_tile_visual(part["data"])
		n.position = part["offset"]
		root.add_child(n)
	var m = root.modulate
	m.a = 0.6
	root.modulate = m   # propagiert auf alle Kinder
	return root


# Einzelne Tile-Grafik (ohne Badges/Labels) für die Vorschau.
func _make_tile_visual(data: Dictionary) -> Node2D:
	var node: Node2D
	if data.get("is_dirt", false):
		node = _create_dirt_node(data)
	elif data.get("type", "") in ["ramp_start", "ramp_end"]:
		node = _create_ramp_node(data)
	else:
		var scene_path: String
		match data.get("type", ""):
			"straight":  scene_path = Paths.SCENE_TILE_STRAIGHT_2D
			"curve_alt": scene_path = Paths.SCENE_TILE_CURVE_ALT_2D
			_:           scene_path = Paths.SCENE_TILE_CURVE_2D
		var scene = load(scene_path)
		node = scene.instantiate() if scene != null else Node2D.new()
		if "direction" in node:
			node.direction = data.get("direction", 1)
			node.queue_redraw()
	node.rotation_degrees = data.get("rotation", 0)
	return node


# Tile-Teile einer Struktur als {offset (px, zellzentriert), data}. Rampe = Start + Ende.
func _ghost_parts(data: Dictionary) -> Array:
	var t = String(data.get("type", ""))
	if t == "ramp_start" or t == "ramp_end":
		var rot = int(data.get("rotation", 0))
		return [
			{"offset": Vector2.ZERO,             "data": {"type": "ramp_start", "rotation": rot, "direction": 1}},
			{"offset": _cell_offset_px(_ramp_end_pos(0, 0, rot)), "data": {"type": "ramp_end", "rotation": rot, "direction": 1}},
		]
	return [{"offset": Vector2.ZERO, "data": data}]


# Belegte Felder einer Struktur als relative Zell-Deltas. Rampe = Start, Mittelfeld, Ende.
func _ghost_footprint_cells(data: Dictionary) -> Array:
	var t = String(data.get("type", ""))
	if t == "ramp_start" or t == "ramp_end":
		var e = _ramp_end_pos(0, 0, int(data.get("rotation", 0)))
		return [Vector2i(0, 0), Vector2i(e.x / 2, e.y / 2), e]
	return [Vector2i(0, 0)]


# Zell-Delta (row,col) → Pixel-Versatz relativ zur Start-Zelle (zellzentriert).
func _cell_offset_px(cell: Vector2i) -> Vector2:
	return Vector2(cell.y * TILE_SIZE, cell.x * TILE_SIZE)


# Dünner Rahmen um ein Footprint-Feld (Stil wie das Grid-Highlight), zellzentriert.
func _make_footprint_outline(cell: Vector2i) -> Node2D:
	var node = Node2D.new()
	var tl   = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0) + _cell_offset_px(cell)
	var bw   = 2
	var col  = Color(1.0, 0.85, 0.0, 0.7)
	for i in range(4):
		var r = ColorRect.new()
		r.color = col
		match i:
			0: r.position = tl;                                 r.size = Vector2(TILE_SIZE, bw)
			1: r.position = tl + Vector2(0, TILE_SIZE - bw);    r.size = Vector2(TILE_SIZE, bw)
			2: r.position = tl;                                 r.size = Vector2(bw, TILE_SIZE)
			3: r.position = tl + Vector2(TILE_SIZE - bw, 0);    r.size = Vector2(bw, TILE_SIZE)
		node.add_child(r)
	return node


# Cursor-Position (global) in Grid-lokale Koordinaten – Tile-Nodes sitzen zellzentriert.
func _ghost_pos_for(global_pos: Vector2) -> Vector2:
	return grid_node.to_local(global_pos)


# [R] beim Ziehen (Shop oder Grid): gezogenes Teil „in der Hand" um 90° drehen.
func _drag_rotate() -> void:
	_drag_data["rotation"] = (int(_drag_data.get("rotation", 0)) + 90) % 360
	if _drag_shop_idx >= 0 and SHOP_ITEMS[_drag_shop_idx]["tier"] == "ramp":
		ramp_preview_rot = _drag_data["rotation"]   # Rampe platziert über ramp_preview_rot
		_update_build_ui()
	_rebuild_drag_ghost()


# [F] beim Ziehen (Shop oder Grid): gezogenes Teil wenden (Kurve tauschen / Gerade umkehren / Rampe).
func _drag_flip() -> void:
	var t = String(_drag_data.get("type", ""))
	if t == "curve" or t == "curve_alt":
		var nt = "curve_alt" if t == "curve" else "curve"
		_drag_data["type"]      = nt
		_drag_data["direction"] = -1 if nt == "curve_alt" else 1
	elif t == "straight":
		_drag_data["direction"] = -1 if int(_drag_data.get("direction", 1)) == 1 else 1
	elif t == "ramp_start":
		# Auffahrseite wechseln ≈ um 180° drehen (Fahrtrichtung kehrt sich um).
		_drag_data["rotation"] = (int(_drag_data.get("rotation", 0)) + 180) % 360
		if _drag_shop_idx >= 0:
			ramp_preview_rot = _drag_data["rotation"]
			_update_build_ui()
	_rebuild_drag_ghost()


# Erzeugt die Ghost-Vorschau aus _drag_data neu (an gleicher Cursor-Position).
func _rebuild_drag_ghost() -> void:
	var pos = _ghost_pos_for(get_global_mouse_position())
	if _drag_ghost != null and is_instance_valid(_drag_ghost):
		pos = _drag_ghost.position
		_drag_ghost.queue_free()
	_drag_ghost = _make_ghost(_drag_data)
	grid_node.add_child(_drag_ghost)
	_drag_ghost.position = pos


# Nach einem Kauf im Schnell-Modus: Werkzeug abwählen und platziertes Tile markieren.
# Mit gehaltener Shift-Taste bleibt das Shop-Werkzeug aktiv → mehrere Teile am Stück platzieren.
func _after_quick_place(row: int, col: int) -> void:
	if placement_mode != "quick":
		return
	if Input.is_key_pressed(KEY_SHIFT):
		return
	selected_shop_slot = -1
	_select_grid_tile(row, col)
	_update_build_ui()


# ── Platzierungs-Modus ───────────────────────────────────────────────────────────

func _load_placement_mode() -> String:
	var cfg = ConfigFile.new()
	cfg.load(Paths.SETTINGS_FILE)
	return String(cfg.get_value("options", "placement_mode", "slow"))


# Wird von PauseMenu beim Umschalten in den Einstellungen aufgerufen (Live-Wechsel).
func set_placement_mode(mode: String) -> void:
	placement_mode = mode
	_reset_drag()
	selected_shop_slot = -1
	selected_grid_row  = -1
	selected_grid_col  = -1
	_update_build_ui()
	_update_grid_highlight()
	tile_selector.deselect()
	_update_hint_label()
	_update_trash_visibility()


func _update_hint_label() -> void:
	if placement_mode == "slow":
		tile_selector.set_hint("[R] Drehen · [F] Wenden\nZiehen & Ablegen")
	else:
		tile_selector.set_hint("[R] Drehen · [F] Wenden · [D] Löschen\nKlick-Modus")


func _handle_grid_left_click(row: int, col: int) -> void:
	var cell_data = grid[row][col]
	var is_start  = (cell_data != null and cell_data.get("is_start", false))

	# Shop-Werkzeug aktiv
	if selected_shop_slot >= 0:
		if is_start:
			return
		# Klick auf das zuletzt platzierte Tile → auswählen statt überschreiben (drehen/wenden)
		if cell_data != null and row == last_placed_row and col == last_placed_col:
			_select_grid_tile(row, col)
		else:
			_place_shop_tile(row, col)
		return

	if is_start:
		return

	# Rampen-Tiles (Altstände): zum ramp_start-Partner wechseln für [R]/[F]
	if cell_data != null and cell_data.get("type", "") in ["ramp_start", "ramp_end"]:
		var target_r = row; var target_c = col
		if cell_data.get("type", "") == "ramp_end":
			target_r = cell_data.get("ramp_partner_row", row)
			target_c = cell_data.get("ramp_partner_col", col)
		if selected_grid_row == target_r and selected_grid_col == target_c:
			_clear_grid_selection()
		else:
			selected_grid_row = target_r; selected_grid_col = target_c
			_update_grid_highlight()
			tile_selector.set_status("Rampe")
		return

	# Grid-Tile bereits ausgewählt → verschieben (leere Zelle) bzw. Auswahl wechseln
	if selected_grid_row >= 0:
		if cell_data == null:
			_move_selected_tile_to(row, col)
		elif selected_grid_row == row and selected_grid_col == col:
			_clear_grid_selection()
		else:
			_select_grid_tile(row, col)
		return

	# Nichts ausgewählt: Tile unter dem Cursor auswählen
	if cell_data != null:
		_select_grid_tile(row, col)


func _select_grid_tile(row: int, col: int) -> void:
	selected_shop_slot = -1
	_update_build_ui()
	_update_delete_panel_style()
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
		_invalidate_track()
		# Verschobene Rampe bleibt ausgewählt (Name im Baumenü + gelbe Markierung).
		_select_grid_tile(new_row, new_col)
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
		"is_dirt":       data.get("is_dirt", false),
	}
	data["node"].queue_free()
	grid[old_row][old_col] = null

	_spawn_tile(new_row, new_col, move_data)
	last_placed_row   = new_row
	last_placed_col   = new_col
	_invalidate_track()
	# Verschobenes Tile bleibt ausgewählt (Name im Baumenü + gelbe Markierung).
	_select_grid_tile(new_row, new_col)


# xform (optional): überschreibt Typ/Rotation/Richtung – z. B. das aus dem Shop
# gezogene Teil trägt seine per [R]/[F] geänderte Ausrichtung mit (Slow-Modus).
func _place_shop_tile(row: int, col: int, xform: Dictionary = {}) -> void:
	var item = SHOP_ITEMS[selected_shop_slot]
	if not Economy.is_tile_unlocked(item["key"]):
		return   # Sicherheitshalber: gesperrte Tiles nicht platzieren
	# Rampe ist ein Sonderfall (2 Felder, eigenes Platzieren)
	if item["tier"] == "ramp":
		_place_ramp(row, col)
		return
	# Preis NUR für Default-Tiles; Dreck ist kostenlos. Preis vor dem Setzen prüfen.
	var price = _tile_price(item)
	if item["tier"] == "default":
		if not Economy.spend(price):
			_flash_currency()
			return
	# Vorhandenes Tile (außer Start) überschreiben → zählt als Löschvorgang (mit Rückerstattung)
	if grid[row][col] != null:
		if grid[row][col].get("is_start", false):
			if item["tier"] == "default":
				Economy.add(price)   # Ausgabe rückgängig: auf Start kann nicht gebaut werden
			return
		var refund = _tile_refund_for(grid[row][col])
		if refund > 0:
			Economy.add(refund)
		_free_tile_node(row, col)
	var def_dir = -1 if item["type"] == "curve_alt" else 1
	_spawn_tile(row, col, {
		"type":          String(xform.get("type", item["type"])),
		"rotation":      int(xform.get("rotation", 0)),
		"flipped":       false,
		"direction":     int(xform.get("direction", def_dir)),
		"points":        0.0,
		"multiplier":    1.0,
		"variant_label": "",
		"series":        "",
		"combine_level": 0,
		"is_start":      false,
		"is_dirt":       item["tier"] == "dirt",
	})
	last_placed_row = row
	last_placed_col = col
	_update_currency_label()
	_update_build_ui()
	_update_grid_highlight()
	_invalidate_track()
	# Schnell-Modus: Werkzeug abwählen & platziertes Tile markieren (Shift = mehrere platzieren).
	_after_quick_place(row, col)


# Entfernt nur die Node + Grid-Eintrag einer Zelle (inkl. Rampen-Partner), ohne UI-Update.
func _free_tile_node(row: int, col: int) -> void:
	var d = grid[row][col]
	if d == null:
		return
	var rtype = d.get("type", "")
	if rtype == "ramp_start" or rtype == "ramp_end":
		var pr = d.get("ramp_partner_row", -1)
		var pc = d.get("ramp_partner_col", -1)
		if pr >= 0 and pc >= 0 and grid[pr][pc] != null:
			grid[pr][pc]["node"].queue_free()
			grid[pr][pc] = null
	d["node"].queue_free()
	grid[row][col] = null


func _remove_tile(row: int, col: int) -> void:
	if grid[row][col] != null:
		if grid[row][col].get("is_start", false):
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


# Feld für eine Rampe nutzbar, wenn leer oder ein Dreck-Tile.
func _ramp_cell_free(row: int, col: int) -> bool:
	var d = grid[row][col]
	return d == null or d.get("is_dirt", false)


# Entfernt ein Dreck-Tile an dieser Stelle (falls vorhanden).
func _clear_dirt_cell(row: int, col: int) -> void:
	var d = grid[row][col]
	if d != null and d.get("is_dirt", false):
		d["node"].queue_free()
		grid[row][col] = null


# Platziert ein Rampen-Paar (Start + Ende 2 Felder entfernt). Das übersprungene
# Mittelfeld bleibt frei für eine kreuzende Strecke (× JUMP_MULT Ertrag dort).
# Werkzeug bleibt ausgewählt; Preis idle-skalierend wie Default-Tiles.
func _place_ramp(row: int, col: int) -> void:
	var item  = SHOP_ITEMS[selected_shop_slot]
	var price = _tile_price(item)
	var rot   = ramp_preview_rot
	for _attempt in range(4):
		var end = _ramp_end_pos(row, col, rot)
		if _ac_in_bounds(end) and _ramp_cell_free(row, col) and _ramp_cell_free(end.x, end.y):
			if not Economy.spend(price):
				_flash_currency()
				return
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
			last_placed_row = row
			last_placed_col = col
			_update_currency_label()
			_update_build_ui()
			_update_grid_highlight()
			_invalidate_track()
			_after_quick_place(row, col)
			return
		rot = (rot + 90) % 360
	tile_selector.set_status("Kein Platz für Rampe (2 freie Felder in einer Richtung nötig)")


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
			_invalidate_track()
			tile_selector.set_status("Rampe")
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
	var el = node.get_node_or_null("EarnLabel")
	if el is Label:
		el.rotation_degrees = -rot_deg
		el.position = Vector2(-TILE_SIZE / 2 + 2, -TILE_SIZE / 2 + 2).rotated(-r)


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
			"is_dirt":       data.get("is_dirt", false),
		}
		data["node"].queue_free()
		grid[row][col] = null
		_spawn_tile(row, col, new_data)
		if selected_grid_row >= 0:
			tile_selector.set_status(_type_display_name(new_type))
		_invalidate_track()
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
			"is_dirt":       data.get("is_dirt", false),
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
		# Auffahrseite wechseln: Start/Ende tauschen UND beide um 180° drehen, damit die
		# Rampen weiter zur Sprung-Lücke hin geneigt bleiben (nur Fahrtrichtung kehrt sich um).
		var frot = (rot + 180) % 360
		grid[s_row][s_col]["node"].queue_free()
		grid[s_row][s_col] = null
		if grid[e_row][e_col] != null:
			grid[e_row][e_col]["node"].queue_free()
			grid[e_row][e_col] = null
		_spawn_tile(e_row, e_col, {
			"type": "ramp_start", "rotation": frot, "flipped": false,
			"direction": 1, "points": 0.0, "multiplier": 1.0,
			"variant_label": "", "series": "", "combine_level": 0,
			"is_start": false, "is_dirt": false,
			"ramp_partner_row": s_row, "ramp_partner_col": s_col,
		})
		_spawn_tile(s_row, s_col, {
			"type": "ramp_end", "rotation": frot, "flipped": false,
			"direction": 1, "points": 0.0, "multiplier": 1.0,
			"variant_label": "", "series": "", "combine_level": 0,
			"is_start": false, "is_dirt": false,
			"ramp_partner_row": e_row, "ramp_partner_col": e_col,
		})
		selected_grid_row = e_row; selected_grid_col = e_col
		_update_grid_highlight()
		_invalidate_track()
		tile_selector.set_status("Rampe")


# ── Hilfsfunktionen ────────────────────────────────────────────────────────────

func _type_display_name(typ: String) -> String:
	match typ:
		"straight":   return "Gerade"
		"curve":      return "Kurve"
		"curve_alt":  return "Kurve 2"
		"ramp_start": return "Rampe"
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
	GlobalModal.open()


# Baut das Grid in der aktuellen Economy-Größe neu auf, falls sie sich geändert hat.
# Das Grid wächst nur (Origin oben-links bleibt fix), daher bleiben platzierte
# Tiles an ihrer Position erhalten.
func _rebuild_grid_for_size() -> void:
	var new_rows = Economy.get_grid_rows()
	var new_cols = Economy.get_grid_cols()
	if new_rows == GRID_ROWS and new_cols == GRID_COLS:
		return

	var saved = get_grid_state()

	for c in grid_node.get_children():
		c.queue_free()

	GRID_ROWS = new_rows
	GRID_COLS = new_cols
	_init_grid()
	_draw_grid_background()
	_setup_grid_highlight()
	_place_start_tile()
	_restore_grid(saved)
	_update_camera_limits()

	selected_grid_row  = -1
	selected_grid_col  = -1
	selected_shop_slot = -1
	_update_grid_highlight()
	_update_build_ui()
	tile_selector.deselect()
	_invalidate_track()


func _on_pruefen_pressed() -> void:
	_track_valid = _is_track_valid()
	if _track_valid:
		tile_selector.set_status("✓ Strecke gültig")
	else:
		tile_selector.set_status("Keine vollständige Runde möglich")
	_refresh_run_bar()


func _on_fahren_pressed() -> void:
	if Economy.is_run_active(_current_track_idx):
		# Runde läuft bereits → einfach zur 3D-Ansicht wechseln
		_switch_to_3d_view()
		return
	if not _is_track_valid():
		tile_selector.set_status("Keine vollständige Runde möglich")
		return
	_persist_track_for_current()
	Economy.start_run(_current_track_idx)
	Engine.set_meta("pending_grid_state", _build_drive_state())
	Engine.set_meta("active_track_idx",   _current_track_idx)
	# KEIN "resuming_run" Meta → World3D weiß: frischer Start
	GameHUD.set_track_3d(_current_track_idx, true)
	GameHUD.set_build_active(false)
	var world_scene = load(Paths.SCENE_WORLD3D)
	if world_scene:
		get_tree().change_scene_to_packed(world_scene)


func _switch_to_3d_view() -> void:
	# Ansicht zu laufender Runde wechseln (kein neuer Run)
	_persist_track_for_current()
	Engine.set_meta("active_track_idx", _current_track_idx)
	Engine.set_meta("resuming_run",     true)
	# Grid-State aus Economy holen (für Track-Generierung)
	var track_grid := Economy.get_track_grid(_current_track_idx)
	if track_grid.size() > 0:
		Engine.set_meta("pending_grid_state", track_grid)
	else:
		Engine.set_meta("pending_grid_state", get_grid_state())
	GameHUD.set_track_3d(_current_track_idx, true)
	GameHUD.set_build_active(false)
	var world_scene = load(Paths.SCENE_WORLD3D)
	if world_scene:
		get_tree().change_scene_to_packed(world_scene)


# Kopie des Grid-States, in der Tiles auf einem Bonusfeld bonus_points/bonus_mult tragen
# und Tiles auf einem Sprung-Mittelfeld einen jump_mult (× JUMP_MULT) bekommen.
func _build_drive_state() -> Array:
	var state = get_grid_state()
	for r in range(GRID_ROWS):
		for c in range(GRID_COLS):
			if bonus_grid[r][c] != null and typeof(state[r][c]) == TYPE_DICTIONARY:
				state[r][c]["bonus_points"] = bonus_grid[r][c]["points"]
				state[r][c]["bonus_mult"]   = bonus_grid[r][c]["mult"]
	# Kreuzungs-Tiles unter einer Rampe: doppelter Ertrag
	for cell in _ramp_jump_cells():
		if typeof(state[cell.x][cell.y]) == TYPE_DICTIONARY:
			state[cell.x][cell.y]["jump_mult"] = JUMP_MULT
	return state


# ── Bonusfelder ─────────────────────────────────────────────────────────────────

# Kurzkennung des Bonus-Upgrade-Zustands (zum Erkennen von Änderungen im Menü).
func _bonus_signature() -> String:
	return "%d_%d_%d" % [
		Economy.get_bonus_count("plus5"),
		Economy.get_bonus_count("plus10"),
		Economy.get_bonus_count("mult15"),
	]


# Würfelt die Bonusfelder neu – bevorzugt auf bebaute Fahrkacheln, sonst auf leere Zellen,
# ohne sich gegenseitig zu überschreiben.
func _roll_bonus_fields() -> void:
	for n in _bonus_marker_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_bonus_marker_nodes.clear()
	for r in range(GRID_ROWS):
		for c in range(GRID_COLS):
			bonus_grid[r][c] = null

	# Plan: jede Bonus-Sorte so oft wie ihr Upgrade-Level (max. 3 je Sorte).
	var to_place = Economy.get_bonus_field_plan()
	if to_place.is_empty():
		return

	# Kandidaten: Bonusfelder wirken nur auf überfahrene Tiles (siehe _build_drive_state +
	# CarController), deshalb BEVORZUGT bebaute Fahrkacheln. Solange ein bebautes Tile (außer
	# Start) noch frei ist, landet der Bonus dort; erst danach dienen leere Zellen als Reserve.
	# Innerhalb jeder Gruppe wird gewürfelt → weiterhin zufällige Position.
	var built: Array = []
	var empty: Array = []
	for r in range(GRID_ROWS):
		for c in range(GRID_COLS):
			if grid[r][c] == null:
				empty.append(Vector2i(r, c))
			elif not grid[r][c].get("is_start", false):
				built.append(Vector2i(r, c))
	built.shuffle()
	empty.shuffle()
	var cells: Array = built + empty

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
		# Kurven sind in BEIDE Richtungen befahrbar (gleiche Bogenform); die Fahrtrichtung ergibt
		# sich im 3D-Lauf automatisch aus dem Streckenfluss. Daher KEINE Richtungs-Ablehnung mehr –
		# eine geschlossene Runde genügt.
		row = nxt.x; col = nxt.y; exit_dir = nxt_exit
	return false


func _invalidate_track() -> void:
	_track_valid = _is_track_valid()
	# Ist ein Tile markiert, dessen Namen im Baumenü beibehalten (z. B. nach [R]/[F]),
	# sonst den Status leeren.
	if selected_grid_row >= 0 and selected_grid_col >= 0 \
			and grid[selected_grid_row][selected_grid_col] != null:
		tile_selector.set_status(_type_display_name(grid[selected_grid_row][selected_grid_col]["type"]))
	else:
		tile_selector.set_status("")
	_refresh_run_bar()
	_refresh_jump_markers()
	_persist_track_for_current()


# ── Sprung-Felder (Rampen-Kreuzungen) ───────────────────────────────────────────

# Mittelfelder aller Rampen (das übersprungene Feld zwischen ramp_start und ramp_end).
func _ramp_jump_cells() -> Array:
	var cells: Array = []
	for r in range(GRID_ROWS):
		for c in range(GRID_COLS):
			var d = grid[r][c]
			if d != null and d.get("type", "") == "ramp_start":
				var pr = d.get("ramp_partner_row", -1)
				var pc = d.get("ramp_partner_col", -1)
				if pr >= 0 and pc >= 0:
					cells.append(Vector2i((r + pr) / 2, (c + pc) / 2))
	return cells


# Zeichnet ×2-Marker auf alle Sprung-Mittelfelder neu.
func _refresh_jump_markers() -> void:
	for n in _jump_marker_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_jump_marker_nodes.clear()
	for cell in _ramp_jump_cells():
		var marker = _make_jump_marker()
		marker.position = _grid_to_world(cell.x, cell.y)
		marker.z_index  = 5
		grid_node.add_child(marker)
		_jump_marker_nodes.append(marker)


func _make_jump_marker() -> Node2D:
	# Nur ein "×2"-Hinweis im Sprung-Mittelfeld – kein Rahmen (überlagert keine Tiles).
	var node = Node2D.new()
	var lbl = Label.new()
	lbl.text = "×2"
	lbl.position = Vector2(0, 0)
	lbl.size = Vector2(TILE_SIZE, TILE_SIZE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.12))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	node.add_child(lbl)
	return node


# Speichert die aktuelle Strecke dauerhaft (inkl. Dreck-Tiles – jetzt vollwertige Tiles).
func _persist_track() -> void:
	_persist_track_for_current()


# ── Routing-Hilfsfunktionen (für Streckenvalidierung) ───────────────────────────

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
	# Eingang muss auch passen: das Tile braucht eine Verbindung auf der entry-Seite.
	# (Sonst würde z. B. eine waagerechte Gerade ein Auto von oben "annehmen".)
	if not conns.get(entry, false):
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


func _on_run_ended_background(track_idx: int, _earned: int) -> void:
	# Kein Popup im 2D-Bauplan – das Lauf-Ende-Popup zeigt nur die 3D-Ansicht.
	# Hier nur die Bau-Leiste aktualisieren, damit ein neuer Lauf gestartet werden kann.
	if track_idx == _current_track_idx:
		_track_valid = _is_track_valid()
		_refresh_run_bar()
		# Bonusfelder nach jeder Runde neu würfeln (weiterhin zufällig, bebaute Tiles bevorzugt).
		_roll_bonus_fields()


# ── TileSelector-Shim (ersetzt die entfernte Sidebar) ─────────────────────────

class _TileSelectorShim:
	var _status: Label  = null
	var _hint:   Label  = null
	var _fahren: Button = null
	var _main:   Node   = null

	func set_status(text: String) -> void:
		if _status != null and is_instance_valid(_status):
			_status.text = text

	func deselect() -> void:
		if _status != null and is_instance_valid(_status):
			_status.text = ""

	func set_hint(text: String) -> void:
		if _hint != null and is_instance_valid(_hint):
			_hint.text = text

	func set_fahren_enabled(enabled: bool) -> void:
		# Run-Bar-Button aktualisieren (der echte Fahren-Button)
		if _main != null:
			_main._track_valid = enabled
			_main._refresh_run_bar()
