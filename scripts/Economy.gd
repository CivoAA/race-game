extends Node
## Zentraler, persistenter Spielzustand: Währung + gekaufte Upgrades + 3 Track-Zustände.
## Wird als Autoload "Economy" geladen. Speichert in Slot-Dateien (user://savegame_slotN.dat).

const TRACK_COUNT = 3

const START_CURRENCY  = 0
# Umrechnung "Tempo"-Zahl (Shop, 25→150) → tatsächliche Auto-Geschwindigkeit (m/s).
# Basis-Tempo 25 · 0.1 = 2.5 m/s (bewusst langsam); Max-Tempo 150 · 0.1 = 15 m/s.
const SPEED_SCALE     = 0.1

# ── Upgrade-Definitionen ────────────────────────────────────────────────────────
# category: "general" oder "car" (car_* sind Vorlagen für car<idx>_<suffix>)
# Kosten pro Level = round(base_cost * growth^level)
# Effektwert pro Level = base + per_level * level
const UPGRADES = {
	# Tempo-ZAHL 25→150 (Anzeige). Tatsächliche Auto-Geschwindigkeit = Tempo · SPEED_SCALE
	# (get_car_speed), Basis also bewusst langsam. EINE Quelle für alle Strecken.
	# Tempo-Stufen 0..25: Tempo = 25 + 5·Level → 25 … 150 (gleicher Top-Speed wie zuvor, nur in
	# kleineren Schritten = deutlich langsamerer Tempo-Zuwachs). Preis unverändert (steigt steil).
	"speed": {
		"category": "general", "name": "Tempo (alle Autos)",
		"base_cost": 50, "growth": 3.0, "max_level": 25,
		"base": 25.0, "per_level": 5.0, "unit": " Tempo",
	},
	# Fahrzeit: eigene Sequenz (_drive_time_value, special-case in _effect_at): 15,20,25,30,
	# 40,50,60,90,120,150,… (base/per_level dort ignoriert). Bei 30 s ~1 Mio Kosten.
	"drive_time": {
		"category": "general", "name": "Fahrzeit",
		"base_cost": 1000, "growth": 5.6, "max_level": 12,
		"base": 30.0, "per_level": 15.0, "unit": "s",
	},
	# grid_size: aktuell NICHT im Shop (kommt später per Prestige) – Definition bleibt für die Getter.
	"grid_size": {
		"category": "hidden", "name": "Streckengröße",
		"base_cost": 100, "growth": 6.0, "max_level": 3,
		"base": 0.0, "per_level": 0.0, "unit": "",
	},
	"car_count": {
		"category": "general", "name": "Zusätzliches Auto",
		"base_cost": 1000000, "growth": 5.0, "max_level": 3,
		"base": 1.0, "per_level": 1.0, "unit": " Autos",
	},
	# End-Multiplikator & Tile-Bonus jetzt global (alle Autos), unter "Allgemeines".
	"endmult": {
		"category": "general", "name": "End-Multiplikator (alle Autos)",
		"base_cost": 500, "growth": 3.5, "max_level": 10,
		"base": 1.0, "per_level": 0.5, "unit": "×",
	},
	"tilebonus": {
		"category": "general", "name": "Tile-Bonus (+ je Feld, alle Autos)",
		"base_cost": 10, "growth": 3.0, "max_level": 14,
		"base": 0.0, "per_level": 0.5, "unit": " /Feld",
	},
	# Tile-Upgrades: zusätzlicher Reward je überfahrenem Feld dieses Typs (additiv, vor endmult).
	# Werden im Streckenteile-Shop an der jeweiligen Tile geupgradet (nicht in der allg. Liste).
	# Die Dreck-Upgrades nutzen eine eigene Wertereihe (_dirt_field_earn, special-case in
	# _effect_at); base/per_level werden dort ignoriert. Dreck-Gerade & -Kurve getrennt.
	# Dreck-Upgrades bewusst günstig & sanft skalierend → früh leicht hochzuziehen.
	"dirtstraightbonus": {
		"category": "tile", "name": "Dreck-Geraden-Ertrag (+ je Feld)",
		"base_cost": 25, "growth": 2.3, "max_level": 20,
		"base": 0.0, "per_level": 0.0, "unit": " /Dreck",
	},
	"dirtcurvebonus": {
		"category": "tile", "name": "Dreck-Kurven-Ertrag (+ je Feld)",
		"base_cost": 25, "growth": 2.3, "max_level": 20,
		"base": 0.0, "per_level": 0.0, "unit": " /Dreck",
	},
	"straightbonus": {
		"category": "tile", "name": "Geraden-Ertrag (+ je Gerade)",
		"base_cost": 200, "growth": 3.0, "max_level": 12,
		"base": 0.0, "per_level": 25.0, "unit": " /Gerade",
	},
	"curvebonus": {
		"category": "tile", "name": "Kurven-Ertrag (+ je Kurve)",
		"base_cost": 200, "growth": 3.0, "max_level": 12,
		"base": 0.0, "per_level": 25.0, "unit": " /Kurve",
	},
	# Eisgerade: gibt KEIN Geld, sondern macht das Auto auf den nächsten Feldern schneller.
	# base/per_level werden NICHT als Geld-Effekt genutzt – der Effekt ist special-cased über
	# get_ice_boost_levels()/get_ice_range() (Speed-Boost + Reichweite). max_level=15, damit die
	# Reichweiten-Stufen (5→4, 10→5, 15→6 Felder) sauber aufgehen.
	"icebonus": {
		"category": "tile", "name": "Eisgeraden-Boost (Speed je Feld)",
		"base_cost": 8000, "growth": 2.6, "max_level": 15,
		"base": 0.0, "per_level": 0.0, "unit": "",
	},
	# Steilwandkurve (Wall-Ride): Geld UND Speed-Boost skalieren mit dem Upgrade. Das Geld läuft
	# über base/per_level (get_effect → +Wert am Einfahrt-Feld, Schritt 1 des Schneeballs), der
	# Speed-Boost ist wie bei der Eisgerade special-cased (get_wall_*). max_level=15, damit die
	# Reichweiten-Stufen (5→4, 10→5, 15→6 Felder) sauber aufgehen.
	"wallbonus": {
		"category": "tile", "name": "Steilwandkurven-Boost (Geld + Speed)",
		"base_cost": 50000, "growth": 2.8, "max_level": 15,
		"base": 5000.0, "per_level": 2500.0, "unit": "",
	},
	# Rampen-Upgrade: additiver Ertrag je Rampe (RAMP_BASE_EARN ist der Grundwert obendrauf) UND
	# alle 5 Stufen +0.2 auf den Sprung-Multiplikator (Stufe 5 → ×2.2, 10 → ×2.4 …) via
	# get_ramp_jump_mult(). max_level bewusst durch 5 teilbar, damit die Mult-Stufen sauber aufgehen.
	"rampbonus": {
		"category": "tile", "name": "Rampen-Ertrag (+ je Rampe)",
		"base_cost": 10000, "growth": 3.0, "max_level": 15,
		"base": 0.0, "per_level": 200.0, "unit": " /Rampe",
	},
	# Looping-Upgrade: erhöht den Loop-Faktor um 0.2 je Stufe (base 2.0 → Stufe 10 = 4.0). Dieser
	# Faktor ist BEIDE Loop-Multiplikatoren zugleich: der eigene ×F UND der Faktor, mit dem jeder
	# andere Multiplikator des Feldes multipliziert wird (M·F). get_effect liefert direkt 2.0+0.2·Lvl.
	"loopbonus": {
		"category": "tile", "name": "Looping-Multiplikator (×)",
		"base_cost": 50000, "growth": 2.5, "max_level": 10,
		"base": 2.0, "per_level": 0.2, "unit": "",
	},
	# Portal-Upgrade: additiver Geld-Ertrag am Eingangs-Portal (kein Multiplikator). 25 Stufen.
	# Geld skaliert bewusst etwas STÄRKER als übliche Tiles (per_level = 60 % der Basis je Stufe),
	# die KOSTEN steigen normal (growth wie andere Tile-Upgrades). base = 25k Grundertrag.
	"portalbonus": {
		"category": "tile", "name": "Portal-Ertrag (+ je Durchgang)",
		"base_cost": 80000, "growth": 2.6, "max_level": 25,
		"base": 25000.0, "per_level": 15000.0, "unit": "",
	},
	# Tribünen-Upgrade: Multiplikator auf das/die Nachbarfeld(er) vor der Tribüne. base 2.5, +0.1/Stufe
	# (Stufe 15 → 4.0). get_effect liefert direkt 2.5+0.1·Lvl. Stack 5 verdoppelt den Wert (in get_stand_mult).
	"standbonus": {
		"category": "tile", "name": "Tribünen-Multiplikator (×)",
		"base_cost": 200000, "growth": 2.6, "max_level": 15,
		"base": 2.5, "per_level": 0.1, "unit": "",
	},
	# Bonusfelder: je Typ max. 3 – das Upgrade-Level = Anzahl dieser Felder (Lv1 schaltet frei,
	# Lv2 = zweites Feld, Lv3 = drittes). Kosten steigen idle-typisch steil.
	"bonus_plus5": {
		"category": "bonus", "name": "+5-Felder",
		"base_cost": 2000, "growth": 6.0, "max_level": 3,
		"base": 0.0, "per_level": 1.0, "unit": "",
	},
	"bonus_plus10": {
		"category": "bonus", "name": "+10-Felder",
		"base_cost": 4000, "growth": 8.0, "max_level": 3,
		"base": 0.0, "per_level": 1.0, "unit": "",
	},
	# ×1.5-Feld ist stark → deutlich teurer (×10 ggü. vorher).
	"bonus_mult15": {
		"category": "bonus", "name": "×1.5-Felder",
		"base_cost": 200000, "growth": 10.0, "max_level": 3,
		"base": 0.0, "per_level": 1.0, "unit": "",
	},
}

