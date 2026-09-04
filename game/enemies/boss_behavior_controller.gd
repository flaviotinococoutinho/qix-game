class_name BossBehaviorController
extends RefCounted
## Decisões puras do chefe. Não lê relógio, Input, física nem estado de apresentação.

const BossBehaviorProfileScript = preload("res://game/enemies/boss_behavior_profile.gd")

const DIRECTION_X := [
	256, 237, 181, 98, 0, -98, -181, -237,
	-256, -237, -181, -98, 0, 98, 181, 237,
]
const DIRECTION_Y := [
	0, 98, 181, 237, 256, 237, 181, 98,
	0, -98, -181, -237, -256, -237, -181, -98,
]


static func next_direction(
	profile: Resource,
	current_direction_index: int,
	origin_cell: Vector2i,
	target_cell: Vector2i,
	rng: DeterministicRng,
) -> int:
	var current := current_direction_index & 15
	if profile == null:
		return rng.next_below(16)
	match profile.pattern:
		BossBehaviorProfileScript.Pattern.PURSUIT:
			var delta := target_cell - origin_cell
			if delta == Vector2i.ZERO:
				return current
			var aimed := nearest_direction_index(delta)
			var jitter: int = profile.pursuit_jitter_steps
			if jitter > 0:
				aimed += rng.next_below(jitter * 2 + 1) - jitter
			return aimed & 15
		BossBehaviorProfileScript.Pattern.SWEEP:
			return (current + profile.sweep_turn_steps) & 15
		_:
			return rng.next_below(16)


## Quantiza um vetor na direção de maior produto escalar da tabela 8.8.
static func nearest_direction_index(delta: Vector2i) -> int:
	if delta == Vector2i.ZERO:
		return 0
	var best_index := 0
	var best_dot: int = delta.x * DIRECTION_X[0] + delta.y * DIRECTION_Y[0]
	for index in range(1, 16):
		var dot: int = delta.x * DIRECTION_X[index] + delta.y * DIRECTION_Y[index]
		if dot > best_dot:
			best_dot = dot
			best_index = index
	return best_index


## O pulso ocupa o fim do período, deixando uma janela inicial previsível ao jogador.
static func effective_speed_fp(
	profile: Resource,
	base_speed_fp: int,
	tick: int,
) -> int:
	if profile == null or profile.pulse_period_ticks <= 0:
		return base_speed_fp
	var phase_tick: int = tick % int(profile.pulse_period_ticks)
	var pulse_start: int = int(profile.pulse_period_ticks) - int(profile.pulse_duration_ticks)
	if phase_tick < pulse_start:
		return base_speed_fp
	@warning_ignore("integer_division")
	return base_speed_fp * profile.pulse_speed_permille / 1000


static func reflected_horizontal(direction_index: int) -> int:
	return (8 - direction_index) & 15


static func reflected_vertical(direction_index: int) -> int:
	return (-direction_index) & 15
