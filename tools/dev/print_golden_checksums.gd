extends SceneTree
## Imprime os valores dourados por rodada de produção para colar em
## tests/integration/replay_checksum_golden_test.gd depois de um bump deliberado de contrato.
## Uso: Godot --headless --path . --script res://tools/dev/print_golden_checksums.gd

const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"
## Rota dourada por rodada: os primeiros segmentos da rota humana de
## boss_active_campaign_playthrough_test — atravessa a fronteira e fecha a primeira captura.
const ROUTES := {
	&"abyssal_relay": [[MoveIntent.Dir.LEFT, false, 36], [MoveIntent.Dir.DOWN, true, 141]],
	&"aurora_foundry": [[MoveIntent.Dir.LEFT, false, 6], [MoveIntent.Dir.DOWN, true, 141]],
	&"verdant_singularity": [[MoveIntent.Dir.LEFT, false, 16], [MoveIntent.Dir.DOWN, true, 141]],
}


func _initialize() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	print("RULES_VERSION=%d SCHEMA_VERSION=%d" % [GameRules.RULES_VERSION, ReplayLog.SCHEMA_VERSION])
	for content in campaign.rounds:
		var simulation := GameSimulation.new(content.rules, content.round_definition, content.seed_value)
		var initial := simulation.state_checksum().hex_encode()
		var replay := ReplayLog.start(simulation)
		var route: Array = ROUTES.get(content.round_id, [])
		for segment in route:
			for _tick in int(segment[2]):
				var intent := MoveIntent.make(segment[0], segment[1])
				simulation.step(intent)
				replay.record(intent)
		print(JSON.stringify({
			"id": String(content.round_id),
			"seed": content.seed_value,
			"config_hash": ReplayLog.config_hash(content.rules, content.round_definition).hex_encode(),
			"ticks": replay.tick_count(),
			"permille": simulation.permille,
			"score": simulation.score,
			"fills_done": simulation.fills_done,
			"initial_checksum": initial,
			"final_checksum": simulation.state_checksum().hex_encode(),
			"replay_checksum": replay.checksum().hex_encode(),
		}))
	quit(0)
