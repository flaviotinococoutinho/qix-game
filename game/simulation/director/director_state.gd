class_name DirectorState
extends RefCounted
## Estado do diretor de ameaça: o índice na escada e os contadores que o alimentam. Só inteiros;
## tudo entra no checksum. As decisões vivem em `ThreatDirector`.

var threat_index: int = 0
var dart_countdown: int = 0
var walker_countdown: int = 0
var overtime: int = 0
var calm_ticks: int = 0
var exposure_fired: int = 0
var streak: int = 0
var streak_bonus: int = 0
var next_walker_bias: int = 1
var spawn_retry_ticks: int = 0
var respawn_grace_left: int = 0
## Pedido pendente de dardo por fúria do Núcleo (consumido pelo diretor no mesmo tick).
var cornered_request: int = 0
var pending_dart_cause: int = MinorActorPools.Cause.LADDER


func reset(profile: ThreatProfile) -> void:
	if profile == null:
		profile = ThreatProfile.inert()
	threat_index = clampi(profile.pressure_bonus, 0, ThreatProfile.LADDER_SIZE - 1)
	dart_countdown = profile.ladder_dart_interval[0] if profile.ladder_dart_interval.size() > 0 else 0
	walker_countdown = profile.walker_spawn_interval_ticks
	overtime = 0
	calm_ticks = 0
	exposure_fired = 0
	streak = 0
	streak_bonus = 0
	next_walker_bias = 1
	spawn_retry_ticks = 0
	respawn_grace_left = 0
	cornered_request = 0
	pending_dart_cause = MinorActorPools.Cause.LADDER


func canonical_values() -> Array[int]:
	return [
		threat_index, dart_countdown, walker_countdown, overtime, calm_ticks, exposure_fired,
		streak, streak_bonus, next_walker_bias, spawn_retry_ticks, respawn_grace_left,
		cornered_request, pending_dart_cause,
	]
