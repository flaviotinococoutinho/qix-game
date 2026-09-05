extends TestCase
## Defende a medição de contraste e a paleta autorada.
##
## O módulo é matemática pura de apresentação: valida-se contra referências conhecidas (preto ×
## branco = 21:1) e contra as modulações reais de `board_reveal.gdshader`. A paleta autorada é
## defendida por catraca — `PaletteContrast.PAIR_FLOOR` — e pela lista de dívida conhecida, para
## que uma melhoria também obrigue a atualizar o texto de `docs/ART_DIRECTION.md`.

const PaletteContrast := preload("res://tools/palette_contrast.gd")
const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"
const EPSILON := 0.005


func test_luminancia_e_contraste_batem_com_referencias_wcag() -> void:
	ok(_close(PaletteContrast.relative_luminance(Color.BLACK), 0.0), "preto tem luminância 0")
	ok(_close(PaletteContrast.relative_luminance(Color.WHITE), 1.0), "branco tem luminância 1")
	# #808080 é o cinza de referência da WCAG: 0.2159 de luminância relativa.
	ok(
		_close(PaletteContrast.relative_luminance(Color("808080")), 0.2159),
		"cinza médio ≈ 0.2159",
	)
	ok(
		_close(PaletteContrast.contrast_ratio(Color.BLACK, Color.WHITE), 21.0, 0.02),
		"preto × branco = 21:1",
	)
	ok(
		_close(PaletteContrast.contrast_ratio(Color.WHITE, Color.WHITE), 1.0),
		"cor contra si mesma = 1:1",
	)


func test_simulacao_tricromata_devolve_a_cor_original() -> void:
	for sample in [Color("46f5c5"), Color("ffd166"), Color("071923"), Color("ff426d")]:
		var simulated: Color = PaletteContrast.simulate(sample, PaletteContrast.Vision.TRICHROMAT)
		ok(_close(simulated.r, sample.r), "R preservado em %s" % sample.to_html(false))
		ok(_close(simulated.g, sample.g), "G preservado em %s" % sample.to_html(false))
		ok(_close(simulated.b, sample.b), "B preservado em %s" % sample.to_html(false))


func test_cada_dicromacia_colapsa_o_eixo_que_lhe_cabe() -> void:
	# Propriedade que separa uma matriz correta de três números plausíveis: protanopia e
	# deuteranopia precisam encolher vermelho × verde, e tritanopia precisa **preservar** esse
	# eixo — ela perde azul × amarelo. Uma matriz trocada quebra este teste, não a tabela.
	var red := Color.RED
	var green := Color.GREEN
	var base := _distance(red, green)
	for vision in [PaletteContrast.Vision.PROTANOPIA, PaletteContrast.Vision.DEUTERANOPIA]:
		var collapsed := _distance(
			PaletteContrast.simulate(red, vision),
			PaletteContrast.simulate(green, vision),
		)
		# Medido: protanopia retém 0.55 e deuteranopia 0.33 da distância original; tritanopia 1.14.
		ok(
			collapsed < base * 0.6,
			"visão %d devia colapsar vermelho × verde (%.3f de %.3f)" % [vision, collapsed, base],
		)
	var tritan := _distance(
		PaletteContrast.simulate(red, PaletteContrast.Vision.TRITANOPIA),
		PaletteContrast.simulate(green, PaletteContrast.Vision.TRITANOPIA),
	)
	ok(tritan > base * 0.9, "tritanopia preserva vermelho × verde (%.3f de %.3f)" % [tritan, base])


func test_swatches_seguem_as_modulacoes_do_shader() -> void:
	var visual := RoundVisualDefinition.new()
	var swatches: Dictionary = PaletteContrast.rendered_swatches(visual)
	eq(swatches["FREE"].size(), 2, "FREE tem os dois extremos da scanline")
	eq(swatches["BOUNDARY"].size(), 2, "BOUNDARY tem os dois extremos do glint")
	eq(swatches["TRAIL"].size(), 2, "TRAIL tem os dois extremos do pulso")
	eq(swatches["THREAT"].size(), 1, "THREAT é desenhado sem modulação pelo EnemyView")
	ok(
		_close(swatches["FREE"][0].g, visual.free_color.g * 0.92),
		"extremo escuro de FREE usa o fator 0.92 do shader",
	)
	ok(
		_close(swatches["BOUNDARY"][0].g, visual.boundary_color.g * 0.86),
		"extremo escuro de BOUNDARY usa o fator 0.86 do shader",
	)
	eq(swatches["TRAIL"][1], visual.trail_hot_color, "extremo quente de TRAIL é trail_hot_color")


func test_paleta_padrao_e_rodadas_autoradas_nao_regridem() -> void:
	for entry in _palettes():
		var measurement: Dictionary = PaletteContrast.measure(entry["visual"])
		var regressions: PackedStringArray = PaletteContrast.regressions(measurement)
		eq(
			String("\n      ".join(regressions)),
			"",
			"%s piorou em relação ao piso registrado" % entry["label"],
		)


func test_a_divida_registrada_descreve_a_paleta_atual() -> void:
	# Este teste falha nos dois sentidos de propósito: se um par piorar e entrar na dívida, e se um
	# par melhorar e sair dela. Nos dois casos alguém precisa reescrever ART_DIRECTION e o piso.
	var expected := PackedStringArray(PaletteContrast.KNOWN_DEBT)
	expected.sort()
	for entry in _palettes():
		var measurement: Dictionary = PaletteContrast.measure(entry["visual"])
		var below: PackedStringArray = measurement["below_target"]
		below.sort()
		eq(
			String(", ".join(below)),
			String(", ".join(expected)),
			"%s: pares abaixo de %.1f:1 divergem da dívida documentada" % [
				entry["label"],
				PaletteContrast.TARGET_RATIO,
			],
		)


func test_free_e_boundary_sobrevivem_a_qualquer_dicromacia() -> void:
	# A leitura "onde está a borda segura" é a única que o jogador não pode perder em nenhum
	# momento; ela precisa passar da meta em todos os modelos de visão, não só no pior caso médio.
	for entry in _palettes():
		var measurement: Dictionary = PaletteContrast.measure(entry["visual"])
		for pair in measurement["pairs"]:
			if pair["pair"] != "FREE×BOUNDARY":
				continue
			for vision_label in pair["by_vision"]:
				var ratio: float = pair["by_vision"][vision_label]
				ok(
					ratio >= PaletteContrast.TARGET_RATIO,
					"%s: FREE×BOUNDARY em %s ficou em %.2f:1" % [
						entry["label"],
						vision_label,
						ratio,
					],
				)


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


func _distance(first: Color, second: Color) -> float:
	var dr := first.r - second.r
	var dg := first.g - second.g
	var db := first.b - second.b
	return sqrt(dr * dr + dg * dg + db * db)


func _close(actual: float, expected: float, epsilon: float = EPSILON) -> bool:
	return absf(actual - expected) <= epsilon
