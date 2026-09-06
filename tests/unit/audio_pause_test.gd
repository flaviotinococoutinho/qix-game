extends TestCase
## Pausar tem de calar o campo inteiro, não só a música — e retomar tem de devolver
## a arbitragem de vozes no ponto em que ela ficou. Ver `QixAudioDirector.apply_pause`.


func test_mix_clock_freezes_while_paused_and_follows_the_real_clock_otherwise() -> void:
	eq(QixAudioDirector.mix_now_msec(5_000, -1), 5_000, "sem pausa, o relógio é o real")
	eq(QixAudioDirector.mix_now_msec(5_000, 1_200), 1_200, "pausado, congela no início da pausa")
	eq(QixAudioDirector.mix_now_msec(9_999, 0), 0, "instante zero ainda é uma pausa válida")


func test_pause_silences_the_sfx_voices_and_not_only_the_music() -> void:
	var director := _director_in_tree()
	director.play_cue(&"death")
	eq(director.presentation_state()["paused_voices"], 0, "a correr, nenhuma voz está suspensa")

	# `paused_voices` é a ordem que o director deu, não uma releitura de
	# `AudioStreamPlayer.stream_paused`: essa deriva dos playbacks vivos, que o
	# runtime headless nunca inicia. Ver o campo `_paused_voices`.
	director.apply_pause(true, 1_000)
	var paused_state := director.presentation_state()
	eq(paused_state["music_paused"], true)
	eq(paused_state["mix_clock_frozen"], true, "o relógio de mix congela com a pausa")
	eq(
		paused_state["paused_voices"],
		QixAudioDirector.SFX_VOICES,
		"as oito vozes de SFX param com a música, não por cima dela",
	)

	director.apply_pause(false, 2_000)
	var resumed_state := director.presentation_state()
	eq(resumed_state["music_paused"], false)
	eq(resumed_state["mix_clock_frozen"], false)
	eq(resumed_state["paused_voices"], 0, "retomar devolve as vozes ao ar")
	director.free()


func test_resuming_shifts_the_voice_deadlines_by_the_time_spent_paused() -> void:
	var death_msec := QixProceduralAudioLibrary.duration_msec(&"death")
	ok(death_msec > 0, "o cue de morte tem duração conhecida")
	var paused_for := 10 * death_msec

	var director := _director_in_tree()
	var started := Time.get_ticks_msec()
	director.play_cue(&"death")
	# O prazo real é `>= started + death_msec`, portanto um instante logo antes
	# disso é seguramente "ocupado" sem depender do relógio da máquina.
	var before_end := started + death_msec - 1
	eq(_busy_count(director, before_end), 1, "a voz segura o `death` até ao fim do cue")

	director.apply_pause(true, started + 1)
	director.apply_pause(false, started + 1 + paused_for)
	eq(
		_busy_count(director, before_end + paused_for),
		1,
		"o tempo pausado não consome o cue: a voz continua ocupada depois de retomar",
	)

	# E o contraste que prova que é o empurrão dos prazos que faz o trabalho: um
	# director que nunca pausou já está livre nesse mesmo ponto do relógio real.
	var never_paused := _director_in_tree()
	var other_started := Time.get_ticks_msec()
	never_paused.play_cue(&"death")
	eq(
		_busy_count(never_paused, other_started + death_msec + paused_for),
		0,
		"sem pausa, o mesmo cue já terminou muito antes",
	)
	director.free()
	never_paused.free()


func test_a_trail_cannot_steal_the_death_voice_across_a_pause() -> void:
	var death_msec := QixProceduralAudioLibrary.duration_msec(&"death")
	var paused_for := 10 * death_msec
	var director := _director_in_tree()
	var started := Time.get_ticks_msec()
	director.play_cue(&"death")
	director.apply_pause(true, started + 1)
	director.apply_pause(false, started + 1 + paused_for)

	var priorities := director.voice_priorities_at(started + death_msec - 1 + paused_for)
	var trail_priority := QixProceduralAudioLibrary.priority_for(&"trail")
	var death_priority := QixProceduralAudioLibrary.priority_for(&"death")
	ok(trail_priority < death_priority, "o `trail` é menos importante que o `death`")

	var holding := _first_busy(priorities)
	# Sem o empurrão dos prazos esta voz já reportaria `IDLE` e o `trail` entraria
	# nela: é a regressão que o teste tranca.
	ne(holding, -1, "alguma voz ainda segura o `death` depois de retomar")
	if holding < 0:
		return
	eq(priorities[holding], death_priority, "e segura-o com a prioridade do `death`")
	ne(
		QixAudioDirector.select_voice(priorities, trail_priority, 0),
		holding,
		"o `trail` de retoma não corta a morte ao meio",
	)
	director.free()


func _director_in_tree() -> QixAudioDirector:
	var director := QixAudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	director.ensure_ready()
	return director


func _busy_count(director: QixAudioDirector, at_msec: int) -> int:
	var busy := 0
	for priority in director.voice_priorities_at(at_msec):
		if priority != QixProceduralAudioLibrary.PRIORITY_IDLE:
			busy += 1
	return busy


func _first_busy(priorities: PackedInt32Array) -> int:
	for index in priorities.size():
		if priorities[index] != QixProceduralAudioLibrary.PRIORITY_IDLE:
			return index
	return -1
