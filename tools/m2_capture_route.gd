extends RefCounted
## Rota determinística de aceitação do G2 no campo real 225×283.
## O boss é imobilizado e ameaça/itens/escada ficam inertes somente na cópia de QA para
## isolar captura, revelação e transição. A campanha com todos os sistemas tem outra rota.

const EXPECTED_PROGRESSION := [179, 358, 493, 780, 825]


static func execute(authored_campaign: CampaignDefinition) -> Dictionary:
	var errors := PackedStringArray()
	if authored_campaign == null:
		errors.append("campanha ausente")
		return {"errors": errors}
	var campaign := _qa_campaign(authored_campaign)
	for error in campaign.validation_errors():
		errors.append("campanha QA inválida: %s" % error)
	if not errors.is_empty():
		return {"errors": errors}

	var session := GameSession.new(campaign)
	session.step(MoveIntent.none(), true)
	if session.phase != GameSession.Phase.PLAYING:
		errors.append("intro não liberou gameplay")

	var progression := PackedInt32Array()
	_drive(session, MoveIntent.Dir.LEFT, false, 36)
	_drive(session, MoveIntent.Dir.DOWN, true, 141)
	progression.append(session.simulation.permille)
	_drive(session, MoveIntent.Dir.RIGHT, false, 20)
	_drive(session, MoveIntent.Dir.UP, true, 141)
	progression.append(session.simulation.permille)
	_drive(session, MoveIntent.Dir.RIGHT, false, 15)
	_drive(session, MoveIntent.Dir.DOWN, true, 141)
	progression.append(session.simulation.permille)
	_drive(session, MoveIntent.Dir.RIGHT, false, 25)
	_drive(session, MoveIntent.Dir.UP, true, 141)
	progression.append(session.simulation.permille)
	_drive(session, MoveIntent.Dir.LEFT, false, 5)
	_drive(session, MoveIntent.Dir.DOWN, true, 141)
	progression.append(session.simulation.permille)

	if progression != PackedInt32Array(EXPECTED_PROGRESSION):
		errors.append("progressão divergente: %s" % str(progression))
	if session.phase != GameSession.Phase.ROUND_CLEAR:
		errors.append("última captura não entrou em ROUND_CLEAR")
	if session.records.size() != 1:
		errors.append("rodada concluída não foi arquivada exatamente uma vez")

	var round_one_score := session.simulation.score
	var capture_count := session.simulation.fills_done
	var archived_replay_ticks := session.records[0].replay.tick_count() if session.records.size() == 1 else -1
	session.step(MoveIntent.none(), true)

	return {
		"errors": errors,
		"boss_profile": "immobilized QA fixture",
		"permille_progression": progression,
		"capture_count": capture_count,
		"round_one_score": round_one_score,
		"archived_replay_ticks": archived_replay_ticks,
		"round_index": session.round_index,
		"phase": session.phase,
		"carried_score": session.simulation.score,
		"carried_lives": session.simulation.lives,
		"new_board_owned": session.simulation.board.owned_interior,
		"new_replay_ticks": session.replay.tick_count(),
	}


static func _qa_campaign(source: CampaignDefinition) -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"lumen_cartography_m2_acceptance"
	campaign.intro_ticks = source.intro_ticks
	campaign.clear_ticks = source.clear_ticks
	var rounds: Array[RoundContent] = []
	for source_content in source.rounds:
		var content := RoundContent.new()
		content.round_id = source_content.round_id
		content.rules = source_content.rules.duplicate(true) as GameRules
		# Diretor inerte: a rota M2 isola captura, revelação e transição do elenco menor.
		content.rules.threat = ThreatProfile.inert()
		(content.rules.items as ItemProfile).enabled = false
		(content.rules.bonus_ladder as BonusLadder).enabled = false
		content.round_definition = source_content.round_definition.duplicate(true) as RoundDefinition
		content.seed_value = source_content.seed_value
		content.visual = source_content.visual
		rounds.append(content)
	campaign.rounds = rounds
	# Geometria e regra de anchor/percentual de produção; bônus fixo é o controle da fixture.
	campaign.rounds[0].rules.boss_substeps = 0
	return campaign


static func _drive(
	session: GameSession,
	direction: int,
	drawing: bool,
	ticks: int,
) -> void:
	for _tick in ticks:
		session.step(MoveIntent.make(direction, drawing))
