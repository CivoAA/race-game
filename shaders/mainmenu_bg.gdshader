shader_type canvas_item;

// Animierter Hauptmenü-Hintergrund (Design „Road Tycoon"):
// dunkler Radial-Verlauf, zwei sanft driftende Glows, eine Perspektiv-Straße mit
// zarten Fahrbahnrändern und einer goldenen, nach vorne fahrenden Mittellinie, die
// weich aus dem Horizont auftaucht – plus Vignette.

const vec3 BG0       = vec3(0.149, 0.169, 0.204); // #262b34
const vec3 BG1       = vec3(0.106, 0.118, 0.141); // #1b1e24
const vec3 BG2       = vec3(0.075, 0.082, 0.098); // #131519
const vec3 ROAD_FAR  = vec3(0.082, 0.094, 0.114); // #15181d
const vec3 ROAD_NEAR = vec3(0.110, 0.125, 0.153); // #1c2027
const vec3 GLOW_BLUE = vec3(0.37, 0.44, 1.00);
const vec3 GLOW_GRN  = vec3(0.27, 0.78, 0.43);
const vec3 DASH_COL  = vec3(0.808, 0.722, 0.463); // #ceb876
const vec3 LANE_COL  = vec3(0.59, 0.63, 0.71);

void fragment() {
	vec2 uv = UV;
	float t = TIME;

	// ── Radial-Verlauf (Ursprung oben mittig) ──
	vec2 p = (uv - vec2(0.5, 0.06));
	p.x *= 1.1;
	float rg = clamp(length(p), 0.0, 1.0);
	vec3 col = mix(BG0, BG1, smoothstep(0.0, 0.52, rg));
	col = mix(col, BG2, smoothstep(0.52, 1.0, rg));

	// ── Driftende, weiche Glows ──
	vec2 g1 = vec2(0.40 + 0.05 * sin(t * 0.18), 0.26 + 0.04 * cos(t * 0.15));
	col += GLOW_BLUE * 0.10 * smoothstep(0.55, 0.0, distance(uv, g1));
	vec2 g2 = vec2(0.80 + 0.05 * sin(t * 0.13 + 1.7), 0.96 + 0.04 * cos(t * 0.19));
	col += GLOW_GRN * 0.08 * smoothstep(0.55, 0.0, distance(uv, g2));

	// ── Perspektiv-Straße (untere 60 %) ──
	float horizon = 0.40;
	if (uv.y > horizon) {
		float ty = (uv.y - horizon) / (1.0 - horizon);     // 0 Horizont .. 1 vorne
		float fade = smoothstep(0.0, 0.30, ty);            // weiches Auftauchen
		float roadHalf = mix(0.012, 0.66, ty * ty * 0.6 + ty * 0.4);
		float dx = uv.x - 0.5;
		float adx = abs(dx);

		// Fahrbahn
		float surf = smoothstep(roadHalf + 0.012, roadHalf - 0.012, adx);
		vec3 roadCol = mix(ROAD_FAR, ROAD_NEAR, ty);
		col = mix(col, roadCol, surf * fade);

		// zarte Fahrbahnränder
		float laneX = roadHalf * 0.52;
		float lane = smoothstep(0.005, 0.0, abs(adx - laneX));
		col = mix(col, LANE_COL, lane * surf * fade * 0.13);

		// fahrende Mittellinie (perspektivisch: vorne lang, hinten dicht)
		float z = (1.0 - ty) / max(ty, 0.02);
		float dashCoord = z * 5.0 + t * 2.4;
		float dash = smoothstep(0.48, 0.52, fract(dashCoord));
		float dashHalf = mix(0.006, 0.05, ty);
		float onDash = smoothstep(dashHalf, dashHalf - 0.008, adx);
		col = mix(col, DASH_COL, onDash * dash * fade * 0.62);
	}

	// ── Vignette ──
	float vig = smoothstep(0.48, 1.05, distance(uv, vec2(0.5, 0.42)) * 1.05);
	col *= 1.0 - vig * 0.40;

	COLOR = vec4(col, 1.0);
}
