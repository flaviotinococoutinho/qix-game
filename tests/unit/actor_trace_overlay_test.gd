extends TestCase


func test_hidden_overlay_does_not_allocate_ui_or_touch_domain() -> void:
	var session := _session()
	var overlay := QixActorTraceOverlay.new()
	var before := session.simulation.state_checksum()
	ok(not overlay.visible)
	for _tick in 10:
		overlay.sync(session)
	eq(overlay.get_child_count(), 0, "nenhum painel ou snapshot visual enquanto F3 está fechado")
	eq(session.simulation.state_checksum(), before)
	overlay.free()


func test_full_roster_snapshot_is_bounded_and_detached() -> void:
	var session := _session()
	var simulation := session.simulation
	var pools := simulation.pools
	for slot in MinorActorPools.MAX_WALKERS:
		WalkerRules.spawn(pools, slot, Vector2i(slot + 2, 0), 1, 1, 24, MinorActorPools.Cause.LADDER)
	for slot in MinorActorPools.MAX_DARTS:
		pools.begin_dart(slot, 24)
		pools.set_dart(slot, MinorActorPools.D.CAUSE, MinorActorPools.Cause.EXPOSURE)
		pools.set_dart(slot, MinorActorPools.D.REASON, MinorActorPools.Reason.ARMED)
	for slot in MinorActorPools.MAX_EMBERS:
		EmberRules.ignite(pools, slot, 0, MinorActorPools.Cause.CUT)
	pools.retire_dart(0, MinorActorPools.Reason.ABSORBED)
	simulation.effects.remaining[ItemProfile.Kind.STASIS] = 123
	var before := simulation.state_checksum()
	var data := QixActorTraceOverlay.snapshot(simulation)
	eq(data.actors.size(), QixActorTraceOverlay.MAX_ACTORS)
	var lines := QixActorTraceOverlay.snapshot_lines(simulation)
	ok(lines.size() <= QixActorTraceOverlay.MAX_LINES)
	ok("\n".join(lines).contains("C:EXPO R:ARMA"))
	ok("\n".join(lines).contains("SAINDO"), "dissipações retêm rastreabilidade")
	data.effects[ItemProfile.Kind.STASIS] = 999
	data.actors[0].lifecycle = ActorLifecycle.State.DESPAWNED
	eq(simulation.effects.remaining[ItemProfile.Kind.STASIS], 123)
	eq(simulation.state_checksum(), before)


func test_visible_overlay_reports_readonly_state_within_viewport() -> void:
	var session := _session()
	var overlay := QixActorTraceOverlay.new()
	Engine.get_main_loop().root.add_child(overlay)
	overlay.visible = true
	var input := GameInputAdapter.new()
	var before := session.simulation.state_checksum()
	overlay.sync(session, input)
	var label := overlay.get_node("Panel/Snapshot") as Label
	ok(label.text.contains("ENTRADA LIGADA"))
	ok(label.text.contains("NÚCLEO F1"))
	var rect := QixActorTraceOverlay.PANEL_RECT
	ok(rect.position.x >= 0 and rect.position.y >= 0)
	ok(rect.end.x <= CoordinateSpace.VIEWPORT.x and rect.end.y <= CoordinateSpace.VIEWPORT.y)
	var line_height := label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))
	ok(line_height * QixActorTraceOverlay.MAX_LINES <= label.size.y, "elenco cheio cabe na altura")
	eq(session.simulation.state_checksum(), before)
	overlay.visible = false
	var frozen_text := label.text
	session.simulation.tick += 1
	overlay.sync(session, input)
	eq(label.text, frozen_text, "oculto não refaz texto")
	overlay.free()


func _session() -> GameSession:
	return GameSession.new(load("res://content/campaigns/main_campaign.tres") as CampaignDefinition)
