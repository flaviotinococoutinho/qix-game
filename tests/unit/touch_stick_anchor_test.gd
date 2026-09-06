extends TestCase
## O stick de toque ancora onde o dedo pousa.
##
## O teste que já existia (`shipping_input_test.gd`) pressiona exatamente em (52, 266) — o centro
## de descanso — e por isso nunca viu o defeito: com centro fixo, a zona de ancoragem inteira
## menos um disco de 11 px devolvia direção no próprio toque. Estes casos pousam o dedo onde um
## polegar realmente pousa.


func _touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event


func _drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	return event


func _controls() -> QixTouchControls:
	var touch := QixTouchControls.new()
	touch.size = Vector2(240, 320)
	return touch


func test_pousar_o_dedo_em_qualquer_ponto_da_zona_nao_pede_direcao() -> void:
	var touch := _controls()
	# Cantos e meio da zona de ancoragem (x <= 132, y >= 153.6) no campo de referência 240×320.
	# Com centro fixo estes quatro davam RIGHT, UP, UP e LEFT no instante do contato.
	for position in [
		Vector2(120, 300),
		Vector2(20, 200),
		Vector2(120, 160),
		Vector2(4, 316),
		Vector2(52, 266),
	]:
		touch.clear_state()
		ok(touch.handle_event(_touch(3, true, position)), "a zona aceita o toque em %s" % position)
		eq(
			touch.direction(),
			MoveIntent.Dir.NONE,
			"pousar em %s não é um passo que o jogador pediu" % position,
		)
		eq(touch.presentation_state()["stick_origin"], position, "a âncora é o ponto de pouso")
	touch.free()


func test_a_direcao_nasce_do_arrasto_a_partir_da_ancora_nao_do_canto() -> void:
	var touch := _controls()
	var origin := Vector2(120, 300)
	touch.handle_event(_touch(3, true, origin))
	# Arrasto curto dentro da zona morta: ainda não é intenção.
	touch.handle_event(_drag(3, origin + Vector2(7, 0)))
	eq(touch.direction(), MoveIntent.Dir.NONE, "abaixo da zona morta continua sem direção")
	# Passado o limiar, a direção é a do deslocamento — e não a do vetor até (52, 266).
	touch.handle_event(_drag(3, origin + Vector2(24, 0)))
	eq(touch.direction(), MoveIntent.Dir.RIGHT)
	touch.handle_event(_drag(3, origin + Vector2(-24, 0)))
	eq(touch.direction(), MoveIntent.Dir.LEFT, "âncora fixa daria RIGHT: (96,300) fica à direita de (52,266)")
	touch.handle_event(_drag(3, origin + Vector2(0, -24)))
	eq(touch.direction(), MoveIntent.Dir.UP)
	touch.handle_event(_drag(3, origin + Vector2(0, 24)))
	eq(touch.direction(), MoveIntent.Dir.DOWN, "âncora fixa daria UP: (120,276) fica acima de (120,300)")
	touch.free()


func test_soltar_devolve_a_ancora_ao_canto_de_descanso() -> void:
	var touch := _controls()
	touch.handle_event(_touch(3, true, Vector2(20, 200)))
	touch.handle_event(_drag(3, Vector2(60, 200)))
	eq(touch.direction(), MoveIntent.Dir.RIGHT)
	touch.handle_event(_touch(3, false, Vector2(60, 200)))
	eq(touch.direction(), MoveIntent.Dir.NONE)
	eq(
		touch.presentation_state()["stick_origin"],
		Vector2(52, 320 - 54),
		"sem dedo em campo o anel volta a desenhar no canto de descanso",
	)
	touch.free()


func test_a_ancora_e_do_primeiro_dedo_um_segundo_toque_na_zona_nao_a_move() -> void:
	var touch := _controls()
	var origin := Vector2(20, 200)
	touch.handle_event(_touch(3, true, origin))
	ok(not touch.handle_event(_touch(4, true, Vector2(120, 300))), "a zona já tem dono")
	eq(touch.presentation_state()["stick_origin"], origin)
	touch.handle_event(_drag(3, origin + Vector2(30, 0)))
	eq(touch.direction(), MoveIntent.Dir.RIGHT, "o arrasto do dono continua medido da âncora dele")
	touch.free()
