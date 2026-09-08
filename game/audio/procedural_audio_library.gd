class_name QixProceduralAudioLibrary
extends RefCounted
## Biblioteca PCM original sintetizada em runtime. Sem arquivos ou RNG global.

const MIX_RATE := 22_050
const MAX_S16 := 32_767.0
const MUSIC_BEATS := 8

## Cada cue declara, além da receita de síntese, **o que ele significa** (`intent`) e
## **quanto ele pesa** (`priority`) quando duas coisas querem soar ao mesmo tempo.
##
## A escala de `priority` é a mesma de `QixHapticFeedback._pulse_for_event`: **maior
## valor = mais importante**. Isso é deliberado — som e háptica descrevem o mesmo
## acontecimento e não podem discordar sobre qual é o acontecimento do tick. Os cues
## que já têm pulso háptico usam o número de lá; os que não têm (`trail`,
## `round_start`) entram abaixo do menor pulso existente, porque são pontuação, não
## consequência.
const PRIORITY_IDLE := -1

## Forma do envelope, autorada ao lado de `intent`. Até aqui os dez cues dividiam um
## único envelope proporcional à duração (attack = 8% do cue), e a consequência era
## audível: `death` só chegava a amplitude cheia ~34 ms depois de começar e
## `game_over` ~60 ms. **Um impacto com fade-in não é um impacto** — ele chega como
## um "uuf" em vez de um golpe, e chega tarde demais para pertencer ao tick que o
## causou. Agora attack e release são **milissegundos absolutos**: um cue longo pode
## ter cauda longa sem por isso demorar a começar.
##
## `onset` diz de que tipo é a subida, e é o que o teste verifica:
##   `&"impact"`   — a coisa aconteceu **agora**. Sobe dentro de
##                   `IMPACT_ATTACK_CEILING_MS` e o pico do PCM cai no começo do cue.
##   `&"announce"` — a coisa **vai** acontecer, ou acabou de mudar de estado. Sobe com
##                   folga; um anúncio que estala soa como erro.
## Cada cauda usa ADSR autorado por significado; os impactos mantêm início rápido
## mesmo quando decay, sustain e pulsação diferenciam atores e recompensas.
const IMPACT_ATTACK_CEILING_MS := 8.0

