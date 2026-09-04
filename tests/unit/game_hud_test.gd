extends TestCase


func test_boss_death_message_is_immediate_and_specific() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _simulation_in_dying_phase()
	hud.sync(simulation, false, [GameEvent.make(
		GameEvent.Kind.PLAYER_DIED,
		{"reason": GameSimulation.DeathReason.BOSS_CONTACT, "lives": simulation.lives},
	)])
	eq((hud.get_node("Status") as Label).text, "CONTATO! · REENTRADA")
	hud.free()


func test_shield_death_message_is_immediate_and_specific() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _simulation_in_dying_phase()
	hud.sync(simulation, false, [GameEvent.make(
		GameEvent.Kind.PLAYER_DIED,
		{"reason": GameSimulation.DeathReason.SHIELD_EXPIRED, "lives": simulation.lives},
	)])
	eq((hud.get_node("Status") as Label).text, "ESCUDO ESGOTADO · REENTRADA")
	hud.free()


func test_percent_counter_climbs_by_denomination_instead_of_snapping() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _playing_simulation()
	hud.sync(simulation, false, [])
	eq((hud.get_node("Percent") as Label).text, "00.0/80", "a primeira leitura assenta")

	simulation.permille = 234
	var before := simulation.state_checksum()
	hud.sync(simulation, false, [])
	eq(
		(hud.get_node("Percent") as Label).text,
		"10.0/80",
		"o primeiro degrau fecha a dezena de %, não o valor inteiro",
	)
	_assert_bar_agrees_with_number(hud, simulation, "no primeiro degrau")

	var ticks := 1
	while (hud.get_node("Percent") as Label).text != "23.4/80" and ticks < 200:
		hud.sync(simulation, false, [])
		ticks += 1
	eq((hud.get_node("Percent") as Label).text, "23.4/80", "o contador chega ao valor confirmado")
	ok(ticks <= 30, "a subida fecha em menos de meio segundo (ticks=%d)" % ticks)
	_assert_bar_agrees_with_number(hud, simulation, "no valor confirmado")
	eq(simulation.state_checksum(), before, "a apresentação não altera a simulação")
	hud.free()


func test_percent_counter_snaps_back_when_progress_regresses() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _playing_simulation()
	simulation.permille = 780
	hud.sync(simulation, false, [])

	# Rodada nova ou reinício: o território anterior já não é do jogador, então nada a encenar.
	simulation.permille = 30
	hud.sync(simulation, false, [])
	eq((hud.get_node("Percent") as Label).text, "03.0/80")
	_assert_bar_agrees_with_number(hud, simulation, "depois de regredir")
	hud.free()


## A rota M2 real progride 179 → 358 → 493 → 780 → 825 permille (`verify_m2_capture_route`).
## A maior conquista dessa rota (28,7 pontos percentuais) é o pior caso da calibragem: se ela
## não fechar dentro de um segundo, o contador virou espera em vez de recompensa.
func test_largest_real_capture_settles_within_one_second() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _playing_simulation()
	simulation.permille = 493
	hud.sync(simulation, false, [])
	simulation.permille = 780
	var ticks := 0
	while (hud.get_node("Percent") as Label).text != "78.0/80" and ticks < 200:
		hud.sync(simulation, false, [])
		ticks += 1
	eq((hud.get_node("Percent") as Label).text, "78.0/80")
	ok(ticks <= 60, "a maior conquista da rota M2 fecha em até 60 ticks (ticks=%d)" % ticks)
	ok(ticks >= 20, "e continua encenada, não instantânea (ticks=%d)" % ticks)
	hud.free()


## A largura do trilho do objetivo é decisão de layout do HUD (`QixGameHud.OBJECTIVE_WIDTH`), não
## deste teste. Fixá-la em píxeis literais faz o teste quebrar a cada ajuste de grade por uma razão
## que não aparece na mensagem de falha — foi o que aconteceu quando a grade do HUD alargou o trilho
## da percentagem. A promessa que importa sobrevive a qualquer largura: a barra conta a mesma
## história que o número que o jogador lê. É essa que se afirma aqui.
func _assert_bar_agrees_with_number(
	hud: QixGameHud, simulation: GameSimulation, context: String
) -> void:
	var shown_percent := (hud.get_node("Percent") as Label).text.split("/")[0].to_float()
	var target := maxi(1, simulation.rules.target_permille)
	var ratio := clampf(shown_percent * 10.0 / float(target), 0.0, 1.0)
	var expected := roundf(QixGameHud.OBJECTIVE_WIDTH * ratio)
	var actual := (hud.get_node("ObjectiveFill") as ColorRect).size.x
	ok(
		absf(actual - expected) <= 1.0,
		"%s: a barra mede %.0f px, mas o número %.1f%% pede %.0f px" % [
			context, actual, shown_percent, expected,
		],
	)


func _playing_simulation() -> GameSimulation:
	var rules := GameRules.new()
	var round_definition := RoundDefinition.new()
	return GameSimulation.new(rules, round_definition, 37)


func _simulation_in_dying_phase() -> GameSimulation:
	var rules := GameRules.new()
	var round_definition := RoundDefinition.new()
	var simulation := GameSimulation.new(rules, round_definition, 37)
	simulation.phase = GameSimulation.Phase.DYING
	return simulation
