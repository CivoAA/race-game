extends CanvasLayer
## Persistente obere Leiste: Track-Tabs, Währung, 2D/3D-Toggle, Baumodus, Shop.
## Autoload "GameHUD" (layer 20, immer sichtbar).

const TRACK_COUNT  = 3
const BAR_H        = 50   # Design-Wert für 540p (Basishöhe)

# Discord-artige Graupalette (Grau-Abstufungen + Blurple-Akzent). Farbe nur für „Standouts"
# (Akzente, Zahlen, Geld in Gold). DUPLIZIERT in GameHUD/Main/GlobalModal/MainMenu/PauseMenu/
# TileSelector – bei Änderungen alle synchron halten.
const C_BG         := Color(0.118, 0.122, 0.133)   # #1e1f22 (dunkelste Fläche)
const C_SURFACE    := Color(0.169, 0.176, 0.192)   # #2b2d31
const C_SURFACE_HI := Color(0.220, 0.227, 0.251)   # #383a40
const C_ACCENT     := Color(0.345, 0.396, 0.949)   # #5865f2 (Blurple – Akzent/aktiv)
const C_ACCENT_MU  := Color(0.290, 0.310, 0.490)   # gedämpftes Blurple
const C_ACCENT_RD  := Color(0.929, 0.259, 0.271)   # #ed4245 (Signal-Rot)
const C_TEXT       := Color(0.859, 0.871, 0.882)   # #dbdee1
const C_TEXT_DIM   := Color(0.580, 0.608, 0.643)   # #949ba4
const C_LINE       := Color(0.247, 0.255, 0.278)   # #3f4147
const C_RUN_ON     := Color(0.180, 0.690, 0.400)   # Discord-Grün (läuft)
const C_RUN_OFF    := Color(0.350, 0.360, 0.400)   # neutrales Grau (aus)

# Design-Konstanten (für 540p ausgelegt – zur Laufzeit mit RUI.vw()/vh() kombiniert)
const R_PAD   = 8
const BTN_GAP = 4
const BTN_H   = 34
const TAB_W   = 108
const TAB_H   = 42
const TAB_GAP = 4
const TAB_X0  = 8

var _active_tab:   int  = 0
var _build_active: bool = false
var _is_3d_view:   bool = false
# Ansicht je Strecke: true = 3D-Fahrt, false = 2D-Bauplan. Bleibt über Szenenwechsel
# erhalten (GameHUD ist Autoload), damit Strecken gleichzeitig in verschiedenen Ansichten
# sein können. _is_3d_view spiegelt immer den Modus der gerade gezeigten Strecke (_active_tab).
var _track_view_3d: Array = []

# Alle dynamisch erzeugten Bar/Nav-Nodes liegen unter diesem Root-Control.
# Wird bei einem Layout-Wechsel (Portrait ↔ Landscape) komplett neu gebaut.
var _ui_root: Control = null

var _tab_btns:     Array[Button]    = []
var _run_dots:     Array[Panel]         = []
var _run_dot_sbs:  Array[StyleBoxFlat]  = []   # je Punkt eigene Stylebox (zum Umfärben)
var _currency_lbl: Label            = null
var _prestige_lbl: Label            = null   # ⭐-Punkte-Badge (erst ab dem ersten Prestige)
var _trophy_lbl:   Label            = null   # 🏆-Trophäen-Badge (erst ab dem ersten Erfolg)
var _money_pill_cx: float           = 0.0    # Mittenpunkt der Geld-Pille (für das „+N 💰"-Popup darunter)
var _ach_toast:    Control          = null   # aktuelles Erfolgs-Popup unten links (nur eins gleichzeitig)
var _timer_lbl:    Label            = null   # Renn-Timer (nur in der 3D-Fahrt sichtbar)
var _timer_box:    Panel            = null   # Pille hinter dem Timer-Label
var _view_2d_btn:  Button           = null
var _view_3d_btn:  Button           = null
var _shop_btn:     Button           = null
var _endless_btn:  Button           = null
var _debug_btn:    Button           = null   # „+1B ⭐"-Cheat-Button
var _cog_btn:      Button           = null   # Einstellungen-Zahnrad (öffnet das Pause-Menü)

signal tab_changed(idx: int)
signal build_mode_toggled(active: bool)
signal view_changed_to_3d()
signal view_changed_to_2d()
signal shop_requested()


func _ready() -> void:
	layer = 20
	# ALWAYS: die Seitenleiste muss auch dann bedienbar bleiben, wenn das Spiel pausiert
	# ist (Einstellungen pausieren), damit man von dort weiter navigieren kann.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_track_view_3d.resize(TRACK_COUNT)
	_track_view_3d.fill(false)
	_build_ui()
	# Runden-Gutschrift (Auto über die Startlinie) – auch im 2D-Hintergrund den "+X"-Effekt zeigen.
	Economy.lap_credited.connect(_on_lap_credited)
	# Prestige kann Strecken freischalten UND das ⭐-Badge erstmals erscheinen lassen → Leiste neu bauen.
	Economy.prestige_changed.connect(_build_ui)
	# Erfolg freigeschaltet → 🏆-Badge ggf. erstmals einblenden + Erfolgs-Popup unten links zeigen.
	Economy.achievement_unlocked.connect(_on_achievement_unlocked)
	# Profilwechsel → komplette Leiste neu bauen, damit Strecken-Tabs UND die Nav-Sperren
	# (Prestige/Werkstatt: Schloss vs. Stern) den Zustand des NEUEN Profils widerspiegeln.
	Economy.slot_changed.connect(func(_s): _build_ui())
	# Ein Tab (Prestige/Werkstatt) wurde freigeschaltet → Nav neu bauen, damit das Schloss verschwindet.
	Economy.tab_unlock_changed.connect(func(): _build_ui())
	# Cheat-Modus-Einstellung blendet die Cheat-Buttons (∞ und +1B ⭐) ein/aus. Neu aufbauen, damit
	# der Renn-Timer korrekt rechts neben der Werte-Reihe geklemmt wird (Cheat-Breite ein/aus).
	Economy.cheat_mode_changed.connect(_build_ui)
	# Bei Layout-Wechsel (Portrait ↔ Landscape) oder Viewport-Resize alles neu aufbauen.
	RUI.layout_changed.connect(_on_layout_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_layout_changed(_layout) -> void:
	_build_ui()


func _on_viewport_resized() -> void:
	# Nur reagieren wenn kein Layout-Wechsel stattfand (der wird von RUI.layout_changed abgedeckt).
	# Dennoch neu bauen damit bar/sidebar die korrekte Breite/Position bekommen.
	_build_ui()


## Baut alle dynamischen Bar- und Nav-Nodes neu.
## Löscht dazu den alten _ui_root vollständig.
func _build_ui() -> void:
	# Referenzen zurücksetzen (werden in _build_bar / _build_side_menu / _build_bottom_nav neu gesetzt)
	_tab_btns.clear()
	_run_dots.clear()
	_run_dot_sbs.clear()
	_currency_lbl = null
	_prestige_lbl = null
	_trophy_lbl   = null
	_timer_lbl    = null
	_timer_box    = null
	_endless_btn   = null
	_debug_btn     = null
	_nav_btns.clear()
	_pause_nav_btn = null

	if _ui_root != null and is_instance_valid(_ui_root):
		_ui_root.queue_free()

	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_root)

	_build_bar()
	if RUI.is_portrait():
		_build_bottom_nav()
	else:
		_build_side_menu()


