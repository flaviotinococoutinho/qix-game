extends TestCase
## O polegar tem a mesma trava de eixo que o stick analógico — e precisa dela mais.
##
## `analog_axis_lock_test.gd` (#38) decidiu que, sob ambiguidade, o eixo já sustentado continua
## valendo, e explicou o custo neste jogo: com `draw` apertado, cada troca de direção é um canto
## novo na trilha confirmada, e comprimento de trilha é a moeda que `TrailExposure` lê para
## acelerar o pulso e nomear o aviso do HUD. O canal de toque ficou de fora dessa decisão e
## continuou com `absf(x) > absf(y)` cru.
##
## Por que o toque é o pior lugar para essa falta: o hardware do gamepad manda um evento por eixo,
## mas o vidro manda `InputEventScreenDrag` **a cada quadro** enquanto o dedo estiver em campo, e o
## centroide de contato de um polegar oscila ~1,5 px sem que o jogador mexa. Medido em `main`
## antes desta mudança, com uma sonda de 60 quadros: um polegar *parado* a 45° da âncora trocava de
## eixo em **60 de 60 quadros**. Um segundo de dedo imóvel comprava 60 cantos de exposição.
##
## A correção não inventa regra nova: normaliza o deslocamento por `STICK_RADIUS` e chama
## `GameInputAdapter.resolve_analog_direction`. Uma regra, dois canais — se a margem for
## recalibrada, os dois se movem juntos.

const LAYOUT := Vector2(240.0, 320.0)
## Dentro da zona do stick (x ≤ 55 % da largura, y ≥ 48 % da altura) e longe da zona de ação.
const ANCHOR := Vector2(60.0, 240.0)


func _controls() -> QixTouchControls:
	var controls := QixTouchControls.new()
	controls.size = LAYOUT
	controls.clear_state()
	return controls


