extends Node3D

const TILE_SIZE = 1.2

# Ertrag pro überfahrenem Tile:
#   Dreck-Tile:              +1 additiv (per Dreck-Ertrag-Upgrade steigerbar)
#   Standard-Tile (u. Start): +5 additiv
#   Default-Tile (gekauft):  +25 additiv, KEIN Multiplikator mehr (rein additiver Ertrag)
const BASIC_TILE_EARN   = 0.0   # Standard-/Start-Felder: kein Grundertrag (nur Upgrades zählen)
const DIRT_TILE_EARN    = 1.0   # Dreck-Felder: Grundertrag +1, per Dreck-Upgrade steigerbar
# Sand: günstigste BEZAHLTE Strecke (+15 Grundertrag, kein Multiplikator).
# Eigene additive Upgrades: sandstraightbonus / sandcurvebonus (kind "psandstraight"/"psandcurve").
const SAND_TILE_EARN     = 15.0
const PREMIUM_TILE_EARN  = 150.0  # Default-Strecke (gebufft) – mittlere Stufe zwischen Sand (+15) und Renn (+1000)
const PREMIUM_TILE_MULT  = 1.0  # Default-Tiles geben keinen Multiplikator mehr (1.0 = neutral)
# Rennstrecke: teuerstes Streckenteil – hoher flacher Ertrag (+1000) UND ein fester ×1.2 obendrauf.
# Eigene additive Upgrades: racestraightbonus / racecurvebonus (kind "pracestraight"/"pracecurve").
const RACE_TILE_EARN     = 1000.0
const RACE_TILE_MULT     = 1.2

var speed: float = 2.5

# Track-Index dieses Autos – Quelle der Fahrzeit (Economy.get_run_elapsed). Von World3D gesetzt.
var track_idx: int = 0

# Pro-Auto-Parameter (von World3D vor start() gesetzt)
var end_mult:    float = 1.0   # Multiplikator auf den Rundenertrag
var tile_bonus:  float = 0.0   # + je überfahrenem Tile
var start_delay: float = 0.0   # verzögerter Start (gestaffelt bei mehreren Autos)

# Super-Auto („Auto 2"): eigenes Modell + abweichende Ökonomie. is_super wählt das Modell (an Car3D
# weitergereicht); speed_div/bonus_tile_add/end_mult_extra wandern in das run_cars-Dict und werden
# von Economy._lap_reward_for_car / _apply_speed_to_active_runs ausgewertet. Normal: 1/0/1.
var is_super:       bool  = false
var speed_div:      float = 1.0   # Tempo wird durch diesen Wert geteilt (3 = drittel so schnell)
var bonus_tile_add: float = 0.0   # zusätzlicher +Ertrag JE Feld (oben drauf auf den globalen Tile-Bonus)
var end_mult_extra: float = 1.0   # zusätzlicher ×Faktor ganz am Ende (oben drauf auf EndMult × Prestige)

# Tile-Reihenfolge für die Runden-Abrechnung (in _build_waypoints gefüllt). Jeder Eintrag
# beschreibt ein befahrenes Feld STRECKENFIX (upgrade-unabhängig): {base, kind, fixed_mult,
# bonus_points, bonus_mult, stand_mult, stand_count, is_jump, is_loop}. Economy faltet daraus pro Runde den Schneeball mit
# den AKTUELLEN Upgrade-Werten – auch für Hintergrund-Strecken (3D-Ansicht nicht offen).
var tile_rewards: Array = []

# ── Bullet-proof Sync: EINE Wahrheitsquelle = Fahrzeit (Economy.run_elapsed) ──────
# Visuelle Position UND Geld-Runden werden ausschließlich aus der verstrichenen Zeit
# über eine pro-Segment-Zeittabelle abgeleitet. Dadurch ist das Auto visuell immer
# genau dann auf dem Start-Tile, wenn Economy eine Runde gutschreibt – bei jedem Tempo.
var lap_time: float = 0.0                              # Zeit für eine volle Runde (Summe seg_time)
var _seg_time: PackedFloat32Array = PackedFloat32Array()  # Dauer je Wegpunkt-Segment
var _cum_time: PackedFloat32Array = PackedFloat32Array()  # Zeit, zu der wp[i] erreicht wird

var waypoints: Array[Vector3] = []
var driving: bool = false
var car: Node3D = null

# Wegpunkt→Step-Zuordnung (für die Tempo-Faktor-Tabelle je Segment).
var _wp_to_step: PackedInt32Array = PackedInt32Array()

const MODEL_ROTATION_OFFSET = PI / 2.0

# Visuelles Roll (Kurvenneigung) und Pitch (Rampenneigung)
const ROLL_FACTOR = 0.055   # rad Roll pro rad/s Gierrate
const ROLL_MAX    = 0.30    # ~17° maximale Kurvenneigung
const ROLL_SMOOTH = 12.0
# Rampen-Nasenneigung = Steigung zur VORAUSSCHAU-Position (PITCH_LOOKAHEAD s in der Zukunft), begrenzt
# auf PITCH_MAX, geglättet mit PITCH_SMOOTH; Drehung um die Querachse (manuelle Basis). Die Vorausschau
# sorgt dafür, dass sich die Schnauze schon HEBT, bevor der Sprungbogen beginnt (keine Asset-Kollision).
const PITCH_MAX   = 0.50    # ~29° maximale Nasenneigung
const PITCH_SMOOTH = 9.0
const PITCH_LOOKAHEAD = 0.22  # s Vorausschau → Nase hebt sich entsprechend früher beim Auffahren
# Zusatz-Höhe für die AUFFAHRT-Hälfte des Rampenbogens (max. am Beginn, klingt zum Scheitel aus).
# Das Auto schwebt dadurch beim Auffahren früher/etwas höher und rutscht nicht mehr in die Rampe.
const RAMP_TAKEOFF_LIFT = 0.12

# Steilkurve (Carrera-Stil): Mittellinien-Höhe am Apex (m) und max. Auto-Querneigung (rad).
# Muss zum Bank.glb-Asset (curve/steilcurve) passen, damit das Auto satt auf der Fahrbahn liegt:
# Das Asset ist eine SANFT gebankte Kurve (nativ 0.1488 hoch ×1.2 Skalierung ≈ 0.179 Welt; die
# befahrbare Bankfläche neigt sich ~20-25°, der 90°-Teil ist die NICHT befahrene Außenwand).
# WALL_PEAK_H = Anstieg der Fahrbahn-Mittellinie zum Apex (Asset-Mitte ≈ 0.074 nativ ×1.2 ≈ 0.089).
const WALL_PEAK_H   = 0.09
const WALL_BANK_MAX = 0.38   # AKTUELL UNGENUTZT: war das rotation.z-Banking, das ist aber (Front=−X) die
							 # Querachse = Nick/Wheelie. Auto neigt sich nur noch seitlich über WALL_LEAN_X.
# Scheitel-Tiefe der Steilkurve: wie weit sich der Apex (Bauch des U) über den alten Halbkreis hinaus
# ins Tile-Innere/in die gebankte Fahrbahn wölbt (× halbe Kachel). Die AUSSEN-Anschlusspunkte bleiben
# dabei FIX an der Kachelkante, der Eingang steht also NICHT raus – nur der Bauch wird tiefer/runder.
#   0.0 = alter enger Halbkreis (Radius = halbe Kachel)
#   ~0.4 = spürbar tiefer (Asset ist ~1.5 Kacheln breit)
const WALL_BULGE = 0.4

# Debug: zeichnet die IST-Fahrlinie als Kugeln (Steilkurven-Punkte ROT, Rest blau), damit man die
# SOLL-Linie auf einem Screenshot drübermalen kann. Vor Release auf false setzen.
const DEBUG_DRAW_PATH := false
const WALL_ROLL_SMOOTH = 25.0  # schnelleres Einrasten der Querneigung als ROLL_SMOOTH (kein Durchglitchen)
# Zusätzliche Längsachsen-Rolle (lokale X, „rechte Tür runter") in der Steilkurve: das Auto kippt zur
# KURVENMITTE hin (zum Punkt, um den es bei einem Vollkreis fahren würde). 0 = aus. 0.52 ≈ 30°.
const WALL_LEAN_X = 0.52
var _wall_lean: float = 0.0   # geglättete aktuelle Längsneigung (rad), läuft außerhalb der Wand auf 0
# Stabile Bank-Richtung der Steilkurve (−1/0/+1): EINMAL beim Einlenken aus der Gierrate bestimmt und
# über die ganzen zwei Kacheln gehalten. Ohne das würde das Auto zwischen den Wegpunkten (konstante
# Fahrtrichtung → yaw_rate=0) immer wieder in die Waagerechte zurückkippen → sichtbares Zucken.
var _wall_lean_dir: float = 0.0

