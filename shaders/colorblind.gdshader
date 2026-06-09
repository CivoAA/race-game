shader_type canvas_item;

// Vollbild-Korrektur für Rot-Grün-Sehschwäche (Deuteranopie). Liest die bereits
// gerenderte Szene und verschiebt die für Betroffene nicht unterscheidbaren
// Rot-/Grünanteile in wahrnehmbare Kanäle (klassische „Daltonisierung").
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec3 rgb = texture(screen_tex, SCREEN_UV).rgb;

	// RGB -> LMS (Zapfen-Antworten)
	float L = 17.8824    * rgb.r + 43.5161  * rgb.g + 4.11935 * rgb.b;
	float M = 3.45565    * rgb.r + 27.1554  * rgb.g + 3.86714 * rgb.b;
	float S = 0.0299566  * rgb.r + 0.184309 * rgb.g + 1.46709 * rgb.b;

	// Deuteranopie-Simulation: M-Zapfen aus L und S rekonstruiert.
	float Ms = 0.494207 * L + 1.24827 * S;

	// LMS(sim) -> RGB
	vec3 sim;
	sim.r =  0.0809444479   * L - 0.130504409   * Ms + 0.116721066  * S;
	sim.g = -0.0102485335   * L + 0.0540193266  * Ms - 0.113614708  * S;
	sim.b = -0.000365296938 * L - 0.00412161469 * Ms + 0.693511405  * S;

	// Differenz (verlorene Information) in sichtbare Kanäle umlegen.
	vec3 err = rgb - sim;
	vec3 corr;
	corr.r = 0.0;
	corr.g = 0.7 * err.r + err.g;
	corr.b = 0.7 * err.r + err.b;

	COLOR = vec4(clamp(rgb + corr, 0.0, 1.0), 1.0);
}
