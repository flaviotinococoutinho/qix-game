extends SceneTree
## Gera os Resources autoráveis da campanha oficial.
##
## Uso:
##   Godot --headless --path . --script res://tools/build_campaign_content.gd

const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"
const CampaignContentTransactionScript := preload(
	"res://tools/campaign_content_transaction.gd",
)
const ROUND_SPECS := [
	{
		"id": &"abyssal_relay",
		"slug": "round_01_abyssal_relay",
		"rules_slug": "standard",
		"boss_profile_slug": "boss_wander",
		"boss_pattern": BossBehaviorProfile.Pattern.WANDER,
		"boss_sweep_steps": 2,
		"boss_pursuit_jitter": 0,
		"boss_pulse_period": 0,
		"boss_pulse_duration": 0,
		"boss_pulse_speed_permille": 1000,
		"seed": 1482031771,
		"boss_start": Vector2i(112, 141),
		"boss_dir": 3,
		"completion_bonus": 1000,
		"shield_ticks": 60 * 30,
		"boss_speed_fp": 96,
		"boss_turn_ticks": 45,
		"boss_phase_turn_ticks": [45, 40, 36],
		"boss_phase_pattern": [-1, -1, BossBehaviorProfile.Pattern.PURSUIT],
		"threat_slug": "threat_calibration",
		"threat_pressure": 0,
		"beacon_cells": [32, 64, 80, 188, 160, 84, 190, 228],
		"display_name": "ABYSSAL RELAY",
		"subtitle": "O relé ainda transmite. Estabilize 80% antes que o escudo apague.",
		"background": "res://assets/backgrounds/abyssal_relay.png",
		"free_color": Color("05131d"),
		"boundary_color": Color("54f5e0"),
		"trail_color": Color("ffd56a"),
		"trail_hot_color": Color("fff4bd"),
		"threat_color": Color("ff4f7b"),
		"accent_color": Color("4aa8c2"),
	},
	{
		"id": &"aurora_foundry",
		"slug": "round_02_aurora_foundry",
		"rules_slug": "pressure",
		"boss_profile_slug": "boss_pursuit",
		"boss_pattern": BossBehaviorProfile.Pattern.PURSUIT,
		"boss_sweep_steps": 2,
		"boss_pursuit_jitter": 1,
		"boss_pulse_period": 360,
		"boss_pulse_duration": 60,
		"boss_pulse_speed_permille": 1150,
		"seed": 189234077,
		"boss_start": Vector2i(70, 156),
		"boss_dir": 11,
		"completion_bonus": 1750,
		"shield_ticks": 60 * 27,
		"boss_speed_fp": 112,
		"boss_turn_ticks": 36,
		"boss_phase_turn_ticks": [36, 33, 30],
		"boss_phase_pattern": [-1, -1, -1],
		"threat_slug": "threat_pressure",
		"threat_pressure": 1,
		"beacon_cells": [28, 100, 72, 222, 148, 60, 194, 166],
		"display_name": "AURORA FOUNDRY",
		"subtitle": "A forja se defende: dardos vêm das bordas, vagalumes patrulham a linha.",
		"background": "res://assets/backgrounds/aurora_foundry.png",
		"free_color": Color("130d24"),
		"boundary_color": Color("67e8ff"),
		"trail_color": Color("ffc857"),
		"trail_hot_color": Color("fff1b0"),
		"threat_color": Color("ff4d8d"),
		"accent_color": Color("a866ff"),
	},
	{
		"id": &"verdant_singularity",
		"slug": "round_03_verdant_singularity",
		"rules_slug": "expert",
		"boss_profile_slug": "boss_sweep",
		"boss_pattern": BossBehaviorProfile.Pattern.SWEEP,
		"boss_sweep_steps": 3,
		"boss_pursuit_jitter": 0,
		"boss_pulse_period": 240,
		"boss_pulse_duration": 48,
		"boss_pulse_speed_permille": 1250,
		"seed": 933117401,
		"boss_start": Vector2i(151, 119),
		"boss_dir": 7,
		"completion_bonus": 2500,
		"shield_ticks": 60 * 24,
		"boss_speed_fp": 128,
		"boss_turn_ticks": 30,
		"boss_phase_turn_ticks": [30, 27, 24],
		"boss_phase_pattern": [-1, -1, -1],
		"threat_slug": "threat_collapse",
		"threat_pressure": 3,
		"beacon_cells": [32, 218, 76, 66, 152, 196, 194, 94],
		"display_name": "VERDANT SINGULARITY",
		"subtitle": "O núcleo colapsa. Sele-o, ou saia com 80% e viva com isso.",
		"background": "res://assets/backgrounds/verdant_singularity_v2.png",
		"free_color": Color("071a16"),
		"boundary_color": Color("71ffbf"),
		"trail_color": Color("ffe066"),
		"trail_hot_color": Color("fff7bd"),
		"threat_color": Color("ff5c72"),
		"accent_color": Color("5fcf96"),
	},
]

var _failures := PackedStringArray()
var _transaction_entries: Array[Dictionary] = []


