extends CanvasLayer
class_name CurrencyHud

var _label: Label = null
var _last_shown: int = -2147483648
var _flash_tween: Tween = null
var _gain_tween: Tween = null


func _ready() -> void:
	layer = 10

	# Subtiler Streifen über voller Breite (in 2D kaum sichtbar, in 3D durch World3D-Bar überlagert)
	var bg := ColorRect.new()
	bg.anchor_left   = 0.0; bg.offset_left   = 0
	bg.anchor_top    = 0.0; bg.offset_top    = 0
	bg.anchor_right  = 1.0; bg.offset_right  = 0
	bg.anchor_bottom = 0.0; bg.offset_bottom = 46
	bg.color    = Color(0, 0, 0, 0.22)
	add_child(bg)

	_label = Label.new()
	_label.anchor_left   = 0.0; _label.offset_left   = 0
	_label.anchor_top    = 0.0; _label.offset_top    = 8
	_label.anchor_right  = 1.0; _label.offset_right  = 0
	_label.anchor_bottom = 0.0; _label.offset_bottom = 38
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.40, 0.85, 0.45))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.90))
	add_child(_label)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var c := Economy.get_currency()
	if c == _last_shown:
		return
	_last_shown = c
	_label.text = "%s  %s" % [Icons.COIN, Economy.format_currency(c)]


func flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_label, "modulate", Color(1, 0.2, 0.2), 0.1)
	_flash_tween.tween_property(_label, "modulate", Color(1, 1, 1), 0.35)


# Hübsches Feedback beim Geldgewinn: grüner Pop der Anzeige + aufsteigendes "+N".
func gain(amount: int) -> void:
	if amount <= 0:
		return

	# Grüner Pop des Haupt-Labels (Skalierung pivotiert in der Mitte)
	_label.pivot_offset = _label.size / 2.0
	if _gain_tween:
		_gain_tween.kill()
	_gain_tween = create_tween()
	_gain_tween.tween_property(_label, "scale", Vector2(1.28, 1.28), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_gain_tween.parallel().tween_property(_label, "modulate", Color(0.45, 1.0, 0.5), 0.12)
	_gain_tween.tween_property(_label, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_gain_tween.parallel().tween_property(_label, "modulate", Color(1, 1, 1), 0.28)

	# Aufsteigendes "+N 💰" das ausblendet
	var fl := Label.new()
	fl.text = "+%s %s" % [Economy.format_currency(amount), Icons.COIN]
	fl.position = Vector2(RUI.vw() / 2.0 - 60, 46)
	fl.size = Vector2(120, 28)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	fl.add_theme_font_size_override("font_size", 22)
	fl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	fl.add_theme_constant_override("outline_size", 4)
	fl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(fl)
	var t := create_tween()
	t.tween_property(fl, "position:y", -4.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(fl, "modulate:a", 0.0, 0.9)
	t.tween_callback(fl.queue_free)
