extends TestCase


func test_valid_campaign_accepts_distinct_authorable_rounds() -> void:
	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"lumen_cartography"
	campaign.rounds = [
		_content(&"abyssal", 101, 9, 9, Vector2i(6, 4)),
		_content(&"aurora", 202, 9, 9, Vector2i(5, 3)),
	]
	eq(campaign.validation_errors(), PackedStringArray())


func test_campaign_reports_missing_and_duplicate_round_data() -> void:
	var empty := CampaignDefinition.new()
	var empty_errors := empty.validation_errors()
	ok(_contains_fragment(empty_errors, "campaign_id"))
	ok(_contains_fragment(empty_errors, "rounds"))
	var duplicate := CampaignDefinition.new()
	duplicate.campaign_id = &"duplicate"
	duplicate.rounds = [
		_content(&"same", 1, 9, 9, Vector2i(6, 4)),
		_content(&"same", 2, 9, 9, Vector2i(5, 3)),
	]
	ok(_contains_fragment(duplicate.validation_errors(), "duplicado"))


func test_round_validation_rejects_invalid_spawn_boss_and_rules() -> void:
	var content := _content(&"broken", 1, 9, 9, Vector2i(6, 4))
	content.round_definition.player_spawn = Vector2i(4, 4)
	content.round_definition.boss_start = Vector2i(0, 0)
	content.rules.target_permille = 0
	var errors := content.validation_errors()
	ok(_contains_fragment(errors, "player_spawn"))
	ok(_contains_fragment(errors, "boss_start"))
	ok(_contains_fragment(errors, "target_permille"))


func test_authorable_seed_must_fit_nonzero_u32_contract() -> void:
	var content := _content(&"bad_seed", 1, 9, 9, Vector2i(6, 4))
	content.seed_value = -1
	ok(_contains_fragment(content.validation_errors(), "seed_value"))
	content.seed_value = 0x1_0000_0000
	ok(_contains_fragment(content.validation_errors(), "seed_value"))


func _content(
	round_id: StringName,
	seed: int,
	width: int,
	height: int,
	boss: Vector2i,
) -> RoundContent:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	var round_definition := RoundDefinition.new()
	round_definition.field_width = width
	round_definition.field_height = height
	round_definition.player_spawn = Vector2i(4, 0)
	round_definition.boss_start = boss
	var visual := RoundVisualDefinition.new()
	visual.display_name = String(round_id)
	visual.background = ImageTexture.create_from_image(
		Image.create_empty(width, height, false, Image.FORMAT_RGBA8),
	)
	var content := RoundContent.new()
	content.round_id = round_id
	content.seed_value = seed
	content.rules = rules
	content.round_definition = round_definition
	content.visual = visual
	return content


func _contains_fragment(errors: PackedStringArray, fragment: String) -> bool:
	for error in errors:
		if error.contains(fragment):
			return true
	return false
