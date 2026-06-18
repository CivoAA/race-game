extends CanvasLayer
## Fullscreen-Modal: Shop | Errungenschaften | Werkstatt.
## Autoload "GlobalModal" (layer 25, über GameHUD).
## process_mode ALWAYS damit es auch bei Pause funktioniert.

# Die Navigation liegt jetzt als dauerhafte Seitenleiste rechts (in GameHUD). Das Modal
# füllt nur den Bereich LINKS davon und beginnt unter der Top-Bar.
const TOP_H     = 50    # unter der GameHUD-Top-Bar
const BOT_H     = 42    # Höhe der unteren Run-Bar (bleibt frei → „Fahren" sichtbar)
const TAB_BAR_H = 48    # (Alt – Tab-Leiste entfernt, Konstante bleibt für Refs)

## Breite des Inhaltsbereichs (Viewport minus rechte Seitenleiste / Portrait: volle Breite)
func _vw() -> float: return RUI.content_w()

## Virtuelle Viewport-Höhe
func _vh() -> float: return RUI.vh()

# Discord-artige Graupalette – siehe GameHUD.gd (alle 6 Dateien synchron halten).
const C_BG        := Color(0.118, 0.122, 0.133)   # #1e1f22
const C_SURFACE   := Color(0.169, 0.176, 0.192)   # #2b2d31
const C_SURFACE2  := Color(0.220, 0.227, 0.251)   # #383a40
const C_ACCENT    := Color(0.345, 0.396, 0.949)   # #5865f2 Blurple
const C_ACCENT_MU := Color(0.290, 0.310, 0.490)
const C_ACCENT_RD := Color(0.929, 0.259, 0.271)   # #ed4245
const C_TEXT      := Color(0.859, 0.871, 0.882)   # #dbdee1
const C_TEXT_DIM  := Color(0.580, 0.608, 0.643)   # #949ba4
const C_LINE      := Color(0.247, 0.255, 0.278)   # #3f4147

# Reifen/Autos/Lackierung sind vorerst ausgeblendet (Platzhalter, noch nicht spielbar).
const SHOP_CATS = [
	{"id": "tiles",    "name": "Streckenteile", "icon": ""},
	{"id": "upgrades", "name": "Upgrades",      "icon": ""},
]
const MODAL_TABS = ["Shop", "Archivments", "Werkstatt", "Statistik", "Prestige", "Garage"]
const WERKSTATT_TAB = 2
const STATISTIK_TAB = 3
const PRESTIGE_TAB = 4
const GARAGE_TAB = 5

var _active_modal_tab: int = 0
var _active_shop_cat:  int = 0

var _modal_tab_btns:    Array[Button] = []
var _shop_sidebar_btns: Array[Button] = []   # Pillen des Shop-Umschalters oben (Streckenteile/Upgrades)
var _buy_mode_btn:      OptionButton  = null   # Kaufmenge-Dropdown („Einzeln/Max") rechts in der Shop-Nav
var _modal_money_lbl:   Label         = null   # Geldstand oben rechts in der Tab-Leiste

# Inhaltsbereiche (je ein Control, visible-Switching)
var _tab_panels:  Array[Control] = []
var _shop_cats:   Array[Control] = []

# Streckenteile-Tab: rotierende 3D-Vorschauen + Karten-Raster (für Neuaufbau nach Freischalten)
var _tile_preview_pivots: Array         = []   # Node3D-Pivots, drehen sich wenn der Tab sichtbar ist
# Vorschauen, die zyklisch durch mehrere Modelle wechseln (z. B. Tribüne durch alle Stapel-Stufen).
# Je Eintrag: {cam, model, pivot, parts:[Node3D...], idx:int, accum:float}.
var _tile_cyclers:        Array         = []
var _tiles_grid:          GridContainer = null
# true = das Karten-Raster muss neu gebaut werden (z. B. nach Speicherstand-Wechsel),
# weil dieser Autoload Szenenwechsel überlebt und Freischaltungen pro Slot gelten.
var _tiles_dirty:         bool          = false
# Freischalt-/Kauf-Buttons (nur noch nicht erworbene) für günstiges Nachfärben bei Geldänderung.
var _tile_buttons:        Array         = []   # je {btn, key}
var _tile_upgrade_buttons: Array        = []   # je {btn, id} – Upgrade-Buttons freigeschalteter Tiles
# Karten mit gestuftem Upgrade: {id, entry, desc, btn} – für In-Place-Aktualisierung beim
# Kauf, OHNE die rotierende 3D-Vorschau neu zu bauen (sonst springt die Drehung zurück).
var _tile_upgrade_cards:  Array         = []
var _upgrade_buttons:     Array         = []   # je {btn, id}
var _last_currency_seen:  float         = -1.0

# ── Upgrade-Hinweise (Tooltips) ──────────────────────────────────────────────────
# Hover über dem Upgrade-„Kästchen" (Name + Stufe, NICHT der Kauf-Button) blendet nach
# HINT_DELAY Sekunden einen Erklärtext ein (Texte aus dem Lang-Autoload). Erkennung per
# Polling in _process (get_global_rect), da mouse_entered/exited in den Containern unzuverlässig
# feuert. Ladekreis am Cursor (HintRing) als visuelles Feedback.
const HINT_DELAY := 2.5
var _hint_panel:   Panel    = null
var _hint_label:   Label    = null
var _hint_ring:    HintRing = null
var _hint_targets_upg:  Array = []   # Upgrade-Zeilen (Shop-Kat 1): je {"id": String, "area": Control}
var _hint_targets_tile: Array = []   # Streckenteil-Karten (Shop-Kat 0): je {"id": String, "area": Control}
var _hint_id:      String   = ""     # aktuell ANGEZEIGTER Hinweis ("" = keiner)
var _hover_id:     String   = ""     # aktuell überfahrenes Kästchen (Hover-Akkumulation)
var _hover_elapsed: float   = 0.0
var _needs_rebuild: bool    = false  # Viewport hat sich geändert → Modal beim nächsten Frame neu aufbauen

# ── Prestige-Tab ────────────────────────────────────────────────────────────────
var _prestige_tree_box:   HBoxContainer = null   # Knoten-Karten (links → rechts), für Neuaufbau
var _prestige_points_lbl: Label         = null   # Kopf oben links: „N Prestiges durchgeführt"
var _prestige_btn:        Button        = null   # Fortschritts-Button „PRESTIGE → +N ⭐"
var _prestige_fill:       ColorRect      = null   # Fortschrittsfüllung (Shader: Form + Reveal + Effekt)
var _prestige_fill_mat:   ShaderMaterial = null   # Material der Füllung (progress/mode/base_color)
var _prestige_btn_lbl:    Label          = null   # Text-Overlay über der Füllung

# EIN Shader rendert Form (runde Ecken via SDF), Füllstand (links→rechts) und den animierten Effekt.
# Aktiv genutzt: 0 Einfarbig (= Performance-Modus, keine Animation) und 5 Glitzer+Wasser (Standard).
# Der Modus wird in _refresh_prestige_action aus Display.performance_mode abgeleitet. Die übrigen
# Effekte (1 Streifen · 2 Glitzer · 3 Wasser · 4 Streifen+Glitzer) bleiben als wiederverwendbare
# Bausteine erhalten, werden aktuell aber nicht ausgewählt.
const PRESTIGE_FILL_SHADER := """
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2  size_px = vec2(360.0, 56.0);
uniform float radius_px = 8.0;
uniform vec4  base_color : source_color = vec4(0.74, 0.48, 0.97, 0.85);
uniform int   mode = 2;

float rrect_sd(vec2 p, vec2 hs, float r) {
	vec2 q = abs(p) - hs + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Diagonale, wandernde Streifen.
vec3 shade_stripes(vec3 base, vec2 px, float t) {
	float s = sin((px.x + px.y - t * 42.0) * 0.20) * 0.5 + 0.5;
	float stripe = smoothstep(0.1, 0.9, s);
	return mix(base * 0.65, base * 1.35, stripe);
}

// Funkelnde Zellen + sanfter Sheen-Lauf – ADDITIV (zum Drauflegen auf andere Effekte).
vec3 glitter_add(vec3 base, vec2 px, float t) {
	vec3 add = vec3(0.0);
	vec2 cell = floor(px / 4.0);
	float tw = hash21(cell);
	float spark = pow(max(0.0, sin(t * 2.2 + tw * 6.2831)), 28.0);
	spark *= step(0.55, hash21(cell + 7.3));
	add += vec3(1.0, 0.96, 0.75) * spark * 1.6;
	float sheen = sin((px.x - t * 70.0) * 0.035) * 0.5 + 0.5;
	add += base * sheen * 0.18;
	return add;
}

// „Gedrehtes" Wasser: Oberfläche = rechte (Füllstands-)Kante. Hell rechts → dunkler nach links,
// vertikal wandernde Wellen, helle Oberkante ein paar Pixel INNERHALB der Kante (sonst unsichtbar).
vec3 shade_water(vec3 base, vec2 px, float fillX, vec2 sz, float t) {
	float depth = clamp((fillX - px.x) / max(1.0, sz.x), 0.0, 1.0);
	vec3 col = mix(base * 1.18, base * 0.55, depth);
	float r1 = sin(px.y * 0.5 + t * 2.5) * 0.5 + 0.5;
	float r2 = sin(px.y * 0.27 - t * 1.7 + px.x * 0.05) * 0.5 + 0.5;
	col += base * r1 * r2 * 0.15;
	float d = fillX - px.x;
	float crest = smoothstep(2.0, 5.0, d) * (1.0 - smoothstep(5.0, 12.0, d));
	col += vec3(1.0, 1.0, 0.92) * crest * 0.6;
	return col;
}

void fragment() {
	vec2 px = UV * size_px;
	float sd = rrect_sd(px - size_px * 0.5, size_px * 0.5, radius_px);
	float shape = 1.0 - smoothstep(-1.0, 1.0, sd);
	float fillX = progress * size_px.x;
	float reveal = 1.0 - smoothstep(fillX - 1.5, fillX + 0.5, px.x);
	float a = shape * reveal;
	if (a <= 0.001) {
		discard;
	}
	vec3 base = base_color.rgb;
	vec3 col = base;
	if (mode == 1) {
		col = shade_stripes(base, px, TIME);
	} else if (mode == 2) {
		col = base + glitter_add(base, px, TIME);
	} else if (mode == 3) {
		col = shade_water(base, px, fillX, size_px, TIME);
	} else if (mode == 4) {
		col = shade_stripes(base, px, TIME) + glitter_add(base, px, TIME);
	} else if (mode == 5) {
		col = shade_water(base, px, fillX, size_px, TIME) + glitter_add(base, px, TIME);
	}
	COLOR = vec4(col, base_color.a * a);
}
"""
var _prestige_confirm:    Control       = null   # Bestätigungs-Overlay
var _prestige_confirm_lbl: Label        = null
var _ascend_confirm:      Control       = null   # Auto-Prestige-Bestätigung (Werkstatt)
var _ascend_confirm_lbl:  Label         = null
var _cosmetic_confirm:     Control       = null   # Kauf-Bestätigung für Garage-Kosmetik (Farbe/Muster)
var _cosmetic_confirm_lbl: RichTextLabel = null
var _cosmetic_yes_btn:     Button        = null   # „Kaufen"-Knopf (ausgegraut bei zu wenig Trophäen)
var _cosmetic_pending_cat: String        = ""     # "paint" | "pattern" – was gerade bestätigt wird
var _cosmetic_pending_idx: int           = -1

# Sperr-Overlay für noch nicht freigeschaltete Tabs (Prestige/Werkstatt). Liegt über dem
# Inhalt und zeigt nur ein Schloss + Hinweistext. TEMP: Freischalt-Bedingung kommt aus
# Economy.is_*_tab_unlocked – sobald es einen Erfolge-Tab gibt, von dort aus speisen.
var _lock_overlay:  Control = null
var _lock_hint_lbl: Label   = null


func _ready() -> void:
	layer        = 25
	visible      = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_modal()
	_build_hint_overlay()
	GameHUD.shop_requested.connect(open)
	Economy.slot_changed.connect(_on_slot_changed)
	Economy.prestige_changed.connect(_rebuild_prestige)
	RUI.layout_changed.connect(_on_layout_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)
	Economy.tab_unlock_changed.connect(_on_tab_unlock_changed)
	Economy.achievement_unlocked.connect(_on_achievement_unlocked)
	Economy.achievement_claimed.connect(_on_achievement_unlocked)   # Trophäen-/Erfolgs-Anzeige mitziehen


# Auflösungs-/Layout-Änderung IMMER vormerken – auch wenn das Modal gerade
# geschlossen ist (typisch: Auflösung im Menü ändern, danach erst öffnen).
# Sichtbar → im nächsten Frame neu bauen (_process); geschlossen → beim nächsten open().
func _on_layout_changed(_l) -> void:
	_needs_rebuild = true


func _on_viewport_resized() -> void:
	_needs_rebuild = true


func _do_rebuild() -> void:
	var saved_tab := _active_modal_tab

	# 3D-Vorschau aus ihrem Container herauslösen, damit sie das free() überlebt.
	if _preview_svc != null and is_instance_valid(_preview_svc):
		var prev_parent := _preview_svc.get_parent()
		if prev_parent != null:
			prev_parent.remove_child(_preview_svc)

	# Alle Kinder sofort freigeben (nicht queue_free, damit _build_modal sofort neue anlegen kann).
	for child in get_children():
		child.free()

	# UI-Referenzen zurücksetzen (Node-Zeiger ungültig nach free()).
	_tab_panels.clear();   _shop_cats.clear();       _modal_tab_btns.clear()
	_shop_sidebar_btns.clear()
	_modal_money_lbl        = null
	_werkstatt_container    = null;  _garage_container    = null
	_prestige_tree_box      = null;  _prestige_points_lbl = null
	_prestige_btn           = null;  _prestige_btn_lbl    = null
	_prestige_fill          = null;  _prestige_fill_mat   = null
	_prestige_confirm       = null;  _prestige_confirm_lbl = null
	_ascend_confirm         = null;  _ascend_confirm_lbl  = null
	_cosmetic_confirm       = null;  _cosmetic_confirm_lbl = null
	_cosmetic_yes_btn       = null
	_cosmetic_pending_cat   = "";    _cosmetic_pending_idx = -1
	_lock_overlay           = null;  _lock_hint_lbl       = null
	_ws_options_box         = null;  _ws_summary_lbl      = null
	_garage_options_box     = null;  _garage_summary_lbl  = null
	_garage_trophy_lbl      = null;  _test_car_btn        = null
	_garage_tab_btns.clear(); _garage_active_tab = 0
	_statistik_vbox         = null;  _stat_value_lbls.clear()
	_tile_preview_pivots.clear();    _tile_cyclers.clear();   _tiles_grid = null
	_tile_buttons.clear();  _tile_upgrade_buttons.clear()
	_tile_upgrade_cards.clear();     _upgrade_buttons.clear()
	_ach_data.clear();      _ach_tiles.clear();       _ach_selected = -1
	_ach_icon_lbl = null;   _ach_title_lbl = null;   _ach_status_lbl = null
	_ach_desc_lbl = null;   _ach_progress_lbl = null
	_ach_claim_btn = null;  _ach_claim_sb = null
	_hint_panel = null;     _hint_label = null;      _hint_ring = null
	_hint_targets_upg.clear();       _hint_targets_tile.clear()
	_hint_id = "";          _hover_id = "";           _hover_elapsed = 0.0
	_last_currency_seen = -1

	_build_modal()
	_build_hint_overlay()
	_show_modal_tab(saved_tab)
	_refresh_affordability()


func _on_slot_changed(_slot: int) -> void:
	_tiles_dirty = true


func open() -> void:
	# Hat sich die Auflösung/das Layout geändert, während das Modal geschlossen war,
	# JETZT mit den aktuellen Viewport-Maßen neu aufbauen – sonst stünden Container &
	# Seitenleiste bis zum nächsten Resize versetzt zueinander.
	if _needs_rebuild:
		_needs_rebuild = false
		_do_rebuild()
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
	_refresh_statistik()  # Statistik-Werte (Geld/Prestige/Strecken …) frisch anzeigen
	_refresh_achievements()  # Erfolge-done-Status (slot-gebunden) frisch anzeigen
	_refresh_werkstatt()  # Auto-Stufe/Lack/Muster könnten sich geändert haben (Vorschau ggf. neu)
	_refresh_modal_money()
	visible = true


# Öffnet das Modal direkt auf einem bestimmten Tab (von der rechten Seitenleiste in GameHUD).
func open_tab(idx: int) -> void:
	open()
	_on_modal_tab(idx)


# Aktuellen Geldstand in der Tab-Leiste (oben rechts) aktualisieren.
func _refresh_modal_money() -> void:
	if _modal_money_lbl != null:
		_modal_money_lbl.text = "%s  %s" % [Icons.COIN, Economy.format_currency(Economy.get_currency())]


# Färbt alle noch kaufbaren Buttons (Streckenteile + Upgrades) nach dem aktuellen Geldstand.
func _refresh_affordability() -> void:
	_refresh_tile_buttons()
	_refresh_upgrade_buttons()


func close() -> void:
	visible = false
	_clear_upgrade_hover()
	# Seitenleiste (GameHUD) markiert keinen Eintrag mehr als aktiv.
	GameHUD._on_modal_closed()


func _process(delta: float) -> void:
	if _needs_rebuild and visible:
		_needs_rebuild = false
		_do_rebuild()
		return
	if not visible:
		return
	# Vorschau-Auto langsam drehen, solange die Werkstatt sichtbar ist
	if (_active_modal_tab == WERKSTATT_TAB or _active_modal_tab == GARAGE_TAB) and _preview_pivot != null:
		_preview_pivot.rotate_y(delta * 0.6)
	# Streckenteil-Vorschauen drehen, solange der Streckenteile-Tab sichtbar ist. Im Performance-Modus
	# bleiben sie statisch stehen (keine Drehung, kein Durchwechseln der Modelle), spart Last.
	elif _active_modal_tab == 0 and _active_shop_cat == 0 and not Display.performance_mode:
		for p in _tile_preview_pivots:
			if is_instance_valid(p):
				p.rotate_y(delta * 0.6)
		_advance_tile_cyclers(delta)

	# Kauf-Buttons (Streckenteile + Upgrades) live nachfärben, sobald sich der Geldstand
	# ändert. Läuft nur, solange das Upgrade-Center offen ist (oben steht `if not visible:
	# return`) und färbt nur um – daher kein Lag im normalen Spiel.
	var cur := Economy.get_currency()
	if cur != _last_currency_seen:
		_last_currency_seen = cur
		_refresh_affordability()
		_refresh_modal_money()

	# Hinweis-„Rad": nur im Shop-Tab (Streckenteile = Kat 0, Upgrades = Kat 1) UND wenn in den
	# Einstellungen aktiviert (Standard an). Sonst ausblenden / nicht aufladen.
	if _active_modal_tab == 0 and Display.shop_hints:
		_update_upgrade_hint(delta)
	elif _hint_id != "" or _hover_id != "":
		_clear_upgrade_hover()

	# Prestige-Tab: Vorschau-Zahl („+N ⭐") live mitziehen, während im Hintergrund Geld reinkommt.
	if _active_modal_tab == PRESTIGE_TAB:
		_refresh_prestige_action()

	# Statistik-Tab: Werte (v. a. Spielzeit) in Echtzeit weiterticken.
	if _active_modal_tab == STATISTIK_TAB:
		_tick_statistik()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# Sprachwechsel zur Laufzeit: Modal-Panels werden einmal gebaut und danach nur ein-/ausgeblendet.
