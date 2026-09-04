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


func test_every_dispatched_cue_declares_intent_and_priority() -> void:
	var kinds := GameEvent.Kind.values()
	var dispatched: Array[StringName] = []
	for kind in kinds:
		var cue_name := QixAudioDirector.cue_for_kind(kind)
		if cue_name != &"" and not dispatched.has(cue_name):
			dispatched.append(cue_name)
	ok(dispatched.size() >= 10, "o plano de cues cobre os marcos de gameplay e sessão")
	for cue_name in dispatched:
		var recipe: Dictionary = QixProceduralAudioLibrary.CUE_RECIPES.get(cue_name, {})
		ok(not recipe.is_empty(), "cue despachado sem receita: %s" % cue_name)
		ok(
			String(recipe.get("intent", "")).length() > 12,
			"cue sem intenção declarada: %s" % cue_name,
		)
		ok(
			QixProceduralAudioLibrary.priority_for(cue_name)
			> QixProceduralAudioLibrary.PRIORITY_IDLE,
			"cue sem prioridade acima de PRIORITY_IDLE: %s" % cue_name,
		)
		ok(QixProceduralAudioLibrary.duration_msec(cue_name) > 0)


## A escala de prioridade do som e a da háptica descrevem os mesmos eventos. Se elas
## divergirem, o jogador ouve um acontecimento e sente outro no mesmo tick.
func test_cue_priority_ladder_agrees_with_the_haptic_ladder() -> void:
	var haptics := QixHapticFeedback.new()
	var pairs := {
		&"capture": GameEvent.Kind.CAPTURED,
		&"reject": GameEvent.Kind.CAPTURE_REJECTED,
		&"shield": GameEvent.Kind.SHIELD_CRITICAL,
		&"death": GameEvent.Kind.PLAYER_DIED,
		&"respawn": GameEvent.Kind.PLAYER_RESPAWNED,
		&"round_clear": GameEvent.Kind.ROUND_WON,
		&"game_over": GameEvent.Kind.GAME_OVER,
		&"campaign_complete": GameEvent.Kind.CAMPAIGN_COMPLETE,
	}
	for cue_name in pairs:
		var events: Array[GameEvent] = [GameEvent.make(pairs[cue_name])]
		var pulse := haptics.plan(events)
		eq(
			QixProceduralAudioLibrary.priority_for(cue_name),
			int(pulse["priority"]),
			"som e háptica discordam sobre o peso de %s" % cue_name,
		)
	# `trail` e `round_start` não têm pulso háptico: entram abaixo do menor que tem.
	ok(QixProceduralAudioLibrary.priority_for(&"trail") < 30)
	ok(QixProceduralAudioLibrary.priority_for(&"round_start") < 30)
	ok(
		QixProceduralAudioLibrary.priority_for(&"trail")
		< QixProceduralAudioLibrary.priority_for(&"round_start"),
		"o cue mais frequente é o mais barato de perder",
	)


func test_voice_allocation_prefers_free_voices_and_refuses_to_cut_something_louder() -> void:
	var idle := QixProceduralAudioLibrary.PRIORITY_IDLE
	var death := QixProceduralAudioLibrary.priority_for(&"death")
	var trail := QixProceduralAudioLibrary.priority_for(&"trail")

	# Voz livre a partir do cursor: o rodízio continua espalhando cues iguais.
	eq(QixAudioDirector.select_voice(PackedInt32Array([idle, idle, idle]), trail, 1), 1)
	eq(QixAudioDirector.select_voice(PackedInt32Array([idle, death, idle]), trail, 1), 2)

	# Sem voz livre: a trilha não corta a morte — é recusada.
	eq(
		QixAudioDirector.select_voice(PackedInt32Array([death, death]), trail, 0),
		-1,
		"o início de uma trilha nunca pode truncar o cue de morte",
	)
	# Mas a morte corta a trilha, e escolhe a voz de menor prioridade.
	eq(QixAudioDirector.select_voice(PackedInt32Array([death, trail]), death, 0), 1)
	# Empate exato também é recusa: o que já soa termina inteiro (§5.4).
	eq(QixAudioDirector.select_voice(PackedInt32Array([trail, trail]), trail, 0), -1)
	# Entre duas vítimas possíveis, a de menor prioridade absoluta.
	var capture := QixProceduralAudioLibrary.priority_for(&"capture")
	eq(QixAudioDirector.select_voice(PackedInt32Array([capture, trail]), death, 0), 1)
	eq(QixAudioDirector.select_voice(PackedInt32Array([trail, capture]), death, 1), 0)
	# Sem vozes configuradas não há para onde despachar.
	eq(QixAudioDirector.select_voice(PackedInt32Array(), death, 0), -1)


func test_director_holds_a_loud_cue_against_a_flood_of_cheap_ones() -> void:
	var hub := QixFeedbackHub.new()
	hub.ensure_ready()
	var director: QixAudioDirector = hub.audio
	director.play_cue(&"death")
	eq(director.presentation_state()["busy_voices"], 1)
	# Sete `capture` enchem as vozes restantes; o oitavo pedido não tem para onde ir
	# e, por ser mais leve que a morte, é recusado em vez de cortá-la.
	for _i in QixAudioDirector.SFX_VOICES - 1:
		director.play_cue(&"capture")
	eq(director.presentation_state()["busy_voices"], QixAudioDirector.SFX_VOICES)
	var before := director.voice_priorities_now()
	director.play_cue(&"capture")
	eq(director.voice_priorities_now(), before, "pedido recusado não muda a alocação")
	ok(
		before.has(QixProceduralAudioLibrary.priority_for(&"death")),
		"a morte continua segurando a voz dela",
	)
	# O cache de síntese é exercitado mesmo pelo pedido recusado.
	eq(director.presentation_state()["cached_cues"], 2)
	director.shutdown()
	eq(director.presentation_state()["busy_voices"], 0)
	hub.free()


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
