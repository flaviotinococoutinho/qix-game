extends TestCase


func test_compatible_replay_has_no_contract_error() -> void:
	var fixture := _fixture(101)
	var replay := ReplayLog.start(fixture.simulation)
	replay.record(MoveIntent.make(MoveIntent.Dir.RIGHT, false))
	eq(replay.compatibility_error(_fixture(101).simulation), "")


func test_replay_rejects_different_seed_rules_and_round() -> void:
	var fixture := _fixture(101)
	var replay := ReplayLog.start(fixture.simulation)
	ne(replay.compatibility_error(_fixture(102).simulation), "", "seed diferente")
	var rules_changed := _fixture(101)
	rules_changed.simulation.rules.target_permille = 700
	ne(replay.compatibility_error(rules_changed.simulation), "", "rules diferentes")
	var round_changed := _fixture(101)
	round_changed.simulation.round_def.boss_start = Vector2i(5, 3)
	ne(replay.compatibility_error(round_changed.simulation), "", "round diferente")


func test_replay_rejects_simulation_that_already_advanced_without_mutating_it() -> void:
	var fixture := _fixture(303)
	var replay := ReplayLog.start(fixture.simulation)
	fixture.simulation.step(MoveIntent.none())
	var before: PackedByteArray = fixture.simulation.state_checksum()
	ne(replay.compatibility_error(fixture.simulation), "")
	eq(replay.replay_into(fixture.simulation), PackedByteArray())
	eq(fixture.simulation.state_checksum(), before)


func test_seed_is_canonical_u32_across_binary_round_trip() -> void:
	var source := _fixture(-1).simulation as GameSimulation
	eq(source.seed_value, 0xFFFFFFFF)
	var replay := ReplayLog.start(source)
	var decoded := ReplayLog.from_bytes(replay.to_bytes())
	ok(decoded != null)
	if decoded == null:
		return
	eq(decoded.seed_value, 0xFFFFFFFF)
	eq(decoded.compatibility_error(_fixture(-1).simulation), "")


func _fixture(seed_value: int) -> Dictionary:
	var rules := GameRules.new()
	rules.substeps_normal = 1
	rules.substeps_speedup = 1
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	var round_definition := RoundDefinition.new()
	round_definition.field_width = 9
	round_definition.field_height = 9
	round_definition.player_spawn = Vector2i(4, 0)
	round_definition.boss_start = Vector2i(6, 4)
	return {"simulation": GameSimulation.new(rules, round_definition, seed_value)}
