extends Node
## Lädt die Übersetzungstabelle (i18n/translations.txt) und registriert sie beim
## TranslationServer. Deutsch ist die Quellsprache und steht direkt im Code; die Tabelle
## liefert je eine Spalte für Englisch (en), Spanisch (es) und Französisch (fr). Fehlt in
## einer Zielsprache ein Eintrag, greift Godots Fallback (Englisch); fehlt der Schlüssel
## ganz, bleibt der deutsche Quelltext stehen. Statische Control-Texte werden über auto_translate automatisch
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

	# Eine Translation je Zielsprache. Spaltenreihenfolge in der Tabelle: key, en, es, fr.
	var tr_en := Translation.new()
	tr_en.locale = "en"
	var tr_es := Translation.new()
	tr_es.locale = "es"
	var tr_fr := Translation.new()
	tr_fr.locale = "fr"
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
			header_done = true   # erste echte Zeile ist die Kopfzeile (key,en,es,fr)
			continue
		if cols.size() < 2:
			continue
		var src := cols[0].replace("\\n", "\n")
		if src == "":
			continue
		# Deutsch immer als Identität; en/es/fr nur, wenn die Spalte gefüllt ist
		# (leere Zelle → Fallback auf Englisch greift automatisch).
		tr_de.add_message(src, src)
		var en := cols[1].replace("\\n", "\n")
		if en != "":
			tr_en.add_message(src, en)
		if cols.size() >= 3:
			var es := cols[2].replace("\\n", "\n")
			if es != "":
				tr_es.add_message(src, es)
		if cols.size() >= 4:
			var fr := cols[3].replace("\\n", "\n")
			if fr != "":
				tr_fr.add_message(src, fr)
	f.close()

	TranslationServer.add_translation(tr_en)
	TranslationServer.add_translation(tr_es)
	TranslationServer.add_translation(tr_fr)
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
