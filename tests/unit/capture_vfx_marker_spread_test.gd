extends TestCase
## As marcas da captura têm que *espalhar-se* pelo foco, e não só cair dentro dele.
##
## `capture_vfx_focus_test.gd` (#37) provou a contenção: nenhuma marca escapa do foco nem do
## campo. Contenção não é distribuição, e era exatamente aí que o efeito falhava em silêncio.
##
## O espalhamento vinha de um pente modular — `(marca * 37) % vão_x` e `(marca * 71) % vão_y`.
## Um pente é regular no *índice*, não no *foco*, e desde o #37 o lado do foco é autorado pela
## trilha que o jogador acabou de desenhar. Quando o lado ressoa com o passo, o pente colapsa:
##
## | vão do foco | o que as doze marcas faziam |
## |---|---|
## | 37 px em x | caíam todas na **mesma coluna** (uma barra vertical de doze cruzes) |
## | 71 px em y | caíam todas na **mesma linha** |
## | 38 px em x | doze marcas num rastro contíguo de 12 px, 71 % do foco vazio |
## | 72 px em y | idem, 85 % do foco vazio |
## | 111 px em x | três colunas |
##
## Um foco de 41×75 px é uma captura banal num campo de 225×283, então isto não é um canto
## patológico: é o clímax do jogo a apostar numa coincidência aritmética. E nenhum teste via,
## porque afirmar "está dentro" fica verde com tudo empilhado num pixel.
##
## A troca é por uma recorrência aditiva com passo irracional (sequência R2 de Roberts), que
## nenhum lado inteiro divide. Este arquivo mede o que o pente não conseguia prometer: **a maior
## lacuna** entre coordenadas ocupadas, como fração do lado do foco. É a métrica certa porque é
## ela que o olho lê — um foco com metade vazia parece uma captura pela metade.
##
## Tudo aqui é apresentação: `marker_positions()` lê `focus_rect` e dois inteiros de evento
## confirmado, e nada volta para a simulação (invariantes 6 e 8).

## Piso medido sobre lados de 24 a 204 px e capturas de 0 a 63000 células: com quatro marcas a
## pior lacuna observada foi 47,6 % e com doze, 26,1 %. Os limites abaixo têm folga sobre isso.
const MAX_GAP_ANY := 0.50
const MAX_GAP_TWELVE := 0.30
## Com doze marcas a pior contagem observada de coordenadas distintas foi 5 (vãos pequenos, em que
## doze pontos não cabem sem colisão). Com quatro, as quatro sempre foram distintas.
const MIN_DISTINCT_TWELVE := 5


## O caso que o pente quebrava, nomeado: 41×75 px é vão 37×71, os dois módulos exatos.
func test_the_focus_side_that_used_to_collapse_the_comb_now_spreads() -> void:
	var vfx := _vfx(Rect2(30.0, 40.0, 41.0, 75.0), 900, 300)
	var markers := vfx.marker_positions()
	eq(markers.size(), 12, "uma captura de 900 células merece as doze marcas")

	var columns := _distinct(markers, true)
	var rows := _distinct(markers, false)
	ok(columns.size() >= MIN_DISTINCT_TWELVE,
		"as doze marcas ocuparam só %d coluna(s): é a barra vertical do pente de volta" % columns.size())
	ok(rows.size() >= MIN_DISTINCT_TWELVE,
		"as doze marcas ocuparam só %d linha(s): é a barra horizontal do pente de volta" % rows.size())
	vfx.free()


