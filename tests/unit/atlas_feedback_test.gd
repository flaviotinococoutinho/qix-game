extends TestCase
## Sinais confirmados do Atlas Vivo: síntese, mix e pausa sem dispositivo de áudio.


class AudioPauseSpy extends QixAudioDirector:
	var clock_msec: int = 0
	var pause_commands: Array[Dictionary] = []

	func _now_msec() -> int:
		return clock_msec

	func _set_player_paused(player: AudioStreamPlayer, value: bool) -> void:
		pause_commands.append({"player": String(player.name), "paused": value})
		super._set_player_paused(player, value)


class MusicPlaybackSpy extends AudioPauseSpy:
	var play_commands: int = 0
	var stop_commands: int = 0
	var playback_running: bool = false

	func _music_is_playing() -> bool:
		return playback_running

	func _play_music() -> void:
		play_commands += 1
		playback_running = true

	func _stop_music() -> void:
		stop_commands += 1
		playback_running = false
		super._stop_music()


func test_actor_and_objective_events_have_distinct_semantic_cues() -> void:
	var expected := {
		GameEvent.Kind.WALKER_SPAWNED: &"walker_spawn",
		GameEvent.Kind.DART_ARMED: &"dart_arm",
		GameEvent.Kind.DART_FIRED: &"dart_fire",
		GameEvent.Kind.TRAIL_CUT: &"trail_cut",
		GameEvent.Kind.EMBER_IGNITED: &"ember",
		GameEvent.Kind.BOSS_PHASE_CHANGED: &"boss_phase",
		GameEvent.Kind.BOSS_CORNERED: &"boss_cornered",
		GameEvent.Kind.OVERTIME_STARTED: &"overtime",
		GameEvent.Kind.BEACON_CAPTURED: &"beacon",
		GameEvent.Kind.BOSS_SEALED: &"sealed",
		GameEvent.Kind.CALM_STARTED: &"calm",
		GameEvent.Kind.WALKER_EXTINGUISHED: &"extinguish",
		GameEvent.Kind.DART_ABSORBED: &"extinguish",
		GameEvent.Kind.EMBER_EXTINGUISHED: &"extinguish",
	}
	for kind in expected:
		eq(QixAudioDirector.cue_for_event(GameEvent.make(kind)), expected[kind])
	var events: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.BEACON_CAPTURED),
		GameEvent.make(GameEvent.Kind.BEACON_CAPTURED), GameEvent.make(GameEvent.Kind.DART_ARMED)]
	eq(QixAudioDirector.cues_for_events(events), [&"beacon", &"dart_arm"],
		"uma cadeia não multiplica vozes do mesmo sino no mesmo tick")


func test_items_select_four_distinct_sounds_and_do_not_warn_on_instant_purge_expiry() -> void:
	var expected: Array[StringName] = [&"velocity", &"stasis", &"shield_freeze", &"purge"]
	var previous := PackedByteArray()
	for index in expected.size():
		var event := GameEvent.make(GameEvent.Kind.ITEM_STARTED, {"item": index + 1})
		eq(QixAudioDirector.cue_for_event(event), expected[index])
		var pcm := QixProceduralAudioLibrary.cue(expected[index]).data
		ne(pcm, previous)
		previous = pcm
	eq(QixAudioDirector.cue_for_event(GameEvent.make(GameEvent.Kind.ITEM_STARTED, {"item": 99})), &"")
	eq(QixAudioDirector.cue_for_event(GameEvent.make(GameEvent.Kind.ITEM_ENDED,
		{"item": ItemProfile.Kind.PURGE})), &"")
	eq(QixAudioDirector.cue_for_event(GameEvent.make(GameEvent.Kind.ITEM_ENDED,
		{"item": ItemProfile.Kind.STASIS})), &"item_end")


func test_falling_threat_does_not_emit_an_escalation_alarm_or_haptic() -> void:
	var falling: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.THREAT_LEVEL_CHANGED,
		{"index": 3, "previous": 4})]
	eq(QixAudioDirector.cues_for_events(falling), [])
	eq(QixHapticFeedback.new().plan(falling), {})
	var rising := GameEvent.make(GameEvent.Kind.THREAT_LEVEL_CHANGED, {"index": 5, "previous": 4})
	eq(QixAudioDirector.cue_for_event(rising), &"threat")


