extends Control

## Balatro-artiges Hauptmenü:
##  • Titel mittig
##  • Profil-Auswahl (Dropdown + Umbenennen) oben links – Profil 1/2/3 = Economy-Slots 0/1/2
##  • Untere Mitte: [Optionen]  [SPIELEN]  [Beenden]
##  • Optionen = dieselben Einstellungen wie im Spiel (PauseMenu), nur Vollbild, mit Auto-Speichern.
## Einstellungen lesen/schreiben dieselbe settings.cfg wie das In-Game-Menü → immer deckungsgleich.

const LANGUAGES    = [["Deutsch", "de"], ["English", "en"]]
const WINDOW_MODES = ["Fenster", "Rahmenlos", "Vollbild"]
# Wählbare Bildschirmauflösungen (Label + Fenstergröße).
const RESOLUTIONS = [
	["1280 × 720", Vector2i(1280, 720)],
	["1366 × 768", Vector2i(1366, 768)],
	["1600 × 900", Vector2i(1600, 900)],
	["1920 × 1080  (Full HD)", Vector2i(1920, 1080)],
	["2560 × 1440  (2K)", Vector2i(2560, 1440)],
	["3840 × 2160  (4K)", Vector2i(3840, 2160)],
	["2560 × 1080  (UltraWide)", Vector2i(2560, 1080)],
	["3440 × 1440  (UltraWide)", Vector2i(3440, 1440)],
	["5120 × 1440  (Super UltraWide)", Vector2i(5120, 1440)],
]
const DEFAULT_RESOLUTION = Vector2i(1920, 1080)

const PROFILE_COUNT = 3

# Einstellungs-Kategorien [Icon, Label] – identisch zum In-Game-Menü (PauseMenu).
func _settings_cats() -> Array:
	return [[Icons.SETTINGS, "Allgemein"], [Icons.VOLUME, "Audio"], [Icons.DESKTOP, "Anzeige"], [Icons.GAMEPAD, "Steuerung"]]

# Steuerungsarten (Pill-/Segment-Auswahl). Reihenfolge = Index.
const CTRL_SUBTABS = ["Klick modus", "Drag & Drop", "Mobile"]
const CTRL_MODE_IDS = ["click", "drag", "mobile"]
const CTRL_DESCS = [
	"Wähle ein Teil in der Palette und klicke dann auf das Baufeld, um es zu setzen.",
	"Ziehe Teile direkt aus der Palette auf das Baufeld – beim Loslassen wird gesetzt.",
	"Touch-Bedienung fürs Handy: Ziehen & Ablegen plus optionaler Drehen-Knopf.",
]

# Discord-artige Graupalette – siehe GameHUD.gd (alle 6 Dateien synchron halten).
const C_BG        := Color(0.118, 0.122, 0.133)   # #1e1f22
const C_SURFACE   := Color(0.169, 0.176, 0.192)   # #2b2d31
const C_SURFACE2  := Color(0.220, 0.227, 0.251)   # #383a40
const C_ACCENT    := Color(0.345, 0.396, 0.949)   # #5865f2 Blurple
const C_ACCENT_MU := Color(0.290, 0.310, 0.490)
const C_ACCENT_RD := Color(0.929, 0.259, 0.271)   # #ed4245
const C_GREEN     := Color(0.30, 0.80, 0.46)      # Play
const C_TEXT      := Color(0.859, 0.871, 0.882)   # #dbdee1
const C_TEXT_DIM  := Color(0.580, 0.608, 0.643)   # #949ba4
const C_LINE      := Color(0.247, 0.255, 0.278)   # #3f4147

# ── Design „Road Tycoon" (Hauptmenü-Optik aus Claude-Design-Handoff) ──
const D_BOX_BG     := Color(0.149, 0.169, 0.200)  # #262b33 Profil/Box-Flächen
const D_BOX_BORDER := Color(0.078, 0.086, 0.106)  # #14161b dunkler Rahmen
const D_BOX_LEDGE  := Color(0.059, 0.067, 0.082)  # #0f1115 3D-Sockel
const D_MENU_BG    := Color(0.118, 0.133, 0.165)  # #1e222a Menü-Box
const D_MENU_LEDGE := Color(0.051, 0.059, 0.071)  # #0d0f12
const D_TITLE_BLUE := Color(0.490, 0.588, 1.000)  # #7d96ff ROAD
const D_TITLE_BLUE_OUT := Color(0.106, 0.137, 0.314) # #1b2350
const D_TITLE_CREAM := Color(0.953, 0.933, 0.882) # #f3eee1 TYCOON
const D_TITLE_CREAM_OUT := Color(0.165, 0.184, 0.239) # #2a2f3d
const D_LINE_BLUE  := Color(0.435, 0.545, 1.000)  # #6f8bff Trennstrich/Glow
# Candy-Buttons (finaler Design-Handoff): dunkle Innenfläche, farbige Outline + farbiger Text.
# Alle drei Knöpfe teilen sich dieselbe dunkle Fläche und denselben dunklen 3D-Sockel –
# nur Rahmen- und Textfarbe unterscheiden sie (blau · grün · rot).
const D_BTN_FACE      := Color(0.137, 0.157, 0.188)  # #232830 dunkle Innenfläche
const D_BTN_FACE_H    := Color(0.153, 0.176, 0.212)  # #272d36 Hover-Fläche
const D_BTN_LEDGE     := Color(0.078, 0.086, 0.106)  # #14161b 3D-Sockel (harter Schatten)
const D_BTN_BLUE_BRD  := Color(0.345, 0.471, 0.941)  # #5878f0 Optionen-Rahmen
const D_BTN_BLUE_TXT  := Color(0.557, 0.643, 1.000)  # #8ea4ff Optionen-Text
const D_BTN_GREEN_BRD := Color(0.271, 0.769, 0.424)  # #45c46c SPIELEN-Rahmen
const D_BTN_GREEN_TXT := Color(0.373, 0.851, 0.541)  # #5fd98a SPIELEN-Text
const D_BTN_RED_BRD   := Color(0.886, 0.341, 0.298)  # #e2574c Beenden-Rahmen
const D_BTN_RED_TXT   := Color(0.961, 0.537, 0.498)  # #f5897f Beenden-Text

var settings := ConfigFile.new()

# Hintergrund-Shader: Auflösung wird übergeben, damit die Straße bei jedem
# Fenster-Seitenverhältnis gleich bleibt (stretch/aspect = "expand"). Der „horizon"
# wird auf die Höhe der blauen Linie unter dem Titel gesetzt – dort startet die Straße.
var _bg_mat:    ShaderMaterial
var _bg_rect:   ColorRect
var _blue_line: TextureRect
var _title_vb:  VBoxContainer
# Ruhe-Y des Titels (er schwebt von hier aus nach oben; die blaue Linie bleibt fix darunter).
const TITLE_BASE_Y    := 70.0
const TITLE_FLOAT_AMP := 7.0   # Hub nach oben in px (wie im Design: translateY -7px)
const TITLE_FLOAT_DUR := 6.0   # Sekunden pro voller Auf-/Ab-Zyklus (wie im Design)
var _title_phase := 0.0        # läuft 0..1, treibt das Schweben in _process()

var _main_panel:    Control
var _options_panel: Control
var _rename_modal:  Control
var _delete_modal:  Control
var _credits_modal: Control
var _bug_modal:     Control
var _delete_text_lbl: Label

