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

# Tier-1-Auto („"Renn"auto") – eigenes Modell, eigene gebackene Texturen (keine Umfärb-Maske).
const MODEL_ERIC_CAR    = "res://assets/3D-models/cars/eric_car/Car_eric.glb"
const TEX_CAR_ALBEDO    = "res://assets/3D-models/cars/test_car/car_0.png"
const TEX_CAR_MASK      = "res://assets/3D-models/cars/test_car/car_mask.png"

# Tier-2-Auto („Frosch", Miata) – mit eigener Umfärb-Maske. Albedo (miata_0.png) hat die umfärbbaren
# Bereiche grün markiert; miata_mask.png wandelt genau diese in Rot (= umfärbbar), Rest schwarz (fix).
const MODEL_FROSCH_CAR  = "res://assets/3D-models/cars/frosh_auto/miata.glb"
const TEX_FROSCH_ALBEDO = "res://assets/3D-models/cars/frosh_auto/miata_0.png"
const TEX_FROSCH_MASK   = "res://assets/3D-models/cars/frosh_auto/miata_mask.png"

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

# Gemeinsame Track-Textur (Atlas). Die neuen GLBs kommen OHNE Material/Textur, tragen aber UVs,
# die in diesen Atlas mappen → die Textur wird in TrackGenerator3D pro Mesh als Albedo gesetzt.
const TEX_TRACK_ATLAS = "res://assets/3D-models/tracks/textures/TrackTexture.png"

# Spezialfelder mit eigenem GLB (ersetzen die früher prozedural gebaute Geometrie).
const MODEL_TRACK_RAMP  = "res://assets/3D-models/tracks/special/ramp/Ramp.glb"
# Looping und Steilwandkurve sind jetzt ebenfalls eigene GLBs (vorher prozedural gebaut).
# Loop = ein Feld (Basislage S→N wie eine Gerade), Bank = ein gebanktes Kurven-Viertel pro Kachel.
const MODEL_TRACK_LOOP  = "res://assets/3D-models/tracks/special/looping/Loop.glb"
const MODEL_TRACK_WALL  = "res://assets/3D-models/tracks/curve/steilcurve/Bank.glb"
# Portal: pro Feld zwei GLBs auf EINER Kachel – die Rampe (zur Straße, befahrbar) plus das Tor
# dahinter. Blau = Eingang, Orange = Ausgang (Rolle ergibt sich aus der gefahrenen Route).
const MODEL_TRACK_PORTAL_RAMP   = "res://assets/3D-models/tracks/special/portal/PortalRamp.glb"
const MODEL_TRACK_PORTAL_BLUE   = "res://assets/3D-models/tracks/special/portal/PortalBlue.glb"
const MODEL_TRACK_PORTAL_ORANGE = "res://assets/3D-models/tracks/special/portal/PortalOrange.glb"
# Tribüne: pro Stapel-Anzahl ein eigenes, fertig arrangiertes GLB (Stand1..Stand4). Stapel ab 4
# (auch 5) nutzt Stand4. Pfad immer über stand_model(count) beziehen.
const MODEL_TRACK_STANDS := [
	"res://assets/3D-models/tracks/special/Stand/Stand1.glb",
	"res://assets/3D-models/tracks/special/Stand/Stand2.glb",
	"res://assets/3D-models/tracks/special/Stand/Stand3.glb",
	"res://assets/3D-models/tracks/special/Stand/Stand4.glb",
]

