class_name GameSimulation
extends RefCounted
## Dono do estado, da ordem do tick e das regras. `step(intent)` avança exatamente um tick.
##
## Ordem do tick (prompt mestre, "Ordem do tick e determinismo"):
##  1. canonicaliza o intent (trilha ativa força draw);
##  2. subpassos do jogador: escreve trilha e testa contato contra o estado atual;
##  3. fechamento → CapturePlan, TRAIL fica ativa até a arbitragem;
##  4. inimigos em ordem estável (só o chefe no corte), testando todos os segmentos varridos;
##  5. arbitragem: LETHAL_CONTACT_WINS escolhe contato; caso contrário, captura válida vence;
##  6. sem contato, aplica o plano atomicamente (TRAIL → BOUNDARY);
##  7. shield, score, condição de rodada;
##  8. lista ordenada de eventos confirmados.
## Inteiros e ponto fixo 8.8 apenas. Nada aqui lê relógio, Input, Tween ou física.

enum Phase { PLAYING, DYING, ROUND_WON, GAME_OVER }
enum DeathReason { BOSS_CONTACT, SHIELD_EXPIRED }

const BossBehaviorControllerScript = preload("res://game/simulation/enemies/boss_behavior_controller.gd")

const DX := [0, 0, 1, 0, -1]   # indexado por MoveIntent.Dir
const DY := [0, -1, 0, 1, 0]

var rules: GameRules
var round_def: RoundDefinition
var seed_value: int
var round_start_state: RoundStartState

var board: BoardState
var rng: DeterministicRng
var resolver := FloodFillCaptureResolver.new()

var tick: int = 0
var phase: int = Phase.PLAYING
var lives: int
var score: int = 0
var permille: int = 0
var fills_done: int = 0
var permille_remainder: int = 0
var shield_ticks: int
var shield_critical_sent: bool = false
var death_ticks_left: int = 0
var speedup_active: bool = false

# jogador
var px: int
var py: int
var pdir: int = MoveIntent.Dir.NONE
var trail: PackedInt32Array = PackedInt32Array()
var trail_active: bool = false
var first_vertex: Vector2i
var segment_len: int = 0
var trail_px_since_score: int = 0

# chefe (ponto fixo 8.8)
var boss_alive: bool = true
var bx_fp: int
var by_fp: int
var bvx_fp: int
var bvy_fp: int
var boss_dir_index: int
var boss_effective_speed_fp: int


func _init(
	p_rules: GameRules,
	p_round: RoundDefinition,
	p_seed: int,
	p_start_state: RoundStartState = null,
) -> void:
	rules = p_rules
	round_def = p_round
	# O RNG e o formato binário de replay usam exatamente a mesma representação u32.
	seed_value = p_seed & 0xFFFFFFFF
	round_start_state = (
		p_start_state.duplicate_state()
		if p_start_state != null
		else RoundStartState.initial(rules)
	)
	reset_round()


## Reinício limpo: mesmo seed ⇒ mesmo estado inicial ⇒ mesmo checksum.
func reset_round() -> void:
	board = BoardState.new(round_def.field_width, round_def.field_height)
	rng = DeterministicRng.new(seed_value)
	tick = 0
	phase = Phase.PLAYING
	lives = round_start_state.lives
	score = round_start_state.score
	permille = 0
	fills_done = 0
	permille_remainder = 0
	shield_ticks = rules.shield_ticks
	shield_critical_sent = false
	death_ticks_left = 0
	speedup_active = false
	px = round_def.player_spawn.x
	py = round_def.player_spawn.y
	assert(board.get_cell(px, py) == BoardState.Cell.BOUNDARY, "spawn precisa estar na moldura")
	pdir = MoveIntent.Dir.NONE
	trail = PackedInt32Array()
	trail_active = false
	first_vertex = Vector2i(px, py)
	segment_len = 0
	trail_px_since_score = 0
	boss_alive = true
	bx_fp = round_def.boss_start.x << 8
	by_fp = round_def.boss_start.y << 8
	boss_dir_index = round_def.boss_dir_index & 15
	boss_effective_speed_fp = BossBehaviorControllerScript.effective_speed_fp(
		rules.boss_behavior,
		rules.boss_speed_fp,
		tick,
	)
	_set_boss_velocity(boss_dir_index, boss_effective_speed_fp)
	assert(board.get_cell(boss_cell().x, boss_cell().y) == BoardState.Cell.FREE, "chefe nasce em FREE")