# Discord-Webhook-URL (Discord → Kanal → Bearbeiten → Integrationen → Webhooks → Neuer Webhook → URL kopieren).
# Leer lassen = Senden deaktiviert (zeigt einen Hinweis). Achtung: Die URL steckt im Client und ist damit auslesbar.
const BUG_WEBHOOK_URL := "https://discord.com/api/webhooks/1513832862019879052/DsbkeRXKj0zDzZ4UU31VLcCuS5_v2RFGzTTNLU12ktLdpx0DHBDI_jzWq02QvDidb8sZ"
const BUG_MAX_CHARS   := 1000
const BUG_NAME_MAX    := 64
var _bug_name_edit:  LineEdit
var _bug_text_edit:  TextEdit
var _bug_counter:    Label
var _bug_send_btn:   Button
var _bug_status_lbl: Label
var _bug_http:       HTTPRequest

var _settings_dirty: bool = false

# ── Profile ──
var _active_profile: int = 0
var _profile_option: OptionButton
var _rename_line_edit: LineEdit

# ── Einstellungen ──
var _lang_option:   OptionButton
var _master_slider: HSlider
var _music_slider:  HSlider
var _sfx_slider:    HSlider
var _window_option: OptionButton
var _res_option:    OptionButton
var _rotate_switch: CheckButton
var _cheat_switch:  CheckButton
var _music_min_switch: CuteToggle
var _fps_switch:       CuteToggle
var _colorblind_switch: CuteToggle
var _darkmode_switch:   CuteToggle
var _mult_option:       OptionButton
var _lbl_master_val: Label
var _lbl_music_val:  Label
var _lbl_sfx_val:    Label

# Reihenfolge entspricht Display.MultiplierMode (ALL, AFFECTED, NONE).
const MULT_DISPLAY_OPTIONS := ["Alles anzeigen", "Nur betroffene Felder", "Nichts"]

var _settings_nav_btns:   Array[Button]  = []
var _settings_cat_panels: Array[Control] = []
# Buttons mit Icon-Präfix im Text: selbst übersetzt (auto_translate aus), Neuaufbau bei Sprachwechsel.
var _icon_text_btns:      Array[Button]  = []

# Steuerung – Modus-Auswahl
var _ctrl_subtab:        int           = 0
var _ctrl_subtab_btns:   Array[Button] = []
var _ctrl_desc_lbl:      Label
var _ctrl_rotate_label:  Label
var _ctrl_mobile_hint:   Label
var _mobile_settings_box: VBoxContainer

var _loading_settings := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	settings.load(Paths.SETTINGS_FILE)
	_active_profile = clampi(int(settings.get_value("options", "active_profile", 0)), 0, PROFILE_COUNT - 1)
	Economy.set_active_slot(_active_profile)

	_build_background()
	_main_panel    = _build_main_panel()
	_options_panel = _build_options_panel()
	_rename_modal  = _build_rename_modal()
	_delete_modal  = _build_delete_modal()
	_credits_modal = _build_credits_modal()
	_bug_modal     = _build_bug_modal()
	_show_main()
	_apply_settings()
	_refresh_profiles()
	# Nach dem ersten Layout den Straßen-Horizont auf die blaue Linie setzen.
	call_deferred("_update_bg")


# Kontinuierliches, butterweiches Titel-Schweben: jeder Frame ist ein Stützpunkt.
# Cosinus-Hub (0 → -AMP → 0) hat überall stetige Geschwindigkeit, also kein „Springen".
func _process(delta: float) -> void:
	if _title_vb == null:
		return
	_title_phase = fmod(_title_phase + delta / TITLE_FLOAT_DUR, 1.0)
	var off := -0.5 * TITLE_FLOAT_AMP * (1.0 - cos(TAU * _title_phase))
	_title_vb.position.y = TITLE_BASE_Y + off


# ── Hintergrund ───────────────────────────────────────────────────────────────

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = C_BG   # Fallback, falls der Shader nicht lädt
	_bg_rect = bg
	var sh := load(Paths.SHADER_MAINMENU_BG)
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		bg.material = mat
		_bg_mat = mat
		# Auflösung + Horizont an den Shader geben und bei jeder Größenänderung neu setzen.
		bg.resized.connect(_update_bg)
		_update_bg()
	add_child(bg)


# Übergibt Pixelgröße (seitenverhältnis-korrekte Straße) und Horizont (Höhe der
# blauen Linie = wo die Straße zu spawnen beginnt) an den Hintergrund-Shader.
func _update_bg() -> void:
	_layout_title_line()
	if _bg_mat == null or _bg_rect == null:
		return
	var s := _bg_rect.size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	_bg_mat.set_shader_parameter("resolution", s)
	if _blue_line != null and _blue_line.is_inside_tree():
		# Mitte der blauen Linie als UV-Anteil → Straße startet exakt dort.
		var y := _blue_line.position.y + _blue_line.size.y * 0.5
		_bg_mat.set_shader_parameter("horizon", clampf(y / s.y, 0.05, 0.92))


# Setzt die blaue Linie fix unter den ruhenden Titel (unabhängig vom Schweben).
func _layout_title_line() -> void:
	if _blue_line == null or _title_vb == null:
		return
	_blue_line.position.y = TITLE_BASE_Y + _title_vb.size.y + 16.0


# ── Hauptmenü ─────────────────────────────────────────────────────────────────

