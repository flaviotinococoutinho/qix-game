class_name QixProceduralAudioLibrary
extends RefCounted
## Biblioteca PCM original sintetizada em runtime. Sem arquivos ou RNG global.

const MIX_RATE := 22_050
const MAX_S16 := 32_767.0
const MUSIC_BEATS := 8

const CUE_RECIPES := {
	&"trail": {"hz": 740.0, "end_hz": 920.0, "seconds": 0.055, "gain": 0.19, "wave": 1},
	&"capture": {"hz": 392.0, "end_hz": 784.0, "seconds": 0.22, "gain": 0.30, "wave": 0},
	&"reject": {"hz": 180.0, "end_hz": 110.0, "seconds": 0.16, "gain": 0.25, "wave": 2},
	&"death": {"hz": 130.0, "end_hz": 44.0, "seconds": 0.42, "gain": 0.42, "wave": 2},
	&"respawn": {"hz": 330.0, "end_hz": 660.0, "seconds": 0.24, "gain": 0.26, "wave": 0},
	&"shield": {"hz": 880.0, "end_hz": 880.0, "seconds": 0.12, "gain": 0.22, "wave": 1},
	&"round_start": {"hz": 262.0, "end_hz": 523.0, "seconds": 0.34, "gain": 0.28, "wave": 0},
	&"round_clear": {"hz": 523.0, "end_hz": 1047.0, "seconds": 0.52, "gain": 0.34, "wave": 0},
	&"game_over": {"hz": 220.0, "end_hz": 55.0, "seconds": 0.75, "gain": 0.34, "wave": 2},
	&"campaign_complete": {"hz": 440.0, "end_hz": 1320.0, "seconds": 0.92, "gain": 0.34, "wave": 0},
}


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