func _on_lap_credited(_track_idx: int, amount: int) -> void:
	gain_currency(amount)


func _build_bar() -> void:
	var vw := RUI.vw()

	# Hintergrund – füllt die volle virtuelle Breite (wichtig für Ultrawide)
	var bg := ColorRect.new()
	bg.size  = Vector2(vw, BAR_H)
	bg.color = C_BG
	_ui_root.add_child(bg)

	var line := ColorRect.new()
	line.position = Vector2(0, BAR_H - 1)
	line.size     = Vector2(vw, 1)
	line.color    = C_LINE
	_ui_root.add_child(line)

	# Tabs (links)
	var tab_y := (BAR_H - TAB_H) / 2.0
	for i in TRACK_COUNT:
		var btn := Button.new()
		btn.position = Vector2(TAB_X0 + i * (TAB_W + TAB_GAP), tab_y)
		btn.size     = Vector2(TAB_W, TAB_H)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Tab-Text wird in _refresh_tabs selbst per tr() übersetzt → Auto-Übersetzung aus.
		btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_style_tab_btn(btn, i == 0)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		_ui_root.add_child(btn)
		_tab_btns.append(btn)

		# Run-Indikator: Kreis mit dunklem Ring
		const DOT_SZ = 10
		var dot := Panel.new()
		dot.size     = Vector2(DOT_SZ, DOT_SZ)
		dot.position = btn.position + Vector2(TAB_W - DOT_SZ - 10, (TAB_H - DOT_SZ) / 2.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot_sb := StyleBoxFlat.new()
		dot_sb.bg_color = C_RUN_OFF
		dot_sb.set_corner_radius_all(DOT_SZ / 2)
		dot_sb.set_border_width_all(2)
		dot_sb.border_color = C_BG
		dot.add_theme_stylebox_override("panel", dot_sb)
		_ui_root.add_child(dot)
		_run_dots.append(dot)
		_run_dot_sbs.append(dot_sb)

	# ── Geld + Statuswerte: links-gepackte Reihe direkt rechts neben „Strecke 3" ──
	# Reihenfolge: 💰 Geld · ⭐ Prestige · 🏆 Trophäen. Prestige/Trophäen erscheinen erst, sobald
	# man sie zum ersten Mal erreicht hat, und rücken lückenlos auf (nie ein Loch dazwischen).
	const PILL_H   = 32
	const MONEY_W  = 116
	const STAT_W   = 92    # Prestige-/Trophäen-Badge
	const DEBUG_W  = 46    # „+1B ⭐"-Cheat-Badge
	const PILL_GAP = 6
	var pill_y     := (BAR_H - PILL_H) / 2.0
	var tabs_right := float(TAB_X0 + TRACK_COUNT * (TAB_W + TAB_GAP))
	var x          := tabs_right + 8.0

	# 💰 Geld – immer sichtbar, bündig rechts neben „Strecke 3". Grün als Geld-Währungsfarbe.
	_currency_lbl = _make_bar_pill(x, pill_y, MONEY_W, Color(0.40, 0.85, 0.45))
	_currency_lbl.text = "%s  %s" % [Icons.COIN, Economy.format_currency(Economy.get_currency())]
	_money_pill_cx = x + MONEY_W / 2.0   # Mitte der Geld-Pille → darunter erscheint das „+N 💰"-Popup
	x += MONEY_W + PILL_GAP

	# ⭐ Prestige-Punkte – erst ab dem ersten Prestige (bzw. den ersten Punkten). Lila wie der Prestige-Tab.
	if Economy.get_prestige_count() > 0 or Economy.get_prestige_points() > 0:
		_prestige_lbl = _make_bar_pill(x, pill_y, STAT_W, Color(0.74, 0.48, 0.97))
		_prestige_lbl.text = "%s %s" % [Icons.STAR, Economy.format_currency(Economy.get_prestige_points())]
		x += STAT_W + PILL_GAP

	# 🏆 Trophäen – erst ab dem ersten freigeschalteten Erfolg. Gold wie das Erfolge-Tab-Icon.
	if Economy.get_unlocked_achievement_count() > 0:
		_trophy_lbl = _make_bar_pill(x, pill_y, STAT_W, Color(1.00, 0.82, 0.30))
		_trophy_lbl.text = "%s %s" % [Icons.TROPHY, Economy.format_currency(Economy.get_ach_currency())]
		x += STAT_W + PILL_GAP

	# Ende der sichtbaren Werte-Reihe (Geld/⭐/🏆) – Basis für die Timer-Klemmung.
	var badges_end := x

	# Endlos-Toggle (Cheat) hinten an die Reihe anhängen.
	_endless_btn = _make_btn_in(Icons.INFINITY, Vector2(x, (BAR_H - BTN_H) / 2.0), 34, BTN_H)
	_endless_btn.pressed.connect(_on_endless_toggled)
	_ui_root.add_child(_endless_btn)
	_refresh_endless_btn()
	x += 34 + PILL_GAP

	# „+1B"-Badge (Cheat-Modus)
	_debug_btn = Button.new()
	_debug_btn.text     = "+1B " + Icons.STAR
	_debug_btn.position = Vector2(x, pill_y)
	_debug_btn.size     = Vector2(DEBUG_W, PILL_H)
	_debug_btn.focus_mode = Control.FOCUS_NONE
	_debug_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_debug_btn.add_theme_font_size_override("font_size", 12)
	var badge_n := StyleBoxFlat.new()
	badge_n.bg_color = Color(0.96, 0.62, 0.18)
	badge_n.set_corner_radius_all(16)
	var badge_h := badge_n.duplicate() as StyleBoxFlat
	badge_h.bg_color = Color(1.0, 0.71, 0.30)
	_debug_btn.add_theme_stylebox_override("normal",  badge_n)
	_debug_btn.add_theme_stylebox_override("hover",   badge_h)
	_debug_btn.add_theme_stylebox_override("pressed", badge_n)
	_debug_btn.add_theme_stylebox_override("focus",   badge_n)
	_debug_btn.add_theme_color_override("font_color", Color(0.20, 0.12, 0.0))
	_debug_btn.tooltip_text = "Verdoppelt dein Geld, +1 Mrd. Geld, +100 %s, +1000 %s" % [Icons.STAR, Icons.TROPHY]
	# Cheat: Geld verdoppeln UND +1 Mrd. (Verdopplung = aktuelles Guthaben zusätzlich addieren),
	# dazu Prestige-Punkte (⭐) und Erfolgs-Trophäen gutschreiben.
	_debug_btn.pressed.connect(func():
		Economy.add(Economy.get_currency() + 1_000_000_000)
		Economy.add_prestige_points(100)
		Economy.add_ach_currency(1000)
	)
	_ui_root.add_child(_debug_btn)
	x += DEBUG_W + PILL_GAP

	# Renn-Timer – rechtsbündig am Inhalts-Rand (= vor der Seitenleiste), aber nie über die
	# sichtbare Werte-Reihe. Die Cheat-Buttons zählen nur dann zur Reihe, wenn der Cheat-Modus
	# aktiv ist (sonst sind sie unsichtbar und dürfen den Timer nicht nach rechts schieben).
	# Sichtbar nur in der 3D-Fahrt der gerade gezeigten Strecke (siehe _refresh_timer).
	var row_end := x if Economy.cheat_mode else badges_end
	const TIMER_W = 122
	var timer_x := maxf(RUI.content_w() - 8.0 - TIMER_W, row_end)

	_timer_box = Panel.new()
	_timer_box.position = Vector2(timer_x, pill_y)
	_timer_box.size     = Vector2(TIMER_W, PILL_H)
	var tmr_sb := StyleBoxFlat.new()
	tmr_sb.bg_color     = C_SURFACE
	tmr_sb.set_border_width_all(1)
	tmr_sb.border_color = C_LINE
	tmr_sb.set_corner_radius_all(16)
	_timer_box.add_theme_stylebox_override("panel", tmr_sb)
	_ui_root.add_child(_timer_box)

	_timer_lbl = Label.new()
	_timer_lbl.position = Vector2(timer_x, 0)
	_timer_lbl.size     = Vector2(TIMER_W, BAR_H)
	_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_timer_lbl.add_theme_font_size_override("font_size", 16)
	_timer_lbl.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_ui_root.add_child(_timer_lbl)
	_refresh_timer()

	_refresh_tabs()
	_refresh_view_buttons()
	_refresh_cheat_visibility()


# Kleine Status-Pille (Panel + zentriertes Label) für Geld/⭐/🏆 in der oberen Leiste.
# Fügt Panel und Label zu _ui_root hinzu und gibt das Label zurück (Text setzt der Aufrufer).
func _make_bar_pill(x: float, y: float, w: float, font_color: Color) -> Label:
	var box := Panel.new()
	box.position = Vector2(x, y)
	box.size     = Vector2(w, 32)
	var sb := StyleBoxFlat.new()
	sb.bg_color     = C_SURFACE
	sb.set_border_width_all(1)
	sb.border_color = C_LINE
	sb.set_corner_radius_all(16)
	box.add_theme_stylebox_override("panel", sb)
	_ui_root.add_child(box)

	var lbl := Label.new()
	lbl.position = Vector2(x, 0)
	lbl.size     = Vector2(w, BAR_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", font_color)
	_ui_root.add_child(lbl)
	return lbl


# ── Rechte Seitenleiste / Navigation ────────────────────────────────────────────
# Dauerhaft sichtbare, durchgezogene Leiste am rechten Rand (volle Höhe bis über die
# Run-Bar). Sie ist GLEICHZEITIG die Navigation des Upgrade-Centers (GlobalModal):
# ein Klick öffnet/wechselt die jeweilige Seite, der aktive Eintrag bleibt markiert.
# Im Portrait-Modus wird stattdessen eine untere Icon-Leiste gebaut (_build_bottom_nav).
const NAV_W      = 150     # Design-Breite der Seitenleiste (Landscape)
const BOT_H      = 42      # Höhe der unteren Run-Bar (bleibt frei)
const NAV_HDR_H  = 52

# Sonder-„tab"-Werte (keine GlobalModal-Seiten):
const PAGE_STRECKE = -1   # Startseite = alles schließen / zurück zur Strecke
const PAGE_OPTIONS = -2   # Einstellungen (liegt im PauseMenu)

# "tab" = Index im GlobalModal (MODAL_TABS): Shop0, Erfolge1, Werkstatt2, Statistik3, Prestige4.
# "Strecke" (tab = -1) ist die Startseite = Modal schließen / zurück zur Strecke.
# Jeder Menüpunkt hat ein farbiges Tabler-Icon (klare, unterscheidbare Akzentfarben).
# Als Funktion statt const, weil die Icon-Glyphen aus dem Icons-Autoload kommen.
func _nav_pages() -> Array:
	return [
		{"icon": Icons.FLAG_3,   "label": "Strecke",   "tab": -1, "color": Color(0.32, 0.80, 0.46)},  # grün
		{"icon": Icons.STORE,    "label": "Shop",      "tab": 0,  "color": Color(0.26, 0.78, 0.85)},  # türkis
		{"icon": Icons.STAR,     "label": "Prestige",  "tab": 4,  "color": Color(0.74, 0.48, 0.97)},  # violett
		{"icon": Icons.TOOLS,    "label": "Werkstatt", "tab": 2,  "color": Color(0.96, 0.55, 0.26)},  # orange
		{"icon": Icons.GARAGE,   "label": "Garage",    "tab": 5,  "color": Color(0.93, 0.42, 0.66)},  # rosa
		{"icon": Icons.TROPHY,   "label": "Erfolge",   "tab": 1,  "color": Color(1.00, 0.82, 0.30)},  # gold
		{"icon": Icons.CHART_BAR,"label": "Statistik", "tab": 3,  "color": Color(0.40, 0.62, 1.00)},  # blau
	]

var _nav_btns:    Array = []   # je {btn, tab}
var _active_page: int   = -1   # gerade geöffnete Seite (-1 = Modal geschlossen)
var _pause_nav_btn: Button = null   # „Pause-Menü"-Eintrag, nur im Mobile-Steuerungsmodus sichtbar


func _build_side_menu() -> void:
	var nav_x  := RUI.vw() - NAV_W
	var nav_top := 0.0
	var nav_bot := RUI.vh() - BOT_H
	var nav_h   := nav_bot - nav_top

	# Hintergrund (durchgezogene Fläche am rechten Rand)
	var bg := ColorRect.new()
	bg.position = Vector2(nav_x, nav_top)
	bg.size     = Vector2(NAV_W, nav_h)
	bg.color    = C_SURFACE
	_ui_root.add_child(bg)

	# Kopf
	var hdr := Label.new()
	hdr.position = Vector2(nav_x + 16, nav_top)
	hdr.size     = Vector2(NAV_W - 22, NAV_HDR_H)
	hdr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 17)
	hdr.add_theme_color_override("font_color", C_ACCENT)
	hdr.text = Icons.MENU + " Menü"
	_ui_root.add_child(hdr)

	var hline := ColorRect.new()
	hline.position = Vector2(nav_x, nav_top + NAV_HDR_H)
	hline.size     = Vector2(NAV_W, 1)
	hline.color    = C_LINE
	_ui_root.add_child(hline)

	# Seiten-Einträge
	const ITEM_H = 44
	const ITEM_GAP = 2
	var y0 := nav_top + NAV_HDR_H + 8
	_nav_btns.clear()
	for entry in _nav_pages():
		var btn := _make_nav_item(entry.icon, entry.label, entry.color, Vector2(nav_x, y0), NAV_W, ITEM_H)
		btn.pressed.connect(_on_nav_page.bind(int(entry.tab)))
		_ui_root.add_child(btn)
		_apply_nav_lock(btn, int(entry.tab))   # Prestige/Werkstatt ggf. als gesperrt markieren
		_nav_btns.append({"btn": btn, "tab": int(entry.tab), "icon": entry.icon, "label": entry.label})
		y0 += ITEM_H + ITEM_GAP

	# Trenner + „Optionen"
	var sep := ColorRect.new()
	sep.position = Vector2(nav_x + 12, y0 + 8)
	sep.size     = Vector2(NAV_W - 24, 1)
	sep.color    = C_LINE
	_ui_root.add_child(sep)
	var opt := _make_nav_item(Icons.SETTINGS, "Optionen", C_TEXT_DIM, Vector2(nav_x, y0 + 18), NAV_W, ITEM_H)
	opt.pressed.connect(_on_nav_page.bind(PAGE_OPTIONS))
	_ui_root.add_child(opt)
	_nav_btns.append({"btn": opt, "tab": PAGE_OPTIONS, "icon": Icons.SETTINGS, "label": "Optionen"})

	# „Pause-Menü" – nur im Mobile-Steuerungsmodus sichtbar
	_pause_nav_btn = _make_nav_item(Icons.PAUSE, "Pause-Menü", Color(0.92, 0.42, 0.42),
		Vector2(nav_x, y0 + 18 + ITEM_H + ITEM_GAP), NAV_W, ITEM_H)
	_pause_nav_btn.pressed.connect(_on_pause_nav_pressed)
	_pause_nav_btn.visible = _load_mobile_mode()
	_ui_root.add_child(_pause_nav_btn)

	# Linke Trennlinie über allen Nav-Einträgen (damit Button-HGs sie nicht überdecken)
	var vline := ColorRect.new()
	vline.position = Vector2(nav_x, nav_top)
	vline.size     = Vector2(1, nav_h)
	vline.color    = C_LINE
	_ui_root.add_child(vline)

	_refresh_nav_highlight()


# ── Portrait-Modus: untere Icon-Leiste ────────────────────────────────────────
# Im Hochformat-Modus (Handy vertikal) ersetzt eine kompakte Icon-Leiste unten
# die rechte Seitenleiste. Die Buttons lösen dieselbe Navigation aus.
func _build_bottom_nav() -> void:
	var vw   := RUI.vw()
	var vh   := RUI.vh()
	var bn_h := RUI.BOTTOM_NAV_H
	var nav_y := vh - bn_h

	# Hintergrund
	var bg := ColorRect.new()
	bg.position = Vector2(0, nav_y)
	bg.size     = Vector2(vw, bn_h)
	bg.color    = C_SURFACE
	_ui_root.add_child(bg)

	var tline := ColorRect.new()
	tline.position = Vector2(0, nav_y)
	tline.size     = Vector2(vw, 1)
	tline.color    = C_LINE
	_ui_root.add_child(tline)

	# Alle Nav-Seiten als gleichmäßig verteilte Icon-Buttons
	var pages := _nav_pages()
	# Einschließlich Optionen
	pages.append({"icon": Icons.SETTINGS, "label": "Optionen", "tab": PAGE_OPTIONS, "color": C_TEXT_DIM})
	var btn_w := vw / float(pages.size())
	_nav_btns.clear()

	for i in pages.size():
		var entry = pages[i]
		var btn  := Button.new()
		btn.position = Vector2(i * btn_w, nav_y)
		btn.size     = Vector2(btn_w, bn_h)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		# Icon als eigenes Label (Farbe unabhängig vom Aktiv-Zustand)
		var ico := Icons.label(entry.icon, 22, entry.color)
		ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ico.set_anchors_preset(Control.PRESET_FULL_RECT)
		ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ico.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		btn.add_child(ico)
		btn.set_meta("txt_lbl", ico)

		_style_nav_btn(btn, false)
		btn.pressed.connect(_on_nav_page.bind(int(entry.tab)))
		_ui_root.add_child(btn)
		_apply_nav_lock(btn, int(entry.tab))   # Prestige/Werkstatt ggf. als gesperrt markieren
		_nav_btns.append({"btn": btn, "tab": int(entry.tab), "icon": entry.icon, "label": entry.label})

	# Pause-Menü-Button ist immer im Portrait-Modus sichtbar (kein ESC auf Handy)
	_pause_nav_btn = _nav_btns.back()["btn"] if _nav_btns else null

	_refresh_nav_highlight()


func _on_pause_nav_pressed() -> void:
	# Erst Offenes schließen, dann das Pause-Menü öffnen.
	if GlobalModal.visible:
		GlobalModal.close()
	if PauseMenu.is_settings_open():
		PauseMenu.close_settings()
	PauseMenu.open_pause()


# Vom PauseMenu beim Wechsel der Steuerungsart aufgerufen.
func set_mobile_mode(enabled: bool) -> void:
	if _pause_nav_btn != null and is_instance_valid(_pause_nav_btn):
		_pause_nav_btn.visible = enabled


func _load_mobile_mode() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(Paths.SETTINGS_FILE)
	return String(cfg.get_value("options", "control_mode", "click")) == "mobile"


# Bei Sprachwechsel (NOTIFICATION_TRANSLATION_CHANGED) die selbst übersetzten Texte
# der oberen Leiste neu aufbauen: Strecken-Tabs und die Seitennavigation. Die farbigen
# Icons sind eigene Kind-Labels und bleiben unverändert – nur der Text wird neu übersetzt.
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED:
		return
	if not _tab_btns.is_empty():
		_refresh_tabs()
	for e in _nav_btns:
		if e.has("label") and is_instance_valid(e["btn"]):
			var lbl = e["btn"].get_meta("txt_lbl", null)
			if lbl != null and is_instance_valid(lbl):
				lbl.text = tr(e["label"])
	if _pause_nav_btn != null and is_instance_valid(_pause_nav_btn):
		var pl = _pause_nav_btn.get_meta("txt_lbl", null)
		if pl != null and is_instance_valid(pl):
			pl.text = tr("Pause-Menü")


# Nav-Eintrag = farbiges Tabler-Icon (eigenes Label links) + übersetztes Text-Label.
# Die Akzentfarbe des Icons ist so unabhängig vom Hover/Aktiv-Zustand des Texts.
func _make_nav_item(icon_glyph: String, label_key: String, icon_color: Color, pos: Vector2, w: float, h: float) -> Button:
	var btn := Button.new()
	btn.position   = pos
	btn.size       = Vector2(w, h)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Farbiges, geprägtes Icon links (eigene Akzentfarbe, unabhängig vom Aktiv-Zustand).
	var ico := Icons.label(icon_glyph, 19, icon_color)
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ico.position = Vector2(12, 0)
	ico.size     = Vector2(24, h)
	_emboss(ico)
	btn.add_child(ico)
	btn.set_meta("icon_lbl", ico)   # für die Tab-Sperre (Schloss-Glyph) referenzierbar

	# Text als eigenes (geprägtes) Label – Button-Text kann keinen Schatten, daher als Label.
	# Klicks gehen durch (mouse_filter ignore) an den Button.
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	lbl.position = Vector2(44, 0)
	lbl.size     = Vector2(w - 50, h)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.text = tr(label_key)
	_emboss(lbl)
	btn.add_child(lbl)
	btn.set_meta("txt_lbl", lbl)

	_style_nav_btn(btn, false)
	return btn


# Geprägter 3D-Look: dunkler Schlagschatten nach unten-rechts.
func _emboss(lbl: Label) -> void:
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 2)


