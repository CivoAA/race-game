extends Control
## Studio-Splash vor dem Hauptmenü: zeigt das Logo (Titel ist im Bild enthalten) auf einem
## dunkelgrauen, leicht bläulichen Vollbild-Hintergrund, blendet sanft ein und überblendet
## flackerfrei ins Hauptmenü. Ein Klick / Tastendruck überspringt den Splash sofort.

const NEXT_SCENE := "res://scenes/MainMenu.tscn"
const BG_COLOR   := Color(0.086, 0.098, 0.129)   # dunkelgrau, leicht bläulich (#16191f)

const LOGO_HEIGHT := 300.0   # Ziel-Höhe des Logos (Seitenverhältnis bleibt erhalten)
const FADE_IN     := 0.5
const HOLD        := 4.0
const FADE_OUT    := 0.5
const SKIP_FADE   := 0.12   # schnelle Blende beim Wegdrücken (Klick/Taste)

const BOX_COLOR     := Color(0.18, 0.21, 0.26)   # dunkler Kasten hinter dem Logo (weißer Text lesbar, #2e353f)
const BOX_PADDING   := 40                          # Innenabstand Logo ↔ Kastenrand (px)
const BOX_RADIUS    := 24                          # Eckenradius des Kastens (px)

var _content: Control = null   # Logo-Container (wird eingeblendet; Hintergrund bleibt sichtbar)
var _leaving := false          # verhindert doppeltes Szenenwechseln (Tween-Ende + Skip)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Vollflächiger Hintergrund (bleibt durchgehend deckend, damit beim Ausblenden kein Blitzen entsteht).
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Zentrierter Inhalt: nur das Logo.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 24)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	_content = col

	# Logo (enthält den Titel bereits – daher kein zusätzlicher Text) in einem hellen Kasten,
	# damit der (dunkle) Text auf dem dunklen Hintergrund gut lesbar ist.
	var logo_tex := load(Paths.TEX_LOGO) as Texture2D
	if logo_tex != null and logo_tex.get_height() > 0:
		var box := PanelContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = BOX_COLOR
		sb.set_corner_radius_all(BOX_RADIUS)
		sb.content_margin_left = BOX_PADDING
		sb.content_margin_right = BOX_PADDING
		sb.content_margin_top = BOX_PADDING
		sb.content_margin_bottom = BOX_PADDING
		box.add_theme_stylebox_override("panel", sb)
		col.add_child(box)

		var logo := TextureRect.new()
		logo.texture = logo_tex
		# IGNORE_SIZE: die (große) Textur erzwingt NICHT ihre eigene Größe als Mindestgröße –
		# stattdessen zählt custom_minimum_size, sonst sprengt ein 1024×1024-Bild das Layout.
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var aspect := float(logo_tex.get_width()) / float(logo_tex.get_height())
		logo.custom_minimum_size = Vector2(LOGO_HEIGHT * aspect, LOGO_HEIGHT)
		box.add_child(logo)

	# Sanft einblenden, halten → danach übernimmt _go_to_menu die flackerfreie Überblendung.
	_content.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_content, "modulate:a", 1.0, FADE_IN)
	tw.tween_interval(HOLD)
	tw.tween_callback(_go_to_menu)


# Klick oder Tastendruck überspringt den Splash – mit schneller Blende (wegdrücken).
# _input (statt _unhandled_input), weil der Splash-Root-Control sonst den Mausklick im GUI-System
# „verbraucht" und _unhandled_input ihn nie zu sehen bekäme.
func _input(event: InputEvent) -> void:
	if _leaving:
		return
	if (event is InputEventKey and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or event is InputEventScreenTouch and event.pressed:
		get_viewport().set_input_as_handled()
		_go_to_menu(SKIP_FADE)


func _go_to_menu(fade := FADE_OUT) -> void:
	if _leaving:
		return
	_leaving = true
	# Vollflächige Blende auf einer eigenen CanvasLayer am Tree-Root: Sie überlebt den
	# Szenenwechsel, deckt ihn vollständig ab (kein leerer Zwischen-Frame → kein Flackern)
	# und blendet danach sanft aufs fertig aufgebaute Hauptmenü auf. `fade` = Blenden-Dauer
	# (beim Klick-Skip kurz, sonst die normale FADE_OUT).
	var layer := CanvasLayer.new()
	layer.layer = 128
	get_tree().root.add_child(layer)

	var cover := ColorRect.new()
	cover.color = BG_COLOR
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.modulate.a = 0.0
	layer.add_child(cover)

	var tw := cover.create_tween()
	tw.tween_property(cover, "modulate:a", 1.0, fade)                 # Splash unter der Blende verschwinden lassen
	tw.tween_callback(func(): cover.get_tree().change_scene_to_file(NEXT_SCENE))
	tw.tween_interval(0.1)                                            # ein paar Frames, bis das Hauptmenü aufgebaut ist
	tw.tween_property(cover, "modulate:a", 0.0, fade)                 # auf das Hauptmenü aufblenden
	tw.tween_callback(layer.queue_free)
