extends Node
## Autoload "Display": globales Anzeige-Overlay über ALLEN Szenen (Hauptmenü,
## Baumodus, Rennen). Hostet die FPS-Anzeige (oben rechts) als Vollbild-CanvasLayer.
##
## Zusätzlich verwaltet es den „Multiplikator anzeigen"-Modus (für die ×-Marker im
## Baumodus). Die Menüs rufen nur die set_*-Funktionen; Persistenz/Anwenden liegt
## hier zentral. Beim Start werden die Werte aus settings.cfg geladen.

# Modi für die ×-Marker auf den Baufeldern.
enum MultiplierMode { ALL, AFFECTED, NONE }

# Zahlenformat für Geldbeträge (Economy.format_currency liest diesen Wert):
#   STANDARD     = Suffixe K/M/B/T … (Standard)
#   SCIENTIFIC   = wissenschaftlich, beliebiger Exponent (z. B. 1.23e7)
#   ENGINEER     = Ingenieurnotation, Exponent in 3er-Schritten (z. B. 12.3e6, 1.5e12)
enum MoneyNotation { STANDARD, SCIENTIFIC, ENGINEER }

signal multiplier_mode_changed(mode: int)
signal money_notation_changed(mode: int)
signal performance_mode_changed(on: bool)

var multiplier_mode: int = MultiplierMode.AFFECTED
var money_notation: int = MoneyNotation.STANDARD
# Performance-Modus (Vorstufe): schaltet unnötige Animationen ab, damit das Spiel flüssiger läuft.
# Aktuell hängt nur die Prestige-Button-Animation daran (an=einfarbig, aus=Glitzer+Wasser); später
# sollen hier weitere Effekte gebündelt werden.
var performance_mode: bool = false

var _layer:     CanvasLayer
var _fps_lbl:   Label

var _settings := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.layer = 110   # über allem (höchste reguläre Ebene ist PauseMenu = 100)
	add_child(_layer)

	# FPS-Anzeige ganz oben rechts. Rechts verankert, wächst nach links → bleibt bei
	# wechselnder Textbreite bündig in der Ecke.
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


func set_multiplier_mode(mode: int) -> void:
	multiplier_mode = clampi(mode, 0, 2)
	multiplier_mode_changed.emit(multiplier_mode)


func set_money_notation(mode: int) -> void:
	money_notation = clampi(mode, 0, 2)
	money_notation_changed.emit(money_notation)


# Performance-Modus setzen (Vorstufe: wirkt vorerst nur auf die Prestige-Button-Animation).
func set_performance_mode(on: bool) -> void:
	performance_mode = on
	performance_mode_changed.emit(performance_mode)


# ── Startwerte laden ────────────────────────────────────────────────────────────

func _load_from_settings() -> void:
	_settings.load(Paths.SETTINGS_FILE)
	_fps_lbl.visible   = bool(_settings.get_value("options", "show_fps", false))
	multiplier_mode    = clampi(int(_settings.get_value("options", "show_multiplier", MultiplierMode.AFFECTED)), 0, 2)
	money_notation     = clampi(int(_settings.get_value("options", "money_notation", MoneyNotation.STANDARD)), 0, 2)
	performance_mode   = bool(_settings.get_value("options", "performance_mode", false))