const CUE_RECIPES := {
	&"trail": {
		"intent": "pontua que a trilha começou; é o cue mais frequente e o mais barato de perder",
		"priority": 10,
		"onset": &"impact",
		"hz": 740.0, "end_hz": 920.0, "seconds": 0.055, "gain": 0.19, "wave": 1,
		"attack_msec": 2.0, "decay_msec": 12.0, "sustain": 0.35, "release_msec": 25.0,
	},
	&"round_start": {
		"intent": "abre a rodada; anuncia, não reage",
		"priority": 20,
		"onset": &"announce",
		"hz": 262.0, "end_hz": 523.0, "seconds": 0.34, "gain": 0.28, "wave": 0,
		"attack_msec": 28.0, "decay_msec": 60.0, "sustain": 0.65, "release_msec": 130.0,
	},
	&"respawn": {
		"intent": "devolve o controle ao jogador depois da morte",
		"priority": 30,
		"onset": &"announce",
		"hz": 330.0, "end_hz": 660.0, "seconds": 0.24, "gain": 0.26, "wave": 0,
		"attack_msec": 20.0, "decay_msec": 45.0, "sustain": 0.55, "release_msec": 100.0,
	},
	## O único cue que **não** nasce de um `GameEvent`: nasce de uma aresta lida sobre
	## o snapshot confirmado (`TrailExposure.crossed_warning`). Por isso não aparece em
	## `QixAudioDirector.cue_for_kind` — ver `QixAudioDirector.EXPOSURE_CUE`.
	##
	## Um terço maior a subir, em seno macio: abre para cima e não resolve. É o papel a
	## esticar sob o traço longo, não um alarme — a exposição foi escolhida pelo jogador,
	## e o jogo confirma a aposta em vez de a repreender. O ganho fica abaixo do `capture`
	## (0,30) e o anúncio sobe com folga, para nunca competir com o transiente de um
	## acontecimento de facto. A prioridade 35 é a mesma do pulso háptico do mesmo limiar
	## (`QixHapticFeedback._exposure_pulse`): ouvir e sentir descrevem o mesmo instante.
	&"exposure": {
		"intent": "a trilha deixou de ser um compromisso e virou uma aposta",
		"priority": 35,
		"onset": &"announce",
		"hz": 466.16, "end_hz": 622.25, "seconds": 0.20, "gain": 0.22, "wave": 0,
		"attack_msec": 26.0, "decay_msec": 35.0, "sustain": 0.65, "release_msec": 90.0,
	},
	&"capture": {
		"intent": "confirma território conquistado; a recompensa do laço",
		"priority": 40,
		"onset": &"impact",
		"hz": 392.0, "end_hz": 784.0, "seconds": 0.22, "gain": 0.30, "wave": 0,
		"attack_msec": 4.0, "decay_msec": 35.0, "sustain": 0.48, "release_msec": 130.0,
	},
	&"reject": {
		"intent": "diz que o laço não fechou — erro de leitura, não punição",
		"priority": 45,
		"onset": &"impact",
		"hz": 180.0, "end_hz": 110.0, "seconds": 0.16, "gain": 0.25, "wave": 2,
		"attack_msec": 3.0, "decay_msec": 22.0, "sustain": 0.30, "release_msec": 85.0,
	},
	&"shield": {
		"intent": "avisa que o escudo entrou no fim; é um relógio, não um impacto",
		"priority": 92,
		"onset": &"impact",
		"hz": 880.0, "end_hz": 880.0, "seconds": 0.12, "gain": 0.22, "wave": 1,
		"attack_msec": 6.0, "decay_msec": 18.0, "sustain": 0.60, "release_msec": 35.0,
	},
	&"round_clear": {
		"intent": "fecha a rodada; carrega a continuidade para a próxima",
		"priority": 80,
		"onset": &"announce",
		"hz": 523.0, "end_hz": 1047.0, "seconds": 0.52, "gain": 0.34, "wave": 0,
		"attack_msec": 42.0, "decay_msec": 90.0, "sustain": 0.70, "release_msec": 240.0,
	},
	&"campaign_complete": {
		"intent": "fecha a campanha inteira; o cue mais raro do jogo",
		"priority": 90,
		"onset": &"announce",
		"hz": 440.0, "end_hz": 1320.0, "seconds": 0.92, "gain": 0.34, "wave": 0,
		"attack_msec": 74.0, "decay_msec": 140.0, "sustain": 0.65, "release_msec": 400.0,
	},
	&"game_over": {
		"intent": "encerra a tentativa; nada depois dele importa mais que ele",
		"priority": 95,
		"onset": &"impact",
		"hz": 220.0, "end_hz": 55.0, "seconds": 0.75, "gain": 0.34, "wave": 2,
		"attack_msec": 5.0, "decay_msec": 120.0, "sustain": 0.40, "release_msec": 420.0,
	},
	&"death": {
		"intent": "a perda de vida; o acontecimento mais alto da sessão",
		"priority": 100,
		"onset": &"impact",
		"hz": 130.0, "end_hz": 44.0, "seconds": 0.42, "gain": 0.42, "wave": 2,
		"attack_msec": 3.0, "decay_msec": 55.0, "sustain": 0.32, "release_msec": 280.0,
	},
	&"walker_spawn": {
		"intent": "um patrulheiro emerge na borda; sinal curto de uma nova rota perigosa",
		"priority": 91, "hz": 220.0, "end_hz": 330.0, "seconds": 0.13, "gain": 0.17, "wave": 3,
		"attack_msec": 5.0, "decay_msec": 20.0, "sustain": 0.35, "release_msec": 70.0,
		"onset": &"impact",
	},
	&"dart_arm": {
		"intent": "telegrapha um dardo antes de armar; o tom ascendente pede atenção à direção",
		"priority": 91, "hz": 1200.0, "end_hz": 1800.0, "seconds": 0.10, "gain": 0.11, "wave": 3,
		"attack_msec": 4.0, "decay_msec": 15.0, "sustain": 0.40, "release_msec": 35.0,
		"onset": &"impact",
	},
	&"dart_fire": {
		"intent": "confirma o disparo já armado; estalo breve para não mascarar o telegraph seguinte",
		"priority": 91, "hz": 1600.0, "end_hz": 650.0, "seconds": 0.045, "gain": 0.12, "wave": 2,
		"attack_msec": 1.5, "decay_msec": 8.0, "sustain": 0.25, "release_msec": 28.0,
		"onset": &"impact",
	},
	&"trail_cut": {
		"intent": "um dardo cortou a trilha; impacto seco identifica ameaça imediata ao traçado",
		"priority": 94, "hz": 340.0, "end_hz": 70.0, "seconds": 0.16, "gain": 0.34, "wave": 2,
		"attack_msec": 2.0, "decay_msec": 25.0, "sustain": 0.25, "release_msec": 95.0,
		"onset": &"impact",
	},
	&"ember": {
		"intent": "uma brasa persegue a trilha; dois pulsos ásperos pedem movimento contínuo",
		"priority": 93, "hz": 300.0, "end_hz": 620.0, "seconds": 0.25, "gain": 0.24, "wave": 2,
		"attack_msec": 4.0, "decay_msec": 25.0, "sustain": 0.65, "release_msec": 70.0, "pulse_hz": 8.0,
		"onset": &"impact",
	},
	&"threat": {
		"intent": "a pressão subiu; pulso grave marca uma mudança confirmada do diretor",
		"priority": 91, "hz": 110.0, "end_hz": 165.0, "seconds": 0.19, "gain": 0.20, "wave": 3,
		"attack_msec": 20.0, "decay_msec": 25.0, "sustain": 0.45, "release_msec": 95.0,
		"onset": &"announce",
	},
	&"overtime": {
		"intent": "o tempo do setor acabou; três pulsos anunciam pressão crescente",
		"priority": 93, "hz": 440.0, "end_hz": 660.0, "seconds": 0.50, "gain": 0.24, "wave": 3,
		"attack_msec": 6.0, "decay_msec": 30.0, "sustain": 0.70, "release_msec": 130.0, "pulse_hz": 6.0,
		"onset": &"impact",
	},
	&"boss_phase": {
		"intent": "o Núcleo mudou de fase; ascensão grave distingue evolução de projétil",
		"priority": 92, "hz": 82.0, "end_hz": 246.0, "seconds": 0.34, "gain": 0.28, "wave": 2,
		"attack_msec": 20.0, "decay_msec": 50.0, "sustain": 0.50, "release_msec": 190.0,
		"onset": &"announce",
	},
	&"boss_cornered": {
		"intent": "o Núcleo encurralado entrou em fúria; o ronco curto antecede a reação",
		"priority": 94, "hz": 70.0, "end_hz": 210.0, "seconds": 0.28, "gain": 0.30, "wave": 2,
		"attack_msec": 20.0, "decay_msec": 40.0, "sustain": 0.50, "release_msec": 120.0,
		"onset": &"announce",
	},
	&"extinguish": {
		"intent": "território neutralizou um ator; pequena nota descendente confirma alívio",
		"priority": 35, "hz": 620.0, "end_hz": 310.0, "seconds": 0.09, "gain": 0.13, "wave": 0,
		"attack_msec": 3.0, "decay_msec": 12.0, "sustain": 0.25, "release_msec": 55.0,
		"onset": &"impact",
	},
	&"calm": {
		"intent": "a captura grande comprou respiro; tom arredondado confirma queda de pressão",
		"priority": 36, "hz": 440.0, "end_hz": 330.0, "seconds": 0.22, "gain": 0.15, "wave": 0,
		"attack_msec": 20.0, "decay_msec": 45.0, "sustain": 0.45, "release_msec": 120.0,
		"onset": &"announce",
	},
	&"beacon": {
		"intent": "uma baliza foi cercada; sino agudo diferencia objetivo da captura de área",
		"priority": 55, "hz": 660.0, "end_hz": 990.0, "seconds": 0.18, "gain": 0.24, "wave": 0,
		"attack_msec": 2.0, "decay_msec": 25.0, "sustain": 0.30, "release_msec": 120.0,
		"onset": &"impact",
	},
	&"velocity": {
		"intent": "Velocidade iniciou; varredura brilhante sobe uma oitava e meia",
		"priority": 60, "hz": 440.0, "end_hz": 1320.0, "seconds": 0.20, "gain": 0.22, "wave": 3,
		"attack_msec": 4.0, "decay_msec": 25.0, "sustain": 0.45, "release_msec": 100.0,
		"onset": &"impact",
	},
	&"stasis": {
		"intent": "Estase iniciou; tom cristalino desce e sustenta a suspensão do Núcleo",
		"priority": 60, "hz": 760.0, "end_hz": 380.0, "seconds": 0.35, "gain": 0.23, "wave": 0,
		"attack_msec": 20.0, "decay_msec": 55.0, "sustain": 0.55, "release_msec": 180.0,
		"onset": &"announce",
	},
	&"shield_freeze": {
		"intent": "Âncora iniciou; intervalo luminoso anuncia reserva de escudo protegida",
		"priority": 60, "hz": 523.0, "end_hz": 659.0, "seconds": 0.32, "gain": 0.23, "wave": 3,
		"attack_msec": 7.0, "decay_msec": 40.0, "sustain": 0.55, "release_msec": 160.0,
		"onset": &"impact",
	},
	&"purge": {
		"intent": "Expurgo neutralizou as ameaças menores; impacto grave com cauda limpa",
		"priority": 62, "hz": 150.0, "end_hz": 42.0, "seconds": 0.30, "gain": 0.31, "wave": 3,
		"attack_msec": 2.0, "decay_msec": 38.0, "sustain": 0.28, "release_msec": 180.0,
		"onset": &"impact",
	},
	&"item_end": {
		"intent": "um efeito temporário acabou; aviso descendente discreto devolve atenção ao campo",
		"priority": 91, "hz": 880.0, "end_hz": 440.0, "seconds": 0.12, "gain": 0.15, "wave": 3,
		"attack_msec": 5.0, "decay_msec": 15.0, "sustain": 0.35, "release_msec": 65.0,
		"onset": &"impact",
	},
	&"sealed": {
		"intent": "o Núcleo foi selado; resolução grave distingue a vitória especial",
		"priority": 82, "hz": 196.0, "end_hz": 784.0, "seconds": 0.50, "gain": 0.32, "wave": 3,
		"attack_msec": 5.0, "decay_msec": 70.0, "sustain": 0.50, "release_msec": 260.0,
		"onset": &"impact",
	},
}


