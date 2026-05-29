extends CanvasLayer

# Referenz auf Main, damit wir set_selected_tile() aufrufen können
@onready var main: Node2D = get_parent()

# Button → Tile-Typ Mapping
const BUTTON_MAP = {
	"BtnStraightH": "straight_h",
	"BtnStraightV": "straight_v",
	"BtnCurveNE":   "curve_ne",
	"BtnCurveNW":   "curve_nw",
	"BtnCurveSE":   "curve_se",
	"BtnCurveSW":   "curve_sw",
	"BtnDelete":    "delete",
}

const LABEL_MAP = {
	"straight_h": "Gerade\nHorizontal",
	"straight_v": "Gerade\nVertikal",
	"curve_ne":   "Kurve\nNord-Ost",
	"curve_nw":   "Kurve\nNord-West",
	"curve_se":   "Kurve\nSüd-Ost",
	"curve_sw":   "Kurve\nSüd-West",
	"delete":     "Löschen\n(Rechtsklick\nauch möglich)",
}

@onready var label_selected: Label = $Panel/VBox/LabelSelected


func _ready() -> void:
	_connect_buttons()


func _connect_buttons() -> void:
	for btn_name in BUTTON_MAP.keys():
		var btn = get_node_or_null("Panel/VBox/" + btn_name)
		if btn:
			btn.pressed.connect(_on_tile_button_pressed.bind(BUTTON_MAP[btn_name]))
		else:
			push_warning("TileSelector: Button '%s' nicht gefunden." % btn_name)


func _on_tile_button_pressed(tile_type: String) -> void:
	main.set_selected_tile(tile_type)
	label_selected.text = "Ausgewählt:\n" + LABEL_MAP.get(tile_type, tile_type)
	print("Tile-Typ gewählt: %s" % tile_type)
