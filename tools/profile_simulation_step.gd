extends SceneTree
## Perfil do custo de `GameSimulation.step()` no campo de produção, com o chefe ativo.
##
## Uso:
##   Godot --headless --path . --script res://tools/profile_simulation_step.gd [-- --ticks=3600]
## Roda a rota humana da rodada 1 (a mesma de boss_active_campaign_playthrough_test) e depois
## intents pseudoaleatórios até completar `--ticks`, medindo cada `step` com o relógio de
## apresentação. Imprime JSON com média, p50, p95, p99 e máximo em microssegundos.
##
## O relógio fica fora do domínio (invariante 1): mede-se por fora, nunca por dentro.
## `tests/integration/simulation_step_budget_test.gd` usa `measure()` como catraca.

const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"
const ROUTE := [
	[MoveIntent.Dir.LEFT, false, 36], [MoveIntent.Dir.DOWN, true, 141],
	[MoveIntent.Dir.RIGHT, false, 20], [MoveIntent.Dir.UP, true, 141],
	[MoveIntent.Dir.RIGHT, false, 15], [MoveIntent.Dir.DOWN, true, 141],
]


func _initialize() -> void:
	var ticks := 3600
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ticks="):
			ticks = maxi(60, argument.trim_prefix("--ticks=").to_int())
	var report := measure(ticks)
	print(JSON.stringify(report))
	quit(0)


## Mede `ticks` passos na rodada 1 da campanha de produção. Devolve estatísticas em µs.
static func measure(ticks: int, round_index: int = 0) -> Dictionary:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	assert(campaign != null, "campanha de produção precisa carregar")
	var content := campaign.rounds[round_index]
	var rules := content.rules.duplicate(true) as GameRules
	rules.shield_ticks = 1_000_000  # o perfil mede custo, não sobrevivência
	rules.shield_critical_ticks = 0
	var simulation := GameSimulation.new(rules, content.round_definition, content.seed_value)
	var intents := _intents_for(ticks, content.seed_value)
	var samples := PackedInt64Array()
	samples.resize(ticks)
	var total := 0
	for i in ticks:
		var started := Time.get_ticks_usec()
		simulation.step(intents[i])
		var elapsed := Time.get_ticks_usec() - started
		samples[i] = elapsed
		total += elapsed
	var sorted := Array(samples)
	sorted.sort()
	return {
		"ticks": ticks,
		"round_index": round_index,
		"final_tick": simulation.tick,
		"final_permille": simulation.permille,
		"final_phase": simulation.phase,
		"mean_usec": float(total) / float(ticks),
		"p50_usec": _percentile(sorted, 50),
		"p95_usec": _percentile(sorted, 95),
		"p99_usec": _percentile(sorted, 99),
		"max_usec": sorted[sorted.size() - 1],
	}


## Rota humana e depois intents pseudoaleatórios de um RNG de teste (não o da simulação).
static func _intents_for(ticks: int, seed_value: int) -> Array[MoveIntent]:
	var out: Array[MoveIntent] = []
	for segment in ROUTE:
		for _t in int(segment[2]):
			out.append(MoveIntent.make(segment[0], segment[1]))
	var rng := DeterministicRng.new(seed_value ^ 0x5EED)
	var current := MoveIntent.Dir.LEFT
	var drawing := false
	while out.size() < ticks:
		if rng.next_below(24) == 0:
			current = 1 + rng.next_below(4)
		if rng.next_below(90) == 0:
			drawing = not drawing
		out.append(MoveIntent.make(current, drawing))
	out.resize(ticks)
	return out


static func _percentile(sorted_values: Array, percentile: int) -> int:
	if sorted_values.is_empty():
		return 0
	@warning_ignore("integer_division")
	var index := mini((percentile * sorted_values.size() + 99) / 100 - 1, sorted_values.size() - 1)
	return int(sorted_values[maxi(index, 0)])