var _prev_yaw: float     = 0.0
var _prev_car_y: float   = 0.0
var _yaw_init: bool      = false
# Geglättete Rampen-Nasenneigung (rad). Wird über die QUERACHSE per manueller Basis gedreht
# (NICHT über rotation.x – das wäre eine Fass-Rolle, da die Front entlang lokaler −X zeigt).
var _pitch: float        = 0.0

# Querneigungs-Intensität (0..1) je Wegpunkt (nur Steilwandkurven-Wegpunkte > 0).
var _wp_bank: PackedFloat32Array = PackedFloat32Array()
var _cur_wp: int = 0
# Fortschritt 0..1 innerhalb des aktuellen Segments (_cur_wp → _cur_wp+1). Wird in _sample_at_time
# gesetzt und in _update_orientation genutzt, um die Looping-Salto-Orientierung GLATT zwischen den
# Wegpunkten zu interpolieren (sonst springt der Winkel pro Punkt und das Auto schiebt kurz durch).
var _cur_seg_f: float = 0.0

# Looping: explizite Orientierung je Wegpunkt (Vector2(pitch, yaw)) oder null = normale Bewegungs-
# Ausrichtung. Nötig, weil im Looping die HORIZONTALE Bewegung umkehrt (oben kopfüber) → die
# bewegungsbasierte Yaw-Berechnung würde das Auto verdrehen.
var _wp_orient: Array = []
var _pending_orient: Array = []   # wird in _waypoints_for_tile je Kachel gefüllt (Länge = Wegpunkte)

# Looping-Geometrie (muss zu TrackGenerator3D passen): Radius, Höhe, seitlicher Ein/Ausfahrt-Versatz.
# An das Loop.glb angepasst (nativ ~0.76 hohe Innenfahrbahn ×1.2 ≈ 0.93 Welt). Die Fahrlinie ist eine
# vertikale Ellipse: Boden bei y=0.05, Top bei 0.05 + 2·LOOP_R. Mit 0.44 liegt der Scheitel bei ≈0.93,
# also genau auf der Loop-Innenfläche – das Auto bleibt IM Asset (vorher 0.55 ⇒ Top 1.15 ⇒ oben raus).
const LOOP_R    = 0.44   # vertikaler Halbradius (Höhe = 2·R ≈ 0.88, passend zur Loop-Innenfläche)
const LOOP_FWD  = 0.45   # Vorwärts-Radius (Ellipse, damit der Looping in die Kachel passt)
const LOOP_OFF  = 0.12   # seitlicher Versatz: rein rechts, raus links (kein Selbst-Überschneiden); klein
						 # halten, damit das Auto auf der schmalen, planaren Loop-Fahrbahn bleibt
const LOOP_SEGS = 22
# Die zwei „Maul"-Übergangspunkte (2. und vorletzter Wegpunkt) liegen am Fuß des Loops, wo die flache
# Anfahrt in die Senkrechte übergeht. Mittig gesetzt schneidet das Auto dort durch die Loop-Struktur.
# Darum beide entlang der Fahrtachse weiter NACH AUSSEN (zur jeweiligen Kachelkante) ziehen: der Einfahrt-
# Punkt Richtung Eingang, der Ausfahrt-Punkt Richtung Ausgang (Welt-Meter; 0 = mittig wie zuvor).
const LOOP_MOUTH_OUT = 0.15

# Portal: Teleport-Segment (Eingangs-Portal → Ausgangs-Portal) bekommt eine feste, kurze Dauer und
# wird beim Sampling „gesnappt" (Auto bleibt am Eingang, blinkt dann zum Ausgang) statt über die
# ganze Karte zu streaken. _wp_teleport markiert das Segment, das bei Wegpunkt i beginnt.
const TELEPORT_TIME = 0.15
var _wp_teleport: PackedByteArray = PackedByteArray()
# Portal-Rampe (PortalRamp.glb): Das Auto fährt von der Eingangskante eine Rampe HOCH und tief ins
# Tile zum Tor, bevor es verschwindet (Teleport). Das Tor/Rampen-Hoch sitzt ~0.3 Welt hinter der
# Tile-Mitte, die Rampe steigt ~0.226 Welt. Werte an das Asset angelehnt, per Debug-Kugeln justierbar.
const PORTAL_RAMP_H     = 0.22   # Höhe, auf die das Auto die Rampe hochfährt (Welt)
const PORTAL_GATE_DEPTH = 0.30   # wie tief hinter die Tile-Mitte (Richtung Tor) es fährt/verschwindet

# Markiert die Wegpunkte des Rampen-Sprungbogens (1 = in der Luft über die Rampe). Dort wird die
# Nase über die Querachse geneigt (Auffahrt hoch, in der Luft runter, Landung wieder eben).
var _wp_jump: PackedByteArray = PackedByteArray()

# Eis-Wheelie: auf einem Eisfeld (ice/ice_curve) – wo das Auto jetzt schon selbst Tempo bekommt –
# stellt es die Nase steil auf und fährt „auf den Hinterrädern" (Speed-Boost-Optik). Der Winkel liegt
# bewusst deutlich über PITCH_MAX (Rampe). Nur auf dem Eisfeld selbst, sanft ein-/ausgeblendet.
const ICE_WHEELIE_PITCH = PI * 30.0 / 180.0   # ~30° Nase hoch
const ICE_PITCH_SMOOTH  = 14.0   # schnelles Aufstellen → Wheelie schon beim Auffahren, nicht erst mittig
# Markiert Wegpunkte, die auf einem Eisfeld liegen (1 = Wheelie). Parallel zu _wp_jump.
var _wp_ice: PackedByteArray = PackedByteArray()


func _ready() -> void:
	var car_script = load(Paths.SCRIPT_CAR_3D)
	car = Node3D.new()
	car.set_script(car_script)
	# Modellauswahl an Car3D durchreichen, BEVOR es zum Baum hinzugefügt wird (dort lädt _ready das Modell).
	car.is_super = is_super
	add_child(car)


func start(grid_state: Array, resume_elapsed: float = 0.0) -> void:
	waypoints = _build_waypoints(grid_state)
	if waypoints.size() < 2 or lap_time <= 0.0:
		push_warning("Keine gültige Route – mind. 2 verbundene Tiles nötig.")
		return
	if DEBUG_DRAW_PATH:
		_draw_debug_path()
	_yaw_init     = false
	_pitch        = 0.0
	# Effektiv bereits gefahrene Zeit dieses Autos (gestaffelten Startversatz abziehen).
	var t := resume_elapsed - start_delay
	if t <= 0.0:
		# Frischer Start – oder das Auto wartet noch auf seinen versetzten Start.
		car.position = waypoints[0]
		# Am Start steht das Auto still → Yaw aus der Bewegung wird noch nicht berechnet.
		# Darum hier schon in Fahrtrichtung (Start-Tile → nächster Wegpunkt) ausrichten,
		# sonst stehen die wartenden Autos rückwärts.
		_face_along_start()
	else:
		# Wiederaufnahme nach 2D↔3D-Wechsel: Position rein aus der Fahrzeit ableiten.
		_sample_at_time(t)
	_prev_car_y = car.position.y
	driving = true
	print("Route: %d Wegpunkte, lap_time %.2fs (resume %.1fs)" % [waypoints.size(), lap_time, resume_elapsed])


# Setzt das Auto rein aus der verstrichenen Fahrzeit (mod Rundenzeit) auf die geschlossene
# Schleife. Nutzt die Segment-Zeittabelle – dadurch identisch zur Geld-Abrechnung in Economy,
# unabhängig von Tempo, Framerate oder (künftig) Booster-/Brems-Tiles.
func _sample_at_time(t: float) -> void:
	var n := waypoints.size()
	if n < 2 or lap_time <= 0.0:
		return
	var t_in_lap := fmod(t, lap_time)
	if t_in_lap < 0.0:
		t_in_lap += lap_time
	if car != null and not car.visible:
		car.visible = true   # Standard: sichtbar (Teleport-Segment unten blendet kurz aus)
	for i in range(n):
		var st := _seg_time[i]
		if t_in_lap <= _cum_time[i] + st or i == n - 1:
			_cur_wp = i
			# Portal-Teleport: das Auto VERSCHWINDET sofort beim Reinfahren (rein visuell) und
			# taucht am Ausgang wieder auf – statt sichtbar am Eingang zu „kleben".
			if i < _wp_teleport.size() and _wp_teleport[i] == 1:
				car.position = waypoints[i]
				car.visible = false
				return
			var f := (t_in_lap - _cum_time[i]) / st if st > 0.0 else 0.0
			_cur_seg_f = clampf(f, 0.0, 1.0)
			car.position = waypoints[i].lerp(waypoints[(i + 1) % n], _cur_seg_f)
			return


