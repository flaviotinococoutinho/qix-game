extends TestCase


func test_capture_collects_beacons_once_in_author_order_and_replays() -> void:
	var sim := _simulation()
	var replay := ReplayLog.start(sim)
	var captures: Array[GameEvent] = []
	for _tick in 15:
		var intent := MoveIntent.make(MoveIntent.Dir.DOWN, true)
		replay.record(intent)
		for event in sim.step(intent):
			if event.kind == GameEvent.Kind.BEACON_CAPTURED:
				captures.append(event)
	eq(sim.fills_done, 1)
	eq(captures.size(), 2)
	if captures.size() != 2:
		return
	eq(captures[0].data.index, 0)
	eq(captures[1].data.index, 1)
	eq(captures[0].data.points, 1000)
	eq(captures[1].data.points, 2000)
	eq(sim.beacons.captured_count(), 2)
	eq(sim.effects.remaining[ItemProfile.Kind.VELOCITY], 360, "pickup não consome duração no tick de captura")
	eq(sim.effects.remaining[ItemProfile.Kind.STASIS], 180)
	var restored := ReplayLog.from_bytes(replay.to_bytes())
	ok(restored != null)
	if restored != null:
		var fresh := GameSimulation.new(sim.rules, sim.round_def, sim.seed_value)
		eq(restored.replay_into(fresh), sim.state_checksum())
	var next := sim.step(MoveIntent.none())
	eq(_count(next, GameEvent.Kind.BEACON_CAPTURED), 0)
	eq(sim.beacons.captured_count(), 2)
	eq(sim.effects.remaining[ItemProfile.Kind.STASIS], 179)


func test_one_tick_effects_affect_a_full_gameplay_tick() -> void:
	var sim := _simulation()
	sim.rules.boss_speed_fp = 96
	sim.rules.boss_substeps = 1
	var profile := sim.item_profile()
	profile.effect_durations_ticks[ItemProfile.Kind.STASIS] = 1
	profile.effect_durations_ticks[ItemProfile.Kind.SHIELD_FREEZE] = 1
	profile.effect_durations_ticks[ItemProfile.Kind.VELOCITY] = 1
	var events: Array[GameEvent] = []
	for kind in [ItemProfile.Kind.STASIS, ItemProfile.Kind.SHIELD_FREEZE, ItemProfile.Kind.VELOCITY]:
		sim._activate_item(kind, events)
	var boss_start := Vector2i(sim.bx_fp, sim.by_fp)
	var shield_start := sim.shield_ticks
	var player_start := sim.px
	var tick_events := sim.step(MoveIntent.make(MoveIntent.Dir.LEFT, false))
	eq(Vector2i(sim.bx_fp, sim.by_fp), boss_start, "um tick de estase congela um tick completo")
	eq(sim.shield_ticks, shield_start, "um tick de âncora congela um tick completo")
	eq(sim.px, player_start - sim.rules.substeps_speedup)
	eq(_count(tick_events, GameEvent.Kind.ITEM_ENDED), 3)
	sim.step(MoveIntent.none())
	ok(Vector2i(sim.bx_fp, sim.by_fp) != boss_start, "chefe volta após expiração")
	eq(sim.shield_ticks, shield_start - 1)


func test_purge_retires_every_minor_kind_and_restores_shield_floor() -> void:
	var sim := _simulation()
	WalkerRules.spawn(sim.pools, 0, Vector2i(0, 15), 0, 1, 30, MinorActorPools.Cause.LADDER)
	sim.pools.begin_dart(0, 24)
	EmberRules.ignite(sim.pools, 0, 0, MinorActorPools.Cause.STALL)
	sim.shield_ticks = 3
	sim.shield_critical_sent = true
	var events: Array[GameEvent] = []
	sim._activate_item(ItemProfile.Kind.PURGE, events)
	eq(sim.pools.alive_total(), 0)
	eq(sim.pools.walker_lifecycle(0), ActorLifecycle.State.DYING)
	eq(sim.pools.dart_lifecycle(0), ActorLifecycle.State.DYING)
	eq(sim.pools.ember_lifecycle(0), ActorLifecycle.State.DYING)
	eq(sim.shield_ticks, sim.item_profile().shield_floor_ticks)
	ok(not sim.shield_critical_sent)
	eq(sim.score, 0, "expurgar não paga pontos de armadilha")
	sim.shield_ticks = 900
	sim._activate_item(ItemProfile.Kind.PURGE, events)
	eq(sim.shield_ticks, 900, "piso nunca reduz reserva maior")


