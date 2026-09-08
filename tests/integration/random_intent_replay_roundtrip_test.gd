extends TestCase
## Reprodutibilidade sob entrada arbitrária (invariante 7): intents pseudoaleatórios em cada
## setor de produção, serializados e reproduzidos numa simulação nova, têm de chegar ao mesmo
## checksum. Rotas autoradas provam o caminho feliz; esta prova cobre o que ninguém autorou.

const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"
const SEEDS := [11, 2026, 90210]
const TICKS := 1800


func test_random_intents_replay_bit_exact_on_every_production_round() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "campanha de produção precisa carregar")
	if campaign == null:
		return
	var distinct := {}
	for content in campaign.rounds:
		for seed_value in SEEDS:
			var rules := content.rules.duplicate(true) as GameRules
			rules.shield_ticks = 100_000  # o escudo mataria antes de o replay ficar interessante
			rules.shield_critical_ticks = 0
			var recorded := GameSimulation.new(rules, content.round_definition, content.seed_value)
			var replay := ReplayLog.start(recorded)
			var driver := DeterministicRng.new(seed_value)
			var direction := MoveIntent.Dir.LEFT
			var drawing := false
			for _tick in TICKS:
				if driver.next_below(20) == 0:
					direction = 1 + driver.next_below(4)
				if driver.next_below(75) == 0:
					drawing = not drawing
				var intent := MoveIntent.make(direction, drawing)
				replay.record(intent)
				recorded.step(intent)
			var restored := ReplayLog.from_bytes(replay.to_bytes())
			ok(restored != null, "%s/%d: log não sobreviveu a to_bytes/from_bytes" % [content.round_id, seed_value])
			if restored == null:
				continue
			var fresh := GameSimulation.new(rules, content.round_definition, content.seed_value)
			eq(restored.compatibility_error(fresh), "", "%s/%d" % [content.round_id, seed_value])
			var replayed_checksum := restored.replay_into(fresh)
			eq(
				replayed_checksum.hex_encode(),
				recorded.state_checksum().hex_encode(),
				"%s/%d: reprodução divergiu do original" % [content.round_id, seed_value],
			)
			eq(fresh.tick, recorded.tick)
			eq(fresh.rng.state, recorded.rng.state, "o RNG precisa terminar no mesmo estado")
			distinct[replayed_checksum.hex_encode()] = true
	ok(distinct.size() == campaign.rounds.size() * SEEDS.size(), "cada seed precisa produzir uma partida distinta")
