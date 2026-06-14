extends Node
## Zentrale Pfad-Datei – alle res:// und user:// Pfade des Projekts hier pflegen.
## Alle anderen Skripte beziehen Pfade ausschließlich über diesen Autoload.

# ── Szenen ────────────────────────────────────────────────────────────────────
const SCENE_MAIN_MENU  = "res://scenes/MainMenu.tscn"
const SCENE_BUILDER    = "res://main.tscn"
const SCENE_WORLD3D    = "res://scenes/World3D.tscn"

const SCENE_TILE_STRAIGHT_2D  = "res://scenes/tiles2d/Straight2D.tscn"
const SCENE_TILE_CURVE_2D     = "res://scenes/tiles2d/Curve2D.tscn"
const SCENE_TILE_CURVE_ALT_2D = "res://scenes/tiles2d/Curve2D_alt.tscn"

const SCENE_TILE_STRAIGHT_3D = "res://scenes/tiles3d/Straight3D.tscn"
const SCENE_TILE_CURVE_3D    = "res://scenes/tiles3d/Curve3D.tscn"

# ── Skripte ───────────────────────────────────────────────────────────────────
const SCRIPT_CURRENCY_HUD    = "res://scripts/CurrencyHud.gd"
const SCRIPT_UPGRADE_MENU    = "res://scripts/UpgradeMenu.gd"
const SCRIPT_CAR_CONTROLLER  = "res://scripts/CarController.gd"
const SCRIPT_CAR_3D          = "res://scripts/Car3D.gd"
const SCRIPT_TRACK_GENERATOR = "res://scripts/TrackGenerator3D.gd"
const SCRIPT_GAME_HUD        = "res://scripts/GameHUD.gd"
const SCRIPT_GLOBAL_MODAL    = "res://scripts/GlobalModal.gd"

# ── Assets ────────────────────────────────────────────────────────────────────
const MODEL_DEFAULT_CAR = "res://assets/3D-models/cars/default_car/car.glb"

# Test-Auto mit Umfärb-Maske (Werkstatt-Lackierung). Albedo + Maske teilen sich die UVs.
const MODEL_TEST_CAR    = "res://assets/3D-models/cars/test_car/car.glb"

# Reines Test-Modell aus Blender – nur zum Ausprobieren (Garage-Knopf „Test-Auto"), keine Maske/Features.
const MODEL_TEST_CAR_BLENDER = "res://assets/3D-models/cars/test_car_blender/test_car_blender.glb"
# Name der Karosserie-Materialfläche im Blender-Testmodell (das „helle Grün") – nur diese wird umgefärbt.
const TEST_CAR_BODY_MATERIAL = "Car_main_color"

# Super-Auto („Auto 2") – eigenes Modell, keine Werkstatt-Lackierung (eigene gebackene Texturen).
const MODEL_ERIC_CAR    = "res://assets/3D-models/cars/eric_car/Car_eric.glb"
const TEX_CAR_ALBEDO    = "res://assets/3D-models/cars/test_car/car_0.png"
const TEX_CAR_MASK      = "res://assets/3D-models/cars/test_car/car_mask.png"

# Shader: färbt nur die maskierten (roten) Bereiche um, behält Hell-Dunkel-Verläufe.
const SHADER_CAR_PAINT  = "res://shaders/car_paint.gdshader"
# Shader: Lack + Muster für FLACHE Material-Farben (Blender-Testmodell, keine Maske/Textur).
const SHADER_CAR_PAINT_FLAT = "res://shaders/car_paint_flat.gdshader"

# Shader: animierter Hauptmenü-Hintergrund (Perspektiv-Straße + Glows).
const SHADER_MAINMENU_BG = "res://shaders/mainmenu_bg.gdshader"

# UI-Soundeffekte – laufen über den "SFX"-Bus, also direkt vom Effekte-Regler gesteuert.
const SFX_UI_HOVER = "res://assets/musik/sound-9.mp3"   # Maus über einen Button
const SFX_UI_CLICK = "res://assets/musik/sound-14.mp3"  # Button geklickt
const SFX_FINISH   = "res://assets/musik/ziel.mp3"      # Auto überfährt die Ziellinie (nur 3D-Ansicht)

# 3D-Strecken-Modelle (Ordnername "staight" ist im Dateisystem so geschrieben).
# Neuer Asset-Satz: pro Belag je ein Geraden- und ein Kurven-GLB, alle auf demselben
# 3×3-Raster (Kachel = 3.0 Modell-Einheiten). Beläge im Spiel:
# Road(=Default)/Dirt/Ice/Race sowie die Test-Beläge Sand/Water/Glue (noch ohne Ökonomie-Effekt).
const MODEL_TRACK_STRAIGHT_DEFAULT = "res://assets/3D-models/tracks/staight/RoadStraight.glb"
const MODEL_TRACK_STRAIGHT_DIRT    = "res://assets/3D-models/tracks/staight/DirtStraight.glb"
const MODEL_TRACK_STRAIGHT_ICE     = "res://assets/3D-models/tracks/staight/IceStraight.glb"
const MODEL_TRACK_STRAIGHT_RACING  = "res://assets/3D-models/tracks/staight/RaceStraight.glb"
const MODEL_TRACK_STRAIGHT_SAND    = "res://assets/3D-models/tracks/staight/SandStraight.glb"
const MODEL_TRACK_STRAIGHT_WATER   = "res://assets/3D-models/tracks/staight/WaterStraight.glb"
const MODEL_TRACK_STRAIGHT_GLUE    = "res://assets/3D-models/tracks/staight/GlueStraight.glb"
const MODEL_TRACK_CURVE_DEFAULT    = "res://assets/3D-models/tracks/curve/RoadCurve.glb"
const MODEL_TRACK_CURVE_DIRT       = "res://assets/3D-models/tracks/curve/DirtCurve.glb"
const MODEL_TRACK_CURVE_ICE        = "res://assets/3D-models/tracks/curve/IceCurve.glb"
const MODEL_TRACK_CURVE_RACING     = "res://assets/3D-models/tracks/curve/RaceCurve.glb"
const MODEL_TRACK_CURVE_SAND       = "res://assets/3D-models/tracks/curve/SandCurve.glb"
const MODEL_TRACK_CURVE_WATER      = "res://assets/3D-models/tracks/curve/WaterCurve.glb"
const MODEL_TRACK_CURVE_GLUE       = "res://assets/3D-models/tracks/curve/GlueCurve.glb"

