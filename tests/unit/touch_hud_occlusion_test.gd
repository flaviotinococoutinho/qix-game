extends TestCase
## O polegar não pode apagar um instrumento.
##
## `TouchControls` é o último nó de `app/bootstrap.tscn` e desenha por cima do `HUD`. Nada na
## suíte media essa sobreposição: `game_hud_layout_test.gd` prova a grade do HUD contra ela
## mesma, e `touch_controls_test.gd` prova a entrada do stick — nenhum dos dois olha para o que
## uma camada faz com os pixels da outra. No meio desse vão, a pausa era desenhada com
## preenchimento a 58 % começando em y=10, dentro dos 19 px da banda superior, e cobria 32 dos
## 82 px do trilho do escudo mais o pé dos números vitais.
##
## O critério adotado aqui separa duas coisas que não têm o mesmo custo:
##
## - **Instrumento do HUD**: número ou trilho que o jogador *lê*. Meio escondido é pior que
##   ausente, porque a leitura errada não se anuncia. Oclusão proibida, sem orçamento.
## - **Campo**: chão que o jogador *vê*. Em retrato de 240×320 não existe canto livre para um
##   alvo de polegar; o trato aceito é velar, nunca tapar. Por isso o limite é de opacidade,
##   e vale para toda peça de chrome.
##
## Os retângulos vêm de `chrome_rects()`, a mesma função que `_draw()` usa, e as caixas do HUD
## são medidas nos nós reais — não em constantes copiadas para cá.

const VIEWPORT := Vector2(240.0, 320.0)

## Instrumentos por banda, com a linha declarada de cada um. O eixo X é lido do nó real; o Y
## vem da constante, e a razão é a mesma que `game_hud_layout_test.gd` já mediu em 2026-09-06:
## dentro de `_initialize()` a altura mínima de um `Label` ainda é a do tema padrão, 23 px, e
## não os 14 de `TEXT_HEIGHT`. Medir `size.y` aqui faria a guarda acusar o rótulo das vitais de
## descer até y=24 — um transbordo do runner, não do HUD.
const TOP_INSTRUMENTS := {
	"Round": "top_text",
	"Score": "top_text",
	"Percent": "top_text",
	"Vitals": "top_text",
	"ObjectiveTrack": "track",
	"ShieldTrack": "track",
}
const BOTTOM_INSTRUMENTS := {"RoundTitle": "bottom_text", "Status": "bottom_text"}

## Nenhum véu da sobreposição pode passar disto. É a opacidade do botão de ação, a peça mais
## carregada que a direção de arte aceita sobre o campo. A comparação é em centésimos porque
## `Color` guarda o alfa em 32 bits: 0,28 autorado volta como 0,28000001.
const MAX_VEIL_ALPHA := 0.28

## Intrusão do chrome **em repouso** na barra inferior, em px, por peça. A barra começa em 302;
## o anel do stick desce até 308 e o botão de ação até 305. Não é zero, e é por isso que existe
## um orçamento: para que não cresça em silêncio.
##
## Com o dedo na zona o anel viaja com ele e pode cobrir a barra inteira — mas nesse instante o
## polegar já está lá, e nenhum recuo de geometria devolve esse pixel. O que se prova do caso
## flutuante é o outro extremo: a âncora nunca alcança a banda superior.
const BOTTOM_BAR_INTRUSION_PX := {"stick": 6.0, "action": 3.0, "pause": 0.0}

## Os dois arcos cruzam a linha de texto do rodapé, que começa em 304. Isto **não** é conforto
## declarado como se fosse folga: é a largura medida do arco na altura dessa linha — 35,8 px do
## anel sobre os 91 do título e 17,6 px do botão sobre os 139 do status. Recuar mais reabriria a
## ergonomia do polegar fechada em #90; o que a guarda faz é impedir que essa mordida cresça.
const TEXT_ROW_ARC_SPAN_PX := {"stick": 36.0, "action": 18.0}


