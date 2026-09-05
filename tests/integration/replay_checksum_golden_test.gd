extends TestCase
## Guarda mecânica dos invariantes 7 e 8 do `CLAUDE.md`.
##
## Os outros testes de replay comparam a simulação **consigo mesma**: rodam uma rota, reproduzem
## o log e conferem que os dois checksums batem. Isso prova determinismo, mas não prova
## estabilidade — se `GameRules`, a geometria ou o perfil do boss mudarem, os dois lados mudam
## juntos e o teste continua verde. É exatamente a mudança que o invariante 7 chama de decisão,
## não de efeito colateral.
##
## Este teste fecha esse buraco fixando valores literais. Ele falha quando o contrato de replay
## se move, e a mensagem de falha diz qual das duas coisas aconteceu:
##
##  * **Você mexeu só na apresentação** (view, HUD, VFX, áudio, háptica) e um checksum mudou.
##    Isso é o invariante 8 sendo violado: a mudança estética vazou para o domínio. Reverta e
##    refaça — não atualize os números daqui.
##  * **Você mudou regra, geometria ou perfil de boss de propósito.** Então os replays gravados
##    com o contrato antigo deixaram de valer. Incremente `GameRules.RULES_VERSION`, atualize os
##    valores dourados abaixo no mesmo commit e diga no PR que replays antigos foram invalidados.
##
## Atualizar os literais sem uma dessas duas justificativas escritas transforma o teste em
## carimbo, e o invariante volta a não existir.

const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"

## Contrato declarado. Mudar qualquer um destes invalida replays gravados.
const GOLDEN_RULES_VERSION := 2
const GOLDEN_SCHEMA_VERSION := 1

## Um por rodada de produção: seed e hash de (regras ⊕ geometria ⊕ perfil de boss).
## `ReplayLog.config_hash` é o que o runtime confere antes de reproduzir qualquer log.
const GOLDEN_ROUNDS := [
	{
		"id": &"abyssal_relay",
		"seed": 1482031771,
		"config_hash": "a044393ee6d0f7ae98612db663499032a9d5c8fb17a7621f5c26326804d00f9c",
	},
	{
		"id": &"aurora_foundry",
		"seed": 189234077,
		"config_hash": "5f5c07f5dc27ef640a06932591f8ec261aebd7ff6e9dd7a44a5e9f8e4de91408",
	},
	{
		"id": &"verdant_singularity",
		"seed": 933117401,
		"config_hash": "bf7e3ac9db8bc272d099fc3a23ca1158ee760ee9f0f82199cfd0196c2984d67d",
	},
]

## Rota curta e reproduzível na rodada 1, com o **chefe ativo** — nada aqui imobiliza ou desloca
## o boss, para que o perfil de comportamento também esteja dentro do checksum final.
## São os dois primeiros segmentos da rota humana de `boss_active_campaign_playthrough_test.gd`:
## atravessa a fronteira e fecha a primeira captura.
const ROUTE := [
	[MoveIntent.Dir.LEFT, false, 36],
	[MoveIntent.Dir.DOWN, true, 141],
]

## Volta completa pelo perímetro, igual nas três rodadas (a geometria de produção é 225×283 nas
## três). O jogador parte de (112,0), passa pelos quatro cantos e **fecha exatamente onde começou**
## — nenhum trecho é bloqueado, nenhuma trilha é aberta, nenhuma captura acontece. Por isso o que
## sobra no checksum final, tirando o jogador de volta ao ponto de partida e o escudo em contagem
## regressiva, é a **trajetória do chefe**.
##
## São 506 ticks: mais que um período de pulso de `boss_pursuit` (360) e mais que dois de
## `boss_sweep` (240), para que a janela de aceleração de cada perfil caia dentro do dourado.
const BOSS_LAP_ROUTE := [
	[MoveIntent.Dir.LEFT, 56],    # (112,0) → canto superior esquerdo
	[MoveIntent.Dir.DOWN, 141],   # → canto inferior esquerdo
	[MoveIntent.Dir.RIGHT, 112],  # → canto inferior direito
	[MoveIntent.Dir.UP, 141],     # → canto superior direito
	[MoveIntent.Dir.LEFT, 56],    # → de volta a (112,0)
]

