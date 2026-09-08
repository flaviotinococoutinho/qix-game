extends TestCase
## F1 — latch de toque, SOCD "último pressionado vence", buffer de curva e fallback no
## GameInputAdapter. Tudo por contagem de ticks (`begin_tick`) e eventos sintéticos do
## InputMap; nada aqui toca o domínio além de ler o byte do MoveIntent resultante.
##
## Convenção de tempo: um evento tratado "no contador N" chegou depois da amostra N e antes de
## `begin_tick` N+1, que é quando o bootstrap o vê — exatamente a janela de um toque sub-tick.

const UP := MoveIntent.Dir.UP
const RIGHT := MoveIntent.Dir.RIGHT
const DOWN := MoveIntent.Dir.DOWN
const LEFT := MoveIntent.Dir.LEFT
const NONE := MoveIntent.Dir.NONE


func test_sub_tick_key_tap_is_latched_into_the_next_sample() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_W, true))
	adapter.handle_event(_key(KEY_W, false))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(NONE, false, false, false, false, false)
	eq(intent.direction, UP, "press e release entre duas amostras contam na amostra seguinte")
	adapter.begin_tick()
	intent = adapter.sample_from_state(NONE, false, false, false, false, false)
	eq(intent.direction, NONE, "o latch dura TAP_LATCH_TICKS e não vira tecla presa")


func test_sub_tick_gamepad_button_tap_and_draw_tap_are_latched() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_joy_button(JOY_BUTTON_DPAD_RIGHT, true))
	adapter.handle_event(_joy_button(JOY_BUTTON_DPAD_RIGHT, false))
	adapter.handle_event(_key(KEY_SPACE, true))
	adapter.handle_event(_key(KEY_SPACE, false))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(NONE, false, false, false, false, false)
	eq(intent.direction, RIGHT, "botão de gamepad mapeado no InputMap também latcha")
	ok(intent.drawing, "toque curto em draw conta no tick seguinte")
	adapter.begin_tick()
	intent = adapter.sample_from_state(NONE, false, false, false, false, false)
	eq(intent.direction, NONE)
	ok(not intent.drawing)


func test_latched_tap_expires_when_no_sample_consumes_it() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_W, true))
	adapter.handle_event(_key(KEY_W, false))
	adapter.begin_tick()
	adapter.begin_tick()
	var intent := adapter.sample_from_state(NONE, false, false, false, false, false)
	eq(intent.direction, NONE, "um toque durante a pausa não dispara ao despausar")


func test_key_echo_does_not_register_a_new_press() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	adapter.sample_from_state(NONE, false, true, false, false, false)
	adapter.handle_event(_key(KEY_A, true))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(RIGHT, false, true, false, true, false)
	eq(intent.direction, LEFT, "LEFT é o press mais recente")
	var echo := _key(KEY_D, true)
	echo.echo = true
	adapter.handle_event(echo)
	adapter.begin_tick()
	intent = adapter.sample_from_state(LEFT, false, true, false, true, false)
	eq(intent.direction, LEFT, "echo de RIGHT não conta como novo press")


func test_socd_last_pressed_wins_on_both_axes() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(NONE, false, true, false, false, false)
	eq(intent.direction, RIGHT)
	adapter.handle_event(_key(KEY_A, true))
	adapter.begin_tick()
	intent = adapter.sample_from_state(RIGHT, false, true, false, true, false)
	eq(intent.direction, LEFT, "LEFT pressionado depois vence RIGHT mantido, mesmo com pdir RIGHT")
	eq(intent.fallback, RIGHT, "a direção mantida vira fallback")
	adapter.handle_event(_key(KEY_A, false))
	adapter.begin_tick()
	intent = adapter.sample_from_state(LEFT, false, true, false, false, false)
	eq(intent.direction, RIGHT, "soltar LEFT devolve RIGHT sem novo press")

	adapter.handle_event(_key(KEY_W, true))
	adapter.begin_tick()
	intent = adapter.sample_from_state(RIGHT, true, true, false, false, false)
	eq(intent.direction, UP, "perpendicular pressionada depois de pdir entra como curva")
	adapter.handle_event(_key(KEY_S, true))
	adapter.begin_tick()
	intent = adapter.sample_from_state(UP, true, true, true, false, false)
	eq(intent.direction, DOWN, "DOWN pressionado depois vence UP mantido no eixo vertical")
	adapter.handle_event(_key(KEY_S, false))
	adapter.begin_tick()
	intent = adapter.sample_from_state(DOWN, true, true, false, false, false)
	eq(intent.direction, UP, "soltar DOWN devolve UP mantido")


