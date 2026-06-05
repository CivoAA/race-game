extends Node3D

const TILE_SIZE = 1.2

# Ertrag pro überfahrenem Tile:
#   Dreck-Tile:              +1 additiv (per Dreck-Ertrag-Upgrade steigerbar)
#   Standard-Tile (u. Start): +5 additiv
#   Default-Tile (gekauft):  +50 additiv UND ×1.2 multiplikativ
# → lange Strecken mit Default-Tiles lohnen sich überproportional.
const BASIC_TILE_EARN   = 0.0   # Standard-/Start-Felder: kein Grundertrag (nur Upgrades zählen)
const DIRT_TILE_EARN    = 1.0   # Dreck-Felder: Grundertrag +1, per Dreck-Upgrade steigerbar
const PREMIUM_TILE_EARN  = 50.0
const PREMIUM_TILE_MULT  = 1.2

var speed: float = 2.5

# Track-Index dieses Autos – Quelle der Fahrzeit (Economy.get_run_elapsed). Von World3D gesetzt.
var track_idx: int = 0

# Pro-Auto-Parameter (von World3D vor start() gesetzt)
var end_mult:    float = 1.0   # Multiplikator auf den Rundenertrag
var tile_bonus:  float = 0.0   # + je überfahrenem Tile
var start_delay: float = 0.0   # verzögerter Start (gestaffelt bei mehreren Autos)

# Tile-Reihenfolge für die Runden-Abrechnung (in _build_waypoints gefüllt). Jeder Eintrag
# beschreibt ein befahrenes Feld STRECKENFIX (upgrade-unabhängig): {base, kind, fixed_mult,
# bonus_points, bonus_mult, is_jump}. Economy faltet daraus pro Runde live den Schneeball mit
# den AKTUELLEN Upgrade-Werten – auch für Hintergrund-Strecken (3D-Ansicht nicht offen).
var tile_rewards: Array = []

# ── Bullet-proof Sync: EINE Wahrheitsquelle = Fahrzeit (Economy.run_elapsed) ──────
# Visuelle Position UND Geld-Runden werden ausschließlich aus der verstrichenen Zeit
# über eine pro-Segment-Zeittabelle abgeleitet. Dadurch ist das Auto visuell immer
# genau dann auf dem Start-Tile, wenn Economy eine Runde gutschreibt – bei jedem Tempo.
var lap_time: float = 0.0                              # Zeit für eine volle Runde (Summe seg_time)
var _seg_time: PackedFloat32Array = PackedFloat32Array()  # Dauer je Wegpunkt-Segment
var _cum_time: PackedFloat32Array = PackedFloat32Array()  # Zeit, zu der wp[i] erreicht wird

var waypoints: Array[Vector3] = []
var driving: bool = false
var car: Node3D = null

# Wegpunkt→Step-Zuordnung (für die Tempo-Faktor-Tabelle je Segment).
var _wp_to_step: PackedInt32Array = PackedInt32Array()

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


func start(grid_state: Array, resume_elapsed: float = 0.0) -> void:
	waypoints = _build_waypoints(grid_state)
	if waypoints.size() < 2 or lap_time <= 0.0:
		push_warning("Keine gültige Route – mind. 2 verbundene Tiles nötig.")
		return
	_yaw_init     = false
	# Effektiv bereits gefahrene Zeit dieses Autos (gestaffelten Startversatz abziehen).
	var t := resume_elapsed - start_delay
	if t <= 0.0:
		# Frischer Start – oder das Auto wartet noch auf seinen versetzten Start.
		car.position = waypoints[0]
		# Am Start steht das Auto still → Yaw aus der Bewegung wird noch nicht berechnet.
		# Darum hier schon in Fahrtrichtung (Start-Tile → nächster Wegpunkt) ausrichten,
		# sonst stehen die wartenden Autos rückwärts.
		_face_along_start()
	else:
		# Wiederaufnahme nach 2D↔3D-Wechsel: Position rein aus der Fahrzeit ableiten.
		_sample_at_time(t)
	_prev_car_y = car.position.y
	driving = true
	print("Route: %d Wegpunkte, lap_time %.2fs (resume %.1fs)" % [waypoints.size(), lap_time, resume_elapsed])


