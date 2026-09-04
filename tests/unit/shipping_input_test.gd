extends TestCase


func test_touch_overlay_scene_is_game_ready_at_reference_viewport() -> void:
	var packed := load("res://ui/touch/touch_controls.tscn") as PackedScene
	ok(packed != null)
	if packed == null:
		return
	var touch := packed.instantiate() as QixTouchControls
	ok(touch != null)
	eq(touch.size, Vector2(240, 320))
	eq(touch.z_index, 35)
	touch.free()


func test_gamepad_stick_and_buttons_are_translated_without_input_map_mutation() -> void:
	var adapter := GameInputAdapter.new()
	var horizontal := InputEventJoypadMotion.new()
	horizontal.axis = JOY_AXIS_LEFT_X
	horizontal.axis_value = 0.82
	adapter.handle_event(horizontal)
	var intent := adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(intent.direction, MoveIntent.Dir.RIGHT)
	eq(intent.drawing, false)

	var draw_down := InputEventJoypadButton.new()
	draw_down.button_index = JOY_BUTTON_A
	draw_down.pressed = true
	adapter.handle_event(draw_down)
	intent = adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(intent.direction, MoveIntent.Dir.RIGHT)
	eq(intent.drawing, true)
	ok(adapter.consume_confirm(), "A confirma transições e mantém draw durante gameplay")
	ok(not adapter.consume_confirm(), "confirm é edge-triggered")

	var pause_down := InputEventJoypadButton.new()
	pause_down.button_index = JOY_BUTTON_START
	pause_down.pressed = true
	adapter.handle_event(pause_down)
	ok(adapter.consume_pause())
	ok(not adapter.consume_pause())


func test_gamepad_deadzone_dpad_and_preferred_direction_are_stable() -> void:
	var adapter := GameInputAdapter.new()
	var horizontal := InputEventJoypadMotion.new()
	horizontal.axis = JOY_AXIS_LEFT_X
	horizontal.axis_value = 0.2
	adapter.handle_event(horizontal)
	var intent := adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(intent.direction, MoveIntent.Dir.NONE)

	var dpad_up := InputEventJoypadButton.new()
	dpad_up.button_index = JOY_BUTTON_DPAD_UP
	dpad_up.pressed = true
	adapter.handle_event(dpad_up)
	var dpad_right := InputEventJoypadButton.new()
	dpad_right.button_index = JOY_BUTTON_DPAD_RIGHT
	dpad_right.pressed = true
	adapter.handle_event(dpad_right)
	intent = adapter.sample_from_state(MoveIntent.Dir.RIGHT, false, false, false, false, false)
	eq(intent.direction, MoveIntent.Dir.RIGHT)


func test_multiple_gamepads_keep_independent_sticks_and_held_buttons() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_joy_motion(1, JOY_AXIS_LEFT_X, 0.9))
	adapter.handle_event(_joy_motion(2, JOY_AXIS_LEFT_X, -0.9))
	var intent := adapter.sample_from_state(
		MoveIntent.Dir.NONE,
		false,
		false,
		false,
		false,
		false,
	)
	eq(intent.direction, MoveIntent.Dir.RIGHT, "conflito entre devices usa a ordem canônica")
	intent = adapter.sample_from_state(MoveIntent.Dir.LEFT, false, false, false, false, false)
	eq(intent.direction, MoveIntent.Dir.LEFT, "direção já ativa continua preferida entre devices")

	adapter.handle_event(_joy_motion(2, JOY_AXIS_LEFT_X, 0.0))
	intent = adapter.sample_from_state(
		MoveIntent.Dir.NONE,
		false,
		false,
		false,
		false,
		false,
	)
	eq(intent.direction, MoveIntent.Dir.RIGHT, "neutral do controle B não apaga stick do A")

	adapter.handle_event(_joy_button(1, JOY_BUTTON_A, true))
	adapter.handle_event(_joy_button(2, JOY_BUTTON_A, true))
	adapter.handle_event(_joy_button(2, JOY_BUTTON_A, false))
	intent = adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	ok(intent.drawing, "soltar A no controle B não solta o botão ainda pressionado no A")
	adapter.handle_event(_joy_button(1, JOY_BUTTON_A, false))
	intent = adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	ok(not intent.drawing, "draw termina quando o último controle solta o botão")


