extends Node3D

const CAM_ANGLE_DEG = 65.0
const CAM_DISTANCE  = 13.0
const CAM_FOV       = 60.0
const SUN_ENERGY    = 1.3
const SUN_ANGLE_DEG = 55.0
const GROUND_SIZE   = 24.0
const GROUND_COLOR  = Color(0.22, 0.38, 0.18)
const GROUND_Y      = -0.02
const TILE_SIZE_3D  = 1.2
const CAR_STAGGER   = 0.5   # Sekunden Startabstand zwischen mehreren Autos

var CurrencyHudScript = load(Paths.SCRIPT_CURRENCY_HUD)

@onready var camera:     Camera3D           = $Camera3D
@onready var sun:        DirectionalLight3D = $DirectionalLight3D
@onready var env_node:   WorldEnvironment   = $WorldEnvironment
@onready var ground:     MeshInstance3D     = $Ground
@onready var track_root: Node3D             = $TrackRoot

var generator: Node3D = null
var car_controllers: Array = []

# Aus der tatsächlichen Grid-Größe berechnetes Streckenzentrum (Kamera/Boden)
var _track_cx: float = 3.6
var _track_cz: float = 3.0

# Lauf-Zustand
var _run_time_left: float = 0.0
var _run_earned:    int   = 0
var _run_active:    bool  = false

var _timer_label:  Label       = null
var _earned_label: Label       = null
var _round_label:  Label       = null
var _currency_hud              = null   # CurrencyHud-Instanz (für Gewinn-Effekt)
var _lap_running:  Array       = []     # laufender Rundenertrag je Auto


func _ready() -> void:
	var grid_state = _resolve_grid_state()

	var grid_rows = grid_state.size()
	var grid_cols = grid_state[0].size() if grid_rows > 0 else 0
	_track_cx = grid_cols * TILE_SIZE_3D / 2.0
	_track_cz = grid_rows * TILE_SIZE_3D / 2.0

	_setup_environment()
	_setup_sun()
	_setup_camera()
	_setup_ground()
	_setup_generator()
	_setup_hud()

	generator.generate(grid_state)
	_start_cars(grid_state)

	_run_time_left = Economy.get_drive_time()
	_run_active    = true
	_update_run_hud()
	_update_round_hud()


# ── Grid-Zustand ────────────────────────────────────────────────────────────────

func _resolve_grid_state() -> Array:
	if Engine.has_meta("pending_grid_state"):
		var gs = Engine.get_meta("pending_grid_state")
		Engine.remove_meta("pending_grid_state")
		return gs
	# Testdaten für direkten Start von World3D.tscn: fahrbare 5×6-Randschleife.
	# Eck-Kurven: rot0=S+E, rot90=W+S, rot180=N+W, rot270=N+E (siehe CarController).
	var sh  = {"type": "straight", "rotation": 0,   "flipped": false, "points": 1.0, "multiplier": 1.0, "variant_label": "+1"}
	var sv  = {"type": "straight", "rotation": 90,  "flipped": false, "points": 1.0, "multiplier": 1.0, "variant_label": "+1"}
	var c00 = {"type": "curve",    "rotation": 0,   "flipped": false, "points": 0.0, "multiplier": 1.0, "variant_label": ""}  # oben-links
	var c90 = {"type": "curve",    "rotation": 90,  "flipped": false, "points": 0.0, "multiplier": 1.0, "variant_label": ""}  # oben-rechts
	var c18 = {"type": "curve",    "rotation": 180, "flipped": false, "points": 0.0, "multiplier": 1.0, "variant_label": ""}  # unten-rechts
	var c27 = {"type": "curve",    "rotation": 270, "flipped": false, "points": 0.0, "multiplier": 1.0, "variant_label": ""}  # unten-links
	var ist = {"type": "straight", "rotation": 0,   "flipped": false, "is_start": true, "points": 0.0, "multiplier": 1.0, "variant_label": ""}
	return [
		[c00, ist, sh,  sh,  sh,  c90],
		[sv,  "",  "",  "",  "",  sv  ],
		[sv,  "",  "",  "",  "",  sv  ],
		[sv,  "",  "",  "",  "",  sv  ],
		[c27, sh,  sh,  sh,  sh,  c18],
	]


# ── Lauf-Schleife ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _run_active:
		return
	_run_time_left -= delta
	if _run_time_left <= 0.0:
		_run_time_left = 0.0
		_end_run()
	_update_run_hud()


