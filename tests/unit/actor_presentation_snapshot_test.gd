extends TestCase
## Contrato das views: estado confirmado, trajetórias reais e nenhuma escrita na simulação.


func test_minor_snapshot_preserves_checksum_and_uses_actual_walker_route() -> void:
	var simulation := _simulation()
	WalkerRules.spawn(simulation.pools, 0, Vector2i(5, 0), 1, 1, 24, MinorActorPools.Cause.LADDER)
	var path := WalkerRules.peek_path(simulation.pools, 0, simulation.board, QixMinorActorView.TELEGRAPH_CELLS)
	var before := simulation.state_checksum()
	var view := QixMinorActorView.new()
	view.sync(simulation)
	var snapshot := view.presentation_state()
	var actor: Dictionary = snapshot.walkers[0]
	eq(actor.lifecycle, ActorLifecycle.State.WARMUP)
	eq(actor.id, simulation.pools.walker_actor_id(0))
	eq(actor.path.size(), path.size())
	for index in path.size():
		@warning_ignore("integer_division")
		var cell := Vector2i(path[index] % simulation.board.width, path[index] / simulation.board.width)
		eq(actor.path[index], Vector2(CoordinateSpace.field_to_screen(cell)))
	eq(simulation.state_checksum(), before, "gerar telegraph não consome RNG nem move o vagalume")
	view.free()


func test_snapshot_is_detached_from_domain_and_callers() -> void:
	var simulation := _simulation()
	WalkerRules.spawn(simulation.pools, 0, Vector2i(5, 0), 1, 1, 0, MinorActorPools.Cause.LADDER)
	var view := QixMinorActorView.new()
	view.sync(simulation)
	var snapshot := view.presentation_state()
	var original: Vector2 = snapshot.walkers[0].position
	snapshot.walkers[0].position = Vector2(999.0, 999.0)
	eq(view.presentation_state().walkers[0].position, original, "um proxy não edita a leitura da view")
	simulation.pools.set_walker(0, MinorActorPools.W.X, 8)
	eq(view.presentation_state().walkers[0].position, original, "a view mantém o último snapshot até sync")
	view.sync(simulation)
	eq(view.presentation_state().walkers[0].position, Vector2(CoordinateSpace.field_to_screen(Vector2i(8, 0))))
	view.free()


func test_retiring_actor_stays_visible_until_confirmed_despawn() -> void:
	var simulation := _simulation()
	WalkerRules.spawn(simulation.pools, 0, Vector2i(5, 0), 1, 1, 0, MinorActorPools.Cause.LADDER)
	var id := simulation.pools.walker_actor_id(0)
	simulation.pools.retire_walker(0, MinorActorPools.Reason.EXTINGUISHED, 12)
	var before := simulation.state_checksum()
	var view := QixMinorActorView.new()
	view.sync(simulation)
	eq(view.presentation_state().walkers.size(), 1)
	eq(view.presentation_state().walkers[0].id, id)
	eq(view.presentation_state().walkers[0].lifecycle, ActorLifecycle.State.DYING)
	ok(view.visible)
	eq(simulation.state_checksum(), before)
	for _tick in 12:
		simulation.pools.advance_removals()
	view.sync(simulation)
	eq(view.presentation_state().walkers.size(), 0)
	ok(not view.visible)
	view.free()


func test_dart_snapshot_uses_domain_direction_and_warmup() -> void:
	var simulation := _simulation()
	var slot := DartRules.try_spawn(
		simulation.pools, simulation.board, Vector2i(16, 14), simulation.rng,
		384, 6, 24, 240, MinorActorPools.Cause.EXPOSURE)
	ok(slot >= 0)
	var dir := simulation.pools.dart(slot, MinorActorPools.D.DIR_INDEX)
	var before := simulation.state_checksum()
	var view := QixMinorActorView.new()
	view.sync(simulation)
	var actor: Dictionary = view.presentation_state().darts[0]
	eq(actor.lifecycle, ActorLifecycle.State.WARMUP)
	eq(actor.warmup, 24)
	eq(actor.direction, Vector2(DartRules.DIRECTION_X[dir], DartRules.DIRECTION_Y[dir]).normalized())
	eq(actor.position, Vector2(CoordinateSpace.field_to_screen(simulation.pools.dart_cell(slot))))
	eq(simulation.state_checksum(), before)
	view.free()


