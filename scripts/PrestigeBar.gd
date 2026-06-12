extends Control
class_name PrestigeBar
## Dünner Prestige-Fortschrittsbalken für die untere Leiste (Geld / Economy.PRESTIGE_K).
## Besteht aus einem dezenten Track + einer Füllung mit DEMSELBEN Shader wie der große
## Prestige-Button im Upgrade-Center (GlobalModal.PRESTIGE_FILL_SHADER) – nur viel dünner.
## Aktualisiert sich selbst pro Frame; Größe folgt den Ankern (dynamisch). Performance-Modus
## → einfarbig (Modus 0) statt animiert (Modus 5 = Glitzer+Wasser), wie der große Balken.

const C_STAR := Color(0.74, 0.48, 0.97)   # Prestige-Lila (Sternfarbe, gespiegelt aus GlobalModal)

# Feste Maximalbreite (kurz, mittig) und seitliche Reserve. Der Balken zentriert sich SELBST
# horizontal: Breite = clamp(Viewport - 2·side_reserve, min, max_width). Wird side_reserve in 2D
# und 3D identisch gesetzt, sitzt der Balken in beiden Ansichten exakt gleich (kein Springen).
# Vertikale Lage/Höhe setzt der Host über anchor_top/bottom + offset_top/bottom (beide an 1.0).
@export var max_width: float    = 200.0
@export var side_reserve: float = 244.0

var _track_sb: StyleBoxFlat  = null
var _fill_mat: ShaderMaterial = null
var _hover_lbl: Label        = null   # erscheint beim Hovern in Lila UNTER der Bar


func _ready() -> void:
	# PASS statt IGNORE: die Bar empfängt Hover (zum Ein-/Ausblenden der Lila-Anzeige darunter),
	# reicht Klicks aber weiter an die untere Leiste durch. Die Kinder bleiben IGNORE, damit die
	# Bar selbst das gehoverte Control ist.
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Track: dezenter dunkler Hintergrund in Pillenform, damit die Balken-Ausdehnung auch
	# bei wenig Fortschritt erkennbar ist (wie der Button-Rahmen im Prestige-Tab).
	var track := Panel.new()
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track_sb = StyleBoxFlat.new()
	_track_sb.bg_color     = Color(0.0, 0.0, 0.0, 0.32)
	_track_sb.border_color = Color(C_STAR.r, C_STAR.g, C_STAR.b, 0.22)
	_track_sb.set_border_width_all(1)
	track.add_theme_stylebox_override("panel", _track_sb)
	add_child(track)

	# Füllung: ColorRect mit dem geteilten Prestige-Shader (Form + Reveal + Effekt).
	var fill := ColorRect.new()
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = GlobalModal.PRESTIGE_FILL_SHADER
	_fill_mat = ShaderMaterial.new()
	_fill_mat.shader = sh
	fill.material = _fill_mat
	add_child(fill)

	# Lila-Anzeige UNTER der Bar, nur beim Hovern sichtbar. Zentriert auf die Bar-Mitte, knapp
	# darunter (eigene Anker → unabhängig von der dynamischen Bar-Breite). Text kommt aus _apply().
	_hover_lbl = Label.new()
	_hover_lbl.visible = false
	_hover_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_hover_lbl.add_theme_font_size_override("font_size", 11)
	_hover_lbl.add_theme_color_override("font_color", C_STAR)
	_hover_lbl.add_theme_constant_override("outline_size", 3)
	_hover_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hover_lbl.anchor_left  = 0.5; _hover_lbl.offset_left  = -100
	_hover_lbl.anchor_right = 0.5; _hover_lbl.offset_right =  100
	_hover_lbl.anchor_top    = 1.0; _hover_lbl.offset_top    = 1
	_hover_lbl.anchor_bottom = 1.0; _hover_lbl.offset_bottom = 15
	add_child(_hover_lbl)
	mouse_entered.connect(func(): _hover_lbl.visible = true)
	mouse_exited.connect(func():  _hover_lbl.visible = false)

	_apply()


func _process(_dt: float) -> void:
	_apply()


# Horizontale Geometrie selbst setzen (zentriert, kurze Maximalbreite, bei schmalem Viewport
# geklemmt) + Pillen-Rundung + Shader-Parameter an Größe/Zustand anpassen.
func _apply() -> void:
	if _fill_mat == null:
		return

	# Zentriert mit fester Maximalbreite; auf schmalen Screens schrumpfen, damit die Seiten-Knöpfe
	# frei bleiben. side_reserve identisch in 2D/3D → gleiche Lage in beiden Ansichten.
	var avail: float = get_parent_area_size().x
	var w: float = clampf(avail - 2.0 * side_reserve, 40.0, max_width)
	anchor_left  = 0.5
	anchor_right = 0.5
	offset_left  = -w * 0.5
	offset_right =  w * 0.5

	var h: float = size.y
	if _track_sb != null:
		_track_sb.set_corner_radius_all(int(round(h * 0.5)))

	var target: float = Economy.PRESTIGE_K
	var progress: float = clampf(float(Economy.get_currency()) / target, 0.0, 1.0)
	if _hover_lbl != null:
		_hover_lbl.text = "Prestige Fortschritt %d%%" % int(round(progress * 100.0))
	_fill_mat.set_shader_parameter("progress", progress)
	_fill_mat.set_shader_parameter("size_px", Vector2(w, h))
	_fill_mat.set_shader_parameter("radius_px", h * 0.5)   # volle Pillen-Rundung an den Enden
	_fill_mat.set_shader_parameter("mode", 0 if Display.performance_mode else 5)
	var a: float = 0.92 if Economy.can_prestige() else 0.6
	_fill_mat.set_shader_parameter("base_color", Color(C_STAR.r, C_STAR.g, C_STAR.b, a))