func boss_cell() -> Vector2i:
	return Vector2i(bx_fp >> 8, by_fp >> 8)


## Células que o chefe ocupa para contato: centro + cruz (raio 1).
func boss_contact_cells() -> PackedInt32Array:
	var c := boss_cell()
	var out := PackedInt32Array()
	out.append(board.index_of(c.x, c.y))
	for d in 4:
		var nx: int = c.x + BoardState.NEIGHBOR_DX[d]
		var ny: int = c.y + BoardState.NEIGHBOR_DY[d]
		if board.in_bounds(nx, ny):
			out.append(board.index_of(nx, ny))
	return out


func player_index() -> int:
	return board.index_of(px, py)


func interior_cells() -> int:
	return board.interior_cell_count()


# ---------------------------------------------------------------------------------------------
# tick
# ---------------------------------------------------------------------------------------------

func step(raw_intent: MoveIntent) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	if phase == Phase.ROUND_WON or phase == Phase.GAME_OVER:
		tick += 1
		return events  # rodada concluída: nenhuma mutação de gameplay
	if phase == Phase.DYING:
		death_ticks_left -= 1
		if death_ticks_left <= 0:
			_respawn(events)
		tick += 1
		return events

	# 1. canonicalizar
	var intent := MoveIntent.make(raw_intent.direction, raw_intent.drawing or trail_active)
	if intent.direction < MoveIntent.Dir.NONE or intent.direction > MoveIntent.Dir.LEFT:
		intent.direction = MoveIntent.Dir.NONE

	# 2/3. jogador
	var lethal := false
	var lethal_reason := DeathReason.BOSS_CONTACT
	var plan: RefCounted = null
	var substeps := _player_substeps()
	for _s in substeps:
		var closed := _player_substep(intent, events)
		if _player_touches_boss():
			lethal = true
		if closed:
			plan = resolver.resolve(board, trail, _anchor_indices())
			break  # fill armado → o jogador para (§4.3)

	# 4. chefe: todos os subpassos, testando cada célula varrida
	if boss_alive and _boss_update():
		lethal = true

	# 5. arbitragem: somente uma captura válida pode superar contato no mesmo tick.
	if lethal and plan is CapturePlan:
		if rules.lethal_contact_wins:
			plan = null
		else:
			lethal = false
	if lethal:
		_die(lethal_reason, events)
		tick += 1
		return events

	# 6. aplicar plano
	if plan != null:
		if plan is CapturePlan:
			_commit_capture(plan as CapturePlan, events)
		else:
			var err := plan as CaptureError
			events.append(GameEvent.make(GameEvent.Kind.CAPTURE_REJECTED,
				{"code": err.code, "message": err.message}))
			_undo_trail()  # política da simulação: rejeição desfaz a trilha sem morte

	# 7. shield
	if phase == Phase.PLAYING and not (rules.shield_pauses_during_trail and trail_active):
		shield_ticks -= 1
		if shield_ticks <= rules.shield_critical_ticks and not shield_critical_sent:
			shield_critical_sent = true
			events.append(GameEvent.make(GameEvent.Kind.SHIELD_CRITICAL))
		if shield_ticks <= 0:
			_die(DeathReason.SHIELD_EXPIRED, events)

	tick += 1
	return events


func _player_substeps() -> int:
	if not speedup_active:
		return rules.substeps_normal
	if trail_active and segment_len < rules.new_segment_slow_px:
		return rules.substeps_normal
	return rules.substeps_speedup


