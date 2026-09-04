class_name RoundStartState
extends RefCounted
## Carry-in explícito de uma rodada. Faz parte do checksum inicial do replay via GameSimulation.

var score: int = 0
var lives: int = 3


static func initial(rules: GameRules) -> RoundStartState:
	var state := RoundStartState.new()
	state.lives = rules.lives_start
	return state


static func carry_from(simulation: GameSimulation) -> RoundStartState:
	var state := RoundStartState.new()
	state.score = simulation.score
	state.lives = simulation.lives
	return state


func duplicate_state() -> RoundStartState:
	var copy := RoundStartState.new()
	copy.score = score
	copy.lives = lives
	return copy
