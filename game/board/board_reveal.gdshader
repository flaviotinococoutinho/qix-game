shader_type canvas_item;
render_mode unshaded;

uniform sampler2D state_mask : filter_nearest, repeat_disable;
uniform vec4 free_color : source_color = vec4(0.027, 0.098, 0.137, 1.0);
uniform vec4 boundary_color : source_color = vec4(0.275, 0.961, 0.773, 1.0);
uniform vec4 trail_color : source_color = vec4(1.0, 0.820, 0.357, 1.0);
uniform vec4 trail_hot_color : source_color = vec4(1.0, 0.957, 0.690, 1.0);
uniform float presentation_tick = 0.0;
// Comprimento confirmado da trilha, normalizado pela TrailExposure. Só apresentação:
// nenhum valor daqui volta para a simulação.
uniform float trail_exposure : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float state = floor(texture(state_mask, UV).r * 255.0 + 0.5);
	// Padrões em células lógicas: o período não muda entre 1x, 3x e o plano 3D.
	vec2 cell = UV / TEXTURE_PIXEL_SIZE;
	float scan = 0.96 + 0.04 * step(0.5, fract((cell.y + presentation_tick * 0.03) * 0.5));
	vec4 result;

	if (state < 0.5) {
		// FREE mantém a ilustração completamente coberta.
		vec2 grid_distance = abs(fract(cell / 24.0 - 0.5) - 0.5) * 24.0;
		float grid = 1.0 - smoothstep(0.0, 0.32, min(grid_distance.x, grid_distance.y));
		float well = 0.84 + 0.16 * (1.0 - length(UV - vec2(0.5)));
		result = vec4(free_color.rgb * scan * well + vec3(0.006, 0.012, 0.016) * grid, free_color.a);
	} else if (state < 1.5) {
		// BOUNDARY é a malha segura de alta legibilidade.
		float glint = 0.86 + 0.14 * step(0.72, fract((cell.x + cell.y) * 0.25));
		result = vec4(boundary_color.rgb * glint, boundary_color.a);
	} else if (state < 2.5) {
		// TRAIL pulsa sem depender da simulação: presentation_tick é somente visual.
		// Quanto mais longe da moldura o traço chega, mais rápido ele pulsa e mais alto fica o
		// piso de luminância — frequência e brilho, não matiz, para que o aviso sobreviva a
		// deuteranopia e à barra de qualidade de ART_DIRECTION.md.
		float rate = 0.20 + 0.55 * trail_exposure;
		float pulse = 0.5 + 0.5 * sin(presentation_tick * rate + cell.x * 0.22 + cell.y * 0.16);
		float heat = mix(pulse, 0.55 + 0.45 * pulse, trail_exposure);
		result = mix(trail_color, trail_hot_color, heat);
	} else {
		// Somente CLAIMED revela o texel original, sem tint ou alteração de alpha.
		result = texture(TEXTURE, UV);
	}

	COLOR = result;
}