const BOSS_LAP_TICKS := 506
const BOSS_LAP_START := Vector2i(112, 0)

## Um por perfil de boss de produção. `pulse_ticks` e `peak_speed_fp` não são decoração: são a
## prova de que a janela de pulso do perfil **está dentro** da volta — sem eles o checksum final
## poderia fixar 506 ticks de velocidade base e ninguém perceberia que o pulso saiu do dourado.
## `boss_wander` não autora pulso (`pulse_period_ticks` = 0), então 0 ticks acelerados é o correto.
const GOLDEN_BOSS_LAPS := [
	{
		"id": &"abyssal_relay",
		"pattern": 0,  # WANDER
		"peak_speed_fp": 96,
		"pulse_ticks": 0,
		"boss_cell": Vector2i(107, 82),
		"final_checksum": "c0790abb74c1cff534218cc3546f1aa3e82f195bbc99e938c905924255ee38f7",
	},
	{
		"id": &"aurora_foundry",
		"pattern": 1,  # PURSUIT
		"peak_speed_fp": 128,
		"pulse_ticks": 60,
		"boss_cell": Vector2i(177, 118),
		"final_checksum": "037b6212a9f6a3be86735ec77ecaa314f3d5df9bb05dc17aea5a9cfca2a15bfc",
	},
	{
		"id": &"verdant_singularity",
		"pattern": 2,  # SWEEP
		"peak_speed_fp": 160,
		"pulse_ticks": 96,
		"boss_cell": Vector2i(125, 127),
		"final_checksum": "8a9e82d9918774311640e80c1a5eff97d066aea45f1cc98825205fa6bb7fab65",
	},
]

const GOLDEN_TICKS := 177
const GOLDEN_PERMILLE := 179
const GOLDEN_SCORE := 2_490
const GOLDEN_INITIAL_CHECKSUM := "9a44499781ea0ee82e80a16d3eedc8fc496469ebebcff5ef92ae5e58195659f0"
const GOLDEN_FINAL_CHECKSUM := "fe898e008ce1e332ebe0a369f1bb1474e37cbd1ee35c15d403548e80f202fa3c"
const GOLDEN_REPLAY_CHECKSUM := "ae29339010984eeaf036b13e1fcda74384b9306322ede94b6aa5561cdfb1011f"

const DRIFT_HINT := (
	"mudou o contrato de replay: se você só mexeu em apresentação, o invariante 8 foi violado"
	+ " e a mudança vazou para o domínio — reverta;"
	+ " se a mudança de regra/geometria/boss foi deliberada, bump em GameRules.RULES_VERSION"
	+ " e atualize os valores dourados no mesmo commit"
)


func test_declared_replay_contract_versions_are_pinned() -> void:
	eq(
		GameRules.RULES_VERSION,
		GOLDEN_RULES_VERSION,
		"GameRules.RULES_VERSION " + DRIFT_HINT,
	)
	eq(
		ReplayLog.SCHEMA_VERSION,
		GOLDEN_SCHEMA_VERSION,
		"ReplayLog.SCHEMA_VERSION mudou: o formato binário do log não é mais o mesmo,"
		+ " logs gravados com o esquema anterior são rejeitados por from_bytes",
	)


func test_production_round_config_hashes_are_pinned_per_round() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	if campaign == null:
		return
	eq(campaign.rounds.size(), GOLDEN_ROUNDS.size(), "número de rodadas de produção " + DRIFT_HINT)
	if campaign.rounds.size() != GOLDEN_ROUNDS.size():
		return
	for index in GOLDEN_ROUNDS.size():
		var golden: Dictionary = GOLDEN_ROUNDS[index]
		var content := campaign.rounds[index]
		eq(content.round_id, golden.id, "identidade da rodada %d mudou" % index)
		eq(
			content.seed_value,
			golden.seed,
			"seed da rodada %d " % index + DRIFT_HINT,
		)
		var hash_hex := ReplayLog.config_hash(
			content.rules, content.round_definition
		).hex_encode()
		eq(
			hash_hex,
			golden.config_hash,
			"config_hash da rodada %d (regras ⊕ geometria ⊕ perfil de boss) " % index + DRIFT_HINT,
		)


