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

// Muster, das NUR ueber die gefaerbten (Masken-)Bereiche gelegt wird.
//   0 = keins, 1 = Streifen, 2 = Diagonale, 3 = Karo, 4 = Punkte, 5 = Verlauf.
// Solide Muster (1-4) zeigen pattern_color statt der Lackfarbe, der Hell-Dunkel-Verlauf bleibt.
// Der Verlauf (5) blendet weich von der gewaehlten Lackfarbe in pattern_color.
uniform int   pattern_mode  = 0;
uniform vec4  pattern_color : source_color = vec4(0.06, 0.06, 0.08, 1.0);
uniform float pattern_scale : hint_range(1.0, 80.0) = 28.0;
uniform float pattern_angle : hint_range(0.0, 3.1416) = 0.0;
// Lack an/aus: false -> Originalfarbe der Karosserie behalten, Muster trotzdem darueberlegen.
// So funktioniert die Standard-(Original-)Optik ebenfalls mit Mustern.
uniform bool  paint_on = true;

void fragment() {
	vec4 base = texture(albedo_tex, UV);
	float m = texture(mask_tex, UV).r;
	// Helligkeit/Verlauf der Original-Karosserie als Schattierung uebernehmen.
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float shade = clamp(lum * shade_gain, 0.0, 1.0);
	// Korpusfarbe: bei aktivem Lack die Lackfarbe, sonst die Originalpixel (Standardfarbe).
	vec3 body = paint_on ? (paint_color.rgb * shade) : base.rgb;
	// Musterfarbe in derselben Schattierung wie der Korpus.
	vec3 patt = pattern_color.rgb * shade;
	// Muster nur innerhalb der Karosserie (wird unten ohnehin per Maske begrenzt).
	if (pattern_mode == 1) {
		// Gerade Streifen entlang einer drehbaren Achse im UV-Raum.
		float coord = UV.x * cos(pattern_angle) + UV.y * sin(pattern_angle);
		float stripe = step(0.5, fract(coord * pattern_scale));
		body = mix(body, patt, stripe);
	} else if (pattern_mode == 2) {
		// Diagonale Streifen (45 Grad).
		float coord = UV.x + UV.y;
		float stripe = step(0.5, fract(coord * pattern_scale * 0.7));
		body = mix(body, patt, stripe);
	} else if (pattern_mode == 3) {
		// Schachbrett/Karo.
		float cx = step(0.5, fract(UV.x * pattern_scale * 0.5));
		float cy = step(0.5, fract(UV.y * pattern_scale * 0.5));
		body = mix(body, patt, abs(cx - cy));
	} else if (pattern_mode == 4) {
		// Punkte-Raster.
		vec2 g = fract(UV * pattern_scale * 0.55) - vec2(0.5);
		float dot_m = 1.0 - step(0.30, length(g));
		body = mix(body, patt, dot_m);
	} else if (pattern_mode == 5) {
		// Weicher Verlauf: helle Karosseriestellen gehen in pattern_color ueber, dunkle behalten
		// die gewaehlte Lackfarbe. shade variiert ueber den ganzen Korpus -> immer sichtbar
		// (UV.y deckt nur einen schmalen Atlas-Bereich ab und taugt dafuer nicht).
		float t = smoothstep(0.15, 0.95, shade);
		body = mix(body, patt, t);
	}
	// Nur dort umfaerben, wo die Maske rot ist; sonst Originalpixel behalten.
	ALBEDO = mix(base.rgb, body, m);
	METALLIC = metallic_v;
	ROUGHNESS = roughness_v;
}
