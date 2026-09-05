class_name BossMotion
extends RefCounted
## Passo de movimento do Núcleo: pulso de velocidade, virada periódica e reflexão canônica em
## qualquer célula não-FREE. Puro: só lê board/regras/tick e o `DeterministicRng` recebido.


## Avança todos os subpassos do chefe. Devolve true se alguma célula varrida tocou o jogador
## ou a trilha. Consome o RNG somente no instante de virada — a ordem de chamadas é contrato.
static func update(
	boss: BossState,
	board: BoardState,
	rules: GameRules,
	tick: int,
	player: PlayerState,
	rng: DeterministicRng,
) -> bool:
	var hit := false
	var effective_speed: int = BossBehaviorController.effective_speed_fp(
		rules.boss_behavior,
		rules.boss_speed_fp,
		tick,
	)
	if effective_speed != boss.effective_speed_fp:
		boss.set_velocity(boss.dir_index, effective_speed)
	if rules.boss_turn_every_ticks > 0 and tick > 0 and tick % rules.boss_turn_every_ticks == 0:
		var next_direction: int = BossBehaviorController.next_direction(
			rules.boss_behavior,
			boss.dir_index,
			boss.cell(),
			player.cell(),
			rng,
		)
		boss.set_velocity(next_direction, effective_speed)
	for _s in rules.boss_substeps:
		# eixo x
		var cx := boss.x_fp >> 8
		var cy := boss.y_fp >> 8
		var nx_fp := boss.x_fp + boss.vx_fp
		var nx := nx_fp >> 8
		if nx != cx:
			var c := board.get_cell(nx, cy)
			if c == BoardState.Cell.FREE:
				boss.x_fp = nx_fp
			else:
				if c == BoardState.Cell.TRAIL:
					hit = true
				boss.set_velocity(
					BossBehaviorController.reflected_horizontal(boss.dir_index),
					boss.effective_speed_fp,
				)
		else:
			boss.x_fp = nx_fp
		# eixo y
		cx = boss.x_fp >> 8
		var ny_fp := boss.y_fp + boss.vy_fp
		var ny := ny_fp >> 8
		if ny != cy:
			var c2 := board.get_cell(cx, ny)
			if c2 == BoardState.Cell.FREE:
				boss.y_fp = ny_fp
			else:
				if c2 == BoardState.Cell.TRAIL:
					hit = true
				boss.set_velocity(
					BossBehaviorController.reflected_vertical(boss.dir_index),
					boss.effective_speed_fp,
				)
		else:
			boss.y_fp = ny_fp
		if touches_player(boss, board, player):
			hit = true
	return hit


## Contato letal: o footprint do chefe cobre a célula do jogador ou uma célula TRAIL viva.
static func touches_player(boss: BossState, board: BoardState, player: PlayerState) -> bool:
	if not boss.alive:
		return false
	var pi := player.index_in(board)
	for c in boss.contact_cells(board):
		if c == pi:
			return true
		if player.trail_active and board.cells[c] == BoardState.Cell.TRAIL:
			return true
	return false
