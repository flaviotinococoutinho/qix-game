extends TestCase
## Defende a medição de contraste e a paleta autorada.
##
## O módulo é matemática pura de apresentação: valida-se contra referências conhecidas (preto ×
## branco = 21:1) e contra as modulações reais de `board_reveal.gdshader`. A paleta autorada é
## defendida por catraca — `PaletteContrast.PAIR_FLOOR` — e pela lista de dívida conhecida, para
## que uma melhoria também obrigue a atualizar o texto de `docs/ART_DIRECTION.md`.

const PaletteContrast := preload("res://tools/palette_contrast.gd")
const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"
const SHADER_PATH := "res://game/board/board_reveal.gdshader"
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
	# FREE cruza três modulações — scanline, poço e grade —, então são oito cantos, não dois.
	eq(swatches["FREE"].size(), 8, "FREE cruza scanline × poço × grade")
	eq(swatches["BOUNDARY"].size(), 2, "BOUNDARY tem os dois extremos do glint")
	eq(swatches["TRAIL"].size(), 2, "TRAIL tem os dois extremos do pulso")
	eq(swatches["THREAT"].size(), 1, "THREAT é desenhado sem modulação pelo EnemyView")
	ok(
		_close(swatches["BOUNDARY"][0].g, visual.boundary_color.g * 0.86),
		"extremo escuro de BOUNDARY usa o fator 0.86 do shader",
	)
	eq(swatches["TRAIL"][1], visual.trail_hot_color, "extremo quente de TRAIL é trail_hot_color")


func test_o_envelope_de_free_cobre_os_dois_extremos_que_o_shader_desenha() -> void:
	# O erro que este teste existe para impedir é o que a medição carregou até 2026-09-08: afirmar
	# "como o shader desenha" enquanto se aplicava só a scanline. Os três canais importam:
	# trocar R e B na grade conserva todos os literais, mas muda as cores realmente desenhadas.
	var visual := RoundVisualDefinition.new()
	var well_floor: float = (
		PaletteContrast.FREE_WELL_BASE + PaletteContrast.FREE_WELL_SPAN * (1.0 - sqrt(0.5))
	)
	for channel in 3:
		var base: float = visual.free_color[channel]
		var darkest := INF
		var brightest := -INF
		for swatch in PaletteContrast.free_swatches(visual.free_color):
			darkest = minf(darkest, swatch[channel])
			brightest = maxf(brightest, swatch[channel])
		ok(absf(darkest - base * PaletteContrast.FREE_SCAN[0] * well_floor) < 0.000001,
			"canal %d: scanline mínima × poço do canto" % channel)
		ok(absf(brightest - (base + PaletteContrast.FREE_GRID_ADD[channel])) < 0.000001,
			"canal %d: a grade é somada ao canal correspondente" % channel)
		ok(brightest > base, "a grade clareia o canal %d" % channel)
		ok(darkest < base * PaletteContrast.FREE_SCAN[0], "o poço escurece o canal %d" % channel)


func test_nenhum_numero_do_ramo_free_do_shader_fica_fora_da_medicao() -> void:
	# Guarda de deriva, não de valor. `well` e `grade` moraram no shader por meses sem que a medição
	# soubesse deles, porque nada obrigava alguém a reler o shader ao mexer nas constantes. Aqui cada
	# literal do ramo FREE precisa constar da tabela abaixo com o motivo escrito — e uma entrada
	# órfã também fica vermelha, para que a tabela não vire um cemitério de números que saíram.
	var declared := {
		"0.92": "piso da scanline; `PaletteContrast.FREE_SCAN[0]`",
		"0.08": "amplitude da scanline: 0.92 + 0.08 fecha em 1.0, o topo de `FREE_SCAN`",
		"0.5": "meio período da scanline e centro do UV/da célula da grade — geometria, não brilho",
		"24.0": "período da grade em células lógicas — geometria, não brilho",
		"1.0": "topo normalizado de `grid`, de `well` e da scanline",
		"0.0": "piso do `smoothstep` da grade",
		"0.32": "largura do traço da grade — geometria, não brilho",
		"0.84": "base do poço; `PaletteContrast.FREE_WELL_BASE`",
		"0.16": "amplitude do poço; `PaletteContrast.FREE_WELL_SPAN`",
		"0.006": "grade somada no canal R; `PaletteContrast.FREE_GRID_ADD.x`",
		"0.012": "grade somada no canal G; `PaletteContrast.FREE_GRID_ADD.y`",
		"0.016": "grade somada no canal B; `PaletteContrast.FREE_GRID_ADD.z`",
	}
	var found := _free_branch_literals()
	ok(not found.is_empty(), "o ramo FREE do shader não rendeu nenhum literal — leitura falhou?")
	for literal in found:
		ok(
			declared.has(literal),
			(
				"o ramo FREE de board_reveal.gdshader usa %s, que a medição não conhece: "
				+ "ou ele entra no envelope de `free_swatches`, ou entra nesta tabela com o motivo."
			) % literal,
		)
	for literal in declared:
		ok(
			found.has(literal),
			"%s consta como literal do ramo FREE mas sumiu do shader: entrada órfã" % literal,
		)
	# Inventário de números não vincula papel nem canal: a fórmula também precisa conferir.
	eq(_free_brightness_contract_errors(FileAccess.get_file_as_string(SHADER_PATH)),
		PackedStringArray(), "scan, well e os canais RGB devem alimentar a fórmula medida")


