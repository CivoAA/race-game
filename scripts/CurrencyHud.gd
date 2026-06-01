extends CanvasLayer
class_name CurrencyHud
## Gemeinsame Währungsanzeige, oben mittig – in 2D- und 3D-View identisch.
## Einfach als Kind-Node in eine Szene hängen (oder per Code instanziieren).

const VIEWPORT_WIDTH = 800

var _label: Label = null
var _last_shown: int = -2147483648
var _flash_tween: Tween = null


func _ready() -> void:
	layer = 10
	_label = Label.new()
	_label.position = Vector2(0, 6)
	_label.size = Vector2(VIEWPORT_WIDTH, 34)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_label.add_theme_constant_override("outline_size", 5)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(_label)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var c = Economy.get_currency()
	if c == _last_shown:
		return
	_last_shown = c
	_label.text = "💰 %d" % c


# Rot aufblinken (z. B. bei zu wenig Währung).
func flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_label, "modulate", Color(1, 0.2, 0.2), 0.1)
	_flash_tween.tween_property(_label, "modulate", Color(1, 1, 1), 0.35)
