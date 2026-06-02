extends Node3D

signal lap_completed(reward: int)
signal lap_progress(running: int)   # laufender Rundenertrag (pro überfahrenem Tile aktualisiert)

const TILE_SIZE = 1.2

# Ertrag pro überfahrenem Tile:
#   Standard-/Dreck-Tile (und Start): +5 additiv
#   Default-Tile (gekauft):           +50 additiv UND ×1.2 multiplikativ
# → lange Strecken mit Default-Tiles lohnen sich überproportional.
const BASIC_TILE_EARN   = 5.0
const PREMIUM_TILE_EARN  = 50.0
const PREMIUM_TILE_MULT  = 1.2

var speed: float = 2.5

# Pro-Auto-Parameter (von World3D vor start() gesetzt)
var end_mult:    float = 1.0   # Multiplikator auf den Rundenertrag
var tile_bonus:  float = 0.0   # + je überfahrenem Tile
var start_delay: float = 0.0   # verzögerter Start (gestaffelt bei mehreren Autos)

# Rundenertrag (in _build_waypoints berechnet)
var lap_base:   float = 0.0
var tile_count: int   = 0
var _delay_remaining: float = 0.0

var waypoints: Array[Vector3] = []
var current_wp: int = 0
var driving: bool = false
var car: Node3D = null

# Laufende Runden-Anzeige: Wegpunkt→Step-Zuordnung + kumulativer Rundenertrag je Step.
var _wp_to_step: PackedInt32Array = PackedInt32Array()
var _cum_reward: PackedInt32Array = PackedInt32Array()
var _cur_step: int = -1

const MODEL_ROTATION_OFFSET = PI / 2.0

# Visuelles Roll (Kurvenneigung) und Pitch (Rampenneigung)
const ROLL_FACTOR = 0.055   # rad Roll pro rad/s Gierrate
const ROLL_MAX    = 0.30    # ~17° maximale Kurvenneigung
const ROLL_SMOOTH = 12.0
const PITCH_FACTOR = 0.14   # rad Pitch pro m/s Vertikalgeschwindigkeit
const PITCH_MAX   = 0.50    # ~29° maximale Nasenneigung
const PITCH_SMOOTH = 9.0

var _prev_yaw: float     = 0.0
var _prev_car_y: float   = 0.0
var _yaw_init: bool      = false


func _ready() -> void:
	var car_script = load(Paths.SCRIPT_CAR_3D)
	car = Node3D.new()
	car.set_script(car_script)
	add_child(car)


func start(grid_state: Array) -> void:
	waypoints = _build_waypoints(grid_state)
	if waypoints.size() < 2:
		push_warning("Keine gültige Route – mind. 2 verbundene Tiles nötig.")
		return
	car.position = waypoints[0]
	current_wp   = 1
	_cur_step    = -1
	_delay_remaining = start_delay
	driving      = true
	print("Route: %d Wegpunkte" % waypoints.size())


func stop() -> void:
	driving = false


func _on_lap_completed() -> void:
	var reward = int(round((lap_base + tile_bonus * tile_count) * end_mult))
	if reward != 0:
		Economy.add(reward)
	lap_completed.emit(reward)


# Meldet den laufenden Rundenertrag, sobald das Auto ein neues Tile betritt.
func _emit_progress_if_changed() -> void:
	if _wp_to_step.is_empty() or current_wp < 0 or current_wp >= _wp_to_step.size():
		return
	var st = _wp_to_step[current_wp]
	if st != _cur_step:
		_cur_step = st
		lap_progress.emit(_cum_reward[st])


