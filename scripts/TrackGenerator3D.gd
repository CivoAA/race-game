extends Node3D

const TILE_SIZE = 1.2
const ROAD_Y    = 0.01

# Gerade GLB-Modelle laufen entlang einer Achse. Falls das Modell quer statt
# längs in der Kachel liegt, hier 90 eintragen (Yaw-Korrektur in Grad).
const STRAIGHT_MODEL_YAW_OFFSET = 90.0

# Yaw-Korrektur für die Kurven-GLBs (Grad). Die Engine-Kurve bei rot=0 verbindet
# Süd- und Ost-Kante; falls das Modell anders ausgerichtet ist, hier in 90°-Schritten anpassen.
const CURVE_MODEL_YAW_OFFSET = 90.0

# Yaw-Korrektur (Grad) für die Spezial-GLBs, falls sie anders ausgerichtet importiert werden.
# In 90°-Schritten anpassen, bis Rampe/Tribüne/Looping/Steilwand richtig stehen.
const RAMP_MODEL_YAW_OFFSET  = -90.0
# Yaw-Korrektur der Tribuene (Grad). Das GLB ist pro Anzahl fertig arrangiert; falls die ganze
# Tribuene um 90°/180° verdreht steht, hier in 90°-Schritten korrigieren.
const STAND_MODEL_YAW_OFFSET = 0.0
# Looping-GLB: Basislage S→N (wie eine Gerade bei rot=0). Yaw anpassen, falls das Modell quer steht.
const LOOP_MODEL_YAW_OFFSET  = 0.0
# Steilwand-GLB (Bank): EIN 2-Kachel-Modell (Basislage rot=0: Partner südlich, Haarnadel öffnet
# nach West). 90° im Uhrzeigersinn gedreht, damit das ausgelieferte Asset richtig steht.
const WALL_MODEL_YAW_OFFSET  = -90.0
# Das 2-Kachel-Asset sitzt mit seinem Ursprung nicht mittig zwischen den Kacheln → entlang der
# Achse Start→Partner ("unten") verschieben, damit die Straße bündig auf die Kante trifft (statt
# auf die Mitte). Wert in KACHELN; negativ = Richtung Start.
const WALL_MODEL_SHIFT_TILES = 0.5
# Portal-GLBs (Rampe + Tor): von oben einfahren → nach links, plus 180°-Korrektur des Assets
# (90 + 180 = 270 ≡ -90).
const PORTAL_MODEL_YAW_OFFSET = -90.0

# Gerade und Kurve wurden auf demselben Modellraster gebaut. Beide Modelle mit
# DEMSELBEN Faktor (TILE_SIZE / MODEL_TILE_NATIVE) skalieren und am Modell-Ursprung
# (= Mittelzelle) zentrieren → gleiche Straßenbreite und nahtlose Übergänge.
# NICHT über die einzelne Modell-AABB normieren: die Kurve belegt nur einen Teil
# des Rasters, ihre AABB ist also kleiner als eine ganze Kachel.
# Neuer Asset-Satz (Blender): eine Gerade ist 1 m lang = eine Kachel, Fahrbahn 0,5 m breit.
# Also 1.0 Modell-Einheit pro Kachel → Skalierung TILE_SIZE/1.0 = 1.2 füllt die Kachel exakt.
const MODEL_TILE_NATIVE = 1.0

# Gemeinsame Track-Atlas-Textur: zentral in MaterialUtil.apply_track_texture (gleiche Quelle wie
# die Shop-3D-Vorschau in GlobalModal). Die GLBs kommen ohne Material, tragen aber die passenden UVs.


# Lädt ein Geraden-GLB, skaliert es auf TILE_SIZE und zentriert es auf der Kachel.
func _make_straight_model(path: String) -> Node3D:
	var holder = Node3D.new()
	var scene = load(path)
	if scene == null:
		push_error("Geraden-Modell nicht gefunden: " + path)
		return holder

	var inst = scene.instantiate()
	holder.add_child(inst)
	MaterialUtil.apply_track_texture(inst)
	MaterialUtil.apply_alpha_scissor(inst)

	var aabb = _local_aabb(inst)
	if aabb.size.z > 0.0:
		# Gemeinsamer Rastermaßstab (Kachel = 3 Modellzellen), uniform – Straße bleibt
		# 1 Zelle breit und füllt die Kachel der Länge nach. Am Modell-Ursprung zentriert
		# (die Gerade ist symmetrisch), nur vertikal auf den Boden gesetzt.
		var s = TILE_SIZE / MODEL_TILE_NATIVE
		inst.scale = Vector3(s, s, s)
		inst.position = Vector3(0.0, -aabb.position.y * s, 0.0)
	return holder