func test_dart_warmup_telegraph_carries_the_domain_corridor_and_only_while_armed() -> void:
	var simulation := _simulation()
	var slot := DartRules.try_spawn(
		simulation.pools, simulation.board, Vector2i(16, 14), simulation.rng,
		384, 6, 24, 240, MinorActorPools.Cause.EXPOSURE)
	ok(slot >= 0)
	var corridor := DartRules.peek_path(
		simulation.pools, slot, simulation.board, QixMinorActorView.TELEGRAPH_MAX_CELLS)
	ok(corridor.size() > QixMinorActorView.MUZZLE_CELLS, "há corredor além da boca do disparo")
	var before := simulation.state_checksum()
	var view := QixMinorActorView.new()
	view.sync(simulation)
	var actor: Dictionary = view.presentation_state().darts[0]
	eq(actor.lifecycle, ActorLifecycle.State.WARMUP)
	eq(actor.path.size(), corridor.size())
	for index in corridor.size():
		@warning_ignore("integer_division")
		var cell := Vector2i(corridor[index] % simulation.board.width, corridor[index] / simulation.board.width)
		eq(actor.path[index], Vector2(CoordinateSpace.field_to_screen(cell)))
	eq(simulation.state_checksum(), before, "desenhar o corredor não consome RNG nem move o dardo")
	# Disparado, o aviso some: a leitura passa a ser o rastro do voo confirmado.
	simulation.pools.set_dart(slot, MinorActorPools.D.WARMUP, 0)
	simulation.pools.set_dart(slot, MinorActorPools.D.STATE, ActorLifecycle.State.ACTIVE)
	view.sync(simulation)
	eq(view.presentation_state().darts[0].lifecycle, ActorLifecycle.State.ACTIVE)
	eq(view.presentation_state().darts[0].path.size(), 0, "corredor previsto só existe no armamento")
	view.free()


func test_retired_ember_uses_last_confirmed_cell_after_trail_disappears() -> void:
	var simulation := _simulation()
	simulation.player.trail_active = true
	simulation.player.trail = PackedInt32Array([
		simulation.board.index_of(16, 1), simulation.board.index_of(16, 2), simulation.board.index_of(16, 3),
	])
	EmberRules.ignite(simulation.pools, 0, 1, MinorActorPools.Cause.CUT, 12)
	EmberRules.update(simulation.pools, 0, simulation.player, 384)
	var expected := Vector2(CoordinateSpace.field_to_screen(Vector2i(16, 2)))
	simulation.pools.retire_ember(0, MinorActorPools.Reason.TRAIL_GONE)
	simulation.player.trail = PackedInt32Array()
	simulation.player.trail_active = false
	var before := simulation.state_checksum()
	var view := QixMinorActorView.new()
	view.sync(simulation)
	eq(view.presentation_state().embers.size(), 1)
	eq(view.presentation_state().embers[0].position, expected)
	eq(view.presentation_state().embers[0].lifecycle, ActorLifecycle.State.DYING)
	eq(simulation.state_checksum(), before)
	view.free()


func test_player_and_boss_lifecycle_and_geometry_do_not_depend_on_body_mode() -> void:
	var simulation := _simulation()
	simulation.player.lifecycle_state = ActorLifecycle.State.WARMUP
	simulation.player.lifecycle_ticks = 30
	simulation.pdir = MoveIntent.Dir.LEFT
	simulation.boss.phase = 2
	simulation.boss.burst_left = 20
	var before := simulation.state_checksum()
	var player := QixPlayerView.new()
	var boss := QixEnemyView.new()
	player.sync(simulation)
	boss.sync(simulation)
	var player_snapshot := player.presentation_state()
	var boss_snapshot := boss.presentation_state()
	player.show_body = false
	boss.show_body = false
	player.sync(simulation)
	boss.sync(simulation)
	eq(player.presentation_state(), player_snapshot)
	eq(boss.presentation_state(), boss_snapshot)
	eq(player_snapshot.lifecycle, ActorLifecycle.State.WARMUP)
	eq(player_snapshot.facing, Vector2.LEFT)
	eq(boss_snapshot.phase, 2)
	ok(boss_snapshot.cornered)
	eq(simulation.state_checksum(), before, "ativar modelos 3D não muda estado nem coordenadas")
	player.free()
	boss.free()


