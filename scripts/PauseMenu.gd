extends CanvasLayer

const LANGUAGES     = [["Deutsch", "de"], ["English", "en"]]
const WINDOW_MODES  = ["Fenster", "Rahmenlos", "Vollbild"]
const UI_SCALES     = [["Klein (80%)", 0.8], ["Normal (100%)", 1.0], ["Groß (125%)", 1.25], ["Sehr groß (150%)", 1.5]]
# Kategorien der Side-Nav in den Einstellungen
const SETTINGS_CATS = [["🌐", "Allgemein"], ["🔊", "Audio"], ["🖥", "Anzeige"], ["🎮", "Steuerung"]]
# Steuerungsarten der Kategorie „Steuerung" (Pill-/Segment-Auswahl). Reihenfolge = Index.
const CTRL_SUBTABS = ["Klick modus", "Drag & Drop", "Mobile"]
const CTRL_MODE_IDS = ["click", "drag", "mobile"]
const CTRL_DESCS = [
	"Wähle ein Teil in der Palette und klicke dann auf das Baufeld, um es zu setzen.",
	"Ziehe Teile direkt aus der Palette auf das Baufeld – beim Loslassen wird gesetzt.",
	"Touch-Bedienung fürs Handy: Ziehen & Ablegen plus optionaler Drehen-Knopf.",
]
const SETTINGS_BASE = Vector2i(960, 540)   # Basis-Auflösung für UI-Skalierung

# Inhaltsbereich der Einstellungen = links der GameHUD-Seitenleiste, unter der Top-Bar und
# über der unteren Leiste – damit die rechte Nav (und Top-/Bottom-Bar) sichtbar/bedienbar bleibt.
const NAV_W  = 150
const TOP_H  = 50
const BOT_H  = 42
const VIEW_W = 960
const VIEW_H = 540

# Discord-artige Graupalette – siehe GameHUD.gd (alle 6 Dateien synchron halten).
const C_SURFACE   := Color(0.169, 0.176, 0.192)   # #2b2d31
const C_SURFACE2  := Color(0.220, 0.227, 0.251)   # #383a40
const C_ACCENT    := Color(0.345, 0.396, 0.949)   # #5865f2 Blurple
const C_ACCENT_MU := Color(0.290, 0.310, 0.490)
const C_ACCENT_RD := Color(0.929, 0.259, 0.271)   # #ed4245
const C_TEXT      := Color(0.859, 0.871, 0.882)   # #dbdee1
const C_TEXT_DIM  := Color(0.580, 0.608, 0.643)   # #949ba4
const C_LINE      := Color(0.247, 0.255, 0.278)   # #3f4147

var settings := ConfigFile.new()

var _dim_bg:             ColorRect   # Vollbild-Abdunkelung (für Einstellungen ausgeblendet)
var _pause_panel:        Control
var _settings_panel:     Control
var _quit_modal:         Control
var _discard_modal:      Control
var _save_modal:         Control

var _save_status_lbl: Label
var _settings_dirty:  bool = false
# Wie wurden die Einstellungen geöffnet? true = über das Pause-Menü (Zurück → Pause),
# false = direkt über „Optionen" in der Seitenleiste (Zurück → zurück ins Spiel).
var _settings_from_pause: bool = false

var _lang_option:    OptionButton
var _master_slider:  HSlider
var _music_slider:   HSlider
var _sfx_slider:     HSlider
var _window_option:    OptionButton
var _ui_scale_option:  OptionButton
var _rotate_switch:    CheckButton
var _cheat_switch:     CheckButton
var _lbl_master_val: Label
var _lbl_music_val:  Label
var _lbl_sfx_val:    Label

var _settings_nav_btns:   Array[Button]  = []
var _settings_cat_panels: Array[Control] = []

# Steuerung – Modus-Auswahl
var _ctrl_subtab:      int           = 0   # aktiver Modus-Index (0 click / 1 drag / 2 mobile)
var _ctrl_subtab_btns: Array[Button] = []
var _ctrl_desc_lbl:    Label
var _ctrl_rotate_label: Label
var _ctrl_mobile_hint: Label

var _loading_settings := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Über allem: GameHUD (20) und dem "Fahrt beenden"-Button im 3D (21) sollen
	# hinter dem Pause-Overlay liegen, damit sie der Dimmer abdeckt.
	layer = 100
	visible = false

	settings.load(Paths.SETTINGS_FILE)

	_dim_bg = ColorRect.new()
	_dim_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_bg.color = Color(0, 0, 0, 0.94)
	add_child(_dim_bg)

	_pause_panel        = _build_pause_panel()
	_settings_panel     = _build_settings_panel()
	_quit_modal         = _build_quit_modal()
	_discard_modal      = _build_discard_modal()
	_save_modal         = _build_save_modal()

	_show_pause()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var scene := get_tree().current_scene
	if scene == null or scene.name == "MainMenu":
		return
	get_viewport().set_input_as_handled()
	if visible:
		_resume()
	else:
		_open()


# ── Öffnen / Schließen ────────────────────────────────────────────────────────

