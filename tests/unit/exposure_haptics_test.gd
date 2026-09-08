extends TestCase
## O limiar de exposição da trilha no canal háptico.
##
## O canal visual desse limiar já existe (`TrailExposure` + HUD). O que se afirma aqui é o
## que faltava: que atravessá-lo se **sente**, uma vez só, no tick certo, e que continua a
## ser leitura — nada disto volta para a simulação.


func test_crossed_warning_is_an_edge_and_rearms_on_the_way_down() -> void:
	var below := TrailExposure.WARNING_RATIO - 0.01
	var above := TrailExposure.WARNING_RATIO
	ok(TrailExposure.crossed_warning(below, above), "subir através do limiar é a aresta")
	ok(not TrailExposure.crossed_warning(above, above), "continuar exposto não é atravessar")
	ok(not TrailExposure.crossed_warning(below, below), "continuar curto não é atravessar")
	ok(not TrailExposure.crossed_warning(above, below), "descer não dispara")
	ok(
		TrailExposure.crossed_warning(below, 1.0) and TrailExposure.crossed_warning(0.0, above),
		"a aresta não depende de quão longe se passou do limiar",
	)


func test_threshold_crossing_taps_once_and_not_every_tick_above_it() -> void:
	var haptics := QixHapticFeedback.new()
	var quiet: Array[GameEvent] = []
	eq(haptics.sync(quiet, 0.2), {}, "trilha curta não toca em nada")
	var crossing := haptics.sync(quiet, TrailExposure.WARNING_RATIO)
	eq(crossing["kind"], &"exposure", "o tick da travessia é o que se sente")
	eq(int(crossing["priority"]), 35)
	ok(int(crossing["duration_ms"]) <= 90, "é um toque, não um alarme")
	ok(
		float(crossing["strong"]) < 0.2 and float(crossing["weak"]) < 0.4,
		"a exposição foi escolhida pelo jogador: o jogo confirma a aposta, não repreende",
	)
	eq(haptics.sync(quiet, 0.9), {}, "seguir exposto não repete o aviso")
	eq(haptics.sync(quiet, 1.0), {}, "nem quando a exposição ainda sobe")
	eq(haptics.sync(quiet, 0.1), {}, "recolher a trilha também não toca")
	eq(haptics.sync(quiet, 1.0)["kind"], &"exposure", "mas apostar de novo, sim")


func test_the_single_pulse_of_the_tick_goes_to_the_louder_news() -> void:
	var above := TrailExposure.WARNING_RATIO
	for kind in [GameEvent.Kind.PLAYER_DIED, GameEvent.Kind.CAPTURED]:
		var haptics := QixHapticFeedback.new()
		var events: Array[GameEvent] = [GameEvent.make(kind)]
		ne(
			haptics.sync(events, above)["kind"],
			&"exposure",
			"o laço fechou ou a vida acabou: o aviso perdeu o objeto",
		)
	var quieter := QixHapticFeedback.new()
	var respawn: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.PLAYER_RESPAWNED)]
	eq(
		quieter.sync(respawn, above)["kind"],
		&"exposure",
		"acima do respawn na escada: 35 > 30",
	)


func test_disabled_haptics_still_track_exposure_so_re_enabling_never_fires_a_stale_edge() -> void:
	var haptics := QixHapticFeedback.new()
	haptics.enabled = false
	var quiet: Array[GameEvent] = []
	eq(haptics.sync(quiet, 1.0), {}, "desligado não toca")
	haptics.enabled = true
	eq(
		haptics.sync(quiet, 1.0),
		{},
		"religar num traço já longo não pode ressuscitar uma aresta atravessada faz tempo",
	)


func test_hub_reads_exposure_from_the_session_and_leaves_it_untouched() -> void:
	eq(QixFeedbackHub.exposure_of(null), 0.0, "sem sessão não há leitura")
	var session := GameSession.new(_campaign())
	var before := session.simulation.state_checksum()
	eq(
		QixFeedbackHub.exposure_of(session),
		TrailExposure.of_simulation(session.simulation),
		"o hub não recalcula a curva por conta própria; delega a quem é dono dela",
	)
	eq(QixFeedbackHub.exposure_of(session), 0.0, "sem trilha activa não há exposição")
	eq(
		session.simulation.state_checksum(),
		before,
		"ler a exposição não move o domínio (invariantes 6 e 8)",
	)


func _campaign() -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"exposure_haptics_test"
	campaign.intro_ticks = 0
	campaign.clear_ticks = 0
	campaign.rounds = [_round()]
	return campaign


func _round() -> RoundContent:
	var rules := GameRules.new()
	rules.target_permille = 800
	var definition := RoundDefinition.new()
	definition.field_width = 13
	definition.field_height = 9
	definition.player_spawn = Vector2i(6, 0)
	definition.boss_start = Vector2i(10, 4)
	var visual := RoundVisualDefinition.new()
	visual.display_name = "ABYSSAL RELAY"
	visual.subtitle = "RESTORE A CARTOGRAFIA PERDIDA"
	visual.background = ImageTexture.create_from_image(Image.create(13, 9, false, Image.FORMAT_RGBA8))
	var content := RoundContent.new()
	content.round_id = &"abyss"
	content.rules = rules
	content.round_definition = definition
	content.seed_value = 11
	content.visual = visual
	return content
