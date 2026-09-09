extends TestCase


func test_pool_identity_survives_death_and_slot_reuse_changes_id() -> void:
	var pools := MinorActorPools.new()
	WalkerRules.spawn(pools, 0, Vector2i(4, 0), 1, 1, 2, MinorActorPools.Cause.LADDER)
	var first_id := pools.walker_actor_id(0)
	eq(pools.walker_lifecycle(0), ActorLifecycle.State.WARMUP)
	pools.retire_walker(0, MinorActorPools.Reason.EXTINGUISHED, 2)
	eq(pools.walker_lifecycle(0), ActorLifecycle.State.DYING)
	eq(pools.walker_actor_id(0), first_id)
	eq(pools.free_walker_slot(), 1, "dissipação reserva a identidade visual do slot")
	pools.advance_removals()
	eq(pools.walker_lifecycle(0), ActorLifecycle.State.DYING)
	pools.advance_removals()
	eq(pools.walker_lifecycle(0), ActorLifecycle.State.DESPAWNED)
	eq(pools.free_walker_slot(), 0)
	WalkerRules.spawn(pools, 0, Vector2i(4, 0), 1, 1, 0, MinorActorPools.Cause.LADDER)
	ok(pools.walker_actor_id(0) > first_id, "identidade não é endereço de pool")
	eq(pools.walker_lifecycle(0), ActorLifecycle.State.ACTIVE)


func test_walker_warmup_is_harmless_through_last_warning_tick() -> void:
	var sim := _simulation()
	WalkerRules.spawn(sim.pools, 0, sim.player.cell(), 1, 1, 2, MinorActorPools.Cause.LADDER)
	for _tick in 2:
		sim.step(MoveIntent.none())
		eq(sim.phase, GameSimulation.Phase.PLAYING)
		eq(sim.pools.walker_lifecycle(0), ActorLifecycle.State.WARMUP)
	sim.step(MoveIntent.none())
	eq(sim.phase, GameSimulation.Phase.DYING)
	eq(sim.player.lifecycle(), ActorLifecycle.State.DYING)


func test_dead_boundary_walker_is_harmless_then_dissipates() -> void:
	var sim := _simulation()
	# Território consolidado já não deixa FREE em torno desta posição da moldura.
	for x in range(3, 8):
		sim.board.set_cell(x, 1, BoardState.Cell.CLAIMED)
	WalkerRules.spawn(sim.pools, 0, sim.player.cell(), 1, 1, 0, MinorActorPools.Cause.LADDER)
	var profile := sim.threat_profile()
	profile.walker_dormant_ticks = 2
	sim.step(MoveIntent.none())
	eq(sim.phase, GameSimulation.Phase.PLAYING, "fronteira morta protege antes do passo do vagalume")
	eq(sim.pools.walker_lifecycle(0), ActorLifecycle.State.DORMANT)
	sim.step(MoveIntent.none())
	eq(sim.pools.walker_lifecycle(0), ActorLifecycle.State.DYING)
	eq(sim.score, profile.walker_trap_points)
	sim.step(MoveIntent.none())
	eq(sim.score, profile.walker_trap_points, "paga a armadilha uma vez")


func test_respawn_grace_covers_all_collisions_for_exact_duration() -> void:
	var sim := _simulation()
	sim.rules.death_ticks = 1
	sim.threat_profile().respawn_grace_ticks = 2
	WalkerRules.spawn(sim.pools, 0, sim.player.cell(), 1, 1, 0, MinorActorPools.Cause.LADDER)
	sim.step(MoveIntent.none())
	eq(sim.phase, GameSimulation.Phase.DYING)
	sim.step(MoveIntent.none())
	eq(sim.player.lifecycle(), ActorLifecycle.State.WARMUP)
	for _tick in 2:
		# A graça deve valer tanto antes como depois do passo do ator.
		sim.pools.set_walker(0, MinorActorPools.W.ACC_FP, 0)
		sim.step(MoveIntent.none())
		eq(sim.phase, GameSimulation.Phase.PLAYING)
	eq(sim.director.respawn_grace_left, 0)
	sim.step(MoveIntent.none())
	eq(sim.phase, GameSimulation.Phase.DYING)