# Setzt das Auto rein aus der verstrichenen Fahrzeit (mod Rundenzeit) auf die geschlossene
# Schleife. Nutzt die Segment-Zeittabelle – dadurch identisch zur Geld-Abrechnung in Economy,
# unabhängig von Tempo, Framerate oder (künftig) Booster-/Brems-Tiles.
func _sample_at_time(t: float) -> void:
	var n := waypoints.size()
	if n < 2 or lap_time <= 0.0:
		return
	var t_in_lap := fmod(t, lap_time)
	if t_in_lap < 0.0:
		t_in_lap += lap_time
	for i in range(n):
		var st := _seg_time[i]
		if t_in_lap <= _cum_time[i] + st or i == n - 1:
			var f := (t_in_lap - _cum_time[i]) / st if st > 0.0 else 0.0
			car.position = waypoints[i].lerp(waypoints[(i + 1) % n], clampf(f, 0.0, 1.0))
			return


func stop() -> void:
	driving = false


func _process(delta: float) -> void:
	if not driving or waypoints.is_empty() or lap_time <= 0.0:
		return

	# EINE Wahrheitsquelle: Fahrzeit aus Economy (läuft in 2D wie 3D identisch weiter).
	# Die Geld-Gutschrift je Runde macht zentral Economy aus derselben t/lap_time – hier nur
	# die visuelle Position und Ausrichtung.
	var t := Economy.get_run_elapsed(track_idx) - start_delay
	if t < 0.0:
		# Gestaffelter Start – dieses Auto wartet noch am Start-Tile.
		car.position = waypoints[0]
		return

	var prev_pos := car.position
	_sample_at_time(t)
	_update_orientation(prev_pos, delta)


# Richtet das stehende Auto am Start in Fahrtrichtung aus (Start-Tile → erster Wegpunkt),
# gleiche Yaw-Formel wie _update_orientation. Ohne das stünde das Modell rückwärts, bis es losfährt.
func _face_along_start() -> void:
	if waypoints.size() < 2:
		return
	var dir := waypoints[1] - waypoints[0]
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.0001:
		car.rotation = Vector3(0.0, atan2(flat.x, flat.z) + MODEL_ROTATION_OFFSET, 0.0)


# Visuelle Ausrichtung (Yaw) + Kurvenneigung (Roll) + Rampenneigung (Pitch) aus der
# tatsächlichen Positionsänderung – funktioniert unverändert mit dem Zeit-Sampling.
func _update_orientation(prev_pos: Vector3, delta: float) -> void:
	var dir := car.position - prev_pos
	var flat_dir := Vector3(dir.x, 0, dir.z)
	if flat_dir.length() > 0.0001:
		var new_yaw := atan2(flat_dir.x, flat_dir.z)
		car.rotation.y = new_yaw + MODEL_ROTATION_OFFSET

		# ── Kurvenneigung (Roll) ──────────────────────────────────────────
		if _yaw_init:
			var dyaw := new_yaw - _prev_yaw
			if dyaw >  PI: dyaw -= 2.0 * PI
			if dyaw < -PI: dyaw += 2.0 * PI
			var yaw_rate  := dyaw / maxf(delta, 0.001)
			var roll_t    := clampf(-yaw_rate * ROLL_FACTOR, -ROLL_MAX, ROLL_MAX)
			car.rotation.z = lerp(car.rotation.z, roll_t, delta * ROLL_SMOOTH)
		else:
			car.rotation.z = lerp(car.rotation.z, 0.0, delta * ROLL_SMOOTH)
		_prev_yaw  = new_yaw
		_yaw_init  = true

	# ── Rampen-Neigung (Pitch) ────────────────────────────────────────────
	var vy      := (car.position.y - _prev_car_y) / maxf(delta, 0.001)
	var pitch_t := clampf(vy * PITCH_FACTOR, -PITCH_MAX, PITCH_MAX)
	car.rotation.x = lerp(car.rotation.x, pitch_t, delta * PITCH_SMOOTH)
	_prev_car_y = car.position.y


# ── Verbindungs-Logik ──────────────────────────────────────────────────────────

func _get_connections(data) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}

	var bn: bool; var be: bool; var bs: bool; var bw: bool
	if data["type"] == "straight" or data["type"] == "ramp_start" or data["type"] == "ramp_end" or data["type"] == "ice":
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