func _press(controls: QixTouchControls, position: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = position
	controls.handle_event(touch)


func _drag(controls: QixTouchControls, position: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = position
	controls.handle_event(drag)


func test_pousar_o_dedo_continua_nao_sendo_um_passo() -> void:
	# Contrato da âncora flutuante (#33): deslocamento zero nunca produz direção.
	var controls := _controls()
	_press(controls, ANCHOR)
	eq(controls.direction(), MoveIntent.Dir.NONE, "o quadro de contato não é um passo")
	controls.free()


func test_sem_direcao_sustentada_o_desempate_e_o_antigo() -> void:
	# O primeiro arrasto de um toque não muda de comportamento com esta mudança.
	eq(
		QixTouchControls.resolve_touch_direction(Vector2(30.0, 18.0), MoveIntent.Dir.NONE),
		MoveIntent.Dir.RIGHT,
		"x domina",
	)
	eq(
		QixTouchControls.resolve_touch_direction(Vector2(18.0, 30.0), MoveIntent.Dir.NONE),
		MoveIntent.Dir.DOWN,
		"y domina",
	)
	eq(
		QixTouchControls.resolve_touch_direction(Vector2(30.0, 30.0), MoveIntent.Dir.NONE),
		MoveIntent.Dir.DOWN,
		"empate exato continua vertical, como antes",
	)


func test_tremor_do_polegar_na_diagonal_nao_vira_canto() -> void:
	# É o caso medido: 60 de 60 quadros antes, nenhum depois.
	var controls := _controls()
	_press(controls, ANCHOR)
	var held := ANCHOR + Vector2(24.0, 24.0)
	_drag(controls, held)
	var sustained := controls.direction()
	ne(sustained, MoveIntent.Dir.NONE, "24/24 px está bem fora da zona morta de 11 px")

	var jitter := [1.4, -1.1, 0.8, -1.5, 1.2, -0.6, 1.5, -1.3, 0.9, -0.9, 1.1, -1.4]
	for index in 60:
		var dx: float = jitter[index % jitter.size()]
		var dy: float = jitter[(index + 5) % jitter.size()]
		_drag(controls, held + Vector2(dx, dy))
		eq(
			controls.direction(),
			sustained,
			"tremor de %.1f/%.1f px no quadro %d não pode virar um canto" % [dx, dy, index],
		)
	controls.free()


func test_virar_de_verdade_ainda_troca_o_eixo() -> void:
	var controls := _controls()
	_press(controls, ANCHOR)
	_drag(controls, ANCHOR + Vector2(2.0, 34.0))
	eq(controls.direction(), MoveIntent.Dir.DOWN, "descendo")

	# Gesto claro, não tremor: o polegar atravessa para o eixo horizontal.
	_drag(controls, ANCHOR + Vector2(34.0, 6.0))
	eq(controls.direction(), MoveIntent.Dir.RIGHT, "o jogador virou de verdade")
	controls.free()


func test_inverter_o_sentido_no_mesmo_eixo_e_imediato() -> void:
	# A margem compara módulos: RIGHT→LEFT não muda qual eixo domina, então não passa pela trava.
	var controls := _controls()
	_press(controls, ANCHOR)
	_drag(controls, ANCHOR + Vector2(34.0, 0.0))
	eq(controls.direction(), MoveIntent.Dir.RIGHT, "indo para a direita")

	_drag(controls, ANCHOR + Vector2(-34.0, 0.0))
	eq(controls.direction(), MoveIntent.Dir.LEFT, "meia-volta é sempre pedido explícito")
	controls.free()


func test_voltar_para_a_zona_morta_continua_zerando() -> void:
	var controls := _controls()
	_press(controls, ANCHOR)
	_drag(controls, ANCHOR + Vector2(34.0, 0.0))
	ne(controls.direction(), MoveIntent.Dir.NONE, "polegar em campo")

	_drag(controls, ANCHOR + Vector2(4.0, 0.0))
	eq(
		controls.direction(),
		MoveIntent.Dir.NONE,
		"dentro de STICK_DEAD_ZONE a direção some, com trava ou sem",
	)
	controls.free()


func test_a_zona_morta_garante_que_virar_continua_alcancavel() -> void:
	## Trava firme demais seria um jogo que não obedece. O menor deslocamento válido normalizado é
	## `STICK_DEAD_ZONE / STICK_RADIUS`; para o eixo perpendicular ser alcançável, ele precisa
	## superar a margem — senão existiria um anel onde o polegar não consegue virar de jeito nenhum.
	var smallest := QixTouchControls.STICK_DEAD_ZONE / QixTouchControls.STICK_RADIUS
	ok(
		smallest > GameInputAdapter.ANALOG_AXIS_SWITCH_MARGIN,
		"deslocamento mínimo %.4f precisa superar a margem %.4f" % [
			smallest, GameInputAdapter.ANALOG_AXIS_SWITCH_MARGIN,
		],
	)

	# E de facto: perpendicular puro no limite da zona morta troca o eixo.
	eq(
		QixTouchControls.resolve_touch_direction(
			Vector2(0.0, QixTouchControls.STICK_DEAD_ZONE + 0.5), MoveIntent.Dir.RIGHT
		),
		MoveIntent.Dir.DOWN,
		"o menor gesto perpendicular válido ainda vira",
	)


func test_o_limite_de_curso_impede_que_a_trava_evapore_num_arrasto_longo() -> void:
	## Um stick físico para no fim de curso; o vidro não. Sem `limit_length(1.0)` um arrasto de
	## 300 px encolheria a margem efetiva a ~0,03° e a trava desapareceria exatamente onde o dedo
	## já está fora da moldura desenhada.
	var far := Vector2(300.0, 300.0 + 20.0)
	eq(
		QixTouchControls.resolve_touch_direction(far, MoveIntent.Dir.RIGHT),
		MoveIntent.Dir.RIGHT,
		"a 300 px, 20 px de diferença entre eixos ainda é ambiguidade, não gesto",
	)