# Rampe: Grundertrag am ramp_start-Feld (geht als base in dessen Tile-Eintrag) und Basis-Sprung-
# Multiplikator (×2). Das Rampen-Upgrade (rampbonus) erhöht den additiven Ertrag pro Stufe und den
# Sprung-Multiplikator je 5 Stufen (get_ramp_jump_mult).
const RAMP_BASE_EARN = 450.0
const RAMP_JUMP_BASE = 2.0

# Looping: eigener Multiplikator ×F. Zusätzlich wird JEDER andere Multiplikator auf demselben Feld
# mit F multipliziert (M → M·F). F = get_loop_factor() = 2.0 + 0.2·loopbonus-Level (Stufe 10 → 4.0).
# Sofort am Feld verrechnet (Schritt 2 des Schneeballs), nicht am Lauf-Ende. LOOP_MULT = Basiswert.
const LOOP_MULT = 2.0

# Grid-Dimensionen pro grid_size-Level: 4×4 → 4×5 → 4×6 → 5×6
const GRID_STEPS = [
	Vector2i(4, 4),
	Vector2i(4, 5),
	Vector2i(4, 6),
	Vector2i(5, 6),
]

# ── Prestige ────────────────────────────────────────────────────────────────────
# „Formel als Gate": beim Prestige bekommt man floor(sqrt(prestige_earned / K)) Punkte (⭐).
# Der Prestige-Button ist erst aktiv, sobald das ≥ 1 ergibt. K ist die einzige Stellschraube
# für „Geld pro Punkt" – unabhängig vom Einkommens-Balancing.
# K = Geld für den 1. Punkt; n. Punkt braucht n²·K. Bei 100k „rastet" Prestige ein (1. Punkt),
# 2. Punkt bei 400k, 3. bei 900k – man muss also erst ein Stück spielen.
const PRESTIGE_K = 100000.0

# Tech-Baum: Knoten werden mit ⭐ bezahlt. Voraussetzung = der jeweils VORHERIGE Knoten muss
# mindestens 1× gekauft sein (prereq = {vorheriger: 1}). Man wird also NICHT zum Mehrfach-Leveln
# gezwungen – nur ein einziger Kauf schaltet den nächsten Knoten frei. „income" ist zusätzlich
# am billigsten. Kosten je Stufe = round(base_cost * growth^level), bezahlt in Prestige-Punkten.
# Reset-fest: Prestige-Fortschritt liegt in prestige_nodes (NICHT in upgrade_levels, das beim
# Prestige geleert wird). Daher leben grid/car/track-Boni hier, nicht im normalen Upgrade-Block.
const PRESTIGE_NODES = {
	# Globaler Einkommens-Multiplikator: Mult = 1 + Level (Lv1 ×2, Lv2 ×3, Lv3 ×4 …). Billig & viele
	# Stufen → der „Brot-und-Butter"-Knoten, in den die ersten Punkte fließen.
	"income": {
		"name": "×-Einkommen", "icon": "✖", "base_cost": 1, "growth": 2.0, "max_level": 25,
		"desc": "Multipliziert allen verdienten Lauf-Ertrag (×2, ×3, ×4 …).", "prereq": {},
	},
	# Streckengröße: identische Stufen wie GRID_STEPS (4×4 → 4×5 → 4×6 → 5×6). Teuer (nur 3 Stufen).
	"grid": {
		"name": "Streckengröße", "icon": "▦", "base_cost": 4, "growth": 4.0, "max_level": 3,
		"desc": "Vergrößert das Baufeld aller Strecken.", "prereq": {"income": 1},
	},
	# Unlocks behalten: einmaliger Kauf (max_level 1). Danach bleiben ALLE freigeschalteten
	# Streckenteile (Gerade/Kurve/Eis/Rampe) über den Prestige-Reset hinweg gratis nutzbar –
	# man zahlt die Freischalt-Gebühr nie wieder. Die Tile-UPGRADES bleiben Level 0 (werden
	# normal zurückgesetzt); nur die einmalige Freischaltung entfällt. Siehe is_tile_unlocked().
	"keep_unlocks": {
		"name": "Unlocks behalten", "icon": "🗝", "base_cost": 5, "growth": 1.0, "max_level": 1,
		"desc": "Freigeschaltete Streckenteile bleiben nach dem Prestige gratis (keine Freischalt-Gebühr mehr).",
		"prereq": {"grid": 1},
	},
	# Zusätzliche Autos – addiert sich auf das normale Auto-Upgrade.
	"car": {
		"name": "Extra-Auto", "icon": "🚗", "base_cost": 6, "growth": 5.0, "max_level": 3,
		"desc": "Je Stufe ein dauerhaft zusätzliches Auto.", "prereq": {"keep_unlocks": 1},
	},
	# Strecken-Freischaltung: Lv1 = Strecke 2, Lv2 = Strecke 3 (Strecke 1 ist immer offen).
	"track": {
		"name": "Extra-Strecke", "icon": "🏁", "base_cost": 8, "growth": 8.0, "max_level": 2,
		"desc": "Schaltet Strecke 2 und 3 frei (eine je Stufe).", "prereq": {"car": 1},
	},
	# Gratis-Straßen: mehrfach kaufbar. Je Stufe darf man FREE_ROADS_PER_LEVEL["straight"] Geraden
	# und ["curve"] Kurven gratis platzieren, BEVOR sie etwas kosten. Danach startet der Preis beim
	# ersten Preis (base_price·growth^0), nicht so, als hätte man schon welche platziert – siehe
	# get_free_tile_quota() + Main._tile_price (Preis um die Gratis-Menge versetzt). Da der Prestige
	# alle Strecken leert, erneuert sich das Gratis-Kontingent jede Prestige-Runde automatisch.
	"free_roads": {
		"name": "Gratis-Straßen", "icon": "🛣", "base_cost": 5, "growth": 2.0, "max_level": 10,
		"desc": "Je Stufe 2 Geraden und 4 Kurven gratis platzierbar, bevor sie etwas kosten.",
		"prereq": {"track": 1},
	},
	# End-Knoten: schaltet die Tribüne ÜBERHAUPT erst frei (15 ⭐, einmalig). Danach muss sie im
	# Shop trotzdem noch für Geld freigeschaltet werden (is_tile_unlocked + Unlock-Gate auf stand_unlock).
	"stand_unlock": {
		"name": "Tribüne", "icon": "🏟", "base_cost": 15, "growth": 1.0, "max_level": 1,
		"desc": "Schaltet die Tribüne frei (danach im Shop noch für Geld freischaltbar).",
		"prereq": {"free_roads": 1},
	},
}
# Reihenfolge im Tech-Baum (links → rechts).
const PRESTIGE_ORDER = ["income", "grid", "keep_unlocks", "car", "track", "free_roads", "stand_unlock"]
const PRESTIGE_TRACK_BASE = 1   # Strecke 1 ist immer offen; je „track"-Stufe eine weitere.

