extends TestCase
## Contratos públicos de balizas, itens e bônus; os testes de integração exercitam o tick.


func test_beacons_require_claimed_territory_and_pay_each_identity_once() -> void:
	var board := BoardState.new(32, 32)
	var state := BeaconState.new()
	ok(state.reset(PackedInt32Array([8, 8, 10, 8, 12, 8]), 32, 32))
	var profile := ItemProfile.new()
	var events: Array[GameEvent] = []
	board.set_cell(8, 8, BoardState.Cell.BOUNDARY)
	board.set_cell(10, 8, BoardState.Cell.TRAIL)
	board.set_cell(12, 8, BoardState.Cell.CLAIMED)
	var board_before := board.canonical_bytes()
	eq(BeaconRules.capture_claimed(state, board, 1, profile, events), 1000)
	eq(events.size(), 1)
	eq(events[0].data.index, 2)
	eq(events[0].data.chain, 1)
	ok(not state.is_captured(0), "baliza sobre fronteira não foi cercada")
	ok(not state.is_captured(1), "trilha pendente não confirma recompensa")
	ok(state.is_captured(2))
	eq(board.canonical_bytes(), board_before, "objetivos nunca escrevem território")
	var state_before := state.canonical_bytes()
	eq(BeaconRules.capture_claimed(state, board, 1, profile, events), 0)
	eq(events.size(), 1, "nenhum evento duplicado")
	eq(state.canonical_bytes(), state_before)


func test_capture_chain_is_stable_per_fill_and_restarts_on_next_fill() -> void:
	var board := BoardState.new(32, 32)
	var state := BeaconState.new()
	ok(state.reset(PackedInt32Array([8, 8, 10, 8, 12, 8]), 32, 32))
	board.set_cell(8, 8, BoardState.Cell.CLAIMED)
	board.set_cell(12, 8, BoardState.Cell.CLAIMED)
	var events: Array[GameEvent] = []
	var profile := ItemProfile.new()
	eq(BeaconRules.capture_claimed(state, board, 1, profile, events), 3000)
	eq(events[0].data.index, 0)
	eq(events[1].data.index, 2)
	eq(events[1].data.chain, 2)
	eq(events[1].data.points, 2000)
	eq(state.captured_fill[2], 1)
	board.set_cell(10, 8, BoardState.Cell.CLAIMED)
	eq(BeaconRules.capture_claimed(state, board, 2, profile, events), 1000)
	eq(events[2].data.chain, 1)
	eq(state.captured_fill[1], 2)


func test_invalid_beacon_placement_is_rejected_atomically() -> void:
	var state := BeaconState.new()
	ok(state.reset(PackedInt32Array([8, 8]), 32, 32))
	var before := state.canonical_bytes()
	for cells in [PackedInt32Array([8]), PackedInt32Array([7, 8]),
			PackedInt32Array([24, 8]), PackedInt32Array([8, 8, 8, 8]),
			PackedInt32Array([-1, 8])]:
		ok(not state.reset(cells, 32, 32))
		eq(state.canonical_bytes(), before)
	var over_capacity := PackedInt32Array()
	for index in 17:
		over_capacity.append_array(PackedInt32Array([8 + index, 8]))
	ok(not state.reset(over_capacity, 64, 32))
	eq(state.canonical_bytes(), before)


func test_beacon_reset_clears_previous_lifecycle_without_aliasing_content() -> void:
	var cells := PackedInt32Array([8, 8])
	var state := BeaconState.new()
	ok(state.reset(cells, 32, 32))
	cells[0] = 9
	eq(state.cell(0), Vector2i(8, 8))
	var board := BoardState.new(32, 32)
	board.set_cell(8, 8, BoardState.Cell.CLAIMED)
	var events: Array[GameEvent] = []
	BeaconRules.capture_claimed(state, board, 1, ItemProfile.new(), events)
	ok(state.is_captured(0))
	ok(state.reset(PackedInt32Array([10, 10]), 32, 32))
	ok(not state.is_captured(0))
	eq(state.captured_count(), 0)
	eq(state.captured_fill[0], 0)
	ok(state.reset(PackedInt32Array(), 3, 3), "rodadas de isolamento não precisam de balizas")
	eq(state.count, 0)


