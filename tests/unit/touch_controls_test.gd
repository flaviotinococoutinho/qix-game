extends TestCase
## F1 — sensação do stick touch: origem flutuante, histerese de magnitude e de setor, flick de
## um tick. Layout de referência 240×320: centro padrão do stick em (52, 266), anel de 42 px.

const UP := MoveIntent.Dir.UP
const RIGHT := MoveIntent.Dir.RIGHT
const DOWN := MoveIntent.Dir.DOWN
const LEFT := MoveIntent.Dir.LEFT
const NONE := MoveIntent.Dir.NONE
const HOME := Vector2(52.0, 266.0)
## Fora do anel (≈ 46,7 px do centro padrão) mas dentro da zona esquerda do stick.
const FLOATING_ORIGIN := Vector2(20.0, 300.0)


func test_stick_floats_to_the_initial_touch_outside_the_ring() -> void:
	var touch := _controls()
	touch.handle_event(_touch(1, true, FLOATING_ORIGIN))
	eq(touch.direction(), NONE, "o toque inicial fora do anel não tem direção: ele é o novo centro")
	eq(touch.presentation_state()["stick_center"], FLOATING_ORIGIN)
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(20.0, 0.0)))
	eq(touch.direction(), RIGHT, "o arrasto é medido a partir do ponto do toque, não do centro padrão")
	touch.handle_event(_touch(1, false, FLOATING_ORIGIN + Vector2(20.0, 0.0)))
	eq(touch.direction(), NONE)
	eq(touch.presentation_state()["stick_center"], HOME, "ao soltar o centro volta ao padrão")
	touch.free()


func test_touch_inside_the_ring_keeps_the_drawn_center_as_a_dpad() -> void:
	var touch := _controls()
	touch.handle_event(_touch(1, true, HOME + Vector2(0.0, -36.0)))
	eq(touch.direction(), NONE, "pousar dentro do anel também não move o jogador")
	eq(touch.presentation_state()["stick_center"], HOME + Vector2(0.0, -36.0))
	touch.handle_event(_drag(1, HOME + Vector2(0.0, -60.0)))
	eq(touch.direction(), UP, "o arrasto após pousar é que pede direção")
	touch.free()


func test_magnitude_hysteresis_enters_at_engage_radius_and_leaves_below_release_radius() -> void:
	var touch := _controls()
	touch.handle_event(_touch(1, true, FLOATING_ORIGIN))
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(10.0, 0.0)))
	eq(touch.direction(), NONE, "10 px ainda não entra")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(11.0, 0.0)))
	eq(touch.direction(), RIGHT, "11 px entra")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(8.0, 0.0)))
	eq(touch.direction(), RIGHT, "8 px mantém a cardinal ativa")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(7.0, 0.0)))
	eq(touch.direction(), RIGHT, "7 px ainda mantém")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(6.0, 0.0)))
	eq(touch.direction(), NONE, "abaixo de 7 px solta")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(10.0, 0.0)))
	eq(touch.direction(), NONE, "depois de soltar é preciso voltar a 11 px para entrar")
	touch.free()


func test_cardinal_switch_needs_ten_degrees_past_the_diagonal() -> void:
	var touch := _controls()
	touch.handle_event(_touch(1, true, FLOATING_ORIGIN))
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(20.0, 0.0)))
	eq(touch.direction(), RIGHT)
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(20.0, -20.0)))
	eq(touch.direction(), RIGHT, "exatamente na diagonal a cardinal ativa fica")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(20.0, -26.0)))
	eq(touch.direction(), RIGHT, "52° do eixo horizontal ainda é RIGHT (limite 55°)")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(20.0, -30.0)))
	eq(touch.direction(), UP, "56° passa a histerese e troca para UP")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(20.0, -26.0)))
	eq(touch.direction(), UP, "voltar a 52° não devolve RIGHT: a histerese vale nos dois sentidos")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(20.0, -12.0)))
	eq(touch.direction(), RIGHT, "59° do eixo vertical devolve RIGHT")
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(-20.0, 0.0)))
	eq(touch.direction(), LEFT, "reversão pelo centro troca de cardinal na hora")
	touch.handle_event(_touch(1, false, FLOATING_ORIGIN + Vector2(-20.0, 0.0)))
	touch.handle_event(_touch(1, true, FLOATING_ORIGIN))
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(20.0, -26.0)))
	eq(touch.direction(), UP, "sem cardinal ativa vale a diagonal simples: 52° é UP")
	touch.free()


func test_flick_shorter_than_a_tick_is_delivered_exactly_once() -> void:
	var touch := _controls()
	touch.handle_event(_touch(1, true, HOME))
	touch.handle_event(_drag(1, HOME + Vector2(0.0, -40.0)))
	touch.handle_event(_touch(1, false, HOME + Vector2(0.0, -40.0)))
	eq(touch.direction(), NONE, "o stick já foi solto")
	eq(touch.consume_flick_direction(), UP, "a direção que ninguém amostrou sobrevive como flick")
	eq(touch.consume_flick_direction(), NONE, "o flick é entregue uma vez só")

	touch.handle_event(_touch(1, true, HOME))
	touch.handle_event(_drag(1, HOME + Vector2(40.0, 0.0)))
	eq(touch.direction(), RIGHT, "amostrado")
	touch.handle_event(_touch(1, false, HOME + Vector2(40.0, 0.0)))
	eq(touch.consume_flick_direction(), NONE, "direção já observada não gera flick")
	touch.free()


func test_adapter_latches_a_touch_flick_for_one_sample() -> void:
	var touch := _controls()
	var adapter := GameInputAdapter.new()
	adapter.attach_touch_controls(touch)
	touch.handle_event(_touch(1, true, HOME))
	touch.handle_event(_drag(1, HOME + Vector2(-40.0, 0.0)))
	touch.handle_event(_touch(1, false, HOME + Vector2(-40.0, 0.0)))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(NONE, false, false, false, false, false)
	eq(intent.direction, LEFT, "flick vira um press latched no adaptador")
	adapter.begin_tick()
	intent = adapter.sample_from_state(NONE, false, false, false, false, false)
	eq(intent.direction, NONE, "e dura um tick, como um toque de tecla")
	touch.free()


func test_clear_state_drops_flick_and_floating_origin() -> void:
	var touch := _controls()
	touch.handle_event(_touch(1, true, FLOATING_ORIGIN))
	touch.handle_event(_drag(1, FLOATING_ORIGIN + Vector2(0.0, 20.0)))
	touch.clear_state()
	eq(touch.direction(), NONE)
	eq(touch.consume_flick_direction(), NONE, "clear_state não deixa flick pendente")
	eq(touch.presentation_state()["stick_center"], HOME)
	touch.free()


func _controls() -> QixTouchControls:
	var touch := QixTouchControls.new()
	touch.size = Vector2(240, 320)
	return touch


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
