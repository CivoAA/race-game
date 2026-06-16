extends RefCounted
class_name MaterialUtil
## Hilfsfunktionen rund um 3D-Materialien.

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