func test_simultaneous_polled_presses_tie_and_keep_canonical_order() -> void:
	var adapter := GameInputAdapter.new()
	adapter.begin_tick()
	var intent := adapter.sample_from_state(NONE, false, true, false, true, false)
	eq(intent.direction, RIGHT, "sem ordem entre presses, a ordem canônica decide")
	intent = adapter.sample_from_state(LEFT, false, true, false, true, false)
	eq(intent.direction, LEFT, "empate de sequência mantém a preferida")


func test_older_perpendicular_press_does_not_hijack_the_current_direction() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_W, true))
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(RIGHT, true, true, false, false, false)
	eq(intent.direction, RIGHT, "UP foi pressionado antes de RIGHT: pdir RIGHT é a intenção mais nova")
	eq(intent.fallback, UP)


func test_turn_buffer_keeps_the_tapped_turn_primary_until_pdir_becomes_it() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	adapter.sample_from_state(NONE, false, true, false, false, false)
	adapter.handle_event(_key(KEY_W, true))
	adapter.handle_event(_key(KEY_W, false))
	for tick in range(1, GameInputAdapter.TURN_BUFFER_TICKS + 1):
		adapter.begin_tick()
		var intent := adapter.sample_from_state(RIGHT, false, true, false, false, false)
		eq(intent.direction, UP, "tick %d: a curva tocada continua primária enquanto pdir é RIGHT" % tick)
		eq(intent.fallback, RIGHT, "tick %d: a direção mantida desliza como fallback" % tick)
	adapter.begin_tick()
	var turned := adapter.sample_from_state(UP, false, true, false, false, false)
	eq(turned.direction, RIGHT, "pdir virou UP: o buffer foi consumido e RIGHT mantido volta")
	eq(turned.fallback, NONE, "sem buffer ativo e sem segunda direção mantida não há fallback")
	adapter.begin_tick()
	var again := adapter.sample_from_state(RIGHT, false, true, false, false, false)
	eq(again.direction, RIGHT, "o press consumido não pede a curva de novo")


func test_turn_buffer_expires_after_six_ticks() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	adapter.sample_from_state(NONE, false, true, false, false, false)
	adapter.handle_event(_key(KEY_W, true))
	adapter.handle_event(_key(KEY_W, false))
	for _tick in GameInputAdapter.TURN_BUFFER_TICKS:
		adapter.begin_tick()
		adapter.sample_from_state(RIGHT, false, true, false, false, false)
	adapter.begin_tick()
	var expired := adapter.sample_from_state(RIGHT, false, true, false, false, false)
	eq(expired.direction, RIGHT, "depois de TURN_BUFFER_TICKS a curva não executada é esquecida")
	eq(expired.fallback, NONE)


func test_fallback_is_the_other_held_direction() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	adapter.sample_from_state(NONE, false, true, false, false, false)
	adapter.handle_event(_key(KEY_W, true))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(RIGHT, true, true, false, false, false)
	eq(intent.direction, UP, "UP mantido e mais recente pede a curva")
	eq(intent.fallback, RIGHT, "RIGHT mantido é o fallback")
	for _tick in GameInputAdapter.TURN_BUFFER_TICKS:
		adapter.begin_tick()
		intent = adapter.sample_from_state(RIGHT, true, true, false, false, false)
	eq(intent.direction, RIGHT, "buffer expirado: pdir mantido volta a ser primária")
	eq(intent.fallback, UP, "sem buffer, a segunda direção mantida é o fallback")