# Gratis platzierbare Default-Tiles je Stufe des „free_roads"-Knotens (siehe get_free_tile_quota).
const FREE_ROADS_PER_LEVEL = {"straight": 2, "curve": 4}

var _currency:     int        = START_CURRENCY
var upgrade_levels: Dictionary = {}
var track:          Array      = []   # gespeicherte Strecke des aktiven Tracks (Rückwärtskompatibilität)
var unlocked_tiles: Dictionary = {}   # freigeschaltete Shop-Tiles: key → true

# Kosmetik: Auto-Lackierung (Werkstatt). car_paint_on=false → Originaltextur (keine Umfärbung).
var car_paint_on:    bool  = false
var car_paint_color: Color = Color(0.85, 0.15, 0.12)

# Prestige-Zustand (überlebt den Prestige-Reset; nur „Neues Spiel"/reset_slot löscht ihn).
var prestige_points: int        = 0   # verfügbare ⭐
var prestige_earned: int        = 0   # seit dem letzten Prestige verdientes Geld (Basis für Punkte)
var prestige_nodes:  Dictionary = {}  # Tech-Baum-Knoten: id → Stufe
var _current_slot:  int        = 0
var _slot_name:     String     = ""

# ── Multi-Track-State ───────────────────────────────────────────────────────────
var _active_track: int = 0
var _tracks: Array = []   # TRACK_COUNT Einträge
var endless_mode: bool = false   # Kein Timer, Geld wird live gutgeschrieben
# Globale Einstellung (slot-unabhängig, in user://settings.cfg): blendet die Cheat-Buttons
# (Endlos-Modus ∞ und +1B ⭐) in der oberen Leiste ein/aus.
var cheat_mode: bool = false

signal run_ended(track_idx: int, earned: int)
# Eine (oder mehrere) Runde(n) wurden gutgeschrieben (Auto über die Startlinie) – Betrag = Summe.
signal lap_credited(track_idx: int, amount: int)
# Ein Shop-Tile wurde freigeschaltet (im Streckenteile-Shop) – Bau-Leiste aktualisiert sich daraufhin.
signal tile_unlocked(key: String)
# Ein anderer Speicherstand wurde geladen/zurückgesetzt – Slot-abhängige UI (z. B. der
# Streckenteile-Shop im GlobalModal-Autoload) muss sich daraufhin neu aufbauen.
signal slot_changed(slot: int)
# Ein Upgrade wurde gekauft – die angeschaute 3D-Strecke setzt ihre Autos daraufhin neu auf
# (Tempo/Anzahl/Reward live). Hintergrund-Strecken übernehmen es beim nächsten Ansehen.
signal upgrade_purchased(id: String)
# Prestige-Punkte oder Tech-Baum-Knoten haben sich geändert (Kauf oder ausgeführtes Prestige).
signal prestige_changed
# Auto-Lackierung wurde in der Werkstatt geändert → 3D-Autos färben sich live um.
signal car_paint_changed
# Cheat-Modus (globale Einstellung) wurde umgeschaltet → HUD blendet die Cheat-Buttons ein/aus.
signal cheat_mode_changed


# ── Freischaltbare Shop-Tiles ───────────────────────────────────────────────────
# Zentrale Freischaltkosten (gemeinsame Quelle für Bau-Shop in Main.gd und den
# Streckenteile-Tab in GlobalModal.gd). Main.SHOP_ITEMS spiegelt diese Werte.
const TILE_UNLOCK_COST = {
	"def_straight": 15000,
	"def_curve":    30000,
	"ice":          150000,
	"ramp":         500000,
	"wall":         2000000,
	"loop":         1000000,
	"portal":       5000000,
	"stand":        50000000,
}

# ── Eisgerade ───────────────────────────────────────────────────────────────────
# Gibt kein Geld, sondern legt auf die nächsten Felder einen ABSOLUTEN Tempo-Bonus (so viel
# schneller wie N Tempo-Stufen, unabhängig vom aktuellen Tempo). Basis +1 Tempo-Stufe, je
# Upgrade-Stufe +0.5; Reichweite 3 Folge-Felder, +1 je 5 Upgrade-Stufen (5→4, 10→5, 15→6).
const ICE_BASE_BOOST_LEVELS = 1.0
const ICE_PER_LEVEL_BOOST   = 0.5
const ICE_BASE_RANGE        = 3

# ── Steilwandkurve (Wall-Ride) ──────────────────────────────────────────────────
# Zwei vertikal gestapelte Kacheln = eine 180°-Haarnadel an einer Steilwand. Beim Rausfahren
# bekommen die nächsten Folge-Felder einen absoluten Tempo-Bonus (wie die Eisgerade), Basis
# +2 Tempo-Stufen, je Upgrade-Stufe +0.5; Reichweite 3 Folge-Felder, +1 je 5 Upgrade-Stufen.
# Das Geld (Grundertrag am Einfahrt-Feld) läuft über das wallbonus-Upgrade (base/per_level).
const WALL_BASE_BOOST_LEVELS = 2.0
const WALL_PER_LEVEL_BOOST   = 0.5
const WALL_BASE_RANGE        = 3


func get_tile_unlock_cost(key: String) -> int:
	return int(TILE_UNLOCK_COST.get(key, 0))


func is_tile_unlocked(key: String) -> bool:
	if key == "" or unlocked_tiles.get(key, false):
		return true
	# Prestige-Perk „Unlocks behalten": ist er gekauft, gelten ALLE regulär freischaltbaren
	# Streckenteile (def_straight/def_curve/ice/ramp) dauerhaft als frei – auch nach dem Reset,
	# ohne dass sie in unlocked_tiles stehen (das wird beim Prestige geleert). AUSNAHME: die Tribüne
	# muss immer separat im Shop für Geld freigeschaltet werden (zusätzlich zum Prestige-Knoten).
	if get_prestige_node_level("keep_unlocks") >= 1 and TILE_UNLOCK_COST.has(key) and key != "stand":
		return true
	return false


# Die Tribüne darf im Shop NUR für Geld freigeschaltet werden, wenn der Prestige-End-Knoten
# „stand_unlock" gekauft ist. Main/GlobalModal fragen das vor dem Freischalten ab.
func can_unlock_tile(key: String) -> bool:
	if key == "stand":
		return get_prestige_node_level("stand_unlock") >= 1
	return true


# Anzahl gratis platzierbarer Default-Tiles dieses Typs (straight/curve) durch den Prestige-Knoten
# „free_roads": Stufe × FREE_ROADS_PER_LEVEL. Andere Typen haben kein Gratis-Kontingent (→ 0).
# Wirkung im Preis: Main._tile_price versetzt den Idle-Preis um diese Menge (die ersten N Tiles
# gratis, danach Preis ab base_price). Reset-fest, da der Knoten den Prestige überlebt.
func get_free_tile_quota(type: String) -> int:
	return int(FREE_ROADS_PER_LEVEL.get(type, 0)) * get_prestige_node_level("free_roads")


func unlock_tile(key: String) -> void:
	if key == "":
		return
	unlocked_tiles[key] = true
	save_game()
	tile_unlocked.emit(key)


func _ready() -> void:
	_load_settings()
	_init_tracks()