func test_no_touch_chrome_covers_a_top_band_instrument() -> void:
	# A prova que motivou este arquivo, medida contra os nós do HUD e não contra constantes.
	var hud := _hud()
	var touch := _controls()
	for name: String in TOP_INSTRUMENTS:
		var instrument := _rect(hud, name, TOP_INSTRUMENTS[name])
		for piece: String in touch.chrome_rects():
			var chrome: Rect2 = touch.chrome_rects()[piece]["rect"]
			ok(
				not chrome.intersects(instrument),
				"o chrome '%s' (%s) cobre o instrumento %s (%s): um número ou trilho meio tapado é lido como se estivesse inteiro" % [
					piece, chrome, name, instrument])
	touch.free()
	hud.free()


func test_the_pause_clears_the_top_bar_by_deriving_its_height() -> void:
	# Encostar por baixo é a intenção; derivar a altura é o que a mantém verdadeira quando a
	# banda mudar. Se alguém aumentar TOP_BAR_HEIGHT, a pausa desce junto em vez de submergir.
	var touch := _controls()
	var pause: Rect2 = touch.chrome_rects()["pause"]["rect"]
	eq(pause.position.y, QixGameHud.TOP_BAR_HEIGHT, "a pausa não está encostada na banda superior")
	ok(
		pause.end.x <= VIEWPORT.x and pause.end.y <= VIEWPORT.y,
		"a pausa sai do viewport: %s" % pause)
	touch.free()


func test_the_floating_stick_can_never_anchor_inside_the_hud_band() -> void:
	# O anel segue o dedo, então a caixa em repouso não prova nada sozinha. O que a mantém fora
	# da banda superior é a zona de ancoragem: o toque mais alto que vira stick está em
	# 0,48 · 320 = 153,6, e 153,6 − 42 de raio ainda deixa 92 px de folga até os 19 px do HUD.
	var touch := _controls()
	var highest_anchor := VIEWPORT.y * QixTouchControls.STICK_ZONE_TOP_RATIO
	touch.handle_event(_touch(1, true, Vector2(10.0, highest_anchor)))
	var stick: Rect2 = touch.chrome_rects()["stick"]["rect"]
	eq(touch.presentation_state()["stick_center"], Vector2(10.0, highest_anchor),
		"a âncora mais alta da zona não foi aceita; a folga medida abaixo seria a do lugar errado")
	ok(
		stick.position.y > QixGameHud.TOP_BAR_HEIGHT,
		"a âncora mais alta põe o anel em y=%.1f, dentro da banda de %.1f px" % [
			stick.position.y, QixGameHud.TOP_BAR_HEIGHT])
	touch.free()


func test_the_resting_intrusion_into_the_bottom_bar_stays_inside_the_budget() -> void:
	var touch := _controls()
	var bar_top := QixGameHud.BOTTOM_BAR_Y
	for piece: String in touch.chrome_rects():
		var chrome: Rect2 = touch.chrome_rects()[piece]["rect"]
		var intrusion := maxf(0.0, chrome.end.y - bar_top)
		var budget: float = BOTTOM_BAR_INTRUSION_PX[piece]
		ok(
			intrusion <= budget,
			"o chrome '%s' desce %.1f px dentro da barra inferior, acima do orçamento de %.1f" % [
				piece, intrusion, budget])
	touch.free()


func test_the_arcs_that_cross_the_bottom_text_row_never_widen_their_bite() -> void:
	# A caixa do anel é um quadrado, mas o que desenha é um círculo: na altura da linha de texto
	# ele é bem mais estreito que a caixa. Medir o círculo é o que separa "cruza a linha" de
	# "come a linha", e é o número que precisa ficar preso.
	var hud := _hud()
	var touch := _controls()
	var row := QixGameHud.BOTTOM_TEXT_Y
	var spans := {
		"stick": [touch.chrome_rects()["stick"]["rect"], "RoundTitle"],
		"action": [touch.chrome_rects()["action"]["rect"], "Status"],
	}
	for piece: String in spans:
		var chrome: Rect2 = spans[piece][0]
		var label := _rect(hud, spans[piece][1], BOTTOM_INSTRUMENTS[spans[piece][1]])
		var span := _circle_span_at(chrome.get_center(), chrome.size.x * 0.5, row)
		ok(
			span <= TEXT_ROW_ARC_SPAN_PX[piece],
			"o arco de '%s' cobre %.1f px da linha de texto, acima dos %.1f medidos" % [
				piece, span, TEXT_ROW_ARC_SPAN_PX[piece]])
		ok(
			span < label.size.x * 0.5,
			"o arco de '%s' já cobre metade de %s (%.1f de %.1f px): deixou de ser mordida e virou tapume" % [
				piece, spans[piece][1], span, label.size.x])
	touch.free()
	hud.free()


