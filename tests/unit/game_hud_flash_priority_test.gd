extends TestCase
## A linha de flash do HUD tem um slot só, e quem escrevia por último ficava com ele — sem olhar
## a quem. Isso inverte a hierarquia de `docs/ART_DIRECTION.md` §Hierarquia 4, que diz que «o
## alerta de perigo conserva prioridade sobre recompensas», justamente no caso mais comum do
## jogo: as balizas ficam no chão livre, que é onde os dardos armam. "DARDO ARMADO · DESVIE"
## dura 30 ticks; a baliza colhida logo a seguir escrevia "BALIZA ×2  +240" por 90 — pontos por
## cima do único aviso sobre o qual ainda dava para agir, e por três vezes mais tempo.
##
## Estas guardas fixam a regra nos dois sentidos: o alerta toma a linha sempre, inclusive de
## outro alerta; a recompensa só entra com a linha livre, e é descartada — não enfileirada —
## quando não entra. O ganho não se perde por isso: ele é pago no contador de pontuação
## (ADR-0009) e a baliza conta em `B n/m` na linha de vitais.
##
## Nada aqui escreve no domínio: os eventos são fatos já confirmados e o HUD só os lê
## (invariante 6).

const DART_TEXT := "DARDO ARMADO · DESVIE"
const SHIELD_TEXT := "ESCUDO CRÍTICO"
const BEACON_TEXT := "BALIZA ×2  +240"
const CAPTURE_TEXT := "CAPTURA +7"

## Folga confortável sobre os 30 ticks do dardo, o mais curto dos alertas.
const TICKS_PAST_THE_DART := 40


func test_reward_in_the_same_tick_does_not_take_the_line_from_an_alert() -> void:
	var hud := _hud()
	var status := hud.get_node("Status") as Label
	hud.sync(_simulation(), false, [_dart(), _beacon()])
	eq(
		status.text,
		DART_TEXT,
		"a baliza colhida no mesmo tick do dardo apagou o aviso que ainda pedia decisão",
	)
	hud.free()


func test_reward_does_not_erase_an_alert_still_on_screen() -> void:
	var hud := _hud()
	var simulation := _simulation()
	var status := hud.get_node("Status") as Label
	hud.sync(simulation, false, [_dart()])
	for _quadro in 5:
		hud.sync(simulation, false, [])
	hud.sync(simulation, false, [_beacon()])
	eq(status.text, DART_TEXT, "a recompensa cobriu um alerta que ainda estava em cena")
	hud.free()


func test_reward_is_discarded_and_not_queued_behind_the_alert() -> void:
	var hud := _hud()
	var simulation := _simulation()
	var status := hud.get_node("Status") as Label
	hud.sync(simulation, false, [_dart(), _beacon()])
	for _quadro in TICKS_PAST_THE_DART:
		hud.sync(simulation, false, [])
	ne(status.text, DART_TEXT, "o alerta sobreviveu ao próprio prazo")
	ne(
		status.text,
		BEACON_TEXT,
		"a recompensa recusada voltou quando o alerta saiu — a linha não é fila de espera",
	)
	hud.free()


func test_reward_takes_the_line_once_it_is_free_of_alerts() -> void:
	var hud := _hud()
	var simulation := _simulation()
	var status := hud.get_node("Status") as Label
	hud.sync(simulation, false, [_dart()])
	for _quadro in TICKS_PAST_THE_DART:
		hud.sync(simulation, false, [])
	hud.sync(simulation, false, [_beacon()])
	eq(status.text, BEACON_TEXT, "com a linha livre a recompensa continua a ter direito a ela")
	hud.free()


func test_a_newer_alert_replaces_an_older_one() -> void:
	var hud := _hud()
	var simulation := _simulation()
	var status := hud.get_node("Status") as Label
	hud.sync(simulation, false, [GameEvent.make(GameEvent.Kind.SHIELD_CRITICAL)])
	eq(status.text, SHIELD_TEXT, "a montagem precisa de começar com o alerta longo em cena")
	hud.sync(simulation, false, [_dart()])
	eq(
		status.text,
		DART_TEXT,
		"a ameaça mais nova é a que ainda pede decisão e tem de tomar a linha",
	)
	hud.free()


func test_a_reward_still_replaces_another_reward() -> void:
	var hud := _hud()
	var simulation := _simulation()
	var status := hud.get_node("Status") as Label
	hud.sync(simulation, false, [GameEvent.make(
		GameEvent.Kind.CAPTURED, {"filled_delta": 7})])
	eq(status.text, CAPTURE_TEXT, "a montagem precisa de começar com uma recompensa em cena")
	hud.sync(simulation, false, [_beacon()])
	eq(status.text, BEACON_TEXT, "entre recompensas continua a valer a mais recente")
	hud.free()


func test_the_flash_hierarchy_does_not_touch_the_domain() -> void:
	var hud := _hud()
	var simulation := _simulation()
	var before := simulation.state_checksum()
	hud.sync(simulation, false, [_dart(), _beacon()])
	for _quadro in TICKS_PAST_THE_DART:
		hud.sync(simulation, false, [])
	eq(
		simulation.state_checksum(),
		before,
		"a hierarquia do flash é apresentação e não pode mexer no domínio (invariantes 6 e 8)",
	)
	hud.free()


func _dart() -> GameEvent:
	return GameEvent.make(GameEvent.Kind.DART_ARMED, {"slot": 0, "dir_index": 0})


func _beacon() -> GameEvent:
	return GameEvent.make(GameEvent.Kind.BEACON_CAPTURED, {"chain": 2, "points": 240})


func _hud() -> QixGameHud:
	var hud := QixGameHud.new()
	hud._ready()
	return hud


## Simulação parada em PLAYING: sem trilha e sem morte, a linha de estado é do flash e mais nada.
func _simulation() -> GameSimulation:
	var rules := GameRules.new()
	rules.substeps_normal = 1
	rules.substeps_speedup = 1
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.shield_ticks = 10_000
	var round_definition := RoundDefinition.new()
	round_definition.field_width = 9
	round_definition.field_height = 9
	round_definition.player_spawn = Vector2i(4, 0)
	round_definition.boss_start = Vector2i(4, 4)
	round_definition.boss_dir_index = 0
	return GameSimulation.new(rules, round_definition, 7)