# ── Globale Einstellungen (slot-unabhängig, user://settings.cfg) ────────────────

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Paths.SETTINGS_FILE)   # fehlende Datei → Defaults
	cheat_mode = bool(cfg.get_value("cheats", "enabled", false))


# Cheat-Modus live anwenden und Hörer benachrichtigen (HUD blendet die Cheat-Buttons um).
# Die Persistenz in user://settings.cfg erfolgt über den Einstellungen-Speicherfluss im
# Pause-Menü (PauseMenu) – hier wird bewusst NICHT auf die Platte geschrieben.
# Beim Ausschalten wird ein evtl. laufender Endlos-Modus beendet, da sein Button verschwindet.
func apply_cheat_mode(val: bool) -> void:
	if cheat_mode == val:
		return
	cheat_mode = val
	if not cheat_mode:
		endless_mode = false
	cheat_mode_changed.emit()


func _init_tracks() -> void:
	_tracks.clear()
	for _i in TRACK_COUNT:
		_tracks.append({
			"grid":            [],
			"run_active":      false,
			"run_timer":       0.0,
			"run_duration":    0.0,   # Gesamt-Fahrzeit dieses Runs (für Restzeit→Position)
			"run_elapsed":     0.0,   # monoton steigende Fahrzeit (Basis für Runden & Position)
			"run_cars":        [],    # je Auto {lap_time, reward, start_delay} – aus 3D gesetzt
			"run_earned":      0,     # bisher in diesem Run gutgeschriebener Gesamtbetrag
			"run_credited":    0,     # davon bereits der Währung gutgeschrieben
			"run_credited_laps": 0,   # Anzahl bereits gutgeschriebener Runden (über alle Autos)
			"pending_summary": false,
			"last_earned":     0,
		})


func _process(delta: float) -> void:
	for i in TRACK_COUNT:
		if not _tracks[i]["run_active"]:
			continue
		# Fahrzeit läuft weiter – egal ob 2D- oder 3D-Ansicht offen ist.
		_tracks[i]["run_elapsed"] = float(_tracks[i]["run_elapsed"]) + delta
		# Geld kommt in Runden-Häppchen: immer wenn ein Auto (rechnerisch) die Startlinie
		# überquert. Das gilt im Hintergrund (2D) genauso wie sichtbar in der 3D-Ansicht.
		_credit_laps(i)
		if endless_mode:
			continue   # Endlos-Modus: kein Timer
		_tracks[i]["run_timer"] -= delta
		if _tracks[i]["run_timer"] <= 0.0:
			_tracks[i]["run_timer"]       = 0.0
			_tracks[i]["run_active"]      = false
			_credit_laps(i)               # letzte fällige Runde(n) noch gutschreiben
			var earned: int = int(_tracks[i]["run_credited"])
			_tracks[i]["pending_summary"] = true
			_tracks[i]["last_earned"]     = earned
			save_game()
			emit_signal("run_ended", i, earned)


# Schreibt fällige Runden gut. Aus der verstrichenen Fahrzeit + Auto-Parametern (lap_time/
# start_delay) ergibt sich die Gesamtzahl überfahrener Startlinien. Bereits abgerechnete Runden
# zählt run_credited_laps (monoton) → robust gegen run_cars-Neuaufbau bei 2D↔3D-Wechsel und
# keine Doppelzählung. Der Reward je Runde wird NICHT eingefroren, sondern bei jeder Gutschrift
# aus den AKTUELLEN Upgrade-Werten (tilebonus/endmult) berechnet → Geld-Upgrades wirken ab der
# nächsten gutgeschriebenen Runde auch auf laufende Läufe (kein rückwirkendes Geld für schon
# gezählte Runden). Die Tile-Reihenfolge je Auto (tiles) ist streckenfix und kommt aus World3D.
func _credit_laps(i: int) -> void:
	var cars: Array = _tracks[i].get("run_cars", [])
	if cars.is_empty():
		return
	var laps_total := _laps_total(i)
	var credited_laps := int(_tracks[i].get("run_credited_laps", 0))
	var new_laps := laps_total - credited_laps
	if new_laps <= 0:
		return
	var gain := new_laps * _current_lap_reward(cars)
	_currency += gain
	prestige_earned += gain   # Basis für die nächste Prestige-Punkte-Ausschüttung
	_tracks[i]["run_credited_laps"] = laps_total
	_tracks[i]["run_credited"] = int(_tracks[i]["run_credited"]) + gain
	_tracks[i]["run_earned"]   = int(_tracks[i]["run_credited"])
	emit_signal("lap_credited", i, gain)


# Wendet ein Tempo-Upgrade auf alle LAUFENDEN Runden an (auch im Hintergrund), ohne dass man
# zuschauen muss: lap_time = lap_k / aktuelles_Tempo neu berechnen und den Runden-Zähler
# snappen → kein rückwirkendes Geld, das neue Tempo zählt ab der nächsten Runde. lap_k ist
# tempo-unabhängig (lap_time·speed). Geld-Upgrades (endmult/tilebonus/tile) wirken ohnehin live
# über _current_lap_reward; hier geht es nur um die geänderte Rundenzeit durch das Tempo.
func _apply_speed_to_active_runs() -> void:
	var sp := get_car_speed(0)
	if sp <= 0.0:
		return
	for i in TRACK_COUNT:
		if not _tracks[i]["run_active"]:
			continue
		for car in _tracks[i].get("run_cars", []):
			var lk := float(car.get("lap_k", 0.0))
			if lk > 0.0:
				car["lap_time"] = lk / sp
		_tracks[i]["run_credited_laps"] = _laps_total(i)


# Gesamtzahl überfahrener Startlinien (über alle Autos) bei der aktuellen Fahrzeit.
func _laps_total(i: int) -> int:
	var cars: Array = _tracks[i].get("run_cars", [])
	var elapsed := float(_tracks[i]["run_elapsed"])
	var total := 0
	for car in cars:
		var lt := float(car.get("lap_time", 0.0))
		if lt <= 0.0:
			continue
		total += int(floor(maxf(0.0, elapsed - float(car.get("start_delay", 0.0))) / lt))
	return total