func _build_main_panel() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Version-Badge (oben rechts) ──
	var ver_box := PanelContainer.new()
	ver_box.add_theme_stylebox_override("panel", _design_box_style(Color(0.125, 0.141, 0.169), Color(0.082, 0.090, 0.110), D_BOX_LEDGE, 11, 4))
	root.add_child(ver_box)
	var ver_lbl := Label.new()
	ver_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	ver_lbl.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	ver_lbl.add_theme_font_size_override("font_size", 15)
	ver_lbl.add_theme_color_override("font_color", Color(0.510, 0.545, 0.600))
	ver_box.add_child(ver_lbl)
	ver_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 30)

	# ── Titel „ROAD TYCOON" (Sticker-Look) – NUR der Text schwebt, die Linie bleibt fix ──
	var title_vb := VBoxContainer.new()
	title_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	title_vb.add_theme_constant_override("separation", 2)
	title_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_vb)
	_title_vb = title_vb

	var line1 := _sticker_label("ROAD", D_TITLE_BLUE, D_TITLE_BLUE_OUT)
	title_vb.add_child(line1)
	var line2 := _sticker_label("TYCOON", D_TITLE_CREAM, D_TITLE_CREAM_OUT)
	title_vb.add_child(line2)

	title_vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 0)
	title_vb.position.y = TITLE_BASE_Y
	# Schweben läuft kontinuierlich in _process() (jeder Frame = ein Stützpunkt) →
	# keine harten Wendepunkte mehr. Werte siehe TITLE_FLOAT_* / _process().

	# Blaue Linie: eigenständig & statisch, sitzt fix unter dem Titel (bewegt sich NICHT mit).
	_blue_line = TextureRect.new()
	_blue_line.texture = _blue_line_tex(440, 3)
	_blue_line.custom_minimum_size = Vector2(440, 3)
	_blue_line.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_blue_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_blue_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_blue_line)
	_blue_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 0)
	# Y wird in _layout_title_line() unter den Titel gesetzt; danach den Straßen-Horizont nachziehen.
	_blue_line.resized.connect(_update_bg)

	# ── Profil-Auswahl (oben links, ohne Label) ──
	var prof_row := HBoxContainer.new()
	prof_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	prof_row.position = Vector2(38, 34)
	prof_row.add_theme_constant_override("separation", 11)
	root.add_child(prof_row)

	_profile_option = OptionButton.new()
	_profile_option.custom_minimum_size = Vector2(248, 52)
	_profile_option.focus_mode = Control.FOCUS_NONE
	_profile_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_profile_option.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_style_profile_box(_profile_option)
	for i in PROFILE_COUNT:
		_profile_option.add_item(_profile_label(i))
	_profile_option.item_selected.connect(_on_profile_selected)
	prof_row.add_child(_profile_option)

	var ren_btn := Button.new()
	ren_btn.text = Icons.PENCIL
	ren_btn.custom_minimum_size = Vector2(52, 52)
	ren_btn.focus_mode = Control.FOCUS_NONE
	ren_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ren_btn.tooltip_text = "Profil umbenennen"
	var ren_sb := _design_box_style(D_BOX_BG, D_BOX_BORDER, D_BOX_LEDGE, 14, 4)
	var ren_sb_h := _design_box_style(D_BOX_BG.lightened(0.10), D_BOX_BORDER, D_BOX_LEDGE, 14, 4)
	ren_btn.add_theme_stylebox_override("normal",  ren_sb)
	ren_btn.add_theme_stylebox_override("hover",   ren_sb_h)
	ren_btn.add_theme_stylebox_override("pressed", ren_sb)
	ren_btn.add_theme_stylebox_override("focus",   ren_sb)
	ren_btn.add_theme_color_override("font_color", Color(0.761, 0.784, 0.824))
	ren_btn.add_theme_font_size_override("font_size", 18)
	ren_btn.pressed.connect(func(): _show_rename_modal(_active_profile))
	prof_row.add_child(ren_btn)

	# ── Menü-Box unten: Optionen · SPIELEN · Beenden ──
	var menu_wrap := CenterContainer.new()
	menu_wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	menu_wrap.offset_top    = -150
	menu_wrap.offset_bottom = -38
	root.add_child(menu_wrap)

	var menu_box := PanelContainer.new()
	menu_box.add_theme_stylebox_override("panel", _design_box_style(D_MENU_BG, D_BOX_BORDER, D_MENU_LEDGE, 22, 4, 16, 20))
	menu_wrap.add_child(menu_box)

	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 16)
	menu_box.add_child(brow)

	var opt_btn := _candy_btn("Optionen", D_BTN_FACE, D_BTN_BLUE_BRD, D_BTN_LEDGE, D_BTN_BLUE_TXT, 20, 11, 20, _show_options)
	opt_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	brow.add_child(opt_btn)

	var play_btn := _candy_btn("SPIELEN", D_BTN_FACE, D_BTN_GREEN_BRD, D_BTN_LEDGE, D_BTN_GREEN_TXT, 29, 18, 30, _on_play_pressed)
	play_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	brow.add_child(play_btn)

	var quit_btn := _candy_btn("Beenden", D_BTN_FACE, D_BTN_RED_BRD, D_BTN_LEDGE, D_BTN_RED_TXT, 20, 11, 20, _on_quit)
	quit_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	brow.add_child(quit_btn)

	# „Fehler melden" – dezenter Link unten rechts (Text + Käfer-Icon rechts daneben).
	var bug_btn := Button.new()
	bug_btn.focus_mode = Control.FOCUS_NONE
	bug_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	bug_btn.add_theme_stylebox_override("normal",  empty)
	bug_btn.add_theme_stylebox_override("hover",   empty)
	bug_btn.add_theme_stylebox_override("pressed", empty)
	bug_btn.add_theme_stylebox_override("focus",   empty)
	bug_btn.add_theme_color_override("font_color",       Color(0.420, 0.451, 0.502))
	bug_btn.add_theme_color_override("font_hover_color", C_TEXT)
	bug_btn.add_theme_font_size_override("font_size", 16)
	_set_icon_btn_text(bug_btn, Icons.BUG, "Fehler melden", true)
	bug_btn.pressed.connect(_show_bug_modal)
	root.add_child(bug_btn)
	bug_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)

	return root


# ── Design-Helfer „Road Tycoon" ───────────────────────────────────────────────

# Box-Stylebox mit dunklem Rahmen und 3D-Sockel (dicker unterer Rand).
func _design_box_style(bg: Color, border: Color, ledge: Color, radius: int, border_w: int,
		pad_v: int = 8, pad_h: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_width_left   = border_w
	sb.border_width_top     = border_w
	sb.border_width_right  = border_w
	sb.border_width_bottom = border_w + 4   # dickerer Boden = 3D-Sockel
	sb.border_color = border
	sb.shadow_color  = ledge
	sb.shadow_size   = 0
	sb.shadow_offset = Vector2(0, 5)
	sb.content_margin_left   = pad_h
	sb.content_margin_right  = pad_h
	sb.content_margin_top    = pad_v
	sb.content_margin_bottom = pad_v
	return sb


# Sticker-Titel-Label: dicke Outline + dunkler Schlagschatten (3D-Aufkleber-Look).
func _sticker_label(text: String, col: Color, outline: Color) -> Label:
	var lbl := Label.new()
	lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 72)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_constant_override("outline_size", 10)
	lbl.add_theme_color_override("font_outline_color", outline)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 6)
	return lbl


