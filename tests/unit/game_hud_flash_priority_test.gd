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
const EMBER_TEXT := "BRASA NA TRILHA · AVANCE"
const PURGE_TEXT := "PURGA ATIVO"

## Folga confortável sobre os 30 ticks do dardo, o mais curto dos alertas.
const TICKS_PAST_THE_DART := 40


func test_reward_in_the_same_tick_does_not_take_the_line_from_an_alert() -> void:
	for reverse_order in [false, true]:
		var hud := _hud()
		var status := hud.get_node("Status") as Label
		var events: Array[GameEvent] = [_dart(), _beacon()]
		if reverse_order:
			events.reverse()
		hud.sync(_simulation(), false, events)
		eq(status.text, DART_TEXT, "o alerta válido vence nas duas ordens do lote")
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
	simulation.shield_ticks = simulation.rules.shield_critical_ticks
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


func test_capture_extinguishes_the_ember_before_the_reward_is_arbitrated() -> void:
	var hud := _hud()
	var simulation := _simulation()
	var status := hud.get_node("Status") as Label
	for _tick in 7:
		simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	ok(simulation.trail_active, "a captura começa com trilha real aberta")
	EmberRules.ignite(simulation.pools, 0, 0, MinorActorPools.Cause.STALL, 30)
	hud.sync(simulation, false, [_ember()])
	eq(status.text, EMBER_TEXT)
	var events := simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	ok(_has_event(events, GameEvent.Kind.CAPTURED), "a rota deve fechar uma captura real")
	ok(_has_event(events, GameEvent.Kind.EMBER_EXTINGUISHED), "a captura extingue a brasa")
	ok(not simulation.trail_active)
	eq(simulation.pools.alive_embers(), 0)
	var before := simulation.state_checksum()
	hud.sync(simulation, false, events)
	ok(status.text.begins_with("CAPTURA +"), "o ganho substitui o perigo já resolvido")
	eq(simulation.state_checksum(), before, "resolver o aviso não escreve na simulação")
	hud.free()


func test_purge_replaces_each_resolved_alert_with_the_confirmed_item() -> void:
	for kind in [GameEvent.Kind.DART_ARMED, GameEvent.Kind.EMBER_IGNITED, GameEvent.Kind.SHIELD_CRITICAL]:
		var hud := _hud()
		var simulation := _simulation()
		var status := hud.get_node("Status") as Label
		var alert := _dart()
		var expected := DART_TEXT
		if kind == GameEvent.Kind.EMBER_IGNITED:
			simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
			EmberRules.ignite(simulation.pools, 0, 0, MinorActorPools.Cause.STALL, 30)
			alert = _ember()
			expected = EMBER_TEXT
		elif kind == GameEvent.Kind.SHIELD_CRITICAL:
			simulation.shield_ticks = simulation.rules.shield_critical_ticks
			alert = GameEvent.make(kind)
			expected = SHIELD_TEXT
		hud.sync(simulation, false, [alert])
		eq(status.text, expected, "o perigo precisa existir antes de ser expurgado")
		var events: Array[GameEvent] = []
		simulation._activate_item(ItemProfile.Kind.PURGE, events)
		eq(simulation.pools.alive_total(), 0)
		ok(simulation.shield_ticks > simulation.rules.shield_critical_ticks)
		var before := simulation.state_checksum()
		hud.sync(simulation, false, events)
		eq(status.text, PURGE_TEXT, "o HUD deve reconhecer o efeito que resolveu o alerta")
		eq(simulation.state_checksum(), before)
		hud.free()


func test_purge_does_not_clear_a_shield_alert_if_the_authored_floor_is_still_critical() -> void:
	var hud := _hud()
	var simulation := _simulation()
	simulation.shield_ticks = 100
	simulation.item_profile().shield_floor_ticks = 150
	hud.sync(simulation, false, [GameEvent.make(GameEvent.Kind.SHIELD_CRITICAL)])
	var events: Array[GameEvent] = []
	simulation._activate_item(ItemProfile.Kind.PURGE, events)
	eq(simulation.shield_ticks, 150)
	hud.sync(simulation, false, events)
	eq((hud.get_node("Status") as Label).text, SHIELD_TEXT, "o nome PURGA não resolve um perigo ainda real")
	hud.free()


func test_absorbing_another_dart_does_not_clear_the_announced_actor() -> void:
	var hud := _hud()
	var simulation := _simulation()
	_spawn_dart(simulation, 1)
	hud.sync(simulation, false, [_dart(1)])
	simulation.pools.retire_dart(0, MinorActorPools.Reason.ABSORBED)
	hud.sync(simulation, false, [
		GameEvent.make(GameEvent.Kind.DART_ABSORBED, {"slot": 0}), _beacon()])
	eq((hud.get_node("Status") as Label).text, DART_TEXT, "o dardo avisado ainda está vivo")
	hud.free()


