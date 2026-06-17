extends RefCounted
class_name MaterialUtil
## Hilfsfunktionen rund um 3D-Materialien.

# Gemeinsame Track-Atlas-Textur. Die Track-GLBs kommen OHNE Material, tragen aber die
# passenden UVs → diese eine Textur deckt alle Beläge ab. Einmal erzeugt und über
# material_override an allen materiallosen Meshes wiederverwendet (Strecke UND Shop-Vorschau).
static var _track_material: StandardMaterial3D = null

static func get_track_material() -> StandardMaterial3D:
	if _track_material == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(Paths.TEX_TRACK_ATLAS)
		mat.roughness = 0.9
		# Komplett unbeleuchtet (kein Licht/Schatten): Atlas-Farben kommen flach durch.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Harte Alpha-Kanten (Atlas hat transparente Bereiche) sauber ausstanzen.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		_track_material = mat
	return _track_material

# Legt die gemeinsame Atlas-Textur auf alle Meshes, die (noch) kein eigenes Material mit
# Albedo-Textur haben. Modelle mit eigenem Material bleiben unangetastet. Godot legt
# materiallosen glTF-Flächen ein leeres (weißes) Default-Material an → nicht auf null prüfen,
# sondern auf "hat keine eigene Albedo-Textur".
static func apply_track_texture(root: Node) -> void:
	if root == null:
		return
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var active := mi.get_active_material(si)
			var has_tex := active is BaseMaterial3D and (active as BaseMaterial3D).albedo_texture != null
			if not has_tex:
				mi.set_surface_override_material(si, get_track_material())

# Wandelt alle Alpha-BLEND-Materialien unter `root` in Alpha-SCISSOR um.
# Behebt die typischen Transparenz-Sortier-/Tiefenfehler bei Texturen mit Alpha-Kanal
# (harte Kanten wie Logos, Gitter, Blätter). Opake Materialien bleiben unberührt.
# Achtung: echte weiche Halbtransparenz (z. B. Glas) wird dadurch hart – solche
# Modelle hier NICHT durchschicken.
static func apply_alpha_scissor(root: Node, threshold: float = 0.5) -> void:
	if root == null:
		return
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var mat := mi.get_active_material(si)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				var m: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.alpha_scissor_threshold = threshold
				mi.set_surface_override_material(si, m)


# Schaltet alle Materialien unter `root` auf "unbeleuchtet" (Unshaded): kein Diffus/Specular,
# keine Licht- oder Schatten-Einflüsse – die Albedo-Farbe/-Textur kommt flach durch.
# StandardMaterial3D mit eigener Albedo-Textur (aus GLBs) wird dupliziert und überschrieben;
# bereits unshaded gesetzte (z. B. das gemeinsame Track-Material) werden übersprungen, damit die
# Material-Wiederverwendung erhalten bleibt. ShaderMaterials bleiben unangetastet – dort steuert
# der jeweilige Shader die Beleuchtung über `render_mode unshaded`.
static func apply_unshaded(root: Node) -> void:
	if root == null:
		return
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var mat := mi.get_active_material(si)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				var m: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mi.set_surface_override_material(si, m)


# Rendert alle Materialien unter `root` doppelseitig (Backface-Culling aus). Nötig für offene/dünne
# Geometrie wie das Portal-Tor: ohne das schaut man von hinten durch die Flächen hindurch.
# Materialien werden pro Surface dupliziert und überschrieben, damit nur dieser Teilbaum betroffen
# ist (das geteilte Track-Material bleibt für die übrige Strecke einseitig).
static func apply_double_sided(root: Node) -> void:
	if root == null:
		return
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var mat := mi.get_active_material(si)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_DISABLED:
				var m: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(si, m)
