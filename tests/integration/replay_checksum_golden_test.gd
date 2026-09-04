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
