extends CanvasLayer
## Persistente obere Leiste: Track-Tabs, Währung, 2D/3D-Toggle, Baumodus, Shop.
## Autoload "GameHUD" (layer 20, immer sichtbar).

const TRACK_COUNT  = 3
const BAR_H        = 50
const VIEWPORT_W   = 960
const VIEWPORT_H   = 540

const C_BG         := Color(0.10, 0.11, 0.16)
const C_SURFACE    := Color(0.17, 0.19, 0.26)
const C_SURFACE_HI := Color(0.22, 0.25, 0.34)
const C_ACCENT     := Color(1.00, 0.52, 0.05)
const C_ACCENT_MU  := Color(0.22, 0.30, 0.50)
const C_ACCENT_RD  := Color(0.80, 0.18, 0.12)
const C_TEXT       := Color(0.93, 0.95, 1.00)
const C_TEXT_DIM   := Color(0.50, 0.56, 0.70)
const C_LINE       := Color(0.21, 0.24, 0.34)
const C_RUN_ON     := Color(0.25, 0.90, 0.45)
const C_RUN_OFF    := Color(0.32, 0.36, 0.50)

# Rechter Block – von rechts nach links:
# Der Bauen-Button ist aus der Top-Nav entfernt (jetzt Hammer-Button unten links in Main.gd).
# Dadurch wird Platz frei für ein großes, auffälliges Upgrade-Center.
const R_PAD      = 8
const UC_W       = 196   # Upgrade-Center (großer, beschrifteter Button)
const UC_H       = 40
const VIEW_W     = 42
const BTN_GAP    = 4
const BTN_H      = 34
const BTN_Y      = (BAR_H - BTN_H) / 2
const UC_Y       = (BAR_H - UC_H) / 2

# Berechnete x-Positionen (von rechts nach links)
const UC_X    = VIEWPORT_W - R_PAD - UC_W                         # 756
const V3D_X   = UC_X - BTN_GAP - VIEW_W                           # 710
const V2D_X   = V3D_X - BTN_GAP - VIEW_W                          # 664

# Tab-Block (links)
const TAB_W   = 108
const TAB_H   = 36
const TAB_Y   = (BAR_H - TAB_H) / 2
const TAB_GAP = 4
const TAB_X0  = 8

var _active_tab:   int  = 0
var _build_active: bool = false
var _is_3d_view:   bool = false
# Ansicht je Strecke: true = 3D-Fahrt, false = 2D-Bauplan. Bleibt über Szenenwechsel
# erhalten (GameHUD ist Autoload), damit Strecken gleichzeitig in verschiedenen Ansichten
# sein können. _is_3d_view spiegelt immer den Modus der gerade gezeigten Strecke (_active_tab).
var _track_view_3d: Array = []

var _tab_btns:     Array[Button]    = []
var _run_dots:     Array[ColorRect] = []
var _currency_lbl: Label            = null
var _view_2d_btn:  Button           = null
var _view_3d_btn:  Button           = null
var _shop_btn:     Button           = null
var _endless_btn:  Button           = null

signal tab_changed(idx: int)
signal build_mode_toggled(active: bool)
signal view_changed_to_3d()
signal view_changed_to_2d()
signal shop_requested()


func _ready() -> void:
	layer = 20
	_track_view_3d.resize(TRACK_COUNT)
	_track_view_3d.fill(false)
	_build_bar()
	# Runden-Gutschrift (Auto über die Startlinie) – auch im 2D-Hintergrund den "+X"-Effekt zeigen.
	Economy.lap_credited.connect(_on_lap_credited)


func _on_lap_credited(_track_idx: int, amount: int) -> void:
	gain_currency(amount)


