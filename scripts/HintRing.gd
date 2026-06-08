extends Control
class_name HintRing
## Kleiner Ladekreis neben dem Mauszeiger. Füllt sich, während man über einem Upgrade-Namen
## hovert; ist der Kreis voll, blendet das Upgrade-Menü den Hinweis ein. Rein visuell –
## fängt keine Mausklicks ab (mouse_filter = IGNORE).

# Füllgrad 0..1. Wird vom Upgrade-Menü pro Frame gesetzt (set_progress → queue_redraw).
var progress: float = 0.0

@export var radius:    float = 12.0   # Radius des Rings
@export var thickness: float = 3.0    # Strichstärke
# Versatz zum Cursor (0,0 = genau auf dem Mauszeiger).
@export var cursor_offset := Vector2.ZERO

const COL_SHADOW := Color(0.0, 0.0, 0.0, 0.45)   # dunkler Hintergrundkreis für Kontrast
const COL_TRACK  := Color(1.0, 1.0, 1.0, 0.30)   # heller voller Ring (Spur)
const COL_FILL   := Color(1.0, 0.85, 0.2, 0.98)  # gelber Fortschritts-Bogen


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_progress(p: float) -> void:
	var v := clampf(p, 0.0, 1.0)
	if is_equal_approx(v, progress):
		return
	progress = v
	queue_redraw()


func _draw() -> void:
	if progress <= 0.0:
		return
	var c := get_local_mouse_position() + cursor_offset
	# Kontrast-Schatten + volle Spur, darüber der wachsende Bogen (oben beginnend, im Uhrzeigersinn).
	draw_circle(c, radius + thickness, COL_SHADOW)
	draw_arc(c, radius, 0.0, TAU, 40, COL_TRACK, thickness, true)
	var start := -PI / 2.0
	draw_arc(c, radius, start, start + TAU * progress, 48, COL_FILL, thickness, true)