func test_hud_exposes_confirmed_pressure_and_urgent_trail_cut() -> void:
	var simulation := _simulation()
	simulation.director.threat_index = 3
	simulation.boss.phase = 1
	var before := simulation.state_checksum()
	var hud := QixGameHud.new()
	hud.sync(simulation, false, [])
	eq((hud.get_node("Status") as Label).text, "FASE 2 · PRESSÃO 4")
	eq(hud.presentation_state().phase, 1)
	eq(hud.presentation_state().pressure, 3)
	hud.sync(simulation, false, [GameEvent.make(GameEvent.Kind.TRAIL_CUT, {"trail_index": 2})])
	eq((hud.get_node("Status") as Label).text, "TRILHA CORTADA · CONTINUE!")
	eq(simulation.state_checksum(), before)
	for index in 5:
		var segment := hud.get_node("ThreatLevel%d" % index) as ColorRect
		ok(segment.position.y >= 0.0 and segment.position.y + segment.size.y <= QixGameHud.TOP_BAR_HEIGHT)
	hud.free()


func test_beacon_snapshot_and_item_hud_only_report_confirmed_states() -> void:
	var simulation := _simulation()
	var items := ItemProfile.new()
	items.enabled = true
	simulation.rules.items = items
	ok(simulation.beacons.reset(PackedInt32Array([10, 10, 20, 10]), 33, 29))
	simulation.beacons.states[1] = BeaconState.State.CAPTURED
	ok(simulation.effects.activate(ItemProfile.Kind.STASIS, items))
	var before := simulation.state_checksum()
	var view := QixMinorActorView.new()
	var hud := QixGameHud.new()
	view.sync(simulation)
	hud.sync(simulation, false, [])
	var actors: Array = view.presentation_state().beacons
	eq(actors.size(), 2)
	eq(actors[0].captured, false)
	eq(actors[1].captured, true)
	eq(actors[1].position, Vector2(CoordinateSpace.field_to_screen(Vector2i(20, 10))))
	eq(hud.presentation_state().beacons_captured, 1)
	eq((hud.get_node("Status") as Label).text, "ESTASE 3s")
	ok((hud.get_node("Vitals") as Label).text.ends_with("B1/2"))
	eq(simulation.state_checksum(), before)
	view.free()
	hud.free()


func test_boss_telegraph_changes_with_effective_phase_pattern() -> void:
	var simulation := _simulation()
	var profile := BossBehaviorProfile.new()
	profile.pattern = BossBehaviorProfile.Pattern.WANDER
	profile.phase_pattern = PackedInt32Array([-1, -1, BossBehaviorProfile.Pattern.PURSUIT])
	simulation.rules.boss_behavior = profile
	simulation.boss.phase = 2
	var before := simulation.state_checksum()
	var view := QixEnemyView.new()
	view.sync(simulation)
	eq(view.presentation_state().pattern, BossBehaviorProfile.Pattern.PURSUIT)
	eq(simulation.state_checksum(), before)
	view.free()


func _simulation() -> GameSimulation:
	var rules := GameRules.new()
	var threat := ThreatProfile.new()
	threat.enabled = true
	rules.threat = threat
	var definition := RoundDefinition.new()
	definition.field_width = 33
	definition.field_height = 29
	definition.player_spawn = Vector2i(16, 0)
	definition.boss_start = Vector2i(20, 20)
	return GameSimulation.new(rules, definition, 8237)