# Wie _sample_at_time, aber OHNE Seiteneffekte (setzt weder car.position noch Sichtbarkeit): liefert
# nur {pos, wp} für die VORAUSSCHAU der Nasen-Neigung. wp = Index des Segment-Start-Wegpunkts.
func _sample_pose_at_time(t: float) -> Dictionary:
	var n := waypoints.size()
	if n < 2 or lap_time <= 0.0:
		return {"pos": car.position if car != null else Vector3.ZERO, "wp": _cur_wp}
	var t_in_lap := fmod(t, lap_time)
	if t_in_lap < 0.0:
		t_in_lap += lap_time
	for i in range(n):
		var st := _seg_time[i]
		if t_in_lap <= _cum_time[i] + st or i == n - 1:
			# Teleport-Segment: am Eingang stehen bleiben (kein Streak über die Karte).
			if i < _wp_teleport.size() and _wp_teleport[i] == 1:
				return {"pos": waypoints[i], "wp": i}
			var f := (t_in_lap - _cum_time[i]) / st if st > 0.0 else 0.0
			return {"pos": waypoints[i].lerp(waypoints[(i + 1) % n], clampf(f, 0.0, 1.0)), "wp": i}
	return {"pos": waypoints[0], "wp": 0}


func stop() -> void:
	driving = false


func _process(delta: float) -> void:
	if not driving or waypoints.is_empty() or lap_time <= 0.0:
		return

	# EINE Wahrheitsquelle: Fahrzeit aus Economy (läuft in 2D wie 3D identisch weiter).
	# Die Geld-Gutschrift je Runde macht zentral Economy aus derselben t/lap_time – hier nur
	# die visuelle Position und Ausrichtung.
	var t := Economy.get_run_elapsed(track_idx) - start_delay
	if t < 0.0:
		# Gestaffelter Start – dieses Auto wartet noch am Start-Tile.
		car.position = waypoints[0]
		return

	var prev_pos := car.position
	_sample_at_time(t)
	_update_orientation(prev_pos, delta, t)


# Richtet das stehende Auto am Start in Fahrtrichtung aus (Start-Tile → erster Wegpunkt),
# gleiche Yaw-Formel wie _update_orientation. Ohne das stünde das Modell rückwärts, bis es losfährt.
func _face_along_start() -> void:
	if waypoints.size() < 2:
		return
	var dir := waypoints[1] - waypoints[0]
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.0001:
		car.rotation = Vector3(0.0, atan2(flat.x, flat.z) + MODEL_ROTATION_OFFSET, 0.0)


# Visuelle Ausrichtung (Yaw) + Kurvenneigung (Roll) + Rampenneigung (Pitch) aus der
# tatsächlichen Positionsänderung – funktioniert unverändert mit dem Zeit-Sampling.
func _update_orientation(prev_pos: Vector3, delta: float, t: float = 0.0) -> void:
	# Looping: explizite Orientierung. Das Auto MUSS sich um seine QUERACHSE überschlagen (Salto),
	# nicht um die Längsachse rollen. Da das Modell durch MODEL_ROTATION_OFFSET nach vorne entlang
	# seiner lokalen −X zeigt, würde ein Euler-Pitch (rotation.x) fälschlich um die Fahrtachse drehen
	# (Fass-Rolle). Darum bauen wir die Basis direkt: erst wie beim Fahren auf die Fahrtrichtung yawen,
	# dann um die WELT-Querachse (rgt) um den Loop-Winkel th kippen. o = Vector2(th, yaw).
	if _cur_wp < _wp_orient.size() and _wp_orient[_cur_wp] != null:
		var o: Vector2 = _wp_orient[_cur_wp]
		var th: float  = o.x
		var yaw: float = o.y
		# Salto-Winkel GLATT zum nächsten Wegpunkt interpolieren (statt pro Punkt zu springen): sonst
		# steht der Auto-Körper im alten Winkel, während es schon den geraden Abschnitt zum nächsten
		# Punkt entlangfährt → eine Ecke schiebt durch die Loop-Wand. Nur, solange der Folgepunkt
		# ebenfalls eine explizite Loop-Orientierung hat (sonst Ein-/Ausfahrt → Bewegungs-Ausrichtung).
		var nxt = _wp_orient[(_cur_wp + 1) % _wp_orient.size()]
		if nxt is Vector2:
			th  = lerp(o.x, (nxt as Vector2).x, _cur_seg_f)
			yaw = lerp_angle(o.y, (nxt as Vector2).y, _cur_seg_f)
		# Fahrtrichtung (horizontal) + Querachse aus dem gespeicherten yaw zurückrechnen
		# (yaw = atan2(fwd.x, fwd.z) + MODEL_ROTATION_OFFSET).
		var fwd := Vector3(-cos(yaw), 0.0, sin(yaw))
		var rgt := Vector3(-fwd.z, 0.0, fwd.x)
		# Basis: auf fwd ausrichten (Ry(yaw)), dann Salto um die Welt-Querachse rgt (rgt × fwd = up,
		# also dreht +th die Nase nach oben – passend zum aufsteigenden Looping-Bogen).
		car.basis = Basis(rgt, th) * Basis(Vector3.UP, yaw)
		_prev_yaw   = yaw - MODEL_ROTATION_OFFSET
		_yaw_init   = true
		_prev_car_y = car.position.y
		return

	var dir := car.position - prev_pos
	var flat_dir := Vector3(dir.x, 0, dir.z)
	_prev_car_y = car.position.y

	# Vorausschau: Position PITCH_LOOKAHEAD s in der Zukunft. Liegt der bevorstehende (oder aktuelle)
	# Abschnitt im Rampensprung, neigt sich die Nase schon JETZT – also bevor der Bogen tatsächlich
	# beginnt. Dadurch schneidet die flache Schnauze nicht mehr ins ansteigende Rampen-Asset.
	var ahead := _sample_pose_at_time(t + PITCH_LOOKAHEAD)
	var ahead_pos: Vector3 = ahead["pos"]
	var ahead_wp:  int     = int(ahead["wp"])
	var jump_now:   bool = _cur_wp  < _wp_jump.size() and _wp_jump[_cur_wp]  == 1
	var jump_ahead: bool = ahead_wp < _wp_jump.size() and _wp_jump[ahead_wp] == 1
	var jump_active: bool = jump_now or jump_ahead
	# Eis-Wheelie nur, solange das Auto auf dem Eisfeld SELBST steht (kein Lookahead) und kein
	# Rampensprung aktiv ist (Rampe hat Vorrang bei der Nasenneigung).
	var ice_now: bool = (not jump_active) and _cur_wp < _wp_ice.size() and _wp_ice[_cur_wp] == 1

	if flat_dir.length() > 0.0001:
		var new_yaw := atan2(flat_dir.x, flat_dir.z)

		# ── Rampensprung: Nase über die QUERACHSE neigen ──────────────────
		# Zielwinkel = Steigung zur Vorausschau-Position (hoch beim Auffahren, runter im Sinkflug zur
		# Landung, eben am Scheitel). Über eine MANUELL gebaute Basis (Drehung um die Welt-Querachse
		# rgt), NICHT über rotation.x – das wäre eine Fass-Rolle, weil die Front entlang der lokalen −X
		# zeigt (siehe Looping-Zweig). Bleibt aktiv, bis die Neigung sanft auf 0 abgeklungen ist →
		# das Auto richtet sich beim Runterfahren langsam wieder gerade aus.
		# Eis-Wheelie: auf dem Eisfeld Zielwinkel = ICE_WHEELIE_PITCH (Nase steil hoch, ~40°), sonst
		# Rampenlogik. Beim Verlassen klingt _pitch über denselben Zweig sanft wieder auf 0 ab.
		if jump_active or ice_now or absf(_pitch) > 0.02:
			var look := ahead_pos - car.position
			var look_flat := Vector2(look.x, look.z).length()
			var pitch_t: float
			if ice_now:
				pitch_t = ICE_WHEELIE_PITCH
			elif jump_active:
				pitch_t = clampf(atan2(look.y, maxf(look_flat, 0.001)), -PITCH_MAX, PITCH_MAX)
			else:
				pitch_t = 0.0
			var smooth: float = ICE_PITCH_SMOOTH if ice_now else PITCH_SMOOTH
			_pitch = lerp(_pitch, pitch_t, clampf(delta * smooth, 0.0, 1.0))
			var yaw_full := new_yaw + MODEL_ROTATION_OFFSET
			var fwd := Vector3(-cos(yaw_full), 0.0, sin(yaw_full))
			var rgt := Vector3(-fwd.z, 0.0, fwd.x)
			car.basis = Basis(rgt, _pitch) * Basis(Vector3.UP, yaw_full)
			_prev_yaw = new_yaw
			_yaw_init = true
			return

		car.rotation.y = new_yaw + MODEL_ROTATION_OFFSET

		# ── Kurvenneigung (Roll) ──────────────────────────────────────────
		if _yaw_init:
			var dyaw := new_yaw - _prev_yaw
			if dyaw >  PI: dyaw -= 2.0 * PI
			if dyaw < -PI: dyaw += 2.0 * PI
			var yaw_rate  := dyaw / maxf(delta, 0.001)
			var roll_t    := clampf(-yaw_rate * ROLL_FACTOR, -ROLL_MAX, ROLL_MAX)
			# Steilwandkurve: dort „lehnt" sich das Auto bewusst stark in die Wand (Banking aus der
			# pro-Wegpunkt-Höhe), in dieselbe Richtung wie die normale Kurvenneigung (sign der Gierrate).
			var bank : float = _wp_bank[_cur_wp] if _cur_wp < _wp_bank.size() else 0.0
			if bank > 0.001:
				# Steilkurve: Auto legt sich NUR seitlich (Tür-Roll um die lokale X, siehe car.rotation.x unten)
				# in die Kurve – KEIN Nick/Wheelie über rotation.z (das war die Querachse, siehe unten).
				# Bank-Richtung EINMALIG am ersten Einlenk-Frame festnageln (_wall_lean_dir==0) und danach
				# HALTEN. Die Neigung selbst ist KONSTANT (WALL_LEAN_X, NICHT mit der pro-Wegpunkt-Höhe
				# `bank` skaliert – das ließ den Roll pro Kachel 0→Scheitel→0 pumpen = sichtbares Zucken): das
				# Auto am ANFANG einmal in die Bank und erst am ENDE (bank→0, beim Verlassen der zwei
				# Kacheln) wieder zurück – kein Zucken mehr „zwischen jedem Punkt".
				if absf(yaw_rate) > 0.001 and _wall_lean_dir == 0.0:
					_wall_lean_dir = signf(yaw_rate)
				# KEIN rotation.z-„Banking" mehr: das ist (Modell-Front = lokale −X) die QUERACHSE = Nick/Salto,
				# also der Wheelie-Effekt wie beim Eis. Der User will in der Steilkurve NUR die seitliche X-Neigung.
				# rotation.z (Pitch-Achse) aktiv auf 0 halten, falls aus einer normalen Kurve noch Rest da ist.
				car.rotation.z = lerp(car.rotation.z, 0.0, clampf(delta * WALL_ROLL_SMOOTH, 0.0, 1.0))
				# Seitliche Neigung um die LÄNGSACHSE (lokale X) in die Kurvenmitte – die EINZIGE Drehung hier,
				# KONSTANT (WALL_LEAN_X ~30°), einmal rein und über beide Kacheln halten.
				_wall_lean = lerp(_wall_lean, _wall_lean_dir * WALL_LEAN_X, clampf(delta * WALL_ROLL_SMOOTH, 0.0, 1.0))
			else:
				car.rotation.z = lerp(car.rotation.z, roll_t, delta * ROLL_SMOOTH)
				_wall_lean = lerp(_wall_lean, 0.0, clampf(delta * ROLL_SMOOTH, 0.0, 1.0))
				_wall_lean_dir = 0.0   # zurücksetzen → die nächste Steilkurve bestimmt die Richtung neu
		else:
			car.rotation.z = lerp(car.rotation.z, 0.0, delta * ROLL_SMOOTH)
			_wall_lean = lerp(_wall_lean, 0.0, clampf(delta * ROLL_SMOOTH, 0.0, 1.0))
		# Längsachsen-Rolle: außerhalb der Steilkurve läuft _wall_lean auf 0 → Auto wird beim Verlassen
		# des Tiles wieder gerade gemacht.
		car.rotation.x = _wall_lean
		_prev_yaw  = new_yaw
		_yaw_init  = true


