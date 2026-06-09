extends Node
## Lädt die Übersetzungstabelle (i18n/translations.txt) und registriert sie beim
## TranslationServer. Deutsch ist die Quellsprache und steht direkt im Code, daher
## gibt es nur eine englische Übersetzung – fehlt ein Eintrag, bleibt der deutsche
## Quelltext stehen. Statische Control-Texte werden über auto_translate automatisch
## übersetzt; dynamisch zusammengesetzte Texte (Tabs, Nav) rufen tr() selbst auf und
## bauen sich bei NOTIFICATION_TRANSLATION_CHANGED neu auf.
##
## Autoload "Localization" (direkt nach Paths, vor den UI-Autoloads).

# Als .txt (nicht .csv), damit Godot die Datei nicht automatisch als Translation-
# Ressource importiert – so bleibt sie auch in exportierten Builds per FileAccess lesbar.
const CSV_PATH := "res://i18n/translations.txt"


func _ready() -> void:
	_load_translations()
	# Gespeicherte Sprache anwenden (Standard: Englisch).
	var cfg := ConfigFile.new()
	cfg.load(Paths.SETTINGS_FILE)
	TranslationServer.set_locale(String(cfg.get_value("options", "language", "en")))


func _load_translations() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_warning("Localization: Übersetzungsdatei nicht gefunden: %s" % CSV_PATH)
		return

	var tr_en := Translation.new()
	tr_en.locale = "en"
	# Identitäts-Übersetzung für Deutsch (Quelltext → Quelltext). Nötig, weil Godots
	# Fallback-Locale standardmäßig "en" ist: ohne eine deutsche Auflösung würden im
	# Deutsch-Modus genau die hier übersetzten Schlüssel auf Englisch „durchschlagen".
	var tr_de := Translation.new()
	tr_de.locale = "de"

	var header_done := false
	while not f.eof_reached():
		var line := f.get_line()
		# Kommentare und Leerzeilen überspringen (vor dem CSV-Parsen prüfen).
		var stripped := line.strip_edges()
		if stripped == "" or stripped.begins_with("#"):
			continue
		var cols := _parse_csv_line(line)
		if not header_done:
			header_done = true   # erste echte Zeile ist die Kopfzeile (key,en)
			continue
		if cols.size() < 2:
			continue
		var src := cols[0].replace("\\n", "\n")
		var dst := cols[1].replace("\\n", "\n")
		if src == "" or dst == "":
			continue
		tr_en.add_message(src, dst)
		tr_de.add_message(src, src)
	f.close()

	TranslationServer.add_translation(tr_en)
	TranslationServer.add_translation(tr_de)


# Eigener CSV-Parser: behandelt in Anführungszeichen gesetzte Felder samt Kommata
# und verdoppelten Anführungszeichen ("") als Escape.
func _parse_csv_line(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var in_quotes := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if in_quotes:
			if c == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					cur += "\""
					i += 1
				else:
					in_quotes = false
			else:
				cur += c
		else:
			if c == "\"":
				in_quotes = true
			elif c == ",":
				out.append(cur)
				cur = ""
			else:
				cur += c
		i += 1
	out.append(cur)
	return out