static func priority_for(cue_name: StringName) -> int:
	var recipe: Dictionary = CUE_RECIPES.get(cue_name, CUE_RECIPES[&"trail"])
	return int(recipe["priority"])


## Quanto tempo o cue ocupa uma voz. O director usa isto para saber o que ainda
## está a soar sem depender de `AudioStreamPlayer.playing`, que é sempre `false`
## no runtime headless (ver `QixAudioDirector.runtime_allows_playback`).
static func duration_msec(cue_name: StringName) -> int:
	var recipe: Dictionary = CUE_RECIPES.get(cue_name, CUE_RECIPES[&"trail"])
	return maxi(1, int(round(float(recipe["seconds"]) * 1000.0)))


## De que tipo é a subida do cue: `&"impact"` ou `&"announce"`. Ver `CUE_RECIPES`.
static func onset_for(cue_name: StringName) -> StringName:
	var recipe: Dictionary = CUE_RECIPES.get(cue_name, CUE_RECIPES[&"trail"])
	return recipe["onset"]


## Tempo, em milissegundos, até o envelope chegar a amplitude cheia.
static func attack_msec(cue_name: StringName) -> float:
	var recipe: Dictionary = CUE_RECIPES.get(cue_name, CUE_RECIPES[&"trail"])
	return float(recipe["attack_msec"])