# Lädt das fertig arrangierte Tribuenen-GLB für einen Stapel. Jede Anzahl (1..4, ab 4 inkl. 5)
# hat ein eigenes Modell, in dem die Tribuenen bereits fertig angeordnet sind (siehe Paths.stand_model).
# Skalierung/Bodenausrichtung wie bei einer Geraden (Kachel = MODEL_TILE_NATIVE).
func _build_stand_stack(stack: int) -> Node3D:
	return _make_straight_model(Paths.stand_model(stack))


# Lädt das Kurven-GLB, skaliert es uniform auf die Kachel (füllt die Kachelfläche)
# und zentriert es. Die Node-Rotation (in generate) richtet die Kurve aus.
func _make_curve_model(path: String) -> Node3D:
	var holder = Node3D.new()
	var scene = load(path)
	if scene == null:
		push_error("Kurven-Modell nicht gefunden: " + path)
		return holder

	var inst = scene.instantiate()
	holder.add_child(inst)
	MaterialUtil.apply_track_texture(inst)
	MaterialUtil.apply_alpha_scissor(inst)

	var aabb = _local_aabb(inst)
	if aabb.size.x > 0.0 and aabb.size.z > 0.0:
		# IDENTISCHER Maßstab wie die Gerade (Kachel = 3 Modellzellen), uniform.
		# NICHT am AABB-Mittelpunkt zentrieren – der Modell-Ursprung (0,0) ist die
		# Mittelzelle des 3×3-Rasters = Kachelmitte. So sitzen die Bogen-Enden genau
		# auf den Kachelkanten-Mitten und stoßen bündig an die Geraden an.
		var s = TILE_SIZE / MODEL_TILE_NATIVE
		inst.scale = Vector3(s, s, s)
		inst.position = Vector3(0.0, -aabb.position.y * s, 0.0)
	return holder


# Kombinierte AABB aller MeshInstance3D im lokalen Raum von root.
func _local_aabb(root: Node3D) -> AABB:
	var res: Array = [null]
	if root is MeshInstance3D and root.mesh != null:
		res[0] = root.mesh.get_aabb()
	for child in root.get_children():
		_aabb_recurse(child, Transform3D.IDENTITY, res)
	return res[0] if res[0] != null else AABB()


func _aabb_recurse(node: Node, xf: Transform3D, res: Array) -> void:
	var cur = xf
	if node is Node3D:
		cur = xf * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var a: AABB = cur * node.mesh.get_aabb()
		res[0] = a if res[0] == null else (res[0] as AABB).merge(a)
	for child in node.get_children():
		_aabb_recurse(child, cur, res)


# Macht ein Eis-Modell eisig: behaelt die Atlas-Textur, senkt aber Roughness und gibt einen
# leichten Blauton + etwas Metallic, damit die Flaeche den Himmel spiegelt (glTF traegt das nicht).
func _apply_ice_look(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var base := mi.get_active_material(0)
		var mat: StandardMaterial3D
		if base is StandardMaterial3D:
			mat = (base as StandardMaterial3D).duplicate()
		else:
			mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.68, 0.83, 1.0)
		mat.roughness    = 0.22
		mat.metallic     = 0.0
		mi.material_override = mat
	for child in node.get_children():
		_apply_ice_look(child)


# ── Portal-Routen-Rolle ────────────────────────────────────────────────────────
# Liefert die Zelle des AUSGANGS-Portals (orange). Die Strecke wird ab dem Start (1,1) Richtung
# Osten verfolgt; das zuerst angefahrene Portal ist der Eingang, sein Partner der Ausgang.
# (-1,-1) wenn die Route nicht durch ein Portal führt. Spiegelt Main._portal_route_roles().
func _portal_exit_cell(grid_state: Array) -> Vector2i:
	var rows := grid_state.size()
	var cols: int = grid_state[0].size() if rows > 0 else 0
	if rows < 2 or cols < 2:
		return Vector2i(-1, -1)
	var row := 1; var col := 1; var exit_dir := "E"
	var visited: Dictionary = {}
	for _i in range(rows * cols * 2):
		var key := "%d_%d" % [row, col]
		if key in visited:
			return Vector2i(-1, -1)
		visited[key] = true
		var cur = grid_state[row][col]
		if typeof(cur) == TYPE_DICTIONARY and cur.get("type", "") == "portal":
			return _portal_partner_cell(grid_state, row, col)
		var nxt := _pt_step(row, col, exit_dir)
		if _pt_ramp_jumps_toward(cur, row, col, exit_dir):
			if _pt_in_bounds(nxt, rows, cols): nxt = _pt_step(nxt.x, nxt.y, exit_dir)
		if not _pt_in_bounds(nxt, rows, cols): return Vector2i(-1, -1)
		var nxt_data = grid_state[nxt.x][nxt.y]
		if typeof(nxt_data) != TYPE_DICTIONARY: return Vector2i(-1, -1)
		var nxt_exit := _pt_through(nxt_data, _pt_opp(exit_dir))
		if nxt_exit == "": return Vector2i(-1, -1)
		row = nxt.x; col = nxt.y; exit_dir = nxt_exit
	return Vector2i(-1, -1)


