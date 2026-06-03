extends Control

const LANGUAGES    = [["Deutsch", "de"], ["English", "en"]]
const WINDOW_MODES = ["Fenster", "Rahmenlos", "Vollbild"]

const C_BG        := Color(0.13, 0.14, 0.20)
const C_SURFACE   := Color(0.19, 0.21, 0.29)
const C_SURFACE2  := Color(0.24, 0.26, 0.36)
const C_ACCENT    := Color(1.00, 0.52, 0.05)
const C_ACCENT_MU := Color(0.22, 0.30, 0.50)
const C_ACCENT_RD := Color(0.80, 0.18, 0.12)
const C_TEXT      := Color(0.93, 0.95, 1.00)
const C_TEXT_DIM  := Color(0.50, 0.56, 0.70)
const C_LINE      := Color(0.21, 0.24, 0.34)

var settings := ConfigFile.new()

var _main_panel:         Control
var _options_panel:      Control
var _achievements_panel: Control
var _slot_panel:         Control
var _confirm_modal:      Control
var _rename_modal:       Control
var _delete_modal:       Control
var _discard_modal:      Control

var _options_dirty: bool = false

var _slot_is_load      := false
var _slot_title_lbl:   Label
var _slot_btns:        Array[Button] = []
var _slot_info_labels: Array[Label]  = []
var _slot_name_labels: Array[Label]  = []
var _slot_rename_btns: Array[Button] = []
var _slot_delete_btns: Array[Button] = []
var _confirm_slot:     int = 0
var _action_slot:      int = 0
var _rename_line_edit: LineEdit

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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	settings.load(Paths.SETTINGS_FILE)
	_build_background()
	_main_panel         = _build_main_panel()
	_options_panel      = _build_options_panel()
	_achievements_panel = _build_achievements_panel()
	_slot_panel         = _build_slot_panel()
	_confirm_modal      = _build_confirm_modal()
	_rename_modal       = _build_rename_modal()
	_delete_modal       = _build_delete_modal()
	_discard_modal      = _build_options_discard_modal()
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

	var _any_save = Economy.slot_exists(0) or Economy.slot_exists(1) or Economy.slot_exists(2)
	if _any_save:
		_add_menu_button(vbox, "01", "Spiel laden",  C_ACCENT,    func(): _show_slot_panel(true))
		_add_menu_button(vbox, "02", "Neues Spiel",  C_ACCENT_MU, func(): _show_slot_panel(false))
	else:
		_add_menu_button(vbox, "01", "Neues Spiel",  C_ACCENT,    func(): _show_slot_panel(false))
		_add_menu_button(vbox, "02", "Spiel laden",  C_ACCENT_MU, func(): _show_slot_panel(true))

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
	panel.custom_minimum_size = Vector2(560, 0)
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
	_slot_name_labels.clear()
	_slot_rename_btns.clear()
	_slot_delete_btns.clear()

	for i in 3:
		vbox.add_child(_build_slot_row(i))

	_add_spacer(vbox, 8)
	_add_back_button(vbox, _show_main)

	return overlay


func _build_slot_row(slot: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# ── Haupt-Button ──
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 62)
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
	_slot_name_labels.append(name_lbl)

	var info_lbl := Label.new()
	info_lbl.text = "LEER"
	info_lbl.custom_minimum_size = Vector2(120, 0)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 12)
	info_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info_lbl)
	_slot_info_labels.append(info_lbl)

	var arrow := Label.new()
	arrow.text = "▶"
	arrow.custom_minimum_size = Vector2(40, 0)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 11)
	arrow.add_theme_color_override("font_color", C_ACCENT_MU)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(arrow)

	btn.pressed.connect(func(): _on_slot_selected(slot))
	row.add_child(btn)
	_slot_btns.append(btn)

	# ── Umbenennen-Button ──
	var ren_btn := _build_action_btn("✎", C_ACCENT_MU)
	ren_btn.pressed.connect(func(): _show_rename_modal(slot))
	row.add_child(ren_btn)
	_slot_rename_btns.append(ren_btn)

	# ── Löschen-Button ──
	var del_btn := _build_action_btn("✕", C_ACCENT_RD)
	del_btn.pressed.connect(func(): _show_delete_modal(slot))
	row.add_child(del_btn)
	_slot_delete_btns.append(del_btn)

	return row


