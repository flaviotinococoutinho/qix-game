extends TestCase
## Defende o contrato de `GameSession.records` documentado no cabeçalho do campo.
##
## Arquivo próprio, e não um teste a mais em `game_session_test.gd`, porque o runner descobre
## testes varrendo diretório: arquivo novo não disputa linhas com a fila de PRs abertos.


func test_records_stays_empty_until_a_round_actually_ends() -> void:
	var session := GameSession.new(_campaign(2, 2))
	eq(session.phase, GameSession.Phase.ROUND_INTRO)
	eq(session.records.size(), 0, "entrar numa rodada não arquiva")
	session.step(MoveIntent.none())
	session.step(MoveIntent.none())
	eq(session.phase, GameSession.Phase.PLAYING)
	eq(session.records.size(), 0)
	for _tick in 4:
		session.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	eq(session.phase, GameSession.Phase.PLAYING, "rota escolhida ainda não fecha a rodada")
	eq(session.records.size(), 0, "jogar não arquiva; encerrar arquiva")


func test_forcing_the_phase_from_outside_archives_nothing() -> void:
	var session := GameSession.new(_campaign(0, 4))
	eq(session.phase, GameSession.Phase.PLAYING)
	session.phase = GameSession.Phase.ROUND_CLEAR
	session.transition_ticks_left = 4
	session.transition_ticks_total = 4
	session.step(MoveIntent.none())
	eq(
		session.records.size(),
		0,
		"a fase é consequência do arquivamento, não a sua causa: só `step` a partir de PLAYING arquiva",
	)


func test_extra_ticks_in_the_terminal_phase_never_append_a_second_record() -> void:
	var session := GameSession.new(_campaign(0, 6))
	_win_current_round(session)
	eq(session.phase, GameSession.Phase.ROUND_CLEAR)
	eq(session.records.size(), 1)
	var archived: RoundRunRecord = session.records[0]
	for _tick in 4:
		session.step(MoveIntent.none())
	eq(session.phase, GameSession.Phase.ROUND_CLEAR, "ainda na transição")
	# Quem garante isto é a máquina de fases: arquivar já tirou a sessão de PLAYING, e só PLAYING
	# arquiva. O booleano `_current_archived` que duplicava essa regra saiu — ver o teste abaixo.
	eq(session.records.size(), 1, "uma entrada por rodada")
	eq(session.records[0], archived, "e é a mesma entrada, não uma cópia nova")


func test_a_lost_round_archives_with_completed_false() -> void:
	var session := GameSession.new(_losing_campaign())
	eq(session.phase, GameSession.Phase.PLAYING)
	eq(session.records.size(), 0)
	# escudo de 1 tick e uma vida: o tick 1 mata, o tick 2 resolve a morte em GAME_OVER.
	session.step(MoveIntent.none())
	session.step(MoveIntent.none())
	eq(session.simulation.phase, GameSimulation.Phase.GAME_OVER)
	eq(session.phase, GameSession.Phase.GAME_OVER)
	eq(session.records.size(), 1, "derrota arquiva tanto quanto vitória")
	ok(not session.records[0].completed, "`completed` é o que distingue as duas")
	eq(session.records[0].round_index, 0)
	for _tick in 3:
		session.step(MoveIntent.none())
	eq(session.records.size(), 1, "GAME_OVER é fase terminal; ticks nela não acumulam registros")


func test_records_size_counts_finished_attempts_not_visited_rounds() -> void:
	var session := GameSession.new(_campaign(0, 1))
	eq(session.current_round_number(), 1)
	eq(session.records.size(), session.current_round_number() - 1)
	_win_current_round(session)
	session.step(MoveIntent.none())          # ROUND_CLEAR → próxima rodada
	eq(session.phase, GameSession.Phase.PLAYING)
	eq(session.current_round_number(), 2)
	eq(session.records.size(), session.current_round_number() - 1)
	_win_current_round(session)
	session.step(MoveIntent.none())
	eq(session.phase, GameSession.Phase.CAMPAIGN_COMPLETE)
	eq(session.records.size(), 2, "campanha completa: uma entrada por rodada encerrada")
	session.restart_campaign()
	eq(session.records.size(), 0, "restart_campaign esvazia a lista")


## O que o antigo `_current_archived` fingia proteger, agora medido em vez de absorvido: nenhum
## tick pode acrescentar mais de um registro, e um registro só nasce de um tick que **começou**
## em PLAYING. Antes, um segundo arquivamento no mesmo tick era silenciosamente descartado pelo
## booleano; hoje ele aparece como falha aqui, que é onde um defeito da máquina de fases deve doer.
func test_a_record_only_appears_on_a_step_that_started_in_playing() -> void:
	var sessions: Array[GameSession] = [
		GameSession.new(_campaign(2, 3)),
		GameSession.new(_losing_campaign()),
	]
	for session: GameSession in sessions:
		var terminal: Array[int] = [GameSession.Phase.GAME_OVER, GameSession.Phase.CAMPAIGN_COMPLETE]
		var archived_from_playing := 0
		for _tick in 64:
			if terminal.has(session.phase):
				break
			var phase_before := session.phase
			var before := session.records.size()
			session.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
			var appended := session.records.size() - before
			ok(appended == 0 or appended == 1, "um tick arquiva no máximo uma tentativa")
			if appended == 1:
				eq(
					phase_before,
					GameSession.Phase.PLAYING,
					"registro nasceu de um tick que não começou em PLAYING",
				)
				archived_from_playing += 1
		ok(archived_from_playing > 0, "a rota precisa encerrar alguma tentativa para medir algo")
		eq(session.records.size(), archived_from_playing, "toda entrada veio de um desses ticks")


func _campaign(intro_ticks: int, clear_ticks: int) -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"records_contract_test"
	campaign.intro_ticks = intro_ticks
	campaign.clear_ticks = clear_ticks
	campaign.rounds = [_content(1, 101, _rules()), _content(2, 202, _rules())]
	return campaign


## Campanha de uma rodada só que termina em derrota sem depender do chefe: o escudo expira.
func _losing_campaign() -> CampaignDefinition:
	var rules := _rules()
	rules.lives_start = 1
	rules.shield_ticks = 1
	rules.shield_critical_ticks = 0
	rules.shield_pauses_during_trail = false
	rules.death_ticks = 0
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"records_contract_loss"
	campaign.intro_ticks = 0
	campaign.clear_ticks = 1
	campaign.rounds = [_content(1, 303, rules)]
	return campaign


func _rules() -> GameRules:
	var rules := GameRules.new()
	rules.target_permille = 500
	rules.completion_bonus = 123
	rules.substeps_normal = 1
	rules.substeps_speedup = 1
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.shield_ticks = 10_000
	return rules


func _content(number: int, seed: int, rules: GameRules) -> RoundContent:
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
