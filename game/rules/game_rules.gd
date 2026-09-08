class_name GameRules
extends Resource
## Configuração autorada e imutável em runtime. Toda regra numérica do domínio vive aqui;
## a proveniência está em reference/volfied/06-gameplay.md ou marcada como DESIGN_DECISION.

## Incrementar sempre que uma regra mude de forma que altere checksums de replay.
## 3: elenco menor, diretor de ameaça, fases do Núcleo, fallback de direção (ADR-0010/0011).
## 4: ciclos de vida, balizas, itens temporizados, selamento e escada de bônus.
const RULES_VERSION := 4
const BossBehaviorProfileScript = preload("res://game/rules/boss_behavior_profile.gd")
const ThreatProfileScript = preload("res://game/rules/threat_profile.gd")
const ItemProfileScript = preload("res://game/rules/item_profile.gd")
const BonusLadderScript = preload("res://game/simulation/scoring/bonus_ladder.gd")

enum PercentMode {
	EXACT,       ## permille = owned * 1000 / interior  (DESIGN_DECISION do remake)
	VOLFIED_63,  ## 63 px = 0,1 %, resto acumulado, +0,6 % no 6.º fill, satura em 999 (§5.7/§6.1)
}

## Razão de fim de rodada (§12.5), gravada em `GameSimulation.round_end_reason`.
enum RoundEndReason { NONE, TARGET, SINGLE_FILL, SEALED }

@export var lives_start: int = 3                 ## §8.1 (valor padrão; DIP no original)
@export var target_permille: int = 800           ## §6.4: 80,0 %
@export var percent_mode: PercentMode = PercentMode.EXACT

@export var trail_score_every_px: int = 4        ## §4.5a: a cada 4 px de trilha…
@export var trail_score_points: int = 10         ## …1 unidade = 10 pontos no ecrã
@export var area_points_per_permille: int = 10   ## §6.3: 100 pontos por 1 %
@export var completion_bonus: int = 1000         ## DESIGN_DECISION local; escada de §12.6 fora do G1

@export var shield_ticks: int = 60 * 30          ## contador autoritativo em ticks
@export var shield_critical_ticks: int = 60 * 5
@export var shield_pauses_during_trail: bool = true  ## perfil Volfied (§9)

@export var substeps_normal: int = 2             ## §4.3: 2 chamadas/frame
## VELOCITY ativa estes subpassos enquanto seu timer estiver vivo. O início de cada segmento
## mantém a velocidade normal até `new_segment_slow_px`, preservando o controle de curvas.
## Ambos entram em canonical_bytes: alterar duração espacial/velocidade muda o contrato de replay.
@export var substeps_speedup: int = 4            ## §4.3: 4 com speed-up…
@export var new_segment_slow_px: int = 8         ## …nunca nos primeiros 8 px de um segmento novo

@export var lethal_contact_wins: bool = true     ## true: contato descarta; false: captura válida evita a morte no mesmo tick
@export var death_ticks: int = 60                ## duração da sequência de morte (apresentação observa)

