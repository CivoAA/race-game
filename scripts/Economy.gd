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
	# Zusätzliche Autos – addiert sich auf das normale Auto-Upgrade.
	"car": {
		"name": "Extra-Auto", "icon": "🚗", "base_cost": 6, "growth": 5.0, "max_level": 3,
		"desc": "Je Stufe ein dauerhaft zusätzliches Auto.", "prereq": {"grid": 1},
	},
	# Strecken-Freischaltung: Lv1 = Strecke 2, Lv2 = Strecke 3 (Strecke 1 ist immer offen).
	"track": {
		"name": "Extra-Strecke", "icon": "🏁", "base_cost": 8, "growth": 8.0, "max_level": 2,
		"desc": "Schaltet Strecke 2 und 3 frei (eine je Stufe).", "prereq": {"car": 1},
	},
}
# Reihenfolge im Tech-Baum (links → rechts).
const PRESTIGE_ORDER = ["income", "grid", "car", "track"]
const PRESTIGE_TRACK_BASE = 1   # Strecke 1 ist immer offen; je „track"-Stufe eine weitere.

var _currency:     int        = START_CURRENCY
var upgrade_levels: Dictionary = {}
var track:          Array      = []   # gespeicherte Strecke des aktiven Tracks (Rückwärtskompatibilität)
var unlocked_tiles: Dictionary = {}   # freigeschaltete Shop-Tiles: key → true

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


# ── Freischaltbare Shop-Tiles ───────────────────────────────────────────────────
# Zentrale Freischaltkosten (gemeinsame Quelle für Bau-Shop in Main.gd und den
# Streckenteile-Tab in GlobalModal.gd). Main.SHOP_ITEMS spiegelt diese Werte.
const TILE_UNLOCK_COST = {
	"def_straight": 15000,
	"def_curve":    30000,
	"ramp":         500000,
}


func get_tile_unlock_cost(key: String) -> int:
	return int(TILE_UNLOCK_COST.get(key, 0))


func is_tile_unlocked(key: String) -> bool:
	return key == "" or unlocked_tiles.get(key, false)


func unlock_tile(key: String) -> void:
	if key == "":
		return
	unlocked_tiles[key] = true
	save_game()
	tile_unlocked.emit(key)


func _ready() -> void:
	_init_tracks()


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
# gezählte Runden). lap_base/tile_count je Auto sind streckenfix und kommen aus World3D.
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


# Reward einer Runde aus den aktuellen Upgrade-Werten (live):
# (lap_base + tilebonus·tile_count + Σ tile-Upgrade·zugehörige Feldzahl)·endmult.
# Alle Autos einer Strecke teilen Layout → einheitlicher Reward; erstes gültiges Auto genügt.
func _current_lap_reward(cars: Array) -> int:
	for car in cars:
		if float(car.get("lap_time", 0.0)) <= 0.0:
			continue
		var lap_base   := float(car.get("lap_base", 0.0))
		var tile_count := int(car.get("tile_count", 0))
		var add := lap_base + get_car_tile_bonus(0) * tile_count
		# Tile-spezifische Upgrades (live aus den aktuellen Stufen, additiv je Feld dieses Typs):
		add += get_effect("dirtstraightbonus") * int(car.get("dirt_straight_count", 0))
		add += get_effect("dirtcurvebonus")    * int(car.get("dirt_curve_count", 0))
		add += get_effect("straightbonus")     * int(car.get("straight_count", 0))
		add += get_effect("curvebonus")        * int(car.get("curve_count", 0))
		# Globaler Prestige-Multiplikator als letzter Faktor (wirkt live auf alle Strecken).
		return int(round(add * get_car_end_mult(0) * get_prestige_mult()))
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
# cars: Array von {lap_time, lap_k, lap_base, tile_count, dirt_straight_count, dirt_curve_count,
#                  straight_count, curve_count, start_delay}.
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


# ── Prestige ────────────────────────────────────────────────────────────────────

func get_prestige_points() -> int:
	return prestige_points


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
