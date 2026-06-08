extends Node3D
## Das Auto – lädt das 3D-Modell und fährt später eine Route ab.
## Position und Rotation werden von außen gesetzt (durch CarController).

# Skalierung des Modells – anpassen falls zu groß/klein
# (Straße ist ~0.4 Einheiten breit; Auto kleiner gehalten, damit es auf die Bahn passt)
const MODEL_SCALE = Vector3(0.18, 0.18, 0.18)

# Höhe des Modells INNERHALB des Auto-Knotens. Die eigentliche Hover-Höhe über dem Boden
# kommt bereits aus der Wegpunkt-Höhe (CarController setzt den Auto-Knoten auf y≈0.05) –
# darum hier 0.0, sonst stapeln sich beide Offsets und das Auto schwebt über der Fahrbahn.
const CAR_Y = 0.0

var model: Node3D = null
var _meshes: Array = []
var _paint_shader: Shader = null

# Super-Auto („Auto 2"): eigenes Modell (eric_car), KEINE Werkstatt-Lackierung. Von CarController
# vor dem add_child() gesetzt, damit _load_model() in _ready() schon das richtige Modell wählt.
var is_super: bool = false


func _ready() -> void:
	_load_model()
	# Lackierung in der Werkstatt geändert → Auto live umfärben (Super-Auto bleibt unlackiert).
	if not is_super and not Economy.car_paint_changed.is_connected(_apply_paint):
		Economy.car_paint_changed.connect(_apply_paint)


func _load_model() -> void:
	# Tier-Auto (is_super) nutzt das Modell der aktuellen Auto-Prestige-Stufe; normale Autos
	# das Test-Auto (mit Umfärb-Maske für die Werkstatt-Lackierung).
	var path := Economy.get_car_tier_model() if is_super else Paths.MODEL_TEST_CAR
	if ResourceLoader.exists(path):
		var scene = load(path)
		model = scene.instantiate()
		model.scale = MODEL_SCALE
		model.position.y = CAR_Y
		add_child(model)
		_meshes.clear()
		_collect_meshes(model)
		# Nur normale Autos bekommen die Werkstatt-Lackierung; das Super-Auto behält seine Textur.
		if not is_super:
			_apply_paint()
		print("Auto-Modell geladen: ", path)
	else:
		# Fallback: einfache Box wenn kein Modell gefunden
		push_warning("Kein Modell unter '%s' gefunden – nutze Platzhalter-Box." % path)
		_spawn_placeholder()


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_meshes.append(node)
	for c in node.get_children():
		_collect_meshes(c)


# Wendet die in der Werkstatt gewählte Lackierung an: Masken-Shader (nur Karosserie,
# Verläufe bleiben) bei gesetzter Farbe, sonst Originaltextur (kein Override).
func _apply_paint() -> void:
	var mat: ShaderMaterial = null
	if Economy.is_car_paint_on():
		mat = _make_paint_material(Economy.get_car_paint_color())
	for m in _meshes:
		if is_instance_valid(m):
			(m as MeshInstance3D).material_override = mat


func _make_paint_material(col: Color) -> ShaderMaterial:
	if _paint_shader == null and ResourceLoader.exists(Paths.SHADER_CAR_PAINT):
		_paint_shader = load(Paths.SHADER_CAR_PAINT)
	var mat := ShaderMaterial.new()
	mat.shader = _paint_shader
	if ResourceLoader.exists(Paths.TEX_CAR_ALBEDO):
		mat.set_shader_parameter("albedo_tex", load(Paths.TEX_CAR_ALBEDO))
	if ResourceLoader.exists(Paths.TEX_CAR_MASK):
		mat.set_shader_parameter("mask_tex", load(Paths.TEX_CAR_MASK))
	mat.set_shader_parameter("paint_color", col)
	# Muster (0 = keins) nur über die gefärbten Maskenbereiche legen.
	mat.set_shader_parameter("pattern_mode", Economy.get_car_pattern())
	mat.set_shader_parameter("pattern_color", Economy.get_car_pattern_color())
	return mat


func _spawn_placeholder() -> void:
	var mi  = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.3, 0.15, 0.5)
	mi.mesh  = box
	var mat  = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.2)
	mi.material_override = mat
	mi.position.y = CAR_Y
	add_child(mi)
