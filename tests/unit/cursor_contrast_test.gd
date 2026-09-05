extends TestCase
## Defende a medição de contraste do **cursor contra o chão** — "onde eu estou", a leitura que o
## jogador faz sessenta vezes por segundo.
##
## Por que existe separado de `palette_contrast_test.gd`: aquele teste mede o campo, e o campo
## está resolvido. Este mede a silhueta do jogador, e a silhueta é montada por
## `QixPlayerView.sync` a partir de cores **emprestadas** da paleta do campo. Isso torna a dívida
## estrutural em vez de autoral: nenhuma escolha de paleta conserta `CURSOR_OUTER×BOUNDARY`,
## porque a camada externa do cursor *é* `boundary_color` por construção.
##
## Só apresentação. Nada aqui toca `game/simulation`, `game/rules` ou `game/session`.

const PaletteContrast := preload("res://tools/palette_contrast.gd")
const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"


func test_o_mapa_de_camadas_acompanha_o_que_a_view_realmente_desenha() -> void:
	# A guarda que dá valor a todo o resto: se alguém trocar a cor de uma camada em
	# `QixPlayerView.sync`, a medição continuaria feliz medindo a camada antiga. Aqui a fonte da
	# verdade é a própria view.
	var session := GameSession.new(_campaign())
	var visual := session.current_content().visual
	var before := session.simulation.state_checksum()
	var player := QixPlayerView.new()
	player.sync(session.simulation, visual)
	var drawn: Dictionary = player.presentation_colors()
	var measured: Dictionary = PaletteContrast.cursor_swatches(visual)
	eq(measured.size(), drawn.size(), "medição e view discordam em quantas camadas existem")
	for layer in PaletteContrast.CURSOR_LAYERS:
		var measured_name: String = layer[0]
		var drawn_name := measured_name.trim_prefix("CURSOR_").to_lower()
		ok(drawn.has(drawn_name), "a view não expõe a camada %s" % drawn_name)
		eq(
			measured[measured_name][0],
			drawn[drawn_name],
			"camada %s: a medição usa uma cor que a view não desenha" % measured_name,
		)
	eq(session.simulation.state_checksum(), before, "medir a paleta não altera a simulação")
	player.free()


func test_a_silhueta_sobre_free_passa_da_meta_em_toda_dicromacia() -> void:
	# Metade boa da medição, e a que precisa de catraca: enquanto desenha, o jogador está sobre
	# `FREE`, e ali as três camadas separam com folga. É exatamente essa folga que se perderia sem
	# querer ao mexer nas cores do cursor para resolver a metade ruim.
	for entry in _palettes():
		var measurement: Dictionary = PaletteContrast.measure_cursor(entry["visual"])
		for pair in measurement["pairs"]:
			if not String(pair["pair"]).ends_with("×FREE"):
				continue
			for vision_label in pair["by_vision"]:
				var ratio: float = pair["by_vision"][vision_label]
				ok(
					ratio >= PaletteContrast.TARGET_RATIO,
					"%s: %s em %s ficou em %.2f:1" % [
						entry["label"], pair["pair"], vision_label, ratio,
					],
				)


func test_o_cursor_nao_regride_em_nenhuma_paleta() -> void:
	for entry in _palettes():
		var measurement: Dictionary = PaletteContrast.measure_cursor(entry["visual"])
		var regressions: PackedStringArray = PaletteContrast.regressions(measurement)
		eq(
			String("\n      ".join(regressions)),
			"",
			"%s: cursor piorou em relação ao piso registrado" % entry["label"],
		)


func test_a_divida_do_cursor_descreve_a_paleta_atual() -> void:
	# Falha nos dois sentidos, como a dívida do campo: consertar um par sem reescrever
	# `CURSOR_KNOWN_DEBT`, o piso e a seção de `ART_DIRECTION` derruba o commit.
	var expected := PackedStringArray(PaletteContrast.CURSOR_KNOWN_DEBT)
	expected.sort()
	for entry in _palettes():
		var measurement: Dictionary = PaletteContrast.measure_cursor(entry["visual"])
		var below: PackedStringArray = measurement["below_target"]
		below.sort()
		eq(
			String(", ".join(below)),
			String(", ".join(expected)),
			"%s: pares do cursor abaixo de %.1f:1 divergem da dívida documentada" % [
				entry["label"], PaletteContrast.TARGET_RATIO,
			],
		)


func test_a_camada_externa_do_cursor_e_o_chao_boundary_por_construcao() -> void:
	# O achado que torna a dívida estrutural, e não uma escolha infeliz de paleta: `_outer` recebe
	# `boundary_color` literal, então a razão é 1,00:1 **em qualquer paleta que alguém autore**.
	# Se um dia a view deixar de emprestar essa cor, este teste falha e a dívida é revista.
	for entry in _palettes():
		var visual: RoundVisualDefinition = entry["visual"]
		var swatches: Dictionary = PaletteContrast.cursor_swatches(visual)
		eq(
			swatches["CURSOR_OUTER"][0],
			visual.boundary_color,
			"%s: a camada externa deixou de ser a própria cor do chão" % entry["label"],
		)
		ok(
			is_equal_approx(
				PaletteContrast.contrast_ratio(visual.boundary_color, visual.boundary_color),
				1.0,
			),
			"uma cor contra si mesma tem de medir 1,00:1",
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


func _campaign() -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"cursor_contrast_test"
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
	visual.display_name = "ABYSSAL RELAY"
	visual.background = ImageTexture.create_from_image(Image.create(13, 9, false, Image.FORMAT_RGBA8))
	# Cores deliberadamente distintas das do padrão: se o mapa de camadas estiver trocado, o
	# assert compara duas cores diferentes em vez de duas cores iguais por acidente.
	visual.boundary_color = Color("62f7d1")
	visual.accent_color = Color("7ab4c1")
	visual.trail_hot_color = Color("fff1b8")
	visual.threat_color = Color("ff3f72")
	var content := RoundContent.new()
	content.round_id = &"cursor_probe"
	content.rules = rules
	content.round_definition = definition
	content.seed_value = 11
	content.visual = visual
	return content