func _open() -> void:
	visible = true
	get_tree().paused = true
	_show_pause()


# Öffentlicher Einstieg (z. B. vom Zahnrad-Button im GameHUD). Im Hauptmenü ohne Wirkung.
func open_pause() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.name == "MainMenu":
		return
	if not visible:
		_open()


# Öffentlicher Einstieg „Optionen" aus der Seitenleiste: öffnet DIREKT die Einstellungen
# (kein Pause-Menü dazwischen). Zurück/Speichern/Verwerfen führen dann zurück ins Spiel.
func open_settings() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.name == "MainMenu":
		return
	visible = true
	get_tree().paused = true
	_settings_from_pause = false
	_show_settings()


func _resume() -> void:
	# Einstellungen automatisch speichern (kein Speichern-Button mehr).
	_autosave_settings()
	get_tree().paused = false
	visible = false


# Schreibt geänderte Einstellungen auf die Platte, falls die Einstellungen offen & „dirty" sind.
# Wird beim Verlassen (ESC, „Strecke"/Seitenwechsel über die Nav) aufgerufen.
func _autosave_settings() -> void:
	if _settings_panel != null and _settings_panel.visible and _settings_dirty:
		settings.save(Paths.SETTINGS_FILE)
		_settings_dirty = false


# ── Pause-Hauptmenü ───────────────────────────────────────────────────────────

func _build_pause_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 5)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", C_ACCENT)
	vbox.add_child(title)

	_add_spacer(vbox, 14)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(400, 1)
	divider.color = C_ACCENT
	vbox.add_child(divider)

	_add_spacer(vbox, 12)

	_add_btn(vbox, "01", "Weiterspielen",    C_ACCENT,    _resume)
	_add_btn(vbox, "02", "Einstellungen",    C_ACCENT_MU, _show_settings_from_pause)
	_add_spacer(vbox, 10)
	_add_btn(vbox, "03", "Speichern",        Color(0.15, 0.60, 0.35), _on_save_pressed)

	_save_status_lbl = Label.new()
	_save_status_lbl.text = "✓ Gespeichert!"
	_save_status_lbl.visible = false
	_save_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_status_lbl.add_theme_font_size_override("font_size", 12)
	_save_status_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
	vbox.add_child(_save_status_lbl)

	_add_btn(vbox, "04", "Spiel beenden",    C_ACCENT_RD, _on_quit_pressed)

	return center


func _on_save_pressed() -> void:
	Economy.save_game()
	_save_status_lbl.visible = true
	get_tree().create_timer(2.0).timeout.connect(
		func():
			if is_instance_valid(_save_status_lbl):
				_save_status_lbl.visible = false
	)


func _on_quit_pressed() -> void:
	Economy.save_game()
	_hide_all()
	_quit_modal.visible = true


# ── Beenden-Modal ─────────────────────────────────────────────────────────────

func _build_quit_modal() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_add_panel_title(vbox, "SPIEL BEENDEN")
	_add_hline(vbox)

	var text_lbl := Label.new()
	text_lbl.text = "Dein Spielstand wurde gespeichert."
	text_lbl.add_theme_color_override("font_color", C_TEXT)
	text_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(text_lbl)

	_add_spacer(vbox, 8)

	_add_btn(vbox, "→", "Zurück zum Hauptmenü", C_ACCENT_MU, _go_main_menu)
	_add_btn(vbox, "→", "Zurück zum Desktop",   C_ACCENT_RD, func(): get_tree().quit())

	_add_spacer(vbox, 4)
	_add_back_button(vbox, _show_pause)

	return center


func _go_main_menu() -> void:
	get_tree().paused = false
	visible = false
	get_tree().change_scene_to_file(Paths.SCENE_MAIN_MENU)


# ── Einstellungen-Panel ───────────────────────────────────────────────────────