# ── Verbindungs-Logik ──────────────────────────────────────────────────────────

func _get_connections(data) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}

	var bn: bool; var be: bool; var bs: bool; var bw: bool
	if data["type"] == "straight" or data["type"] == "ramp_start" or data["type"] == "ramp_end" or data["type"] == "ice" or data["type"] == "race_straight" or data["type"] == "sand_straight" or data["type"] == "water_straight" or data["type"] == "glue_straight":
		bn = false; be = true; bs = false; bw = true
	elif data["type"] == "loop":
		# Looping: bei rot=0 vertikal (rein Süden, raus Norden). Drehbar wie eine Gerade.
		bn = true; be = false; bs = true; bw = false
	elif data["type"] == "wall_start":
		# Steilwandkurve – Einfahrt-Hälfte: bei rot=0 offen nach S (zur Partner-Kachel) und W (außen).
		bn = false; be = false; bs = true; bw = true
	elif data["type"] == "wall_end":
		# Steilwandkurve – Ausfahrt-Hälfte: bei rot=0 offen nach N (zur Partner-Kachel) und W (außen).
		bn = true; be = false; bs = false; bw = true
	elif data["type"] == "portal":
		# Portal: genau EINE offene Seite (zur andockenden Strecke), je nach Rotation.
		var od := _portal_open_dir_d(data)
		return {"N": od == "N", "E": od == "E", "S": od == "S", "W": od == "W"}
	elif data["type"] == "curve" or data["type"] == "curve_alt" or data["type"] == "ice_curve" or data["type"] == "race_curve" or data["type"] == "sand_curve" or data["type"] == "water_curve" or data["type"] == "glue_curve":
		# curve/curve_alt/ice_curve/race_curve/sand_/water_/glue_curve haben dieselben Öffnungen – nur Wegpunkte unterscheiden sich
		# rot=0: S+E  rot=90: W+S  rot=180: N+W  rot=270: N+E
		match data["rotation"]:
			0:   bn = false; be = true;  bs = true;  bw = false
			90:  bn = false; be = false; bs = true;  bw = true
			180: bn = true;  be = false; bs = false; bw = true
			270: bn = true;  be = true;  bs = false; bw = false
			_:   bn = false; be = true;  bs = true;  bw = false
		return {"N": bn, "E": be, "S": bs, "W": bw}
	else:
		return {}

	# Rotation im Uhrzeigersinn: 90° CW dreht N→E, E→S, S→W, W→N
	var steps = (data["rotation"] / 90) % 4
	var rn = bn; var re = be; var rs = bs; var rw = bw
	for _i in range(steps):
		var tmp_n = rw; var tmp_e = rn; var tmp_s = re; var tmp_w = rs
		rn = tmp_n; re = tmp_e; rs = tmp_s; rw = tmp_w

	if data.get("direction", 1) == -1:
		for _j in range(2):
			var tmp_n = rw; var tmp_e = rn; var tmp_s = re; var tmp_w = rs
			rn = tmp_n; re = tmp_e; rs = tmp_s; rw = tmp_w

	return {"N": rn, "E": re, "S": rs, "W": rw}


func _through(data, entry_dir: String) -> String:
	# Portal: nimmt das Auto nur über seine offene Seite an; der eigentliche „Ausgang" ist der
	# Teleport zum Partner-Portal (in _build_waypoints behandelt). Hier nur die Einfahrt zulassen.
	if _is_portal(data):
		var od := _portal_open_dir_d(data)
		return od if entry_dir == od else ""
	var conns = _get_connections(data)
	for dir in ["N", "E", "S", "W"]:
		if conns.get(dir, false) and dir != entry_dir:
			return dir
	return ""


func _step(row: int, col: int, dir: String) -> Vector2i:
	match dir:
		"N": return Vector2i(row - 1, col)
		"S": return Vector2i(row + 1, col)
		"E": return Vector2i(row, col + 1)
		"W": return Vector2i(row, col - 1)
	return Vector2i(-1, -1)


func _opposite(dir: String) -> String:
	match dir:
		"N": return "S"
		"S": return "N"
		"E": return "W"
		"W": return "E"
	return ""


# True, wenn das Tile eine Rampe ist und exit_dir zur Partner-Kachel zeigt (= Sprung über das
# Mittelfeld). Gilt für ramp_start UND ramp_end, damit die Rampe in beide Richtungen befahrbar ist.
func _ramp_jumps_toward(data, row: int, col: int, exit_dir: String) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var t = data.get("type", "")
	if t != "ramp_start" and t != "ramp_end":
		return false
	var pr = int(data.get("ramp_partner_row", -1))
	var pc = int(data.get("ramp_partner_col", -1))
	if pr < 0 or pc < 0:
		return false
	var dir := ""
	if pc > col: dir = "E"
	elif pc < col: dir = "W"
	elif pr > row: dir = "S"
	elif pr < row: dir = "N"
	return dir == exit_dir


# ── Wegpunkt-Berechnung ────────────────────────────────────────────────────────