func _build_action_btn(icon: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = icon
	btn.custom_minimum_size = Vector2(54, 62)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",  _btn_style(C_SURFACE,                 accent.darkened(0.4)))
	btn.add_theme_stylebox_override("hover",   _btn_style(C_SURFACE.lightened(0.05), accent))
	btn.add_theme_stylebox_override("pressed", _btn_style(C_SURFACE2,                accent))
	btn.add_theme_stylebox_override("focus",   _btn_style(C_SURFACE,                 accent.darkened(0.4)))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 18)
	return btn


func _show_slot_panel(is_load: bool) -> void:
	_slot_is_load = is_load
	_hide_all()
	_slot_panel.visible = true
	_slot_title_lbl.text = "SPIEL LADEN" if is_load else "NEUES SPIEL"
	_refresh_slot_rows()


func _refresh_slot_rows() -> void:
	for i in 3:
		var info = Economy.get_slot_info(i)
		var has_data = not info.is_empty()

		if has_data:
			var custom_name = String(info.get("name", ""))
			_slot_name_labels[i].text = custom_name.to_upper() if custom_name != "" else "SLOT %d" % (i + 1)

			var ts   = String(info.get("timestamp", ""))
			var date = ts.substr(0, 10) if ts.length() >= 10 else ts
			var time = ts.substr(11, 5) if ts.length() >= 16 else ""
			var disp = "%s %s" % [date, time] if time != "" else date
			_slot_info_labels[i].text = "%d G  %s" % [int(info.get("currency", 0)), disp]
			_slot_info_labels[i].add_theme_color_override("font_color", C_ACCENT.darkened(0.1))
		else:
			_slot_name_labels[i].text = "SLOT %d" % (i + 1)
			_slot_info_labels[i].text = "LEER"
			_slot_info_labels[i].add_theme_color_override("font_color", C_TEXT_DIM)

		_slot_btns[i].disabled = _slot_is_load and not has_data
		_slot_rename_btns[i].visible = has_data
		_slot_delete_btns[i].visible = has_data


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


# ── Umbenennen-Modal ──────────────────────────────────────────────────────────

func _build_rename_modal() -> Control:
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

	_add_panel_title(vbox, "UMBENENNEN")
	_add_hline(vbox)
	_add_spacer(vbox, 2)

	_rename_line_edit = LineEdit.new()
	_rename_line_edit.placeholder_text = "Name eingeben..."
	_rename_line_edit.custom_minimum_size = Vector2(0, 48)
	_rename_line_edit.add_theme_color_override("font_color", C_TEXT)
	_rename_line_edit.add_theme_color_override("font_placeholder_color", C_TEXT_DIM)
	_rename_line_edit.add_theme_font_size_override("font_size", 15)

	var le_style := StyleBoxFlat.new()
	le_style.bg_color = C_SURFACE
	le_style.border_width_left = 2
	le_style.border_color = C_ACCENT_MU
	le_style.content_margin_left   = 10
	le_style.content_margin_right  = 10
	le_style.content_margin_top    = 4
	le_style.content_margin_bottom = 4
	var le_focus := le_style.duplicate() as StyleBoxFlat
	le_focus.border_color = C_ACCENT
	_rename_line_edit.add_theme_stylebox_override("normal", le_style)
	_rename_line_edit.add_theme_stylebox_override("focus",  le_focus)
	_rename_line_edit.text_submitted.connect(func(_t): _confirm_rename())
	vbox.add_child(_rename_line_edit)

	_add_spacer(vbox, 4)
	_add_menu_button(vbox, "→", "Speichern",  C_ACCENT,    _confirm_rename)
	_add_menu_button(vbox, "←", "Abbrechen",  C_ACCENT_MU, func():
		_hide_all()
		_slot_panel.visible = true
	)

	return overlay


func _show_rename_modal(slot: int) -> void:
	_action_slot = slot
	var info = Economy.get_slot_info(slot)
	_rename_line_edit.text = String(info.get("name", ""))
	_rename_line_edit.grab_focus()
	_hide_all()
	_rename_modal.visible = true


