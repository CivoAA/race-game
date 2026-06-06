extends Node3D

const TILE_SIZE = 1.2
const ROAD_Y    = 0.01

# Gerade GLB-Modelle laufen entlang einer Achse. Falls das Modell quer statt
# längs in der Kachel liegt, hier 90 eintragen (Yaw-Korrektur in Grad).
const STRAIGHT_MODEL_YAW_OFFSET = 90.0

# Yaw-Korrektur für das Default-Kurven-GLB (Grad). Die Engine-Kurve bei rot=0 verbindet
# Süd- und Ost-Kante; falls das Modell anders ausgerichtet ist, hier in 90°-Schritten anpassen.
const CURVE_MODEL_YAW_OFFSET = 180.0

# Gerade und Kurve wurden auf demselben 3×3-Modellraster gebaut: eine Spielkachel
# entspricht 3 Rasterzellen, also 3.0 Modell-Einheiten Kantenlänge. Beide Modelle mit
# DEMSELBEN Faktor (TILE_SIZE / MODEL_TILE_NATIVE) skalieren und am Modell-Ursprung
# (= Mittelzelle) zentrieren → gleiche Straßenbreite (1 Zelle) und nahtlose Übergänge.
# NICHT über die einzelne Modell-AABB normieren: die Kurve belegt nur einen 2×2-Ausschnitt
# des Rasters, ihre AABB ist also kleiner als eine ganze Kachel.
const MODEL_TILE_NATIVE = 3.0

# Steilwandkurve (Carrera-Stil): Querneigung der Fahrbahn am Apex + leichte Mittellinien-Höhe.
# Muss zu CarController passen (WALL_PEAK_H = Höhenprofil der Wegpunkte). KEINE separate Wand mehr –
# die Fahrbahn selbst ist die Steilkurve, damit die Autos nicht verdeckt werden.
const WALL_PEAK_H     = 0.15
const WALL_BANK_DEG   = 60.0
const WALL_SEGS       = 40    # feine Geometrie (≥4× so viele Segmente wie zuvor)


# Baut eine Steilkurven-Hälfte (Viertelbogen) prozedural als GEBANKTE Fahrbahn (Carrera-Steilkurve,
# 60°), ohne verdeckende Wand. Basislage rot=0; die Node-Rotation in generate() (-d["rotation"])
# dreht das Ganze in die Weltlage. Geometrie folgt denselben CarController-Wegpunkten (gleiche
# Bogenformel, Apex = gemeinsame Kante beider Kacheln, dort maximale Neigung).
func _build_wall_mesh(node: Node3D, is_start: bool) -> void:
	var half   = TILE_SIZE / 2.0
	var road_w = TILE_SIZE * 0.62
	var kerb_w = TILE_SIZE * 0.05
	var road_col = Color(0.21, 0.22, 0.27)
	var kerb_a   = Color(0.92, 0.92, 0.95)
	var kerb_b   = Color(0.85, 0.20, 0.18)

	# Bogen-Parameter für die Basislage (rot=0): wall_start = eff90, wall_end = eff180.
	var cx: float; var cz: float; var a_from: float; var a_to: float
	if is_start:
		cx = -half; cz =  half; a_from = PI * 1.5; a_to = PI * 2.0
	else:
		cx = -half; cz = -half; a_from = 0.0;      a_to = PI * 0.5
	var arc_center = Vector3(cx, 0.0, cz)
	var apex = Vector3(0.0, 0.0, half if is_start else -half)
	var d_max: float = half * sqrt(2.0)
	var segs = WALL_SEGS

	for i in range(segs):
		var tm = (float(i) + 0.5) / segs
		var ang = lerp(a_from, a_to, tm)
		var p = Vector3(cx + cos(ang) * half, 0.0, cz + sin(ang) * half)
		var d = Vector2(p.x - apex.x, p.z - apex.z).length()
		var hf = clampf(1.0 - d / d_max, 0.0, 1.0)
		hf = smoothstep(0.0, 1.0, hf)   # gerundeter Scheitel statt spitzer ∧-Übergang an der Naht
		var h = WALL_PEAK_H * hf
		# Tangente (Fahrtrichtung) und Außenradiale (von der Bogenmitte weg).
		var dir_sign = 1.0 if a_to > a_from else -1.0
		var tang = (Vector3(-sin(ang), 0.0, cos(ang)) * dir_sign).normalized()
		var yaw  = atan2(tang.x, tang.z)
		var radial = (p - arc_center); radial.y = 0.0; radial = radial.normalized()
		var seg_len = (PI * 0.5 * half) / segs + 0.02   # Bogenlänge eines Segments + Überlappung

		# Querneigung der Fahrbahn (außen hoch). Vorzeichen so wählen, dass die Außenkante steigt.
		var basis_yaw = Basis(Vector3.UP, yaw)
		var local_x   = basis_yaw.x                       # Querachse der Fahrbahn (vor Roll)
		var roll_sign = signf(radial.dot(local_x))
		var bank = deg_to_rad(WALL_BANK_DEG) * hf * roll_sign
		var road_basis = basis_yaw * Basis(Vector3(0, 0, 1), bank)
		var seg_pos = Vector3(p.x, ROAD_Y + h, p.z)

		# Gebanktes Fahrbahn-Segment (die Steilkurve selbst – Autos fahren oben drauf, sichtbar).
		var road = MeshInstance3D.new()
		var rbox = BoxMesh.new()
		rbox.size = Vector3(road_w, 0.05, seg_len)
		road.mesh = rbox
		road.material_override = _wall_mat(road_col)
		road.transform = Transform3D(road_basis, seg_pos)
		node.add_child(road)

		# Flache Rot-Weiß-Randsteine an beiden Kanten (in der Bankebene → verdecken nichts).
		for s in [-1.0, 1.0]:
			var kerb = MeshInstance3D.new()
			var kbox = BoxMesh.new()
			kbox.size = Vector3(kerb_w, 0.05, seg_len)
			kerb.mesh = kbox
			kerb.material_override = _wall_mat(kerb_a if i % 2 == 0 else kerb_b)
			var off = road_basis * Vector3(s * (road_w / 2.0 + kerb_w / 2.0), 0.0, 0.0)
			kerb.transform = Transform3D(road_basis, seg_pos + off)
			node.add_child(kerb)