## Devolve true se este subpasso fechou a trilha numa fronteira.
func _player_substep(intent: MoveIntent, events: Array[GameEvent]) -> bool:
	if intent.direction == MoveIntent.Dir.NONE:
		return false
	var nx: int = px + DX[intent.direction]
	var ny: int = py + DY[intent.direction]
	if not board.in_bounds(nx, ny):
		return false
	var nxt := board.get_cell(nx, ny)
	if not trail_active:
		if nxt == BoardState.Cell.BOUNDARY:
			px = nx
			py = ny
			pdir = intent.direction
			return false
		if nxt == BoardState.Cell.FREE and intent.drawing:
			first_vertex = Vector2i(px, py)
			trail_active = true
			trail = PackedInt32Array()
			segment_len = 0
			trail_px_since_score = 0
			_extend_trail(nx, ny, intent.direction, events)
			events.append(GameEvent.make(GameEvent.Kind.TRAIL_STARTED, {"x": nx, "y": ny}))
			return false
		return false  # FREE sem draw, CLAIMED: não sai da fronteira
	# trilha ativa
	if nxt == BoardState.Cell.FREE:
		_extend_trail(nx, ny, intent.direction, events)
		return false
	if nxt == BoardState.Cell.BOUNDARY:
		px = nx
		py = ny
		pdir = intent.direction
		return true  # fechamento; TRAIL permanece até a arbitragem
	return false  # CLAIMED ou a própria TRAIL: bloqueado (§4.5a "apaga a marca e pára")


func _extend_trail(nx: int, ny: int, dir: int, events: Array[GameEvent]) -> void:
	if pdir != MoveIntent.Dir.NONE and _axis(pdir) != _axis(dir):
		segment_len = 0  # vértice: mudança legal de eixo zera o comprimento do segmento (§4.5b)
	px = nx
	py = ny
	pdir = dir
	var i := board.index_of(nx, ny)
	board.set_index(i, BoardState.Cell.TRAIL)
	trail.append(i)
	segment_len += 1
	trail_px_since_score += 1
	if trail_px_since_score >= rules.trail_score_every_px:
		trail_px_since_score = 0
		_add_score(rules.trail_score_points, events)


static func _axis(dir: int) -> int:
	return 0 if (dir == MoveIntent.Dir.UP or dir == MoveIntent.Dir.DOWN) else 1


func _player_touches_boss() -> bool:
	if not boss_alive:
		return false
	var pi := player_index()
	for c in boss_contact_cells():
		if c == pi:
			return true
		if trail_active and board.cells[c] == BoardState.Cell.TRAIL:
			return true
	return false


func _anchor_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	if boss_alive and round_def.boss_protects_territory:
		var c := boss_cell()
		out.append(board.index_of(c.x, c.y))
	return out


# --- chefe ------------------------------------------------------------------------------------

func _set_boss_velocity(idx: int, speed_fp: int) -> void:
	boss_dir_index = idx & 15
	boss_effective_speed_fp = speed_fp
	bvx_fp = (BossBehaviorControllerScript.DIRECTION_X[boss_dir_index] * speed_fp) >> 8
	bvy_fp = (BossBehaviorControllerScript.DIRECTION_Y[boss_dir_index] * speed_fp) >> 8


## Devolve true se alguma célula varrida tocou jogador ou trilha.
func _boss_update() -> bool:
	var hit := false
	var effective_speed: int = BossBehaviorControllerScript.effective_speed_fp(
		rules.boss_behavior,
		rules.boss_speed_fp,
		tick,
	)
	if effective_speed != boss_effective_speed_fp:
		_set_boss_velocity(boss_dir_index, effective_speed)
	if rules.boss_turn_every_ticks > 0 and tick > 0 and tick % rules.boss_turn_every_ticks == 0:
		var next_direction: int = BossBehaviorControllerScript.next_direction(
			rules.boss_behavior,
			boss_dir_index,
			boss_cell(),
			Vector2i(px, py),
			rng,
		)
		_set_boss_velocity(next_direction, effective_speed)
	for _s in rules.boss_substeps:
		# eixo x
		var cx := bx_fp >> 8
		var cy := by_fp >> 8
		var nx_fp := bx_fp + bvx_fp
		var nx := nx_fp >> 8
		if nx != cx:
			var c := board.get_cell(nx, cy)
			if c == BoardState.Cell.FREE:
				bx_fp = nx_fp
			else:
				if c == BoardState.Cell.TRAIL:
					hit = true
				_set_boss_velocity(
					BossBehaviorControllerScript.reflected_horizontal(boss_dir_index),
					boss_effective_speed_fp,
				)
		else:
			bx_fp = nx_fp
		# eixo y
		cx = bx_fp >> 8
		var ny_fp := by_fp + bvy_fp
		var ny := ny_fp >> 8
		if ny != cy:
			var c2 := board.get_cell(cx, ny)
			if c2 == BoardState.Cell.FREE:
				by_fp = ny_fp
			else:
				if c2 == BoardState.Cell.TRAIL:
					hit = true
				_set_boss_velocity(
					BossBehaviorControllerScript.reflected_vertical(boss_dir_index),
					boss_effective_speed_fp,
				)
		else:
			by_fp = ny_fp
		if _player_touches_boss():
			hit = true
	return hit