func _confirm_rename() -> void:
	var new_name = _rename_line_edit.text.strip_edges()
	Economy.rename_slot(_action_slot, new_name)
	_hide_all()
	_slot_panel.visible = true
	_refresh_slot_rows()


# ── Löschen-Modal ─────────────────────────────────────────────────────────────

func _build_delete_modal() -> Control:
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

	_add_panel_title(vbox, "LÖSCHEN?")
	_add_hline(vbox)

	var text_lbl := Label.new()
	text_lbl.text = "Dieser Spielstand wird\nunwiderruflich gelöscht."
	text_lbl.add_theme_color_override("font_color", C_TEXT)
	text_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(text_lbl)

	_add_spacer(vbox, 4)
	_add_menu_button(vbox, "→", "Löschen",   C_ACCENT_RD, _confirm_delete)
	_add_menu_button(vbox, "←", "Abbrechen", C_ACCENT_MU, func():
		_hide_all()
		_slot_panel.visible = true
	)

	return overlay


func _show_delete_modal(slot: int) -> void:
	_action_slot = slot
	_hide_all()
	_delete_modal.visible = true


func _confirm_delete() -> void:
	Economy.delete_slot(_action_slot)
	_hide_all()
	_slot_panel.visible = true
	_refresh_slot_rows()


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
	# Fullscreen-Modal (kein overlay – liegt über dem Hauptmenü-Hintergrund)
	var overlay := _make_overlay()

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.11, 0.12, 0.17)
	ps.set_border_width_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_vbox.add_theme_constant_override("separation", 0)
	panel.add_child(outer_vbox)

	# Header
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 52)
	header.add_theme_constant_override("separation", 0)
	outer_vbox.add_child(header)

	var lpad := Control.new(); lpad.custom_minimum_size = Vector2(24, 0)
	header.add_child(lpad)
	var title_lbl := Label.new()
	title_lbl.text = "OPTIONEN"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", C_ACCENT)
	header.add_child(title_lbl)
	_add_hline(outer_vbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	var vpad := Control.new(); vpad.custom_minimum_size = Vector2(0, 8)
	scroll.add_child(vbox)
	vbox.add_child(vpad)

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

	var bot_line := ColorRect.new()
	bot_line.custom_minimum_size = Vector2(0, 1)
	bot_line.color = C_LINE
	outer_vbox.add_child(bot_line)

	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size = Vector2(0, 56)
	btn_row.add_theme_constant_override("separation", 0)
	outer_vbox.add_child(btn_row)

	var bpad := Control.new(); bpad.custom_minimum_size = Vector2(20, 0)
	btn_row.add_child(bpad)

	var back_btn := Button.new()
	back_btn.text = "← Zurück"
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.custom_minimum_size = Vector2(0, 44)
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_btn.add_theme_stylebox_override("normal",  _btn_style(C_SURFACE,    C_ACCENT_MU))
	back_btn.add_theme_stylebox_override("hover",   _btn_style(C_SURFACE.lightened(0.05), C_ACCENT))
	back_btn.add_theme_stylebox_override("pressed", _btn_style(C_SURFACE2,   C_ACCENT))
	back_btn.add_theme_stylebox_override("focus",   _btn_style(C_SURFACE,    C_ACCENT_MU))
	back_btn.add_theme_color_override("font_color", C_TEXT)
	back_btn.add_theme_font_size_override("font_size", 13)
	back_btn.pressed.connect(_on_options_back)
	btn_row.add_child(back_btn)

	var sep := Control.new(); sep.custom_minimum_size = Vector2(8, 0)
	btn_row.add_child(sep)

	var save_btn := Button.new()
	save_btn.text = "💾 Speichern"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.custom_minimum_size = Vector2(0, 44)
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	save_btn.add_theme_stylebox_override("normal",  _btn_style(Color(0.08, 0.26, 0.14), Color(0.25, 0.80, 0.42)))
	save_btn.add_theme_stylebox_override("hover",   _btn_style(Color(0.10, 0.34, 0.18), Color(0.35, 0.95, 0.52)))
	save_btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.08, 0.26, 0.14), Color(0.25, 0.80, 0.42)))
	save_btn.add_theme_stylebox_override("focus",   _btn_style(Color(0.08, 0.26, 0.14), Color(0.25, 0.80, 0.42)))
	save_btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	save_btn.add_theme_font_size_override("font_size", 13)
	save_btn.pressed.connect(_on_options_save)
	btn_row.add_child(save_btn)

	var epad := Control.new(); epad.custom_minimum_size = Vector2(20, 0)
	btn_row.add_child(epad)

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
	_rename_modal.visible       = false
	_delete_modal.visible       = false
	_discard_modal.visible      = false


