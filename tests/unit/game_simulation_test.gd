extends TestCase


func test_draw_close_capture_and_replay_are_deterministic() -> void:
	var rules := _test_rules()
	var round_definition := _test_round(Vector2i(6, 4))
	var simulation := GameSimulation.new(rules, round_definition, 12345)
	var replay := ReplayLog.start(simulation)
	var all_events: Array[GameEvent] = []
	for _y in range(1, 9):
		var intent := MoveIntent.make(MoveIntent.Dir.DOWN, true)
		replay.record(intent)
		all_events.append_array(simulation.step(intent))
	eq(simulation.player_index(), simulation.board.index_of(4, 8), "jogador fecha na borda inferior")
	eq(simulation.board.get_cell(2, 4), BoardState.Cell.CLAIMED)
	eq(simulation.board.get_cell(4, 4), BoardState.Cell.BOUNDARY)
	eq(simulation.board.get_cell(6, 4), BoardState.Cell.FREE, "lado do chefe permanece livre")
	eq(simulation.board.owned_interior, 28)
	eq(simulation.board.count_owned_interior(), 28)
	eq(simulation.permille, 571)
	ok(_has_event(all_events, GameEvent.Kind.TRAIL_STARTED))
	ok(_has_event(all_events, GameEvent.Kind.CAPTURED))
	ok(_has_event(all_events, GameEvent.Kind.PERCENT_CHANGED))
	var final_checksum := simulation.state_checksum()
	var replayed := GameSimulation.new(rules, round_definition, 12345)
	eq(replay.replay_into(replayed), final_checksum, "mesmos intents + seed ⇒ mesmo estado")
	eq(replayed.board.canonical_bytes(), simulation.board.canonical_bytes())


func test_boss_contact_undoes_trail_and_respawns_at_first_vertex() -> void:
	var rules := _test_rules()
	rules.death_ticks = 2
	rules.lives_start = 2
	var simulation := GameSimulation.new(rules, _test_round(Vector2i(4, 2)), 7)
	var death_events := simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	eq(simulation.phase, GameSimulation.Phase.DYING)
	eq(simulation.lives, 1)
	ok(_has_event(death_events, GameEvent.Kind.PLAYER_DIED))
	eq(simulation.trail.size(), 0)
	eq(simulation.board.get_cell(4, 1), BoardState.Cell.FREE, "morte desfaz toda a trilha")
	simulation.step(MoveIntent.none())
	var respawn_events := simulation.step(MoveIntent.none())
	eq(simulation.phase, GameSimulation.Phase.PLAYING)
	eq(Vector2i(simulation.px, simulation.py), Vector2i(4, 0))
	ok(_has_event(respawn_events, GameEvent.Kind.PLAYER_RESPAWNED))


func test_last_life_transitions_to_game_over() -> void:
	var rules := _test_rules()
	rules.death_ticks = 1
	rules.lives_start = 1
	var simulation := GameSimulation.new(rules, _test_round(Vector2i(4, 2)), 11)
	simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	var events := simulation.step(MoveIntent.none())
	eq(simulation.phase, GameSimulation.Phase.GAME_OVER)
	eq(simulation.lives, 0)
	ok(_has_event(events, GameEvent.Kind.GAME_OVER))


func test_capture_reaching_target_wins_and_awards_bonus() -> void:
	var rules := _test_rules()
	rules.target_permille = 500
	rules.completion_bonus = 123
	var simulation := GameSimulation.new(rules, _test_round(Vector2i(6, 4)), 19)
	var all_events: Array[GameEvent] = []
	for _y in range(1, 9):
		all_events.append_array(simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true)))
	eq(simulation.phase, GameSimulation.Phase.ROUND_WON)
	eq(simulation.permille, 571)
	eq(simulation.score, 5843, "trilha 10 + área 5710 + bônus 123")
	ok(_has_event(all_events, GameEvent.Kind.ROUND_WON))


