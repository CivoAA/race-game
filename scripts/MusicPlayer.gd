extends Node
## Autoload "MusicPlayer": spielt die Hintergrundmusik dauerhaft in Schleife auf
## dem "Music"-Audiobus. Die Lautstärke wird über den Musik-Regler (Options in
## MainMenu/PauseMenu) gesteuert, der direkt die Lautstärke des "Music"-Busses setzt.

const MUSIC_PATH := "res://assets/musik/mainmenu.mp3"

var _player: AudioStreamPlayer
# true  = Musik läuft weiter, wenn das Fenster minimiert / im Hintergrund ist
# false = Musik pausiert, sobald das Fenster den Fokus verliert
var _music_on_minimize := true


func _ready() -> void:
	# Musik läuft weiter, auch wenn das Spiel pausiert ist (PauseMenu).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_on_minimize = bool(_load_setting("music_on_minimize", true))

	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)

	var stream := load(MUSIC_PATH)
	if stream == null:
		push_warning("MusicPlayer: Konnte Musik nicht laden: %s" % MUSIC_PATH)
		return

	# MP3/OGG in Endlosschleife abspielen.
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true

	_player.stream = stream
	# Sicherheitsnetz: Falls der Loop-Flag des Streams mal nicht greift, beim Ende neu starten.
	# (Bei aktivem Loop wird "finished" nicht ausgelöst → harmlos.)
	_player.finished.connect(_player.play)
	_player.play()


# Vom Audio-Menü aufgerufen, wenn der Toggle umgeschaltet wird.
func set_music_on_minimize(on: bool) -> void:
	_music_on_minimize = on
	# Sofort wirksam: läuft wieder, falls gerade wegen Fokusverlust pausiert.
	if on and _player != null:
		_player.stream_paused = false


# Fenster-Fokuswechsel (auch Minimieren) abfangen und Musik je nach Einstellung
# pausieren bzw. fortsetzen.
func _notification(what: int) -> void:
	if _player == null:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if not _music_on_minimize:
				_player.stream_paused = true
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_player.stream_paused = false


func _load_setting(key: String, default_value: Variant) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(Paths.SETTINGS_FILE)
	return cfg.get_value("options", key, default_value)