# True, wenn das Tile eine Rampe ist und exit_dir zur Partner-Kachel zeigt (= Sprung über das
# Mittelfeld). Gilt für ramp_start UND ramp_end, damit die Rampe in beide Richtungen befahrbar ist.
func _ramp_jumps_toward(data, row: int, col: int, exit_dir: String) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var t = data.get("type", "")
	if t != "ramp_start" and t != "ramp_end":
		return false
	var pr = int(data.get("ramp_partner_row", -1))
	var pc = int(data.get("ramp_partner_col", -1))
	if pr < 0 or pc < 0:
		return false
	var dir := ""
	if pc > col: dir = "E"
	elif pc < col: dir = "W"
	elif pr > row: dir = "S"
	elif pr < row: dir = "N"
	return dir == exit_dir


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
		# Rampe: Mittelfeld (der Sprung) überspringen, sobald der Ausgang zur Partner-Kachel zeigt –
		# egal ob von der ramp_start- oder ramp_end-Seite (Fahrtrichtung wird automatisch erkannt).
		if _ramp_jumps_toward(grid_state[row][col], row, col, exit_dir):
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

	# Pro befahrenem Feld einen STRECKENFIXEN Ertrags-Eintrag bauen (ohne Upgrade-Werte!).
	# Economy._current_lap_reward faltet daraus pro Runde live den "Schneeball".
	# >>> VERBINDLICHE RECHEN-REGEL (Schritt 1 = alle +Werte, dann Schritt 2 = alle ×Werte je Feld;
	#     bei Unklarheit über +/× beim Nutzer rückfragen): siehe Block über _current_lap_reward
	#     in Economy.gd. Neue tile-bezogene Boni hier als +Wert (base/bonus_points) ODER ×Wert
	#     (fixed_mult/bonus_mult) einsortieren – passend zu dieser Regel.
	# kind steuert, welches additive Upgrade Economy auf dieses Feld legt.
	var n        = route.size()
	tile_rewards = []
	var step_speed := PackedFloat32Array()   # Tempo-Faktor je Step (Booster/Bremse, sonst 1.0)
	var step_bonus := PackedFloat32Array()   # absoluter m/s-Bonus je Step (Eisgerade)
	for _k in range(n):
		step_bonus.append(0.0)
	for k in range(n):
		var d = route[k]["data"]
		step_speed.append(_tile_speed_factor(d))
		var rec := {
			"base": 0.0, "kind": "plain", "fixed_mult": 1.0,
			"bonus_points": 0.0, "bonus_mult": 1.0, "is_jump": false,
		}
		if typeof(d) == TYPE_DICTIONARY:
			var t = d.get("type", "")
			# Default-Tile = gekauft (nicht Dreck, nicht Start) und eine echte Fahrkachel.
			var is_premium = (not d.get("is_dirt", false)) and (not d.get("is_start", false)) \
				and t in ["straight", "curve", "curve_alt"]
			if is_premium:
				rec["base"]       = PREMIUM_TILE_EARN
				rec["fixed_mult"] = PREMIUM_TILE_MULT
				rec["kind"]       = "pstraight" if t == "straight" else "pcurve"
			elif t == "ramp_start":
				# Rampe: Grundertrag am Absprung-Feld. Den Sprung-×2 legt Economy live drauf
				# (get_ramp_jump_mult), weil das übersprungene Mittelfeld nicht befahren wird.
				rec["base"] = Economy.RAMP_BASE_EARN
				rec["kind"] = "ramp"
			elif d.get("is_dirt", false):
				rec["base"] = DIRT_TILE_EARN
				rec["kind"] = "dstraight" if t == "straight" else "dcurve"
			else:
				rec["base"] = BASIC_TILE_EARN   # Start-/Standard-/ramp_end-Feld (nur Tile-Bonus zählt)
			rec["bonus_points"] = float(d.get("bonus_points", 0.0))
			rec["bonus_mult"]   = float(d.get("bonus_mult", 1.0))
			# Sprung-Mittelfeld: ein ECHTES, befahrenes Tile mit jump_mult bekommt den Sprung-×2.
			rec["is_jump"]      = d.get("jump_mult", 1.0) != 1.0
		tile_rewards.append(rec)

	# Eisgerade: legt auf die nächsten get_ice_range() Felder (in Fahrtrichtung, über die
	# geschlossene Schleife) einen absoluten Tempo-Bonus. Mehrere Eisgeraden summieren sich.
	# Das eigene Feld bleibt normal schnell – nur die FOLGE-Felder werden „rutschig".
	var ice_bonus := Economy.get_ice_speed_bonus()
	var ice_range := Economy.get_ice_range()
	if ice_bonus > 0.0 and n > 0:
		for ik in range(n):
			var idata = route[ik]["data"]
			if typeof(idata) == TYPE_DICTIONARY and idata.get("type", "") == "ice":
				for j in range(1, ice_range + 1):
					step_bonus[(ik + j) % n] += ice_bonus

	# Wegpunkte aus Route bauen + Zuordnung Wegpunkt→Step (für die Tempo-Faktor-Tabelle)
	var wps: Array[Vector3] = []
	_wp_to_step = PackedInt32Array()
	for si in range(n):
		var step = route[si]
		var center = Vector3(
			step["col"] * TILE_SIZE + TILE_SIZE / 2.0,
			0.05,
			step["row"] * TILE_SIZE + TILE_SIZE / 2.0
		)
		var tile_wps = _waypoints_for_tile(center, step["data"], step["exit"], step["row"], step["col"])
		for _w in range(tile_wps.size()):
			_wp_to_step.append(si)
		wps.append_array(tile_wps)

	# Segment-Zeittabelle bauen: Position UND Geld leiten sich ab jetzt nur noch hieraus ab.
	_build_time_table(wps, step_speed, step_bonus)
	return wps


