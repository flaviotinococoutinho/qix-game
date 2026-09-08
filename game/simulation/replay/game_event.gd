class_name GameEvent
extends RefCounted
## Fato pequeno e tipado, confirmado pela simulação. Views, VFX e áudio só observam.
## Novos tipos são sempre apensados ao fim do enum: os inteiros existentes são contrato.

enum Kind {
	TRAIL_STARTED,
	CAPTURED,          # data: claimed, trail, filled_delta, permille
	CAPTURE_REJECTED,  # data: code, message
	PLAYER_DIED,       # data: reason, lives
	PLAYER_RESPAWNED,  # data: x, y
	SCORE_CHANGED,     # data: score, delta
	PERCENT_CHANGED,   # data: permille
	SHIELD_CRITICAL,
	ROUND_WON,         # data: permille, score, reason
	GAME_OVER,
	ROUND_INTRO_STARTED, # sessão: nova rodada criada, gameplay ainda bloqueado
	ROUND_STARTED,       # sessão: intro concluída, gameplay liberado
	ROUND_CLEAR_STARTED, # sessão: vitória arquivada, fundo pode ser revelado
	CAMPAIGN_COMPLETE,   # sessão: última rodada concluída
	# --- elenco menor e diretor de ameaça (fase 2) ---
	THREAT_LEVEL_CHANGED, # data: index, previous
	OVERTIME_STARTED,     # data: tick
	WALKER_SPAWNED,       # data: slot, x, y, dir, cause, warmup
	WALKER_EXTINGUISHED,  # data: slot, x, y, points
	DART_ARMED,           # data: slot, x, y, dir_index, cause, warmup
	DART_FIRED,           # data: slot
	DART_ABSORBED,        # data: slot, x, y
	TRAIL_CUT,            # data: slot, trail_index, x, y
	EMBER_IGNITED,        # data: slot, trail_index, cause
	EMBER_EXTINGUISHED,   # data: count
	BOSS_PHASE_CHANGED,   # data: phase, permille
	BOSS_CORNERED,        # data: burst_ticks, phase
	PLAYER_STALLING,      # data: ticks
	CALM_STARTED,         # data: ticks
	BEACON_CAPTURED,      # data: index, x, y, chain, points, item
	ITEM_STARTED,         # data: item, ticks
	ITEM_ENDED,           # data: item
	BOSS_SEALED,          # data: free_remaining
}

var kind: int
var data: Dictionary


static func make(k: int, d: Dictionary = {}) -> GameEvent:
	var e := GameEvent.new()
	e.kind = k
	e.data = d
	return e