# Horizontaler Blauverlauf-Strich (an den Enden transparent, mittig leuchtend).
func _blue_line_tex(w: int, h: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.24, 0.5, 0.76, 1.0])
	g.colors = PackedColorArray([
		Color(D_LINE_BLUE.r, D_LINE_BLUE.g, D_LINE_BLUE.b, 0.0),
		D_LINE_BLUE, D_TITLE_BLUE, D_LINE_BLUE,
		Color(D_LINE_BLUE.r, D_LINE_BLUE.g, D_LINE_BLUE.b, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = w
	tex.height = h
	tex.fill_from = Vector2(0, 0)
	tex.fill_to   = Vector2(1, 0)
	return tex


# Knubbeliger Candy-Button mit 3D-Sockel und taktilem Druck-Feedback.
func _candy_btn(text: String, face: Color, border: Color, ledge: Color, fg: Color,
		font_size: int, pad_v: int, pad_h: int, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",  _candy_sb(face,         border, ledge, pad_v, pad_h, false))
	btn.add_theme_stylebox_override("hover",   _candy_sb(D_BTN_FACE_H, border, ledge, pad_v, pad_h, false))
	btn.add_theme_stylebox_override("pressed", _candy_sb(face,         border, ledge, pad_v, pad_h, true))
	btn.add_theme_stylebox_override("focus",   _candy_sb(face,         border, ledge, pad_v, pad_h, false))
	btn.add_theme_color_override("font_color",       fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.pressed.connect(cb)
	return btn


func _candy_sb(face: Color, border: Color, ledge: Color, pad_v: int, pad_h: int, pressed: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = face
	sb.set_corner_radius_all(16)
	# Gleichmäßige farbige Outline rundum – die Farbe trägt der Knopf, nicht die Fläche.
	sb.border_color = border
	sb.set_border_width_all(4)
	# Dunkler 3D-Sockel als harter (unscharfer) Schatten unter dem Knopf (box-shadow 0 Npx 0).
	# Gedrückt: Sockel schrumpft, Inhalt rutscht nach unten → Button „sinkt".
	sb.shadow_color  = ledge
	sb.shadow_size   = 0
	sb.shadow_offset = Vector2(0, 3 if pressed else 7)
	sb.content_margin_left   = pad_h
	sb.content_margin_right  = pad_h
	sb.content_margin_top    = (pad_v + 5) if pressed else pad_v
	sb.content_margin_bottom = pad_v
	return sb


# Profil-Auswahl (OptionButton) im „Road Tycoon"-Box-Look.
func _style_profile_box(opt: OptionButton) -> void:
	var sb   := _design_box_style(D_BOX_BG, D_BOX_BORDER, D_BOX_LEDGE, 14, 4, 11, 18)
	var sb_h := _design_box_style(D_BOX_BG.lightened(0.10), D_BOX_BORDER, D_BOX_LEDGE, 14, 4, 11, 18)
	# Mehr Luft rechts, damit der Dropdown-Pfeil nicht am Rand klebt.
	sb.content_margin_right = 30
	sb_h.content_margin_right = 30
	opt.add_theme_constant_override("arrow_margin", 8)
	opt.add_theme_stylebox_override("normal",  sb)
	opt.add_theme_stylebox_override("hover",   sb_h)
	opt.add_theme_stylebox_override("pressed", sb_h)
	opt.add_theme_stylebox_override("focus",   sb)
	opt.add_theme_color_override("font_color",       Color(0.933, 0.941, 0.953))
	opt.add_theme_color_override("font_hover_color", Color(0.984, 0.992, 1.0))
	opt.add_theme_font_size_override("font_size", 21)
	# Popup-Liste passend einfärben.
	var pop := opt.get_popup()
	pop.add_theme_color_override("font_color", Color(0.839, 0.855, 0.882))
	var pop_sb := StyleBoxFlat.new()
	pop_sb.bg_color = Color(0.137, 0.153, 0.180)
	pop_sb.set_corner_radius_all(12)
	pop_sb.set_border_width_all(3)
	pop_sb.border_color = D_BOX_BORDER
	pop_sb.content_margin_left = 6; pop_sb.content_margin_right = 6
	pop_sb.content_margin_top  = 6; pop_sb.content_margin_bottom = 6
	pop.add_theme_stylebox_override("panel", pop_sb)


# Gefüllter, abgerundeter Aktions-Button mit vollem Rahmen (Balatro-Look).
func _main_action_btn(txt: String, sz: Vector2, bg: Color, border: Color, fg: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = sz
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",  _action_sb(bg,                 border))
	btn.add_theme_stylebox_override("hover",   _action_sb(bg.lightened(0.10), border.lightened(0.18)))
	btn.add_theme_stylebox_override("pressed", _action_sb(bg.darkened(0.10),  border))
	btn.add_theme_stylebox_override("focus",   _action_sb(bg,                 border))
	btn.add_theme_color_override("font_color",       fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(cb)
	return btn


func _action_sb(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(12)
	sb.content_margin_left   = 18
	sb.content_margin_right  = 18
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	# Sanfter Schlagschatten → angehobener Knopf.
	sb.shadow_color  = Color(0, 0, 0, 0.4)
	sb.shadow_size   = 4
	sb.shadow_offset = Vector2(0, 3)
	return sb


# ── Profile ───────────────────────────────────────────────────────────────────

func _profile_label(slot: int) -> String:
	var info = Economy.get_slot_info(slot)
	var custom := String(info.get("name", "")) if not info.is_empty() else ""
	# Eigener Name bleibt unübersetzt; nur der Standard ("Profil N") wird lokalisiert
	# (das Dropdown hat auto_translate aus, um Nutzernamen zu schützen).
	return custom if custom != "" else tr("Profil %d") % (slot + 1)


func _refresh_profiles() -> void:
	if _profile_option == null:
		return
	for i in PROFILE_COUNT:
		_profile_option.set_item_text(i, _profile_label(i))
	_profile_option.selected = _active_profile


func _on_profile_selected(idx: int) -> void:
	_active_profile = idx
	Economy.set_active_slot(idx)
	settings.set_value("options", "active_profile", idx)
	settings.save(Paths.SETTINGS_FILE)


func _on_play_pressed() -> void:
	var slot := _active_profile
	# Vorhandenes Profil fortsetzen, leeres Profil frisch starten.
	if Economy.slot_exists(slot):
		Economy.load_game_from_slot(slot)
	else:
		Economy.reset_slot(slot)
	get_tree().change_scene_to_file(Paths.SCENE_BUILDER)


func _on_quit() -> void:
	get_tree().quit()


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

	_add_panel_title(vbox, "PROFIL UMBENENNEN")
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
	_add_menu_button(vbox, "←", "Abbrechen",  C_ACCENT_MU, _show_main)

	return overlay


func _show_rename_modal(slot: int) -> void:
	_active_profile = slot
	var info = Economy.get_slot_info(slot)
	_rename_line_edit.text = String(info.get("name", "")) if not info.is_empty() else ""
	_hide_all()
	_rename_modal.visible = true
	_rename_line_edit.grab_focus()


func _confirm_rename() -> void:
	var new_name = _rename_line_edit.text.strip_edges()
	Economy.rename_slot(_active_profile, new_name)
	_refresh_profiles()
	_show_main()


# ── Spielstand-löschen-Modal ──────────────────────────────────────────────────

func _build_delete_modal() -> Control:
	var overlay := _make_overlay()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_add_panel_title(vbox, "SPIELSTAND LÖSCHEN?")
	_add_hline(vbox)

	_delete_text_lbl = Label.new()
	_delete_text_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_delete_text_lbl.add_theme_color_override("font_color", C_TEXT)
	_delete_text_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_delete_text_lbl)

	_add_spacer(vbox, 6)
	_add_menu_button(vbox, "→", "Löschen",   C_ACCENT_RD, _confirm_delete)
	_add_menu_button(vbox, "←", "Abbrechen", C_ACCENT_MU, func(): _delete_modal.visible = false)

	return overlay


# Modal liegt über dem (gedimmten) Optionen-Panel – nur das Modal ein-/ausblenden.
func _show_delete_modal() -> void:
	var pname := _profile_label(_active_profile)
	_delete_text_lbl.text = tr("Das Profil „%s“ wird\nunwiderruflich gelöscht.") % pname
	_delete_modal.visible = true


func _confirm_delete() -> void:
	Economy.delete_slot(_active_profile)
	_refresh_profiles()
	_delete_modal.visible = false


# ── Credits-Modal ─────────────────────────────────────────────────────────────

func _build_credits_modal() -> Control:
	var overlay := _make_overlay()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(RUI.px(540), 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Dev Team
	_credits_heading(vbox, "DEV TEAM")
	_credits_thin_div(vbox)
	_add_spacer(vbox, 4)
	_credits_names_rows(vbox, ["Civoknis", "Reo"])

	_credits_big_div(vbox)

	# Mitwirkende
	_credits_heading(vbox, "MITWIRKENDE")
	_credits_thin_div(vbox)
	_add_spacer(vbox, 4)
	var audio_lbl := Label.new()
	audio_lbl.text = "Audio: Tessemi"
	audio_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	audio_lbl.add_theme_font_size_override("font_size", 17)
	audio_lbl.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(audio_lbl)

	var visuals_lbl := Label.new()
	visuals_lbl.text = "Visuals: RaccoonDog"
	visuals_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visuals_lbl.add_theme_font_size_override("font_size", 17)
	visuals_lbl.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(visuals_lbl)

	_credits_big_div(vbox)

	# Tester
	_credits_heading(vbox, "TESTER")
	_credits_thin_div(vbox)
	_add_spacer(vbox, 4)
	_credits_names_rows(vbox, ["DaCat", "Marlonikus", "Tessemi", "RaccoonDog"])
	_add_spacer(vbox, 14)
	_add_menu_button(vbox, "←", "Zurück", C_ACCENT_MU, func(): _credits_modal.visible = false)

	return overlay


func _show_credits_modal() -> void:
	_credits_modal.visible = true


# Große, geprägte (3D) Überschrift im Credits-Modal.
func _credits_heading(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 27)
	lbl.add_theme_color_override("font_color", C_ACCENT)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_emboss(lbl, 0.75)
	parent.add_child(lbl)


# Dünne Trennlinie direkt unter einer Überschrift.
func _credits_thin_div(parent: VBoxContainer) -> void:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.color = C_LINE
	parent.add_child(d)


# Größere Trennlinie zwischen den Abschnitten.
func _credits_big_div(parent: VBoxContainer) -> void:
	_add_spacer(parent, 8)
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 2)
	d.color = C_ACCENT_MU
	parent.add_child(d)
	_add_spacer(parent, 8)


# Namen nebeneinander, maximal 4 pro Zeile, dann Umbruch. Zentriert (fett = Standardschrift).
func _credits_names_rows(parent: VBoxContainer, names: Array) -> void:
	var i := 0
	while i < names.size():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 28)
		var upper := mini(i + 4, names.size())
		for j in range(i, upper):
			var lbl := Label.new()
			lbl.text = names[j]
			lbl.add_theme_font_size_override("font_size", 17)
			lbl.add_theme_color_override("font_color", C_TEXT)
			row.add_child(lbl)
		parent.add_child(row)
		i += 4


# ── Bug-Report-Modal ──────────────────────────────────────────────────────────

func _build_bug_modal() -> Control:
	var overlay := _make_overlay()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_add_panel_title(vbox, "FEHLER MELDEN")
	_add_hline(vbox)

	var hint := Label.new()
	hint.text = "Beschreibe den Fehler und klicke auf Senden!"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", C_TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	_bug_name_edit = LineEdit.new()
	_bug_name_edit.placeholder_text = "Name / Discord ID (Optional)"
	_bug_name_edit.max_length = BUG_NAME_MAX
	_bug_name_edit.add_theme_color_override("font_color", C_TEXT)
	_bug_name_edit.add_theme_color_override("font_placeholder_color", C_TEXT_DIM)
	_bug_name_edit.add_theme_font_size_override("font_size", 14)
	var name_sb := StyleBoxFlat.new()
	name_sb.bg_color = C_SURFACE
	name_sb.set_border_width_all(1)
	name_sb.border_color = C_ACCENT_MU
	name_sb.set_corner_radius_all(6)
	name_sb.content_margin_left = 8; name_sb.content_margin_right = 8
	name_sb.content_margin_top  = 6; name_sb.content_margin_bottom = 6
	_bug_name_edit.add_theme_stylebox_override("normal", name_sb)
	_bug_name_edit.add_theme_stylebox_override("focus", name_sb)
	vbox.add_child(_bug_name_edit)

	_bug_text_edit = TextEdit.new()
	_bug_text_edit.custom_minimum_size = Vector2(0, 200)
	_bug_text_edit.placeholder_text = "Bitte erkläre uns kurz den Fehler oder schreibe uns einen Verbesserungsvorschlag!"
	_bug_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_bug_text_edit.add_theme_color_override("font_color", C_TEXT)
	_bug_text_edit.add_theme_color_override("font_placeholder_color", C_TEXT_DIM)
	_bug_text_edit.add_theme_font_size_override("font_size", 14)
	var te_sb := StyleBoxFlat.new()
	te_sb.bg_color = C_SURFACE
	te_sb.set_border_width_all(1)
	te_sb.border_color = C_ACCENT_MU
	te_sb.set_corner_radius_all(6)
	te_sb.content_margin_left = 8; te_sb.content_margin_right = 8
	te_sb.content_margin_top  = 6; te_sb.content_margin_bottom = 6
	_bug_text_edit.add_theme_stylebox_override("normal", te_sb)
	_bug_text_edit.add_theme_stylebox_override("focus", te_sb)
	_bug_text_edit.text_changed.connect(_on_bug_text_changed)
	vbox.add_child(_bug_text_edit)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	vbox.add_child(bottom)
	_bug_counter = Label.new()
	_bug_counter.text = "0/%d" % BUG_MAX_CHARS
	_bug_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bug_counter.add_theme_font_size_override("font_size", 11)
	_bug_counter.add_theme_color_override("font_color", C_TEXT_DIM)
	bottom.add_child(_bug_counter)
	_bug_status_lbl = Label.new()
	_bug_status_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_bug_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bug_status_lbl.add_theme_font_size_override("font_size", 11)
	bottom.add_child(_bug_status_lbl)

	_add_spacer(vbox, 4)
	_bug_send_btn = _add_menu_button(vbox, "→", "Senden", C_ACCENT, _send_bug_report)
	_add_menu_button(vbox, "←", "Abbrechen", C_ACCENT_MU, _show_main)

	# Versand läuft über einen HTTP-POST an den Discord-Webhook (kein Mailprogramm).
	_bug_http = HTTPRequest.new()
	add_child(_bug_http)
	_bug_http.request_completed.connect(_on_bug_request_completed)

	return overlay


func _show_bug_modal() -> void:
	_bug_name_edit.text = ""
	_bug_text_edit.text = ""
	_bug_counter.text = "0/%d" % BUG_MAX_CHARS
	_bug_status_lbl.text = ""
	_bug_send_btn.disabled = false
	_hide_all()
	_bug_modal.visible = true
	_bug_text_edit.grab_focus()


# Auf maximal BUG_MAX_CHARS Zeichen begrenzen und den Zähler aktualisieren.
func _on_bug_text_changed() -> void:
	var t := _bug_text_edit.text
	if t.length() > BUG_MAX_CHARS:
		_bug_text_edit.text = t.substr(0, BUG_MAX_CHARS)
		# Cursor ans Ende setzen (substr resettet ihn an den Anfang).
		var last := _bug_text_edit.get_line_count() - 1
		_bug_text_edit.set_caret_line(last)
		_bug_text_edit.set_caret_column(_bug_text_edit.get_line(last).length())
	_bug_counter.text = "%d/%d" % [_bug_text_edit.text.length(), BUG_MAX_CHARS]


# Schickt die Nachricht per HTTPS-POST an den Discord-Webhook ({"content": "..."}).
func _send_bug_report() -> void:
	var body := _bug_text_edit.text.strip_edges()
	if body == "":
		return
	if BUG_WEBHOOK_URL == "":
		_set_bug_status(tr("Kein Webhook konfiguriert."), C_ACCENT_RD)
		return
	_bug_send_btn.disabled = true
	_set_bug_status(tr("Senden…"), C_TEXT_DIM)
	var payload := JSON.stringify(_bug_payload(body))
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _bug_http.request(BUG_WEBHOOK_URL, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		_on_bug_send_failed()


# Baut die Discord-Webhook-Nutzlast: die Nachricht als Embed-Beschreibung plus relevante
# Kontextdaten (Profil, Guthaben, Sprache, OS, Fenster, Engine/Version) als Embed-Felder.
func _bug_payload(message: String) -> Dictionary:
	var slot := _active_profile
	var info = Economy.get_slot_info(slot)
	var currency := str(int(info.get("currency", 0))) if not info.is_empty() else "—"
	var win := DisplayServer.window_get_size()
	var fields := [
		{"name": "Profil",   "value": "%s (Slot %d)" % [_profile_label(slot), slot + 1], "inline": true},
		{"name": "Guthaben", "value": currency, "inline": true},
		{"name": "Sprache",  "value": TranslationServer.get_locale(), "inline": true},
		{"name": "OS",       "value": "%s %s" % [OS.get_name(), OS.get_version()], "inline": true},
		{"name": "Fenster",  "value": "%d×%d" % [win.x, win.y], "inline": true},
		{"name": "Engine",   "value": str(Engine.get_version_info().get("string", "")), "inline": true},
	]
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	if ver != "":
		fields.append({"name": "Version", "value": ver, "inline": true})
	var reporter := _bug_name_edit.text.strip_edges()
	if reporter != "":
		fields.insert(0, {"name": "Von", "value": reporter, "inline": false})
	return {
		"embeds": [{
			"title": "🐛 Bug-Report",
			"description": message,
			"color": 0xED4245,
			"fields": fields,
			"timestamp": Time.get_datetime_string_from_system(true) + "Z",
		}]
	}


func _on_bug_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	# Discord antwortet bei Erfolg mit 204 (No Content), je nach Aufruf auch 200.
	if result == HTTPRequest.RESULT_SUCCESS and response_code in [200, 204]:
		_bug_send_btn.disabled = false
		_set_bug_status(Icons.CHECK + " " + tr("Gesendet! Danke."), C_GREEN)
		_bug_text_edit.text = ""
		_bug_counter.text = "0/%d" % BUG_MAX_CHARS
		get_tree().create_timer(1.4).timeout.connect(func():
			if _bug_modal != null and _bug_modal.visible:
				_show_main()
		)
	else:
		_on_bug_send_failed()


func _on_bug_send_failed() -> void:
	_bug_send_btn.disabled = false
	_set_bug_status(Icons.X + " " + tr("Senden fehlgeschlagen. Bitte später erneut."), C_ACCENT_RD)


func _set_bug_status(text: String, color: Color) -> void:
	_bug_status_lbl.text = text
	_bug_status_lbl.add_theme_color_override("font_color", color)


# ── Optionen-Panel (Vollbild, identisch zum In-Game-Menü) ─────────────────────

func _build_options_panel() -> Control:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = C_BG
	overlay.visible = false
	add_child(overlay)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_vbox.add_theme_constant_override("separation", 0)
	overlay.add_child(outer_vbox)

	# Header
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 56)
	header.add_theme_constant_override("separation", 0)
	outer_vbox.add_child(header)
	var lpad := Control.new(); lpad.custom_minimum_size = Vector2(28, 0)
	header.add_child(lpad)
	var title := Label.new()
	title.text = "OPTIONEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_ACCENT)
	_emboss(title)
	header.add_child(title)
	_add_hline(outer_vbox)

	# Horizontale Kategorie-Leiste
	var navbar := PanelContainer.new()
	navbar.custom_minimum_size = Vector2(0, 50)
	var nav_sb := StyleBoxFlat.new()
	nav_sb.bg_color = C_SURFACE.darkened(0.18)
	nav_sb.border_width_bottom = 1
	nav_sb.border_color = C_LINE
	nav_sb.content_margin_left = 24; nav_sb.content_margin_right = 24
	nav_sb.content_margin_top = 8;   nav_sb.content_margin_bottom = 8
	navbar.add_theme_stylebox_override("panel", nav_sb)
	outer_vbox.add_child(navbar)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	navbar.add_child(nav)
	_settings_nav_btns.clear()
	var cats := _settings_cats()
	for i in cats.size():
		_add_settings_nav(nav, i, cats[i][0], cats[i][1])

	# Inhaltsbereich
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	outer_vbox.add_child(holder)
	_settings_cat_panels.clear()

	# Kategorie 0 – Allgemein (Sprache)
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

	_add_spacer(v0, 10)
	_add_hline(v0)
	_add_section_label(v0, "PROFIL")
	var prof_btns := HBoxContainer.new()
	prof_btns.add_theme_constant_override("separation", 10)
	v0.add_child(prof_btns)

	var del_btn := _build_footer_btn("", Color(0.16, 0.09, 0.10), C_ACCENT_RD)
	del_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	del_btn.custom_minimum_size = Vector2(240, 46)
	del_btn.add_theme_color_override("font_color",       Color(1.0, 0.6, 0.58))
	del_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.72, 0.70))
	_set_icon_btn_text(del_btn, Icons.TRASH, "Spielstand löschen")
	del_btn.pressed.connect(_show_delete_modal)
	prof_btns.add_child(del_btn)

	var credits_btn := _build_footer_btn("", C_SURFACE, C_ACCENT_MU)
	credits_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	credits_btn.custom_minimum_size = Vector2(200, 46)
	_set_icon_btn_text(credits_btn, Icons.SPARKLES, "Credits")
	credits_btn.pressed.connect(_show_credits_modal)
	prof_btns.add_child(credits_btn)

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

	_add_spacer(v1, 8)
	_add_hline(v1)
	_add_section_label(v1, "HINTERGRUND")
	_music_min_switch = _add_toggle_row(v1, "Musik bei Minimierung:")
	_music_min_switch.toggled.connect(_on_music_min_toggled)
	_add_setting_hint(v1, "Spielt die Musik weiter, wenn das Fenster minimiert oder im Hintergrund ist.")

	# Kategorie 2 – Anzeige (Modus + Auflösung + Cheat-Modus)
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

	var res_row := _make_hrow(v2)
	_make_row_label(res_row, "Bildschirmauflösung:")
	_res_option = OptionButton.new()
	_res_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_btn(_res_option)
	for res in RESOLUTIONS:
		_res_option.add_item(res[0])
	_res_option.item_selected.connect(_on_resolution_changed)
	res_row.add_child(_res_option)

	_add_hline(v2)
	_add_section_label(v2, "DARSTELLUNG")

	_fps_switch = _add_toggle_row(v2, "FPS anzeigen:")
	_fps_switch.toggled.connect(_on_fps_toggled)

	_darkmode_switch = _add_toggle_row(v2, "Dark Mode:")
	_darkmode_switch.toggled.connect(_on_darkmode_toggled)

	_colorblind_switch = _add_toggle_row(v2, "Farbenblind-Modus:")
	_colorblind_switch.toggled.connect(_on_colorblind_toggled)
	_add_setting_hint(v2, "Passt die Farben für eine Rot-Grün-Sehschwäche an.")

	var mult_row := _make_hrow(v2)
	_make_row_label(mult_row, "Multiplikatoren zeigen:")
	_mult_option = OptionButton.new()
	_mult_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_btn(_mult_option)
	for opt in MULT_DISPLAY_OPTIONS:
		_mult_option.add_item(opt)
	_mult_option.item_selected.connect(_on_mult_display_changed)
	mult_row.add_child(_mult_option)
	_add_setting_hint(v2, "Steuert die ×-Werte auf den Baufeldern (z. B. ×5).")

	_add_hline(v2)
	_add_section_label(v2, "CHEAT-MODUS")
	var cheat_row := _make_hrow(v2)
	_make_row_label(cheat_row, "Cheat-Modus:")
	_cheat_switch = _make_placement_switch()
	_cheat_switch.toggled.connect(_on_cheat_toggled)
	cheat_row.add_child(_cheat_switch)
	var cheat_hint := Label.new()
	cheat_hint.text = "Zeigt den Endlos-Modus (%s) und den +1B %s Button in der oberen Leiste an." % [Icons.INFINITY, Icons.STAR]
	cheat_hint.add_theme_font_size_override("font_size", 11)
	cheat_hint.add_theme_color_override("font_color", C_TEXT_DIM)
	cheat_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v2.add_child(cheat_hint)

	# Kategorie 3 – Steuerung
	var v3 := _new_settings_cat(holder)
	_build_steuerung_cat(v3)

	_show_settings_cat(0)

	# Fußzeile: nur „Zurück" (Auto-Speichern beim Verlassen – kein Speichern-Button).
	var bot_line := ColorRect.new()
	bot_line.custom_minimum_size = Vector2(0, 1)
	bot_line.color = C_LINE
	outer_vbox.add_child(bot_line)

	# Kleiner „Zurück"-Button unten links in der Ecke (Auto-Speichern beim Verlassen).
	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size = Vector2(0, 60)
	btn_row.add_theme_constant_override("separation", 0)
	outer_vbox.add_child(btn_row)
	var bpad := Control.new(); bpad.custom_minimum_size = Vector2(24, 0)
	btn_row.add_child(bpad)
	var back_btn := _build_footer_btn("←  Zurück", C_SURFACE, C_ACCENT_MU)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_btn.custom_minimum_size = Vector2(128, 42)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.pressed.connect(_on_options_back)
	btn_row.add_child(back_btn)

	return overlay


func _build_footer_btn(txt: String, bg: Color, border: Color) -> Button:
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


# ── Settings Top-Nav ──────────────────────────────────────────────────────────

func _add_settings_nav(parent: HBoxContainer, idx: int, icon: String, label: String) -> void:
	var btn := Button.new()
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.set_meta("nav_icon", icon)
	btn.set_meta("nav_label", label)
	btn.text = "%s  %s" % [icon, tr(label)]
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_settings_nav(btn, idx == 0)
	btn.pressed.connect(_on_settings_nav.bind(idx))
	parent.add_child(btn)
	_settings_nav_btns.append(btn)


# Icon-Präfix-Button (z.B. „🗑  Spielstand löschen"): Text selbst übersetzen, da auto_translate
# den zusammengesetzten String (Glyph + Text) nicht als Übersetzungsschlüssel findet.
func _set_icon_btn_text(btn: Button, icon: String, label_key: String, suffix := false) -> void:
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.set_meta("btn_icon", icon)
	btn.set_meta("btn_label", label_key)
	btn.set_meta("btn_suffix", suffix)   # true = Icon rechts vom Text
	btn.text = _icon_btn_text(icon, label_key, suffix)
	if not _icon_text_btns.has(btn):
		_icon_text_btns.append(btn)


func _icon_btn_text(icon: String, label_key: String, suffix: bool) -> String:
	return ("%s  %s" % [tr(label_key), icon]) if suffix else ("%s  %s" % [icon, tr(label_key)])


# Beim Sprachwechsel die selbst übersetzten Texte (Kategorie-Tabs, Icon-Buttons, Profile) neu beschriften.
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED:
		return
	for btn in _settings_nav_btns:
		if is_instance_valid(btn) and btn.has_meta("nav_label"):
			btn.text = "%s  %s" % [btn.get_meta("nav_icon"), tr(btn.get_meta("nav_label"))]
	for btn in _icon_text_btns:
		if is_instance_valid(btn) and btn.has_meta("btn_label"):
			btn.text = _icon_btn_text(btn.get_meta("btn_icon"), btn.get_meta("btn_label"), bool(btn.get_meta("btn_suffix")))
	_refresh_profiles()


func _style_settings_nav(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color            = C_SURFACE2 if active else Color(0, 0, 0, 0)
	sb.border_width_bottom = 3
	sb.border_color        = C_ACCENT if active else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top  = 6;  sb.content_margin_bottom = 6
	if active:
		sb.shadow_color  = Color(0, 0, 0, 0.4)
		sb.shadow_size   = 3
		sb.shadow_offset = Vector2(0, 2)
	var sb_h := sb.duplicate() as StyleBoxFlat
	if not active:
		sb_h.bg_color = C_SURFACE
	for state in ["normal", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_constant_override("outline_size", 1)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))


func _on_settings_nav(idx: int) -> void:
	for i in _settings_nav_btns.size():
		_style_settings_nav(_settings_nav_btns[i], i == idx)
	_show_settings_cat(idx)


func _show_settings_cat(idx: int) -> void:
	for i in _settings_cat_panels.size():
		_settings_cat_panels[i].visible = (i == idx)


func _new_settings_cat(holder: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.visible = false
	holder.add_child(scroll)
	_settings_cat_panels.append(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	return vbox


# ── Steuerung-Kategorie ───────────────────────────────────────────────────────

func _build_steuerung_cat(parent: VBoxContainer) -> void:
	_add_section_label(parent, "STEUERUNGSART")

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

	_ctrl_desc_lbl = Label.new()
	_ctrl_desc_lbl.add_theme_font_size_override("font_size", 11)
	_ctrl_desc_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	_ctrl_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(_ctrl_desc_lbl)

	_mobile_settings_box = VBoxContainer.new()
	_mobile_settings_box.add_theme_constant_override("separation", 14)
	parent.add_child(_mobile_settings_box)
	_add_hline(_mobile_settings_box)
	_add_section_label(_mobile_settings_box, "MOBILE-EINSTELLUNGEN")
	var rotate_row := _make_hrow(_mobile_settings_box)
	_ctrl_rotate_label = _make_row_label(rotate_row, "Drehen-Knopf:")
	_rotate_switch = _make_placement_switch()
	_rotate_switch.toggled.connect(_on_rotate_btn_toggled)
	rotate_row.add_child(_rotate_switch)
	_ctrl_mobile_hint = Label.new()
	_ctrl_mobile_hint.text = "Zeigt im 2D-Bauplan einen ↻-Knopf zum Drehen. Im Mobile-Modus standardmäßig an, in den anderen Modi deaktiviert."
	_ctrl_mobile_hint.add_theme_font_size_override("font_size", 11)
	_ctrl_mobile_hint.add_theme_color_override("font_color", C_TEXT_DIM)
	_ctrl_mobile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_mobile_settings_box.add_child(_ctrl_mobile_hint)

	_apply_ctrl_mode(0, false)


func _on_ctrl_mode_selected(idx: int) -> void:
	_apply_ctrl_mode(idx, true)


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

	# GameHUD ist im Menü ausgeblendet; der Aufruf ist gefahrlos (toggelt nur den Pause-Eintrag).
	GameHUD.set_mobile_mode(is_mobile)
	settings.set_value("options", "control_mode", mode_id)
	var pm := "quick" if mode_id == "click" else "slow"
	settings.set_value("options", "placement_mode", pm)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("set_placement_mode"):
		scene.set_placement_mode(pm)

	if is_mobile and not settings.has_section_key("options", "rotate_button"):
		settings.set_value("options", "rotate_button", true)
	var rot := is_mobile and bool(settings.get_value("options", "rotate_button", true))
	_loading_settings = true
	_rotate_switch.button_pressed = rot
	_loading_settings = false
	_rotate_switch.text = "An" if rot else "Aus"
	_settings_dirty = true


func _set_mobile_settings_enabled(enabled: bool) -> void:
	if _mobile_settings_box != null:
		_mobile_settings_box.visible = enabled


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


# ── Bildschirmauflösung ───────────────────────────────────────────────────────

func _on_resolution_changed(index: int) -> void:
	if _loading_settings: return
	var size: Vector2i = RESOLUTIONS[index][1]
	settings.set_value("options", "resolution", size)
	_apply_resolution(size)
	_settings_dirty = true


func _apply_resolution(size: Vector2i) -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return
	DisplayServer.window_set_size(size)
	var screen_id := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen_id)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


# ── Panel-Wechsel ─────────────────────────────────────────────────────────────

func _hide_all() -> void:
	_main_panel.visible    = false
	_options_panel.visible = false
	_rename_modal.visible  = false
	_delete_modal.visible  = false
	_credits_modal.visible = false
	_bug_modal.visible     = false


func _show_main() -> void:
	_hide_all()
	_main_panel.visible = true


func _show_options() -> void:
	_hide_all()
	_options_panel.visible = true
	_settings_dirty = false
	_sync_settings_ui()
	_on_settings_nav(0)


# Optionen verlassen → automatisch speichern.
func _on_options_back() -> void:
	if _settings_dirty:
		settings.save(Paths.SETTINGS_FILE)
		_settings_dirty = false
	_show_main()


# ── Einstellungen Sync ────────────────────────────────────────────────────────

func _sync_settings_ui() -> void:
	_loading_settings = true

	var lang := settings.get_value("options", "language", "en") as String
	for i in LANGUAGES.size():
		if LANGUAGES[i][1] == lang:
			_lang_option.selected = i
			break

	_master_slider.value    = settings.get_value("options", "master_volume", 100.0)
	_music_slider.value     = settings.get_value("options", "music_volume",  80.0)
	_sfx_slider.value       = settings.get_value("options", "sfx_volume",    100.0)
	_lbl_master_val.text    = "%d%%" % int(_master_slider.value)
	_lbl_music_val.text     = "%d%%" % int(_music_slider.value)
	_lbl_sfx_val.text       = "%d%%" % int(_sfx_slider.value)
	_window_option.selected = settings.get_value("options", "window_mode",   0)

	var res: Vector2i = settings.get_value("options", "resolution", DEFAULT_RESOLUTION)
	for i in RESOLUTIONS.size():
		if RESOLUTIONS[i][1] == res:
			_res_option.selected = i
			break

	var mode := String(settings.get_value("options", "control_mode", _infer_default_ctrl_mode()))
	var midx := CTRL_MODE_IDS.find(mode)
	if midx < 0:
		midx = 0
	_apply_ctrl_mode(midx, false)
	var is_mobile: bool = String(CTRL_MODE_IDS[midx]) == "mobile"
	var rotbtn: bool = is_mobile and bool(settings.get_value("options", "rotate_button", true))
	_rotate_switch.button_pressed = rotbtn
	_rotate_switch.text = "An" if rotbtn else "Aus"

	var cheat := bool(settings.get_value("cheats", "enabled", false))
	_cheat_switch.button_pressed = cheat
	_cheat_switch.text = "An" if cheat else "Aus"

	_music_min_switch.button_pressed  = bool(settings.get_value("options", "music_on_minimize", true))
	_fps_switch.button_pressed        = bool(settings.get_value("options", "show_fps", false))
	_darkmode_switch.button_pressed   = bool(settings.get_value("options", "dark_mode", false))
	_colorblind_switch.button_pressed = bool(settings.get_value("options", "colorblind", false))
	_mult_option.selected             = clampi(int(settings.get_value("options", "show_multiplier", Display.MultiplierMode.AFFECTED)), 0, 2)

	_loading_settings = false


func _infer_default_ctrl_mode() -> String:
	var pm := String(settings.get_value("options", "placement_mode", "slow"))
	return "click" if pm == "quick" else "drag"


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


func _on_rotate_btn_toggled(pressed: bool) -> void:
	_rotate_switch.text = "An" if pressed else "Aus"
	if _loading_settings: return
	settings.set_value("options", "rotate_button", pressed)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("set_rotate_button_visible"):
		scene.set_rotate_button_visible(pressed)
	_settings_dirty = true


func _on_cheat_toggled(pressed: bool) -> void:
	_cheat_switch.text = "An" if pressed else "Aus"
	if _loading_settings: return
	settings.set_value("cheats", "enabled", pressed)
	Economy.apply_cheat_mode(pressed)
	_settings_dirty = true


func _on_music_min_toggled(pressed: bool) -> void:
	if _loading_settings: return
	settings.set_value("options", "music_on_minimize", pressed)
	MusicPlayer.set_music_on_minimize(pressed)
	_settings_dirty = true


func _on_fps_toggled(pressed: bool) -> void:
	if _loading_settings: return
	settings.set_value("options", "show_fps", pressed)
	Display.set_fps_visible(pressed)
	_settings_dirty = true


func _on_darkmode_toggled(pressed: bool) -> void:
	if _loading_settings: return
	settings.set_value("options", "dark_mode", pressed)
	Display.set_dark_mode(pressed)
	_settings_dirty = true


func _on_colorblind_toggled(pressed: bool) -> void:
	if _loading_settings: return
	settings.set_value("options", "colorblind", pressed)
	Display.set_colorblind(pressed)
	_settings_dirty = true


func _on_mult_display_changed(index: int) -> void:
	if _loading_settings: return
	settings.set_value("options", "show_multiplier", index)
	Display.set_multiplier_mode(index)
	_settings_dirty = true


# ── Einstellungen anwenden ────────────────────────────────────────────────────

func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, _vol_db(settings.get_value("options", "master_volume", 100.0)))
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, _vol_db(settings.get_value("options", "music_volume", 80.0)))
	var si := AudioServer.get_bus_index("SFX")
	if si >= 0:
		AudioServer.set_bus_volume_db(si, _vol_db(settings.get_value("options", "sfx_volume", 100.0)))
	_apply_window_mode(settings.get_value("options", "window_mode", 0))
	_apply_resolution(settings.get_value("options", "resolution", DEFAULT_RESOLUTION))
	TranslationServer.set_locale(settings.get_value("options", "language", "en"))


func _apply_window_mode(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			_apply_resolution(settings.get_value("options", "resolution", DEFAULT_RESOLUTION))
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			_apply_resolution(settings.get_value("options", "resolution", DEFAULT_RESOLUTION))
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _vol_db(percent: float) -> float:
	if percent <= 0.0: return -80.0
	return linear_to_db(percent / 100.0)


# ── UI-Hilfsfunktionen ────────────────────────────────────────────────────────

func _make_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.visible = false
	add_child(overlay)
	return overlay


# Numerierter Listen-Button (für Modal-Aktionen wie Speichern/Abbrechen).
func _add_menu_button(parent: VBoxContainer, num: String, label: String,
		accent: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(360, 52)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",   _btn_style(C_SURFACE,                 accent.darkened(0.4)))
	btn.add_theme_stylebox_override("hover",    _btn_style(C_SURFACE.lightened(0.05), accent))
	btn.add_theme_stylebox_override("pressed",  _btn_style(C_SURFACE2,                accent))
	btn.add_theme_stylebox_override("focus",    _btn_style(C_SURFACE,                 accent.darkened(0.4)))

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
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.clip_text = true
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
	slider.size_flags_vertical   = Control.SIZE_SHRINK_CENTER

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


# Beschriftete Zeile mit einem niedlichen, abgerundeten 3D-Toggle rechts.
func _add_toggle_row(parent: VBoxContainer, label_text: String) -> CuteToggle:
	var row := _make_hrow(parent)
	_make_row_label(row, label_text)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var sw := CuteToggle.new()
	row.add_child(sw)
	return sw


# Kleiner, gedämpfter Hinweistext unter einer Einstellung.
func _add_setting_hint(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(lbl)


func _add_panel_title(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", C_ACCENT)
	_emboss(lbl)
	parent.add_child(lbl)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", C_TEXT)
	_emboss(lbl)
	parent.add_child(lbl)


# Geprägter 3D-Look für Überschriften: dunkler Schlagschatten nach unten-rechts.
func _emboss(lbl: Label, strength: float = 0.55) -> void:
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, strength))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 2)


func _add_hline(parent: Node) -> void:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = C_LINE
	parent.add_child(line)


func _add_spacer(parent: BoxContainer, height: int) -> void:
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


func _make_placement_switch() -> CheckButton:
	var sw := CheckButton.new()
	sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sw.focus_mode = Control.FOCUS_NONE
	sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sw.add_theme_color_override("font_color",         C_TEXT)
	sw.add_theme_color_override("font_hover_color",   C_TEXT)
	sw.add_theme_color_override("font_pressed_color", C_TEXT)
	sw.add_theme_font_size_override("font_size", 13)
	sw.add_theme_color_override("icon_normal_color",  Color(0.78, 0.82, 0.92))
	sw.add_theme_color_override("icon_hover_color",   Color(0.95, 0.97, 1.00))
	sw.add_theme_color_override("icon_pressed_color", C_ACCENT)
	sw.add_theme_color_override("icon_focus_color",   Color(0.78, 0.82, 0.92))
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