func _show_main() -> void:
	_hide_all()
	_main_panel.visible = true


func _show_options() -> void:
	_hide_all()
	_options_panel.visible = true
	_options_dirty = false
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

	var slow := (settings.get_value("options", "placement_mode", "slow") as String) == "slow"
	_placement_switch.button_pressed = slow
	_update_placement_switch_text(slow)

	_loading_settings = false


func _on_language_changed(index: int) -> void:
	if _loading_settings: return
	settings.set_value("options", "language", LANGUAGES[index][1])
	TranslationServer.set_locale(LANGUAGES[index][1])
	_options_dirty = true


func _on_master_volume_changed(value: float) -> void:
	_lbl_master_val.text = "%d%%" % int(value)
	if _loading_settings: return
	settings.set_value("options", "master_volume", value)
	AudioServer.set_bus_volume_db(0, _vol_db(value))
	_options_dirty = true


func _on_music_volume_changed(value: float) -> void:
	_lbl_music_val.text = "%d%%" % int(value)
	if _loading_settings: return
	settings.set_value("options", "music_volume", value)
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0: AudioServer.set_bus_volume_db(idx, _vol_db(value))
	_options_dirty = true


func _on_sfx_volume_changed(value: float) -> void:
	_lbl_sfx_val.text = "%d%%" % int(value)
	if _loading_settings: return
	settings.set_value("options", "sfx_volume", value)
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0: AudioServer.set_bus_volume_db(idx, _vol_db(value))
	_options_dirty = true


func _on_window_mode_changed(index: int) -> void:
	if _loading_settings: return
	settings.set_value("options", "window_mode", index)
	_apply_window_mode(index)
	_options_dirty = true


func _on_placement_toggled(pressed: bool) -> void:
	_update_placement_switch_text(pressed)
	if _loading_settings: return
	settings.set_value("options", "placement_mode", "slow" if pressed else "quick")
	_options_dirty = true


func _on_options_back() -> void:
	if _options_dirty:
		_hide_all()
		_discard_modal.visible = true
	else:
		_show_main()


func _on_options_save() -> void:
	settings.save(Paths.SETTINGS_FILE)
	_options_dirty = false


func _on_options_discard() -> void:
	settings.load(Paths.SETTINGS_FILE)
	AudioServer.set_bus_volume_db(0, _vol_db(settings.get_value("options", "master_volume", 100.0)))
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0: AudioServer.set_bus_volume_db(mi, _vol_db(settings.get_value("options", "music_volume", 80.0)))
	var si := AudioServer.get_bus_index("SFX")
	if si >= 0: AudioServer.set_bus_volume_db(si, _vol_db(settings.get_value("options", "sfx_volume", 100.0)))
	_apply_window_mode(settings.get_value("options", "window_mode", 0))
	TranslationServer.set_locale(settings.get_value("options", "language", "de"))
	_options_dirty = false
	_show_main()


func _build_options_discard_modal() -> Control:
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

	_add_panel_title(vbox, "ÄNDERUNGEN VERWERFEN?")
	_add_hline(vbox)

	var text_lbl := Label.new()
	text_lbl.text = "Nicht gespeicherte Einstellungen\ngehen verloren."
	text_lbl.add_theme_color_override("font_color", C_TEXT)
	text_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(text_lbl)

	_add_spacer(vbox, 6)
	_add_menu_button(vbox, "→", "Verwerfen",  C_ACCENT_RD, _on_options_discard)
	_add_menu_button(vbox, "←", "Abbrechen",  C_ACCENT_MU, func():
		_hide_all()
		_options_panel.visible = true
	)

	return overlay


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
