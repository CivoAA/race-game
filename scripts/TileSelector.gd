extends CanvasLayer

@onready var main: Node2D     = get_parent()
@onready var label_selected: Label = $Panel/VBox/LabelSelected
@onready var label_hint: Label     = $Panel/VBox/LabelHint


func _ready() -> void:
	$Panel/VBox/BtnFahren.pressed.connect(main._on_fahren_pressed)
	$Panel/VBox/BtnPruefen.pressed.connect(main._on_pruefen_pressed)
	$Panel/VBox/BtnUpgrades.pressed.connect(main._on_upgrades_pressed)


func deselect() -> void:
	label_selected.text = ""


func set_status(text: String) -> void:
	label_selected.text = text


func set_fahren_enabled(enabled: bool) -> void:
	$Panel/VBox/BtnFahren.disabled = not enabled