# ── 2D-Tile-Texturen (Bauplan-Ansicht) ─────────────────────────────────────────
# Belag-Artworks für die 2D-Strecken statt der prozeduralen Zeichnung. Die Dateinamen
# stehen exakt wie im Ordner (inkl. Tippfehler "cruve"/"straigth" und Belag "eis"),
# darum eine feste Tabelle statt generierter Pfade.
#   Geraden-Orientierung:  OW = waagerecht (Ost-West), NS = senkrecht (Nord-Süd)
#   Kurven-Orientierung (zwei offene Kanten): OS=unten+rechts, SW=unten+links,
#                                             NW=oben+links,   NO=oben+rechts
const TEX_GRASS_2D = "res://assets/2D-tiles/grass2.png"
# Studio-Logo (Splash-Screen vor dem Hauptmenü).
const TEX_LOGO = "res://assets/2D-tiles/allgemein/logo.png"
# Start-Feld-Markierung (Ziel/Start-Flagge) – liegt über grass2, ersetzt das alte grüne Overlay.
const TEX_START_2D = "res://assets/2D-tiles/allgemein/start.png"
# Start-Feld senkrecht (Pfeil nach Süden/unten) – für die N/S-Achse, statt die O/W-Flagge zu drehen.
const TEX_START_NS_2D = "res://assets/2D-tiles/allgemein/start_NS.png"
# Looping-Artwork (2D): EIN Bild, standardmäßig OW gemalt – für die NS-Basislage 90° gedreht.
const TEX_LOOP_2D    = "res://assets/2D-tiles/allgemein/looping.png"
# Steilwandkurve-Artwork (2D): EIN Bild, 32×64 = deckt das GANZE 2-Kachel-Paar ab (Basislage rot=0:
# senkrecht, wall_start oben/Nord, wall_end unten/Süd). Wird nur am wall_start gezeichnet.
const TEX_WALL_2D    = "res://assets/2D-tiles/allgemein/bankedTurn.png"
# Portal-Artwork (2D): richtungsgebunden – man fährt nur von EINER (der offenen) Seite rein.
# Pro Farbe vier Bilder, nummeriert nach der offenen Einfahr-Seite: 1=Ost, 2=Süd, 3=West, 4=Nord.
# Blau = Eingang (oder noch unbestimmte Rolle), Gelb = Ausgang (per gefahrener Route gesetzt).
# Die Bilder sind absolut/welt-orientiert gemalt → keine Node-Drehung, Auswahl über portal_texture().
const TEX_PORTAL_BLUE := {
	"E": "res://assets/2D-tiles/allgemein/bluePortal1.png",
	"S": "res://assets/2D-tiles/allgemein/bluePortal2.png",
	"W": "res://assets/2D-tiles/allgemein/bluePortal3.png",
	"N": "res://assets/2D-tiles/allgemein/bluePortal4.png",
}
const TEX_PORTAL_YELLOW := {
	"E": "res://assets/2D-tiles/allgemein/yellowPortal1.png",
	"S": "res://assets/2D-tiles/allgemein/yellowPortal2.png",
	# Gelb: Artworks 3 und 4 sind gegenüber Blau vertauscht gemalt – yellowPortal4 zeigt die nach
	# WEST offene Einfahrt, yellowPortal3 die nach NORD offene (deshalb hier W↔N getauscht).
	"W": "res://assets/2D-tiles/allgemein/yellowPortal4.png",
	"N": "res://assets/2D-tiles/allgemein/yellowPortal3.png",
}

