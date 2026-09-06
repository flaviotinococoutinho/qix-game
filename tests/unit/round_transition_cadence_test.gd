extends TestCase
## Defende o ritmo da passagem entre rodadas.
##
## A passagem carrega score, vidas e o próximo setor desde #15, mas entregava tudo no mesmo
## frame: era texto, não animação. O que se mede aqui é a ordem de entrada das linhas e a
## batida sobre a linha de continuidade — e, sobretudo, que nada disso toca o domínio.


func test_the_panel_opens_in_reading_order_instead_of_all_at_once() -> void:
	var view := _view()
	# Antes do primeiro limiar só o cabeçalho está em cena: quem olha o painel lê o nome do
	# setor antes de qualquer número disputar a atenção.
	view._apply_cadence(0.0, QixRoundTransitionView.DEFAULT_ACCENT)
	eq(view._subtitle_label.visible, false, "subtítulo entra cedo demais")
	eq(view._result_label.visible, false, "resultado entra cedo demais")
	eq(view._continuity_label.visible, false, "continuidade entra cedo demais")
	eq(view._prompt_label.visible, false, "prompt entra cedo demais")

	var order := [
		[QixRoundTransitionView.REVEAL_SUBTITLE, "_subtitle_label"],
		[QixRoundTransitionView.REVEAL_RESULT, "_result_label"],
		[QixRoundTransitionView.REVEAL_CONTINUITY, "_continuity_label"],
		[QixRoundTransitionView.REVEAL_PROMPT, "_prompt_label"],
	]
	for index in range(1, order.size()):
		ok(
			(order[index][0] as float) > (order[index - 1][0] as float),
			"%s não entra depois de %s" % [order[index][1], order[index - 1][1]])
	for step: Array in order:
		var threshold: float = step[0]
		view._apply_cadence(threshold, QixRoundTransitionView.DEFAULT_ACCENT)
		eq(view.get(step[1] as String).visible, true, "%s não entrou no próprio limiar" % step[1])
	view.free()


func test_the_continuity_line_lands_on_a_beat_that_decays_instead_of_blinking() -> void:
	var view := _view()
	var accent := QixRoundTransitionView.DEFAULT_ACCENT
	eq(view._beat(QixRoundTransitionView.REVEAL_CONTINUITY - 0.01), 0.0,
		"há batida antes de a continuidade entrar")
	eq(view._beat(QixRoundTransitionView.REVEAL_CONTINUITY), 1.0,
		"a batida não está cheia no frame da entrada")
	var span: float = QixRoundTransitionView.ACCENT_SPAN
	var mid := view._beat(QixRoundTransitionView.REVEAL_CONTINUITY + span * 0.5)
	ok(mid > 0.0 and mid < 1.0, "a batida não decai: mede %.3f a meio do vão" % mid)
	eq(view._beat(QixRoundTransitionView.REVEAL_CONTINUITY + span), 0.0,
		"a batida não fecha ao fim do vão")

	# Um vão curto demais é um piscar de um frame: a 60/s, o intro de 60 ticks tem de dar à
	# batida ao menos meia dúzia deles para ela ser lida como ênfase e não como ruído.
	ok(span * 60.0 >= 6.0, "a batida dura %.1f ticks no intro de 60" % (span * 60.0))

	view._apply_cadence(QixRoundTransitionView.REVEAL_CONTINUITY, accent)
	var lit: Color = view._continuity_label.get_theme_color("font_color")
	var edge_lit: float = view._edge.size.x
	view._apply_cadence(QixRoundTransitionView.REVEAL_CONTINUITY + span, accent)
	var settled: Color = view._continuity_label.get_theme_color("font_color")
	ok(lit.get_luminance() > settled.get_luminance(),
		"a linha de continuidade não clareia na batida (%.3f vs %.3f)" % [
			lit.get_luminance(), settled.get_luminance()])
	ok(edge_lit > view._edge.size.x,
		"a aresta do painel não engrossa na batida (%.1f vs %.1f)" % [
			edge_lit, view._edge.size.x])
	# O canal não cromático tem de voltar exatamente ao valor de repouso: uma aresta que
	# engrossa e não volta vira estado, não acento.
	eq(view._edge.size.x, QixRoundTransitionView.EDGE_WIDTH, "a aresta não volta ao repouso")
	eq(settled, accent, "a continuidade não assenta na cor do setor")
	view.free()


