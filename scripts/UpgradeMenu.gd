extends CanvasLayer
class_name UpgradeMenu
## Upgrade-Overlay für die 2D-View. Kategorie-Tabs links (Allgemeines, Auto N),
## Upgrade-Zeilen rechts, Reset-Button. Liest/schreibt alles über das Economy-Autoload.

signal closed

# Kategorien (Reihenfolge = Tab-Reihenfolge). Pro-Auto-Tabs sind aktuell entfernt;
# Tempo/End-Mult/Tile-Bonus liegen global unter "Allgemeines". Streckengröße: später per Prestige.
const GENERAL_CATEGORIES = [
	{"name": "Allgemeines", "ids": ["speed", "drive_time", "endmult", "tilebonus", "car_count"]},
	{"name": "Bonusfelder", "ids": ["bonus_plus5", "bonus_plus10", "bonus_mult15"]},
]
const VIEW_W = 960
const VIEW_H = 540

var _current_cat:  int           = 0   # 0 = Allgemeines, 1..n = Auto i
var _cat_box:      VBoxContainer = null
var _content_box:  VBoxContainer = null


func _ready() -> void:
	layer = 12
	_build_static()
	_rebuild()


func _build_static() -> void:
	# Abdunkelnder Hintergrund (blockiert Klicks dahinter im GUI-Layer)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size  = Vector2(VIEW_W, VIEW_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel = Panel.new()
	panel.position = Vector2(40, 20)
	panel.size     = Vector2(880, 500)
	var style = StyleBoxFlat.new()
	style.bg_color     = Color(0.13, 0.14, 0.17, 1.0)
	style.border_color = Color(0.5, 0.5, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var title = Label.new()
	title.text = "UPGRADES"
	title.position = Vector2(0, 10)
	title.size = Vector2(880, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	panel.add_child(title)

	_cat_box = VBoxContainer.new()
	_cat_box.position = Vector2(14, 54)
	_cat_box.custom_minimum_size = Vector2(160, 0)
	_cat_box.add_theme_constant_override("separation", 6)
	panel.add_child(_cat_box)

	_content_box = VBoxContainer.new()
	_content_box.position = Vector2(188, 54)
	_content_box.custom_minimum_size = Vector2(674, 0)
	_content_box.add_theme_constant_override("separation", 8)
	panel.add_child(_content_box)

	var close_btn = Button.new()
	close_btn.text = "Schließen"
	close_btn.position = Vector2(756, 452)
	close_btn.size = Vector2(110, 38)
	close_btn.pressed.connect(_on_close)
	panel.add_child(close_btn)

	var reset_btn = Button.new()
	reset_btn.text = "Fortschritt zurücksetzen"
	reset_btn.position = Vector2(14, 452)
	reset_btn.size = Vector2(240, 38)
	reset_btn.pressed.connect(_on_reset)
	panel.add_child(reset_btn)


# ── Aufbau / Aktualisierung ─────────────────────────────────────────────────────

func _category_count() -> int:
	return GENERAL_CATEGORIES.size()


func _ids_for_category(cat: int) -> Array:
	return GENERAL_CATEGORIES[cat]["ids"]


func _rebuild() -> void:
	_current_cat = clampi(_current_cat, 0, _category_count() - 1)
	_rebuild_categories()
	_rebuild_content()


func _rebuild_categories() -> void:
	for c in _cat_box.get_children():
		c.queue_free()

	for i in range(GENERAL_CATEGORIES.size()):
		_add_cat_button(GENERAL_CATEGORIES[i]["name"], i)


func _add_cat_button(text: String, cat: int) -> void:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(160, 36)
	btn.toggle_mode = true
	btn.button_pressed = (cat == _current_cat)
	btn.pressed.connect(func():
		_current_cat = cat
		_rebuild()
	)
	_cat_box.add_child(btn)


func _rebuild_content() -> void:
	for c in _content_box.get_children():
		c.queue_free()
	for id in _ids_for_category(_current_cat):
		_content_box.add_child(_build_row(id))


func _build_row(id: String) -> Control:
	var row = Control.new()
	row.custom_minimum_size = Vector2(674, 48)

	var bg = ColorRect.new()
	bg.color = Color(0.18, 0.19, 0.23)
	bg.size = Vector2(674, 46)
	bg.position = Vector2(0, 1)
	row.add_child(bg)

	var level = Economy.get_upgrade_level(id)
	var maxed = Economy.is_maxed(id)

	var name_lbl = Label.new()
	name_lbl.position = Vector2(10, 4)
	name_lbl.size = Vector2(210, 40)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.text = "%s\nLv %d/%d" % [Economy.get_upgrade_name(id), level, Economy.get_max_level(id)]
	row.add_child(name_lbl)

	var eff_lbl = Label.new()
	eff_lbl.position = Vector2(226, 4)
	eff_lbl.size = Vector2(200, 40)
	eff_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	eff_lbl.add_theme_font_size_override("font_size", 13)
	eff_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	if maxed:
		eff_lbl.text = Economy.effect_text(id, level)
	else:
		eff_lbl.text = "%s → %s" % [Economy.effect_text(id, level), Economy.effect_text(id, level + 1)]
	row.add_child(eff_lbl)

	var btn = Button.new()
	btn.position = Vector2(432, 4)
	btn.size = Vector2(234, 40)
	if maxed:
		btn.text = "MAX"
		btn.disabled = true
	else:
		btn.text = "%s 💰" % Economy.format_currency(Economy.get_upgrade_cost(id))
		btn.disabled = not Economy.can_buy(id)
		btn.pressed.connect(func(): _on_buy(id))
	row.add_child(btn)

	return row


# ── Aktionen ────────────────────────────────────────────────────────────────────

func _on_buy(id: String) -> void:
	if Economy.buy_upgrade(id):
		_rebuild()


func _on_reset() -> void:
	Economy.reset()
	_current_cat = 0
	_rebuild()


func _on_close() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()
