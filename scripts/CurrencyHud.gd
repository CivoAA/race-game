extends CanvasLayer
class_name CurrencyHud

const VIEWPORT_WIDTH = 960

var _label: Label = null
var _last_shown: int = -2147483648
var _flash_tween: Tween = null


func _ready() -> void:
	layer = 10

	# Dunkler Streifen über dem Grid-Bereich (links/rechts durch Panel-Bgs abgedeckt)
	var bg := ColorRect.new()
	bg.position = Vector2(144, 0)
	bg.size     = Vector2(608, 38)
	bg.color    = Color(0, 0, 0, 0.40)
	add_child(bg)

	_label = Label.new()
	_label.position = Vector2(144, 4)
	_label.size = Vector2(608, 30)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
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
	_label.text = "💰  %d" % c


func flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_label, "modulate", Color(1, 0.2, 0.2), 0.1)
	_flash_tween.tween_property(_label, "modulate", Color(1, 1, 1), 0.35)
