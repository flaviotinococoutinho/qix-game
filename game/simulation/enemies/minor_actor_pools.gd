class_name MinorActorPools
extends RefCounted
## Ocupação dos atores menores, fora do `BoardState` (invariante 3), em pools de tamanho fixo.
## `PackedInt32Array` com stride por tipo: `to_byte_array()` é canônico sem ordenar nada e o
## ocupação não cresce com o tempo de partida. O Volfied percorre 22 ranhuras fixas (§12.3); aqui são 4 + 6 + 4, porque a
## 1 px por célula catorze atores já saturam a leitura.
##
## Cada ator carrega `cause` (por que nasceu) e `reason` (última decisão): a rastreabilidade é
## estado do domínio, lida pela view, e entra no checksum como qualquer outro fato.

const MAX_WALKERS := 4
const MAX_DARTS := 6
const MAX_EMBERS := 4

## Vagalume: vive em BOUNDARY viva; `dir` é índice em BoardState.NEIGHBOR_* (0..3).
enum W { ALIVE, X, Y, DIR, ACC_FP, BIAS, WARMUP, DORMANT, CAUSE, REASON, ID, STATE, STATE_TICKS }
const WALKER_STRIDE := 13
## Dardo: projétil 8.8 sobre FREE em uma das 16 direções do Núcleo.
enum D { ALIVE, X_FP, Y_FP, DIR_INDEX, SPEED_FP, WARMUP, LIFE, CAUSE, REASON, AUX, ID, STATE, STATE_TICKS }
const DART_STRIDE := 13
## Brasa: índice na trilha do jogador; não tem célula própria.
enum E { ALIVE, TRAIL_INDEX, ACC_FP, CAUSE, REASON, ID, STATE, STATE_TICKS, WARMUP, LAST_CELL }
const EMBER_STRIDE := 10

## Por que um ator nasceu.
enum Cause { NONE, LADDER, CAMP, EXPOSURE, CORNERED, STREAK, CUT, STALL, OVERTIME }
## Última decisão de um ator. Nomeável no overlay de rastreio e no HUD.
enum Reason {
	NONE, SPAWNED, KEEP, TURN_HAND, TURN_COUNTER, REVERSE, DORMANT, EXTINGUISHED,
	ARMED, FIRED, ABSORBED, CUT_TRAIL, HIT_PLAYER, ADVANCE, WAIT, TRAIL_GONE, EXPIRED,
}

var next_actor_id: int = 3

var walkers := PackedInt32Array()
var darts := PackedInt32Array()
var embers := PackedInt32Array()


func _init() -> void:
	walkers.resize(MAX_WALKERS * WALKER_STRIDE)
	darts.resize(MAX_DARTS * DART_STRIDE)
	embers.resize(MAX_EMBERS * EMBER_STRIDE)
	clear()


func clear() -> void:
	next_actor_id = 3
	walkers.fill(0)
	darts.fill(0)
	embers.fill(0)


# --- vagalumes --------------------------------------------------------------------------------

func walker(slot: int, field: int) -> int:
	return walkers[slot * WALKER_STRIDE + field]


func set_walker(slot: int, field: int, value: int) -> void:
	walkers[slot * WALKER_STRIDE + field] = value


func walker_alive(slot: int) -> bool:
	return walkers[slot * WALKER_STRIDE + W.ALIVE] != 0


func walker_cell(slot: int) -> Vector2i:
	return Vector2i(walker(slot, W.X), walker(slot, W.Y))


func alive_walkers() -> int:
	var count := 0
	for slot in MAX_WALKERS:
		if walker_alive(slot):
			count += 1
	return count


func free_walker_slot() -> int:
	for slot in MAX_WALKERS:
		if walker_lifecycle(slot) == ActorLifecycle.State.DESPAWNED:
			return slot
	return -1


func clear_walker(slot: int) -> void:
	for field in WALKER_STRIDE:
		walkers[slot * WALKER_STRIDE + field] = 0


# --- dardos -----------------------------------------------------------------------------------

func dart(slot: int, field: int) -> int:
	return darts[slot * DART_STRIDE + field]


func set_dart(slot: int, field: int, value: int) -> void:
	darts[slot * DART_STRIDE + field] = value


func dart_alive(slot: int) -> bool:
	return darts[slot * DART_STRIDE + D.ALIVE] != 0


func dart_cell(slot: int) -> Vector2i:
	return Vector2i(dart(slot, D.X_FP) >> 8, dart(slot, D.Y_FP) >> 8)


func alive_darts() -> int:
	var count := 0
	for slot in MAX_DARTS:
		if dart_alive(slot):
			count += 1
	return count


func free_dart_slot() -> int:
	for slot in MAX_DARTS:
		if dart_lifecycle(slot) == ActorLifecycle.State.DESPAWNED:
			return slot
	return -1


func clear_dart(slot: int) -> void:
	for field in DART_STRIDE:
		darts[slot * DART_STRIDE + field] = 0


# --- brasas -----------------------------------------------------------------------------------

func ember(slot: int, field: int) -> int:
	return embers[slot * EMBER_STRIDE + field]


func set_ember(slot: int, field: int, value: int) -> void:
	embers[slot * EMBER_STRIDE + field] = value


func ember_alive(slot: int) -> bool:
	return embers[slot * EMBER_STRIDE + E.ALIVE] != 0


