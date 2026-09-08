extends TestCase
## Defende o canal não cromático do cursor: o contorno de tinta de `QixPlayerView`.
##
## `cursor_contrast_test.gd` mediu e provou o problema — as três camadas opacas da silhueta são
## emprestadas da paleta do campo, então `CURSOR_OUTER×BOUNDARY` mede 1,00:1 **em qualquer paleta
## que alguém autore**, e o núcleo não passa de 1,12:1. Enquanto o jogador anda protegido pela
## borda, "onde eu estou" não separa do chão por luminância nenhuma.
##
## O contorno resolve por luminância, não por cor: é o `free_color` da rodada, a cor mais escura de
## cada paleta. Este teste é a guarda. Ele falha se alguém trocar a tinta por uma cor clara,
## encolher o contorno até desaparecer, ou autorar uma paleta cujo `free_color` deixe de sustentar
## a leitura. Ver `docs/decisions/ADR-0012-cursor-ink-outline.md`.
##
## Só apresentação. Nada aqui toca `game/simulation`, `game/rules` ou `game/session`, e o último
## teste prova que sincronizar a silhueta não move `state_checksum()` (invariantes 6 e 8).

const PaletteContrast := preload("res://tools/palette_contrast.gd")
const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"

## Piso da WCAG 2.1 SC 1.4.11, o mesmo que `RIM_TARGET_RATIO` do anel da ameaça.
const INK_TARGET_RATIO := 3.0


func test_o_contorno_envolve_a_silhueta_por_uma_margem_desenhavel() -> void:
	ok(
		QixPlayerView.INK_REACH > QixPlayerView.BODY_REACH,
		"o contorno tem de ser maior que a silhueta para existir como contorno",
	)
	ok(
		QixPlayerView.INK_REACH - QixPlayerView.BODY_REACH >= 1.0,
		"espessura abaixo de 1 px não sobrevive à escala de 240×320",
	)
	# A cruz de tinta tem de conter a cruz opaca inteira, senão o contorno abre num dos braços e é
	# exatamente nos braços que o olho procura a direção.
	var body := QixPlayerView.cross_rects(QixPlayerView.BODY_REACH)
	var ink := QixPlayerView.cross_rects(QixPlayerView.INK_REACH)
	eq(ink.size(), body.size(), "as duas cruzes têm de ter a mesma construção")
	for index in body.size():
		ok(
			ink[index].encloses(body[index]),
			"o retângulo %d da tinta não cobre o da silhueta" % index,
		)


func test_a_geometria_da_cruz_e_a_que_a_view_desenha() -> void:
	# Amarra `cross_rects` à silhueta 5×5 historicamente autorada: se alguém reescrever a fórmula,
	# o cursor muda de tamanho e isto falha em vez de o jogador descobrir na tela.
	var body := QixPlayerView.cross_rects(QixPlayerView.BODY_REACH)
	eq(body[0], Rect2(-2.0, -1.0, 5.0, 3.0), "a barra horizontal da silhueta mudou")
	eq(body[1], Rect2(-1.0, -2.0, 3.0, 5.0), "a barra vertical da silhueta mudou")


func test_a_proa_nasce_fora_do_contorno() -> void:
	# Sem isto a proa de #35 começaria dentro da própria tinta e a leitura de direção competiria
	# com a de posição, em vez de a completar.
	ok(
		QixPlayerView.FACING_NEAR > QixPlayerView.INK_REACH,
		"a proa começa dentro do contorno: %.1f contra %.1f" % [
			QixPlayerView.FACING_NEAR, QixPlayerView.INK_REACH,
		],
	)
	eq(
		QixPlayerView.FACING_FAR - QixPlayerView.FACING_NEAR,
		2.0,
		"o comprimento de 2 px da proa é o que #35 mediu; encurtá-lo é outra decisão",
	)


