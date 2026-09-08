class_name WalkerRules
extends RefCounted
## Vagalume de borda — a gramática das faíscas de Qix traduzida: patrulha só a fronteira
## **viva** (BOUNDARY com algum vizinho-8 FREE). Fronteira morta, entre território conquistado
## e a moldura, é corredor seguro: conquistar bem vira caçar, e um vagalume encurralado apaga.
## Funções estáticas puras sobre `MinorActorPools`; o RNG só é usado por quem decide o spawn.

const NEIGHBOR_DX := BoardState.NEIGHBOR_DX
const NEIGHBOR_DY := BoardState.NEIGHBOR_DY

enum StepOutcome { WAITING, MOVED, DORMANT, EXTINGUISHED }


static func is_live_boundary(board: BoardState, x: int, y: int) -> bool:
	if not board.in_bounds(x, y) or board.get_cell(x, y) != BoardState.Cell.BOUNDARY:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if board.in_bounds(nx, ny) and board.get_cell(nx, ny) == BoardState.Cell.FREE:
				return true
	return false


static func spawn(
	pools: MinorActorPools,
	slot: int,
	cell: Vector2i,
	dir: int,
	bias: int,
	warmup_ticks: int,
	cause: int,
) -> void:
	pools.begin_walker(slot, warmup_ticks)
	pools.set_walker(slot, MinorActorPools.W.X, cell.x)
	pools.set_walker(slot, MinorActorPools.W.Y, cell.y)
	pools.set_walker(slot, MinorActorPools.W.DIR, dir & 3)
	pools.set_walker(slot, MinorActorPools.W.BIAS, 1 if bias >= 0 else -1)
	pools.set_walker(slot, MinorActorPools.W.WARMUP, warmup_ticks)
	pools.set_walker(slot, MinorActorPools.W.CAUSE, cause)
	pools.set_walker(slot, MinorActorPools.W.REASON, MinorActorPools.Reason.SPAWNED)


## Direção inicial legal a partir de uma célula da moldura: a primeira das quatro que leva a
## uma fronteira viva, começando pela preferida. -1 se nenhuma.
static func initial_direction(board: BoardState, cell: Vector2i, preferred: int) -> int:
	for offset in 4:
		var dir := (preferred + offset) & 3
		if is_live_boundary(board, cell.x + NEIGHBOR_DX[dir], cell.y + NEIGHBOR_DY[dir]):
			return dir
	return -1


