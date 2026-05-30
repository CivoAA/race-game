extends Node3D
## Kurve bei rot=0: N+E offen
## Mittelpunkt unten-rechts, Bogen 180°→270° — exakt wie Curve2D.
## Einfach die ganze Node3D rotieren um andere Richtungen zu erreichen.

const TILE_SIZE = 1.2
const ROAD_Y    = 0.01
const KERB_Y    = 0.03
const COLOR_ROAD = Color(0.20, 0.20, 0.22)
const COLOR_KERB = Color(0.85, 0.82, 0.75)


func _ready() -> void:
	_build()


func _build() -> void:
	var half   = TILE_SIZE / 2.0
	var road_r = half
	var road_w = TILE_SIZE * 0.50
	var kerb_w = TILE_SIZE * 0.07
	var segs   = 20

	# Mittelpunkt unten-rechts, Bogen 180°→270°
	var cx     = half
	var cz     = half
	var a_from = PI
	var a_to   = PI * 1.5

	var seg_angle = (a_to - a_from) / float(segs)

	for i in range(segs):
		var a_mid   = a_from + (float(i) + 0.5) * seg_angle
		var a_rot   = a_mid + PI / 2.0
		var sx      = cx + cos(a_mid) * road_r
		var sz      = cz + sin(a_mid) * road_r
		var arc_len = road_r * abs(seg_angle) + 0.005

		var seg = _box(Vector3(arc_len, 0.015, road_w), COLOR_ROAD, Vector3(sx, ROAD_Y, sz))
		seg.rotation.y = -a_rot
		add_child(seg)

		for side in [-1, 1]:
			var r_k = road_r + side * (road_w / 2.0 + kerb_w / 2.0)
			var k   = _box(
				Vector3(arc_len, 0.025, kerb_w), COLOR_KERB,
				Vector3(cx + cos(a_mid) * r_k, KERB_Y, cz + sin(a_mid) * r_k)
			)
			k.rotation.y = -a_rot
			add_child(k)


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
