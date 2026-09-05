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

const CUE_RECIPES := {
	&"trail": {
		"intent": "pontua que a trilha começou; é o cue mais frequente e o mais barato de perder",
		"priority": 10,
		"hz": 740.0, "end_hz": 920.0, "seconds": 0.055, "gain": 0.19, "wave": 1,
	},
	&"round_start": {
		"intent": "abre a rodada; anuncia, não reage",
		"priority": 20,
		"hz": 262.0, "end_hz": 523.0, "seconds": 0.34, "gain": 0.28, "wave": 0,
	},
	&"respawn": {
		"intent": "devolve o controle ao jogador depois da morte",
		"priority": 30,
		"hz": 330.0, "end_hz": 660.0, "seconds": 0.24, "gain": 0.26, "wave": 0,
	},
	&"capture": {
		"intent": "confirma território conquistado; a recompensa do laço",
		"priority": 40,
		"hz": 392.0, "end_hz": 784.0, "seconds": 0.22, "gain": 0.30, "wave": 0,
	},
	&"reject": {
		"intent": "diz que o laço não fechou — erro de leitura, não punição",
		"priority": 45,
		"hz": 180.0, "end_hz": 110.0, "seconds": 0.16, "gain": 0.25, "wave": 2,
	},
	&"shield": {
		"intent": "avisa que o escudo entrou no fim; é um relógio, não um impacto",
		"priority": 50,
		"hz": 880.0, "end_hz": 880.0, "seconds": 0.12, "gain": 0.22, "wave": 1,
	},
	&"round_clear": {
		"intent": "fecha a rodada; carrega a continuidade para a próxima",
		"priority": 80,
		"hz": 523.0, "end_hz": 1047.0, "seconds": 0.52, "gain": 0.34, "wave": 0,
	},
	&"campaign_complete": {
		"intent": "fecha a campanha inteira; o cue mais raro do jogo",
		"priority": 90,
		"hz": 440.0, "end_hz": 1320.0, "seconds": 0.92, "gain": 0.34, "wave": 0,
	},
	&"game_over": {
		"intent": "encerra a tentativa; nada depois dele importa mais que ele",
		"priority": 95,
		"hz": 220.0, "end_hz": 55.0, "seconds": 0.75, "gain": 0.34, "wave": 2,
	},
	&"death": {
		"intent": "a perda de vida; o acontecimento mais alto da sessão",
		"priority": 100,
		"hz": 130.0, "end_hz": 44.0, "seconds": 0.42, "gain": 0.42, "wave": 2,
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


static func cue(cue_name: StringName) -> AudioStreamWAV:
	var recipe: Dictionary = CUE_RECIPES.get(cue_name, CUE_RECIPES[&"trail"])
	return _tone(
		float(recipe["hz"]),
		float(recipe["end_hz"]),
		float(recipe["seconds"]),
		float(recipe["gain"]),
		int(recipe["wave"]),
	)


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


static func _tone(
	start_hz: float,
	end_hz: float,
	seconds: float,
	gain: float,
	wave: int,
) -> AudioStreamWAV:
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
		var envelope := _attack_release(progress)
		var harmonic := sin(TAU * phase * 2.0) * 0.18
		_write_s16(bytes, frame, (raw + harmonic) * gain * envelope)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


static func _attack_release(progress: float) -> float:
	var attack := smoothstep(0.0, 0.08, progress)
	var release := 1.0 - smoothstep(0.55, 1.0, progress)
	return attack * release


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
