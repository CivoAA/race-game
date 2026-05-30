extends Node3D

const TILE_SIZE = 1.2
var speed: float = 2.0

var waypoints: Array[Vector3] = []
var current_wp: int = 0
var driving: bool = false
var car: Node3D = null

const MODEL_ROTATION_OFFSET = PI / 2.0


func _ready() -> void:
	var car_script = load("res://scripts/Car3D.gd")
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
	driving      = true
	print("Route: %d Wegpunkte" % waypoints.size())


func stop() -> void:
	driving = false


func _process(delta: float) -> void:
	if not driving or waypoints.is_empty():
		return

	var target = waypoints[current_wp]
	var dir    = target - car.position
	var dist   = dir.length()

	if dist < 0.04:
		current_wp = (current_wp + 1) % waypoints.size()
		return

	car.position += dir.normalized() * speed * delta

	var flat_dir = Vector3(dir.x, 0, dir.z).normalized()
	if flat_dir.length() > 0.001:
		var angle = atan2(flat_dir.x, flat_dir.z)
		car.rotation.y = angle + MODEL_ROTATION_OFFSET


# ── Verbindungs-Logik ──────────────────────────────────────────────────────────
# Basis-Verbindungen VOR Rotation:
# straight (0°): offen nach E und W
# curve    (0°, flip=false): offen nach N und E  → Kurve dreht von N nach E
# curve    (0°, flip=true):  offen nach N und W  → Kurve dreht von N nach W
#
# Rotation dreht im Uhrzeigersinn: N→E→S→W→N
# D.h. bei 90°: was vorher N war ist jetzt E, was E war ist S usw.

func _get_connections(data) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}

	# Basis bei rot=0: Gerade=W+E, Kurve=N+E
	var bn: bool; var be: bool; var bs: bool; var bw: bool
	if data["type"] == "straight":
		bn = false; be = true; bs = false; bw = true
	else:
		# Geometrisch berechnet aus Curve3D (cx,cz,Bogenwinkel):
		# Geometrisch verifiziert (kombiniert aus beiden Scripts):
		# rot=0:   N+W offen  (cx=-half,cz=-half, 0°→90°)
		# rot=90:  N+E offen  (cx=+half,cz=-half, 90°→180°)
		# rot=180: S+E offen  (cx=+half,cz=+half, 180°→270°)
		# rot=270: S+W offen  (cx=-half,cz=+half, 270°→360°)
		# rot=0:   S+E  rot=90: W+S  rot=180: N+W  rot=270: N+E
		match data["rotation"]:
			0:   bn = false; be = true;  bs = true;  bw = false
			90:  bn = false; be = false; bs = true;  bw = true
			180: bn = true;  be = false; bs = false; bw = true
			270: bn = true;  be = true;  bs = false; bw = false
			_:   bn = false; be = true;  bs = true;  bw = false
		return {"N": bn, "E": be, "S": bs, "W": bw}

	# Rotation im Uhrzeigersinn: 90° CW dreht N→E, E→S, S→W, W→N
	# Also: neues_N = altes_W, neues_E = altes_N, neues_S = altes_E, neues_W = altes_S
	var steps = (data["rotation"] / 90) % 4
	var rn = bn; var re = be; var rs = bs; var rw = bw
	for _i in range(steps):
		var tmp_n = rw; var tmp_e = rn; var tmp_s = re; var tmp_w = rs
		rn = tmp_n; re = tmp_e; rs = tmp_s; rw = tmp_w

	# direction=-1: Fahrtrichtung umgekehrt → Rotation um 180° für Verbindungen
	if data.get("direction", 1) == -1:
		# Nochmal 2 Schritte drehen (= 180°)
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
	# Startpunkt: das Start-Tile (horizontal Gerade) das World3D immer setzt
	# Position wird aus grid_state gesucht: Tile mit meta "is_start" = true
	# Fallback: erstes Tile mit E-Verbindung das einen gültigen Nachbarn hat
	var start_row = -1
	var start_col = -1
	var exit_dir  = "E"

	# Start-Tile suchen (von World3D als {"type":"straight","rotation":0,"flipped":false,"is_start":true} gesetzt)
	for row in range(4):
		for col in range(4):
			var d = grid_state[row][col]
			if typeof(d) == TYPE_DICTIONARY and d.get("is_start", false):
				start_row = row
				start_col = col
				exit_dir  = "E"
				break
		if start_row >= 0:
			break

	# Fallback falls kein Start-Tile gefunden
	if start_row < 0:
		for row in range(4):
			for col in range(4):
				var d = grid_state[row][col]
				if typeof(d) != TYPE_DICTIONARY:
					continue
				var conns = _get_connections(d)
				for dir in ["E", "S", "W", "N"]:
					if not conns.get(dir, false):
						continue
					var nxt = _step(row, col, dir)
					if nxt.x < 0 or nxt.x >= 4 or nxt.y < 0 or nxt.y >= 4:
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

	# Route verfolgen (max 32 Schritte = mehr als genug für 4x4)
	var visited: Dictionary = {}
	var route: Array = []
	var row = start_row
	var col = start_col

	# Auto direkt auf Mitte des Start-Tiles setzen
	var start_center = Vector3(
		start_col * TILE_SIZE + TILE_SIZE / 2.0,
		0.05,
		start_row * TILE_SIZE + TILE_SIZE / 2.0
	)

	for _i in range(32):
		var key = "%d_%d" % [row, col]
		if key in visited:
			break
		visited[key] = true
		route.append({"row": row, "col": col, "data": grid_state[row][col], "exit": exit_dir})

		var next = _step(row, col, exit_dir)
		if next.x < 0 or next.x >= 4 or next.y < 0 or next.y >= 4:
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

	# Wegpunkte aus Route bauen
	var wps: Array[Vector3] = []
	for step in route:
		var center = Vector3(
			step["col"] * TILE_SIZE + TILE_SIZE / 2.0,
			0.05,
			step["row"] * TILE_SIZE + TILE_SIZE / 2.0
		)
		wps.append_array(_waypoints_for_tile(center, step["data"], step["exit"]))

	return wps


func _waypoints_for_tile(center: Vector3, data: Dictionary, exit_dir: String) -> Array[Vector3]:
	var wps: Array[Vector3] = []
	var half = TILE_SIZE / 2.0
	var type    = data["type"]
	var rot     = data["rotation"]
	var flipped = data["flipped"]

	if type == "straight":
		# Vom Tile-Mittelpunkt zum Ausgang fahren
		# (kein Eingangs-Wegpunkt - verhindert dass Auto hinter Start spawnt)
		wps.append(center)
		wps.append(center + _dir_to_vec(exit_dir) * half)

	elif type == "curve":
		# Alle 4 Fälle geometrisch verifiziert:
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