func _process(delta: float) -> void:
	if not driving or waypoints.is_empty():
		return
	if _delay_remaining > 0.0:
		_delay_remaining -= delta
		return

	var target = waypoints[current_wp]
	var dir    = target - car.position
	var dist   = dir.length()

	if dist < 0.04:
		var nxt = (current_wp + 1) % waypoints.size()
		if nxt < current_wp:   # Wegpunkt-Liste umgebrochen → eine Runde fertig
			_on_lap_completed()
			_cur_step = -1     # Runden-Anzeige für die nächste Runde zurücksetzen
		current_wp = nxt
		_emit_progress_if_changed()
		return

	car.position += dir.normalized() * speed * delta

	var flat_dir = Vector3(dir.x, 0, dir.z).normalized()
	if flat_dir.length() > 0.001:
		var new_yaw = atan2(flat_dir.x, flat_dir.z)
		car.rotation.y = new_yaw + MODEL_ROTATION_OFFSET

		# ── Kurvenneigung (Roll) ──────────────────────────────────────────
		if _yaw_init:
			var dyaw = new_yaw - _prev_yaw
			if dyaw >  PI: dyaw -= 2.0 * PI
			if dyaw < -PI: dyaw += 2.0 * PI
			var yaw_rate  = dyaw / max(delta, 0.001)
			var roll_t    = clamp(-yaw_rate * ROLL_FACTOR, -ROLL_MAX, ROLL_MAX)
			car.rotation.z = lerp(car.rotation.z, roll_t, delta * ROLL_SMOOTH)
		else:
			car.rotation.z = lerp(car.rotation.z, 0.0, delta * ROLL_SMOOTH)
		_prev_yaw  = new_yaw
		_yaw_init  = true

	# ── Rampen-Neigung (Pitch) ────────────────────────────────────────────
	var vy      = (car.position.y - _prev_car_y) / max(delta, 0.001)
	var pitch_t = clamp(vy * PITCH_FACTOR, -PITCH_MAX, PITCH_MAX)
	car.rotation.x = lerp(car.rotation.x, pitch_t, delta * PITCH_SMOOTH)
	_prev_car_y = car.position.y


# ── Verbindungs-Logik ──────────────────────────────────────────────────────────

func _get_connections(data) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}

	var bn: bool; var be: bool; var bs: bool; var bw: bool
	if data["type"] == "straight" or data["type"] == "ramp_start" or data["type"] == "ramp_end":
		bn = false; be = true; bs = false; bw = true
	elif data["type"] == "curve" or data["type"] == "curve_alt":
		# curve und curve_alt haben dieselben Öffnungen – nur Wegpunkte unterscheiden sich
		# rot=0: S+E  rot=90: W+S  rot=180: N+W  rot=270: N+E
		match data["rotation"]:
			0:   bn = false; be = true;  bs = true;  bw = false
			90:  bn = false; be = false; bs = true;  bw = true
			180: bn = true;  be = false; bs = false; bw = true
			270: bn = true;  be = true;  bs = false; bw = false
			_:   bn = false; be = true;  bs = true;  bw = false
		return {"N": bn, "E": be, "S": bs, "W": bw}
	else:
		return {}

	# Rotation im Uhrzeigersinn: 90° CW dreht N→E, E→S, S→W, W→N
	var steps = (data["rotation"] / 90) % 4
	var rn = bn; var re = be; var rs = bs; var rw = bw
	for _i in range(steps):
		var tmp_n = rw; var tmp_e = rn; var tmp_s = re; var tmp_w = rs
		rn = tmp_n; re = tmp_e; rs = tmp_s; rw = tmp_w

	if data.get("direction", 1) == -1:
		for _j in range(2):
			var tmp_n = rw; var tmp_e = rn; var tmp_s = re; var tmp_w = rs
			rn = tmp_n; re = tmp_e; rs = tmp_s; rw = tmp_w

	return {"N": rn, "E": re, "S": rs, "W": rw}


func _through(data, entry_dir: String) -> String:
	var conns = _get_connections(data)
	for dir in ["N", "E", "S", "W"]:
		if conns.get(dir, false) and dir != entry_dir:
			return dir
	return ""


func _step(row: int, col: int, dir: String) -> Vector2i:
	match dir:
		"N": return Vector2i(row - 1, col)
		"S": return Vector2i(row + 1, col)
		"E": return Vector2i(row, col + 1)
		"W": return Vector2i(row, col - 1)
	return Vector2i(-1, -1)


