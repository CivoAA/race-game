shader_type spatial;
render_mode cull_back, unshaded;

// Lackierung + Muster für FLACHE Material-Farben (Blender-Testmodell, keine Albedo-/Maskentextur).
// Wird nur auf die Karosserie-Fläche gelegt; die Schattierung kommt aus dem Echtzeit-Licht.

// Grundfarbe der Karosserie (gewählte Lackfarbe oder die Originalfarbe, wenn kein Lack aktiv).
uniform vec4  body_color : source_color = vec4(0.10, 0.80, 0.10, 1.0);
// Muster: 0 = keins, 1 = Streifen, 2 = Diagonale, 3 = Karo, 4 = Punkte, 5 = Verlauf.
uniform int   pattern_mode  = 0;
uniform vec4  pattern_color : source_color = vec4(0.06, 0.06, 0.08, 1.0);
uniform float pattern_scale : hint_range(1.0, 80.0) = 28.0;
uniform float pattern_angle : hint_range(0.0, 3.1416) = 0.0;
// Material-Anmutung vom Originalmaterial übernommen.
uniform float metallic_v  : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_v : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec3 body = body_color.rgb;
	vec3 patt = pattern_color.rgb;
	if (pattern_mode == 1) {
		// Gerade Streifen entlang einer drehbaren Achse im UV-Raum.
		float coord = UV.x * cos(pattern_angle) + UV.y * sin(pattern_angle);
		body = mix(body, patt, step(0.5, fract(coord * pattern_scale)));
	} else if (pattern_mode == 2) {
		// Diagonale Streifen (45 Grad).
		body = mix(body, patt, step(0.5, fract((UV.x + UV.y) * pattern_scale * 0.7)));
	} else if (pattern_mode == 3) {
		// Schachbrett/Karo.
		float cx = step(0.5, fract(UV.x * pattern_scale * 0.5));
		float cy = step(0.5, fract(UV.y * pattern_scale * 0.5));
		body = mix(body, patt, abs(cx - cy));
	} else if (pattern_mode == 4) {
		// Punkte-Raster.
		vec2 g = fract(UV * pattern_scale * 0.55) - vec2(0.5);
		body = mix(body, patt, 1.0 - step(0.30, length(g)));
	} else if (pattern_mode == 5) {
		// Weicher Verlauf über die UV-Achse (flache Farbe hat keine Albedo-Helligkeit).
		body = mix(body, patt, smoothstep(0.05, 0.95, fract(UV.y)));
	}
	ALBEDO = body;
	METALLIC = metallic_v;
	ROUGHNESS = roughness_v;
}
