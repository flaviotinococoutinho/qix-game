class_name BoardState
extends RefCounted
## Única autoridade sobre o território (ADR-0001).
## Uma célula = 1 byte em `cells`; índice = y * width + x. O anel externo é a moldura.
## Ocupação de inimigos, efeitos e apresentação NÃO vivem aqui.

enum Cell { FREE = 0, BOUNDARY = 1, TRAIL = 2, CLAIMED = 3 }

const NEIGHBOR_DX := [0, 1, 0, -1]  # cima, direita, baixo, esquerda — ordem fixa
const NEIGHBOR_DY := [-1, 0, 1, 0]

var width: int
var height: int
var cells: PackedByteArray
## Incrementa a cada mutação. Um CapturePlan só é aplicado se foi planejado nesta versão.
var version: int = 0
## Células interiores que pertencem ao jogador (CLAIMED ou trilha consolidada em BOUNDARY).
## É o numerador do percentual; a moldura inicial fica fora do denominador.
var owned_interior: int = 0


func _init(w: int, h: int) -> void:
	assert(w >= 3 and h >= 3, "board precisa de moldura + interior")
	width = w
	height = h
	cells = PackedByteArray()
	cells.resize(w * h)
	cells.fill(Cell.FREE)
	for x in w:
		cells[x] = Cell.BOUNDARY
		cells[(h - 1) * w + x] = Cell.BOUNDARY
	for y in h:
		cells[y * w] = Cell.BOUNDARY
		cells[y * w + (w - 1)] = Cell.BOUNDARY


func interior_cell_count() -> int:
	return (width - 2) * (height - 2)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func is_interior(x: int, y: int) -> bool:
	return x > 0 and y > 0 and x < width - 1 and y < height - 1


func is_interior_index(i: int) -> bool:
	@warning_ignore("integer_division")
	var y := i / width
	var x := i - y * width
	return is_interior(x, y)


func index_of(x: int, y: int) -> int:
	assert(in_bounds(x, y), "fora do board: (%d,%d)" % [x, y])
	return y * width + x


func x_of(i: int) -> int:
	@warning_ignore("integer_division")
	return i - (i / width) * width


func y_of(i: int) -> int:
	@warning_ignore("integer_division")
	return i / width


func get_cell(x: int, y: int) -> int:
	assert(in_bounds(x, y), "fora do board: (%d,%d)" % [x, y])
	return cells[y * width + x]


func get_index(i: int) -> int:
	assert(i >= 0 and i < cells.size(), "índice fora do array: %d" % i)
	return cells[i]


## Mutação primitiva. Só a simulação e o desfazer de trilha chamam isto diretamente.
func set_index(i: int, state: int) -> void:
	assert(i >= 0 and i < cells.size(), "índice fora do array: %d" % i)
	assert(state >= Cell.FREE and state <= Cell.CLAIMED)
	cells[i] = state
	version += 1


func set_cell(x: int, y: int, state: int) -> void:
	set_index(index_of(x, y), state)


## Aplica o plano uma única vez, atomicamente. Devolve false — sem tocar em um byte —
## se a versão divergir ou se alguma célula não estiver no estado que o plano assume.
func apply_capture_plan(plan: CapturePlan) -> bool:
	if plan.board_version != version:
		return false
	for i in plan.claimed_indices:
		if i < 0 or i >= cells.size() or cells[i] != Cell.FREE or not is_interior_index(i):
			return false
	for i in plan.trail_indices:
		if i < 0 or i >= cells.size() or cells[i] != Cell.TRAIL:
			return false
	for i in plan.claimed_indices:
		cells[i] = Cell.CLAIMED
	for i in plan.trail_indices:
		cells[i] = Cell.BOUNDARY
	owned_interior += plan.filled_delta
	version += 1
	return true


## Recontagem independente do contador incremental; usada por testes de invariante.
func count_owned_interior() -> int:
	var n := 0
	for y in range(1, height - 1):
		var row := y * width
		for x in range(1, width - 1):
			var c := cells[row + x]
			if c == Cell.CLAIMED or c == Cell.BOUNDARY:
				n += 1
	return n


func duplicate_board() -> BoardState:
	var b := BoardState.new(width, height)
	b.cells = cells.duplicate()
	b.version = version
	b.owned_interior = owned_interior
	return b


## Bytes canônicos em ordem fixa: w, h, version, owned_interior (u32 LE) + células.
func canonical_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(16)
	out.encode_u32(0, width)
	out.encode_u32(4, height)
	out.encode_u32(8, version)
	out.encode_u32(12, owned_interior)
	out.append_array(cells)
	return out


func checksum() -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical_bytes())
	return ctx.finish()
