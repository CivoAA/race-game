extends Node
## Autoload "Sfx": spielt UI-Soundeffekte (Hover & Klick) auf dem "SFX"-Bus.
## Da der Effekte-Regler (Options in MainMenu/PauseMenu) die Lautstärke des
## "SFX"-Busses setzt, werden diese Sounds automatisch lauter/leiser geregelt.
##
## Verkabelung: JEDER Button im ganzen Spiel wird automatisch verbunden –
##   • Maus über dem Button  → Hover-Sound (sound-9)
##   • Button gedrückt        → Klick-Sound (sound-14)
## Dazu wird auf get_tree().node_added gehorcht, sodass auch erst später per Code
## erzeugte Buttons (Menüs, Modals, HUD) ohne manuelles Verbinden mitspielen.

# Wie viele Effekte gleichzeitig klingen dürfen (kleiner Stimmen-Pool, damit ein
# schneller Hover-Klick-Wechsel sich nicht selbst abschneidet).
const POOL_SIZE := 6

# Grund-Pegel der UI-Sounds in Dezibel (verlustfrei, liegt UNTER dem Effekte-Regler).
#   0 = Originallautstärke · negativ = leiser · jeweils ~ -6 dB = halbe Lautstärke.
# Hier zum Feinjustieren drehen, ohne die MP3-Dateien anzufassen.
const HOVER_GAIN_DB := -10.0
const CLICK_GAIN_DB := -8.0

# Mindestabstand zwischen zwei Hover-Sounds in Millisekunden. Wer schnell über mehrere
# Menüpunkte fährt, löst dadurch nicht im Maschinengewehr-Tempo Dutzende Sounds aus.
const HOVER_MIN_INTERVAL_MS := 60

var _hover_stream: AudioStream
var _click_stream: AudioStream
# Hover hat eine EIGENE Stimme: jeder neue Hover startet sie neu und schneidet damit
# den vorherigen Hover ab → nie gestapelte, überlagerte Hover-Sounds.
var _hover_player: AudioStreamPlayer
var _last_hover_ms := 0
# Klicks dürfen sich überlappen → kleiner Round-Robin-Stimmen-Pool.
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	# Auch im pausierten Spiel (PauseMenu) sollen Menü-Sounds klingen.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_hover_stream = _load_oneshot(Paths.SFX_UI_HOVER)
	_click_stream = _load_oneshot(Paths.SFX_UI_CLICK)

	# Dedizierte Einzelstimme für Hover (siehe oben).
	_hover_player = AudioStreamPlayer.new()
	_hover_player.bus = "SFX"
	_hover_player.stream = _hover_stream
	_hover_player.volume_db = HOVER_GAIN_DB
	add_child(_hover_player)

	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)

	# Künftige Buttons automatisch verkabeln und die bereits vorhandenen gleich mit.
	get_tree().node_added.connect(_on_node_added)
	_wire_existing(get_tree().root)


# Effekt-Streams dürfen – anders als die Hintergrundmusik – nicht loopen.
# Eigene Kopie (duplicate), damit der Loop-Flag keine andere Verwendung beeinflusst.
func _load_oneshot(path: String) -> AudioStream:
	var res := load(path)
	if res == null:
		push_warning("Sfx: Konnte Sound nicht laden: %s" % path)
		return null
	if res is AudioStreamMP3:
		var s := (res as AudioStreamMP3).duplicate() as AudioStreamMP3
		s.loop = false
		return s
	if res is AudioStreamOggVorbis:
		var s := (res as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		s.loop = false
		return s
	return res as AudioStream


# ── Öffentliche Wiedergabe (auch manuell aufrufbar: Sfx.play_click()) ──────────

func play_hover() -> void:
	if _hover_player == null:
		return
	# Zu dicht aufeinanderfolgende Hover (schneller Sweep) überspringen.
	var now := Time.get_ticks_msec()
	if now - _last_hover_ms < HOVER_MIN_INTERVAL_MS:
		return
	_last_hover_ms = now
	# Neustart schneidet einen evtl. noch laufenden Hover ab → immer nur eine Stimme.
	_hover_player.play()


func play_click() -> void:
	_play(_click_stream, CLICK_GAIN_DB)


# Spielt den Stream über die nächste freie Stimme im Pool (Round-Robin).
func _play(stream: AudioStream, gain_db: float) -> void:
	if stream == null or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = gain_db
	p.play()


# ── Automatische Button-Verkabelung ────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node)


func _wire_existing(root: Node) -> void:
	for child in root.get_children():
		if child is BaseButton:
			_wire_button(child)
		_wire_existing(child)


func _wire_button(btn: BaseButton) -> void:
	# Doppelte Verbindung vermeiden (Node kann mehrfach durchlaufen werden).
	if btn.has_meta("_sfx_wired"):
		return
	btn.set_meta("_sfx_wired", true)
	# Hover nur, wenn der Button aktiv ist (deaktivierte sollen nicht klingen).
	btn.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			play_hover()
	)
	# Klick beim Drücken (button_down) → snappy und passt zur Druck-Animation.
	btn.button_down.connect(play_click)
