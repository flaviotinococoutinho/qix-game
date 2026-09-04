extends TestCase


func test_vertical_cut_claims_side_without_anchor() -> void:
	var board := BoardState.new(9, 9)
	var trail := PackedInt32Array()
	for y in range(1, 8):
		var i := board.index_of(4, y)
		board.set_index(i, BoardState.Cell.TRAIL)
		trail.append(i)
	var anchor := board.index_of(6, 4)
	var result := FloodFillCaptureResolver.new().resolve(board, trail, PackedInt32Array([anchor]))
	ok(result is CapturePlan, "um corte cardinal válido deve produzir CapturePlan")
	if not (result is CapturePlan):
		return
	var plan := result as CapturePlan
	eq(plan.claimed_indices.size(), 21, "três colunas à esquerda × sete linhas")
	eq(plan.trail_indices, trail)
	eq(plan.free_remaining, 21, "lado do chefe permanece livre")
	eq(plan.filled_delta, 28, "área reclamada + trilha consolidada")
	ok(board.apply_capture_plan(plan), "plano válido deve aplicar atomicamente")
	eq(board.get_cell(2, 4), BoardState.Cell.CLAIMED)
	eq(board.get_cell(4, 4), BoardState.Cell.BOUNDARY)
	eq(board.get_cell(6, 4), BoardState.Cell.FREE, "anchor protege o próprio lado")
	eq(board.owned_interior, 28)
	eq(board.count_owned_interior(), board.owned_interior)


func test_self_cross_is_rejected_without_mutation() -> void:
	var board := BoardState.new(7, 7)
	var a := board.index_of(3, 1)
	var b := board.index_of(3, 2)
	board.set_index(a, BoardState.Cell.TRAIL)
	board.set_index(b, BoardState.Cell.TRAIL)
	var before := board.canonical_bytes()
	var trail := PackedInt32Array([a, b, a])
	var result := FloodFillCaptureResolver.new().resolve(
		board,
		trail,
		PackedInt32Array([board.index_of(5, 3)]),
	)
	ok(result is CaptureError)
	if result is CaptureError:
		eq((result as CaptureError).code, CaptureError.Code.TRAIL_SELF_CROSS)
	eq(board.canonical_bytes(), before, "resolver puro não pode mutar o board")
