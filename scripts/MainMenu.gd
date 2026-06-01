extends Control

const LANGUAGES     = [["Deutsch", "de"], ["English", "en"]]
const WINDOW_MODES  = ["Fenster", "Rahmenlos", "Vollbild"]

const C_BG        := Color(0.07, 0.08, 0.12)
const C_SURFACE   := Color(0.10, 0.115, 0.165)
const C_SURFACE2  := Color(0.085, 0.095, 0.140)
const C_ACCENT    := Color(1.00, 0.45, 0.08)
const C_ACCENT_MU := Color(0.22, 0.27, 0.40)
const C_ACCENT_RD := Color(0.65, 0.16, 0.10)
const C_TEXT      := Color(0.82, 0.85, 0.90)
const C_TEXT_DIM  := Color(0.36, 0.40, 0.50)
const C_LINE      := Color(0.14, 0.16, 0.23)

var settings := ConfigFile.new()

var _main_panel:         Control
var _options_panel:      Control
var _achievements_panel: Control
var _slot_panel:         Control
var _confirm_modal:      Control

var _slot_is_load     := false
var _slot_title_lbl:  Label
var _slot_btns:       Array[Button] = []
var _slot_info_labels: Array[Label] = []
var _confirm_slot:    int = 0

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
	settings.load(Paths.SETTINGS_FILE)
	_build_background()
	_main_panel         = _build_main_panel()
	_options_panel      = _build_options_panel()
	_achievements_panel = _build_achievements_panel()
	_slot_panel         = _build_slot_panel()
	_confirm_modal      = _build_confirm_modal()
	_show_main()
	_apply_settings()


# ── Hintergrund ───────────────────────────────────────────────────────────────

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)


# ── Hauptmenü ─────────────────────────────────────────────────────────────────

func _build_main_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(440, 0)
	vbox.add_theme_constant_override("separation", 5)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "RACE ROGUE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", C_ACCENT)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "ROGUELIKE RENNSPIEL"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", C_TEXT_DIM)
	vbox.add_child(subtitle)

	_add_spacer(vbox, 20)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(440, 1)
	divider.color = C_ACCENT
	vbox.add_child(divider)

	_add_spacer(vbox, 14)

	_add_menu_button(vbox, "01", "Neues Spiel",      C_ACCENT,    func(): _show_slot_panel(false))
	_add_menu_button(vbox, "02", "Spiel laden",      C_ACCENT_MU, func(): _show_slot_panel(true))
	_add_menu_button(vbox, "03", "Optionen",         C_ACCENT_MU, _show_options)
	_add_menu_button(vbox, "04", "Errungenschaften", C_ACCENT_MU, _show_achievements)
	_add_spacer(vbox, 10)
	_add_menu_button(vbox, "05", "Beenden",          C_ACCENT_RD, _on_quit)

	return center


func _add_menu_button(parent: VBoxContainer, num: String, label: String,
		accent: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(440, 58)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	btn.add_theme_stylebox_override("normal",   _btn_style(C_SURFACE,                 accent.darkened(0.4)))
	btn.add_theme_stylebox_override("hover",    _btn_style(C_SURFACE.lightened(0.05), accent))
	btn.add_theme_stylebox_override("pressed",  _btn_style(C_SURFACE2,                accent))
	btn.add_theme_stylebox_override("focus",    _btn_style(C_SURFACE,                 accent.darkened(0.4)))
	btn.add_theme_stylebox_override("disabled", _btn_style(C_SURFACE2,                accent.darkened(0.6)))

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


# ── Slot-Panel ────────────────────────────────────────────────────────────────

func _build_slot_panel() -> Control:
	var overlay := _make_overlay()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_slot_title_lbl = Label.new()
	_slot_title_lbl.text = "NEUES SPIEL"
	_slot_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_slot_title_lbl.add_theme_font_size_override("font_size", 28)
	_slot_title_lbl.add_theme_color_override("font_color", C_ACCENT)
	vbox.add_child(_slot_title_lbl)

	_add_hline(vbox)
	_add_spacer(vbox, 4)

	_slot_btns.clear()
	_slot_info_labels.clear()
	for i in 3:
		var btn := _build_slot_button(i)
		vbox.add_child(btn)
		_slot_btns.append(btn)

	_add_spacer(vbox, 8)
	_add_back_button(vbox, _show_main)

	return overlay


func _build_slot_button(slot: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(424, 62)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	btn.add_theme_stylebox_override("normal",   _btn_style(C_SURFACE,                 C_ACCENT_MU))
	btn.add_theme_stylebox_override("hover",    _btn_style(C_SURFACE.lightened(0.05), C_ACCENT))
	btn.add_theme_stylebox_override("pressed",  _btn_style(C_SURFACE2,                C_ACCENT))
	btn.add_theme_stylebox_override("focus",    _btn_style(C_SURFACE,                 C_ACCENT_MU))
	btn.add_theme_stylebox_override("disabled", _btn_style(C_SURFACE2,                C_ACCENT_MU.darkened(0.5)))

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
	num_lbl.text = "0%d" % (slot + 1)
	num_lbl.custom_minimum_size = Vector2(32, 0)
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num_lbl.add_theme_font_size_override("font_size", 11)
	num_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(num_lbl)

	var name_lbl := Label.new()
	name_lbl.text = "SLOT %d" % (slot + 1)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)

	var info_lbl := Label.new()
	info_lbl.text = "LEER"
	info_lbl.name = "InfoLabel"
	info_lbl.custom_minimum_size = Vector2(130, 0)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 12)
	info_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info_lbl)
	_slot_info_labels.append(info_lbl)

	var arrow := Label.new()
	arrow.text = "▶"
	arrow.custom_minimum_size = Vector2(48, 0)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 11)
	arrow.add_theme_color_override("font_color", C_ACCENT_MU)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(arrow)

	btn.pressed.connect(func(): _on_slot_selected(slot))
	return btn


