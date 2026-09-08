class_name ThreatDirector
extends RefCounted
## Diretor de ameaça: decide **quando** cada ator menor nasce, lendo tick, território e o
## comportamento do jogador. Regras estáticas sobre `DirectorState` e pools limitados;
## só eventos confirmados e resultados auxiliares usam buffers temporários.
##
## Índice de ameaça (0..15) = tempo + território + pressão da rodada + overtime + sequência
## de capturas mínimas − calmaria. Ele indexa a escada de `ThreatProfile` (forma de
## `enemy_rate_table`, §10). Três laços de sensação:
##  - cada captura recarrega o dardo ao intervalo cheio: **capturar compra respiro**;
##  - trilha exposta (limiar do HUD) chama fogo: o aviso ganha consequência;
##  - acampar na borda ou parar a desenhar acende o próprio risco.
## Justiça: nenhum spawn perto do jogador, nem no tick de um fechamento; todo ator nasce em
## aviso (`warmup`) e ninguém menor mata durante a graça pós-reentrada.


## Índice de ameaça para o instante atual. Puro.
static func compute_index(state: DirectorState, profile: ThreatProfile, tick: int, permille: int) -> int:
	@warning_ignore("integer_division")
	var time_index := mini(6, tick / maxi(1, profile.time_step_ticks))
	@warning_ignore("integer_division")
	var area_index := mini(6, permille / maxi(1, profile.area_step_permille))
	var overtime_index := 0
	if state.overtime > 0:
		@warning_ignore("integer_division")
		overtime_index = 1 + maxi(0, tick - profile.round_time_limit_ticks) / maxi(1, profile.overtime_step_ticks)
	var calm := 1 if state.calm_ticks > 0 else 0
	return clampi(
		time_index + area_index + profile.pressure_bonus + overtime_index + state.streak_bonus - calm,
		0,
		ThreatProfile.LADDER_SIZE - 1,
	)


