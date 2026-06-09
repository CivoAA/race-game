extends Node
## Autoload "Icons": Tabler Icons (MIT-Lizenz, v3.44.0) als Icon-Font.
##
## Jedes Icon ist ein Glyph der Schrift tabler-icons.ttf an einem Unicode-Codepoint
## (Private-Use-Area). Anzeige wie zuvor die Emojis – als Text in einem Label/Button.
##
## Die Codepoints stehen unten als Integer in _CP; in _ready werden daraus die String-
## Glyphen (TROPHY, COIN, …) per char() gebaut und als Properties gesetzt. So braucht der
## Quelltext keine unsichtbaren Glyph-Literale.
##
## Zusätzlich wird die Schrift in _ready als FALLBACK in den Theme-Default-Font gehängt,
## damit die Glyphen auch INLINE in normalem Text rendern (z. B. ""+1.234"), ohne pro
## Label die Schrift umzustellen.
##
## Verwendung:
##   lbl.text = Icons.TROPHY                       # reicht dank Fallback
##   var l := Icons.label(Icons.TROPHY, 24, col)   # fertiges, gefärbtes Icon-Label
##
## Neue Icons: Name + Codepoint stehen in tabler-icons.css (siehe tabler.io/icons);
## content "\eXXXX" dort → hier in _CP als 0xeXXXX ergänzen und gleichnamige var anlegen.

const FONT_PATH  := "res://assets/fonts/tabler-icons.ttf"
const THEME_PATH := "res://ui_theme.tres"

# Wird in _ready geladen (load statt preload → Spiel startet auch ohne Reimport,
# Icons bleiben dann nur leer statt das Skript zu brechen).
var FONT: Font = null

# Name → Codepoint (Tabler Icons 3.44.0). Quelle der Wahrheit für die Glyphen unten.
const _CP := {
	"CLOCK": 0xea70, "TROPHY": 0xeb45, "FLAG": 0xeaa6, "FLAG_3": 0xee8d,
	"BOLT": 0xea38, "TOOLS": 0xebca, "HAMMER": 0xef91, "FLAME": 0xec2c,
	"WIND": 0xec34, "SHOPPING_CART": 0xeb25, "STORE": 0xea4e, "CHART_BAR": 0xea59,
	"CHART_LINE": 0xea5c, "STAR": 0xeb2e, "SETTINGS": 0xeb20, "ADJUSTMENTS": 0xea03,
	"CAR": 0xebbb, "STEERING_WHEEL": 0xec7b, "TRUCK": 0xebc4, "HOME": 0xeac1,
	"COIN": 0xeb82, "COINS": 0xf65d, "LOCK": 0xeae2, "LOCK_OPEN": 0xeae1,
	"CIRCLE_CHECK": 0xea67, "CHECK": 0xea5e, "X": 0xeb55, "CIRCLE_X": 0xea6a,
	"PLUS": 0xeb0b, "MINUS": 0xeaf2, "ARROW_UP": 0xea25, "ARROW_BIG_UP": 0xeddd,
	"ARROW_DOWN": 0xea16, "WORLD": 0xeb54, "MAP_2": 0xeae7, "GAUGE": 0xeab1,
	"ROSETTE_CHECK": 0xf1f8, "MEDAL": 0xec78, "AWARD": 0xea2c, "PLAY": 0xed46,
	"PAUSE": 0xed45, "VOLUME": 0xeb51, "VOLUME_OFF": 0xeb50, "MUSIC": 0xeafc,
	"GAMEPAD": 0xf1d2, "DESKTOP": 0xea89, "ROAD": 0xf018, "STADIUM": 0xf641,
	"SNOWFLAKE": 0xec0b, "MOUNTAIN": 0xef97, "PALETTE": 0xeb01, "ROCKET": 0xec45,
	"MAGNET": 0xeae3, "SHIELD": 0xeb24, "PENCIL": 0xeb04, "FLOPPY": 0xeb62,
	"VIDEO": 0xed22, "CAMERA": 0xea54, "TRASH": 0xeb41, "MENU": 0xec42,
	"INFINITY": 0xeb69, "RECYCLE": 0xeb9b, "KEY": 0xeac7, "SPARKLES": 0xf6d7,
	"CIRCLE_DASHED": 0xed27, "CIRCLE": 0xea6b, "MATH": 0xeeb3, "TRENDING_UP": 0xeb43,
	"ENGINE": 0xef7e, "CONFETTI": 0xee46, "LAYOUT_GRID": 0xedba, "BUG": 0xea48,
	"GARAGE": 0xfc77,
}

