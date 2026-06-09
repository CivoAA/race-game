extends Node
## Autoload "MusicPlayer": spielt die Hintergrundmusik dauerhaft in Schleife auf
## dem "Music"-Audiobus. Die Lautstärke wird über den Musik-Regler (Options in
## MainMenu/PauseMenu) gesteuert, der direkt die Lautstärke des "Music"-Busses setzt.

const MUSIC_PATH := "res://assets/musik/mainmenu.mp3"

var _player: AudioStreamPlayer


func _ready() -> void:
	# Musik läuft weiter, auch wenn das Spiel pausiert ist (PauseMenu).
	process_mode = Node.PROCESS_MODE_ALWAYS

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
