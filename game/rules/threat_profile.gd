class_name ThreatProfile
extends Resource
## Perfil autorável do diretor de ameaça e dos atores menores. Só inteiros; entra nos bytes
## canônicos de `GameRules` e, portanto, no contrato de replay.
##
## A escada de 16 degraus tem a forma de `enemy_rate_table` (reference/volfied/06-gameplay.md
## §10): intervalo 384→48 em passos de 48, "respiro" no índice 11 quando a velocidade dobra, e
## piso 24 em vez de 3 — vinte dardos por segundo é mangueira, não teste de habilidade num campo
## de 1 px por célula. Os valores marcados DESIGN_DECISION são deste jogo.

const PROFILE_VERSION := 2
const LADDER_SIZE := 16

## Desligado, o diretor fica inerte e nenhum ator menor nasce (QA e rotas de isolamento).
@export var enabled: bool = true
## Degraus extra por rodada (0 / 1 / 3 na campanha) — a face difícil de um setor.
@export_range(0, 8, 1) var pressure_bonus: int = 0
## Um degrau de tempo a cada N ticks, teto 6 (DESIGN_DECISION: 15 s).
@export_range(60, 7200, 1) var time_step_ticks: int = 900
## Um degrau de território a cada N permille, teto 6 (12,5 % até o alvo de 80 %).
@export_range(25, 1000, 1) var area_step_permille: int = 125
## Limite de tempo da rodada; depois dele o índice sobe a cada `overtime_step_ticks` (§10).
@export_range(600, 36000, 1) var round_time_limit_ticks: int = 5400
@export_range(60, 3600, 1) var overtime_step_ticks: int = 300

@export var ladder_dart_interval: PackedInt32Array = PackedInt32Array(
	[384, 336, 288, 240, 192, 144, 96, 72, 60, 48, 40, 96, 72, 48, 32, 24])
## 85 = um passo a cada 3 frames; 128 = a cada 2; 256 = a cada frame; 512 = dois por frame (§10).
@export var ladder_dart_speed_fp: PackedInt32Array = PackedInt32Array(
	[85, 85, 85, 85, 85, 85, 85, 85, 128, 256, 256, 512, 512, 512, 512, 512])
@export var ladder_walker_speed_fp: PackedInt32Array = PackedInt32Array(
	[64, 64, 72, 80, 88, 96, 104, 112, 120, 128, 136, 144, 152, 160, 176, 192])
@export var ladder_max_walkers: PackedInt32Array = PackedInt32Array(
	[1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4])