func test_three_successive_captures_reach_eighty_percent_deterministically() -> void:
	var rules := _test_rules()
	var round_definition := _test_round_sized(13, 9, Vector2i(4, 0), Vector2i(11, 4))
	var simulation := GameSimulation.new(rules, round_definition, 23)
	var replay := ReplayLog.start(simulation)
	var all_events: Array[GameEvent] = []
	_step_repeated(simulation, replay, all_events, MoveIntent.Dir.DOWN, true, 8)
	eq(simulation.board.owned_interior, 28)
	eq(simulation.permille, 363)
	eq(simulation.phase, GameSimulation.Phase.PLAYING)
	_step_repeated(simulation, replay, all_events, MoveIntent.Dir.RIGHT, false, 4)
	_step_repeated(simulation, replay, all_events, MoveIntent.Dir.UP, true, 8)
	eq(simulation.board.owned_interior, 56)
	eq(simulation.permille, 727)
	eq(simulation.phase, GameSimulation.Phase.PLAYING)
	_step_repeated(simulation, replay, all_events, MoveIntent.Dir.RIGHT, false, 1)
	_step_repeated(simulation, replay, all_events, MoveIntent.Dir.DOWN, true, 8)
	eq(simulation.board.owned_interior, 63)
	eq(simulation.board.count_owned_interior(), 63)
	eq(simulation.permille, 818)
	eq(simulation.fills_done, 3)
	eq(simulation.score, 9210)
	eq(simulation.phase, GameSimulation.Phase.ROUND_WON)
	eq(_count_events(all_events, GameEvent.Kind.CAPTURED), 3)
	eq(_count_events(all_events, GameEvent.Kind.ROUND_WON), 1)
	eq(replay.tick_count(), 29)
	eq(simulation.board.get_cell(11, 4), BoardState.Cell.FREE)
	var replayed := GameSimulation.new(rules, round_definition, 23)
	eq(replay.replay_into(replayed), simulation.state_checksum())
	eq(replayed.board.canonical_bytes(), simulation.board.canonical_bytes())


func test_capture_wins_same_tick_when_lethal_contact_rule_is_disabled() -> void:
	var rules := _test_rules()
	rules.substeps_normal = 2
	rules.lethal_contact_wins = false
	var simulation := GameSimulation.new(rules, _test_round(Vector2i(5, 7)), 29)
	var all_events: Array[GameEvent] = []
	for _tick in 4:
		all_events.append_array(simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true)))
	eq(simulation.phase, GameSimulation.Phase.PLAYING)
	eq(simulation.lives, rules.lives_start, "captura vencedora não deve também consumir vida")
	eq(simulation.board.owned_interior, 28)
	ok(_has_event(all_events, GameEvent.Kind.CAPTURED))
	ok(not _has_event(all_events, GameEvent.Kind.PLAYER_DIED))


func test_lethal_contact_discards_same_tick_capture_by_default() -> void:
	var rules := _test_rules()
	rules.substeps_normal = 2
	var simulation := GameSimulation.new(rules, _test_round(Vector2i(5, 7)), 31)
	var all_events: Array[GameEvent] = []
	for _tick in 4:
		all_events.append_array(simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true)))
	eq(simulation.phase, GameSimulation.Phase.DYING)
	eq(simulation.lives, rules.lives_start - 1)
	eq(simulation.board.owned_interior, 0)
	ok(not _has_event(all_events, GameEvent.Kind.CAPTURED))
	ok(_has_event(all_events, GameEvent.Kind.PLAYER_DIED))


func test_replay_binary_round_trip_preserves_canonical_payload() -> void:
	var rules := _test_rules()
	var round_definition := _test_round(Vector2i(6, 4))
	var simulation := GameSimulation.new(rules, round_definition, 0xCAFE)
	var replay := ReplayLog.start(simulation)
	replay.record(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	replay.record(MoveIntent.make(MoveIntent.Dir.RIGHT, false))
	replay.record(MoveIntent.none())
	var encoded := replay.to_bytes()
	var decoded := ReplayLog.from_bytes(encoded)
	ok(decoded != null, "payload canônico precisa desserializar")
	if decoded == null:
		return
	eq(decoded.to_bytes(), encoded)
	eq(decoded.checksum(), replay.checksum())
	eq(decoded.seed_value, replay.seed_value)
	eq(decoded.round_hash, replay.round_hash)
	eq(decoded.initial_checksum, replay.initial_checksum)
	eq(decoded.intents, replay.intents)


func _test_rules() -> GameRules:
	var rules := GameRules.new()
	rules.substeps_normal = 1
	rules.substeps_speedup = 1
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.shield_ticks = 10_000
	return rules


func _test_round(boss_position: Vector2i) -> RoundDefinition:
	return _test_round_sized(9, 9, Vector2i(4, 0), boss_position)


func _test_round_sized(
	width: int,
	height: int,
	player_spawn: Vector2i,
	boss_position: Vector2i,
) -> RoundDefinition:
	var round_definition := RoundDefinition.new()
	round_definition.field_width = width
	round_definition.field_height = height
	round_definition.player_spawn = player_spawn
	round_definition.boss_start = boss_position
	round_definition.boss_dir_index = 0
	return round_definition


func _step_repeated(
	simulation: GameSimulation,
	replay: ReplayLog,
	events: Array[GameEvent],
	direction: int,
	drawing: bool,
	count: int,
) -> void:
	for _tick in count:
		var intent := MoveIntent.make(direction, drawing)
		replay.record(intent)
		events.append_array(simulation.step(intent))


func _has_event(events: Array[GameEvent], kind: int) -> bool:
	for event in events:
		if event.kind == kind:
			return true
	return false


func _count_events(events: Array[GameEvent], kind: int) -> int:
	var count := 0
	for event in events:
		if event.kind == kind:
			count += 1
	return count
