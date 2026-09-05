class_name GameSimulation
extends RefCounted
## Orquestrador de uma rodada: dono da ordem do tick, da arbitragem e do checksum composto.
## `step(intent)` avança exatamente um tick. Os estados vivem em objetos pequenos
## (`PlayerState`, `BossState`, `ScoreLedger`, `ShieldClock`) e as regras em funções estáticas
## (`PlayerMotion`, `BossMotion`, `BossBehaviorController`, `FloodFillCaptureResolver`).
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

var rules: GameRules
var round_def: RoundDefinition
var seed_value: int
var round_start_state: RoundStartState

var board: BoardState
var rng: DeterministicRng
var resolver := FloodFillCaptureResolver.new()

var player := PlayerState.new()
var boss := BossState.new()
var ledger := ScoreLedger.new()
var shield := ShieldClock.new()

var tick: int = 0
var phase: int = Phase.PLAYING
var lives: int
var death_ticks_left: int = 0
var speedup_active: bool = false

# ---------------------------------------------------------------------------------------------
# Fachada de leitura. Views, HUD e testes leem por aqui; os setters existem para fixtures de
# apresentação e nunca são chamados por quem observa a simulação em jogo.
# ---------------------------------------------------------------------------------------------

var px: int:
	get: return player.px
	set(value): player.px = value
var py: int:
	get: return player.py
	set(value): player.py = value
var pdir: int:
	get: return player.pdir
	set(value): player.pdir = value
var trail: PackedInt32Array:
	get: return player.trail
	set(value): player.trail = value
var trail_active: bool:
	get: return player.trail_active
	set(value): player.trail_active = value
var first_vertex: Vector2i:
	get: return player.first_vertex
	set(value): player.first_vertex = value
var segment_len: int:
	get: return player.segment_len
	set(value): player.segment_len = value
var trail_px_since_score: int:
	get: return player.trail_px_since_score
	set(value): player.trail_px_since_score = value

var score: int:
	get: return ledger.score
	set(value): ledger.score = value
var permille: int:
	get: return ledger.permille
	set(value): ledger.permille = value
var fills_done: int:
	get: return ledger.fills_done
	set(value): ledger.fills_done = value
var permille_remainder: int:
	get: return ledger.permille_remainder
	set(value): ledger.permille_remainder = value

var shield_ticks: int:
	get: return shield.ticks
	set(value): shield.ticks = value
var shield_critical_sent: bool:
	get: return shield.critical_sent
	set(value): shield.critical_sent = value

var boss_alive: bool:
	get: return boss.alive
	set(value): boss.alive = value
var bx_fp: int:
	get: return boss.x_fp
	set(value): boss.x_fp = value
var by_fp: int:
	get: return boss.y_fp
	set(value): boss.y_fp = value
var bvx_fp: int:
	get: return boss.vx_fp
	set(value): boss.vx_fp = value
var bvy_fp: int:
	get: return boss.vy_fp
	set(value): boss.vy_fp = value
var boss_dir_index: int:
	get: return boss.dir_index
	set(value): boss.dir_index = value
var boss_effective_speed_fp: int:
	get: return boss.effective_speed_fp
	set(value): boss.effective_speed_fp = value


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
	ledger.reset(round_start_state.score)
	shield.reset(rules)
	death_ticks_left = 0
	speedup_active = false
	player.reset(round_def.player_spawn)
	assert(board.get_cell(player.px, player.py) == BoardState.Cell.BOUNDARY, "spawn precisa estar na moldura")
	boss.reset(round_def.boss_start, round_def.boss_dir_index)
	boss.set_velocity(
		boss.dir_index,
		BossBehaviorController.effective_speed_fp(rules.boss_behavior, rules.boss_speed_fp, tick),
	)
	assert(board.get_cell(boss.cell().x, boss.cell().y) == BoardState.Cell.FREE, "chefe nasce em FREE")


func boss_cell() -> Vector2i:
	return boss.cell()


## Células que o chefe ocupa para contato: centro + cruz (raio 1).
func boss_contact_cells() -> PackedInt32Array:
	return boss.contact_cells(board)


