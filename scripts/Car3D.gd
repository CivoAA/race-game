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

# Das Blender-Testmodell ist um 90° verdreht exportiert (fährt mit der rechten Tür voran) →
# nur dieses Modell um die Hochachse korrigieren. Falls dann die LINKE Tür vorn ist: Vorzeichen drehen.
const TEST_CAR_YAW_FIX = -90.0

var model: Node3D = null
var _meshes: Array = []
var _paint_shader: Shader = null
var _flat_shader: Shader = null
# Blender-Testmodell hat keine Lack-Maske, sondern flache Material-Farben → Umfärben per „Color-Key"
# (nur die Karosserie-Materialfläche, das helle Grün) statt Masken-Shader.
var _color_key: bool = false

# Super-Auto („Auto 2"): eigenes Modell (eric_car), KEINE Werkstatt-Lackierung. Von CarController
# vor dem add_child() gesetzt, damit _load_model() in _ready() schon das richtige Modell wählt.
var is_super: bool = false


func _ready() -> void:
	_load_model()
	# Lackierung in der Werkstatt geändert → Auto live umfärben. Nur Stufen mit Umfärb-Maske
	# (Test-Auto Stufe 0, Frosch Stufe 2) bzw. das Blender-Testmodell (Color-Key); "Renn"auto
	# (Stufe 1) hat keine Maske.
	if (_color_key or Economy.tier_has_mask()) and not Economy.car_paint_changed.is_connected(_apply_paint):
		Economy.car_paint_changed.connect(_apply_paint)


func _load_model() -> void:
	# Tier-Auto (is_super) nutzt das Modell der aktuellen Auto-Prestige-Stufe; normale Autos
	# das Test-Auto (mit Umfärb-Maske für die Werkstatt-Lackierung).
	# Reiner Test-Schalter (Garage „Test-Auto"): überschreibt alles mit dem Blender-Testmodell.
	var path := Economy.get_car_tier_model() if is_super else Paths.MODEL_TEST_CAR
	if Economy.test_blender_car:
		path = Paths.MODEL_TEST_CAR_BLENDER
	_color_key = (path == Paths.MODEL_TEST_CAR_BLENDER)
	if ResourceLoader.exists(path):
		var scene = load(path)
		model = scene.instantiate()
		# Das Blender-Testmodell ist ~4× zu groß exportiert → nur dieses auf ¼ herunterskalieren.
		model.scale = (MODEL_SCALE * 0.25) if path == Paths.MODEL_TEST_CAR_BLENDER else MODEL_SCALE
		# … und um 90° verdreht → nur dieses Modell zurückdrehen, damit die Front nach vorne zeigt.
		if path == Paths.MODEL_TEST_CAR_BLENDER:
			model.rotation_degrees.y = TEST_CAR_YAW_FIX
		model.position.y = CAR_Y
		add_child(model)
		# Alpha-Texturen (Alpha-Kanal) auf Scissor stellen → keine Transparenz-Sortierfehler.
		MaterialUtil.apply_alpha_scissor(model)
		# Unbeleuchtet wie der Rest des 3D-Views. Der Lack-/Muster-Shader (für Tier-0-Auto) bringt
		# seine eigene Unshaded-Optik mit; hier werden die übrigen GLB-Materialien (Tier-Autos,
		# nicht umgefärbte Teile) flach geschaltet.
		MaterialUtil.apply_unshaded(model)
		_meshes.clear()
		_collect_meshes(model)
		# Lackierung nur für Stufen mit Umfärb-Maske (Stufe 0 Test-Auto, Stufe 2 Frosch) bzw. das
		# Blender-Testmodell (Color-Key). "Renn"auto (Stufe 1) hat keine Maske und behält seine Textur.
		if _color_key or Economy.tier_has_mask():
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
	# Blender-Testmodell: kein Masken-Shader, sondern nur die grüne Karosserie-Fläche umfärben.
	if _color_key:
		_apply_paint_colorkey()
		return
	var mat: ShaderMaterial = null
	# Maskenmaterial auch ohne Lack anlegen, sobald ein Muster gewählt ist – so wirkt das
	# Muster auch auf der Original-(Standard-)Farbe (paint_on=false im Shader).
	if Economy.is_car_paint_on() or Economy.get_car_pattern() != 0:
		mat = _make_paint_material(Economy.get_car_paint_color())
	for m in _meshes:
		if is_instance_valid(m):
			(m as MeshInstance3D).material_override = mat


