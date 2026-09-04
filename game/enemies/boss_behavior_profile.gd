class_name BossBehaviorProfile
extends Resource
## Perfil autorável do chefe. Apenas dados inteiros entram na simulação e no hash de replay.

const PROFILE_VERSION := 1

enum Pattern {
	WANDER,   ## escolhe uma direção pseudoaleatória no intervalo de virada
	PURSUIT,  ## aponta para o jogador, com jitter determinístico opcional
	SWEEP,    ## percorre a rosa de 16 direções em passos fixos
}

@export var pattern: Pattern = Pattern.WANDER
@export_range(-7, 7, 1) var sweep_turn_steps: int = 2
@export_range(0, 3, 1) var pursuit_jitter_steps: int = 0

## Pulso no fim de cada período. Zero desativa e mantém 1000 permille (1x).
@export_range(0, 3600, 1) var pulse_period_ticks: int = 0
@export_range(0, 1800, 1) var pulse_duration_ticks: int = 0
@export_range(1000, 2000, 10) var pulse_speed_permille: int = 1000


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if pattern < Pattern.WANDER or pattern > Pattern.SWEEP:
		errors.append("pattern fora do intervalo")
	if sweep_turn_steps == 0 or sweep_turn_steps < -7 or sweep_turn_steps > 7:
		errors.append("sweep_turn_steps precisa estar em -7..-1 ou 1..7")
	if pursuit_jitter_steps < 0 or pursuit_jitter_steps > 3:
		errors.append("pursuit_jitter_steps precisa estar entre 0 e 3")
	if pulse_period_ticks < 0 or pulse_period_ticks > 3600:
		errors.append("pulse_period_ticks precisa estar entre 0 e 3600")
	if pulse_duration_ticks < 0 or pulse_duration_ticks > 1800:
		errors.append("pulse_duration_ticks precisa estar entre 0 e 1800")
	if pulse_speed_permille < 1000 or pulse_speed_permille > 2000:
		errors.append("pulse_speed_permille precisa estar entre 1000 e 2000")
	if pulse_period_ticks == 0:
		if pulse_duration_ticks != 0:
			errors.append("pulse_duration_ticks precisa ser zero quando o pulso está desativado")
		if pulse_speed_permille != 1000:
			errors.append("pulse_speed_permille precisa ser 1000 quando o pulso está desativado")
	elif pulse_duration_ticks <= 0 or pulse_duration_ticks > pulse_period_ticks:
		errors.append("pulse_duration_ticks precisa estar entre 1 e pulse_period_ticks")
	return errors


func canonical_bytes() -> PackedByteArray:
	var values := [
		PROFILE_VERSION,
		pattern,
		sweep_turn_steps,
		pursuit_jitter_steps,
		pulse_period_ticks,
		pulse_duration_ticks,
		pulse_speed_permille,
	]
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	for index in values.size():
		bytes.encode_s32(index * 4, values[index])
	return bytes