func _wall_mat(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	return mat


func _build_ramp_mesh(node: Node3D, is_start: bool) -> void:
	var road_w = TILE_SIZE * 0.50
	var kerb_w = TILE_SIZE * 0.07
	var peak_h = 0.35
	var segs   = 6
	var ramp_col = Color(0.95, 0.55, 0.08)

	for i in range(segs):
		var t = (float(i) + 0.5) / segs
		var h = peak_h * (t if is_start else (1.0 - t))
		var x = -TILE_SIZE / 2.0 + TILE_SIZE * t
		var seg_len = TILE_SIZE / segs + 0.01

		# Fahrbahn-Segment bei dieser Höhe
		node.add_child(_box(
			Vector3(seg_len, 0.02, road_w),
			Color(0.20, 0.20, 0.22),
			Vector3(x, ROAD_Y + h, 0)
		))
		# Randsteine
		for s in [-1, 1]:
			node.add_child(_box(
				Vector3(seg_len, 0.03, kerb_w),
				Color(0.85, 0.82, 0.75),
				Vector3(x, ROAD_Y + h + 0.01, s * (road_w / 2.0 + kerb_w / 2.0))
			))

	# Orange Markierung am höchsten Punkt (Absprung/Landung)
	var peak_x = (TILE_SIZE / 2.0 - TILE_SIZE / segs) * (1.0 if is_start else -1.0)
	node.add_child(_box(
		Vector3(TILE_SIZE / segs, 0.015, road_w * 0.85),
		ramp_col,
		Vector3(peak_x, ROAD_Y + peak_h + 0.012, 0)
	))


# Lädt ein Geraden-GLB, skaliert es auf TILE_SIZE und zentriert es auf der Kachel.
func _make_straight_model(path: String) -> Node3D:
	var holder = Node3D.new()
	var scene = load(path)
	if scene == null:
		push_error("Geraden-Modell nicht gefunden: " + path)
		return holder

	var inst = scene.instantiate()
	holder.add_child(inst)

	var aabb = _local_aabb(inst)
	if aabb.size.z > 0.0:
		# Gemeinsamer Rastermaßstab (Kachel = 3 Modellzellen), uniform – Straße bleibt
		# 1 Zelle breit und füllt die Kachel der Länge nach. Am Modell-Ursprung zentriert
		# (die Gerade ist symmetrisch), nur vertikal auf den Boden gesetzt.
		var s = TILE_SIZE / MODEL_TILE_NATIVE
		inst.scale = Vector3(s, s, s)
		inst.position = Vector3(0.0, -aabb.position.y * s, 0.0)
	return holder


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


func _box(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi  = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mi.mesh  = box
	var mat  = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.85
	mi.material_override = mat
	mi.position = pos
	return mi


func _apply_dirt_material(node: Node) -> void:
	if node is MeshInstance3D:
		var box = node.mesh as BoxMesh
		if box != null:
			var mat = StandardMaterial3D.new()
			mat.roughness = 0.95
			if abs(box.size.y - 0.015) < 0.001:
				box.size.z *= 0.50
				mat.albedo_color = Color(0.48, 0.30, 0.11)
			else:
				mat.albedo_color = Color(0.12, 0.14, 0.10)
			node.material_override = mat
	for child in node.get_children():
		_apply_dirt_material(child)


func generate(grid_state: Array) -> void:
	for child in get_children():
		child.queue_free()

	var grid_rows = grid_state.size()
	var grid_cols = grid_state[0].size() if grid_rows > 0 else 0

	for row in range(grid_rows):
		for col in range(grid_cols):
			var d = grid_state[row][col]
			if typeof(d) != TYPE_DICTIONARY:
				continue

			# curve_alt hat dieselbe 3D-Form wie curve
			# Rampe: programmatisch generiert, keine Szene
			if d["type"] == "ramp_start" or d["type"] == "ramp_end":
				var ramp_node = Node3D.new()
				ramp_node.position = Vector3(
					col * TILE_SIZE + TILE_SIZE / 2.0, 0.0,
					row * TILE_SIZE + TILE_SIZE / 2.0
				)
				ramp_node.rotation_degrees.y = -d["rotation"]
				_build_ramp_mesh(ramp_node, d["type"] == "ramp_start")
				add_child(ramp_node)
				continue

			# Steilwandkurve: prozedural (ansteigende, geneigte Fahrbahn + 70°-Außenwand).
			if d["type"] == "wall_start" or d["type"] == "wall_end":
				var wall_node = Node3D.new()
				wall_node.position = Vector3(
					col * TILE_SIZE + TILE_SIZE / 2.0, 0.0,
					row * TILE_SIZE + TILE_SIZE / 2.0
				)
				wall_node.rotation_degrees.y = -d["rotation"]
				_build_wall_mesh(wall_node, d["type"] == "wall_start")
				add_child(wall_node)
				continue

			var tile_pos = Vector3(
				col * TILE_SIZE + TILE_SIZE / 2.0,
				0.0,
				row * TILE_SIZE + TILE_SIZE / 2.0
			)

			# Gerade: GLB-Modell. Eisgerade nutzt dieselbe Geraden-Form/Skalierung, aber das
			# eigene Ice-GLB (mit Eis-Textur); Dirt = eigenes Dreck-GLB, sonst Default.
			if d["type"] == "straight" or d["type"] == "ice":
				var model_path: String
				if d["type"] == "ice":
					model_path = Paths.MODEL_TRACK_STRAIGHT_ICE
				elif d.get("is_dirt", false):
					model_path = Paths.MODEL_TRACK_STRAIGHT_DIRT
				else:
					model_path = Paths.MODEL_TRACK_STRAIGHT_DEFAULT
				var straight = _make_straight_model(model_path)
				straight.position = tile_pos
				straight.rotation_degrees.y = -d["rotation"] + STRAIGHT_MODEL_YAW_OFFSET
				add_child(straight)
				continue

			# Kurve (curve / curve_alt): Default = GLB-Modell, Dirt = prozedural (+ Dirt-Material).
			# curve und curve_alt haben dieselbe Bogenform – nur die Fahrtrichtung unterscheidet sich.
			if not d.get("is_dirt", false):
				var curve = _make_curve_model(Paths.MODEL_TRACK_CURVE_DEFAULT)
				curve.position = tile_pos
				curve.rotation_degrees.y = -d["rotation"] + CURVE_MODEL_YAW_OFFSET
				add_child(curve)
				continue

			var scene = load(Paths.SCENE_TILE_CURVE_3D)
			if scene == null:
				push_error("3D-Tile-Szene nicht gefunden: " + Paths.SCENE_TILE_CURVE_3D)
				continue

			var node = scene.instantiate()
			node.position = tile_pos
			node.rotation_degrees.y = -d["rotation"]
			add_child(node)
			_apply_dirt_material(node)
