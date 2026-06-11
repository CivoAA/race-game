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

# 3D-Strecken-Modelle (Ordnername "staight" ist im Dateisystem so geschrieben)
const MODEL_TRACK_STRAIGHT_DEFAULT = "res://assets/3D-models/tracks/staight/Default/Default_Street.glb"
const MODEL_TRACK_STRAIGHT_DIRT    = "res://assets/3D-models/tracks/staight/Dirt/Dirt_straight.glb"
const MODEL_TRACK_STRAIGHT_ICE     = "res://assets/3D-models/tracks/staight/ice/Ice_straight.glb"
const MODEL_TRACK_CURVE_DEFAULT    = "res://assets/3D-models/tracks/curve/Default/c.default.glb"

# ── Speicherung & Einstellungen ───────────────────────────────────────────────
const SETTINGS_FILE = "user://settings.cfg"
const SAVE_SLOT_FMT = "user://savegame_slot%d.dat"

func save_slot_path(slot: int) -> String:
	return SAVE_SLOT_FMT % slot
