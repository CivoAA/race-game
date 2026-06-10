extends Node3D

# Kamera: Elevation = Höhenwinkel über dem Boden (klein = flacher/mehr von der Seite),
# Azimut = seitliches Herumschwenken um die Streckenmitte (0 = gerade von vorne).
const CAM_ELEVATION_DEG = 45.0
const CAM_AZIMUTH_DEG   = 0.0
const CAM_DISTANCE      = 7.0
const CAM_FOV           = 60.0
const SUN_ENERGY    = 1.3
const SUN_ANGLE_DEG = 55.0
const GROUND_SIZE   = 24.0
const GROUND_COLOR  = Color(0.22, 0.38, 0.18)
const GROUND_Y      = -0.02
const TILE_SIZE_3D  = 1.2
const CAR_STAGGER   = 0.5   # Sekunden Startabstand zwischen mehreren Autos

# CurrencyHud wird durch GameHUD (Autoload) ersetzt

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
var _run_active:      bool  = false
var _active_track_idx: int  = 0
var _grid_state:      Array = []   # für Auto-Respawn bei Live-Upgrade gemerkt

var _finish_btn:   Button = null
var _bottom_bar:   Control = null   # untere Leiste (wie im 2D-Bauplan), trägt den Finish-Button


func _ready() -> void:
	# Track-Index ermitteln
	_active_track_idx = 0
	if Engine.has_meta("active_track_idx"):
		_active_track_idx = int(Engine.get_meta("active_track_idx"))
		Engine.remove_meta("active_track_idx")

	# Unterscheidung: frischer Start vs. View-Wechsel (Runde läuft bereits)
	var is_resuming: bool = Engine.get_meta("resuming_run", false)
	if is_resuming:
		Engine.remove_meta("resuming_run")

	var grid_state = _resolve_grid_state()
	_grid_state = grid_state
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

	# Lauf-Status kommt immer aus Economy (single source of truth); der Timer-Text
	# wird von GameHUD gerendert.
	_run_active    = Economy.is_run_active(_active_track_idx)

	# Strecken-Tabs bleiben auch in 3D aktiv → auf Wechsel reagieren. run_ended liefert das
	# Popup, wenn die Runde endet. Beide auch im bereits-beendet-Fall verbinden, damit man
	# vom wartenden Popup aus die Strecke wechseln kann.
	GameHUD.tab_changed.connect(_on_tab_changed)
	Economy.run_ended.connect(_on_economy_run_ended)
	# Upgrade-Kauf → Autos der angeschauten Strecke neu aufsetzen (Tempo/Anzahl/Reward live).
	Economy.upgrade_purchased.connect(_on_upgrade_purchased)

	if not _run_active:
		# Runde ist bereits beendet (z.B. während man eine andere Strecke ansah) → Popup
		_show_summary()
		return

	_start_cars(grid_state)


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

func _process(_delta: float) -> void:
	if not _run_active:
		return
	# Economy ist die einzige Timer-Quelle – World3D zählt NICHT selbst und prüft hier nur
	# das Lauf-Ende. Die Timer-Anzeige liegt in GameHUD.
	if not Economy.is_run_active(_active_track_idx):
		_end_run()


func _on_economy_run_ended(track_idx: int, _earned: int) -> void:
	if track_idx == _active_track_idx and _run_active:
		_end_run()


# "Fahrt beenden": Lauf vorzeitig beenden (ohne den Timer abzuwarten) → Zusammenfassung.
func _on_finish_run_pressed() -> void:
	_end_run()


# Upgrade gekauft, während diese Strecke gezeigt wird: Autos neu aufsetzen, damit Tempo,
# Anzahl und der Runden-HUD-Reward sofort die neuen Werte zeigen. Das Geld bleibt rück-
# wirkungsfrei (Economy snappt den Runden-Zähler beim Neusetzen der run_cars).
func _on_upgrade_purchased(_id: String) -> void:
	if _run_active:
		_respawn_cars()


