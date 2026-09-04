extends TestCase


func test_session_transitions_between_rounds_without_advancing_finished_simulation() -> void:
	var campaign := _campaign(2, 2)
	var session := GameSession.new(campaign)
	eq(session.phase, GameSession.Phase.ROUND_INTRO)
	eq(session.round_index, 0)
	eq(session.simulation.tick, 0)
	eq(session.replay.tick_count(), 0)
	session.step(MoveIntent.none())
	eq(session.phase, GameSession.Phase.ROUND_INTRO)
	session.step(MoveIntent.none())
	eq(session.phase, GameSession.Phase.PLAYING)
	eq(session.simulation.tick, 0, "intro nunca avança gameplay")
	_win_current_round(session)
	eq(session.phase, GameSession.Phase.ROUND_CLEAR)
	eq(session.records.size(), 1)
	var finished_simulation := session.simulation
	var finished_tick := finished_simulation.tick
	var finished_replay_ticks := session.replay.tick_count()
	var carried_score := finished_simulation.score
	var carried_lives := finished_simulation.lives
	session.step(MoveIntent.none())
	eq(finished_simulation.tick, finished_tick)
	eq(session.replay.tick_count(), finished_replay_ticks)
	session.step(MoveIntent.none())
	eq(session.phase, GameSession.Phase.ROUND_INTRO)
	eq(session.round_index, 1)
	ne(session.simulation, finished_simulation, "cada rodada recebe uma simulação nova")
	eq(session.simulation.score, carried_score)
	eq(session.simulation.lives, carried_lives)
	eq(session.simulation.board.owned_interior, 0)
	eq(session.simulation.permille, 0)
	eq(session.simulation.shield_ticks, session.current_content().rules.shield_ticks)
	eq(session.replay.tick_count(), 0, "replay não atravessa fronteira de rodada")


func test_last_round_reaches_campaign_complete_and_restart_is_clean() -> void:
	var campaign := _campaign(0, 1)
	campaign.rounds.resize(1)
	var session := GameSession.new(campaign)
	eq(session.phase, GameSession.Phase.PLAYING)
	_win_current_round(session)
	eq(session.phase, GameSession.Phase.ROUND_CLEAR)
	session.step(MoveIntent.none())
	eq(session.phase, GameSession.Phase.CAMPAIGN_COMPLETE)
	eq(session.records.size(), 1)
	eq(session.records[0].round_id, &"round_01")
	ok(session.records[0].completed)
	eq(session.records[0].replay.tick_count(), 8)
	var final_score := session.simulation.score
	session.restart_campaign()
	eq(session.round_index, 0)
	eq(session.phase, GameSession.Phase.PLAYING)
	eq(session.simulation.score, 0)
	eq(session.simulation.lives, 3)
	eq(session.records.size(), 0)
	ne(final_score, 0)


func test_confirm_skips_presentation_ticks_but_never_records_an_intent() -> void:
	var session := GameSession.new(_campaign(120, 120))
	var intro_events := session.step(MoveIntent.make(MoveIntent.Dir.DOWN, true), true)
	eq(session.phase, GameSession.Phase.PLAYING)
	eq(session.simulation.tick, 0)
	eq(session.replay.tick_count(), 0)
	ok(_has_event(intro_events, GameEvent.Kind.ROUND_STARTED))
	_win_current_round(session)
	var gameplay_ticks := session.simulation.tick
	var replay_ticks := session.replay.tick_count()
	var clear_events := session.step(MoveIntent.make(MoveIntent.Dir.UP, true), true)
	eq(session.phase, GameSession.Phase.ROUND_INTRO)
	eq(session.round_index, 1)
	eq(session.records[0].final_tick, gameplay_ticks)
	eq(session.records[0].replay.tick_count(), replay_ticks)
	ok(_has_event(clear_events, GameEvent.Kind.ROUND_INTRO_STARTED))


func test_archived_record_preserves_replay_start_state() -> void:
	var campaign := _campaign(0, 1)
	campaign.rounds.resize(1)
	var session := GameSession.new(campaign)
	_win_current_round(session)
	var start_state: RoundStartState = session.records[0].start_state
	ok(start_state != null)
	eq(start_state.score, 0)
	eq(start_state.lives, 3)
	ne(start_state, session.simulation.round_start_state, "registro recebe cópia imutável por convenção")
	var content := campaign.rounds[0]
	var replayed := GameSimulation.new(
		content.rules,
		content.round_definition,
		content.seed_value,
		start_state,
	)
	eq(session.records[0].replay.replay_into(replayed), session.records[0].final_checksum)


func _campaign(intro_ticks: int, clear_ticks: int) -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"session_test"
	campaign.intro_ticks = intro_ticks
	campaign.clear_ticks = clear_ticks
	campaign.rounds = [_content(1, 101), _content(2, 202)]
	return campaign


func _content(number: int, seed: int) -> RoundContent:
	var rules := GameRules.new()
	rules.target_permille = 500
	rules.completion_bonus = 123
	rules.substeps_normal = 1
	rules.substeps_speedup = 1
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.shield_ticks = 10_000
	var round_definition := RoundDefinition.new()
	round_definition.field_width = 9
	round_definition.field_height = 9
	round_definition.player_spawn = Vector2i(4, 0)
	round_definition.boss_start = Vector2i(6, 4)
	var visual := RoundVisualDefinition.new()
	visual.display_name = "ROUND %02d" % number
	visual.background = ImageTexture.create_from_image(
		Image.create_empty(9, 9, false, Image.FORMAT_RGBA8),
	)
	var content := RoundContent.new()
	content.round_id = StringName("round_%02d" % number)
	content.rules = rules
	content.round_definition = round_definition
	content.visual = visual
	content.seed_value = seed
	return content


func _win_current_round(session: GameSession) -> void:
	for _tick in 8:
		session.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))


func _has_event(events: Array[GameEvent], kind: int) -> bool:
	for event in events:
		if event.kind == kind:
			return true
	return false
