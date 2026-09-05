class_name GameEvent
extends RefCounted
## Fato pequeno e tipado, confirmado pela simulação. Views, VFX e áudio só observam.

enum Kind {
	TRAIL_STARTED,
	CAPTURED,          # data: claimed, trail, filled_delta, permille
	CAPTURE_REJECTED,  # data: code, message
	PLAYER_DIED,       # data: reason, lives
	PLAYER_RESPAWNED,  # data: x, y
	SCORE_CHANGED,     # data: score, delta
	PERCENT_CHANGED,   # data: permille
	SHIELD_CRITICAL,
	ROUND_WON,         # data: permille, score
	GAME_OVER,
	ROUND_INTRO_STARTED, # sessão: nova rodada criada, gameplay ainda bloqueado
	ROUND_STARTED,       # sessão: intro concluída, gameplay liberado
	ROUND_CLEAR_STARTED, # sessão: vitória arquivada, fundo pode ser revelado
	CAMPAIGN_COMPLETE,   # sessão: última rodada concluída
}

var kind: int
var data: Dictionary


static func make(k: int, d: Dictionary = {}) -> GameEvent:
	var e := GameEvent.new()
	e.kind = k
	e.data = d
	return e