# Setzt das Aussehen eines Nav-Eintrags je nach Aktiv-Zustand. Das aktive Element trägt
# IMMER (auch beim Hovern) den Akzent-Balken + die Akzent-Textfarbe → eindeutig markiert.
func _style_nav_btn(btn: Button, active: bool) -> void:
	if active:
		var sb := _nav_sb(C_SURFACE_HI, true)
		btn.add_theme_stylebox_override("normal",  sb)
		btn.add_theme_stylebox_override("hover",   _nav_sb(C_SURFACE_HI.lightened(0.05), true))
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("focus",   sb)
	else:
		btn.add_theme_stylebox_override("normal",  _nav_sb(C_SURFACE,    false))
		btn.add_theme_stylebox_override("hover",   _nav_sb(C_SURFACE_HI, false))
		btn.add_theme_stylebox_override("pressed", _nav_sb(C_SURFACE_HI, false))
		btn.add_theme_stylebox_override("focus",   _nav_sb(C_SURFACE,    false))
	var lbl = btn.get_meta("txt_lbl", null)
	if lbl != null and is_instance_valid(lbl):
		lbl.add_theme_color_override("font_color", C_ACCENT if active else C_TEXT_DIM)


# Flache, randlose Listen-Optik; aktiver Eintrag bekommt einen Akzent-Balken links.
func _nav_sb(bg: Color, active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.content_margin_left   = 44   # Platz für das farbige Icon-Label links
	sb.content_margin_right  = 8
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	if active:
		sb.border_width_left = 3
		sb.border_color      = C_ACCENT
	return sb


func _on_nav_page(tab: int) -> void:
	var prev := _active_page
	# Erst alles Offene schließen (Upgrade-Center ODER Einstellungen). _active_page wird
	# danach selbst gesetzt – die Schließen-Callbacks dürfen das Ergebnis nicht überschreiben.
	if GlobalModal.visible:
		GlobalModal.close()
	if PauseMenu.is_settings_open():
		PauseMenu.close_settings()
	# Erneuter Klick auf den aktiven Eintrag (oder „Strecke") → geschlossen lassen.
	if tab == prev or tab == PAGE_STRECKE:
		_active_page = PAGE_STRECKE
		_refresh_nav_highlight()
		return
	_active_page = tab
	_refresh_nav_highlight()
	if tab == PAGE_OPTIONS:
		PauseMenu.open_settings()
	else:
		GlobalModal.open_tab(tab)


# Wird von GlobalModal.close() gerufen (ESC / ✕ / erneuter Klick) → Markierung zurücksetzen.
func _on_modal_closed() -> void:
	_active_page = -1
	_refresh_nav_highlight()


func _refresh_nav_highlight() -> void:
	for e in _nav_btns:
		var btn: Button = e["btn"]
		if not is_instance_valid(btn):
			continue
		_style_nav_btn(btn, int(e["tab"]) == _active_page)


# TEMP: Tab gesperrt? Prestige (Tab 4) bzw. Werkstatt (Tab 2) bis zur Verdienst-Schwelle.
# Bedingung kommt aus Economy.is_*_tab_unlocked – sobald es einen Erfolge-Tab gibt, von dort speisen.
func _is_tab_locked(tab: int) -> bool:
	if tab == 4: return not Economy.is_prestige_tab_unlocked()
	if tab == 2: return not Economy.is_werkstatt_tab_unlocked()
	return false


# Gesperrte Nav-Einträge: Schloss-Glyph statt farbigem Icon + abgedunkelter Text. Klick bleibt
# möglich → öffnet den Tab, der dann das Sperr-Overlay mit dem Freischalt-Hinweis zeigt.
func _apply_nav_lock(btn: Button, tab: int) -> void:
	if not _is_tab_locked(tab):
		return
	# Icon-Label: Seitenleiste = eigenes "icon_lbl"; Bottom-Nav = das einzige Label ("txt_lbl").
	var ico = btn.get_meta("icon_lbl", null)
	if ico == null:
		ico = btn.get_meta("txt_lbl", null)
	if ico != null and is_instance_valid(ico):
		ico.text = Icons.LOCK
		ico.modulate = Color(1, 1, 1, 0.55)
	var lbl = btn.get_meta("txt_lbl", null)
	if lbl != null and is_instance_valid(lbl) and lbl != ico:
		lbl.modulate = Color(1, 1, 1, 0.6)


## Erzeugt einen kleinen Aktions-Button und fügt ihn zu _ui_root hinzu.
func _make_btn_in(txt: String, pos: Vector2, w: float, h: float) -> Button:
	var btn := Button.new()
	btn.text     = txt
	btn.position = pos
	btn.size     = Vector2(w, h)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",  _sb(C_SURFACE,    C_ACCENT_MU))
	btn.add_theme_stylebox_override("hover",   _sb(C_SURFACE_HI, C_ACCENT))
	btn.add_theme_stylebox_override("pressed", _sb(C_SURFACE,    C_ACCENT))
	btn.add_theme_stylebox_override("focus",   _sb(C_SURFACE,    C_ACCENT_MU))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 12)
	return btn


