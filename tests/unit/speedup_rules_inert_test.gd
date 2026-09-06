extends TestCase
## Contrato do speed-up do jogador — hoje **inerte**.
##
## `GameRules.substeps_speedup` e `GameRules.new_segment_slow_px` são autorados, validados por
## `validation_errors()` e entram em `canonical_bytes()` (logo, no `config_hash` do replay).
## `GameSimulation._player_substeps()` só os consulta quando `speedup_active` é verdadeiro — e
## **nenhum caminho do domínio, da sessão ou da apresentação escreve nesse campo**. O intent que
## o domínio recebe (`MoveIntent`) carrega direção e `drawing`, e não tem bit de "rápido".
##
## Consequência medida abaixo: mexer nesses dois números **invalida todo replay existente** e
## **não muda um único tick** de jogo. Um leitor de `GameRules` vê "4 subpassos com speed-up,
## nunca nos primeiros 8 px de um segmento novo" e conclui, razoavelmente, que o jogo tem
## speed-up. Não tem.
##
## Este teste fica **vermelho no dia em que alguém ligar o speed-up**. Isso é o objetivo: quem
## ligar tem de voltar aqui, reescrever o contrato e fechar o item do `docs/LOOP_LEDGER.md`.

## [substeps_speedup, new_segment_slow_px] — o primeiro par é o de produção.
const SWEEP := [[4, 8], [1, 8], [8, 0], [2, 32]]


func test_speedup_active_stays_off_along_a_full_capture_route() -> void:
	var simulation := _run_route(4, 8)
	eq(simulation.speedup_active, false,
		"nenhum caminho liga speedup_active; se isto falhar, o speed-up ganhou produtor")
	eq(simulation.fills_done, 2, "a rota precisa mesmo capturar, senão não mede nada")


func test_authored_speedup_rules_do_not_change_a_single_tick() -> void:
	var reference := _run_route(SWEEP[0][0], SWEEP[0][1])
	var reference_checksum := reference.state_checksum()
	for index in range(1, SWEEP.size()):
		var variant: Array = SWEEP[index]
		var simulation := _run_route(variant[0], variant[1])
		eq(simulation.state_checksum(), reference_checksum,
			"substeps_speedup=%d / new_segment_slow_px=%d mudou o estado — o speed-up ganhou efeito"
				% [variant[0], variant[1]])
		eq(simulation.tick, reference.tick)
		eq(simulation.permille, reference.permille)
		eq(simulation.score, reference.score)


func test_inert_speedup_rules_still_invalidate_every_existing_replay() -> void:
	var round_definition := _route_round()
	var seen := {}
	for variant in SWEEP:
		var hash_hex := ReplayLog.config_hash(
			_route_rules(variant[0], variant[1]), round_definition).hex_encode()
		ok(not seen.has(hash_hex),
			"config_hash repetiu para substeps_speedup=%d / new_segment_slow_px=%d" % variant)
		seen[hash_hex] = true
	eq(seen.size(), SWEEP.size(),
		"cada valor destes campos inertes produz um config_hash distinto: editá-los custa "
		+ "compatibilidade de replay e não compra comportamento nenhum")


func test_production_rounds_author_a_speedup_that_never_happens() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	ok(not campaign.rounds.is_empty(), "campanha de produção sem rodadas")
	for index in campaign.rounds.size():
		var rules: GameRules = campaign.rounds[index].rules
		ok(rules.substeps_speedup > rules.substeps_normal,
			"rodada %d autora um speed-up (%d > %d subpassos) que nunca é alcançado"
				% [index, rules.substeps_speedup, rules.substeps_normal])


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