func test_sealed_win_uses_confirmed_free_area_and_boss_lifecycle() -> void:
	var sim := _simulation()
	sim.item_profile().sealed_free_cell_limit = 500
	var ladder := sim.rules.bonus_ladder as BonusLadder
	ladder.enabled = true
	var all: Array[GameEvent] = []
	for _tick in 15:
		all.append_array(sim.step(MoveIntent.make(MoveIntent.Dir.DOWN, true)))
	eq(sim.phase, GameSimulation.Phase.ROUND_WON)
	eq(sim.round_end_reason, GameRules.RoundEndReason.SEALED)
	eq(_count(all, GameEvent.Kind.BOSS_SEALED), 1)
	eq(_count(all, GameEvent.Kind.ROUND_WON), 1)
	ok(sim.permille < sim.rules.target_permille, "selamento é alternativa ao alvo")
	eq(sim.boss.lifecycle(), ActorLifecycle.State.DYING)
	for event in all:
		if event.kind == GameEvent.Kind.ROUND_WON:
			eq(event.data.bonus, 12500, "piso1000 × selado10 × sem morte1,25")
	for _tick in sim.threat_profile().actor_despawn_ticks:
		sim.step(MoveIntent.none())
	eq(sim.boss.lifecycle(), ActorLifecycle.State.DESPAWNED)


func test_duplicate_beacon_placement_is_rejected_by_round_contract() -> void:
	var sim := _simulation()
	var definition := sim.round_def.duplicate(true) as RoundDefinition
	definition.beacon_cells = PackedInt32Array([8, 10, 8, 10])
	ok(not definition.validation_errors().is_empty())


func test_lethal_tick_keeps_effect_timer_in_sync_with_frozen_boss() -> void:
	var sim := _simulation()
	sim.rules.death_ticks = 1
	var events: Array[GameEvent] = []
	sim._activate_item(ItemProfile.Kind.STASIS, events)
	WalkerRules.spawn(sim.pools, 0, sim.player.cell(), 1, 1, 0, MinorActorPools.Cause.LADDER)
	sim.step(MoveIntent.none())
	eq(sim.phase, GameSimulation.Phase.DYING)
	eq(sim.boss.stasis_ticks, sim.effects.remaining[ItemProfile.Kind.STASIS],
		"tick letal já consumiu estase no movimento e deve consumir seu relógio")
	sim.step(MoveIntent.none())
	eq(sim.phase, GameSimulation.Phase.PLAYING)
	eq(sim.boss.stasis_ticks, sim.effects.remaining[ItemProfile.Kind.STASIS])


func _simulation() -> GameSimulation:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.shield_ticks = 10000
	rules.target_permille = 995
	var profile := rules.items as ItemProfile
	profile.enabled = true
	profile.sealed_free_cell_limit = 0
	var definition := RoundDefinition.new()
	definition.field_width = 31
	definition.field_height = 31
	definition.player_spawn = Vector2i(15, 0)
	definition.boss_start = Vector2i(24, 24)
	definition.beacon_cells = PackedInt32Array([8, 10, 8, 20])
	return GameSimulation.new(rules, definition, 17)


func _count(events: Array[GameEvent], kind: int) -> int:
	var count := 0
	for event in events:
		if event.kind == kind:
			count += 1
	return count
