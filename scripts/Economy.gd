extends Node
## Zentraler, persistenter Spielzustand: Währung + gekaufte Upgrades + 3 Track-Zustände.
## Wird als Autoload "Economy" geladen. Speichert in Slot-Dateien (user://savegame_slotN.dat).

const TRACK_COUNT = 3

const START_CURRENCY  = 0
const BASE_SPEED      = 4.0    # Grund-Tempo – bei 4 m/s läuft ein kleiner 16-Tile-Kurs (~19m) in ~5s

# ── Upgrade-Definitionen ────────────────────────────────────────────────────────
# category: "general" oder "car" (car_* sind Vorlagen für car<idx>_<suffix>)
# Kosten pro Level = round(base_cost * growth^level)
# Effektwert pro Level = base + per_level * level
const UPGRADES = {
	"speed": {
		"category": "general", "name": "Tempo (alle Autos)",
		"base_cost": 50, "growth": 2.2, "max_level": 12,
		"base": 0.0, "per_level": 0.5, "unit": " Tempo",
	},
	"drive_time": {
		"category": "general", "name": "Fahrzeit",
		"base_cost": 250, "growth": 2.6, "max_level": 10,
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
		"base_cost": 60, "growth": 3.0, "max_level": 10,
		"base": 1.0, "per_level": 0.5, "unit": "×",
	},
	"tilebonus": {
		"category": "general", "name": "Tile-Bonus (+ je Feld, alle Autos)",
		"base_cost": 30, "growth": 2.3, "max_level": 14,
		"base": 0.0, "per_level": 0.5, "unit": " /Feld",
	},
	# Bonusfelder: je Typ max. 3 – das Upgrade-Level = Anzahl dieser Felder (Lv1 schaltet frei,
	# Lv2 = zweites Feld, Lv3 = drittes). Kosten steigen idle-typisch steil.
	"bonus_plus5": {
		"category": "bonus", "name": "+5-Felder",
		"base_cost": 50, "growth": 6.0, "max_level": 3,
		"base": 0.0, "per_level": 1.0, "unit": "",
	},
	"bonus_plus10": {
		"category": "bonus", "name": "+10-Felder",
		"base_cost": 250, "growth": 8.0, "max_level": 3,
		"base": 0.0, "per_level": 1.0, "unit": "",
	},
	"bonus_mult15": {
		"category": "bonus", "name": "×1.5-Felder",
		"base_cost": 1000, "growth": 10.0, "max_level": 3,
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

var _currency:     int        = START_CURRENCY
var upgrade_levels: Dictionary = {}
var track:          Array      = []   # gespeicherte Strecke des aktiven Tracks (Rückwärtskompatibilität)
var unlocked_tiles: Dictionary = {}   # freigeschaltete Shop-Tiles: key → true
var _current_slot:  int        = 0
var _slot_name:     String     = ""

# ── Multi-Track-State ───────────────────────────────────────────────────────────
var _active_track: int = 0
var _tracks: Array = []   # TRACK_COUNT Einträge
var endless_mode: bool = false   # Kein Timer, Geld wird live gutgeschrieben

signal run_ended(track_idx: int, earned: int)


# ── Freischaltbare Shop-Tiles ───────────────────────────────────────────────────

func is_tile_unlocked(key: String) -> bool:
	return key == "" or unlocked_tiles.get(key, false)


func unlock_tile(key: String) -> void:
	if key == "":
		return
	unlocked_tiles[key] = true
	save_game()


func _ready() -> void:
	_init_tracks()


func _init_tracks() -> void:
	_tracks.clear()
	for _i in TRACK_COUNT:
		_tracks.append({
			"grid":            [],
			"run_active":      false,
			"run_timer":       0.0,
			"run_earned":      0,
			"earn_per_sec":    0.0,
			"pending_summary": false,
			"last_earned":     0,
		})


func _process(delta: float) -> void:
	for i in TRACK_COUNT:
		if _tracks[i]["run_active"]:
			var eps := float(_tracks[i].get("earn_per_sec", 0.0))
			if endless_mode:
				# Endlos-Modus: kein Timer, Hintergrund-Einnahmen sofort gutschreiben
				if eps > 0.0:
					_currency += eps * delta
			else:
				_tracks[i]["run_timer"] -= delta
				# Hintergrund-Einnahmen wenn 2D-Ansicht aktiv (kein World3D vorhanden)
				if eps > 0.0:
					_tracks[i]["run_earned"] = float(_tracks[i]["run_earned"]) + eps * delta
				if _tracks[i]["run_timer"] <= 0.0:
					_tracks[i]["run_timer"]       = 0.0
					_tracks[i]["run_active"]      = false
					_tracks[i]["earn_per_sec"]    = 0.0
					var earned: int = int(_tracks[i]["run_earned"])
					_currency += earned              # Gesamtbetrag gutschreiben
					_tracks[i]["pending_summary"] = true
					_tracks[i]["last_earned"]     = earned
					save_game()
					emit_signal("run_ended", i, earned)


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
	_tracks[track_idx]["run_earned"]   = 0
	_tracks[track_idx]["earn_per_sec"] = 0.0


func add_run_earned(track_idx: int, amount: int) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["run_earned"] += amount


func stop_run(track_idx: int) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["run_active"]   = false
	_tracks[track_idx]["earn_per_sec"] = 0.0


func get_run_earned(track_idx: int) -> int:
	if track_idx < 0 or track_idx >= _tracks.size():
		return 0
	return int(_tracks[track_idx]["run_earned"])


func set_earn_rate(track_idx: int, rate: float) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["earn_per_sec"] = maxf(rate, 0.0)


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
	var d = _def_for(id)
	if d.is_empty():
		return 0.0
	return float(d["base"]) + float(d["per_level"]) * level


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


func get_grid_rows() -> int:
	return GRID_STEPS[clampi(get_upgrade_level("grid_size"), 0, GRID_STEPS.size() - 1)].x


func get_grid_cols() -> int:
	return GRID_STEPS[clampi(get_upgrade_level("grid_size"), 0, GRID_STEPS.size() - 1)].y


func get_car_count() -> int:
	return 1 + get_upgrade_level("car_count")


# Tempo/End-Mult/Tile-Bonus sind jetzt global (gelten für alle Autos gleich).
func get_car_speed(_i: int) -> float:
	return BASE_SPEED + _effect_at("speed", get_upgrade_level("speed"))


func get_car_end_mult(_i: int) -> float:
	return _effect_at("endmult", get_upgrade_level("endmult"))


func get_car_tile_bonus(_i: int) -> float:
	return _effect_at("tilebonus", get_upgrade_level("tilebonus"))


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
		"timestamp":   Time.get_datetime_string_from_system(false, true),
		"name":        _slot_name,
	}))
	f.close()