# Statisch gesetzte (selbst per tr() übersetzte) Texte hier neu setzen; dynamische Inhalte über die
# vorhandenen Refresh-Funktionen (alle mit Null-Guard, also auch vor dem Bau unkritisch).
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED:
		return
	if _ws_title_lbl != null and is_instance_valid(_ws_title_lbl):
		_ws_title_lbl.text = "%s  %s" % [Icons.CAR, tr("Auto-Aufstieg")]
	if not _garage_tab_btns.is_empty():
		var gtabs := _garage_tabs()
		for i in _garage_tab_btns.size():
			if i < gtabs.size() and is_instance_valid(_garage_tab_btns[i]):
				_garage_tab_btns[i].text = "%s  %s" % [gtabs[i].icon, tr(gtabs[i].name)]
	_update_test_car_btn()
	_refresh_werkstatt()
	_refresh_achievements()
	_refresh_prestige_action()


func _build_modal() -> void:
	# Abdunkelung und Panel über dem Spielbereich (links der Sidebar, unter Top-Bar,
	# über der Run-Bar). Anker-basiert → passt sich automatisch an Viewport-Änderungen an.
	var area_h := _vh() - TOP_H - BOT_H

	var dim := ColorRect.new()
	# Anker: oben bei TOP_H, unten -BOT_H, rechts -RUI.nav_w() (Portrait: 0), links 0
	dim.anchor_left   = 0.0; dim.offset_left   = 0
	dim.anchor_top    = 0.0; dim.offset_top    = TOP_H
	dim.anchor_right  = 1.0; dim.offset_right  = -RUI.nav_w()
	dim.anchor_bottom = 1.0; dim.offset_bottom = -(BOT_H + RUI.nav_h())
	dim.color        = Color(0, 0, 0, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Panel.new()
	panel.anchor_left   = 0.0; panel.offset_left   = 0
	panel.anchor_top    = 0.0; panel.offset_top    = TOP_H
	panel.anchor_right  = 1.0; panel.offset_right  = -RUI.nav_w()
	panel.anchor_bottom = 1.0; panel.offset_bottom = -(BOT_H + RUI.nav_h())
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_BG
	ps.set_border_width_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	# Inhaltsbereiche füllen das ganze Panel – navigiert wird über die rechte Seitenleiste.
	# Geschlossen wird über „Strecke" in der Nav, erneuten Klick auf die aktive Seite oder ESC.
	const CONTENT_Y = 0

	_build_shop_panel(panel,           CONTENT_Y, area_h)   # Tab 0
	_build_achievements_panel(panel,   CONTENT_Y, area_h)   # Tab 1
	_build_werkstatt_panel(panel,      CONTENT_Y, area_h)   # Tab 2
	_build_statistik_panel(panel,      CONTENT_Y, area_h)   # Tab 3
	_build_prestige_panel(panel,       CONTENT_Y, area_h)   # Tab 4
	_build_garage_panel(panel,         CONTENT_Y, area_h)   # Tab 5

	_build_prestige_confirm(panel)
	_build_ascend_confirm(panel)
	_build_cosmetic_confirm(panel)
	_build_lock_overlay(panel)   # zuletzt → liegt über dem Inhalt der gesperrten Tabs

	_show_modal_tab(0)


# Vollflächiges Sperr-Overlay (Schloss + Hinweis) für noch nicht freigeschaltete Tabs. Wird in
# _show_modal_tab je nach aktivem Tab ein-/ausgeblendet; Anker-basiert → resize-fest.
func _build_lock_overlay(parent: Control) -> void:
	_lock_overlay = Control.new()
	_lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_overlay.visible = false
	parent.add_child(_lock_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # blockt Klicks auf den dahinterliegenden Inhalt
	_lock_overlay.add_child(bg)

	var icon := Label.new()
	icon.anchor_left = 0.0; icon.anchor_right = 1.0
	icon.anchor_top  = 0.5; icon.anchor_bottom = 0.5
	icon.offset_top  = -86; icon.offset_bottom = -22
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 56)
	if Icons.FONT != null:
		icon.add_theme_font_override("font", Icons.FONT)
	icon.add_theme_color_override("font_color", C_TEXT_DIM)
	icon.text = Icons.LOCK
	_lock_overlay.add_child(icon)

	var title := Label.new()
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.anchor_top  = 0.5; title.anchor_bottom = 0.5
	title.offset_top  = -14; title.offset_bottom = 20
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_TEXT)
	title.text = "Gesperrt"
	_lock_overlay.add_child(title)

	_lock_hint_lbl = Label.new()
	_lock_hint_lbl.anchor_left = 0.0; _lock_hint_lbl.anchor_right = 1.0
	_lock_hint_lbl.anchor_top  = 0.5; _lock_hint_lbl.anchor_bottom = 0.5
	_lock_hint_lbl.offset_top  = 28;  _lock_hint_lbl.offset_bottom = 96
	_lock_hint_lbl.offset_left = 24;  _lock_hint_lbl.offset_right = -24
	_lock_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_hint_lbl.add_theme_font_size_override("font_size", 14)
	_lock_hint_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	_lock_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lock_overlay.add_child(_lock_hint_lbl)


# ── Modal-Tab-Switching ────────────────────────────────────────────────────────
# Tabs werden über die rechte Seitenleiste (GameHUD) angesteuert – hier nur das
# Umschalten des sichtbaren Inhalts + passender Refresh.

func _on_modal_tab(idx: int) -> void:
	_active_modal_tab = idx
	_clear_upgrade_hover()   # Tab-Wechsel → offenen Hinweis/Ring sofort ausblenden
	_show_modal_tab(idx)
	_refresh_affordability()
	if idx == PRESTIGE_TAB:
		_rebuild_prestige()
	elif idx == STATISTIK_TAB:
		_refresh_statistik()


func _show_modal_tab(idx: int) -> void:
	for i in _tab_panels.size():
		_tab_panels[i].visible = (i == idx)
	# Gesperrte Tabs (Prestige/Werkstatt vor Freischaltung): Inhalt durch das Schloss-Overlay
	# verdecken und hier nichts weiter aufbauen.
	var locked := _is_tab_locked(idx)
	if _lock_overlay != null:
		_lock_overlay.visible = locked
		if locked:
			_lock_hint_lbl.text = _tab_lock_hint(idx)
	if locked:
		return
	# Die gemeinsame 3D-Auto-Vorschau in den gerade sichtbaren Tab (Werkstatt/Garage) umhängen.
	if idx == WERKSTATT_TAB:
		_attach_preview_to(_werkstatt_container)
		_apply_ws_config()
	elif idx == GARAGE_TAB:
		_attach_preview_to(_garage_container)
		_apply_ws_config()


# TEMP: Tab gesperrt? (Prestige/Werkstatt bis zur Verdienst-Schwelle). Sobald es einen Erfolge-Tab
# gibt, leitet sich is_*_tab_unlocked von dort ab – diese Abfrage bleibt unverändert.
func _is_tab_locked(idx: int) -> bool:
	if idx == PRESTIGE_TAB:  return not Economy.is_prestige_tab_unlocked()
	if idx == WERKSTATT_TAB: return not Economy.is_werkstatt_tab_unlocked()
	return false


func _tab_lock_hint(idx: int) -> String:
	# Namen bewusst NICHT nennen, solange gesperrt – nur die Verdienst-Schwelle als Hinweis.
	if idx == PRESTIGE_TAB:
		return "Verdiene 100K (seit dem letzten Prestige), um diesen Bereich dauerhaft freizuschalten."
	if idx == WERKSTATT_TAB:
		return "Sammle 1.000.000 Prestige-Punkte (⭐), um diesen Bereich dauerhaft freizuschalten."
	return ""


# Ein Tab wurde live freigeschaltet → falls er gerade offen ist, Sperre sofort entfernen.
func _on_tab_unlock_changed() -> void:
	if visible:
		_show_modal_tab(_active_modal_tab)


# Hängt das gemeinsame Vorschau-SubViewport in den angegebenen Tab-Container (gleiche Position).
func _attach_preview_to(container: Control) -> void:
	if _preview_svc == null or not is_instance_valid(_preview_svc) or container == null:
		return
	var cur := _preview_svc.get_parent()
	if cur == container:
		return
	if cur != null:
		cur.remove_child(_preview_svc)
	container.add_child(_preview_svc)
	_preview_svc.position = Vector2(_preview_x(), PREVIEW_Y)
	_preview_svc.size     = Vector2(PREVIEW_W, PREVIEW_H)
	# In der Garage ggf. nach links rücken (Muster-Tab: Platz für die Muster-Farbauswahl rechts).
	if container == _garage_container:
		_layout_garage_preview()


# ── Shop ──────────────────────────────────────────────────────────────────────

const SHOP_NAV_H = 46   # Höhe der durchgehenden Top-Nav-Leiste im Shop

func _build_shop_panel(parent: Control, cy: int, ch: int) -> void:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(container)
	_tab_panels.append(container)

	# Durchgehende Top-Nav-Leiste über die volle Breite (von ganz links bis zur Menü-Nav rechts).
	# Ersetzt die frühere linke Sidebar – der Inhalt darunter nutzt ebenfalls die volle Breite.
	var navbar := ColorRect.new()
	navbar.position = Vector2(0, 0)
	navbar.size     = Vector2(_vw(), SHOP_NAV_H)
	navbar.color    = C_SURFACE
	container.add_child(navbar)

	# Reiter links in der Leiste (flächenbündig, aktiver mit Akzent-Unterstrich). Mit Icon je Reiter.
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(0, 0)
	tabs.add_theme_constant_override("separation", 0)
	container.add_child(tabs)

	for i in SHOP_CATS.size():
		var cat  = SHOP_CATS[i]
		var btn  := Button.new()
		btn.text = "%s   %s" % [_shop_cat_icon(cat.id), tr(cat.name)]
		btn.custom_minimum_size = Vector2(0, SHOP_NAV_H)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_shop_toggle(btn, i == 0)
		btn.pressed.connect(_on_shop_cat.bind(i))
		tabs.add_child(btn)
		_shop_sidebar_btns.append(btn)

	# Kaufmenge-Umschalter („Einzeln" / „Max") rechtsbündig in der Nav-Leiste – gilt für BEIDE
	# Shop-Kategorien (Streckenteile-Upgrades + allgemeine Upgrades), da er in der gemeinsamen
	# Leiste sitzt. „Max" kauft beim Klick auf einen Upgrade-Knopf so viele Stufen wie mit dem
	# aktuellen Geld möglich (siehe Economy.buy_upgrade_max / max_affordable_info).
	var mode_lbl := Label.new()
	mode_lbl.anchor_left  = 1.0; mode_lbl.offset_left  = -300
	mode_lbl.anchor_right = 1.0; mode_lbl.offset_right = -150
	mode_lbl.offset_top   = 0;   mode_lbl.offset_bottom = SHOP_NAV_H
	mode_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	mode_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mode_lbl.add_theme_font_size_override("font_size", 13)
	mode_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	mode_lbl.text = tr("Kaufmenge")
	container.add_child(mode_lbl)

	var mode_opt := OptionButton.new()
	mode_opt.anchor_left  = 1.0; mode_opt.offset_left  = -142
	mode_opt.anchor_right = 1.0; mode_opt.offset_right = -12
	mode_opt.offset_top   = 7;   mode_opt.offset_bottom = SHOP_NAV_H - 7
	mode_opt.focus_mode = Control.FOCUS_NONE
	mode_opt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mode_opt.add_theme_font_size_override("font_size", 13)
	mode_opt.add_item(tr("Einzeln"), 0)
	mode_opt.add_item(tr("Max"), 1)
	mode_opt.select(1 if Economy.buy_max_mode else 0)
	mode_opt.item_selected.connect(_on_buy_mode_selected)
	container.add_child(mode_opt)
	_buy_mode_btn = mode_opt

	# Untere Trennlinie der Nav-Leiste
	var sline := ColorRect.new()
	sline.position = Vector2(0, SHOP_NAV_H)
	sline.size     = Vector2(_vw(), 1)
	sline.color    = C_LINE
	container.add_child(sline)

	# Inhaltsbereiche je Kategorie – volle Breite, beginnend unter der Nav-Leiste.
	# Nur Streckenteile (0) + Upgrades (1). Reifen/Autos/Lackierung sind ausgeblendet.
	_build_cat_tiles(container, 0, ch, _vw(), SHOP_NAV_H + 1)
	_build_cat_upgrades(container, 0, ch, _vw(), SHOP_NAV_H + 1)

	_show_shop_cat(0)


func _on_shop_cat(idx: int) -> void:
	_active_shop_cat = idx
	_clear_upgrade_hover()   # andere Kategorie → andere Ziel-Liste, offenen Hinweis verwerfen
	for i in _shop_sidebar_btns.size():
		_style_shop_toggle(_shop_sidebar_btns[i], i == idx)
	_show_shop_cat(idx)
	_refresh_affordability()


func _show_shop_cat(idx: int) -> void:
	for cat in _shop_cats:
		cat.visible = false
	if idx < _shop_cats.size():
		_shop_cats[idx].visible = true


# Kaufmenge-Dropdown umgestellt (0 = Einzeln, 1 = Max). Beide Kategorien neu beschriften, damit
# die Kauf-Knöpfe sofort die Einzelstufe bzw. die „+N · Gesamtkosten"-Vorschau zeigen.
func _on_buy_mode_selected(idx: int) -> void:
	Economy.buy_max_mode = (idx == 1)
	_refresh_affordability()
	if _active_shop_cat == 1:
		_rebuild_shop_upgrades()


# Beschriftung eines Kauf-Knopfs je nach Kaufmenge-Modus. „Max" zeigt, wie viele Stufen mit dem
# aktuellen Geld auf einmal gekauft würden (+N) und deren Gesamtkosten; sind 0/1 Stufen leistbar,
# fällt die Anzeige auf den Einzelkauf zurück. `with_stufe` → Einzelmodus nennt zusätzlich die
# Zielstufe (Streckenteil-Karten), sonst nur den Preis (allgemeine Upgrade-Karten).
func _buy_label(id: String, with_stufe: bool) -> String:
	if Economy.buy_max_mode:
		var info := Economy.max_affordable_info(id)
		if int(info["count"]) >= 2:
			return Icons.ARROW_UP + (tr("  +%d Stufen  ·  %s %s") % [int(info["count"]), Economy.format_currency(int(info["cost"])), Icons.COIN])
	if with_stufe:
		return Icons.ARROW_UP + (tr(" Stufe %d  ·  %s %s") % [Economy.get_upgrade_level(id) + 1, Economy.format_currency(Economy.get_upgrade_cost(id)), Icons.COIN])
	return Icons.ARROW_UP + "  %s %s" % [Economy.format_currency(Economy.get_upgrade_cost(id)), Icons.COIN]


# Setzt Text + passende Schriftgröße eines Kauf-Knopfs. clip_text ist die harte Grenze: lange
# „Max"-Beschriftungen (große Stufenzahlen/Beträge) lassen den Knopf NIE über die Kartenbreite
# hinaus wachsen oder verschieben. Passt der Text nicht, wird die Schrift stufenweise verkleinert
# (bis min. 9) statt den Knopf zu vergrößern. Im Einzelmodus bleibt die Basis-Schriftgröße.
func _set_buy_btn_label(btn: Button, id: String, with_stufe: bool, base_size: int) -> void:
	var txt := _buy_label(id, with_stufe)
	btn.clip_text = true
	btn.text = txt
	var avail := btn.size.x - 14.0
	var font := btn.get_theme_font("font")
	var fs := base_size
	while fs > 9:
		var w := 0.0
		if font != null:
			w = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		else:
			w = float(txt.length()) * (float(fs) * 0.55)
		if w <= avail:
			break
		fs -= 1
	btn.add_theme_font_size_override("font_size", fs)


# ── Streckenteile-Katalog ───────────────────────────────────────────────────────
# Werkstatt-Stil: pro Tile eine rotierende 3D-Vorschau + Freischalt-Button darunter.
# key/cost werden aus Economy.TILE_UNLOCK_COST gezogen (gemeinsame Quelle mit Main.gd).
#   key ""       → kostenlos/immer freigeschaltet (Dreck-Tiles)
#   model ""     → noch kein eigenes 3D-Modell → Default-Strecke unter schwarzem Film
#   film true    → Modell vorhanden, aber als Platzhalter abgedunkelt
#   coming true  → noch nicht verfügbar (Button deaktiviert)
func _tile_entries() -> Array:
	return [
		{"name": "Erd-Gerade",  "key": "",            "model": Paths.MODEL_TRACK_STRAIGHT_DIRT,    "desc": "+1 Ertrag · frei", "upgrade": "dirtstraightbonus", "field_earn_base": 1},
		{"name": "Erd-Kurve",   "key": "",            "model": Paths.MODEL_TRACK_CURVE_DIRT,       "desc": "+1 Ertrag · frei", "upgrade": "dirtcurvebonus", "field_earn_base": 1},
		# Sand: günstigste bezahlte Strecke (+15, eigene additive Upgrades) – zwischen Dreck und Eis/Default.
		{"name": "Sand-Gerade",   "key": "sand_straight", "model": Paths.MODEL_TRACK_STRAIGHT_SAND,  "desc": "+15 Ertrag", "upgrade": "sandstraightbonus", "field_earn_base": 15},
		{"name": "Sand-Kurve",    "key": "sand_curve",    "model": Paths.MODEL_TRACK_CURVE_SAND,     "desc": "+15 Ertrag", "upgrade": "sandcurvebonus", "field_earn_base": 15},
		# Eis: EIN Eintrag schaltet Gerade + Kurve frei und führt das gemeinsame Upgrade (icebonus).
		# Direkt hinter Sand, da der Freischaltpreis (25k) preislich dazwischen passt.
		{"name": "Eis (Gerade + Kurve)", "key": "ice", "model": Paths.MODEL_TRACK_STRAIGHT_ICE,     "desc": "Speed-Boost · kein Geld", "upgrade": "icebonus", "field_earn_base": 0},
		{"name": "Straßen-Gerade", "key": "def_straight","model": Paths.MODEL_TRACK_STRAIGHT_DEFAULT, "desc": "+150 Ertrag", "upgrade": "straightbonus", "field_earn_base": 150},
		{"name": "Straßen-Kurve",  "key": "def_curve",   "model": Paths.MODEL_TRACK_CURVE_DEFAULT,    "desc": "+150 Ertrag", "upgrade": "curvebonus", "field_earn_base": 150},
		{"name": "Rennstrecke",  "key": "race_straight","model": Paths.MODEL_TRACK_STRAIGHT_RACING,  "desc": "+1000 Ertrag · ×1.2", "upgrade": "racestraightbonus", "field_earn_base": 1000},
		{"name": "Rennkurve",    "key": "race_curve",  "model": Paths.MODEL_TRACK_CURVE_RACING,     "desc": "+1000 Ertrag · ×1.2", "upgrade": "racecurvebonus", "field_earn_base": 1000},
		{"name": "Rampe",        "key": "ramp",        "model": Paths.MODEL_TRACK_RAMP,              "desc": "Sprung ×2 · Kreuzung", "upgrade": "rampbonus", "field_earn_base": int(Economy.RAMP_BASE_EARN)},
		{"name": "Steilwandkurve","key": "wall",       "model": Paths.MODEL_TRACK_WALL,             "desc": "180°-Wall-Ride · Geld + Speed", "upgrade": "wallbonus", "field_earn_base": 0},
		{"name": "Looping",      "key": "loop",        "model": Paths.MODEL_TRACK_LOOP,             "desc": "×2 · verdoppelt andere ×", "upgrade": "loopbonus", "field_earn_base": 0},
		# Portal = zwei GLBs auf EINER Kachel (Rampe + blaues Tor) → als Modell-Liste in der Vorschau.
		{"name": "Portal",       "key": "portal",      "model": Paths.MODEL_TRACK_PORTAL_RAMP,      "models": [Paths.MODEL_TRACK_PORTAL_RAMP, Paths.MODEL_TRACK_PORTAL_BLUE], "desc": "Teleport · +25k /Durchgang", "upgrade": "portalbonus", "field_earn_base": 0},
		# Tribüne: im Spiel stapelbar (Stand1..4) → die Vorschau wechselt zyklisch durch alle Stufen.
		{"name": "Tribüne",      "key": "stand",       "model": Paths.stand_model(1), "models": Paths.MODEL_TRACK_STANDS, "cycle": true, "desc": "×2.5 Nachbarfeld · stapelbar", "upgrade": "standbonus", "field_earn_base": 0},
		# Test-Beläge (Wasser/Kleber): nur die neuen 3D-Assets zum Ausprobieren, vorerst ohne
		# Ökonomie-Effekt. Freischaltkosten 1 (Economy.TILE_UNLOCK_COST), kein Upgrade.
		{"name": "Wasser-Gerade", "key": "water_straight","model": Paths.MODEL_TRACK_STRAIGHT_WATER, "desc": "Test · noch kein Effekt", "upgrade": "", "field_earn_base": 0},
		{"name": "Wasser-Kurve",  "key": "water_curve",   "model": Paths.MODEL_TRACK_CURVE_WATER,    "desc": "Test · noch kein Effekt", "upgrade": "", "field_earn_base": 0},
		{"name": "Kleber-Gerade", "key": "glue_straight", "model": Paths.MODEL_TRACK_STRAIGHT_GLUE,  "desc": "Test · noch kein Effekt", "upgrade": "", "field_earn_base": 0},
		{"name": "Kleber-Kurve",  "key": "glue_curve",    "model": Paths.MODEL_TRACK_CURVE_GLUE,     "desc": "Test · noch kein Effekt", "upgrade": "", "field_earn_base": 0},
	]


