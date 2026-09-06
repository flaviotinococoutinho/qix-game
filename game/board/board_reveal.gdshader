shader_type canvas_item;
render_mode unshaded;

uniform sampler2D state_mask : filter_nearest, repeat_disable;
uniform vec4 free_color : source_color = vec4(0.027, 0.098, 0.137, 1.0);
uniform vec4 boundary_color : source_color = vec4(0.275, 0.961, 0.773, 1.0);
uniform vec4 trail_color : source_color = vec4(1.0, 0.820, 0.357, 1.0);
uniform vec4 trail_hot_color : source_color = vec4(1.0, 0.957, 0.690, 1.0);
// Fases já acumuladas e enroladas pela view, não o tick cru. O tick cru multiplicado por uma
// taxa variável fazia a fase saltar a cada mudança de exposição (ver QixBoardView._advance_phases);
// além disso crescia sem limite, o que corrói a precisão de `float` no fragmento.
// `scan_phase` tem período 2.0 e `trail_pulse_phase` tem período TAU, então o enrolamento é
// invisível. Só apresentação: nenhum valor daqui volta para a simulação.
uniform float scan_phase = 0.0;
uniform float trail_pulse_phase = 0.0;
// Comprimento confirmado da trilha, normalizado pela TrailExposure. Só apresentação:
// nenhum valor daqui volta para a simulação.
uniform float trail_exposure : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float state = floor(texture(state_mask, UV).r * 255.0 + 0.5);
	float scan = 0.92 + 0.08 * step(0.5, fract((FRAGCOORD.y + scan_phase) * 0.5));
	vec4 result;

	if (state < 0.5) {
		// FREE mantém a ilustração completamente coberta.
		result = vec4(free_color.rgb * scan, free_color.a);
	} else if (state < 1.5) {
		// BOUNDARY é a malha segura de alta legibilidade.
		float glint = 0.86 + 0.14 * step(0.72, fract((FRAGCOORD.x + FRAGCOORD.y) * 0.25));
		result = vec4(boundary_color.rgb * glint, boundary_color.a);
	} else if (state < 2.5) {
		// TRAIL pulsa sem depender da simulação: a fase é somente visual.
		// Quanto mais longe da moldura o traço chega, mais rápido ele pulsa e mais alto fica o
		// piso de luminância — frequência e brilho, não matiz, para que o aviso sobreviva a
		// deuteranopia e à barra de qualidade de ART_DIRECTION.md. A *taxa* que acelera o pulso
		// vive na view, integrada tick a tick; aqui só chega a fase resultante.
		float pulse = 0.5 + 0.5 * sin(trail_pulse_phase + FRAGCOORD.x * 0.22 + FRAGCOORD.y * 0.16);
		float heat = mix(pulse, 0.55 + 0.45 * pulse, trail_exposure);
		result = mix(trail_color, trail_hot_color, heat);
	} else {
		// Somente CLAIMED revela o texel original, sem tint ou alteração de alpha.
		result = texture(TEXTURE, UV);
	}

	COLOR = result;
}
