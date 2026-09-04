extends TestCase

const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"
const EXPECTED_BACKGROUNDS := [
	"res://assets/backgrounds/abyssal_relay.png",
	"res://assets/backgrounds/aurora_foundry.png",
	"res://assets/backgrounds/verdant_singularity_v2.png",
]


func test_main_campaign_is_complete_valid_and_authorable() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "campanha principal precisa existir")
	if campaign == null:
		return
	eq(campaign.resource_path, CAMPAIGN_PATH)
	eq(campaign.campaign_id, &"lumen_cartography")
	eq(campaign.rounds.size(), 3)
	eq(campaign.intro_ticks, 72)
	eq(campaign.clear_ticks, 150)
	eq(campaign.validation_errors(), PackedStringArray())


func test_rounds_reference_separate_gameplay_and_visual_resources() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	var seen_ids := {}
	var seen_seeds := {}
	for index in campaign.rounds.size():
		var content := campaign.rounds[index]
		ok(content.resource_path.begins_with("res://content/rounds/"))
		ok(content.rules.resource_path.begins_with("res://content/rules/"))
		ok(content.round_definition.resource_path.begins_with("res://content/rounds/definitions/"))
		ok(content.visual.resource_path.begins_with("res://content/visuals/"))
		ok(not seen_ids.has(content.round_id), "round_id precisa ser único")
		ok(not seen_seeds.has(content.seed_value), "seed precisa ser única")
		seen_ids[content.round_id] = true
		seen_seeds[content.seed_value] = true


func test_every_round_targets_eighty_percent_and_uses_approved_art() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	for index in campaign.rounds.size():
		var content := campaign.rounds[index]
		eq(content.rules.target_permille, 800)
		eq(content.round_definition.field_width, 225)
		eq(content.round_definition.field_height, 283)
		eq(content.visual.background.resource_path, EXPECTED_BACKGROUNDS[index])
		eq(content.visual.background.get_width(), 225)
		eq(content.visual.background.get_height(), 283)


func test_difficulty_and_reward_progress_across_three_rounds() -> void:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null)
	if campaign == null:
		return
	for index in range(1, campaign.rounds.size()):
		var previous := campaign.rounds[index - 1].rules
		var current := campaign.rounds[index].rules
		ok(current.shield_ticks < previous.shield_ticks, "escudo deve ficar mais curto")
		ok(current.boss_speed_fp > previous.boss_speed_fp, "boss deve acelerar")
		ok(current.boss_turn_every_ticks < previous.boss_turn_every_ticks, "boss deve reagir antes")
		ok(current.completion_bonus > previous.completion_bonus, "bônus deve crescer")
