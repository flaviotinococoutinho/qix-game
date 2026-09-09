class_name DartRules
extends RefCounted
## Dardo — o tiro do Núcleo (reference/volfied/ACHADOS_ANOTACAO.md banda 02, §10). Nasce por
## *backtrack* a partir do jogador: escolhe uma direção, recua por células FREE e nasce na última,
## de modo que a reta passe exatamente pela posição do jogador no instante do disparo — desviar
## duas células basta. Fica parado no aviso (`warmup`), depois voa; qualquer célula não-FREE o
## absorve (território conquistado é escudo literal) e uma célula TRAIL vira **corte**: nasce uma
## brasa nesse ponto em vez de morte instantânea.

enum Outcome { NONE, FIRED, CONTACT, CUT, ABSORBED, EXPIRED }

const DIRECTION_X := BossBehaviorController.DIRECTION_X
const DIRECTION_Y := BossBehaviorController.DIRECTION_Y


## Tenta nascer num slot livre. Devolve o slot ou -1. Consome exatamente um `next_below(16)`.
static func try_spawn(
	pools: MinorActorPools,
	board: BoardState,
	player_cell: Vector2i,
	rng: DeterministicRng,
	speed_fp: int,
	min_range: int,
	warmup_ticks: int,
	life_ticks: int,
	cause: int,
) -> int:
	var slot := pools.free_dart_slot()
	if slot < 0:
		return -1
	var base := rng.next_below(16)
	for attempt in 16:
		var dir := (base + attempt * 3) & 15
		var back := (dir + 8) & 15
		# Centro da célula do jogador em 8.8; recua uma célula por passo pela rosa de 16.
		var x_fp := (player_cell.x << 8) + 128
		var y_fp := (player_cell.y << 8) + 128
		var last_x_fp := -1
		var last_y_fp := -1
		var range_cells := 0
		while true:
			x_fp += DIRECTION_X[back]
			y_fp += DIRECTION_Y[back]
			var cx := x_fp >> 8
			var cy := y_fp >> 8
			if not board.in_bounds(cx, cy) or board.get_cell(cx, cy) != BoardState.Cell.FREE:
				break
			last_x_fp = x_fp
			last_y_fp = y_fp
			range_cells += 1
		var spawn_distance := absi((last_x_fp >> 8) - player_cell.x) + absi((last_y_fp >> 8) - player_cell.y)
		if range_cells >= min_range and spawn_distance >= min_range:
			pools.begin_dart(slot, warmup_ticks)
			pools.set_dart(slot, MinorActorPools.D.X_FP, last_x_fp)
			pools.set_dart(slot, MinorActorPools.D.Y_FP, last_y_fp)
			pools.set_dart(slot, MinorActorPools.D.DIR_INDEX, dir)
			pools.set_dart(slot, MinorActorPools.D.SPEED_FP, speed_fp)
			pools.set_dart(slot, MinorActorPools.D.WARMUP, warmup_ticks)
			pools.set_dart(slot, MinorActorPools.D.LIFE, life_ticks)
			pools.set_dart(slot, MinorActorPools.D.CAUSE, cause)
			pools.set_dart(slot, MinorActorPools.D.REASON, MinorActorPools.Reason.SPAWNED)
			pools.set_dart(slot, MinorActorPools.D.AUX, range_cells)
			return slot
	return -1


## Um tick do dardo. `cut_index` (saída) recebe o índice da trilha cortada quando o resultado
## é CUT. Contato usa Chebyshev ≤ 1 contra a célula do jogador, testado a cada subpasso.
static func update(
	pools: MinorActorPools,
	slot: int,
	board: BoardState,
	player: PlayerState,
	lethal_allowed: bool,
	cut_index: Array[int],
	despawn_ticks: int = 12,
) -> int:
	if not pools.dart_alive(slot):
		return Outcome.NONE
	var warmup := pools.dart(slot, MinorActorPools.D.WARMUP)
	if warmup > 0:
		warmup -= 1
		pools.set_dart(slot, MinorActorPools.D.WARMUP, warmup)
		pools.set_dart(slot, MinorActorPools.D.STATE_TICKS, warmup)
		if warmup == 0:
			pools.set_dart(slot, MinorActorPools.D.REASON, MinorActorPools.Reason.FIRED)
			return Outcome.FIRED
		return Outcome.NONE
	pools.set_dart(slot, MinorActorPools.D.STATE, ActorLifecycle.State.ACTIVE)
	pools.set_dart(slot, MinorActorPools.D.STATE_TICKS, 0)
	var life := pools.dart(slot, MinorActorPools.D.LIFE)
	pools.set_dart(slot, MinorActorPools.D.LIFE, maxi(0, life - 1))
	if life <= 0:
		pools.retire_dart(slot, MinorActorPools.Reason.EXPIRED, despawn_ticks)
		return Outcome.EXPIRED
	var speed := pools.dart(slot, MinorActorPools.D.SPEED_FP)
	var dir := pools.dart(slot, MinorActorPools.D.DIR_INDEX)
	@warning_ignore("integer_division")
	var substeps := (speed + 255) / 256
	@warning_ignore("integer_division")
	var step_fp := speed / maxi(1, substeps)
	var x_fp := pools.dart(slot, MinorActorPools.D.X_FP)
	var y_fp := pools.dart(slot, MinorActorPools.D.Y_FP)
	var player_cell := player.cell()
	for substep in substeps:
		var distance_fp := step_fp + (1 if substep < speed % maxi(1, substeps) else 0)
		x_fp += (DIRECTION_X[dir] * distance_fp) >> 8
		y_fp += (DIRECTION_Y[dir] * distance_fp) >> 8
		var cx := x_fp >> 8
		var cy := y_fp >> 8
		pools.set_dart(slot, MinorActorPools.D.X_FP, x_fp)
		pools.set_dart(slot, MinorActorPools.D.Y_FP, y_fp)
		if not board.in_bounds(cx, cy):
			pools.retire_dart(slot, MinorActorPools.Reason.ABSORBED, despawn_ticks)
			return Outcome.ABSORBED
		var cell := board.get_cell(cx, cy)
		if cell == BoardState.Cell.TRAIL:
			var index := player.trail.find(board.index_of(cx, cy))
			pools.retire_dart(slot, MinorActorPools.Reason.CUT_TRAIL, despawn_ticks)
			pools.set_dart(slot, MinorActorPools.D.X_FP, x_fp)
			pools.set_dart(slot, MinorActorPools.D.Y_FP, y_fp)
			cut_index.append(maxi(index, 0))
			return Outcome.CUT
		if cell != BoardState.Cell.FREE:
			pools.retire_dart(slot, MinorActorPools.Reason.ABSORBED, despawn_ticks)
			pools.set_dart(slot, MinorActorPools.D.X_FP, x_fp)
			pools.set_dart(slot, MinorActorPools.D.Y_FP, y_fp)
			return Outcome.ABSORBED
		pools.set_dart(slot, MinorActorPools.D.X_FP, x_fp)
		pools.set_dart(slot, MinorActorPools.D.Y_FP, y_fp)
		if lethal_allowed and board.get_cell(player_cell.x, player_cell.y) == BoardState.Cell.TRAIL \
			and absi(cx - player_cell.x) <= 1 and absi(cy - player_cell.y) <= 1:
			pools.set_dart(slot, MinorActorPools.D.REASON, MinorActorPools.Reason.HIT_PLAYER)
			return Outcome.CONTACT
	pools.set_dart(slot, MinorActorPools.D.REASON, MinorActorPools.Reason.ADVANCE)
	return Outcome.NONE