func test_item_order_is_authorable_and_depends_on_beacon_identity_and_fill() -> void:
	var profile := ItemProfile.new()
	profile.capture_cycle = PackedInt32Array([0, 1, 2, 3, 4, 0, 1, 2, 3, 4])
	eq(profile.item_for_capture(0, 1), ItemProfile.Kind.VELOCITY)
	eq(profile.item_for_capture(1, 1), ItemProfile.Kind.STASIS)
	eq(profile.item_for_capture(0, 2), ItemProfile.Kind.STASIS)
	eq(profile.item_for_capture(15, 7), ItemProfile.Kind.STASIS)
	eq(profile.item_for_capture(-1, 1), ItemProfile.Kind.NONE)
	eq(profile.item_for_capture(16, 1), ItemProfile.Kind.NONE)
	eq(profile.item_for_capture(0, -1), ItemProfile.Kind.NONE)


func test_chain_has_bounded_growth_and_profile_validation_is_strict() -> void:
	var profile := ItemProfile.new()
	ok(profile.validation_errors().is_empty())
	eq(profile.chain_points(0), 0)
	eq(profile.chain_points(1), 1000)
	eq(profile.chain_points(2), 2000)
	eq(profile.chain_points(7), 64000)
	eq(profile.chain_points(16), 64000)
	profile.capture_cycle[0] = 5
	ok(not profile.validation_errors().is_empty(), "ID desconhecido não é conteúdo válido")
	profile = ItemProfile.new()
	profile.effect_durations_ticks[ItemProfile.Kind.STASIS] = -1
	ok(not profile.validation_errors().is_empty())
	profile = ItemProfile.new()
	profile.chain_max_steps = 32
	ok(not profile.validation_errors().is_empty(), "não permitir shift arbitrário")


func test_temporary_effect_lasts_exactly_authorable_ticks_and_expires_once() -> void:
	var profile := ItemProfile.new()
	profile.effect_durations_ticks[ItemProfile.Kind.STASIS] = 2
	var timers := EffectTimers.new()
	ok(timers.activate(ItemProfile.Kind.STASIS, profile))
	ok(timers.active(ItemProfile.Kind.STASIS))
	eq(timers.remaining[ItemProfile.Kind.STASIS], 2)
	eq(timers.advance(), PackedInt32Array())
	ok(timers.active(ItemProfile.Kind.STASIS))
	eq(timers.advance(), PackedInt32Array([ItemProfile.Kind.STASIS]))
	ok(not timers.active(ItemProfile.Kind.STASIS))
	eq(timers.advance(), PackedInt32Array())
	eq(timers.remaining[ItemProfile.Kind.STASIS], 0)


func test_effect_refresh_does_not_stack_or_shorten_an_active_effect() -> void:
	var profile := ItemProfile.new()
	profile.effect_durations_ticks[ItemProfile.Kind.VELOCITY] = 4
	var timers := EffectTimers.new()
	ok(timers.activate(ItemProfile.Kind.VELOCITY, profile))
	timers.advance()
	ok(timers.activate(ItemProfile.Kind.VELOCITY, profile))
	eq(timers.remaining[ItemProfile.Kind.VELOCITY], 4)
	profile.effect_durations_ticks[ItemProfile.Kind.VELOCITY] = 2
	ok(timers.activate(ItemProfile.Kind.VELOCITY, profile))
	eq(timers.remaining[ItemProfile.Kind.VELOCITY], 4)
	ok(timers.activate(ItemProfile.Kind.STASIS, profile))
	ok(timers.active(ItemProfile.Kind.VELOCITY))
	ok(timers.active(ItemProfile.Kind.STASIS), "efeitos distintos coexistem")
	timers.reset()
	ok(not timers.active(ItemProfile.Kind.STASIS))
	ok(not timers.active(ItemProfile.Kind.VELOCITY))


