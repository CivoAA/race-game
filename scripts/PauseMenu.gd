extends CanvasLayer

const LANGUAGES     = [["Deutsch", "de"], ["English", "en"]]
const WINDOW_MODES  = ["Fenster", "Rahmenlos", "Vollbild"]

const C_SURFACE   := Color(0.10, 0.115, 0.165)
const C_SURFACE2  := Color(0.085, 0.095, 0.140)
const C_ACCENT    := Color(1.00, 0.45, 0.08)
const C_ACCENT_MU := Color(0.22, 0.27, 0.40)
const C_ACCENT_RD := Color(0.65, 0.16, 0.10)
const C_TEXT      := Color(0.82, 0.85, 0.90)
const C_TEXT_DIM  := Color(0.36, 0.40, 0.50)
const C_LINE      := Color(0.14, 0.16, 0.23)

var settings := ConfigFile.new()

var _pause_panel:        Control
var _settings_panel:     Control
var _achievements_panel: Control
var _quit_modal:         Control

var _save_status_lbl: Label

var _lang_option:    OptionButton
var _master_slider:  HSlider
var _music_slider:   HSlider
var _sfx_slider:     HSlider
var _window_option:    OptionButton
var _placement_switch: CheckButton
var _lbl_master_val: Label
var _lbl_music_val:  Label
var _lbl_sfx_val:    Label

var _loading_settings := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	visible = false

	settings.load(Paths.SETTINGS_FILE)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.78)
	add_child(bg)

	_pause_panel        = _build_pause_panel()
	_settings_panel     = _build_settings_panel()
	_achievements_panel = _build_achievements_panel()
	_quit_modal         = _build_quit_modal()

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


func _resume() -> void:
	get_tree().paused = false
	visible = false


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
	_add_btn(vbox, "02", "Einstellungen",    C_ACCENT_MU, _show_settings)
	_add_btn(vbox, "03", "Errungenschaften", C_ACCENT_MU, _show_achievements)
	_add_spacer(vbox, 10)
	_add_btn(vbox, "04", "Speichern",        Color(0.15, 0.60, 0.35), _on_save_pressed)

	_save_status_lbl = Label.new()
	_save_status_lbl.text = "✓ Gespeichert!"
	_save_status_lbl.visible = false
	_save_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_status_lbl.add_theme_font_size_override("font_size", 12)
	_save_status_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
	vbox.add_child(_save_status_lbl)

	_add_btn(vbox, "05", "Spiel beenden",    C_ACCENT_RD, _on_quit_pressed)

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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 520)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(outer_vbox)

	_add_panel_title(outer_vbox, "EINSTELLUNGEN")
	_add_hline(outer_vbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	_add_section_label(vbox, "SPRACHE")
	var lang_row := _make_hrow(vbox)
	_make_row_label(lang_row, "Sprache:")
	_lang_option = OptionButton.new()
	_lang_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_btn(_lang_option)
	for lang in LANGUAGES:
		_lang_option.add_item(lang[0])
	_lang_option.item_selected.connect(_on_language_changed)
	lang_row.add_child(_lang_option)

	_add_hline(vbox)
	_add_section_label(vbox, "LAUTSTÄRKE")

	var r: Array
	r = _add_slider_row(vbox, "Master:")
	_master_slider = r[0]; _lbl_master_val = r[1]
	_master_slider.value_changed.connect(_on_master_volume_changed)

	r = _add_slider_row(vbox, "Musik:")
	_music_slider = r[0]; _lbl_music_val = r[1]
	_music_slider.value_changed.connect(_on_music_volume_changed)

	r = _add_slider_row(vbox, "Effekte:")
	_sfx_slider = r[0]; _lbl_sfx_val = r[1]
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	_add_hline(vbox)
	_add_section_label(vbox, "ANZEIGEMODUS")
	var win_row := _make_hrow(vbox)
	_make_row_label(win_row, "Modus:")
	_window_option = OptionButton.new()
	_window_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_btn(_window_option)
	for mode in WINDOW_MODES:
		_window_option.add_item(mode)
	_window_option.item_selected.connect(_on_window_mode_changed)
	win_row.add_child(_window_option)

	_add_hline(vbox)
	_add_section_label(vbox, "STEUERUNG")
	var place_row := _make_hrow(vbox)
	_make_row_label(place_row, "Platzierung:")
	_placement_switch = _make_placement_switch()
	_placement_switch.toggled.connect(_on_placement_toggled)
	place_row.add_child(_placement_switch)

	_add_spacer(outer_vbox, 8)
	_add_back_button(outer_vbox, _show_pause)

	return center


# ── Errungenschaften-Panel ────────────────────────────────────────────────────

func _build_achievements_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 460)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_add_panel_title(vbox, "ERRUNGENSCHAFTEN")
	_add_hline(vbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)

	var achievements := [
		["Erster Start",       "Starte dein erstes Rennen",            false],
		["Schnellster Fahrer", "Beende ein Rennen unter 60 Sekunden",  false],
		["Streckenbauer",      "Erstelle 10 verschiedene Strecken",    false],
		["Unaufhaltsam",       "Gewinne 5 Rennen in Folge",            false],
		["Vollgas",            "Erreiche die maximale Geschwindigkeit", false],
	]

	for i in achievements.size():
		var ach = achievements[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.custom_minimum_size = Vector2(0, 54)
		list.add_child(row)

		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(3, 0)
		bar.color = C_ACCENT if ach[2] else C_ACCENT_MU
		bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(bar)

		var pad := Control.new()
		pad.custom_minimum_size = Vector2(10, 0)
		row.add_child(pad)

		var star := Label.new()
		star.text = "★" if ach[2] else "☆"
		star.custom_minimum_size = Vector2(24, 0)
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		star.add_theme_font_size_override("font_size", 22)
		star.add_theme_color_override("font_color", C_ACCENT if ach[2] else C_TEXT_DIM)
		row.add_child(star)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)

		var name_lbl := Label.new()
		name_lbl.text = ach[0].to_upper()
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", C_TEXT if ach[2] else C_TEXT.darkened(0.15))
		info.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = ach[1]
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		info.add_child(desc_lbl)

		if i < achievements.size() - 1:
			var sep := ColorRect.new()
			sep.custom_minimum_size = Vector2(0, 1)
			sep.color = C_LINE
			list.add_child(sep)

	_add_spacer(vbox, 4)
	_add_back_button(vbox, _show_pause)

	return center


