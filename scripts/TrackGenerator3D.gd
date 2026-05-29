extends Node3D
## TrackGenerator3D – liest Grid-State und baut 3D-Tiles.

const TILE_SIZE = 1.2
const ROAD_Y    = 0.01
const KERB_Y    = 0.03

const COLOR_ROAD  = Color(0.20, 0.20, 0.22)
const COLOR_KERB  = Color(0.85, 0.82, 0.75)


func generate(grid_state: Array) -> void:
	for child in get_children():
		child.queue_free()

	for row in range(4):
		for col in range(4):
			var tile_type: String = grid_state[row][col]
			if tile_type == "":
				continue

			var world_pos = Vector3(
				col * TILE_SIZE + TILE_SIZE / 2.0,
				0.0,
				row * TILE_SIZE + TILE_SIZE / 2.0
			)

			match tile_type:
				"straight_h": _spawn_straight(world_pos, false)
				"straight_v": _spawn_straight(world_pos, true)
				"curve_ne":   _spawn_curve(world_pos, "ne")
				"curve_nw":   _spawn_curve(world_pos, "nw")
				"curve_se":   _spawn_curve(world_pos, "se")
				"curve_sw":   _spawn_curve(world_pos, "sw")


# ── Gerade ─────────────────────────────────────────────────────────────────────

func _spawn_straight(pos: Vector3, vertical: bool) -> void:
	var root = Node3D.new()
	root.position = pos
	add_child(root)

	var road_w = TILE_SIZE * 0.50
	var kerb_w = TILE_SIZE * 0.07

	if not vertical:
		root.add_child(_make_box(Vector3(TILE_SIZE, 0.015, road_w), COLOR_ROAD, Vector3(0, ROAD_Y, 0)))
		for s in [-1, 1]:
			root.add_child(_make_box(
				Vector3(TILE_SIZE, 0.025, kerb_w), COLOR_KERB,
				Vector3(0, KERB_Y, s * (road_w / 2.0 + kerb_w / 2.0))
			))
	else:
		root.add_child(_make_box(Vector3(road_w, 0.015, TILE_SIZE), COLOR_ROAD, Vector3(0, ROAD_Y, 0)))
		for s in [-1, 1]:
			root.add_child(_make_box(
				Vector3(kerb_w, 0.025, TILE_SIZE), COLOR_KERB,
				Vector3(s * (road_w / 2.0 + kerb_w / 2.0), KERB_Y, 0)
			))


# ── Kurve ──────────────────────────────────────────────────────────────────────
# Koordinatensystem: X = rechts (col), Z = unten (row)
# NE = kommt von Norden (oben, -Z) geht nach Osten (rechts, +X)
#      → Bogen liegt in der unten-rechten Ecke (+X, +Z)
#      → Kreismittelpunkt bei (+half, +half)
#      → Bogen von 180° (links vom Zentrum = Norden des Tiles) bis 270° (oben vom Zentrum = Osten)

func _spawn_curve(pos: Vector3, dir: String) -> void:
	var root = Node3D.new()
	root.position = pos
	add_child(root)

	var half      = TILE_SIZE / 2.0
	var road_r    = half          # Radius zur Straßenmitte
	var road_w    = TILE_SIZE * 0.50
	var kerb_w    = TILE_SIZE * 0.07
	var segments  = 20

	# Bogenmittelpunkt (in XZ) und Winkelbereich
	# Winkel 0° = +X (rechts), 90° = +Z (unten), 180° = -X (links), 270° = -Z (oben)
	var cx: float
	var cz: float
	var a_from: float
	var a_to: float

	match dir:
		"ne":
			# Nord↔Ost: Bogen in der unten-rechten Ecke
			cx = half;  cz = -half
			a_from = PI * 0.5;    a_to = PI              # 180°→270°
		"nw":
			# Nord↔West: Bogen in der unten-linken Ecke
			cx = -half; cz = -half
			a_from = PI * 0;      a_to = PI * 0.5        # 270°→360°
		"se":
			# Süd↔Ost: Bogen in der oben-rechten Ecke
			cx = half;  cz = half
			a_from = PI * 1.5;    a_to = PI * 1          # 90°→180°
		"sw":
			# Süd↔West: Bogen in der oben-linken Ecke
			cx = -half; cz = half
			a_from = PI * 1.5;    a_to = PI * 2          # 0°→90°

	var seg_angle = (a_to - a_from) / float(segments)

	for i in range(segments):
		var a_mid = a_from + (float(i) + 0.5) * seg_angle
		var a_rot = a_mid + PI / 2.0   # tangential zur Kurve

		# Fahrbahn-Segment
		var sx = cx + cos(a_mid) * road_r
		var sz = cz + sin(a_mid) * road_r
		var arc_len = road_r * abs(seg_angle) + 0.005

		var seg = _make_box(
			Vector3(arc_len, 0.015, road_w),
			COLOR_ROAD, Vector3(sx, ROAD_Y, sz)
		)
		seg.rotation.y = -a_rot
		root.add_child(seg)

		# Randsteine innen + außen
		for side in [-1, 1]:
			var r_k = road_r + side * (road_w / 2.0 + kerb_w / 2.0)
			var kx  = cx + cos(a_mid) * r_k
			var kz  = cz + sin(a_mid) * r_k
			var k   = _make_box(
				Vector3(arc_len, 0.025, kerb_w),
				COLOR_KERB, Vector3(kx, KERB_Y, kz)
			)
			k.rotation.y = -a_rot
			root.add_child(k)


# ── Hilfsfunktion ──────────────────────────────────────────────────────────────

func _make_box(size: Vector3, color: Color, position: Vector3) -> MeshInstance3D:
	var mi  = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mi.mesh  = box
	var mat  = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.85
	mi.material_override = mat
	mi.position = position
	return mi
