extends TestCase


func test_frame_ring_is_boundary_and_interior_free() -> void:
	var b := BoardState.new(5, 4)
	for x in 5:
		eq(b.get_cell(x, 0), BoardState.Cell.BOUNDARY, "topo")
		eq(b.get_cell(x, 3), BoardState.Cell.BOUNDARY, "fundo")
	for y in 4:
		eq(b.get_cell(0, y), BoardState.Cell.BOUNDARY, "esquerda")
		eq(b.get_cell(4, y), BoardState.Cell.BOUNDARY, "direita")
	for y in range(1, 3):
		for x in range(1, 4):
			eq(b.get_cell(x, y), BoardState.Cell.FREE, "interior")
	eq(b.interior_cell_count(), 6)
	eq(b.owned_interior, 0)


func test_historical_field_has_62663_interior_cells() -> void:
	var b := BoardState.new(225, 283)
	eq(b.interior_cell_count(), 62663, "06-gameplay.md §4.4: 281 × 223")
	eq(b.cells.size(), 225 * 283)


func test_set_bumps_version_and_checksum_changes() -> void:
	var b := BoardState.new(6, 6)
	var c0 := b.checksum()
	var v0 := b.version
	b.set_cell(2, 2, BoardState.Cell.TRAIL)
	eq(b.version, v0 + 1)
	ne(b.checksum(), c0, "checksum deve mudar com a mutação")
	var b2 := BoardState.new(6, 6)
	b2.set_cell(2, 2, BoardState.Cell.TRAIL)
	eq(b2.checksum(), b.checksum(), "mesmo estado ⇒ mesmo checksum")


func test_apply_plan_rejects_version_mismatch_byte_for_byte() -> void:
	var b := BoardState.new(6, 6)
	var plan := CapturePlan.new()
	plan.board_version = b.version + 1
	plan.claimed_indices = PackedInt32Array([b.index_of(2, 2)])
	plan.filled_delta = 1
	var before := b.canonical_bytes()
	eq(b.apply_capture_plan(plan), false)
	eq(b.canonical_bytes(), before, "estado preservado byte a byte")
	eq(b.owned_interior, 0)


func test_apply_plan_rejects_wrong_cell_state_atomically() -> void:
	var b := BoardState.new(6, 6)
	b.set_cell(3, 3, BoardState.Cell.CLAIMED)
	var plan := CapturePlan.new()
	plan.board_version = b.version
	plan.claimed_indices = PackedInt32Array([b.index_of(2, 2), b.index_of(3, 3)])  # (3,3) já CLAIMED
	plan.filled_delta = 2
	var before := b.canonical_bytes()
	eq(b.apply_capture_plan(plan), false)
	eq(b.canonical_bytes(), before, "nenhuma célula do plano pode ter sido escrita")


func test_apply_plan_converts_and_counts_once() -> void:
	var b := BoardState.new(6, 6)
	b.set_cell(1, 2, BoardState.Cell.TRAIL)
	b.set_cell(2, 2, BoardState.Cell.TRAIL)
	var plan := CapturePlan.new()
	plan.board_version = b.version
	plan.claimed_indices = PackedInt32Array([b.index_of(1, 1), b.index_of(2, 1)])
	plan.trail_indices = PackedInt32Array([b.index_of(1, 2), b.index_of(2, 2)])
	plan.filled_delta = 4
	eq(b.apply_capture_plan(plan), true)
	eq(b.get_cell(1, 1), BoardState.Cell.CLAIMED)
	eq(b.get_cell(1, 2), BoardState.Cell.BOUNDARY, "trilha vira fronteira")
	eq(b.owned_interior, 4)
	eq(b.count_owned_interior(), 4, "contador incremental == recontagem")
	# aplicar de novo o mesmo plano deve falhar (versão mudou) sem mudar nada
	var before := b.canonical_bytes()
	eq(b.apply_capture_plan(plan), false)
	eq(b.canonical_bytes(), before)


func test_index_helpers_roundtrip() -> void:
	var b := BoardState.new(7, 9)
	for y in 9:
		for x in 7:
			var i := b.index_of(x, y)
			eq(b.x_of(i), x)
			eq(b.y_of(i), y)
			eq(b.is_interior_index(i), b.is_interior(x, y))


func test_duplicate_is_independent() -> void:
	var b := BoardState.new(6, 6)
	var d := b.duplicate_board()
	d.set_cell(2, 2, BoardState.Cell.TRAIL)
	eq(b.get_cell(2, 2), BoardState.Cell.FREE, "cópia não afeta o original")
