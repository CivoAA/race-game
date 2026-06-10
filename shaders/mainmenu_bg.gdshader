shader_type canvas_item;

// Animierter Hauptmenü-Hintergrund (Design „Road Tycoon"):
// dunkler Radial-Verlauf, zwei sehr schwache driftende Glows, eine Perspektiv-Straße
// mit dünnen, klaren Fahrbahnrändern (Trapez) und einer dezenten, nach vorne fahrenden
// Mittellinie, die weich aus dem Horizont auftaucht – plus Vignette.
//
// WICHTIG – Seitenverhältnis: Das Fenster nutzt stretch/aspect = "expand", d. h. bei
// breiteren Fenstern wird mehr Breite sichtbar. Damit die Straße NICHT in die Breite
// gezogen wird, rechnen wir horizontal in „Höhen-Einheiten" (cx) relativ zur Bildmitte.
// So bleibt die Straße bei jeder Auflösung gleich breit und gleich dünn linienführend.
uniform vec2 resolution = vec2(960.0, 540.0);
// Vertikaler Start der Straße als UV-Anteil – wird auf die blaue Linie unter dem
// Titel gesetzt. Die Straße taucht GENAU hier auf und geht nie höher.
uniform float horizon : hint_range(0.0, 1.0) = 0.42;

const vec3 BG0       = vec3(0.149, 0.169, 0.204); // #262b34 oben mittig
const vec3 BG1       = vec3(0.106, 0.118, 0.141); // #1b1e24
const vec3 BG2       = vec3(0.075, 0.082, 0.098); // #131519 Rand
const vec3 ROAD_FAR  = vec3(0.052, 0.060, 0.075); // #0d0f13 Fahrbahn fern (sehr dunkel)
const vec3 ROAD_NEAR = vec3(0.082, 0.094, 0.116); // #15181d Fahrbahn nah
const vec3 GLOW_BLUE = vec3(0.37, 0.44, 1.00);
const vec3 GLOW_GRN  = vec3(0.27, 0.78, 0.43);
const vec3 DASH_COL  = vec3(0.808, 0.722, 0.463); // #ceb876
const vec3 LANE_COL  = vec3(0.62, 0.66, 0.74);    // #9fa8bd Fahrbahnrand

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float aspect = max(resolution.x / max(resolution.y, 1.0), 0.0001);

	// Horizontale Koordinate in Höhen-Einheiten: 0 = Mitte, unabhängig von der Breite.
	float cx = (uv.x - 0.5) * aspect;
	float adx = abs(cx);

	// ── Radial-Verlauf (Ursprung oben mittig) ──
	vec2 pr = vec2(cx, (uv.y - 0.06));
	float rg = clamp(length(pr) * 1.15, 0.0, 1.0);
	vec3 col = mix(BG0, BG1, smoothstep(0.0, 0.52, rg));
	col = mix(col, BG2, smoothstep(0.52, 1.0, rg));

	// ── Sehr schwache, driftende Glows ──
	vec2 g1 = vec2((0.40 + 0.05 * sin(t * 0.18) - 0.5) * aspect, 0.26 + 0.04 * cos(t * 0.15));
	col += GLOW_BLUE * 0.055 * smoothstep(0.50, 0.0, distance(vec2(cx, uv.y), g1));
	vec2 g2 = vec2((0.80 + 0.05 * sin(t * 0.13 + 1.7) - 0.5) * aspect, 0.96 + 0.04 * cos(t * 0.19));
	col += GLOW_GRN * 0.045 * smoothstep(0.50, 0.0, distance(vec2(cx, uv.y), g2));

	// ── Perspektiv-Straße (startet exakt an der blauen Linie) ──
	if (uv.y > horizon) {
		float ty = (uv.y - horizon) / (1.0 - horizon);   // 0 Horizont .. 1 vorne
		float persp = ty * ty * 0.55 + ty * 0.45;        // Perspektiv-Profil
		float roadHalf = mix(0.015, 0.58, persp);        // halbe Straßenbreite in Höhen-Einheiten
		float surfFade = smoothstep(0.0, 0.22, ty);      // Fahrbahn taucht weich auf

		// Fahrbahn – etwas dunkler als der Hintergrund (kein Aufhellen, kein Bloom)
		float surf = smoothstep(roadHalf + 0.02, roadHalf - 0.02, adx);
		vec3 roadCol = mix(ROAD_FAR, ROAD_NEAR, ty);
		col = mix(col, roadCol, surf * surfFade);

		// Fahrbahnränder = das prägende Trapez. Dünn & klar, perspektivisch leicht dicker.
		float lineW = mix(0.0014, 0.0042, ty);
		float edge = smoothstep(lineW, 0.0, abs(adx - roadHalf));
		col = mix(col, LANE_COL, edge * surfFade * 0.55);

		// Fahrende Mittellinie – blendet erst unter dem Horizont ein (kein Bloom)
		float dashFade = smoothstep(0.12, 0.55, ty);
		float z = (1.0 - ty) / max(ty, 0.04);
		float dashCoord = z * 3.2 + t * 2.0;
		float dash = smoothstep(0.46, 0.54, fract(dashCoord));
		float dashHalf = mix(0.003, 0.022, ty);
		float onDash = smoothstep(dashHalf, dashHalf - 0.007, adx);
		col = mix(col, DASH_COL, onDash * dash * dashFade * 0.40);
	}

	// ── Vignette ──
	float vig = smoothstep(0.46, 1.05, length(vec2(cx, (uv.y - 0.42))) * 1.05);
	col *= 1.0 - vig * 0.48;

	COLOR = vec4(col, 1.0);
}