# Glyph-Strings – in _ready aus _CP befüllt. Vor _ready leer (""), danach das jeweilige Icon.
var CLOCK: String; var TROPHY: String; var FLAG: String; var FLAG_3: String
var BOLT: String; var TOOLS: String; var HAMMER: String; var FLAME: String
var WIND: String; var SHOPPING_CART: String; var STORE: String; var CHART_BAR: String
var CHART_LINE: String; var STAR: String; var SETTINGS: String; var ADJUSTMENTS: String
var CAR: String; var STEERING_WHEEL: String; var TRUCK: String; var HOME: String
var COIN: String; var COINS: String; var LOCK: String; var LOCK_OPEN: String
var CIRCLE_CHECK: String; var CHECK: String; var X: String; var CIRCLE_X: String
var PLUS: String; var MINUS: String; var ARROW_UP: String; var ARROW_BIG_UP: String
var ARROW_DOWN: String; var WORLD: String; var MAP_2: String; var GAUGE: String
var ROSETTE_CHECK: String; var MEDAL: String; var AWARD: String; var PLAY: String
var PAUSE: String; var VOLUME: String; var VOLUME_OFF: String; var MUSIC: String
var GAMEPAD: String; var DESKTOP: String; var ROAD: String; var STADIUM: String
var SNOWFLAKE: String; var MOUNTAIN: String; var PALETTE: String; var ROCKET: String
var MAGNET: String; var SHIELD: String; var PENCIL: String; var FLOPPY: String
var VIDEO: String; var CAMERA: String; var TRASH: String; var MENU: String
var INFINITY: String; var RECYCLE: String; var KEY: String; var SPARKLES: String
var CIRCLE_DASHED: String; var CIRCLE: String; var MATH: String; var TRENDING_UP: String
var ENGINE: String; var CONFETTI: String; var LAYOUT_GRID: String; var BUG: String
var GARAGE: String


func _ready() -> void:
	# Glyph-Strings aus den Codepoints bauen (char() liefert das 1-Zeichen-Icon).
	for name in _CP:
		set(name, char(_CP[name]))

	var f := load(FONT_PATH)
	if f is Font:
		FONT = f
		_install_as_fallback()
	else:
		push_warning("Icons: Tabler-Font nicht gefunden (%s). Projekt einmal im Godot-Editor öffnen, damit die .ttf importiert wird." % FONT_PATH)


# Tabler als Fallback an den Theme-Default-Font hängen → Icon-Glyphen rendern inline in
# jedem Label, das die Standardschrift nutzt (also fast überall).
func _install_as_fallback() -> void:
	var theme := load(THEME_PATH)
	if theme is Theme and theme.default_font is Font:
		var base: Font = theme.default_font
		var fbs := base.fallbacks
		if not fbs.has(FONT):
			fbs.append(FONT)
			base.fallbacks = fbs


## Fertiges, zentriertes Icon-Label (mit explizitem Font-Override – unabhängig vom Fallback).
func label(glyph: String, size: int = 20, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	apply(l, glyph, size, color)
	return l


## Bestehendes Label auf ein Icon umstellen. size/color optional (≤0 bzw. a==0 = unverändert).
func apply(lbl: Label, glyph: String, size: int = -1, color: Color = Color(0, 0, 0, 0)) -> void:
	if FONT != null:
		lbl.add_theme_font_override("font", FONT)
	lbl.text = glyph
	if size > 0:
		lbl.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		lbl.add_theme_color_override("font_color", color)
