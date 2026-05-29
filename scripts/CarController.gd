extends Node3D
## CarController – berechnet aus dem Grid-State eine Route als Wegpunkte
## und bewegt das Auto smoothly entlang.

const TILE_SIZE    = 1.2
const WAYPOINTS_PER_STRAIGHT = 2   # Punkte pro Geraden-Tile
const WAYPOINTS_PER_CURVE    = 8   # Punkte pro Kurven-Tile (mehr = smoother)

# Fahrgeschwindigkeit in Einheiten/Sekunde
var speed: float = 2.0

# Die berechneten Wegpunkte für eine Runde
var waypoints: Array[Vector3] = []
var current_wp: int = 0

# Das Auto-Node
var car: Node3D = null

# Läuft das Auto gerade?
var driving: bool = false


func _ready() -> void:
	# Car3D als Kind spawnen
	var car_script = load("res://scripts/Car3D.gd")
	car = Node3D.new()
	car.set_script(car_script)
	add_child(car)


func start(grid_state: Array) -> void:
	waypoints = _build_waypoints(grid_state)
	if waypoints.size() < 2:
		push_warning("Keine gültige Route gefunden – mind. 2 verbundene Tiles nötig.")
		return

	# Auto auf ersten Wegpunkt setzen
	car.position = waypoints[0]
	current_wp   = 1
	driving      = true
	print("Route gestartet mit %d Wegpunkten." % waypoints.size())


func stop() -> void:
	driving = false


func _process(delta: float) -> void:
	if not driving or waypoints.is_empty():
		return

	var target = waypoints[current_wp]
	var dir    = (target - car.position)
	var dist   = dir.length()

	if dist < 0.05:
		# Wegpunkt erreicht → nächster (Endlosschleife)
		current_wp = (current_wp + 1) % waypoints.size()
		return

	# Bewegen
	car.position += dir.normalized() * speed * delta

	# Auto in Fahrtrichtung drehen (nur Y-Achse)
	if dir.length() > 0.001:
		var look_target = car.position + dir.normalized()
		car.look_at(look_target, Vector3.UP)
		# Modell-Offset falls das Modell falsch ausgerichtet ist
		car.rotation.y += PI   # ← auskommentieren falls Auto rückwärts fährt


# ── Wegpunkt-Berechnung ────────────────────────────────────────────────────────

func _build_waypoints(grid_state: Array) -> Array[Vector3]:
	# 1. Startpunkt finden (erstes nicht-leeres Tile)
	var start_row = -1
	var start_col = -1
	for row in range(4):
		for col in range(4):
			if grid_state[row][col] != "":
				start_row = row
				start_col = col
				break
		if start_row >= 0:
			break

	if start_row < 0:
		return []

	# 2. Route per Flood-Walk verfolgen
	var visited: Dictionary = {}
	var route: Array = []   # Array von [row, col, tile_type]
	var row = start_row
	var col = start_col

	# Startrichtung ermitteln
	var tile = grid_state[row][col]
	var exit_dir = _first_exit(tile)   # z.B. "E"

	for _i in range(32):   # max 16 Tiles, Sicherheitslimit
		var key = "%d_%d" % [row, col]
		if key in visited:
			break   # Runde geschlossen
		visited[key] = true
		route.append([row, col, grid_state[row][col]])

		# Nächste Zelle in exit_dir
		var next = _step(row, col, exit_dir)
		if next.x < 0 or next.x >= 4 or next.y < 0 or next.y >= 4:
			break
		var next_tile = grid_state[next.x][next.y]
		if next_tile == "":
			break

		# Eingangsseite der nächsten Zelle = Gegenseite von exit_dir
		var entry_dir = _opposite(exit_dir)
		exit_dir = _through(next_tile, entry_dir)
		if exit_dir == "":
			break

		row = next.x
		col = next.y

	# 3. Wegpunkte aus Route generieren
	var wps: Array[Vector3] = []
	for i in range(route.size()):
		var r    = route[i][0]
		var c    = route[i][1]
		var type = route[i][2]
		var center = Vector3(c * TILE_SIZE + TILE_SIZE / 2.0, 0.05, r * TILE_SIZE + TILE_SIZE / 2.0)
		wps.append_array(_waypoints_for_tile(center, type))

	return wps


func _waypoints_for_tile(center: Vector3, tile_type: String) -> Array[Vector3]:
	var wps: Array[Vector3] = []
	var half = TILE_SIZE / 2.0

	match tile_type:
		"straight_h":
			wps.append(center + Vector3(-half, 0, 0))
			wps.append(center + Vector3( half, 0, 0))
		"straight_v":
			wps.append(center + Vector3(0, 0, -half))
			wps.append(center + Vector3(0, 0,  half))
		"curve_ne":
			_add_curve_waypoints(wps, center, Vector3(half, 0, -half), PI * 0.5, PI)
		"curve_nw":
			_add_curve_waypoints(wps, center, Vector3(-half, 0, -half), 0.0, PI * 0.5)
		"curve_se":
			_add_curve_waypoints(wps, center, Vector3(half, 0, half), PI * 1.5, PI)
		"curve_sw":
			_add_curve_waypoints(wps, center, Vector3(-half, 0, half), PI * 1.5, PI * 2.0)

	return wps


func _add_curve_waypoints(wps: Array[Vector3], center: Vector3, curve_center_offset: Vector3, a_from: float, a_to: float) -> void:
	var cc   = center + curve_center_offset
	var r    = TILE_SIZE / 2.0
	var steps = WAYPOINTS_PER_CURVE
	for i in range(steps + 1):
		var t     = float(i) / float(steps)
		var angle = lerp(a_from, a_to, t)
		wps.append(Vector3(
			cc.x + cos(angle) * r,
			0.05,
			cc.z + sin(angle) * r
		))


# ── Hilfsfunktionen für Routing ────────────────────────────────────────────────

## Gibt die erste mögliche Ausgangsseite eines Tiles zurück
func _first_exit(tile_type: String) -> String:
	var conns = _get_connections(tile_type)
	for dir in conns:
		if conns[dir]:
			return dir
	return ""


## Gibt die Durchgangsrichtung: komme von entry_dir, wohin gehe ich?
func _through(tile_type: String, entry_dir: String) -> String:
	var conns = _get_connections(tile_type)
	for dir in conns:
		if conns[dir] and dir != entry_dir:
			return dir
	return ""


## Verbindungen pro Tile-Typ (muss zu euren 2D-Tiles passen)
func _get_connections(tile_type: String) -> Dictionary:
	match tile_type:
		"straight_h": return {"N": false, "E": true,  "S": false, "W": true}
		"straight_v": return {"N": true,  "E": false, "S": true,  "W": false}
		"curve_ne":   return {"N": true,  "E": true,  "S": false, "W": false}
		"curve_nw":   return {"N": true,  "E": false, "S": false, "W": true}
		"curve_se":   return {"N": false, "E": true,  "S": true,  "W": false}
		"curve_sw":   return {"N": false, "E": false, "S": true,  "W": true}
	return {}


## Einen Schritt in eine Richtung im Grid
func _step(row: int, col: int, dir: String) -> Vector2i:
	match dir:
		"N": return Vector2i(row - 1, col)
		"S": return Vector2i(row + 1, col)
		"E": return Vector2i(row, col + 1)
		"W": return Vector2i(row, col - 1)
	return Vector2i(-1, -1)


## Gegenrichtung
func _opposite(dir: String) -> String:
	match dir:
		"N": return "S"
		"S": return "N"
		"E": return "W"
		"W": return "E"
	return ""