# Spezialfelder mit eigenem GLB (ersetzen die früher prozedural gebaute Geometrie).
const MODEL_TRACK_RAMP  = "res://assets/3D-models/tracks/special/Ramp.glb"
const MODEL_TRACK_STAND = "res://assets/3D-models/tracks/special/Stand.glb"

# ── 2D-Tile-Texturen (Bauplan-Ansicht) ─────────────────────────────────────────
# Belag-Artworks für die 2D-Strecken statt der prozeduralen Zeichnung. Die Dateinamen
# stehen exakt wie im Ordner (inkl. Tippfehler "cruve"/"straigth" und Belag "eis"),
# darum eine feste Tabelle statt generierter Pfade.
#   Geraden-Orientierung:  OW = waagerecht (Ost-West), NS = senkrecht (Nord-Süd)
#   Kurven-Orientierung (zwei offene Kanten): OS=unten+rechts, SW=unten+links,
#                                             NW=oben+links,   NO=oben+rechts
const TEX_GRASS_2D = "res://assets/2D-tiles/grass2.png"
# Start-Feld-Markierung (Ziel/Start-Flagge) – liegt über grass2, ersetzt das alte grüne Overlay.
const TEX_START_2D = "res://assets/2D-tiles/allgemein/start.png"
# Rampen-Artwork (96×32 = 3 Kacheln breit: links Absprung, Mitte Sprungfeld, rechts Landung).
const TEX_RAMP_2D  = "res://assets/2D-tiles/ramp.png"
const TILE2D_TEXTURES := {
	"default_straight_OW": "res://assets/2D-tiles/default_straigth_OW.png",
	"default_straight_NS": "res://assets/2D-tiles/default_straigth_NS.png",
	"default_curve_OS":    "res://assets/2D-tiles/default_cruve_OS.png",
	"default_curve_SW":    "res://assets/2D-tiles/default_cruve_SW.png",
	"default_curve_NW":    "res://assets/2D-tiles/default_cruve_NW.png",
	"default_curve_NO":    "res://assets/2D-tiles/default_cruve_NO.png",
	"dirt_straight_OW":    "res://assets/2D-tiles/dirt_staight_OW.png",
	"dirt_straight_NS":    "res://assets/2D-tiles/dirt_staight_NS.png",
	"dirt_curve_OS":       "res://assets/2D-tiles/dirt_curve_OS.png",
	"dirt_curve_SW":       "res://assets/2D-tiles/dirt_cruve_SW.png",
	"dirt_curve_NW":       "res://assets/2D-tiles/dirt_cruve_NW.png",
	"dirt_curve_NO":       "res://assets/2D-tiles/dirt_cruve_NO.png",
	"ice_straight_OW":     "res://assets/2D-tiles/eis_straigth_OW.png",
	"ice_straight_NS":     "res://assets/2D-tiles/eis_straigth_NS.png",
	"ice_curve_OS":        "res://assets/2D-tiles/eis_curve_OS.png",
	"ice_curve_SW":        "res://assets/2D-tiles/eis_curve_SW.png",
	"ice_curve_NW":        "res://assets/2D-tiles/eis_curve_NW.png",
	"ice_curve_NO":        "res://assets/2D-tiles/eis_curve_NO.png",
	# Rennbelag (eigener Pixelart-Satz im Unterordner "racing"). Effekt/Preis = Default,
	# nur das Artwork unterscheidet sich. Orientierungen exakt wie oben (OW/NS, OS/SW/NW/NO).
	"race_straight_OW":    "res://assets/2D-tiles/racing/track_straight_OW.png",
	"race_straight_NS":    "res://assets/2D-tiles/racing/track_straight_NS.png",
	"race_curve_OS":       "res://assets/2D-tiles/racing/track_curve_OS.png",
	"race_curve_SW":       "res://assets/2D-tiles/racing/track_curve_SW.png",
	"race_curve_NW":       "res://assets/2D-tiles/racing/track_curve_NW.png",
	"race_curve_NO":       "res://assets/2D-tiles/racing/track_curve_NO.png",
}

# Liefert den res://-Pfad der 2D-Textur für Belag (default/dirt/ice), Form (straight/curve)
# und Drehung in Grad (0/90/180/270). Leerer String, wenn es kein passendes Artwork gibt.
func tile2d_texture(belag: String, shape: String, rotation: int) -> String:
	var rot := ((int(rotation) % 360) + 360) % 360
	var orient := ""
	if shape == "straight":
		orient = "OW" if rot % 180 == 0 else "NS"
	else:
		match rot:
			90:  orient = "SW"
			180: orient = "NW"
			270: orient = "NO"
			_:   orient = "OS"
	return TILE2D_TEXTURES.get("%s_%s_%s" % [belag, shape, orient], "")


# ── Speicherung & Einstellungen ───────────────────────────────────────────────
const SETTINGS_FILE = "user://settings.cfg"
const SAVE_SLOT_FMT = "user://savegame_slot%d.dat"

func save_slot_path(slot: int) -> String:
	return SAVE_SLOT_FMT % slot
