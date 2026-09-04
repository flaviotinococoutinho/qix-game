extends TestCase

const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"
const BossBehaviorProfileScript = preload("res://game/enemies/boss_behavior_profile.gd")


func test_campaign_uses_three_distinct_authorable_boss_profiles() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	var expected_patterns := [
		BossBehaviorProfileScript.Pattern.WANDER,
		BossBehaviorProfileScript.Pattern.PURSUIT,
		BossBehaviorProfileScript.Pattern.SWEEP,
	]
	for index in campaign.rounds.size():
		var profile = campaign.rounds[index].rules.boss_behavior
		ok(profile != null, "cada rodada precisa de perfil explícito")
		if profile == null:
			continue
		eq(profile.pattern, expected_patterns[index])
		ok(profile.resource_path.begins_with("res://content/rules/boss_"))
		eq(profile.validation_errors(), PackedStringArray())


func test_campaign_boss_speed_never_exceeds_one_cell_per_substep() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	for content in campaign.rounds:
		var rules := content.rules as GameRules
		var peak_speed: int = rules.boss_speed_fp * rules.boss_behavior.pulse_speed_permille / 1000
		ok(peak_speed <= 256, "%s pode saltar células: %d" % [content.round_id, peak_speed])
		eq(rules.validation_errors(), PackedStringArray())


func test_each_authored_profile_is_deterministic_and_stays_inside_free_interior() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	var final_checksums: Array[PackedByteArray] = []
	for content in campaign.rounds:
		var rules := content.rules.duplicate(true) as GameRules
		rules.shield_ticks = 100_000
		rules.shield_critical_ticks = 0
		var simulation_a := GameSimulation.new(rules, content.round_definition, content.seed_value)
		var simulation_b := GameSimulation.new(rules, content.round_definition, content.seed_value)
		for _tick in 720:
			simulation_a.step(MoveIntent.none())
			simulation_b.step(MoveIntent.none())
			var cell := simulation_a.boss_cell()
			ok(cell.x > 0 and cell.y > 0)
			ok(cell.x < simulation_a.board.width - 1)
			ok(cell.y < simulation_a.board.height - 1)
			ok(simulation_a.board.get_cell(cell.x, cell.y) == BoardState.Cell.FREE)
		eq(simulation_a.state_checksum(), simulation_b.state_checksum())
		final_checksums.append(simulation_a.state_checksum())
	ne(final_checksums[0], final_checksums[1], "perfis diferentes precisam produzir trajetórias distintas")
	ne(final_checksums[1], final_checksums[2], "perfis diferentes precisam produzir trajetórias distintas")


func test_replay_round_trip_remains_exact_with_pursuit_and_speed_pulse() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	var content := campaign.rounds[1] as RoundContent
	var rules := content.rules.duplicate(true) as GameRules
	rules.shield_ticks = 100_000
	rules.shield_critical_ticks = 0
	var simulation := GameSimulation.new(rules, content.round_definition, content.seed_value)
	var replay := ReplayLog.start(simulation)
	for frame in 600:
		var intent := MoveIntent.none()
		if frame % 90 < 15:
			intent = MoveIntent.make(MoveIntent.Dir.RIGHT, false)
		replay.record(intent)
		simulation.step(intent)
	var replayed := GameSimulation.new(rules, content.round_definition, content.seed_value)
	eq(replay.replay_into(replayed), simulation.state_checksum())
	eq(replayed.state_checksum(), simulation.state_checksum())
	eq(replayed.rng.state, simulation.rng.state)