# Das ANDERE Portal in der Strecke (von max. 2). (-1,-1) falls keins.
func _portal_partner_cell(grid_state: Array, row: int, col: int) -> Vector2i:
	for r in range(grid_state.size()):
		var line = grid_state[r]
		for c in range(line.size()):
			var d = line[c]
			if typeof(d) == TYPE_DICTIONARY and d.get("type", "") == "portal" and not (r == row and c == col):
				return Vector2i(r, c)
	return Vector2i(-1, -1)


# Durchgang-Richtung: bei Eintritt über `entry` (Himmelsrichtung) die Ausfahrt-Richtung ("" wenn
# das Tile von dieser Seite nicht befahrbar ist). Spiegelt Main._ac_through().
func _pt_through(data: Dictionary, entry: String) -> String:
	var t = data.get("type", "")
	var rot := int(data.get("rotation", 0)) % 360
	var conns: Dictionary
	if t in ["straight", "ramp_start", "ramp_end", "ice", "race_straight", "sand_straight", "water_straight", "glue_straight"]:
		conns = _pt_rot_conns(false, true, false, true, rot)
	elif t == "loop":
		conns = _pt_rot_conns(true, false, true, false, rot)
	elif t == "portal":
		var od := _pt_portal_open_dir(rot)
		return od if entry == od else ""
	elif t == "wall_start" or t == "wall_end":
		conns = _pt_rot_conns(t == "wall_end", false, t == "wall_start", true, rot)
	elif t in ["curve", "curve_alt", "ice_curve", "race_curve", "sand_curve", "water_curve", "glue_curve"]:
		match rot:
			0:   conns = {"N": false, "E": true,  "S": true,  "W": false}
			90:  conns = {"N": false, "E": false, "S": true,  "W": true}
			180: conns = {"N": true,  "E": false, "S": false, "W": true}
			270: conns = {"N": true,  "E": true,  "S": false, "W": false}
			_:   conns = {}
	else:
		return ""
	if not conns.get(entry, false):
		return ""
	for dir in ["N", "E", "S", "W"]:
		if conns.get(dir, false) and dir != entry:
			return dir
	return ""


# Verbindungs-Dictionary aus der Basislage (rot=0) um `rot` Grad im Uhrzeigersinn drehen.
func _pt_rot_conns(bn: bool, be: bool, bs: bool, bw: bool, rot: int) -> Dictionary:
	var steps := (rot / 90) % 4
	for _i in range(steps):
		var tn = bw; var te = bn; var ts = be; var tw = bs
		bn = tn; be = te; bs = ts; bw = tw
	return {"N": bn, "E": be, "S": bs, "W": bw}


func _pt_portal_open_dir(rot: int) -> String:
	return ["W", "N", "E", "S"][(int(rot) / 90) % 4]


func _pt_step(row: int, col: int, dir: String) -> Vector2i:
	match dir:
		"N": return Vector2i(row - 1, col)
		"S": return Vector2i(row + 1, col)
		"E": return Vector2i(row, col + 1)
		"W": return Vector2i(row, col - 1)
	return Vector2i(-1, -1)


func _pt_opp(dir: String) -> String:
	match dir:
		"N": return "S"
		"S": return "N"
		"E": return "W"
		"W": return "E"
	return ""


func _pt_in_bounds(cell: Vector2i, rows: int, cols: int) -> bool:
	return cell.x >= 0 and cell.x < rows and cell.y >= 0 and cell.y < cols


# True, wenn das Tile eine Rampe ist und exit_dir zur Partner-Kachel zeigt (Sprung übers Mittelfeld).
func _pt_ramp_jumps_toward(data, row: int, col: int, exit_dir: String) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var t = data.get("type", "")
	if t != "ramp_start" and t != "ramp_end":
		return false
	var pr := int(data.get("ramp_partner_row", -1))
	var pc := int(data.get("ramp_partner_col", -1))
	if pr < 0 or pc < 0:
		return false
	var to_dir := ""
	if pc > col: to_dir = "E"
	elif pc < col: to_dir = "W"
	elif pr > row: to_dir = "S"
	elif pr < row: to_dir = "N"
	return to_dir == exit_dir