func _end_run() -> void:
	if not _run_active:
		return   # Doppelaufruf verhindern
	_run_active = false
	for ctrl in car_controllers:
		ctrl.stop()
	Economy.stop_run(_active_track_idx)
	Economy.save_game()
	_show_summary()


# ── HUD ─────────────────────────────────────────────────────────────────────────

func _setup_hud() -> void:
	# HUD-Overlay (Layer 21 = über GameHUD Layer 20)
	# Kein eigener Hintergrund – GameHUD stellt die Bar bereit (inkl. Renn-Timer neben der Währung).
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)

	# Untere Leiste (wie im 2D-Bauplan): bleibt während der Fahrt sichtbar und trägt unten
	# links den "Fahrt beenden"-Button. Geht über die ganze Breite, y = 498..540.
	const BAR_H = 42
	_bottom_bar = Control.new()
	_bottom_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Vollbild-Container, aber NUR die sichtbare untere Leiste soll Klicks fangen.
	# Ohne IGNORE würde dieser Container (Layer 21, über GameHUD/Popup) alle Klicks
	# über den ganzen Bildschirm schlucken → Seitenleiste & "Zurück zum Bauplan"
	# unklickbar. Kinder (z.B. der Finish-Button) erhalten Klicks weiterhin selbst.
	_bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_bottom_bar)

	var bar_bg := ColorRect.new()
	bar_bg.anchor_left   = 0.0; bar_bg.offset_left   = 0
	bar_bg.anchor_right  = 1.0; bar_bg.offset_right  = 0
	bar_bg.anchor_top    = 1.0; bar_bg.offset_top    = -BAR_H
	bar_bg.anchor_bottom = 1.0; bar_bg.offset_bottom = 0
	bar_bg.color    = Color(0.118, 0.122, 0.133)   # Discord-BG (#1e1f22)
	_bottom_bar.add_child(bar_bg)

	var bar_line := ColorRect.new()
	bar_line.anchor_left   = 0.0; bar_line.offset_left   = 0
	bar_line.anchor_right  = 1.0; bar_line.offset_right  = 0
	bar_line.anchor_top    = 1.0; bar_line.offset_top    = -BAR_H
	bar_line.anchor_bottom = 1.0; bar_line.offset_bottom = -BAR_H + 1
	bar_line.color    = Color(0.247, 0.255, 0.278)  # Discord-Line (#3f4147)
	_bottom_bar.add_child(bar_line)

	# "Fahrt beenden": beendet den Lauf vorzeitig (ohne den Timer abzuwarten) und zeigt die
	# Zusammenfassung, von der aus es per "Zurück zum Bauplan" in die 2D-Ansicht geht.
	# Streckenwechsel weiterhin über die Tabs. Sitzt unten links auf der Leiste.
	_finish_btn = Button.new()
	_finish_btn.text     = "⏹  Fahrt beenden"
	_finish_btn.anchor_left   = 0.0; _finish_btn.offset_left   = 8
	_finish_btn.anchor_right  = 0.0; _finish_btn.offset_right  = 178
	_finish_btn.anchor_top    = 1.0; _finish_btn.offset_top    = -(BAR_H + 34) / 2.0
	_finish_btn.anchor_bottom = 1.0; _finish_btn.offset_bottom = -(BAR_H - 34) / 2.0
	_finish_btn.focus_mode = Control.FOCUS_NONE
	_finish_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_finish_btn.tooltip_text = "Lauf jetzt beenden und zur Zusammenfassung"
	var fsb := StyleBoxFlat.new()
	fsb.bg_color          = Color(0.16, 0.09, 0.10, 0.94)
	fsb.border_width_left = 3
	fsb.border_color      = Color(0.85, 0.28, 0.22)
	fsb.set_corner_radius_all(8)
	fsb.content_margin_left = 10; fsb.content_margin_right  = 10
	fsb.content_margin_top  = 5;  fsb.content_margin_bottom = 5
	var fsb_h := fsb.duplicate() as StyleBoxFlat
	fsb_h.bg_color = Color(0.24, 0.13, 0.14, 0.97)
	_finish_btn.add_theme_stylebox_override("normal",  fsb)
	_finish_btn.add_theme_stylebox_override("hover",   fsb_h)
	_finish_btn.add_theme_stylebox_override("pressed", fsb)
	_finish_btn.add_theme_stylebox_override("focus",   fsb)
	_finish_btn.add_theme_color_override("font_color",       Color(1.00, 0.55, 0.48))
	_finish_btn.add_theme_color_override("font_hover_color", Color(1.00, 0.70, 0.64))
	_finish_btn.add_theme_font_size_override("font_size", 13)
	_finish_btn.pressed.connect(_on_finish_run_pressed)
	_bottom_bar.add_child(_finish_btn)

	# Status-Text rechts neben dem Button (dezent), füllt die Leiste.
	var bar_status := Label.new()
	bar_status.text = "Runde läuft – Strecke %d" % (_active_track_idx + 1)
	bar_status.anchor_left   = 0.0; bar_status.offset_left   = 192
	bar_status.anchor_right  = 1.0; bar_status.offset_right  = -8
	bar_status.anchor_top    = 1.0; bar_status.offset_top    = -BAR_H
	bar_status.anchor_bottom = 1.0; bar_status.offset_bottom = 0
	bar_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_status.add_theme_font_size_override("font_size", 12)
	bar_status.add_theme_color_override("font_color", Color(0.580, 0.608, 0.643))
	_bottom_bar.add_child(bar_status)

	# Der Renn-Timer wird von GameHUD in der oberen Leiste neben der Währung gezeigt
	# (responsive, single source) – World3D rendert ihn nicht mehr selbst.