func test_no_reachable_focus_leaves_half_of_itself_empty() -> void:
	var worst_gap := 0.0
	var worst_label := ""
	var worst_twelve := 0.0
	var worst_twelve_label := ""
	var fewest_twelve := 1000
	# Lados de 24 (o piso `MIN_FOCUS_SIDE`) ao campo inteiro de produção, e capturas que cobrem
	# os dois extremos da contagem de marcas (`mini(12, maxi(4, filled_delta / 64))`).
	for side in range(24, 205, 3):
		for capture in [[0, 0], [200, 120], [768, 500], [900, 300], [63_000, 999]]:
			var vfx := _vfx(Rect2(12.0, 20.0, float(side), float(side)), capture[0], capture[1])
			var markers := vfx.marker_positions()
			var span := float(side) - 2.0 * QixCaptureVfx.MARKER_RADIUS
			for horizontal in [true, false]:
				var gap := _largest_gap(_distinct(markers, horizontal), span)
				var label := "lado %d, captura %s, eixo %s" % [
					side, capture, "x" if horizontal else "y",
				]
				if gap > worst_gap:
					worst_gap = gap
					worst_label = label
				if markers.size() == 12:
					if gap > worst_twelve:
						worst_twelve = gap
						worst_twelve_label = label
					fewest_twelve = mini(fewest_twelve, _distinct(markers, horizontal).size())
			vfx.free()

	ok(worst_gap <= MAX_GAP_ANY,
		"maior lacuna %.3f do foco em %s — acima do teto %.2f" % [worst_gap, worst_label, MAX_GAP_ANY])
	ok(worst_twelve <= MAX_GAP_TWELVE,
		"com doze marcas a maior lacuna foi %.3f em %s — acima do teto %.2f" % [
			worst_twelve, worst_twelve_label, MAX_GAP_TWELVE,
		])
	ok(fewest_twelve >= MIN_DISTINCT_TWELVE,
		"doze marcas chegaram a ocupar só %d coordenadas distintas" % fewest_twelve)


## A distribuição não pode custar a contenção que o #37 conquistou, nem depender de um foco grande.
func test_every_marker_stays_inside_the_focus_for_every_swept_side() -> void:
	for side in range(24, 205, 7):
		for capture in [[0, 0], [321, 777], [63_000, 999]]:
			var focus := Rect2(12.0, 20.0, float(side), float(side))
			var vfx := _vfx(focus, capture[0], capture[1])
			for marker in vfx.marker_positions():
				ok(focus.has_point(marker),
					"lado %d, captura %s: marca em %s escapou do foco %s" % [
						side, capture, marker, focus,
					])
			vfx.free()


## Apresentação determinística: a mesma captura desenha a mesma constelação. Sem isto, duas
## reproduções do mesmo replay divergiriam na tela sem divergir no domínio.
func test_the_same_capture_always_draws_the_same_constellation() -> void:
	var first := _vfx(Rect2(30.0, 40.0, 41.0, 75.0), 900, 300)
	var second := _vfx(Rect2(30.0, 40.0, 41.0, 75.0), 900, 300)
	eq(first.marker_positions(), second.marker_positions())
	# ...e capturas diferentes não repetem a constelação anterior no mesmo foco.
	var other := _vfx(Rect2(30.0, 40.0, 41.0, 75.0), 901, 300)
	ok(other.marker_positions() != first.marker_positions(),
		"duas capturas distintas desenharam exatamente as mesmas marcas")
	first.free()
	second.free()
	other.free()


func _vfx(focus: Rect2, filled_delta: int, permille: int) -> QixCaptureVfx:
	var vfx := QixCaptureVfx.new()
	vfx.focus_rect = focus
	vfx.last_filled_delta = filled_delta
	vfx.last_permille = permille
	return vfx


func _distinct(markers: PackedVector2Array, horizontal: bool) -> PackedFloat32Array:
	var seen := PackedFloat32Array()
	for marker in markers:
		var value := marker.x if horizontal else marker.y
		if not seen.has(value):
			seen.append(value)
	seen.sort()
	return seen


## Maior vão entre coordenadas ocupadas consecutivas, em fração do lado. Uma coordenada só devolve
## 1.0: tudo empilhado é a pior lacuna possível, e é exatamente o que o pente produzia.
func _largest_gap(occupied: PackedFloat32Array, span: float) -> float:
	if occupied.size() <= 1 or span <= 0.0:
		return 1.0
	var largest := 0.0
	for i in occupied.size() - 1:
		largest = maxf(largest, occupied[i + 1] - occupied[i])
	return largest / span