## Duração, em milissegundos, da cauda que fecha o cue.
static func release_msec(cue_name: StringName) -> float:
	var recipe: Dictionary = CUE_RECIPES.get(cue_name, CUE_RECIPES[&"trail"])
	return float(recipe["release_msec"])


## O envelope do cue num instante, isolado do portador. Existe para que o teste
## possa afirmar a forma da subida sem ter de separar envelope de onda no PCM.
static func envelope_at_msec(cue_name: StringName, elapsed_msec: float) -> float:
	return envelope_at(cue_name, elapsed_msec / 1000.0)


static func cue(cue_name: StringName) -> AudioStreamWAV:
	var recipe: Dictionary = CUE_RECIPES.get(cue_name, CUE_RECIPES[&"trail"])
	return _tone(recipe)


## Envelope público permite medir ataque e cauda sem abrir o dispositivo de áudio.
static func envelope_at(cue_name: StringName, elapsed_seconds: float) -> float:
	var recipe: Dictionary = CUE_RECIPES.get(cue_name, CUE_RECIPES[&"trail"])
	return _envelope(recipe, elapsed_seconds)


## Loop chiptune/ambient de 8 beats. Cada setor muda escala, tempo e voicing.
static func music_for_round(round_index: int) -> AudioStreamWAV:
	var variant := posmod(round_index, 3)
	var bpm: float = [108.0, 116.0, 124.0][variant]
	var beat_seconds: float = 60.0 / bpm
	var seconds := beat_seconds * MUSIC_BEATS
	var frame_count := maxi(1, int(round(seconds * MIX_RATE)))
	var bytes := PackedByteArray()
	# O mixer WAV 4.7.2 inclui loop_end no bloco decodificado, mas só faz o
	# wrap quando offset >= loop_end. Um guard frame contendo a primeira amostra
	# mantém a sequência exata e impede a leitura one-past-end documentada no
	# issue godotengine/godot#119778.
	bytes.resize((frame_count + 1) * 2)
	var roots: Array[float] = [55.0, 65.406, 73.416]
	var scales: Array = [
		[1.0, 1.1892, 1.3348, 1.4983, 1.7818, 1.4983, 1.3348, 1.1892],
		[1.0, 1.1225, 1.3348, 1.5874, 1.7818, 2.0, 1.5874, 1.3348],
		[1.0, 1.1892, 1.4142, 1.4983, 1.7818, 2.0, 1.7818, 1.4142],
	]
	var root := roots[variant]
	var notes: Array = scales[variant]
	for frame in frame_count:
		var t := float(frame) / MIX_RATE
		var beat_position := t / beat_seconds
		var beat := mini(MUSIC_BEATS - 1, int(beat_position))
		var local_beat := fmod(beat_position, 1.0)
		var bass_hz: float = root * float(notes[beat])
		var lead_hz := bass_hz * (4.0 if beat % 2 == 0 else 3.0)
		var bass := sin(TAU * bass_hz * t) * 0.20
		var triangle_phase := fmod(lead_hz * t, 1.0)
		var triangle := (4.0 * absf(triangle_phase - 0.5) - 1.0) * 0.075
		var pulse_envelope := exp(-local_beat * 11.0)
		var kick := sin(TAU * (48.0 + 30.0 * (1.0 - local_beat)) * t) * pulse_envelope * 0.12
		var shimmer := sin(TAU * (lead_hz * 2.01) * t) * 0.025 * (0.4 + 0.6 * sin(PI * local_beat))
		var seam_fade := _loop_seam_envelope(frame, frame_count)
		_write_s16(bytes, frame, (bass + triangle + kick + shimmer) * seam_fade)
	bytes[frame_count * 2] = bytes[0]
	bytes[frame_count * 2 + 1] = bytes[1]
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	return stream