func _make_hud_label(pos: Vector2, font_size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.position = pos
	lbl.anchor_left = 0.0; lbl.anchor_right = 1.0; lbl.offset_left = 0; lbl.offset_right = 0
	lbl.size = Vector2(0, 28)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return lbl


func _show_summary() -> void:
	# Das Popup wird ausschließlich hier (3D-Ansicht) gezeigt. Der pending_summary-Flag
	# in Economy gilt als "quittiert", sobald das Popup in der 3D-Ansicht erscheint.
	Economy.clear_pending_summary(_active_track_idx)
	# Die untere Leiste (mit "Fahrt beenden") bleibt durchgehend sichtbar – auch über dem
	# Lauf-beendet-Popup. Sie liegt auf Layer 21 (über dem Popup-Layer 8).

	var layer = CanvasLayer.new()
	layer.layer = 8
	add_child(layer)

	# Abdunkelnder Hintergrund
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color    = Color(0, 0, 0, 0.55)
	layer.add_child(dim)

	const PW = 400
	const PH = 230

	var panel := Panel.new()
	# Zentriert via Ankerpunkt Mitte
	panel.anchor_left   = 0.5; panel.offset_left   = -PW / 2
	panel.anchor_right  = 0.5; panel.offset_right  =  PW / 2
	panel.anchor_top    = 0.5; panel.offset_top    = -PH / 2
	panel.anchor_bottom = 0.5; panel.offset_bottom =  PH / 2
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
	earned_lbl.text = "+%s %s  verdient" % [Economy.format_currency(Economy.get_run_earned(_active_track_idx)), Icons.COIN]
	earned_lbl.position = Vector2(0, 72)
	earned_lbl.size = Vector2(PW, 38)
	earned_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	earned_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	earned_lbl.add_theme_font_size_override("font_size", 24)
	earned_lbl.add_theme_color_override("font_color", Color(0.50, 1.0, 0.60))
	earned_lbl.add_theme_constant_override("outline_size", 3)
	earned_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	panel.add_child(earned_lbl)

	# Zurück-Button
	var btn := Button.new()
	btn.text = "← Zurück zum Bauplan"
	btn.position = Vector2(28, 152)
	btn.size = Vector2(PW - 56, 50)
	var btn_sb := StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.12, 0.14, 0.20)
	btn_sb.border_width_left = 3
	btn_sb.border_color = Color(1.0, 0.82, 0.18, 0.70)
	btn_sb.set_corner_radius_all(8)
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
	btn.pressed.connect(_on_back_to_builder)
	panel.add_child(btn)