func load_game() -> void:
	load_game_from_slot(_current_slot)


func load_game_from_slot(slot: int) -> void:
	_current_slot = slot
	var path = get_save_path(slot)
	if not FileAccess.file_exists(path):
		return
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt = f.get_as_text()
	f.close()
	var data = str_to_var(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_currency      = int(data.get("currency", START_CURRENCY))
	var ups        = data.get("upgrades", {})
	upgrade_levels = ups.duplicate() if typeof(ups) == TYPE_DICTIONARY else {}
	var tr         = data.get("track", [])
	track          = tr if typeof(tr) == TYPE_ARRAY else []
	var unl        = data.get("unlocked", {})
	unlocked_tiles = unl.duplicate() if typeof(unl) == TYPE_DICTIONARY else {}
	_slot_name     = String(data.get("name", ""))
	# Multi-Track-Grids laden
	_init_tracks()
	var tg = data.get("track_grids", [])
	if typeof(tg) == TYPE_ARRAY:
		for i in min(tg.size(), TRACK_COUNT):
			if typeof(tg[i]) == TYPE_ARRAY:
				_tracks[i]["grid"] = tg[i]
	else:
		# Rückwärtskompatibilität: alten track-State in Track 0 laden
		if track.size() > 0:
			_tracks[0]["grid"] = track


func reset_slot(slot: int) -> void:
	_current_slot  = slot
	_currency      = START_CURRENCY
	upgrade_levels = {}
	track          = []
	unlocked_tiles = {}
	_slot_name     = ""
	_init_tracks()
	save_game_to_slot(slot)


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
