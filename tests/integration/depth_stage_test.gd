extends TestCase
## Palco é observador: alternar render, vista plana e movimento não altera gameplay.


func test_projection_uses_one_coordinate_contract_for_center_and_axes() -> void:
	eq(QixDepthStage.screen_to_stage(Vector2(120, 160)), Vector3.ZERO)
	eq(QixDepthStage.screen_to_stage(Vector2(200, 80)), Vector3(1, 1, 0))
	eq(QixDepthStage.screen_to_stage(Vector2(120, 160), 0.1), Vector3(0, 0, 0.1))


func test_original_glbs_have_meshes_and_no_gameplay_colliders() -> void:
	for name in ["surveyor", "core", "walker", "dart", "ember", "beacon"]:
		var packed := load("res://assets/models/lumen/%s.glb" % name) as PackedScene
		ok(packed != null, "modelo original %s precisa importar" % name)
		if packed == null:
			continue
		var actor := packed.instantiate()
		ok(actor.find_children("*", "MeshInstance3D", true, false).size() > 0)
		eq(actor.find_children("*", "CollisionObject3D", true, false).size(), 0)
		actor.free()


func test_terminal_dissolve_reads_session_progress_without_advancing_archived_simulation() -> void:
	var session := GameSession.new(load("res://content/campaigns/main_campaign.tres") as CampaignDefinition)
	session.phase = GameSession.Phase.ROUND_CLEAR
	session.transition_ticks_total = 150
	session.transition_ticks_left = 150
	var checksum := session.simulation.state_checksum()
	eq(QixBootstrap.terminal_actor_alpha(session), 1.0)
	for tick in 24:
		session.step(MoveIntent.none())
	eq(QixBootstrap.terminal_actor_alpha(session), 0.0)
	eq(session.simulation.state_checksum(), checksum)
	session.phase = GameSession.Phase.CAMPAIGN_COMPLETE
	eq(QixBootstrap.terminal_actor_alpha(session), 0.0)