func _build_cat_tiles(parent: Control, x: int, h: int, w: int, top: int = 0) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x, top)
	scroll.size     = Vector2(w, h - top)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_shop_cats.append(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(w - 20, 0)
	vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(vbox)

	# Kein Info-Text und kein eigener „STRECKENTEILE"-Header mehr – die aktive Toggle-Pille oben
	# ist der Titel. Die Karten mit ihrer 3D-Vorschau sprechen für sich.
	var htop := Control.new()
	htop.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(htop)

	# Karten-Raster horizontal ZENTRIERT (CenterContainer) statt linksbündig – die Karten sitzen
	# mittig im verfügbaren Platz, egal wie viele Spalten gerade passen.
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(center)

	_tiles_grid = GridContainer.new()
	# Spaltenzahl responsiv aus der verfügbaren Breite (Karte 174 + 12 Abstand, 16er-Ränder).
	# Da der Shop jetzt die volle Breite nutzt, passen meist 4–5 Karten statt vorher 3.
	_tiles_grid.columns = clampi(int((w - 32 + 12) / (174 + 12)), 3, 5)
	_tiles_grid.add_theme_constant_override("h_separation", 12)
	_tiles_grid.add_theme_constant_override("v_separation", 12)
	center.add_child(_tiles_grid)

	_populate_tiles_grid()

	var bpad := Control.new()
	bpad.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(bpad)


func _populate_tiles_grid() -> void:
	if _tiles_grid == null:
		return
	_tile_preview_pivots.clear()
	_tile_cyclers.clear()
	_tile_buttons.clear()
	_tile_upgrade_buttons.clear()
	_tile_upgrade_cards.clear()
	# Hover-Ziele zeigen auf die gleich freigegebenen Karten → Liste + offenen Hinweis verwerfen.
	_hint_targets_tile.clear()
	_clear_upgrade_hover()
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
	# Manche Tiles (Portal) bestehen aus mehreren GLBs auf einer Kachel → "models"-Liste bevorzugen,
	# sonst das einzelne Modell (Fallback: Default-Strecke unter Film, wenn keins gesetzt ist).
	var show_models: Array = entry.get("models", [])
	if show_models.is_empty():
		show_models = [model] if model != "" else [Paths.MODEL_TRACK_STRAIGHT_DEFAULT]

	_build_tile_preview(card, CARD_PREV_POS, CARD_PREV_SZ, show_models, entry.get("cycle", false))

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
	if has_upg:
		desc_lbl.text = _tile_upgrade_desc(upg_id, entry)
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
		btn.text     = Icons.CHECK + " Freigeschaltet"
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(Color(0.10, 0.26, 0.15), Color(0.30, 0.75, 0.42)))
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.95, 0.65))
	elif coming:
		btn.text     = "Bald verfügbar"
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
		btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	elif not Economy.can_unlock_tile(key):
		# Premium-Tiles (Rampe/Steilwand/Looping/Portal/Tribüne): erst den zugehörigen Prestige-Baum-
		# Knoten kaufen, dann hier für Geld freischalten.
		btn.text     = Icons.LOCK + " Prestige-Baum nötig"
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
		btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	else:
		btn.text = "%s %s %s" % [Icons.LOCK, Economy.format_currency(Economy.get_tile_unlock_cost(key)), Icons.COIN]
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_unlock_btn(btn, Economy.get_currency() >= Economy.get_tile_unlock_cost(key))
		btn.pressed.connect(_on_tile_unlock.bind(key))
		_tile_buttons.append({"btn": btn, "key": key})
	card.add_child(btn)

	# Karte mit gestuftem Upgrade merken → beim Kauf nur Text/Button neu setzen,
	# statt das ganze Raster (inkl. drehender 3D-Vorschau) neu zu bauen.
	if has_upg:
		_tile_upgrade_cards.append({"id": upg_id, "entry": entry, "desc": desc_lbl, "btn": btn})

	# Hover über der ganzen Karte zeigt den Erklär-Hinweis zum Streckenteil (auch vor dem Kauf).
	if upg_id != "" and Lang.hint(upg_id) != "":
		_hint_targets_tile.append({"id": upg_id, "area": card})

	return card


# Beschreibungstext einer freigeschalteten Tile mit gestuftem Upgrade (aktuelle Stufe/Werte).
# Eigene Funktion, damit der Text beim Kauf in-place erneuert werden kann.
func _tile_upgrade_desc(upg_id: String, entry: Dictionary) -> String:
	if upg_id == "icebonus":
		# Eisgerade: Speed-Boost (Tempo-Stufen) + Reichweite statt Geld-Ertrag.
		var ice_lv := Economy.get_upgrade_level(upg_id)
		var max_tag := " (MAX)" if Economy.is_maxed(upg_id) else ""
		return "%s +%.1f Lvl · %d Felder%s" % [Icons.SNOWFLAKE, Economy.get_ice_boost_levels(ice_lv), Economy.get_ice_range(ice_lv), max_tag]
	elif upg_id == "wallbonus":
		# Steilwandkurve: Geld-Grundertrag + Speed-Boost (Tempo-Stufen) + Reichweite.
		var wall_lv := Economy.get_upgrade_level(upg_id)
		var wmax_tag := " (MAX)" if Economy.is_maxed(upg_id) else ""
		return "+%s %s · +%.1f Lvl · %d Felder%s" % [Economy.format_currency(Economy.get_wall_earn(wall_lv)), Icons.COIN, Economy.get_wall_boost_levels(wall_lv), Economy.get_wall_range(wall_lv), wmax_tag]
	elif upg_id == "loopbonus":
		# Looping: eigener ×F und Faktor F auf alle anderen Multiplikatoren des Feldes.
		var loop_lv := Economy.get_upgrade_level(upg_id)
		var lmax_tag := " (MAX)" if Economy.is_maxed(upg_id) else ""
		return "×%.1f · andere ×%.1f%s" % [Economy.get_loop_factor(loop_lv), Economy.get_loop_factor(loop_lv), lmax_tag]
	elif upg_id == "portalbonus":
		# Portal: additiver Geld-Ertrag je Durchgang (kein Multiplikator).
		var p_lv := Economy.get_upgrade_level(upg_id)
		var pmax_tag := " (MAX)" if Economy.is_maxed(upg_id) else ""
		return "+%s %s /Durchgang%s" % [Economy.format_currency(Economy.get_portal_earn(p_lv)), Icons.COIN, pmax_tag]
	elif upg_id == "standbonus":
		# Tribüne: Multiplikator auf das/die Nachbarfeld(er).
		var s_lv := Economy.get_upgrade_level(upg_id)
		var smax_tag := " (MAX)" if Economy.is_maxed(upg_id) else ""
		return "×%.1f /Nachbarfeld%s" % [Economy.get_effect("standbonus", s_lv), smax_tag]
	# Aktuellen Ertrag pro Feld zeigen, bei nicht-maxed mit "von → zu". Halb-Schritte (verdreifachte
	# Tile-Upgrades) zeigt format_half unter 10 mit Nachkommastelle (9.5), ab 10 ganzzahlig.
	var base_e := int(entry.get("field_earn_base", 0))
	var lv     := Economy.get_upgrade_level(upg_id)
	var cur    := Economy.format_half(float(base_e) + Economy.get_effect(upg_id, lv))
	# Rampe: zusätzlich den Sprung-Multiplikator (steigt je 5 Stufen) statt "Feld" zeigen.
	if upg_id == "rampbonus":
		var suffix := " (MAX)" if Economy.is_maxed(upg_id) else " → +%s" % Economy.format_half(float(base_e) + Economy.get_effect(upg_id, lv + 1))
		return "+%s%s · ×%.1f" % [cur, suffix, Economy.get_ramp_jump_mult()]
	# Rennstrecke/-kurve: zusätzlich zum +Ertrag den festen ×1.2 anzeigen.
	var race_suffix := " · ×1.2" if upg_id in ["racestraightbonus", "racecurvebonus"] else ""
	if Economy.is_maxed(upg_id):
		return "Ertrag/Feld: +%s (MAX)%s" % [cur, race_suffix]
	var nxt := Economy.format_half(float(base_e) + Economy.get_effect(upg_id, lv + 1))
	return "Ertrag/Feld: +%s → +%s%s" % [cur, nxt, race_suffix]


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
		# Im Max-Modus hängt die „+N · Gesamtkosten"-Anzeige am Geldstand → live mitziehen.
		if Economy.buy_max_mode:
			_set_buy_btn_label(ub, uid, true, 12)


func _on_tile_unlock(key: String) -> void:
	if Economy.is_tile_unlocked(key):
		return
	# Premium-Tiles: erst den Prestige-Baum-Gate-Knoten kaufen, dann hier für Geld freischalten.
	if not Economy.can_unlock_tile(key):
		return
	var cost := Economy.get_tile_unlock_cost(key)
	if Economy.spend(cost):
		Economy.unlock_tile(key)   # → Signal tile_unlocked: Bau-Leiste in Main aktualisiert sich
		_populate_tiles_grid()     # Karte auf "✓ Freigeschaltet" umstellen


# Macht den Karten-Button einer freigeschalteten Tile zum Upgrade-Button (Kosten/Stufe).
func _setup_tile_upgrade_btn(btn: Button, id: String) -> void:
	if Economy.is_maxed(id):
		btn.text     = Icons.CHECK + " MAX (Stufe %d)" % Economy.get_upgrade_level(id)
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(Color(0.10, 0.26, 0.15), Color(0.30, 0.75, 0.42)))
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.95, 0.65))
		return
	_set_buy_btn_label(btn, id, true, 12)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_upgrade_btn(btn, Economy.can_buy(id))
	btn.pressed.connect(_on_buy_tile_upgrade.bind(id))
	_tile_upgrade_buttons.append({"btn": btn, "id": id})


func _on_buy_tile_upgrade(id: String) -> void:
	var ok := false
	if Economy.buy_max_mode:
		ok = Economy.buy_upgrade_max(id) > 0
	else:
		ok = Economy.buy_upgrade(id)
	if ok:
		# Nur die betroffene Karte (Text + Button) aktualisieren, NICHT das ganze Raster
		# neu bauen – sonst springt die rotierende 3D-Vorschau bei jedem Kauf zurück.
		_refresh_tile_upgrade_card(id)


# Aktualisiert Beschreibung + Button einer Upgrade-Karte in-place (Stufe/Kosten/„von→zu"),
# ohne die 3D-Vorschau neu aufzubauen, damit deren Drehung erhalten bleibt.
func _refresh_tile_upgrade_card(id: String) -> void:
	for e in _tile_upgrade_cards:
		if e["id"] != id:
			continue
		var desc = e["desc"]
		if is_instance_valid(desc):
			desc.text = _tile_upgrade_desc(id, e["entry"])
		var btn = e["btn"]
		if is_instance_valid(btn):
			_refresh_tile_upgrade_btn(btn, id)
		return


# Setzt Text/Optik eines Tile-Upgrade-Buttons neu (gleiche Darstellung wie beim Aufbau in
# _setup_tile_upgrade_btn). Bei MAX wird der Button grün/deaktiviert; ein deaktivierter
# Button feuert „pressed" nicht mehr, daher muss das Kauf-Signal nicht getrennt werden.
func _refresh_tile_upgrade_btn(btn: Button, id: String) -> void:
	if Economy.is_maxed(id):
		btn.text     = Icons.CHECK + " MAX (Stufe %d)" % Economy.get_upgrade_level(id)
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(Color(0.10, 0.26, 0.15), Color(0.30, 0.75, 0.42)))
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.95, 0.65))
		return
	_set_buy_btn_label(btn, id, true, 12)
	_style_upgrade_btn(btn, Economy.can_buy(id))


# Baut eine kleine 3D-Vorschau (eigene SubViewport-Welt) auf und merkt sich den
# rotierenden Pivot. Kamera rahmt das Modell automatisch über sein AABB.
func _build_tile_preview(parent: Control, pos: Vector2, sz: Vector2, model_paths: Array, cycle: bool = false) -> void:
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

	# Alle Modell-Teile in EINEN Container hängen (manche Tiles wie Portal bestehen aus mehreren
	# GLBs auf einer Kachel), damit Zentrierung/Kamera-Rahmung das Gesamtbild umfasst. Beim Cycling
	# (z. B. Tribüne) wird hingegen immer nur EIN Teil eingeblendet und reihum durchgeschaltet.
	var model := Node3D.new()
	pivot.add_child(model)
	var parts: Array = []
	for mp in model_paths:
		if typeof(mp) == TYPE_STRING and mp != "" and ResourceLoader.exists(mp):
			var part := (load(mp) as PackedScene).instantiate() as Node3D
			model.add_child(part)
			parts.append(part)
	if parts.is_empty():
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.2, 3.0)
		mi.mesh  = box
		model.add_child(mi)
	# Track-GLBs kommen ohne Material → erst die gemeinsame Atlas-Textur auflegen (sonst nur
	# weiße Umrisse), dann Alpha-Kanten ausstanzen. Gleiche Quelle wie die echte 3D-Strecke.
	MaterialUtil.apply_track_texture(model)
	MaterialUtil.apply_alpha_scissor(model)
	MaterialUtil.apply_unshaded(model)

	# Cycling: nur das erste Teil zeigen, Rest verstecken, und einen Cycler registrieren.
	var do_cycle := cycle and parts.size() > 1
	var frame_target: Node3D = model
	if do_cycle:
		for i in parts.size():
			(parts[i] as Node3D).visible = (i == 0)
		frame_target = parts[0]
		_tile_cyclers.append({"cam": cam, "model": model, "pivot": pivot, "parts": parts, "idx": 0, "accum": 0.0})

	# Kamera leicht von schräg oben auf das gerahmte Modell ausrichten.
	_frame_tile_preview(cam, model, pivot, frame_target)


# Rahmt die Kamera so, dass `target` (Teil unter `model`/`pivot`) mittig sitzt und voll im Bild ist.
# Misst die AABB im Pivot-Raum (drehunabhängig), zentriert das Teil über model.position und setzt
# Kamera-Distanz aus dem Radius – wiederverwendbar für die initiale Rahmung und jeden Cycle-Wechsel.
func _frame_tile_preview(cam: Camera3D, model: Node3D, pivot: Node3D, target: Node3D) -> void:
	model.position = Vector3.ZERO
	var aabb := _aabb_in_space(target, pivot)
	if aabb.size == Vector3.ZERO:
		cam.position = Vector3(2.0, 1.6, 3.2)
		cam.look_at(Vector3.ZERO, Vector3.UP)
		return
	var center := aabb.position + aabb.size * 0.5
	model.position = -center
	var radius := aabb.size.length() * 0.5
	var dist := radius / tan(deg_to_rad(cam.fov * 0.5)) * 1.15
	# Deutlich höher positionieren, damit man die Strecke stärker von schräg oben sieht
	# (~28° statt ~14° über der Horizontalen) – die Form der Kachel ist so besser erkennbar.
	cam.position = Vector3(dist * 0.3, dist * 0.5, dist * 0.9)
	cam.look_at(Vector3.ZERO, Vector3.UP)


# Sekunden, die jede Stufe einer durchwechselnden Vorschau (Tribüne) sichtbar bleibt.
const TILE_CYCLE_INTERVAL = 1.4


# Schaltet registrierte Cycler reihum auf das nächste Modell weiter und rahmt es neu.
func _advance_tile_cyclers(delta: float) -> void:
	for cyc in _tile_cyclers:
		if not is_instance_valid(cyc["model"]):
			continue
		var parts: Array = cyc["parts"]
		if parts.size() < 2:
			continue
		cyc["accum"] += delta
		if cyc["accum"] < TILE_CYCLE_INTERVAL:
			continue
		cyc["accum"] = 0.0
		var cur = parts[cyc["idx"]]
		if is_instance_valid(cur):
			cur.visible = false
		cyc["idx"] = (int(cyc["idx"]) + 1) % parts.size()
		var nxt = parts[cyc["idx"]]
		if is_instance_valid(nxt):
			nxt.visible = true
			_frame_tile_preview(cyc["cam"], cyc["model"], cyc["pivot"], nxt)


func _build_cat_placeholder(parent: Control, x: int, h: int, w: int,
		title: String, desc: String) -> void:
	var container := Control.new()
	container.position = Vector2(x, 0)
	container.size     = Vector2(w, h)
	parent.add_child(container)
	_shop_cats.append(container)

	var center_y  = h / 2.0 - 60
	var icon_lbl := Label.new()
	icon_lbl.text     = Icons.LOCK
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


