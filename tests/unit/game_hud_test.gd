extends TestCase


func test_boss_death_message_is_immediate_and_specific() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _simulation_in_dying_phase()
	hud.sync(simulation, false, [GameEvent.make(
		GameEvent.Kind.PLAYER_DIED,
		{"reason": GameSimulation.DeathReason.BOSS_CONTACT, "lives": simulation.lives},
	)])
	eq((hud.get_node("Status") as Label).text, "CONTATO! · REENTRADA")
	hud.free()


func test_shield_death_message_is_immediate_and_specific() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _simulation_in_dying_phase()
	hud.sync(simulation, false, [GameEvent.make(
		GameEvent.Kind.PLAYER_DIED,
		{"reason": GameSimulation.DeathReason.SHIELD_EXPIRED, "lives": simulation.lives},
	)])
	eq((hud.get_node("Status") as Label).text, "ESCUDO ESGOTADO · REENTRADA")
	hud.free()


func _simulation_in_dying_phase() -> GameSimulation:
	var rules := GameRules.new()
	var round_definition := RoundDefinition.new()
	var simulation := GameSimulation.new(rules, round_definition, 37)
	simulation.phase = GameSimulation.Phase.DYING
	return simulation