func test_free_shader_guard_binds_channels_and_operations_even_when_literals_repeat() -> void:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	eq(_free_brightness_contract_errors(source), PackedStringArray())
	var mutations: Array[String] = [
		source.replace("vec3(0.006, 0.012, 0.016)", "vec3(0.016, 0.012, 0.006)"),
		source.replace("float scan = 0.92 + 0.08", "float scan = 0.08 + 0.92"),
		source.replace("float well = 0.84 + 0.16", "float well = 0.16 + 0.84"),
		source.replace("free_color.rgb * scan * well", "free_color.rgb * scan + well"),
	]
	for mutated in mutations:
		ok(mutated != source, "a fixture precisa alterar a fórmula real")
		ok(not _free_brightness_contract_errors(mutated).is_empty(),
			"mesmos números em canais ou operações diferentes não representam o mesmo shader")
	var formatted := source.replace("float well =", "float /* anotação */ well  =\n")
	formatted = formatted.replace("vec3(0.006, 0.012, 0.016)", "vec3( 0.006,\n0.012, 0.016 )")
	eq(_free_brightness_contract_errors(formatted), PackedStringArray(),
		"espaçamento e comentários não mudam a fórmula")


## Extrai valores pelo papel que exercem na fórmula. Forma desconhecida exige revisão:
## não tentamos interpretar GLSL arbitrário nem aceitar uma equação nova como equivalente.
func _free_brightness_contract_errors(source: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var comments := RegEx.create_from_string("(?s)/\\*.*?\\*/|//[^\\n]*")
	var clean := comments.sub(source, "", true)
	var branch_pattern := RegEx.create_from_string(
		"(?s)if\\s*\\(\\s*state\\s*<\\s*0\\.5\\s*\\)\\s*\\{(.*?)\\}\\s*else\\s+if")
	var branch_match := branch_pattern.search(clean)
	if branch_match == null:
		return PackedStringArray(["ramo FREE não reconhecido"])
	var branch := branch_match.get_string(1)
	var number := "([0-9]+(?:\\.[0-9]+)?)"
	var scan_pattern := RegEx.create_from_string(
		"\\bfloat\\s+scan\\s*=\\s*%s\\s*\\+\\s*%s\\s*\\*\\s*step\\s*\\(" % [number, number])
	var scan := scan_pattern.search(clean)
	if scan == null:
		errors.append("scan: fórmula não reconhecida")
	else:
		var base := scan.get_string(1).to_float()
		var span := scan.get_string(2).to_float()
		if absf(base - PaletteContrast.FREE_SCAN[0]) > 0.000001 \
			or absf(base + span - PaletteContrast.FREE_SCAN[1]) > 0.000001:
			errors.append("scan: base ou amplitude diverge de FREE_SCAN")
	var well_pattern := RegEx.create_from_string(
		("\\bfloat\\s+well\\s*=\\s*%s\\s*\\+\\s*%s\\s*\\*\\s*"
		+ "\\(\\s*1\\.0\\s*-\\s*length\\s*\\(\\s*UV\\s*-\\s*vec2\\s*"
		+ "\\(\\s*0\\.5\\s*\\)\\s*\\)\\s*\\)\\s*;") % [number, number])
	var well := well_pattern.search(branch)
	if well == null:
		errors.append("well: fórmula não reconhecida")
	elif absf(well.get_string(1).to_float() - PaletteContrast.FREE_WELL_BASE) > 0.000001 \
		or absf(well.get_string(2).to_float() - PaletteContrast.FREE_WELL_SPAN) > 0.000001:
		errors.append("well: base ou amplitude diverge da medição")
	var result_pattern := RegEx.create_from_string(
		("\\bresult\\s*=\\s*vec4\\s*\\(\\s*free_color\\.rgb\\s*\\*\\s*scan\\s*\\*\\s*well\\s*"
		+ "\\+\\s*vec3\\s*\\(\\s*%s\\s*,\\s*%s\\s*,\\s*%s\\s*\\)\\s*\\*\\s*grid\\s*,\\s*"
		+ "free_color\\.a\\s*\\)\\s*;") % [number, number, number])
	var result := result_pattern.search(branch)
	if result == null:
		errors.append("result: produto de scan/well e soma da grade não reconhecidos")
	else:
		for channel in 3:
			if absf(result.get_string(channel + 1).to_float() - PaletteContrast.FREE_GRID_ADD[channel]) > 0.000001:
				errors.append("grade: canal %d diverge de FREE_GRID_ADD" % channel)
	return errors


## Literais do ramo FREE, mais a linha `scan` que ele consome. Devolve as grafias como estão no
## shader: comparar texto evita discutir formatação de `float`.
func _free_branch_literals() -> Dictionary:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	if source.is_empty():
		fail("shader ausente ou ilegível em " + SHADER_PATH)
		return {}
	var scan_start := source.find("float scan =")
	var branch_start := source.find("if (state < 0.5) {")
	var branch_end := source.find("} else if", branch_start)
	if scan_start < 0 or branch_start < 0 or branch_end < 0:
		fail("board_reveal.gdshader mudou de forma: ramo FREE não localizado")
		return {}
	var scan_line := source.substr(scan_start, source.find(";", scan_start) - scan_start)
	var branch := source.substr(branch_start, branch_end - branch_start)
	var regex := RegEx.new()
	regex.compile("[0-9]+\\.[0-9]+")
	var result := {}
	for text in [scan_line, branch]:
		for match_result in regex.search_all(text):
			result[match_result.get_string()] = true
	return result


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
