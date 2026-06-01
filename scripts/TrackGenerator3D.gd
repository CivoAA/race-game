extends Node3D

const TILE_SIZE = 1.2
const ROAD_Y    = 0.01

# Gerade GLB-Modelle laufen entlang einer Achse. Falls das Modell quer statt
# längs in der Kachel liegt, hier 90 eintragen (Yaw-Korrektur in Grad).
const STRAIGHT_MODEL_YAW_OFFSET = 90.0



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
	if aabb.size.x > 0.0 and aabb.size.z > 0.0:
		var longest = max(aabb.size.x, aabb.size.z)
		var s = TILE_SIZE / longest
		inst.scale = Vector3(s, s, s)
		# horizontal mittig auf der Kachel, vertikal auf dem Boden (y=0)
		inst.position = Vector3(
			-(aabb.position.x + aabb.size.x / 2.0) * s,
			-aabb.position.y * s,
			-(aabb.position.z + aabb.size.z / 2.0) * s
		)
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

			var tile_pos = Vector3(
				col * TILE_SIZE + TILE_SIZE / 2.0,
				0.0,
				row * TILE_SIZE + TILE_SIZE / 2.0
			)

			# Gerade: GLB-Modell (Default = normal, Dirt = automatisch generiert)
			if d["type"] == "straight":
				var model_path = Paths.MODEL_TRACK_STRAIGHT_DIRT if d.get("is_dirt", false) else Paths.MODEL_TRACK_STRAIGHT_DEFAULT
				var straight = _make_straight_model(model_path)
				straight.position = tile_pos
				straight.rotation_degrees.y = -d["rotation"] + STRAIGHT_MODEL_YAW_OFFSET
				add_child(straight)
				continue

			# Kurve (curve / curve_alt): weiterhin prozedural
			var scene = load(Paths.SCENE_TILE_CURVE_3D)
			if scene == null:
				push_error("3D-Tile-Szene nicht gefunden: " + Paths.SCENE_TILE_CURVE_3D)
				continue

			var node = scene.instantiate()
			node.position = tile_pos
			node.rotation_degrees.y = -d["rotation"]
			add_child(node)
			if d.get("is_dirt", false):
				_apply_dirt_material(node)
