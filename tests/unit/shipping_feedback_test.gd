extends TestCase


func test_procedural_cues_are_deterministic_small_pcm_streams() -> void:
	var first := QixProceduralAudioLibrary.cue(&"capture")
	var second := QixProceduralAudioLibrary.cue(&"capture")
	ok(first is AudioStreamWAV)
	eq(first.mix_rate, QixProceduralAudioLibrary.MIX_RATE)
	eq(first.format, AudioStreamWAV.FORMAT_16_BITS)
	ok(first.data.size() > 1000)
	ok(first.data.size() < 64 * 1024, "SFX procedural deve permanecer pequeno")
	eq(first.data, second.data, "síntese não usa estado global nem RNG")
	var peak := 0
	for offset in range(0, first.data.size(), 2):
		peak = maxi(peak, absi(first.data.decode_s16(offset)))
	ok(peak > 4000, "cue audível")
	ok(peak < 32767, "headroom evita clipping antes do limiter")


func test_music_is_original_loopable_and_varies_by_round() -> void:
	var abyss := QixProceduralAudioLibrary.music_for_round(0)
	var aurora := QixProceduralAudioLibrary.music_for_round(1)
	eq(abyss.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	eq(abyss.loop_begin, 0)
	var frame_count := abyss.data.size() / 2
	var authored_frame_count := int(round(60.0 / 108.0 * QixProceduralAudioLibrary.MUSIC_BEATS * QixProceduralAudioLibrary.MIX_RATE))
	eq(
		frame_count,
		authored_frame_count + 1,
		"o PCM inclui um guard frame com a primeira amostra para contornar o boundary bug do mixer WAV",
	)
	eq(
		abyss.loop_end,
		frame_count - 1,
		"loop_end precisa apontar para o último frame PCM válido; frame_count faria o mixer ler fora do buffer",
	)
	eq(abyss.data.decode_s16(abyss.loop_end * 2), abyss.data.decode_s16(0), "guard frame repete o início do loop")
	ok(abyss.data != aurora.data)
	ok(abyss.data.size() < 256 * 1024, "loop procedural cabe confortavelmente no pacote")
	eq(abyss.data.decode_s16(0), 0)
	ok(absi(abyss.data.decode_s16(abyss.data.size() - 2)) < 256, "seam do loop chega a silêncio sem click forte")


func test_audio_event_plan_covers_gameplay_and_session_milestones() -> void:
	var events: Array[GameEvent] = [
		GameEvent.make(GameEvent.Kind.TRAIL_STARTED),
		GameEvent.make(GameEvent.Kind.CAPTURED),
		GameEvent.make(GameEvent.Kind.PLAYER_DIED),
		GameEvent.make(GameEvent.Kind.ROUND_STARTED),
		GameEvent.make(GameEvent.Kind.CAMPAIGN_COMPLETE),
	]
	eq(
		QixAudioDirector.cues_for_events(events),
		[&"trail", &"capture", &"death", &"round_start", &"campaign_complete"],
	)
	var completion_tick: Array[GameEvent] = [
		GameEvent.make(GameEvent.Kind.ROUND_WON),
		GameEvent.make(GameEvent.Kind.ROUND_CLEAR_STARTED),
	]
	eq(QixAudioDirector.cues_for_events(completion_tick), [&"round_clear"], "não dobra o stinger no mesmo tick")


func test_audio_hub_builds_separate_music_and_sfx_buses_with_limiter() -> void:
	var hub := QixFeedbackHub.new()
	hub.ensure_ready()
	var master := AudioServer.get_bus_index(QixAudioDirector.BUS_MASTER)
	var music := AudioServer.get_bus_index(QixAudioDirector.BUS_MUSIC)
	var sfx := AudioServer.get_bus_index(QixAudioDirector.BUS_SFX)
	ok(master >= 0)
	ok(music >= 0)
	ok(sfx >= 0)
	eq(AudioServer.get_bus_send(music), QixAudioDirector.BUS_MASTER)
	eq(AudioServer.get_bus_send(sfx), QixAudioDirector.BUS_MASTER)
	ok(AudioServer.get_bus_effect(master, 0) is AudioEffectLimiter)
	hub.audio.set_mix(0.5, 0.4, 0.3)
	eq(roundi(db_to_linear(AudioServer.get_bus_volume_db(master)) * 100.0), 50)
	eq(roundi(db_to_linear(AudioServer.get_bus_volume_db(music)) * 100.0), 40)
	eq(roundi(db_to_linear(AudioServer.get_bus_volume_db(sfx)) * 100.0), 30)
	hub.free()


func test_headless_runtime_never_starts_a_hardware_audio_playback() -> void:
	ok(not QixAudioDirector.runtime_allows_playback(), "smoke headless não deve abrir playback de áudio")


func test_shipping_probes_never_open_audio_playback_objects() -> void:
	ok(QixAudioDirector.arguments_allow_playback(PackedStringArray(), true))
	ok(not QixAudioDirector.arguments_allow_playback(
		PackedStringArray(["--shipping-probe=frame-pacing"]),
		true,
	))
	ok(not QixAudioDirector.arguments_allow_playback(
		PackedStringArray(["--shipping-probe=framebuffer"]),
		true,
	))
	ok(
		QixAudioDirector.arguments_allow_playback(
			PackedStringArray(["--shipping-probe=frame-pacing"]),
			false,
		),
		"argumento reservado não pode silenciar uma build normal sem a feature shipping_qa",
	)


func test_haptic_plan_coalesces_same_tick_to_highest_priority_and_scales_intensity() -> void:
	var feedback := QixHapticFeedback.new()
	feedback.intensity = 0.5
	var events: Array[GameEvent] = [
		GameEvent.make(GameEvent.Kind.CAPTURED, {"filled_delta": 100}),
		GameEvent.make(GameEvent.Kind.ROUND_WON),
	]
	var pulse := feedback.plan(events)
	eq(pulse["kind"], &"round_won")
	eq(pulse["priority"], 80)
	eq(roundi(float(pulse["weak"]) * 1000.0), 350)
	eq(roundi(float(pulse["strong"]) * 1000.0), 400)
	eq(pulse["duration_ms"], 240)


func test_feedback_observers_do_not_mutate_simulation_or_replay() -> void:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	var definition := RoundDefinition.new()
	definition.field_width = 9
	definition.field_height = 9
	definition.player_spawn = Vector2i(4, 0)
	definition.boss_start = Vector2i(7, 4)
	var simulation := GameSimulation.new(rules, definition, 77)
	var replay := ReplayLog.start(simulation)
	var events := simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	replay.record(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	var checksum := simulation.state_checksum()
	var replay_bytes := replay.to_bytes()
	QixAudioDirector.cues_for_events(events)
	QixHapticFeedback.new().plan(events)
	eq(simulation.state_checksum(), checksum)
	eq(replay.to_bytes(), replay_bytes)


func test_feedback_hub_exposes_single_bootstrap_integration_surface() -> void:
	var hub := QixFeedbackHub.new()
	hub.ensure_ready()
	ok(hub.audio is QixAudioDirector)
	ok(hub.haptics is QixHapticFeedback)
	eq(hub.get_child_count(), 1)
	hub.audio.play_round_music(0)
	ok(hub.audio.presentation_state().music_loaded)
	hub.audio.shutdown()
	eq(hub.audio.presentation_state().music_loaded, false)
	eq(hub.audio.presentation_state().cached_music, 0)
	hub.free()
