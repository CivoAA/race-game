extends Node
## Zentraler, persistenter Spielzustand: Währung + gekaufte Upgrades + 3 Track-Zustände.
## Wird als Autoload "Economy" geladen. Speichert in Slot-Dateien (user://savegame_slotN.dat).

const TRACK_COUNT = 3

const START_CURRENCY  = 0
# Umrechnung "Tempo"-Zahl (Shop, 25→150) → tatsächliche Auto-Geschwindigkeit (m/s).
# Basis-Tempo 25 · 0.1 = 2.5 m/s (bewusst langsam); Max-Tempo 150 · 0.1 = 15 m/s.
const SPEED_SCALE     = 0.1
# Tempo („Shop-Speed") wächst STÜCKWEISE LINEAR, damit es nicht zu viele Stufen gibt (siehe
# _speed_effect_value): +5/Stufe bis Tempo 450, dann +10/Stufe bis 1350, darüber +15/Stufe.
# Tatsächliche „ingame Speed" = Tempo ÷ Auto-Tier-Teiler (get_car_speed_div); engine-m/s = ingame · SPEED_SCALE.
# JEDES Auto-Tier teilt das Tempo durch SUPER_CAR_SPEED_DIV^t (Tier 0→÷1, 1→÷3, 2→÷9, 3→÷27) – jedes
# Auto ist also ein Drittel so schnell wie das vorige (1:1 / 3:1 / 9:1 / 27:1). Jedes Auto erreicht
# trotzdem dieselbe ingame-Höchstgeschwindigkeit (150): sein Tempo-Cap ist entsprechend höher,
# get_speed_cap_tempo() = SPEED_CAP_TEMPO · 3^t → 150 / 450 / 1350 / 4050 (= Sperrpunkt des Tempo-
# Upgrades je Tier). Jeder Tier startet mit so viel Tempo-Stufen, dass die ingame-Speed 5 ist
# (get_speed_tier_start_level, gratis als Head-Start). NUR Eis-/Steilwandkurve dürfen über die
# tatsächliche Höchstgeschwindigkeit hinaus beschleunigen (absoluter Segment-Aufschlag, CarController).
const SPEED_CAP_TEMPO = 150.0     # ingame-Höchstgeschwindigkeit (Tempo ÷ Tier-Teiler) für JEDES Auto
# Tempo-Kosten: steile Phase bis zum Standard-Cap (Tempo 150 = SPEED_STEEP_LEVELS Stufen bei +5),
# darüber sanftes Wachstum, damit die höheren Tiers ihren 3× höheren Cap mit ihrer (ebenfalls
# deutlich größeren) Wirtschaft erreichen können. Greift je Tier ab der ersten BEZAHLTen Stufe (der
# Head-Start verschiebt die Kostenkurve). Siehe _speed_cost.
const SPEED_STEEP_LEVELS = 30     # Stufen bis Tempo 150 = SPEED_CAP_TEMPO / 5 (steiler Kostenverlauf)
const SPEED_STEEP_GROWTH = 2.0    # Kostenwachstum je Stufe in der steilen Phase (0 → Tempo 150)
const SPEED_TAIL_GROWTH  = 1.04   # sanftes Kostenwachstum oberhalb des Standard-Caps (höhere Tiers)

# ── Super-Auto („Auto 2") ──────────────────────────────────────────────────────
# MEHRFACH kaufbar (super_car_count): jeder Kauf „kombiniert" SUPER_CAR_COST_CARS normale Autos zu
# EINEM Super-Auto – viel langsamer (Tempo ÷ SUPER_CAR_SPEED_DIV), dafür +SUPER_CAR_TILE_BONUS je
# Feld und ganz am Ende ×SUPER_CAR_END_MULT (beides OBEN DRAUF auf die globalen Geld-Upgrades).
# Kaufbar IMMER, wenn man genug FREIE Standard-Autos (SUPER_CAR_COST_CARS je weiteres Super-Auto)
# und Tempo ≥ SUPER_CAR_REQ_SPEED hat. Preis steigt je Kauf: COST·GROWTH^bereits_gekauft.
# Beim Streckenstart spawnen pro Super-Auto SUPER_CAR_COST_CARS Autos weniger + 1 Super-Auto.
const SUPER_CAR_COST        = 1_000_000_000   # Basis-Kaufpreis (1 Mrd); steigt je gekauftem Super-Auto
const SUPER_CAR_COST_GROWTH = 4.0             # Preis-Faktor je weiterem Super-Auto (1→4→16→64 Mrd …)
const SUPER_CAR_REQ_SPEED   = 75              # min. Tempo (speed-Effektwert) als Voraussetzung (≥)
const SUPER_CAR_COST_CARS   = 4               # so viele normale Autos werden je Super-Auto ersetzt
const SUPER_CAR_SPEED_DIV   = 3.0             # Tempo wird durch diesen Wert geteilt
const SUPER_CAR_TILE_BONUS  = 10000.0         # zusätzlicher +Ertrag JE Feld (oben drauf)
const SUPER_CAR_END_MULT    = 1.0             # KEIN zusätzlicher End-×Faktor mehr (Tier-Auto nur +Wert/Feld)

# ── Auto-Prestige (Tier) ────────────────────────────────────────────────────────
# In der Werkstatt (Tab „Autos") kann man ab einer Geld-Schwelle das Auto „upgraden": car_tier += 1,
# danach Voll-Reset (alles inkl. Prestige-Tree, NUR car_tier + Kosmetik bleiben) und ×4 Prestigepunkte
# je Stufe. Ab Stufe ≥1 fährt NUR das Tier-Auto (Super-Auto-Ökonomie); 4 normale Autos = 1 fahrendes
# Tier-Auto, Basis 1 gratis. Modell je Stufe liefert get_car_tier_model() (Paths sind Autoload-Consts,
# daher kein const-Array hier möglich). CAR_TIER_COUNT = Anzahl definierter Stufen-Modelle.
const CAR_TIER_COUNT        = 4   # 0 = Standard (default_car), 1 = "Renn"auto (eric), 2 = Frosch (miata), 3 = Blender-Auto (test_car_blender)
# JEDER Auto-Aufstieg wird mit PRESTIGE-PUNKTEN (⭐) bezahlt – KEIN Geld mehr. ⭐-Kosten je Aufstieg,
# indiziert nach dem AKTUELLEN car_tier: Standard→"Renn"auto = 1e7, "Renn"auto→Frosch = 1e12. Über die
# Liste hinaus skaliert es ×CAR_ASCEND_POINT_GROWTH je weiterer Stufe.
const CAR_ASCEND_POINT_COSTS = [1e7, 1e12, 1e17]  # ⭐ für [Tier 0→1, Tier 1→2, Tier 2→3]
const CAR_ASCEND_POINT_GROWTH = 1000.0           # ⭐-Schwelle ×1000 je Stufe über die Liste hinaus
const CAR_ASCEND_BASE       = 100_000_000_000.0  # (Legacy, ungenutzt) frühere Geld-Schwelle
const CAR_ASCEND_GROWTH     = 10.0               # Schwelle ×10 je weiterer Stufe
const CAR_ASCEND_POINT_MULT = 4.0                # ×4 Prestigepunkte je Stufe (stapelt: ×4, ×16, …)
const CAR_ASCEND_COUNT_MULT = 2.0                # ×2 Prestige-Zähler je Stufe (stapelt: ×2, ×4, …) →
												 # jedes Prestige schaltet entspr. mehr Baum-Knoten frei,
												 # macht den Werkstatt-Reset (prestige_count→0) weicher

# ── Upgrade-Definitionen ────────────────────────────────────────────────────────
# category: "general" oder "car" (car_* sind Vorlagen für car<idx>_<suffix>)
# Kosten pro Level = round(base_cost * growth^level)
# Effektwert pro Level = base + per_level * level
const UPGRADES = {
	# Tempo-ZAHL („Shop-Speed"): STÜCKWEISE linear (+5/+10/+15, siehe _speed_effect_value); base/
	# per_level werden für Tempo NICHT genutzt. Ingame-Speed = Tempo ÷ get_car_speed_div (Tier 1:1/3:1/
	# 9:1/27:1), engine-m/s = ingame · SPEED_SCALE. Tempo-Cap (Shop-Sperre) tier-abhängig 150/450/1350/
	# 4050 für dieselbe ingame-Höchstgeschwindigkeit 150 (get_speed_cap_tempo). Jeder Tier startet mit
	# Head-Start auf ingame-Speed 5 (get_speed_tier_start_level). Kosten: steil bis Tempo 150
	# (SPEED_STEEP_*), darüber sanft (SPEED_TAIL_GROWTH); siehe _speed_cost. max_level = großzügige
	# Obergrenze, der wirksame Cap kommt aus effective_max_level.
	"speed": {
		"category": "general", "name": "Tempo",
		"base_cost": 50, "growth": 4.4, "max_level": 2000,
		"base": 0.0, "per_level": 5.0, "unit": " Tempo",
	},
	# Fahrzeit: eigene Sequenz (_drive_time_value, special-case in _effect_at): 15,20,25,30,
	# 40,50,60,90,120,150,… (base/per_level dort ignoriert). Bei 30 s ~1 Mio Kosten.
	"drive_time": {
		# Im Shop normal bis Stufe 9 (= 150 s) kaufbar. Der Prestige-Knoten „Unendliche Fahrzeit"
		# (drive_time_inf) hebt den Cap auf Stufe 10 an (effective_max_level); erst der KAUF dieser
		# Stufe 10 schaltet das endlose Fahren frei (DRIVE_TIME_INF_LEVEL, is_endless_run).
		"category": "general", "name": "Fahrzeit",
		"base_cost": 1000, "growth": 5.6, "max_level": 9,
		"base": 30.0, "per_level": 15.0, "unit": "s",
	},
	# grid_size: aktuell NICHT im Shop (kommt später per Prestige) – Definition bleibt für die Getter.
	"grid_size": {
		"category": "hidden", "name": "Streckengröße",
		"base_cost": 100, "growth": 6.0, "max_level": 3,
		"base": 0.0, "per_level": 0.0, "unit": "",
	},
	"car_count": {
		# Mit dem Prestige-Knoten „Auto-Startlevel" (car_start) zusammengeführt: beide teilen sich diese
		# Level-Skala (get_upgrade_level = max(gekauft, Head-Start-Floor)). HART GEDECKELT: die effektive
		# max_level kommt aus get_max_level("car_count") = 3 · SUPER_CAR_COST_CARS^car_tier (Tier 0 → 3,
		# Tier 1 → 12, Tier 2 → 48). Jedes zusätzliche fahrende Auto kostet je Werkstatt-Stufe ×4 so viele
		# Käufe; Fahr-Cap bleibt ACTIVE_CAR_CAP (= 4). Der max_level-Wert hier ist nur ein Fallback.
		"category": "general", "name": "Zusätzliches Auto",
		"base_cost": 1000000, "growth": 1.6, "max_level": 48,
		"base": 1.0, "per_level": 1.0, "unit": " Autos",
	},
	# End-Multiplikator & Tile-Bonus jetzt global (alle Autos), unter "Allgemeines".
	# Effekt special-cased (_endmult_value, base/per_level IGNORIERT): Stufe 1 = ×1.1, dann
	# in 0.1-Schritten bis ×3 (Lv20), in 0.2-Schritten bis ×5 (Lv30), in 0.5-Schritten bis
	# ×15 (Lv50), in 1.0-Schritten bis ×35 (Lv70). base_cost/growth bleiben unverändert.
	"endmult": {
		"category": "general", "name": "End-Multiplikator",
		"base_cost": 500, "growth": 3.5, "max_level": 70,
		"base": 1.0, "per_level": 0.5, "unit": "×",
	},
	# Tile-Bonus: +Geld je überfahrenem Feld. 100 Stufen. Kosten special-cased (_tilebonus_cost): die
	# ersten 10 Stufen wachsen sanfter (TILEBONUS_EARLY_GROWTH 1.25, günstigerer Einstieg), danach
	# stetig wieder mit growth 1.413. Effekt special-cased (_tilebonus_value, base/per_level IGNORIERT):
	# sanft bis +10/Feld bei Lv20, danach stark beschleunigt → Lv50 ≈ +10.000/Feld.
	"tilebonus": {
		"category": "general", "name": "Tile-Bonus",
		"base_cost": 10, "growth": 1.413, "max_level": 100,
		"base": 0.0, "per_level": 0.5, "unit": " /Feld",
	},
	# Tile-Upgrades: zusätzlicher Reward je überfahrenem Feld dieses Typs (additiv, vor endmult).
	# Werden im Streckenteile-Shop an der jeweiligen Tile geupgradet (nicht in der allg. Liste).
	# Die Dreck-Upgrades nutzen eine eigene Wertereihe (_dirt_field_earn, special-case in
	# _effect_at); base/per_level werden dort ignoriert. Dreck-Gerade & -Kurve getrennt.
	# Dreck-Upgrades bewusst günstig & sanft skalierend → früh leicht hochzuziehen.
	# Dreck-Upgrades: 3× so viele Stufen (60 statt 20). Ertrag/Kosten special-cased über
	# _tile_series (steigende 0.5-Schrittfolge + geom. Kosten g^(1/3)); Gesamtertrag & -kosten
	# bleiben wie bei den alten 20 Stufen. base/per_level werden ignoriert. base_cost/growth bleiben
	# die ALTEN Werte (Quelle für die Gesamt-Ziele, NICHT mehr direkt der Preis).
	"dirtstraightbonus": {
		"category": "tile", "name": "Erd-Geraden-Ertrag (+ je Feld)",
		"base_cost": 25, "growth": 2.3, "max_level": 60,
		"base": 0.0, "per_level": 0.0, "unit": " /Erde",
	},
	"dirtcurvebonus": {
		"category": "tile", "name": "Erd-Kurven-Ertrag (+ je Feld)",
		"base_cost": 25, "growth": 2.3, "max_level": 60,
		"base": 0.0, "per_level": 0.0, "unit": " /Erde",
	},
	# Gerade/Kurve geben einen FLACHEN +Ertrag pro Feld (kein Multiplikator mehr, siehe
	# CarController.PREMIUM_TILE_*). Das Upgrade skaliert bewusst halb so stark wie früher
	# (per_level 12.5 statt 25) und beginnt damit auch bei der Hälfte.
	# 3× so viele Stufen (36 statt 12). Ertrag/Kosten special-cased über _tile_series (steigende
	# 0.5-Schrittfolge + geom. Kosten g^(1/3)); Gesamtertrag (per_level·alt_max=150) & Gesamtkosten
	# bleiben wie bei den alten 12 Stufen. per_level/base_cost/growth = ALTE Werte (Ziel-Quelle).
	"straightbonus": {
		"category": "tile", "name": "Geraden-Ertrag (+ je Gerade)",
		"base_cost": 200, "growth": 3.0, "max_level": 36,
		"base": 0.0, "per_level": 12.5, "unit": " /Gerade",
	},
	"curvebonus": {
		"category": "tile", "name": "Kurven-Ertrag (+ je Kurve)",
		"base_cost": 200, "growth": 3.0, "max_level": 36,
		"base": 0.0, "per_level": 12.5, "unit": " /Kurve",
	},
	# Sand: günstigste bezahlte Strecke (+15 Grundertrag). Rein additive Upgrades; günstig
	# (base_cost 100) und mit moderatem Effekt (per_level 7.5), passend zum niedrigen Grundertrag.
	# 3× so viele Stufen (36 statt 12), Ertrag/Kosten via _tile_series (Gesamt = alte 12 Stufen).
	"sandstraightbonus": {
		"category": "tile", "name": "Sand-Geraden-Ertrag (+ je Gerade)",
		"base_cost": 100, "growth": 3.0, "max_level": 36,
		"base": 0.0, "per_level": 7.5, "unit": " /Gerade",
	},
	"sandcurvebonus": {
		"category": "tile", "name": "Sand-Kurven-Ertrag (+ je Kurve)",
		"base_cost": 100, "growth": 3.0, "max_level": 36,
		"base": 0.0, "per_level": 7.5, "unit": " /Kurve",
	},
	# Rennstrecke ist ein EIGENES Streckenteil (nicht mehr identisch zur Default-Gerade/-Kurve):
	# höherer flacher +Ertrag (CarController.RACE_TILE_EARN) UND ein fester ×1.2 (RACE_TILE_MULT).
	# Diese beiden Upgrades addieren NUR (+ je Feld, kein Multiplikator – Wunsch), skalieren aber
	# doppelt so stark wie die Default-Variante (per_level 25 statt 12.5) und kosten ~10× mehr.
	# 3× so viele Stufen (36 statt 12), Ertrag/Kosten via _tile_series (Gesamt = alte 12 Stufen).
	"racestraightbonus": {
		"category": "tile", "name": "Rennstrecken-Ertrag (+ je Gerade)",
		"base_cost": 2000, "growth": 3.0, "max_level": 36,
		"base": 0.0, "per_level": 25.0, "unit": " /Gerade",
	},
	"racecurvebonus": {
		"category": "tile", "name": "Rennkurven-Ertrag (+ je Kurve)",
		"base_cost": 2400, "growth": 3.0, "max_level": 36,
		"base": 0.0, "per_level": 25.0, "unit": " /Kurve",
	},
	# Eisgerade: gibt KEIN Geld, sondern macht das Auto auf den nächsten Feldern schneller.
	# base/per_level werden NICHT als Geld-Effekt genutzt – der Effekt ist special-cased über
	# get_ice_boost_levels()/get_ice_range() (Speed-Boost + Reichweite). max_level=15, damit die
	# Reichweiten-Stufen (5→4, 10→5, 15→6 Felder) sauber aufgehen.
	"icebonus": {
		"category": "tile", "name": "Eisgeraden-Boost (Speed je Feld)",
		"base_cost": 400, "growth": 2.6, "max_level": 15,
		"base": 0.0, "per_level": 0.0, "unit": "",
	},
	# Kleber-/Slime-Belag (Gegenstück zur Eisgerade): klebt das Auto fest → es wird auf dem Kleber-Feld
	# und den nächsten GLUE_BASE_RANGE Feldern PROZENTUAL LANGSAMER (multiplikativer Tempo-Faktor).
	# Dafür gibt es viel Geld je Kleber-Feld (Basis 50k). EIN gemeinsames Upgrade für Gerade UND Kurve
	# (wie icebonus). Effekt special-cased: Geld via get_glue_earn (prozentual steigend), Verlangsamung
	# via get_glue_slow_pct (Stufe 0 = −90 %, je 3 Upgrade-Stufen −5 %-Punkte, min. −20 %). base/per_level ignoriert.
	"gluebonus": {
		# base_cost = 20 % des Kleber-Freischaltpreises (1e12) – wie die Platzier-Preise der späten Teile.
		"category": "tile", "name": "Kleber-Ertrag (+ je Feld, bremst)",
		"base_cost": 200000000000, "growth": 1.5, "max_level": 42,
		"base": 0.0, "per_level": 0.0, "unit": "",
	},
	# Steilwandkurve (Wall-Ride): Geld UND Speed-Boost skalieren mit dem Upgrade. Das Geld läuft
	# über base/per_level (get_effect → +Wert am Einfahrt-Feld, Schritt 1 des Schneeballs), der
	# Speed-Boost ist wie bei der Eisgerade special-cased (get_wall_*). max_level=15, damit die
	# Reichweiten-Stufen (5→4, 10→5, 15→6 Felder) sauber aufgehen.
	"wallbonus": {
		"category": "tile", "name": "Steilwandkurven-Boost (Geld + Speed)",
		"base_cost": 50000, "growth": 2.8, "max_level": 15,
		"base": 5000.0, "per_level": 2500.0, "unit": "",
	},
	# Rampen-Upgrade: additiver Ertrag je Rampe (RAMP_BASE_EARN ist der Grundwert obendrauf) UND
	# alle 5 Stufen +0.2 auf den Sprung-Multiplikator (Stufe 5 → ×2.2, 10 → ×2.4 …) via
	# get_ramp_jump_mult(). max_level bewusst durch 5 teilbar, damit die Mult-Stufen sauber aufgehen.
	"rampbonus": {
		"category": "tile", "name": "Rampen-Ertrag (+ je Rampe)",
		"base_cost": 10000, "growth": 3.0, "max_level": 15,
		"base": 0.0, "per_level": 200.0, "unit": " /Rampe",
	},
	# Looping-Upgrade: erhöht den Loop-Faktor um 0.1 je Stufe (base 2.0 → Stufe 30 = 5.0). Seit
	# 2026-06-19 ist der Looping ein ganz normaler Multiplikator ×F (kein Schneeball mehr).
	# get_effect liefert direkt 2.0+0.1·Lvl. Preis startet bei 25 % des Unlock-Preises (2 Mrd → 500 Mio)
	# und wächst weiter steil (growth 2.8), passend zum teuren Spät-Tile.
	"loopbonus": {
		"category": "tile", "name": "Looping-Multiplikator (×)",
		"base_cost": 500000000, "growth": 2.8, "max_level": 30,
		"base": 2.0, "per_level": 0.1, "unit": "",
	},
	# Portal-Upgrade: additiver Geld-Ertrag am Eingangs-Portal (kein Multiplikator). 25 Stufen.
	# Geld skaliert bewusst etwas STÄRKER als übliche Tiles (per_level = 60 % der Basis je Stufe),
	# die KOSTEN steigen normal (growth wie andere Tile-Upgrades). base = 25k Grundertrag.
	"portalbonus": {
		"category": "tile", "name": "Portal-Ertrag (+ je Durchgang)",
		"base_cost": 80000, "growth": 2.6, "max_level": 25,
		"base": 25000.0, "per_level": 15000.0, "unit": "",
	},
	# Tribünen-Upgrade: Multiplikator auf das/die Nachbarfeld(er) vor der Tribüne. base 2.5, +0.1/Stufe
	# (Stufe 15 → 4.0). get_effect liefert direkt 2.5+0.1·Lvl. Stack 5 verdoppelt den Wert (in get_stand_mult).
	"standbonus": {
		"category": "tile", "name": "Tribünen-Multiplikator (×)",
		"base_cost": 200000, "growth": 2.6, "max_level": 15,
		"base": 2.5, "per_level": 0.1, "unit": "",
	},
	# Bonusfelder: je Typ max. 3 – das Upgrade-Level = Anzahl dieser Felder (Lv1 schaltet frei,
	# Lv2 = zweites Feld, Lv3 = drittes). Kosten steigen idle-typisch steil.
	"bonus_plus5": {
		"category": "bonus", "name": "+5-Feld",
		"base_cost": 2000, "growth": 6.0, "max_level": 3,
		"base": 0.0, "per_level": 1.0, "unit": "",
	},
	"bonus_plus10": {
		"category": "bonus", "name": "+10-Feld",
		"base_cost": 4000, "growth": 8.0, "max_level": 3,
		"base": 0.0, "per_level": 1.0, "unit": "",
	},
	# ×1.5-Feld ist stark → deutlich teurer (×10 ggü. vorher).
	"bonus_mult15": {
		"category": "bonus", "name": "×1.5-Felder",
		"base_cost": 200000, "growth": 10.0, "max_level": 3,
		"base": 0.0, "per_level": 1.0, "unit": "",
	},
}

# Rampe: Grundertrag am ramp_start-Feld (geht als base in dessen Tile-Eintrag) und Basis-Sprung-
# Multiplikator (×2). Das Rampen-Upgrade (rampbonus) erhöht den additiven Ertrag pro Stufe und den
# Sprung-Multiplikator je 5 Stufen (get_ramp_jump_mult).
const RAMP_BASE_EARN = 450.0
const RAMP_JUMP_BASE = 2.0

