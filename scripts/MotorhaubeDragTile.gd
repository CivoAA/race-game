extends Panel
## Eine ziehbare Kachel im Motorhaube-Tuning – sowohl ein Palette-Item (Vorlage) als auch ein
## bereits platziertes Item. Startet den Godot-eigenen Drag mit den Item-Daten; das Ablegen,
## Verschieben und Entfernen erledigt das MotorhaubeGrid (der Drop-Empfänger).
##
## drag_data: {"mh": true, "id": String, "size": Vector2i, "from_grid": bool, "index": int}
##   from_grid=false → neues Item aus der Palette; from_grid=true → platziertes Item (index).
## preview_color/preview_px: Aussehen der Drag-Vorschau (Platzhalter bis Pixel-Assets existieren).

var drag_data:     Dictionary = {}
var preview_color: Color      = Color.WHITE
var preview_px:    Vector2    = Vector2(64, 64)


func _get_drag_data(_pos: Vector2) -> Variant:
	if drag_data.is_empty():
		return null
	var prev := ColorRect.new()
	prev.color = Color(preview_color.r, preview_color.g, preview_color.b, 0.85)
	prev.size  = preview_px
	# Vorschau am Cursor zentrieren.
	var wrap := Control.new()
	wrap.add_child(prev)
	prev.position = -preview_px * 0.5
	set_drag_preview(wrap)
	return drag_data.duplicate(true)