func _build_settings_panel() -> Control:
	# Modal NUR über dem Spielbereich links der Seitenleiste, unter der Top-Bar und über der
	# unteren Leiste – so bleibt die rechte Nav (GameHUD) sichtbar und bedienbar.
	var overlay := ColorRect.new()
	overlay.position     = Vector2(0, TOP_H)
	overlay.size         = Vector2(VIEW_W - NAV_W, VIEW_H - TOP_H - BOT_H)
	overlay.color        = Color(0, 0, 0, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.118, 0.122, 0.133)   # Discord-BG
	ps.set_border_width_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_vbox.add_theme_constant_override("separation", 0)
	panel.add_child(outer_vbox)

	# Header-Leiste
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 52)
	header.add_theme_constant_override("separation", 0)
	outer_vbox.add_child(header)

	var title := Label.new()
	title.text = "EINSTELLUNGEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", C_ACCENT)
	var lpad := Control.new(); lpad.custom_minimum_size = Vector2(24, 0)
	header.add_child(lpad); header.add_child(title)

	_add_hline(outer_vbox)

	# ── Body: Top-Nav (oben) + Inhaltsbereich (darunter) ──────────────────────
	# Horizontale Kategorie-Leiste direkt unter dem Header.
	var navbar := PanelContainer.new()
	navbar.custom_minimum_size = Vector2(0, 50)
	var nav_sb := StyleBoxFlat.new()
	nav_sb.bg_color = C_SURFACE.darkened(0.18)
	nav_sb.border_width_bottom = 1
	nav_sb.border_color = C_LINE
	nav_sb.content_margin_left = 16; nav_sb.content_margin_right = 16
	nav_sb.content_margin_top = 8;   nav_sb.content_margin_bottom = 8
	navbar.add_theme_stylebox_override("panel", nav_sb)
	outer_vbox.add_child(navbar)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	navbar.add_child(nav)
	_settings_nav_btns.clear()
	for i in SETTINGS_CATS.size():
		_add_settings_nav(nav, i, SETTINGS_CATS[i][0], SETTINGS_CATS[i][1])

	# Inhaltsbereich darunter (hält alle Kategorie-Panels, eines sichtbar)
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	outer_vbox.add_child(holder)
	_settings_cat_panels.clear()

	# Kategorie 0 – Sprache
	var v0 := _new_settings_cat(holder)
	_add_section_label(v0, "SPRACHE")
	var lang_row := _make_hrow(v0)
	_make_row_label(lang_row, "Sprache:")
	_lang_option = OptionButton.new()
	_lang_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_btn(_lang_option)
	for lang in LANGUAGES:
		_lang_option.add_item(lang[0])
	_lang_option.item_selected.connect(_on_language_changed)
	lang_row.add_child(_lang_option)

	# Kategorie 1 – Audio
	var v1 := _new_settings_cat(holder)
	_add_section_label(v1, "LAUTSTÄRKE")
	var r: Array
	r = _add_slider_row(v1, "Master:")
	_master_slider = r[0]; _lbl_master_val = r[1]
	_master_slider.value_changed.connect(_on_master_volume_changed)
	r = _add_slider_row(v1, "Musik:")
	_music_slider = r[0]; _lbl_music_val = r[1]
	_music_slider.value_changed.connect(_on_music_volume_changed)
	r = _add_slider_row(v1, "Effekte:")
	_sfx_slider = r[0]; _lbl_sfx_val = r[1]
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	# Kategorie 2 – Anzeige (Modus + UI-Skalierung)
	var v2 := _new_settings_cat(holder)
	_add_section_label(v2, "ANZEIGEMODUS")
	var win_row := _make_hrow(v2)
	_make_row_label(win_row, "Modus:")
	_window_option = OptionButton.new()
	_window_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_btn(_window_option)
	for mode in WINDOW_MODES:
		_window_option.add_item(mode)
	_window_option.item_selected.connect(_on_window_mode_changed)
	win_row.add_child(_window_option)

	_add_hline(v2)
	_add_section_label(v2, "UI-SKALIERUNG")
	var scale_row := _make_hrow(v2)
	_make_row_label(scale_row, "Skalierung:")
	_ui_scale_option = OptionButton.new()
	_ui_scale_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_btn(_ui_scale_option)
	for s in UI_SCALES:
		_ui_scale_option.add_item(s[0])
	_ui_scale_option.item_selected.connect(_on_ui_scale_changed)
	scale_row.add_child(_ui_scale_option)
	var scale_hint := Label.new()
	scale_hint.text = "Skaliert das gesamte Fenster (im Vollbild ohne Wirkung)."
	scale_hint.add_theme_font_size_override("font_size", 11)
	scale_hint.add_theme_color_override("font_color", C_TEXT_DIM)
	scale_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v2.add_child(scale_hint)

	# Cheats sind jetzt ein Abschnitt der Anzeige-Kategorie (eigener Tab entfällt).
	_add_hline(v2)
	_add_section_label(v2, "CHEAT-MODUS")
	var cheat_row := _make_hrow(v2)
	_make_row_label(cheat_row, "Cheat-Modus:")
	_cheat_switch = _make_placement_switch()
	_cheat_switch.toggled.connect(_on_cheat_toggled)
	cheat_row.add_child(_cheat_switch)
	var cheat_hint := Label.new()
	cheat_hint.text = "Zeigt den Endlos-Modus (∞) und den +1B ⭐ Button in der oberen Leiste an."
	cheat_hint.add_theme_font_size_override("font_size", 11)
	cheat_hint.add_theme_color_override("font_color", C_TEXT_DIM)
	cheat_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v2.add_child(cheat_hint)

	# Kategorie 3 – Steuerung (mit Unter-Tabs: Klick modus / Drag & Drop / Mobile)
	var v3 := _new_settings_cat(holder)
	_build_steuerung_cat(v3)

	_show_settings_cat(0)

	# Kein Speichern/Zurück-Button mehr: Änderungen werden automatisch übernommen und beim
	# Schließen (über die Seitenleiste oder ESC) gespeichert. Nur ein dezenter Hinweis.
	var bot_line := ColorRect.new()
	bot_line.custom_minimum_size = Vector2(0, 1)
	bot_line.color = C_LINE
	outer_vbox.add_child(bot_line)

	var hint_row := HBoxContainer.new()
	hint_row.custom_minimum_size = Vector2(0, 40)
	outer_vbox.add_child(hint_row)

	var hpad := Control.new(); hpad.custom_minimum_size = Vector2(24, 0)
	hint_row.add_child(hpad)

	var hint := Label.new()
	hint.text = "✓  Änderungen werden automatisch gespeichert"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", C_TEXT_DIM)
	hint_row.add_child(hint)

	return overlay


