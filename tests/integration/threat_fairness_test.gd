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
	# O teto do desenho precisa cobrir a distância em que o dardo nasce, senão o corredor é
	# cortado justamente antes do alvo e o aviso volta a esconder a mira.
	var min_range := ThreatProfile.new().dart_min_range
	ok(QixMinorActorView.TELEGRAPH_MAX_CELLS >= min_range * 2,
		"o teto de %d células cobre com folga o alcance mínimo de %d" % [QixMinorActorView.TELEGRAPH_MAX_CELLS, min_range])
	var reach := QixMinorActorView.TELEGRAPH_MAX_CELLS
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
