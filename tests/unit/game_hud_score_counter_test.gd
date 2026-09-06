extends TestCase
## A pontuação encenada pelo caminho da área (`QixGameHud._advance_shown_score`).
##
## O contador de percentagem já sobe em degraus (ADR-0009), mas o rótulo `S ######` continuava a
## saltar: a mesma captura produzia um número encenado e outro instantâneo lado a lado na banda
## superior. O que se afirma aqui é a promessa da correção — os dois sobem juntos, nenhum deles
## desce, e nada disto toca o domínio.


func test_score_climbs_with_the_area_instead_of_snapping() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _playing_simulation()
	simulation.permille = 493
	simulation.score = 4930
	hud.sync(simulation, false, [])
	eq(_score_text(hud), "S 004930", "a primeira leitura assenta")

	# O maior salto da rota M2 real: 49,3 % → 78,0 % (`verify_m2_capture_route`).
	simulation.permille = 780
	simulation.score = 8000
	var before := simulation.state_checksum()

	hud.sync(simulation, false, [])
	var first := _shown_score(hud)
	ok(first > 4930, "o primeiro tick já pagou parte da conquista (mostrado=%d)" % first)
	ok(first < 8000, "mas não pagou tudo de uma vez (mostrado=%d)" % first)

	var score_arrival := -1
	var percent_arrival := -1
	var ticks := 1
	while ticks < 200 and (score_arrival < 0 or percent_arrival < 0):
		hud.sync(simulation, false, [])
		ticks += 1
		if score_arrival < 0 and _shown_score(hud) == 8000:
			score_arrival = ticks
		if percent_arrival < 0 and _percent_text(hud) == "78.0/80":
			percent_arrival = ticks
	eq(_score_text(hud), "S 008000", "a pontuação chega ao valor confirmado")
	eq(
		score_arrival,
		percent_arrival,
		"pontuação e percentagem pousam no mesmo tick (S=%d, %%=%d)" % [
			score_arrival, percent_arrival,
		],
	)
	eq(simulation.state_checksum(), before, "a apresentação não altera a simulação")
	hud.free()


func test_score_never_regresses_when_a_second_capture_lands_mid_climb() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _playing_simulation()
	simulation.permille = 100
	simulation.score = 1000
	hud.sync(simulation, false, [])

	simulation.permille = 500
	simulation.score = 5000
	var highest := _shown_score(hud)
	for _i in range(6):
		hud.sync(simulation, false, [])
		highest = _assert_non_decreasing(hud, highest, "na primeira captura")

	# Segunda captura antes de a primeira fechar: o intervalo de área alarga debaixo dos pés do
	# contador. A fração fechada recua, mas o número que o jogador lê não pode recuar com ela.
	simulation.permille = 800
	simulation.score = 8000
	var ticks := 0
	while ticks < 200 and _shown_score(hud) != 8000:
		hud.sync(simulation, false, [])
		highest = _assert_non_decreasing(hud, highest, "depois da segunda captura")
		ticks += 1
	eq(_score_text(hud), "S 008000", "e ainda assim chega ao valor confirmado")
	eq(_percent_text(hud), "80.0/80", "com a área no mesmo lugar")
	hud.free()


func test_trail_points_settle_at_once_because_there_is_no_area_climbing() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _playing_simulation()
	simulation.permille = 300
	simulation.score = 3000
	hud.sync(simulation, false, [])

	# Gotejo da trilha: pontos sem território novo. Encenar isto seria ruído contínuo a competir
	# com a única subida que carrega significado — a da conquista.
	simulation.score = 3025
	hud.sync(simulation, false, [])
	eq(_score_text(hud), "S 003025")
	hud.free()


func test_score_settles_at_once_when_the_round_restarts() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _playing_simulation()
	simulation.permille = 780
	simulation.score = 8000
	hud.sync(simulation, false, [])

	# Rodada nova: a área regride e a pontuação de partida é a do domínio, sem encenação nenhuma.
	simulation.permille = 30
	simulation.score = 8000
	hud.sync(simulation, false, [])
	eq(_score_text(hud), "S 008000")
	eq(_percent_text(hud), "03.0/80")
	hud.free()


func _assert_non_decreasing(hud: QixGameHud, highest: int, context: String) -> int:
	var shown := _shown_score(hud)
	ok(shown >= highest, "%s: a pontuação desceu de %d para %d" % [context, highest, shown])
	return maxi(highest, shown)


func _score_text(hud: QixGameHud) -> String:
	return (hud.get_node("Score") as Label).text


func _shown_score(hud: QixGameHud) -> int:
	return int(_score_text(hud).substr(2))


func _percent_text(hud: QixGameHud) -> String:
	return (hud.get_node("Percent") as Label).text


func _playing_simulation() -> GameSimulation:
	var rules := GameRules.new()
	var round_definition := RoundDefinition.new()
	return GameSimulation.new(rules, round_definition, 37)