func _build_cat_upgrades(parent: Control, x: int, h: int, w: int, top: int = 0) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x, top)
	scroll.size     = Vector2(w, h - top)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_shop_cats.append(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(w - 20, 0)
	vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(vbox)
	_add_upgrade_rows(vbox, w - 20)


# ── Errungenschaften ──────────────────────────────────────────────────────────

# ── Errungenschaften ──────────────────────────────────────────────────────────────
# Icon-Kachelraster rechts; links eine Spalte, die den angeklickten Erfolg ausführlich
# beschreibt. Daten sind aktuell statisch (noch nicht an echte Spielereignisse gekoppelt).

const ACH_LEFT_W = 250    # Breite der Beschreibungs-Spalte links
const ACH_TILE   = 88     # Kachelgröße (quadratisch)

var _ach_data:     Array = []
var _ach_tiles:    Array = []   # je {"btn": Button, "sb": StyleBoxFlat, "done": bool}
var _ach_selected: int   = -1
var _ach_icon_lbl:   Label = null
var _ach_title_lbl:  Label = null
var _ach_status_lbl: Label = null
var _ach_desc_lbl:   Label = null
var _ach_progress_lbl: Label = null   # „% erreicht" in der Kopfzeile
var _ach_claim_btn:  Button = null    # „Einsammeln"-Knopf in der Detailspalte (nur bei erreichten Erfolgen)
var _ach_claim_sb:   StyleBoxFlat = null   # Stylebox des Einsammeln-Knopfs (zum Umfärben je Zustand)


# Icon-Glyph je Erfolgs-ID (UI-Sache; die Glyphen werden erst zur Laufzeit aus Icons befüllt,
# daher hier als Funktion statt als const-Tabelle). Unbekannte IDs → neutrales Pokal-Icon.
func _ach_icon_for(id: String) -> String:
	match id:
		"first_race":     return Icons.FLAG_3
		"tile_road":      return Icons.ROAD
		"tile_ice":       return Icons.SNOWFLAKE
		"tile_ramp":      return Icons.ROCKET
		"tile_wall":      return Icons.MOUNTAIN
		"tile_loop":      return Icons.RECYCLE
		"tile_portal":    return Icons.CIRCLE_DASHED
		"tile_stand":     return Icons.STADIUM
		"stand_max":      return Icons.CONFETTI
		"lap_1k":         return Icons.CLOCK
		"lap_100k":       return Icons.GAUGE
		"lap_1m":         return Icons.BOLT
		"lap_1b":         return Icons.FLAME
		"money_100k":     return Icons.COIN
		"money_1m":       return Icons.COINS
		"money_1b":       return Icons.TRENDING_UP
		"money_1t":       return Icons.TROPHY
		"car_ascend":     return Icons.GARAGE
		"first_prestige": return Icons.STAR
		"prestige_5":     return Icons.MEDAL
		"prestige_10":    return Icons.AWARD
		"pp_10":          return Icons.SPARKLES
		"pp_100":         return Icons.ROSETTE_CHECK
		"pp_1000":        return Icons.STAR
		"track_2":        return Icons.MAP_2
		"track_3":        return Icons.WORLD
		"loop_jump":      return Icons.RECYCLE
		"loop_jump_portal": return Icons.RECYCLE
		"loop_triple":    return Icons.INFINITY
		"loop_mania":     return Icons.FLAME
		"only_special":   return Icons.CIRCLE_DASHED
		"stand_empire":   return Icons.STADIUM
		"thrifty":        return Icons.COIN
		"loner":          return Icons.STEERING_WHEEL
		"marathon":       return Icons.CLOCK
		"master_builder": return Icons.HAMMER
		"completionist":  return Icons.ROSETTE_CHECK
	return Icons.TROPHY


# Öffentlicher Zugriff auf das Erfolgs-Icon (z. B. für den Achievement-Toast in der GameHUD).
func icon_for_achievement(id: String) -> String:
	return _ach_icon_for(id)


# Baut die Anzeige-Daten aus der zentralen Erfolgs-Definition in Economy (Quelle der Wahrheit).
# done-Status ist slot-gebunden → kommt aus Economy.is_achievement_unlocked.
func _build_ach_data() -> Array:
	var out: Array = []
	for id in Economy.ACHIEVEMENT_ORDER:
		out.append(_ach_entry(id, false))
	# Geheime Erfolge als eigener Block dahinter (in der UI unter einer Trennlinie).
	for id in Economy.SECRET_ACHIEVEMENT_ORDER:
		out.append(_ach_entry(id, true))
	return out


# Anzeige-Eintrag für einen Erfolg. Geheime, noch NICHT freigeschaltete Erfolge werden verdeckt:
# Name „???", Fragezeichen-Icon und verdeckte Beschreibung – erst nach dem Freischalten echt.
func _ach_entry(id: String, secret: bool) -> Dictionary:
	var d: Dictionary = Economy.ACHIEVEMENTS.get(id, {})
	var done: bool = Economy.is_achievement_unlocked(id)
	var hidden := secret and not done
	return {
		"id":     id,
		"secret": secret,
		"icon":   "?" if hidden else _ach_icon_for(id),
		"name":   "???" if hidden else String(d.get("name", id)),
		"desc":   tr("Geheimer Erfolg – schalte ihn frei, um ihn zu enthüllen.") if hidden else String(d.get("desc", "")),
		"done":   done,
	}


# Setzt ein Erfolgs-Icon auf ein Label. PUA-Glyphen brauchen die Icon-Schrift; das verdeckte
# „?" rendert dagegen in der normalen Schrift (die Icon-Font hat kein ASCII-Fragezeichen).
func _apply_ach_icon(lbl: Label, glyph: String) -> void:
	lbl.text = glyph
	if Icons.FONT != null and glyph != "?":
		lbl.add_theme_font_override("font", Icons.FONT)
	else:
		lbl.remove_theme_font_override("font")


func _build_achievements_panel(parent: Control, cy: int, ch: int) -> void:
	_ach_data = _build_ach_data()
	_ach_tiles.clear()
	_ach_selected = -1

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(root)
	_tab_panels.append(root)

	var outer := VBoxContainer.new()
	outer.position = Vector2(16, 0)
	outer.size     = Vector2(_vw() - 32, ch)
	outer.add_theme_constant_override("separation", 8)
	root.add_child(outer)

	var head_row := _add_cat_header(outer, "ERRUNGENSCHAFTEN")
	# Fortschritt in Prozent – rechts neben dem Titel, aktualisiert sich live.
	head_row.add_child(_hpad(12))
	_ach_progress_lbl = Label.new()
	_ach_progress_lbl.add_theme_font_size_override("font_size", 13)
	_ach_progress_lbl.add_theme_color_override("font_color", C_CLAIM_GOLD)   # Gold wie die Erfolgswährung
	_emboss(_ach_progress_lbl)
	head_row.add_child(_ach_progress_lbl)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	outer.add_child(body)

	body.add_child(_build_ach_detail_panel())
	body.add_child(_build_ach_grid())

	_update_ach_progress()
	_select_achievement(0)


# Linke Spalte: große Detailansicht des aktuell gewählten Erfolgs.
func _build_ach_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ACH_LEFT_W, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color      = C_SURFACE
	sb.border_color  = C_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18; sb.content_margin_right  = 18
	sb.content_margin_top  = 18; sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	_ach_icon_lbl = Label.new()
	_ach_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ach_icon_lbl.add_theme_font_size_override("font_size", 56)
	if Icons.FONT != null:
		_ach_icon_lbl.add_theme_font_override("font", Icons.FONT)
	v.add_child(_ach_icon_lbl)

	_ach_title_lbl = Label.new()
	_ach_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ach_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ach_title_lbl.add_theme_font_size_override("font_size", 18)
	_ach_title_lbl.add_theme_color_override("font_color", C_TEXT)
	_emboss(_ach_title_lbl)
	v.add_child(_ach_title_lbl)

	_ach_status_lbl = Label.new()
	_ach_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ach_status_lbl.add_theme_font_size_override("font_size", 12)
	v.add_child(_ach_status_lbl)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = C_LINE
	v.add_child(sep)

	_ach_desc_lbl = Label.new()
	_ach_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ach_desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ach_desc_lbl.add_theme_font_size_override("font_size", 13)
	_ach_desc_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	v.add_child(_ach_desc_lbl)

	# Einsammeln-Knopf ganz unten. Sichtbar nur bei erreichten Erfolgen; aktiv nur, solange noch nicht
	# eingesammelt. Belohnung (Trophäen) gibt's erst hier – nicht automatisch beim Freischalten.
	_ach_claim_sb = StyleBoxFlat.new()
	_ach_claim_sb.set_corner_radius_all(8)
	_ach_claim_sb.content_margin_top = 10; _ach_claim_sb.content_margin_bottom = 10
	_ach_claim_sb.content_margin_left = 14; _ach_claim_sb.content_margin_right = 14
	_ach_claim_btn = Button.new()
	_ach_claim_btn.focus_mode = Control.FOCUS_NONE
	_ach_claim_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ach_claim_btn.add_theme_font_size_override("font_size", 14)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		_ach_claim_btn.add_theme_stylebox_override(st, _ach_claim_sb)
	_ach_claim_btn.pressed.connect(_on_ach_claim_pressed)
	v.add_child(_ach_claim_btn)

	return panel


# Rechte Seite: scrollbares Raster aus quadratischen Icon-Kacheln.
func _build_ach_grid() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	# Spalte: normales Raster oben, darunter (falls vorhanden) die Trennlinie + das Geheim-Raster.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	# HFlowContainer statt GridContainer: bricht die fix großen Kacheln automatisch um,
	# sodass je nach Fensterbreite so viele nebeneinander passen, wie Platz haben.
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)

	# Geheime Erfolge kommen unter einer Trennlinie in ein eigenes Raster (erst beim ersten geheimen
	# Eintrag angelegt – ohne geheime Erfolge gibt es keine Trennlinie). Reihenfolge = _ach_data.
	var secret_grid: HFlowContainer = null
	for i in _ach_data.size():
		if bool(_ach_data[i].get("secret", false)):
			if secret_grid == null:
				col.add_child(_make_secret_divider())
				secret_grid = HFlowContainer.new()
				secret_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				secret_grid.add_theme_constant_override("h_separation", 10)
				secret_grid.add_theme_constant_override("v_separation", 10)
				col.add_child(secret_grid)
			secret_grid.add_child(_make_ach_tile(i))
		else:
			grid.add_child(_make_ach_tile(i))

	return scroll


# Trennlinie mit Überschrift zwischen den normalen und den geheimen Erfolgen: ──── GEHEIM ────
func _make_secret_divider() -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var line_l := ColorRect.new()
	line_l.color = C_LINE
	line_l.custom_minimum_size = Vector2(0, 1)
	line_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_l.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	row.add_child(line_l)

	var lbl := Label.new()
	lbl.text = tr("GEHEIME ERFOLGE")
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	_emboss(lbl)
	row.add_child(lbl)

	var line_r := ColorRect.new()
	line_r.color = C_LINE
	line_r.custom_minimum_size = Vector2(0, 1)
	line_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_r.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	row.add_child(line_r)

	return row


# Eine Kachel: Icon + kurzer Titel, klickbar → wählt den Erfolg in der Detailspalte.
func _make_ach_tile(idx: int) -> Button:
	var data: Dictionary = _ach_data[idx]
	var done: bool = data["done"]

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(ACH_TILE, ACH_TILE)
	btn.focus_mode  = Control.FOCUS_NONE
	btn.tooltip_text = data["name"]

	var sb := StyleBoxFlat.new()
	sb.bg_color     = C_SURFACE if done else C_BG
	sb.border_color = C_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, sb)

	# Inhalt liegt über dem Button und ignoriert Maus-Events → Klick trifft den Button.
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	btn.add_child(v)

	var icon := Label.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 30)
	_apply_ach_icon(icon, data["icon"])
	icon.modulate = Color(1, 1, 1, 1.0 if done else 0.45)
	v.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(ACH_TILE - 10, 0)
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", C_TEXT if done else C_TEXT_DIM)
	name_lbl.text = data["name"]
	v.add_child(name_lbl)

	btn.pressed.connect(_select_achievement.bind(idx))
	var claimable: bool = Economy.can_claim_achievement(String(data.get("id", "")))
	_ach_tiles.append({"btn": btn, "sb": sb, "done": done, "claimable": claimable, "icon": icon, "name_lbl": name_lbl})
	return btn


# Markiert die gewählte Kachel und füllt die linke Detailspalte.
func _select_achievement(idx: int) -> void:
	if idx < 0 or idx >= _ach_data.size():
		return
	_ach_selected = idx

	for i in _ach_tiles.size():
		var t: Dictionary = _ach_tiles[i]
		var tsb: StyleBoxFlat = t["sb"]
		var sel := i == idx
		var tdone: bool = t["done"]
		var tclaim: bool = t.get("claimable", false)
		var tclaimed: bool = tdone and not tclaim   # erreicht UND Währung schon eingesammelt
		# Rahmen: gewähltes grünes (eingesammeltes) Feld = dunkelgrün-grau (Blau passt nicht aufs Grün),
		# sonst gewählt = blau, einsammelbar = gold, eingesammelt = grün, erreicht = gedämpft, sonst Linie.
		if sel and tclaimed:
			tsb.border_color = C_CLAIMED_SEL
		elif sel:
			tsb.border_color = C_ACCENT
		elif tclaim:
			tsb.border_color = C_CLAIM_GOLD
		elif tclaimed:
			tsb.border_color = C_CLAIMED_GREEN
		elif tdone:
			tsb.border_color = C_ACCENT_MU
		else:
			tsb.border_color = C_LINE
		tsb.set_border_width_all(2 if (sel or tclaim or tclaimed) else 1)
		# Füllung: eingesammelt = dunkelgrün (bleibt auch bei Auswahl grün erkennbar), sonst wie gehabt.
		if tclaimed:
			tsb.bg_color = C_CLAIMED_BG
		elif sel:
			tsb.bg_color = C_SURFACE2
		elif tdone:
			tsb.bg_color = C_SURFACE
		else:
			tsb.bg_color = C_BG
		(t["btn"] as Button).queue_redraw()

	var data: Dictionary = _ach_data[idx]
	var done: bool = data["done"]
	_apply_ach_icon(_ach_icon_lbl, data["icon"])
	_ach_icon_lbl.modulate = Color(1, 1, 1, 1.0 if done else 0.5)
	_ach_title_lbl.text    = data["name"]
	_ach_desc_lbl.text     = data["desc"]
	if done and Economy.is_achievement_claimed(String(data.get("id", ""))):
		_ach_status_lbl.text = "%s %s" % [Icons.CHECK, tr("Eingesammelt")]
		_ach_status_lbl.add_theme_color_override("font_color", C_CLAIMED_GREEN)
	elif done:
		_ach_status_lbl.text = "%s %s" % [Icons.CHECK, tr("Freigeschaltet")]
		_ach_status_lbl.add_theme_color_override("font_color", C_ACCENT)
	else:
		_ach_status_lbl.text = "%s %s" % [Icons.LOCK, tr("Gesperrt")]
		_ach_status_lbl.add_theme_color_override("font_color", C_TEXT_DIM)

	_update_ach_claim_btn(String(data.get("id", "")))


# Farben des Einsammeln-Knopfs (Gold = einsammelbar). Dunkler Text auf der Gold-Füllung.
const C_CLAIM_GOLD := Color(1.00, 0.82, 0.30)
const C_CLAIM_DARK := Color(0.20, 0.15, 0.02)
# Eingesammelt (Währung abgeholt) = grün markiert: kräftiger Rahmen/Text + dunkelgrüne Füllung.
const C_CLAIMED_GREEN := Color(0.30, 0.78, 0.42)
const C_CLAIMED_BG    := Color(0.12, 0.22, 0.15)
# Auswahl-Rahmen auf einem eingesammelten (grünen) Feld: dunkelgrün-grau statt Blau (Blau passt nicht aufs Grün).
const C_CLAIMED_SEL   := Color(0.36, 0.46, 0.38)

# Setzt Sichtbarkeit, Text und Stil des Einsammeln-Knopfs für den gewählten Erfolg.
#   • noch nicht erreicht → versteckt
#   • erreicht, noch nicht eingesammelt → Gold, aktiv, „Einsammeln  +N 🏆"
#   • bereits eingesammelt → grün gefüllt + grüner Rahmen, deaktiviert, „✓ Eingesammelt"
func _update_ach_claim_btn(id: String) -> void:
	if _ach_claim_btn == null or _ach_claim_sb == null:
		return
	if id == "" or not Economy.is_achievement_unlocked(id):
		_ach_claim_btn.visible = false
		return
	_ach_claim_btn.visible = true
	if Economy.is_achievement_claimed(id):
		_ach_claim_btn.disabled = true
		_ach_claim_btn.text = "%s %s" % [Icons.CHECK, tr("Eingesammelt")]
		_ach_claim_btn.add_theme_color_override("font_color", C_CLAIMED_GREEN)
		_ach_claim_sb.bg_color     = C_CLAIMED_BG
		_ach_claim_sb.border_color = C_CLAIMED_GREEN
		_ach_claim_sb.set_border_width_all(2)
	else:
		_ach_claim_btn.disabled = false
		_ach_claim_btn.text = tr("Einsammeln   +%d %s") % [Economy.get_achievement_reward(id), Icons.TROPHY]
		_ach_claim_btn.add_theme_color_override("font_color", C_CLAIM_DARK)
		_ach_claim_sb.bg_color     = C_CLAIM_GOLD
		_ach_claim_sb.border_color = C_CLAIM_GOLD
		_ach_claim_sb.set_border_width_all(0)


# Klick auf „Einsammeln": Trophäen des gewählten Erfolgs gutschreiben (Economy entscheidet, ob möglich)
# und alle Erfolgs-/Trophäen-Anzeigen neu zeichnen.
func _on_ach_claim_pressed() -> void:
	if _ach_selected < 0 or _ach_selected >= _ach_data.size():
		return
	var id := String(_ach_data[_ach_selected].get("id", ""))
	if Economy.claim_achievement(id):
		_refresh_achievements()
		_refresh_garage_trophies()


# Berechnet den Anteil freigeschalteter Erfolge und schreibt ihn in die Kopfzeile.
func _update_ach_progress() -> void:
	if _ach_progress_lbl == null:
		return
	var total := _ach_data.size()
	var done := 0
	for d in _ach_data:
		if d.get("done", false):
			done += 1
	var pct := 0
	if total > 0:
		pct = int(round(100.0 * float(done) / float(total)))
	_ach_progress_lbl.text = "%d %% (%d/%d)" % [pct, done, total]


# Gleicht den done-Status aller Kacheln mit Economy ab (Quelle der Wahrheit) und zeichnet
# Kacheln, Detailspalte und Prozentanzeige neu. Wird beim Öffnen (Slot kann gewechselt haben)
# und live über das achievement_unlocked-Signal aufgerufen. No-Op, solange das Panel noch nicht
# gebaut ist (greift z. B. nicht während _ready vor dem ersten _build_modal).
func _refresh_achievements() -> void:
	if _ach_tiles.is_empty() or _ach_progress_lbl == null:
		return
	for i in _ach_data.size():
		var id: String = String(_ach_data[i].get("id", ""))
		# Eintrag neu bauen → ein gerade freigeschalteter geheimer Erfolg wird enthüllt (??? → echt).
		var entry := _ach_entry(id, bool(_ach_data[i].get("secret", false)))
		_ach_data[i] = entry
		var done: bool = entry["done"]
		if i < _ach_tiles.size():
			var t: Dictionary = _ach_tiles[i]
			t["done"] = done
			t["claimable"] = Economy.can_claim_achievement(id)
			var icl := t["icon"] as Label
			_apply_ach_icon(icl, entry["icon"])
			icl.modulate = Color(1, 1, 1, 1.0 if done else 0.45)
			var nl := t["name_lbl"] as Label
			nl.text = entry["name"]
			nl.add_theme_color_override("font_color", C_TEXT if done else C_TEXT_DIM)
			(t["btn"] as Button).tooltip_text = entry["name"]
	_update_ach_progress()
	_select_achievement(_ach_selected if _ach_selected >= 0 else 0)


# Live-Update, wenn im Spiel ein Erfolg freigeschaltet wird (Signal aus Economy).
func _on_achievement_unlocked(_id: String) -> void:
	_refresh_achievements()
	_refresh_garage_trophies()   # Trophäen-Stand (Garage) mitziehen


# ── Statistik ───────────────────────────────────────────────────────────────────
# Einfache Übersichts-Seite (Geld, Prestige, Strecken, Baufeld …). Wird beim Öffnen
# und beim Tab-Wechsel frisch befüllt.

var _statistik_vbox: VBoxContainer = null
var _stat_value_lbls: Dictionary = {}   # key → Wert-Label (für Live-Aktualisierung im _process)