func _build_bar() -> void:
	# Hintergrund
	var bg := ColorRect.new()
	bg.position = Vector2(0, 0)
	bg.size     = Vector2(VIEWPORT_W, BAR_H)
	bg.color    = C_BG
	add_child(bg)

	var line := ColorRect.new()
	line.position = Vector2(0, BAR_H - 1)
	line.size     = Vector2(VIEWPORT_W, 1)
	line.color    = C_LINE
	add_child(line)

	# Tabs (links)
	for i in TRACK_COUNT:
		var btn := Button.new()
		btn.position = Vector2(TAB_X0 + i * (TAB_W + TAB_GAP), TAB_Y)
		btn.size     = Vector2(TAB_W, TAB_H)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_tab_btn(btn, i == 0)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		add_child(btn)
		_tab_btns.append(btn)

		var dot := ColorRect.new()
		dot.size     = Vector2(7, 7)
		dot.position = btn.position + Vector2(TAB_W - 10, 6)
		dot.color    = C_RUN_OFF
		add_child(dot)
		_run_dots.append(dot)

	# Währung (Mitte)
	_currency_lbl = Label.new()
	_currency_lbl.position = Vector2(VIEWPORT_W / 2.0 - 100, 0)
	_currency_lbl.size     = Vector2(200, BAR_H)
	_currency_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_currency_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_currency_lbl.add_theme_font_size_override("font_size", 18)
	_currency_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22))
	_currency_lbl.add_theme_constant_override("outline_size", 3)
	_currency_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	add_child(_currency_lbl)

	# Rechter Block: Upgrade-Center (2D/3D-Umschaltung erfolgt jetzt über den
	# "Fahren!/3D"-Button im Run-Bar bzw. den 2D-Toggle in der 3D-Ansicht).
	_shop_btn = _make_uc_btn("UPGRADE-CENTER", Vector2(UC_X, UC_Y), UC_W, UC_H)
	_shop_btn.pressed.connect(_on_shop_pressed)
	add_child(_shop_btn)

	# Debug-Button: +1.000.000 Gold (rechts neben Währungsanzeige)
	var debug_btn := _make_btn("+1M", Vector2(582, BTN_Y), 34, BTN_H)
	debug_btn.pressed.connect(func(): Economy.add(1_000_000))
	add_child(debug_btn)

	# Endlos-Modus-Toggle (links neben Währungsanzeige)
	_endless_btn = _make_btn("∞", Vector2(344, BTN_Y), 34, BTN_H)
	_endless_btn.pressed.connect(_on_endless_toggled)
	add_child(_endless_btn)
	_refresh_endless_btn()

	_refresh_tabs()
	_refresh_view_buttons()


func _make_btn(txt: String, pos: Vector2, w: float, h: float) -> Button:
	var btn := Button.new()
	btn.text     = txt
	btn.position = pos
	btn.size     = Vector2(w, h)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",  _sb(C_SURFACE,    C_ACCENT_MU))
	btn.add_theme_stylebox_override("hover",   _sb(C_SURFACE_HI, C_ACCENT))
	btn.add_theme_stylebox_override("pressed", _sb(C_SURFACE,    C_ACCENT))
	btn.add_theme_stylebox_override("focus",   _sb(C_SURFACE,    C_ACCENT_MU))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 12)
	return btn


# Dezenter Upgrade-Center-Button: fügt sich in die Bar-Hintergrundfarbe ein,
# nur orange Schrift und ein schmaler Akzentrahmen heben ihn hervor (kein Icon).
func _make_uc_btn(txt: String, pos: Vector2, w: float, h: float) -> Button:
	var btn := Button.new()
	btn.text     = txt
	btn.position = pos
	btn.size     = Vector2(w, h)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal",  _uc_sb(C_BG,         C_ACCENT))
	btn.add_theme_stylebox_override("hover",   _uc_sb(C_SURFACE,    C_ACCENT))
	btn.add_theme_stylebox_override("pressed", _uc_sb(C_SURFACE_HI, C_ACCENT))
	btn.add_theme_stylebox_override("focus",   _uc_sb(C_BG,         C_ACCENT))
	btn.add_theme_color_override("font_color",       C_ACCENT)
	btn.add_theme_color_override("font_hover_color", C_ACCENT.lightened(0.2))
	btn.add_theme_font_size_override("font_size", 14)
	return btn


