extends TestCase
## A forma da subida de cada cue.
##
## Até `QixProceduralAudioLibrary` autorar attack e release por cue, os dez cues
## dividiam um envelope proporcional à duração — e o cue mais importante do jogo
## era, por isso, o mais lento a começar: `death` (0,42 s) só alcançava 90% do seu
## pico 31 ms depois de disparar, e `game_over` (0,75 s) 51 ms. A 60 fps isso é
## um impacto que chega dois a três ticks atrasado, com fade-in. Um impacto com
## fade-in não é um impacto.
##
## Estes testes fixam as duas metades do contrato: o que precisa **bater** bate
## dentro de `IMPACT_ATTACK_CEILING_MS`, e o que precisa **anunciar** continua
## subindo com folga. As medidas são feitas no PCM sintetizado, não na receita —
## um número na receita que não chegue à onda não vale nada.

const CEILING_MS := QixProceduralAudioLibrary.IMPACT_ATTACK_CEILING_MS
## Piso da subida de anúncio: bem acima do teto de impacto, para que a diferença
## entre as duas famílias sobreviva a um ajuste pequeno de autoração.
const ANNOUNCE_FLOOR_MS := 12.0


## Instante, em milissegundos, em que o PCM cruza 90% do seu próprio pico. É a
## primeira vez que o cue soa com a força que ele vai ter — o que o ouvido lê
## como "começou".
func _msec_to_ninety_percent_of_peak(cue_name: StringName) -> float:
	var data := QixProceduralAudioLibrary.cue(cue_name).data
	var peak := 0
	for offset in range(0, data.size(), 2):
		peak = maxi(peak, absi(data.decode_s16(offset)))
	var threshold := int(0.9 * peak)
	var frames := data.size() / 2
	for frame in frames:
		if absi(data.decode_s16(frame * 2)) >= threshold:
			return 1000.0 * float(frame) / QixProceduralAudioLibrary.MIX_RATE
	return 1000.0 * float(frames) / QixProceduralAudioLibrary.MIX_RATE


func test_every_cue_declares_an_onset_shape_in_absolute_milliseconds() -> void:
	for cue_name in QixProceduralAudioLibrary.CUE_RECIPES:
		var onset := QixProceduralAudioLibrary.onset_for(cue_name)
		ok(
			onset == &"impact" or onset == &"announce",
			"cue sem família de onset declarada: %s" % cue_name,
		)
		var attack := QixProceduralAudioLibrary.attack_msec(cue_name)
		var release := QixProceduralAudioLibrary.release_msec(cue_name)
		var total := float(QixProceduralAudioLibrary.duration_msec(cue_name))
		ok(attack > 0.0, "attack sem duração deixa um degrau de amostra em %s" % cue_name)
		ok(release > 0.0, "release sem duração corta o cue a seco em %s" % cue_name)
		ok(
			attack + release < total,
			"%s não tem instante nenhum em amplitude cheia: %.1f + %.1f >= %.1f ms"
			% [cue_name, attack, release, total],
		)


func test_impact_cues_reach_full_amplitude_before_the_ceiling() -> void:
	var impacts := 0
	for cue_name in QixProceduralAudioLibrary.CUE_RECIPES:
		if QixProceduralAudioLibrary.onset_for(cue_name) != &"impact":
			continue
		impacts += 1
		var attack := QixProceduralAudioLibrary.attack_msec(cue_name)
		ok(
			attack <= CEILING_MS,
			"attack autorado acima do teto de impacto em %s: %.1f ms" % [cue_name, attack],
		)
		ok(
			QixProceduralAudioLibrary.envelope_at_msec(cue_name, attack) > 0.90,
			"o envelope de %s não atingiu o ataque autorado" % cue_name,
		)
		var measured := _msec_to_ninety_percent_of_peak(cue_name)
		ok(
			measured <= CEILING_MS,
			"o PCM de %s só chega a 90%% do pico em %.2f ms (teto %.0f ms)"
			% [cue_name, measured, CEILING_MS],
		)
	ok(impacts >= 5, "a família de impacto encolheu; cues de reação viraram anúncio")


func test_announcement_cues_keep_a_soft_rise() -> void:
	var announcements := 0
	for cue_name in QixProceduralAudioLibrary.CUE_RECIPES:
		if QixProceduralAudioLibrary.onset_for(cue_name) != &"announce":
			continue
		announcements += 1
		ok(
			QixProceduralAudioLibrary.attack_msec(cue_name) >= ANNOUNCE_FLOOR_MS,
			"anúncio com subida de impacto estala em vez de abrir: %s" % cue_name,
		)
		ok(
			QixProceduralAudioLibrary.envelope_at_msec(cue_name, CEILING_MS) < 0.9,
			"%s já está em amplitude quase cheia no teto de impacto" % cue_name,
		)
		var measured := _msec_to_ninety_percent_of_peak(cue_name)
		ok(
			measured >= ANNOUNCE_FLOOR_MS,
			"o PCM de %s abre como impacto: 90%% do pico em %.2f ms" % [cue_name, measured],
		)
	ok(announcements >= 3, "a família de anúncio encolheu; o jogo ficou todo em ataque")


## O envelope é uma curva, não um degrau: sobe de zero, assenta em cheio e volta a
## zero. Sem isto, um attack de 2 ms viraria um clique de amostra.
func test_envelope_starts_at_silence_settles_full_and_closes() -> void:
	for cue_name in QixProceduralAudioLibrary.CUE_RECIPES:
		var attack := QixProceduralAudioLibrary.attack_msec(cue_name)
		var total := float(QixProceduralAudioLibrary.duration_msec(cue_name))
		eq(QixProceduralAudioLibrary.envelope_at_msec(cue_name, 0.0), 0.0, cue_name)
		ok(
			QixProceduralAudioLibrary.envelope_at_msec(cue_name, attack * 0.5) < 0.75,
			"a metade do attack de %s já está quase cheia — é degrau, não curva" % cue_name,
		)
		ok(
			QixProceduralAudioLibrary.envelope_at_msec(cue_name, attack) > 0.90,
			"o attack de %s não fecha no tempo que declara" % cue_name,
		)
		ok(
			QixProceduralAudioLibrary.envelope_at_msec(cue_name, total) < 0.001,
			"%s não volta ao silêncio no fim" % cue_name,
		)


## ADSR e pulsação podem mudar a cauda por cue. O contrato relevante é chegar ao
## silêncio com continuidade, sem prolongar o cue nem retirar espaço do ataque.
func test_authored_release_has_room_and_reaches_silence_continuously() -> void:
	for cue_name in QixProceduralAudioLibrary.CUE_RECIPES:
		var total := float(QixProceduralAudioLibrary.duration_msec(cue_name))
		var release := QixProceduralAudioLibrary.release_msec(cue_name)
		var attack := QixProceduralAudioLibrary.attack_msec(cue_name)
		ok(release >= 20.0 and release < total - attack, "cauda inválida em %s" % cue_name)
		var before_end := QixProceduralAudioLibrary.envelope_at_msec(cue_name, total - 1.0)
		ok(before_end >= 0.0 and before_end < 0.01, "cauda corta amplitude em %s" % cue_name)
		eq(QixProceduralAudioLibrary.envelope_at_msec(cue_name, total + 1.0), 0.0, cue_name)