func test_a_transition_without_a_clock_opens_the_panel_whole() -> void:
	# Pausa, fim de jogo e campanha concluída chegam com `transition_ticks_total` = 0 e, por
	# isso, com progresso 1.0. São estados terminais ou congelados: montar o painel por partes
	# atrasaria uma leitura que já é definitiva.
	var view := _view()
	view._apply_cadence(1.0, QixRoundTransitionView.DEFAULT_THREAT)
	for field: String in ["_subtitle_label", "_result_label", "_continuity_label", "_prompt_label"]:
		eq((view.get(field) as Label).visible, true, "%s não está em cena sem relógio" % field)
	eq(view._beat(1.0), 0.0, "um painel sem relógio ainda bate")
	eq(view._edge.size.x, QixRoundTransitionView.EDGE_WIDTH, "aresta engrossada sem batida")
	view.free()


func test_the_cadence_closes_before_the_shortest_transition_ends() -> void:
	# `intro_ticks` = 60 é a passagem mais curta da campanha de produção. Se o último limiar
	# caísse perto de 1.0, o prompt "ENTER · INICIAR AGORA" apareceria depois de já não haver
	# tempo para o usar — a cadência teria comido a própria afordância.
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	ok(campaign != null, "campanha de produção não carregou")
	if campaign == null:
		return
	var shortest := mini(campaign.intro_ticks, campaign.clear_ticks)
	var last: float = QixRoundTransitionView.REVEAL_PROMPT
	var ticks_left := float(shortest) * (1.0 - last)
	ok(ticks_left >= 20.0,
		"o prompt entra a %.1f ticks do fim numa passagem de %d" % [ticks_left, shortest])


func test_the_cadence_reads_the_session_and_never_writes_to_it() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	var session := GameSession.new(campaign)
	eq(session.phase, GameSession.Phase.ROUND_INTRO, "a campanha não abre em intro")
	var view := _view()
	var checksum := session.simulation.state_checksum()
	var replay := session.replay.to_bytes()
	var ticks_left := session.transition_ticks_left
	# Percorre a intro inteira sincronizando a cada tick, como o bootstrap faz.
	var seen_hidden := false
	var seen_beat := false
	while session.phase == GameSession.Phase.ROUND_INTRO:
		view.sync(session, false, [])
		if not view._prompt_label.visible:
			seen_hidden = true
		# A fração vem da view, não da sessão: `#25` tirou `transition_progress()` do domínio
		# porque devolvia `float` (invariante 1). Quem apresenta é dono da divisão.
		if view._beat(view._transition_progress(session)) > 0.0:
			seen_beat = true
		session.step(MoveIntent.none())
	ok(seen_hidden, "o prompt esteve em cena a intro inteira: não há cadência")
	ok(seen_beat, "a batida nunca aconteceu ao longo da intro")
	eq(session.simulation.state_checksum(), checksum, "a apresentação mexeu no domínio")
	eq(session.replay.to_bytes(), replay, "a apresentação escreveu no replay")
	ok(ticks_left > 0, "a intro de produção não tem relógio")
	view.free()


func _view() -> QixRoundTransitionView:
	var view := QixRoundTransitionView.new()
	# Entrar na árvore resolve o tema, como em `game_hud_layout_test`; o runner corre antes de
	# a árvore processar, então `_ready` é chamado à mão e a guarda `_built` mantém idempotente.
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view._ready()
	return view