## Um tick do diretor. Roda depois do Núcleo e antes dos atores menores; `closed_this_tick`
## bloqueia spawns (justiça: nada nasce no tick de um fechamento).
static func update(sim: GameSimulation, closed_this_tick: bool, events: Array[GameEvent]) -> void:
	var profile: ThreatProfile = sim.rules.threat
	var state := sim.director
	if profile == null or not profile.enabled:
		return
	var pools := sim.pools
	var player := sim.player

	if state.calm_ticks > 0:
		state.calm_ticks -= 1
	if state.spawn_retry_ticks > 0:
		state.spawn_retry_ticks -= 1

	# Overtime (§10: ao expirar o limite, a cadência dispara).
	if state.overtime == 0 and sim.tick >= profile.round_time_limit_ticks:
		state.overtime = 1
		events.append(GameEvent.make(GameEvent.Kind.OVERTIME_STARTED, {"tick": sim.tick}))

	# Comportamento: parado a desenhar acende a trilha; parado na borda chama um dardo.
	if not closed_this_tick and player.stall_ticks >= profile.stall_ignite_ticks and player.trail_active and player.trail.size() > 1:
		var slot := pools.free_ember_slot()
		if slot >= 0:
			EmberRules.ignite(pools, slot, 0, MinorActorPools.Cause.STALL, profile.ember_warmup_ticks)
			events.append(GameEvent.make(GameEvent.Kind.EMBER_IGNITED, {
				"slot": slot, "trail_index": 0, "cause": MinorActorPools.Cause.STALL}))
		player.stall_ticks = 0
	elif player.stall_ticks >= profile.camp_dart_ticks and not player.trail_active:
		events.append(GameEvent.make(GameEvent.Kind.PLAYER_STALLING, {"ticks": player.stall_ticks}))
		state.dart_countdown = 0
		state.pending_dart_cause = MinorActorPools.Cause.CAMP
		player.stall_ticks = 0

	# Exposição: a trilha longa (mesmo limiar que o HUD nomeia) chama fogo uma vez por trilha.
	if player.trail_active:
		if state.exposure_fired == 0 and player.trail.size() >= profile.exposure_dart_px:
			state.exposure_fired = 1
			state.pending_dart_cause = MinorActorPools.Cause.EXPOSURE
			@warning_ignore("integer_division")
			state.dart_countdown = mini(state.dart_countdown, state.dart_countdown / 2)
	else:
		state.exposure_fired = 0

	# Fúria do Núcleo pede um dardo imediato.
	if state.cornered_request > 0:
		state.cornered_request = 0
		state.dart_countdown = 0
		state.pending_dart_cause = MinorActorPools.Cause.CORNERED

	# Índice e escada.
	var index := compute_index(state, profile, sim.tick, sim.ledger.permille)
	if index != state.threat_index:
		events.append(GameEvent.make(GameEvent.Kind.THREAT_LEVEL_CHANGED, {
			"index": index, "previous": state.threat_index}))
		state.threat_index = index

	# Contagens.
	if state.dart_countdown > 0:
		state.dart_countdown -= 1
	if state.walker_countdown > 0:
		state.walker_countdown -= 1

	if closed_this_tick:
		return

	# Dardo.
	if state.dart_countdown <= 0:
		var cause := state.pending_dart_cause
		if cause == MinorActorPools.Cause.LADDER and state.overtime > 0:
			cause = MinorActorPools.Cause.OVERTIME
		var slot := DartRules.try_spawn(
			pools, sim.board, player.cell(), sim.rng,
			profile.ladder_dart_speed_fp[index], profile.dart_min_range,
			profile.dart_warmup_ticks, profile.dart_life_ticks, cause,
		)
		state.dart_countdown = profile.ladder_dart_interval[index]
		state.pending_dart_cause = MinorActorPools.Cause.LADDER
		if slot >= 0:
			var cell := pools.dart_cell(slot)
			events.append(GameEvent.make(GameEvent.Kind.DART_ARMED, {
				"slot": slot, "x": cell.x, "y": cell.y,
				"dir_index": pools.dart(slot, MinorActorPools.D.DIR_INDEX), "cause": cause,
				"warmup": profile.dart_warmup_ticks}))

	# Uma tentativa bloqueada no portão não adia o relógio independente dos dardos.
	if state.spawn_retry_ticks > 0:
		return
	# Vagalume.
	if state.walker_countdown <= 0 and pools.alive_walkers() < profile.ladder_max_walkers[index]:
		var gate := sim.round_def.walker_gate()
		var distance := absi(gate.x - player.px) + absi(gate.y - player.py)
		var slot := pools.free_walker_slot()
		if slot < 0 or distance < profile.spawn_safe_radius or not WalkerRules.is_live_boundary(sim.board, gate.x, gate.y):
			state.spawn_retry_ticks = profile.spawn_retry_ticks
			return
		var preferred := 1 if state.next_walker_bias > 0 else 3
		var dir := WalkerRules.initial_direction(sim.board, gate, preferred)
		if dir < 0:
			state.spawn_retry_ticks = profile.spawn_retry_ticks
			return
		WalkerRules.spawn(pools, slot, gate, dir, state.next_walker_bias, profile.walker_warmup_ticks,
			MinorActorPools.Cause.LADDER)
		state.next_walker_bias = -state.next_walker_bias
		state.walker_countdown = profile.walker_spawn_interval_ticks
		events.append(GameEvent.make(GameEvent.Kind.WALKER_SPAWNED, {
			"slot": slot, "x": gate.x, "y": gate.y, "dir": dir, "cause": MinorActorPools.Cause.LADDER,
			"warmup": profile.walker_warmup_ticks}))


## Reações a uma captura aplicada: recarga do dardo, calmaria, sequência anti-tartaruga.
static func on_capture(sim: GameSimulation, permille_delta: int, events: Array[GameEvent]) -> void:
	var profile: ThreatProfile = sim.rules.threat
	var state := sim.director
	if profile == null or not profile.enabled:
		return
	state.dart_countdown = profile.ladder_dart_interval[state.threat_index]
	state.pending_dart_cause = MinorActorPools.Cause.LADDER
	if permille_delta >= profile.calm_capture_permille and profile.calm_ticks > 0:
		state.calm_ticks = profile.calm_ticks
		events.append(GameEvent.make(GameEvent.Kind.CALM_STARTED, {"ticks": profile.calm_ticks}))
	if permille_delta < profile.streak_capture_permille:
		state.streak += 1
		if state.streak >= profile.streak_trigger:
			state.streak = 0
			state.streak_bonus = mini(state.streak_bonus + 1, ThreatProfile.LADDER_SIZE - 1)
	else:
		state.streak = 0
