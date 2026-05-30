extends Node3D
## Gerade bei rot=0: W↔E offen
## Einfach die ganze Node3D rotieren um andere Richtungen zu erreichen.

const TILE_SIZE = 1.2
const ROAD_Y    = 0.01
const KERB_Y    = 0.03
const COLOR_ROAD = Color(0.20, 0.20, 0.22)
const COLOR_KERB = Color(0.85, 0.82, 0.75)


func _ready() -> void:
	_build()


func _build() -> void:
	var road_w = TILE_SIZE * 0.50
	var kerb_w = TILE_SIZE * 0.07

	# Fahrbahn
	add_child(_box(Vector3(TILE_SIZE, 0.015, road_w), COLOR_ROAD, Vector3(0, ROAD_Y, 0)))

	# Randsteine
	for s in [-1, 1]:
		add_child(_box(
			Vector3(TILE_SIZE, 0.025, kerb_w), COLOR_KERB,
			Vector3(0, KERB_Y, s * (road_w / 2.0 + kerb_w / 2.0))
		))


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