func generate(grid_state: Array) -> void:
	for child in get_children():
		child.queue_free()

	var grid_rows = grid_state.size()
	var grid_cols = grid_state[0].size() if grid_rows > 0 else 0
	# Welches der beiden Portale ist der Ausgang (orange)? Ergibt sich aus der gefahrenen Route
	# (Eingang = zuerst angefahrenes Portal). (-1,-1) wenn unbestimmt → beide bleiben Eingang/blau.
	var portal_exit := _portal_exit_cell(grid_state)

	for row in range(grid_rows):
		for col in range(grid_cols):
			var d = grid_state[row][col]
			if typeof(d) != TYPE_DICTIONARY:
				continue

			# curve_alt hat dieselbe 3D-Form wie curve
			if d["type"] == "ramp_start" or d["type"] == "ramp_end":
				# Rampe als EIN GLB: nur am ramp_start-Feld instanzieren; das ramp_end-Feld bleibt
				# leer. Das Modell selbst deckt die ganze Rampe ab (Absprung -> Landung).
				if d["type"] == "ramp_end":
					continue
				var ramp = _make_straight_model(Paths.MODEL_TRACK_RAMP)
				ramp.position = Vector3(
					col * TILE_SIZE + TILE_SIZE / 2.0, 0.0,
					row * TILE_SIZE + TILE_SIZE / 2.0
				)
				ramp.rotation_degrees.y = -d["rotation"] + RAMP_MODEL_YAW_OFFSET
				add_child(ramp)
				continue

			# Steilwandkurve: EIN GLB deckt beide Haarnadel-Kacheln ab (wie die Rampe). Nur am
			# wall_start instanzieren, wall_end bleibt leer. Platziert auf dem Mittelpunkt zwischen
			# beiden Kacheln (= gemeinsame Apex-Kante), sodass das 2-Kachel-Modell beide ausfüllt.
			if d["type"] == "wall_start" or d["type"] == "wall_end":
				if d["type"] == "wall_end":
					continue
				var pr := int(d.get("ramp_partner_row", row))
				var pc := int(d.get("ramp_partner_col", col))
				# Mittelpunkt beider Kacheln + Korrektur-Verschiebung entlang der Achse Start→Partner.
				var pdir := Vector3(pc - col, 0.0, pr - row)
				if pdir.length() > 0.0:
					pdir = pdir.normalized()
				var wall = _make_curve_model(Paths.MODEL_TRACK_WALL)
				wall.position = Vector3(
					(col + pc) * 0.5 * TILE_SIZE + TILE_SIZE / 2.0, 0.0,
					(row + pr) * 0.5 * TILE_SIZE + TILE_SIZE / 2.0
				) + pdir * (TILE_SIZE * WALL_MODEL_SHIFT_TILES)
				wall.rotation_degrees.y = -d["rotation"] + WALL_MODEL_YAW_OFFSET
				add_child(wall)
				continue

			# Looping: eigenes Loop-GLB (Einzelfeld, Basislage S→N wie eine Gerade).
			if d["type"] == "loop":
				var loop = _make_straight_model(Paths.MODEL_TRACK_LOOP)
				loop.position = Vector3(
					col * TILE_SIZE + TILE_SIZE / 2.0, 0.0,
					row * TILE_SIZE + TILE_SIZE / 2.0
				)
				loop.rotation_degrees.y = -d["rotation"] + LOOP_MODEL_YAW_OFFSET
				add_child(loop)
				continue

			# Portal: zwei GLBs auf EINER Kachel – die Rampe (zur Straße, befahrbar) und das Tor
			# dahinter. Blau = Eingang, Orange = Ausgang. Beide hängen an einem Knoten, der über die
			# Tile-Rotation in die Weltlage gedreht wird (Basislage rot=0: offen nach West).
			if d["type"] == "portal":
				var is_exit := portal_exit.x >= 0 and Vector2i(row, col) == portal_exit
				var portal_node = Node3D.new()
				portal_node.position = Vector3(
					col * TILE_SIZE + TILE_SIZE / 2.0, 0.0,
					row * TILE_SIZE + TILE_SIZE / 2.0
				)
				portal_node.rotation_degrees.y = -d["rotation"] + PORTAL_MODEL_YAW_OFFSET
				portal_node.add_child(_make_straight_model(Paths.MODEL_TRACK_PORTAL_RAMP))
				var gate_path: String = Paths.MODEL_TRACK_PORTAL_ORANGE if is_exit else Paths.MODEL_TRACK_PORTAL_BLUE
				portal_node.add_child(_make_straight_model(gate_path))
				add_child(portal_node)
				continue

			if d["type"] == "stand":
				# Tribuene: pro Stapel-Anzahl ein eigenes, fertig arrangiertes GLB
				# (Stand1..Stand4, siehe _build_stand_stack / Paths.stand_model).
				var stack := int(d.get("stack", 1))
				var stand = _build_stand_stack(stack)
				stand.position = Vector3(
					col * TILE_SIZE + TILE_SIZE / 2.0, 0.0,
					row * TILE_SIZE + TILE_SIZE / 2.0
				)
				# Stand1 ist im Asset um 180° verdreht → für den Einer-Stapel ausgleichen.
				var stand_extra := 180.0 if clampi(stack, 1, 4) == 1 else 0.0
				stand.rotation_degrees.y = -d["rotation"] + STAND_MODEL_YAW_OFFSET + stand_extra
				add_child(stand)
				continue

			var tile_pos = Vector3(
				col * TILE_SIZE + TILE_SIZE / 2.0,
				0.0,
				row * TILE_SIZE + TILE_SIZE / 2.0
			)

			# Gerade: GLB-Modell. Eisgerade nutzt dieselbe Geraden-Form/Skalierung, aber das
			# eigene Ice-GLB (mit Eis-Textur); Dirt = eigenes Dreck-GLB, sonst Default.
			if d["type"] in ["straight", "ice", "race_straight", "sand_straight", "water_straight", "glue_straight"]:
				var model_path: String
				if d["type"] == "ice":
					model_path = Paths.MODEL_TRACK_STRAIGHT_ICE
				elif d["type"] == "race_straight":
					# Rennstrecke: eigenes Renn-Geraden-GLB (eigene gebackene Textur).
					model_path = Paths.MODEL_TRACK_STRAIGHT_RACING
				elif d["type"] == "sand_straight":
					model_path = Paths.MODEL_TRACK_STRAIGHT_SAND
				elif d["type"] == "water_straight":
					model_path = Paths.MODEL_TRACK_STRAIGHT_WATER
				elif d["type"] == "glue_straight":
					model_path = Paths.MODEL_TRACK_STRAIGHT_GLUE
				elif d.get("is_dirt", false):
					model_path = Paths.MODEL_TRACK_STRAIGHT_DIRT
				else:
					model_path = Paths.MODEL_TRACK_STRAIGHT_DEFAULT
				var straight = _make_straight_model(model_path)
				straight.position = tile_pos
				straight.rotation_degrees.y = -d["rotation"] + STRAIGHT_MODEL_YAW_OFFSET
				if d["type"] == "ice":
					_apply_ice_look(straight)
				add_child(straight)
				continue

			# Kurve (curve / curve_alt / ice_curve / race_curve):
			# Jeder Belag hat jetzt sein eigenes Kurven-GLB (Road/Dirt/Ice/Race). curve und curve_alt
			# teilen dieselbe Bogenform (nur die Fahrtrichtung unterscheidet sich) -> gleiche Modell-Auswahl
			# wie bei der Geraden. Damit entfaellt die prozedurale Dreck-Kurve und das Eis-Overlay.
			var curve_path: String
			if d["type"] == "ice_curve":
				curve_path = Paths.MODEL_TRACK_CURVE_ICE
			elif d["type"] == "race_curve":
				curve_path = Paths.MODEL_TRACK_CURVE_RACING
			elif d["type"] == "sand_curve":
				curve_path = Paths.MODEL_TRACK_CURVE_SAND
			elif d["type"] == "water_curve":
				curve_path = Paths.MODEL_TRACK_CURVE_WATER
			elif d["type"] == "glue_curve":
				curve_path = Paths.MODEL_TRACK_CURVE_GLUE
			elif d.get("is_dirt", false):
				curve_path = Paths.MODEL_TRACK_CURVE_DIRT
			else:
				curve_path = Paths.MODEL_TRACK_CURVE_DEFAULT
			var curve = _make_curve_model(curve_path)
			curve.position = tile_pos
			# Das WaterCurve-GLB ist 180° verdreht modelliert → nur für Wasser zusätzlich umdrehen.
			var curve_extra_yaw := 180.0 if d["type"] == "water_curve" else 0.0
			curve.rotation_degrees.y = -d["rotation"] + CURVE_MODEL_YAW_OFFSET + curve_extra_yaw
			if d["type"] == "ice_curve":
				_apply_ice_look(curve)
			add_child(curve)
