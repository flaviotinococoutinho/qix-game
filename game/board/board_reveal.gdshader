shader_type canvas_item;
render_mode unshaded;

uniform sampler2D state_mask : filter_nearest, repeat_disable;
uniform vec4 free_color : source_color = vec4(0.027, 0.098, 0.137, 1.0);
uniform vec4 boundary_color : source_color = vec4(0.275, 0.961, 0.773, 1.0);
uniform vec4 trail_color : source_color = vec4(1.0, 0.820, 0.357, 1.0);
uniform vec4 trail_hot_color : source_color = vec4(1.0, 0.957, 0.690, 1.0);
uniform float presentation_tick = 0.0;

void fragment() {
	float state = floor(texture(state_mask, UV).r * 255.0 + 0.5);
	float scan = 0.92 + 0.08 * step(0.5, fract((FRAGCOORD.y + presentation_tick * 0.08) * 0.5));
	vec4 result;

	if (state < 0.5) {
		// FREE mantém a ilustração completamente coberta.
		result = vec4(free_color.rgb * scan, free_color.a);
	} else if (state < 1.5) {
		// BOUNDARY é a malha segura de alta legibilidade.
		float glint = 0.86 + 0.14 * step(0.72, fract((FRAGCOORD.x + FRAGCOORD.y) * 0.25));
		result = vec4(boundary_color.rgb * glint, boundary_color.a);
	} else if (state < 2.5) {
		// TRAIL pulsa sem depender da simulação: presentation_tick é somente visual.
		float pulse = 0.5 + 0.5 * sin(presentation_tick * 0.20 + FRAGCOORD.x * 0.22 + FRAGCOORD.y * 0.16);
		result = mix(trail_color, trail_hot_color, pulse);
	} else {
		// Somente CLAIMED revela o texel original, sem tint ou alteração de alpha.
		result = texture(TEXTURE, UV);
	}

	COLOR = result;
}
