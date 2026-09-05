extends TestCase

const BossBehaviorProfileScript = preload("res://game/rules/boss_behavior_profile.gd")
const BossBehaviorControllerScript = preload("res://game/simulation/enemies/boss_behavior_controller.gd")


func test_nearest_direction_uses_fixed_point_octants_without_floats() -> void:
	eq(BossBehaviorControllerScript.nearest_direction_index(Vector2i(10, 0)), 0)
	eq(BossBehaviorControllerScript.nearest_direction_index(Vector2i(10, 10)), 2)
	eq(BossBehaviorControllerScript.nearest_direction_index(Vector2i(0, 10)), 4)
	eq(BossBehaviorControllerScript.nearest_direction_index(Vector2i(-10, 0)), 8)
	eq(BossBehaviorControllerScript.nearest_direction_index(Vector2i(0, -10)), 12)
	eq(BossBehaviorControllerScript.nearest_direction_index(Vector2i(10, -10)), 14)


func test_profiles_reject_invalid_authoring_limits() -> void:
	var profile = BossBehaviorProfileScript.new()
	profile.pattern = 99
	profile.sweep_turn_steps = 0
	profile.pursuit_jitter_steps = 5
	profile.pulse_period_ticks = 10
	profile.pulse_duration_ticks = 11
	profile.pulse_speed_permille = 999
	var errors: PackedStringArray = profile.validation_errors()
	ok(_contains(errors, "pattern"))
	ok(_contains(errors, "sweep_turn_steps"))
	ok(_contains(errors, "pursuit_jitter_steps"))
	ok(_contains(errors, "pulse_duration_ticks"))
	ok(_contains(errors, "pulse_speed_permille"))


func test_wander_and_pursuit_randomness_are_seed_deterministic_and_bounded() -> void:
	var wander = BossBehaviorProfileScript.new()
	wander.pattern = BossBehaviorProfileScript.Pattern.WANDER
	var rng_a := DeterministicRng.new(0xA11CE)
	var rng_b := DeterministicRng.new(0xA11CE)
	for turn in 32:
		var a: int = BossBehaviorControllerScript.next_direction(
			wander, turn & 15, Vector2i.ZERO, Vector2i(20, 20), rng_a,
		)
		var b: int = BossBehaviorControllerScript.next_direction(
			wander, turn & 15, Vector2i.ZERO, Vector2i(20, 20), rng_b,
		)
		eq(a, b)
		ok(a >= 0 and a < 16)

	var pursuit = BossBehaviorProfileScript.new()
	pursuit.pattern = BossBehaviorProfileScript.Pattern.PURSUIT
	pursuit.pursuit_jitter_steps = 2
	rng_a = DeterministicRng.new(771)
	rng_b = DeterministicRng.new(771)
	for _turn in 32:
		var a: int = BossBehaviorControllerScript.next_direction(
			pursuit, 8, Vector2i.ZERO, Vector2i(100, 0), rng_a,
		)
		var b: int = BossBehaviorControllerScript.next_direction(
			pursuit, 8, Vector2i.ZERO, Vector2i(100, 0), rng_b,
		)
		eq(a, b)
		ok(_circular_distance(a, 0) <= 2, "jitter não pode fugir da janela autorada")


func test_pursuit_without_jitter_aims_at_player_and_sweep_wraps() -> void:
	var pursuit = BossBehaviorProfileScript.new()
	pursuit.pattern = BossBehaviorProfileScript.Pattern.PURSUIT
	pursuit.pursuit_jitter_steps = 0
	var rng := DeterministicRng.new(42)
	eq(BossBehaviorControllerScript.next_direction(
		pursuit, 1, Vector2i(4, 4), Vector2i(4, 20), rng,
	), 4)
	var state_before := rng.state
	eq(BossBehaviorControllerScript.next_direction(
		pursuit, 7, Vector2i(4, 4), Vector2i(4, 4), rng,
	), 7, "alvo sobreposto mantém direção sem consumir RNG")
	eq(rng.state, state_before)

	var sweep = BossBehaviorProfileScript.new()
	sweep.pattern = BossBehaviorProfileScript.Pattern.SWEEP
	sweep.sweep_turn_steps = 3
	eq(BossBehaviorControllerScript.next_direction(
		sweep, 15, Vector2i.ZERO, Vector2i.ZERO, rng,
	), 2)
	sweep.sweep_turn_steps = -3
	eq(BossBehaviorControllerScript.next_direction(
		sweep, 1, Vector2i.ZERO, Vector2i.ZERO, rng,
	), 14)


func test_speed_pulse_has_quiet_lead_in_and_exact_integer_boundaries() -> void:
	var profile = BossBehaviorProfileScript.new()
	profile.pulse_period_ticks = 240
	profile.pulse_duration_ticks = 60
	profile.pulse_speed_permille = 1500
	eq(BossBehaviorControllerScript.effective_speed_fp(profile, 100, 0), 100)
	eq(BossBehaviorControllerScript.effective_speed_fp(profile, 100, 179), 100)
	eq(BossBehaviorControllerScript.effective_speed_fp(profile, 100, 180), 150)
	eq(BossBehaviorControllerScript.effective_speed_fp(profile, 100, 239), 150)
	eq(BossBehaviorControllerScript.effective_speed_fp(profile, 100, 240), 100)