# Tempo-Faktor eines Tiles (1.0 = normal). Booster-/Brems-Tiles setzen später "speed_mult"
# in ihrem Tile-Dictionary; lap_time und visuelle Position passen sich automatisch an.
func _tile_speed_factor(data) -> float:
	if typeof(data) == TYPE_DICTIONARY:
		return maxf(0.05, float(data.get("speed_mult", 1.0)))
	return 1.0


# Pro Wegpunkt-Segment: Dauer = Länge ÷ (Tempo × Tile-Faktor). lap_time = Summe aller Dauern.
# Das ist die EINE Wahrheitsquelle für visuelle Position (_sample_at_time) und Geld
# (Economy._credit_laps bekommt dasselbe lap_time von World3D).
func _build_time_table(wps: Array[Vector3], step_speed: PackedFloat32Array, step_bonus: PackedFloat32Array = PackedFloat32Array()) -> void:
	var n := wps.size()
	_seg_time = PackedFloat32Array()
	_cum_time = PackedFloat32Array()
	var acc := 0.0
	for i in range(n):
		_cum_time.append(acc)
		var seg_len := wps[i].distance_to(wps[(i + 1) % n])
		var stp := _wp_to_step[i] if i < _wp_to_step.size() else 0
		var factor : float = step_speed[stp] if stp < step_speed.size() else 1.0
		# Eisgerade-Bonus ist ABSOLUT (m/s), wird also auf das Segment-Tempo addiert – nicht
		# multipliziert –, damit er „so viel schneller wie N Tempo-Stufen" bleibt, egal wie hoch
		# das Grund-Tempo ist.
		var bonus : float = step_bonus[stp] if stp < step_bonus.size() else 0.0
		var seg_speed : float = maxf(0.01, speed * factor + bonus)
		_seg_time.append(seg_len / seg_speed)
		acc += seg_len / seg_speed
	lap_time = acc


func _waypoints_for_tile(center: Vector3, data: Dictionary, exit_dir: String, row: int, col: int) -> Array[Vector3]:
	var wps: Array[Vector3] = []
	var half = TILE_SIZE / 2.0
	var type    = data["type"]
	var rot     = data["rotation"]
	var flipped = data.get("flipped", false)

	if type == "ramp_start" or type == "ramp_end":
		# Nur die AUFFAHR-Seite (Ausgang zeigt zur Partner-Kachel) erzeugt den Sprungbogen über das
		# Mittelfeld; die Lande-Seite liefert keine eigenen Wegpunkte. So springt das Auto unabhängig
		# davon, ob die Strecke von der Start- oder End-Seite in die Rampe läuft.
		if _ramp_jumps_toward(data, row, col, exit_dir):
			# Parabolischer Bogen: Auffahr-Mitte → über Mittelfeld → Partner-Ausgang
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

	elif type == "straight" or type == "ice":
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

		# Sweep-Richtung des Bogens an die TATSÄCHLICHE Durchfahrtsrichtung (exit_dir) koppeln,
		# nicht an den Tile-Typ (curve/curve_alt). Der Vorwärts-Bogen (a_from→a_to) verlässt das
		# Tile je Rotation Richtung E/S/W/N; fährt das Auto andersherum, Reihenfolge tauschen –
		# sonst läge der erste Wegpunkt an der Ausgangskante und das Auto würde rückwärts fahren.
		var fwd_exit := "E"
		match rot % 360:
			0:   fwd_exit = "E"
			90:  fwd_exit = "S"
			180: fwd_exit = "W"
			270: fwd_exit = "N"
		if exit_dir != fwd_exit:
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
