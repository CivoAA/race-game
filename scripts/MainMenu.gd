extends Control

const SETTINGS_FILE = "user://settings.cfg"
const LANGUAGES     = [["Deutsch", "de"], ["English", "en"], ["Français", "fr"]]
const WINDOW_MODES  = ["Fenster", "Rahmenlos", "Vollbild"]

var settings := ConfigFile.new()

var _main_panel:         Control
var _options_panel:      Control
var _achievements_panel: Control

var _lang_option:    OptionButton
var _master_slider:  HSlider
var _music_slider:   HSlider
var _sfx_slider:     HSlider
var _window_option:  OptionButton
var _lbl_master_val: Label
var _lbl_music_val:  Label
var _lbl_sfx_val:    Label

var _loading_settings := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	settings.load(SETTINGS_FILE)
	_build_background()
	_main_panel         = _build_main_panel()
	_options_panel      = _build_options_panel()
	_achievements_panel = _build_achievements_panel()
	_show_main()
	_apply_settings()


# ── Hintergrund ───────────────────────────────────────────────────────────────

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.08, 0.14)
	add_child(bg)


# ── Hauptmenü ─────────────────────────────────────────────────────────────────

func _build_main_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(340, 0)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := Label.new()
	title.text                 = "RACE ROGUE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.1))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text                 = "Roguelike Rennspiel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75))
	vbox.add_child(subtitle)

	_add_spacer(vbox, 32)

	_add_menu_button(vbox, "Neues Spiel",      _on_new_game)
	_add_menu_button(vbox, "Spiel laden",      _on_load_game)
	_add_menu_button(vbox, "Optionen",         _show_options)
	_add_menu_button(vbox, "Errungenschaften", _show_achievements)
	_add_spacer(vbox, 8)
	_add_menu_button(vbox, "Beenden",          _on_quit)

	return center


func _add_menu_button(parent: VBoxContainer, text: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text                  = text
	btn.custom_minimum_size   = Vector2(340, 52)
	btn.pressed.connect(cb)
	parent.add_child(btn)


# ── Optionen-Panel ────────────────────────────────────────────────────────────

func _build_options_panel() -> Control:
	var overlay := _make_overlay()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	_add_panel_title(vbox, "OPTIONEN")
	_add_hsep(vbox)

	# — Sprache ——————————————————————
	_add_section_label(vbox, "SPRACHE")
	var lang_row := _make_hrow(vbox)
	_make_row_label(lang_row, "Sprache:")
	_lang_option = OptionButton.new()
	_lang_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for lang in LANGUAGES:
		_lang_option.add_item(lang[0])
	_lang_option.item_selected.connect(_on_language_changed)
	lang_row.add_child(_lang_option)

	_add_hsep(vbox)

	# — Lautstärke ———————————————————
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

	_add_hsep(vbox)

	# — Anzeigemodus —————————————————
	_add_section_label(vbox, "ANZEIGEMODUS")
	var win_row := _make_hrow(vbox)
	_make_row_label(win_row, "Modus:")
	_window_option = OptionButton.new()
	_window_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for mode in WINDOW_MODES:
		_window_option.add_item(mode)
	_window_option.item_selected.connect(_on_window_mode_changed)
	win_row.add_child(_window_option)

	_add_spacer(vbox, 8)

	var back := Button.new()
	back.text               = "Zurück"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_show_main)
	vbox.add_child(back)

	return overlay


# ── Errungenschaften-Panel ────────────────────────────────────────────────────

func _build_achievements_panel() -> Control:
	var overlay := _make_overlay()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 480)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_add_panel_title(vbox, "ERRUNGENSCHAFTEN")
	_add_hsep(vbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	# Platzhalter-Errungenschaften — später durch echte Spieldaten ersetzen
	var achievements := [
		["Erster Start",       "Starte dein erstes Rennen",            false],
		["Schnellster Fahrer", "Beende ein Rennen unter 60 Sekunden",  false],
		["Streckenbauer",      "Erstelle 10 verschiedene Strecken",     false],
		["Unaufhaltsam",       "Gewinne 5 Rennen in Folge",            false],
		["Vollgas",            "Erreiche die maximale Geschwindigkeit", false],
	]

	for ach in achievements:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		list.add_child(row)

		var star := Label.new()
		star.text                = "★" if ach[2] else "☆"
		star.custom_minimum_size = Vector2(28, 0)
		star.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
		star.add_theme_font_size_override("font_size", 26)
		star.add_theme_color_override("font_color",
				Color(1.0, 0.75, 0.1) if ach[2] else Color(0.4, 0.4, 0.5))
		row.add_child(star)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var name_lbl := Label.new()
		name_lbl.text = ach[0]
		name_lbl.add_theme_color_override("font_color",
				Color(1, 1, 1) if ach[2] else Color(0.75, 0.75, 0.85))
		info.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = ach[1]
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
		info.add_child(desc_lbl)

		_add_hsep(list)

	var back := Button.new()
	back.text               = "Zurück"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_show_main)
	vbox.add_child(back)

	return overlay