# ── Auto(s) ─────────────────────────────────────────────────────────────────────

# Setzt die Autos der laufenden Runde neu auf (z.B. nach Upgrade-Kauf). Positionen ergeben
# sich wieder aus der Fahrzeit, der Lauf läuft also nahtlos mit neuem Tempo/Anzahl weiter.
func _respawn_cars() -> void:
	for ctrl in car_controllers:
		if is_instance_valid(ctrl):
			ctrl.stop()
			$CarRoot.remove_child(ctrl)
			ctrl.queue_free()
	car_controllers.clear()
	_start_cars(_grid_state)


func _start_cars(grid_state: Array) -> void:
	var script = load(Paths.SCRIPT_CAR_CONTROLLER)
	var total  = Economy.get_car_count()
	# Auto-Prestige-Stufe entscheidet, WAS fährt:
	#  Stufe 0 → wie bisher: `total` normale Autos (Test-Modell), keine Tier-Autos.
	#  Stufe ≥1 → NUR Tier-Autos (Super-Auto-Ökonomie, Modell der Stufe): get_tier_car_count()
	#            = 1 Basis + je SUPER_CAR_COST_CARS normale Autos eines mehr. Normale Autos fahren nicht.
	var tier: int        = Economy.get_car_tier()
	var supers: int      = Economy.get_tier_car_count() if tier >= 1 else 0
	var normal_cnt: int  = 0 if tier >= 1 else total
	var spawn_cnt: int   = normal_cnt + supers
	if spawn_cnt < 1:
		spawn_cnt = 1
	var slot := 0
	for i in range(normal_cnt):
		var ctrl = Node3D.new()
		ctrl.set_script(script)
		ctrl.track_idx   = _active_track_idx
		ctrl.speed       = Economy.get_car_speed(i)
		ctrl.end_mult    = Economy.get_car_end_mult(i)
		ctrl.tile_bonus  = Economy.get_car_tile_bonus(i)
		# Startabstand skaliert invers mit der Auto-Anzahl: je mehr Autos, desto dichter starten
		# sie hintereinander. Abstand zwischen zwei Autos = CAR_STAGGER/spawn_cnt
		# (2 Autos → 0.25 s, 3 → 0.17 s, 4 → 0.125 s …).
		ctrl.start_delay = CAR_STAGGER / float(spawn_cnt) * slot
		$CarRoot.add_child(ctrl)
		car_controllers.append(ctrl)
		slot += 1
	for s in range(supers):
		var sctrl = Node3D.new()
		sctrl.set_script(script)
		sctrl.track_idx      = _active_track_idx
		sctrl.is_super       = true
		sctrl.speed          = Economy.get_car_speed(0) / Economy.SUPER_CAR_SPEED_DIV
		sctrl.speed_div      = Economy.SUPER_CAR_SPEED_DIV
		sctrl.bonus_tile_add = Economy.SUPER_CAR_TILE_BONUS
		sctrl.end_mult_extra = Economy.SUPER_CAR_END_MULT
		sctrl.start_delay    = CAR_STAGGER / float(spawn_cnt) * slot
		$CarRoot.add_child(sctrl)
		car_controllers.append(sctrl)
		slot += 1
	await get_tree().process_frame
	# Bereits verstrichene Fahrzeit → Autos an die passende Stelle der Strecke setzen
	# (statt am Start), damit sie nach einem 2D↔3D-Wechsel nahtlos weiterfahren.
	var resume_elapsed := Economy.get_run_elapsed(_active_track_idx)
	for ctrl in car_controllers:
		ctrl.start(grid_state, resume_elapsed)
	# Auto-Parameter für die runden-basierte Abrechnung an Economy übergeben:
	# lap_time (geschlossene Rundenlänge ÷ Tempo), Ertrag je Runde und Startversatz.
	# Damit kann Economy die Startlinien-Überquerungen exakt – auch im 2D-Hintergrund – abrechnen.
	# lap_time kommt jetzt DIREKT aus dem Auto (gleiche Segment-Zeittabelle, die auch die
	# visuelle Position bestimmt) → Geld-Runde fällt exakt mit der sichtbaren Start-Überfahrt
	# zusammen, bei jedem Tempo und (künftig) mit Booster-Tiles.
	# tile_rewards (Tile-Reihenfolge) ist streckenfix (upgrade-unabhängig). Economy faltet daraus
	# den Reward je Runde live mit den aktuellen Upgrade-Werten → Geld-Upgrades wirken auf laufende
	# Läufe, auch auf Hintergrund-Strecken (3D-Ansicht nicht offen).
	var cars: Array = []
	for ctrl in car_controllers:
		if ctrl.waypoints.size() < 2 or float(ctrl.lap_time) <= 0.0:
			continue
		cars.append({
			"lap_time":       float(ctrl.lap_time),
			# lap_k = lap_time·speed ist tempo-unabhängig → Economy rechnet lap_time bei Tempo-
			# Upgrades live neu (auch für Hintergrund-Strecken), ohne Neu-Spawn.
			"lap_k":          float(ctrl.lap_time) * float(ctrl.speed),
			"tiles":          ctrl.tile_rewards.duplicate(true),
			"start_delay":    float(ctrl.start_delay),
			# Pro-Auto-Ökonomie (Super-Auto; normale Autos: 1/0/1 → unverändert).
			"speed_div":      float(ctrl.speed_div),
			"tile_bonus_add": float(ctrl.bonus_tile_add),
			"end_mult_extra": float(ctrl.end_mult_extra),
		})
	Economy.set_run_cars(_active_track_idx, cars)