# ╔══════════════════════════════════════════════════════════════════════════════════════════╗
# ║ VERBINDLICHE RECHEN-REGEL FÜR DEN RUNDEN-ERTRAG (gilt für ALLE zukünftigen Änderungen!)    ║
# ║                                                                                            ║
# ║ Der Ertrag einer Runde ist ein fortlaufender "Schneeball" über die Felder in FAHRREIHEN-   ║
# ║ FOLGE. Pro Feld gilt strikt diese Reihenfolge:                                             ║
# ║   1. ERST ALLE +Werte dieses Feldes addieren (Grundertrag + Tile-Bonus + +5/+10-Feld +     ║
# ║      tile-spezifische Upgrades …).                                                         ║
# ║   2. DANN ALLE ×Werte dieses Feldes anwenden (Premium ×1.2, ×1.5-Feld, Rampen-/Sprung ×2 …)║
# ║      auf die GESAMTE bisher angesammelte Summe.                                            ║
# ║   → running = (running + Σ aller +Werte) · (Produkt aller ×Werte)                          ║
# ║ Ganz zum Schluss EINMAL auf die ganze Runde: × End-Multiplikator × Prestige.               ║
# ║ Die Reihenfolge der Felder zählt also (frühe +Werte werden von späteren ×Werten mitgezo-   ║
# ║ gen; späte ×Werte multiplizieren eine größere Summe).                                       ║
# ║                                                                                            ║
# ║ Jeder NEUE Bonus/jedes neue Upgrade muss in genau dieses Schema eingeordnet werden:        ║
# ║ ist es ein "+" (Schritt 1) oder ein "×" (Schritt 2), und auf WELCHE Felder wirkt es?       ║
# ║ → Wenn das nicht eindeutig klar ist, NICHT raten – beim Nutzer rückfragen, BEVOR es        ║
# ║   eingebaut wird (ob +/×, auf welchen Feldern, und an welcher Stelle im Schneeball).        ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════╝
#
# Quelle der Felder: car["tiles"] (streckenfixe Tile-Reihenfolge aus CarController). Konkrete
# Zuordnung in diesem Code: base = Grundertrag, tile-Bonus/tile-spezifische Upgrades + bonus_points
# = Schritt 1; fixed_mult (Premium ×1.2), bonus_mult (×1.5-Feld), jump_mult (kind=="ramp"/is_jump)
# = Schritt 2. Alles aus den AKTUELLEN Upgrade-Werten → wirkt live, auch auf Hintergrund-Strecken.
# Alle Autos einer Strecke teilen das Layout → einheitlicher Reward; erstes gültiges Auto genügt.
func _current_lap_reward(cars: Array) -> int:
	for car in cars:
		if float(car.get("lap_time", 0.0)) <= 0.0:
			continue
		var tiles: Array = car.get("tiles", [])
		if tiles.is_empty():
			continue
		var tilebonus   := get_car_tile_bonus(0)
		var jump_mult   := get_ramp_jump_mult()
		var straight_b  := get_effect("straightbonus")
		var curve_b     := get_effect("curvebonus")
		var dstraight_b := get_effect("dirtstraightbonus")
		var dcurve_b    := get_effect("dirtcurvebonus")
		var ramp_b      := get_effect("rampbonus")
		var wall_b      := get_wall_earn()
		var portal_b    := get_portal_earn()
		var running := 0.0
		for tile in tiles:
			# 1. Alle +Werte dieses Feldes.
			var add: float = float(tile.get("base", 0.0)) + tilebonus + float(tile.get("bonus_points", 0.0))
			match String(tile.get("kind", "plain")):
				"pstraight": add += straight_b
				"pcurve":    add += curve_b
				"dstraight": add += dstraight_b
				"dcurve":    add += dcurve_b
				"ramp":      add += ramp_b
				"wall":      add += wall_b
				"portal":    add += portal_b
			# 2. Alle ×Werte dieses Feldes.
			var fm: float = float(tile.get("fixed_mult", 1.0))
			var bm: float = float(tile.get("bonus_mult", 1.0))
			var has_jump: bool = String(tile.get("kind", "")) == "ramp" or bool(tile.get("is_jump", false))
			var m: float
			if bool(tile.get("is_loop", false)):
				# Looping: eigener ×F UND jeder ANDERE Multiplikator dieses Feldes mit F multipliziert
				# (M·F). F = get_loop_factor() (Basis 2.0, +0.2 je loopbonus-Stufe). Beispiel auf
				# Rampen-Sprungfeld bei F=2: ((X+0)·(2·2))·2. Auf ×1.5-Feld: (X·(1.5·2))·2.
				var lf := get_loop_factor()
				m = lf
				if fm != 1.0: m *= fm * lf
				if bm != 1.0: m *= bm * lf
				if has_jump:  m *= jump_mult * lf
			else:
				m = fm * bm
				if has_jump:
					m *= jump_mult
			running = (running + add) * m
		# End-Multiplikator und globaler Prestige-Multiplikator zum Schluss (live auf allen Strecken).
		return int(round(running * get_car_end_mult(0) * get_prestige_mult()))
	return 0


# ── Multi-Track API ─────────────────────────────────────────────────────────────

func get_active_track() -> int:
	return _active_track


func set_active_track(idx: int) -> void:
	_active_track = clampi(idx, 0, TRACK_COUNT - 1)


func get_track_grid(track_idx: int) -> Array:
	if track_idx < 0 or track_idx >= _tracks.size():
		return []
	return _tracks[track_idx]["grid"]


func set_track_grid(track_idx: int, grid: Array) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["grid"] = grid
	# Rückwärtskompatibilität: aktiver Track → track-Feld synchron halten
	if track_idx == _active_track:
		track = grid


func is_run_active(track_idx: int) -> bool:
	if track_idx < 0 or track_idx >= _tracks.size():
		return false
	return _tracks[track_idx]["run_active"]


func get_run_time_left(track_idx: int) -> float:
	if track_idx < 0 or track_idx >= _tracks.size():
		return 0.0
	return _tracks[track_idx]["run_timer"]


func start_run(track_idx: int) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["run_active"]   = true
	_tracks[track_idx]["run_timer"]    = get_drive_time()
	_tracks[track_idx]["run_duration"] = get_drive_time()
	_tracks[track_idx]["run_elapsed"]  = 0.0
	_tracks[track_idx]["run_cars"]     = []
	_tracks[track_idx]["run_earned"]   = 0
	_tracks[track_idx]["run_credited"] = 0
	_tracks[track_idx]["run_credited_laps"] = 0


# Bisher verstrichene Fahrzeit dieses Runs (für die Rückrechnung der Auto-Position).
func get_run_elapsed(track_idx: int) -> float:
	if track_idx < 0 or track_idx >= _tracks.size():
		return 0.0
	return float(_tracks[track_idx].get("run_elapsed", 0.0))


# Auto-Parameter für die Hintergrund-Simulation setzen (von World3D beim Start/Respawn der Autos).
# cars: Array von {lap_time, lap_k, tiles, start_delay} – tiles = streckenfixe Tile-Reihenfolge,
# aus der _current_lap_reward den Runden-Ertrag live faltet.
func set_run_cars(track_idx: int, cars: Array) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["run_cars"] = cars
	# lap_time/Autozahl können sich geändert haben (Tempo-/Auto-Upgrade beim Live-Respawn oder
	# beim Wieder-Betreten der 3D-Ansicht). Bereits gezählte Runden NICHT rückwirkend neu
	# bewerten: Zähler auf den aktuellen Stand snappen → nur künftige Runden zählen (mit neuem
	# lap_time/Reward). Im Normalfall (gleiches lap_time) ist das ein No-Op.
	_tracks[track_idx]["run_credited_laps"] = _laps_total(track_idx)


func stop_run(track_idx: int) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["run_active"] = false


func get_run_earned(track_idx: int) -> int:
	if track_idx < 0 or track_idx >= _tracks.size():
		return 0
	return int(_tracks[track_idx]["run_earned"])


func has_pending_summary(track_idx: int) -> bool:
	if track_idx < 0 or track_idx >= _tracks.size():
		return false
	return bool(_tracks[track_idx].get("pending_summary", false))


func get_last_earned(track_idx: int) -> int:
	if track_idx < 0 or track_idx >= _tracks.size():
		return 0
	return int(_tracks[track_idx].get("last_earned", 0))


func clear_pending_summary(track_idx: int) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["pending_summary"] = false
	_tracks[track_idx]["last_earned"]     = 0


# ── Slot-Management ────────────────────────────────────────────────────────────

func get_save_path(slot: int) -> String:
	return Paths.save_slot_path(slot)


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(get_save_path(slot))