func _uc_sb(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(5)
	sb.content_margin_left   = 8
	sb.content_margin_right  = 8
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	return sb


func _sb(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_bottom = 2
	sb.border_color = border
	sb.set_corner_radius_all(3)
	sb.content_margin_left   = 5
	sb.content_margin_right  = 5
	sb.content_margin_top    = 3
	sb.content_margin_bottom = 3
	return sb


func _style_tab_btn(btn: Button, active: bool) -> void:
	var bg := C_SURFACE_HI if active else C_SURFACE
	var bc := C_ACCENT     if active else C_ACCENT_MU
	var sb := StyleBoxFlat.new()
	sb.bg_color            = bg
	sb.border_width_bottom = 3
	sb.border_color        = bc
	sb.set_corner_radius_all(3)
	sb.content_margin_left   = 8
	sb.content_margin_right  = 8
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", C_TEXT if active else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 12)
	# Disabled-Stil (ausgegraut in 3D-Modus)
	var sb_dis := StyleBoxFlat.new()
	sb_dis.bg_color            = C_SURFACE.darkened(0.15)
	sb_dis.border_width_bottom = 3
	sb_dis.border_color        = C_LINE
	sb_dis.set_corner_radius_all(3)
	sb_dis.content_margin_left   = 8
	sb_dis.content_margin_right  = 8
	sb_dis.content_margin_top    = 4
	sb_dis.content_margin_bottom = 4
	btn.add_theme_stylebox_override("disabled", sb_dis)
	btn.add_theme_color_override("font_disabled_color", Color(0.28, 0.31, 0.43))


func _refresh_tabs() -> void:
	for i in TRACK_COUNT:
		_tab_btns[i].text     = "Strecke %d" % (i + 1)
		_style_tab_btn(_tab_btns[i], i == _active_tab)
		# Tabs bleiben auch in der 3D-Ansicht aktiv – Streckenwechsel ist immer erlaubt.
		_tab_btns[i].disabled = false
		_run_dots[i].color    = C_RUN_ON if Economy.is_run_active(i) else C_RUN_OFF


func _refresh_view_buttons() -> void:
	# Die 2D/3D-Buttons wurden aus der Top-Nav entfernt; nichts mehr zu stylen.
	if _view_2d_btn == null or _view_3d_btn == null:
		return
	var sb_on := StyleBoxFlat.new()
	sb_on.bg_color            = C_SURFACE_HI
	sb_on.border_width_bottom = 2
	sb_on.border_color        = C_ACCENT
	sb_on.set_corner_radius_all(3)
	sb_on.content_margin_left = 5; sb_on.content_margin_right  = 5
	sb_on.content_margin_top  = 3; sb_on.content_margin_bottom = 3

	if _is_3d_view:
		_view_3d_btn.add_theme_stylebox_override("normal", sb_on)
		_view_3d_btn.add_theme_color_override("font_color", C_ACCENT)
		_view_2d_btn.add_theme_stylebox_override("normal", _sb(C_SURFACE, C_ACCENT_MU))
		_view_2d_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	else:
		_view_2d_btn.add_theme_stylebox_override("normal", sb_on)
		_view_2d_btn.add_theme_color_override("font_color", C_ACCENT)
		_view_3d_btn.add_theme_stylebox_override("normal", _sb(C_SURFACE, C_ACCENT_MU))
		_view_3d_btn.add_theme_color_override("font_color", C_TEXT_DIM)


func _process(_delta: float) -> void:
	# Im Hauptmenü ausblenden
	var scene := get_tree().current_scene
	var in_menu := scene != null and scene.name == "MainMenu"
	visible = not in_menu
	if in_menu:
		return

	if _currency_lbl != null:
		_currency_lbl.text = "💰  %s" % Economy.format_currency(Economy.get_currency())
	for i in TRACK_COUNT:
		if i < _run_dots.size():
			_run_dots[i].color = C_RUN_ON if Economy.is_run_active(i) else C_RUN_OFF


# ── Callbacks ──────────────────────────────────────────────────────────────────

func _on_tab_pressed(idx: int) -> void:
	if idx == _active_tab:
		return
	_active_tab   = idx
	_build_active = false
	# Die gezeigte Ansicht richtet sich nach dem gemerkten Modus der Zielstrecke.
	_is_3d_view   = is_track_3d(idx)
	Economy.set_active_track(idx)
	_refresh_tabs()
	_refresh_view_buttons()
	# Die jeweils geladene Szene (Main bzw. World3D) reagiert auf tab_changed und lädt
	# die zur Ansicht der Zielstrecke passende Szene.
	emit_signal("tab_changed", idx)


# Wird vom Hammer-Button in Main.gd aufgerufen (Baumodus an/aus).
func request_build_toggle() -> void:
	if _is_3d_view:
		return
	_build_active = not _build_active
	_refresh_view_buttons()
	emit_signal("build_mode_toggled", _build_active)


func _on_view_2d() -> void:
	if not _is_3d_view:
		return
	_is_3d_view = false
	_refresh_view_buttons()
	_refresh_tabs()
	emit_signal("view_changed_to_2d")


func _on_view_3d() -> void:
	if _is_3d_view:
		return
	_is_3d_view   = true
	_build_active = false
	_refresh_view_buttons()
	_refresh_tabs()
	emit_signal("view_changed_to_3d")


func _on_shop_pressed() -> void:
	emit_signal("shop_requested")


# ── Öffentliche API ────────────────────────────────────────────────────────────

func get_active_tab() -> int:
	return _active_tab


func set_view_3d(is3d: bool) -> void:
	_is_3d_view = is3d
	if is3d:
		_build_active = false
	_refresh_view_buttons()
	_refresh_tabs()


# ── Ansicht je Strecke ───────────────────────────────────────────────────────

func is_track_3d(idx: int) -> bool:
	return idx >= 0 and idx < _track_view_3d.size() and _track_view_3d[idx]


func set_track_3d(idx: int, val: bool) -> void:
	if idx >= 0 and idx < _track_view_3d.size():
		_track_view_3d[idx] = val
	if idx == _active_tab:
		_is_3d_view = val
	_refresh_view_buttons()
	_refresh_tabs()


# Lädt die 3D-Ansicht (World3D) der Strecke idx; die laufende Runde wird fortgesetzt.
# Einzige Stelle, die für einen Strecken-/Ansichtswechsel World3D lädt (von Main UND World3D
# beim Tab-Wechsel genutzt).
func goto_world3d(idx: int) -> void:
	set_track_3d(idx, true)
	var grid: Array = Economy.get_track_grid(idx)
	Engine.set_meta("active_track_idx",   idx)
	Engine.set_meta("resuming_run",       true)
	Engine.set_meta("pending_grid_state", grid)
	var world_scene = load(Paths.SCENE_WORLD3D)
	if world_scene:
		get_tree().change_scene_to_packed(world_scene)


func set_build_active(val: bool) -> void:
	_build_active = val
	_refresh_view_buttons()


func is_build_active() -> bool:
	return _build_active


func _on_endless_toggled() -> void:
	Economy.endless_mode = not Economy.endless_mode
	_refresh_endless_btn()


func _refresh_endless_btn() -> void:
	if _endless_btn == null:
		return
	if Economy.endless_mode:
		var sb := StyleBoxFlat.new()
		sb.bg_color            = C_SURFACE_HI
		sb.border_width_bottom = 2
		sb.border_color        = C_ACCENT
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 5; sb.content_margin_right  = 5
		sb.content_margin_top  = 3; sb.content_margin_bottom = 3
		_endless_btn.add_theme_stylebox_override("normal", sb)
		_endless_btn.add_theme_color_override("font_color", C_ACCENT)
	else:
		_endless_btn.add_theme_stylebox_override("normal", _sb(C_SURFACE, C_ACCENT_MU))
		_endless_btn.add_theme_color_override("font_color", C_TEXT_DIM)


func flash_currency() -> void:
	if _currency_lbl == null:
		return
	var tw := create_tween()
	tw.tween_property(_currency_lbl, "modulate", Color(1, 0.2, 0.2), 0.08)
	tw.tween_property(_currency_lbl, "modulate", Color(1, 1, 1), 0.30)


func gain_currency(amount: int) -> void:
	if amount <= 0 or _currency_lbl == null:
		return
	_currency_lbl.pivot_offset = _currency_lbl.size / 2.0
	var tw := create_tween()
	tw.tween_property(_currency_lbl, "scale", Vector2(1.22, 1.22), 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_currency_lbl, "modulate", Color(0.45, 1.0, 0.5), 0.10)
	tw.tween_property(_currency_lbl, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_currency_lbl, "modulate", Color(1, 1, 1), 0.25)

	var fl := Label.new()
	fl.text = "+%s 💰" % Economy.format_currency(amount)
	fl.position = Vector2(VIEWPORT_W / 2.0 - 60, BAR_H)
	fl.size     = Vector2(120, 26)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	fl.add_theme_font_size_override("font_size", 18)
	fl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	fl.add_theme_constant_override("outline_size", 3)
	fl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(fl)
	var t := create_tween()
	t.tween_property(fl, "position:y", float(BAR_H) - 20.0, 0.85) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(fl, "modulate:a", 0.0, 0.85)
	t.tween_callback(fl.queue_free)
