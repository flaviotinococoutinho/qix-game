class_name ShieldClock
extends RefCounted
## O escudo é um contador de ticks (§9): pausa enquanto há trilha e mata ao esgotar.

enum Outcome { NONE, CRITICAL, EXPIRED }

var ticks: int = 0
var critical_sent: bool = false


func reset(rules: GameRules) -> void:
	ticks = rules.shield_ticks
	critical_sent = false


## Um tick do escudo. `paused` é decidido pelo orquestrador (trilha ativa, item Âncora…).
func advance(rules: GameRules, paused: bool) -> int:
	if paused:
		return Outcome.NONE
	ticks -= 1
	var outcome := Outcome.NONE
	if ticks <= rules.shield_critical_ticks and not critical_sent:
		critical_sent = true
		outcome = Outcome.CRITICAL
	if ticks <= 0:
		return Outcome.EXPIRED
	return outcome


func canonical_values() -> Array[int]:
	return [ticks, 1 if critical_sent else 0]
