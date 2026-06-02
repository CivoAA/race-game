extends CanvasLayer

const C_BG       := Color(0.09, 0.10, 0.14)
const C_BORDER   := Color(0.20, 0.23, 0.32)
const C_ACCENT   := Color(1.00, 0.45, 0.08)
const C_BLUE     := Color(0.22, 0.27, 0.42)
const C_SURFACE  := Color(0.13, 0.15, 0.21)
const C_SURFACE2 := Color(0.09, 0.10, 0.14)
const C_TEXT     := Color(0.82, 0.85, 0.90)
const C_TEXT_DIM := Color(0.32, 0.37, 0.50)

@onready var main: Node2D          = get_parent()
@onready var label_selected: Label = $Panel/VBox/LabelSelected
@onready var label_hint: Label     = $Panel/VBox/LabelHint


func _ready() -> void:
	$Panel/VBox/BtnFahren.pressed.connect(main._on_fahren_pressed)
	$Panel/VBox/BtnPruefen.pressed.connect(main._on_pruefen_pressed)
	$Panel/VBox/BtnUpgrades.pressed.connect(main._on_upgrades_pressed)
	_apply_styles()


func _apply_styles() -> void:
	var panel := $Panel as Panel
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_BG
	ps.border_width_right = 1
	ps.border_color = C_BORDER
	panel.add_theme_stylebox_override("panel", ps)

	var track_lbl := $Panel/VBox/Label as Label
	track_lbl.add_theme_font_size_override("font_size", 11)
	track_lbl.add_theme_color_override("font_color", C_ACCENT)
	track_lbl.add_theme_constant_override("outline_size", 0)

	label_selected.add_theme_font_size_override("font_size", 11)
	label_selected.add_theme_color_override("font_color", C_TEXT)

	label_hint.add_theme_font_size_override("font_size", 10)
	label_hint.add_theme_color_override("font_color", C_TEXT_DIM)

	_style_btn($Panel/VBox/BtnUpgrades, C_BLUE)
	_style_btn($Panel/VBox/BtnPruefen,  C_BLUE)
	_style_btn_go($Panel/VBox/BtnFahren)


func _style_btn(btn: Button, accent: Color) -> void:
	btn.add_theme_stylebox_override("normal",   _sb(C_SURFACE,                 accent.darkened(0.5)))
	btn.add_theme_stylebox_override("hover",    _sb(C_SURFACE.lightened(0.07), accent))
	btn.add_theme_stylebox_override("pressed",  _sb(C_SURFACE2,                accent))
	btn.add_theme_stylebox_override("focus",    _sb(C_SURFACE,                 accent.darkened(0.5)))
	btn.add_theme_stylebox_override("disabled", _sb(C_SURFACE2,                accent.darkened(0.7)))
	btn.add_theme_color_override("font_color",          C_TEXT)
	btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 12)


func _style_btn_go(btn: Button) -> void:
	var go_n := Color(0.09, 0.30, 0.16)
	var go_h := Color(0.12, 0.42, 0.22)
	var go_a := Color(0.30, 0.95, 0.50)
	btn.add_theme_stylebox_override("normal",   _sb(go_n,       go_a.darkened(0.45)))
	btn.add_theme_stylebox_override("hover",    _sb(go_h,       go_a))
	btn.add_theme_stylebox_override("pressed",  _sb(C_SURFACE2, go_a))
	btn.add_theme_stylebox_override("focus",    _sb(go_n,       go_a.darkened(0.45)))
	btn.add_theme_stylebox_override("disabled", _sb(C_SURFACE2, Color(0.25, 0.40, 0.28)))
	btn.add_theme_color_override("font_color",          Color(0.60, 1.00, 0.72))
	btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 13)


func _sb(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 3
	sb.border_color = border
	sb.set_corner_radius_all(3)
	sb.content_margin_top    = 9
	sb.content_margin_bottom = 9
	sb.content_margin_left   = 6
	sb.content_margin_right  = 6
	return sb


func deselect() -> void:
	label_selected.text = ""


func set_status(text: String) -> void:
	label_selected.text = text


func set_fahren_enabled(enabled: bool) -> void:
	$Panel/VBox/BtnFahren.disabled = not enabled