func get_slot_info(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var f = FileAccess.open(get_save_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var txt = f.get_as_text()
	f.close()
	var data = str_to_var(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return {
		"currency":  int(data.get("currency", 0)),
		"timestamp": String(data.get("timestamp", "")),
		"name":      String(data.get("name", "")),
	}


func set_active_slot(slot: int) -> void:
	_current_slot = slot


func get_active_slot() -> int:
	return _current_slot


# ── Währung ─────────────────────────────────────────────────────────────────────

func get_currency() -> int:
	return _currency


func spend(amount: int) -> bool:
	if _currency < amount:
		return false
	_currency -= amount
	save_game()
	return true


func add(amount: int) -> void:
	_currency += amount
	save_game()


func add_silent(amount: int) -> void:
	_currency += amount  # Kein sofortiges Speichern (z.B. per Runde)


# ── Upgrade-Abfragen ──────────────────────────────────────────────────────────

func get_upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


func _def_for(id: String) -> Dictionary:
	if UPGRADES.has(id):
		return UPGRADES[id]
	return {}


# Effektwert (base + per_level * level) eines Upgrades bei gegebenem Level.
func _effect_at(id: String, level: int) -> float:
	# Dreck-Ertrag folgt einer eigenen, beschleunigenden Wertereihe (Bonus = Feldertrag − 1,
	# da Dreck-Grundertrag = 1). Per-Feld-Ertrag: 1,2,3,5,7,9,12,15,…
	if id == "dirtstraightbonus" or id == "dirtcurvebonus":
		return float(_dirt_field_earn(level) - 1)
	# Fahrzeit: eigene Stufen-Sequenz (10,15,…,30,40,…,60,90,…).
	if id == "drive_time":
		return float(_drive_time_value(level))
	var d = _def_for(id)
	if d.is_empty():
		return 0.0
	return float(d["base"]) + float(d["per_level"]) * level


# Fahrzeit (s) bei Upgrade-Stufe `level`: 15,20,25,30,40,50,60,90,120,150,…
# Bis 30 s in 5er-Schritten, bis 60 s in 10er-Schritten, danach in 30er-Schritten.
func _drive_time_value(level: int) -> int:
	var t := 15
	for _l in range(maxi(0, level)):
		if t < 30:
			t += 5
		elif t < 60:
			t += 10
		else:
			t += 30
	return t


# Ertrag eines Dreck-Felds bei Upgrade-Stufe `level`: 1,2,3,5,7,9,12,15,18,21,25,…
# Regel: Inkrement k wird (k+1)-mal angewandt (zwei +1, drei +2, vier +3, …).
func _dirt_field_earn(level: int) -> int:
	var total := 1
	var inc   := 1
	var steps := 0
	for _l in range(maxi(0, level)):
		total += inc
		steps += 1
		if steps >= inc + 1:
			steps = 0
			inc  += 1
	return total


func get_upgrade_cost(id: String) -> int:
	var d = _def_for(id)
	if d.is_empty():
		return 0
	var level = get_upgrade_level(id)
	return int(round(float(d["base_cost"]) * pow(float(d["growth"]), level)))


func is_maxed(id: String) -> bool:
	var d = _def_for(id)
	if d.is_empty():
		return true
	return get_upgrade_level(id) >= int(d["max_level"])


func can_buy(id: String) -> bool:
	return not is_maxed(id) and _currency >= get_upgrade_cost(id)


func buy_upgrade(id: String) -> bool:
	if not can_buy(id):
		return false
	_currency -= get_upgrade_cost(id)
	upgrade_levels[id] = get_upgrade_level(id) + 1
	save_game()
	# Tempo-Upgrade sofort auf alle laufenden Runden anwenden (auch Hintergrund), future-only.
	if id == "speed":
		_apply_speed_to_active_runs()
	emit_signal("upgrade_purchased", id)
	return true


# ── Anzeige-Helfer (für das Upgrade-Menü) ──────────────────────────────────────

func get_upgrade_name(id: String) -> String:
	return String(_def_for(id).get("name", id))


func get_upgrade_unit(id: String) -> String:
	return String(_def_for(id).get("unit", ""))


func get_max_level(id: String) -> int:
	return int(_def_for(id).get("max_level", 0))


# Effektwert bei aktuellem (level < 0) oder angegebenem Level.
func get_effect(id: String, level: int = -1) -> float:
	if level < 0:
		level = get_upgrade_level(id)
	return _effect_at(id, level)


# Lesbarer Effekt-Text für eine bestimmte Stufe (Sonderfälle: grid_size, car_count).
func effect_text(id: String, level: int) -> String:
	if id.begins_with("bonus_"):
		if level <= 0:
			return "🔒 gesperrt"
		return "%d Feld" % level if level == 1 else "%d Felder" % level
	if id == "grid_size":
		var lv = clampi(level, 0, GRID_STEPS.size() - 1)
		return "%d×%d" % [GRID_STEPS[lv].x, GRID_STEPS[lv].y]
	if id == "car_count":
		return "%d Autos" % (1 + level)
	# Eisgerade: kein Geld-Effekt → Speed-Boost (Tempo-Stufen) + Reichweite zeigen.
	if id == "icebonus":
		return "+%.1f Lvl · %d Felder" % [get_ice_boost_levels(level), get_ice_range(level)]
	# Steilwandkurve: Geld-Grundertrag + Speed-Boost (Tempo-Stufen) + Reichweite.
	if id == "wallbonus":
		return "+%s 💰 · +%.1f Lvl · %d Felder" % [format_currency(get_wall_earn(level)), get_wall_boost_levels(level), get_wall_range(level)]
	# Looping: eigener ×F und Faktor F auf alle anderen Multiplikatoren des Feldes.
	if id == "loopbonus":
		return "×%.1f · andere ×%.1f" % [get_loop_factor(level), get_loop_factor(level)]
	# Portal: additiver Geld-Ertrag je Durchgang (kein Multiplikator).
	if id == "portalbonus":
		return "+%s 💰 /Durchgang" % format_currency(get_portal_earn(level))
	# Tribüne: Multiplikator auf das/die Nachbarfeld(er).
	if id == "standbonus":
		return "×%.1f /Nachbarfeld" % get_effect("standbonus", level)
	var v = _effect_at(id, level)
	var unit = get_upgrade_unit(id)
	if id == "endmult":
		return "×%.2f" % v
	# Ganzzahlig ohne Nachkommastellen, sonst eine Stelle
	if absf(v - round(v)) < 0.001:
		return "%d%s" % [int(round(v)), unit]
	return "%.1f%s" % [v, unit]


# ── Zahl-Formatierung (Idle-Stil: 1.23K, 4.56M, … sonst wissenschaftlich) ──────

const _CURR_SUFFIX = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

func format_currency(value) -> String:
	var v = float(value)
	var sign_str = "-" if v < 0.0 else ""
	v = absf(v)
	if v < 1000.0:
		return sign_str + str(int(round(v)))
	var tier = int(floor(log(v) / log(1000.0)))
	if tier >= 1 and tier < _CURR_SUFFIX.size():
		var scaled = v / pow(1000.0, tier)
		return sign_str + _trim_num(scaled) + _CURR_SUFFIX[tier]
	# Sehr groß → wissenschaftliche Notation (z. B. 1.23e40)
	var exp = int(floor(log(v) / log(10.0)))
	var mant = v / pow(10.0, exp)
	return sign_str + ("%.2fe%d" % [mant, exp])


# Zahl mit bis zu 2 Nachkommastellen, ohne überflüssige Nullen ("12.30"→"12.3", "5.00"→"5").
func _trim_num(x: float) -> String:
	var s = "%.2f" % x
	if s.find(".") >= 0:
		while s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s


# ── Abgeleitete Spielwerte ──────────────────────────────────────────────────────

func get_drive_time() -> float:
	return _effect_at("drive_time", get_upgrade_level("drive_time"))


# Streckengröße kommt jetzt aus dem Prestige-Tech-Baum (reset-fest), nicht mehr aus upgrade_levels.
func get_grid_rows() -> int:
	return GRID_STEPS[clampi(get_prestige_node_level("grid"), 0, GRID_STEPS.size() - 1)].x


func get_grid_cols() -> int:
	return GRID_STEPS[clampi(get_prestige_node_level("grid"), 0, GRID_STEPS.size() - 1)].y


# Autos = 1 + normales Auto-Upgrade (reset-bar) + Prestige-Extra-Autos (reset-fest).
func get_car_count() -> int:
	return 1 + get_upgrade_level("car_count") + get_prestige_node_level("car")


# Freigeschaltete Strecken = Basis + Prestige-Knoten „track" (Obergrenze = TRACK_COUNT-Kapazität).
func get_unlocked_tracks() -> int:
	return clampi(PRESTIGE_TRACK_BASE + get_prestige_node_level("track"), 1, TRACK_COUNT)


# Tempo/End-Mult/Tile-Bonus sind jetzt global (gelten für alle Autos gleich).
# Tatsächliche Geschwindigkeit = Tempo-Zahl · SPEED_SCALE. EINZIGE Geschwindigkeitsquelle für
# alle Strecken (lap_time/lap_k/Position leiten sich daraus ab → keine Multi-Strecken-Probleme).
func get_car_speed(_i: int) -> float:
	return _effect_at("speed", get_upgrade_level("speed")) * SPEED_SCALE


func get_car_end_mult(_i: int) -> float:
	return _effect_at("endmult", get_upgrade_level("endmult"))


func get_car_tile_bonus(_i: int) -> float:
	return _effect_at("tilebonus", get_upgrade_level("tilebonus"))


# Gesamter Ertrag pro Rampe (Grundwert + additiver Anteil des Rampen-Upgrades). Für Anzeige.
func get_ramp_earn() -> float:
	return RAMP_BASE_EARN + get_effect("rampbonus")


# Sprung-Multiplikator für das übersprungene Kreuzungs-Feld: Basis ×2, je 5 Stufen des
# Rampen-Upgrades +0.2 (Stufe 5 → ×2.2, 10 → ×2.4 …).
func get_ramp_jump_mult() -> float:
	return RAMP_JUMP_BASE + 0.2 * float(get_upgrade_level("rampbonus") / 5)


# Speed-Boost einer Eisgerade in „Tempo-Stufen": Basis 1.0 + 0.5 je Upgrade-Stufe.
func get_ice_boost_levels(level: int = -1) -> float:
	if level < 0:
		level = get_upgrade_level("icebonus")
	return ICE_BASE_BOOST_LEVELS + ICE_PER_LEVEL_BOOST * level


# Absoluter Geschwindigkeits-Bonus (m/s), den eine Eisgerade auf jedes betroffene Folge-Feld
# legt: so viel schneller wie N Tempo-Stufen (1 Stufe = speed.per_level · SPEED_SCALE m/s),
# bewusst UNABHÄNGIG vom aktuellen Tempo. CarController addiert das auf die Segment-Tempi der
# nächsten get_ice_range() Felder → kürzere lap_time → mehr Runden (indirekt mehr Geld).
func get_ice_speed_bonus(level: int = -1) -> float:
	return get_ice_boost_levels(level) * float(UPGRADES["speed"]["per_level"]) * SPEED_SCALE


# Reichweite einer Eisgerade: 3 Folge-Felder, +1 je 5 Upgrade-Stufen (5→4, 10→5, 15→6).
func get_ice_range(level: int = -1) -> int:
	if level < 0:
		level = get_upgrade_level("icebonus")
	return ICE_BASE_RANGE + int(level / 5)


# ── Steilwandkurve (Wall-Ride) ──────────────────────────────────────────────────

# Geld-Grundertrag der Steilwandkurve (am Einfahrt-Feld, additiv = Schritt 1 des Schneeballs):
# base 5000 + per_level je Upgrade-Stufe. Live über das wallbonus-Upgrade.
func get_wall_earn(level: int = -1) -> float:
	return get_effect("wallbonus", level)


# Speed-Boost einer Steilwandkurve in „Tempo-Stufen": Basis 2.0 + 0.5 je Upgrade-Stufe.
func get_wall_boost_levels(level: int = -1) -> float:
	if level < 0:
		level = get_upgrade_level("wallbonus")
	return WALL_BASE_BOOST_LEVELS + WALL_PER_LEVEL_BOOST * level


# Absoluter Geschwindigkeits-Bonus (m/s) auf die Folge-Felder beim Rausfahren – analog zur
# Eisgerade „so viel schneller wie N Tempo-Stufen", unabhängig vom aktuellen Tempo.
func get_wall_speed_bonus(level: int = -1) -> float:
	return get_wall_boost_levels(level) * float(UPGRADES["speed"]["per_level"]) * SPEED_SCALE


# Reichweite der Steilwandkurve: 3 Folge-Felder, +1 je 5 Upgrade-Stufen (5→4, 10→5, 15→6).
func get_wall_range(level: int = -1) -> int:
	if level < 0:
		level = get_upgrade_level("wallbonus")
	return WALL_BASE_RANGE + int(level / 5)


# Looping-Faktor F = 2.0 + 0.2·loopbonus-Level. Gilt für BEIDE Loop-Multiplikatoren (eigener ×F
# und der Faktor, mit dem jeder andere Feld-Multiplikator multipliziert wird).
func get_loop_factor(level: int = -1) -> float:
	return get_effect("loopbonus", level)


# Portal-Ertrag (additiv, kein Multiplikator) am Eingangs-Portal: base 25k + per_level je Stufe.
func get_portal_earn(level: int = -1) -> float:
	return get_effect("portalbonus", level)


# Tribünen-Multiplikator für EIN Nachbarfeld: base 2.5 + 0.1·Level. Ab Stack 5 verdoppelt.
func get_stand_mult(stack: int = 1, level: int = -1) -> float:
	var m := get_effect("standbonus", level)
	if stack >= 5:
		m *= 2.0
	return m


# ── Prestige ────────────────────────────────────────────────────────────────────

func get_prestige_points() -> int:
	return prestige_points


# Debug/Cheat: Prestige-Punkte direkt gutschreiben (für Test-Buttons). Speichert + meldet Änderung.
func add_prestige_points(n: int) -> void:
	prestige_points += n
	save_game()
	prestige_changed.emit()


func get_prestige_earned() -> int:
	return prestige_earned


func _prestige_def(id: String) -> Dictionary:
	return PRESTIGE_NODES.get(id, {})


func get_prestige_node_level(id: String) -> int:
	return int(prestige_nodes.get(id, 0))


func get_prestige_node_max(id: String) -> int:
	return int(_prestige_def(id).get("max_level", 0))


func is_prestige_node_maxed(id: String) -> bool:
	return get_prestige_node_level(id) >= get_prestige_node_max(id)


func is_prestige_node_coming(id: String) -> bool:
	return bool(_prestige_def(id).get("coming", false))


# Kosten der nächsten Stufe in ⭐ = round(base_cost · growth^level).
func get_prestige_node_cost(id: String) -> int:
	var d := _prestige_def(id)
	if d.is_empty():
		return 0
	return int(round(float(d["base_cost"]) * pow(float(d["growth"]), get_prestige_node_level(id))))


# Freigeschaltet, sobald alle Voraussetzungs-Knoten ihre Mindeststufe erreicht haben.
func is_prestige_node_unlocked(id: String) -> bool:
	var prereq: Dictionary = _prestige_def(id).get("prereq", {})
	for req_id in prereq:
		if get_prestige_node_level(req_id) < int(prereq[req_id]):
			return false
	return true


func can_buy_prestige_node(id: String) -> bool:
	return (not is_prestige_node_coming(id)
		and is_prestige_node_unlocked(id)
		and not is_prestige_node_maxed(id)
		and prestige_points >= get_prestige_node_cost(id))


func buy_prestige_node(id: String) -> bool:
	if not can_buy_prestige_node(id):
		return false
	prestige_points -= get_prestige_node_cost(id)
	prestige_nodes[id] = get_prestige_node_level(id) + 1
	save_game()
	prestige_changed.emit()
	# Grid/Auto-Knoten wirken sofort: gleiche Signal-Wege wie normale Upgrades nutzen.
	if id == "grid":
		emit_signal("upgrade_purchased", "grid_size")
	elif id == "car":
		emit_signal("upgrade_purchased", "car_count")
	return true


# Globaler Einkommens-Multiplikator: 1 + Stufe des „income"-Knotens (Lv1 ×2, Lv2 ×3, …).
func get_prestige_mult() -> float:
	return 1.0 + float(get_prestige_node_level("income"))


# Lesbarer Effekt-Text eines Knotens bei gegebener Stufe (für „von → zu" im Tech-Baum).
func prestige_node_effect_text(id: String, level: int) -> String:
	match id:
		"income":
			return "×%d" % (1 + level)
		"grid":
			var lv := clampi(level, 0, GRID_STEPS.size() - 1)
			return "%d×%d" % [GRID_STEPS[lv].x, GRID_STEPS[lv].y]
		"car":
			return "+%d Auto" % level if level == 1 else "+%d Autos" % level
		"track":
			var n := PRESTIGE_TRACK_BASE + level
			return "%d Strecke" % n if n == 1 else "%d Strecken" % n
		"keep_unlocks":
			return "✓ aktiv" if level >= 1 else "aus"
		"stand_unlock":
			return "✓ freigeschaltet" if level >= 1 else "gesperrt"
		"free_roads":
			return "%d Geraden · %d Kurven" % [
				FREE_ROADS_PER_LEVEL["straight"] * level, FREE_ROADS_PER_LEVEL["curve"] * level]
	return str(level)


# Punkte, die ein Prestige JETZT einbringen würde: floor(sqrt(prestige_earned / K)).
func prestige_pending_points() -> int:
	if prestige_earned <= 0:
		return 0
	return int(floor(sqrt(float(prestige_earned) / PRESTIGE_K)))


func can_prestige() -> bool:
	return prestige_pending_points() >= 1


# Führt das Prestige aus: schreibt die fälligen Punkte gut und setzt ALLES außer dem
# Prestige-Block zurück (Geld, Upgrades, freigeschaltete Tiles, alle Strecken-Layouts).
# Gibt die erhaltenen Punkte zurück (0 = nicht möglich).
func do_prestige() -> int:
	var gained := prestige_pending_points()
	if gained < 1:
		return 0
	prestige_points += gained
	# Harter Reset – nur prestige_points/prestige_nodes bleiben erhalten.
	_currency      = START_CURRENCY
	upgrade_levels = {}
	track          = []
	unlocked_tiles = {}
	prestige_earned = 0
	_active_track  = 0   # Strecke 2/3 sind wieder gesperrt → zurück auf Strecke 1
	_init_tracks()
	save_game()
	prestige_changed.emit()
	return gained


# ── Bonusfelder ─────────────────────────────────────────────────────────────────

# Anzahl Felder eines Bonus-Typs = Upgrade-Level (0..3). kind ∈ {plus5, plus10, mult15}.
func get_bonus_count(kind: String) -> int:
	return get_upgrade_level("bonus_" + kind)


func is_bonus_unlocked(kind: String) -> bool:
	return get_bonus_count(kind) >= 1


# Plan der zu platzierenden Bonusfelder: jede Sorte so oft wie ihr Level.
func get_bonus_field_plan() -> Array:
	var out: Array = []
	for _i in range(get_bonus_count("plus5")):
		out.append({"label": "+5",   "points": 5.0,  "mult": 1.0})
	for _i in range(get_bonus_count("plus10")):
		out.append({"label": "+10",  "points": 10.0, "mult": 1.0})
	for _i in range(get_bonus_count("mult15")):
		out.append({"label": "×1.5", "points": 0.0,  "mult": 1.5})
	return out


# ── Auto-Lackierung (Kosmetik) ───────────────────────────────────────────────────

func is_car_paint_on() -> bool:
	return car_paint_on


func get_car_paint_color() -> Color:
	return car_paint_color


# Setzt die Lackierung. on=false → Originaltextur (color wird ignoriert). Persistiert + Live-Update.
func set_car_paint(on: bool, color: Color = Color(0.85, 0.15, 0.12)) -> void:
	car_paint_on = on
	if on:
		car_paint_color = color
	save_game()
	car_paint_changed.emit()


# ── Persistenz ──────────────────────────────────────────────────────────────────

# Strecke (Grid-State) merken – wird vom 2D-Bauplan bei Änderungen gesetzt.
func save_track(state: Array) -> void:
	track = state
	save_game()


func get_track() -> Array:
	return track


func has_track() -> bool:
	return not track.is_empty()


# var_to_str/str_to_var statt JSON: erhält Typen exakt (z. B. int-Rotationen).
func save_game() -> void:
	save_game_to_slot(_current_slot)


func save_game_to_slot(slot: int) -> void:
	var f = FileAccess.open(get_save_path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("Speichern fehlgeschlagen: " + get_save_path(slot))
		return
	# Track-Grids serialisieren
	var track_grids: Array = []
	for i in TRACK_COUNT:
		track_grids.append(_tracks[i]["grid"] if i < _tracks.size() else [])
	f.store_string(var_to_str({
		"currency":    _currency,
		"upgrades":    upgrade_levels,
		"track":       track,
		"track_grids": track_grids,
		"unlocked":    unlocked_tiles,
		"prestige_points": prestige_points,
		"prestige_earned": prestige_earned,
		"prestige_nodes":  prestige_nodes,
		"car_paint_on":    car_paint_on,
		"car_paint_color": car_paint_color,
		"timestamp":   Time.get_datetime_string_from_system(false, true),
		"name":        _slot_name,
	}))
	f.close()


func load_game() -> void:
	load_game_from_slot(_current_slot)


func load_game_from_slot(slot: int) -> void:
	_current_slot = slot
	# Erst auf Standardwerte zurücksetzen, damit KEIN Zustand (z. B. freigeschaltete
	# Tiles) vom vorher geladenen Slot übrig bleibt – auch wenn die Datei fehlt/defekt ist.
	_currency       = START_CURRENCY
	upgrade_levels  = {}
	track           = []
	unlocked_tiles  = {}
	prestige_points = 0
	prestige_earned = 0
	prestige_nodes  = {}
	car_paint_on    = false
	car_paint_color = Color(0.85, 0.15, 0.12)
	_slot_name      = ""
	_init_tracks()

	var path = get_save_path(slot)
	if FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.READ)
		if f != null:
			var txt = f.get_as_text()
			f.close()
			var data = str_to_var(txt)
			if typeof(data) == TYPE_DICTIONARY:
				_currency      = int(data.get("currency", START_CURRENCY))
				var ups        = data.get("upgrades", {})
				upgrade_levels = ups.duplicate() if typeof(ups) == TYPE_DICTIONARY else {}
				var tr         = data.get("track", [])
				track          = tr if typeof(tr) == TYPE_ARRAY else []
				var unl        = data.get("unlocked", {})
				unlocked_tiles = unl.duplicate() if typeof(unl) == TYPE_DICTIONARY else {}
				prestige_points = int(data.get("prestige_points", 0))
				prestige_earned = int(data.get("prestige_earned", 0))
				var pn         = data.get("prestige_nodes", {})
				prestige_nodes = pn.duplicate() if typeof(pn) == TYPE_DICTIONARY else {}
				car_paint_on   = bool(data.get("car_paint_on", false))
				var cpc        = data.get("car_paint_color", car_paint_color)
				car_paint_color = cpc if typeof(cpc) == TYPE_COLOR else car_paint_color
				_slot_name     = String(data.get("name", ""))
				# Multi-Track-Grids laden
				var tg = data.get("track_grids", [])
				if typeof(tg) == TYPE_ARRAY:
					for i in min(tg.size(), TRACK_COUNT):
						if typeof(tg[i]) == TYPE_ARRAY:
							_tracks[i]["grid"] = tg[i]
				elif track.size() > 0:
					# Rückwärtskompatibilität: alten track-State in Track 0 laden
					_tracks[0]["grid"] = track

	slot_changed.emit(slot)


func reset_slot(slot: int) -> void:
	_current_slot   = slot
	_currency       = START_CURRENCY
	upgrade_levels  = {}
	track           = []
	unlocked_tiles  = {}
	prestige_points = 0
	prestige_earned = 0
	prestige_nodes  = {}
	car_paint_on    = false
	car_paint_color = Color(0.85, 0.15, 0.12)
	_slot_name      = ""
	_init_tracks()
	save_game_to_slot(slot)
	slot_changed.emit(slot)


func rename_slot(slot: int, new_name: String) -> void:
	if not slot_exists(slot):
		return
	var f = FileAccess.open(get_save_path(slot), FileAccess.READ)
	if f == null:
		return
	var data = str_to_var(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	data["name"] = new_name
	var fw = FileAccess.open(get_save_path(slot), FileAccess.WRITE)
	if fw == null:
		return
	fw.store_string(var_to_str(data))
	fw.close()
	if slot == _current_slot:
		_slot_name = new_name


func delete_slot(slot: int) -> void:
	if not slot_exists(slot):
		return
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(get_save_path(slot).get_file())


func reset() -> void:
	reset_slot(_current_slot)
