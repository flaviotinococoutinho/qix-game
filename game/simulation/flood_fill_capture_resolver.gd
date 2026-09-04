class_name FloodFillCaptureResolver
extends RefCounted
## Resolver puro de captura (06-gameplay.md §5.5: "nunca se preenche o lado onde está o
## inimigo grande"). Recebe board + trilha + anchors já escritos, trata TRAIL como barreira,
## faz BFS a partir dos anchors com fila pré-alocada e ordem fixa de vizinhos, e devolve
## CapturePlan (células FREE não alcançadas viram CLAIMED) ou CaptureError.
## Não altera board, score, entidades nem publica signals.

var _queue: PackedInt32Array = PackedInt32Array()
var _visited: PackedByteArray = PackedByteArray()


## `anchors` são índices de células (centro de cada inimigo com protects_territory).
func resolve(board: BoardState, trail: PackedInt32Array, anchors: PackedInt32Array) -> RefCounted:
	var w := board.width
	var n := board.cells.size()

	# 1. validar a trilha
	if trail.is_empty():
		return CaptureError.new(CaptureError.Code.EMPTY_TRAIL, "trilha vazia")
	_ensure_capacity(n)
	_visited.fill(0)
	var prev := -1
	for k in trail.size():
		var i := trail[k]
		if i < 0 or i >= n:
			return CaptureError.new(CaptureError.Code.TRAIL_OUT_OF_BOUNDS, "trilha[%d]=%d" % [k, i])
		if not board.is_interior_index(i):
			return CaptureError.new(CaptureError.Code.TRAIL_NOT_INTERIOR, "trilha[%d]=%d na moldura" % [k, i])
		if board.cells[i] != BoardState.Cell.TRAIL:
			return CaptureError.new(CaptureError.Code.TRAIL_CELL_NOT_TRAIL, "trilha[%d]=%d não é TRAIL" % [k, i])
		if _visited[i] != 0:
			return CaptureError.new(CaptureError.Code.TRAIL_SELF_CROSS, "trilha repete %d" % i)
		_visited[i] = 2  # marca temporária: célula de trilha
		if prev >= 0 and not _cardinal_adjacent(prev, i, w):
			return CaptureError.new(CaptureError.Code.TRAIL_NOT_CONTIGUOUS, "trilha[%d]→[%d] não é cardinal" % [k - 1, k])
		prev = i
	if not _touches_boundary(board, trail[0]):
		return CaptureError.new(CaptureError.Code.TRAIL_START_NOT_ON_BOUNDARY, "início %d sem fronteira vizinha" % trail[0])
	if not _touches_boundary(board, trail[trail.size() - 1]):
		return CaptureError.new(CaptureError.Code.TRAIL_END_NOT_ON_BOUNDARY, "fim %d sem fronteira vizinha" % trail[trail.size() - 1])

	# 2. validar anchors
	if anchors.is_empty():
		return CaptureError.new(CaptureError.Code.NO_ANCHOR, "nenhum anchor vivo")
	for a in anchors:
		if a < 0 or a >= n:
			return CaptureError.new(CaptureError.Code.ANCHOR_OUT_OF_BOUNDS, "anchor %d" % a)
		if board.cells[a] != BoardState.Cell.FREE:
			return CaptureError.new(CaptureError.Code.ANCHOR_NOT_FREE, "anchor %d não está em FREE" % a)

	# 3. BFS a partir dos anchors; TRAIL/BOUNDARY/CLAIMED são barreiras
	_visited.fill(0)
	var head := 0
	var tail := 0
	for a in anchors:
		if _visited[a] == 0:
			_visited[a] = 1
			_queue[tail] = a
			tail += 1
	var cells := board.cells
	while head < tail:
		var i := _queue[head]
		head += 1
		@warning_ignore("integer_division")
		var y := i / w
		var x := i - y * w
		for d in 4:
			var nx: int = x + BoardState.NEIGHBOR_DX[d]
			var ny: int = y + BoardState.NEIGHBOR_DY[d]
			var j: int = ny * w + nx
			# a moldura é BOUNDARY, portanto nunca saímos do array
			if cells[j] == BoardState.Cell.FREE and _visited[j] == 0:
				_visited[j] = 1
				_queue[tail] = j
				tail += 1

	# 4/5/6. descrever o plano
	var plan := CapturePlan.new()
	plan.board_version = board.version
	plan.trail_indices = trail.duplicate()
	var claimed := PackedInt32Array()
	var free_remaining := 0
	for y in range(1, board.height - 1):
		var row := y * w
		for x in range(1, w - 1):
			var i := row + x
			if cells[i] == BoardState.Cell.FREE:
				if _visited[i] == 0:
					claimed.append(i)
				else:
					free_remaining += 1
	plan.claimed_indices = claimed
	plan.free_remaining = free_remaining
	plan.filled_delta = claimed.size() + trail.size()
	return plan


func _ensure_capacity(n: int) -> void:
	if _queue.size() < n:
		_queue.resize(n)
	if _visited.size() != n:
		_visited.resize(n)


static func _cardinal_adjacent(a: int, b: int, w: int) -> bool:
	var d := b - a
	if d == 1 or d == -1:
		@warning_ignore("integer_division")
		return (a / w) == (b / w)  # mesma linha (sem wrap)
	return d == w or d == -w


static func _touches_boundary(board: BoardState, i: int) -> bool:
	var w := board.width
	@warning_ignore("integer_division")
	var y := i / w
	var x := i - y * w
	for d in 4:
		var nx: int = x + BoardState.NEIGHBOR_DX[d]
		var ny: int = y + BoardState.NEIGHBOR_DY[d]
		if board.cells[ny * w + nx] == BoardState.Cell.BOUNDARY:
			return true
	return false