@export_range(60, 7200, 1) var walker_spawn_interval_ticks: int = 600
@export_range(0, 600, 1) var walker_warmup_ticks: int = 30
@export_range(1, 3600, 1) var walker_dormant_ticks: int = 60
@export_range(0, 100000, 1) var walker_trap_points: int = 500
@export_range(0, 600, 1) var dart_warmup_ticks: int = 24
@export_range(2, 200, 1) var dart_min_range: int = 24
@export_range(60, 36000, 1) var dart_life_ticks: int = 900
## 384 = 1,5 célula por tick contra 2 do jogador: fechar escapa, hesitar morre.
@export_range(1, 512, 1) var ember_speed_fp: int = 384
## Aviso antes de a brasa avançar; cortes perto da cabeça sempre deixam tempo de reação.
@export_range(1, 600, 1) var ember_warmup_ticks: int = 12
## Um ator eliminado mantém identidade/posição para apresentar sua dissipação.
@export_range(0, 600, 1) var actor_despawn_ticks: int = 12
## §3.3 #8 player_stall_counter; o limiar é nosso: 0,75 s parado a meio de um traço.
@export_range(1, 3600, 1) var stall_ignite_ticks: int = 45
@export_range(1, 36000, 1) var camp_dart_ticks: int = 240
## ≈ TrailExposure.WARNING_RATIO com piso 8 e teto 127; o aviso do HUD ganha consequência.
@export_range(1, 400, 1) var exposure_dart_px: int = 68
@export_range(0, 1000, 1) var calm_capture_permille: int = 150
@export_range(0, 3600, 1) var calm_ticks: int = 300
@export_range(0, 1000, 1) var streak_capture_permille: int = 15
@export_range(1, 20, 1) var streak_trigger: int = 4
## Justiça: nenhum ator nasce a menos disto do jogador (Manhattan), nem no tick de um fechamento.
@export_range(0, 200, 1) var spawn_safe_radius: int = 16
## Após reentrada, atores menores não matam por este tempo (o Núcleo continua letal).
@export_range(0, 600, 1) var respawn_grace_ticks: int = 60
@export_range(0, 600, 1) var spawn_retry_ticks: int = 60


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for name in ["ladder_dart_interval", "ladder_dart_speed_fp", "ladder_walker_speed_fp", "ladder_max_walkers"]:
		var ladder: PackedInt32Array = get(name)
		if ladder.size() != LADDER_SIZE:
			errors.append("%s precisa ter %d degraus" % [name, LADDER_SIZE])
	for value in ladder_dart_interval:
		if value < 1:
			errors.append("ladder_dart_interval precisa ser positivo")
			break
	for value in ladder_dart_speed_fp:
		if value < 1 or value > 512:
			errors.append("ladder_dart_speed_fp precisa estar entre 1 e 512 (dois passos por tick)")
			break
	for value in ladder_walker_speed_fp:
		if value < 1 or value > 256:
			errors.append("ladder_walker_speed_fp precisa estar entre 1 e 256 (nunca salta célula)")
			break
	for value in ladder_max_walkers:
		if value < 0 or value > MinorActorPools.MAX_WALKERS:
			errors.append("ladder_max_walkers precisa estar entre 0 e %d" % MinorActorPools.MAX_WALKERS)
			break
	if ember_speed_fp < 1 or ember_speed_fp > 512:
		errors.append("ember_speed_fp acima de dois índices por tick torna a brasa injusta")
	if dart_min_range < spawn_safe_radius:
		errors.append("dart_min_range precisa ser maior ou igual a spawn_safe_radius")
	for name in ["time_step_ticks", "area_step_permille", "round_time_limit_ticks", "overtime_step_ticks",
		"walker_spawn_interval_ticks", "walker_dormant_ticks", "dart_life_ticks", "stall_ignite_ticks",
		"camp_dart_ticks", "exposure_dart_px", "streak_trigger", "ember_warmup_ticks"]:
		if int(get(name)) <= 0:
			errors.append("%s precisa ser positivo" % name)
	for name in ["pressure_bonus", "walker_warmup_ticks", "walker_trap_points", "dart_warmup_ticks",
		"calm_ticks", "calm_capture_permille", "streak_capture_permille", "spawn_safe_radius",
		"respawn_grace_ticks", "spawn_retry_ticks", "actor_despawn_ticks"]:
		if int(get(name)) < 0:
			errors.append("%s não pode ser negativo" % name)
	if dart_min_range < 2:
		errors.append("dart_min_range precisa ser pelo menos 2")
	if pressure_bonus > 8 or spawn_safe_radius > 200 or actor_despawn_ticks > 600:
		errors.append("pressão, raio seguro ou dissipação acima do limite autorável")
	if calm_capture_permille > 1000 or streak_capture_permille > 1000:
		errors.append("limiar de captura precisa estar em 0..1000")
	return errors


func canonical_bytes() -> PackedByteArray:
	var values: Array[int] = [
		PROFILE_VERSION, 1 if enabled else 0, pressure_bonus, time_step_ticks, area_step_permille,
		round_time_limit_ticks, overtime_step_ticks,
	]
	values.append_array(Array(ladder_dart_interval))
	values.append_array(Array(ladder_dart_speed_fp))
	values.append_array(Array(ladder_walker_speed_fp))
	values.append_array(Array(ladder_max_walkers))
	values.append_array([
		walker_spawn_interval_ticks, walker_warmup_ticks, walker_dormant_ticks, walker_trap_points,
		dart_warmup_ticks, dart_min_range, dart_life_ticks, ember_speed_fp, stall_ignite_ticks,
		camp_dart_ticks, exposure_dart_px, calm_capture_permille, calm_ticks,
		streak_capture_permille, streak_trigger, spawn_safe_radius, respawn_grace_ticks,
		spawn_retry_ticks, ember_warmup_ticks, actor_despawn_ticks,
	])
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	for index in values.size():
		bytes.encode_s32(index * 4, values[index])
	return bytes


## Um perfil inerte para QA: sem atores, sem escada — reproduz o jogo de uma só ameaça.
static func inert() -> ThreatProfile:
	var profile := ThreatProfile.new()
	profile.enabled = false
	return profile