func _build_waypoints(grid_state: Array) -> Array[Vector3]:
	var grid_rows = grid_state.size()
	var grid_cols = grid_state[0].size() if grid_rows > 0 else 0

	var start_row = -1
	var start_col = -1
	var exit_dir  = "E"

	# Start-Tile suchen
	for row in range(grid_rows):
		for col in range(grid_cols):
			var d = grid_state[row][col]
			if typeof(d) == TYPE_DICTIONARY and d.get("is_start", false):
				start_row = row
				start_col = col
				# Fahrtrichtung = Pfeil-Richtung des Start-Felds: 0→O, 90→S, 180→W, 270→N.
				# Spiegelt Main._start_exit_dir().
				exit_dir  = ["E", "S", "W", "N"][(((int(d.get("rotation", 0)) % 360) + 360) / 90) % 4]
				break
		if start_row >= 0:
			break

	# Fallback: erstes Tile das einen gültigen Nachbarn hat
	if start_row < 0:
		for row in range(grid_rows):
			for col in range(grid_cols):
				var d = grid_state[row][col]
				if typeof(d) != TYPE_DICTIONARY:
					continue
				var conns = _get_connections(d)
				for dir in ["E", "S", "W", "N"]:
					if not conns.get(dir, false):
						continue
					var nxt = _step(row, col, dir)
					if nxt.x < 0 or nxt.x >= grid_rows or nxt.y < 0 or nxt.y >= grid_cols:
						continue
					if typeof(grid_state[nxt.x][nxt.y]) != TYPE_DICTIONARY:
						continue
					start_row = row; start_col = col; exit_dir = dir
					break
				if start_row >= 0:
					break
			if start_row >= 0:
				break

	if start_row < 0:
		return []

	# Route verfolgen – max Schritte = alle Tiles × 2, genug für jeden geschlossenen Kreis
	var max_steps = grid_rows * grid_cols * 2
	var visited: Dictionary = {}
	var route: Array = []
	var row = start_row
	var col = start_col

	for _i in range(max_steps):
		var key = "%d_%d" % [row, col]
		if key in visited:
			break
		visited[key] = true
		var cur_data = grid_state[row][col]
		var rec_entry := {"row": row, "col": col, "data": cur_data, "exit": exit_dir}

		# Portal: teleportiert zum Partner-Portal; das Auto verlässt das Partner-Portal über dessen
		# offene Seite (Richtung = durch die Fahrtrichtung bestimmt). Das Partner-Portal wird NICHT
		# als eigenes Route-Feld gezählt (kein doppelter Ertrag) – seine Pose steckt in den Wegpunkten.
		if _is_portal(cur_data):
			var part = _portal_partner(grid_state, row, col)
			if part.x < 0:
				route.append(rec_entry)
				break
			rec_entry["portal_to_row"] = part.x
			rec_entry["portal_to_col"] = part.y
			route.append(rec_entry)
			var odir = _portal_open_dir_d(grid_state[part.x][part.y])
			var emerge = _step(part.x, part.y, odir)
			if emerge.x < 0 or emerge.x >= grid_rows or emerge.y < 0 or emerge.y >= grid_cols:
				break
			var emerge_data = grid_state[emerge.x][emerge.y]
			if typeof(emerge_data) != TYPE_DICTIONARY:
				break
			visited["%d_%d" % [part.x, part.y]] = true   # Partner-Portal verbraucht
			var nx = _through(emerge_data, _opposite(odir))
			if nx == "":
				break
			row = emerge.x; col = emerge.y; exit_dir = nx
			continue

		route.append(rec_entry)

		var next = _step(row, col, exit_dir)
		# Rampe: Mittelfeld (der Sprung) überspringen, sobald der Ausgang zur Partner-Kachel zeigt –
		# egal ob von der ramp_start- oder ramp_end-Seite (Fahrtrichtung wird automatisch erkannt).
		if _ramp_jumps_toward(grid_state[row][col], row, col, exit_dir):
			var skip = _step(next.x, next.y, exit_dir)
			if skip.x >= 0 and skip.x < grid_rows and skip.y >= 0 and skip.y < grid_cols:
				next = skip
		if next.x < 0 or next.x >= grid_rows or next.y < 0 or next.y >= grid_cols:
			break
		var next_data = grid_state[next.x][next.y]
		if typeof(next_data) != TYPE_DICTIONARY:
			break

		var entry = _opposite(exit_dir)
		var next_exit = _through(next_data, entry)
		if next_exit == "":
			break

		row = next.x
		col = next.y
		exit_dir = next_exit

	print("Route: %d Tiles gefunden" % route.size())

	# Pro befahrenem Feld einen STRECKENFIXEN Ertrags-Eintrag bauen (ohne Upgrade-Werte!).
	# Economy._lap_reward_for_car faltet daraus pro Runde live den "Schneeball".
	# >>> VERBINDLICHE RECHEN-REGEL (Schritt 1 = alle +Werte, dann Schritt 2 = alle ×Werte je Feld;
	#     bei Unklarheit über +/× beim Nutzer rückfragen): siehe Block über _lap_reward_for_car
	#     in Economy.gd. Neue tile-bezogene Boni hier als +Wert (base/bonus_points) ODER ×Wert
	#     (fixed_mult/bonus_mult) einsortieren – passend zu dieser Regel.
	# kind steuert, welches additive Upgrade Economy auf dieses Feld legt.
	var n        = route.size()
	tile_rewards = []
	var step_speed := PackedFloat32Array()   # Tempo-Faktor je Step (Booster/Bremse, sonst 1.0)
	var step_bonus := PackedFloat32Array()   # absoluter m/s-Bonus je Step (Eisgerade)
	for _k in range(n):
		step_bonus.append(0.0)
	for k in range(n):
		var d = route[k]["data"]
		step_speed.append(_tile_speed_factor(d))
		var rec := {
			"base": 0.0, "kind": "plain", "fixed_mult": 1.0,
			"bonus_points": 0.0, "bonus_mult": 1.0, "stand_mult": 1.0, "stand_count": 0,
			"is_jump": false, "is_loop": false, "loop_teleport": false,
			"type": "", "is_start": false, "is_dirt": false,   # für geheime Erfolge (Routen-Form)
		}
		if typeof(d) == TYPE_DICTIONARY:
			var t = d.get("type", "")
			rec["type"]     = t
			rec["is_start"] = bool(d.get("is_start", false))
			rec["is_dirt"]  = bool(d.get("is_dirt", false))
			# Default-Tile = gekauft (nicht Dreck, nicht Start) und eine echte Fahrkachel.
			var is_premium = (not d.get("is_dirt", false)) and (not d.get("is_start", false)) \
				and t in ["straight", "curve", "curve_alt", "race_straight", "race_curve", "sand_straight", "sand_curve"]
			if is_premium and t in ["race_straight", "race_curve"]:
				# Rennstrecke: hoher flacher Ertrag (+1000) UND fester ×1.2; eigene additive Upgrades.
				rec["base"]       = RACE_TILE_EARN
				rec["fixed_mult"] = RACE_TILE_MULT
				rec["kind"]       = "pracestraight" if t == "race_straight" else "pracecurve"
			elif is_premium and t in ["sand_straight", "sand_curve"]:
				# Sand: günstigste bezahlte Strecke (+15, kein Multiplikator); eigene additive Upgrades.
				rec["base"]       = SAND_TILE_EARN
				rec["fixed_mult"] = 1.0
				rec["kind"]       = "psandstraight" if t == "sand_straight" else "psandcurve"
			elif is_premium:
				rec["base"]       = PREMIUM_TILE_EARN
				rec["fixed_mult"] = PREMIUM_TILE_MULT
				rec["kind"]       = "pstraight" if t == "straight" else "pcurve"
			elif t == "ramp_start":
				# Rampe: Grundertrag am Absprung-Feld. Den Sprung-×2 legt Economy live drauf
				# (get_ramp_jump_mult, via kind "ramp") – die Rampe verdoppelt damit ihren EIGENEN
				# Ertrag. Zusätzlich bekommt das übersprungene Mittelfeld denselben ×2 (is_jump).
				rec["base"] = Economy.RAMP_BASE_EARN
				rec["kind"] = "ramp"
			elif t == "wall_start":
				# Steilwandkurve: Geld-Grundertrag am Einfahrt-Feld. Den vollen Betrag (Basis +
				# Upgrade) legt Economy live als kind "wall" drauf (get_wall_earn). wall_end bleibt 0.
				rec["base"] = 0.0
				rec["kind"] = "wall"
			elif t == "loop":
				# Looping: kein eigener Additiv-Ertrag, aber ×2 + Verdopplung aller anderen Mult.
				# (Economy._lap_reward_for_car über is_loop). base/kind bleiben neutral.
				rec["is_loop"] = true
			elif t == "portal":
				# Portal: additiver Geld-Ertrag am Eingangs-Portal (Economy get_portal_earn als kind
				# "portal"). Nur das betretene Portal steht in der Route → kein doppelter Ertrag.
				rec["kind"] = "portal"
				# Geheim „Loopingspringer?": liegt genau ein Looping zwischen diesem und dem Partner-
				# Portal (waagerecht/senkrecht), teleportiert das Auto durch den Looping (statt Rampe).
				rec["loop_teleport"] = _portal_loop_teleport(grid_state, route[k])
			elif d.get("is_dirt", false):
				rec["base"] = DIRT_TILE_EARN
				rec["kind"] = "dstraight" if t == "straight" else "dcurve"
			else:
				rec["base"] = BASIC_TILE_EARN   # Start-/Standard-/ramp_end-Feld (nur Tile-Bonus zählt)
			rec["bonus_points"] = float(d.get("bonus_points", 0.0))
			rec["bonus_mult"]   = float(d.get("bonus_mult", 1.0))   # ×1.5-Bonusfeld (ohne Tribünen)
			rec["stand_mult"]   = float(d.get("stand_mult", 1.0))   # Produkt aller Tribünen-Mult.
			rec["stand_count"]  = int(d.get("stand_count", 0))      # Anzahl wirkender Tribünen
			# Sprung-Mittelfeld: ein ECHTES, befahrenes Tile mit jump_mult bekommt den Sprung-×2.
			rec["is_jump"]      = d.get("jump_mult", 1.0) != 1.0
		tile_rewards.append(rec)

	# Eisgerade: legt einen absoluten Tempo-Bonus auf das EIGENE Feld UND die nächsten
	# get_ice_range() Felder (in Fahrtrichtung, über die geschlossene Schleife). Das Auto wird also
	# schon auf dem Eisfeld selbst schneller (j=0) und bleibt es die Folge-Felder lang. Mehrere
	# Eisgeraden summieren sich.
	var ice_bonus := Economy.get_ice_speed_bonus()
	var ice_range := Economy.get_ice_range()
	if ice_bonus > 0.0 and n > 0:
		for ik in range(n):
			var idata = route[ik]["data"]
			if typeof(idata) == TYPE_DICTIONARY and idata.get("type", "") in ["ice", "ice_curve"]:
				for j in range(0, ice_range + 1):
					step_bonus[(ik + j) % n] += ice_bonus

	# Steilwandkurve: der absolute Tempo-Bonus greift SOFORT beim Auffahren – auf dem Einfahrt-Feld
	# selbst (j=0) UND den nächsten get_wall_range() Folge-Feldern, genau wie bei der Eisgerade.
	# (Vorher startete er erst ab dem Folgefeld j=1, also erst auf der zweiten Haarnadel-Hälfte.)
	var wall_bonus := Economy.get_wall_speed_bonus()
	var wall_range := Economy.get_wall_range()
	if wall_bonus > 0.0 and n > 0:
		for wk in range(n):
			var wdata = route[wk]["data"]
			if typeof(wdata) == TYPE_DICTIONARY and wdata.get("type", "") == "wall_start":
				for j in range(0, wall_range + 1):
					step_bonus[(wk + j) % n] += wall_bonus

	# Wegpunkte aus Route bauen + Zuordnung Wegpunkt→Step (für die Tempo-Faktor-Tabelle)
	var wps: Array[Vector3] = []
	_wp_to_step = PackedInt32Array()
	_wp_bank = PackedFloat32Array()
	_wp_orient = []
	_wp_teleport = PackedByteArray()
	_wp_jump = PackedByteArray()
	_wp_ice = PackedByteArray()
	var half_t: float = TILE_SIZE / 2.0
	for si in range(n):
		var step = route[si]
		var center = Vector3(
			step["col"] * TILE_SIZE + TILE_SIZE / 2.0,
			0.05,
			step["row"] * TILE_SIZE + TILE_SIZE / 2.0
		)
		var sdata = step["data"]
		var tile_wps: Array[Vector3] = []
		var tile_orient: Array = []
		var tile_tele: PackedByteArray = PackedByteArray()
		var tile_jump: PackedByteArray = PackedByteArray()
		var tile_ice: PackedByteArray = PackedByteArray()
		var tile_bank: PackedFloat32Array = PackedFloat32Array()

		if _is_portal(sdata) and step.has("portal_to_row"):
			# Portal: Eingangskante → Eingang-Mitte → [Teleport] → Ausgang-Mitte → Ausgangskante.
			# Orientierung explizit (Eingang/Ausgang-Yaw), damit der Snap keinen Dreh-Glitch erzeugt.
			var oa := _portal_open_dir_d(sdata)
			var bdata = grid_state[int(step["portal_to_row"])][int(step["portal_to_col"])]
			var ob := _portal_open_dir_d(bdata)
			var b_center := Vector3(
				int(step["portal_to_col"]) * TILE_SIZE + TILE_SIZE / 2.0,
				0.05,
				int(step["portal_to_row"]) * TILE_SIZE + TILE_SIZE / 2.0
			)
			var vin := _dir_to_vec(_opposite(oa))
			var vout := _dir_to_vec(ob)
			var yaw_in := atan2(vin.x, vin.z) + MODEL_ROTATION_OFFSET
			var yaw_out := atan2(vout.x, vout.z) + MODEL_ROTATION_OFFSET
			# Eingang/Ausgang fahren NICHT bis zur Mitte, sondern eine Rampe HOCH und tief ins Tile zum
			# Tor (entgegen der offenen Seite). Dort verschwindet/erscheint das Auto (Teleport).
			var gate_a : Vector3 = center - _dir_to_vec(oa) * PORTAL_GATE_DEPTH + Vector3(0.0, PORTAL_RAMP_H, 0.0)
			var gate_b : Vector3 = b_center - _dir_to_vec(ob) * PORTAL_GATE_DEPTH + Vector3(0.0, PORTAL_RAMP_H, 0.0)
			tile_wps.append(center + _dir_to_vec(oa) * half_t)   # Eingangskante (unten)
			tile_wps.append(gate_a)                              # Rampe hoch, tief zum Tor → verschwindet
			tile_wps.append(gate_b)                              # erscheint am Ausgangs-Tor (oben, tief)
			tile_wps.append(b_center + _dir_to_vec(ob) * half_t) # Ausgangskante (Rampe runter, raus)
			# Nase neigt sich wie bei der Rampe: beim Hochfahren Nase hoch (+), beim Runterfahren Nase
			# runter (−). Winkel = Steigung der Rampe (Höhe / horizontaler Weg Kante→Tor). Über dieselbe
			# Pitch-Basis wie der Looping-Salto (o.x in _update_orientation, Drehung um die Querachse).
			var climb : float = atan2(PORTAL_RAMP_H, half_t + PORTAL_GATE_DEPTH)
			# Eingangskante+Tor: Nase hoch (climb). Ausgangs-Tor: Nase runter (−climb, Abstieg). Ausgangs-
			# KANTE: wieder waagerecht (0) → beim Verlassen des Tiles steht das Auto gerade.
			tile_orient = [Vector2(climb, yaw_in), Vector2(climb, yaw_in), Vector2(-climb, yaw_out), Vector2(0.0, yaw_out)]
			tile_tele = PackedByteArray([0, 1, 0, 0])   # Segment ab Wegpunkt[1] = Teleport (Tor→Tor)
			tile_bank = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
			tile_jump = PackedByteArray([0, 0, 0, 0])
			tile_ice = PackedByteArray([0, 0, 0, 0])
		else:
			tile_wps = _waypoints_for_tile(center, sdata, step["exit"], step["row"], step["col"])
			tile_orient = _pending_orient.duplicate()
			var is_wall : bool = typeof(sdata) == TYPE_DICTIONARY and sdata.get("type", "") in ["wall_start", "wall_end"]
			# Rampen-Kachel mit Sprungbogen → alle ihre Wegpunkte als „in der Luft" markieren.
			var is_ramp : bool = typeof(sdata) == TYPE_DICTIONARY and sdata.get("type", "") in ["ramp_start", "ramp_end"]
			# Eisfeld → alle seine Wegpunkte für den Wheelie markieren (Nase hoch, nur hier).
			var is_ice : bool = typeof(sdata) == TYPE_DICTIONARY and sdata.get("type", "") in ["ice", "ice_curve"]
			for w in range(tile_wps.size()):
				tile_tele.append(0)
				tile_jump.append(1 if is_ramp else 0)
				tile_ice.append(1 if is_ice else 0)
				tile_bank.append(clampf((tile_wps[w].y - 0.05) / WALL_PEAK_H, 0.0, 1.0) if is_wall else 0.0)

		for _w in range(tile_wps.size()):
			_wp_to_step.append(si)
		_wp_bank.append_array(tile_bank)
		_wp_orient.append_array(tile_orient)
		_wp_teleport.append_array(tile_tele)
		_wp_jump.append_array(tile_jump)
		_wp_ice.append_array(tile_ice)
		wps.append_array(tile_wps)

	# Wheelie schon auf dem ANFAHRT-Segment auslösen: das erste Wegpunkt eines Eisfeldes ist seine
	# Mitte (Gerade: [Mitte, Ausgangskante]), die Anfahrt von der Eingangskante gehört noch zum
	# Vorgänger-Step. Darum auch den jeweils VORHERGEHENDEN Wegpunkt jedes Eis-Wegpunkts markieren →
	# das Auto stellt die Nase bereits beim Auffahren auf, nicht erst in der Feldmitte.
	var ni := _wp_ice.size()
	if ni > 0:
		var orig := _wp_ice.duplicate()
		for w in range(ni):
			if orig[w] == 1:
				_wp_ice[(w - 1 + ni) % ni] = 1

	# Segment-Zeittabelle bauen: Position UND Geld leiten sich ab jetzt nur noch hieraus ab.
	_build_time_table(wps, step_speed, step_bonus)
	return wps


