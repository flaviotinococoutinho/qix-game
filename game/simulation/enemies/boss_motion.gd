class_name BossMotion
extends RefCounted
## Passo de movimento do Núcleo: fase por permille, pulso e surto de velocidade, virada
## periódica (com caça à trilha) e reflexão canônica em qualquer célula não-FREE. Puro: só lê
## board/regras/tick e o `DeterministicRng` recebido.

enum Outcome { NONE, HIT }


## Velocidade efetiva neste tick: base × fase × (pulso ou surto), em 8.8. Validada pelas
## regras para nunca passar de 256 por subpasso.
static func speed_for(boss: BossState, rules: GameRules, tick: int) -> int:
	var profile: Resource = rules.boss_behavior
	var base: int = BossBehaviorController.effective_speed_fp(profile, rules.boss_speed_fp, tick)
	if profile == null:
		return base
	var phase_permille := 1000
	if boss.phase < profile.phase_speed_permille.size():
		phase_permille = profile.phase_speed_permille[boss.phase]
	@warning_ignore("integer_division")
	var speed: int = base * phase_permille / 1000
	if boss.burst_left > 0 and base == rules.boss_speed_fp:
		# Surto vale quando o pulso não está ativo; os dois nunca se multiplicam.
		@warning_ignore("integer_division")
		speed = speed * profile.cornered_speed_permille / 1000
	return mini(speed, 256)


static func turn_every(boss: BossState, rules: GameRules) -> int:
	var profile: Resource = rules.boss_behavior
	if profile != null and boss.phase < profile.phase_turn_ticks.size() \
		and profile.phase_turn_ticks[boss.phase] > 0:
		return profile.phase_turn_ticks[boss.phase]
	return rules.boss_turn_every_ticks


## Avança todos os subpassos do chefe. Devolve true se alguma célula varrida tocou o jogador
## ou a trilha. Consome o RNG somente no instante de virada — a ordem de chamadas é contrato.
## Emite `BOSS_PHASE_CHANGED` e `BOSS_CORNERED`; a fúria pede um dardo ao diretor.
static func update(
	boss: BossState,
	board: BoardState,
	rules: GameRules,
	tick: int,
	permille: int,
	player: PlayerState,
	rng: DeterministicRng,
	director: DirectorState,
	events: Array[GameEvent],
) -> bool:
	var profile: Resource = rules.boss_behavior
	# Fase por território conquistado.
	if profile != null:
		var next_phase: int = profile.phase_for_permille(permille)
		if next_phase != boss.phase:
			boss.phase = next_phase
			events.append(GameEvent.make(GameEvent.Kind.BOSS_PHASE_CHANGED, {
				"phase": next_phase, "permille": permille}))
	if boss.burst_left > 0:
		boss.burst_left -= 1
	if boss.stasis_ticks > 0:
		boss.stasis_ticks -= 1
		return false

	var hit := false
	var effective_speed := speed_for(boss, rules, tick)
	if effective_speed != boss.effective_speed_fp:
		boss.set_velocity(boss.dir_index, effective_speed)
	var every := turn_every(boss, rules)
	if every > 0 and tick > 0 and tick % every == 0:
		var next_direction := _decide_direction(boss, board, rules, player, rng)
		boss.set_velocity(next_direction, effective_speed)

	# Janela de fúria: conta reflexões; a janela zera sozinha.
	if profile != null and profile.cornered_window_ticks > 0:
		if boss.window_left <= 0:
			boss.window_left = profile.cornered_window_ticks
			boss.reflections = 0
		else:
			boss.window_left -= 1

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
				boss.reflections += 1
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
				boss.reflections += 1
		else:
			boss.y_fp = ny_fp
		if touches_player(boss, board, player):
			hit = true

	# Fúria emergente: encurralado bate mais nas paredes; o jogador sente que o apertou.
	if profile != null and profile.cornered_reflections > 0 and boss.burst_left <= 0 \
		and boss.reflections >= profile.cornered_reflections:
		boss.reflections = 0
		boss.window_left = profile.cornered_window_ticks
		boss.burst_left = profile.cornered_burst_ticks
		director.cornered_request = 1
		events.append(GameEvent.make(GameEvent.Kind.BOSS_CORNERED, {
			"burst_ticks": profile.cornered_burst_ticks, "phase": boss.phase}))
	return hit


## Direção nova: o padrão da fase, mirando o meio da trilha quando ela está ao alcance (a
## partir de `trail_hunt_from_phase`): o Volfied faz o tiro nascer junto do jogador (§10); aqui
## o Núcleo caça a trilha, que é o que dói.
static func _decide_direction(
	boss: BossState,
	board: BoardState,
	rules: GameRules,
	player: PlayerState,
	rng: DeterministicRng,
) -> int:
	var profile: Resource = rules.boss_behavior
	if profile == null:
		return rng.next_below(16)
	var origin := boss.cell()
	var target := player.cell()
	var pattern: int = profile.pattern_for_phase(boss.phase)
	if player.trail_active and boss.phase >= profile.trail_hunt_from_phase and player.trail.size() > 2:
		@warning_ignore("integer_division")
		var mid_index: int = player.trail[player.trail.size() / 2]
		var mid := Vector2i(board.x_of(mid_index), board.y_of(mid_index))
		if absi(mid.x - origin.x) + absi(mid.y - origin.y) <= profile.trail_hunt_cells:
			target = mid
			pattern = BossBehaviorProfile.Pattern.PURSUIT
	return BossBehaviorController.next_direction_for_pattern(
		pattern,
		profile.sweep_turn_steps,
		profile.pursuit_jitter_steps,
		boss.dir_index,
		origin,
		target,
		rng,
	)


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