func _build_statistik_panel(parent: Control, cy: int, ch: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_tab_panels.append(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(_vw() - 20, 0)
	vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(vbox)
	_statistik_vbox = vbox

	_refresh_statistik()


func _refresh_statistik() -> void:
	if _statistik_vbox == null:
		return
	for c in _statistik_vbox.get_children():
		c.queue_free()
	_stat_value_lbls.clear()

	var run_total := 0.0
	for i in Economy.TRACK_COUNT:
		run_total += Economy.get_run_earned(i)

	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, 18)
	_statistik_vbox.add_child(top_pad)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	_statistik_vbox.add_child(cols)

	cols.add_child(_hpad(28))
	cols.add_child(_make_stat_column("Globale Statistiken", [
		[
			["Spielzeit",                 Economy.format_playtime(Economy.get_total_playtime()), "playtime"],
			["Fahrtdauer pro Runde",      "%.1f s" % Economy.get_drive_time()],
		],
		[
			["Freigeschaltete Strecken",  "%d / %d" % [Economy.get_unlocked_tracks(), Economy.TRACK_COUNT]],
			["Autos pro Strecke",         str(Economy.get_car_count())],
			["Baufeld",                   "%d × %d" % [Economy.get_grid_rows(), Economy.get_grid_cols()]],
		],
		[
			["Geschwindigkeits-Bonus",    "×%d" % int(Economy.get_prestige_mult()), "speed_bonus"],
		],
	]))
	cols.add_child(_hpad(44))
	cols.add_child(_make_stat_column("Wirtschaft", [
		[
			["Aktuelles Guthaben",        Economy.format_currency(Economy.get_currency()), "guthaben"],
			["Laufende Runden-Erträge",   Economy.format_currency(run_total), "run_total"],
		],
		[
			["Prestige-Punkte",           Economy.format_currency(Economy.get_prestige_points()), "prestige_pts"],
			["Verdient seit Prestige",    Economy.format_currency(Economy.get_prestige_earned()), "prestige_earned"],
		],
	]))
	cols.add_child(_hpad(28))


# Baut eine Statistik-Spalte: Titel + Gruppen, zwischen Gruppen eine gepunktete Trennlinie.
func _make_stat_column(title: String, groups: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(330, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)

	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 19)
	head.add_theme_color_override("font_color", C_TEXT)
	_emboss(head)
	col.add_child(head)

	var head_pad := Control.new()
	head_pad.custom_minimum_size = Vector2(0, 14)
	col.add_child(head_pad)

	for gi in groups.size():
		var group: Array = groups[gi]
		for r in group:
			var key: String = r[2] if r.size() > 2 else ""
			col.add_child(_make_stat_line(r[0], r[1], key))
		if gi < groups.size() - 1:
			col.add_child(_make_stat_dotsep())
	return col


func _make_stat_line(label_txt: String, value_txt: String, key: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 34)

	var l := Label.new()
	l.text = label_txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", C_TEXT)
	row.add_child(l)

	var v := Label.new()
	v.text = value_txt
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 14)
	v.add_theme_color_override("font_color", C_ACCENT)
	row.add_child(v)
	# Werte, die sich live ändern (Zeit, Geld, Prestige …), für _tick_statistik merken.
	if key != "":
		_stat_value_lbls[key] = v
	return row


# Aktualisiert nur die Wert-Labels der Statistik (läuft im _process, solange der Tab offen ist).
func _tick_statistik() -> void:
	if _stat_value_lbls.is_empty():
		return
	_set_stat("playtime", Economy.format_playtime(Economy.get_total_playtime()))
	_set_stat("guthaben", Economy.format_currency(Economy.get_currency()))
	if _stat_value_lbls.has("run_total"):
		var run_total := 0.0
		for i in Economy.TRACK_COUNT:
			run_total += Economy.get_run_earned(i)
		_set_stat("run_total", Economy.format_currency(run_total))
	_set_stat("prestige_pts", Economy.format_currency(Economy.get_prestige_points()))
	_set_stat("prestige_earned", Economy.format_currency(Economy.get_prestige_earned()))
	_set_stat("speed_bonus", "×%d" % int(Economy.get_prestige_mult()))


func _set_stat(key: String, value_txt: String) -> void:
	var lbl = _stat_value_lbls.get(key)
	if lbl != null and is_instance_valid(lbl):
		lbl.text = value_txt


# Gepunktete Gruppen-Trennlinie (wie im Statistik-Screenshot).
func _make_stat_dotsep() -> Label:
	var dots := Label.new()
	dots.custom_minimum_size = Vector2(0, 18)
	dots.text = "·".repeat(80)
	dots.clip_text = true
	dots.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dots.add_theme_color_override("font_color", C_TEXT_DIM.darkened(0.15))
	return dots


# ── Werkstatt (Auto-Konfiguration) ─────────────────────────────────────────────
# Werkstatt = Auto-Aufstieg („Autos"). Garage = Lackierung + Muster. Beide Tabs zeigen
# dieselbe rotierende 3D-Vorschau: EIN gemeinsames SubViewport, das beim Tab-Wechsel in
# den jeweils sichtbaren Container umgehängt wird (gleiche Position).

# Garage-Unter-Tabs (Lackierung · Muster). Als Funktion, weil die Glyphen aus dem Icons-Autoload kommen.
func _garage_tabs() -> Array:
	return [
		{"id": "paint",   "name": "Lackierung", "icon": Icons.PALETTE},
		{"id": "pattern", "name": "Muster",     "icon": Icons.LAYOUT_GRID},
	]

# Werkstatt
var _ws_sel:         Dictionary    = {"paint": 0, "pattern": 0}
var _ws_options_box: Control       = null   # Auto-Aufstieg-Inhalt
var _ws_summary_lbl: Label         = null   # Auto-Aufstieg-Status
var _ws_title_lbl:   Label         = null   # „🚗 Auto-Aufstieg"-Titel (selbst per tr() übersetzt)

# Garage
var _garage_active_tab:  int           = 0
var _garage_tab_btns:    Array[Button] = []
var _garage_options_box: Control       = null
var _garage_summary_lbl: Label         = null
var _garage_trophy_lbl:  Label         = null   # Trophäen-Stand (Erfolgs-Währung), nur hier sichtbar
var _test_car_btn:       Button        = null   # Reiner Test: schaltet das Blender-Testmodell an/aus
var _garage_frame:       Panel         = null   # Rahmen hinter der Vorschau (für Repositionierung beim Muster-Tab)
var _pattern_color_box:  Control       = null   # Farbauswahl für die Muster-Farbe (nur im Muster-Tab)

# Container beider Tabs (für das Umhängen der gemeinsamen Vorschau) + die Vorschau selbst.
var _werkstatt_container: Control = null
var _garage_container:    Control = null
var _preview_svc:         SubViewportContainer = null

# Gemeinsame Vorschau-Geometrie (in beiden Tabs identisch).
const PREVIEW_W = 480
const PREVIEW_H = 252
# _preview_x() ist laufzeitabhängig (_vw() ändert sich mit Viewport) – wird per _preview_x() berechnet.
const PREVIEW_Y = 158.0
func _preview_x() -> float: return (_vw() - PREVIEW_W) / 2.0

# Muster-Farbauswahl rechts neben der Vorschau: Breite der Swatch-Spalte + Abstand zur Vorschau.
# Im Muster-Tab rückt die Vorschau nach links und die Spalte sitzt rechts daneben; ist zu wenig
# Platz (Portrait), liegt die Auswahl als Streifen UNTER der Vorschau (siehe _layout_garage_preview).
const PCOL_W         = 150.0
const PREV_PICK_GAP  = 24.0

# 3D-Vorschau
var _preview_pivot:  Node3D    = null
var _preview_model:  Node3D    = null
var _preview_cam:    Camera3D  = null
var _preview_meshes: Array     = []
var _preview_tier:   int       = -1   # Auto-Stufe, deren Modell aktuell in der Vorschau hängt


func _ws_options(id: String) -> Array:
	match id:
		"paint":
			# „Original" (kein Override) zuerst, danach eine breite Palette. Mehr Farben = besser.
			return [
				{"name": "Original",   "icon": Icons.CAR},
				{"name": "Rot",        "color": Color(0.85, 0.15, 0.12)},
				{"name": "Dunkelrot",  "color": Color(0.55, 0.08, 0.10)},
				{"name": "Orange",     "color": Color(0.95, 0.45, 0.10)},
				{"name": "Bernstein",  "color": Color(0.90, 0.62, 0.10)},
				{"name": "Gelb",       "color": Color(0.95, 0.85, 0.15)},
				{"name": "Limette",    "color": Color(0.65, 0.85, 0.18)},
				{"name": "Grün",       "color": Color(0.15, 0.65, 0.30)},
				{"name": "Smaragd",    "color": Color(0.08, 0.50, 0.38)},
				{"name": "Türkis",     "color": Color(0.12, 0.72, 0.70)},
				{"name": "Cyan",       "color": Color(0.18, 0.78, 0.92)},
				{"name": "Hellblau",   "color": Color(0.35, 0.62, 0.95)},
				{"name": "Blau",       "color": Color(0.13, 0.40, 0.85)},
				{"name": "Marine",     "color": Color(0.10, 0.16, 0.45)},
				{"name": "Violett",    "color": Color(0.45, 0.25, 0.80)},
				{"name": "Lila",       "color": Color(0.62, 0.20, 0.78)},
				{"name": "Magenta",    "color": Color(0.85, 0.20, 0.62)},
				{"name": "Pink",       "color": Color(0.95, 0.45, 0.70)},
				{"name": "Rosa",       "color": Color(0.96, 0.72, 0.78)},
				{"name": "Braun",      "color": Color(0.42, 0.27, 0.16)},
				{"name": "Sand",       "color": Color(0.82, 0.72, 0.52)},
				{"name": "Grau",       "color": Color(0.50, 0.52, 0.56)},
				{"name": "Anthrazit",  "color": Color(0.18, 0.19, 0.22)},
				{"name": "Schwarz",    "color": Color(0.06, 0.06, 0.08)},
				{"name": "Weiß",       "color": Color(0.92, 0.93, 0.96)},
				{"name": "Gold",       "color": Color(0.83, 0.68, 0.21)},
			]
		"pattern":
			# Muster über die Lack-Maske. idx = car_pattern (= pattern_mode im Shader, 0 = keins).
			# "kind" steuert nur die kleine Vorschau-Grafik der Karte; "gradient" blendet in die Farbe.
			return [
				{"name": "Keins",     "icon": Icons.CIRCLE_X},
				{"name": "Streifen",  "kind": "stripes"},
				{"name": "Diagonal",  "kind": "diagonal"},
				{"name": "Karo",      "kind": "checker"},
				{"name": "Punkte",    "kind": "dots"},
				{"name": "Verlauf",   "kind": "gradient"},
			]
	return []


func _build_werkstatt_panel(parent: Control, cy: int, ch: int) -> void:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(container)
	_tab_panels.append(container)
	_werkstatt_container = container

	var title := Label.new()
	title.position = Vector2(0, 14)
	title.size     = Vector2(_vw(), 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_TEXT)
	title.text = "%s  %s" % [Icons.CAR, tr("Auto-Aufstieg")]
	container.add_child(title)
	_ws_title_lbl = title

	# Auto-Aufstieg-Inhalt
	_ws_options_box = Control.new()
	_ws_options_box.position = Vector2(0, 48)
	_ws_options_box.size     = Vector2(_vw(), 102)
	container.add_child(_ws_options_box)

	_build_preview_frame(container)
	_ws_summary_lbl = _make_preview_summary(container)

	# Gemeinsame 3D-Vorschau (initial in der Werkstatt) – wird beim Tab-Wechsel umgehängt.
	_sync_paint_selection_from_economy()
	_build_preview_viewport(container, Vector2(_preview_x(), PREVIEW_Y), Vector2(PREVIEW_W, PREVIEW_H))
	_rebuild_autos_options()


# Garage-Tab: Lackierung + Muster (aus der Werkstatt ausgelagert), dieselbe 3D-Vorschau.
func _build_garage_panel(parent: Control, cy: int, ch: int) -> void:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(container)
	_tab_panels.append(container)
	_garage_container = container

	# Unter-Tab-Leiste (Lackierung · Muster)
	const SUB_W   = 150
	const SUB_GAP = 8
	var gtabs = _garage_tabs()
	var total_w = gtabs.size() * SUB_W + (gtabs.size() - 1) * SUB_GAP
	var sx = (_vw() - total_w) / 2.0
	_garage_tab_btns.clear()
	for i in gtabs.size():
		var t = gtabs[i]
		var btn := Button.new()
		btn.text     = "%s  %s" % [t.icon, tr(t.name)]
		btn.position = Vector2(sx + i * (SUB_W + SUB_GAP), 12)
		btn.size     = Vector2(SUB_W, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_ws_tab(btn, i == 0)
		btn.pressed.connect(_on_garage_tab.bind(i))
		container.add_child(btn)
		_garage_tab_btns.append(btn)

	# Optionsraster (Lack-Swatches / Muster-Karten)
	_garage_options_box = Control.new()
	_garage_options_box.position = Vector2(0, 58)
	_garage_options_box.size     = Vector2(_vw(), 92)
	container.add_child(_garage_options_box)

	_garage_frame = _build_preview_frame(container)
	_garage_summary_lbl = _make_preview_summary(container)

	# Farbauswahl für die Muster-Farbe (nur im Muster-Tab sichtbar). Lage/Größe setzt
	# _layout_garage_preview() je nach Platz (rechts neben der Vorschau bzw. darunter).
	_pattern_color_box = Control.new()
	_pattern_color_box.visible = false
	container.add_child(_pattern_color_box)

	# Trophäen-Stand steht jetzt dauerhaft in der oberen Leiste (🏆-Badge) → hier keine eigene
	# Anzeige mehr. _garage_trophy_lbl bleibt null; _refresh_garage_trophies() ist dann ein No-Op.

	# Reiner Test-Knopf (nur im Muster-Tab sichtbar): schaltet das Blender-Testmodell an/aus.
	_test_car_btn = Button.new()
	_test_car_btn.position = Vector2(_vw() - 150 - 16, 12)
	_test_car_btn.size     = Vector2(150, 36)
	_test_car_btn.focus_mode = Control.FOCUS_NONE
	_test_car_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_test_car_btn.visible  = (_garage_tabs()[_garage_active_tab].id == "pattern")
	_test_car_btn.pressed.connect(_on_toggle_test_car)
	container.add_child(_test_car_btn)
	_update_test_car_btn()

	_sync_paint_selection_from_economy()
	_rebuild_garage_options()


# Bordierter Vorschau-Rahmen (Hintergrund hinter dem 3D-Viewport). Gibt den Rahmen zurück, damit
# die Garage ihn beim Muster-Tab nach links verschieben kann.
func _build_preview_frame(container: Control) -> Panel:
	var frame := Panel.new()
	frame.position = Vector2(_preview_x() - 3, PREVIEW_Y - 3)
	frame.size     = Vector2(PREVIEW_W + 6, PREVIEW_H + 6)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color     = C_SURFACE
	fsb.border_color = C_LINE
	fsb.set_border_width_all(1)
	fsb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fsb)
	container.add_child(frame)
	return frame


# Zusammenfassungs-Label unter dem Vorschau-Rahmen.
func _make_preview_summary(container: Control) -> Label:
	var lbl := Label.new()
	lbl.position = Vector2(_preview_x(), PREVIEW_Y + PREVIEW_H + 6)
	lbl.size     = Vector2(PREVIEW_W, 22)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	container.add_child(lbl)
	return lbl


# Auto-Aufstieg-Inhalt der Werkstatt neu aufbauen (Box leeren + Inhalt setzen).
func _rebuild_autos_options() -> void:
	if _ws_options_box == null:
		return
	for c in _ws_options_box.get_children():
		c.queue_free()
	_build_autos_options()


# Setzt die markierte Lackierungs-/Muster-Karte passend zum gespeicherten Economy-Zustand.
func _sync_paint_selection_from_economy() -> void:
	_ws_sel["pattern"] = Economy.get_car_pattern()
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


func _on_garage_tab(idx: int) -> void:
	_garage_active_tab = idx
	for i in _garage_tab_btns.size():
		_style_ws_tab(_garage_tab_btns[i], i == idx)
	if _test_car_btn != null:
		_test_car_btn.visible = (_garage_tabs()[idx].id == "pattern")
	_rebuild_garage_options()


# Reiner Test: Blender-Testmodell an-/ausschalten und die 3D-Vorschau sofort neu aufbauen.
func _on_toggle_test_car() -> void:
	Economy.test_blender_car = not Economy.test_blender_car
	if _preview_model != null:
		_preview_model.queue_free()
		_preview_model = null
	_load_preview_model()
	_frame_preview_camera()
	_apply_ws_config()
	_update_test_car_btn()


func _update_test_car_btn() -> void:
	if _test_car_btn == null:
		return
	_test_car_btn.text = "%s  %s: %s" % [Icons.CAR, tr("Test-Auto"), (tr("AN") if Economy.test_blender_car else tr("AUS"))]
	_style_ws_tab(_test_car_btn, Economy.test_blender_car)


# Beim Öffnen des Modals: Werkstatt/Garage an den Economy-Zustand angleichen. Nach einem
# Auto-Aufstieg (car_tier geändert) das gemeinsame Vorschau-Modell neu laden; sonst nur Optik.
func _refresh_werkstatt() -> void:
	if _preview_pivot == null:
		return
	if _preview_tier != Economy.get_car_tier():
		if _preview_model != null:
			_preview_model.queue_free()
			_preview_model = null
		_load_preview_model()
		_frame_preview_camera()
	_sync_paint_selection_from_economy()
	_rebuild_autos_options()
	_rebuild_garage_options()
	_refresh_garage_trophies()
	_apply_ws_config()


# Aktualisiert den Trophäen-Stand (Erfolgs-Währung) in der Garage. No-Op, solange das Panel
# noch nicht gebaut ist. Trophäen-Icon = Pokal; Wert über die Idle-Zahlenformatierung.
func _refresh_garage_trophies() -> void:
	if _garage_trophy_lbl == null:
		return
	_garage_trophy_lbl.text = "%s  %d Trophäen" % [Icons.TROPHY, Economy.get_ach_currency()]


func _rebuild_garage_options() -> void:
	if _garage_options_box == null:
		return
	for c in _garage_options_box.get_children():
		c.queue_free()

	var id = _garage_tabs()[_garage_active_tab].id
	var opts = _ws_options(id)
	var sel = int(_ws_sel.get(id, 0))
	# Kartengröße je Kategorie: viele Lackfarben → kompakte Swatches ohne Label (Name in der
	# Zusammenfassung); Muster → größere Karten mit Label.
	var cw := 56.0
	var ch := 40.0
	var show_label := false
	if id == "pattern":
		cw = 120.0; ch = 78.0; show_label = true
	const GAP = 6
	var cols = maxi(1, int((_vw() + GAP) / (cw + GAP)))
	cols = mini(cols, opts.size())
	var rows = int(ceil(float(opts.size()) / float(cols)))
	var grid_h = rows * ch + max(0, rows - 1) * GAP
	var oy = maxf(2.0, (_garage_options_box.size.y - grid_h) / 2.0)
	for i in opts.size():
		var r = int(i / cols)
		var in_row = mini(cols, opts.size() - r * cols)
		var row_w = in_row * cw + max(0, in_row - 1) * GAP
		var sx = (_vw() - row_w) / 2.0
		var ci = i - r * cols
		var card := _make_ws_option(id, opts[i], i, i == sel, cw, ch, show_label)
		card.position = Vector2(sx + ci * (cw + GAP), oy + r * (ch + GAP))
		card.size     = Vector2(cw, ch)
		_garage_options_box.add_child(card)

	_update_garage_summary()
	# Vorschau ggf. nach links rücken + Muster-Farbauswahl rechts daneben (nur Muster-Tab) füllen.
	_layout_garage_preview()
	_rebuild_pattern_colors()
	# Sammel-Erfolge prüfen (auch nachträglich, falls schon alles besessen wird).
	_check_cosmetic_collection_achievements()


# Positioniert Vorschau-Rahmen, Zusammenfassung, 3D-Viewport und Muster-Farbauswahl. Im Muster-Tab
# rückt die Vorschau nach links und die Farbspalte sitzt rechts daneben; ist dafür zu wenig Platz
# (Portrait), liegt die Farbauswahl als Streifen unter der Zusammenfassung. In allen anderen Fällen
# bleibt die Vorschau mittig und die Farbauswahl ist ausgeblendet.
func _layout_garage_preview() -> void:
	var is_pattern: bool = String(_garage_tabs()[_garage_active_tab].id) == "pattern"
	var room: bool = _vw() >= PREVIEW_W + PREV_PICK_GAP + PCOL_W + 32.0
	var side: bool = is_pattern and room
	var px := _preview_x()
	if side:
		px = (_vw() - (PREVIEW_W + PREV_PICK_GAP + PCOL_W)) / 2.0
	if _garage_frame != null:
		_garage_frame.position = Vector2(px - 3, PREVIEW_Y - 3)
	if _garage_summary_lbl != null:
		_garage_summary_lbl.position = Vector2(px, PREVIEW_Y + PREVIEW_H + 6)
	if _preview_svc != null and is_instance_valid(_preview_svc) and _preview_svc.get_parent() == _garage_container:
		_preview_svc.position = Vector2(px, PREVIEW_Y)
	if _pattern_color_box != null:
		_pattern_color_box.visible = is_pattern
		if side:
			_pattern_color_box.position = Vector2(px + PREVIEW_W + PREV_PICK_GAP, PREVIEW_Y)
			_pattern_color_box.size     = Vector2(PCOL_W, PREVIEW_H)
		else:
			_pattern_color_box.position = Vector2(_preview_x(), PREVIEW_Y + PREVIEW_H + 30)
			_pattern_color_box.size     = Vector2(PREVIEW_W, 96)


