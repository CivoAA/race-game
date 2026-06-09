extends Node
## Responsive UI — Autoload "RUI"
## Berechnet Viewport-Dimensionen und Layout-Modus zur Laufzeit.
## Alle anderen UI-Scripts nutzen RUI.vw/vh/px/font statt hartkodierten Pixelwerten.
##
## Basis-Design-Auflösung: 960×540 (16:9). Die virtuellen Koordinaten des Canvas
## werden von Godot (canvas_items + expand) automatisch auf das physische Fenster
## skaliert – RUI löst nur die Sonderfälle: abweichende Seitenverhältnisse und
## Mindestgrößen für Schriften/Buttons.

const BASE_W := 960.0
const BASE_H := 540.0

enum Layout {
	LANDSCAPE,        # normales 16:9 oder ähnlich (960×540 …)
	ULTRAWIDE,        # sehr breite Seitenverhältnisse (> 21:9, z. B. 3440×1440)
	PORTRAIT,         # hochformatig (z. B. 720×1280, 1080×1920)
}

var _vp     : Vector2 = Vector2(BASE_W, BASE_H)
var _layout : Layout  = Layout.LANDSCAPE

signal layout_changed(layout: Layout)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_on_viewport_changed)
	_on_viewport_changed()


func _on_viewport_changed() -> void:
	_vp = get_viewport().get_visible_rect().size
	var new_layout := _compute_layout()
	if new_layout != _layout:
		_layout = new_layout
		layout_changed.emit(_layout)


func _compute_layout() -> Layout:
	var aspect := _vp.x / maxf(_vp.y, 1.0)
	if aspect < 0.85:
		return Layout.PORTRAIT
	elif aspect > 2.1:
		return Layout.ULTRAWIDE
	return Layout.LANDSCAPE


# ── Viewport-Dimensionen ──────────────────────────────────────────────────────

## Aktuelle virtuelle Viewport-Breite (ändert sich bei Ultrawide / Portrait).
func vw() -> float: return _vp.x

## Aktuelle virtuelle Viewport-Höhe.
func vh() -> float: return _vp.y

## Aktueller Layout-Modus.
func layout() -> Layout: return _layout
func is_portrait()  -> bool: return _layout == Layout.PORTRAIT
func is_ultrawide() -> bool: return _layout == Layout.ULTRAWIDE
func is_landscape() -> bool: return _layout == Layout.LANDSCAPE


# ── Sidebar-Geometrie ─────────────────────────────────────────────────────────
# Im Landscape/Ultrawide-Modus liegt die Navigation als rechte Seitenleiste.
# Im Portrait-Modus liegt sie als untere Leiste (nav_h > 0, nav_w = 0).

const SIDEBAR_W  : float = 150.0   # Breite der rechten Seitenleiste (Landscape)
const BOTTOM_NAV_H : float = 56.0  # Höhe der unteren Navigationsleiste (Portrait)

## Breite der rechten Seitenleiste (0 im Portrait-Modus).
func nav_w() -> float:
	return 0.0 if is_portrait() else SIDEBAR_W

## Höhe der unteren Navigationsleiste (0 im Landscape/Ultrawide-Modus).
func nav_h() -> float:
	return BOTTOM_NAV_H if is_portrait() else 0.0

## Breite des Spielinhalts-Bereichs (Viewport minus Seitenleiste).
func content_w() -> float: return _vp.x - nav_w()

## Höhe des Spielinhalts-Bereichs (Viewport minus untere Nav, minus Top-Bar abziehen liegt beim Aufrufer).
func content_h() -> float: return _vp.y - nav_h()


# ── Skalierungs-Helfer ────────────────────────────────────────────────────────
# Mit canvas_items + expand skaliert Godot den Canvas automatisch proportional.
# px() / font() liefern physische Mindestwerte, damit Elemente auf sehr kleinen
# Bildschirmen nicht zu winzig werden und auf sehr großen nicht übergroß.

## Skaliert einen Pixelwert (ausgelegt für BASE_H = 540px) auf die aktuelle
## Viewport-Höhe. Für Button-Höhen, Icon-Größen, Abstände.
## Begrenzt auf [0.6× … 3.0×] damit 4K-UIs nicht überdimensional werden.
func px(base: float) -> int:
	return int(base * clampf(_vp.y / BASE_H, 0.6, 3.0))


## Wie px(), aber konservativer begrenzt für Schriftgrößen (max 2.0×),
## weil der Canvas-Stretch die Schrift bereits vergrößert.
func font(base: int) -> int:
	return int(base * clampf(_vp.y / BASE_H, 0.75, 2.0))
