class_name BossBehaviorProfile
extends Resource
## Perfil autorável do Núcleo. Apenas dados inteiros entram na simulação e no hash de replay.
##
## v2 acrescenta **fases por permille**: conforme o território fecha, o Núcleo acelera, vira
## antes, pode trocar de padrão e passa a caçar o meio da trilha; e a **fúria emergente**: seis
## reflexões numa janela curta disparam um surto. O ator principal deixa de ser estático dentro
## da rodada — a curva de dificuldade nasce do mapa, não de um roteiro.

const PROFILE_VERSION := 2
const PHASES := 3

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

## Fases: limiares de permille que abrem as fases 1 e 2 (a fase 0 começa em zero).
@export var phase_thresholds_permille: PackedInt32Array = PackedInt32Array([300, 550])
## Multiplicador de velocidade por fase, em permille do `boss_speed_fp` das regras.
@export var phase_speed_permille: PackedInt32Array = PackedInt32Array([1000, 1100, 1200])
## Intervalo de virada por fase; 0 mantém `boss_turn_every_ticks` das regras.
@export var phase_turn_ticks: PackedInt32Array = PackedInt32Array([0, 0, 0])
## Padrão por fase; -1 mantém `pattern`.
@export var phase_pattern: PackedInt32Array = PackedInt32Array([-1, -1, -1])
## A partir desta fase, com trilha viva a ≤ `trail_hunt_cells`, o Núcleo mira o meio da trilha.
@export_range(0, 3, 1) var trail_hunt_from_phase: int = 1
@export_range(0, 400, 1) var trail_hunt_cells: int = 48

## Fúria: reflexões dentro da janela ⇒ surto de velocidade e um dardo (ver ThreatDirector).
@export_range(0, 600, 1) var cornered_window_ticks: int = 60
@export_range(0, 64, 1) var cornered_reflections: int = 6
@export_range(0, 600, 1) var cornered_burst_ticks: int = 90
@export_range(1000, 2000, 10) var cornered_speed_permille: int = 1250


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
	if phase_thresholds_permille.size() != PHASES - 1:
		errors.append("phase_thresholds_permille precisa ter %d limiares" % (PHASES - 1))
	else:
		if phase_thresholds_permille[0] < 1 or phase_thresholds_permille[1] <= phase_thresholds_permille[0] \
			or phase_thresholds_permille[1] > 1000:
			errors.append("phase_thresholds_permille precisa ser crescente em 1..1000")
	for name in ["phase_speed_permille", "phase_turn_ticks", "phase_pattern"]:
		if (get(name) as PackedInt32Array).size() != PHASES:
			errors.append("%s precisa ter %d fases" % [name, PHASES])
	if phase_speed_permille.size() == PHASES:
		for value in phase_speed_permille:
			if value < 500 or value > 2000:
				errors.append("phase_speed_permille precisa estar entre 500 e 2000")
				break
	if phase_turn_ticks.size() == PHASES:
		for value in phase_turn_ticks:
			if value < 0 or value > 3600:
				errors.append("phase_turn_ticks precisa estar entre 0 e 3600")
				break
	if phase_pattern.size() == PHASES:
		for value in phase_pattern:
			if value < -1 or value > Pattern.SWEEP:
				errors.append("phase_pattern precisa ser -1 ou um Pattern")
				break
	if cornered_speed_permille < 1000 or cornered_speed_permille > 2000:
		errors.append("cornered_speed_permille precisa estar entre 1000 e 2000")
	if trail_hunt_from_phase < 0 or trail_hunt_from_phase > PHASES or trail_hunt_cells < 0 or trail_hunt_cells > 400:
		errors.append("caça à trilha fora dos limites de fase/alcance")
	if cornered_window_ticks < 0 or cornered_window_ticks > 600 or cornered_reflections < 0 or cornered_reflections > 64:
		errors.append("janela/reflexões de fúria fora do intervalo")
	if cornered_burst_ticks < 0 or cornered_burst_ticks > 600:
		errors.append("cornered_burst_ticks precisa estar entre 0 e 600")
	if cornered_reflections > 0 and cornered_burst_ticks > 0 and cornered_window_ticks == 0:
		errors.append("fúria habilitada exige uma janela positiva")
	return errors


## Maior multiplicador de velocidade que o perfil pode aplicar, em permille.
func peak_speed_permille() -> int:
	var phase_peak := 1000
	for value in phase_speed_permille:
		phase_peak = maxi(phase_peak, value)
	var burst_peak := maxi(pulse_speed_permille, cornered_speed_permille if cornered_burst_ticks > 0 else 1000)
	@warning_ignore("integer_division")
	return phase_peak * burst_peak / 1000


func phase_for_permille(permille: int) -> int:
	var phase := 0
	for threshold in phase_thresholds_permille:
		if permille >= threshold:
			phase += 1
	return mini(phase, PHASES - 1)


func pattern_for_phase(phase: int) -> int:
	var index := clampi(phase, 0, PHASES - 1)
	if index < phase_pattern.size() and phase_pattern[index] >= 0:
		return phase_pattern[index]
	return pattern


func canonical_bytes() -> PackedByteArray:
	var values: Array[int] = [
		PROFILE_VERSION,
		pattern,
		sweep_turn_steps,
		pursuit_jitter_steps,
		pulse_period_ticks,
		pulse_duration_ticks,
		pulse_speed_permille,
	]
	values.append_array(Array(phase_thresholds_permille))
	values.append_array(Array(phase_speed_permille))
	values.append_array(Array(phase_turn_ticks))
	values.append_array(Array(phase_pattern))
	values.append_array([
		trail_hunt_from_phase, trail_hunt_cells, cornered_window_ticks, cornered_reflections,
		cornered_burst_ticks, cornered_speed_permille,
	])
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	for index in values.size():
		bytes.encode_s32(index * 4, values[index])
	return bytes