func test_reusing_the_dart_slot_does_not_keep_the_old_actor_warning_alive() -> void:
	var hud := _hud()
	var simulation := _simulation()
	hud.sync(simulation, false, [_dart()])
	var retired_id := simulation.pools.dart_actor_id(0)
	simulation.pools.retire_dart(0, MinorActorPools.Reason.ABSORBED, 0)
	_spawn_dart(simulation, 0)
	ne(simulation.pools.dart_actor_id(0), retired_id)
	hud.sync(simulation, false, [_beacon()])
	eq((hud.get_node("Status") as Label).text, BEACON_TEXT, "um slot reutilizado não ressuscita aviso sem novo evento")
	hud.free()


func test_an_alert_resolved_in_its_own_event_batch_never_hides_the_reward() -> void:
	var hud := _hud()
	var simulation := _simulation()
	simulation.pools.retire_dart(0, MinorActorPools.Reason.ABSORBED)
	hud.sync(simulation, false, [
		_dart(), _beacon(), GameEvent.make(GameEvent.Kind.DART_ABSORBED, {"slot": 0})])
	eq((hud.get_node("Status") as Label).text, BEACON_TEXT, "o snapshot final resolve até o aviso novo no lote")
	hud.free()


func test_absorbing_a_dart_does_not_resolve_an_unrelated_shield_alert() -> void:
	var hud := _hud()
	var simulation := _simulation()
	simulation.shield_ticks = simulation.rules.shield_critical_ticks
	hud.sync(simulation, false, [GameEvent.make(GameEvent.Kind.SHIELD_CRITICAL)])
	simulation.pools.retire_dart(0, MinorActorPools.Reason.ABSORBED)
	hud.sync(simulation, false, [
		GameEvent.make(GameEvent.Kind.DART_ABSORBED, {"slot": 0}), _beacon()])
	eq((hud.get_node("Status") as Label).text, SHIELD_TEXT, "a resolução de outra causa não libera esta prioridade")
	hud.free()


func test_death_and_respawn_do_not_restore_an_old_alert_or_block_new_rewards() -> void:
	var hud := _hud()
	var simulation := _simulation()
	var status := hud.get_node("Status") as Label
	hud.sync(simulation, false, [_dart()])
	simulation.shield_ticks = 1
	hud.sync(simulation, false, simulation.step(MoveIntent.none()))
	eq(simulation.phase, GameSimulation.Phase.DYING)
	eq(status.text, "ESCUDO ESGOTADO · REENTRADA")
	for _tick in 6:
		hud.sync(simulation, false, simulation.step(MoveIntent.none()))
		if simulation.phase == GameSimulation.Phase.PLAYING:
			break
	eq(simulation.phase, GameSimulation.Phase.PLAYING, "a fixture deve completar a reentrada")
	ne(status.text, DART_TEXT)
	hud.sync(simulation, false, [_beacon()])
	eq(status.text, BEACON_TEXT, "o alerta anterior à morte não conserva a prioridade")
	hud.free()


func test_a_new_simulation_does_not_inherit_an_alert_from_equal_actor_ids() -> void:
	var hud := _hud()
	var previous := _simulation()
	var current := _simulation()
	eq(previous.pools.dart_actor_id(0), current.pools.dart_actor_id(0))
	hud.sync(previous, false, [_dart()])
	hud.sync(current, false, [_beacon()])
	eq((hud.get_node("Status") as Label).text, BEACON_TEXT, "IDs são locais à simulação")
	hud.free()


func _dart(slot: int = 0) -> GameEvent:
	return GameEvent.make(GameEvent.Kind.DART_ARMED, {"slot": slot, "dir_index": 0})


func _ember() -> GameEvent:
	return GameEvent.make(GameEvent.Kind.EMBER_IGNITED, {"slot": 0})


func _has_event(events: Array[GameEvent], kind: int) -> bool:
	for event in events:
		if event.kind == kind:
			return true
	return false


func _spawn_dart(simulation: GameSimulation, slot: int) -> void:
	simulation.pools.begin_dart(slot, 100)
	simulation.pools.set_dart(slot, MinorActorPools.D.X_FP, (1 << 8) + 128)
	simulation.pools.set_dart(slot, MinorActorPools.D.Y_FP, (1 << 8) + 128)
	simulation.pools.set_dart(slot, MinorActorPools.D.WARMUP, 100)
	simulation.pools.set_dart(slot, MinorActorPools.D.LIFE, 100)


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
	rules.death_ticks = 2
	var items := ItemProfile.new()
	items.enabled = true
	items.sealed_free_cell_limit = 0
	rules.items = items
	var round_definition := RoundDefinition.new()
	round_definition.field_width = 9
	round_definition.field_height = 9
	round_definition.player_spawn = Vector2i(4, 0)
	round_definition.boss_start = Vector2i(6, 4)
	round_definition.boss_dir_index = 0
	var simulation := GameSimulation.new(rules, round_definition, 7)
	_spawn_dart(simulation, 0)
	return simulation