# Verfügbare Muster-Farben: Schwarz & Weiß immer gratis (Kontrast-Basis, damit ein Muster nie
# unsichtbar ist), danach ALLE über die Lackierung freigeschalteten Farben – ohne sie erneut
# kaufen zu müssen. Schwarz/Weiß werden nicht doppelt aufgeführt.
func _pattern_color_options() -> Array:
	var black := Color(0.06, 0.06, 0.08)
	var white := Color(0.92, 0.93, 0.96)
	var out: Array = [
		{"name": tr("Schwarz"), "color": black},
		{"name": tr("Weiß"),    "color": white},
	]
	for o in _ws_options("paint"):
		if not o.has("color"):
			continue
		var col: Color = o.color
		if col.is_equal_approx(black) or col.is_equal_approx(white):
			continue
		if Economy.is_paint_unlocked(col):
			out.append({"name": tr(String(o.name)), "color": col})
	return out


# Füllt die Muster-Farbauswahl (nur im Muster-Tab). Titel + scrollbares Swatch-Raster; die aktuell
# gewählte Muster-Farbe ist mit Akzentrahmen markiert. Klick → set_car_pattern_color + Live-Update.
func _rebuild_pattern_colors() -> void:
	if _pattern_color_box == null:
		return
	for c in _pattern_color_box.get_children():
		c.queue_free()
	if _garage_tabs()[_garage_active_tab].id != "pattern":
		return
	var box_w := _pattern_color_box.size.x
	var box_h := _pattern_color_box.size.y

	var title := Label.new()
	title.position = Vector2(0, 0)
	title.size     = Vector2(box_w, 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", C_TEXT_DIM)
	title.text = tr("Muster-Farbe")
	_pattern_color_box.add_child(title)

	const SW  = 30
	const GAP = 8
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 22)
	scroll.size     = Vector2(box_w, maxf(0.0, box_h - 22.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pattern_color_box.add_child(scroll)

	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(box_w, 0)
	scroll.add_child(center)

	var grid := GridContainer.new()
	grid.columns = maxi(1, int((box_w + GAP) / (float(SW) + GAP)))
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	center.add_child(grid)

	var sel_col := Economy.get_car_pattern_color()
	for entry in _pattern_color_options():
		var col: Color = entry.color
		grid.add_child(_make_pattern_color_swatch(col, String(entry.name), col.is_equal_approx(sel_col)))


func _make_pattern_color_swatch(col: Color, nm: String, selected: bool) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(30, 30)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = nm
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_border_width_all(3 if selected else 1)
	sb.border_color = C_ACCENT if selected else C_LINE
	sb.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", sb)
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_pattern_color_selected(col)
	)
	return card


func _on_pattern_color_selected(col: Color) -> void:
	Economy.set_car_pattern_color(col)
	_rebuild_garage_options()
	_apply_ws_config()


func _make_ws_option(cat: String, opt: Dictionary, idx: int, selected: bool, w: float, h: float, show_label: bool) -> Panel:
	var card := Panel.new()
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Die Kinder (Farbfläche/Streifen/Icon/Label) dürfen Klicks NICHT abfangen, sonst reagiert
	# nur der schmale Rand der Karte. Mit MOUSE_FILTER_IGNORE landet jeder Klick beim card.gui_input.

	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE2 if selected else C_SURFACE
	sb.set_border_width_all(2 if selected else 1)
	sb.border_color = C_ACCENT if selected else C_LINE
	sb.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", sb)

	var pad := 6.0
	var content_h := (h - 20.0) if show_label else (h - 2.0 * pad)
	if opt.has("color"):
		var sw := ColorRect.new()
		sw.position = Vector2(pad, pad)
		sw.size     = Vector2(w - 2.0 * pad, content_h)
		sw.color    = opt.color
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(sw)
	elif opt.has("kind"):
		# Kleine Muster-Vorschau auf der aktuellen Lackfarbe (Standardfarbe, falls kein Lack aktiv).
		var base_col: Color = Economy.get_car_paint_color() if Economy.is_car_paint_on() else Color(0.55, 0.57, 0.62)
		var bg := ColorRect.new()
		bg.position = Vector2(pad, pad)
		bg.size     = Vector2(w - 2.0 * pad, content_h)
		bg.color    = base_col
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(bg)
		_build_pattern_preview(bg, String(opt.kind), Vector2(w - 2.0 * pad, content_h), base_col)
	else:
		var icon := Label.new()
		icon.position = Vector2(0, pad)
		icon.size     = Vector2(w, content_h)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 24 if show_label else 18)
		icon.text = opt.get("icon", "◆")
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(icon)

	if show_label:
		var name_lbl := Label.new()
		name_lbl.position = Vector2(0, h - 20.0)
		name_lbl.size     = Vector2(w, 18)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", C_TEXT if selected else C_TEXT_DIM)
		name_lbl.text = tr(opt.name)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_lbl)
	else:
		card.tooltip_text = tr(opt.name)

	# Gesperrte (noch nicht gekaufte) Kosmetik abdunkeln + Schloss/Preis zeigen.
	if _is_option_locked(cat, opt, idx):
		var veil := ColorRect.new()
		veil.position = Vector2(pad, pad)
		veil.size     = Vector2(w - 2.0 * pad, content_h)
		veil.color    = Color(0.0, 0.0, 0.0, 0.5)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(veil)
		var lock := Label.new()
		lock.position = Vector2(pad, pad)
		lock.size     = Vector2(w - 2.0 * pad, content_h)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lock.add_theme_font_size_override("font_size", 16 if show_label else 13)
		lock.add_theme_color_override("font_color", C_TEXT)
		lock.text = "%s\n%d %s" % [Icons.LOCK, Economy.COSMETIC_COST, Icons.TROPHY] if show_label else Icons.LOCK
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lock)
		card.tooltip_text = tr("%s – kaufen für %d Trophäen") % [tr(opt.name), Economy.COSMETIC_COST]

	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_ws_option_selected(cat, idx)
	)
	return card


# Ist diese Garage-Option noch gesperrt (Kosmetik, die erst mit Trophäen gekauft werden muss)?
# „Original"-Lack (kein Color) und Muster „Keins" (idx 0) sind immer frei.
func _is_option_locked(cat: String, opt: Dictionary, idx: int) -> bool:
	if cat == "paint":
		return opt.has("color") and not Economy.is_paint_unlocked(opt.color)
	if cat == "pattern":
		return not Economy.is_pattern_unlocked(idx)
	return false


# Mini-Vorschau eines Musters auf einer Karte (rein dekorativ). parent ist die Farbfläche (base_col).
func _build_pattern_preview(parent: Control, kind: String, sz: Vector2, base_col: Color) -> void:
	var patt := Economy.get_car_pattern_color()
	match kind:
		"stripes":
			var n := 5
			var sw := sz.x / float(n * 2 - 1)
			for s in range(n):
				var st := ColorRect.new()
				st.position = Vector2(s * 2.0 * sw, 0)
				st.size     = Vector2(sw, sz.y)
				st.color    = patt
				st.mouse_filter = Control.MOUSE_FILTER_IGNORE
				parent.add_child(st)
		"diagonal":
			# Diagonale Balken über versetzte, gedrehte Rechtecke angedeutet.
			var n2 := 6
			var step := sz.x / float(n2)
			for s in range(n2 + 4):
				var st := ColorRect.new()
				st.color = patt
				st.size  = Vector2(step * 0.5, sz.y * 2.0)
				st.position = Vector2((s - 2) * step, -sz.y * 0.5)
				st.rotation = -0.6
				st.pivot_offset = Vector2.ZERO
				st.mouse_filter = Control.MOUSE_FILTER_IGNORE
				parent.add_child(st)
			parent.clip_contents = true
		"checker":
			var cols := 4
			var rows := 3
			var cwd := sz.x / float(cols)
			var chd := sz.y / float(rows)
			for ry in range(rows):
				for cx in range(cols):
					if (cx + ry) % 2 == 0:
						continue
					var sq := ColorRect.new()
					sq.position = Vector2(cx * cwd, ry * chd)
					sq.size     = Vector2(cwd, chd)
					sq.color    = patt
					sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
					parent.add_child(sq)
		"dots":
			var cols2 := 4
			var rows2 := 3
			var cwd2 := sz.x / float(cols2)
			var chd2 := sz.y / float(rows2)
			var d := minf(cwd2, chd2) * 0.5
			for ry in range(rows2):
				for cx in range(cols2):
					var dotp := Panel.new()
					var dsb := StyleBoxFlat.new()
					dsb.bg_color = patt
					dsb.set_corner_radius_all(int(d / 2.0))
					dotp.add_theme_stylebox_override("panel", dsb)
					dotp.position = Vector2(cx * cwd2 + (cwd2 - d) / 2.0, ry * chd2 + (chd2 - d) / 2.0)
					dotp.size     = Vector2(d, d)
					dotp.mouse_filter = Control.MOUSE_FILTER_IGNORE
					parent.add_child(dotp)
		"gradient":
			# Vertikaler Verlauf von base_col (oben) nach pattern_color (unten) über Stufen.
			var steps := 8
			for s in range(steps):
				var t := float(s) / float(steps - 1)
				var seg := ColorRect.new()
				seg.position = Vector2(0, t * sz.y)
				seg.size     = Vector2(sz.x, sz.y / float(steps) + 1.0)
				seg.color    = base_col.lerp(patt, t)
				seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
				parent.add_child(seg)


func _on_ws_option_selected(cat: String, idx: int) -> void:
	var opts = _ws_options(cat)
	var opt: Dictionary = opts[idx] if idx >= 0 and idx < opts.size() else {}
	# Gesperrte Kosmetik nicht sofort kaufen, sondern erst per Modal bestätigen lassen.
	if _is_option_locked(cat, opt, idx):
		_open_cosmetic_confirm(cat, idx, opt)
		return
	_ws_sel[cat] = idx
	# Lackierung/Muster persistent merken → 3D-Autos (Vorschau wie ingame) übernehmen es live.
	if cat == "paint":
		var col = opt.get("color", null)
		Economy.set_car_paint(col != null, col if col != null else Economy.get_car_paint_color())
	elif cat == "pattern":
		Economy.set_car_pattern(idx)
	_rebuild_garage_options()
	_apply_ws_config()


# Öffnet das Kauf-Bestätigungs-Modal für eine gesperrte Kosmetik (Farbe/Muster). Merkt sich die
# ausstehende Auswahl; gekauft wird erst nach Klick auf „Kaufen" (_on_cosmetic_confirmed).
func _open_cosmetic_confirm(cat: String, idx: int, opt: Dictionary) -> void:
	if _cosmetic_confirm == null or _cosmetic_confirm_lbl == null:
		return
	_cosmetic_pending_cat = cat
	_cosmetic_pending_idx = idx
	var kind_word := tr("die Farbe") if cat == "paint" else tr("das Muster")
	var nm := tr(String(opt.get("name", "?")))
	var have := Economy.get_ach_currency()
	var can_afford := have >= Economy.COSMETIC_COST
	# Preis + Währungssymbol in der Währungsfarbe (Trophäen-Gold) hervorheben.
	var msg := tr("[center]Möchten Sie %s \"%s\" für [color=#%s]%d %s[/color] kaufen?") % [
		kind_word, nm, C_CLAIM_GOLD.to_html(false), Economy.COSMETIC_COST, Icons.TROPHY]
	if not can_afford:
		# Hinweis, warum „Kaufen" ausgegraut ist: wie viele Trophäen noch fehlen.
		var missing := Economy.COSMETIC_COST - have
		msg += "\n" + (tr("[color=#%s]Dir fehlen %d %s.[/color]") % [C_ACCENT_RD.to_html(false), missing, Icons.TROPHY])
	msg += "[/center]"
	_cosmetic_confirm_lbl.text = msg
	# „Kaufen" ausgrauen, wenn das Trophäen-Guthaben nicht reicht.
	if _cosmetic_yes_btn != null:
		_cosmetic_yes_btn.disabled = not can_afford
	_cosmetic_confirm.visible = true


# „Kaufen" im Kosmetik-Modal: Trophäen abbuchen und – bei Erfolg – die Kosmetik direkt auswählen
# und anwenden. Reicht das Guthaben nicht, Modal schließen und kurzen Hinweis zeigen.
func _on_cosmetic_confirmed() -> void:
	var cat := _cosmetic_pending_cat
	var idx := _cosmetic_pending_idx
	_cosmetic_confirm.visible = false
	if cat == "" or idx < 0:
		return
	var opts = _ws_options(cat)
	var opt: Dictionary = opts[idx] if idx < opts.size() else {}
	var bought := Economy.buy_paint(opt.color) if cat == "paint" else Economy.buy_pattern(idx)
	if not bought:
		_flash_garage_summary(tr("Zu wenig Trophäen – %d nötig (Erfolge bringen welche).") % Economy.COSMETIC_COST)
		return
	_refresh_garage_trophies()
	# Kosmetik-Erfolge (erste Kosmetik / alle Lacke / alle Muster) werden in _rebuild_garage_options()
	# weiter unten geprüft – dieser Aufruf deckt also auch den frischen Kauf ab.
	_ws_sel[cat] = idx
	if cat == "paint":
		var col = opt.get("color", null)
		Economy.set_car_paint(col != null, col if col != null else Economy.get_car_paint_color())
	elif cat == "pattern":
		Economy.set_car_pattern(idx)
	_rebuild_garage_options()
	_apply_ws_config()


# Schaltet die Kosmetik-Erfolge frei: erste Kosmetik besessen + ALLE Lackfarben / ALLE Muster.
# Wird sowohl nach einem Kauf als auch beim (Neu-)Aufbau der Garage aufgerufen, damit bereits
# erfüllte Bedingungen auch nachträglich greifen (unlock_achievement ist idempotent).
func _check_cosmetic_collection_achievements() -> void:
	var owns_any := false

	var all_paints := true
	for o in _ws_options("paint"):
		if o.has("color"):
			if Economy.is_paint_unlocked(o.color):
				owns_any = true
			else:
				all_paints = false
	if all_paints:
		Economy.unlock_achievement("all_paints")

	var all_patterns := true
	var pats = _ws_options("pattern")
	for i in pats.size():
		if i == 0:
			continue   # idx 0 = „Keins" (immer frei, keine echte Kosmetik)
		if Economy.is_pattern_unlocked(i):
			owns_any = true
		else:
			all_patterns = false
	if all_patterns:
		Economy.unlock_achievement("all_patterns")

	if owns_any:
		Economy.unlock_achievement("first_cosmetic")


func _build_cosmetic_confirm(parent: Control) -> void:
	# Wie das Prestige-/Ascend-Overlay: dimmt den Modal-Inhalt und zentriert ein Bestätigungs-Panel.
	var ph_area := _vh() - TOP_H - BOT_H
	_cosmetic_confirm = Control.new()
	_cosmetic_confirm.position = Vector2(0, 0)
	_cosmetic_confirm.size     = Vector2(_vw(), ph_area)
	_cosmetic_confirm.visible  = false
	parent.add_child(_cosmetic_confirm)

	var dim := ColorRect.new()
	dim.position     = Vector2(0, 0)
	dim.size         = Vector2(_vw(), ph_area)
	dim.color        = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_cosmetic_confirm.add_child(dim)

	const PW = 460
	const PH = 230
	var panel := Panel.new()
	panel.position = Vector2((_vw() - PW) / 2.0, (ph_area - PH) / 2.0)
	panel.size     = Vector2(PW, PH)
	var psb := StyleBoxFlat.new()
	psb.bg_color = C_BG
	psb.border_color = C_CLAIM_GOLD          # Währungsfarbe (Trophäen-Gold) als Rahmen
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", psb)
	_cosmetic_confirm.add_child(panel)

	var title := Label.new()
	title.position = Vector2(0, 22)
	title.size     = Vector2(PW, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_CLAIM_GOLD)
	title.text = "%s  %s" % [Icons.TROPHY, tr("KAUFEN?")]
	_emboss(title, 0.7)
	panel.add_child(title)

	_cosmetic_confirm_lbl = RichTextLabel.new()
	_cosmetic_confirm_lbl.bbcode_enabled = true
	_cosmetic_confirm_lbl.fit_content    = true
	_cosmetic_confirm_lbl.scroll_active  = false
	_cosmetic_confirm_lbl.position = Vector2(24, 74)
	_cosmetic_confirm_lbl.size     = Vector2(PW - 48, 90)
	_cosmetic_confirm_lbl.add_theme_font_size_override("normal_font_size", 15)
	_cosmetic_confirm_lbl.add_theme_color_override("default_color", C_TEXT)
	panel.add_child(_cosmetic_confirm_lbl)

	var yes := Button.new()
	yes.position = Vector2(24, PH - 58)
	yes.size     = Vector2((PW - 60) / 2.0, 40)
	yes.focus_mode = Control.FOCUS_NONE
	yes.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	yes.add_theme_font_size_override("font_size", 14)
	yes.text = "%s  %s" % [Icons.TROPHY, tr("Kaufen")]
	yes.add_theme_stylebox_override("normal",  _sbf(C_CLAIM_GOLD.darkened(0.55), C_CLAIM_GOLD))
	yes.add_theme_stylebox_override("hover",   _sbf(C_CLAIM_GOLD.darkened(0.40), C_CLAIM_GOLD))
	yes.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_CLAIM_GOLD))
	# Ausgegrauter Zustand (zu wenig Trophäen): dezenter Rahmen, gedimmter Text. Wird je Öffnen gesetzt.
	yes.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
	yes.add_theme_color_override("font_color", C_CLAIM_GOLD)
	yes.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	yes.pressed.connect(_on_cosmetic_confirmed)
	panel.add_child(yes)
	_cosmetic_yes_btn = yes

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
	no.pressed.connect(func(): _cosmetic_confirm.visible = false)
	panel.add_child(no)


# Kurzer Hinweistext in der Vorschau-Zusammenfassung (z. B. bei zu wenig Trophäen). Wird beim
# nächsten _update_garage_summary() (Auswahländerung) wieder überschrieben.
func _flash_garage_summary(msg: String) -> void:
	if _garage_summary_lbl != null:
		_garage_summary_lbl.text = msg


func _update_garage_summary() -> void:
	if _garage_summary_lbl == null:
		return
	var pi = int(_ws_sel.get("paint", 0))
	var paint_opts = _ws_options("paint")
	var paint_nm = String(paint_opts[pi].name) if pi < paint_opts.size() else "?"
	var qi = int(_ws_sel.get("pattern", 0))
	var pat_opts = _ws_options("pattern")
	var pat_nm = String(pat_opts[qi].name) if qi < pat_opts.size() else "?"
	_garage_summary_lbl.text = tr("Lackierung: %s  ·  Muster: %s") % [tr(paint_nm), tr(pat_nm)]


