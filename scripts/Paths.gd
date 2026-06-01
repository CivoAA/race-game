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

# ── Assets ────────────────────────────────────────────────────────────────────
const MODEL_DEFAULT_CAR = "res://assets/3D-models/cars/default_car/car.glb"

# 3D-Strecken-Modelle (Ordnername "staight" ist im Dateisystem so geschrieben)
const MODEL_TRACK_STRAIGHT_DEFAULT = "res://assets/3D-models/tracks/staight/Default/Default_Street.glb"
const MODEL_TRACK_STRAIGHT_DIRT    = "res://assets/3D-models/tracks/staight/Dirt/Dirt_straight.glb"

# ── Speicherung & Einstellungen ───────────────────────────────────────────────
const SETTINGS_FILE = "user://settings.cfg"
const SAVE_SLOT_FMT = "user://savegame_slot%d.dat"

func save_slot_path(slot: int) -> String:
	return SAVE_SLOT_FMT % slot
