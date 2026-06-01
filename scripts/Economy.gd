extends Node
## Zentraler, persistenter Spielzustand: Währung + gekaufte Upgrades.
## Wird als Autoload "Economy" geladen. Speichert in Slot-Dateien (user://savegame_slotN.dat).

const START_CURRENCY  = 500
const BASE_SPEED      = 2.5    # Grund-Tempo eines Autos (bewusst langsam; via Upgrades schneller)

# ── Upgrade-Definitionen ────────────────────────────────────────────────────────
# category: "general" oder "car" (car_* sind Vorlagen für car<idx>_<suffix>)
# Kosten pro Level = round(base_cost * growth^level)
# Effektwert pro Level = base + per_level * level
const UPGRADES = {
	"speed": {
		"category": "general", "name": "Tempo (alle Autos)",
		"base_cost": 25, "growth": 1.6, "max_level": 10,
		"base": 0.0, "per_level": 0.5, "unit": " Tempo",
	},
	"drive_time": {
		"category": "general", "name": "Fahrzeit",
		"base_cost": 40, "growth": 1.8, "max_level": 8,
		"base": 10.0, "per_level": 5.0, "unit": "s",
	},
	"grid_size": {
		"category": "general", "name": "Streckengröße",
		"base_cost": 100, "growth": 3.0, "max_level": 3,
		"base": 0.0, "per_level": 0.0, "unit": "",
	},
	"car_count": {
		"category": "general", "name": "Zusätzliches Auto",
		"base_cost": 150, "growth": 2.5, "max_level": 3,
		"base": 1.0, "per_level": 1.0, "unit": " Autos",
	},
	# Vorlagen für Pro-Auto-Upgrades (Key real: car0_speed, car1_endmult, …)
	"car_speed": {
		"category": "car", "name": "Tempo",
		"base_cost": 20, "growth": 1.6, "max_level": 10,
		"base": 0.0, "per_level": 0.5, "unit": " Tempo",
	},
	"car_endmult": {
		"category": "car", "name": "End-Multiplikator",
		"base_cost": 60, "growth": 2.0, "max_level": 8,
		"base": 1.0, "per_level": 0.5, "unit": "×",
	},
	"car_tilebonus": {
		"category": "car", "name": "Tile-Bonus (+ je Feld)",
		"base_cost": 30, "growth": 1.7, "max_level": 12,
		"base": 0.0, "per_level": 0.5, "unit": " /Feld",
	},
	# Bonusfelder: einmalige Freischaltungen (max_level 1) + Anzahl-Upgrade
	"unlock_plus5": {
		"category": "bonus", "name": "+5-Feld freischalten",
		"base_cost": 50, "growth": 1.0, "max_level": 1,
		"base": 0.0, "per_level": 0.0, "unit": "",
	},
	"unlock_plus10": {
		"category": "bonus", "name": "+10-Feld freischalten",
		"base_cost": 120, "growth": 1.0, "max_level": 1,
		"base": 0.0, "per_level": 0.0, "unit": "",
	},
	"unlock_mult15": {
		"category": "bonus", "name": "×1.5-Feld freischalten",
		"base_cost": 200, "growth": 1.0, "max_level": 1,
		"base": 0.0, "per_level": 0.0, "unit": "",
	},
	"bonus_count": {
		"category": "bonus", "name": "Mehr Bonusfelder",
		"base_cost": 80, "growth": 1.8, "max_level": 6,
		"base": 0.0, "per_level": 1.0, "unit": " extra",
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
var track:          Array      = []   # gespeicherte Strecke (Grid-State ohne Dreck-Tiles)
var _current_slot:  int        = 0


func _ready() -> void:
	pass  # Slot wird explizit aus dem Menü gesetzt


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


# ── Upgrade-Abfragen ──────────────────────────────────────────────────────────

func get_upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


func _def_for(id: String) -> Dictionary:
	if UPGRADES.has(id):
		return UPGRADES[id]
	# Pro-Auto-Key "car<idx>_<suffix>" → Vorlage "car_<suffix>"
	if id.begins_with("car"):
		var us = id.find("_")
		if us > 0:
			var tkey = "car_" + id.substr(us + 1)
			if UPGRADES.has(tkey):
				return UPGRADES[tkey]
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
	if id.begins_with("unlock_"):
		return "🔓 frei" if level >= 1 else "🔒 gesperrt"
	if id == "grid_size":
		var lv = clampi(level, 0, GRID_STEPS.size() - 1)
		return "%d×%d" % [GRID_STEPS[lv].x, GRID_STEPS[lv].y]
	if id == "car_count":
		return "%d Autos" % (1 + level)
	var v = _effect_at(id, level)
	var unit = get_upgrade_unit(id)
	if id == "car_endmult":
		return "×%.2f" % v
	# Ganzzahlig ohne Nachkommastellen, sonst eine Stelle
	if absf(v - round(v)) < 0.001:
		return "%d%s" % [int(round(v)), unit]
	return "%.1f%s" % [v, unit]


# ── Abgeleitete Spielwerte ──────────────────────────────────────────────────────

func get_drive_time() -> float:
	return _effect_at("drive_time", get_upgrade_level("drive_time"))


func get_grid_rows() -> int:
	return GRID_STEPS[clampi(get_upgrade_level("grid_size"), 0, GRID_STEPS.size() - 1)].x


func get_grid_cols() -> int:
	return GRID_STEPS[clampi(get_upgrade_level("grid_size"), 0, GRID_STEPS.size() - 1)].y


func get_car_count() -> int:
	return 1 + get_upgrade_level("car_count")


func get_car_speed(i: int) -> float:
	var global_bonus = _effect_at("speed", get_upgrade_level("speed"))
	var car_bonus    = _effect_at("car_speed", get_upgrade_level("car%d_speed" % i))
	return BASE_SPEED + global_bonus + car_bonus


func get_car_end_mult(i: int) -> float:
	return _effect_at("car_endmult", get_upgrade_level("car%d_endmult" % i))


func get_car_tile_bonus(i: int) -> float:
	return _effect_at("car_tilebonus", get_upgrade_level("car%d_tilebonus" % i))


# ── Bonusfelder ─────────────────────────────────────────────────────────────────

func is_bonus_unlocked(kind: String) -> bool:
	return get_upgrade_level("unlock_" + kind) >= 1


# Liste der freigeschalteten Bonus-Typen als {label, points, mult}.
func get_unlocked_bonus_types() -> Array:
	var out: Array = []
	if is_bonus_unlocked("plus5"):
		out.append({"label": "+5",   "points": 5.0,  "mult": 1.0})
	if is_bonus_unlocked("plus10"):
		out.append({"label": "+10",  "points": 10.0, "mult": 1.0})
	if is_bonus_unlocked("mult15"):
		out.append({"label": "×1.5", "points": 0.0,  "mult": 1.5})
	return out


# Zusätzliche (zufällige) Bonusfelder über die je-1-pro-Typ-Garantie hinaus.
func get_bonus_extra_count() -> int:
	return get_upgrade_level("bonus_count")


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
	f.store_string(var_to_str({
		"currency":  _currency,
		"upgrades":  upgrade_levels,
		"track":     track,
		"timestamp": Time.get_datetime_string_from_system(false, true),
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


func reset_slot(slot: int) -> void:
	_current_slot  = slot
	_currency      = START_CURRENCY
	upgrade_levels = {}
	track          = []
	save_game_to_slot(slot)


func reset() -> void:
	reset_slot(_current_slot)