func test_production_route_reproduces_the_pinned_checksums_with_the_boss_active() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	if campaign == null:
		return
	var content := campaign.rounds[0]
	ok(content.rules.boss_substeps > 0, "o chefe precisa estar ativo para entrar no checksum")

	var simulation := GameSimulation.new(
		content.rules, content.round_definition, content.seed_value
	)
	eq(
		simulation.state_checksum().hex_encode(),
		GOLDEN_INITIAL_CHECKSUM,
		"checksum do estado inicial " + DRIFT_HINT,
	)

	var replay := ReplayLog.start(simulation)
	for segment in ROUTE:
		for _tick in int(segment[2]):
			var intent := MoveIntent.make(segment[0], segment[1])
			simulation.step(intent)
			replay.record(intent)

	eq(replay.tick_count(), GOLDEN_TICKS, "comprimento da rota mudou; a rota é parte do dourado")
	eq(simulation.permille, GOLDEN_PERMILLE, "progresso da primeira captura " + DRIFT_HINT)
	eq(simulation.score, GOLDEN_SCORE, "pontuação da primeira captura " + DRIFT_HINT)
	eq(simulation.fills_done, 1, "a rota dourada precisa fechar exatamente uma captura")
	eq(
		simulation.state_checksum().hex_encode(),
		GOLDEN_FINAL_CHECKSUM,
		"checksum final após %d ticks " % GOLDEN_TICKS + DRIFT_HINT,
	)
	eq(
		replay.checksum().hex_encode(),
		GOLDEN_REPLAY_CHECKSUM,
		"checksum do log serializado " + DRIFT_HINT,
	)


## A rota dourada acima corre só na rodada 1, com `boss_wander`. PURSUIT e SWEEP mudam a
## trajetória do chefe — e a trajetória entra no checksum (`bx_fp`, `by_fp`, `bvx_fp`, `bvy_fp`,
## `boss_dir_index`, `boss_effective_speed_fp`). Sem um literal por perfil, editar
## `content/rules/boss_pursuit.tres` ou `boss_sweep.tres` invalida replays gravados **em silêncio**:
## `boss_campaign_balance_test.gd` compara cada perfil consigo mesmo e continua verde.
func test_each_production_boss_profile_has_a_pinned_final_checksum() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	if campaign == null:
		return
	eq(campaign.rounds.size(), GOLDEN_BOSS_LAPS.size(), "número de rodadas de produção " + DRIFT_HINT)
	if campaign.rounds.size() != GOLDEN_BOSS_LAPS.size():
		return

	for index in GOLDEN_BOSS_LAPS.size():
		var golden: Dictionary = GOLDEN_BOSS_LAPS[index]
		var content := campaign.rounds[index]
		eq(content.round_id, golden.id, "identidade da rodada %d mudou" % index)
		eq(
			content.rules.boss_behavior.pattern,
			golden.pattern,
			"o padrão de boss da rodada %d mudou; o dourado abaixo é de outro perfil" % index,
		)

		# Regras de produção **sem duplicar nem afrouxar**: é o contrato que o jogo grava.
		var simulation := GameSimulation.new(
			content.rules, content.round_definition, content.seed_value
		)
		eq(Vector2i(simulation.px, simulation.py), BOSS_LAP_START, "partida da volta mudou")

		var base_speed_fp: int = content.rules.boss_speed_fp
		var peak_speed_fp := base_speed_fp
		var pulse_ticks := 0
		for segment in BOSS_LAP_ROUTE:
			for _tick in int(segment[1]):
				simulation.step(MoveIntent.make(segment[0], false))
				if simulation.boss_effective_speed_fp > base_speed_fp:
					pulse_ticks += 1
					peak_speed_fp = maxi(peak_speed_fp, simulation.boss_effective_speed_fp)

		eq(simulation.tick, BOSS_LAP_TICKS, "comprimento da volta mudou; a rota é parte do dourado")
		# A volta tem de continuar sendo uma volta: se qualquer trecho passar a ser bloqueado, ou a
		# geometria mudar, o jogador não fecha no ponto de partida e o dourado deixa de medir o boss.
		eq(
			Vector2i(simulation.px, simulation.py),
			BOSS_LAP_START,
			"a volta pelo perímetro da rodada %d não fechou; a geometria mudou" % index,
		)
		eq(simulation.phase, GameSimulation.Phase.PLAYING, "a volta não pode terminar em morte")
		eq(simulation.fills_done, 0, "a volta não pode capturar território")
		ok(not simulation.trail_active, "a volta não abre trilha")

		eq(
			peak_speed_fp,
			golden.peak_speed_fp,
			"velocidade de pico do chefe na rodada %d " % index + DRIFT_HINT,
		)
		eq(
			pulse_ticks,
			golden.pulse_ticks,
			"ticks acelerados do chefe na rodada %d — a janela de pulso saiu da volta" % index,
		)
		eq(
			simulation.boss_cell(),
			golden.boss_cell,
			"célula final do chefe na rodada %d " % index + DRIFT_HINT,
		)
		eq(
			simulation.state_checksum().hex_encode(),
			golden.final_checksum,
			"checksum após a volta na rodada %d " % index + DRIFT_HINT,
		)