func test_disconnect_removes_only_that_gamepads_state_and_edges() -> void:
	var adapter := GameInputAdapter.new()
	adapter.handle_event(_joy_motion(10, JOY_AXIS_LEFT_Y, -0.9))
	adapter.handle_event(_joy_button(10, JOY_BUTTON_A, true))
	adapter.handle_event(_joy_button(10, JOY_BUTTON_START, true))
	adapter.handle_event(_joy_motion(20, JOY_AXIS_LEFT_X, 0.9))
	adapter.handle_event(_joy_button(20, JOY_BUTTON_A, true))
	adapter.handle_event(_joy_button(20, JOY_BUTTON_START, true))

	adapter.handle_joy_connection_changed(20, false)
	var held := adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(held.direction, MoveIntent.Dir.UP, "disconnect de B mantém o stick do controle A")
	ok(held.drawing, "disconnect de B mantém o draw pressionado no controle A")
	ok(adapter.consume_confirm(), "edge de confirmação do controle A sobrevive ao disconnect de B")
	ok(adapter.consume_pause(), "edge de pausa do controle A sobrevive ao disconnect de B")

	adapter.handle_joy_connection_changed(10, false)
	held = adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(held.direction, MoveIntent.Dir.NONE)
	ok(not held.drawing)

	var only_b := GameInputAdapter.new()
	only_b.handle_event(_joy_button(20, JOY_BUTTON_A, true))
	only_b.handle_event(_joy_button(20, JOY_BUTTON_START, true))
	only_b.handle_joy_connection_changed(20, false)
	ok(not only_b.consume_confirm(), "disconnect descarta apenas o confirm enfileirado pelo device removido")
	ok(not only_b.consume_pause(), "disconnect descarta apenas o pause enfileirado pelo device removido")


func test_gamepad_disconnect_and_reset_release_all_raw_state() -> void:
	var adapter := GameInputAdapter.new()
	ok(adapter.has_method("handle_joy_connection_changed"), "adapter precisa expor reset explícito de desconexão")
	if not adapter.has_method("handle_joy_connection_changed"):
		return
	var axis := InputEventJoypadMotion.new()
	axis.device = 0
	axis.axis = JOY_AXIS_LEFT_Y
	axis.axis_value = -0.9
	adapter.handle_event(axis)
	var draw := InputEventJoypadButton.new()
	draw.device = 0
	draw.button_index = JOY_BUTTON_A
	draw.pressed = true
	adapter.handle_event(draw)
	var held := adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(held.direction, MoveIntent.Dir.UP)
	ok(held.drawing)

	adapter.handle_joy_connection_changed(0, false)
	var released := adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(released.direction, MoveIntent.Dir.NONE)
	ok(not released.drawing)
	ok(not adapter.consume_confirm(), "desconexão descarta edges que pertenciam ao device removido")

	axis.device = 1
	axis.axis_value = 0.9
	adapter.handle_event(axis)
	draw.device = 2
	draw.button_index = JOY_BUTTON_X
	adapter.handle_event(draw)
	adapter.handle_event(_joy_button(3, JOY_BUTTON_A, true))
	adapter.handle_event(_joy_button(2, JOY_BUTTON_START, true))
	adapter.reset_transient_state()
	released = adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(released.direction, MoveIntent.Dir.NONE, "restart/focus loss não transporta stick")
	ok(not released.drawing, "restart/focus loss não transporta botão")
	ok(not adapter.consume_confirm(), "reset global descarta confirm de todos os devices")
	ok(not adapter.consume_pause(), "reset global também descarta edges de todos os devices")


func test_touch_controls_support_stick_draw_confirm_pause_and_multitouch() -> void:
	var touch := QixTouchControls.new()
	touch.size = Vector2(240, 320)

	var stick_down := _touch_event(7, true, Vector2(52, 266))
	touch.handle_event(stick_down)
	var stick_drag := InputEventScreenDrag.new()
	stick_drag.index = 7
	stick_drag.position = Vector2(88, 266)
	touch.handle_event(stick_drag)
	eq(touch.direction(), MoveIntent.Dir.RIGHT)

	var draw_down := _touch_event(8, true, Vector2(192, 266))
	touch.handle_event(draw_down)
	ok(touch.is_drawing())
	ok(touch.consume_confirm(), "botão de ação também confirma overlays")
	ok(not touch.consume_confirm())

	var draw_up := _touch_event(8, false, Vector2(192, 266))
	touch.handle_event(draw_up)
	ok(not touch.is_drawing())
	eq(touch.direction(), MoveIntent.Dir.RIGHT, "soltar draw não interrompe o stick de outro dedo")

	var pause_down := _touch_event(9, true, Vector2(214, 22))
	touch.handle_event(pause_down)
	ok(touch.consume_pause())
	ok(not touch.consume_pause())

	var stick_up := _touch_event(7, false, Vector2(88, 266))
	touch.handle_event(stick_up)
	eq(touch.direction(), MoveIntent.Dir.NONE)
	touch.free()


func test_adapter_merges_touch_with_keyboard_snapshot_and_keeps_domain_intent_only() -> void:
	var touch := QixTouchControls.new()
	touch.size = Vector2(240, 320)
	touch.handle_event(_touch_event(1, true, Vector2(52, 266)))
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(52, 226)
	touch.handle_event(drag)
	touch.handle_event(_touch_event(2, true, Vector2(192, 266)))
	var adapter := GameInputAdapter.new()
	adapter.attach_touch_controls(touch)
	var intent := adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(intent.direction, MoveIntent.Dir.UP)
	eq(intent.drawing, true)
	touch.free()


func _touch_event(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event


func _joy_motion(device: int, axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event


func _joy_button(device: int, button_index: int, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button_index
	event.pressed = pressed
	return event
