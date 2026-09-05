extends TestCase
## Defende o canal não cromático da ameaça: o anel de tinta de `QixEnemyView`.
##
## `docs/ART_DIRECTION.md` já registra a dívida — `BOUNDARY`×`THREAT` a 1,27:1 e `TRAIL`×`THREAT`
## a 1,82:1 na pior dicromacia. Enquanto o corpo do chefe for a única marca, "onde está a ameaça"
## depende de matiz, e um jogador com deuteranopia lê o losango sobre a borda por forma apenas.
## O anel resolve isso por luminância, não por cor: ele é o `free_color` da rodada, o mais escuro
## da paleta, e por isso separa da borda e da trilha por larga margem em qualquer visão.
##
## Este teste é a guarda que o item de backlog pedia. Ele falha se alguém trocar a tinta por uma
## cor clara, encolher o anel até desaparecer, ou autorar uma paleta cujo `free_color` deixe de
## sustentar a leitura. Ver `docs/decisions/ADR-0011-threat-ink-outline.md`.

const PaletteContrast := preload("res://tools/palette_contrast.gd")

## Mesmo piso de `PaletteContrast.TARGET_RATIO` (WCAG 2.1 SC 1.4.11). Aqui ele é meta cumprida,
## não dívida: o anel existe justamente para ficar acima dele.
const RIM_TARGET_RATIO := 3.0

const VISUAL_PATHS := [
	"res://content/visuals/round_01_abyssal_relay.tres",
	"res://content/visuals/round_02_aurora_foundry.tres",
	"res://content/visuals/round_03_verdant_singularity.tres",
]


func test_anel_de_tinta_envolve_o_corpo_por_uma_margem_desenhavel() -> void:
	ok(
		QixEnemyView.RIM_RADIUS > QixEnemyView.BODY_RADIUS,
		"o anel precisa ser maior que o corpo, senão não há contorno",
	)
	eq(
		QixEnemyView.RIM_RADIUS - QixEnemyView.BODY_RADIUS,
		1.0,
		"a espessura é 1 px: a menor marca que o campo 240×320 sustenta",
	)
	var view := QixEnemyView.new()
	var geometry := view.silhouette_geometry()
	var body: PackedVector2Array = geometry["body"]
	var rim: PackedVector2Array = geometry["rim"]
	eq(body.size(), 4, "o corpo é um losango de quatro vértices")
	eq(rim.size(), 4, "o anel é um losango de quatro vértices")
	for index in body.size():
		var body_vertex := body[index]
		var rim_vertex := rim[index]
		ok(
			rim_vertex.length() > body_vertex.length(),
			"vértice %d do anel fica fora do corpo" % index,
		)
		ok(
			body_vertex.normalized().dot(rim_vertex.normalized()) > 0.999,
			"vértice %d do anel aponta na mesma direção do corpo" % index,
		)
	view.free()


func test_a_tinta_do_anel_e_o_chao_nao_reclamado_da_rodada() -> void:
	# A tinta não é uma constante estética solta: ela é o `free_color` autorado. Se a paleta muda,
	# o anel muda com ela — e o teste de contraste abaixo continua valendo sem edição.
	var view := QixEnemyView.new()
	eq(
		view.presentation_colors()["ink"],
		QixEnemyView.DEFAULT_INK,
		"sem visual autorado o anel usa a tinta padrão",
	)
	eq(
		QixEnemyView.DEFAULT_INK,
		RoundVisualDefinition.new().free_color,
		"a tinta padrão acompanha o `free_color` padrão",
	)
	for path in VISUAL_PATHS:
		var visual: RoundVisualDefinition = load(path)
		var simulation := _session().simulation
		view.sync(simulation, visual)
		eq(
			view.presentation_colors()["ink"],
			visual.free_color,
			"%s: o anel adota o `free_color` da rodada" % path.get_file(),
		)
		ne(
			view.presentation_colors()["ink"],
			view.presentation_colors()["body"],
			"%s: tinta e corpo não podem ser a mesma cor" % path.get_file(),
		)
	view.free()


