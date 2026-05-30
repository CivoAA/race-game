extends Node3D
## Das Auto – lädt das 3D-Modell und fährt später eine Route ab.
## Position und Rotation werden von außen gesetzt (durch CarController).

# Pfad zum 3D-Modell – passe das an falls deine Datei anders heißt
const MODEL_PATH = "res://assets/3D-models/eric_car/Car_eric.glb"

# Skalierung des Modells – anpassen falls zu groß/klein
const MODEL_SCALE = Vector3(0.3, 0.3, 0.3)

# Höhe über dem Boden
const CAR_Y = 0.05

var model: Node3D = null


func _ready() -> void:
	_load_model()


func _load_model() -> void:
	if ResourceLoader.exists(MODEL_PATH):
		var scene = load(MODEL_PATH)
		model = scene.instantiate()
		model.scale = MODEL_SCALE
		model.position.y = CAR_Y
		add_child(model)
		print("Auto-Modell geladen: ", MODEL_PATH)
	else:
		# Fallback: einfache Box wenn kein Modell gefunden
		push_warning("Kein Modell unter '%s' gefunden – nutze Platzhalter-Box." % MODEL_PATH)
		_spawn_placeholder()


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
