extends Node3D

const CAM_ANGLE_DEG = 70.0
const CAM_DISTANCE  = 9.0
const CAM_FOV       = 45.0
const SUN_ENERGY    = 1.3
const SUN_ANGLE_DEG = 55.0
const GROUND_SIZE   = 20.0
const GROUND_COLOR  = Color(0.22, 0.38, 0.18)
const GROUND_Y      = -0.02
const TILE_SIZE_3D  = 1.2
const GRID_SIZE     = 4
const TRACK_HALF    = (GRID_SIZE * TILE_SIZE_3D) / 2.0

@onready var camera:     Camera3D           = $Camera3D
@onready var sun:        DirectionalLight3D = $DirectionalLight3D
@onready var env_node:   WorldEnvironment   = $WorldEnvironment
@onready var ground:     MeshInstance3D     = $Ground
@onready var track_root: Node3D             = $TrackRoot

var generator: Node3D = null


func _ready() -> void:
	_setup_environment()
	_setup_sun()
	_setup_camera()
	_setup_ground()
	_setup_generator()

	# Grid-State von Main übernehmen – oder Testdaten falls direkt gestartet
	var grid_state: Array
	if Engine.has_meta("pending_grid_state"):
		grid_state = Engine.get_meta("pending_grid_state")
		Engine.remove_meta("pending_grid_state")
	else:
		# Testdaten für direkten Start von World3D.tscn
		var sh  = {"type": "straight", "rotation": 0,  "flipped": false}  # horizontal
		var sv  = {"type": "straight", "rotation": 90, "flipped": false}  # vertikal
		# Ecken aus _get_connections Lookup:
		# oben-links:   S+E offen → rot=180, flip=true
		# oben-rechts:  W+S offen → rot=90,  flip=true
		# unten-links:  E+N offen → rot=270, flip=true
		# unten-rechts: N+W offen → rot=0,   flip=true
		var c_ol = {"type": "curve", "rotation": 180, "flipped": true}
		var c_or = {"type": "curve", "rotation": 90,  "flipped": true}
		var c_ul = {"type": "curve", "rotation": 270, "flipped": true}
		var c_ur = {"type": "curve", "rotation": 0,   "flipped": true}
		grid_state = [
			[c_ol, sh,  sh,  c_or],
			[sv,   "",  "",  sv  ],
			[sv,   "",  "",  sv  ],
			[c_ul, sh,  sh,  c_ur],
		]

	generator.generate(grid_state)
	_start_car(grid_state)




# ── Start-Tile ────────────────────────────────────────────────────────────────

func _insert_start_tile(grid_state: Array) -> Array:
	# Schon vorhanden?
	for row in range(4):
		for col in range(4):
			var d = grid_state[row][col]
			if typeof(d) == TYPE_DICTIONARY and d.get("is_start", false):
				return grid_state

	# Mittleres 2x2 bevorzugen
	for pos in [[1,1],[1,2],[2,1],[2,2]]:
		var r = pos[0]; var col = pos[1]
		if typeof(grid_state[r][col]) != TYPE_DICTIONARY:
			grid_state[r][col] = {"type":"straight","rotation":0,"flipped":false,"is_start":true}
			print("Start-Tile bei [%d,%d]" % [r, col])
			return grid_state

	# Irgendein freies Feld
	for row in range(4):
		for col in range(4):
			if typeof(grid_state[row][col]) != TYPE_DICTIONARY:
				grid_state[row][col] = {"type":"straight","rotation":0,"flipped":false,"is_start":true}
				return grid_state

	return grid_state

# ── Zurück zum Bauplan ────────────────────────────────────────────────────────

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back_pressed()


# ── Setup ─────────────────────────────────────────────────────────────────────

func _setup_generator() -> void:
	var script = load("res://scripts/TrackGenerator3D.gd")
	generator = Node3D.new()
	generator.set_script(script)
	track_root.add_child(generator)


func _setup_environment() -> void:
	var env = Environment.new()
	env.background_mode      = Environment.BG_COLOR
	env.background_color     = Color(0.53, 0.73, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.6, 0.65, 0.7)
	env.ambient_light_energy = 0.5
	env_node.environment = env


func _setup_sun() -> void:
	sun.light_energy     = SUN_ENERGY
	sun.shadow_enabled   = true
	sun.rotation_degrees = Vector3(-SUN_ANGLE_DEG, 30, 0)


func _setup_camera() -> void:
	camera.fov = CAM_FOV
	var angle_rad = deg_to_rad(CAM_ANGLE_DEG)
	camera.position = Vector3(
		TRACK_HALF,
		CAM_DISTANCE * sin(angle_rad),
		TRACK_HALF + CAM_DISTANCE * cos(angle_rad)
	)
	camera.look_at(Vector3(TRACK_HALF, 0, TRACK_HALF), Vector3.UP)


func _setup_ground() -> void:
	var plane    = PlaneMesh.new()
	plane.size   = Vector2(GROUND_SIZE, GROUND_SIZE)
	ground.mesh  = plane
	var mat      = StandardMaterial3D.new()
	mat.albedo_color     = GROUND_COLOR
	mat.roughness        = 0.9
	ground.material_override = mat
	ground.position = Vector3(TRACK_HALF, GROUND_Y, TRACK_HALF)


# ── Auto ──────────────────────────────────────────────────────────────────────
var car_controller: Node3D = null

func _start_car(grid_state: Array) -> void:
	var script = load("res://scripts/CarController.gd")
	car_controller = Node3D.new()
	car_controller.set_script(script)
	$CarRoot.add_child(car_controller)
	# Kurz warten damit TrackGenerator fertig ist
	await get_tree().process_frame
	car_controller.start(grid_state)
