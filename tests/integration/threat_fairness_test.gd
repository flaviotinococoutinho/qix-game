extends TestCase


func test_first_ten_seconds_never_kill_idle_player_with_minor_actor() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	for content in campaign.rounds:
		for seed_value in [11, 2026, 90210]:
			var sim := GameSimulation.new(content.rules, content.round_definition, seed_value)
			for _tick in 600:
				for event in sim.step(MoveIntent.none()):
					if event.kind == GameEvent.Kind.PLAYER_DIED:
						ok(event.data.reason < GameSimulation.DeathReason.WALKER_CONTACT,
							"%s seed %d: ator menor matou antes de 600 ticks" % [content.round_id, seed_value])
					if event.kind in [GameEvent.Kind.WALKER_SPAWNED, GameEvent.Kind.DART_ARMED]:
						var distance: int = absi(event.data.x - sim.px) + absi(event.data.y - sim.py)
						ok(distance >= sim.threat_profile().spawn_safe_radius,
							"spawn respeita o raio seguro medido no tick de nascimento")
			ok(sim.pools.alive_total() <= MinorActorPools.MAX_WALKERS + MinorActorPools.MAX_DARTS + MinorActorPools.MAX_EMBERS)


## O dardo nasce por backtrack a partir do jogador, então a reta armada passa por ele. Um aviso
## de comprimento fixo escondia isso: `dart_min_range` vale 24 células por padrão e o raio antigo
## cobria cinco. Quem estava na mira não tinha como ler que estava na mira.
func test_armed_dart_corridor_reaches_the_player_it_was_aimed_at() -> void:
	var board := BoardState.new(60, 60)
	var player_cell := Vector2i(30, 30)
	var reach := board.width + board.height
	var aimed := 0
	for seed_value in [11, 2026, 90210, 4242]:
		var pools := MinorActorPools.new()
		var rng := DeterministicRng.new(seed_value)
		var slot := DartRules.try_spawn(
			pools, board, player_cell, rng, 384, 24, 24, 240, MinorActorPools.Cause.EXPOSURE)
		ok(slot >= 0, "seed %d: o dardo nasce com alcance mínimo de 24 células" % seed_value)
		if slot < 0:
			continue
		var corridor := DartRules.peek_path(pools, slot, board, reach)
		ok(corridor.size() > QixMinorActorView.MUZZLE_CELLS,
			"seed %d: o corredor é mais longo que a boca de cinco células" % seed_value)
		for index in corridor:
			@warning_ignore("integer_division")
			var cell := Vector2i(index % board.width, index / board.width)
			if absi(cell.x - player_cell.x) <= 1 and absi(cell.y - player_cell.y) <= 1:
				aimed += 1
				break
	eq(aimed, 4, "o corredor avisado alcança a vizinhança que a regra de contato usa")


func test_dart_telegraph_reaches_the_target_on_the_production_board() -> void:
	var definition := RoundDefinition.new()
	definition.boss_start = Vector2i(150, 100)
	var simulation := GameSimulation.new(GameRules.new(), definition, 17)
	var target := Vector2i(112, 141)
	simulation.player.reset(target)
	simulation.player.trail_active = true
	simulation.player.trail = PackedInt32Array([simulation.board.index_of(target.x, target.y)])
	simulation.board.set_cell(target.x, target.y, BoardState.Cell.TRAIL)
	var slot := DartRules.try_spawn(simulation.pools, simulation.board, target,
		DeterministicRng.new(17), 384, 24, 24, 900, MinorActorPools.Cause.EXPOSURE)
	eq(Vector2i(simulation.board.width, simulation.board.height), Vector2i(225, 283))
	eq(slot, 0)
	eq(simulation.pools.dart_cell(slot), Vector2i(1, 141), "24 é mínimo; o nascimento está a 111 células")
	var before := simulation.state_checksum()
	var view := QixMinorActorView.new()
	view.sync(simulation)
	var actor: Dictionary = view.presentation_state().darts[0]
	var target_screen := Vector2(CoordinateSpace.field_to_screen(target))
	ok(actor.path.size() > 48, "o aviso não pode parar na antiga janela de 48 células")
	ok(actor.path.has(target_screen), "a posição que motivou a mira precisa aparecer no aviso desenhado")
	eq(actor.corridor[actor.corridor.size() - 1], target_screen, "a trilha é o terminal real do disparo")
	eq(actor.muzzle.size(), QixMinorActorView.MUZZLE_CELLS + 1)
	eq(simulation.state_checksum(), before)
	view.free()


func test_boss_hunts_trail_even_when_base_pattern_wanders() -> void:
	var rules := GameRules.new()
	var profile := rules.boss_behavior as BossBehaviorProfile
	profile.pattern = BossBehaviorProfile.Pattern.WANDER
	profile.trail_hunt_from_phase = 1
	profile.trail_hunt_cells = 48
	var boss := BossState.new()
	boss.reset(Vector2i(10, 10), 0)
	boss.phase = 1
	var board := BoardState.new(31, 31)
	var player := PlayerState.new()
	player.reset(Vector2i(0, 15))
	player.trail_active = true
	player.trail = PackedInt32Array([board.index_of(10, 19), board.index_of(10, 20), board.index_of(10, 21)])
	for seed_value in [11, 2026, 90210]:
		var direction := BossMotion._decide_direction(boss, board, rules, player, DeterministicRng.new(seed_value))
		eq(direction, 4, "fase de caça mira o meio da trilha ao sul")