# ── Panel-Wechsel ─────────────────────────────────────────────────────────────

func _hide_all() -> void:
	_pause_panel.visible        = false
	_settings_panel.visible     = false
	_achievements_panel.visible = false
	_quit_modal.visible         = false


func _show_pause() -> void:
	_hide_all()
	_pause_panel.visible = true


func _show_settings() -> void:
	_hide_all()
	_settings_panel.visible = true
	_sync_settings_ui()


func _show_achievements() -> void:
	_hide_all()
	_achievements_panel.visible = true


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

	var slow := (settings.get_value("options", "placement_mode", "slow") as String) == "slow"
	_placement_switch.button_pressed = slow
	_update_placement_switch_text(slow)

	_loading_settings = false


func _on_language_changed(index: int) -> void:
	if _loading_settings: return
	settings.set_value("options", "language", LANGUAGES[index][1])
	settings.save(Paths.SETTINGS_FILE)
	TranslationServer.set_locale(LANGUAGES[index][1])


func _on_master_volume_changed(value: float) -> void:
	_lbl_master_val.text = "%d%%" % int(value)
	if _loading_settings: return
	settings.set_value("options", "master_volume", value)
	settings.save(Paths.SETTINGS_FILE)
	AudioServer.set_bus_volume_db(0, _vol_db(value))


func _on_music_volume_changed(value: float) -> void:
	_lbl_music_val.text = "%d%%" % int(value)
	if _loading_settings: return
	settings.set_value("options", "music_volume", value)
	settings.save(Paths.SETTINGS_FILE)
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0: AudioServer.set_bus_volume_db(idx, _vol_db(value))


func _on_sfx_volume_changed(value: float) -> void:
	_lbl_sfx_val.text = "%d%%" % int(value)
	if _loading_settings: return
	settings.set_value("options", "sfx_volume", value)
	settings.save(Paths.SETTINGS_FILE)
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0: AudioServer.set_bus_volume_db(idx, _vol_db(value))


func _on_window_mode_changed(index: int) -> void:
	if _loading_settings: return
	settings.set_value("options", "window_mode", index)
	settings.save(Paths.SETTINGS_FILE)
	_apply_window_mode(index)


func _on_placement_toggled(pressed: bool) -> void:
	_update_placement_switch_text(pressed)
	if _loading_settings: return
	var mode := "slow" if pressed else "quick"
	settings.set_value("options", "placement_mode", mode)
	settings.save(Paths.SETTINGS_FILE)
	# Laufende Bauplan-Szene live umschalten (falls geöffnet).
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("set_placement_mode"):
		scene.set_placement_mode(mode)


# Schalter-Beschriftung zeigt den aktiven Modus an (an = Langsam/Ziehen, aus = Schnell/Klick).
func _update_placement_switch_text(slow: bool) -> void:
	_placement_switch.text = "Langsam" if slow else "Schnell"


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
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE
	sb.set_corner_radius_all(4)
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
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _vol_db(percent: float) -> float:
	if percent <= 0.0: return -80.0
	return linear_to_db(percent / 100.0)
