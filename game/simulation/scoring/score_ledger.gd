class_name ScoreLedger
extends RefCounted
## Pontuação e percentagem confirmadas. Toda variação de score passa por `add`, que emite o
## evento; a percentagem segue o modo de `GameRules` (§6.1 ou exato).

var score: int = 0
var permille: int = 0
var fills_done: int = 0
var permille_remainder: int = 0


func reset(start_score: int) -> void:
	score = start_score
	permille = 0
	fills_done = 0
	permille_remainder = 0


func add(delta: int, events: Array[GameEvent]) -> void:
	if delta == 0:
		return
	score += delta
	events.append(GameEvent.make(GameEvent.Kind.SCORE_CHANGED, {"score": score, "delta": delta}))


## Registra um preenchimento aplicado e recalcula a percentagem. Devolve a percentagem anterior.
func record_fill(board: BoardState, rules: GameRules, filled_delta: int) -> int:
	fills_done += 1
	var old_permille := permille
	match rules.percent_mode:
		GameRules.PercentMode.EXACT:
			@warning_ignore("integer_division")
			permille = board.owned_interior * 1000 / board.interior_cell_count()
		GameRules.PercentMode.VOLFIED_63:
			var acc := permille_remainder + filled_delta
			@warning_ignore("integer_division")
			permille += acc / 63
			permille_remainder = acc % 63
			if fills_done == 6:
				permille += 6
			permille = mini(permille, 999)
	permille = clampi(permille, 0, 1000)
	return old_permille


func canonical_values() -> Array[int]:
	return [score, permille, fills_done, permille_remainder]
