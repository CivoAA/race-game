shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Originaltextur des Autos (Magenta-Karosserie + Rest des Atlas).
// filter_nearest -> gleiche pixelige/scharfe Kanten wie das Originalmaterial.
uniform sampler2D albedo_tex : source_color, filter_nearest;
// Maske: Rot-Kanal = umfaerbbar (Karosserie), Schwarz = unveraendert.
// filter_nearest -> harte Kanten, keine interpolierten Mischwerte an den Raendern.
uniform sampler2D mask_tex : hint_default_black, filter_nearest;
// Ziel-Lackfarbe.
uniform vec4 paint_color : source_color = vec4(0.85, 0.15, 0.12, 1.0);
// Verstaerkt die Helligkeit, damit die hellsten Karosserie-Stellen die volle
// Lackfarbe erreichen (Original-Magenta ist relativ dunkel).
uniform float shade_gain : hint_range(0.5, 3.0) = 1.9;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_v : hint_range(0.0, 1.0) = 0.40;

void fragment() {
	vec4 base = texture(albedo_tex, UV);
	float m = texture(mask_tex, UV).r;
	// Helligkeit/Verlauf der Original-Karosserie als Schattierung uebernehmen.
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	vec3 painted = paint_color.rgb * clamp(lum * shade_gain, 0.0, 1.0);
	// Nur dort umfaerben, wo die Maske rot ist; sonst Originalpixel behalten.
	ALBEDO = mix(base.rgb, painted, m);
	METALLIC = metallic_v;
	ROUGHNESS = roughness_v;
}