func _opposite(dir: String) -> String:
	match dir:
		"N": return "S"
		"S": return "N"
		"E": return "W"
		"W": return "E"
	return ""


# ── Wegpunkt-Berechnung ────────────────────────────────────────────────────────

func _build_waypoints(grid_state: Array) -> Array[Vector3]:
	var grid_rows = grid_state.size()
	var grid_cols = grid_state[0].size() if grid_rows > 0 else 0

	var start_row = -1
	var start_col = -1
	var exit_dir  = "E"

	# Start-Tile suchen
	for row in range(grid_rows):
		for col in range(grid_cols):
			var d = grid_state[row][col]
			if typeof(d) == TYPE_DICTIONARY and d.get("is_start", false):
				start_row = row
				start_col = col
				exit_dir  = "E"
				break
		if start_row >= 0:
			break

	# Fallback: erstes Tile das einen gültigen Nachbarn hat
	if start_row < 0:
		for row in range(grid_rows):
			for col in range(grid_cols):
				var d = grid_state[row][col]
				if typeof(d) != TYPE_DICTIONARY:
					continue
				var conns = _get_connections(d)
				for dir in ["E", "S", "W", "N"]:
					if not conns.get(dir, false):
						continue
					var nxt = _step(row, col, dir)
					if nxt.x < 0 or nxt.x >= grid_rows or nxt.y < 0 or nxt.y >= grid_cols:
						continue
					if typeof(grid_state[nxt.x][nxt.y]) != TYPE_DICTIONARY:
						continue
					start_row = row; start_col = col; exit_dir = dir
					break
				if start_row >= 0:
					break
			if start_row >= 0:
				break

	if start_row < 0:
		return []

	# Route verfolgen – max Schritte = alle Tiles × 2, genug für jeden geschlossenen Kreis
	var max_steps = grid_rows * grid_cols * 2
	var visited: Dictionary = {}
	var route: Array = []
	var row = start_row
	var col = start_col

	for _i in range(max_steps):
		var key = "%d_%d" % [row, col]
		if key in visited:
			break
		visited[key] = true
		route.append({"row": row, "col": col, "data": grid_state[row][col], "exit": exit_dir})

		var next = _step(row, col, exit_dir)
		# ramp_start: Mittelfeld (der Sprung) überspringen
		if typeof(grid_state[row][col]) == TYPE_DICTIONARY:
			if grid_state[row][col].get("type", "") == "ramp_start":
				var skip = _step(next.x, next.y, exit_dir)
				if skip.x >= 0 and skip.x < grid_rows and skip.y >= 0 and skip.y < grid_cols:
					next = skip
		if next.x < 0 or next.x >= grid_rows or next.y < 0 or next.y >= grid_cols:
			break
		var next_data = grid_state[next.x][next.y]
		if typeof(next_data) != TYPE_DICTIONARY:
			break

		var entry = _opposite(exit_dir)
		var next_exit = _through(next_data, entry)
		if next_exit == "":
			break

		row = next.x
		col = next.y
		exit_dir = next_exit

	print("Route: %d Tiles gefunden" % route.size())

	# Runden-Grundwert: flat +1 pro Tile (Dreck nur +0.1), plus Bonusfeld-Effekte.
	# Bonusfeld +5/+10 = bonus_points (additiv), ×1.5 = bonus_mult (multipliziert die
	# Summe am Ende, reihenfolge-unabhängig).
	# Pro-Tile-Beiträge → kumulativer Rundenertrag (mirror der Endformel in _on_lap_completed),
	# damit die Runden-Anzeige pro überfahrenem Tile auf den finalen Wert hochzählt.
	var n        = route.size()
	var cum_add  = 0.0
	var cum_mult = 1.0
	_cum_reward = PackedInt32Array()
	for k in range(n):
		var d = route[k]["data"]
		var a = 0.0
		var m = 1.0
		if typeof(d) == TYPE_DICTIONARY:
			var t = d.get("type", "")
			# Default-Tile = gekauft (nicht Dreck, nicht Start) und eine echte Fahrkachel.
			var is_premium = (not d.get("is_dirt", false)) and (not d.get("is_start", false)) \
				and t in ["straight", "curve", "curve_alt"]
			if is_premium:
				a = PREMIUM_TILE_EARN + d.get("bonus_points", 0.0)
				m = PREMIUM_TILE_MULT
			else:
				a = BASIC_TILE_EARN + d.get("bonus_points", 0.0)
			# Sprung-Kreuzung: dieses Tile bringt doppelten (× jump_mult) Ertrag
			a *= d.get("jump_mult", 1.0)
			var bm = d.get("bonus_mult", 1.0)
			if bm != 1.0:
				m *= bm
		cum_add  += a
		cum_mult *= m
		_cum_reward.append(int(round((cum_add * cum_mult + tile_bonus * (k + 1)) * end_mult)))
	lap_base   = cum_add * cum_mult
	tile_count = n

	# Wegpunkte aus Route bauen + Zuordnung Wegpunkt→Step (für die Runden-Anzeige)
	var wps: Array[Vector3] = []
	_wp_to_step = PackedInt32Array()
	for si in range(n):
		var step = route[si]
		var center = Vector3(
			step["col"] * TILE_SIZE + TILE_SIZE / 2.0,
			0.05,
			step["row"] * TILE_SIZE + TILE_SIZE / 2.0
		)
		var tile_wps = _waypoints_for_tile(center, step["data"], step["exit"])
		for _w in range(tile_wps.size()):
			_wp_to_step.append(si)
		wps.append_array(tile_wps)

	return wps


