class_name EmberRules
extends RefCounted
## Brasa — a faísca que corre pela trilha (ACHADOS banda 02: um tiro corta a trilha e nascem
## faíscas que a percorrem até o jogador) e o pavio de Qix (§3.3 #8 player_stall_counter: parar
## a desenhar acende a própria trilha). Vive como índice em `PlayerState.trail`, sem célula
## própria. A 1,5 célula por tick contra 2 do jogador, quem continua desenhando escapa; quem
## hesita, não.

enum Outcome { NONE, ADVANCED, CONTACT }


static func ignite(pools: MinorActorPools, slot: int, trail_index: int, cause: int, warmup_ticks: int = 12) -> void:
	pools.begin_ember(slot, warmup_ticks)
	pools.set_ember(slot, MinorActorPools.E.WARMUP, warmup_ticks)
	pools.set_ember(slot, MinorActorPools.E.LAST_CELL, -1)
	pools.set_ember(slot, MinorActorPools.E.TRAIL_INDEX, maxi(0, trail_index))
	pools.set_ember(slot, MinorActorPools.E.CAUSE, cause)
	pools.set_ember(slot, MinorActorPools.E.REASON, MinorActorPools.Reason.SPAWNED)


## Um tick: avança rumo à cabeça da trilha. Contato quando alcança a célula do jogador.
static func update(pools: MinorActorPools, slot: int, player: PlayerState, speed_fp: int, despawn_ticks: int = 12) -> int:
	if not pools.ember_alive(slot):
		return Outcome.NONE
	if not player.trail_active or player.trail.is_empty():
		pools.retire_ember(slot, MinorActorPools.Reason.TRAIL_GONE, despawn_ticks)
		return Outcome.NONE
	var warmup := pools.ember(slot, MinorActorPools.E.WARMUP)
	if warmup > 0:
		pools.set_ember(slot, MinorActorPools.E.WARMUP, warmup - 1)
		pools.set_ember(slot, MinorActorPools.E.STATE_TICKS, warmup - 1)
		pools.set_ember(slot, MinorActorPools.E.LAST_CELL, cell_index(pools, slot, player))
		return Outcome.NONE
	pools.set_ember(slot, MinorActorPools.E.STATE, ActorLifecycle.State.ACTIVE)
	pools.set_ember(slot, MinorActorPools.E.STATE_TICKS, 0)
	var acc := pools.ember(slot, MinorActorPools.E.ACC_FP) + speed_fp
	var index := pools.ember(slot, MinorActorPools.E.TRAIL_INDEX)
	var advanced := false
	while acc >= 256:
		acc -= 256
		index += 1
		advanced = true
	var head := player.trail.size() - 1
	pools.set_ember(slot, MinorActorPools.E.ACC_FP, acc)
	if index >= head:
		pools.set_ember(slot, MinorActorPools.E.TRAIL_INDEX, head)
		pools.set_ember(slot, MinorActorPools.E.LAST_CELL, player.trail[head])
		pools.set_ember(slot, MinorActorPools.E.REASON, MinorActorPools.Reason.HIT_PLAYER)
		return Outcome.CONTACT
	pools.set_ember(slot, MinorActorPools.E.TRAIL_INDEX, index)
	pools.set_ember(slot, MinorActorPools.E.LAST_CELL, player.trail[index])
	pools.set_ember(slot, MinorActorPools.E.REASON,
		MinorActorPools.Reason.ADVANCE if advanced else MinorActorPools.Reason.WAIT)
	return Outcome.ADVANCED if advanced else Outcome.NONE


## A trilha acabou (captura aplicada ou desfeita): todas as brasas apagam. Devolve quantas.
static func extinguish_all(pools: MinorActorPools, despawn_ticks: int = 12) -> int:
	var count := 0
	for slot in MinorActorPools.MAX_EMBERS:
		if pools.ember_alive(slot):
			pools.retire_ember(slot, MinorActorPools.Reason.TRAIL_GONE, despawn_ticks)
			count += 1
	return count


## Célula atual de uma brasa viva, ou -1.
static func cell_index(pools: MinorActorPools, slot: int, player: PlayerState) -> int:
	if not pools.ember_alive(slot) or player.trail.is_empty():
		return pools.ember(slot, MinorActorPools.E.LAST_CELL)
	var index := clampi(pools.ember(slot, MinorActorPools.E.TRAIL_INDEX), 0, player.trail.size() - 1)
	return player.trail[index]
