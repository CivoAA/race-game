extends Node
## Zentrale Hinweis-/Tooltip-Tabelle für den Shop (Texte, die über dem Upgrade-Namen
## erscheinen, wenn man ~1 s darüber hovert).
##
## Lokalisierung läuft jetzt komplett über i18n/translations.txt (TranslationServer):
## Diese Datei hält nur noch die Zuordnung  Upgrade-ID → deutscher Quelltext.  Der
## deutsche Text ist zugleich der Übersetzungs-Schlüssel; die englische (oder weitere)
## Übersetzung steht in translations.txt. `hint()` gibt daher `tr(<deutscher Text>)`
## zurück – fehlt eine Übersetzung, bleibt der deutsche Quelltext stehen.
##
## Neue Sprache hinzufügen: KEINE Änderung hier nötig – einfach den deutschen Text als
## Schlüssel mit der Übersetzung in translations.txt ergänzen.
##
## Platzhalter: {value} im Text wird NICHT hier, sondern vom Aufrufer (GlobalModal)
## durch den aktuellen Upgrade-Wert ersetzt – so bleibt der Text sprachunabhängig.
##
## Öffentliche API (hint(), set_language(), get_language()) bleibt unverändert, damit die
## Aufrufer (GlobalModal) unverändert weiterlaufen.

# id → deutscher Quelltext (= Übersetzungs-Schlüssel in i18n/translations.txt).
# Nur Upgrades, die im Upgrade-Menü ("Allgemeines"/"Bonusfelder") auftauchen, brauchen
# hier einen Eintrag.
const HINTS := {
	"speed":
		"Tempo macht deine Autos schneller, sodass sie in derselben Zeit mehr Runden "
		+ "fahren und du mehr verdienst. Pass aber auf: Manche Autos brauchen mehr "
		+ "Tempo als andere.",
	"tilebonus":
		"Der Tile-Bonus gibt dir {value} Währung zusätzlich für jedes Feld, über das "
		+ "dein Auto fährt – ganz egal, welches Feld du baust.",
	"drive_time":
		"Die Fahrzeit bestimmt, wie lange ein Lauf dauert. Je länger gefahren wird, "
		+ "desto mehr Runden schaffen deine Autos pro Lauf.",
	"endmult":
		"Der End-Multiplikator vervielfacht den gesamten Ertrag einer Runde ganz am "
		+ "Ende. Jede Stufe macht damit jeden Lauf wertvoller.",
	"car_count":
		"Jede Stufe gibt dir ein weiteres Auto auf der Strecke. Mehr Autos bedeuten "
		+ "mehr Runden gleichzeitig und damit mehr Währung.",
	"bonus_plus5":
		"Schaltet +5-Felder frei. Sie werden automatisch auf der Strecke platziert (nicht "
		+ "von dir gebaut). Fährt ein Auto darüber, gibt es zusätzliche Währung obendrauf.",
	"bonus_plus10":
		"Schaltet +10-Felder frei – wie die +5-Felder, nur mit doppeltem Bonus. Sie werden "
		+ "ebenfalls automatisch auf der Strecke platziert.",
	"bonus_mult15":
		"Schaltet ×1.5-Felder frei (werden automatisch platziert). Sie multiplizieren den "
		+ "bis dahin gesammelten Ertrag einer Runde, statt nur etwas dazuzuaddieren.",

	# Super-Auto („Auto 2" / Kombination)
	"super_car":
		"Auto 2 verschmilzt mehrere normale Autos zu einem einzigen Kombi-Auto: Es fährt "
		+ "langsamer, bringt aber pro Feld viel mehr Währung und am Ende einen extra "
		+ "Multiplikator. Du brauchst dafür genug Autos und genug Tempo.",

	# ── Streckenteile (Schlüssel = Upgrade-ID der Tile) ──────────────────────
	"dirtstraightbonus":
		"Dreck-Gerade: ein von Anfang an gratis Streckenteil. Jedes überfahrene Feld bringt "
		+ "etwas Währung; dieses Upgrade erhöht den Ertrag pro Dreck-Gerade.",
	"dirtcurvebonus":
		"Dreck-Kurve: gratis Kurvenstück. Wie die Dreck-Gerade, nur als Kurve – das Upgrade "
		+ "steigert den Ertrag pro Dreck-Kurve.",
	"straightbonus":
		"Normale Gerade: bringt mehr Währung als die Dreck-Variante und hat einen kleinen "
		+ "×-Bonus. Das Upgrade erhöht den Ertrag pro Gerade.",
	"curvebonus":
		"Normale Kurve: bringt mehr Währung als die Dreck-Variante und hat einen kleinen "
		+ "×-Bonus. Das Upgrade erhöht den Ertrag pro Kurve.",
	"icebonus":
		"Eisgerade: gibt keine Währung, macht dein Auto aber auf den folgenden Feldern "
		+ "schneller – mehr Tempo bedeutet mehr Runden. Das Upgrade verstärkt Boost und Reichweite.",
	"rampbonus":
		"Rampe: lässt das Auto über das nächste Kreuzungsfeld springen und verdoppelt dort "
		+ "den Ertrag. Das Upgrade erhöht den Rampen-Ertrag und den Sprung-Bonus.",
	"wallbonus":
		"Steilwandkurve: eine 180°-Kehre. Sie bringt Währung und gibt dem Auto danach einen "
		+ "Tempo-Schub. Das Upgrade steigert beides.",
	"loopbonus":
		"Looping: verdoppelt den Ertrag des Feldes und verstärkt zusätzlich alle anderen "
		+ "Multiplikatoren auf diesem Feld. Das Upgrade erhöht den Faktor.",
	"portalbonus":
		"Portal: teleportiert dein Auto von einem Ende zum anderen und gibt bei jedem "
		+ "Durchgang viel Währung. Es gibt immer genau zwei pro Strecke. Das Upgrade erhöht den Ertrag.",
	"standbonus":
		"Tribüne: nicht befahrbar, vervielfacht aber den Ertrag der direkt benachbarten "
		+ "Felder. Mehrere nebeneinander stapeln den Effekt. Das Upgrade erhöht den Multiplikator.",
}


# Sprache umschalten. Lokalisierung läuft über den TranslationServer (siehe
# Localization.gd) – daher hier nur an diesen durchreichen, API bleibt erhalten.
func set_language(code: String) -> void:
	TranslationServer.set_locale(code)


func get_language() -> String:
	return TranslationServer.get_locale()


## Hinweistext für ein Upgrade in der aktuellen Sprache (über translations.txt). Leerer
## String, wenn für die ID kein Text hinterlegt ist (→ Aufrufer zeigt keinen Tooltip).
func hint(id: String) -> String:
	if not HINTS.has(id):
		return ""
	return tr(String(HINTS[id]))
