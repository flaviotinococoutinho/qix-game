extends TestCase


func test_feedback_hub_runs_against_real_campaign_without_mutating_domain() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	var session := GameSession.new(campaign)
	var before := session.simulation.state_checksum()
	var replay_before := session.replay.to_bytes()
	var hub := QixFeedbackHub.new()
	hub.haptics.enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(hub)
	var events: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.CAPTURED, {"filled_delta": 200})]
	hub.sync(session, events, false)
	var state := hub.audio.presentation_state()
	eq(state["round_index"], 0)
	eq(state["music_loaded"], true)
	eq(state["voice_count"], QixAudioDirector.SFX_VOICES)
	eq(state["cached_music"], 1)
	eq(state["cached_cues"], 1)
	eq(session.simulation.state_checksum(), before)
	eq(session.replay.to_bytes(), replay_before)
	hub.sync(session, [], true)
	eq(hub.audio.presentation_state()["music_paused"], true)
	hub.free()


func test_touch_and_gamepad_paths_produce_identical_canonical_intent() -> void:
	var gamepad := GameInputAdapter.new()
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_Y
	axis.axis_value = -0.9
	gamepad.handle_event(axis)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	gamepad.handle_event(button)
	var from_gamepad := gamepad.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)

	var touch := QixTouchControls.new()
	touch.size = Vector2(240, 320)
	touch.handle_event(_touch(1, true, Vector2(52, 230)))
	touch.handle_event(_touch(2, true, Vector2(192, 266)))
	var touch_adapter := GameInputAdapter.new()
	touch_adapter.attach_touch_controls(touch)
	var from_touch := touch_adapter.sample_from_state(MoveIntent.Dir.NONE, false, false, false, false, false)
	eq(from_gamepad.to_byte(), from_touch.to_byte(), "dispositivos convergem antes de entrar no replay")
	touch.free()


func _touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event
