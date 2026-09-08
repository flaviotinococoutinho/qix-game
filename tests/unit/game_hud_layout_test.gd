extends TestCase
## Defende a grade do HUD em 240×320.
##
## O HUD é montado em código, com coordenadas absolutas. Sem estes testes, um ajuste de um
## pixel num bloco encosta silenciosamente no vizinho e só aparece num dispositivo real — que
## nenhuma execução deste projeto na nuvem consegue observar. Aqui a banda é medida com a
## fonte de verdade, não conferida a olho.

## Pior caso plausível de cada campo, com o texto que a `sync` realmente formata.
const WORST_CASE_TEXT := {
	"Round": "R 3/3",
	"Score": "S 999999",
	"Percent": "100.0/75",
	"Vitals": "L×5  E99",
	"Status": "ESCUDO ESGOTADO · REENTRADA",
}

## `RoundTitle` fica de fora do teste de caber: nomes de setor são conteúdo autorável e o
## rótulo já declara `OVERRUN_TRIM_ELLIPSIS`. Truncar um nome longo é decisão, não acidente.
const TOP_BAND := ["Round", "Score", "Percent", "Vitals"]
const BOTTOM_BAND := ["RoundTitle", "Status"]


func test_every_band_respects_the_margins_and_never_leaves_the_viewport() -> void:
	var hud := _hud()
	for band: Array in [TOP_BAND, BOTTOM_BAND]:
		var first := _rect(hud, band[0])
		var last := _rect(hud, band[band.size() - 1])
		eq(first.position.x, QixGameHud.MARGIN, "%s começa fora da margem" % band[0])
		eq(
			CoordinateSpace.VIEWPORT.x - last.end.x,
			QixGameHud.MARGIN,
			"%s não fecha na margem oposta" % band[band.size() - 1])
	hud.free()


func test_neighbours_in_a_band_never_overlap_and_keep_the_gutter() -> void:
	var hud := _hud()
	for band: Array in [TOP_BAND, BOTTOM_BAND]:
		for index in range(1, band.size()):
			var left := _rect(hud, band[index - 1])
			var right := _rect(hud, band[index])
			ok(
				right.position.x - left.end.x >= QixGameHud.GUTTER,
				"%s e %s estão a %.1f px, abaixo da goteira de %.1f" % [
					band[index - 1], band[index],
					right.position.x - left.end.x, QixGameHud.GUTTER])
	hud.free()


func test_each_track_is_aligned_with_the_label_it_annotates() -> void:
	var hud := _hud()
	# Um trilho desalinhado do próprio número faz o jogador ler dois instrumentos onde há um.
	for pair: Array in [["Percent", "ObjectiveTrack"], ["Vitals", "ShieldTrack"]]:
		var label := _rect(hud, pair[0])
		var track := _rect(hud, pair[1])
		eq(track.position.x, label.position.x, "%s não começa em %s" % [pair[1], pair[0]])
		eq(track.size.x, label.size.x, "%s não tem a largura de %s" % [pair[1], pair[0]])
	# O preenchimento nasce exatamente sobre o trilho, senão o zero já parece progresso.
	for pair: Array in [["ObjectiveTrack", "ObjectiveFill"], ["ShieldTrack", "ShieldFill"]]:
		eq(_rect(hud, pair[1]).position, _rect(hud, pair[0]).position,
			"%s não nasce sobre %s" % [pair[1], pair[0]])
	hud.free()


func test_worst_case_text_fits_the_rectangle_it_was_given() -> void:
	var hud := _hud()
	for node_name: String in WORST_CASE_TEXT.keys():
		var label := hud.get_node(node_name) as Label
		var text: String = WORST_CASE_TEXT[node_name]
		var font_size: int = label.get_theme_font_size("font_size")
		var measured := label.get_theme_font("font").get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		ok(
			measured <= label.size.x,
			"%s: \"%s\" mede %.1f px e o retângulo tem %.1f" % [
				node_name, text, measured, label.size.x])
	hud.free()


func test_the_percentage_is_the_only_promoted_field() -> void:
	# Volfied dá à percentagem a fonte alternativa — o único dos 22 campos numéricos do HUD
	# que não usa a fonte normal (`reference/volfied/07-texto-e-fonte.md` §5.1, campo 4; a
	# fonte alternativa é a de dígitos grandes de §2.3). O comportamento adotado aqui é a
	# hierarquia, não os tiles: o número que responde "quanto falta" pesa mais que os outros.
	var hud := _hud()
	var percent_size := (hud.get_node("Percent") as Label).get_theme_font_size("font_size")
	for node_name: String in ["Round", "Score", "Vitals", "RoundTitle", "Status"]:
		var other := (hud.get_node(node_name) as Label).get_theme_font_size("font_size")
		ok(
			percent_size > other,
			"Percent (%d) não pesa mais que %s (%d)" % [percent_size, node_name, other])
	hud.free()