func test_all_envelopes_have_silent_edges_non_clipping_pcm_and_fast_impacts() -> void:
	for cue_name in QixProceduralAudioLibrary.CUE_RECIPES:
		var recipe: Dictionary = QixProceduralAudioLibrary.CUE_RECIPES[cue_name]
		var duration := float(recipe["seconds"])
		eq(QixProceduralAudioLibrary.envelope_at(cue_name, 0.0), 0.0)
		eq(QixProceduralAudioLibrary.envelope_at(cue_name, duration), 0.0)
		eq(QixProceduralAudioLibrary.envelope_at(cue_name, duration + 1.0), 0.0)
		var stream := QixProceduralAudioLibrary.cue(cue_name)
		eq(stream.data.decode_s16(0), 0, "ataque sem descontinuidade: %s" % cue_name)
		eq(stream.data.decode_s16(stream.data.size() - 2), 0, "cauda silenciosa: %s" % cue_name)
		var peak := 0
		for offset in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(offset)))
		ok(peak > 1000, "cue não vazio: %s" % cue_name)
		ok(peak < 25000, "headroom antes do limiter: %s" % cue_name)
		ok(stream.data.size() < 65536, "cada cue permanece pequeno: %s" % cue_name)
	for cue_name in [&"death", &"capture", &"trail_cut", &"purge", &"dart_fire"]:
		var early_peak := 0.0
		for millisecond in range(1, 7):
			early_peak = maxf(early_peak, QixProceduralAudioLibrary.envelope_at(
				cue_name, float(millisecond) / 1000.0))
		ok(early_peak > 0.90, "impacto precisa responder nos primeiros 6 ms: %s" % cue_name)
	ne(QixProceduralAudioLibrary.envelope_at(&"death", 0.003),
		QixProceduralAudioLibrary.envelope_at(&"round_start", 0.003),
		"impacto e anúncio possuem envelopes próprios")


func test_danger_outweighs_rewards_but_never_death_in_both_feedback_channels() -> void:
	var rewards: Array[StringName] = [&"capture", &"beacon", &"velocity", &"purge", &"round_clear", &"campaign_complete"]
	var dangers: Array[StringName] = [&"shield", &"dart_arm", &"ember", &"trail_cut", &"boss_cornered", &"overtime"]
	var death := QixProceduralAudioLibrary.priority_for(&"death")
	for danger in dangers:
		var priority := QixProceduralAudioLibrary.priority_for(danger)
		ok(priority < death)
		for reward in rewards:
			ok(priority > QixProceduralAudioLibrary.priority_for(reward))
	var haptics := QixHapticFeedback.new()
	var events: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.BEACON_CAPTURED),
		GameEvent.make(GameEvent.Kind.TRAIL_CUT), GameEvent.make(GameEvent.Kind.ROUND_WON)]
	var pulse := haptics.plan(events)
	eq(pulse.kind, &"trail_cut")
	eq(pulse.priority, QixProceduralAudioLibrary.priority_for(&"trail_cut"))
	events.append(GameEvent.make(GameEvent.Kind.PLAYER_DIED))
	eq(haptics.plan(events).kind, &"death")
	eq(haptics.plan(events, false, true), {}, "pausa não produz vibração")


func test_eight_voice_budget_keeps_death_when_new_threats_and_rewards_arrive() -> void:
	var director := QixAudioDirector.new()
	director.ensure_ready()
	for index in 8:
		director.play_cue(&"campaign_complete")
	eq(director.presentation_state().voice_count, 8)
	eq(director.presentation_state().busy_voices, 8)
	director.play_cue(&"dart_arm")
	ok(director.voice_priorities_now().has(QixProceduralAudioLibrary.priority_for(&"dart_arm")))
	director.play_cue(&"death")
	for index in 12:
		director.play_cue(&"beacon")
	ok(director.voice_priorities_now().has(QixProceduralAudioLibrary.priority_for(&"death")))
	eq(director.presentation_state().voice_count, 8)
	ok(director.presentation_state().busy_voices <= 8)
	director.shutdown()
	director.free()


func test_pause_suspends_all_players_and_rejects_new_cues_without_a_backlog() -> void:
	var director := AudioPauseSpy.new()
	director.ensure_ready()
	director.play_cue(&"campaign_complete")
	director.set_paused(true)
	eq(director.pause_commands.size(), 9, "música + oito vozes recebem pausa")
	for name in ["Music", "Sfx00", "Sfx01", "Sfx02", "Sfx03", "Sfx04", "Sfx05", "Sfx06", "Sfx07"]:
		ok(director.pause_commands.has({"player": name, "paused": true}),
			"comando de pausa precisa chegar ao driver de %s" % name)
	var snapshot := director.voice_priorities_now()
	var before := director.presentation_state()
	director.clock_msec = 5000  # cinco segundos de pausa excedem toda duração de cue
	var events: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.PLAYER_DIED)]
	director.sync(null, events, true)
	director.play_cue(&"purge")
	ok(director.presentation_state().music_paused)
	ok(director.presentation_state().sfx_paused)
	eq(director.voice_priorities_now(), snapshot)
	eq(director.presentation_state().cached_cues, before.cached_cues,
		"pausa não sintetiza nem enfileira novos cues")
	# Sem AudioStreamPlayback, o getter da engine é false por contrato e não confirma
	# recebimento do comando. O spy acima chama o setter real e comprova todos os destinos.
	director.pause_commands.clear()
	director.sync(null, [], false)
	eq(director.pause_commands.size(), 9, "todas as saídas recebem retomada")
	for command in director.pause_commands:
		eq(command.paused, false)
	ok(not director.presentation_state().music_paused)
	ok(not director.presentation_state().sfx_paused)
	eq(director.presentation_state().cached_cues, before.cached_cues)
	eq(director.voice_priorities_now(), snapshot, "a pausa preserva a duração restante")
	director.clock_msec = 5919
	eq(director.presentation_state().busy_voices, 1, "o cue original ainda tem 1 ms")
	director.clock_msec = 5920
	eq(director.presentation_state().busy_voices, 0, "termina após 920 ms ativos, excluindo pausa")
	director.shutdown()
	director.free()