func _on_lap_completed(reward: int, idx: int) -> void:
	_run_earned += reward
	if idx >= 0 and idx < _lap_running.size():
		_lap_running[idx] = 0   # Runde gutgeschrieben → laufender Zähler zurück
	_update_round_hud()
	_update_run_hud()
	# Geld wird der Hauptwährung gutgeschrieben → hübsches Feedback
	if _currency_hud != null:
		_currency_hud.gain(reward)


func _on_lap_progress(running: int, idx: int) -> void:
	if idx >= 0 and idx < _lap_running.size():
		_lap_running[idx] = running
	_update_round_hud()


func _end_run() -> void:
	_run_active = false
	for ctrl in car_controllers:
		ctrl.stop()
	Economy.save_game()
	_show_summary()


# ── HUD ─────────────────────────────────────────────────────────────────────────

func _setup_hud() -> void:
	# Gemeinsame Währungs-HUD (oben mittig, wie in der 2D-View)
	_currency_hud = CurrencyHudScript.new()
	add_child(_currency_hud)

	# Eigene HUD-Bar (Layer 9 = unter CurrencyHud Layer 10)
	# Verstärkt den CurrencyHud-Streifen zu einem soliden, durchgängigen Balken
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)

	# Dunkler, durchgehender Hintergrundbalken – volle Breite, kein sichtbarer Rand
	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(0, 0)
	bar_bg.size     = Vector2(960, 46)
	bar_bg.color    = Color(0.05, 0.06, 0.09, 0.88)
	layer.add_child(bar_bg)

	# Leuchtende Unterkante für Tiefe
	var bar_line := ColorRect.new()
	bar_line.position = Vector2(0, 45)
	bar_line.size     = Vector2(960, 1)
	bar_line.color    = Color(0.28, 0.34, 0.52, 0.90)
	layer.add_child(bar_line)

	# Timer – links, groß
	_timer_label = Label.new()
	_timer_label.position = Vector2(12, 8)
	_timer_label.size     = Vector2(210, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_timer_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 21)
	_timer_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_timer_label.add_theme_constant_override("outline_size", 3)
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	layer.add_child(_timer_label)

	# Trennlinie links nach Timer
	var sep_l := ColorRect.new()
	sep_l.position = Vector2(228, 8)
	sep_l.size     = Vector2(1, 30)
	sep_l.color    = Color(0.28, 0.34, 0.52, 0.50)
	layer.add_child(sep_l)

	# Trennlinie rechts vor Stats
	var sep_r := ColorRect.new()
	sep_r.position = Vector2(730, 8)
	sep_r.size     = Vector2(1, 30)
	sep_r.color    = Color(0.28, 0.34, 0.52, 0.50)
	layer.add_child(sep_r)

	# Laufende Runde – rechts oben
	_round_label = Label.new()
	_round_label.position = Vector2(736, 6)
	_round_label.size     = Vector2(216, 17)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_round_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_round_label.add_theme_font_size_override("font_size", 14)
	_round_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.35))
	_round_label.add_theme_constant_override("outline_size", 3)
	_round_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	layer.add_child(_round_label)

	# Lauf gesamt – rechts unten
	_earned_label = Label.new()
	_earned_label.position = Vector2(736, 24)
	_earned_label.size     = Vector2(216, 17)
	_earned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_earned_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_earned_label.add_theme_font_size_override("font_size", 13)
	_earned_label.add_theme_color_override("font_color", Color(0.50, 0.95, 0.58))
	_earned_label.add_theme_constant_override("outline_size", 3)
	_earned_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	layer.add_child(_earned_label)


