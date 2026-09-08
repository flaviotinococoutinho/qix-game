class_name BossState
extends RefCounted
## Estado do Núcleo em ponto fixo 8.8. As decisões vivem em `BossBehaviorController` e o
## passo de movimento em `BossMotion`; aqui só há dados e conversões.

var actor_id: int = ActorLifecycle.BOSS_ID
var despawn_ticks_left: int = 0

var alive: bool = true
var x_fp: int = 0
var y_fp: int = 0
var vx_fp: int = 0
var vy_fp: int = 0
var dir_index: int = 0
var effective_speed_fp: int = 0
## Fase por permille (0..2), fúria (reflexões numa janela) e estase (item).
var phase: int = 0
var reflections: int = 0
var window_left: int = 0
var burst_left: int = 0
var stasis_ticks: int = 0


func reset(start: Vector2i, start_dir_index: int) -> void:
	alive = true
	despawn_ticks_left = 0
	x_fp = start.x << 8
	y_fp = start.y << 8
	dir_index = start_dir_index & 15
	vx_fp = 0
	vy_fp = 0
	effective_speed_fp = 0
	phase = 0
	reflections = 0
	window_left = 0
	burst_left = 0
	stasis_ticks = 0


func cell() -> Vector2i:
	return Vector2i(x_fp >> 8, y_fp >> 8)


## Células que o chefe ocupa para contato: centro + cruz (raio 1).
func contact_cells(board: BoardState) -> PackedInt32Array:
	var c := cell()
	var out := PackedInt32Array()
	out.append(board.index_of(c.x, c.y))
	for d in 4:
		var nx: int = c.x + BoardState.NEIGHBOR_DX[d]
		var ny: int = c.y + BoardState.NEIGHBOR_DY[d]
		if board.in_bounds(nx, ny):
			out.append(board.index_of(nx, ny))
	return out


func set_velocity(idx: int, speed_fp: int) -> void:
	dir_index = idx & 15
	effective_speed_fp = speed_fp
	vx_fp = (BossBehaviorController.DIRECTION_X[dir_index] * speed_fp) >> 8
	vy_fp = (BossBehaviorController.DIRECTION_Y[dir_index] * speed_fp) >> 8


func is_surging() -> bool:
	return burst_left > 0


## Valores inteiros na ordem canônica do checksum.
func canonical_values() -> Array[int]:
	return [
		1 if alive else 0, x_fp, y_fp, vx_fp, vy_fp, dir_index, effective_speed_fp,
		phase, reflections, window_left, burst_left, stasis_ticks, despawn_ticks_left, actor_id,
	]


func lifecycle() -> int:
	if not alive:
		return ActorLifecycle.State.DYING if despawn_ticks_left > 0 else ActorLifecycle.State.DESPAWNED
	if stasis_ticks > 0:
		return ActorLifecycle.State.DORMANT
	return ActorLifecycle.State.ACTIVE


func begin_dying(ticks: int) -> void:
	alive = false
	despawn_ticks_left = maxi(0, ticks)


func advance_removal() -> void:
	if not alive and despawn_ticks_left > 0:
		despawn_ticks_left -= 1
