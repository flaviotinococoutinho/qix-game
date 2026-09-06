extends TestCase
## Guarda de autoração da paleta: dois papéis com a mesma cor são uma leitura a menos.
##
## Por que um teste e não uma revisão: a colisão de papéis é invisível para todas as outras
## guardas do projeto. `tools/palette_contrast.gd` mede a razão de luminância entre pares e
## recusa uma paleta que *piore* o que já foi medido — mas razão 1,00 não é um par fraco, é a
## ausência de par, e uma paleta autorada com `trail_color == trail_hot_color` passaria por lá
## exatamente como passa hoje pela transação de conteúdo: em silêncio, com o canal de risco da
## exposição desenhado como cor chapada.


func test_production_palettes_keep_every_role_separate() -> void:
	for path in [
		"res://content/visuals/round_01_abyssal_relay.tres",
		"res://content/visuals/round_02_aurora_foundry.tres",
		"res://content/visuals/round_03_verdant_singularity.tres",
	]:
		var visual := load(path) as RoundVisualDefinition
		ok(visual != null, "paleta de produção ausente: %s" % path)
		if visual == null:
			continue
		eq(_collisions(visual), PackedStringArray(), "paleta de produção com papéis colididos: %s" % path)


func test_collapsed_heat_channel_is_refused() -> void:
	# `board_reveal.gdshader` faz `mix(trail_color, trail_hot_color, heat)`. Iguais, o pulso da
	# trilha existe no shader e não existe na tela.
	var visual := _authorable()
	visual.trail_hot_color = visual.trail_color
	var errors := _collisions(visual)
	eq(errors.size(), 1, "esperava exatamente uma colisão, obtive: %s" % str(errors))
	ok(_mentions(errors, "trail_color"), "o erro precisa nomear o papel colidido")
	ok(_mentions(errors, "trail_hot_color"), "o erro precisa nomear o outro papel")


func test_every_role_pair_is_guarded() -> void:
	# Não basta guardar os pares que hoje doem: o próximo setor autorado escolhe outros seis
	# valores, e a guarda tem de valer para os quinze pares, não para os que alguém lembrou.
	var roles := RoundVisualDefinition.DISTINCT_ROLES
	var pairs := 0
	for index in roles.size():
		for other in range(index + 1, roles.size()):
			var visual := _authorable()
			visual.set(roles[other], visual.get(roles[index]))
			var errors := _collisions(visual)
			eq(errors.size(), 1, "par %s×%s passou sem erro" % [roles[index], roles[other]])
			pairs += 1
	eq(pairs, 15, "seis papéis dão quinze pares")


func test_roles_that_differ_below_8_bit_quantization_still_collide() -> void:
	# 0,5019 e 0,5020 são o mesmo byte depois do arredondamento. Comparar `Color` diria que os
	# papéis estão separados; o jogador veria uma cor só.
	var visual := _authorable()
	visual.free_color = Color(0.501960, 0.2, 0.3, 1.0)
	visual.threat_color = Color(0.502020, 0.2, 0.3, 1.0)
	ne(visual.free_color, visual.threat_color, "as cores não são iguais como float")
	ok(not _collisions(visual).is_empty(), "mas são o mesmo pixel em RGBA8")


func test_alpha_alone_separates_two_roles() -> void:
	# O shader carrega o alpha autorado de FREE e BOUNDARY (`free_color.a`, `boundary_color.a`),
	# e o halo do cursor sobrescreve o seu. Dois papéis com o mesmo RGB e alphas diferentes são
	# duas leituras — não é colisão.
	var visual := _authorable()
	visual.accent_color = Color(visual.threat_color.r, visual.threat_color.g, visual.threat_color.b, 0.4)
	eq(_collisions(visual), PackedStringArray(), "alpha distinto não é colisão de papel")


## Só as colisões de papel: `validation_errors` também cobra `display_name` e `background`, que
## este teste não autora e não quer medir.
func _collisions(visual: RoundVisualDefinition) -> PackedStringArray:
	var found := PackedStringArray()
	for error in visual.validation_errors(9, 9):
		if error.contains("mesma cor"):
			found.append(error)
	return found


func _mentions(errors: PackedStringArray, fragment: String) -> bool:
	for error in errors:
		if error.contains(fragment):
			return true
	return false


## Seis valores deliberadamente separados, para que qualquer colisão medida seja a que o teste
## introduziu.
func _authorable() -> RoundVisualDefinition:
	var visual := RoundVisualDefinition.new()
	visual.display_name = "SETOR DE TESTE"
	visual.free_color = Color("101010")
	visual.boundary_color = Color("202020")
	visual.trail_color = Color("303030")
	visual.trail_hot_color = Color("404040")
	visual.threat_color = Color("505050")
	visual.accent_color = Color("606060")
	return visual
