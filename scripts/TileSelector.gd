extends CanvasLayer

@onready var main: Node2D = get_parent()
@onready var label_selected: Label = $Panel/VBox/LabelSelected
@onready var label_hint: Label     = $Panel/VBox/LabelHint


func _ready() -> void:
	$Panel/VBox/BtnStraight.pressed.connect(func():  _select("straight"))
	$Panel/VBox/BtnCurve.pressed.connect(func():     _select("curve"))
	$Panel/VBox/BtnCurveAlt.pressed.connect(func():  _select("curve_alt"))
	$Panel/VBox/BtnDelete.pressed.connect(func():    _select("delete"))
	$Panel/VBox/BtnFahren.pressed.connect(main._on_fahren_pressed)


func _select(type: String) -> void:
	main.set_selected_type(type)
	match type:
		"straight":  label_selected.text = "Gerade"
		"curve":     label_selected.text = "Kurve"
		"curve_alt": label_selected.text = "Kurve 2"
		"delete":    label_selected.text = "Löschen"