## Ältere Signatur – bleibt für externe Aufrufer erhalten.
func _make_btn(txt: String, pos: Vector2, w: float, h: float) -> Button:
	return _make_btn_in(txt, pos, w, h)


# Upgrade-Center-Button: gefüllte Akzent-Pille (Cyan) mit dunklem Text – primäre Aktion.
func _make_uc_btn(txt: String, pos: Vector2, w: float, h: float) -> Button:
	var btn := Button.new()
	btn.text     = txt
	btn.position = pos
	btn.size     = Vector2(w, h)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var uc_blue := Color(0.48, 0.70, 1.00)   # hellblau (Rahmen + Schrift)
	btn.add_theme_stylebox_override("normal",  _uc_sb(C_BG,         uc_blue))
	btn.add_theme_stylebox_override("hover",   _uc_sb(C_SURFACE,    uc_blue))
	btn.add_theme_stylebox_override("pressed", _uc_sb(C_SURFACE_HI, uc_blue))
	btn.add_theme_stylebox_override("focus",   _uc_sb(C_BG,         uc_blue))
	btn.add_theme_color_override("font_color",       uc_blue)
	btn.add_theme_color_override("font_hover_color", uc_blue.lightened(0.15))
	btn.add_theme_font_size_override("font_size", 14)
	return btn


