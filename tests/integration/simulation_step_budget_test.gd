extends TestCase
## Catraca do custo do tick (invariante 2 na prática): `step()` precisa caber no orçamento
## mesmo com tudo o que o domínio vier a ganhar. Mede-se por fora, com relógio de
## apresentação; o domínio continua sem saber que existe tempo de parede.

const ProfileScript := preload("res://tools/profile_simulation_step.gd")

## Orçamento de p95 em µs num tick de gameplay com o chefe ativo. O valor cobre a máquina de
## referência (Apple M2) com folga de ~4× sobre a medição de 2026-09-05; se estourar, o custo
## novo precisa ser justificado em docs/PERFORMANCE.md, não o número aqui aumentado às cegas.
const P95_BUDGET_USEC := 300
const TICKS := 1200


func test_step_p95_stays_inside_budget_on_the_production_field() -> void:
	var report: Dictionary = ProfileScript.measure(TICKS)
	eq(int(report["ticks"]), TICKS)
	ok(int(report["final_tick"]) == TICKS, "todos os ticks precisam ter rodado")
	ok(
		int(report["p95_usec"]) <= P95_BUDGET_USEC,
		"p95 de step() = %d µs excede o orçamento de %d µs (p50 %d, máx %d)" % [
			int(report["p95_usec"]), P95_BUDGET_USEC, int(report["p50_usec"]), int(report["max_usec"]),
		],
	)
	ok(int(report["final_permille"]) > 0, "a rota do perfil precisa capturar território")
