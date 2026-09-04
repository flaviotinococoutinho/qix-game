extends SceneTree
## Uso: Godot --headless --path . --script res://tools/verify_m2_capture_route.gd

const ROUTE := preload("res://tools/m2_capture_route.gd")


func _initialize() -> void:
	var campaign := load("res://content/campaigns/main_campaign.tres") as CampaignDefinition
	var result: Dictionary = ROUTE.execute(campaign)
	print(JSON.stringify(result, "  "))
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	quit(0 if errors.is_empty() else 1)