func alive_embers() -> int:
	var count := 0
	for slot in MAX_EMBERS:
		if ember_alive(slot):
			count += 1
	return count


func free_ember_slot() -> int:
	for slot in MAX_EMBERS:
		if ember_lifecycle(slot) == ActorLifecycle.State.DESPAWNED:
			return slot
	return -1


func clear_ember(slot: int) -> void:
	for field in EMBER_STRIDE:
		embers[slot * EMBER_STRIDE + field] = 0


func alive_total() -> int:
	return alive_walkers() + alive_darts() + alive_embers()


## Bytes canônicos: próximo ID e três pools na ordem fixa. Tamanho constante por capacidade.
func canonical_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_s32(0, next_actor_id)
	out.append_array(walkers.to_byte_array())
	out.append_array(darts.to_byte_array())
	out.append_array(embers.to_byte_array())
	return out


func walker_lifecycle(slot: int) -> int:
	return walker(slot, W.STATE)


func walker_actor_id(slot: int) -> int:
	return walker(slot, W.ID)


func begin_walker(slot: int, warmup_ticks: int) -> void:
	clear_walker(slot)
	set_walker(slot, W.ALIVE, 1)
	set_walker(slot, W.ID, next_actor_id)
	next_actor_id += 1
	set_walker(slot, W.STATE, ActorLifecycle.State.WARMUP if warmup_ticks > 0 else ActorLifecycle.State.ACTIVE)
	set_walker(slot, W.STATE_TICKS, maxi(0, warmup_ticks))


func retire_walker(slot: int, reason: int, despawn_ticks: int = 12) -> void:
	set_walker(slot, W.ALIVE, 0)
	set_walker(slot, W.REASON, reason)
	set_walker(slot, W.STATE, ActorLifecycle.State.DYING if despawn_ticks > 0 else ActorLifecycle.State.DESPAWNED)
	set_walker(slot, W.STATE_TICKS, maxi(0, despawn_ticks))


func dart_lifecycle(slot: int) -> int:
	return dart(slot, D.STATE)


func dart_actor_id(slot: int) -> int:
	return dart(slot, D.ID)


func begin_dart(slot: int, warmup_ticks: int) -> void:
	clear_dart(slot)
	set_dart(slot, D.ALIVE, 1)
	set_dart(slot, D.ID, next_actor_id)
	next_actor_id += 1
	set_dart(slot, D.STATE, ActorLifecycle.State.WARMUP if warmup_ticks > 0 else ActorLifecycle.State.ACTIVE)
	set_dart(slot, D.STATE_TICKS, maxi(0, warmup_ticks))


func retire_dart(slot: int, reason: int, despawn_ticks: int = 12) -> void:
	set_dart(slot, D.ALIVE, 0)
	set_dart(slot, D.REASON, reason)
	set_dart(slot, D.STATE, ActorLifecycle.State.DYING if despawn_ticks > 0 else ActorLifecycle.State.DESPAWNED)
	set_dart(slot, D.STATE_TICKS, maxi(0, despawn_ticks))


func ember_lifecycle(slot: int) -> int:
	return ember(slot, E.STATE)


func ember_actor_id(slot: int) -> int:
	return ember(slot, E.ID)


func begin_ember(slot: int, warmup_ticks: int) -> void:
	clear_ember(slot)
	set_ember(slot, E.ALIVE, 1)
	set_ember(slot, E.ID, next_actor_id)
	next_actor_id += 1
	set_ember(slot, E.STATE, ActorLifecycle.State.WARMUP if warmup_ticks > 0 else ActorLifecycle.State.ACTIVE)
	set_ember(slot, E.STATE_TICKS, maxi(0, warmup_ticks))


func retire_ember(slot: int, reason: int, despawn_ticks: int = 12) -> void:
	set_ember(slot, E.ALIVE, 0)
	set_ember(slot, E.REASON, reason)
	set_ember(slot, E.STATE, ActorLifecycle.State.DYING if despawn_ticks > 0 else ActorLifecycle.State.DESPAWNED)
	set_ember(slot, E.STATE_TICKS, maxi(0, despawn_ticks))


## Avança apenas remoções já iniciadas, antes dos spawns: um slot DYING nunca é reutilizado.
func advance_removals() -> void:
	for slot in MAX_WALKERS:
		if walker_lifecycle(slot) == ActorLifecycle.State.DYING:
			var remaining := walker(slot, W.STATE_TICKS) - 1
			set_walker(slot, W.STATE_TICKS, maxi(0, remaining))
			if remaining <= 0:
				set_walker(slot, W.STATE, ActorLifecycle.State.DESPAWNED)
	for slot in MAX_DARTS:
		if dart_lifecycle(slot) == ActorLifecycle.State.DYING:
			var remaining := dart(slot, D.STATE_TICKS) - 1
			set_dart(slot, D.STATE_TICKS, maxi(0, remaining))
			if remaining <= 0:
				set_dart(slot, D.STATE, ActorLifecycle.State.DESPAWNED)
	for slot in MAX_EMBERS:
		if ember_lifecycle(slot) == ActorLifecycle.State.DYING:
			var remaining := ember(slot, E.STATE_TICKS) - 1
			set_ember(slot, E.STATE_TICKS, maxi(0, remaining))
			if remaining <= 0:
				set_ember(slot, E.STATE, ActorLifecycle.State.DESPAWNED)
