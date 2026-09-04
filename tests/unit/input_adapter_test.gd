extends TestCase


func test_no_pressed_direction_yields_none() -> void:
	eq(GameInputAdapter.choose_direction(false, false, false, false), MoveIntent.Dir.NONE)


func test_single_pressed_direction_is_selected() -> void:
	eq(GameInputAdapter.choose_direction(false, true, false, false), MoveIntent.Dir.RIGHT)


func test_preferred_direction_wins_when_two_directions_overlap() -> void:
	eq(
		GameInputAdapter.choose_direction(true, true, false, false, MoveIntent.Dir.RIGHT),
		MoveIntent.Dir.RIGHT,
	)
	eq(
		GameInputAdapter.choose_direction(true, true, false, false, MoveIntent.Dir.UP),
		MoveIntent.Dir.UP,
	)


func test_canonical_priority_is_used_without_a_pressed_preference() -> void:
	eq(
		GameInputAdapter.choose_direction(true, true, true, true, MoveIntent.Dir.LEFT),
		MoveIntent.Dir.LEFT,
	)
	eq(
		GameInputAdapter.choose_direction(true, true, false, false, MoveIntent.Dir.DOWN),
		MoveIntent.Dir.UP,
	)