# Tempo-Faktor eines Tiles (1.0 = normal). Booster-/Brems-Tiles setzen später "speed_mult"
# in ihrem Tile-Dictionary; lap_time und visuelle Position passen sich automatisch an.
func _tile_speed_factor(data) -> float:
	if typeof(data) == TYPE_DICTIONARY:
		return maxf(0.05, float(data.get("speed_mult", 1.0)))
	return 1.0


# Pro Wegpunkt-Segment: Dauer = Länge ÷ (Tempo × Tile-Faktor). lap_time = Summe aller Dauern.
# Das ist die EINE Wahrheitsquelle für visuelle Position (_sample_at_time) und Geld
# (Economy._credit_laps bekommt dasselbe lap_time von World3D).
func _build_time_table(wps: Array[Vector3], step_speed: PackedFloat32Array, step_bonus: PackedFloat32Array = PackedFloat32Array()) -> void:
	var n := wps.size()
	_seg_time = PackedFloat32Array()
	_cum_time = PackedFloat32Array()
	var acc := 0.0
	for i in range(n):
		_cum_time.append(acc)
		# Portal-Teleport: feste, kurze Dauer (kein Streak über die ganze Karte) statt Länge/Tempo.
		if i < _wp_teleport.size() and _wp_teleport[i] == 1:
			_seg_time.append(TELEPORT_TIME)
			acc += TELEPORT_TIME
			continue
		var seg_len := wps[i].distance_to(wps[(i + 1) % n])
		var stp := _wp_to_step[i] if i < _wp_to_step.size() else 0
		var factor : float = step_speed[stp] if stp < step_speed.size() else 1.0
		# Eisgerade-Bonus ist ABSOLUT (m/s), wird also auf das Segment-Tempo addiert – nicht
		# multipliziert –, damit er „so viel schneller wie N Tempo-Stufen" bleibt, egal wie hoch
		# das Grund-Tempo ist.
		var bonus : float = step_bonus[stp] if stp < step_bonus.size() else 0.0
		var seg_speed : float = maxf(0.01, speed * factor + bonus)
		_seg_time.append(seg_len / seg_speed)
		acc += seg_len / seg_speed
	lap_time = acc