# Looping: ganz normaler Multiplikator ×F (seit 2026-06-19 kein Schneeball mehr – der liegt auf der
# Rampe). F = get_loop_factor() = 2.0 + 0.1·loopbonus-Level (Stufe 0 → 2.0, Stufe 30 → 5.0).
# LOOP_MULT = Basiswert (Stufe 0).
const LOOP_MULT = 2.0

# Grid-Dimensionen pro grid_size-Level: 4×4 → 4×5 → 4×6 → 5×6
const GRID_STEPS = [
	Vector2i(4, 4),
	Vector2i(4, 5),
	Vector2i(4, 6),
	Vector2i(5, 6),
]

# ── Prestige ────────────────────────────────────────────────────────────────────
# Punkte pro Prestige: ohne den EINMALIGEN „Break Prestige"-Unlock genau 1 Punkt; danach geldgetrieben.
#   pts      = 1                                   (Break Prestige nicht gekauft)
#   pts      = floor( sqrt(Geld / K) )             (Break Prestige gekauft) – am Gate 1, 8M 2, 200M 10 …
#   Ergebnis = pts · Auto-Stufen-Bonus (get_car_point_mult) · 2^„points_mult"
# KEIN Hard-Cap – mehr Geld gibt immer mehr Punkte; die Bremse ist rein ökonomisch (Punkt N braucht
# N²·K Geld). Der Prestige-Button rastet ab dem GELD AUF DEM KONTO ≥ K (= 2 Mio.) ein. K = Stellschraube.
const PRESTIGE_K = 2000000.0

# TEMP – Tab-Freischaltung: Schwellen, ab denen der Prestige- bzw. Werkstatt-Tab DAUERHAFT
# freigeschaltet wird. Prestige nach GELD AUF DEM KONTO (gleiche Schwelle wie der Gate),
# Werkstatt nach BESESSENEN PRESTIGE-PUNKTEN (⭐). Siehe _check_tab_unlocks().
# ENTFERNEN, sobald es einen Erfolge-Tab gibt – die Freischaltung dann dort auslösen.
const PRESTIGE_TAB_UNLOCK_EARN    = 2000000.0   # 2 Mio. (Geld auf dem Konto)
const WERKSTATT_TAB_UNLOCK_POINTS = 1000000     # 1 Mio. Prestige-Punkte (⭐ auf dem Konto)

# Tech-Baum: Knoten werden mit ⭐ bezahlt. Freigeschaltet wird POSITIONSBASIERT: der Knoten an
# Position p (1-basiert in PRESTIGE_ORDER) wird sichtbar/kaufbar, sobald man p-mal prestigt hat
# (prestige_count ≥ p). Jedes Prestige schaltet also genau den nächsten Knoten frei – kaufen muss
# man ihn weiterhin mit Punkten. Kosten je Stufe = round(base_cost * growth^level) in ⭐; die ersten
# Stufen liegen bewusst bei 1–5 ⭐, spätere Stufen werden teuer (growth).
# Reset-fest: Prestige-Fortschritt liegt in prestige_nodes (NICHT in upgrade_levels, das beim
# Prestige geleert wird). Daher leben grid/car/track-Boni hier, nicht im normalen Upgrade-Block.
# Neue Knoten lassen sich einfach durch Eintrag hier + Position in PRESTIGE_ORDER ergänzen.
const PRESTIGE_NODES = {
	# Globaler Einkommens-Multiplikator: Mult = 1 + Level (Lv1 ×2, Lv2 ×3, Lv3 ×4 …). Billig & viele
	# Stufen → der „Brot-und-Butter"-Knoten, in den die ersten Punkte fließen. Vorn = sofort spürbar.
	"income": {
		"name": "×-Einkommen", "icon": "", "base_cost": 1, "growth": 2.0, "max_level": 25,
		"desc": "Multipliziert allen verdienten Lauf-Ertrag (×2, ×3, ×4 …).",
	},
	# Auto-Startlevel (Head-Start, siehe HEADSTART_NODES): hebt das Start-Level des car_count-Upgrades
	# an → je Stufe ein dauerhaft zusätzliches Auto. Ersetzt das frühere separate „Extra-Auto" und
	# führt Tree- + Shop-Auto zusammen. Vorn = sofort spürbar.
	"car_start": {
		"name": "Auto-Startlevel", "icon": "", "base_cost": 1, "growth": 3.0, "max_level": 10,
		"desc": "Je Stufe startet das Auto-Upgrade nach dem Prestige eine Stufe höher (ein Auto mehr).",
	},
	# Strecken-Freischaltung: Lv1 = Strecke 2, Lv2 = Strecke 3 (Strecke 1 ist immer offen). Früh, damit
	# man schnell die teureren Strecken für mehr Geld/Punkte nutzen kann.
	"track": {
		"name": "Extra-Strecke", "icon": "", "base_cost": 1, "growth": 8.0, "max_level": 2,
		"desc": "Schaltet Strecke 2 und 3 frei (eine je Stufe).",
	},
	# Break Prestige: EINMALIGER Unlock (max_level 1, 1 ⭐). Ohne ihn gibt jedes Prestige nur 1 Punkt;
	# danach skalieren die Punkte mit dem GELD auf dem Konto (floor(√(Geld/K))) – unbegrenzt, die Bremse
	# ist rein ökonomisch (Punkt N braucht N²·K Geld). Liegt an Pos 4 (nach dem 4. Prestige verfügbar).
	"earning": {
		"name": "Break Prestige", "icon": "", "base_cost": 1, "growth": 1.0, "max_level": 1,
		"desc": "Einmalig: schaltet die Punkte-Skalierung frei. Danach bringt jedes Prestige Punkte nach dem verdienten Geld – statt nur 1.",
	},
	# Tile-Bonus-Startlevel (Head-Start auf tilebonus): das „Ertrag je Feld"-Upgrade startet höher.
	# Je Prestige-Stufe +5 Spiel-Stufen (HEADSTART_STEP), daher auf 20 begrenzt: 20·5 = 100 = volles
	# Tile-Bonus-Maximum. Zusammen mit der Preisverschiebung sind diese Stufen gratis und der Shop-Kauf
	# startet wieder beim Stufe-0-Preis. growth etwas steiler (1.6), weil jede Stufe nun 5× so viel bringt.
	"tilebonus_start": {
		"name": "Tile-Bonus-Start", "icon": "", "base_cost": 8, "growth": 1.6, "max_level": 20,
		"desc": "Je Stufe startet das „Ertrag je Feld\"-Upgrade nach dem Prestige fünf Stufen höher (max. Stufe 20 = Tile-Bonus voll).",
	},
	# Unlocks behalten: einmaliger Kauf (max_level 1). Danach bleiben ALLE bereits gekauften
	# Streckenteil-Freischaltungen über den Prestige-Reset hinweg erhalten – auch die Prestige-gegateten
	# Premium-Tiles (Rampe/Steilwand/Looping/Portal/Tribüne), sobald sie einmal gekauft wurden.
	# do_prestige leert unlocked_tiles dann nicht mehr. Siehe is_tile_unlocked().
	"keep_unlocks": {
		"name": "Unlocks behalten", "icon": "", "base_cost": 26, "growth": 1.0, "max_level": 1,
		"desc": "Einmal freigeschaltete Streckenteile bleiben nach dem Prestige freigeschaltet.",
	},
	# ×2 Prestige-Punkte: später Multiplikator-Knoten (ersetzt die alten +1-Punkt-Knoten). Je Stufe
	# verdoppeln sich die Punkte pro Prestige (final mit get_car_point_mult kombiniert).
	"points_mult": {
		"name": "×2 Prestige-Punkte", "icon": "", "base_cost": 20, "growth": 5.0, "max_level": 5,
		"desc": "Je Stufe verdoppeln sich die Prestige-Punkte pro Prestige (×2, ×4, ×8 …).",
	},
	# Tile-Gate Steilwand (wie Tribüne): schaltet die Steilwandkurve ÜBERHAUPT erst frei. Danach im
	# Shop noch für Geld freischaltbar (can_unlock_tile + is_tile_unlocked).
	"wall_unlock": {
		"name": "Steilwand", "icon": "", "base_cost": 3, "growth": 1.0, "max_level": 1,
		"desc": "Schaltet die Steilwandkurve frei (danach im Shop noch für Geld freischaltbar).",
	},
	# „× Auto" (NEU, hinter der Steilwand): EINMALIGE Freischaltung. Multipliziert die Prestige-Punkte
	# pro Prestige mit der Anzahl deiner Autos = (gekaufte Auto-Upgrades + 1, fürs Standard-Auto). Am
	# Anfang max ×4 (3 Auto-Käufe + 1); steigt mit den Werkstatt-Stufen (mehr kaufbare Auto-Upgrades).
	# Wirkt VOR den globalen Multiplikatoren (siehe prestige_pending_points).
	"car_points": {
		"name": "× Auto", "icon": "", "base_cost": 8, "growth": 1.0, "max_level": 1,
		"desc": "Multipliziert die Prestige-Punkte pro Prestige mit der Anzahl deiner Autos.",
	},
	# Unendliche Fahrzeit (NEU, einmalig, vor Tempo-Start): schaltet im Shop die Fahrzeit-Stufe 10 frei.
	# Erst wenn man diese Stufe kauft, fällt das Zeitlimit weg (is_endless_run / DRIVE_TIME_INF_LEVEL).
	"drive_time_inf": {
		"name": "Unendliche Fahrzeit", "icon": "", "base_cost": 10, "growth": 1.0, "max_level": 1,
		"desc": "Einmalig: schaltet im Shop die Fahrzeit-Stufe 10 frei. Kaufst du sie, fährt jede Strecke endlos.",
	},
	# Tempo-Startlevel (Head-Start auf speed): das Tempo-Upgrade startet höher.
	"speed_start": {
		"name": "Tempo-Start", "icon": "", "base_cost": 11, "growth": 1.5, "max_level": 15,
		"desc": "Je Stufe startet das Tempo-Upgrade nach dem Prestige fünf Stufen höher.",
	},
	# Tile-Gate Looping.
	"loop_unlock": {
		"name": "Looping", "icon": "", "base_cost": 15, "growth": 1.0, "max_level": 1,
		"desc": "Schaltet das Looping frei (danach im Shop noch für Geld freischaltbar).",
	},
	# Tile-Gate Rampe.
	"ramp_unlock": {
		"name": "Rampe", "icon": "", "base_cost": 33, "growth": 1.0, "max_level": 1,
		"desc": "Schaltet die Rampe frei (danach im Shop noch für Geld freischaltbar).",
	},
	# Streckengröße: identische Stufen wie GRID_STEPS (4×4 → 4×5 → 4×6 → 5×6). Nur 3 Stufen. Steht
	# jetzt VOR der Rampe (2026-06-21 getauscht).
	"grid": {
		"name": "Streckengröße", "icon": "", "base_cost": 42, "growth": 4.0, "max_level": 3,
		"desc": "Vergrößert das Baufeld aller Strecken.",
	},
	# End-Multiplikator-Startlevel (Head-Start auf endmult).
	"endmult_start": {
		"name": "End-Mult-Start", "icon": "", "base_cost": 52, "growth": 1.7, "max_level": 10,
		"desc": "Je Stufe startet das End-Multiplikator-Upgrade nach dem Prestige fünf Stufen höher.",
	},
	# Tile-Gate Portal.
	"portal_unlock": {
		"name": "Portal", "icon": "", "base_cost": 65, "growth": 1.0, "max_level": 1,
		"desc": "Schaltet das Portal frei (danach im Shop noch für Geld freischaltbar).",
	},
	# Tile-Gate Tribüne (bestehend, ans Ende verschoben).
	"stand_unlock": {
		"name": "Tribüne", "icon": "", "base_cost": 80, "growth": 1.0, "max_level": 1,
		"desc": "Schaltet die Tribüne frei (danach im Shop noch für Geld freischaltbar).",
	},
}
# Reihenfolge im Tech-Baum (links → rechts). Position p (1-basiert) ⇒ freigeschaltet nach dem
# p-ten Prestige (siehe is_prestige_node_unlocked).
const PRESTIGE_ORDER = ["income", "car_start", "track", "earning", "wall_unlock", "car_points", "tilebonus_start", "loop_unlock", "points_mult", "drive_time_inf", "speed_start", "keep_unlocks", "grid", "ramp_unlock", "endmult_start", "portal_unlock", "stand_unlock"]
const PRESTIGE_TRACK_BASE = 1   # Strecke 1 ist immer offen; je „track"-Stufe eine weitere.

# Auto-Startlevel: eigene ⭐-Kostenkurve (in get_prestige_node_cost special-cased). Stufe 1 kostet 1
# (wie die anderen Front-Knoten), danach steil – Stufe 3 (= 4. Auto, Fahr-Cap voll) 150k, Stufe 4 1,5M;
# ab da ×10. Levels über 3 braucht man erst mit der Werkstatt-Stufe (ACTIVE_CAR_CAP = 4 bei Tier 0).
const CAR_START_COSTS = [1, 2000, 150000, 1500000, 15000000, 150000000, 1500000000, 15000000000, 150000000000, 1500000000000]

# Extra-Strecke: eigene ⭐-Kostenkurve (in get_prestige_node_cost special-cased). Stufe 1 (= Strecke 2)
# kostet 1 ⭐ (wie die anderen Front-Knoten), Stufe 2 (= Strecke 3) bewusst teuer: 300k ⭐.
const TRACK_COSTS = [1, 300000]

# Feste ⭐-Kostenkurven für die mehrstufigen „Wert"-Knoten (in get_prestige_node_cost special-cased).
# Bewusst auf runde Zahlen gesetzt statt per base_cost·growth^level (die Felder im PRESTIGE_NODES-
# Eintrag werden für diese IDs IGNORIERT). Ziel-Design: auf halbem Weg zum Max kostet eine Stufe rund
# 100k ⭐ (Band 50k–150k), die frühen Stufen steigen sanft dahin, die obere Hälfte wird teuer. Voll
# maxen kostet zig Milliarden ⭐ – man erreicht die Werkstatt (1 Mio. ⭐) also lange vorher. Länge des
# Arrays == max_level des Knotens.
const PRESTIGE_COST_TABLE = {
	"income": [1, 3, 7, 18, 45, 120, 300, 800, 2000, 5500, 14000, 37000, 100000, 250000, 650000,
		1700000, 4500000, 11000000, 30000000, 75000000, 200000000, 500000000, 1300000000,
		3500000000, 9000000000],
	"tilebonus_start": [8, 20, 55, 140, 365, 950, 2500, 6500, 17000, 43000, 110000, 290000, 750000,
		2000000, 5000000, 13000000, 35000000, 90000000, 235000000, 600000000],
	"speed_start": [11, 40, 150, 550, 2000, 7500, 28000, 100000, 385000, 1400000, 5300000, 20000000,
		72000000, 270000000, 1000000000],
	"endmult_start": [52, 235, 1100, 4900, 22000, 100000, 460000, 2100000, 9500000, 43000000],
	"points_mult": [20, 1400, 100000, 7000000, 500000000],
	"grid": [42, 100000, 240000000],
}

# Head-Start-Knoten → Upgrade-IDs, deren Start-Level (Floor) sie anheben. Der Floor liegt reset-fest
# in prestige_nodes; get_upgrade_level() liest ihn mit → wirkt LIVE beim Kauf und überlebt den
# Prestige-Reset (upgrade_levels wird geleert, der Floor bleibt). Mehrere Knoten auf dieselbe
# Upgrade-ID summieren sich. buy_prestige_node emittiert upgrade_purchased für die gemappten IDs.
const HEADSTART_NODES = {
	"car_start":       ["car_count"],
	"tilebonus_start": ["tilebonus"],
	"speed_start":     ["speed"],
	"endmult_start":   ["endmult"],
}
# Wie viele SPIEL-Stufen jede Prestige-Stufe dieses Head-Start-Knotens schenkt. Die „Wert"-Knoten
# (Tile-Bonus/Tempo/End-Mult) geben je Prestige-Stufe 5 Spiel-Stufen (lohnen sich dadurch deutlich
# mehr); car_start bleibt bei 1 (mehr würde das gleichzeitige Fahr-Cap von 4 Autos sprengen). Knoten,
# die hier nicht stehen, geben standardmäßig 1. Zusammen mit der Preisverschiebung (_upgrade_cost_at)
# sind die geschenkten Stufen GRATIS und der nächste BEZAHLTE Kauf startet wieder beim Stufe-0-Preis.
const HEADSTART_STEP = {
	"tilebonus_start": 5,
	"speed_start":     5,
	"endmult_start":   5,
}
# Tile-Gate-Knoten → Tile-Key. Diese Tiles müssen erst im Prestige-Baum freigeschaltet werden, bevor
# sie im Shop für Geld kaufbar sind (wie die Tribüne). Siehe can_unlock_tile/is_tile_unlocked.
const TILE_GATE_NODES = {
	"wall_unlock":   "wall",
	"loop_unlock":   "loop",
	"ramp_unlock":   "ramp",
	"portal_unlock": "portal",
	"stand_unlock":  "stand",
}

# ── Erfolge (Achievements) ────────────────────────────────────────────────────────
# Pro Profil gespeichert (unlocked_achievements, slot-gebunden). Definition als reine Daten;
# Icons sind UI-Sache und liegen in GlobalModal. Zwei Arten von Erfolgen:
#   • Ereignis-Erfolge (ohne "metric") werden explizit per unlock_achievement(id) freigeschaltet
#     (z. B. erstes Rennen, erstes Streckenteil platzieren, Auto-Aufstieg).
#   • Schwellen-Erfolge (mit "metric" + "target") schaltet _check_metric_achievements() automatisch
#     frei, sobald der jeweilige Wert die Schwelle erreicht. metric ∈
#     {currency, prestige_points, prestige_count, lap_earn}.
# Freischalten ist idempotent + sofort persistiert; achievement_unlocked meldet es der UI live.
# WICHTIG: Freischalten (= Bedingung erfüllt) schreibt die Trophäen NICHT automatisch gut. Der Spieler
# muss jeden erreichten Erfolg im Erfolge-Tab manuell EINSAMMELN (claim_achievement) → dann erst gibt's
# die Trophäen. „Erreicht" (unlocked_achievements) und „eingesammelt" (claimed_achievements) sind getrennt.
const ACHIEVEMENTS = {
	"first_race":     {"name": "Erster Start",   "desc": "Starte dein allererstes Rennen."},
	"tile_road":      {"name": "Streckenbauer",  "desc": "Platziere zum ersten Mal eine Straße (Gerade oder Kurve)."},
	"tile_ice":       {"name": "Eiszeit",        "desc": "Platziere zum ersten Mal eine Eisgerade."},
	"tile_ramp":      {"name": "Abheben",        "desc": "Platziere zum ersten Mal eine Rampe."},
	"tile_wall":      {"name": "Steile Sache",   "desc": "Platziere zum ersten Mal eine Steilwandkurve."},
	"tile_loop":      {"name": "Looping",        "desc": "Platziere zum ersten Mal ein Looping."},
	"tile_portal":    {"name": "Portalspringer", "desc": "Platziere zum ersten Mal ein Portal."},
	"tile_stand":     {"name": "Volle Tribüne",  "desc": "Platziere zum ersten Mal eine Tribüne."},
	"stand_max":      {"name": "Ausverkauft",    "desc": "Staple eine Tribüne auf die maximale Stufe (5×)."},
	"lap_1k":         {"name": "Erste Einnahmen", "desc": "Verdiene 1.000 mit EINEM Auto in einer Runde (Start bis Start).",          "metric": "lap_earn",        "target": 1000.0},
	"lap_100k":       {"name": "Gute Runde",      "desc": "Verdiene 100.000 mit EINEM Auto in einer Runde.",                          "metric": "lap_earn",        "target": 100000.0},
	"lap_1m":         {"name": "Spitzenrunde",    "desc": "Verdiene 1.000.000 mit EINEM Auto in einer Runde.",                        "metric": "lap_earn",        "target": 1000000.0},
	"lap_1b":         {"name": "Traumrunde",      "desc": "Verdiene 1.000.000.000 mit EINEM Auto in einer Runde.",                    "metric": "lap_earn",        "target": 1000000000.0},
	"money_100k":     {"name": "Erstes Vermögen", "desc": "Besitze 100.000 Währung.",            "metric": "currency",        "target": 100000.0},
	"money_1m":       {"name": "Millionär",       "desc": "Besitze 1.000.000 Währung.",          "metric": "currency",        "target": 1000000.0},
	"money_1b":       {"name": "Milliardär",      "desc": "Besitze 1.000.000.000 Währung.",      "metric": "currency",        "target": 1000000000.0},
	"money_1t":       {"name": "Billionär",       "desc": "Besitze 1.000.000.000.000 Währung.",  "metric": "currency",        "target": 1000000000000.0},
	"car_ascend":     {"name": "Werkstatt-Profi", "desc": "Werte dein Auto zum ersten Mal in der Werkstatt auf."},
	"first_prestige": {"name": "Neuanfang",       "desc": "Führe dein erstes Prestige durch.",   "metric": "prestige_count",  "target": 1},
	"prestige_5":     {"name": "Wiedergeboren",   "desc": "Führe 5 Prestiges durch.",            "metric": "prestige_count",  "target": 5},
	"prestige_10":    {"name": "Aufgestiegen",    "desc": "Führe 10 Prestiges durch.",           "metric": "prestige_count",  "target": 10},
	"pp_10":          {"name": "Sternensammler",  "desc": "Besitze 10 Prestige-Punkte.",         "metric": "prestige_points", "target": 10},
	"pp_100":         {"name": "Sternenhaufen",   "desc": "Besitze 100 Prestige-Punkte.",        "metric": "prestige_points", "target": 100},
	"pp_1000":        {"name": "Galaxie",         "desc": "Besitze 1.000 Prestige-Punkte.",      "metric": "prestige_points", "target": 1000},
	"pp_1m":          {"name": "Universum",       "desc": "Besitze 1.000.000 Prestige-Punkte (schaltet die Werkstatt frei).", "metric": "prestige_points", "target": 1000000},
	"track_2":        {"name": "Neue Strecke",    "desc": "Schalte Strecke 2 frei.",   "metric": "unlocked_tracks", "target": 2},
	"track_3":        {"name": "Streckensammler", "desc": "Schalte Strecke 3 frei.",   "metric": "unlocked_tracks", "target": 3},
	# ── NEU (zur Prüfung, Namen mit * markiert) ──────────────────────────────
	# Garage-Kosmetik (Event-Erfolge, freigeschaltet beim Kauf in GlobalModal):
	"first_cosmetic": {"name": "*Stilbewusst",   "desc": "Kaufe deine erste Lackierung oder dein erstes Muster."},
	"all_patterns":   {"name": "*Mustersammler", "desc": "Besitze alle Muster in der Garage."},
	"all_paints":     {"name": "*Lacksammler",   "desc": "Besitze alle Farben in der Garage."},
	# Schwellen-Erfolge (laufen automatisch über die bestehenden Metriken):
	"lap_1t":         {"name": "*Billionenrunde", "desc": "Verdiene 1.000.000.000.000 mit EINEM Auto in einer Runde.", "metric": "lap_earn",       "target": 1000000000000.0},
	"money_1q":       {"name": "*Billiardär",     "desc": "Besitze 1.000.000.000.000.000 Währung.",                    "metric": "currency",       "target": 1000000000000000.0},
	"prestige_25":    {"name": "*Unsterblich",    "desc": "Führe 25 Prestiges durch.",                                 "metric": "prestige_count", "target": 25},
	# ── Geheime Erfolge ("secret": true) ─────────────────────────────────────
	# Werden im Erfolge-Tab unter einer Trennlinie als „???" mit Fragezeichen-Icon gezeigt,
	# bis sie ausgelöst werden. Event-Erfolge (kein "metric") → per unlock_achievement(id).
	"loop_jump":      {"name": "Loopingspringer", "desc": "Spring einmal durch einen Looping.", "secret": true},
	"loop_jump_portal": {"name": "Loopingspringer?", "desc": "Setze statt der Rampe zwei Portale auf beide Seiten eines Loopings (in einer Linie) und teleportiere dich durch den Looping.", "secret": true},
	"loop_triple":    {"name": "Schwindelfrei",   "desc": "Fahre eine Strecke mit mindestens 3 Loopings.", "secret": true},
	"loop_mania":     {"name": "Looping-Wahnsinn","desc": "Fahre eine Strecke mit mindestens 10 Loopings.", "secret": true},
	"only_special":   {"name": "Im Kreis gedacht","desc": "Fahre eine Strecke ganz ohne normale Geraden/Kurven – nur Spezial-Teile.", "secret": true},
	"stand_empire":   {"name": "Tribünen-Imperium","desc": "Habe gleichzeitig 5 voll gestapelte Tribünen (×5) auf einer Strecke.", "secret": true},
	"thrifty":        {"name": "Sparfuchs",       "desc": "Erreiche dein erstes Prestige, ohne je eine Kosmetik gekauft zu haben.", "secret": true},
	"loner":          {"name": "Eigenbrötler",    "desc": "Schalte Strecke 3 frei, ohne je dein Auto in der Werkstatt aufzuwerten.", "secret": true},
	"marathon":       {"name": "Dauerläufer",     "desc": "Lass ein einzelnes Rennen 3 Stunden ununterbrochen laufen.", "secret": true},
	"master_builder": {"name": "Großbaumeister",  "desc": "Platziere insgesamt 1.000 Streckenteile.", "secret": true},
	"completionist":  {"name": "Komplettist",     "desc": "Sammle alle regulären Erfolge ein.", "secret": true},
}
# Anzeige-Reihenfolge im Erfolge-Tab (links → rechts, oben → unten). Grob nach der WAHRSCHEINLICHEN
# Freischalt-Progression sortiert (früh → spät), bewusst über Geld-/Runden-/Tile-/Prestige-/Strecken-
# Erfolge gemischt statt strikt nach Kategorie – orientiert an den Freischalt-/Kostengrenzen.
const ACHIEVEMENT_ORDER = [
	"first_race",      # sofort
	"tile_road",       # Gerade/Kurve (ab 15k/30k)
	"lap_1k",          # 1k je Runde
	"money_100k",      # 100k Geld
	"first_prestige",  # erstes Prestige (ab 100k verdient)
	"tile_ice",        # Eisgerade (500k)
	"lap_100k",        # 100k je Runde
	"money_1m",        # 1M Geld
	"pp_10",           # 10 ⭐
	"prestige_5",      # 5 Prestiges
	"tile_ramp",       # Rampe (25M)
	"lap_1m",          # 1M je Runde
	"tile_wall",       # Steilwand (500M)
	"money_1b",        # 1B Geld
	"prestige_10",     # 10 Prestiges
	"pp_100",          # 100 ⭐
	"track_2",         # Strecke 2 (Prestige-Knoten)
	"tile_loop",       # Looping (15B)
	"car_ascend",      # Auto-Aufstieg (100B)
	"tile_portal",     # Portal (100B)
	"money_1t",        # 1T Geld
	"tile_stand",      # Tribüne (1T)
	"stand_max",       # Tribüne 5× gestapelt
	"lap_1b",          # 1B je Runde (sehr spät)
	"track_3",         # Strecke 3
	"pp_1000",         # 1.000 ⭐ (sehr spät)
	# ── NEU (zur Prüfung) ──
	"first_cosmetic",  # erste Kosmetik gekauft (Garage ab 100B freigeschaltet)
	"lap_1t",          # 1T je Runde
	"all_patterns",    # alle Muster
	"money_1q",        # 1.000T (1e15) Geld
	"prestige_25",     # 25 Prestiges
	"all_paints",      # alle Lackfarben (am teuersten → ganz spät)
]