## Um tick do vagalume. Devolve o resultado; o chamador emite eventos e testa contato.
static func update(
	pools: MinorActorPools,
	slot: int,
	board: BoardState,
	speed_fp: int,
	dormant_limit: int,
	despawn_ticks: int = 12,
) -> int:
	if not pools.walker_alive(slot):
		return StepOutcome.WAITING
	if pools.walker(slot, MinorActorPools.W.WARMUP) > 0:
		pools.set_walker(slot, MinorActorPools.W.WARMUP, pools.walker(slot, MinorActorPools.W.WARMUP) - 1)
		pools.set_walker(slot, MinorActorPools.W.STATE_TICKS, pools.walker(slot, MinorActorPools.W.WARMUP))
		if pools.walker(slot, MinorActorPools.W.WARMUP) == 0:
			pools.set_walker(slot, MinorActorPools.W.REASON, MinorActorPools.Reason.ARMED)
		return StepOutcome.WAITING
	var x := pools.walker(slot, MinorActorPools.W.X)
	var y := pools.walker(slot, MinorActorPools.W.Y)
	var dir := pools.walker(slot, MinorActorPools.W.DIR)
	var bias := pools.walker(slot, MinorActorPools.W.BIAS)
	var chosen := choose_direction(board, x, y, dir, bias) if is_live_boundary(board, x, y) else -1
	if chosen < 0:
		var dormant := pools.walker(slot, MinorActorPools.W.DORMANT) + 1
		pools.set_walker(slot, MinorActorPools.W.DORMANT, dormant)
		pools.set_walker(slot, MinorActorPools.W.STATE, ActorLifecycle.State.DORMANT)
		pools.set_walker(slot, MinorActorPools.W.STATE_TICKS, maxi(0, dormant_limit - dormant))
		pools.set_walker(slot, MinorActorPools.W.REASON, MinorActorPools.Reason.DORMANT)
		if dormant >= dormant_limit:
			pools.retire_walker(slot, MinorActorPools.Reason.EXTINGUISHED, despawn_ticks)
			return StepOutcome.EXTINGUISHED
		return StepOutcome.DORMANT
	pools.set_walker(slot, MinorActorPools.W.DORMANT, 0)
	pools.set_walker(slot, MinorActorPools.W.STATE, ActorLifecycle.State.ACTIVE)
	pools.set_walker(slot, MinorActorPools.W.STATE_TICKS, 0)
	var acc := pools.walker(slot, MinorActorPools.W.ACC_FP) + speed_fp
	var moved := false
	while acc >= 256:
		acc -= 256
		chosen = choose_direction(board, x, y, dir, bias)
		if chosen < 0:
			break
		pools.set_walker(slot, MinorActorPools.W.REASON, _reason_for(dir, chosen, bias))
		dir = chosen
		x += NEIGHBOR_DX[dir]
		y += NEIGHBOR_DY[dir]
		moved = true
	pools.set_walker(slot, MinorActorPools.W.ACC_FP, acc)
	pools.set_walker(slot, MinorActorPools.W.X, x)
	pools.set_walker(slot, MinorActorPools.W.Y, y)
	pools.set_walker(slot, MinorActorPools.W.DIR, dir)
	if not moved:
		pools.set_walker(slot, MinorActorPools.W.REASON, MinorActorPools.Reason.KEEP)
	return StepOutcome.MOVED if moved else StepOutcome.WAITING


## Ordem de candidatos: reto, mão, contramão, trás — "reto vence" torna a rota previsível.
static func choose_direction(board: BoardState, x: int, y: int, dir: int, bias: int) -> int:
	for order in 4:
		var candidate := dir
		match order:
			1: candidate = (dir + bias) & 3
			2: candidate = (dir - bias) & 3
			3: candidate = (dir + 2) & 3
		if is_live_boundary(board, x + NEIGHBOR_DX[candidate], y + NEIGHBOR_DY[candidate]):
			return candidate
	return -1


static func _reason_for(from_dir: int, to_dir: int, bias: int) -> int:
	if to_dir == from_dir:
		return MinorActorPools.Reason.KEEP
	if to_dir == ((from_dir + bias) & 3):
		return MinorActorPools.Reason.TURN_HAND
	if to_dir == ((from_dir + 2) & 3):
		return MinorActorPools.Reason.REVERSE
	return MinorActorPools.Reason.TURN_COUNTER


## Telegraph puro: as próximas `count` células que o vagalume vai pisar, pela mesma regra do
## passo real. A view desenha isto sobre o snapshot; o rastro é igual ao futuro por construção.
static func peek_path(pools: MinorActorPools, slot: int, board: BoardState, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not pools.walker_alive(slot) or not is_live_boundary(board, pools.walker_cell(slot).x, pools.walker_cell(slot).y):
		return out
	var x := pools.walker(slot, MinorActorPools.W.X)
	var y := pools.walker(slot, MinorActorPools.W.Y)
	var dir := pools.walker(slot, MinorActorPools.W.DIR)
	var bias := pools.walker(slot, MinorActorPools.W.BIAS)
	for _step in count:
		var chosen := choose_direction(board, x, y, dir, bias)
		if chosen < 0:
			break
		dir = chosen
		x += NEIGHBOR_DX[dir]
		y += NEIGHBOR_DY[dir]
		out.append(board.index_of(x, y))
	return out