func _waypoints_for_tile(center: Vector3, data: Dictionary, exit_dir: String) -> Array[Vector3]:
	var wps: Array[Vector3] = []
	var half = TILE_SIZE / 2.0
	var type    = data["type"]
	var rot     = data["rotation"]
	var flipped = data.get("flipped", false)

	if type == "ramp_start":
		# Parabolischer Bogen: ramp_start-Mitte → über Mittelfeld → ramp_end-Ausgang
		var d      = _dir_to_vec(exit_dir)
		var peak_h = 0.55
		var p_end  = Vector3(
			center.x + d.x * TILE_SIZE * 2.5,
			0.05,
			center.z + d.z * TILE_SIZE * 2.5
		)
		var arc_steps = 16
		for i in range(arc_steps + 1):
			var t   = float(i) / arc_steps
			var pos = center.lerp(p_end, t)
			pos.y   = peak_h * 4.0 * t * (1.0 - t) + 0.05
			wps.append(pos)

	elif type == "ramp_end":
		pass  # Bogen wurde bereits von ramp_start generiert

	elif type == "straight":
		wps.append(center)
		wps.append(center + _dir_to_vec(exit_dir) * half)

	elif type == "curve" or type == "curve_alt":
		var cx: float; var cz: float
		var a_from: float; var a_to: float
		match rot:
			0:
				cx =  half; cz =  half; a_from = PI;        a_to = PI * 1.5
			90:
				cx = -half; cz =  half; a_from = PI * 1.5;  a_to = PI * 2.0
			180:
				cx = -half; cz = -half; a_from = 0.0;       a_to = PI * 0.5
			270:
				cx =  half; cz = -half; a_from = PI * 0.5;  a_to = PI
			_:
				cx =  half; cz =  half; a_from = PI;        a_to = PI * 1.5

		if type == "curve_alt":
			var tmp = a_from; a_from = a_to; a_to = tmp

		var steps = 10
		for i in range(steps + 1):
			var t     = float(i) / float(steps)
			var angle = lerp(a_from, a_to, t)
			wps.append(Vector3(
				center.x + cx + cos(angle) * half,
				0.05,
				center.z + cz + sin(angle) * half
			))

	return wps


func _dir_to_vec(dir: String) -> Vector3:
	match dir:
		"N": return Vector3(0, 0, -1)
		"S": return Vector3(0, 0,  1)
		"E": return Vector3( 1, 0, 0)
		"W": return Vector3(-1, 0, 0)
	return Vector3.ZERO