# Anzeige-Reihenfolge der GEHEIMEN Erfolge (eigener Block unter einer Trennlinie im Erfolge-Tab).
# Werden verdeckt (??? + Fragezeichen) gezeigt, bis sie freigeschaltet sind.
const SECRET_ACHIEVEMENT_ORDER = [
	"loop_jump",
	"loop_jump_portal",
	"loop_triple",
	"loop_mania",
	"only_special",
	"stand_empire",
	"thrifty",
	"loner",
	"marathon",
	"master_builder",
	"completionist",
]

# „Dauerläufer": ein einzelnes Rennen muss so viele Sekunden ununterbrochen laufen (3 Stunden).
const MARATHON_SECONDS := 3.0 * 60.0 * 60.0

# Trophäen: eigene Erfolgs-Währung. Jeder EINGESAMMELTE Erfolg bringt ACH_REWARD Trophäen.
# Nur in der Garage angezeigt (slot-gebunden, kein Spieleffekt – reine Sammel-Währung).
const ACH_REWARD = 100
# Kosten je freischaltbarer Kosmetik (Lackfarbe / Muster), bezahlt mit Trophäen (ach_currency).
const COSMETIC_COST = 250

var _currency:     float      = START_CURRENCY   # float, damit Geld weit über int64 (9,2e18) hinaus bis ~1e308 wächst, ohne zu „flippen"
var upgrade_levels: Dictionary = {}
var track:          Array      = []   # gespeicherte Strecke des aktiven Tracks (Rückwärtskompatibilität)
var unlocked_tiles: Dictionary = {}   # freigeschaltete Shop-Tiles: key → true
var unlocked_achievements: Dictionary = {}   # erreichte Erfolge (Bedingung erfüllt): id → true (slot-gebunden)
var claimed_achievements:  Dictionary = {}   # bereits EINGESAMMELTE Erfolge: id → true (slot-gebunden)
var ach_currency: int = 0   # Trophäen aus eingesammelten Erfolgen (slot-gebunden, nur in der Garage sichtbar)

# Kosmetik: Auto-Lackierung (Werkstatt). car_paint_on=false → Originaltextur (keine Umfärbung).
var car_paint_on:    bool  = false
var car_paint_color: Color = Color(0.85, 0.15, 0.12)
# Kosmetik: Muster über die Lack-Maske (0 = keins, 1 = Streifen …). pattern_color = Schwarz.
var car_pattern:       int   = 0
var car_pattern_color: Color = Color(0.06, 0.06, 0.08)
# Mit Trophäen freigeschaltete Kosmetik (slot-/profil-gebunden, siehe [[profile_isolation]]).
# unlocked_paints: html-Hex (rrggbb) → true; unlocked_patterns: Muster-Index (int) → true.
# „Original"-Lack und Muster „Keins" (Index 0) sind immer gratis und stehen NICHT in den Dicts.
var unlocked_paints:   Dictionary = {}
var unlocked_patterns: Dictionary = {}

# Auto-Prestige-Stufe (überlebt normales Prestige; nur „Neues Spiel"/reset_slot löscht sie).
# 0 = Standard-Auto, 1 = eric, … (siehe CAR_TIER_MODELS). Ab Stufe ≥1 fährt NUR das Tier-Auto.
var car_tier: int = 0

# Reiner Test-Schalter (Garage „Muster" → Knopf „Test-Auto"): zwingt das Blender-Testmodell.
# Nicht gespeichert, lebt nur in der Session – bewusst kein Feature, nur zum Ausprobieren.
var test_blender_car: bool = false

# Anzahl gekaufter Super-Autos („Auto 2"). LEGACY: nicht mehr per Shop kaufbar (durch car_tier ersetzt),
# Feld bleibt nur für die Save-Migration erhalten.
var super_car_count: int   = 0

# Zähler für geheime Erfolge (profil-gebunden, überlebt Prestige – nur reset_slot löscht ihn).
var total_tiles_placed: int = 0      # insgesamt platzierte Streckenteile (für „Großbaumeister")

# ── Motorhaube (Backpack-Tuning, Werkstatt-Untertab) ────────────────────────────
# Großes Tuning-Raster (wie Backpack Battles): Items per Drag ablegen. Die Items haben
# AKTUELL KEINEN Spieleffekt – reines UI-/Sammel-Gerüst mit Platzhalter-Assets.
# Freischaltung + Raster-Upgrades kosten Geld. Profil-gebunden, überlebt Prestige; nur
# reset_slot löscht. Siehe [[project_werkstatt_carconfig]].
var motorhaube_unlocked:   bool  = false
var motorhaube_grid_level: int   = 0      # Index in MOTORHAUBE_GRID_SIZES
var motorhaube_items:      Array = []     # platzierte Items: [{id:String, x:int, y:int}]

# Raster-Stufen (Spalten × Reihen). Upgrade-Pfad: 1×2 → 2×2 → 2×3 → 3×3 → 3×4 → 4×4.
const MOTORHAUBE_GRID_SIZES := [
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 3),
	Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 4),
]
const MOTORHAUBE_UNLOCK_COST := 5000.0
# Kosten Stufe i → i+1 (Platzhalter-Balancing, später leicht anpassbar).
const MOTORHAUBE_UPGRADE_COSTS := [10000.0, 25000.0, 50000.0, 100000.0, 250000.0]

# Verfügbare Item-Vorlagen (Palette zum Ziehen). size = Felder (Spalten × Reihen) à 32px.
# color = Platzhalter bis die Pixel-Assets existieren. Noch KEIN Effekt (bewusst leer).
# Insgesamt 20 Bauteile in gemischten Größen (1×1, 1×2, 2×1, 2×2, 1×3, 3×1).
const MOTORHAUBE_ITEM_DEFS := [
	{"id": "bolt",        "name": "Schraube",      "size": Vector2i(1, 1), "color": Color(0.62, 0.66, 0.72)},
	{"id": "plug",        "name": "Zündkerze",     "size": Vector2i(1, 1), "color": Color(0.93, 0.74, 0.30)},
	{"id": "nut",         "name": "Mutter",        "size": Vector2i(1, 1), "color": Color(0.70, 0.72, 0.76)},
	{"id": "fuse",        "name": "Sicherung",     "size": Vector2i(1, 1), "color": Color(0.95, 0.55, 0.25)},
	{"id": "sensor",      "name": "Sensor",        "size": Vector2i(1, 1), "color": Color(0.40, 0.80, 0.78)},
	{"id": "piston",      "name": "Kolben",        "size": Vector2i(1, 1), "color": Color(0.78, 0.50, 0.36)},
	{"id": "valve",       "name": "Ventil",        "size": Vector2i(1, 1), "color": Color(0.55, 0.78, 0.40)},
	{"id": "belt",        "name": "Keilriemen",    "size": Vector2i(1, 2), "color": Color(0.36, 0.55, 0.92)},
	{"id": "spring",      "name": "Feder",         "size": Vector2i(1, 2), "color": Color(0.80, 0.80, 0.45)},
	{"id": "cable",       "name": "Kabel",         "size": Vector2i(1, 2), "color": Color(0.85, 0.40, 0.55)},
	{"id": "pump",        "name": "Pumpe",         "size": Vector2i(1, 2), "color": Color(0.50, 0.60, 0.85)},
	{"id": "hose",        "name": "Schlauch",      "size": Vector2i(2, 1), "color": Color(0.42, 0.78, 0.55)},
	{"id": "gasket",      "name": "Dichtung",      "size": Vector2i(2, 1), "color": Color(0.88, 0.62, 0.50)},
	{"id": "manifold",    "name": "Krümmer",       "size": Vector2i(2, 1), "color": Color(0.60, 0.55, 0.70)},
	{"id": "battery",     "name": "Batterie",      "size": Vector2i(2, 2), "color": Color(0.85, 0.42, 0.40)},
	{"id": "filter",      "name": "Luftfilter",    "size": Vector2i(2, 2), "color": Color(0.66, 0.50, 0.88)},
	{"id": "radiator",    "name": "Kühler",        "size": Vector2i(2, 2), "color": Color(0.40, 0.70, 0.90)},
	{"id": "turbo",       "name": "Turbolader",    "size": Vector2i(2, 2), "color": Color(0.90, 0.45, 0.30)},
	{"id": "intercooler", "name": "Ladeluftkühler","size": Vector2i(1, 3), "color": Color(0.45, 0.75, 0.70)},
	{"id": "exhaust",     "name": "Auspuff",       "size": Vector2i(3, 1), "color": Color(0.58, 0.60, 0.64)},
]

# Prestige-Zustand (überlebt den Prestige-Reset; nur „Neues Spiel"/reset_slot löscht ihn).
var prestige_points: float      = 0.0   # verfügbare ⭐ (float wie _currency → kein int64-Flip bei sehr hohen Punkten)
var prestige_earned: float      = 0.0   # seit dem letzten Prestige verdientes Geld (float wie _currency, kein Überlauf)
var prestige_nodes:  Dictionary = {}  # Tech-Baum-Knoten: id → Stufe
var prestige_count:  int        = 0   # Anzahl ausgeführter Prestiges → gated Baum-Freischaltung
# TEMP: dauerhafte Tab-Freischaltung (Prestige/Werkstatt), sobald die Verdienst-Schwelle einmal
# erreicht wurde. ENTFERNEN, sobald es einen Erfolge-Tab gibt – dann dort setzen (_check_tab_unlocks).
var prestige_tab_unlocked:  bool = false
var werkstatt_tab_unlocked: bool = false
var total_playtime:  float      = 0.0 # gesamte gespielte Zeit in Sekunden (slot-gebunden)
var _current_slot:  int        = 0
var _slot_name:     String     = ""

# ── Multi-Track-State ───────────────────────────────────────────────────────────
var _active_track: int = 0
var _tracks: Array = []   # TRACK_COUNT Einträge
var endless_mode: bool = false   # Kein Timer, Geld wird live gutgeschrieben
# Globale Einstellung (slot-unabhängig, in user://settings.cfg): blendet die Cheat-Buttons
# (Endlos-Modus ∞ und +1B ⭐) in der oberen Leiste ein/aus.
var cheat_mode: bool = false
# Shop-Kaufmenge (durchschaltbarer Knopf im Shop): Index in BUY_QTY_OPTIONS. Feste Mengen 1/5/10/25
# kaufen genau so viele Stufen je Klick (Preis = Summe dieser Stufen); -1 = „Max" (so viele Stufen wie
# mit dem aktuellen Geld leistbar). Reine UI-/Session-Einstellung – nicht gespeichert, gilt für
# Upgrades UND Streckenteil-Upgrades.
const BUY_QTY_OPTIONS = [1, 5, 10, 25, -1]
var buy_qty_mode: int = 0   # Index in BUY_QTY_OPTIONS (Standard: Einzelkauf)

signal run_ended(track_idx: int, earned: float)
# Eine (oder mehrere) Runde(n) wurden gutgeschrieben (Auto über die Startlinie) – Betrag = Summe.
signal lap_credited(track_idx: int, amount: float)
# Ein Shop-Tile wurde freigeschaltet (im Streckenteile-Shop) – Bau-Leiste aktualisiert sich daraufhin.
signal tile_unlocked(key: String)
# Ein anderer Speicherstand wurde geladen/zurückgesetzt – Slot-abhängige UI (z. B. der
# Streckenteile-Shop im GlobalModal-Autoload) muss sich daraufhin neu aufbauen.
signal slot_changed(slot: int)
# Ein Upgrade wurde gekauft – die angeschaute 3D-Strecke setzt ihre Autos daraufhin neu auf
# (Tempo/Anzahl/Reward live). Hintergrund-Strecken übernehmen es beim nächsten Ansehen.
signal upgrade_purchased(id: String)
# Prestige-Punkte oder Tech-Baum-Knoten haben sich geändert (Kauf oder ausgeführtes Prestige).
signal prestige_changed
# TEMP: ein Tab (Prestige/Werkstatt) wurde dauerhaft freigeschaltet → Nav/Modal entsperren live.
# ENTFERNEN bzw. durch ein Erfolgs-Signal ersetzen, sobald es einen Erfolge-Tab gibt.
signal tab_unlock_changed
# Auto-Lackierung wurde in der Werkstatt geändert → 3D-Autos färben sich live um.
signal car_paint_changed
# Cheat-Modus (globale Einstellung) wurde umgeschaltet → HUD blendet die Cheat-Buttons ein/aus.
signal cheat_mode_changed
# Ein Erfolg wurde freigeschaltet (Bedingung erfüllt, id aus ACHIEVEMENTS) → Erfolge-Tab + HUD live.
signal achievement_unlocked(id: String)
# Ein erreichter Erfolg wurde manuell EINGESAMMELT → Trophäen-Stand/Anzeige live aktualisieren.
signal achievement_claimed(id: String)


# ── Freischaltbare Shop-Tiles ───────────────────────────────────────────────────
# Zentrale Freischaltkosten (gemeinsame Quelle für Bau-Shop in Main.gd und den
# Streckenteile-Tab in GlobalModal.gd). Main.SHOP_ITEMS spiegelt diese Werte.
const TILE_UNLOCK_COST = {
	# Sand: günstigste bezahlte Strecke – niedrige Freischaltkosten.
	"sand_straight":  5000,
	"sand_curve":     7000,
	# Default (gebufft, +150): mittlere Stufe, etwas günstiger als die (neue) Rennstrecke.
	"def_straight":  50000,
	"def_curve":     60000,
	# Rennstrecke (+1000 · ×1.2): teuerstes reguläres Streckenteil.
	"race_straight": 200000,
	"race_curve":    220000,
	# Eis: EIN gemeinsamer Schlüssel schaltet Gerade + Kurve frei (Preis von der Geraden).
	"ice":          25000,
	# Reihenfolge Steilwand → Looping → Rampe (2026-06-19), aufsteigende Freischaltkosten. Der Looping
	# ist der simple Multiplikator (mittlere Stufe), die Rampe trägt den Schneeball-Effekt und ist die
	# teure Spät-Freischaltung. Muss mit Main.SHOP_ITEMS (gleiche unlock-Werte) übereinstimmen.
	"wall":         500000000,
	"loop":         2000000000,
	"ramp":         15000000000,
	"portal":       100000000000,
	"stand":        1000000000000,
	# Kleber-/Slime-Belag: EIN gemeinsamer Schlüssel schaltet Gerade + Kurve frei (wie Eis). Sehr späte,
	# starke Strecke (bremst, zahlt aber viel) → Freischaltkosten 1e12.
	"glue":         1000000000000,
	# Test-Belag (Wasser): nur zum Ausprobieren der neuen 3D-Assets, vorerst ohne Ökonomie-Effekt.
	"water_straight": 1,
	"water_curve":    1,
}

# ── Eisgerade ───────────────────────────────────────────────────────────────────
# Gibt kein Geld, sondern legt auf die nächsten Felder einen ABSOLUTEN Tempo-Bonus (so viel
# schneller wie N Tempo-Stufen, unabhängig vom aktuellen Tempo). Basis +1 Tempo-Stufe, je
# Upgrade-Stufe +0.5; Reichweite 3 Folge-Felder, +1 je 5 Upgrade-Stufen (5→4, 10→5, 15→6).
const ICE_BASE_BOOST_LEVELS = 1.0
const ICE_PER_LEVEL_BOOST   = 0.5
const ICE_BASE_RANGE        = 3

# ── Steilwandkurve (Wall-Ride) ──────────────────────────────────────────────────
# Zwei vertikal gestapelte Kacheln = eine 180°-Haarnadel an einer Steilwand. Der absolute Tempo-Bonus
# (wie die Eisgerade) greift sofort beim Auffahren und wirkt über die Kurve HINAUS: Basis +2 Tempo-
# Stufen, je Upgrade-Stufe +0.5. Reichweite zählt ab dem Einfahrt-Feld (j=0); die Kurve selbst belegt
# j=0 (wall_start) + j=1 (wall_end), Reichweite 4 ⇒ 3 Felder AUSSERHALB der Kurve, +1 je 5 Upgrade-Stufen.
# Das Geld (Grundertrag am Einfahrt-Feld) läuft über das wallbonus-Upgrade (base/per_level).
const WALL_BASE_BOOST_LEVELS = 2.0
const WALL_PER_LEVEL_BOOST   = 0.5
const WALL_BASE_RANGE        = 4

# ── Kleber-/Slime-Belag ─────────────────────────────────────────────────────────
# Gegenstück zur Eisgerade: bremst das Auto PROZENTUAL (multiplikativer Tempo-Faktor NUR auf dem
# Kleber-Feld selbst, GLUE_BASE_RANGE=0), zahlt dafür viel Geld je Feld. Geld: Basis 50k,
# je Upgrade-Stufe prozentual mehr (×GLUE_EARN_GROWTH). Verlangsamung: Stufe 0 = −90 % (Auto fährt nur
# 10 %), je GLUE_SLOW_PCT_STEP Upgrade-Stufen −5 %-Punkte Abzug, bis auf Max-Stufe nur noch −20 %
# (Auto fährt 80 %). Ein Upgrade (gluebonus) regelt BEIDES für Gerade+Kurve.
const GLUE_BASE_EARN    = 50000.0
const GLUE_EARN_GROWTH  = 1.09     # +~9 % Ertrag je Upgrade-Stufe (50k → ~54,5k → … prozentual)
const GLUE_SLOW_PCT_BASE = 90      # %-Tempo-Abzug bei Upgrade-Stufe 0 (Auto fährt 10 %)
const GLUE_SLOW_PCT_PER  = 5       # je GLUE_SLOW_PCT_STEP Stufen −5 %-Punkte Abzug
const GLUE_SLOW_PCT_STEP = 3       # Upgrade-Stufen je −5 %-Punkte
const GLUE_SLOW_PCT_MIN  = 20      # minimaler Abzug auf Max-Stufe (Auto fährt 80 %)
const GLUE_BASE_RANGE   = 0        # nur das Kleber-Feld selbst (j=0) wird gebremst, keine Folge-Felder


func get_tile_unlock_cost(key: String) -> int:
	return int(TILE_UNLOCK_COST.get(key, 0))


func is_tile_unlocked(key: String) -> bool:
	# Ein Tile ist freigeschaltet, sobald es EINMAL gekauft wurde (steht dann in unlocked_tiles).
	# Über das Prestige hinweg bleiben diese Käufe erhalten, wenn der Knoten „Unlocks behalten"
	# (keep_unlocks) gekauft ist – do_prestige leert unlocked_tiles dann nicht (siehe dort). Ohne den
	# Knoten wird wie bisher alles zurückgesetzt und muss erneut für Geld freigeschaltet werden.
	return key == "" or bool(unlocked_tiles.get(key, false))


# Premium-Tiles (Rampe/Steilwand/Looping/Portal/Tribüne) dürfen im Shop NUR für Geld freigeschaltet
# werden, wenn ihr Prestige-Gate-Knoten gekauft ist. Main/GlobalModal fragen das vor dem Freischalten ab.
func can_unlock_tile(key: String) -> bool:
	for nid in TILE_GATE_NODES:
		if TILE_GATE_NODES[nid] == key:
			return get_prestige_node_level(nid) >= 1
	return true


# Der frühere „Gratis-Straßen"-Knoten wurde entfernt → es gibt kein Gratis-Kontingent mehr.
# Bleibt als no-op (0) erhalten, damit Main._tile_price/_tile_refund_for unverändert funktionieren.
func get_free_tile_quota(_type: String) -> int:
	return 0