func _uc_sb(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(20)   # Pille
	sb.content_margin_left   = 14
	sb.content_margin_right  = 14
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	return sb


func _sb(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(10)
	sb.content_margin_left   = 5
	sb.content_margin_right  = 5
	sb.content_margin_top    = 3
	sb.content_margin_bottom = 3
	return sb


# Normale (nicht-fette) Schrift für die Strecken-Tabs – die globale UI-Schrift ist fett,
# das wirkt auf den kleinen Tabs zu wuchtig. Einmal gebaut und gecacht.
var _tab_font_regular: SystemFont = null
func _regular_tab_font() -> SystemFont:
	if _tab_font_regular == null:
		_tab_font_regular = SystemFont.new()
		_tab_font_regular.font_names = PackedStringArray(["Segoe UI", "Bahnschrift", "Inter", "Roboto", "Arial"])
		_tab_font_regular.font_weight = 400
	return _tab_font_regular


func _style_tab_btn(btn: Button, active: bool) -> void:
	# Rechteckige Form: aktiver Tab gefüllt mit Akzent (dunkler Text), inaktive dezent.
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ACCENT if active else C_SURFACE
	sb.set_corner_radius_all(4)
	sb.content_margin_left   = 10
	sb.content_margin_right  = 10
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	# 3D-/Pillen-Effekt: weicher Schlagschatten nach unten → angehobene Pille.
	sb.shadow_color  = Color(0, 0, 0, 0.45)
	sb.shadow_size   = 3
	sb.shadow_offset = Vector2(0, 2)
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus",   sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	if not active:
		sb_h.bg_color = C_SURFACE_HI
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_color_override("font_color", C_BG if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 13)
	# Schrift bewusst in normaler Stärke (nicht fett) – wirkt auf den Tabs ruhiger.
	# Der 3D-Look kommt allein vom Pillen-Schatten oben.
	btn.add_theme_font_override("font", _regular_tab_font())
	# Disabled (gesperrte Strecke)
	var sb_dis := sb.duplicate() as StyleBoxFlat
	sb_dis.bg_color = C_SURFACE.darkened(0.2)
	btn.add_theme_stylebox_override("disabled", sb_dis)
	btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM.darkened(0.15))


func _set_run_dot(i: int, on: bool) -> void:
	if i < _run_dot_sbs.size():
		_run_dot_sbs[i].bg_color = C_RUN_ON if on else C_RUN_OFF


func _refresh_tabs() -> void:
	var unlocked := Economy.get_unlocked_tracks()
	for i in TRACK_COUNT:
		var is_locked := i >= unlocked
		# Gesperrte Strecken (per Prestige „Extra-Strecke" freischaltbar) zeigen ein Schloss.
		# tr() übersetzt den Format-String („Strecke %d" → „Track %d") vor dem Einsetzen
		# der Nummer; auto_translate ist für die Tabs aus (siehe _build_bar).
		var tab_label := tr("Strecke %d") % (i + 1)
		_tab_btns[i].text     = (Icons.LOCK + " " + tab_label) if is_locked else tab_label
		_style_tab_btn(_tab_btns[i], i == _active_tab)
		# Tabs bleiben auch in der 3D-Ansicht aktiv – nur gesperrte Strecken sind nicht wählbar.
		_tab_btns[i].disabled = is_locked
		_run_dots[i].visible  = not is_locked
		_set_run_dot(i, Economy.is_run_active(i))


func _refresh_view_buttons() -> void:
	# Die 2D/3D-Buttons wurden aus der Top-Nav entfernt; nichts mehr zu stylen.
	if _view_2d_btn == null or _view_3d_btn == null:
		return
	var sb_on := StyleBoxFlat.new()
	sb_on.bg_color            = C_SURFACE_HI
	sb_on.border_width_bottom = 2
	sb_on.border_color        = C_ACCENT
	sb_on.set_corner_radius_all(3)
	sb_on.content_margin_left = 5; sb_on.content_margin_right  = 5
	sb_on.content_margin_top  = 3; sb_on.content_margin_bottom = 3

	if _is_3d_view:
		_view_3d_btn.add_theme_stylebox_override("normal", sb_on)
		_view_3d_btn.add_theme_color_override("font_color", C_ACCENT)
		_view_2d_btn.add_theme_stylebox_override("normal", _sb(C_SURFACE, C_ACCENT_MU))
		_view_2d_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	else:
		_view_2d_btn.add_theme_stylebox_override("normal", sb_on)
		_view_2d_btn.add_theme_color_override("font_color", C_ACCENT)
		_view_3d_btn.add_theme_stylebox_override("normal", _sb(C_SURFACE, C_ACCENT_MU))
		_view_3d_btn.add_theme_color_override("font_color", C_TEXT_DIM)


func _process(_delta: float) -> void:
	# Im Hauptmenü ausblenden
	var scene := get_tree().current_scene
	var in_menu := scene != null and scene.name == "MainMenu"
	visible = not in_menu
	if in_menu:
		return

	if _currency_lbl != null:
		_currency_lbl.text = "%s  %s" % [Icons.COIN, Economy.format_currency(Economy.get_currency())]
	if _prestige_lbl != null:
		_prestige_lbl.text = "%s %s" % [Icons.STAR, Economy.format_currency(Economy.get_prestige_points())]
	if _trophy_lbl != null:
		_trophy_lbl.text = "%s %s" % [Icons.TROPHY, Economy.format_currency(Economy.get_ach_currency())]
	_refresh_timer()
	for i in TRACK_COUNT:
		if i < _run_dot_sbs.size():
			_set_run_dot(i, Economy.is_run_active(i))

	# Nav-Highlight mit dem echten Zustand abgleichen: wurde die Seite/Optionen extern
	# geschlossen (✕/ESC/eigene Buttons), Markierung auf „Strecke" zurücksetzen.
	var synced := _active_page
	if _active_page == PAGE_OPTIONS and not PauseMenu.is_settings_open():
		synced = PAGE_STRECKE
	elif _active_page >= 0 and not GlobalModal.visible:
		synced = PAGE_STRECKE
	if synced != _active_page:
		_active_page = synced
		_refresh_nav_highlight()


# ── Callbacks ──────────────────────────────────────────────────────────────────

func _on_tab_pressed(idx: int) -> void:
	if idx == _active_tab:
		return
	# Gesperrte Strecke (noch nicht per Prestige freigeschaltet) → ignorieren.
	if idx >= Economy.get_unlocked_tracks():
		return
	_active_tab   = idx
	# Baumodus über 2D→2D-Streckenwechsel hinweg beibehalten; nur beim Wechsel in eine
	# 3D-Strecke schließen (dort gibt es kein Baumenü). Main.gd synchronisiert die Sichtbarkeit
	# des Baupanels in _on_tab_changed an diesen Zustand – sonst bliebe das Panel desynchron
	# sichtbar und der Schließen-Knopf bräuchte zwei Klicks.
	if is_track_3d(idx):
		_build_active = false
	# Die gezeigte Ansicht richtet sich nach dem gemerkten Modus der Zielstrecke.
	_is_3d_view   = is_track_3d(idx)
	Economy.set_active_track(idx)
	_refresh_tabs()
	_refresh_view_buttons()
	# Die jeweils geladene Szene (Main bzw. World3D) reagiert auf tab_changed und lädt
	# die zur Ansicht der Zielstrecke passende Szene.
	emit_signal("tab_changed", idx)


# Wird vom Hammer-Button in Main.gd aufgerufen (Baumodus an/aus).
func request_build_toggle() -> void:
	if _is_3d_view:
		return
	_build_active = not _build_active
	_refresh_view_buttons()
	emit_signal("build_mode_toggled", _build_active)


func _on_view_2d() -> void:
	if not _is_3d_view:
		return
	_is_3d_view = false
	_refresh_view_buttons()
	_refresh_tabs()
	emit_signal("view_changed_to_2d")


func _on_view_3d() -> void:
	if _is_3d_view:
		return
	_is_3d_view   = true
	_build_active = false
	_refresh_view_buttons()
	_refresh_tabs()
	emit_signal("view_changed_to_3d")


func _on_shop_pressed() -> void:
	emit_signal("shop_requested")


# ── Öffentliche API ────────────────────────────────────────────────────────────

func get_active_tab() -> int:
	return _active_tab


func set_view_3d(is3d: bool) -> void:
	_is_3d_view = is3d
	if is3d:
		_build_active = false
	_refresh_view_buttons()
	_refresh_tabs()


# ── Ansicht je Strecke ───────────────────────────────────────────────────────

func is_track_3d(idx: int) -> bool:
	return idx >= 0 and idx < _track_view_3d.size() and _track_view_3d[idx]


func set_track_3d(idx: int, val: bool) -> void:
	if idx >= 0 and idx < _track_view_3d.size():
		_track_view_3d[idx] = val
	if idx == _active_tab:
		_is_3d_view = val
	_refresh_view_buttons()
	_refresh_tabs()


# Lädt die 3D-Ansicht (World3D) der Strecke idx; die laufende Runde wird fortgesetzt.
# Einzige Stelle, die für einen Strecken-/Ansichtswechsel World3D lädt (von Main UND World3D
# beim Tab-Wechsel genutzt).
func goto_world3d(idx: int) -> void:
	set_track_3d(idx, true)
	var grid: Array = Economy.get_track_grid(idx)
	Engine.set_meta("active_track_idx",   idx)
	Engine.set_meta("resuming_run",       true)
	Engine.set_meta("pending_grid_state", grid)
	var world_scene = load(Paths.SCENE_WORLD3D)
	if world_scene:
		get_tree().change_scene_to_packed(world_scene)


func set_build_active(val: bool) -> void:
	_build_active = val
	_refresh_view_buttons()


# Nach einem Prestige: zurück auf Strecke 1 in 2D (Strecke 2/3 sind wieder gesperrt). Wird von
# GlobalModal vor dem Szenenwechsel in den Bauplan aufgerufen.
func reset_after_prestige() -> void:
	_active_tab   = 0
	_is_3d_view   = false
	_build_active = false
	for i in _track_view_3d.size():
		_track_view_3d[i] = false
	_refresh_tabs()
	_refresh_view_buttons()


func is_build_active() -> bool:
	return _build_active


# ── Einstellungen / Cheat-Buttons ───────────────────────────────────────────────

# Blendet die Cheat-Buttons (∞ und +1B ⭐) je nach Einstellung ein/aus.
func _refresh_cheat_visibility() -> void:
	if _endless_btn != null:
		_endless_btn.visible = Economy.cheat_mode
	if _debug_btn != null:
		_debug_btn.visible = Economy.cheat_mode
	_refresh_endless_btn()


func _on_endless_toggled() -> void:
	Economy.endless_mode = not Economy.endless_mode
	_refresh_endless_btn()


func _refresh_endless_btn() -> void:
	if _endless_btn == null:
		return
	if Economy.endless_mode:
		var sb := StyleBoxFlat.new()
		sb.bg_color            = C_SURFACE_HI
		sb.border_width_bottom = 2
		sb.border_color        = C_ACCENT
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 5; sb.content_margin_right  = 5
		sb.content_margin_top  = 3; sb.content_margin_bottom = 3
		_endless_btn.add_theme_stylebox_override("normal", sb)
		_endless_btn.add_theme_color_override("font_color", C_ACCENT)
	else:
		_endless_btn.add_theme_stylebox_override("normal", _sb(C_SURFACE, C_ACCENT_MU))
		_endless_btn.add_theme_color_override("font_color", C_TEXT_DIM)


# Renn-Timer aktualisieren: nur in der 3D-Fahrt der gerade gezeigten Strecke und nur
# bei laufender Runde sichtbar. Im Endlos-Modus erscheint ∞ statt der Restzeit. Die
# Position wird in _build_bar aus der Währungsgeometrie bestimmt (responsive).
func _refresh_timer() -> void:
	if _timer_lbl == null or _timer_box == null:
		return
	var show := is_track_3d(_active_tab) and Economy.is_run_active(_active_tab)
	_timer_box.visible = show
	_timer_lbl.visible = show
	if not show:
		return
	if Economy.endless_mode:
		_timer_lbl.text = "%s  %s" % [Icons.CLOCK, Icons.INFINITY]
	else:
		_timer_lbl.text = "%s  %.1f s" % [Icons.CLOCK, Economy.get_run_time_left(_active_tab)]


func flash_currency() -> void:
	if _currency_lbl == null:
		return
	var tw := create_tween()
	tw.tween_property(_currency_lbl, "modulate", Color(1, 0.2, 0.2), 0.08)
	tw.tween_property(_currency_lbl, "modulate", Color(1, 1, 1), 0.30)


func gain_currency(amount: int) -> void:
	if amount <= 0 or _currency_lbl == null:
		return
	_currency_lbl.pivot_offset = _currency_lbl.size / 2.0
	var tw := create_tween()
	tw.tween_property(_currency_lbl, "scale", Vector2(1.22, 1.22), 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_currency_lbl, "modulate", Color(0.45, 1.0, 0.5), 0.10)
	tw.tween_property(_currency_lbl, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_currency_lbl, "modulate", Color(1, 1, 1), 0.25)

	# „+N 💰" direkt UNTER der Geld-Pille (horizontal an deren Mitte ausgerichtet), nach unten driftend.
	var fl := Label.new()
	fl.text = "+%s %s" % [Economy.format_currency(amount), Icons.COIN]
	fl.position = Vector2(_money_pill_cx - 60.0, BAR_H + 2.0)
	fl.size     = Vector2(120, 26)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	fl.add_theme_font_size_override("font_size", 18)
	fl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	fl.add_theme_constant_override("outline_size", 3)
	fl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(fl)
	var t := create_tween()
	t.tween_property(fl, "position:y", float(BAR_H) + 22.0, 0.85) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(fl, "modulate:a", 0.0, 0.85)
	t.tween_callback(fl.queue_free)


# ── Erfolgs-Popup (unten links) ─────────────────────────────────────────────────
# Über Economy.achievement_unlocked ausgelöst. Das erste Achievement blendet zusätzlich das
# 🏆-Badge in der oberen Leiste ein (Neuaufbau nur dann nötig – danach reicht das _process-Update).
func _on_achievement_unlocked(id: String) -> void:
	if _trophy_lbl == null:
		_build_ui()
	_show_achievement_toast(id)


# Kleines Popup unten links (links von der Seitenleiste, über der unteren Run-Bar mit dem Fahren-Knopf):
# zeigt nur Icon und Name des freigeschalteten Erfolgs. Die Trophäen werden NICHT automatisch
# vergeben – man sammelt sie im Erfolge-Tab ein. Es ist immer nur EIN Popup gleichzeitig sichtbar.
func _show_achievement_toast(id: String) -> void:
	if _ach_toast != null and is_instance_valid(_ach_toast):
		_ach_toast.queue_free()

	const TW = 300
	const TH = 60
	var bottom_h: float = float(RUI.BOTTOM_NAV_H) if RUI.is_portrait() else float(BOT_H)
	var base_y: float   = RUI.vh() - bottom_h - 12.0 - TH

	var toast := Panel.new()
	toast.size     = Vector2(TW, TH)
	toast.position = Vector2(12, base_y + 16.0)
	toast.modulate = Color(1, 1, 1, 0)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE   # darf nie Klicks (z. B. Fahren-Knopf) abfangen
	var sb := StyleBoxFlat.new()
	sb.bg_color      = C_SURFACE_HI
	sb.border_color  = C_ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.shadow_color  = Color(0, 0, 0, 0.5)
	sb.shadow_size   = 6
	sb.shadow_offset = Vector2(0, 3)
	toast.add_theme_stylebox_override("panel", sb)
	add_child(toast)
	_ach_toast = toast

	# Erfolgs-Icon links (eigenes Icon-Font-Glyph aus GlobalModal – Quelle der Wahrheit für Icons).
	var ico := Label.new()
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ico.position = Vector2(12, 10)
	ico.size     = Vector2(40, 40)
	ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ico.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	ico.add_theme_font_size_override("font_size", 30)
	if Icons.FONT != null:
		ico.add_theme_font_override("font", Icons.FONT)
	ico.add_theme_color_override("font_color", C_ACCENT)
	ico.text = GlobalModal.icon_for_achievement(id)
	toast.add_child(ico)

	var cap := Label.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.position = Vector2(62, 11)
	cap.size     = Vector2(TW - 74, 16)
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", C_ACCENT)
	cap.text = "NEUER ERFOLG FREIGESCHALTET"
	toast.add_child(cap)

	var nm := Label.new()
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.position = Vector2(62, 27)
	nm.size     = Vector2(TW - 74, 22)
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", C_TEXT)
	nm.text = String(Economy.ACHIEVEMENTS.get(id, {}).get("name", id))
	toast.add_child(nm)

	# Einblenden (hochgleiten + einblenden), kurz halten, ausblenden, entfernen.
	var t := create_tween()
	t.tween_property(toast, "position:y", base_y, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(toast, "modulate:a", 1.0, 0.25)
	t.tween_interval(2.4)
	t.tween_property(toast, "modulate:a", 0.0, 0.45)
	t.tween_callback(toast.queue_free)
