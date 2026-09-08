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
## 4 em 2026-09-07: lifecycle, justiça, balizas, efeitos e bônus (ADR-0012).
## Valores medidos por tools/dev/print_golden_checksums.gd após o bump deliberado.
## Histórico: 2 → 3 em 2026-09-05 (ADR-0010/0011: elenco menor, diretor de ameaça, fases do
## Núcleo, fallback de direção). Replays gravados sob a versão 2 deixaram de valer.
const GOLDEN_RULES_VERSION := 4
const GOLDEN_SCHEMA_VERSION := 1

## Um por rodada de produção: seed, hash de (regras ⊕ geometria ⊕ perfil de boss) e uma rota
## curta com o **chefe ativo** — nada aqui imobiliza ou desloca o boss, para que o perfil de
## comportamento também esteja dentro do checksum final. Cada rota é o começo da rota humana de
## `boss_active_campaign_playthrough_test.gd`: atravessa a fronteira e fecha a primeira captura.
## `ReplayLog.config_hash` é o que o runtime confere antes de reproduzir qualquer log.
const GOLDEN_ROUNDS := [
	{
		"id": &"abyssal_relay",
		"seed": 1482031771,
		"config_hash": "14dd171dfb689135b6d2e30191f7a9f0156e61be1919fce87d10a3a2516d852c",
		"route": [[MoveIntent.Dir.LEFT, false, 36], [MoveIntent.Dir.DOWN, true, 141]],
		"ticks": 177,
		"permille": 179,
		"score": 3490,
		"initial_checksum": "de10ab08cc65b3b8590aeb02e20a4f122f6c6c45716c347cbbe00acdb6a3018b",
		"final_checksum": "8eced70a2512a08ae8f5e63cc94c0ec1a44488ef49e7fe482faadfb47d47a455",
		"replay_checksum": "e34b9c1bded742abff6a6c8d44783da2eb0758f8f1591e147bbce6b1f2eca2c5",
	},
	{
		"id": &"aurora_foundry",
		"seed": 189234077,
		"config_hash": "ed2512d123940b985bfca5200af7d6a9ead8547b972bdd915154b3aea47b5958",
		"route": [[MoveIntent.Dir.LEFT, false, 6], [MoveIntent.Dir.DOWN, true, 141]],
		"ticks": 147,
		"permille": 556,
		"score": 9260,
		"initial_checksum": "44c84c2395f82cdbcca8737ed67fadef59c0fb8e13571db2cc981b843aa2c40c",
		"final_checksum": "88a68736a37b443c45f5ffa8080349fab96dfe30e2546f543e495bc45cf21105",
		"replay_checksum": "6c24cdda0da6a1fc1c4ca8fd41b2b2e0d3cf569b66ecba4582025f40c29de561",
	},
	{
		"id": &"verdant_singularity",
		"seed": 933117401,
		"config_hash": "cd3c57cb8131f7b7f69c0440981d045f318297b0b8f30b608d06275c97dc4b1f",
		"route": [[MoveIntent.Dir.LEFT, false, 16], [MoveIntent.Dir.DOWN, true, 141]],
		"ticks": 157,
		"permille": 358,
		"score": 7280,
		"initial_checksum": "6f0e1adc533399166c7438677f8077a193060b384746cc0ad0df8fcfd5ec241d",
		"final_checksum": "a509cccc924207e68377b2e4135ecfeb7da06fd9703de642a3af01481af7250c",
		"replay_checksum": "d4a97d27e05f1a6e124095ed7ab6dee18db9aa5584be0cd098f596496dc84ae3",
	},
]

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


func test_production_routes_reproduce_the_pinned_checksums_with_the_boss_active() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	if campaign == null:
		return
	for index in mini(campaign.rounds.size(), GOLDEN_ROUNDS.size()):
		var golden: Dictionary = GOLDEN_ROUNDS[index]
		var content := campaign.rounds[index]
		var label := "%s: " % golden.id
		ok(content.rules.boss_substeps > 0, label + "o chefe precisa estar ativo para entrar no checksum")

		var simulation := GameSimulation.new(
			content.rules, content.round_definition, content.seed_value
		)
		eq(
			simulation.state_checksum().hex_encode(),
			golden.initial_checksum,
			label + "checksum do estado inicial " + DRIFT_HINT,
		)

		var replay := ReplayLog.start(simulation)
		for segment in golden.route:
			for _tick in int(segment[2]):
				var intent := MoveIntent.make(segment[0], segment[1])
				simulation.step(intent)
				replay.record(intent)

		eq(replay.tick_count(), golden.ticks, label + "comprimento da rota mudou; a rota é parte do dourado")
		eq(simulation.permille, golden.permille, label + "progresso da primeira captura " + DRIFT_HINT)
		eq(simulation.score, golden.score, label + "pontuação da primeira captura " + DRIFT_HINT)
		eq(simulation.fills_done, 1, label + "a rota dourada precisa fechar exatamente uma captura")
		eq(
			simulation.state_checksum().hex_encode(),
			golden.final_checksum,
			label + "checksum final após %d ticks " % golden.ticks + DRIFT_HINT,
		)
		eq(
			replay.checksum().hex_encode(),
			golden.replay_checksum,
			label + "checksum do log serializado " + DRIFT_HINT,
		)


func test_pinned_replays_still_reproduce_bit_exact_on_a_fresh_simulation() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	if campaign == null:
		return
	for index in mini(campaign.rounds.size(), GOLDEN_ROUNDS.size()):
		var golden: Dictionary = GOLDEN_ROUNDS[index]
		var content := campaign.rounds[index]
		var recorded := GameSimulation.new(
			content.rules, content.round_definition, content.seed_value
		)
		var replay := ReplayLog.start(recorded)
		for segment in golden.route:
			for _tick in int(segment[2]):
				var intent := MoveIntent.make(segment[0], segment[1])
				recorded.step(intent)
				replay.record(intent)

		# Serializa e desserializa: o log que o jogo grava em disco tem de valer o mesmo.
		var restored := ReplayLog.from_bytes(replay.to_bytes())
		ok(restored != null, "%s: o log dourado precisa sobreviver a to_bytes/from_bytes" % golden.id)
		if restored == null:
			continue

		var fresh := GameSimulation.new(content.rules, content.round_definition, content.seed_value)
		eq(restored.compatibility_error(fresh), "", "%s: log dourado precisa ser compatível com o runtime" % golden.id)
		var final_checksum := restored.replay_into(fresh)
		eq(
			final_checksum.hex_encode(),
			golden.final_checksum,
			"%s: reprodução do log dourado divergiu do checksum fixado " % golden.id + DRIFT_HINT,
		)
