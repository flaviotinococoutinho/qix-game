extends TestCase
## Rota humana reproduzível: só usa intents públicos e nunca desativa ou move o chefe nem o
## diretor de ameaça — vagalumes, dardos e as fases do Núcleo estão todos ativos.

const ROUTES := [
	# R1: velocidade da primeira baliza encurta o segundo traço; a faixa central evita
	# o Núcleo que agora patrulha a antiga rota x80. Fecha com uma faixa curta em x56.
	[
		[MoveIntent.Dir.LEFT, false, 36], [MoveIntent.Dir.DOWN, true, 141],
		[MoveIntent.Dir.RIGHT, false, 20], [MoveIntent.Dir.UP, true, 72],
		[MoveIntent.Dir.DOWN, false, 25], [MoveIntent.Dir.LEFT, true, 21],
		[MoveIntent.Dir.RIGHT, false, 4], [MoveIntent.Dir.DOWN, true, 47],
	],
	[
		[MoveIntent.Dir.LEFT, false, 6], [MoveIntent.Dir.DOWN, true, 141],
		[MoveIntent.Dir.UP, false, 61], [MoveIntent.Dir.LEFT, true, 50],
	],
	# R3: usa os 180 ticks de estase para cruzar pelo topo; dois cortes curtos finais
	# contornam a zona de caça, ao sul (y178) e ao norte (y54).
	[
		[MoveIntent.Dir.LEFT, false, 16], [MoveIntent.Dir.DOWN, true, 141],
		[MoveIntent.Dir.UP, false, 71], [MoveIntent.Dir.RIGHT, false, 25],
		[MoveIntent.Dir.DOWN, true, 72], [MoveIntent.Dir.UP, false, 26],
		[MoveIntent.Dir.LEFT, true, 26], [MoveIntent.Dir.UP, false, 31],
		[MoveIntent.Dir.RIGHT, true, 26],
	],
]

const EXPECTED_PROGRESSION := [
	[179, 645, 771, 818],
	[556, 808],
	[358, 556, 720, 805],
]


func test_full_campaign_route_completes_with_active_boss_no_deaths_and_exact_replays() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	var session := GameSession.new(campaign)
	var completed_scores := PackedInt32Array()
	var seen_items := {}
	var beacon_count := 0
	for round_index in campaign.rounds.size():
		ok(campaign.rounds[round_index].rules.boss_substeps > 0, "chefe precisa estar ativo")
		ok(campaign.rounds[round_index].rules.threat.enabled, "diretor precisa estar ativo")
		ok(campaign.rounds[round_index].rules.items.enabled, "itens precisam estar ativos")
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
					if event.kind == GameEvent.Kind.ITEM_STARTED:
						seen_items[event.data.item] = true
					if event.kind == GameEvent.Kind.BEACON_CAPTURED:
						beacon_count += 1
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
	eq(completed_scores, PackedInt32Array([15_595, 29_865, 46_045]))
	eq(seen_items.size(), 4, "rota exercita todos os quatro itens")
	eq(beacon_count, 10, "balizas confirmadas nas três rodadas")
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
