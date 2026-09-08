class_name PlayerMotion
extends RefCounted
## Regras puras de movimento e trilha do cartógrafo (06-gameplay.md §4.3–§4.6).
## Funções estáticas: recebem estado, board e regras; escrevem somente no `PlayerState`, nas
## células TRAIL do board e no `ScoreLedger`. Nunca leem relógio, Input ou acaso.

## Resultado de um subpasso. `BLOCKED` distingue "pedi e não andei" de `IDLE` ("não pedi"):
## é o que permite a uma direção de fallback ser tentada sem estado extra no domínio.
enum StepResult { IDLE, BLOCKED, MOVED, CLOSED }

const DX := [0, 0, 1, 0, -1]   # indexado por MoveIntent.Dir
const DY := [0, -1, 0, 1, 0]


## Um subpasso de uma célula. Devolve `CLOSED` quando a trilha encostou numa fronteira e o
## fechamento precisa ser resolvido; a TRAIL permanece escrita até a arbitragem.
static func substep(
	state: PlayerState,
	board: BoardState,
	rules: GameRules,
	intent: MoveIntent,
	ledger: ScoreLedger,
	events: Array[GameEvent],
) -> int:
	if intent.direction == MoveIntent.Dir.NONE:
		return StepResult.IDLE
	var nx: int = state.px + DX[intent.direction]
	var ny: int = state.py + DY[intent.direction]
	if not board.in_bounds(nx, ny):
		return StepResult.BLOCKED
	var nxt := board.get_cell(nx, ny)
	if not state.trail_active:
		if nxt == BoardState.Cell.BOUNDARY:
			state.px = nx
			state.py = ny
			state.pdir = intent.direction
			return StepResult.MOVED
		if nxt == BoardState.Cell.FREE and intent.drawing:
			state.first_vertex = Vector2i(state.px, state.py)
			state.trail_active = true
			state.trail = PackedInt32Array()
			state.segment_len = 0
			state.trail_px_since_score = 0
			_extend_trail(state, board, rules, nx, ny, intent.direction, ledger, events)
			events.append(GameEvent.make(GameEvent.Kind.TRAIL_STARTED, {"x": nx, "y": ny}))
			return StepResult.MOVED
		return StepResult.BLOCKED  # FREE sem draw, CLAIMED: não sai da fronteira
	# trilha ativa
	if nxt == BoardState.Cell.FREE:
		_extend_trail(state, board, rules, nx, ny, intent.direction, ledger, events)
		return StepResult.MOVED
	if nxt == BoardState.Cell.BOUNDARY:
		state.px = nx
		state.py = ny
		state.pdir = intent.direction
		return StepResult.CLOSED  # fechamento; TRAIL permanece até a arbitragem
	return StepResult.BLOCKED  # CLAIMED ou a própria TRAIL: bloqueado (§4.5a "apaga a marca e pára")


static func _extend_trail(
	state: PlayerState,
	board: BoardState,
	rules: GameRules,
	nx: int,
	ny: int,
	dir: int,
	ledger: ScoreLedger,
	events: Array[GameEvent],
) -> void:
	if state.pdir != MoveIntent.Dir.NONE and axis_of(state.pdir) != axis_of(dir):
		state.segment_len = 0  # vértice: mudança legal de eixo zera o comprimento do segmento (§4.5b)
	state.px = nx
	state.py = ny
	state.pdir = dir
	var i := board.index_of(nx, ny)
	board.set_index(i, BoardState.Cell.TRAIL)
	state.trail.append(i)
	state.segment_len += 1
	state.trail_px_since_score += 1
	if state.trail_px_since_score >= rules.trail_score_every_px:
		state.trail_px_since_score = 0
		ledger.add(rules.trail_score_points, events)


## Desfaz a trilha até o primeiro vértice: nenhum resíduo TRAIL fica no board (§4.6).
static func undo_trail(state: PlayerState, board: BoardState) -> void:
	for i in state.trail:
		if board.cells[i] == BoardState.Cell.TRAIL:
			board.set_index(i, BoardState.Cell.FREE)
	state.trail = PackedInt32Array()
	state.trail_active = false
	state.segment_len = 0
	state.trail_px_since_score = 0


## A trilha virou fronteira: esquece a construção sem tocar o board (o plano já foi aplicado).
static func consolidate_trail(state: PlayerState) -> void:
	state.trail = PackedInt32Array()
	state.trail_active = false
	state.segment_len = 0


static func axis_of(dir: int) -> int:
	return 0 if (dir == MoveIntent.Dir.UP or dir == MoveIntent.Dir.DOWN) else 1


static func is_perpendicular(a: int, b: int) -> bool:
	if a == MoveIntent.Dir.NONE or b == MoveIntent.Dir.NONE:
		return false
	return axis_of(a) != axis_of(b)
