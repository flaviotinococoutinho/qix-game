extends TestCase
## O buffer de curva vive no intent, não em estado do domínio: o adaptador decide, o domínio
## executa só quando o primário bloqueia, e o replay grava as duas intenções num byte.


func test_byte_round_trip_carries_direction_draw_and_fallback() -> void:
	for dir in range(MoveIntent.Dir.NONE, MoveIntent.Dir.LEFT + 1):
		for fallback in range(MoveIntent.Dir.NONE, MoveIntent.Dir.LEFT + 1):
			for draw in [false, true]:
				var intent := MoveIntent.make(dir, draw, fallback)
				var restored := MoveIntent.from_byte(intent.to_byte())
				eq(restored.direction, dir)
				eq(restored.drawing, draw)
				eq(restored.fallback, fallback)
				ok(intent.to_byte() < 128, "bit 7 fica reservado em zero")


func test_legacy_bytes_without_fallback_decode_identically() -> void:
	# Um log gravado antes do fallback só usa os bits 0..3.
	var legacy := (MoveIntent.Dir.DOWN & 0x7) | 0x8
	var restored := MoveIntent.from_byte(legacy)
	eq(restored.direction, MoveIntent.Dir.DOWN)
	ok(restored.drawing)
	eq(restored.fallback, MoveIntent.Dir.NONE)


func test_out_of_range_fallback_saturates_to_none() -> void:
	var restored := MoveIntent.from_byte((5 << 4) | MoveIntent.Dir.UP)
	eq(restored.direction, MoveIntent.Dir.UP)
	eq(restored.fallback, MoveIntent.Dir.NONE)
	var also := MoveIntent.from_byte((7 << 4) | 0x8)
	eq(also.fallback, MoveIntent.Dir.NONE)


func test_fallback_keeps_the_player_sliding_until_the_turn_becomes_legal() -> void:
	# Jogador no topo da moldura, sem desenhar: DOWN entra em FREE sem draw (bloqueado),
	# RIGHT é a direção segurada. Ele desliza para a direita até a coluna da moldura, onde
	# DOWN vira BOUNDARY e a curva pedida acontece sozinha — sem estado extra no checksum.
	var rules := _rules()
	var simulation := GameSimulation.new(rules, _round(9, 9, Vector2i(2, 0)), 5)
	var intent := MoveIntent.make(MoveIntent.Dir.DOWN, false, MoveIntent.Dir.RIGHT)
	simulation.step(intent)
	eq(Vector2i(simulation.px, simulation.py), Vector2i(3, 0), "fallback anda pela moldura")
	for _tick in 5:
		simulation.step(intent)
	eq(Vector2i(simulation.px, simulation.py), Vector2i(8, 0), "chega ao canto pela direção segurada")
	simulation.step(intent)
	eq(Vector2i(simulation.px, simulation.py), Vector2i(8, 1), "no canto a curva pedida vira legal e acontece")
	ok(not simulation.trail_active, "nada disto começou uma trilha")


func test_fallback_is_ignored_when_the_primary_moves() -> void:
	var rules := _rules()
	var simulation := GameSimulation.new(rules, _round(9, 9, Vector2i(4, 0)), 5)
	simulation.step(MoveIntent.make(MoveIntent.Dir.RIGHT, false, MoveIntent.Dir.LEFT))
	eq(Vector2i(simulation.px, simulation.py), Vector2i(5, 0))


func test_fallback_equal_to_primary_is_canonicalized_away_and_replay_stays_exact() -> void:
	var rules := _rules()
	var definition := _round(9, 9, Vector2i(4, 0))
	var recorded := GameSimulation.new(rules, definition, 77)
	var replay := ReplayLog.start(recorded)
	var script := [
		MoveIntent.make(MoveIntent.Dir.DOWN, false, MoveIntent.Dir.RIGHT),
		MoveIntent.make(MoveIntent.Dir.RIGHT, false, MoveIntent.Dir.RIGHT),
		MoveIntent.make(MoveIntent.Dir.DOWN, true, MoveIntent.Dir.LEFT),
		MoveIntent.make(MoveIntent.Dir.DOWN, true, MoveIntent.Dir.LEFT),
		MoveIntent.make(MoveIntent.Dir.LEFT, true, MoveIntent.Dir.DOWN),
	]
	for intent in script:
		replay.record(intent)
		recorded.step(intent)
	var fresh := GameSimulation.new(rules, definition, 77)
	eq(replay.replay_into(fresh), recorded.state_checksum(), "o byte com fallback reproduz exato")


func _rules() -> GameRules:
	var rules := GameRules.new()
	rules.substeps_normal = 1
	rules.substeps_speedup = 1
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.shield_ticks = 10_000
	return rules


func _round(w: int, h: int, spawn: Vector2i) -> RoundDefinition:
	var definition := RoundDefinition.new()
	definition.field_width = w
	definition.field_height = h
	definition.player_spawn = spawn
	definition.boss_start = Vector2i(4, 4)
	return definition