func _make_hud_label(pos: Vector2, font_size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.position = pos
	lbl.size = Vector2(960, 28)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return lbl


func _update_run_hud() -> void:
	if _timer_label != null:
		_timer_label.text = "⏱  %.1f s" % _run_time_left
	if _earned_label != null:
		_earned_label.text = "Gesamt  +%s 💰" % Economy.format_currency(_run_earned)


func _update_round_hud() -> void:
	if _round_label == null:
		return
	var sum := 0
	for v in _lap_running:
		sum += int(v)
	_round_label.text = "Runde  +%s 💰" % Economy.format_currency(sum)


func _show_summary() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 8
	add_child(layer)

	# Abdunkelnder Hintergrund
	var dim := ColorRect.new()
	dim.position = Vector2(0, 0)
	dim.size     = Vector2(960, 540)
	dim.color    = Color(0, 0, 0, 0.55)
	layer.add_child(dim)

	const PW = 400
	const PH = 230

	var panel := Panel.new()
	panel.size     = Vector2(PW, PH)
	panel.position = Vector2((960 - PW) / 2.0, (540 - PH) / 2.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13, 0.97)
	style.border_width_left   = 3
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color        = Color(1.0, 0.82, 0.18)
	style.set_corner_radius_all(8)
	style.content_margin_left   = 28
	style.content_margin_right  = 28
	style.content_margin_top    = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	# Titel
	var title := Label.new()
	title.text = "LAUF BEENDET"
	title.position = Vector2(0, 16)
	title.size = Vector2(PW, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	panel.add_child(title)

	# Trennlinie
	var line := ColorRect.new()
	line.position = Vector2(28, 58)
	line.size     = Vector2(PW - 56, 1)
	line.color    = Color(1.0, 0.82, 0.18, 0.30)
	panel.add_child(line)

	# Verdient-Label
	var earned_lbl := Label.new()
	earned_lbl.text = "+%s 💰  verdient" % Economy.format_currency(_run_earned)
	earned_lbl.position = Vector2(0, 72)
	earned_lbl.size = Vector2(PW, 38)
	earned_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	earned_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	earned_lbl.add_theme_font_size_override("font_size", 24)
	earned_lbl.add_theme_color_override("font_color", Color(0.50, 1.0, 0.60))
	earned_lbl.add_theme_constant_override("outline_size", 3)
	earned_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	panel.add_child(earned_lbl)

	# Info-Text
	var info := Label.new()
	info.text = "Der Betrag wurde deinem Konto gutgeschrieben."
	info.position = Vector2(0, 118)
	info.size = Vector2(PW, 22)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.36, 0.40, 0.52))
	panel.add_child(info)

	# Zurück-Button
	var btn := Button.new()
	btn.text = "← Zurück zum Bauplan"
	btn.position = Vector2(28, 152)
	btn.size = Vector2(PW - 56, 50)
	var btn_sb := StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.12, 0.14, 0.20)
	btn_sb.border_width_left = 3
	btn_sb.border_color = Color(1.0, 0.82, 0.18, 0.70)
	btn_sb.set_corner_radius_all(4)
	btn_sb.content_margin_top = 8; btn_sb.content_margin_bottom = 8
	var btn_hov := btn_sb.duplicate() as StyleBoxFlat
	btn_hov.bg_color = Color(0.18, 0.20, 0.28)
	btn_hov.border_color = Color(1.0, 0.82, 0.18)
	btn.add_theme_stylebox_override("normal",  btn_sb)
	btn.add_theme_stylebox_override("hover",   btn_hov)
	btn.add_theme_stylebox_override("pressed", btn_sb)
	btn.add_theme_stylebox_override("focus",   btn_sb)
	btn.add_theme_color_override("font_color", Color(0.82, 0.85, 0.90))
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_on_back_pressed)
	panel.add_child(btn)


# ── Auto(s) ─────────────────────────────────────────────────────────────────────

func _start_cars(grid_state: Array) -> void:
	var script = load(Paths.SCRIPT_CAR_CONTROLLER)
	var count  = Economy.get_car_count()
	_lap_running.clear()
	_lap_running.resize(count)
	_lap_running.fill(0)
	for i in range(count):
		var ctrl = Node3D.new()
		ctrl.set_script(script)
		ctrl.speed       = Economy.get_car_speed(i)
		ctrl.end_mult    = Economy.get_car_end_mult(i)
		ctrl.tile_bonus  = Economy.get_car_tile_bonus(i)
		ctrl.start_delay = CAR_STAGGER * i
		$CarRoot.add_child(ctrl)
		ctrl.lap_completed.connect(_on_lap_completed.bind(i))
		ctrl.lap_progress.connect(_on_lap_progress.bind(i))
		car_controllers.append(ctrl)
	await get_tree().process_frame
	for ctrl in car_controllers:
		ctrl.start(grid_state)


# ── Zurück zum Bauplan ────────────────────────────────────────────────────────

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(Paths.SCENE_BUILDER)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back_pressed()


# ── Setup ─────────────────────────────────────────────────────────────────────

func _setup_generator() -> void:
	var script = load(Paths.SCRIPT_TRACK_GENERATOR)
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
		_track_cx,
		CAM_DISTANCE * sin(angle_rad),
		_track_cz + CAM_DISTANCE * cos(angle_rad)
	)
	camera.look_at(Vector3(_track_cx, 0, _track_cz), Vector3.UP)


func _setup_ground() -> void:
	var plane    = PlaneMesh.new()
	plane.size   = Vector2(GROUND_SIZE, GROUND_SIZE)
	ground.mesh  = plane
	var mat      = StandardMaterial3D.new()
	mat.albedo_color     = GROUND_COLOR
	mat.roughness        = 0.9
	ground.material_override = mat
	ground.position = Vector3(_track_cx, GROUND_Y, _track_cz)