func _initialize() -> void:
	var authored_rounds: Array[RoundContent] = []
	for spec in ROUND_SPECS:
		var content := _build_round(spec)
		if content != null:
			authored_rounds.append(content)

	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"lumen_cartography"
	campaign.intro_ticks = 72
	campaign.clear_ticks = 150
	campaign.rounds = authored_rounds
	for validation_error in campaign.validation_errors():
		_failures.append("campanha inválida: %s" % validation_error)
	if _failures.is_empty():
		_transaction_entries.append({"resource": campaign, "path": CAMPAIGN_PATH})
		var transaction = CampaignContentTransactionScript.new()
		for transaction_error in transaction.execute(_transaction_entries):
			_failures.append("transação: %s" % transaction_error)
		if transaction.staged_count != _transaction_entries.size():
			_failures.append(
				"transação validou somente %d/%d payloads" % [
					transaction.staged_count,
					_transaction_entries.size(),
				],
			)
		if transaction.promoted_from_stage_count != _transaction_entries.size():
			_failures.append(
				"transação promoveu somente %d/%d payloads de staging" % [
					transaction.promoted_from_stage_count,
					_transaction_entries.size(),
				],
			)
		if _failures.is_empty():
			print(
				"Transação concluída: %d staged, %d committed" % [
					transaction.staged_count,
					transaction.committed_count,
				],
			)
			for entry in _transaction_entries:
				print("salvo: " + String(entry.path))

	if not _failures.is_empty():
		for failure in _failures:
			printerr("ERRO: " + failure)
		quit(1)
		return
	print("Campanha autorável gerada: %s (%d rodadas)" % [CAMPAIGN_PATH, authored_rounds.size()])
	quit(0)


func _build_round(spec: Dictionary) -> RoundContent:
	var boss_behavior := _create_boss_behavior(spec)
	var threat := _create_threat(spec)
	var rules := _create_rules(spec, boss_behavior, threat)
	var definition := _create_round_definition(spec)
	var visual := _create_visual(spec)
	var content := RoundContent.new()
	content.round_id = spec.id
	content.rules = rules
	content.round_definition = definition
	content.seed_value = spec.seed
	content.visual = visual
	for validation_error in content.validation_errors():
		_failures.append("%s inválida: %s" % [spec.slug, validation_error])
	if not _failures.is_empty():
		return null

	var rules_path := "res://content/rules/%s.tres" % spec.rules_slug
	var boss_behavior_path := "res://content/rules/%s.tres" % spec.boss_profile_slug
	var threat_path := "res://content/rules/%s.tres" % spec.threat_slug
	var definition_path := "res://content/rounds/definitions/%s.tres" % spec.slug
	var visual_path := "res://content/visuals/%s.tres" % spec.slug
	var content_path := "res://content/rounds/%s.tres" % spec.slug
	_transaction_entries.append({"resource": boss_behavior, "path": boss_behavior_path})
	_transaction_entries.append({"resource": threat, "path": threat_path})
	_transaction_entries.append({"resource": rules, "path": rules_path})
	_transaction_entries.append({"resource": definition, "path": definition_path})
	_transaction_entries.append({"resource": visual, "path": visual_path})
	_transaction_entries.append({"resource": content, "path": content_path})
	return content


func _create_rules(spec: Dictionary, boss_behavior: BossBehaviorProfile, threat: ThreatProfile) -> GameRules:
	var rules := GameRules.new()
	rules.lives_start = 3
	rules.target_permille = 800
	rules.percent_mode = GameRules.PercentMode.EXACT
	rules.trail_score_every_px = 4
	rules.trail_score_points = 10
	rules.area_points_per_permille = 10
	rules.completion_bonus = spec.completion_bonus
	rules.shield_ticks = spec.shield_ticks
	rules.shield_critical_ticks = 60 * 5
	rules.shield_pauses_during_trail = true
	rules.substeps_normal = 2
	rules.substeps_speedup = 4
	rules.new_segment_slow_px = 8
	rules.lethal_contact_wins = true
	rules.death_ticks = 60
	rules.boss_substeps = 2
	rules.boss_speed_fp = spec.boss_speed_fp
	rules.boss_turn_every_ticks = spec.boss_turn_ticks
	rules.boss_behavior = boss_behavior
	rules.threat = threat
	rules.items = ItemProfile.new()
	rules.items.enabled = true
	rules.bonus_ladder = BonusLadder.new()
	rules.bonus_ladder.enabled = true
	return rules


## Diretor de ameaça por setor: a escada é a mesma (§10), a pressão inicial cresce 0 → 1 → 3.
func _create_threat(spec: Dictionary) -> ThreatProfile:
	var threat := ThreatProfile.new()
	threat.enabled = true
	threat.pressure_bonus = spec.threat_pressure
	return threat


func _create_boss_behavior(spec: Dictionary) -> BossBehaviorProfile:
	var profile := BossBehaviorProfile.new()
	profile.pattern = spec.boss_pattern
	profile.sweep_turn_steps = spec.boss_sweep_steps
	profile.pursuit_jitter_steps = spec.boss_pursuit_jitter
	profile.pulse_period_ticks = spec.boss_pulse_period
	profile.pulse_duration_ticks = spec.boss_pulse_duration
	profile.pulse_speed_permille = spec.boss_pulse_speed_permille
	profile.phase_turn_ticks = PackedInt32Array(spec.boss_phase_turn_ticks)
	profile.phase_pattern = PackedInt32Array(spec.boss_phase_pattern)
	return profile


func _create_round_definition(spec: Dictionary) -> RoundDefinition:
	var definition := RoundDefinition.new()
	definition.field_width = 225
	definition.field_height = 283
	definition.player_spawn = Vector2i(112, 0)
	definition.boss_start = spec.boss_start
	definition.boss_dir_index = spec.boss_dir
	definition.boss_protects_territory = true
	definition.beacon_cells = PackedInt32Array(spec.beacon_cells)
	return definition


func _create_visual(spec: Dictionary) -> RoundVisualDefinition:
	var visual := RoundVisualDefinition.new()
	visual.display_name = spec.display_name
	visual.subtitle = spec.subtitle
	visual.background = load(spec.background) as Texture2D
	visual.free_color = spec.free_color
	visual.boundary_color = spec.boundary_color
	visual.trail_color = spec.trail_color
	visual.trail_hot_color = spec.trail_hot_color
	visual.threat_color = spec.threat_color
	visual.accent_color = spec.accent_color
	return visual
