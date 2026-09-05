extends TestCase
## A floritura da captura tem que acontecer **onde o jogador acabou de desenhar**.
##
## Até aqui `QixCaptureVfx._draw` espalhava as marcas pelo campo inteiro com dois módulos
## literais — `% 214` e `% 272` — herdados da geometria de produção (225×283). Duas consequências,
## nesta ordem de gravidade:
##
## 1. **Os literais não são o campo.** `RoundDefinition.field_width/height` são autoráveis
##    (invariante 9: autoração acontece em conteúdo, não em código). Num campo menor que
##    214×272 — e o dos próprios testes de apresentação é 13×9 — as marcas caíam **fora da
##    moldura**, por cima do HUD. Nenhum teste via isso, porque ver exigia expor a posição: é o
##    que `marker_positions()` passa a fazer.
## 2. **O momento de recompensa apontava para o lugar errado.** Fechar uma região é o clímax do
##    jogo, e a confirmação nascia espalhada uniformemente pelo campo, longe do traço que o
##    jogador acabou de fechar — o olho é puxado para longe da conquista em vez de para cima dela.
##
## A correção lê a extensão da trilha enquanto ela é desenhada (estado **confirmado** do domínio,
## leitura pura, sem cópia do board) e congela esse recorte no tick da captura. A moldura continua
## piscando no campo inteiro, porque o território mudou no campo inteiro; a varredura e as marcas
## passam a morar sobre o traço.

const FIELD_SIDE := 61


func test_capture_flourish_is_confined_to_the_trail_that_closed_the_region() -> void:
	var simulation := _simulation(FIELD_SIDE, FIELD_SIDE)
	var vfx := QixCaptureVfx.new()
	# Corte reto de cima a baixo na coluna 30: a trilha ocupa uma coluna e quase toda a altura.
	var captures := _draw(simulation, vfx, MoveIntent.Dir.DOWN, true, FIELD_SIDE - 1)
	eq(captures, 1, "a rota precisa fechar exatamente uma região, senão nada abaixo afirma algo")

	var field: Rect2 = vfx.field_rect()
	var focus: Rect2 = vfx.focus_rect
	# Faixa de 24 px (o piso `MIN_FOCUS_SIDE`) centrada na coluna desenhada, e não os 61 do campo.
	eq(focus.size, Vector2(QixCaptureVfx.MIN_FOCUS_SIDE, float(FIELD_SIDE - 2)))
	eq(focus.position, Vector2(25.5, 20.0))
	ok(focus.size.x < field.size.x, "o foco tem que ser mais estreito que o campo, senão não foca")
	eq(vfx.presentation_state()["focus_rect"], focus)

	var markers: PackedVector2Array = vfx.marker_positions()
	ok(markers.size() >= 4, "uma captura grande merece mais de uma marca")
	for marker in markers:
		ok(focus.has_point(marker), "marca em %s escapou do foco %s" % [marker, focus])
		ok(field.has_point(marker), "marca em %s escapou do campo %s" % [marker, field])

	# Invariante 8: a mesma rota sem VFX nenhum tem que terminar no mesmo checksum. Comparar o
	# estado antes e depois da rota não provaria nada — a simulação avança de propósito; o que se
	# afirma é que *observar* a trilha, tick a tick, não deixa rastro no domínio.
	var untouched := _simulation(FIELD_SIDE, FIELD_SIDE)
	eq(_draw(untouched, null, MoveIntent.Dir.DOWN, true, FIELD_SIDE - 1), 1)
	eq(simulation.state_checksum(), untouched.state_checksum(),
		"o VFX é estritamente observacional: a rota tem que fechar no mesmo checksum sem ele")
	eq(simulation.board.canonical_bytes(), untouched.board.canonical_bytes())
	vfx.free()


func test_the_focus_follows_the_next_trail_instead_of_sticking_to_the_previous_one() -> void:
	var simulation := _simulation(FIELD_SIDE, FIELD_SIDE)
	var vfx := QixCaptureVfx.new()
	eq(_draw(simulation, vfx, MoveIntent.Dir.DOWN, true, FIELD_SIDE - 1), 1)
	var first: Rect2 = vfx.focus_rect
	# Anda 15 células pela borda inferior sem desenhar e corta de baixo para cima.
	eq(_draw(simulation, vfx, MoveIntent.Dir.RIGHT, false, 15), 0)
	eq(_draw(simulation, vfx, MoveIntent.Dir.UP, true, FIELD_SIDE - 1), 1)
	var second: Rect2 = vfx.focus_rect
	eq(second.position, first.position + Vector2(15.0, 0.0), "o foco acompanha a coluna nova")
	for marker in vfx.marker_positions():
		ok(second.has_point(marker), "marca em %s ficou presa na captura anterior" % marker)
	vfx.free()


## O caso que a geometria literal quebrava: um campo autorado menor que os antigos 214×272.
func test_marks_stay_inside_an_authored_field_smaller_than_the_old_literals() -> void:
	for dimensions in [Vector2i(13, 9), Vector2i(9, 9), Vector2i(31, 17)]:
		var simulation := _simulation(dimensions.x, dimensions.y)
		var vfx := QixCaptureVfx.new()
		eq(_draw(simulation, vfx, MoveIntent.Dir.DOWN, true, dimensions.y - 1), 1,
			"campo %s precisa fechar uma região" % dimensions)
		var field: Rect2 = vfx.field_rect()
		for marker in vfx.marker_positions():
			ok(field.has_point(marker),
				"campo %s: marca em %s caiu fora da moldura %s" % [dimensions, marker, field])
		vfx.free()


## Sem trilha observada ainda, o recorte degrada para o campo inteiro — o comportamento antigo,
## e não um retângulo vazio que apagaria a floritura.
func test_without_an_observed_trail_the_flourish_degrades_to_the_whole_field() -> void:
	var simulation := _simulation(FIELD_SIDE, FIELD_SIDE)
	var vfx := QixCaptureVfx.new()
	var synthetic: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.CAPTURED, {
		"filled_delta": 900, "permille": 300,
	})]
	vfx.sync(simulation, synthetic)
	eq(vfx.focus_rect, vfx.field_rect())
	for marker in vfx.marker_positions():
		ok(vfx.field_rect().has_point(marker), "marca em %s fora do campo" % marker)
	vfx.free()


func _draw(
	simulation: GameSimulation,
	vfx: QixCaptureVfx,
	direction: int,
	drawing: bool,
	ticks: int,
) -> int:
	var captures := 0
	for _tick in ticks:
		var events := simulation.step(MoveIntent.make(direction, drawing))
		if vfx != null:
			vfx.sync(simulation, events)
		for event in events:
			if event.kind == GameEvent.Kind.CAPTURED:
				captures += 1
	return captures


## Chefe parado e escudo longo: o que está sob teste é a geometria da floritura, não o combate.
func _simulation(width: int, height: int) -> GameSimulation:
	var rules := GameRules.new()
	rules.substeps_normal = 1
	rules.substeps_speedup = 1
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.shield_ticks = 10_000
	var round_definition := RoundDefinition.new()
	round_definition.field_width = width
	round_definition.field_height = height
	@warning_ignore("integer_division")
	round_definition.player_spawn = Vector2i(width / 2, 0)
	@warning_ignore("integer_division")
	round_definition.boss_start = Vector2i(width - 3, height / 2)
	round_definition.boss_dir_index = 0
	return GameSimulation.new(rules, round_definition, 12345)