# --- captura ----------------------------------------------------------------------------------

func _commit_capture(plan: CapturePlan, events: Array[GameEvent]) -> void:
	var before := board.owned_interior
	if not board.apply_capture_plan(plan):
		events.append(GameEvent.make(GameEvent.Kind.CAPTURE_REJECTED,
			{"code": -1, "message": "board recusou o plano (versão %d ≠ %d)" % [plan.board_version, board.version]}))
		_undo_trail()
		return
	assert(board.owned_interior - before == plan.filled_delta)
	trail = PackedInt32Array()
	trail_active = false
	segment_len = 0
	fills_done += 1
	var old_permille := permille
	_update_permille(plan.filled_delta)
	events.append(GameEvent.make(GameEvent.Kind.CAPTURED, {
		"claimed": plan.claimed_indices.size(), "trail": plan.trail_indices.size(),
		"filled_delta": plan.filled_delta, "permille": permille}))
	if permille != old_permille:
		events.append(GameEvent.make(GameEvent.Kind.PERCENT_CHANGED, {"permille": permille}))
		_add_score((permille - old_permille) * rules.area_points_per_permille, events)
	if permille >= rules.target_permille:
		phase = Phase.ROUND_WON
		_add_score(rules.completion_bonus, events)
		events.append(GameEvent.make(GameEvent.Kind.ROUND_WON, {"permille": permille, "score": score}))


func _update_permille(filled_delta: int) -> void:
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


func _add_score(delta: int, events: Array[GameEvent]) -> void:
	if delta == 0:
		return
	score += delta
	events.append(GameEvent.make(GameEvent.Kind.SCORE_CHANGED, {"score": score, "delta": delta}))


# --- morte ------------------------------------------------------------------------------------

func _undo_trail() -> void:
	for i in trail:
		if board.cells[i] == BoardState.Cell.TRAIL:
			board.set_index(i, BoardState.Cell.FREE)
	trail = PackedInt32Array()
	trail_active = false
	segment_len = 0
	trail_px_since_score = 0


func _die(reason: int, events: Array[GameEvent]) -> void:
	var had_trail := trail_active
	_undo_trail()  # §4.6: desfaz a trilha até o primeiro vértice; nenhum resíduo TRAIL
	if not had_trail:
		first_vertex = Vector2i(px, py)
	lives -= 1
	phase = Phase.DYING
	death_ticks_left = rules.death_ticks
	events.append(GameEvent.make(GameEvent.Kind.PLAYER_DIED, {"reason": reason, "lives": lives}))


func _respawn(events: Array[GameEvent]) -> void:
	if lives <= 0:
		phase = Phase.GAME_OVER
		events.append(GameEvent.make(GameEvent.Kind.GAME_OVER))
		return
	px = first_vertex.x
	py = first_vertex.y
	pdir = MoveIntent.Dir.NONE
	shield_ticks = rules.shield_ticks
	shield_critical_sent = false
	phase = Phase.PLAYING
	events.append(GameEvent.make(GameEvent.Kind.PLAYER_RESPAWNED, {"x": px, "y": py}))


# --- checksum ---------------------------------------------------------------------------------

## SHA-256 de todo o estado em bytes canônicos, ordem fixa. Nunca JSON/Dictionary/hash().
func state_checksum() -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(board.canonical_bytes())
	var vals := [tick, phase, lives, score, permille, fills_done, permille_remainder,
		shield_ticks, 1 if shield_critical_sent else 0, death_ticks_left, 1 if speedup_active else 0,
		px, py, pdir, 1 if trail_active else 0, first_vertex.x, first_vertex.y,
		segment_len, trail_px_since_score,
		1 if boss_alive else 0, bx_fp, by_fp, bvx_fp, bvy_fp, boss_dir_index,
		boss_effective_speed_fp,
		rng.state, trail.size()]
	var b := PackedByteArray()
	b.resize(vals.size() * 4)
	for k in vals.size():
		b.encode_s32(k * 4, vals[k])
	ctx.update(b)
	if trail.size() > 0:
		ctx.update(trail.to_byte_array())
	return ctx.finish()