# ── Zurück zum Bauplan / Streckenwechsel ──────────────────────────────────────

func _disconnect_hud_signals() -> void:
	if GameHUD.tab_changed.is_connected(_on_tab_changed):
		GameHUD.tab_changed.disconnect(_on_tab_changed)
	if Economy.run_ended.is_connected(_on_economy_run_ended):
		Economy.run_ended.disconnect(_on_economy_run_ended)
	if Economy.upgrade_purchased.is_connected(_on_upgrade_purchased):
		Economy.upgrade_purchased.disconnect(_on_upgrade_purchased)


# Einziger Weg zurück in den 2D-Bauplan dieser Strecke: das Run-Ende-Popup
# ("Zurück zum Bauplan"). Während ein Lauf läuft, gibt es keinen freien 2D-Wechsel –
# nur Streckenwechsel über die Tabs (Req: in 3D nicht nach 2D, nur zwischen Strecken).
func _on_back_to_builder() -> void:
	_disconnect_hud_signals()
	GameHUD.set_track_3d(_active_track_idx, false)
	get_tree().change_scene_to_file(Paths.SCENE_BUILDER)


# Strecken-Tab gewechselt: Zielstrecke in ihrer gemerkten Ansicht laden. Die Runde der
# aktuellen Strecke läuft im Hintergrund (Economy) weiter.
func _on_tab_changed(idx: int) -> void:
	if idx == _active_track_idx:
		return
	_disconnect_hud_signals()
	if GameHUD.is_track_3d(idx):
		GameHUD.goto_world3d(idx)
	else:
		get_tree().change_scene_to_file(Paths.SCENE_BUILDER)


# ESC öffnet in der 3D-Ansicht das Pausemenü (PauseMenu-Autoload), nicht den Wechsel
# zurück in die 2D-Ansicht. Deshalb KEIN eigener ESC-Handler hier – PauseMenu fängt
# "ui_cancel" global ab.


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
	var elev = deg_to_rad(CAM_ELEVATION_DEG)
	var azim = deg_to_rad(CAM_AZIMUTH_DEG)
	var horiz = CAM_DISTANCE * cos(elev)   # horizontale Entfernung zur Mitte
	camera.position = Vector3(
		_track_cx + horiz * sin(azim),
		CAM_DISTANCE * sin(elev),
		_track_cz + horiz * cos(azim)
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