static func _tone(recipe: Dictionary) -> AudioStreamWAV:
	var start_hz := float(recipe["hz"])
	var end_hz := float(recipe["end_hz"])
	var seconds := float(recipe["seconds"])
	var gain := float(recipe["gain"])
	var wave := int(recipe["wave"])
	var frame_count := maxi(1, int(round(seconds * MIX_RATE)))
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 2)
	var phase := 0.0
	for frame in frame_count:
		var progress := float(frame) / float(maxi(1, frame_count - 1))
		var hz := lerpf(start_hz, end_hz, progress)
		phase = fmod(phase + hz / MIX_RATE, 1.0)
		var raw := sin(TAU * phase)
		if wave == 1:
			raw = 1.0 if raw >= 0.0 else -1.0
		elif wave == 2:
			raw = 2.0 * phase - 1.0
		elif wave == 3:
			raw = 4.0 * absf(phase - 0.5) - 1.0
		var envelope := _envelope(recipe, progress * seconds)
		var harmonic := sin(TAU * phase * 2.0) * 0.18
		_write_s16(bytes, frame, (raw + harmonic) * gain * envelope)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


static func _envelope(recipe: Dictionary, elapsed: float) -> float:
	var seconds := float(recipe["seconds"])
	if elapsed <= 0.0 or elapsed >= seconds:
		return 0.0
	var attack := float(recipe["attack_msec"]) / 1000.0
	var decay := float(recipe["decay_msec"]) / 1000.0
	var release := float(recipe["release_msec"]) / 1000.0
	var sustain := float(recipe["sustain"])
	var level := smoothstep(0.0, attack, elapsed)
	if elapsed > attack:
		level = lerpf(1.0, sustain, smoothstep(attack, attack + decay, elapsed))
	level *= 1.0 - smoothstep(seconds - release, seconds, elapsed)
	var pulse_hz := float(recipe.get("pulse_hz", 0.0))
	if pulse_hz > 0.0:
		level *= 0.40 + 0.60 * pow(0.5 + 0.5 * cos(TAU * elapsed * pulse_hz), 2.0)
	return level


static func _loop_seam_envelope(frame: int, frame_count: int) -> float:
	var seam_frames := maxi(1, int(MIX_RATE * 0.012))
	if frame < seam_frames:
		return float(frame) / seam_frames
	if frame >= frame_count - seam_frames:
		return float(frame_count - 1 - frame) / seam_frames
	return 1.0


static func _write_s16(bytes: PackedByteArray, frame: int, sample: float) -> void:
	var signed := clampi(int(round(clampf(sample, -1.0, 1.0) * MAX_S16)), -32_768, 32_767)
	var encoded := signed & 0xFFFF
	bytes[frame * 2] = encoded & 0xFF
	bytes[frame * 2 + 1] = (encoded >> 8) & 0xFF
