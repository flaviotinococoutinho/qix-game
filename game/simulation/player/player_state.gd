class_name PlayerState
extends RefCounted
## Estado do cartógrafo: posição em células, direção corrente e a trilha em construção.
## Só dados inteiros. As regras de movimento vivem em `PlayerMotion`; nada aqui decide.

var px: int = 0
var py: int = 0
var pdir: int = MoveIntent.Dir.NONE
## Índices de célula da trilha em construção, na ordem em que foram desenhados.
var trail: PackedInt32Array = PackedInt32Array()
var trail_active: bool = false
## Onde a trilha começou; é o ponto de reentrada após uma morte (§4.6).
var first_vertex: Vector2i = Vector2i.ZERO
## Comprimento do segmento reto atual; zera a cada mudança legal de eixo (§4.5b).
var segment_len: int = 0
## Pixels de trilha desde o último pagamento de pontos (§4.5a: a cada 4 px).
var trail_px_since_score: int = 0


func reset(spawn: Vector2i) -> void:
	px = spawn.x
	py = spawn.y
	pdir = MoveIntent.Dir.NONE
	trail = PackedInt32Array()
	trail_active = false
	first_vertex = spawn
	segment_len = 0
	trail_px_since_score = 0


func cell() -> Vector2i:
	return Vector2i(px, py)


func index_in(board: BoardState) -> int:
	return board.index_of(px, py)


## Valores inteiros na ordem canônica do checksum (a trilha em si é anexada à parte).
func canonical_values() -> Array[int]:
	return [
		px, py, pdir, 1 if trail_active else 0, first_vertex.x, first_vertex.y,
		segment_len, trail_px_since_score,
	]