func test_timers_reject_invalid_ids_without_mutating_and_expire_in_id_order() -> void:
	var profile := ItemProfile.new()
	profile.effect_durations_ticks = PackedInt32Array([0, 1, 1, 1, 1])
	var timers := EffectTimers.new()
	var before := timers.canonical_bytes()
	for kind in [-1, 0, 5, 1000]:
		ok(not timers.activate(kind, profile))
		ok(not timers.active(kind))
		eq(timers.canonical_bytes(), before)
	for kind in [4, 2, 3, 1]:
		ok(timers.activate(kind, profile))
	eq(timers.advance(), PackedInt32Array([1, 2, 3, 4]))


func test_bonus_ladder_rewards_precision_and_handles_all_round_end_reasons() -> void:
	var ladder := BonusLadder.new()
	ok(ladder.validation_errors().is_empty())
	eq(ladder.base_points(799), 0)
	eq(ladder.base_points(800), 1000)
	eq(ladder.base_points(809), 1000)
	eq(ladder.base_points(810), 1100)
	eq(ladder.base_points(900), 2000)
	eq(ladder.base_points(950), 3000)
	eq(ladder.base_points(990), 10000)
	eq(ladder.base_points(993), 13000)
	eq(ladder.base_points(998), 30000)
	eq(ladder.base_points(999), 50000)
	eq(ladder.base_points(1000), 50000)
	eq(ladder.award(800, GameRules.RoundEndReason.TARGET, false), 1000)
	eq(ladder.award(800, GameRules.RoundEndReason.TARGET, true), 1250)
	eq(ladder.award(800, GameRules.RoundEndReason.SEALED, false), 10000)
	eq(ladder.award(600, GameRules.RoundEndReason.SEALED, false), 10000,
		"selamento confirmado antes do primeiro limiar ainda paga a base")
	eq(ladder.award(600, GameRules.RoundEndReason.TARGET, true), 1250,
		"alvo customizado continua remunerando uma vitória confirmada")
	eq(ladder.award(800, GameRules.RoundEndReason.SINGLE_FILL, true), 125000)
	eq(ladder.award(900, GameRules.RoundEndReason.NONE, true), 0)
	eq(ladder.award(900, 99, true), 0)


func test_bonus_ladder_rejects_unsorted_mismatched_or_negative_content() -> void:
	var ladder := BonusLadder.new()
	ladder.thresholds_permille = PackedInt32Array([900, 800])
	ladder.points = PackedInt32Array([1000, 2000])
	ok(not ladder.validation_errors().is_empty())
	ladder = BonusLadder.new()
	ladder.points.resize(2)
	ok(not ladder.validation_errors().is_empty())
	ladder = BonusLadder.new()
	ladder.points[0] = -1
	ok(not ladder.validation_errors().is_empty())


func test_authorable_profiles_and_mutable_states_have_canonical_fingerprints() -> void:
	var profile := ItemProfile.new()
	var original_profile := profile.canonical_bytes()
	profile.effect_durations_ticks[1] += 1
	ne(profile.canonical_bytes(), original_profile)
	var ladder := BonusLadder.new()
	var original_ladder := ladder.canonical_bytes()
	ladder.no_death_bonus_permille += 1
	ne(ladder.canonical_bytes(), original_ladder)
	var a := EffectTimers.new()
	var b := EffectTimers.new()
	eq(a.canonical_bytes(), b.canonical_bytes())
	ok(a.activate(ItemProfile.Kind.STASIS, profile))
	ne(a.canonical_bytes(), b.canonical_bytes())
	ok(b.activate(ItemProfile.Kind.STASIS, profile))
	eq(a.canonical_bytes(), b.canonical_bytes())