func test_no_chrome_veil_is_opaque_enough_to_hide_the_field_under_it() -> void:
	# Velar é o trato; tapar não é. A pausa era a única peça fora dessa família, com 58 %.
	var touch := _controls()
	for piece: String in touch.chrome_rects():
		var veil: Color = touch.chrome_rects()[piece]["veil"]
		ok(
			snappedf(veil.a, 0.01) <= MAX_VEIL_ALPHA,
			"o véu de '%s' tem alfa %.2f, acima do teto de %.2f: a moldura e um corpo de ameaça deixam de se ler debaixo dele" % [
				piece, veil.a, MAX_VEIL_ALPHA])
	touch.free()


func test_the_guard_accuses_a_planted_chrome_over_an_instrument() -> void:
	# Uma varredura que não sabe acusar nada passa para sempre sem olhar. A violação plantada é
	# a pausa no lugar de onde ela saiu: y=10, dentro da banda, sobre o trilho do escudo.
	var hud := _hud()
	var planted := Rect2(Vector2(VIEWPORT.x - 42.0, 10.0), Vector2(32.0, 24.0))
	var shield := _rect(hud, "ShieldTrack", "track")
	ok(planted.intersects(shield), "a violação plantada deixou de tocar o trilho do escudo")
	var covered := planted.intersection(shield)
	ok(
		covered.size.x >= 30.0,
		"a geometria histórica cobria 32 px do trilho; a medição atual acusa %.1f" % covered.size.x)
	# E o critério em vigor recusa exatamente essa caixa.
	ok(
		not _controls_pause_rect().intersects(shield),
		"a pausa em vigor voltou a tocar o trilho do escudo")
	hud.free()


func test_the_pause_still_answers_a_touch_at_its_new_home_and_not_at_the_old_one() -> void:
	# Geometria sem entrada não é um botão. E o ponto antigo, agora sobre o escudo, não pode
	# continuar pausando: um toque ali seria uma pausa que o jogador não pediu ao ler as vitais.
	var touch := _controls()
	var pause: Rect2 = touch.chrome_rects()["pause"]["rect"]
	touch.handle_event(_touch(1, true, pause.get_center()))
	ok(touch.consume_pause(), "o centro da pausa não pausou")
	touch.handle_event(_touch(1, false, pause.get_center()))
	touch.handle_event(_touch(2, true, Vector2(VIEWPORT.x - 26.0, 14.0)))
	ok(not touch.consume_pause(), "um toque sobre a banda do HUD ainda é lido como pausa")
	touch.free()


func _controls() -> QixTouchControls:
	var touch := QixTouchControls.new()
	touch.size = VIEWPORT
	return touch


func _controls_pause_rect() -> Rect2:
	var touch := _controls()
	var rect: Rect2 = touch.chrome_rects()["pause"]["rect"]
	touch.free()
	return rect


func _touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event


func _hud() -> QixGameHud:
	# Mesmo caminho de `game_hud_layout_test.gd`: entrar na árvore resolve o tema, e `_ready`
	# não dispara sozinho dentro de `_initialize()`.
	var hud := QixGameHud.new()
	Engine.get_main_loop().root.add_child(hud)
	hud._ready()
	return hud


## Largura do círculo na altura `y`. Zero quando a linha passa fora dele.
func _circle_span_at(center: Vector2, radius: float, y: float) -> float:
	var dy := absf(y - center.y)
	if dy >= radius:
		return 0.0
	return 2.0 * sqrt(radius * radius - dy * dy)


## X do nó real, Y da linha declarada — ver a nota em `TOP_INSTRUMENTS`.
func _rect(hud: QixGameHud, node_name: String, row: String) -> Rect2:
	var control := hud.get_node(node_name) as Control
	var top := QixGameHud.TOP_TEXT_Y
	var height := QixGameHud.TEXT_HEIGHT
	match row:
		"track":
			top = QixGameHud.TRACK_Y
			height = QixGameHud.TRACK_HEIGHT
		"bottom_text":
			top = QixGameHud.BOTTOM_TEXT_Y
	return Rect2(Vector2(control.position.x, top), Vector2(control.size.x, height))