func _show_slot_panel(is_load: bool) -> void:
	_slot_is_load = is_load
	_hide_all()
	_slot_panel.visible = true

	if is_load:
		_slot_title_lbl.text = "SPIEL LADEN"
	else:
		_slot_title_lbl.text = "NEUES SPIEL"

	for i in 3:
		var info = Economy.get_slot_info(i)
		if info.is_empty():
			_slot_info_labels[i].text = "LEER"
			_slot_info_labels[i].add_theme_color_override("font_color", C_TEXT_DIM)
			_slot_btns[i].disabled = is_load
		else:
			var ts   = String(info.get("timestamp", ""))
			var date = ts.substr(0, 10) if ts.length() >= 10 else ts
			var time = ts.substr(11, 5) if ts.length() >= 16 else ""
			var disp = "%s %s" % [date, time] if time != "" else date
			_slot_info_labels[i].text = "%d G  %s" % [int(info.get("currency", 0)), disp]
			_slot_info_labels[i].add_theme_color_override("font_color", C_ACCENT.darkened(0.1))
			_slot_btns[i].disabled = false


func _on_slot_selected(slot: int) -> void:
	if _slot_is_load:
		Economy.load_game_from_slot(slot)
		get_tree().change_scene_to_file(Paths.SCENE_BUILDER)
	else:
		if Economy.slot_exists(slot):
			_show_confirm_modal(slot)
		else:
			Economy.reset_slot(slot)
			get_tree().change_scene_to_file(Paths.SCENE_BUILDER)


# ── Bestätigungs-Modal (Spielstand überschreiben) ─────────────────────────────

func _build_confirm_modal() -> Control:
	var overlay := _make_overlay()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_add_panel_title(vbox, "ÜBERSCHREIBEN?")
	_add_hline(vbox)

	var text_lbl := Label.new()
	text_lbl.text = "Dieser Spielstand wird\nunwiderruflich überschrieben."
	text_lbl.add_theme_color_override("font_color", C_TEXT)
	text_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(text_lbl)

	_add_spacer(vbox, 6)

	_add_menu_button(vbox, "→", "Neu starten", C_ACCENT_RD, func():
		Economy.reset_slot(_confirm_slot)
		get_tree().change_scene_to_file(Paths.SCENE_BUILDER)
	)
	_add_menu_button(vbox, "←", "Abbrechen", C_ACCENT_MU, func():
		_hide_all()
		_slot_panel.visible = true
	)

	return overlay


func _show_confirm_modal(slot: int) -> void:
	_confirm_slot = slot
	_hide_all()
	_confirm_modal.visible = true


# ── Optionen-Panel ────────────────────────────────────────────────────────────

func _build_options_panel() -> Control:
	var overlay := _make_overlay()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_add_panel_title(vbox, "OPTIONEN")
	_add_hline(vbox)

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

	_add_spacer(vbox, 8)
	_add_back_button(vbox, _show_main)

	return overlay


# ── Errungenschaften-Panel ────────────────────────────────────────────────────

func _build_achievements_panel() -> Control:
	var overlay := _make_overlay()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 480)
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
	_add_back_button(vbox, _show_main)

	return overlay


# ── UI-Hilfsfunktionen ────────────────────────────────────────────────────────

func _make_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.78)
	add_child(overlay)
	return overlay


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


# ── Panel-Wechsel ─────────────────────────────────────────────────────────────

func _hide_all() -> void:
	_main_panel.visible         = false
	_options_panel.visible      = false
	_achievements_panel.visible = false
	_slot_panel.visible         = false
	_confirm_modal.visible      = false


func _show_main() -> void:
	_hide_all()
	_main_panel.visible = true


func _show_options() -> void:
	_hide_all()
	_options_panel.visible = true
	_sync_options_ui()


func _show_achievements() -> void:
	_hide_all()
	_achievements_panel.visible = true


# ── Callbacks ─────────────────────────────────────────────────────────────────

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

	_master_slider.value    = settings.get_value("options", "master_volume", 100.0)
	_music_slider.value     = settings.get_value("options", "music_volume",  80.0)
	_sfx_slider.value       = settings.get_value("options", "sfx_volume",    100.0)
	_window_option.selected = settings.get_value("options", "window_mode",   0)

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
