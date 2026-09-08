extends TestCase
## O nome preserva a regressão original: sem itens nem flag explícita, as regras de aceleração
## não mudam o movimento. Atlas v4 dá a elas um produtor real: o item VELOCITY, capturado numa
## baliza e mantido em EffectTimers. Os três casos isolados continuam úteis para provar que a
## configuração não acelera o jogador sozinha; o caso de produção fecha captura → efeito → passo.
## Ambos os parâmetros participam do config_hash, mesmo numa rodada que não ofereça itens.

## [substeps_speedup, new_segment_slow_px] — o primeiro par é o de produção.
const SWEEP := [[4, 8], [1, 8], [8, 0], [2, 32]]


func test_explicit_speedup_flag_stays_off_without_items() -> void:
	var simulation := _run_route(4, 8)
	eq(simulation.speedup_active, false,
		"a fixture sem itens não liga a flag explícita de aceleração")
	eq(simulation.fills_done, 2, "a rota precisa mesmo capturar, senão não mede nada")


func test_speedup_rules_do_not_change_movement_without_an_active_source() -> void:
	var reference := _run_route(SWEEP[0][0], SWEEP[0][1])
	var reference_checksum := reference.state_checksum()
	for index in range(1, SWEEP.size()):
		var variant: Array = SWEEP[index]
		var simulation := _run_route(variant[0], variant[1])
		eq(simulation.state_checksum(), reference_checksum,
			"substeps_speedup=%d / new_segment_slow_px=%d mudou o estado sem fonte de aceleração"
				% [variant[0], variant[1]])
		eq(simulation.tick, reference.tick)
		eq(simulation.permille, reference.permille)
		eq(simulation.score, reference.score)


func test_speedup_configuration_participates_in_replay_even_without_items() -> void:
	var round_definition := _route_round()
	var seen := {}
	for variant in SWEEP:
		var hash_hex := ReplayLog.config_hash(
			_route_rules(variant[0], variant[1]), round_definition).hex_encode()
		ok(not seen.has(hash_hex),
			"config_hash repetiu para substeps_speedup=%d / new_segment_slow_px=%d" % variant)
		seen[hash_hex] = true
	eq(seen.size(), SWEEP.size(),
		"as regras autoradas participam do contrato de replay mesmo na fixture sem itens")


func test_production_beacon_activates_authored_velocity_and_replays() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	if campaign == null:
		return
	ok(not campaign.rounds.is_empty(), "campanha de produção sem rodadas")
	if campaign.rounds.is_empty():
		return
	for index in campaign.rounds.size():
		var rules: GameRules = campaign.rounds[index].rules
		var profile := rules.items as ItemProfile
		ok(profile != null and profile.enabled, "rodada %d oferece itens" % index)
		ok(rules.substeps_speedup > rules.substeps_normal,
			"rodada %d autora VELOCITY mais rápida (%d > %d subpassos)"
				% [index, rules.substeps_speedup, rules.substeps_normal])
	var content := campaign.rounds[0]
	var simulation := GameSimulation.new(content.rules, content.round_definition, content.seed_value)
	var replay := ReplayLog.start(simulation)
	var collected_velocity := false
	# Primeira captura da rota humana validada, com chefe e ameaças de produção ativos.
	for segment in [[MoveIntent.Dir.LEFT, false, 36], [MoveIntent.Dir.DOWN, true, 141]]:
		for _tick in int(segment[2]):
			var intent := MoveIntent.make(segment[0], segment[1])
			replay.record(intent)
			for event in simulation.step(intent):
				if event.kind == GameEvent.Kind.ITEM_STARTED and event.data.item == ItemProfile.Kind.VELOCITY:
					collected_velocity = true
	ok(collected_velocity, "capturar a baliza de produção ativa VELOCITY")
	ok(simulation.effects.active(ItemProfile.Kind.VELOCITY))
	eq(simulation.speedup_active, false, "o timer é autoritativo, sem copiar o efeito para a flag")
	var before_x := simulation.px
	var move := MoveIntent.make(MoveIntent.Dir.LEFT, false)
	replay.record(move)
	simulation.step(move)
	eq(before_x - simulation.px, content.rules.substeps_speedup,
		"VELOCITY adquirida pela captura usa a velocidade autorada no próximo tick")
	var restored := ReplayLog.from_bytes(replay.to_bytes())
	ok(restored != null)
	if restored != null:
		var fresh := GameSimulation.new(content.rules, content.round_definition, content.seed_value)
		eq(restored.replay_into(fresh), simulation.state_checksum(),
			"captura, duração do item e movimento acelerado sobrevivem ao replay")


# ---------------------------------------------------------------------------------------------
# rota
# ---------------------------------------------------------------------------------------------

## Campo 13×9, chefe imóvel: isola o jogador para que só os subpassos dele possam variar.
func _route_rules(substeps_speedup: int, new_segment_slow_px: int) -> GameRules:
	var rules := GameRules.new()
	rules.substeps_normal = 2            # valor de produção: o speed-up dobraria isto
	rules.substeps_speedup = substeps_speedup
	rules.new_segment_slow_px = new_segment_slow_px
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.shield_ticks = 10_000
	rules.target_permille = 1000         # não terminar a rodada antes do fim da rota
	(rules.items as ItemProfile).enabled = false
	return rules


func _route_round() -> RoundDefinition:
	var round_definition := RoundDefinition.new()
	round_definition.field_width = 13
	round_definition.field_height = 9
	round_definition.player_spawn = Vector2i(4, 0)
	round_definition.boss_start = Vector2i(11, 4)
	round_definition.boss_dir_index = 0
	return round_definition


## Desce e captura, anda na moldura, sobe e captura de novo — trilha longa o bastante para que
## o piso de `new_segment_slow_px` (8 px) importasse, se importasse.
func _run_route(substeps_speedup: int, new_segment_slow_px: int) -> GameSimulation:
	var simulation := GameSimulation.new(
		_route_rules(substeps_speedup, new_segment_slow_px), _route_round(), 23)
	_drive(simulation, MoveIntent.Dir.DOWN, true, 4)
	_drive(simulation, MoveIntent.Dir.RIGHT, false, 2)
	_drive(simulation, MoveIntent.Dir.UP, true, 4)
	return simulation


func _drive(simulation: GameSimulation, direction: int, drawing: bool, ticks: int) -> void:
	for _tick in ticks:
		simulation.step(MoveIntent.make(direction, drawing))