# Färbt/mustert im Blender-Testmodell NUR die grüne Karosserie-Materialfläche um (per Surface-Override),
# alle anderen Flächen bleiben unangetastet. Lack aus + kein Muster → Override weg (Original-Grün zurück).
func _apply_paint_colorkey() -> void:
	for m in _meshes:
		if not is_instance_valid(m):
			continue
		var mi := m as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var src := mesh.surface_get_material(si)
			if _is_test_body_material(src):
				mi.set_surface_override_material(si, _make_body_material(src))


# Baut das Lack-/Muster-Material für die Karosserie-Fläche. Grundfarbe = Lackfarbe (Lack an) bzw.
# Originalfarbe der Fläche (Lack aus). Ohne Lack UND ohne Muster → null (Originalmaterial behalten).
func _make_body_material(orig: Material) -> ShaderMaterial:
	var paint_on := Economy.is_car_paint_on()
	var pat := Economy.get_car_pattern()
	if not paint_on and pat == 0:
		return null
	if _flat_shader == null and ResourceLoader.exists(Paths.SHADER_CAR_PAINT_FLAT):
		_flat_shader = load(Paths.SHADER_CAR_PAINT_FLAT)
	var base: Color = Economy.get_car_paint_color()
	if not paint_on and orig is BaseMaterial3D:
		base = (orig as BaseMaterial3D).albedo_color
	var mat := ShaderMaterial.new()
	mat.shader = _flat_shader
	mat.set_shader_parameter("body_color", base)
	mat.set_shader_parameter("pattern_mode", pat)
	mat.set_shader_parameter("pattern_color", Economy.get_car_pattern_color())
	if orig is BaseMaterial3D:
		mat.set_shader_parameter("metallic_v", (orig as BaseMaterial3D).metallic)
		mat.set_shader_parameter("roughness_v", (orig as BaseMaterial3D).roughness)
	return mat


# Erkennt die umfärbbare Karosserie-Fläche: zuerst über den Material-Namen, ersatzweise über die
# Farbe (kräftig grün: hoher Grünanteil, wenig Rot/Blau) – schließt die gelbgrünen „Light"-Teile aus.
func _is_test_body_material(mat: Material) -> bool:
	if mat == null:
		return false
	if mat.resource_name == Paths.TEST_CAR_BODY_MATERIAL:
		return true
	if mat is BaseMaterial3D:
		# Grün klar dominant (Verhältnis-Test → robust gegen linear/sRGB); schließt das gelbgrüne
		# „Light"-Material (hoher Rotanteil) aus.
		var c := (mat as BaseMaterial3D).albedo_color
		return c.g > 0.4 and c.g > c.r * 1.8 and c.g > c.b * 1.8
	return false


func _make_paint_material(col: Color) -> ShaderMaterial:
	if _paint_shader == null and ResourceLoader.exists(Paths.SHADER_CAR_PAINT):
		_paint_shader = load(Paths.SHADER_CAR_PAINT)
	var mat := ShaderMaterial.new()
	mat.shader = _paint_shader
	# Albedo + Maske der aktuellen Auto-Stufe (Stufe 0 Test-Auto, Stufe 2 Frosch/Miata).
	var albedo_path := Economy.get_car_tier_albedo()
	var mask_path   := Economy.get_car_tier_mask()
	if ResourceLoader.exists(albedo_path):
		mat.set_shader_parameter("albedo_tex", load(albedo_path))
	if ResourceLoader.exists(mask_path):
		mat.set_shader_parameter("mask_tex", load(mask_path))
	mat.set_shader_parameter("paint_color", col)
	mat.set_shader_parameter("paint_on", Economy.is_car_paint_on())
	# Muster (0 = keins) nur über die Maskenbereiche legen.
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
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position.y = CAR_Y
	add_child(mi)