# Tribünen-Artwork (2D, top-down Pixelart), richtungsgebunden je Stapel-Stufe:
#   Stapel 1 (singleGrandstand): EINE Boost-Richtung = Blickrichtung. 1=Süd 2=West 3=Ost 4=Nord.
#   Stapel 2 (doubleGrandstand): zwei gegenüberliegende Richtungen → NS- oder OW-Variante.
#   Stapel 3 (tipleGrandstand):  drei Richtungen; der Buchstabe nennt die NICHT geboostete Seite
#                                (die, in die sie NICHT schaut). O = Ost.
#   Stapel 4/5 (fullGrandstand): geschlossener Rechteck-Rahmen, alle vier Richtungen geboostet.
#               TEX_STAND_QUAD gesetzt → echtes Artwork (Platzhalter nur noch Fallback wenn leer).
# Alle Bilder sind absolut/welt-orientiert gemalt → keine Node-Drehung (siehe _create_stand_node).
const TEX_STAND_SINGLE := {
	"S": "res://assets/2D-tiles/allgemein/singleGrandstand1.png",
	"W": "res://assets/2D-tiles/allgemein/singleGrandstand2.png",   # Asset 2 schaut nach links = West
	"E": "res://assets/2D-tiles/allgemein/singleGrandstand3.png",   # Asset 3 schaut nach rechts = Ost
	"N": "res://assets/2D-tiles/allgemein/singleGrandstand4.png",
}
const TEX_STAND_DOUBLE_NS = "res://assets/2D-tiles/allgemein/doubleGrandstandNS.png"
const TEX_STAND_DOUBLE_OW = "res://assets/2D-tiles/allgemein/doubleGrandstandOW.png"
const TEX_STAND_TRIPLE := {
	"N": "res://assets/2D-tiles/allgemein/tipleGrandstandN.png",
	"E": "res://assets/2D-tiles/allgemein/tipleGrandstandO.png",
	"S": "res://assets/2D-tiles/allgemein/tipleGrandstandS.png",
	"W": "res://assets/2D-tiles/allgemein/tipleGrandstandW.png",
}
# Stapel 4/5: echtes 4er-Artwork (geschlossener Rechteck-Rahmen, welt-orientiert wie die anderen).
const TEX_STAND_QUAD = "res://assets/2D-tiles/allgemein/fullGrandstand.png"
const TEX_STAND_QUAD_PLACEHOLDER = "res://assets/2D-tiles/allgemein/tipleGrandstandN.png"
const STAND_QUAD_PLACEHOLDER_TINT = Color(0.45, 0.65, 1.0)   # Blaufärbung des Platzhalters
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
	# Kleber-/Slime-Belag (eigener Pixelart-Satz im Unterordner "glue", Dateipräfix "slime",
	# Geraden-Tippfehler "stright"). Orientierungen exakt wie oben (OW/NS, OS/SW/NW/NO).
	"glue_straight_OW":    "res://assets/2D-tiles/glue/slime_stright_OW.png",
	"glue_straight_NS":    "res://assets/2D-tiles/glue/slime_stright_NS.png",
	"glue_curve_OS":       "res://assets/2D-tiles/glue/slime_curve_OS.png",
	"glue_curve_SW":       "res://assets/2D-tiles/glue/slime_curve_SW.png",
	"glue_curve_NW":       "res://assets/2D-tiles/glue/slime_curve_NW.png",
	"glue_curve_NO":       "res://assets/2D-tiles/glue/slime_curve_NO.png",
	# Sandbelag (eigener Pixelart-Satz im Unterordner "sand", korrekte Schreibweise
	# "straight"/"curve"). Effekt/Preis wie Default – nur das Artwork unterscheidet sich.
	# Orientierungen exakt wie oben (OW/NS, OS/SW/NW/NO).
	"sand_straight_OW":    "res://assets/2D-tiles/sand/sand_straight_OW.png",
	"sand_straight_NS":    "res://assets/2D-tiles/sand/sand_straight_NS.png",
	"sand_curve_OS":       "res://assets/2D-tiles/sand/sand_curve_OS.png",
	"sand_curve_SW":       "res://assets/2D-tiles/sand/sand_curve_SW.png",
	"sand_curve_NW":       "res://assets/2D-tiles/sand/sand_curve_NW.png",
	"sand_curve_NO":       "res://assets/2D-tiles/sand/sand_curve_NO.png",
	# Wasserbelag (eigener Pixelart-Satz im Unterordner "wasser"). Effekt/Preis wie die anderen
	# Test-Beläge – nur das Artwork unterscheidet sich. Orientierungen exakt wie oben (OW/NS, OS/SW/NW/NO).
	"water_straight_OW":   "res://assets/2D-tiles/wasser/water_straight_OW.png",
	"water_straight_NS":   "res://assets/2D-tiles/wasser/water_straight_NS.png",
	"water_curve_OS":      "res://assets/2D-tiles/wasser/water_curve_OS.png",
	"water_curve_SW":      "res://assets/2D-tiles/wasser/water_curve_SW.png",
	"water_curve_NW":      "res://assets/2D-tiles/wasser/water_curve_NW.png",
	"water_curve_NO":      "res://assets/2D-tiles/wasser/water_curve_NO.png",
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


# Liefert das fertig arrangierte Tribuenen-GLB für eine Stapel-Anzahl (1..4; ab 4 → Stand4).
func stand_model(count: int) -> String:
	return MODEL_TRACK_STANDS[clampi(count, 1, MODEL_TRACK_STANDS.size()) - 1]


# Richtungsgebundenes Portal-Artwork (2D): open_dir = offene Einfahr-Seite (N/E/S/W),
# is_exit = Ausgangs-Rolle (gelb) statt Eingang/unbestimmt (blau). Fallback auf "E".
func portal_texture(open_dir: String, is_exit: bool) -> String:
	var tbl: Dictionary = TEX_PORTAL_YELLOW if is_exit else TEX_PORTAL_BLUE
	return tbl.get(open_dir, tbl.get("E", ""))


# ── Speicherung & Einstellungen ───────────────────────────────────────────────
const SETTINGS_FILE = "user://settings.cfg"
const SAVE_SLOT_FMT = "user://savegame_slot%d.dat"

func save_slot_path(slot: int) -> String:
	return SAVE_SLOT_FMT % slot