func unlock_tile(key: String) -> void:
	if key == "":
		return
	unlocked_tiles[key] = true
	save_game()
	tile_unlocked.emit(key)


func _ready() -> void:
	_migrate_legacy_user_dir()
	_load_settings()
	_init_tracks()


# ── Einmalige Migration vom alten user://-Ordner ────────────────────────────────
# Früher hieß der Speicherordner "RaceTrackBuilder"; mit der Umbenennung auf
# "RoadTycoon" (config/custom_user_dir_name) zeigt user:// auf einen neuen, leeren
# Ordner. Diese Routine kopiert vorhandene Spielstände + Einstellungen EINMALIG
# herüber und löscht den alten Ordner anschließend. Sie greift nur, solange im
# neuen Ordner noch keine Saves liegen – läuft also faktisch genau einmal.
const LEGACY_USER_DIR_NAME = "RaceTrackBuilder"

func _migrate_legacy_user_dir() -> void:
	# Liegen im neuen Ordner schon Saves? Dann ist die Migration erledigt (läuft so genau einmal).
	if _new_user_dir_has_data():
		return
	var new_abs := ProjectSettings.globalize_path("user://").trim_suffix("/").trim_suffix("\\")
	var base := new_abs.get_base_dir()   # Windows: %APPDATA% (Roaming)
	# Mögliche Alt-Speicherorte in Prioritätsreihenfolge. Hintergrund: Bis dieser Build lief
	# use_custom_user_dir faktisch NICHT (der Eintrag war kaputt), darum lag user:// unter dem
	# Godot-Standardpfad …/Godot/app_userdata/<Projektname>. Jetzt (custom dir aktiv) zeigt user://
	# direkt auf %APPDATA%/RoadTycoon → einmalig die alten Spielstände herüberkopieren.
	var candidates := [
		base.path_join("Godot/app_userdata/RoadTycoon"),               # Beta-Saves (Name RoadTycoon, custom dir war aus)
		base.path_join("Godot/app_userdata/" + LEGACY_USER_DIR_NAME),  # noch älter (alter Projektname)
		base.path_join(LEGACY_USER_DIR_NAME),                          # falls custom dir je mit altem Namen lief
	]
	for legacy_abs in candidates:
		if legacy_abs == new_abs or not DirAccess.dir_exists_absolute(legacy_abs):
			continue
		if not _dir_has_save_data(legacy_abs):
			continue
		DirAccess.make_dir_recursive_absolute(new_abs)
		_copy_dir_recursive(legacy_abs, new_abs)
		# Alt-Ordner bewusst NICHT löschen: bleibt als Backup und stört einen evtl. älteren
		# Parallel-Build nicht. Der _new_user_dir_has_data()-Check oben verhindert Doppel-Migration.
		return

func _new_user_dir_has_data() -> bool:
	return _dir_has_save_data(ProjectSettings.globalize_path("user://"))

func _dir_has_save_data(abs_path: String) -> bool:
	var d := DirAccess.open(abs_path)
	if d == null:
		return false
	for fname in d.get_files():
		if fname.begins_with("savegame_slot") or fname == "settings.cfg":
			return true
	return false

func _copy_dir_recursive(from_abs: String, to_abs: String) -> void:
	var d := DirAccess.open(from_abs)
	if d == null:
		return
	DirAccess.make_dir_recursive_absolute(to_abs)
	for fname in d.get_files():
		var dst := to_abs.path_join(fname)
		if not FileAccess.file_exists(dst):
			DirAccess.copy_absolute(from_abs.path_join(fname), dst)
	for sub in d.get_directories():
		_copy_dir_recursive(from_abs.path_join(sub), to_abs.path_join(sub))


# ── Globale Einstellungen (slot-unabhängig, user://settings.cfg) ────────────────

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Paths.SETTINGS_FILE)   # fehlende Datei → Defaults
	cheat_mode = bool(cfg.get_value("cheats", "enabled", false))


# Cheat-Modus live anwenden und Hörer benachrichtigen (HUD blendet die Cheat-Buttons um).
# Die Persistenz in user://settings.cfg erfolgt über den Einstellungen-Speicherfluss im
# Pause-Menü (PauseMenu) – hier wird bewusst NICHT auf die Platte geschrieben.
# Beim Ausschalten wird ein evtl. laufender Endlos-Modus beendet, da sein Button verschwindet.
func apply_cheat_mode(val: bool) -> void:
	if cheat_mode == val:
		return
	cheat_mode = val
	if not cheat_mode:
		endless_mode = false
	cheat_mode_changed.emit()


func _init_tracks() -> void:
	_tracks.clear()
	for _i in TRACK_COUNT:
		_tracks.append({
			"grid":            [],
			"run_active":      false,
			"run_timer":       0.0,
			"run_duration":    0.0,   # Gesamt-Fahrzeit dieses Runs (für Restzeit→Position)
			"run_elapsed":     0.0,   # monoton steigende Fahrzeit (Basis für Runden & Position)
			"run_cars":        [],    # je Auto {lap_time, reward, start_delay} – aus 3D gesetzt
			"run_earned":      0.0,   # bisher in diesem Run gutgeschriebener Gesamtbetrag (float, kein Überlauf)
			"run_credited":    0.0,   # davon bereits der Währung gutgeschrieben
			"run_credited_laps": 0,   # Anzahl bereits gutgeschriebener Runden (über alle Autos)
			"pending_summary": false,
			"last_earned":     0.0,
		})


func _process(delta: float) -> void:
	total_playtime += delta
	for i in TRACK_COUNT:
		if not _tracks[i]["run_active"]:
			continue
		# Fahrzeit läuft weiter – egal ob 2D- oder 3D-Ansicht offen ist.
		_tracks[i]["run_elapsed"] = float(_tracks[i]["run_elapsed"]) + delta
		# Geheimer Erfolg „Dauerläufer": ein Rennen läuft ununterbrochen lang genug (run_elapsed wird
		# bei Neustart/Reset auf 0 gesetzt → zählt wirklich nur durchgehende Läufe). unlock ist idempotent.
		if float(_tracks[i]["run_elapsed"]) >= MARATHON_SECONDS:
			unlock_achievement("marathon")
		# Geld kommt in Runden-Häppchen: immer wenn ein Auto (rechnerisch) die Startlinie
		# überquert. Das gilt im Hintergrund (2D) genauso wie sichtbar in der 3D-Ansicht.
		_credit_laps(i)
		if is_endless_run():
			continue   # Endlos-Modus (Cheat ODER Prestige-Knoten „Unendliche Fahrzeit"): kein Timer
		_tracks[i]["run_timer"] -= delta
		if _tracks[i]["run_timer"] <= 0.0:
			_tracks[i]["run_timer"]       = 0.0
			_tracks[i]["run_active"]      = false
			_credit_laps(i)               # letzte fällige Runde(n) noch gutschreiben
			var earned: float = float(_tracks[i]["run_credited"])
			_tracks[i]["pending_summary"] = true
			_tracks[i]["last_earned"]     = earned
			save_game()
			emit_signal("run_ended", i, earned)


# Schreibt fällige Runden gut. Aus der verstrichenen Fahrzeit + Auto-Parametern (lap_time/
# start_delay) ergibt sich die Gesamtzahl überfahrener Startlinien. Bereits abgerechnete Runden
# zählt run_credited_laps (monoton) → robust gegen run_cars-Neuaufbau bei 2D↔3D-Wechsel und
# keine Doppelzählung. Der Reward je Runde wird NICHT eingefroren, sondern bei jeder Gutschrift
# aus den AKTUELLEN Upgrade-Werten (tilebonus/endmult) berechnet → Geld-Upgrades wirken ab der
# nächsten gutgeschriebenen Runde auch auf laufende Läufe (kein rückwirkendes Geld für schon
# gezählte Runden). Die Tile-Reihenfolge je Auto (tiles) ist streckenfix und kommt aus World3D.
func _credit_laps(i: int) -> void:
	var cars: Array = _tracks[i].get("run_cars", [])
	if cars.is_empty():
		return
	# PRO AUTO abrechnen: Autos können unterschiedlich schnell sein (Super-Auto) → unterschiedlich
	# viele Runden UND unterschiedlichen Reward. Jeder Eintrag merkt sich seine schon gezählten
	# Runden in "credited_laps" (monoton). run_cars wird bei 2D↔3D-Wechsel/Respawn neu gesetzt; dort
	# snappt set_run_cars die Zähler → keine Doppelzählung, kein rückwirkendes Geld.
	var elapsed := float(_tracks[i]["run_elapsed"])
	var gain := 0.0
	for car in cars:
		var lt := float(car.get("lap_time", 0.0))
		if lt <= 0.0:
			continue
		var car_laps := int(floor(maxf(0.0, elapsed - float(car.get("start_delay", 0.0))) / lt))
		var new_laps := car_laps - int(car.get("credited_laps", 0))
		if new_laps <= 0:
			continue
		var car_reward := _lap_reward_for_car(car)
		gain += float(new_laps) * float(car_reward)
		car["credited_laps"] = car_laps
		# Erfolge „verdiene X mit EINEM Auto in einer Runde" – am Pro-Auto-Rundenertrag.
		_check_metric_achievements("lap_earn", float(car_reward))
		# Geheime Erfolge rund um Loopings: per Rampe DURCH-gesprungen = „Loopingspringer", 3+ = „Schwindelfrei", 10+ = „Looping-Wahnsinn".
		var loops := _car_route_loop_count(car)
		# „Loopingspringer": NUR wenn man mit einer Rampe DURCH einen Looping springt (Loop auf einem
		# Rampen-Mittelfeld), nicht schon beim normalen Durchfahren eines Loopings.
		if _car_route_loop_jumped(car):
			unlock_achievement("loop_jump")
		if loops >= 3:
			unlock_achievement("loop_triple")
		if loops >= 10:
			unlock_achievement("loop_mania")
		# „Loopingspringer?": Portal-Looping-Portal in einer Linie, das Auto teleportiert durch den Loop.
		if _car_route_loop_teleport(car):
			unlock_achievement("loop_jump_portal")
		# „Im Kreis gedacht": Strecke ganz ohne normale Geraden/Kurven (nur Spezial-Teile + Start).
		if _car_route_only_special(car):
			unlock_achievement("only_special")
	if gain <= 0.0:
		return
	_currency += gain
	prestige_earned += gain   # Basis für die nächste Prestige-Punkte-Ausschüttung
	_check_metric_achievements("currency", float(_currency))   # „Besitze X Währung"-Erfolge
	_check_tab_unlocks()      # TEMP: Prestige-/Werkstatt-Tab freischalten, sobald Schwelle erreicht
	_tracks[i]["run_credited"] = float(_tracks[i]["run_credited"]) + gain
	_tracks[i]["run_earned"]   = float(_tracks[i]["run_credited"])
	emit_signal("lap_credited", i, gain)


# Wendet ein Tempo-Upgrade auf alle LAUFENDEN Runden an (auch im Hintergrund), ohne dass man
# zuschauen muss: lap_time = lap_k / aktuelles_Tempo neu berechnen und den Runden-Zähler
# snappen → kein rückwirkendes Geld, das neue Tempo zählt ab der nächsten Runde. lap_k ist
# tempo-unabhängig (lap_time·speed). Geld-Upgrades (endmult/tilebonus/tile) wirken ohnehin live
# über _lap_reward_for_car; hier geht es nur um die geänderte Rundenzeit durch das Tempo.
func _apply_speed_to_active_runs() -> void:
	var sp := get_car_speed(0)
	if sp <= 0.0:
		return
	for i in TRACK_COUNT:
		if not _tracks[i]["run_active"]:
			continue
		var elapsed := float(_tracks[i]["run_elapsed"])
		for car in _tracks[i].get("run_cars", []):
			var lk := float(car.get("lap_k", 0.0))
			# Auto-eigenes Tempo = globales Tempo ÷ speed_div (Tier t: ÷3^t; Standard: 1).
			var car_div := maxf(0.001, float(car.get("speed_div", 1.0)))
			var car_sp := sp / car_div
			# JEDES Auto fährt höchstens 15 m/s (SPEED_CAP_TEMPO · SPEED_SCALE): pro Tier ist das Tempo
			# 3× höher gedeckelt, geteilt durch das 3× größere speed_div → dieselbe tatsächliche
			# Höchstgeschwindigkeit. Eis/Steilwand bleiben über den absoluten Segment-Aufschlag in
			# CarController weiterhin schneller (nicht via lap_k).
			car_sp = minf(car_sp, SPEED_CAP_TEMPO * SPEED_SCALE)
			if lk > 0.0 and car_sp > 0.0:
				car["lap_time"] = lk / car_sp
			# Runden-Zähler dieses Autos auf den aktuellen Stand snappen (neues lap_time → future-only).
			var lt := float(car.get("lap_time", 0.0))
			car["credited_laps"] = int(floor(maxf(0.0, elapsed - float(car.get("start_delay", 0.0))) / lt)) if lt > 0.0 else 0


# Gesamtzahl überfahrener Startlinien (über alle Autos) bei der aktuellen Fahrzeit.
func _laps_total(i: int) -> int:
	var cars: Array = _tracks[i].get("run_cars", [])
	var elapsed := float(_tracks[i]["run_elapsed"])
	var total := 0
	for car in cars:
		var lt := float(car.get("lap_time", 0.0))
		if lt <= 0.0:
			continue
		total += int(floor(maxf(0.0, elapsed - float(car.get("start_delay", 0.0))) / lt))
	return total


# ╔══════════════════════════════════════════════════════════════════════════════════════════╗
# ║ VERBINDLICHE RECHEN-REGEL FÜR DEN RUNDEN-ERTRAG (gilt für ALLE zukünftigen Änderungen!)    ║
# ║                                                                                            ║
# ║ Der Ertrag einer Runde ist ein fortlaufender "Schneeball" über die Felder in FAHRREIHEN-   ║
# ║ FOLGE. Pro Feld gilt strikt diese Reihenfolge:                                             ║
# ║   1. ERST ALLE +Werte dieses Feldes addieren (Grundertrag + Tile-Bonus + +5/+10-Feld +     ║
# ║      tile-spezifische Upgrades …).                                                         ║
# ║   2. DANN ALLE ×Werte dieses Feldes anwenden (×1.5-Feld, Tribüne, Rampen-/Sprung ×2 …)      ║
# ║      auf die GESAMTE bisher angesammelte Summe.                                            ║
# ║   → running = (running + Σ aller +Werte) · (Produkt aller ×Werte)                          ║
# ║ Ganz zum Schluss EINMAL auf die ganze Runde: × End-Multiplikator × Prestige.               ║
# ║ Die Reihenfolge der Felder zählt also (frühe +Werte werden von späteren ×Werten mitgezo-   ║
# ║ gen; späte ×Werte multiplizieren eine größere Summe).                                       ║
# ║                                                                                            ║
# ║ Jeder NEUE Bonus/jedes neue Upgrade muss in genau dieses Schema eingeordnet werden:        ║
# ║ ist es ein "+" (Schritt 1) oder ein "×" (Schritt 2), und auf WELCHE Felder wirkt es?       ║
# ║ → Wenn das nicht eindeutig klar ist, NICHT raten – beim Nutzer rückfragen, BEVOR es        ║
# ║   eingebaut wird (ob +/×, auf welchen Feldern, und an welcher Stelle im Schneeball).        ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════╝
#
# Quelle der Felder: car["tiles"] (streckenfixe Tile-Reihenfolge aus CarController). Konkrete
# Zuordnung in diesem Code: base = Grundertrag, tile-Bonus/tile-spezifische Upgrades + bonus_points
# = Schritt 1; fixed_mult (Tile-eigener ×, Default-Tiles = 1.0), bonus_mult (×1.5-Feld), jump_mult (NUR is_jump = das
# übersprungene Mittelfeld zwischen ramp_start/ramp_end; die Rampe SELBST bekommt KEIN ×2)
# = Schritt 2. Alles aus den AKTUELLEN Upgrade-Werten → wirkt live, auch auf Hintergrund-Strecken.
# Rundenertrag EINES Autos. Alle Autos einer Strecke teilen das Layout (tiles), unterscheiden sich
# aber ggf. in Pro-Auto-Overrides (Super-Auto): tile_bonus_add = zusätzlicher +Ertrag JE Feld (oben
# drauf auf den globalen Tile-Bonus, Schritt 1); end_mult_extra = zusätzlicher ×Faktor ganz am Ende
# (oben drauf auf EndMult × Prestige). Normale Autos haben 0 bzw. 1 → identisch zu vorher.
# Anzahl Loopings in der streckenfixen Route dieses Autos (für die Loop-Geheim-Erfolge).
func _car_route_loop_count(car: Dictionary) -> int:
	var n := 0
	for tile in car.get("tiles", []):
		if bool(tile.get("is_loop", false)):
			n += 1
	return n


# „Loopingspringer": Mindestens ein befahrener Looping liegt auf dem übersprungenen Mittelfeld einer
# Rampe – das Auto SPRINGT also mit der Rampe durch den Looping (nicht nur durchgefahren). Der Looping-
# Tile-Eintrag trägt dann is_loop=true UND is_jump=true (Rampen-Mittelfeld, jump_mult≠1).
func _car_route_loop_jumped(car: Dictionary) -> bool:
	for tile in car.get("tiles", []):
		if bool(tile.get("is_loop", false)) and bool(tile.get("is_jump", false)):
			return true
	return false


# „Loopingspringer?": Mindestens ein befahrenes Portal hat sein Partner-Portal so platziert, dass
# genau ein Looping zwischen beiden liegt (waagerecht ODER senkrecht) → das Auto teleportiert durch
# den Looping. Das Flag setzt CarController beim Routenbau (loop_teleport am Portal-Tile).
func _car_route_loop_teleport(car: Dictionary) -> bool:
	for tile in car.get("tiles", []):
		if bool(tile.get("loop_teleport", false)):
			return true
	return false


# „Im Kreis gedacht": Route enthält mindestens ein Spezial-Teil (Loop/Portal/Rampe/Steilwand) und
# KEIN normales Fahr-Teil (Gerade/Kurve/Dreck). Das Startfeld ist unvermeidbar und darum erlaubt.
func _car_route_only_special(car: Dictionary) -> bool:
	const SPECIAL := ["loop", "portal", "ramp_start", "ramp_end", "wall_start", "wall_end"]
	var has_special := false
	for tile in car.get("tiles", []):
		if bool(tile.get("is_loop", false)) or String(tile.get("type", "")) in SPECIAL:
			has_special = true
		elif bool(tile.get("is_start", false)):
			continue   # Startfeld zählt nicht als „normales" Teil
		else:
			return false   # jedes andere befahrene Feld disqualifiziert
	return has_special


func _lap_reward_for_car(car: Dictionary) -> int:
	if float(car.get("lap_time", 0.0)) <= 0.0:
		return 0
	var tiles: Array = car.get("tiles", [])
	if tiles.is_empty():
		return 0
	var tilebonus   := get_car_tile_bonus(0) + float(car.get("tile_bonus_add", 0.0))
	var jump_mult   := get_ramp_jump_mult()
	var straight_b  := get_effect("straightbonus")
	var curve_b     := get_effect("curvebonus")
	var sandstraight_b := get_effect("sandstraightbonus")
	var sandcurve_b    := get_effect("sandcurvebonus")
	var racestraight_b := get_effect("racestraightbonus")
	var racecurve_b    := get_effect("racecurvebonus")
	var glue_b         := get_glue_earn()
	var dstraight_b := get_effect("dirtstraightbonus")
	var dcurve_b    := get_effect("dirtcurvebonus")
	var ramp_b      := get_effect("rampbonus")
	var wall_b      := get_wall_earn()
	var portal_b    := get_portal_earn()
	var running := 0.0
	for tile in tiles:
		# 1. Alle +Werte dieses Feldes.
		var add: float = float(tile.get("base", 0.0)) + tilebonus + float(tile.get("bonus_points", 0.0))
		match String(tile.get("kind", "plain")):
			"pstraight": add += straight_b
			"pcurve":    add += curve_b
			"psandstraight": add += sandstraight_b
			"psandcurve":    add += sandcurve_b
			"pracestraight": add += racestraight_b
			"pracecurve":    add += racecurve_b
			"pgluestraight", "pgluecurve": add += glue_b
			"dstraight": add += dstraight_b
			"dcurve":    add += dcurve_b
			"ramp":      add += ramp_b
			"wall":      add += wall_b
			"portal":    add += portal_b
		# 2. Alle ×Werte dieses Feldes.
		var fm: float = float(tile.get("fixed_mult", 1.0))
		var bm: float = float(tile.get("bonus_mult", 1.0))      # ×1.5-Bonusfeld (OHNE Tribünen)
		var sm: float = float(tile.get("stand_mult", 1.0))      # Produkt aller Tribünen-Mult.
		var sc: int   = int(tile.get("stand_count", 0))         # Anzahl wirkender Tribünen
		# Rampe ⇄ Looping GETAUSCHT (2026-06-19): Der Schneeball-Effekt liegt jetzt auf der RAMPE,
		# konkret auf dem übersprungenen Mittelfeld (is_jump): eigener ×J UND jeder ANDERE
		# Multiplikator dieses Feldes wird mit J skaliert (M·J), J = get_ramp_jump_mult(). JEDE
		# Tribüne zählt EINZELN (sm·J^sc). Die Rampe SELBST (kind "ramp") verdoppelt nur ihren
		# EIGENEN Ertrag (simpler ×J). Der Looping ist jetzt ein GANZ NORMALER Multiplikator (×F).
		var m: float
		if bool(tile.get("is_jump", false)):
			var jf := jump_mult
			m = jf
			if fm != 1.0: m *= fm * jf
			if bm != 1.0: m *= bm * jf
			if sc > 0:    m *= sm * pow(jf, sc)
			if bool(tile.get("is_loop", false)): m *= get_loop_factor() * jf
		elif bool(tile.get("is_loop", false)):
			# Looping: ganz normaler Multiplikator, kombiniert sich normal mit den anderen Mult.
			m = fm * bm * sm * get_loop_factor()
		else:
			m = fm * bm * sm
			if String(tile.get("kind", "plain")) == "ramp":
				m *= jump_mult   # Rampe verdoppelt ihren eigenen Ertrag
		running = (running + add) * m
	# End-Multiplikator, globaler Prestige-Multiplikator und (Super-Auto) der Extra-End-×Faktor zum Schluss.
	return int(round(running * get_car_end_mult(0) * get_prestige_mult() * float(car.get("end_mult_extra", 1.0))))


# ── Multi-Track API ─────────────────────────────────────────────────────────────

func get_active_track() -> int:
	return _active_track


func set_active_track(idx: int) -> void:
	_active_track = clampi(idx, 0, TRACK_COUNT - 1)


func get_track_grid(track_idx: int) -> Array:
	if track_idx < 0 or track_idx >= _tracks.size():
		return []
	return _tracks[track_idx]["grid"]


func set_track_grid(track_idx: int, grid: Array) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["grid"] = grid
	# Rückwärtskompatibilität: aktiver Track → track-Feld synchron halten
	if track_idx == _active_track:
		track = grid


func is_run_active(track_idx: int) -> bool:
	if track_idx < 0 or track_idx >= _tracks.size():
		return false
	return _tracks[track_idx]["run_active"]


func get_run_time_left(track_idx: int) -> float:
	if track_idx < 0 or track_idx >= _tracks.size():
		return 0.0
	return _tracks[track_idx]["run_timer"]


