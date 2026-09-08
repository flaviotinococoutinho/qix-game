extends TestCase
## A causa da morte é a única coisa que a morte ensina: contato com a ameaça e escudo esgotado são
## dois erros diferentes e pedem correções diferentes. Quem a escreve é a linha de estado do HUD, e
## quanto tempo ela dura é do domínio — `rules.death_ticks`, a mesma duração que a fase DYING.
##
## Antes desta guarda a duração era a constante 45 do próprio HUD, sem relação nenhuma com a regra:
## com o `death_ticks` padrão (60) a causa sumia nos últimos 15 ticks da sequência, e com qualquer
## `death_ticks` abaixo de 45 ela sobrevivia à reentrada e cobria a linha de estado do jogo vivo.
##
## Estes testes conduzem uma morte de facto por `GameSimulation.step` — não fixam a fase à mão —
## para que o que se mede seja a sequência que o jogador vê.

const BOSS_CONTACT_TEXT := "CONTATO! · REENTRADA"


func test_death_cause_is_named_for_every_tick_of_the_dying_phase() -> void:
	var rules := _test_rules()
	rules.death_ticks = 60  ## o valor padrão de `GameRules`
	var simulation := GameSimulation.new(rules, _test_round(Vector2i(4, 2)), 7)
	var hud := QixGameHud.new()
	hud._ready()

	var events := simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	eq(simulation.phase, GameSimulation.Phase.DYING, "a montagem precisa de matar de facto")
	hud.sync(simulation, false, events)

	var status := hud.get_node("Status") as Label
	eq(status.text, BOSS_CONTACT_TEXT, "a causa aparece no primeiro quadro da morte")

	var seen := 1
	while simulation.phase == GameSimulation.Phase.DYING:
		var tick_events := simulation.step(MoveIntent.none())
		if simulation.phase != GameSimulation.Phase.DYING:
			break
		hud.sync(simulation, false, tick_events)
		seen += 1
		eq(
			status.text,
			BOSS_CONTACT_TEXT,
			"quadro %d de %d da sequência de morte deixou de nomear a causa" % [
				seen, rules.death_ticks,
			],
		)
	eq(seen, rules.death_ticks, "a sequência observada tem de durar `death_ticks` quadros")
	hud.free()


func test_death_cause_does_not_outlive_a_short_dying_phase() -> void:
	var rules := _test_rules()
	rules.death_ticks = 12  ## abaixo dos 45 ticks que o HUD fixava
	var simulation := GameSimulation.new(rules, _test_round(Vector2i(4, 2)), 7)
	var hud := QixGameHud.new()
	hud._ready()

	hud.sync(simulation, false, simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true)))
	var status := hud.get_node("Status") as Label
	eq(status.text, BOSS_CONTACT_TEXT, "a causa aparece mesmo numa sequência curta")

	while simulation.phase == GameSimulation.Phase.DYING:
		hud.sync(simulation, false, simulation.step(MoveIntent.none()))
	eq(simulation.phase, GameSimulation.Phase.PLAYING, "a montagem precisa de chegar à reentrada")

	hud.sync(simulation, false, [])
	ne(
		status.text,
		BOSS_CONTACT_TEXT,
		"a mensagem de morte cobriu a linha de estado depois de o jogador ter o controlo de volta",
	)
	hud.free()


func test_death_status_does_not_touch_the_domain() -> void:
	var rules := _test_rules()
	rules.death_ticks = 30
	var simulation := GameSimulation.new(rules, _test_round(Vector2i(4, 2)), 7)
	var hud := QixGameHud.new()
	hud._ready()
	hud.sync(simulation, false, simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true)))

	var before := simulation.state_checksum()
	for _quadro in 10:
		hud.sync(simulation, false, [])
	eq(simulation.state_checksum(), before, "o HUD leu a regra da morte e não escreveu no domínio")
	hud.free()


func _test_rules() -> GameRules:
	var rules := GameRules.new()
	rules.substeps_normal = 1
	rules.substeps_speedup = 1
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.shield_ticks = 10_000
	return rules


func _test_round(boss_position: Vector2i) -> RoundDefinition:
	var round_definition := RoundDefinition.new()
	round_definition.field_width = 9
	round_definition.field_height = 9
	round_definition.player_spawn = Vector2i(4, 0)
	round_definition.boss_start = boss_position
	round_definition.boss_dir_index = 0
	return round_definition
