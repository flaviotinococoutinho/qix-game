extends TestCase

const ROUTE_SCRIPT := "res://tools/m2_capture_route.gd"


func test_production_geometry_reaches_target_in_five_captures_and_opens_round_two() -> void:
	ok(ResourceLoader.exists(ROUTE_SCRIPT), "rota reprodutível M2 precisa existir")
	if not ResourceLoader.exists(ROUTE_SCRIPT):
		return
	var route_script: GDScript = load(ROUTE_SCRIPT)
	ok(route_script != null, "rota M2 precisa compilar")
	if route_script == null:
		return
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	var result: Dictionary = route_script.execute(campaign)
	eq(result.errors, PackedStringArray())
	eq(result.permille_progression, PackedInt32Array([179, 358, 493, 780, 825]))
	eq(result.capture_count, 5)
	eq(result.round_one_score, 12_750)
	eq(result.archived_replay_ticks, 806)
	eq(result.round_index, 1)
	eq(result.phase, GameSession.Phase.ROUND_INTRO)
	eq(result.carried_score, 12_750)
	eq(result.carried_lives, 3)
	eq(result.new_board_owned, 0)
	eq(result.new_replay_ticks, 0)