func test_fallback_remembers_a_direction_released_up_to_four_ticks_ago() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	adapter.sample_from_state(NONE, false, true, false, false, false)
	# O dedo sai de RIGHT e entra em UP no mesmo intervalo: a curva fica primária e o RIGHT
	# recém-solto continua deslizando o jogador até a curva ser legal.
	adapter.handle_event(_key(KEY_D, false))
	adapter.handle_event(_key(KEY_W, true))
	for tick in range(1, GameInputAdapter.RELEASE_MEMORY_TICKS + 2):
		adapter.begin_tick()
		var intent := adapter.sample_from_state(RIGHT, true, false, false, false, false)
		eq(intent.direction, UP, "tick %d: a curva pedida é primária" % tick)
		eq(intent.fallback, RIGHT, "tick %d: RIGHT solto há ≤ %d ticks ainda é fallback" % [tick, GameInputAdapter.RELEASE_MEMORY_TICKS])
	adapter.begin_tick()
	var forgotten := adapter.sample_from_state(RIGHT, true, false, false, false, false)
	eq(forgotten.direction, UP)
	eq(forgotten.fallback, NONE, "passada a memória de release, a direção solta é esquecida")


func test_released_direction_is_not_a_fallback_without_an_active_turn_buffer() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	adapter.sample_from_state(NONE, false, true, false, false, false)
	adapter.handle_event(_key(KEY_D, false))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(RIGHT, false, false, false, false, false)
	eq(intent.direction, NONE)
	eq(intent.fallback, NONE, "soltar tudo parado não inventa movimento")


func test_fallback_is_never_equal_to_the_primary() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_W, true))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(NONE, true, false, false, false, false)
	eq(intent.direction, UP)
	eq(intent.fallback, NONE, "uma única direção mantida não vira fallback de si mesma")
	adapter.begin_tick()
	intent = adapter.sample_from_state(RIGHT, true, false, false, false, false)
	eq(intent.direction, UP, "UP mantido é a curva pedida em relação a pdir RIGHT")
	ne(intent.fallback, intent.direction, "fallback nunca repete a primária")
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	intent = adapter.sample_from_state(RIGHT, true, true, false, false, false)
	ne(intent.fallback, intent.direction)
	ok(intent.fallback == NONE or MoveIntent.is_valid_dir(intent.fallback))


func test_resulting_intent_byte_carries_primary_draw_and_fallback() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	adapter.sample_from_state(NONE, false, true, false, false, false)
	adapter.handle_event(_key(KEY_W, true))
	adapter.begin_tick()
	var intent := adapter.sample_from_state(RIGHT, true, true, false, false, true)
	eq(intent.to_byte(), (UP & 0x7) | 0x8 | (RIGHT << 4), "bits 0-2 primária, bit 3 draw, bits 4-6 fallback")
	var restored := MoveIntent.from_byte(intent.to_byte())
	eq(restored.direction, UP)
	eq(restored.fallback, RIGHT)
	ok(restored.drawing)


func test_reset_transient_state_drops_latches_buffer_and_release_memory() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_key(KEY_D, true))
	adapter.begin_tick()
	adapter.sample_from_state(NONE, false, true, false, false, false)
	adapter.handle_event(_key(KEY_W, true))
	adapter.handle_event(_key(KEY_W, false))
	adapter.reset_transient_state()
	adapter.begin_tick()
	var intent := adapter.sample_from_state(RIGHT, false, false, false, false, false)
	eq(intent.direction, NONE, "restart/focus loss não transporta latch nem buffer")
	eq(intent.fallback, NONE, "nem memória de release")


func test_static_choose_direction_keeps_the_sequence_free_contract() -> void:
	eq(GameInputAdapter.choose_direction(true, true, true, true, LEFT), LEFT)
	eq(GameInputAdapter.choose_direction(true, true, false, false, DOWN), UP)
	eq(
		GameInputAdapter.choose_direction_with_sequence(true, true, false, false, UP, 1, 2, 0, 0),
		UP,
		"preferida pressionada e não revertida continua vencendo perpendiculares mais novas",
	)
	eq(
		GameInputAdapter.choose_direction_with_sequence(false, true, false, true, RIGHT, 0, 1, 0, 2),
		LEFT,
		"oposta mais recente reverte a preferida",
	)
	eq(
		GameInputAdapter.choose_direction_with_sequence(true, false, false, true, NONE, 1, 0, 0, 2),
		LEFT,
		"sem preferida vence a maior sequência",
	)


func _key(physical: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.pressed = pressed
	return event


func _joy_button(button_index: int, pressed: bool, device: int = 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button_index
	event.pressed = pressed
	return event
