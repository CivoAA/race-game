extends Node
## Autoload "Display": globales Anzeige-Overlay über ALLEN Szenen (Hauptmenü,
## Baumodus, Rennen). Bündelt drei optionale Effekte als ein Vollbild-CanvasLayer:
##   • FPS-Anzeige (oben links)
##   • Dark Mode (alles etwas dunkler)
##   • Farbenblind-Korrektur (Rot-Grün-Daltonisierung per Shader)
##
## Zusätzlich verwaltet es den „Multiplikator anzeigen"-Modus (für die ×-Marker im
## Baumodus). Die Menüs rufen nur die set_*-Funktionen; Persistenz/Anwenden liegt
## hier zentral. Beim Start werden die Werte aus settings.cfg geladen.

# Modi für die ×-Marker auf den Baufeldern.
enum MultiplierMode { ALL, AFFECTED, NONE }

signal multiplier_mode_changed(mode: int)

var multiplier_mode: int = MultiplierMode.AFFECTED

var _layer:     CanvasLayer
var _cb_rect:   ColorRect
var _dark_rect: ColorRect
var _fps_lbl:   Label

var _settings := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.layer = 110   # über allem (höchste reguläre Ebene ist PauseMenu = 100)
	add_child(_layer)

	# Farbenblind-Korrektur zuerst: liest die darunter gerenderte Szene (Screen-Textur).
	_cb_rect = ColorRect.new()
	_cb_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cb_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cb_rect.color = Color(1, 1, 1, 1)
	var sh := load(Paths.SHADER_COLORBLIND)
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_cb_rect.material = mat
	_cb_rect.visible = false
	_layer.add_child(_cb_rect)

	# Dark-Mode-Abdunklung über der (ggf. korrigierten) Szene.
	_dark_rect = ColorRect.new()
	_dark_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark_rect.color = Color(0, 0, 0, 0.28)
	_dark_rect.visible = false
	_layer.add_child(_dark_rect)

	# FPS-Anzeige ganz oben rechts (wird von Dark/Colorblind nicht beeinflusst).
	# Rechts verankert, wächst nach links → bleibt bei wechselnder Textbreite bündig
	# in der Ecke.
	_fps_lbl = Label.new()
	_fps_lbl.anchor_left   = 1.0
	_fps_lbl.anchor_right  = 1.0
	_fps_lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_lbl.offset_left   = -8
	_fps_lbl.offset_right  = -8
	_fps_lbl.offset_top    = 4
	_fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_lbl.add_theme_font_size_override("font_size", 13)
	_fps_lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	_fps_lbl.add_theme_constant_override("outline_size", 4)
	_fps_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_fps_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_lbl.visible = false
	_layer.add_child(_fps_lbl)

	_load_from_settings()


func _process(_delta: float) -> void:
	if _fps_lbl.visible:
		_fps_lbl.text = "%d FPS" % Engine.get_frames_per_second()


# ── Anwenden (von den Menüs aufgerufen) ─────────────────────────────────────────
# Reine Anwendung der Effekte – die Persistenz (settings.cfg) liegt wie bei allen
# anderen Optionen bei den Menüs (MainMenu/PauseMenu), um doppelte Schreiber auf
# dieselbe Datei zu vermeiden.

func set_fps_visible(on: bool) -> void:
	_fps_lbl.visible = on


func set_dark_mode(on: bool) -> void:
	_dark_rect.visible = on


func set_colorblind(on: bool) -> void:
	# Ohne geladenen Shader würde der weiße Rect das Bild verdecken → nur dann zeigen.
	_cb_rect.visible = on and _cb_rect.material != null


func set_multiplier_mode(mode: int) -> void:
	multiplier_mode = clampi(mode, 0, 2)
	multiplier_mode_changed.emit(multiplier_mode)


# ── Startwerte laden ────────────────────────────────────────────────────────────

func _load_from_settings() -> void:
	_settings.load(Paths.SETTINGS_FILE)
	_fps_lbl.visible   = bool(_settings.get_value("options", "show_fps", false))
	_dark_rect.visible = bool(_settings.get_value("options", "dark_mode", false))
	_cb_rect.visible   = bool(_settings.get_value("options", "colorblind", false)) and _cb_rect.material != null
	multiplier_mode    = clampi(int(_settings.get_value("options", "show_multiplier", MultiplierMode.AFFECTED)), 0, 2)