func test_full_atlas_feedback_sync_preserves_domain_checksum_and_event_payloads() -> void:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	var definition := RoundDefinition.new()
	definition.field_width = 32
	definition.field_height = 32
	definition.player_spawn = Vector2i(16, 0)
	definition.boss_start = Vector2i(16, 16)
	definition.beacon_cells = PackedInt32Array([8, 8])
	var simulation := GameSimulation.new(rules, definition, 77)
	var checksum := simulation.state_checksum()
	var events: Array[GameEvent] = [GameEvent.make(GameEvent.Kind.BEACON_CAPTURED,
		{"index": 0, "x": 8, "y": 8, "chain": 1, "points": 1000, "item": ItemProfile.Kind.STASIS}),
		GameEvent.make(GameEvent.Kind.ITEM_STARTED, {"item": ItemProfile.Kind.STASIS, "ticks": 180}),
		GameEvent.make(GameEvent.Kind.DART_ARMED)]
	var payload := events[0].data.duplicate(true)
	var director := QixAudioDirector.new()
	director.sync(null, events)
	QixHapticFeedback.new().plan(events)
	eq(simulation.state_checksum(), checksum)
	eq(events[0].data, payload)
	eq(director.presentation_state().cached_cues, 3)
	director.shutdown()
	director.free()


func test_pause_mute_unmute_resume_restarts_stopped_music_through_each_entry_point() -> void:
	for entry in ["setter", "direct", "sync"]:
		var director := MusicPlaybackSpy.new()
		director.play_round_music(0)
		eq(director.play_commands, 1, "%s: música inicial" % entry)
		director.clock_msec = 100
		_change_music_pause(director, entry, true)  # P
		director.set_enabled(false)                # M
		eq(director.stop_commands, 1)
		ok(not director.playback_running)
		director.set_enabled(true)                 # M, ainda pausado
		eq(director.play_commands, 1, "%s: religar durante a pausa não inicia áudio" % entry)
		director.clock_msec = 5100
		_change_music_pause(director, entry, false) # P
		eq(director.play_commands, 2, "%s: retomar recria playback encerrado por mute" % entry)
		ok(director.playback_running)
		director.sync(null, [], false)
		eq(director.play_commands, 2, "sync do próximo tick não reinicia música já tocando")
		# Uma pausa comum conserva o playback e sua posição, sem começar a música de novo.
		_change_music_pause(director, entry, true)
		_change_music_pause(director, entry, false)
		eq(director.play_commands, 2, "%s: pausa simples não reinicia a trilha sonora" % entry)
		# Permanecer sem som também tem de ser respeitado ao sair da pausa.
		_change_music_pause(director, entry, true)
		director.set_enabled(false)
		_change_music_pause(director, entry, false)
		eq(director.play_commands, 2, "%s: retomar com áudio desabilitado mantém silêncio" % entry)
		director.shutdown()
		director.free()


func test_music_loaded_while_paused_starts_only_after_resume() -> void:
	var director := MusicPlaybackSpy.new()
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	var session := GameSession.new(campaign)
	director.ensure_ready()
	director.apply_pause(true, 0)
	director.sync(session, [], true)
	ok(director.presentation_state().music_loaded)
	eq(director.play_commands, 0, "carregar a rodada durante pausa não começa o playback")
	director.sync(session, [], false)
	eq(director.play_commands, 1, "sync retoma o stream carregado durante a pausa")
	director.shutdown()
	director.free()


func _change_music_pause(director: MusicPlaybackSpy, entry: String, value: bool) -> void:
	match entry:
		"setter": director.set_paused(value)
		"direct": director.apply_pause(value, director.clock_msec)
		"sync": director.sync(null, [], value)