# Tab „Autos": Auto-Prestige-Panel (Aufstieg auf die nächste Auto-Stufe gegen Voll-Reset + ×4 ⭐).
func _build_autos_options() -> void:
	var tier := Economy.get_car_tier()
	var cost := Economy.get_car_ascend_cost()
	var can  := Economy.can_ascend_car()

	var info := Label.new()
	info.position = Vector2(0, 2)
	info.size     = Vector2(_vw(), 40)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", C_TEXT)
	var pts  := int(pow(Economy.CAR_ASCEND_POINT_MULT, tier + 1))
	var step := int(pow(Economy.CAR_ASCEND_COUNT_MULT, tier + 1))
	info.text = tr("Aktuelles Auto: %s (Stufe %d)\nUpgrade: %s  →  Reset inkl. Prestige-Baum, danach ×%d %s und %d Baum-Knoten je Prestige") % [
		tr(_car_tier_name(tier)), tier, Economy.format_currency(cost), pts, Icons.STAR, step]
	_ws_options_box.add_child(info)

	var btn := Button.new()
	btn.size     = Vector2(300, 36)
	btn.position = Vector2((_vw() - 300) / 2.0, 50)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 14)
	btn.disabled = not can
	btn.text = "%s  %s" % [Icons.ARROW_BIG_UP, tr("Auto upgraden")]
	if can:
		btn.add_theme_stylebox_override("normal",  _sbf(C_STAR_BG, C_STAR))
		btn.add_theme_stylebox_override("hover",   _sbf(C_STAR_BG_HI, C_STAR))
		btn.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_STAR))
		btn.add_theme_color_override("font_color", C_STAR)
		btn.pressed.connect(_on_ascend_pressed)
	else:
		btn.add_theme_stylebox_override("normal", _sbf(C_SURFACE, C_LINE))
		btn.add_theme_color_override("font_color", C_TEXT_DIM)
		btn.tooltip_text = tr("Erst genug Guthaben sammeln (%s)") % Economy.format_currency(cost)
	_ws_options_box.add_child(btn)

	if _ws_summary_lbl != null:
		if tier >= 1:
			_ws_summary_lbl.text = tr("Es fährt nur das %s-Auto · 4 normale Autos = 1 fahrendes Auto (Lack/Muster folgt für dieses Modell)") % tr(_car_tier_name(tier))
		else:
			_ws_summary_lbl.text = "Nach dem Upgrade fährt nur noch das neue Auto auf der Strecke."


func _car_tier_name(tier: int) -> String:
	match tier:
		0: return "Standard"
		1: return "Eric"
		_: return "Tier %d" % tier


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
	# Nach einem _do_rebuild() existiert _preview_svc noch – teuer, daher wiederverwenden.
	if _preview_svc != null and is_instance_valid(_preview_svc):
		parent.add_child(_preview_svc)
		_preview_svc.position = pos
		_preview_svc.size     = sz
		return

	var svc := SubViewportContainer.new()
	svc.position     = pos
	svc.size         = sz
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(svc)
	_preview_svc = svc   # gemeinsame Vorschau, wird zwischen Werkstatt/Garage umgehängt

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
	# Modell der aktuellen Auto-Prestige-Stufe (Stufe 0 = Test-Auto mit Umfärb-Maske).
	# Reiner Test-Schalter (Garage „Test-Auto"): überschreibt mit dem Blender-Testmodell.
	var mpath := Paths.MODEL_TEST_CAR_BLENDER if Economy.test_blender_car else Economy.get_car_tier_model()
	if ResourceLoader.exists(mpath):
		model = (load(mpath) as PackedScene).instantiate()
	else:
		# Platzhalter-Box falls kein Modell vorhanden
		model = Node3D.new()
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.15, 0.5)
		mi.mesh  = box
		model.add_child(mi)
	_preview_pivot.add_child(model)
	MaterialUtil.apply_alpha_scissor(model)
	MaterialUtil.apply_unshaded(model)
	_preview_model = model
	_preview_tier  = Economy.get_car_tier()
	_collect_meshes(model)


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_preview_meshes.append(node)
	for c in node.get_children():
		_collect_meshes(c)


# Kombiniertes AABB aller VisualInstance3D unterhalb von root (im root-lokalen Raum).
func _calc_aabb(root: Node3D) -> AABB:
	return _aabb_in_space(root, root)


# Kombinierte AABB aller VisualInstance3D unter `node`, ausgedrückt im lokalen Raum von `space`.
# Mit space == node erhält man die lokale AABB; mit einem gemeinsamen Pivot bleibt das Ergebnis
# drehunabhängig (Pivot-Rotation wird herausgerechnet) – wichtig fürs Re-Rahmen beim Cycling.
func _aabb_in_space(node: Node3D, space: Node3D) -> AABB:
	var result := AABB()
	var has := false
	var inv := space.global_transform.affine_inverse()
	var stack: Array = [node]
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
	# Blender-Testmodell: keine Maske, nur die grüne Karosserie-Fläche umfärben (Color-Key).
	if Economy.test_blender_car:
		_apply_preview_colorkey()
		_update_garage_summary()
		return
	# Lack/Muster brauchen die Umfärb-Maske (nur Test-Auto, Stufe 0). Höhere Tier-Modelle haben
	# keine Maske → Originaltextur zeigen (kein Override), wie ingame.
	var opts = _ws_options("paint")
	var pi = int(_ws_sel.get("paint", 0))
	var col = null
	if Economy.get_car_tier() == 0 and pi >= 0 and pi < opts.size():
		col = opts[pi].get("color", null)
	# Material auch ohne Lack anlegen, sobald ein Muster gewählt ist (Muster auf Standardfarbe).
	var want_mat := col != null or Economy.get_car_pattern() != 0
	for m in _preview_meshes:
		if not is_instance_valid(m):
			continue
		if want_mat:
			(m as MeshInstance3D).material_override = _make_paint_material(col if col != null else Economy.get_car_paint_color())
		else:
			(m as MeshInstance3D).material_override = null
	_update_garage_summary()


# Vorschau des Blender-Testmodells: färbt NUR die grüne Karosserie-Materialfläche um (Surface-Override),
# gesteuert über die gewählte Lackfarbe in der „Lackierung". „Original" → Override weg (Grün zurück).
func _apply_preview_colorkey() -> void:
	for m in _preview_meshes:
		if not is_instance_valid(m):
			continue
		var mi := m as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var src := mesh.surface_get_material(si)
			if _is_test_body_material(src):
				mi.set_surface_override_material(si, _make_body_material(src))


# Wie in Car3D: Lack-/Muster-Material für die Karosserie-Fläche (Lackfarbe bzw. Originalfarbe +
# optionales Muster). Ohne Lack und ohne Muster → null (Originalmaterial behalten).
func _make_body_material(orig: Material) -> ShaderMaterial:
	var paint_on := Economy.is_car_paint_on()
	var pat := Economy.get_car_pattern()
	if not paint_on and pat == 0:
		return null
	if _flat_shader == null and ResourceLoader.exists(Paths.SHADER_CAR_PAINT_FLAT):
		_flat_shader = load(Paths.SHADER_CAR_PAINT_FLAT)
	var base: Color = Economy.get_car_paint_color()
	if not paint_on and orig is BaseMaterial3D:
		base = (orig as BaseMaterial3D).albedo_color
	var mat := ShaderMaterial.new()
	mat.shader = _flat_shader
	mat.set_shader_parameter("body_color", base)
	mat.set_shader_parameter("pattern_mode", pat)
	mat.set_shader_parameter("pattern_color", Economy.get_car_pattern_color())
	if orig is BaseMaterial3D:
		mat.set_shader_parameter("metallic_v", (orig as BaseMaterial3D).metallic)
		mat.set_shader_parameter("roughness_v", (orig as BaseMaterial3D).roughness)
	return mat


# Erkennt die umfärbbare Karosserie-Fläche (heller Grün-Korpus) per Material-Name, ersatzweise per Farbe.
func _is_test_body_material(mat: Material) -> bool:
	if mat == null:
		return false
	if mat.resource_name == Paths.TEST_CAR_BODY_MATERIAL:
		return true
	if mat is BaseMaterial3D:
		# Grün klar dominant (Verhältnis-Test → robust gegen linear/sRGB); schließt das gelbgrüne
		# „Light"-Material (hoher Rotanteil) aus.
		var c := (mat as BaseMaterial3D).albedo_color
		return c.g > 0.4 and c.g > c.r * 1.8 and c.g > c.b * 1.8
	return false


# Shader-Material für die Maskenlackierung (Albedo + Maske gecacht).
var _paint_shader: Shader = null
var _flat_shader: Shader = null   # Lack/Muster für flache Material-Farben (Blender-Testmodell)

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
	mat.set_shader_parameter("paint_on", Economy.is_car_paint_on())
	# Muster (0 = keins) nur über die Maskenbereiche legen.
	mat.set_shader_parameter("pattern_mode", Economy.get_car_pattern())
	mat.set_shader_parameter("pattern_color", Economy.get_car_pattern_color())
	return mat


# ── Upgrade-Reihen ────────────────────────────────────────────────────────────

func _add_upgrade_rows(vbox: VBoxContainer, row_w: float) -> void:
	_upgrade_buttons.clear()
	# Hover-Ziele zeigen auf die gleich freigegebenen Info-Boxen → Liste + offenen Hinweis verwerfen.
	_hint_targets_upg.clear()
	_clear_upgrade_hover()
	# Kleiner Abstand oben, damit der Inhalt nicht an der Trennlinie unter dem Umschalter klebt.
	# Liegt hier (statt im Container), damit der Rebuild ihn nicht entfernt.
	var utop := Control.new()
	utop.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(utop)

	# Upgrade-Karten zentriert im Raster (responsive Spaltenzahl, Karte 230 breit).
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(center)

	var grid := GridContainer.new()
	grid.columns = clampi(int((row_w + 20 - 32 + 12) / (UPG_CARD_W + 12)), 1, 4)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	center.add_child(grid)

	# Feste Reihenfolge nach STARTPREIS aufsteigend (niedrigster zuerst). Hartkodiert – sortiert
	# sich NICHT bei jeder Preisänderung neu. base_cost: tilebonus 10, speed 50, endmult 500,
	# drive_time 1000, bonus_plus5 2000, bonus_plus10 4000, bonus_mult15 200k, car_count 1M.
	var ids = ["tilebonus", "speed", "endmult", "drive_time",
			   "bonus_plus5", "bonus_plus10", "bonus_mult15", "car_count"]
	for id in ids:
		if Economy.UPGRADES[id].get("category", "") == "hidden":
			continue
		grid.add_child(_make_upgrade_card(id))

	var bpad := Control.new()
	bpad.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(bpad)
	# Hinweis: Das „Auto 2"-Kombinieren ist in die Werkstatt (Tab „Autos", Auto-Prestige) umgezogen.


# Tabler-Icon je Upgrade (id → Glyph; rendert dank Font-Fallback inline). Unbekannt → Blitz.
func _upgrade_icon(id: String) -> String:
	match id:
		"tilebonus":    return Icons.ROAD
		"speed":        return Icons.GAUGE
		"endmult":      return Icons.MATH
		"drive_time":   return Icons.CLOCK
		"bonus_plus5":  return Icons.PLUS
		"bonus_plus10": return Icons.PLUS
		"bonus_mult15": return Icons.FLAME
		"car_count":    return Icons.CAR
	return Icons.BOLT


const UPG_CARD_W = 230
const UPG_CARD_H = 196

# Eine Upgrade-Karte: Icon, Name, Stufe + Fortschrittsbalken, Effekt (von → zu) und Kauf-Knopf.
# Gleiches Karten-Gefühl wie die Prestige-Knoten – deutlich aufgeräumter als die früheren Zeilen.
func _make_upgrade_card(id: String) -> Panel:
	var lv     := Economy.get_upgrade_level(id)
	var mx     := Economy.get_max_level(id)
	var maxed  := Economy.is_maxed(id)
	var has_lv := lv > 0

	var card := Panel.new()
	card.custom_minimum_size = Vector2(UPG_CARD_W, UPG_CARD_H)
	var csb := StyleBoxFlat.new()
	csb.bg_color     = C_SURFACE
	csb.border_color = C_ACCENT if has_lv else C_LINE
	csb.set_border_width_all(2 if has_lv else 1)
	csb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", csb)

	# Icon
	var icon := Label.new()
	icon.position = Vector2(0, 14)
	icon.size     = Vector2(UPG_CARD_W, 36)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 30)
	icon.add_theme_color_override("font_color", C_ACCENT if has_lv else C_TEXT)
	icon.text = _upgrade_icon(id)
	card.add_child(icon)

	# Name
	var name_lbl := Label.new()
	name_lbl.position = Vector2(8, 52)
	name_lbl.size     = Vector2(UPG_CARD_W - 16, 22)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.text = Economy.get_upgrade_name(id).to_upper()
	card.add_child(name_lbl)

	# Stufe
	var lv_lbl := Label.new()
	lv_lbl.position = Vector2(8, 76)
	lv_lbl.size     = Vector2(UPG_CARD_W - 16, 16)
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.add_theme_font_size_override("font_size", 11)
	lv_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lv_lbl.text = tr("Stufe %d / %d") % [lv, mx]
	card.add_child(lv_lbl)

	# Stufen-Fortschrittsbalken (gefüllt nach lv/max)
	var bar_w := UPG_CARD_W - 48
	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(24, 96)
	bar_bg.size     = Vector2(bar_w, 6)
	bar_bg.color    = C_BG
	card.add_child(bar_bg)
	var frac := 0.0 if mx <= 0 else clampf(float(lv) / float(mx), 0.0, 1.0)
	if frac > 0.0:
		var bar_fill := ColorRect.new()
		bar_fill.position = Vector2(24, 96)
		bar_fill.size     = Vector2(bar_w * frac, 6)
		bar_fill.color    = C_ACCENT
		card.add_child(bar_fill)

	# Effekt (von → zu, bzw. nur aktuell bei MAX/Tempo)
	var eff_lbl := Label.new()
	eff_lbl.position = Vector2(8, 110)
	eff_lbl.size     = Vector2(UPG_CARD_W - 16, 32)
	eff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eff_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff_lbl.add_theme_font_size_override("font_size", 13)
	eff_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.58))
	if id != "speed" and not maxed:
		eff_lbl.text = "%s → %s" % [Economy.effect_text(id, lv), Economy.effect_text(id, lv + 1)]
	else:
		eff_lbl.text = Economy.effect_text(id, lv)
	card.add_child(eff_lbl)

	# Kauf-Knopf unten
	var buy_btn := Button.new()
	buy_btn.position = Vector2(12, UPG_CARD_H - 48)
	buy_btn.size     = Vector2(UPG_CARD_W - 24, 38)
	buy_btn.focus_mode = Control.FOCUS_NONE
	buy_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	buy_btn.add_theme_font_size_override("font_size", 13)
	if maxed:
		buy_btn.text     = Icons.CHECK + " MAX"
		buy_btn.disabled = true
		buy_btn.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
		buy_btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	else:
		_set_buy_btn_label(buy_btn, id, false, 13)
		_style_upgrade_btn(buy_btn, Economy.can_buy(id))
		_upgrade_buttons.append({"btn": buy_btn, "id": id})
	buy_btn.pressed.connect(_on_buy_upgrade.bind(id))
	card.add_child(buy_btn)

	# Ganze Karte ist der Hover-Bereich für den Erklär-Hinweis – nur wenn ein Text hinterlegt ist.
	if Lang.hint(id) != "":
		_hint_targets_upg.append({"id": id, "area": card})

	return card


func _on_buy_upgrade(id: String) -> void:
	var ok := false
	if Economy.buy_max_mode:
		ok = Economy.buy_upgrade_max(id) > 0
	else:
		ok = Economy.buy_upgrade(id)
	if ok:
		# Upgrades leben jetzt nur noch im Shop-Tab (Kategorie-Index 1)
		if _active_modal_tab == 0 and _active_shop_cat == 1:
			_rebuild_shop_upgrades()


# ── Upgrade-Hinweise (Tooltips) ──────────────────────────────────────────────────

# Verborgenes Hinweis-Fenster + Cursor-Ladekreis. Als letzte Kinder angelegt → ganz oben.
func _build_hint_overlay() -> void:
	_hint_panel = Panel.new()
	_hint_panel.size = Vector2(360, 116)
	_hint_panel.visible = false
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE2
	sb.border_color = C_ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	_hint_panel.add_theme_stylebox_override("panel", sb)
	add_child(_hint_panel)

	_hint_label = Label.new()
	_hint_label.position = Vector2(12, 10)
	_hint_label.size = Vector2(336, 96)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", C_TEXT)
	_hint_panel.add_child(_hint_label)

	_hint_ring = HintRing.new()
	_hint_ring.position = Vector2.ZERO
	_hint_ring.size = Vector2(_vw(), _vh())
	add_child(_hint_ring)


# Pro Frame (nur Shop-Tab): Kästchen/Karte unter der Maus suchen, Ring füllen, Hinweis zeigen.
func _update_upgrade_hint(delta: float) -> void:
	var target := _hint_target_under_mouse()
	var id: String = String(target.get("id", ""))
	if id == "":
		if _hover_id != "" or _hint_id != "":
			_clear_upgrade_hover()
		return
	if id != _hover_id:
		_hover_id = id
		_hover_elapsed = 0.0
		if _hint_id != "":
			_hide_hint()
	if _hint_id == id:
		_hint_ring.set_progress(0.0)   # bereits sichtbar
		return
	_hover_elapsed += delta
	_hint_ring.set_progress(_hover_elapsed / HINT_DELAY)
	if _hover_elapsed >= HINT_DELAY:
		_show_upgrade_hint(id, target["area"])
		_hint_ring.set_progress(0.0)


# Kästchen/Karte, deren Bereich gerade unter der Maus liegt (oder {}). Je nach Shop-Kategorie
# wird die passende Ziel-Liste durchsucht (0 = Streckenteile, 1 = Upgrades).
func _hint_target_under_mouse() -> Dictionary:
	var mouse := _hint_panel.get_global_mouse_position()
	var targets: Array = _hint_targets_tile if _active_shop_cat == 0 else _hint_targets_upg
	for t in targets:
		var area: Control = t["area"]
		if is_instance_valid(area) and area.get_global_rect().has_point(mouse):
			return t
	return {}


# Hinweis-Fenster mit dem Text füllen und unter dem Kästchen positionieren.
func _show_upgrade_hint(id: String, anchor: Control) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	_hint_label.text = Lang.hint(id).replace("{value}", _hint_value(id))
	var r := anchor.get_global_rect()
	var px := clampf(r.position.x, 8.0, _vw() - _hint_panel.size.x - 8.0)
	var py := clampf(r.position.y + r.size.y + 6.0, 8.0, _vh() - _hint_panel.size.y - 8.0)
	_hint_panel.position = Vector2(px, py)
	_hint_panel.visible = true
	_hint_id = id


func _hide_hint() -> void:
	_hint_id = ""
	if _hint_panel != null:
		_hint_panel.visible = false


func _clear_upgrade_hover() -> void:
	_hover_id = ""
	_hover_elapsed = 0.0
	if _hint_ring != null:
		_hint_ring.set_progress(0.0)
	_hide_hint()


# Ersetzt {value} im Hinweistext durch den aktuellen Upgrade-Wert.
func _hint_value(id: String) -> String:
	if id == "tilebonus":
		var v := Economy.get_car_tile_bonus(0)
		return ("%d" % int(round(v))) if absf(v - round(v)) < 0.001 else ("%.1f" % v)
	return ""