func test_text_rows_stay_inside_their_bar() -> void:
	# Só o eixo X é medido no runtime, e a razão não é a que este comentário afirmava antes.
	# A altura de um `Label` é presa ao mínimo dele; o runner corre dentro de `_initialize()`,
	# antes de a árvore processar um frame, e nessa janela o mínimo vale 23 px — o do tema
	# padrão, não o do override. Medido em 2026-09-06: `update_minimum_size()`, um
	# `custom_minimum_size` explícito e um `Theme` com `default_font_size` **não** resolvem
	# (os dois últimos eram as saídas que o backlog propunha); só um frame processado resolve,
	# e mesmo aí o `size` já atribuído continua nos 23 px, porque Godot clampa para cima e
	# nunca re-encolhe. Na via do jogo — HUD a entrar numa árvore que já processa — o mínimo
	# já é o certo no `add_child` e a linha assenta em TEXT_HEIGHT.
	#
	# O contrato vertical é, portanto, verificado fora daqui, por
	# `tools/verify_hud_row_geometry.gd`, que monta o HUD durante um frame e mede o retângulo
	# real. O que sobra para este teste são as constantes declaradas e a altura da fonte.
	var hud := _hud()
	var rows := [
		[QixGameHud.TOP_TEXT_Y, 0.0, QixGameHud.TOP_BAR_HEIGHT, TOP_BAND],
		[
			QixGameHud.BOTTOM_TEXT_Y,
			QixGameHud.BOTTOM_BAR_Y,
			QixGameHud.BOTTOM_BAR_Y + QixGameHud.BOTTOM_BAR_HEIGHT,
			BOTTOM_BAND,
		],
	]
	for row: Array in rows:
		var text_top: float = row[0]
		var bar_top: float = row[1]
		var bar_bottom: float = row[2]
		ok(
			text_top >= bar_top and text_top + QixGameHud.TEXT_HEIGHT <= bar_bottom,
			"linha de texto %.1f..%.1f sai da barra %.1f..%.1f" % [
				text_top, text_top + QixGameHud.TEXT_HEIGHT, bar_top, bar_bottom])
		for node_name: String in row[3]:
			var label := hud.get_node(node_name) as Label
			var height := label.get_theme_font("font").get_height(
				label.get_theme_font_size("font_size"))
			ok(
				height <= QixGameHud.TEXT_HEIGHT,
				"%s: fonte de %.1f px de altura numa linha de %.1f" % [
					node_name, height, QixGameHud.TEXT_HEIGHT])
	hud.free()


func test_the_horizontal_measurements_are_the_designed_ones_and_not_a_floor() -> void:
	# Todos os outros testes deste arquivo leem `size.x` e acreditam nele. Isso só é legítimo
	# enquanto o mínimo horizontal do `Label` couber na largura pedida: se algum dia alguém
	# puser `custom_minimum_size.x`, ou der texto ao rótulo antes da medição, `size.x` passa a
	# ser o piso do `Label` e não a largura autorada — e as margens, goteiras e alinhamentos
	# acima passariam a medir a coisa errada, todos verdes. O eixo Y já cai nesse buraco
	# (mínimo de 23 px no runner); esta guarda é para o X não cair em silêncio.
	var hud := _hud()
	for node_name: String in TOP_BAND + BOTTOM_BAND:
		var label := hud.get_node(node_name) as Label
		ok(
			label.get_combined_minimum_size().x <= label.size.x,
			"%s: mínimo horizontal de %.1f px numa largura pedida de %.1f — a medição do eixo X deixou de ser a autorada" % [
				node_name, label.get_combined_minimum_size().x, label.size.x])
	hud.free()


func test_the_objective_track_never_collides_with_the_row_above_it() -> void:
	# O trilho vive no mesmo 19 px da barra superior que os números. Se a linha de texto
	# crescer, ela come o trilho antes de qualquer coisa avisar.
	ok(
		QixGameHud.TOP_TEXT_Y + QixGameHud.TEXT_HEIGHT <= QixGameHud.TRACK_Y,
		"o texto do topo desce até %.1f e o trilho começa em %.1f" % [
			QixGameHud.TOP_TEXT_Y + QixGameHud.TEXT_HEIGHT, QixGameHud.TRACK_Y])
	ok(
		QixGameHud.TRACK_Y + QixGameHud.TRACK_HEIGHT <= QixGameHud.TOP_BAR_HEIGHT,
		"o trilho termina em %.1f e a barra em %.1f" % [
			QixGameHud.TRACK_Y + QixGameHud.TRACK_HEIGHT, QixGameHud.TOP_BAR_HEIGHT])


func test_the_objective_track_is_the_widest_instrument() -> void:
	# A leitura primária é "quanto falta". O escudo é urgente, mas é o segundo instrumento:
	# se ele for o mais largo, o olho vai para a ameaça antes de ir para o progresso.
	ok(
		QixGameHud.OBJECTIVE_WIDTH > QixGameHud.SHIELD_WIDTH,
		"objetivo tem %.1f px e escudo %.1f" % [
			QixGameHud.OBJECTIVE_WIDTH, QixGameHud.SHIELD_WIDTH])


func _hud() -> QixGameHud:
	var hud := QixGameHud.new()
	# Entrar na árvore resolve o tema; sem isso `get_theme_font` devolveria o fallback e a
	# medição não seria a do HUD real. O runner corre dentro de `_initialize()`, antes de a
	# árvore processar, então `_ready` não dispara sozinho — chamá-lo é o que `game_hud_test`
	# já faz, e a guarda `_built` mantém a chamada idempotente.
	Engine.get_main_loop().root.add_child(hud)
	hud._ready()
	return hud


func _rect(hud: QixGameHud, node_name: String) -> Rect2:
	var control := hud.get_node(node_name) as Control
	return Rect2(control.position, control.size)