func start_run(track_idx: int) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["run_active"]   = true
	_tracks[track_idx]["run_timer"]    = get_drive_time()
	_tracks[track_idx]["run_duration"] = get_drive_time()
	_tracks[track_idx]["run_elapsed"]  = 0.0
	_tracks[track_idx]["run_cars"]     = []
	_tracks[track_idx]["run_earned"]   = 0.0
	_tracks[track_idx]["run_credited"] = 0.0
	_tracks[track_idx]["run_credited_laps"] = 0
	unlock_achievement("first_race")   # Erfolg: erstes Rennen gestartet


# Bisher verstrichene Fahrzeit dieses Runs (für die Rückrechnung der Auto-Position).
func get_run_elapsed(track_idx: int) -> float:
	if track_idx < 0 or track_idx >= _tracks.size():
		return 0.0
	return float(_tracks[track_idx].get("run_elapsed", 0.0))


# Auto-Parameter für die Hintergrund-Simulation setzen (von World3D beim Start/Respawn der Autos).
# cars: Array von {lap_time, lap_k, tiles, start_delay, speed_div, tile_bonus_add, end_mult_extra} –
# tiles = streckenfixe Tile-Reihenfolge, aus der _lap_reward_for_car den Runden-Ertrag live faltet.
func set_run_cars(track_idx: int, cars: Array) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["run_cars"] = cars
	# lap_time/Autozahl können sich geändert haben (Tempo-/Auto-Upgrade beim Live-Respawn oder
	# beim Wieder-Betreten der 3D-Ansicht). Bereits gezählte Runden NICHT rückwirkend neu
	# bewerten: jeden Auto-Zähler auf den aktuellen Stand snappen → nur künftige Runden zählen
	# (mit neuem lap_time/Reward). Im Normalfall (gleiches lap_time) ist das ein No-Op.
	var elapsed := float(_tracks[track_idx]["run_elapsed"])
	for car in cars:
		var lt := float(car.get("lap_time", 0.0))
		car["credited_laps"] = int(floor(maxf(0.0, elapsed - float(car.get("start_delay", 0.0))) / lt)) if lt > 0.0 else 0


func stop_run(track_idx: int) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["run_active"] = false


func get_run_earned(track_idx: int) -> float:
	if track_idx < 0 or track_idx >= _tracks.size():
		return 0.0
	return float(_tracks[track_idx]["run_earned"])


func has_pending_summary(track_idx: int) -> bool:
	if track_idx < 0 or track_idx >= _tracks.size():
		return false
	return bool(_tracks[track_idx].get("pending_summary", false))


func get_last_earned(track_idx: int) -> float:
	if track_idx < 0 or track_idx >= _tracks.size():
		return 0.0
	return float(_tracks[track_idx].get("last_earned", 0))


func clear_pending_summary(track_idx: int) -> void:
	if track_idx < 0 or track_idx >= _tracks.size():
		return
	_tracks[track_idx]["pending_summary"] = false
	_tracks[track_idx]["last_earned"]     = 0


# ── Slot-Management ────────────────────────────────────────────────────────────

func get_save_path(slot: int) -> String:
	return Paths.save_slot_path(slot)


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(get_save_path(slot))


