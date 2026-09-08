extends TestCase
## Grade dos comandos medida com a fonte do runtime; comandos nunca cobrem uma partida ativa.


func test_command_rows_fit_and_keep_clear_space_below_the_title() -> void:
	var view := QixRoundTransitionView.new()
	Engine.get_main_loop().root.add_child(view)
	view._ready()
	var controls := view.get_node("Controls") as ColorRect
	var legend := view.get_node("Controls/Legend") as Label
	# O runner está em SceneTree._initialize(): o Label pode conservar size.y=23 da
	# fonte padrão até o primeiro frame. Medimos aqui a tipografia real e a grade;
	# os retângulos já assentados pertencem à sonda com renderer/frame_post_draw.
	var legend_font := legend.get_theme_font("font")
	var legend_height := legend_font.get_height(legend.get_theme_font_size("font_size"))
	ok(legend_height > 0.0, "a medição exige uma fonte resolvida")
	var previous_bottom := legend.position.y + legend_height
	for index in QixRoundTransitionView.CONTROL_LINES.size():
		var row := controls.get_node("Command%d" % index) as Label
		ok(row.position.y >= previous_bottom + 1.0, "rótulos não podem encostar")
		var font_size := row.get_theme_font_size("font_size")
		var font := row.get_theme_font("font")
		ok(font.get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= row.size.x,
			"linha de comando cabe inteira em 240 px: " + row.text)
		ok(font.get_height(font_size) <= QixRoundTransitionView.CONTROL_ROW_HEIGHT)
		previous_bottom = row.position.y + QixRoundTransitionView.CONTROL_ROW_HEIGHT
	ok(previous_bottom <= controls.size.y - 2.0)
	ok(QixRoundTransitionView.PANEL_RECT.end.y + 8.0 <= controls.position.y)
	ok(controls.position.y + controls.size.y <= QixGameHud.BOTTOM_BAR_Y - 2.0)
	ok((controls.get_node("Command3") as Label).text.contains("F2"))
	ok((controls.get_node("Command3") as Label).text.contains("M  SOM"))
	ok((controls.get_node("Command4") as Label).text.contains("F4"))
	view.free()


func test_commands_appear_only_in_intro_or_pause() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	var session := GameSession.new(campaign)
	var view := QixRoundTransitionView.new()
	view._ready()
	var controls := view.get_node("Controls") as ColorRect
	session.phase = GameSession.Phase.ROUND_INTRO
	view.sync(session)
	ok(controls.visible)
	session.phase = GameSession.Phase.PLAYING
	view.sync(session)
	ok(not controls.visible)
	ok(not view.visible, "gameplay mantém o campo descoberto")
	view.sync(session, true)
	ok(controls.visible)
	for phase in [GameSession.Phase.ROUND_CLEAR, GameSession.Phase.GAME_OVER, GameSession.Phase.CAMPAIGN_COMPLETE]:
		session.phase = phase
		view.sync(session)
		ok(not controls.visible)
	view.free()


func test_pressure_bar_differentiates_every_director_level() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	var session := GameSession.new(campaign)
	var hud := QixGameHud.new()
	hud._ready()
	for level in ThreatProfile.LADDER_SIZE:
		session.simulation.director.threat_index = level
		hud.sync(session, false, [])
		var lit := 0
		for index in ThreatProfile.LADDER_SIZE:
			var segment := hud.get_node("ThreatLevel%d" % index) as ColorRect
			if segment.color != QixGameHud.TRACK_COLOR:
				lit += 1
			ok(segment.position.x >= QixGameHud.SCORE_X)
			ok(segment.position.x + segment.size.x <= QixGameHud.SCORE_X + QixGameHud.SCORE_WIDTH)
		eq(lit, level + 1, "a pressão só satura no último degrau")
	hud.free()