@export var boss_substeps: int = 2
@export var boss_speed_fp: int = 96              ## ponto fixo 8.8 por subpasso (0,375 px)
@export var boss_turn_every_ticks: int = 45
@export var boss_behavior: Resource = BossBehaviorProfileScript.new()
## Diretor de ameaça e atores menores. `ThreatProfile.inert()` reproduz o jogo de uma só ameaça.
@export var threat: Resource = ThreatProfileScript.new()
@export var items: Resource = ItemProfileScript.new()
@export var bonus_ladder: Resource = BonusLadderScript.new()


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if lives_start <= 0:
		errors.append("lives_start precisa ser positivo")
	if target_permille < 1 or target_permille > 1000:
		errors.append("target_permille precisa estar entre 1 e 1000")
	if trail_score_every_px <= 0:
		errors.append("trail_score_every_px precisa ser positivo")
	if trail_score_points < 0 or area_points_per_permille < 0 or completion_bonus < 0:
		errors.append("pontuação não pode ser negativa")
	if shield_ticks <= 0:
		errors.append("shield_ticks precisa ser positivo")
	if shield_critical_ticks < 0 or shield_critical_ticks > shield_ticks:
		errors.append("shield_critical_ticks fora do intervalo")
	if substeps_normal <= 0 or substeps_speedup <= 0:
		errors.append("substeps precisam ser positivos")
	if new_segment_slow_px < 0:
		errors.append("new_segment_slow_px negativo")
	if death_ticks < 0:
		errors.append("death_ticks negativo")
	if boss_substeps < 0 or boss_substeps > 8:
		errors.append("boss_substeps precisa estar entre 0 e 8")
	if boss_speed_fp < 0 or boss_speed_fp > 256:
		errors.append("boss_speed_fp precisa estar entre 0 e 256")
	if boss_turn_every_ticks < 0 or boss_turn_every_ticks > 3600:
		errors.append("boss_turn_every_ticks precisa estar entre 0 e 3600")
	if boss_behavior == null:
		errors.append("boss_behavior ausente")
	elif not boss_behavior is BossBehaviorProfile or not boss_behavior.has_method("validation_errors") \
		or not boss_behavior.has_method("canonical_bytes") \
		or not boss_behavior.has_method("peak_speed_permille"):
		errors.append("boss_behavior precisa ser BossBehaviorProfile")
	else:
		for error in boss_behavior.validation_errors():
			errors.append("boss_behavior: " + error)
		@warning_ignore("integer_division")
		var peak_speed_fp: int = boss_speed_fp * boss_behavior.peak_speed_permille() / 1000
		if peak_speed_fp > 256:
			errors.append("boss_behavior pode exceder uma célula por subpasso (pico %d)" % peak_speed_fp)
	if threat == null:
		errors.append("threat ausente")
	elif not threat is ThreatProfile or not threat.has_method("validation_errors") or not threat.has_method("canonical_bytes"):
		errors.append("threat precisa ser ThreatProfile")
	else:
		for error in threat.validation_errors():
			errors.append("threat: " + error)
	for name in ["items", "bonus_ladder"]:
		var profile: Resource = get(name)
		var correct_type := (profile is ItemProfile) if name == "items" else (profile is BonusLadder)
		if not correct_type or profile == null or not profile.has_method("validation_errors") or not profile.has_method("canonical_bytes"):
			errors.append("%s precisa ser um perfil autorável válido" % name)
		else:
			for error in profile.validation_errors():
				errors.append("%s: %s" % [name, error])
	return errors


## Bytes canônicos para o hash de configuração do replay.
func canonical_bytes() -> PackedByteArray:
	var vals := [
		RULES_VERSION, lives_start, target_permille, percent_mode,
		trail_score_every_px, trail_score_points, area_points_per_permille, completion_bonus,
		shield_ticks, shield_critical_ticks, 1 if shield_pauses_during_trail else 0,
		substeps_normal, substeps_speedup, new_segment_slow_px,
		1 if lethal_contact_wins else 0, death_ticks,
		boss_substeps, boss_speed_fp, boss_turn_every_ticks,
		1 if boss_behavior != null else 0,
		1 if threat != null else 0, 1 if items != null else 0, 1 if bonus_ladder != null else 0,
	]
	var out := PackedByteArray()
	out.resize(vals.size() * 4)
	for k in vals.size():
		out.encode_s32(k * 4, vals[k])
	if boss_behavior != null and boss_behavior.has_method("canonical_bytes"):
		out.append_array(boss_behavior.canonical_bytes())
	if threat != null and threat.has_method("canonical_bytes"):
		out.append_array(threat.canonical_bytes())
	if items != null and items.has_method("canonical_bytes"):
		out.append_array(items.canonical_bytes())
	if bonus_ladder != null and bonus_ladder.has_method("canonical_bytes"):
		out.append_array(bonus_ladder.canonical_bytes())
	return out