# ── UI-Hilfsfunktionen ────────────────────────────────────────────────────────

func _make_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	add_child(overlay)
	return overlay


func _make_hrow(parent: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	return row


func _make_row_label(row: HBoxContainer, text: String) -> Label:
	var lbl := Label.new()
	lbl.text               = text
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	return lbl


func _add_slider_row(parent: VBoxContainer, label_text: String) -> Array:
	var row := _make_hrow(parent)
	_make_row_label(row, label_text)

	var slider := HSlider.new()
	slider.min_value             = 0.0
	slider.max_value             = 100.0
	slider.step                  = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text               = "100%"
	val_lbl.custom_minimum_size = Vector2(48, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val_lbl)

	return [slider, val_lbl]


func _add_panel_title(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text               = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.1))
	parent.add_child(lbl)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
	parent.add_child(lbl)


func _add_hsep(parent: Node) -> void:
	parent.add_child(HSeparator.new())


func _add_spacer(parent: VBoxContainer, height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)


# ── Panel-Wechsel ─────────────────────────────────────────────────────────────

func _show_main() -> void:
	_main_panel.visible         = true
	_options_panel.visible      = false
	_achievements_panel.visible = false


func _show_options() -> void:
	_main_panel.visible    = false
	_options_panel.visible = true
	_sync_options_ui()


func _show_achievements() -> void:
	_main_panel.visible         = false
	_achievements_panel.visible = true


# ── Hauptmenü-Callbacks ───────────────────────────────────────────────────────

func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://main.tscn")


func _on_load_game() -> void:
	pass  # TODO: Speichersystem implementieren


func _on_quit() -> void:
	get_tree().quit()


# ── Optionen: UI-Sync ─────────────────────────────────────────────────────────

func _sync_options_ui() -> void:
	_loading_settings = true

	var lang := settings.get_value("options", "language", "de") as String
	for i in LANGUAGES.size():
		if LANGUAGES[i][1] == lang:
			_lang_option.selected = i
			break

	# value = x löst value_changed aus → Label-Update findet statt,
	# Speichern wird durch _loading_settings unterdrückt.
	_master_slider.value    = settings.get_value("options", "master_volume", 100.0)
	_music_slider.value     = settings.get_value("options", "music_volume",  80.0)
	_sfx_slider.value       = settings.get_value("options", "sfx_volume",    100.0)
	_window_option.selected = settings.get_value("options", "window_mode",   0)

	_loading_settings = false


# ── Optionen-Callbacks ────────────────────────────────────────────────────────

func _on_language_changed(index: int) -> void:
	if _loading_settings:
		return
	settings.set_value("options", "language", LANGUAGES[index][1])
	settings.save(SETTINGS_FILE)
	TranslationServer.set_locale(LANGUAGES[index][1])


func _on_master_volume_changed(value: float) -> void:
	_lbl_master_val.text = "%d%%" % int(value)
	if _loading_settings:
		return
	settings.set_value("options", "master_volume", value)
	settings.save(SETTINGS_FILE)
	AudioServer.set_bus_volume_db(0, _vol_db(value))


func _on_music_volume_changed(value: float) -> void:
	_lbl_music_val.text = "%d%%" % int(value)
	if _loading_settings:
		return
	settings.set_value("options", "music_volume", value)
	settings.save(SETTINGS_FILE)
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _vol_db(value))


func _on_sfx_volume_changed(value: float) -> void:
	_lbl_sfx_val.text = "%d%%" % int(value)
	if _loading_settings:
		return
	settings.set_value("options", "sfx_volume", value)
	settings.save(SETTINGS_FILE)
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _vol_db(value))


func _on_window_mode_changed(index: int) -> void:
	if _loading_settings:
		return
	settings.set_value("options", "window_mode", index)
	settings.save(SETTINGS_FILE)
	_apply_window_mode(index)


# ── Einstellungen anwenden ────────────────────────────────────────────────────

func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0,
			_vol_db(settings.get_value("options", "master_volume", 100.0)))
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi,
				_vol_db(settings.get_value("options", "music_volume", 80.0)))
	var si := AudioServer.get_bus_index("SFX")
	if si >= 0:
		AudioServer.set_bus_volume_db(si,
				_vol_db(settings.get_value("options", "sfx_volume", 100.0)))
	_apply_window_mode(settings.get_value("options", "window_mode", 0))
	TranslationServer.set_locale(settings.get_value("options", "language", "de"))


func _apply_window_mode(index: int) -> void:
	match index:
		0:  # Fenster
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1:  # Rahmenlos
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:  # Vollbild
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _vol_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)