## O log gravado numa rodada com PURSUIT/SWEEP tem de reproduzir o mesmo checksum depois de passar
## por disco. Cobre o invariante 7 na via que o jogo usa de verdade — `from_bytes` + `replay_into`.
func test_each_boss_lap_survives_serialization_and_replays_bit_exact() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	if campaign == null:
		return
	if campaign.rounds.size() != GOLDEN_BOSS_LAPS.size():
		return

	for index in GOLDEN_BOSS_LAPS.size():
		var golden: Dictionary = GOLDEN_BOSS_LAPS[index]
		var content := campaign.rounds[index]
		var recorded := GameSimulation.new(
			content.rules, content.round_definition, content.seed_value
		)
		var replay := ReplayLog.start(recorded)
		for segment in BOSS_LAP_ROUTE:
			for _tick in int(segment[1]):
				var intent := MoveIntent.make(segment[0], false)
				recorded.step(intent)
				replay.record(intent)

		var restored := ReplayLog.from_bytes(replay.to_bytes())
		ok(restored != null, "o log da volta da rodada %d precisa sobreviver a to_bytes" % index)
		if restored == null:
			continue
		var fresh := GameSimulation.new(content.rules, content.round_definition, content.seed_value)
		eq(
			restored.compatibility_error(fresh),
			"",
			"log da volta da rodada %d precisa ser compatível com o runtime" % index,
		)
		eq(
			restored.replay_into(fresh).hex_encode(),
			golden.final_checksum,
			"reprodução da volta da rodada %d divergiu do checksum fixado " % index + DRIFT_HINT,
		)


func test_pinned_replay_still_reproduces_bit_exact_on_a_fresh_simulation() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	if campaign == null:
		return
	var content := campaign.rounds[0]
	var recorded := GameSimulation.new(
		content.rules, content.round_definition, content.seed_value
	)
	var replay := ReplayLog.start(recorded)
	for segment in ROUTE:
		for _tick in int(segment[2]):
			var intent := MoveIntent.make(segment[0], segment[1])
			recorded.step(intent)
			replay.record(intent)

	# Serializa e desserializa: o log que o jogo grava em disco tem de valer o mesmo.
	var restored := ReplayLog.from_bytes(replay.to_bytes())
	ok(restored != null, "o log dourado precisa sobreviver a to_bytes/from_bytes")
	if restored == null:
		return

	var fresh := GameSimulation.new(content.rules, content.round_definition, content.seed_value)
	eq(restored.compatibility_error(fresh), "", "log dourado precisa ser compatível com o runtime")
	var final_checksum := restored.replay_into(fresh)
	eq(
		final_checksum.hex_encode(),
		GOLDEN_FINAL_CHECKSUM,
		"reprodução do log dourado divergiu do checksum fixado " + DRIFT_HINT,
	)