func test_reflections_preserve_the_orthogonal_component_and_are_involutions() -> void:
	for direction in 16:
		var horizontal: int = BossBehaviorControllerScript.reflected_horizontal(direction)
		var vertical: int = BossBehaviorControllerScript.reflected_vertical(direction)
		eq(BossBehaviorControllerScript.DIRECTION_X[horizontal], -BossBehaviorControllerScript.DIRECTION_X[direction])
		eq(BossBehaviorControllerScript.DIRECTION_Y[horizontal], BossBehaviorControllerScript.DIRECTION_Y[direction])
		eq(BossBehaviorControllerScript.DIRECTION_X[vertical], BossBehaviorControllerScript.DIRECTION_X[direction])
		eq(BossBehaviorControllerScript.DIRECTION_Y[vertical], -BossBehaviorControllerScript.DIRECTION_Y[direction])
		eq(BossBehaviorControllerScript.reflected_horizontal(horizontal), direction)
		eq(BossBehaviorControllerScript.reflected_vertical(vertical), direction)


func test_behavior_profile_is_part_of_rules_canonical_contract() -> void:
	var rules_a := GameRules.new()
	var rules_b := GameRules.new()
	var sweep = BossBehaviorProfileScript.new()
	sweep.pattern = BossBehaviorProfileScript.Pattern.SWEEP
	sweep.sweep_turn_steps = 2
	rules_b.boss_behavior = sweep
	ne(rules_a.canonical_bytes(), rules_b.canonical_bytes())
	ok(rules_a.validation_errors().is_empty())
	ok(rules_b.validation_errors().is_empty())
	var unsafe = BossBehaviorProfileScript.new()
	unsafe.pulse_period_ticks = 120
	unsafe.pulse_duration_ticks = 30
	unsafe.pulse_speed_permille = 1500
	rules_b.boss_speed_fp = 200
	rules_b.boss_behavior = unsafe
	ok(_contains(rules_b.validation_errors(), "exceder uma célula"))
	rules_b.boss_behavior = Resource.new()
	ok(_contains(rules_b.validation_errors(), "BossBehaviorProfile"))
	ok(rules_b.canonical_bytes().size() > 0, "configuração inválida ainda precisa ter hash estável para diagnóstico")


func test_replay_rejects_a_different_behavior_profile_before_mutation() -> void:
	var rules := GameRules.new()
	var definition := RoundDefinition.new()
	definition.field_width = 17
	definition.field_height = 13
	definition.player_spawn = Vector2i(8, 0)
	definition.boss_start = Vector2i(8, 6)
	var source := GameSimulation.new(rules, definition, 9182)
	var replay := ReplayLog.start(source)
	replay.record(MoveIntent.none())

	var changed_rules := GameRules.new()
	var pursuit = BossBehaviorProfileScript.new()
	pursuit.pattern = BossBehaviorProfileScript.Pattern.PURSUIT
	changed_rules.boss_behavior = pursuit
	var target := GameSimulation.new(changed_rules, definition, 9182)
	var before := target.state_checksum()
	ne(replay.compatibility_error(target), "")
	eq(replay.replay_into(target), PackedByteArray())
	eq(target.state_checksum(), before)


func test_enemy_presentation_exposes_pattern_and_pulse_without_mutating_simulation() -> void:
	var rules := GameRules.new()
	var profile = BossBehaviorProfileScript.new()
	profile.pattern = BossBehaviorProfileScript.Pattern.PURSUIT
	profile.pulse_period_ticks = 10
	profile.pulse_duration_ticks = 2
	profile.pulse_speed_permille = 1500
	rules.boss_behavior = profile
	rules.boss_turn_every_ticks = 0
	var definition := RoundDefinition.new()
	definition.field_width = 17
	definition.field_height = 13
	definition.player_spawn = Vector2i(8, 0)
	definition.boss_start = Vector2i(8, 6)
	var simulation := GameSimulation.new(rules, definition, 441)
	for _tick in 9:
		simulation.step(MoveIntent.none())
	var before := simulation.state_checksum()
	var view := QixEnemyView.new()
	view.sync(simulation)
	eq(view.presentation_state()["pattern"], BossBehaviorProfileScript.Pattern.PURSUIT)
	ok(view.presentation_state()["surging"])
	ok((view.presentation_state()["facing"] as Vector2).length() > 0.99)
	eq(simulation.state_checksum(), before)
	view.free()


func _contains(errors: PackedStringArray, needle: String) -> bool:
	for error in errors:
		if error.contains(needle):
			return true
	return false


func _circular_distance(a: int, b: int) -> int:
	var direct := absi(a - b)
	return mini(direct, 16 - direct)