func _waypoints_for_tile(center: Vector3, data: Dictionary, exit_dir: String, row: int, col: int) -> Array[Vector3]:
	var wps: Array[Vector3] = []
	_pending_orient = []   # je Wegpunkt: Vector2(pitch,yaw) (Looping) oder null (normale Ausrichtung)
	var half = TILE_SIZE / 2.0
	var type    = data["type"]
	var rot     = data["rotation"]
	var flipped = data.get("flipped", false)

	if type == "ramp_start" or type == "ramp_end":
		# Nur die AUFFAHR-Seite (Ausgang zeigt zur Partner-Kachel) erzeugt den Sprungbogen über das
		# Mittelfeld; die Lande-Seite liefert keine eigenen Wegpunkte. So springt das Auto unabhängig
		# davon, ob die Strecke von der Start- oder End-Seite in die Rampe läuft.
		if _ramp_jumps_toward(data, row, col, exit_dir):
			# Parabolischer Bogen: Auffahr-Mitte → über Mittelfeld → Partner-Ausgang
			var d      = _dir_to_vec(exit_dir)
			var peak_h = 0.55
			var p_end  = Vector3(
				center.x + d.x * TILE_SIZE * 2.5,
				0.05,
				center.z + d.z * TILE_SIZE * 2.5
			)
			var arc_steps = 16
			for i in range(arc_steps + 1):
				var t   = float(i) / arc_steps
				var pos = center.lerp(p_end, t)
				# Auffahrt-Hälfte (t<0.5) etwas anheben (max. am Anfang, linear bis zum Scheitel auf 0):
				# bringt das Auto früher/höher → kein Einrutschen in die Rampe. Scheitel/Landung bleiben.
				var lift := RAMP_TAKEOFF_LIFT * maxf(0.0, 1.0 - t / 0.5)
				pos.y   = peak_h * 4.0 * t * (1.0 - t) + 0.05 + lift
				wps.append(pos)

	elif type == "straight" or type == "ice" or type == "race_straight" or type == "sand_straight" or type == "water_straight" or type == "glue_straight":
		wps.append(center)
		wps.append(center + _dir_to_vec(exit_dir) * half)

	elif type == "loop":
		# Looping: Anfahrt (leicht nach rechts) → senkrechter Looping (Auto fährt komplett herum,
		# oben kopfüber) → Ausfahrt (zurück zur Mitte, nach links). Der Looping kehrt horizontal zu
		# seinem Einstieg zurück; Ein-/Ausstieg sind seitlich versetzt (rein rechts, raus links),
		# damit sich die Strecke nicht selbst schneidet. Höhe 2·LOOP_R → Rampensprung fliegt hindurch.
		var fwd   := _dir_to_vec(exit_dir)
		var rgt   := Vector3(-fwd.z, 0.0, fwd.x)   # „rechts" relativ zur Fahrtrichtung
		var up    := Vector3(0.0, 1.0, 0.0)
		var yaw   := atan2(fwd.x, fwd.z) + MODEL_ROTATION_OFFSET
		var entry : Vector3 = center - fwd * half
		var lp_in := center + rgt * LOOP_OFF        # Looping-Einstieg (rechts versetzt)
		var lp_out := center - rgt * LOOP_OFF       # Looping-Ausstieg (links versetzt)
		var ex : Vector3 = center + fwd * half
		# 1. Anfahrt (eben). Damit das Auto GERADE in den Looping einfährt (statt seitlich zum
		# Loop-Fuß zu schwenken), liegen die letzten beiden Anfahrt-Punkte exakt auf der seitlichen
		# Loop-Einstiegslinie (lp_in, Versatz LOOP_OFF): der vorhandene Maul-Punkt wird seitlich auf
		# diese Linie ausgerichtet, und direkt vor dem Loop-Fuß kommt ein zusätzlicher Punkt dazu.
		# Der seitliche Versatz passiert so früh auf der flachen Anfahrt (entry → Maul-Punkt).
		wps.append(entry);                          _pending_orient.append(null)
		wps.append(lp_in - fwd * (half * 0.5));     _pending_orient.append(null)  # Maul-Punkt, auf Loop-Linie
		wps.append(lp_in - fwd * LOOP_MOUTH_OUT);   _pending_orient.append(null)  # neu: direkt vor dem Loop-Fuß
		# 2. Looping (θ 1..LOOP_SEGS → 2π). Pitch = θ (Auto dreht sich einmal komplett).
		for i in range(1, LOOP_SEGS + 1):
			var th := TAU * float(i) / float(LOOP_SEGS)
			var p := lp_in + fwd * (LOOP_FWD * sin(th)) + up * (LOOP_R * (1.0 - cos(th))) \
				+ rgt * (-2.0 * LOOP_OFF * (th / TAU))
			wps.append(p)
			_pending_orient.append(Vector2(th, yaw))
		# 3. Ausfahrt (eben), spiegelbildlich: erst GERADE aus dem Loop-Fuß heraus (zwei Punkte auf der
		# lp_out-Linie), dann seitlich zur Kachelmitte zurück.
		wps.append(lp_out + fwd * LOOP_MOUTH_OUT);  _pending_orient.append(null)  # neu: direkt hinter dem Loop-Fuß
		wps.append(lp_out + fwd * (half * 0.5));    _pending_orient.append(null)  # Maul-Punkt, auf Loop-Linie
		wps.append(ex);                             _pending_orient.append(null)

	elif type == "curve" or type == "curve_alt" or type == "ice_curve" or type == "race_curve" or type == "sand_curve" or type == "water_curve" or type == "glue_curve":
		var cx: float; var cz: float
		var a_from: float; var a_to: float
		match rot:
			0:
				cx =  half; cz =  half; a_from = PI;        a_to = PI * 1.5
			90:
				cx = -half; cz =  half; a_from = PI * 1.5;  a_to = PI * 2.0
			180:
				cx = -half; cz = -half; a_from = 0.0;       a_to = PI * 0.5
			270:
				cx =  half; cz = -half; a_from = PI * 0.5;  a_to = PI
			_:
				cx =  half; cz =  half; a_from = PI;        a_to = PI * 1.5

		# Sweep-Richtung des Bogens an die TATSÄCHLICHE Durchfahrtsrichtung (exit_dir) koppeln,
		# nicht an den Tile-Typ (curve/curve_alt). Der Vorwärts-Bogen (a_from→a_to) verlässt das
		# Tile je Rotation Richtung E/S/W/N; fährt das Auto andersherum, Reihenfolge tauschen –
		# sonst läge der erste Wegpunkt an der Ausgangskante und das Auto würde rückwärts fahren.
		var fwd_exit := "E"
		match rot % 360:
			0:   fwd_exit = "E"
			90:  fwd_exit = "S"
			180: fwd_exit = "W"
			270: fwd_exit = "N"
		if exit_dir != fwd_exit:
			var tmp = a_from; a_from = a_to; a_to = tmp

		var steps = 10
		for i in range(steps + 1):
			var t     = float(i) / float(steps)
			var angle = lerp(a_from, a_to, t)
			wps.append(Vector3(
				center.x + cx + cos(angle) * half,
				0.05,
				center.z + cz + sin(angle) * half
			))

	elif type == "wall_start" or type == "wall_end":
		# Steilwandkurve (Wall-Ride): zwei vertikal gestapelte Kacheln bilden eine 180°-Haarnadel.
		# Jede Kachel ist ein Viertelbogen wie eine Kurve (effektive Kurven-Rotation eff). Zusätzlich
		# hebt sich die Fahrbahn zur GEMEINSAMEN Kante beider Kacheln (Apex) → das Auto fährt dort
		# „an der Wand". Der Apex ist für beide Kacheln derselbe Weltpunkt → nahtloser Übergang.
		var pr := int(data.get("ramp_partner_row", row))
		var pc := int(data.get("ramp_partner_col", col))
		# Runder Halbkreis über beide Kacheln, OHNE dass der Eingang raussteht: Die Außen-Anschluss-
		# punkte (Kachelkanten-Mitte zur Strecke) bleiben FIX, nur der Scheitel (Apex) wölbt sich um
		# WALL_BULGE tiefer in die gebankte Fahrbahn. Pro Kachel ein Kreisbogen Außenpunkt→Apex; die
		# Tangente am Apex steht senkrecht zur Öffnung → beide Hälften treffen sich glatt zum runden U.
		# WALL_BULGE=0 ⇒ exakt der alte Halbkreis (Radius = halbe Kachel).
		var conns := _get_connections(data)
		var partner_d := _partner_dir(row, col, pr, pc)
		var outer_d := ""
		for dd_dir in ["N", "E", "S", "W"]:
			if conns.get(dd_dir, false) and dd_dir != partner_d:
				outer_d = dd_dir
		var outer_vec := _dir_to_vec(outer_d)
		var partner_vec := _dir_to_vec(partner_d)
		var shared_mid := Vector2(center.x + partner_vec.x * half, center.z + partner_vec.z * half)
		var p_out := Vector2(center.x + outer_vec.x * half, center.z + outer_vec.z * half)
		var depth : float = half * WALL_BULGE
		# Apex = Scheitelpunkt der gemeinsamen Kante, um depth ins Tile-Innere (entgegen der Öffnung) gewölbt.
		var apex_v : Vector2 = shared_mid - Vector2(outer_vec.x, outer_vec.z) * depth
		# Kreisbogen durch p_out und apex_v mit Apex-Tangente senkrecht zur Öffnung: Mittelpunkt liegt
		# auf der Öffnungs-Achse durch den Apex. R aus |C−p_out| = |C−apex| = R.
		var u : float = depth + half
		var arc_r : float = (u * u + half * half) / (2.0 * u)
		var arc_c2 : Vector2 = apex_v + Vector2(outer_vec.x, outer_vec.z) * arc_r
		var ang_p : float = (p_out - arc_c2).angle()
		var dsw2 : float = (apex_v - arc_c2).angle() - ang_p
		while dsw2 >  PI: dsw2 -= TAU
		while dsw2 < -PI: dsw2 += TAU
		var apex := Vector3(apex_v.x, 0.05, apex_v.y)
		var d_max : float = maxf((p_out - apex_v).length(), 0.001)
		var steps2 = 12
		var wall_pts : Array[Vector3] = []
		for i in range(steps2 + 1):
			var t2    = float(i) / float(steps2)
			var ang : float = ang_p + dsw2 * t2
			var p := Vector3(arc_c2.x + cos(ang) * arc_r, 0.05, arc_c2.y + sin(ang) * arc_r)
			var dd := Vector2(p.x - apex.x, p.z - apex.z).length()
			var hf := clampf(1.0 - dd / d_max, 0.0, 1.0)
			hf = smoothstep(0.0, 1.0, hf)   # gerundeter Scheitel (passend zur 3D-Fahrbahn)
			p.y = 0.05 + WALL_PEAK_H * hf
			wall_pts.append(p)
		# Reihenfolge an die Fahrtrichtung: verlässt das Auto die Kachel nach außen → Apex zuerst
		# (Apex→Außen); verlässt es Richtung Partner → Außen zuerst (Außen→Apex).
		if exit_dir == outer_d:
			wall_pts.reverse()
		for wp in wall_pts:
			wps.append(wp)

	# Wegpunkte ohne explizite Looping-Orientierung bekommen null (= normale Bewegungs-Ausrichtung).
	while _pending_orient.size() < wps.size():
		_pending_orient.append(null)
	return wps