func get_slot_info(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var f = FileAccess.open(get_save_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var txt = f.get_as_text()
	f.close()
	var data = str_to_var(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return {
		"currency":  float(data.get("currency", 0)),
		"timestamp": String(data.get("timestamp", "")),
		"name":      String(data.get("name", "")),
	}


func set_active_slot(slot: int) -> void:
	_current_slot = slot


func get_active_slot() -> int:
	return _current_slot


# ── Währung ─────────────────────────────────────────────────────────────────────

func get_currency() -> float:
	return _currency


func spend(amount: float) -> bool:
	if _currency < amount:
		return false
	_currency -= amount
	save_game()
	return true


func add(amount: float) -> void:
	_currency += amount
	_check_metric_achievements("currency", float(_currency))   # „Besitze X Währung"-Erfolge
	save_game()


func add_silent(amount: float) -> void:
	_currency += amount  # Kein sofortiges Speichern (z.B. per Runde)


# ── Motorhaube (Backpack-Tuning) ────────────────────────────────────────────────
func is_motorhaube_unlocked() -> bool:
	return motorhaube_unlocked


func unlock_motorhaube() -> bool:
	if motorhaube_unlocked or _currency < MOTORHAUBE_UNLOCK_COST:
		return false
	_currency -= MOTORHAUBE_UNLOCK_COST
	motorhaube_unlocked = true
	save_game()
	return true


func get_motorhaube_grid_level() -> int:
	return clampi(motorhaube_grid_level, 0, MOTORHAUBE_GRID_SIZES.size() - 1)


func get_motorhaube_grid_size() -> Vector2i:
	return MOTORHAUBE_GRID_SIZES[get_motorhaube_grid_level()]


func is_motorhaube_grid_maxed() -> bool:
	return get_motorhaube_grid_level() >= MOTORHAUBE_GRID_SIZES.size() - 1


# Kosten des nächsten Raster-Upgrades; -1, wenn bereits maximal.
func get_motorhaube_upgrade_cost() -> float:
	if is_motorhaube_grid_maxed():
		return -1.0
	return MOTORHAUBE_UPGRADE_COSTS[get_motorhaube_grid_level()]


func can_upgrade_motorhaube_grid() -> bool:
	return motorhaube_unlocked and not is_motorhaube_grid_maxed() and _currency >= get_motorhaube_upgrade_cost()


func upgrade_motorhaube_grid() -> bool:
	if not can_upgrade_motorhaube_grid():
		return false
	_currency -= get_motorhaube_upgrade_cost()
	motorhaube_grid_level += 1
	save_game()
	return true


func get_motorhaube_items() -> Array:
	return motorhaube_items


# Vom UI nach jeder Drag-Änderung (Ablegen/Verschieben/Entfernen) gesetzt. Persistiert sofort.
func set_motorhaube_items(items: Array) -> void:
	motorhaube_items = items.duplicate(true)
	save_game()


# Item-Vorlage (id, name, size, color) zu einer id; {} falls unbekannt.
func get_motorhaube_item_def(id: String) -> Dictionary:
	for d in MOTORHAUBE_ITEM_DEFS:
		if String(d["id"]) == id:
			return d
	return {}


# Meldet ein neu platziertes Streckenteil (vom Bau-Code in Main aufgerufen). Zählt für den geheimen
# Erfolg „Großbaumeister" (1.000 Teile gesamt) und persistiert sofort (Platzieren ist eine Nutzeraktion).
func register_tile_placed() -> void:
	total_tiles_placed += 1
	if total_tiles_placed >= 1000:
		unlock_achievement("master_builder")
	save_game()


# ── Upgrade-Abfragen ──────────────────────────────────────────────────────────

func get_upgrade_level(id: String) -> int:
	# Effektives Level = max(gekauftes Level, Head-Start-Floor aus dem Prestige-Baum), auf max_level
	# geclamped. Der Floor wirkt dadurch live (buy_prestige_node) und überlebt den Prestige-Reset
	# (upgrade_levels wird geleert, prestige_nodes nicht). buy_upgrade nutzt diesen Wert → der Kauf
	# zählt automatisch ab dem Floor weiter.
	var floored := maxi(int(upgrade_levels.get(id, 0)), get_upgrade_headstart(id))
	var mx := int(_def_for(id).get("max_level", floored))
	if id == "car_count":
		mx = get_max_level(id)   # dynamischer Hart-Cap je Werkstatt-Stufe (3/12/48)
	return mini(floored, mx)


# Summe der Head-Start-Knoten-Stufen, die das Start-Level dieses Upgrades anheben (0 = keiner).
# Tempo bekommt zusätzlich einen Auto-Tier-Head-Start (get_speed_tier_start_level), damit ein frisch
# aufgestiegenes Auto bereits mit ingame-Speed 5 startet (die Stufen sind gratis = Kostenverschiebung).
func get_upgrade_headstart(uid: String) -> int:
	var lv := 0
	for nid in HEADSTART_NODES:
		if uid in HEADSTART_NODES[nid]:
			lv += get_prestige_node_level(nid) * int(HEADSTART_STEP.get(nid, 1))
	if uid == "speed":
		lv += get_speed_tier_start_level()
	return lv


func _def_for(id: String) -> Dictionary:
	if UPGRADES.has(id):
		return UPGRADES[id]
	return {}


# Effektwert (base + per_level * level) eines Upgrades bei gegebenem Level.
func _effect_at(id: String, level: int) -> float:
	# Verdreifachte Tile-Upgrades (Dreck/Sand/Default/Renn, je Gerade+Kurve): kumulierter Ertrag =
	# Summe der steigenden 0.5-Schrittfolge aus _tile_series bis zur aktuellen Stufe. base/per_level
	# werden ignoriert (Gesamt-Ertrag = wie die alten 12/20 Stufen, nur über 3× so viele verteilt).
	if _is_tripled_tile(id):
		var cum: PackedFloat32Array = _tile_series(id)["eff_cum"]
		return cum[clampi(level, 0, cum.size() - 1)]
	# Fahrzeit: eigene Stufen-Sequenz (10,15,…,30,40,…,60,90,…).
	if id == "drive_time":
		return float(_drive_time_value(level))
	# Tempo: stückweise linear (+5/+10/+15 je Stufe ab Tempo 0/450/1350) → siehe _speed_effect_value.
	if id == "speed":
		return _speed_effect_value(level)
	# Tile-Bonus: beschleunigende Stufen-Summe (base/per_level ignoriert).
	if id == "tilebonus":
		return _tilebonus_value(level)
	# Kleber-Belag: Geld je Feld (prozentual steigend); base/per_level ignoriert.
	if id == "gluebonus":
		return get_glue_earn(level)
	# End-Multiplikator: stückweise Steigung (base/per_level ignoriert).
	if id == "endmult":
		return _endmult_value(level)
	var d = _def_for(id)
	if d.is_empty():
		return 0.0
	return float(d["base"]) + float(d["per_level"]) * level


# Fahrzeit (s) bei Upgrade-Stufe `level`: 15,20,25,30,40,50,60,90,120,150,…
# Bis 30 s in 5er-Schritten, bis 60 s in 10er-Schritten, danach in 30er-Schritten.
func _drive_time_value(level: int) -> int:
	var t := 15
	for _l in range(maxi(0, level)):
		if t < 30:
			t += 5
		elif t < 60:
			t += 10
		else:
			t += 30
	return t


# Ertrag eines Dreck-Felds bei Upgrade-Stufe `level`: 1,2,3,5,7,9,12,15,18,21,25,…
# Regel: Inkrement k wird (k+1)-mal angewandt (zwei +1, drei +2, vier +3, …).
func _dirt_field_earn(level: int) -> int:
	var total := 1
	var inc   := 1
	var steps := 0
	for _l in range(maxi(0, level)):
		total += inc
		steps += 1
		if steps >= inc + 1:
			steps = 0
			inc  += 1
	return total


# ── Verdreifachte Tile-Upgrades (Dreck/Sand/Default/Renn) ───────────────────────
# Jedes dieser Upgrades hat jetzt 3× so viele Stufen. Ertrag und Kosten werden EINMALIG generiert
# (gecacht) statt aus base/per_level/growth: eine STEIGENDE, auf 0.5 gerundete Ertrags-Schrittfolge
# (kleinster Schritt +0.5) und eine geometrische Kostenreihe mit growth^(1/3). Beide Reihen sind so
# skaliert, dass Gesamtertrag UND Gesamtkosten denen der alten Stufenzahl (max_level/3) entsprechen.
# base_cost/growth/per_level im UPGRADES-Eintrag bleiben die ALTEN Werte und dienen nur als Ziel-Quelle.
const TRIPLED_TILE_IDS = [
	"dirtstraightbonus", "dirtcurvebonus",
	"sandstraightbonus", "sandcurvebonus",
	"straightbonus", "curvebonus",
	"racestraightbonus", "racecurvebonus",
]
var _tile_series_cache: Dictionary = {}


func _is_tripled_tile(id: String) -> bool:
	return id in TRIPLED_TILE_IDS


# Liefert {eff_cum: PackedFloat32Array (Größe max+1, kumulierter Ertrag je Stufe),
#          cost: PackedInt64Array (Größe max, Kosten der Stufe i→i+1)} – gecacht.
func _tile_series(id: String) -> Dictionary:
	if _tile_series_cache.has(id):
		return _tile_series_cache[id]
	var d: Dictionary = UPGRADES[id]
	var new_max := int(d["max_level"])
	var old_max := new_max / 3
	var bc := float(d["base_cost"])
	var g  := float(d["growth"])
	# Alte Gesamtkosten (Summe der alten Stufenpreise base_cost·growth^i, i = 0 … old_max-1).
	var total_cost := 0.0
	for i in range(old_max):
		total_cost += round(bc * pow(g, i))
	# Alter Gesamtertrag: Dreck folgt der _dirt_field_earn-Reihe, die übrigen sind linear (per_level).
	var total_eff: float
	if id == "dirtstraightbonus" or id == "dirtcurvebonus":
		total_eff = float(_dirt_field_earn(old_max) - 1)
	else:
		total_eff = float(d["per_level"]) * old_max
	var res := {
		"eff_cum": _build_rising_halfsteps(new_max, total_eff),
		"cost":    _build_geom_cost(new_max, g, total_cost),
	}
	_tile_series_cache[id] = res
	return res


# Steigende, auf 0.5 gerundete Ertrags-Schritte über n Stufen, Summe ≈ total. Start ≈ 0.6·Schnitt
# (mind. 0.5), Steigung so gewählt, dass die Summe `total` möglichst genau trifft. Rückgabe ist die
# KUMULATIVE Reihe der Größe n+1 (cum[0]=0, cum[k]=Σ der ersten k Schritte) → get_effect = cum[level].
func _build_rising_halfsteps(n: int, total: float) -> PackedFloat32Array:
	var avg := total / float(maxi(1, n))
	var start := maxf(0.5, avg * 0.6)
	var best_inc := PackedFloat32Array()
	var best_err := INF
	var b := 0.0
	while b <= 1.0:
		var sum := 0.0
		var inc := PackedFloat32Array()
		for L in range(n):
			var v := maxf(0.5, round((start + b * float(L)) / 0.5) * 0.5)
			inc.append(v)
			sum += v
		var err := absf(sum - total)
		if err < best_err:
			best_err = err
			best_inc = inc
		b += 0.0005
	var cum := PackedFloat32Array()
	cum.append(0.0)
	var acc := 0.0
	for v in best_inc:
		acc += v
		cum.append(acc)
	return cum


# Geometrische Kostenreihe über n Stufen mit Wachstum growth^(1/3), Basis so skaliert, dass die
# Summe `total` (= alte Gesamtkosten) trifft. So liegt der Preis an jeder 3×-Grenze auf dem alten Wert.
func _build_geom_cost(n: int, g: float, total: float) -> PackedInt64Array:
	var gc := pow(g, 1.0 / 3.0)
	var denom := pow(gc, float(n)) - 1.0
	var base := total / float(maxi(1, n)) if absf(denom) < 0.0000001 else total * (gc - 1.0) / denom
	var cost := PackedInt64Array()
	for i in range(n):
		cost.append(int(round(base * pow(gc, float(i)))))
	return cost


# Sanfterer Kosten-Einstieg des Tile-Bonus (siehe _tilebonus_cost): die ersten 10 Stufen wachsen
# mit TILEBONUS_EARLY_GROWTH statt dem regulären growth (1.413), danach stetig wieder regulär.
const TILEBONUS_EARLY_LEVELS = 10
const TILEBONUS_EARLY_GROWTH = 1.25


# Tile-Bonus (+Geld /Feld) bei Upgrade-Stufe `level` (0..100). Zwei Phasen:
#   Lv0–20:  linear +0.5/Stufe  → +10/Feld bei Lv20 (dort ≈ 10k Kosten).
#   Lv20–100: stark beschleunigt, Verdopplung alle 3 Stufen → Lv50 ≈ +10.000/Feld, Lv100 ≈ +1e9/Feld.
# Stetig bei Lv20 (beide Zweige = 10). Closed-Form, da pro Runde im Reward aufgerufen.
func _tilebonus_value(level: int) -> float:
	var lv := clampi(level, 0, 100)
	if lv <= 20:
		return 0.5 * lv
	# Lv20–25: Verdopplung alle 3 Stufen (wie zuvor) → bei Lv25 ≈ +31.7/Feld.
	if lv <= 25:
		return 10.0 * pow(2.0, float(lv - 20) / 3.0)
	# Ab Stufe 25 etwas flacher (Verdopplung alle 4 statt 3 Stufen), stetig an Lv25 angeknüpft.
	var at25 := 10.0 * pow(2.0, 5.0 / 3.0)
	return at25 * pow(2.0, float(lv - 25) / 4.0)


# End-Multiplikator bei Upgrade-Stufe `level` (0..70). Vier Phasen mit zunehmender Schrittweite:
#   Lv0–20:  +0.1/Stufe → ×1.0 … ×3.0   (Stufe 1 = ×1.1)
#   Lv20–30: +0.2/Stufe → ×3.0 … ×5.0
#   Lv30–50: +0.5/Stufe → ×5.0 … ×15.0
#   Lv50–70: +1.0/Stufe → ×15.0 … ×35.0
# Geschlossene Form (stetig an den Phasengrenzen), da pro Runde im Reward aufgerufen.
func _endmult_value(level: int) -> float:
	var lv := clampi(level, 0, 70)
	if lv <= 20:
		return 1.0 + 0.1 * lv
	if lv <= 30:
		return 3.0 + 0.2 * (lv - 20)
	if lv <= 50:
		return 5.0 + 0.5 * (lv - 30)
	return 15.0 + 1.0 * (lv - 50)


func get_upgrade_cost(id: String) -> int:
	return _upgrade_cost_at(id, get_upgrade_level(id))


# Kosten, um ein Upgrade von Stufe `level` auf `level+1` zu bringen. get_upgrade_cost nutzt die
# aktuelle Stufe; für die „Max"-Vorschau (max_affordable_info) brauchen wir die Kosten beliebiger
# Stufen, daher hier mit explizitem Level.
func _upgrade_cost_at(id: String, level: int) -> int:
	# Preisverschiebung: Head-Start-Knoten schenken die ersten Stufen GRATIS und verschieben die
	# Kostenkurve mit – die nächste BEZAHLTE Stufe kostet wieder wie normal die Stufe 0. Dafür rechnet
	# die Kostenformel mit dem „bezahlten" Stufen-Index (effektive Stufe minus geschenkter Head-Start),
	# nie unter 0. Ohne Head-Start (=0) bleibt alles unverändert. Greift für ALLE Head-Start-Upgrades
	# (Tile-Bonus/Tempo/End-Mult/Auto). Verdreifachte Tile-Upgrades haben keinen Head-Start (paid=level).
	var paid := maxi(0, level - get_upgrade_headstart(id))
	if id == "speed":
		return _speed_cost(paid)
	if id == "tilebonus":
		return _tilebonus_cost(paid)
	# Verdreifachte Tile-Upgrades: Kosten der NÄCHSTEN Stufe aus _tile_series (geom. mit growth^(1/3),
	# Summe = alte Gesamtkosten; liegt an jeder 3×-Grenze exakt auf dem alten Preis).
	if _is_tripled_tile(id):
		var cost: PackedInt64Array = _tile_series(id)["cost"]
		return 0 if paid >= cost.size() else int(cost[paid])
	var d = _def_for(id)
	if d.is_empty():
		return 0
	return int(round(float(d["base_cost"]) * pow(float(d["growth"]), paid)))


# „Max"-Kaufmenge (Shop-Umschalter „Einzeln/Max"): wie viele Stufen mit dem aktuellen Geld auf
# einmal gekauft werden könnten (bis max_level) und was sie zusammen kosten. Reine Vorschau –
# kauft nichts. Iterativ, da die Kosten je Stufe steigen. → {"count": int, "cost": int}
func max_affordable_info(id: String) -> Dictionary:
	var lvl   := get_upgrade_level(id)
	var mx    := effective_max_level(id)
	var money := _currency
	var count := 0
	var total := 0
	while lvl + count < mx:
		var c := _upgrade_cost_at(id, lvl + count)
		if money < c:
			break
		money -= c
		total += c
		count += 1
	return {"count": count, "cost": total}


# Aktuell gewählte Kaufmenge (Wert aus BUY_QTY_OPTIONS; -1 = Max).
func get_buy_qty() -> int:
	return BUY_QTY_OPTIONS[clampi(buy_qty_mode, 0, BUY_QTY_OPTIONS.size() - 1)]


func is_buy_max() -> bool:
	return get_buy_qty() < 0


# Schaltet den Kaufmengen-Knopf eine Stufe weiter (1 → 5 → 10 → 25 → Max → 1 …).
func cycle_buy_qty() -> void:
	buy_qty_mode = (buy_qty_mode + 1) % BUY_QTY_OPTIONS.size()


# Kauf-Vorschau für die aktuelle Kaufmenge. Bei „Max" identisch zu max_affordable_info (so viele
# Stufen wie leistbar). Bei fester Menge N werden die nächsten min(N, Rest-Stufen) Stufen
# zusammengerechnet – der Preis (cost) ist IMMER die Summe dieser Stufen, auch wenn das Geld (noch)
# nicht reicht; `affordable` sagt nur, ob aktuell leistbar. → {"count", "cost", "affordable"}
func buy_qty_info(id: String) -> Dictionary:
	if is_buy_max():
		var mi := max_affordable_info(id)
		mi["affordable"] = int(mi["count"]) > 0
		return mi
	var lvl := get_upgrade_level(id)
	var mx  := effective_max_level(id)
	var target := mini(get_buy_qty(), mx - lvl)
	var total := 0
	for i in range(target):
		total += _upgrade_cost_at(id, lvl + i)
	return {"count": target, "cost": total, "affordable": target > 0 and _currency >= float(total)}


# Kann mit der aktuellen Kaufmenge gekauft werden (mind. 1 Stufe und leistbar)?
func can_buy_qty(id: String) -> bool:
	var info := buy_qty_info(id)
	return int(info["count"]) > 0 and bool(info["affordable"])


# Tile-Bonus-Kosten der NÄCHSTEN Stufe. Wie beim Tempo: die ersten TILEBONUS_EARLY_LEVELS Stufen
# wachsen sanfter (TILEBONUS_EARLY_GROWTH statt growth) → günstigerer, flacherer Einstieg. Ab dieser
# Stufe geht es STETIG (kein Sprung) mit dem ursprünglichen growth weiter (am 10er-Preis angeknüpft).
func _tilebonus_cost(level: int) -> int:
	var d := UPGRADES["tilebonus"]
	var bc := float(d["base_cost"])
	var g  := float(d["growth"])
	if level <= TILEBONUS_EARLY_LEVELS:
		return int(round(bc * pow(TILEBONUS_EARLY_GROWTH, level)))
	var early := bc * pow(TILEBONUS_EARLY_GROWTH, TILEBONUS_EARLY_LEVELS)
	return int(round(early * pow(g, level - TILEBONUS_EARLY_LEVELS)))


# Tempo-Kosten der NÄCHSTEN Stufe. Zwei stetig ineinander übergehende Phasen (kein Preissprung):
#   Stufe 0 … SPEED_STEEP_LEVELS:  steiler Verlauf (×SPEED_STEEP_GROWTH) bis zum Standard-Cap
#                                  (Tempo 150) – der „Auto 1"-Grind.
#   darüber:                       sanftes Tail-Wachstum (×SPEED_TAIL_GROWTH). Die höheren Auto-Tiers
#                                  klettern dieselbe steile Phase hoch und ziehen ihren 3× höheren
#                                  Cap über das günstige Tail nach (machbar dank größerer Wirtschaft).
# Der Übergang knüpft am Preis bei SPEED_STEEP_LEVELS an → genau ein ×SPEED_TAIL_GROWTH-Schritt.
func _speed_cost(level: int) -> int:
	var bc := float(UPGRADES["speed"]["base_cost"])
	if level < SPEED_STEEP_LEVELS:
		return int(round(bc * pow(SPEED_STEEP_GROWTH, level)))
	var at_cap := bc * pow(SPEED_STEEP_GROWTH, SPEED_STEEP_LEVELS)   # Preis am Standard-Cap (Tempo 150)
	return int(round(at_cap * pow(SPEED_TAIL_GROWTH, level - SPEED_STEEP_LEVELS)))


# Faktor, um den das AKTUELLE Auto-Tier langsamer fährt als das Standard-Auto. Jedes Tier teilt das
# Tempo erneut durch SUPER_CAR_SPEED_DIV (Tier 0 → 1, Tier 1 → 3, Tier 2 → 9 …) → jedes Auto ist ein
# Drittel so schnell wie das davor. Dadurch braucht man pro Auto entsprechend mehr Tempo, um dieselbe
# tatsächliche Höchstgeschwindigkeit (15 m/s) zu erreichen.
func get_car_speed_div(tier: int = -1) -> float:
	var t := car_tier if tier < 0 else tier
	return pow(SUPER_CAR_SPEED_DIV, float(maxi(0, t)))


# Tempo-Wert (Stat), bei dem das AKTUELLE Auto seine tatsächliche Höchstgeschwindigkeit (15 m/s)
# erreicht. Skaliert mit dem Tier: Standard 150, Tier 1 450, Tier 2 1350 … (= SPEED_CAP_TEMPO · div).
# Bestimmt, wann das Tempo-Upgrade im Shop sperrt.
func get_speed_cap_tempo(tier: int = -1) -> float:
	return SPEED_CAP_TEMPO * get_car_speed_div(tier)


# Tempo-Effekt (Shop-Speed) bei `level`. STÜCKWEISE linear, damit es nicht zu viele Stufen gibt:
#   bis Tempo 450  : +5  je Stufe  (Stufe 0..90  → 0..450)
#   bis Tempo 1350 : +10 je Stufe  (Stufe 90..180 → 450..1350)
#   darüber        : +15 je Stufe  (Stufe >180)
func _speed_effect_value(level: int) -> float:
	if level <= 90:
		return 5.0 * level
	if level <= 180:
		return 450.0 + 10.0 * (level - 90)
	return 1350.0 + 15.0 * (level - 180)


# Umkehrung von _speed_effect_value: kleinste Tempo-Stufe, deren Effekt `target` erreicht.
func _speed_level_for_effect(target: float) -> int:
	if target <= 450.0:
		return maxi(0, int(ceil(target / 5.0)))
	if target <= 1350.0:
		return 90 + int(ceil((target - 450.0) / 10.0))
	return 180 + int(ceil((target - 1350.0) / 15.0))


# Kleinste Tempo-Stufe, deren Effekt den Tempo-Cap des AKTUELLEN Autos (get_speed_cap_tempo) erreicht
# – ab da bringt das Tempo-Upgrade diesem Auto nichts mehr und der Shop sperrt es.
# Tier 0=30, 1=90, 2=180, 3=360 Stufen.
func _speed_cap_level() -> int:
	return _speed_level_for_effect(get_speed_cap_tempo())


# Start-Tempo-Stufe je Auto-Tier: so viel, dass die ingame-Speed (Tempo ÷ Tier-Teiler) = 5 ist
# (Tempo = 5 · 3^t). Diese Stufen bekommt der Spieler GRATIS als Head-Start (get_upgrade_headstart),
# damit ein frisch aufgestiegenes (3× langsameres) Auto nicht im Schneckentempo startet.
# Tier 0→1, 1→3, 2→9, 3→27 Stufen.
func get_speed_tier_start_level() -> int:
	return _speed_level_for_effect(5.0 * get_car_speed_div())


# Erreichbare Höchststufe für den AKTUELLEN Auto-Stand. Beim Tempo ist das der Tier-abhängige Cap
# (150 / 450 / 1350 …); jenseits davon brächte mehr Tempo dem (immer gedeckelten) Auto nichts.
# Alle anderen Upgrades: unverändert get_max_level.
# Fahrzeit-Shop-Stufe, die das Zeitlimit aufhebt („Unendliche Fahrzeit"). Sie ist nur kaufbar, wenn der
# gleichnamige Prestige-Knoten (drive_time_inf) gekauft wurde – dann hebt effective_max_level den Cap
# von 9 auf diese Stufe an. Erst der KAUF dieser Stufe schaltet den Endlos-Modus frei (is_endless_run).
const DRIVE_TIME_INF_LEVEL = 10

func effective_max_level(id: String) -> int:
	if id == "speed":
		return _speed_cap_level()
	# Fahrzeit: „Stufe 10" (kein Zeitlimit) wird erst durch den Prestige-Knoten drive_time_inf kaufbar.
	if id == "drive_time" and get_prestige_node_level("drive_time_inf") >= 1:
		return DRIVE_TIME_INF_LEVEL
	return get_max_level(id)


func is_maxed(id: String) -> bool:
	var d = _def_for(id)
	if d.is_empty():
		return true
	return get_upgrade_level(id) >= effective_max_level(id)


func can_buy(id: String) -> bool:
	return not is_maxed(id) and _currency >= get_upgrade_cost(id)


func buy_upgrade(id: String) -> bool:
	if not can_buy(id):
		return false
	_currency -= get_upgrade_cost(id)
	upgrade_levels[id] = get_upgrade_level(id) + 1
	save_game()
	# Tempo-Upgrade sofort auf alle laufenden Runden anwenden (auch Hintergrund), future-only.
	if id == "speed":
		_apply_speed_to_active_runs()
	emit_signal("upgrade_purchased", id)
	return true


# „Max"-Kauf (Shop-Umschalter): kauft so viele Stufen wie mit dem aktuellen Geld möglich (bis
# max_level) und gibt die Anzahl gekaufter Stufen zurück. Kosten/Effekt werden je Stufe einzeln
# verrechnet (Kosten steigen mit der Stufe), daher iterativ. save_game + Signal nur EINMAL am Ende.
func buy_upgrade_max(id: String) -> int:
	var bought := 0
	while can_buy(id):
		_currency -= get_upgrade_cost(id)
		upgrade_levels[id] = get_upgrade_level(id) + 1
		bought += 1
	if bought > 0:
		save_game()
		if id == "speed":
			_apply_speed_to_active_runs()
		emit_signal("upgrade_purchased", id)
	return bought


# Kauf gemäß aktueller Kaufmenge (Knopf-Umschalter). „Max" → buy_upgrade_max. Feste Menge N → kauft
# genau die in buy_qty_info ermittelten Stufen in EINEM Schritt (nur wenn die Summe leistbar ist),
# sonst nichts. save_game + Signal nur einmal. Rückgabe = Anzahl gekaufter Stufen.
func buy_upgrade_qty(id: String) -> int:
	if is_buy_max():
		return buy_upgrade_max(id)
	var info := buy_qty_info(id)
	var n := int(info["count"])
	if n <= 0 or not bool(info["affordable"]):
		return 0
	_currency -= float(info["cost"])
	upgrade_levels[id] = get_upgrade_level(id) + n
	save_game()
	if id == "speed":
		_apply_speed_to_active_runs()
	emit_signal("upgrade_purchased", id)
	return n


# ── Anzeige-Helfer (für das Upgrade-Menü) ──────────────────────────────────────

func get_upgrade_name(id: String) -> String:
	return String(_def_for(id).get("name", id))


func get_upgrade_unit(id: String) -> String:
	return String(_def_for(id).get("unit", ""))


func get_max_level(id: String) -> int:
	if id == "car_count":
		# Hart-Cap: pro Werkstatt-Stufe kostet jedes zusätzliche AKTIVE Auto SUPER_CAR_COST_CARS^tier
		# Käufe; bei (ACTIVE_CAR_CAP-1 =) 3 Extra-Autos ergibt das Tier 0 → 3, Tier 1 → 12, Tier 2 → 48.
		return (ACTIVE_CAR_CAP - 1) * get_car_cost_per_extra()
	return int(_def_for(id).get("max_level", 0))


# Effektwert bei aktuellem (level < 0) oder angegebenem Level.
func get_effect(id: String, level: int = -1) -> float:
	if level < 0:
		level = get_upgrade_level(id)
	return _effect_at(id, level)


# Lesbarer Effekt-Text für eine bestimmte Stufe (Sonderfälle: grid_size, car_count).
func effect_text(id: String, level: int) -> String:
	if id.begins_with("bonus_"):
		if level <= 0:
			return Icons.LOCK + " gesperrt"
		return "%d Feld" % level if level == 1 else "%d Felder" % level
	if id == "grid_size":
		var lv = clampi(level, 0, GRID_STEPS.size() - 1)
		return "%d×%d" % [GRID_STEPS[lv].x, GRID_STEPS[lv].y]
	if id == "car_count":
		# Tatsächlich fahrende Autos für dieses Level (je Werkstatt-Stufe kostet ein Auto mehr Käufe).
		return "%d Autos" % mini(1 + int(level / get_car_cost_per_extra()), ACTIVE_CAR_CAP)
	# Eisgerade: kein Geld-Effekt → Speed-Boost (Tempo-Stufen) + Reichweite zeigen.
	if id == "icebonus":
		return "+%.1f Lvl · %d Felder" % [get_ice_boost_levels(level), get_ice_range(level)]
	# Kleber-Belag: Geld-Grundertrag je Feld + prozentuale Bremse.
	if id == "gluebonus":
		return "+%s %s · −%d%% Tempo" % [format_currency(get_glue_earn(level)), Icons.COIN, get_glue_slow_pct(level)]
	# Steilwandkurve: Geld-Grundertrag + Speed-Boost (Tempo-Stufen) + Reichweite.
	if id == "wallbonus":
		return "+%s %s · +%.1f Lvl · %d Felder" % [format_currency(get_wall_earn(level)), Icons.COIN, get_wall_boost_levels(level), get_wall_range(level)]
	# Looping: ganz normaler Multiplikator ×F (seit 2026-06-19 kein Schneeball mehr – der liegt jetzt auf der Rampe).
	if id == "loopbonus":
		return "×%.1f" % get_loop_factor(level)
	# Rampe (seit 2026-06-19 mit Schneeball): additiver Ertrag je Rampe + ×J auf sich und alle anderen Mult. des Sprungfeldes.
	if id == "rampbonus":
		var je := RAMP_BASE_EARN + _effect_at("rampbonus", level)
		return "+%s %s · ×%.1f · andere ×%.1f" % [format_currency(je), Icons.COIN, get_ramp_jump_mult(level), get_ramp_jump_mult(level)]
	# Portal: additiver Geld-Ertrag je Durchgang (kein Multiplikator).
	if id == "portalbonus":
		return "+%s %s /Durchgang" % [format_currency(get_portal_earn(level)), Icons.COIN]
	# Tribüne: Multiplikator auf das/die Nachbarfeld(er).
	if id == "standbonus":
		return "×%.1f /Nachbarfeld" % get_effect("standbonus", level)
	# Tile-Bonus: Geld je Feld, wird in hohen Stufen riesig (Lv100 ≈ +1.4e7/Feld). Ab 1000 die
	# Idle-Kurznotation (K/M/… bzw. wissenschaftlich, je nach money_notation) statt der langen Zahl;
	# darunter die feinen 0.5-Schritte unverändert lassen.
	if id == "tilebonus":
		var tv := _effect_at("tilebonus", level)
		var tu := get_upgrade_unit(id)
		if tv >= 1000.0:
			return "%s%s" % [format_currency(tv), tu]
		if absf(tv - round(tv)) < 0.001:
			return "%d%s" % [int(round(tv)), tu]
		return "%.1f%s" % [tv, tu]
	# Fahrzeit: die freischaltbare Endlos-Stufe (DRIVE_TIME_INF_LEVEL) zeigt ∞ statt einer Sekundenzahl.
	if id == "drive_time" and level >= DRIVE_TIME_INF_LEVEL:
		return Icons.INFINITY
	var v = _effect_at(id, level)
	var unit = get_upgrade_unit(id)
	if id == "endmult":
		return "×%.2f" % v
	# Verdreifachte Tile-Upgrades kommen in 0.5-Schritten: unter 10 mit Nachkommastelle, ab 10 ganz.
	if _is_tripled_tile(id):
		return "%s%s" % [format_half(v), unit]
	# Ganzzahlig ohne Nachkommastellen, sonst eine Stelle
	if absf(v - round(v)) < 0.001:
		return "%d%s" % [int(round(v)), unit]
	return "%.1f%s" % [v, unit]


# Anzeige von +Ertrags-Werten, die in 0.5-Schritten kommen (verdreifachte Tile-Upgrades): unter 10
# mit einer Nachkommastelle (z. B. „9.5"), ab 10 ganzzahlig gerundet (Halb-Schritte sind dort
# vernachlässigbar/unleserlich). 9.0 → „9", 9.5 → „9.5", 10.5 → „11".
func format_half(value: float) -> String:
	if value < 10.0 and absf(value - round(value)) > 0.01:
		return "%.1f" % value
	return str(int(round(value)))


# ── Zahl-Formatierung (Idle-Stil: 1.23K, 4.56M, … sonst wissenschaftlich) ──────

const _CURR_SUFFIX = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

func format_currency(value) -> String:
	var v = float(value)
	var sign_str = "-" if v < 0.0 else ""
	v = absf(v)
	# Kleine Beträge in allen Notationen als reine Zahl (e-/Suffix-Form ist hier unleserlich).
	if v < 1000.0:
		return sign_str + str(int(round(v)))
	# Gewähltes Geld-Zahlenformat (globale Anzeige-Einstellung in Display).
	var mode := Display.money_notation
	if mode == Display.MoneyNotation.SCIENTIFIC:
		# e-Form bereits ab 1e6 (eine Million): ab da z. B. "1.23e6" statt der langen Zahl (Wunsch).
		if v < 1e6:
			return sign_str + str(int(round(v)))
		# Beliebiger Exponent, Mantisse in [1,10): z. B. 1.23e7.
		var sexp = int(floor(log(v) / log(10.0)))
		return sign_str + _trim_num(v / pow(10.0, sexp)) + "e" + str(sexp)
	elif mode == Display.MoneyNotation.ENGINEER:
		# e-Form erst ab 1e9 (darunter reine Zahl, damit der Shop nicht schon bei "1e3" startet).
		if v < 1e9:
			return sign_str + str(int(round(v)))
		# Exponent in 3er-Schritten, Mantisse in [1,1000): z. B. 12.3e6.
		var eexp = (int(floor(log(v) / log(10.0))) / 3) * 3
		return sign_str + _trim_num(v / pow(10.0, eexp)) + "e" + str(eexp)
	# STANDARD: Suffixe K/M/B/T …; jenseits der Tabelle wissenschaftlich.
	var tier = int(floor(log(v) / log(1000.0)))
	if tier >= 1 and tier < _CURR_SUFFIX.size():
		return sign_str + _trim_num(v / pow(1000.0, tier)) + _CURR_SUFFIX[tier]
	var exp = int(floor(log(v) / log(10.0)))
	return sign_str + _trim_num(v / pow(10.0, exp)) + "e" + str(exp)


# Zahl mit bis zu 2 Nachkommastellen, ohne überflüssige Nullen ("12.30"→"12.3", "5.00"→"5").
func _trim_num(x: float) -> String:
	var s = "%.2f" % x
	if s.find(".") >= 0:
		while s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s


# ── Abgeleitete Spielwerte ──────────────────────────────────────────────────────

func get_drive_time() -> float:
	return _effect_at("drive_time", get_upgrade_level("drive_time"))


# Läuft ein Run ohne Zeitlimit? Entweder der Cheat-Toggle (endless_mode) ODER der Prestige-Knoten
# „Unendliche Fahrzeit": aktiv, sobald die Fahrzeit-Shop-Stufe DRIVE_TIME_INF_LEVEL (10) GEKAUFT ist.
# Diese Stufe ist ihrerseits nur kaufbar, wenn der Prestige-Knoten drive_time_inf vorhanden ist
# (effective_max_level) – der Knoten allein macht also noch nicht endlos, erst der Shop-Kauf. Dann fährt
# die Strecke bis zum manuellen Beenden weiter (kein run_timer-Ablauf, siehe _process). UI zeigt ∞.
func is_endless_run() -> bool:
	return endless_mode or get_upgrade_level("drive_time") >= DRIVE_TIME_INF_LEVEL


func get_total_playtime() -> float:
	return total_playtime


# Sekunden → "H:MM:SS" (z. B. 1:59:46), für die Statistik-Seite.
func format_playtime(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	return "%d:%02d:%02d" % [h, m, s]


# Streckengröße kommt jetzt aus dem Prestige-Tech-Baum (reset-fest), nicht mehr aus upgrade_levels.
func get_grid_rows() -> int:
	return GRID_STEPS[clampi(get_prestige_node_level("grid"), 0, GRID_STEPS.size() - 1)].x


func get_grid_cols() -> int:
	return GRID_STEPS[clampi(get_prestige_node_level("grid"), 0, GRID_STEPS.size() - 1)].y


# BESESSENE Autos = 1 + normales Auto-Upgrade (car_count, inkl. car_start-Floor). Kann weit über den
# Fahr-Cap hinausgehen – das „Überschuss" füttert die Werkstatt-Tier-Ökonomie (SUPER_CAR_COST_CARS).
func get_car_count() -> int:
	# Das Auto-Startlevel (car_start) hebt den car_count-Floor (siehe get_upgrade_level) → kein
	# separater + node("car")-Term mehr.
	return 1 + get_upgrade_level("car_count")


# Max. gleichzeitig FAHRENDE normale Autos (Tier 0). Mehr besessene Autos fahren nicht gleichzeitig –
# sie lohnen erst über die Werkstatt-Stufe, wo SUPER_CAR_COST_CARS Autos zu einem Tier-Auto werden.
const ACTIVE_CAR_CAP = 4

# Wie viele car_count-Käufe EIN zusätzliches fahrendes Auto kostet. Steigt je Werkstatt-Stufe ×4
# (SUPER_CAR_COST_CARS): Tier 0 → 1, Tier 1 → 4, Tier 2 → 16. Zusammen mit dem Fahr-Cap (4 Autos =
# 3 Extra) ergibt das den Shop-Hart-Cap get_max_level("car_count") = 3/12/48.
func get_car_cost_per_extra() -> int:
	return int(pow(float(SUPER_CAR_COST_CARS), float(car_tier)))


# Tatsächlich fahrende Autos (Wahrheitsquelle für Spawn + Renten/Reward, auch Hintergrund):
# 1 Standard-Auto + je get_car_cost_per_extra() gekauften Auto-Upgrades eines mehr, gedeckelt auf
# ACTIVE_CAR_CAP (= 4). Gilt einheitlich für alle Tiers (Tier ≥1 fährt das Tier-Auto-Modell).
func get_active_car_count() -> int:
	return mini(1 + int(get_upgrade_level("car_count") / get_car_cost_per_extra()), ACTIVE_CAR_CAP)


# ── Super-Auto („Auto 2") ──────────────────────────────────────────────────────

func get_super_car_count() -> int:
	return super_car_count

# Preis des NÄCHSTEN Super-Autos = Basis · Wachstum^(bereits gekaufte).
func get_super_car_cost() -> int:
	return int(round(float(SUPER_CAR_COST) * pow(SUPER_CAR_COST_GROWTH, super_car_count)))

# Voraussetzungen für ein WEITERES Super-Auto erfüllt? Es müssen noch genug FREIE Standard-Autos da
# sein (SUPER_CAR_COST_CARS je bereits gekauftem + 1 neuem) UND Tempo ≥ Schwelle. (Preis NICHT geprüft.)
func super_car_prereqs_met() -> bool:
	return get_car_count() >= SUPER_CAR_COST_CARS * (super_car_count + 1) \
		and get_effect("speed") >= float(SUPER_CAR_REQ_SPEED)

# Kann JETZT ein weiteres Super-Auto gekauft werden? (Voraussetzungen + Geld da)
func can_buy_super_car() -> bool:
	return super_car_prereqs_met() and _currency >= get_super_car_cost()

func buy_super_car() -> bool:
	if not can_buy_super_car():
		return false
	_currency -= get_super_car_cost()
	super_car_count += 1
	save_game()
	# Gleicher Signalweg wie normale Upgrades → World3D setzt die Autos neu auf, Shop aktualisiert sich.
	emit_signal("upgrade_purchased", "super_car")
	return true


# ── Auto-Prestige (Tier) ────────────────────────────────────────────────────────

func get_car_tier() -> int:
	return car_tier

# Modellpfad der aktuellen (oder einer gegebenen) Stufe; über die definierten Stufen hinaus → letztes Modell.
# Reihenfolge: 0 default_car, 1 eric ("Renn"auto), 2 Frosch (miata), 3 Blender-Auto (test_car_blender).
func get_car_tier_model(tier: int = -1) -> String:
	var t = car_tier if tier < 0 else tier
	match clampi(t, 0, CAR_TIER_COUNT - 1):
		0: return Paths.MODEL_DEFAULT_CAR
		1: return Paths.MODEL_ERIC_CAR
		2: return Paths.MODEL_FROSCH_CAR
		_: return Paths.MODEL_TEST_CAR_BLENDER


# Albedo-Textur für die Werkstatt-Lackierung der jeweiligen Stufe (UV-gebunden ans Modell). Nur Stufe 2
# (Frosch) nutzt die Maske; die anderen liefern einen Platzhalter (wird ohne Maske nicht angewandt).
func get_car_tier_albedo(tier: int = -1) -> String:
	var t = car_tier if tier < 0 else tier
	match clampi(t, 0, CAR_TIER_COUNT - 1):
		2: return Paths.TEX_FROSCH_ALBEDO
		_: return Paths.TEX_CAR_ALBEDO


# Umfärb-Maske der jeweiligen Stufe (Rot = umfärbbar). Nur Stufe 2 (Frosch) hat eine Maske.
func get_car_tier_mask(tier: int = -1) -> String:
	var t = car_tier if tier < 0 else tier
	match clampi(t, 0, CAR_TIER_COUNT - 1):
		2: return Paths.TEX_FROSCH_MASK
		_: return Paths.TEX_CAR_MASK


# Hat die Stufe eine Umfärb-Maske (→ Lack/Muster greifen per Masken-Shader)? Nur Stufe 2 (Frosch).
# Stufe 0 (default_car) und 1 (eric) haben keine Maske; Stufe 3 (Blender-Auto) wird über den
# Color-Key umgefärbt (siehe Car3D._color_key), nicht über die Maske.
func tier_has_mask(tier: int = -1) -> bool:
	var t = car_tier if tier < 0 else tier
	return t == 2


# Wird die Stufe über den Color-Key umgefärbt (statt Maske)? Trifft auf das Blender-Auto zu.
func tier_is_colorkey(tier: int = -1) -> bool:
	return get_car_tier_model(tier) == Paths.MODEL_TEST_CAR_BLENDER


# Lässt sich die Stufe in der Werkstatt lackieren/mustern (Maske ODER Color-Key)?
func tier_supports_paint(tier: int = -1) -> bool:
	return tier_has_mask(tier) or tier_is_colorkey(tier)

# LEGACY/UNGENUTZT: frühere GELD-Schwelle für den Aufstieg. Der Aufstieg läuft jetzt komplett über
# Prestige-Punkte (get_car_ascend_point_cost / can_ascend_car). Funktion bleibt nur als Referenz.
func get_car_ascend_cost() -> float:
	if car_tier == 0:
		return 5_000_000.0
	var stage := 8.0 + float(car_tier - 1) * 12.0
	return PRESTIGE_K * pow(10.0, stage)

# JEDER Aufstieg wird mit Prestige-Punkten bezahlt (für die UI beibehalten, immer true).
func car_ascend_uses_points() -> bool:
	return true

# ⭐-Schwelle des NÄCHSTEN Aufstiegs (indiziert nach aktuellem car_tier). Über die Liste hinaus
# ×CAR_ASCEND_POINT_GROWTH je weiterer Stufe.
func get_car_ascend_point_cost() -> float:
	if car_tier < CAR_ASCEND_POINT_COSTS.size():
		return float(CAR_ASCEND_POINT_COSTS[car_tier])
	var last := float(CAR_ASCEND_POINT_COSTS[CAR_ASCEND_POINT_COSTS.size() - 1])
	return last * pow(CAR_ASCEND_POINT_GROWTH, float(car_tier - (CAR_ASCEND_POINT_COSTS.size() - 1)))

func can_ascend_car() -> bool:
	# Werkstatt ist bei CAR_TIER_COUNT Autos (letzte Stufe) gedeckelt – kein Aufstieg mehr.
	if car_tier >= CAR_TIER_COUNT - 1:
		return false
	return prestige_points >= get_car_ascend_point_cost()


# Werkstatt-Ökonomie je Stufe (oben drauf auf die globalen Geld-Upgrades). Wird je Auto deutlich stärker:
#  Tier 1 ("Renn"auto):  +10k je Feld,        ×3  End-Multiplikator.
#  Tier 2 (Frosch):      +1.000.000 je Feld,  ×10 End-Multiplikator.
#  Tier 3 (Blender-Auto):+100.000.000 je Feld,×30 End-Multiplikator.
func get_tier_tile_bonus(tier: int = -1) -> float:
	var t = car_tier if tier < 0 else tier
	match t:
		2: return 1_000_000.0
		3: return 100_000_000.0
		_: return SUPER_CAR_TILE_BONUS   # 10.000 (Tier 1)

func get_tier_end_mult(tier: int = -1) -> float:
	var t = car_tier if tier < 0 else tier
	match t:
		1: return 3.0
		2: return 10.0
		3: return 30.0
		_: return SUPER_CAR_END_MULT      # 1.0 (neutral)

# Multiplikator auf verdiente Prestigepunkte (stapelt je Auto-Stufe: ×4, ×16, …).
func get_car_point_mult() -> float:
	return pow(CAR_ASCEND_POINT_MULT, car_tier)

# Wie viele Prestige-Zähler ein einzelnes Prestige gutschreibt (stapelt je Auto-Stufe: 1, 2, 4, …).
# Da ascend_car prestige_count auf 0 setzt, holt man so pro Prestige mehrere Baum-Knoten auf einmal
# zurück (Auto-Stufe 1 = 2 Knoten/Prestige), damit der Werkstatt-Reset nicht so hart trifft.
func get_car_prestige_step() -> int:
	return int(pow(CAR_ASCEND_COUNT_MULT, car_tier))

# Anzahl fahrender Tier-Autos ab Stufe ≥1: Basis 1 + je SUPER_CAR_COST_CARS normale Autos eines mehr.
func get_tier_car_count() -> int:
	return 1 + int(get_car_count() / SUPER_CAR_COST_CARS)

# Führt den Auto-Aufstieg aus: car_tier += 1, danach Reset (Geld/Upgrades/Tiles + Prestige-PUNKTE,
# Node-Level UND prestige_count → der Tech-Baum ist wieder gated und muss neu hochgeprestigt werden).
# Als Ausgleich schaltet jedes Prestige nach dem Aufstieg gleich mehrere Knoten frei
# (get_car_prestige_step, stapelt ×2 je Stufe), damit der Reset nicht so hart trifft.
# NICHT zurückgesetzt: car_tier + Kosmetik; Tab-Unlocks (prestige_/werkstatt_) bleiben ebenfalls dauerhaft.
func ascend_car() -> bool:
	if not can_ascend_car():
		return false
	car_tier += 1
	unlock_achievement("car_ascend")   # Erfolg: erstes Auto-Upgrade in der Werkstatt
	_currency       = START_CURRENCY
	upgrade_levels  = {}
	track           = []
	unlocked_tiles  = {}
	prestige_earned = 0.0
	prestige_points = 0.0
	prestige_nodes  = {}   # Node-LEVEL zurück auf 0 (neu kaufen)
	prestige_count  = 0    # Zähler zurück → Baum wieder gated, aber jedes Prestige holt jetzt mehr Knoten auf einmal
	super_car_count = 0
	_active_track   = 0
	_init_tracks()
	save_game()
	prestige_changed.emit()
	# Wie ein Upgrade-Kauf → angeschaute 3D-Strecke setzt die Autos (neues Modell) neu auf.
	emit_signal("upgrade_purchased", "super_car")
	return true


# Freigeschaltete Strecken = Basis + Prestige-Knoten „track" (Obergrenze = TRACK_COUNT-Kapazität).
func get_unlocked_tracks() -> int:
	return clampi(PRESTIGE_TRACK_BASE + get_prestige_node_level("track"), 1, TRACK_COUNT)


# Tempo/End-Mult/Tile-Bonus sind jetzt global (gelten für alle Autos gleich).
# Tatsächliche Geschwindigkeit = Tempo-Zahl · SPEED_SCALE. EINZIGE Geschwindigkeitsquelle für
# alle Strecken (lap_time/lap_k/Position leiten sich daraus ab → keine Multi-Strecken-Probleme).
func get_car_speed(_i: int) -> float:
	return _effect_at("speed", get_upgrade_level("speed")) * SPEED_SCALE


func get_car_end_mult(_i: int) -> float:
	return _effect_at("endmult", get_upgrade_level("endmult"))


func get_car_tile_bonus(_i: int) -> float:
	return _effect_at("tilebonus", get_upgrade_level("tilebonus"))


# Gesamter Ertrag pro Rampe (Grundwert + additiver Anteil des Rampen-Upgrades). Für Anzeige.
func get_ramp_earn() -> float:
	return RAMP_BASE_EARN + get_effect("rampbonus")


# Sprung-Multiplikator für das übersprungene Kreuzungs-Feld: Basis ×2, je 5 Stufen des
# Rampen-Upgrades +0.2 (Stufe 5 → ×2.2, 10 → ×2.4 …).
func get_ramp_jump_mult(level: int = -1) -> float:
	if level < 0:
		level = get_upgrade_level("rampbonus")
	return RAMP_JUMP_BASE + 0.2 * float(level / 5)


# Speed-Boost einer Eisgerade in „Tempo-Stufen": Basis 1.0 + 0.5 je Upgrade-Stufe.
func get_ice_boost_levels(level: int = -1) -> float:
	if level < 0:
		level = get_upgrade_level("icebonus")
	return ICE_BASE_BOOST_LEVELS + ICE_PER_LEVEL_BOOST * level


# Absoluter Geschwindigkeits-Bonus (m/s), den eine Eisgerade auf jedes betroffene Folge-Feld
# legt: so viel schneller wie N Tempo-Stufen (1 Stufe = speed.per_level · SPEED_SCALE m/s),
# bewusst UNABHÄNGIG vom aktuellen Tempo. CarController addiert das auf die Segment-Tempi der
# nächsten get_ice_range() Felder → kürzere lap_time → mehr Runden (indirekt mehr Geld).
func get_ice_speed_bonus(level: int = -1) -> float:
	return get_ice_boost_levels(level) * float(UPGRADES["speed"]["per_level"]) * SPEED_SCALE


# Reichweite einer Eisgerade: 3 Folge-Felder, +1 je 5 Upgrade-Stufen (5→4, 10→5, 15→6).
func get_ice_range(level: int = -1) -> int:
	if level < 0:
		level = get_upgrade_level("icebonus")
	return ICE_BASE_RANGE + int(level / 5)


# ── Kleber-/Slime-Belag ─────────────────────────────────────────────────────────

# Geld je überfahrenem Kleber-Feld: Basis 50k, je Upgrade-Stufe prozentual mehr (×GLUE_EARN_GROWTH).
func get_glue_earn(level: int = -1) -> float:
	if level < 0:
		level = get_upgrade_level("gluebonus")
	return GLUE_BASE_EARN * pow(GLUE_EARN_GROWTH, level)


# Prozentualer Tempo-ABZUG auf Kleber-Feldern (positiv = so viel %-Punkte langsamer): Start
# GLUE_SLOW_PCT_BASE (90 %), je GLUE_SLOW_PCT_STEP Upgrade-Stufen −GLUE_SLOW_PCT_PER, nie unter
# GLUE_SLOW_PCT_MIN (20 %). Mehr Upgrade = weniger Bremse + mehr Geld.
func get_glue_slow_pct(level: int = -1) -> int:
	if level < 0:
		level = get_upgrade_level("gluebonus")
	return maxi(GLUE_SLOW_PCT_MIN, GLUE_SLOW_PCT_BASE - GLUE_SLOW_PCT_PER * int(level / GLUE_SLOW_PCT_STEP))


# Multiplikativer Tempo-FAKTOR auf Kleber-Feldern (1.0 = normal): 1 − Abzug%. Stufe 0 = 0.10 (10 %
# Tempo), Max-Stufe = 0.80. Wird in CarController auf das Segment-Tempo multipliziert (Gegenstück zum
# absoluten Eis-/Steilwand-Bonus). Unabhängig vom Grund-Tempo, daher auch bei schnellen Autos spürbar.
func get_glue_speed_factor(level: int = -1) -> float:
	return clampf(1.0 - float(get_glue_slow_pct(level)) / 100.0, 0.01, 1.0)


# Reichweite der Kleber-Bremse: nur das Feld selbst (j=0), + GLUE_BASE_RANGE (=0) Folge-Felder.
func get_glue_range(_level: int = -1) -> int:
	return GLUE_BASE_RANGE


# ── Steilwandkurve (Wall-Ride) ──────────────────────────────────────────────────

# Geld-Grundertrag der Steilwandkurve (am Einfahrt-Feld, additiv = Schritt 1 des Schneeballs):
# base 5000 + per_level je Upgrade-Stufe. Live über das wallbonus-Upgrade.
func get_wall_earn(level: int = -1) -> float:
	return get_effect("wallbonus", level)


# Speed-Boost einer Steilwandkurve in „Tempo-Stufen": Basis 2.0 + 0.5 je Upgrade-Stufe.
func get_wall_boost_levels(level: int = -1) -> float:
	if level < 0:
		level = get_upgrade_level("wallbonus")
	return WALL_BASE_BOOST_LEVELS + WALL_PER_LEVEL_BOOST * level


# Absoluter Geschwindigkeits-Bonus (m/s) auf die Folge-Felder beim Rausfahren – analog zur
# Eisgerade „so viel schneller wie N Tempo-Stufen", unabhängig vom aktuellen Tempo.
func get_wall_speed_bonus(level: int = -1) -> float:
	return get_wall_boost_levels(level) * float(UPGRADES["speed"]["per_level"]) * SPEED_SCALE


# Reichweite der Steilwandkurve ab dem Einfahrt-Feld (j=0). Basis 4 ⇒ Kurve (j=0/1) + 3 Felder
# außerhalb; +1 je 5 Upgrade-Stufen (5→5, 10→6, 15→7).
func get_wall_range(level: int = -1) -> int:
	if level < 0:
		level = get_upgrade_level("wallbonus")
	return WALL_BASE_RANGE + int(level / 5)


# Looping-Faktor F = 2.0 + 0.1·loopbonus-Level (Stufe 0 → 2.0, Stufe 30 → 5.0). Ganz normaler
# Multiplikator ×F (seit 2026-06-19 kein Schneeball mehr – der liegt auf der Rampe).
func get_loop_factor(level: int = -1) -> float:
	return get_effect("loopbonus", level)


# Portal-Ertrag (additiv, kein Multiplikator) am Eingangs-Portal: base 25k + per_level je Stufe.
func get_portal_earn(level: int = -1) -> float:
	return get_effect("portalbonus", level)


# Tribünen-Multiplikator für EIN Nachbarfeld: base 2.5 + 0.1·Level. Ab Stack 5 verdoppelt.
func get_stand_mult(stack: int = 1, level: int = -1) -> float:
	var m := get_effect("standbonus", level)
	if stack >= 5:
		m *= 2.0
	return m


# ── Prestige ────────────────────────────────────────────────────────────────────

func get_prestige_points() -> float:
	return prestige_points


# Debug/Cheat: Prestige-Punkte direkt gutschreiben (für Test-Buttons). Speichert + meldet Änderung.
func add_prestige_points(n: int) -> void:
	prestige_points += n
	_check_metric_achievements("prestige_points", float(prestige_points))   # „Besitze X ⭐"-Erfolge
	save_game()
	prestige_changed.emit()


func get_prestige_earned() -> float:
	return prestige_earned


func _prestige_def(id: String) -> Dictionary:
	return PRESTIGE_NODES.get(id, {})


func get_prestige_node_level(id: String) -> int:
	return int(prestige_nodes.get(id, 0))


func get_prestige_node_max(id: String) -> int:
	return int(_prestige_def(id).get("max_level", 0))


func is_prestige_node_maxed(id: String) -> bool:
	return get_prestige_node_level(id) >= get_prestige_node_max(id)


func is_prestige_node_coming(id: String) -> bool:
	return bool(_prestige_def(id).get("coming", false))


# Kosten der nächsten Stufe in ⭐ = round(base_cost · growth^level).
func get_prestige_node_cost(id: String) -> int:
	var d := _prestige_def(id)
	if d.is_empty():
		return 0
	var lvl := get_prestige_node_level(id)
	# Auto-Startlevel: eigene steile Kostenkurve (CAR_START_COSTS), siehe Konstante.
	if id == "car_start":
		return int(CAR_START_COSTS[clampi(lvl, 0, CAR_START_COSTS.size() - 1)])
	# Extra-Strecke: eigene Kostenkurve (TRACK_COSTS) – Strecke 3 ist mit 300k ⭐ ein echtes Ziel.
	if id == "track":
		return int(TRACK_COSTS[clampi(lvl, 0, TRACK_COSTS.size() - 1)])
	# Mehrstufige Wert-Knoten: feste, runde ⭐-Kurve (PRESTIGE_COST_TABLE) statt base_cost·growth^level.
	if PRESTIGE_COST_TABLE.has(id):
		var tbl: Array = PRESTIGE_COST_TABLE[id]
		return int(tbl[clampi(lvl, 0, tbl.size() - 1)])
	return int(round(float(d["base_cost"]) * pow(float(d["growth"]), lvl)))


func get_prestige_count() -> int:
	return prestige_count


# Position (1-basiert) in PRESTIGE_ORDER = Anzahl benötigter Prestiges, bis der Knoten erscheint.
func get_prestige_node_unlock_count(id: String) -> int:
	var pos := PRESTIGE_ORDER.find(id)
	return pos + 1 if pos >= 0 else 0


# Freigeschaltet, sobald man oft genug prestigt hat (positionsbasiert). Jedes Prestige öffnet genau
# den nächsten Knoten; kaufen muss man ihn weiterhin mit ⭐. Ersetzt die alte Prereq-Kette.
func is_prestige_node_unlocked(id: String) -> bool:
	var need := get_prestige_node_unlock_count(id)
	if need <= 0:
		return true
	return prestige_count >= need


# ── TEMP: Tab-Freischaltung ──────────────────────────────────────────────────────
# Prestige- und Werkstatt-Tab starten gesperrt und werden dauerhaft frei: Prestige sobald das GELD
# AUF DEM KONTO die Schwelle (= Gate) erreicht, Werkstatt sobald prestige_earned (seit letztem
# Prestige) seine Schwelle erreicht. Wird live aus _credit_laps und beim Laden geprüft. ENTFERNEN,
# sobald ein Erfolge-Tab existiert – die Freischaltung dann dort über den jeweiligen Erfolg auslösen.
func _check_tab_unlocks() -> void:
	var changed := false
	if not prestige_tab_unlocked and float(_currency) >= PRESTIGE_TAB_UNLOCK_EARN:
		prestige_tab_unlocked = true
		changed = true
	if not werkstatt_tab_unlocked and prestige_points >= WERKSTATT_TAB_UNLOCK_POINTS:
		werkstatt_tab_unlocked = true
		changed = true
	if changed:
		save_game()
		tab_unlock_changed.emit()


func is_prestige_tab_unlocked() -> bool:
	return prestige_tab_unlocked


func is_werkstatt_tab_unlocked() -> bool:
	return werkstatt_tab_unlocked


func can_buy_prestige_node(id: String) -> bool:
	return (not is_prestige_node_coming(id)
		and is_prestige_node_unlocked(id)
		and not is_prestige_node_maxed(id)
		and prestige_points >= get_prestige_node_cost(id))


func buy_prestige_node(id: String) -> bool:
	if not can_buy_prestige_node(id):
		return false
	prestige_points -= get_prestige_node_cost(id)
	prestige_nodes[id] = get_prestige_node_level(id) + 1
	save_game()
	prestige_changed.emit()
	# Grid/Head-Start-Knoten wirken sofort: gleiche Signal-Wege wie normale Upgrades nutzen.
	if id == "grid":
		emit_signal("upgrade_purchased", "grid_size")
	elif HEADSTART_NODES.has(id):
		# Floor live anwenden: für jede gemappte Upgrade-ID das Standard-Upgrade-Signal feuern
		# (z. B. car_start → "car_count" → Auto-Rebuild in Main).
		for uid in HEADSTART_NODES[id]:
			emit_signal("upgrade_purchased", uid)
	if id == "track":
		_check_metric_achievements("unlocked_tracks", float(get_unlocked_tracks()))   # Strecke 2/3-Erfolge
		# Geheimer Erfolg „Eigenbrötler": Strecke 3 frei, ohne je das Auto in der Werkstatt aufgewertet
		# zu haben (car_ascend wird beim ersten Aufstieg freigeschaltet → guter Indikator).
		if get_unlocked_tracks() >= 3 and not is_achievement_unlocked("car_ascend"):
			unlock_achievement("loner")
	return true


# Globaler Einkommens-Multiplikator: 1 + Stufe des „income"-Knotens (Lv1 ×2, Lv2 ×3, …).
func get_prestige_mult() -> float:
	return 1.0 + float(get_prestige_node_level("income"))


# Lesbarer Effekt-Text eines Knotens bei gegebener Stufe (für „von → zu" im Tech-Baum).
func prestige_node_effect_text(id: String, level: int) -> String:
	match id:
		"income":
			return "×%d" % (1 + level)
		"grid":
			var lv := clampi(level, 0, GRID_STEPS.size() - 1)
			return "%d×%d" % [GRID_STEPS[lv].x, GRID_STEPS[lv].y]
		"car_start":
			return (tr("+%d Auto") if level == 1 else tr("+%d Autos")) % level
		"track":
			var n := PRESTIGE_TRACK_BASE + level
			return (tr("%d Strecke") if n == 1 else tr("%d Strecken")) % n
		"earning":
			# Einmaliger Unlock der geldgetriebenen Punkte-Skalierung.
			return Icons.CHECK + " " + tr("freigeschaltet") if level >= 1 else Icons.LOCK + " " + tr("gesperrt")
		"car_points":
			# Einmaliger Unlock: zeigt den aktuell wirksamen ×-Faktor (= Auto-Upgrades + 1).
			if level >= 1:
				return "×%d" % (get_upgrade_level("car_count") + 1)
			return Icons.LOCK + " " + tr("gesperrt")
		"drive_time_inf":
			# Schaltet die Endlos-Stufe im Shop frei (Kauf dort macht erst endlos).
			return Icons.CHECK + " " + tr("freigeschaltet") if level >= 1 else Icons.LOCK + " " + tr("gesperrt")
		"points_mult":
			return tr("×%d Punkte") % int(pow(2.0, float(level)))
		"tilebonus_start", "speed_start", "endmult_start":
			return tr("Start Lv %d") % level
		"keep_unlocks":
			return Icons.CHECK + " " + tr("aktiv") if level >= 1 else tr("aus")
		"wall_unlock", "loop_unlock", "ramp_unlock", "portal_unlock", "stand_unlock":
			return Icons.CHECK + " " + tr("freigeschaltet") if level >= 1 else tr("gesperrt")
	return str(level)


# Punkte-Grundwert je „Stufe" mit „Break Prestige": die ersten vier Stufen sind fix [1,2,3,5], ab da
# wächst es je Stufe um ×1,5 (ausgehend vom letzten festen Wert 5). Eine Stufe = Geld ×10.
const PRESTIGE_POINT_STEPS := [1, 2, 3, 5]
const PRESTIGE_STAGE_GROWTH := 10.0   # Geld-Faktor je Punkte-Stufe (2 Mio.→St.0, 20 Mio.→1, 200 Mio.→2 …)

func _prestige_points_for_stage(stage: int) -> float:
	if stage < PRESTIGE_POINT_STEPS.size():
		return float(PRESTIGE_POINT_STEPS[stage])
	# Ab Stufe 4 vom letzten festen Wert (5) je Stufe ×1,5 weiter (float → bis ~1e308 ohne Überlauf).
	return floor(5.0 * pow(1.5, float(stage - 3)))


# Punkte, die ein Prestige JETZT einbringt: ohne „Break Prestige" genau 1; danach folgt der
# Grundwert der Stufenkurve [1,2,3,5]→×1,5, wobei jede Stufe ×10 Geld kostet (2 Mio.→1, 20 Mio.→2,
# 200 Mio.→3, 2 Mrd.→5 …). Final × Auto-Stufen-Bonus × 2^„points_mult". Gate: GELD ≥ K (2 Mio.).
func prestige_pending_points() -> float:
	if float(_currency) < PRESTIGE_K:
		return 0.0
	var pts := 1.0
	if get_prestige_node_level("earning") >= 1:
		# Stufe = wie oft das Geld die ×10-Schwelle ab K überschritten hat (einmalige Freischaltung).
		var ratio := float(_currency) / PRESTIGE_K
		var stage := 0
		var threshold := PRESTIGE_STAGE_GROWTH
		while ratio >= threshold:
			stage += 1
			threshold *= PRESTIGE_STAGE_GROWTH
		pts = _prestige_points_for_stage(stage)
	# „× Auto" (einmaliger Unlock): multipliziert die Punkte mit der Anzahl deiner Autos
	# = (gekaufte Auto-Upgrades + 1). Am Anfang max ×4 (3 Käufe + Standard-Auto).
	var car_mult := 1.0
	if get_prestige_node_level("car_points") >= 1:
		car_mult = float(get_upgrade_level("car_count") + 1)
	return floor(pts * car_mult * get_car_point_mult() * pow(2.0, float(get_prestige_node_level("points_mult"))))


# Füllgrad der unteren Prestige-Leiste [0,1). VOR dem ersten fälligen Punkt (Geld < K): Geld/K.
# DANACH: Fortschritt bis zur nächsten Punkte-Stufe. Die Stufen liegen an ×10-Grenzen → der
# Nachkomma-Anteil von log10(Geld/K) ist genau dieser Fortschritt.
func prestige_progress() -> float:
	var ratio := float(_currency) / PRESTIGE_K
	if ratio < 1.0:
		return clampf(ratio, 0.0, 1.0)
	# Ohne „Break Prestige" bleibt es bei 1 Punkt → Leiste voll (kein weiterer Fortschritt).
	if get_prestige_node_level("earning") < 1:
		return 1.0
	# Danach: Fortschritt bis zur nächsten Stufe (×10 Geld = +1 ganze log10-Stufe).
	var f := log(ratio) / log(PRESTIGE_STAGE_GROWTH)
	return clampf(f - floor(f), 0.0, 1.0)


func can_prestige() -> bool:
	return prestige_pending_points() >= 1.0


# Führt das Prestige aus: schreibt die fälligen Punkte gut und setzt ALLES außer dem
# Prestige-Block zurück (Geld, Upgrades, freigeschaltete Tiles, alle Strecken-Layouts).
# Gibt die erhaltenen Punkte zurück (0 = nicht möglich).
func do_prestige() -> float:
	var gained := prestige_pending_points()
	if gained < 1.0:
		return 0.0
	var was_first_prestige := prestige_count == 0
	prestige_points += gained
	prestige_count  += get_car_prestige_step()   # schaltet positionsbasiert den/die nächsten Knoten frei (×2 je Auto-Stufe)
	# Geheimer Erfolg „Sparfuchs": erstes Prestige, ohne je eine Kosmetik gekauft zu haben
	# (first_cosmetic wird beim ersten Kosmetik-Kauf freigeschaltet → guter Indikator).
	if was_first_prestige and not is_achievement_unlocked("first_cosmetic"):
		unlock_achievement("thrifty")
	# Erfolge: „X Prestiges durchgeführt" (count) und „Besitze X ⭐" (Punkte aus diesem Prestige).
	_check_metric_achievements("prestige_count", float(prestige_count))
	_check_metric_achievements("prestige_points", float(prestige_points))
	_check_tab_unlocks()   # Werkstatt-Tab schaltet ab 1 Mio. ⭐ frei (TEMP, siehe _check_tab_unlocks)
	# Harter Reset – nur prestige_points/prestige_nodes/prestige_count + Tab-Unlocks bleiben erhalten.
	_currency      = START_CURRENCY
	upgrade_levels = {}
	track          = []
	# „Unlocks behalten" (keep_unlocks): einmal gekaufte Tile-Freischaltungen – inklusive der im
	# Prestige-Baum gegateten Premium-Tiles (Rampe/Steilwand/Looping/Portal/Tribüne) – überstehen das
	# Prestige. Ohne den Knoten werden sie wie alles andere geleert und müssen erneut gekauft werden.
	if get_prestige_node_level("keep_unlocks") < 1:
		unlocked_tiles = {}
	prestige_earned = 0
	_active_track  = 0   # Strecke 2/3 sind wieder gesperrt → zurück auf Strecke 1
	_init_tracks()
	save_game()
	prestige_changed.emit()
	return gained


# ── Erfolge (Achievements) ────────────────────────────────────────────────────────

func is_achievement_unlocked(id: String) -> bool:
	return bool(unlocked_achievements.get(id, false))


# Geheimer Erfolg? (in der UI verdeckt als „???" mit Fragezeichen, bis freigeschaltet)
func is_achievement_secret(id: String) -> bool:
	return bool(ACHIEVEMENTS.get(id, {}).get("secret", false))


# Wurde dieser erreichte Erfolg bereits eingesammelt (Trophäen gutgeschrieben)?
func is_achievement_claimed(id: String) -> bool:
	return bool(claimed_achievements.get(id, false))


# Einsammelbar = Bedingung erfüllt (freigeschaltet) UND noch nicht eingesammelt.
func can_claim_achievement(id: String) -> bool:
	return ACHIEVEMENTS.has(id) and is_achievement_unlocked(id) and not is_achievement_claimed(id)


# Anzahl erreichter, aber noch NICHT eingesammelter Erfolge (für Badge/Hinweis in der UI).
func get_claimable_achievement_count() -> int:
	var n := 0
	for id in ACHIEVEMENTS:
		if can_claim_achievement(id):
			n += 1
	return n


# Sammelt die Trophäen-Belohnung eines erreichten, noch nicht eingesammelten Erfolgs ein.
# Schreibt die Trophäen gut, merkt den Erfolg als eingesammelt, persistiert sofort (slot-gebunden)
# und meldet es der UI (achievement_claimed). Nicht einsammelbare/bereits erledigte Erfolge: No-Op.
func claim_achievement(id: String) -> bool:
	if not can_claim_achievement(id):
		return false
	claimed_achievements[id] = true
	ach_currency += get_achievement_reward(id)   # Trophäen-Belohnung (datengetrieben je Erfolg)
	save_game()
	achievement_claimed.emit(id)
	# Geheimer Meta-Erfolg „Komplettist": sobald ALLE regulären Erfolge eingesammelt sind.
	if _all_regular_achievements_claimed():
		unlock_achievement("completionist")
	return true


# Sind alle regulären (nicht-geheimen) Erfolge bereits eingesammelt? (Bedingung für „Komplettist")
func _all_regular_achievements_claimed() -> bool:
	for id in ACHIEVEMENT_ORDER:
		if not is_achievement_claimed(id):
			return false
	return true


# Trophäen-Stand (Erfolgs-Währung, nur Garage). 100 je freigeschaltetem Erfolg.
func get_ach_currency() -> int:
	return ach_currency


# Debug/Cheat: Trophäen (Erfolgs-Währung) direkt gutschreiben (Cheat-Button). Speichert sofort.
func add_ach_currency(n: int) -> void:
	ach_currency += n
	save_game()


func get_achievement_count() -> int:
	return ACHIEVEMENTS.size()


func get_unlocked_achievement_count() -> int:
	var n := 0
	for id in ACHIEVEMENTS:
		if is_achievement_unlocked(id):
			n += 1
	return n


# Schaltet einen Erfolg frei (Bedingung erfüllt, idempotent). Schreibt die Trophäen NICHT gut –
# das passiert erst beim manuellen Einsammeln (claim_achievement). Speichert sofort (slot-gebunden)
# und meldet die Änderung, damit Erfolge-Tab/HUD sie live anzeigen. Unbekannte/erledigte: No-Op.
func unlock_achievement(id: String) -> void:
	if not ACHIEVEMENTS.has(id) or is_achievement_unlocked(id):
		return
	unlocked_achievements[id] = true
	save_game()
	achievement_unlocked.emit(id)


# Trophäen-Belohnung eines Erfolgs. Aktuell für alle gleich (ACH_REWARD); ein optionales Feld
# "reward" je Eintrag in ACHIEVEMENTS überschreibt das pro Erfolg (für künftig variable Belohnungen).
func get_achievement_reward(id: String) -> int:
	return int(ACHIEVEMENTS.get(id, {}).get("reward", ACH_REWARD))


# Prüft alle schwellenbasierten Erfolge einer Metrik gegen den aktuellen Wert und schaltet die
# erreichten frei. Wird aus den jeweiligen Wertänderungen aufgerufen (Geld/Punkte/Prestige/Runde).
func _check_metric_achievements(metric: String, value: float) -> void:
	for id in ACHIEVEMENTS:
		var d: Dictionary = ACHIEVEMENTS[id]
		if String(d.get("metric", "")) == metric and not is_achievement_unlocked(id):
			if value >= float(d.get("target", 0.0)):
				unlock_achievement(id)


# ── Bonusfelder ─────────────────────────────────────────────────────────────────

# Anzahl Felder eines Bonus-Typs = Upgrade-Level (0..3). kind ∈ {plus5, plus10, mult15}.
func get_bonus_count(kind: String) -> int:
	return get_upgrade_level("bonus_" + kind)


func is_bonus_unlocked(kind: String) -> bool:
	return get_bonus_count(kind) >= 1


# Plan der zu platzierenden Bonusfelder: jede Sorte so oft wie ihr Level.
func get_bonus_field_plan() -> Array:
	var out: Array = []
	for _i in range(get_bonus_count("plus5")):
		out.append({"label": "+5",   "points": 5.0,  "mult": 1.0})
	for _i in range(get_bonus_count("plus10")):
		out.append({"label": "+10",  "points": 10.0, "mult": 1.0})
	for _i in range(get_bonus_count("mult15")):
		out.append({"label": "×1.5", "points": 0.0,  "mult": 1.5})
	return out


# ── Auto-Lackierung (Kosmetik) ───────────────────────────────────────────────────

func is_car_paint_on() -> bool:
	return car_paint_on


func get_car_paint_color() -> Color:
	return car_paint_color


# Setzt die Lackierung. on=false → Originaltextur (color wird ignoriert). Persistiert + Live-Update.
func set_car_paint(on: bool, color: Color = Color(0.85, 0.15, 0.12)) -> void:
	car_paint_on = on
	if on:
		car_paint_color = color
	save_game()
	car_paint_changed.emit()


# Muster über die Lack-Maske (0 = keins, 1 = Streifen). Nutzt denselben Live-Update-Signalweg.
func get_car_pattern() -> int:
	return car_pattern


func get_car_pattern_color() -> Color:
	return car_pattern_color


func set_car_pattern(idx: int) -> void:
	car_pattern = idx
	save_game()
	car_paint_changed.emit()


# Muster-Farbe (Farbe der Streifen/Punkte etc. über der Lackmaske). Wählbar aus den freigeschalteten
# Lackfarben (siehe Garage), damit ein Muster auch auf gleichfarbigem Lack sichtbar bleibt – z. B.
# weißes Muster auf schwarzem Auto. Nutzt denselben Live-Update-Signalweg wie set_car_pattern.
func set_car_pattern_color(col: Color) -> void:
	car_pattern_color = col
	save_game()
	car_paint_changed.emit()


# ── Kosmetik-Freischaltung (mit Trophäen) ─────────────────────────────────────────
# Lackfarben werden über ihren Hex-Wert identifiziert (UI-unabhängig, stabil bei Umsortierung).

func _paint_key(col: Color) -> String:
	return col.to_html(false)


# Eine Lackfarbe ist nutzbar, wenn sie gekauft wurde. „Original" (kein Color) gilt separat als gratis.
func is_paint_unlocked(col: Color) -> bool:
	return bool(unlocked_paints.get(_paint_key(col), false))


# Muster „Keins" (0) ist immer frei; alle anderen müssen gekauft werden.
func is_pattern_unlocked(idx: int) -> bool:
	return idx == 0 or bool(unlocked_patterns.get(idx, false))


# Kauft eine Lackfarbe für COSMETIC_COST Trophäen. Gibt true zurück, wenn sie danach freigeschaltet
# ist (bereits gekauft → true ohne Abbuchung, zu wenig Trophäen → false).
func buy_paint(col: Color) -> bool:
	var k := _paint_key(col)
	if bool(unlocked_paints.get(k, false)):
		return true
	if ach_currency < COSMETIC_COST:
		return false
	ach_currency -= COSMETIC_COST
	unlocked_paints[k] = true
	save_game()
	return true


# Kauft ein Muster für COSMETIC_COST Trophäen (analog zu buy_paint).
func buy_pattern(idx: int) -> bool:
	if is_pattern_unlocked(idx):
		return true
	if ach_currency < COSMETIC_COST:
		return false
	ach_currency -= COSMETIC_COST
	unlocked_patterns[idx] = true
	save_game()
	return true


# ── Persistenz ──────────────────────────────────────────────────────────────────

# Strecke (Grid-State) merken – wird vom 2D-Bauplan bei Änderungen gesetzt.
func save_track(state: Array) -> void:
	track = state
	save_game()


func get_track() -> Array:
	return track


func has_track() -> bool:
	return not track.is_empty()


# var_to_str/str_to_var statt JSON: erhält Typen exakt (z. B. int-Rotationen).
func save_game() -> void:
	save_game_to_slot(_current_slot)


func save_game_to_slot(slot: int) -> void:
	var f = FileAccess.open(get_save_path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("Speichern fehlgeschlagen: " + get_save_path(slot))
		return
	# Track-Grids serialisieren
	var track_grids: Array = []
	for i in TRACK_COUNT:
		track_grids.append(_tracks[i]["grid"] if i < _tracks.size() else [])
	f.store_string(var_to_str({
		"currency":    _currency,
		"upgrades":    upgrade_levels,
		"track":       track,
		"track_grids": track_grids,
		"unlocked":    unlocked_tiles,
		"achievements": unlocked_achievements,
		"claimed_achievements": claimed_achievements,
		"ach_currency": ach_currency,
		"prestige_points": prestige_points,
		"prestige_earned": prestige_earned,
		"prestige_nodes":  prestige_nodes,
		"prestige_count":  prestige_count,
		"prestige_tab_unlocked":  prestige_tab_unlocked,   # TEMP (siehe _check_tab_unlocks)
		"werkstatt_tab_unlocked": werkstatt_tab_unlocked,  # TEMP (siehe _check_tab_unlocks)
		"total_playtime":  total_playtime,
		"car_paint_on":    car_paint_on,
		"car_paint_color": car_paint_color,
		"car_pattern":     car_pattern,
		"car_pattern_color": car_pattern_color,
		"unlocked_paints":   unlocked_paints,
		"unlocked_patterns": unlocked_patterns,
		"car_tier":        car_tier,
		"super_car_count": super_car_count,
		"total_tiles_placed": total_tiles_placed,
		"motorhaube_unlocked":   motorhaube_unlocked,
		"motorhaube_grid_level": motorhaube_grid_level,
		"motorhaube_items":      motorhaube_items,
		"timestamp":   Time.get_datetime_string_from_system(false, true),
		"name":        _slot_name,
	}))
	f.close()


func load_game() -> void:
	load_game_from_slot(_current_slot)


func load_game_from_slot(slot: int) -> void:
	_current_slot = slot
	# Erst auf Standardwerte zurücksetzen, damit KEIN Zustand (z. B. freigeschaltete
	# Tiles) vom vorher geladenen Slot übrig bleibt – auch wenn die Datei fehlt/defekt ist.
	_reset_state_to_defaults()

	var path = get_save_path(slot)
	if FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.READ)
		if f != null:
			var txt = f.get_as_text()
			f.close()
			var data = str_to_var(txt)
			if typeof(data) == TYPE_DICTIONARY:
				_currency      = float(data.get("currency", START_CURRENCY))
				var ups        = data.get("upgrades", {})
				upgrade_levels = ups.duplicate() if typeof(ups) == TYPE_DICTIONARY else {}
				var tr         = data.get("track", [])
				track          = tr if typeof(tr) == TYPE_ARRAY else []
				var unl        = data.get("unlocked", {})
				unlocked_tiles = unl.duplicate() if typeof(unl) == TYPE_DICTIONARY else {}
				var ach        = data.get("achievements", {})
				unlocked_achievements = ach.duplicate() if typeof(ach) == TYPE_DICTIONARY else {}
				# Eingesammelte Erfolge. Alt-Saves (vor dem Einsammel-System) kennen den Schlüssel nicht –
				# dort wurden die Trophäen früher automatisch gutgeschrieben, also gelten alle bereits
				# erreichten Erfolge als eingesammelt (verhindert doppeltes Einsammeln derselben Trophäen).
				if data.has("claimed_achievements"):
					var clm = data.get("claimed_achievements", {})
					claimed_achievements = clm.duplicate() if typeof(clm) == TYPE_DICTIONARY else {}
				else:
					claimed_achievements = unlocked_achievements.duplicate()
				ach_currency   = int(data.get("ach_currency", 0))
				prestige_points = float(data.get("prestige_points", 0))
				prestige_earned = float(data.get("prestige_earned", 0))
				var pn         = data.get("prestige_nodes", {})
				prestige_nodes = pn.duplicate() if typeof(pn) == TYPE_DICTIONARY else {}
				_migrate_prestige_nodes()   # Alt-Knoten umbenennen / entfernte Knoten erstatten
				# Alt-Save ohne prestige_count: aus den bereits gekauften Knoten ableiten, damit
				# sie weiterhin freigeschaltet bleiben (höchste belegte Position).
				prestige_count = int(data.get("prestige_count", _infer_prestige_count()))
				prestige_tab_unlocked  = bool(data.get("prestige_tab_unlocked", false))   # TEMP
				werkstatt_tab_unlocked = bool(data.get("werkstatt_tab_unlocked", false))  # TEMP
				total_playtime = float(data.get("total_playtime", 0.0))
				car_paint_on   = bool(data.get("car_paint_on", false))
				var cpc        = data.get("car_paint_color", car_paint_color)
				car_paint_color = cpc if typeof(cpc) == TYPE_COLOR else car_paint_color
				car_pattern    = int(data.get("car_pattern", 0))
				var cptc       = data.get("car_pattern_color", car_pattern_color)
				car_pattern_color = cptc if typeof(cptc) == TYPE_COLOR else car_pattern_color
				var up         = data.get("unlocked_paints", {})
				unlocked_paints = up.duplicate() if typeof(up) == TYPE_DICTIONARY else {}
				var upat       = data.get("unlocked_patterns", {})
				unlocked_patterns = upat.duplicate() if typeof(upat) == TYPE_DICTIONARY else {}
				car_tier       = int(data.get("car_tier", 0))
				# Migration: alter Bool-Unlock (super_car_on) → 1 Super-Auto.
				super_car_count = int(data.get("super_car_count", 1 if bool(data.get("super_car_on", false)) else 0))
				total_tiles_placed = int(data.get("total_tiles_placed", 0))
				motorhaube_unlocked   = bool(data.get("motorhaube_unlocked", false))
				motorhaube_grid_level = int(data.get("motorhaube_grid_level", 0))
				var mhi        = data.get("motorhaube_items", [])
				motorhaube_items = mhi.duplicate(true) if typeof(mhi) == TYPE_ARRAY else []
				_slot_name     = String(data.get("name", ""))
				# Multi-Track-Grids laden
				var tg = data.get("track_grids", [])
				if typeof(tg) == TYPE_ARRAY:
					for i in min(tg.size(), TRACK_COUNT):
						if typeof(tg[i]) == TYPE_ARRAY:
							_tracks[i]["grid"] = tg[i]
				elif track.size() > 0:
					# Rückwärtskompatibilität: alten track-State in Track 0 laden
					_tracks[0]["grid"] = track

	_check_tab_unlocks()   # TEMP: bei bereits erreichter Schwelle die Tabs sofort entsperren
	# Schwellen-Erfolge rückwirkend prüfen: bereits erfüllte Werte (Geld/Punkte/Prestige-Anzahl)
	# eines geladenen Profils sofort als erledigt markieren (auch für Alt-Saves vor diesem Feature).
	_check_metric_achievements("currency", float(_currency))
	_check_metric_achievements("prestige_points", float(prestige_points))
	_check_metric_achievements("prestige_count", float(prestige_count))
	_check_metric_achievements("unlocked_tracks", float(get_unlocked_tracks()))
	# Geheimen Meta-Erfolg „Komplettist" rückwirkend prüfen (Alt-Saves, die schon alles eingesammelt haben).
	if _all_regular_achievements_claimed():
		unlock_achievement("completionist")
	slot_changed.emit(slot)


# Migration des Prestige-Baums beim Laden (Überarbeitung 2026-06-18):
#  1) altes "car" (Extra-Auto) → "car_start" (Auto-Startlevel, gleiche Semantik).
#  2) entfernte Knoten (points2/points3/free_roads/scaling): bereits ausgegebene ⭐ kulant
#     zurückerstatten und den Knoten löschen, damit kein toter Eintrag im Baum verbleibt.
func _migrate_prestige_nodes() -> void:
	if typeof(prestige_nodes) != TYPE_DICTIONARY:
		prestige_nodes = {}
		return
	if prestige_nodes.has("car"):
		var car_lv := int(prestige_nodes["car"])
		prestige_nodes["car_start"] = maxi(int(prestige_nodes.get("car_start", 0)), car_lv)
		prestige_nodes.erase("car")
	var removed := {
		"points2":    {"base_cost": 1, "growth": 1.0},
		"points3":    {"base_cost": 3, "growth": 1.0},
		"free_roads": {"base_cost": 5, "growth": 2.0},
		"scaling":    {"base_cost": 5, "growth": 1.0},
	}
	for nid in removed:
		if prestige_nodes.has(nid):
			var lv := int(prestige_nodes[nid])
			var d: Dictionary = removed[nid]
			for i in lv:
				prestige_points += int(round(float(d["base_cost"]) * pow(float(d["growth"]), i)))
			prestige_nodes.erase(nid)


# Migration für Alt-Saves ohne prestige_count: so viele Prestiges annehmen, dass bereits gekaufte
# Knoten weiterhin freigeschaltet bleiben (höchste belegte Position in PRESTIGE_ORDER).
func _infer_prestige_count() -> int:
	var pc := 0
	for nid in prestige_nodes:
		if int(prestige_nodes[nid]) > 0:
			pc = maxi(pc, get_prestige_node_unlock_count(nid))
	return pc


# Setzt ALLEN slot-gebundenen Zustand auf Werkseinstellungen. EINZIGE Quelle, damit
# load_game_from_slot (Defaults vor dem Laden) und reset_slot (Neues Spiel) garantiert dasselbe
# zurücksetzen → keine Profil-Leaks. JEDER neue persistente Zustand (Upgrade, Freischaltung,
# Kosmetik, Auto-Tier, Prestige …) MUSS hier zurückgesetzt werden, sonst sickert er in andere
# Profile durch. _current_slot/Datei-IO setzt der Aufrufer.
func _reset_state_to_defaults() -> void:
	_currency       = START_CURRENCY
	upgrade_levels  = {}
	track           = []
	unlocked_tiles  = {}
	unlocked_achievements = {}   # Erfolge sind PROFIL-gebunden → bei Slot-Wechsel/Reset leeren
	claimed_achievements  = {}
	ach_currency    = 0
	prestige_points = 0.0
	prestige_earned = 0.0
	prestige_nodes  = {}
	prestige_count  = 0
	prestige_tab_unlocked  = false
	werkstatt_tab_unlocked = false
	total_playtime  = 0.0
	car_paint_on    = false
	car_paint_color = Color(0.85, 0.15, 0.12)
	car_pattern     = 0
	car_pattern_color = Color(0.06, 0.06, 0.08)
	unlocked_paints   = {}   # gekaufte Kosmetik ist PROFIL-gebunden → bei Slot-Wechsel/Reset leeren
	unlocked_patterns = {}
	car_tier        = 0   # Werkstatt-Auto („2. Auto") ist PROFIL-gebunden
	super_car_count = 0
	total_tiles_placed = 0
	motorhaube_unlocked   = false
	motorhaube_grid_level = 0
	motorhaube_items      = []
	_slot_name      = ""
	_init_tracks()


func reset_slot(slot: int) -> void:
	_current_slot   = slot
	_reset_state_to_defaults()
	save_game_to_slot(slot)
	slot_changed.emit(slot)


func rename_slot(slot: int, new_name: String) -> void:
	var data: Dictionary
	if slot_exists(slot):
		var f = FileAccess.open(get_save_path(slot), FileAccess.READ)
		if f == null:
			return
		var parsed = str_to_var(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			return
		data = parsed
	else:
		# Slot existiert noch nicht (z. B. direkt nach dem Löschen): frisches
		# Standard-Profil anlegen, damit der Name sofort gespeichert wird. Der
		# nächste Spielstart lädt dieses Profil dann (statt es neu zu resetten)
		# und behält den Namen – ohne den aktuell geladenen Zustand anzutasten.
		data = {
			"currency":  START_CURRENCY,
			"timestamp": Time.get_datetime_string_from_system(false, true),
		}
	data["name"] = new_name
	var fw = FileAccess.open(get_save_path(slot), FileAccess.WRITE)
	if fw == null:
		return
	fw.store_string(var_to_str(data))
	fw.close()
	if slot == _current_slot:
		_slot_name = new_name


func delete_slot(slot: int) -> void:
	if not slot_exists(slot):
		return
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(get_save_path(slot).get_file())


func reset() -> void:
	reset_slot(_current_slot)
