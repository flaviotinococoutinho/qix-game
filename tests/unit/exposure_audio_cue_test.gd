extends TestCase
## O limiar de exposição da trilha no canal **sonoro**.
##
## O canal visual desse limiar existe desde `TrailExposure` + HUD, e o háptico desde
## `exposure_haptics_test.gd`. Faltava o som: o único canal que chega ao jogador com o olhar
## preso ao chefe **e** com o telemóvel pousado na mesa, onde não há motor de vibração para
## sentir. O que se afirma aqui é o que o item pedia — que atravessar o limiar seja audível,
## com prioridade declarada, sem que nada disto volte para a simulação.


func test_the_exposure_cue_is_authored_and_agrees_with_the_haptic_ladder() -> void:
	var recipe: Dictionary = QixProceduralAudioLibrary.CUE_RECIPES.get(
		QixAudioDirector.EXPOSURE_CUE, {}
	)
	ok(not recipe.is_empty(), "o cue do limiar não está autorado")
	var haptics := QixHapticFeedback.new()
	var quiet: Array[GameEvent] = []
	var pulse := haptics.plan(quiet, true)
	eq(
		QixProceduralAudioLibrary.priority_for(QixAudioDirector.EXPOSURE_CUE),
		int(pulse["priority"]),
		"som e háptica têm de concordar sobre quanto pesa o mesmo instante",
	)
	eq(pulse["kind"], QixAudioDirector.EXPOSURE_CUE, "e sobre como se chama")


## O limiar não é um impacto: nada bateu, o estado é que mudou. Um transiente aqui soaria
## como erro do jogador — e o item explicitamente não quer repreender a aposta.
func test_the_exposure_cue_announces_instead_of_impacting_and_stays_below_the_reward() -> void:
	var cue := QixAudioDirector.EXPOSURE_CUE
	eq(QixProceduralAudioLibrary.onset_for(cue), &"announce")
	ok(
		QixProceduralAudioLibrary.duration_msec(cue)
		< QixProceduralAudioLibrary.duration_msec(&"round_clear"),
		"um aviso mais longo que o fecho da rodada deixa de ser aviso",
	)
	var exposure_gain := float(QixProceduralAudioLibrary.CUE_RECIPES[cue]["gain"])
	var capture_gain := float(QixProceduralAudioLibrary.CUE_RECIPES[&"capture"]["gain"])
	ok(
		exposure_gain < capture_gain,
		"o aviso não pode soar mais alto que a recompensa: %.2f >= %.2f"
		% [exposure_gain, capture_gain],
	)


## A regra que a háptica resolve por ter um só actuador, e que o mix — com oito vozes — tem
## de escrever à mão. Ver `QixAudioDirector.exposure_cue_survives`.
func test_the_warning_loses_its_object_when_something_louder_happened_in_the_same_tick() -> void:
	var louder: Array[StringName] = [&"capture"]
	ok(not QixAudioDirector.exposure_cue_survives(louder), "o laço fechou: a notícia é o território")
	var lethal: Array[StringName] = [&"death"]
	ok(not QixAudioDirector.exposure_cue_survives(lethal), "sem trilha não há exposição a avisar")
	var quieter: Array[StringName] = [&"respawn", &"round_start", &"trail"]
	ok(
		QixAudioDirector.exposure_cue_survives(quieter),
		"abaixo de 35 na escada: o aviso continua a ser o acontecimento do tick",
	)
	var nothing: Array[StringName] = []
	ok(QixAudioDirector.exposure_cue_survives(nothing), "tick calado deixa o aviso passar")


func test_the_director_gives_a_voice_to_the_crossing_and_only_to_the_crossing() -> void:
	var exposure_priority := QixProceduralAudioLibrary.priority_for(
		QixAudioDirector.EXPOSURE_CUE
	)
	var quiet: Array[GameEvent] = []

	var silent := _director_in_tree()
	silent.sync(null, quiet, false, false)
	eq(_holders(silent, exposure_priority), 0, "sem travessia, nenhuma voz segura o aviso")
	silent.free()

	var crossing := _director_in_tree()
	crossing.sync(null, quiet, false, true)
	eq(_holders(crossing, exposure_priority), 1, "a travessia soa, uma vez, numa voz")
	crossing.free()

	var busy := _director_in_tree()
	var captured: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.CAPTURED)]
	busy.sync(null, captured, false, true)
	eq(
		_holders(busy, exposure_priority),
		0,
		"com captura no mesmo tick o aviso não entra na voz livre ao lado dela",
	)
	eq(
		_holders(busy, QixProceduralAudioLibrary.priority_for(&"capture")),
		1,
		"…e a captura soa na mesma",
	)
	busy.free()


## A aresta tem um dono só (`QixHapticFeedback._previous_exposure`), e o hub lê-a antes de a
## avançar. Se `would_cross_warning` mutasse, o pulso háptico do mesmo tick desapareceria.
func test_the_hub_reads_the_edge_without_consuming_it() -> void:
	var haptics := QixHapticFeedback.new()
	var quiet: Array[GameEvent] = []
	var above := TrailExposure.WARNING_RATIO

	ok(not haptics.would_cross_warning(0.2), "trilha curta não atravessa nada")
	ok(haptics.would_cross_warning(above), "a leitura vê a aresta…")
	ok(haptics.would_cross_warning(above), "…e perguntá-la duas vezes não a gasta")
	eq(
		haptics.sync(quiet, above)["kind"],
		QixAudioDirector.EXPOSURE_CUE,
		"o pulso do tick continua lá depois de o som ter perguntado",
	)
	ok(not haptics.would_cross_warning(1.0), "e depois de `sync` a memória avançou")


func test_the_sound_of_the_threshold_does_not_move_the_domain() -> void:
	var hub := QixFeedbackHub.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(hub)
	hub.ensure_ready()
	var session := GameSession.new(_campaign())
	var before := session.simulation.state_checksum()
	var events: Array[GameEvent] = []
	for tick in 8:
		hub.sync(session, events, false)
	eq(
		session.simulation.state_checksum(),
		before,
		"sincronizar feedback é leitura: nada aqui escreve no domínio (invariantes 6 e 8)",
	)
	hub.free()


func _director_in_tree() -> QixAudioDirector:
	var director := QixAudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	director.ensure_ready()
	return director


## Quantas vozes seguram exactamente esta prioridade agora.
func _holders(director: QixAudioDirector, priority: int) -> int:
	var count := 0
	for held in director.voice_priorities_now():
		if held == priority:
			count += 1
	return count


func _campaign() -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"exposure_audio_cue_test"
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