# Super-Auto („Auto 2"): MEHRFACH kaufbar (kein Unlock). Preis steigt je Kauf; kaufbar immer, wenn
# genug freie Standard-Autos (4 je weiterem Super-Auto) und Tempo ≥ Schwelle vorhanden sind.
func _make_super_car_row(row_w: float) -> Control:
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

	# Hover-Bereich für den Erklär-Hinweis zum Kombinations-Auto.
	if Lang.hint("super_car") != "":
		_hint_targets_upg.append({"id": "super_car", "area": info})

	var n_lbl := Label.new()
	n_lbl.text = "%s  ×%d" % [tr("AUTO 2 (KOMBINATION)"), Economy.get_super_car_count()]
	n_lbl.add_theme_font_size_override("font_size", 13)
	n_lbl.add_theme_color_override("font_color", C_TEXT)
	info.add_child(n_lbl)

	var d_lbl := Label.new()
	d_lbl.text = tr("%d Autos → 1 Super-Auto  ·  Tempo ≥%d nötig  ·  +%s/Feld · Tempo ÷%d") % [
		Economy.SUPER_CAR_COST_CARS, Economy.SUPER_CAR_REQ_SPEED,
		Economy.format_currency(Economy.SUPER_CAR_TILE_BONUS),
		int(Economy.SUPER_CAR_SPEED_DIV)]
	d_lbl.add_theme_font_size_override("font_size", 11)
	d_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	info.add_child(d_lbl)

	row.add_child(_hpad(12))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 40)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 12)
	btn.text = Icons.ARROW_UP + "  %s %s" % [Economy.format_currency(Economy.get_super_car_cost()), Icons.COIN]
	_style_upgrade_btn(btn, Economy.can_buy_super_car())
	btn.pressed.connect(_on_buy_super_car)
	_upgrade_buttons.append({"btn": btn, "id": "super_car"})
	row.add_child(btn)
	row.add_child(_hpad(16))
	return row


func _on_buy_super_car() -> void:
	if Economy.buy_super_car():
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
		# Super-Auto ist kein gestuftes UPGRADES-Upgrade → eigener Kaufbarkeits-Check.
		if id == "super_car":
			_style_upgrade_btn(btn, Economy.can_buy_super_car())
			continue
		if Economy.is_maxed(id):
			continue
		_style_upgrade_btn(btn, Economy.can_buy(id))
		# Im Max-Modus hängt die „+N · Gesamtkosten"-Anzeige am Geldstand → live mitziehen.
		if Economy.buy_max_mode:
			_set_buy_btn_label(btn, id, false, 13)


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

const C_STAR       := Color(0.74, 0.48, 0.97)   # Prestige-Lila (Sternfarbe) – klar abgegrenzt von Geld-Gold
const C_STAR_BG    := Color(0.20, 0.12, 0.30)   # dunkles Lila: gefüllter Prestige-Button-Hintergrund (normal)
const C_STAR_BG_HI := Color(0.28, 0.17, 0.40)   # dunkles Lila: Prestige-Button-Hintergrund (hover)

func _build_prestige_panel(parent: Control, cy: int, ch: int) -> void:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(container)
	_tab_panels.append(container)

	# ── Kopfbereich ──────────────────────────────────────────────────────────
	# Oben links nur noch die Anzahl bisheriger Prestiges (die ⭐-Punkte stehen jetzt in der
	# oberen Leiste). Der große Auslöser rechts ist ein Fortschrittsbalken: er füllt sich von
	# links nach rechts mit dem Geld auf dem Konto, bis 2 Mio. erreicht sind.
	_prestige_points_lbl = Label.new()
	_prestige_points_lbl.position = Vector2(24, 14)
	_prestige_points_lbl.size     = Vector2(420, 54)
	_prestige_points_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prestige_points_lbl.add_theme_font_size_override("font_size", 22)
	_prestige_points_lbl.add_theme_color_override("font_color", C_STAR)
	container.add_child(_prestige_points_lbl)

	# Großer Prestige-Auslöser rechts oben (Fortschrittsbalken + Text-Overlay).
	_prestige_btn = Button.new()
	_prestige_btn.position = Vector2(_vw() - 24 - 360, 12)
	_prestige_btn.size     = Vector2(360, 56)
	_prestige_btn.focus_mode = Control.FOCUS_NONE
	_prestige_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_prestige_btn.clip_contents = true   # Sicherheits-Clip: hält Maske/Füllung/Text in der Buttonfläche
	_prestige_btn.pressed.connect(_on_prestige_pressed)
	container.add_child(_prestige_btn)

	# Fortschrittsfüllung: EIN Shader zeichnet zugleich die runde Buttonform (SDF, gleiche Rundung 8),
	# den Füllstand (links→rechts, senkrechte Kante) und einen animierten Effekt. Liegt UNTER dem Text.
	var fill_sh := Shader.new()
	fill_sh.code = PRESTIGE_FILL_SHADER
	_prestige_fill_mat = ShaderMaterial.new()
	_prestige_fill_mat.shader = fill_sh
	_prestige_fill_mat.set_shader_parameter("size_px",   _prestige_btn.size)
	_prestige_fill_mat.set_shader_parameter("radius_px", 8.0)
	_prestige_fill = ColorRect.new()
	_prestige_fill.position     = Vector2(0, 0)
	_prestige_fill.size         = _prestige_btn.size   # volle Buttonfläche; Shader maskiert Form + Reveal
	_prestige_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prestige_fill.material     = _prestige_fill_mat
	_prestige_btn.add_child(_prestige_fill)

	# Text-Overlay (zentriert, über der Füllung).
	_prestige_btn_lbl = Label.new()
	_prestige_btn_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prestige_btn_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prestige_btn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prestige_btn_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_prestige_btn_lbl.add_theme_font_size_override("font_size", 16)
	# Dunkle Kontur, damit der Text über der animierten Gold-Füllung UND dem dunklen Rest lesbar bleibt.
	_prestige_btn_lbl.add_theme_constant_override("outline_size", 4)
	_prestige_btn_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prestige_btn.add_child(_prestige_btn_lbl)

	# Trennlinie
	var line := ColorRect.new()
	line.position = Vector2(0, 80)
	line.size     = Vector2(_vw(), 1)
	line.color    = C_LINE
	container.add_child(line)

	# ── Tech-Baum (horizontal scrollbar) ─────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 88)
	scroll.size     = Vector2(_vw(), ch - 88)
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
	# Ein Tile-Gate-Knoten (Rampe/Steilwand/Looping/Portal/Tribüne) kann die Shop-Freischaltung gerade
	# erlaubt haben → Tile-Karten neu bewerten, damit „🔒 Prestige-Baum nötig" sofort zu „🔒 N 💰" wird.
	if _tiles_grid != null and is_instance_valid(_tiles_grid):
		_populate_tiles_grid()


# Nur Kopfbereich (Punkte, verdient, Prestige-Knopf) aktualisieren – günstig, läuft im _process.
func _refresh_prestige_action() -> void:
	if _prestige_points_lbl == null:
		return
	# Kopf oben links: nur die Anzahl bisheriger Prestiges (⭐-Punkte stehen in der oberen Leiste).
	_prestige_points_lbl.text = "%s  %s" % [Icons.RECYCLE, tr("%d Prestiges durchgeführt") % Economy.get_prestige_count()]

	var pending := Economy.prestige_pending_points()
	var cur     := Economy.get_currency()
	var target  := Economy.PRESTIGE_K
	var progress: float = clampf(float(cur) / target, 0.0, 1.0)

	# Füllstand + Effekt an den Shader. Performance-Modus → einfarbig (0, keine Animation),
	# sonst der animierte Glitzer+Wasser-Effekt (5).
	_prestige_fill_mat.set_shader_parameter("progress", progress)
	_prestige_fill_mat.set_shader_parameter("mode", 0 if Display.performance_mode else 5)

	if pending >= 1.0:
		_prestige_btn_lbl.text = "%s  PRESTIGE  →  +%s %s" % [Icons.RECYCLE, Economy.format_currency(pending), Icons.STAR]
		_prestige_btn.disabled = false
		# Volle, leuchtende Prestige-Gold-Füllung.
		_prestige_fill_mat.set_shader_parameter("base_color", Color(C_STAR.r, C_STAR.g, C_STAR.b, 0.90))
		_prestige_btn.add_theme_stylebox_override("normal",  _sbf(C_STAR_BG, C_STAR))
		_prestige_btn.add_theme_stylebox_override("hover",   _sbf(C_STAR_BG_HI, C_STAR))
		_prestige_btn.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_STAR))
		_prestige_btn_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		# Noch nicht erreicht → Fortschritt (Geld / Ziel). Füllung weiterhin in Prestige-Gold, nur dezenter.
		_prestige_btn_lbl.text = "%s  %s / %s %s" % [
			Icons.RECYCLE, Economy.format_currency(cur), Economy.format_currency(int(target)), Icons.COIN]
		_prestige_btn.disabled = true
		_prestige_fill_mat.set_shader_parameter("base_color", Color(C_STAR.r, C_STAR.g, C_STAR.b, 0.62))
		var sb := _sbf(C_SURFACE, C_STAR.darkened(0.45))
		_prestige_btn.add_theme_stylebox_override("normal",   sb)
		_prestige_btn.add_theme_stylebox_override("disabled", sb)
		_prestige_btn_lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))


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
			arrow.add_theme_color_override("font_color", C_STAR if next_unlocked else C_LINE)
			arrow.text = "→"
			_prestige_tree_box.add_child(arrow)


# Tabler-Icon je Prestige-Knoten (id → Glyph). Liegt hier statt in PRESTIGE_NODES (const),
# weil die Glyphen aus dem Icons-Autoload kommen.
func _prestige_node_icon(id: String) -> String:
	match id:
		"income":          return Icons.X
		"car_start":       return Icons.CAR
		"track":           return Icons.FLAG_3
		"earning":         return Icons.TRENDING_UP
		"car_points":      return Icons.STEERING_WHEEL
		"drive_time_inf":  return Icons.CLOCK
		"tilebonus_start": return Icons.COIN
		"keep_unlocks":    return Icons.KEY
		"points_mult":     return Icons.STAR
		"wall_unlock":     return Icons.MOUNTAIN
		"speed_start":     return Icons.GAUGE
		"loop_unlock":     return Icons.INFINITY
		"ramp_unlock":     return Icons.ROCKET
		"grid":            return Icons.LAYOUT_GRID
		"endmult_start":   return Icons.SPARKLES
		"portal_unlock":   return Icons.CIRCLE_DASHED
		"stand_unlock":    return Icons.STADIUM
	return Icons.STAR


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
	csb.border_color = C_STAR if has_level else (C_LINE if active else C_LINE.darkened(0.2))
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
	icon.text = _prestige_node_icon(id)
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
	lv_lbl.text = tr("Stufe %d / %d") % [level, Economy.get_prestige_node_max(id)]
	card.add_child(lv_lbl)

	# Effekt (von → zu, bzw. nur aktuell wenn maxed)
	var eff_lbl := Label.new()
	eff_lbl.position = Vector2(6, 116)
	eff_lbl.size     = Vector2(CARD_W - 12, 30)
	eff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eff_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	eff_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.58))
	eff_lbl.add_theme_font_size_override("font_size", 14)
	# Einmalige Freischaltungen (max 1 Stufe) zeigen NUR ihren Zustand – „gesperrt" bzw. nach dem
	# Kauf „freigeschaltet", kein „von → zu". Gestufte Knoten weiter mit „aktuell → nächste".
	if maxed or Economy.get_prestige_node_max(id) <= 1:
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
		btn.text     = Icons.LOCK + " " + _prestige_prereq_text(id)
		btn.disabled = true
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_stylebox_override("disabled", _sbf(C_SURFACE, C_ACCENT_MU.darkened(0.5)))
		btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	elif maxed:
		btn.text     = Icons.CHECK + " MAX (Stufe %d)" % level
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", _sbf(Color(0.10, 0.26, 0.15), Color(0.30, 0.75, 0.42)))
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.95, 0.65))
	else:
		var cost := Economy.get_prestige_node_cost(id)
		btn.text = "%d %s" % [cost, Icons.STAR]
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_prestige_buy_btn(btn, Economy.can_buy_prestige_node(id))
		btn.pressed.connect(_on_buy_prestige_node.bind(id))
	card.add_child(btn)

	return card


# Freischalt-Text eines Knotens: er erscheint nach dem N. Prestige (positionsbasiert).
func _prestige_prereq_text(id: String) -> String:
	var need := Economy.get_prestige_node_unlock_count(id)
	if need <= 0:
		return "gesperrt"
	return "nach %d. Prestige" % need


# Stil eines Prestige-Kauf-Knopfs (leistbar = Gold, sonst gedämpft).
func _style_prestige_buy_btn(btn: Button, can: bool) -> void:
	if can:
		btn.add_theme_stylebox_override("normal",  _sbf(C_STAR_BG, C_STAR))
		btn.add_theme_stylebox_override("hover",   _sbf(C_STAR_BG_HI, C_STAR))
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
	_prestige_confirm_lbl.text = tr("Du erhältst %s %s.\n\nGeld, Upgrades, freigeschaltete Teile und ALLE\nStrecken werden zurückgesetzt. Prestige-Boni bleiben.") % [Economy.format_currency(Economy.prestige_pending_points()), Icons.STAR]
	_prestige_confirm.visible = true


func _build_prestige_confirm(parent: Control) -> void:
	# Das Modal-Panel beginnt bei y=TOP_H und lässt unten die Run-Bar frei → Overlay daran ausrichten.
	var ph_area := _vh() - TOP_H - BOT_H
	_prestige_confirm = Control.new()
	_prestige_confirm.position = Vector2(0, 0)
	_prestige_confirm.size     = Vector2(_vw(), ph_area)
	_prestige_confirm.visible  = false
	parent.add_child(_prestige_confirm)

	var dim := ColorRect.new()
	dim.position     = Vector2(0, 0)
	dim.size         = Vector2(_vw(), ph_area)
	dim.color        = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_prestige_confirm.add_child(dim)

	const PW = 460
	const PH = 280
	var panel := Panel.new()
	panel.position = Vector2((_vw() - PW) / 2.0, (ph_area - PH) / 2.0)
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
	_emboss(title, 0.7)
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
	yes.text = Icons.RECYCLE + "  Prestige"
	yes.add_theme_stylebox_override("normal",  _sbf(C_STAR_BG, C_STAR))
	yes.add_theme_stylebox_override("hover",   _sbf(C_STAR_BG_HI, C_STAR))
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


# ── Auto-Prestige ausführen (mit Bestätigung) ──────────────────────────────────

func _on_ascend_pressed() -> void:
	if not Economy.can_ascend_car():
		return
	var next_tier := Economy.get_car_tier() + 1
	var pts  := int(pow(Economy.CAR_ASCEND_POINT_MULT, next_tier))
	var step := int(pow(Economy.CAR_ASCEND_COUNT_MULT, next_tier))
	_ascend_confirm_lbl.text = tr("Dein Auto wird zu %s aufgewertet (Stufe %d).\n\nGeld, Upgrades, Teile UND der Prestige-Baum\nwerden komplett zurückgesetzt. Danach fährt nur\nnoch dieses Auto, du erhältst ×%d %s pro Prestige\nund jedes Prestige schaltet %d Baum-Knoten frei.") % [
		tr(_car_tier_name(next_tier)), next_tier, pts, Icons.STAR, step]
	_ascend_confirm.visible = true


func _build_ascend_confirm(parent: Control) -> void:
	var ph_area := _vh() - TOP_H - BOT_H
	_ascend_confirm = Control.new()
	_ascend_confirm.position = Vector2(0, 0)
	_ascend_confirm.size     = Vector2(_vw(), ph_area)
	_ascend_confirm.visible  = false
	parent.add_child(_ascend_confirm)

	var dim := ColorRect.new()
	dim.position     = Vector2(0, 0)
	dim.size         = Vector2(_vw(), ph_area)
	dim.color        = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_ascend_confirm.add_child(dim)

	const PW = 480
	const PH = 290
	var panel := Panel.new()
	panel.position = Vector2((_vw() - PW) / 2.0, (ph_area - PH) / 2.0)
	panel.size     = Vector2(PW, PH)
	var psb := StyleBoxFlat.new()
	psb.bg_color = C_BG
	psb.border_color = C_STAR
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", psb)
	_ascend_confirm.add_child(panel)

	var title := Label.new()
	title.position = Vector2(0, 22)
	title.size     = Vector2(PW, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_STAR)
	title.text = "AUTO UPGRADEN?"
	_emboss(title, 0.7)
	panel.add_child(title)

	_ascend_confirm_lbl = Label.new()
	_ascend_confirm_lbl.position = Vector2(24, 64)
	_ascend_confirm_lbl.size     = Vector2(PW - 48, 140)
	_ascend_confirm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ascend_confirm_lbl.add_theme_font_size_override("font_size", 13)
	_ascend_confirm_lbl.add_theme_color_override("font_color", C_TEXT)
	panel.add_child(_ascend_confirm_lbl)

	var yes := Button.new()
	yes.position = Vector2(24, PH - 58)
	yes.size     = Vector2((PW - 60) / 2.0, 40)
	yes.focus_mode = Control.FOCUS_NONE
	yes.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	yes.add_theme_font_size_override("font_size", 14)
	yes.text = "%s  %s" % [Icons.ARROW_BIG_UP, tr("Upgraden")]
	yes.add_theme_stylebox_override("normal",  _sbf(C_STAR_BG, C_STAR))
	yes.add_theme_stylebox_override("hover",   _sbf(C_STAR_BG_HI, C_STAR))
	yes.add_theme_stylebox_override("pressed", _sbf(C_SURFACE, C_STAR))
	yes.add_theme_color_override("font_color", C_STAR)
	yes.pressed.connect(_on_ascend_confirmed)
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
	no.pressed.connect(func(): _ascend_confirm.visible = false)
	panel.add_child(no)


func _on_ascend_confirmed() -> void:
	var ok := Economy.ascend_car()
	_ascend_confirm.visible = false
	if not ok:
		return
	# Voll-Reset (inkl. Prestige-Baum) → Streckenteile + Upgrades beim nächsten Öffnen neu, zurück
	# auf Strecke 1 im 2D-Bauplan mit frischen, leeren Strecken.
	_tiles_dirty = true
	GameHUD.reset_after_prestige()
	get_tree().change_scene_to_file(Paths.SCENE_BUILDER)
	# Modal offen lassen, auf dem Werkstatt-Tab (Index 2) mit dem neuen Auto.
	open()
	_on_modal_tab(2)


# ── UI-Hilfsfunktionen ────────────────────────────────────────────────────────

func _add_cat_header(vbox: VBoxContainer, title: String) -> HBoxContainer:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(pad)

	var row := HBoxContainer.new()
	row.add_child(_hpad(16))
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", C_TEXT)
	_emboss(lbl)
	row.add_child(lbl)
	vbox.add_child(row)
	return row

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
	sb.content_margin_left = 12; sb.content_margin_right  = 12
	sb.content_margin_top  = 6;  sb.content_margin_bottom = 6
	# 3D-Effekt: weicher Schlagschatten → angehobener Tab.
	sb.shadow_color  = Color(0, 0, 0, 0.4)
	sb.shadow_size   = 3
	sb.shadow_offset = Vector2(0, 2)
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_constant_override("outline_size", 1)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))


# Icon-Glyph je Shop-Kategorie (rendert dank Font-Fallback inline im normalen Button-Text).
func _shop_cat_icon(id: String) -> String:
	match id:
		"tiles":    return Icons.ROAD
		"upgrades": return Icons.TRENDING_UP
	return ""


# Reiter der Shop-Top-Nav (links in der Leiste). Aktiv = leicht hellere Fläche mit Akzent-Unterstrich
# und hellem Text, inaktiv = Leistenfarbe mit gedimmtem Text. Hellerer Hover-Stil als Klick-Feedback.
func _style_shop_toggle(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color            = C_SURFACE2 if active else C_SURFACE
	sb.border_width_bottom = 3
	sb.border_color        = C_ACCENT if active else Color(0, 0, 0, 0)
	sb.content_margin_left = 24; sb.content_margin_right  = 24
	sb.content_margin_top  = 8;  sb.content_margin_bottom = 8
	var sb_hover: StyleBoxFlat = sb.duplicate()
	sb_hover.bg_color = sb.bg_color.lightened(0.08)
	for state in ["normal", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 14)


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


# Geprägter 3D-Look für Überschriften: dunkler Schlagschatten nach unten-rechts.
func _emboss(lbl: Label, strength: float = 0.55) -> void:
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, strength))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
