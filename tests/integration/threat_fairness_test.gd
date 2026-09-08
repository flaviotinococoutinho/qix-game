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