func test_cut_at_trail_head_gives_ember_warning_before_contact() -> void:
	var player := PlayerState.new()
	player.trail_active = true
	player.trail = PackedInt32Array([20, 21, 22])
	var pools := MinorActorPools.new()
	EmberRules.ignite(pools, 0, 2, MinorActorPools.Cause.CUT, 3)
	for _tick in 3:
		eq(EmberRules.update(pools, 0, player, 384), EmberRules.Outcome.NONE)
		eq(pools.ember_lifecycle(0), ActorLifecycle.State.WARMUP)
	eq(EmberRules.update(pools, 0, player, 384), EmberRules.Outcome.CONTACT)
	eq(pools.ember_lifecycle(0), ActorLifecycle.State.ACTIVE)
	EmberRules.extinguish_all(pools)
	player.trail.clear()
	eq(EmberRules.cell_index(pools, 0, player), 22, "dissipação conserva a última célula")


func test_dart_substeps_preserve_speed_remainder_and_safe_ground() -> void:
	var pools := MinorActorPools.new()
	var board := BoardState.new(20, 20)
	var player := PlayerState.new()
	player.reset(Vector2i(5, 0))
	_setup_dart(pools, Vector2i(5, 1), 511)
	var cuts: Array[int] = []
	var start := pools.dart(0, MinorActorPools.D.X_FP)
	eq(DartRules.update(pools, 0, board, player, true, cuts), DartRules.Outcome.NONE)
	eq(pools.dart(0, MinorActorPools.D.X_FP) - start, 511)
	# Borda protegida não sofre hitbox de dardo vizinho em FREE, inclusive quando
	# TRAIL continua ativa até a arbitragem do fechamento neste tick.
	player.trail_active = true
	_setup_dart(pools, Vector2i(4, 1), 85)
	eq(DartRules.update(pools, 0, board, player, true, cuts), DartRules.Outcome.NONE)


func test_capture_absorbs_warmup_dart_without_reusing_dying_slot() -> void:
	var pools := MinorActorPools.new()
	var board := BoardState.new(20, 20)
	_setup_dart(pools, Vector2i(5, 5), 256)
	pools.set_dart(0, MinorActorPools.D.WARMUP, 24)
	board.set_cell(5, 5, BoardState.Cell.CLAIMED)
	eq(DartRules.absorb_grounded(pools, board), PackedInt32Array([0]))
	eq(pools.dart_lifecycle(0), ActorLifecycle.State.DYING)
	eq(pools.free_dart_slot(), 1)
	eq(DartRules.absorb_grounded(pools, board).size(), 0)


func test_full_pools_refuse_spawn_without_rng_or_identity_mutation() -> void:
	var pools := MinorActorPools.new()
	for slot in MinorActorPools.MAX_DARTS:
		pools.begin_dart(slot, 24)
	var rng := DeterministicRng.new(7)
	var before := pools.canonical_bytes()
	var rng_before := rng.state
	eq(DartRules.try_spawn(pools, BoardState.new(50, 50), Vector2i(25, 0), rng, 85, 16, 24, 900, 1), -1)
	eq(pools.canonical_bytes(), before)
	eq(rng.state, rng_before)


func test_invalid_lifecycle_timers_are_rejected_and_affect_replay_hash() -> void:
	var profile := ThreatProfile.new()
	var baseline := profile.canonical_bytes()
	profile.ember_warmup_ticks += 1
	ok(profile.canonical_bytes() != baseline)
	profile.ember_warmup_ticks = 0
	profile.walker_dormant_ticks = 0
	profile.respawn_grace_ticks = -1
	ok(profile.validation_errors().size() >= 3)


func test_dart_peek_path_walks_the_same_corridor_that_update_confirms() -> void:
	var pools := MinorActorPools.new()
	var board := BoardState.new(20, 20)
	var player := PlayerState.new()
	player.reset(Vector2i(5, 0))
	# A 256 fp o dardo anda uma célula por tick num único subpasso, então amostrar por tick
	# observa o percurso inteiro e a igualdade pode ser estrita.
	_setup_dart(pools, Vector2i(5, 10), 256)
	var before := pools.canonical_bytes()
	var peeked := DartRules.peek_path(pools, 0, board, board.width + board.height)
	eq(pools.canonical_bytes(), before, "prever o corredor não move nem retira o dardo")
	ok(peeked.size() > 0)
	eq(_walk_dart(pools, board, player, Vector2i(5, 10)), peeked,
		"o aviso mostra exatamente o percurso que o dardo vai cumprir")
	eq(pools.dart(0, MinorActorPools.D.REASON), MinorActorPools.Reason.ABSORBED,
		"o corredor termina na borda que absorve o dardo")
	# Acima de uma célula por tick o domínio arbitra cada subpasso, e o corredor previsto é
	# mais fino que a amostragem por tick: toda célula andada precisa estar prevista, na ordem.
	var fast := MinorActorPools.new()
	_setup_dart(fast, Vector2i(5, 10), 384)
	var fast_peek := DartRules.peek_path(fast, 0, board, board.width + board.height)
	var fast_walk := _walk_dart(fast, board, player, Vector2i(5, 10))
	ok(fast_walk.size() < fast_peek.size(), "o subpasso visita células que a amostragem por tick pula")
	var cursor := 0
	for index in fast_walk:
		while cursor < fast_peek.size() and fast_peek[cursor] != index:
			cursor += 1
		ok(cursor < fast_peek.size(), "célula andada %d estava prevista no corredor" % index)
		cursor += 1
	eq(fast_walk[fast_walk.size() - 1], fast_peek[fast_peek.size() - 1],
		"os dois terminam na mesma célula absorvente")