func player_index() -> int:
	return player.index_in(board)


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
	var intent := MoveIntent.make(raw_intent.direction, raw_intent.drawing or player.trail_active)
	if intent.direction < MoveIntent.Dir.NONE or intent.direction > MoveIntent.Dir.LEFT:
		intent.direction = MoveIntent.Dir.NONE

	# 2/3. jogador
	var lethal := false
	var lethal_reason := DeathReason.BOSS_CONTACT
	var plan: RefCounted = null
	var substeps := _player_substeps()
	for _s in substeps:
		var result := PlayerMotion.substep(player, board, rules, intent, ledger, events)
		if BossMotion.touches_player(boss, board, player):
			lethal = true
		if result == PlayerMotion.StepResult.CLOSED:
			plan = resolver.resolve(board, player.trail, _anchor_indices())
			break  # fill armado → o jogador para (§4.3)

	# 4. chefe: todos os subpassos, testando cada célula varrida
	if boss.alive and BossMotion.update(boss, board, rules, tick, player, rng):
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
			PlayerMotion.undo_trail(player, board)  # política da simulação: rejeição desfaz a trilha sem morte

	# 7. shield
	if phase == Phase.PLAYING:
		var paused := rules.shield_pauses_during_trail and player.trail_active
		match shield.advance(rules, paused):
			ShieldClock.Outcome.CRITICAL:
				events.append(GameEvent.make(GameEvent.Kind.SHIELD_CRITICAL))
			ShieldClock.Outcome.EXPIRED:
				_die(DeathReason.SHIELD_EXPIRED, events)

	tick += 1
	return events


func _player_substeps() -> int:
	if not speedup_active:
		return rules.substeps_normal
	if player.trail_active and player.segment_len < rules.new_segment_slow_px:
		return rules.substeps_normal
	return rules.substeps_speedup


func _anchor_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	if boss.alive and round_def.boss_protects_territory:
		var c := boss.cell()
		out.append(board.index_of(c.x, c.y))
	return out


# --- captura ----------------------------------------------------------------------------------

func _commit_capture(plan: CapturePlan, events: Array[GameEvent]) -> void:
	var before := board.owned_interior
	if not board.apply_capture_plan(plan):
		events.append(GameEvent.make(GameEvent.Kind.CAPTURE_REJECTED,
			{"code": -1, "message": "board recusou o plano (versão %d ≠ %d)" % [plan.board_version, board.version]}))
		PlayerMotion.undo_trail(player, board)
		return
	assert(board.owned_interior - before == plan.filled_delta)
	PlayerMotion.consolidate_trail(player)
	var old_permille := ledger.record_fill(board, rules, plan.filled_delta)
	events.append(GameEvent.make(GameEvent.Kind.CAPTURED, {
		"claimed": plan.claimed_indices.size(), "trail": plan.trail_indices.size(),
		"filled_delta": plan.filled_delta, "permille": ledger.permille}))
	if ledger.permille != old_permille:
		events.append(GameEvent.make(GameEvent.Kind.PERCENT_CHANGED, {"permille": ledger.permille}))
		ledger.add((ledger.permille - old_permille) * rules.area_points_per_permille, events)
	if ledger.permille >= rules.target_permille:
		phase = Phase.ROUND_WON
		ledger.add(rules.completion_bonus, events)
		events.append(GameEvent.make(GameEvent.Kind.ROUND_WON, {"permille": ledger.permille, "score": ledger.score}))


# --- morte ------------------------------------------------------------------------------------

func _die(reason: int, events: Array[GameEvent]) -> void:
	var had_trail := player.trail_active
	PlayerMotion.undo_trail(player, board)  # §4.6: desfaz a trilha até o primeiro vértice; nenhum resíduo TRAIL
	if not had_trail:
		player.first_vertex = player.cell()
	lives -= 1
	phase = Phase.DYING
	death_ticks_left = rules.death_ticks
	events.append(GameEvent.make(GameEvent.Kind.PLAYER_DIED, {"reason": reason, "lives": lives}))


func _respawn(events: Array[GameEvent]) -> void:
	if lives <= 0:
		phase = Phase.GAME_OVER
		events.append(GameEvent.make(GameEvent.Kind.GAME_OVER))
		return
	player.px = player.first_vertex.x
	player.py = player.first_vertex.y
	player.pdir = MoveIntent.Dir.NONE
	shield.reset(rules)
	phase = Phase.PLAYING
	events.append(GameEvent.make(GameEvent.Kind.PLAYER_RESPAWNED, {"x": player.px, "y": player.py}))


# --- checksum ---------------------------------------------------------------------------------

## SHA-256 de todo o estado em bytes canônicos, ordem fixa. Nunca JSON/Dictionary/hash().
## A ordem abaixo é contrato: mudar exige bump de `GameRules.RULES_VERSION` e dourados novos.
func state_checksum() -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(board.canonical_bytes())
	var vals: Array[int] = [tick, phase, lives]
	vals.append_array(ledger.canonical_values())
	vals.append_array(shield.canonical_values())
	vals.append_array([death_ticks_left, 1 if speedup_active else 0])
	vals.append_array(player.canonical_values())
	vals.append_array(boss.canonical_values())
	vals.append_array([rng.state, player.trail.size()])
	var b := PackedByteArray()
	b.resize(vals.size() * 4)
	for k in vals.size():
		b.encode_s32(k * 4, vals[k])
	ctx.update(b)
	if player.trail.size() > 0:
		ctx.update(player.trail.to_byte_array())
	return ctx.finish()