func test_o_anel_separa_a_ameaca_de_cada_chao_em_todas_as_visoes() -> void:
	# O par que falha hoje é `THREAT` contra `BOUNDARY` e contra `TRAIL`. É contra esses dois chãos
	# que o anel precisa provar valor — e em todas as quatro visões, não só na tricromática.
	var visuals: Array[RoundVisualDefinition] = [RoundVisualDefinition.new()]
	for path in VISUAL_PATHS:
		visuals.append(load(path))
	for visual in visuals:
		var swatches := PaletteContrast.rendered_swatches(visual)
		var ink := visual.free_color
		for floor_state in ["BOUNDARY", "TRAIL"]:
			for vision in PaletteContrast.VISION_ORDER:
				var ratio := INF
				for floor_color in swatches[floor_state]:
					ratio = minf(ratio, PaletteContrast.contrast_ratio(
						PaletteContrast.simulate(ink, vision),
						PaletteContrast.simulate(floor_color, vision),
					))
				ok(
					ratio >= RIM_TARGET_RATIO,
					"%s: anel × %s em %s = %.2f (piso %.1f)" % [
						visual.display_name,
						floor_state,
						PaletteContrast.VISION_LABELS[vision],
						ratio,
						RIM_TARGET_RATIO,
					],
				)


func test_o_anel_tambem_se_separa_do_proprio_corpo() -> void:
	# Um anel que se confunde com o corpo é um corpo maior, não um contorno. Este é o par que
	# garante que a silhueta tenha borda **e** interior legíveis.
	var visuals: Array[RoundVisualDefinition] = [RoundVisualDefinition.new()]
	for path in VISUAL_PATHS:
		visuals.append(load(path))
	for visual in visuals:
		for vision in PaletteContrast.VISION_ORDER:
			var ratio := PaletteContrast.contrast_ratio(
				PaletteContrast.simulate(visual.free_color, vision),
				PaletteContrast.simulate(visual.threat_color, vision),
			)
			ok(
				ratio >= RIM_TARGET_RATIO,
				"%s: anel × corpo em %s = %.2f (piso %.1f)" % [
					visual.display_name,
					PaletteContrast.VISION_LABELS[vision],
					ratio,
					RIM_TARGET_RATIO,
				],
			)


func test_o_anel_nao_toca_o_dominio() -> void:
	# Invariante 6 e 8: desenhar o contorno lê o snapshot e não muda nada — nem estado, nem
	# checksum. Se esta asserção cair, a estética vazou para a simulação.
	var session := _session()
	var simulation := session.simulation
	var before := simulation.state_checksum()
	var tick_before := simulation.tick
	var view := QixEnemyView.new()
	view.sync(simulation, load(VISUAL_PATHS[0]))
	view.silhouette_geometry()
	view.presentation_colors()
	eq(simulation.state_checksum(), before, "sincronizar a silhueta não altera o checksum")
	eq(simulation.tick, tick_before, "sincronizar a silhueta não avança o tick")
	view.free()


func _session() -> GameSession:
	var rules := GameRules.new()
	var definition := RoundDefinition.new()
	definition.field_width = 13
	definition.field_height = 9
	definition.player_spawn = Vector2i(6, 0)
	definition.boss_start = Vector2i(10, 4)
	var visual := RoundVisualDefinition.new()
	visual.display_name = "SILHUETA"
	visual.background = ImageTexture.create_from_image(Image.create(13, 9, false, Image.FORMAT_RGBA8))
	var content := RoundContent.new()
	content.round_id = &"silhouette"
	content.rules = rules
	content.round_definition = definition
	content.seed_value = 20260905
	content.visual = visual
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"silhouette_test"
	campaign.rounds = [content]
	return GameSession.new(campaign)