## Corredor que o dardo ainda vai percorrer, lido do estado confirmado com a mesma aritmética de
## `update()`: mesmos subpassos, mesma parada na borda e na primeira célula não-FREE. Não muta o
## pool nem consome RNG — é leitura pura, para que o aviso de armamento mostre o percurso real.
## O contato com o jogador não encerra o corredor de propósito: o alvo precisa enxergar que a
## reta passa por ele, que é o que torna «desviar duas células basta» uma promessa legível.
static func peek_path(pools: MinorActorPools, slot: int, board: BoardState, max_cells: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not pools.dart_alive(slot) or max_cells <= 0:
		return out
	var speed := pools.dart(slot, MinorActorPools.D.SPEED_FP)
	var dir := pools.dart(slot, MinorActorPools.D.DIR_INDEX)
	var x_fp := pools.dart(slot, MinorActorPools.D.X_FP)
	var y_fp := pools.dart(slot, MinorActorPools.D.Y_FP)
	if not board.in_bounds(x_fp >> 8, y_fp >> 8):
		return out
	# O aviso é redesenhado a cada frame enquanto o dardo está armado, e o campo cheio dá
	# corredores de duas centenas de células. Os invariantes do laço vêm para locais e o
	# subpasso que não troca de célula sai antes de qualquer leitura do campo: mesma
	# aritmética de `update()`, sem o custo por chamada. `board.cells` **não** vira local:
	# copiar o `PackedByteArray` por chamada custa mais do que tudo o que o laço economiza.
	var width := board.width
	var height := board.height
	var last_x := x_fp >> 8
	var last_y := y_fp >> 8
	@warning_ignore("integer_division")
	var substeps := (speed + 255) / 256
	@warning_ignore("integer_division")
	var step_fp := speed / maxi(1, substeps)
	var remainder := speed % maxi(1, substeps)
	var dx_fp: int = DIRECTION_X[dir]
	var dy_fp: int = DIRECTION_Y[dir]
	# `LIFE` limita o corredor pelo mesmo prazo que retira o dardo por EXPIRED.
	for _tick in pools.dart(slot, MinorActorPools.D.LIFE):
		for substep in substeps:
			var distance_fp := step_fp + (1 if substep < remainder else 0)
			x_fp += (dx_fp * distance_fp) >> 8
			y_fp += (dy_fp * distance_fp) >> 8
			var cx := x_fp >> 8
			var cy := y_fp >> 8
			if cx == last_x and cy == last_y:
				continue
			if cx < 0 or cx >= width or cy < 0 or cy >= height:
				return out
			last_x = cx
			last_y = cy
			var index := cy * width + cx
			out.append(index)
			# A célula que absorve ou corta entra no corredor: é onde o dardo termina.
			if board.get_cell(cx, cy) != BoardState.Cell.FREE or out.size() >= max_cells:
				return out
	return out


## Dardos sobre células que deixaram de ser FREE (após uma captura) apagam. Devolve os slots.
static func absorb_grounded(pools: MinorActorPools, board: BoardState, despawn_ticks: int = 12) -> PackedInt32Array:
	var absorbed := PackedInt32Array()
	for slot in MinorActorPools.MAX_DARTS:
		if not pools.dart_alive(slot):
			continue
		var cell := pools.dart_cell(slot)
		if not board.in_bounds(cell.x, cell.y) or board.get_cell(cell.x, cell.y) != BoardState.Cell.FREE:
			pools.retire_dart(slot, MinorActorPools.Reason.ABSORBED, despawn_ticks)
			absorbed.append(slot)
	return absorbed