func test_a_tinta_do_contorno_e_o_chao_nao_reclamado_da_rodada() -> void:
	# A tinta não é uma constante estética solta: é o `free_color` autorado, então acompanha
	# qualquer rodada futura sem edição de código. Mesmo contrato do anel da ameaça.
	var view := QixPlayerView.new()
	eq(
		view.presentation_colors()["ink"],
		QixPlayerView.DEFAULT_INK,
		"sem visual autorado o contorno usa a tinta padrão",
	)
	eq(
		QixPlayerView.DEFAULT_INK,
		RoundVisualDefinition.new().free_color,
		"a tinta padrão acompanha o `free_color` padrão",
	)
	var simulation := GameSession.new(_campaign()).simulation
	for entry in _palettes():
		var visual: RoundVisualDefinition = entry["visual"]
		view.sync(simulation, visual)
		eq(
			view.presentation_colors()["ink"],
			visual.free_color,
			"%s: o contorno adota o `free_color` da rodada" % entry["label"],
		)
		ne(
			view.presentation_colors()["ink"],
			view.presentation_colors()["outer"],
			"%s: tinta e camada externa não podem ser a mesma cor" % entry["label"],
		)
	view.free()


func test_o_contorno_separa_o_cursor_da_borda_em_toda_dicromacia() -> void:
	# O par que passa a carregar a leitura, e a razão de a ADR existir: sobre `BOUNDARY` a silhueta
	# mede 1,00–1,12:1 e o contorno mede quase nove vezes isso.
	for entry in _palettes():
		var measurement: Dictionary = PaletteContrast.measure_cursor(entry["visual"])
		var seen := false
		for pair in measurement["pairs"]:
			if String(pair["pair"]) != "CURSOR_INK×BOUNDARY":
				continue
			seen = true
			for vision_label in pair["by_vision"]:
				var ratio: float = pair["by_vision"][vision_label]
				ok(
					ratio >= INK_TARGET_RATIO,
					"%s: CURSOR_INK×BOUNDARY em %s ficou em %.2f:1, abaixo de %.1f:1" % [
						entry["label"], vision_label, ratio, INK_TARGET_RATIO,
					],
				)
		ok(seen, "%s: o par do contorno saiu da medição" % entry["label"])


func test_sincronizar_o_cursor_nao_move_a_simulacao() -> void:
	var session := GameSession.new(_campaign())
	var before := session.simulation.state_checksum()
	var before_tick := session.simulation.tick
	var player := QixPlayerView.new()
	player.sync(session.simulation, session.current_content().visual)
	eq(session.simulation.state_checksum(), before, "desenhar o contorno alterou o checksum")
	eq(session.simulation.tick, before_tick, "desenhar o contorno avançou o tick")
	player.free()


func _palettes() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{"label": "paleta padrão", "visual": RoundVisualDefinition.new()},
	]
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	if campaign == null:
		fail("campanha ausente em " + CAMPAIGN_PATH)
		return entries
	for content in campaign.rounds:
		if content == null or content.visual == null:
			continue
		entries.append({"label": String(content.round_id), "visual": content.visual})
	return entries


func _campaign() -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"cursor_ink_outline_test"
	campaign.intro_ticks = 0
	campaign.clear_ticks = 0
	campaign.rounds = [_round()]
	return campaign


func _round() -> RoundContent:
	var rules := GameRules.new()
	rules.target_permille = 800
	var definition := RoundDefinition.new()
	definition.field_width = 13
	definition.field_height = 9
	definition.player_spawn = Vector2i(6, 0)
	definition.boss_start = Vector2i(10, 4)
	var visual := RoundVisualDefinition.new()
	visual.background = ImageTexture.create_from_image(Image.create(13, 9, false, Image.FORMAT_RGBA8))
	var content := RoundContent.new()
	content.round_id = &"cursor_ink_probe"
	content.rules = rules
	content.round_definition = definition
	content.seed_value = 11
	content.visual = visual
	return content
