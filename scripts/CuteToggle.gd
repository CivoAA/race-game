class_name CuteToggle
extends Button
## Niedlicher, abgerundeter „Pillen"-Schalter mit 3D-Effekt (Schlagschatten +
## Glanzlicht) und sanft gleitendem Knopf. Wiederverwendbar in allen Menüs.
## Verhält sich wie ein normaler Toggle-Button (toggle_mode), nur eigens gezeichnet.
##
## Verwendung:
##   var sw := CuteToggle.new()
##   sw.button_pressed = true
##   sw.toggled.connect(_on_xy_toggled)
##   row.add_child(sw)

const TRACK_OFF  := Color(0.220, 0.227, 0.251)   # C_SURFACE2 (aus)
const TRACK_ON   := Color(0.255, 0.78, 0.45)      # freundliches Grün (an)
const BORDER_OFF := Color(0.247, 0.255, 0.278)    # C_LINE
const BORDER_ON  := Color(0.16, 0.52, 0.30)
const KNOB_COL   := Color(0.97, 0.98, 1.00)

var _knob_t: float = 0.0   # 0 = aus (Knopf links), 1 = an (Knopf rechts)
var _tw: Tween


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(56, 30)
	# Eigene Zeichnung – Standard-Styleboxen des Buttons entfernen.
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	toggled.connect(_on_toggled)


func _ready() -> void:
	_knob_t = 1.0 if button_pressed else 0.0
	queue_redraw()


func _on_toggled(on: bool) -> void:
	var target := 1.0 if on else 0.0
	if not is_inside_tree():
		_knob_t = target
		queue_redraw()
		return
	if _tw and _tw.is_running():
		_tw.kill()
	_tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_method(_set_knob_t, _knob_t, target, 0.18)


func _set_knob_t(v: float) -> void:
	_knob_t = v
	queue_redraw()


func _draw() -> void:
	var sz := size
	var h := sz.y
	var r := h * 0.5

	# ── Gleis (Pille) mit 3D-Schatten ──
	var track := StyleBoxFlat.new()
	track.bg_color     = TRACK_OFF.lerp(TRACK_ON, _knob_t)
	track.border_color = BORDER_OFF.lerp(BORDER_ON, _knob_t)
	track.set_border_width_all(1)
	track.set_corner_radius_all(int(r))
	track.shadow_color  = Color(0, 0, 0, 0.35)
	track.shadow_size   = 3
	track.shadow_offset = Vector2(0, 2)
	draw_style_box(track, Rect2(Vector2.ZERO, sz))

	# Dezenter dunkler Innenrand unten → vertieftes Gleis (3D).
	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0, 0, 0, 0.0)
	inner.set_corner_radius_all(int(r))
	inner.set_border_width_all(0)
	inner.border_width_bottom = 2
	inner.border_color = Color(0, 0, 0, 0.18)
	draw_style_box(inner, Rect2(Vector2.ZERO, sz))

	# ── Knopf mit Schlagschatten + Glanzlicht (3D) ──
	var pad := 3.0
	var knob_r := r - pad
	var cx: float = lerp(r, sz.x - r, _knob_t)
	var cy := r
	draw_circle(Vector2(cx, cy + 1.5), knob_r, Color(0, 0, 0, 0.30))     # Schatten
	draw_circle(Vector2(cx, cy), knob_r, KNOB_COL)                       # Knopf
	draw_circle(Vector2(cx, cy), knob_r, Color(0, 0, 0, 0.10), false, 1.0)  # feiner Rand
	draw_circle(Vector2(cx - knob_r * 0.28, cy - knob_r * 0.30), knob_r * 0.42, Color(1, 1, 1, 0.55))  # Glanz
