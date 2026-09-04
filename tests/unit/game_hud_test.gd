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
	eq(int((hud.get_node("ObjectiveFill") as ColorRect).size.x), 6,
		"a barra conta a mesma história que o número")

	var ticks := 1
	while (hud.get_node("Percent") as Label).text != "23.4/80" and ticks < 200:
		hud.sync(simulation, false, [])
		ticks += 1
	eq((hud.get_node("Percent") as Label).text, "23.4/80", "o contador chega ao valor confirmado")
	ok(ticks <= 30, "a subida fecha em menos de meio segundo (ticks=%d)" % ticks)
	eq(int((hud.get_node("ObjectiveFill") as ColorRect).size.x), 15)
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
	eq(int((hud.get_node("ObjectiveFill") as ColorRect).size.x), 2)
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