# Footer-Button (Zurück/Speichern) – abgerundet, voller Rahmen, größere Klickfläche.
func _build_settings_btn(txt: String, bg: Color, border: Color) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 52)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",  _footer_btn_style(bg,                 border))
	btn.add_theme_stylebox_override("hover",   _footer_btn_style(bg.lightened(0.10), border.lightened(0.18)))
	btn.add_theme_stylebox_override("pressed", _footer_btn_style(bg.darkened(0.10),  border))
	btn.add_theme_stylebox_override("focus",   _footer_btn_style(bg,                 border))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 15)
	return btn


func _footer_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(10)
	sb.content_margin_left   = 14
	sb.content_margin_right  = 14
	sb.content_margin_top    = 12
	sb.content_margin_bottom = 12
	return sb


# Großer, gefüllter Haupt-Button (z. B. grünes „Übernehmen") – zentrierter Text, abgerundet.
func _build_primary_btn(txt: String, cb: Callable,
		bg := Color(0.15, 0.60, 0.35), border := Color(0.30, 0.85, 0.48)) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(0, 54)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",  _footer_btn_style(bg,                 border))
	btn.add_theme_stylebox_override("hover",   _footer_btn_style(bg.lightened(0.10), border.lightened(0.18)))
	btn.add_theme_stylebox_override("pressed", _footer_btn_style(bg.darkened(0.10),  border))
	btn.add_theme_stylebox_override("focus",   _footer_btn_style(bg,                 border))
	btn.add_theme_color_override("font_color",       Color(0.95, 1.0, 0.96))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(cb)
	return btn


