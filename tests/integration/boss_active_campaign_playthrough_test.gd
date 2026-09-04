extends TestCase
## Rota humana reproduzível: só usa intents públicos e nunca desativa ou move o chefe.

const ROUTES := [
	[
		[MoveIntent.Dir.LEFT, false, 36], [MoveIntent.Dir.DOWN, true, 141],
		[MoveIntent.Dir.RIGHT, false, 20], [MoveIntent.Dir.UP, true, 141],
		[MoveIntent.Dir.RIGHT, false, 15], [MoveIntent.Dir.DOWN, true, 141],
		[MoveIntent.Dir.RIGHT, false, 25], [MoveIntent.Dir.UP, true, 141],
		[MoveIntent.Dir.RIGHT, false, 15], [MoveIntent.Dir.DOWN, true, 141],
	],
	[
		[MoveIntent.Dir.LEFT, false, 6], [MoveIntent.Dir.DOWN, true, 141],
		[MoveIntent.Dir.UP, false, 61], [MoveIntent.Dir.LEFT, true, 50],
	],
	[
		[MoveIntent.Dir.LEFT, false, 16], [MoveIntent.Dir.DOWN, true, 141],
		[MoveIntent.Dir.RIGHT, false, 40], [MoveIntent.Dir.UP, true, 141],
		[MoveIntent.Dir.DOWN, false, 70], [MoveIntent.Dir.LEFT, true, 40],
	],
]

const EXPECTED_PROGRESSION := [
	[179, 358, 493, 717, 869],
	[556, 808],
	[358, 645, 824],
]


func test_full_campaign_route_completes_with_active_boss_no_deaths_and_exact_replays() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	var session := GameSession.new(campaign)
	var completed_scores := PackedInt32Array()
	for round_index in campaign.rounds.size():
		ok(campaign.rounds[round_index].rules.boss_substeps > 0, "chefe precisa estar ativo")
		session.step(MoveIntent.none(), true)
		eq(session.phase, GameSession.Phase.PLAYING)
		var progression := PackedInt32Array()
		var death_seen := false
		var fills_before := 0
		for segment in ROUTES[round_index]:
			for _tick in int(segment[2]):
				var events := session.step(MoveIntent.make(segment[0], segment[1]))
				for event in events:
					if event.kind == GameEvent.Kind.PLAYER_DIED:
						death_seen = true
			if bool(segment[1]) and session.simulation.fills_done > fills_before:
				progression.append(session.simulation.permille)
				fills_before = session.simulation.fills_done
		ok(not death_seen, "rota balanceada não deve exigir sacrificar vida")
		eq(progression, PackedInt32Array(EXPECTED_PROGRESSION[round_index]))
		eq(session.phase, GameSession.Phase.ROUND_CLEAR)
		eq(session.simulation.lives, 3)
		completed_scores.append(session.simulation.score)
		session.step(MoveIntent.none(), true)
		if round_index + 1 < campaign.rounds.size():
			eq(session.phase, GameSession.Phase.ROUND_INTRO)
		else:
			eq(session.phase, GameSession.Phase.CAMPAIGN_COMPLETE)

	eq(session.records.size(), 3)
	eq(completed_scores, PackedInt32Array([13_190, 23_960, 36_290]))
	for record in session.records:
		ok(record.completed)
		var content := campaign.rounds[record.round_index] as RoundContent
		var replayed := GameSimulation.new(
			content.rules,
			content.round_definition,
			content.seed_value,
			record.start_state,
		)
		eq(record.replay.replay_into(replayed), record.final_checksum)
		eq(replayed.state_checksum(), record.final_checksum)