# ── Portal-Helfer ────────────────────────────────────────────────────────────────
func _is_portal(data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("type", "") == "portal"


# Offene Seite eines Portals (wo die Strecke andockt) abhängig von der Rotation.
func _portal_open_dir_d(data) -> String:
	var rot = int(data.get("rotation", 0)) % 360
	return ["W", "N", "E", "S"][(rot / 90) % 4]


# Geheim-Erfolg „Loopingspringer?": Liegt zwischen einem Portal (entry) und seinem Partner-Portal
# GENAU EIN Looping in einer geraden Linie (waagerecht ODER senkrecht, beide Portale 2 Felder
# auseinander, das Mittelfeld ein Loop)? Dann teleportiert das Auto „durch" den Looping statt zu fahren.
func _portal_loop_teleport(grid_state: Array, entry: Dictionary) -> bool:
	if not entry.has("portal_to_row"):
		return false
	var r0 := int(entry["row"]); var c0 := int(entry["col"])
	var r1 := int(entry["portal_to_row"]); var c1 := int(entry["portal_to_col"])
	var mr := -1; var mc := -1
	if r0 == r1 and abs(c0 - c1) == 2:
		mr = r0; mc = (c0 + c1) / 2
	elif c0 == c1 and abs(r0 - r1) == 2:
		mr = (r0 + r1) / 2; mc = c0
	else:
		return false
	if mr < 0 or mr >= grid_state.size() or mc < 0 or mc >= grid_state[mr].size():
		return false
	var mid = grid_state[mr][mc]
	return typeof(mid) == TYPE_DICTIONARY and mid.get("type", "") == "loop"


# Das ANDERE Portal auf der Strecke (von max. 2). (-1,-1) falls keins.
func _portal_partner(grid_state: Array, row: int, col: int) -> Vector2i:
	for r in range(grid_state.size()):
		var rowarr = grid_state[r]
		for c in range(rowarr.size()):
			var d = rowarr[c]
			if typeof(d) == TYPE_DICTIONARY and d.get("type", "") == "portal" and not (r == row and c == col):
				return Vector2i(r, c)
	return Vector2i(-1, -1)


# Himmelsrichtung von (row,col) zur Partner-Kachel (pr,pc) – für die Steilwandkurve.
func _partner_dir(row: int, col: int, pr: int, pc: int) -> String:
	if pc > col: return "E"
	elif pc < col: return "W"
	elif pr > row: return "S"
	elif pr < row: return "N"
	return "S"


func _dir_to_vec(dir: String) -> Vector3:
	match dir:
		"N": return Vector3(0, 0, -1)
		"S": return Vector3(0, 0,  1)
		"E": return Vector3( 1, 0, 0)
		"W": return Vector3(-1, 0, 0)
	return Vector3.ZERO


# ── Debug-Fahrlinie ───────────────────────────────────────────────────────────────
# Zeichnet an jeden Wegpunkt eine kleine Kugel: Steilkurven-Punkte ROT (über _wp_bank erkannt),
# alle anderen dezent blau. Jeder Aufbau löscht die alten Marker (Gruppe "wall_dbg") und zeichnet
# neu → es bleibt immer genau EIN Satz übrig, egal wie viele Autos die Route bauen.
func _draw_debug_path() -> void:
	if car == null:
		return
	var parent := car.get_parent()
	if parent == null:
		return
	for old in get_tree().get_nodes_in_group("wall_dbg"):
		old.queue_free()
	var n := waypoints.size()
	for i in range(n):
		var is_wall : bool = i < _wp_bank.size() and _wp_bank[i] > 0.001
		var sm := SphereMesh.new()
		sm.radius = 0.06 if is_wall else 0.03
		sm.height = sm.radius * 2.0
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.12, 0.12) if is_wall else Color(0.2, 0.6, 1.0)
		mi.material_override = mat
		mi.position = waypoints[i] + Vector3(0.0, 0.06, 0.0)
		mi.add_to_group("wall_dbg")
		parent.add_child(mi)