func test_dart_peek_path_stops_on_the_first_cell_that_is_not_free() -> void:
	var pools := MinorActorPools.new()
	var board := BoardState.new(20, 20)
	_setup_dart(pools, Vector2i(5, 10), 256)
	var open := DartRules.peek_path(pools, 0, board, board.width + board.height)
	board.set_cell(9, 10, BoardState.Cell.CLAIMED)
	var blocked := DartRules.peek_path(pools, 0, board, board.width + board.height)
	ok(blocked.size() < open.size(), "território conquistado encurta o aviso, como encurta o voo")
	eq(blocked[blocked.size() - 1], board.index_of(9, 10),
		"a célula que absorve entra no corredor: é onde o dardo termina")
	eq(DartRules.peek_path(pools, 0, board, 2).size(), 2, "o teto limita o laço sem inventar rota")


## Anda o dardo do slot 0 até o primeiro desfecho, devolvendo as células novas por tick.
func _walk_dart(
	pools: MinorActorPools, board: BoardState, player: PlayerState, start: Vector2i
) -> PackedInt32Array:
	var walked := PackedInt32Array()
	var cuts: Array[int] = []
	var last := board.index_of(start.x, start.y)
	for _tick in 64:
		var outcome := DartRules.update(pools, 0, board, player, false, cuts)
		var cell := pools.dart_cell(0)
		var index := board.index_of(cell.x, cell.y)
		if index != last:
			walked.append(index)
			last = index
		if outcome != DartRules.Outcome.NONE:
			break
	return walked


func test_dart_peek_path_preserves_slow_oblique_steps_and_expiry() -> void:
	var board := BoardState.new(20, 20)
	var player := PlayerState.new()
	player.reset(Vector2i(0, 0))
	for direction in 16:
		for speed in [1, 85, 255]:
			var pools := MinorActorPools.new()
			_setup_dart(pools, Vector2i(10, 10), speed)
			pools.set_dart(0, MinorActorPools.D.DIR_INDEX, direction)
			pools.set_dart(0, MinorActorPools.D.LIFE, 30)
			var before := pools.canonical_bytes()
			var predicted := DartRules.peek_path(pools, 0, board, board.width + board.height)
			eq(pools.canonical_bytes(), before)
			eq(_walk_dart(pools, board, player, Vector2i(10, 10)), predicted,
				"saltar ticks sem mudar célula preserva direção %d, velocidade %d e LIFE" % [direction, speed])
			ok(not pools.dart_alive(0), "o percurso foi observado até absorção ou expiração")


func _setup_dart(pools: MinorActorPools, cell: Vector2i, speed: int) -> void:
	pools.begin_dart(0, 0)
	pools.set_dart(0, MinorActorPools.D.X_FP, cell.x << 8)
	pools.set_dart(0, MinorActorPools.D.Y_FP, cell.y << 8)
	pools.set_dart(0, MinorActorPools.D.DIR_INDEX, 0)
	pools.set_dart(0, MinorActorPools.D.SPEED_FP, speed)
	pools.set_dart(0, MinorActorPools.D.LIFE, 900)


func _simulation() -> GameSimulation:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.shield_ticks = 10000
	var definition := RoundDefinition.new()
	definition.field_width = 21
	definition.field_height = 21
	definition.player_spawn = Vector2i(5, 0)
	definition.boss_start = Vector2i(15, 15)
	return GameSimulation.new(rules, definition, 7)
