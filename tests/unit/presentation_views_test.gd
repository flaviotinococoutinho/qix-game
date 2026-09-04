extends TestCase


func test_hud_reads_session_round_identity_and_target_progress() -> void:
	var session := GameSession.new(_campaign(12, 24))
	session.simulation.permille = 400
	session.simulation.score = 12340
	session.simulation.lives = 2
	session.simulation.shield_ticks = 300
	var before := session.simulation.state_checksum()
	var hud := QixGameHud.new()
	hud._ready()
	hud.sync(session, false, [])
	eq((hud.get_node("Round") as Label).text, "R 1/2")
	eq((hud.get_node("Score") as Label).text, "S 012340")
	eq((hud.get_node("Percent") as Label).text, "40.0/80")
	eq((hud.get_node("RoundTitle") as Label).text, "ABYSSAL RELAY")
	eq((hud.get_node("Vitals") as Label).text, "L×2  E05")
	eq(int((hud.get_node("ObjectiveFill") as ColorRect).size.x), 25)
	eq(session.simulation.state_checksum(), before, "a apresentação não altera a simulação")
	hud.free()


func test_transition_overlay_exposes_real_intro_and_clear_progress() -> void:
	var session := GameSession.new(_campaign(10, 20))
	var view := QixRoundTransitionView.new()
	view._ready()
	view.sync(session, false, [])
	ok(view.visible)
	eq((view.get_node("Panel/Phase") as Label).text, "SETOR 01 / 02")
	eq((view.get_node("Panel/Title") as Label).text, "ABYSSAL RELAY")
	eq(int((view.get_node("Panel/ProgressFill") as ColorRect).size.x), 0)

	session.transition_ticks_left = 5
	view.sync(session, false, [])
	eq(int((view.get_node("Panel/ProgressFill") as ColorRect).size.x), 80)

	session.simulation.permille = 400
	session.phase = GameSession.Phase.ROUND_CLEAR
	session.transition_ticks_total = 20
	session.transition_ticks_left = 5
	view.sync(session, false, [])
	eq((view.get_node("Panel/Title") as Label).text, "SETOR ESTABILIZADO")
	eq((view.get_node("Panel/Result") as Label).text, "40.0% REVELADO")
	eq(int((view.get_node("Panel/ProgressFill") as ColorRect).size.x), 120)
	view.free()


func test_transition_overlay_covers_pause_game_over_and_campaign_complete() -> void:
	var session := GameSession.new(_campaign(0, 0))
	var view := QixRoundTransitionView.new()
	view._ready()
	view.sync(session)
	ok(not view.visible, "PLAYING não deve bloquear o campo")
	view.sync(session, true)
	ok(view.visible)
	eq((view.get_node("Panel/Title") as Label).text, "PAUSA")

	session.phase = GameSession.Phase.GAME_OVER
	view.sync(session)
	eq((view.get_node("Panel/Title") as Label).text, "FIM DE JOGO")
	eq((view.get_node("Panel/Prompt") as Label).text, "ENTER  ·  REINICIAR CAMPANHA")

	session.phase = GameSession.Phase.CAMPAIGN_COMPLETE
	view.sync(session)
	eq((view.get_node("Panel/Title") as Label).text, "CAMPANHA CONCLUÍDA")
	eq(int((view.get_node("Panel/ProgressFill") as ColorRect).size.x), 160)
	view.free()


func test_capture_vfx_reacts_to_events_then_expires_without_touching_gameplay() -> void:
	var session := GameSession.new(_campaign(0, 0))
	var vfx := QixCaptureVfx.new()
	var before := session.simulation.state_checksum()
	var captured: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.CAPTURED, {
		"filled_delta": 173,
		"permille": 420,
	})]
	vfx.sync(session, captured)
	eq(vfx.last_filled_delta, 173)
	eq(vfx.capture_ticks_left, QixCaptureVfx.CAPTURE_DURATION_TICKS)
	ok(vfx.visible)
	for _tick in QixCaptureVfx.CAPTURE_DURATION_TICKS:
		vfx.sync(session, [])
	eq(vfx.capture_ticks_left, 0)
	ok(not vfx.visible)
	eq(session.simulation.state_checksum(), before, "VFX deve ser estritamente observacional")
	vfx.free()


func test_capture_vfx_uses_the_authorable_round_geometry() -> void:
	var session := GameSession.new(_campaign(0, 0))
	var vfx := QixCaptureVfx.new()
	vfx.sync(session, [])
	var field: Rect2 = vfx.field_rect()
	eq(field.position, Vector2(CoordinateSpace.FIELD_ORIGIN))
	eq(field.size, Vector2(13.0, 9.0))
	vfx.free()


func test_capture_vfx_has_distinct_round_clear_and_hit_channels() -> void:
	var session := GameSession.new(_campaign(0, 0))
	var vfx := QixCaptureVfx.new()
	var events: Array[GameEvent] = [
		GameEvent.make(GameEvent.Kind.ROUND_CLEAR_STARTED),
		GameEvent.make(GameEvent.Kind.PLAYER_DIED),
	]
	vfx.sync(session, events)
	eq(vfx.clear_ticks_left, QixCaptureVfx.CLEAR_DURATION_TICKS)
	eq(vfx.hit_ticks_left, QixCaptureVfx.HIT_DURATION_TICKS)
	ok(vfx.visible)
	eq(vfx.presentation_state()["last_filled_delta"], 0)
	vfx.free()


func test_player_and_enemy_use_visual_palette_without_mutating_simulation() -> void:
	var session := GameSession.new(_campaign(0, 0))
	var simulation := session.simulation
	var visual := session.current_content().visual
	var before := simulation.state_checksum()
	var player := QixPlayerView.new()
	var enemy := QixEnemyView.new()
	player.sync(simulation, visual)
	enemy.sync(simulation, visual)
	eq(player.position, Vector2(CoordinateSpace.field_to_screen(Vector2i(simulation.px, simulation.py))))
	eq(enemy.position, Vector2(CoordinateSpace.field_to_screen(simulation.boss_cell())))
	eq(player.presentation_colors()["core"], visual.trail_hot_color)
	eq(enemy.presentation_colors()["body"], visual.threat_color)
	eq(simulation.state_checksum(), before)
	player.free()
	enemy.free()


func _campaign(intro_ticks: int, clear_ticks: int) -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"presentation_test"
	campaign.intro_ticks = intro_ticks
	campaign.clear_ticks = clear_ticks
	campaign.rounds = [_round(&"abyss", "ABYSSAL RELAY", 11), _round(&"aurora", "AURORA FOUNDRY", 23)]
	return campaign


func _round(round_id: StringName, title: String, seed_value: int) -> RoundContent:
	var rules := GameRules.new()
	rules.target_permille = 800
	var definition := RoundDefinition.new()
	definition.field_width = 13
	definition.field_height = 9
	definition.player_spawn = Vector2i(6, 0)
	definition.boss_start = Vector2i(10, 4)
	var visual := RoundVisualDefinition.new()
	visual.display_name = title
	visual.subtitle = "RESTORE A CARTOGRAFIA PERDIDA"
	visual.background = ImageTexture.create_from_image(Image.create(13, 9, false, Image.FORMAT_RGBA8))
	visual.boundary_color = Color("62f7d1")
	visual.trail_hot_color = Color("fff1b8")
	visual.threat_color = Color("ff3f72")
	var content := RoundContent.new()
	content.round_id = round_id
	content.rules = rules
	content.round_definition = definition
	content.seed_value = seed_value
	content.visual = visual
	return content