# Dezenter Text-Link (kein Hintergrund) – z. B. „Abbrechen“ unter dem Haupt-Button.
func _build_ghost_btn(txt: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(0, 40)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal",  empty)
	btn.add_theme_stylebox_override("hover",   empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus",   empty)
	btn.add_theme_color_override("font_color",       C_TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(cb)
	return btn


# ── Settings Top-Nav ──────────────────────────────────────────────────────────

func _add_settings_nav(parent: HBoxContainer, idx: int, icon: String, label: String) -> void:
	var btn := Button.new()
	btn.text = "%s  %s" % [icon, label]
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_settings_nav(btn, idx == 0)
	btn.pressed.connect(_on_settings_nav.bind(idx))
	parent.add_child(btn)
	_settings_nav_btns.append(btn)


# Horizontale Tab-Optik: aktiver Tab mit Akzent-Balken UNTEN + gefüllter Fläche.
func _style_settings_nav(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color            = C_SURFACE2 if active else Color(0, 0, 0, 0)
	sb.border_width_bottom = 3
	sb.border_color        = C_ACCENT if active else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top  = 6;  sb.content_margin_bottom = 6
	var sb_h := sb.duplicate() as StyleBoxFlat
	if not active:
		sb_h.bg_color = C_SURFACE
	for state in ["normal", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 14)


func _on_settings_nav(idx: int) -> void:
	for i in _settings_nav_btns.size():
		_style_settings_nav(_settings_nav_btns[i], i == idx)
	_show_settings_cat(idx)


func _show_settings_cat(idx: int) -> void:
	for i in _settings_cat_panels.size():
		_settings_cat_panels[i].visible = (i == idx)


# ── Steuerung-Kategorie: Modus-Auswahl (Klick / Drag & Drop / Mobile) ──────────
# Die Pill-/Segment-Tabs OBEN sind keine reinen Ansichts-Tabs mehr, sondern wählen
# die aktive Steuerungsart. „Klick modus" = placement_mode quick, „Drag & Drop" = slow,
# „Mobile" = slow + Touch-Extras (Drehen-Knopf, Pause-Eintrag in der Side-Nav).

func _build_steuerung_cat(parent: VBoxContainer) -> void:
	_add_section_label(parent, "STEUERUNGSART")

	# Segment-/Pill-Auswahl: bestimmt den aktiven Steuerungsmodus.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	parent.add_child(bar)
	_ctrl_subtab_btns.clear()
	for i in CTRL_SUBTABS.size():
		var b := Button.new()
		b.text = CTRL_SUBTABS[i]
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_ctrl_subtab(b, i == 0)
		b.pressed.connect(_on_ctrl_mode_selected.bind(i))
		bar.add_child(b)
		_ctrl_subtab_btns.append(b)

	# Beschreibung des aktiven Modus
	_ctrl_desc_lbl = Label.new()
	_ctrl_desc_lbl.add_theme_font_size_override("font_size", 11)
	_ctrl_desc_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	_ctrl_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(_ctrl_desc_lbl)

	# Mobile-spezifische Einstellungen – nur im Mobile-Modus bedienbar, sonst ausgegraut.
	_add_hline(parent)
	_add_section_label(parent, "MOBILE-EINSTELLUNGEN")
	var rotate_row := _make_hrow(parent)
	_ctrl_rotate_label = _make_row_label(rotate_row, "Drehen-Knopf:")
	_rotate_switch = _make_placement_switch()
	_rotate_switch.toggled.connect(_on_rotate_btn_toggled)
	rotate_row.add_child(_rotate_switch)
	_ctrl_mobile_hint = Label.new()
	_ctrl_mobile_hint.text = "Zeigt im 2D-Bauplan einen ↻-Knopf zum Drehen. Im Mobile-Modus standardmäßig an, in den anderen Modi deaktiviert."
	_ctrl_mobile_hint.add_theme_font_size_override("font_size", 11)
	_ctrl_mobile_hint.add_theme_color_override("font_color", C_TEXT_DIM)
	_ctrl_mobile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(_ctrl_mobile_hint)

	# Anzeige initial setzen (echter Wert kommt aus _sync_settings_ui).
	_apply_ctrl_mode(0, false)


# Modus-Wechsel durch Klick auf eine Pill (persistiert + wendet an).
func _on_ctrl_mode_selected(idx: int) -> void:
	_apply_ctrl_mode(idx, true)


# Setzt den aktiven Steuerungsmodus. persist=false → nur UI/Anzeige (für _sync_settings_ui).
func _apply_ctrl_mode(idx: int, persist: bool) -> void:
	_ctrl_subtab = idx
	for i in _ctrl_subtab_btns.size():
		_style_ctrl_subtab(_ctrl_subtab_btns[i], i == idx)
	var mode_id: String = CTRL_MODE_IDS[idx]
	var is_mobile := mode_id == "mobile"
	_ctrl_desc_lbl.text = CTRL_DESCS[idx]
	_set_mobile_settings_enabled(is_mobile)

	if not persist or _loading_settings:
		return

	# Pause-Eintrag in der rechten Side-Nav nur im Mobile-Modus (GameHUD lädt den
	# Startzustand selbst; hier nur auf echte Nutzer-Wechsel reagieren).
	GameHUD.set_mobile_mode(is_mobile)
	settings.set_value("options", "control_mode", mode_id)
	# placement_mode für Main: click → quick, drag/mobile → slow (Ziehen/Touch).
	var pm := "quick" if mode_id == "click" else "slow"
	settings.set_value("options", "placement_mode", pm)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("set_placement_mode"):
		scene.set_placement_mode(pm)

	# Erstmaliger Wechsel IN den Mobile-Modus: Drehen-Knopf standardmäßig AN.
	if is_mobile and not settings.has_section_key("options", "rotate_button"):
		settings.set_value("options", "rotate_button", true)
	var rot := is_mobile and bool(settings.get_value("options", "rotate_button", true))
	_loading_settings = true
	_rotate_switch.button_pressed = rot
	_loading_settings = false
	_rotate_switch.text = "An" if rot else "Aus"
	_apply_rotate_button(is_mobile)
	_settings_dirty = true


# Aktiviert/Deaktiviert die Mobile-Einstellungen (Drehen-Knopf).
func _set_mobile_settings_enabled(enabled: bool) -> void:
	_rotate_switch.disabled = not enabled
	_rotate_switch.modulate = Color(1, 1, 1, 1.0 if enabled else 0.45)
	_ctrl_rotate_label.add_theme_color_override("font_color", C_TEXT_DIM if enabled else C_LINE)


# Wendet die effektive Drehen-Knopf-Sichtbarkeit an (nur im Mobile-Modus sichtbar).
func _apply_rotate_button(is_mobile: bool) -> void:
	var rot := is_mobile and bool(settings.get_value("options", "rotate_button", true))
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("set_rotate_button_visible"):
		scene.set_rotate_button_visible(rot)


# Pill-/Segment-Tab: aktiv = gefüllte abgerundete Fläche + Akzent-Balken unten.
func _style_ctrl_subtab(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color            = C_SURFACE2 if active else C_SURFACE.darkened(0.15)
	sb.set_corner_radius_all(10)
	sb.border_width_bottom = 3 if active else 0
	sb.border_color        = C_ACCENT if active else Color(0, 0, 0, 0)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top  = 7;  sb.content_margin_bottom = 7
	var sb_h := sb.duplicate() as StyleBoxFlat
	if not active:
		sb_h.bg_color = C_SURFACE
	for state in ["normal", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 13)


# Erstellt einen scrollbaren Kategorie-Bereich im Inhalts-Holder und gibt dessen VBox zurück.
func _new_settings_cat(holder: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.visible = false
	holder.add_child(scroll)
	_settings_cat_panels.append(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	return vbox


# ── UI-Skalierung ─────────────────────────────────────────────────────────────

func _on_ui_scale_changed(index: int) -> void:
	if _loading_settings: return
	var factor: float = UI_SCALES[index][1]
	settings.set_value("options", "ui_scale", factor)
	_apply_ui_scale(factor)
	_settings_dirty = true


func _apply_ui_scale(factor: float) -> void:
	# Wirkt nur im Fenster-/Rahmenlos-Modus; Vollbild skaliert ohnehin auf den Monitor.
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return
	var size := Vector2i(int(round(SETTINGS_BASE.x * factor)), int(round(SETTINGS_BASE.y * factor)))
	DisplayServer.window_set_size(size)
	var screen_id := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen_id)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


# ── Panel-Wechsel ─────────────────────────────────────────────────────────────

func _hide_all() -> void:
	# Standard: Vollbild-Abdunkelung an (Pause-Menü/Modals). Einstellungen schalten sie ab,
	# damit die rechte Seitenleiste sichtbar bleibt.
	if _dim_bg != null:
		_dim_bg.visible = true
	_pause_panel.visible        = false
	_settings_panel.visible     = false
	_quit_modal.visible         = false
	_discard_modal.visible      = false
	_save_modal.visible         = false


func _show_pause() -> void:
	_hide_all()
	_pause_panel.visible = true


# Einstellungen aus dem Pause-Menü heraus öffnen (Zurück führt wieder ins Pause-Menü).
func _show_settings_from_pause() -> void:
	_settings_from_pause = true
	_show_settings()


func _show_settings() -> void:
	_hide_all()
	# Keine Vollbild-Abdunkelung → die rechte Seitenleiste (GameHUD) bleibt sichtbar.
	if _dim_bg != null:
		_dim_bg.visible = false
	_settings_panel.visible = true
	_settings_dirty = false
	_sync_settings_ui()
	_on_settings_nav(0)


# Sind die Einstellungen gerade offen? (für die Nav-Koordination in GameHUD)
func is_settings_open() -> bool:
	return visible and _settings_panel != null and _settings_panel.visible


# Von der Seitenleiste (GameHUD) gerufen, wenn von den Einstellungen zu einer anderen
# Seite (oder „Strecke") gewechselt wird: Einstellungen schließen, Spiel fortsetzen.
func close_settings() -> void:
	if is_settings_open():
		_resume()


# Einstellungen verlassen: je nach Einstieg zurück ins Pause-Menü oder direkt ins Spiel.
func _exit_settings() -> void:
	if _settings_from_pause:
		_show_pause()
	else:
		_resume()
		# Nav-Highlight in der Seitenleiste (Optionen → Strecke) zurücksetzen.
		GameHUD._on_modal_closed()


# ── UI-Hilfsfunktionen ────────────────────────────────────────────────────────

func _add_btn(parent: VBoxContainer, num: String, label: String,
		accent: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(400, 56)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	btn.add_theme_stylebox_override("normal",  _btn_style(C_SURFACE,                 accent.darkened(0.4)))
	btn.add_theme_stylebox_override("hover",   _btn_style(C_SURFACE.lightened(0.05), accent))
	btn.add_theme_stylebox_override("pressed", _btn_style(C_SURFACE2,                accent))
	btn.add_theme_stylebox_override("focus",   _btn_style(C_SURFACE,                 accent.darkened(0.4)))

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 0)
	btn.add_child(hbox)

	var lpad := Control.new()
	lpad.custom_minimum_size = Vector2(18, 0)
	lpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lpad)

	var num_lbl := Label.new()
	num_lbl.text = num
	num_lbl.custom_minimum_size = Vector2(32, 0)
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num_lbl.add_theme_font_size_override("font_size", 11)
	num_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(num_lbl)

	var text_lbl := Label.new()
	text_lbl.text = label.to_upper()
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_lbl.add_theme_font_size_override("font_size", 14)
	text_lbl.add_theme_color_override("font_color", C_TEXT)
	text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_lbl)

	var arrow := Label.new()
	arrow.text = "▶"
	arrow.custom_minimum_size = Vector2(48, 0)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 11)
	arrow.add_theme_color_override("font_color", accent)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(arrow)

	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 3
	sb.border_color = border
	sb.content_margin_left   = 0
	sb.content_margin_right  = 0
	sb.content_margin_top    = 0
	sb.content_margin_bottom = 0
	return sb


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.10, 0.15)
	sb.border_width_left = 3
	sb.border_color = C_ACCENT
	sb.content_margin_left   = 28
	sb.content_margin_right  = 28
	sb.content_margin_top    = 28
	sb.content_margin_bottom = 28
	return sb


func _make_hrow(parent: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	return row


func _make_row_label(row: HBoxContainer, text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	row.add_child(lbl)
	return lbl


func _add_slider_row(parent: VBoxContainer, label_text: String) -> Array:
	var row := _make_hrow(parent)
	_make_row_label(row, label_text)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var track_sb := StyleBoxFlat.new()
	track_sb.bg_color = C_SURFACE
	track_sb.content_margin_top    = 4
	track_sb.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track_sb)

	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = C_ACCENT.darkened(0.2)
	fill_sb.content_margin_top    = 4
	fill_sb.content_margin_bottom = 4
	slider.add_theme_stylebox_override("grabber_area", fill_sb)

	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = "100%"
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_lbl.add_theme_color_override("font_color", C_TEXT)
	row.add_child(val_lbl)

	return [slider, val_lbl]


func _add_panel_title(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", C_ACCENT)
	parent.add_child(lbl)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	parent.add_child(lbl)


func _add_hline(parent: Node) -> void:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = C_LINE
	parent.add_child(line)


func _add_spacer(parent: VBoxContainer, height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)


func _style_option_btn(opt: OptionButton) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE
	sb.border_width_left = 2
	sb.border_color = C_ACCENT_MU
	sb.content_margin_left   = 8
	sb.content_margin_right  = 8
	sb.content_margin_top    = 6
	sb.content_margin_bottom = 6
	opt.add_theme_stylebox_override("normal",  sb)
	opt.add_theme_stylebox_override("hover",   sb)
	opt.add_theme_stylebox_override("pressed", sb)
	opt.add_theme_stylebox_override("focus",   sb)
	opt.add_theme_color_override("font_color", C_TEXT)


func _add_back_button(parent: VBoxContainer, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = "← ZURÜCK"
	btn.custom_minimum_size = Vector2(0, 48)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",  _btn_style(C_SURFACE,                 C_ACCENT_MU))
	btn.add_theme_stylebox_override("hover",   _btn_style(C_SURFACE.lightened(0.05), C_ACCENT))
	btn.add_theme_stylebox_override("pressed", _btn_style(C_SURFACE2,                C_ACCENT))
	btn.add_theme_stylebox_override("focus",   _btn_style(C_SURFACE,                 C_ACCENT_MU))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(cb)
	parent.add_child(btn)


# ── Einstellungen Sync ────────────────────────────────────────────────────────

func _sync_settings_ui() -> void:
	_loading_settings = true

	var lang := settings.get_value("options", "language", "de") as String
	for i in LANGUAGES.size():
		if LANGUAGES[i][1] == lang:
			_lang_option.selected = i
			break

	_master_slider.value    = settings.get_value("options", "master_volume", 100.0)
	_music_slider.value     = settings.get_value("options", "music_volume",  80.0)
	_sfx_slider.value       = settings.get_value("options", "sfx_volume",    100.0)
	_window_option.selected = settings.get_value("options", "window_mode",   0)

	var sf := float(settings.get_value("options", "ui_scale", 1.0))
	for i in UI_SCALES.size():
		if abs(float(UI_SCALES[i][1]) - sf) < 0.001:
			_ui_scale_option.selected = i
			break

	# Steuerungsart (Modus-Auswahl). Fallback: aus altem placement_mode ableiten.
	var mode := String(settings.get_value("options", "control_mode", _infer_default_ctrl_mode()))
	var midx := CTRL_MODE_IDS.find(mode)
	if midx < 0:
		midx = 0
	_apply_ctrl_mode(midx, false)   # nur Anzeige – nicht erneut speichern
	var is_mobile: bool = String(CTRL_MODE_IDS[midx]) == "mobile"
	var rotbtn: bool = is_mobile and bool(settings.get_value("options", "rotate_button", true))
	_rotate_switch.button_pressed = rotbtn
	_rotate_switch.text = "An" if rotbtn else "Aus"

	var cheat := bool(settings.get_value("cheats", "enabled", false))
	_cheat_switch.button_pressed = cheat
	_cheat_switch.text = "An" if cheat else "Aus"

	_loading_settings = false


func _on_language_changed(index: int) -> void:
	if _loading_settings: return
	settings.set_value("options", "language", LANGUAGES[index][1])
	TranslationServer.set_locale(LANGUAGES[index][1])
	_settings_dirty = true


func _on_master_volume_changed(value: float) -> void:
	_lbl_master_val.text = "%d%%" % int(value)
	if _loading_settings: return
	settings.set_value("options", "master_volume", value)
	AudioServer.set_bus_volume_db(0, _vol_db(value))
	_settings_dirty = true


func _on_music_volume_changed(value: float) -> void:
	_lbl_music_val.text = "%d%%" % int(value)
	if _loading_settings: return
	settings.set_value("options", "music_volume", value)
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0: AudioServer.set_bus_volume_db(idx, _vol_db(value))
	_settings_dirty = true


func _on_sfx_volume_changed(value: float) -> void:
	_lbl_sfx_val.text = "%d%%" % int(value)
	if _loading_settings: return
	settings.set_value("options", "sfx_volume", value)
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0: AudioServer.set_bus_volume_db(idx, _vol_db(value))
	_settings_dirty = true


func _on_window_mode_changed(index: int) -> void:
	if _loading_settings: return
	settings.set_value("options", "window_mode", index)
	_apply_window_mode(index)
	_settings_dirty = true


# Altes placement_mode in eine Steuerungsart übersetzen (für Saves ohne control_mode).
func _infer_default_ctrl_mode() -> String:
	var pm := String(settings.get_value("options", "placement_mode", "slow"))
	return "click" if pm == "quick" else "drag"


func _on_rotate_btn_toggled(pressed: bool) -> void:
	_rotate_switch.text = "An" if pressed else "Aus"
	if _loading_settings: return
	settings.set_value("options", "rotate_button", pressed)
	# Live anwenden, falls gerade der 2D-Bauplan offen ist (sonst greift es beim nächsten Laden).
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("set_rotate_button_visible"):
		scene.set_rotate_button_visible(pressed)
	_settings_dirty = true


func _on_cheat_toggled(pressed: bool) -> void:
	_cheat_switch.text = "An" if pressed else "Aus"
	if _loading_settings: return
	settings.set_value("cheats", "enabled", pressed)
	# Live anwenden, damit die Cheat-Buttons (∞ / +1B ⭐) sofort ein-/ausblenden.
	Economy.apply_cheat_mode(pressed)
	_settings_dirty = true


func _on_settings_back() -> void:
	if _settings_dirty:
		_hide_all()
		_discard_modal.visible = true
	else:
		_exit_settings()


func _on_settings_save() -> void:
	# Vor dem Speichern nachfragen, ob die Änderungen übernommen werden sollen.
	_hide_all()
	_save_modal.visible = true


# Bestätigt: speichern, übernehmen und die Einstellungen schließen.
func _on_save_confirm() -> void:
	settings.save(Paths.SETTINGS_FILE)
	_settings_dirty = false
	_exit_settings()


func _on_discard_confirm() -> void:
	# Einstellungen aus Datei neu laden und anwenden
	settings.load(Paths.SETTINGS_FILE)
	AudioServer.set_bus_volume_db(0, _vol_db(settings.get_value("options", "master_volume", 100.0)))
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0: AudioServer.set_bus_volume_db(mi, _vol_db(settings.get_value("options", "music_volume", 80.0)))
	var si := AudioServer.get_bus_index("SFX")
	if si >= 0: AudioServer.set_bus_volume_db(si, _vol_db(settings.get_value("options", "sfx_volume", 100.0)))
	_apply_window_mode(settings.get_value("options", "window_mode", 0))
	_apply_ui_scale(float(settings.get_value("options", "ui_scale", 1.0)))
	TranslationServer.set_locale(settings.get_value("options", "language", "de"))
	Economy.apply_cheat_mode(bool(settings.get_value("cheats", "enabled", false)))
	_settings_dirty = false
	_exit_settings()


func _build_discard_modal() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_add_panel_title(vbox, "ÄNDERUNGEN VERWERFEN?")
	_add_hline(vbox)

	var text_lbl := Label.new()
	text_lbl.text = "Nicht gespeicherte Einstellungen\ngehen verloren."
	text_lbl.add_theme_color_override("font_color", C_TEXT)
	text_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(text_lbl)

	_add_spacer(vbox, 6)
	_add_btn(vbox, "→", "Verwerfen",  C_ACCENT_RD, _on_discard_confirm)
	_add_btn(vbox, "←", "Abbrechen", C_ACCENT_MU, func():
		_hide_all()
		_settings_panel.visible = true
	)

	return center


func _build_save_modal() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_add_panel_title(vbox, "ÜBERNEHMEN?")
	_add_hline(vbox)

	var text_lbl := Label.new()
	text_lbl.text = "Die Änderungen werden gespeichert\nund die Einstellungen geschlossen."
	text_lbl.add_theme_color_override("font_color", C_TEXT)
	text_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(text_lbl)

	_add_spacer(vbox, 10)
	vbox.add_child(_build_primary_btn("✓  ÜBERNEHMEN", _on_save_confirm))
	vbox.add_child(_build_ghost_btn("Abbrechen", func():
		_hide_all()
		_settings_panel.visible = true
	))

	return center


func _make_placement_switch() -> CheckButton:
	var sw := CheckButton.new()
	sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sw.focus_mode = Control.FOCUS_NONE
	sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sw.add_theme_color_override("font_color",         C_TEXT)
	sw.add_theme_color_override("font_hover_color",   C_TEXT)
	sw.add_theme_color_override("font_pressed_color", C_TEXT)
	sw.add_theme_font_size_override("font_size", 13)
	# Helle Schalter-Grafik, damit sie sich vom dunklen Panel abhebt (v. a. im "Schnell"/Aus-Zustand).
	sw.add_theme_color_override("icon_normal_color",  Color(0.78, 0.82, 0.92))
	sw.add_theme_color_override("icon_hover_color",   Color(0.95, 0.97, 1.00))
	sw.add_theme_color_override("icon_pressed_color", C_ACCENT)
	sw.add_theme_color_override("icon_focus_color",   Color(0.78, 0.82, 0.92))
	# Umrahmtes Feld: Füllung bleibt konstant (C_SURFACE), nur der Toggle wechselt die Farbe.
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = C_ACCENT_MU
	sb.content_margin_left   = 8
	sb.content_margin_right  = 8
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	sw.add_theme_stylebox_override("normal",  sb)
	sw.add_theme_stylebox_override("hover",   sb)
	sw.add_theme_stylebox_override("pressed", sb)
	sw.add_theme_stylebox_override("focus",   sb)
	return sw


func _apply_window_mode(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			_apply_ui_scale(float(settings.get_value("options", "ui_scale", 1.0)))
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			_apply_ui_scale(float(settings.get_value("options", "ui_scale", 1.0)))
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _vol_db(percent: float) -> float:
	if percent <= 0.0: return -80.0
	return linear_to_db(percent / 100.0)
