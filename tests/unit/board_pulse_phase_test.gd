extends TestCase
## O pulso da trilha precisa *acelerar*, não trocar de fase.
##
## `TrailExposure` já governa a velocidade do pulso (ver `trail_exposure_test.gd`). O que estes
## testes defendem é a outra metade: que mudar essa velocidade não teleporte a fase. A forma antiga
## — `sin(tick * rate)` avaliada no fragmento — saltava `tick * Δrate` sempre que a exposição
## mudava, e a exposição muda a cada tick enquanto se desenha. Medido no campo de produção, isso
## dava ~6 rad por tick aos 10 s de rodada e ~368 rad no tick do fecho: aliasing a 60 Hz no
## exato canal que deveria comunicar risco crescente.
##
## Nada aqui toca o domínio: são fases de apresentação sobre snapshots já confirmados
## (invariantes 6 e 8).

## Teto físico do que o pulso pode andar num tick: a taxa máxima da view, com exposição saturada.
const MAX_RATE := QixBoardView.TRAIL_PULSE_BASE_RATE + QixBoardView.TRAIL_PULSE_EXPOSURE_GAIN


func test_pulse_phase_never_jumps_more_than_one_tick_of_rate() -> void:
	var simulation := _aged_simulation(600)
	var view := _view()

	view.sync(simulation)
	var previous := _pulse_phase(view)
	var worst := 0.0

	# Desenha até a trilha fechar sozinha na moldura oposta: cobre a subida da exposição *e* o
	# tick do fecho, que era o pior salto da fórmula antiga.
	for _i in 200:
		simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
		view.sync(simulation)
		var current := _pulse_phase(view)
		worst = maxf(worst, _phase_distance(previous, current))
		previous = current
		if simulation.phase != GameSimulation.Phase.PLAYING:
			break

	ok(worst <= MAX_RATE + 0.0001,
		"a fase do pulso andou %.4f rad num tick; o teto é %.4f" % [worst, MAX_RATE])
	view.free()


func test_pulse_phase_is_bounded_however_long_the_round_runs() -> void:
	var simulation := _aged_simulation(0)
	var view := _view()

	for _i in 5000:
		simulation.step(MoveIntent.none())
		view.sync(simulation)

	var pulse := _pulse_phase(view)
	var scan := _scan_phase(view)
	ok(pulse >= 0.0 and pulse < TAU, "a fase do pulso saiu de [0, TAU): %f" % pulse)
	ok(scan >= 0.0 and scan < QixBoardView.SCAN_PERIOD,
		"a fase da varredura saiu de [0, SCAN_PERIOD): %f" % scan)
	ok(simulation.tick >= 5000, "o roteiro precisa mesmo envelhecer a rodada")
	view.free()


func test_scan_wrap_is_invisible_because_the_period_is_exact() -> void:
	# O shader avalia `fract((FRAGCOORD.y + scan_phase) * 0.5)`. Enrolar em 2.0 tem de devolver
	# exatamente o mesmo degrau — senão a varredura daria um salto visível a cada volta.
	for y in [0.0, 1.0, 7.0, 183.0, 319.0]:
		for phase in [0.0, 0.37, 1.0, 1.99]:
			var here := fmod((y + phase) * 0.5, 1.0)
			var wrapped := fmod((y + phase + QixBoardView.SCAN_PERIOD) * 0.5, 1.0)
			ok(absf(here - wrapped) < 0.0001,
				"o enrolamento da varredura é visível em y=%.0f, fase=%.2f" % [y, phase])


func test_exposure_still_makes_the_pulse_faster() -> void:
	# A correção não pode ter custado o efeito: mais exposição continua a ser mais velocidade.
	var idle := _advanced_over(30, 0.0)
	var exposed := _advanced_over(30, 1.0)
	ok(exposed > idle * 3.0,
		"exposição saturada devia acelerar o pulso (parado %.3f rad, exposto %.3f rad)"
			% [idle, exposed])


func test_a_frame_without_a_new_tick_does_not_move_the_pulse() -> void:
	# A view é sincronizada por quadro, o domínio avança por tick. Um quadro repetido não pode
	# adiantar a animação — seria apresentação a inventar tempo que a simulação não deu.
	var simulation := _aged_simulation(120)
	var view := _view()
	view.sync(simulation)
	var first := _pulse_phase(view)
	view.sync(simulation)
	view.sync(simulation)
	eq(_pulse_phase(view), first, "sincronizar duas vezes no mesmo tick moveu a fase")
	view.free()


func test_a_new_round_resumes_the_phase_instead_of_cutting_it() -> void:
	# Rodada nova reinicia o tick em 0. A fase não pode voltar a zero junto: isso seria um corte
	# visível no meio da transição. Ela continua de onde estava e volta a andar no tick seguinte.
	var view := _view()
	var first_round := _aged_simulation(300)
	# O primeiro `sync` só ancora o tick — é ele que impede um salto ao entrar numa rodada já
	# avançada. A fase começa a acumular a partir do segundo.
	view.sync(first_round)
	eq(_pulse_phase(view), 0.0, "o primeiro sync ancora o tick sem inventar fase")
	for _i in 40:
		first_round.step(MoveIntent.none())
		view.sync(first_round)
	var carried := _pulse_phase(view)
	ok(carried > 0.0, "o roteiro precisa ter acumulado alguma fase")

	var second_round := _aged_simulation(0)
	view.sync(second_round)
	eq(_pulse_phase(view), carried, "o tick voltar a zero não pode zerar a fase")

	second_round.step(MoveIntent.none())
	view.sync(second_round)
	ok(_pulse_phase(view) != carried, "passado o primeiro tick da rodada nova, a fase volta a andar")
	view.free()


# --- apoio -------------------------------------------------------------------------------------

## Mesma geometria de produção de `trail_exposure_test.gd`, com o chefe parado: o que está em teste
## é a fase, não o acaso do chefe.
func _aged_simulation(ticks: int) -> GameSimulation:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.shield_ticks = 60 * 600
	var simulation := GameSimulation.new(rules, RoundDefinition.new(), 4177)
	for _i in ticks:
		simulation.step(MoveIntent.none())
	return simulation


func _view() -> QixBoardView:
	var view := QixBoardView.new()
	view._ready()
	return view


func _pulse_phase(view: QixBoardView) -> float:
	var material := view.reveal_sprite().material as ShaderMaterial
	return float(material.get_shader_parameter("trail_pulse_phase"))


func _scan_phase(view: QixBoardView) -> float:
	var material := view.reveal_sprite().material as ShaderMaterial
	return float(material.get_shader_parameter("scan_phase"))


## Distância angular entre duas fases enroladas: sem isto, a volta de TAU para 0 leria como um
## salto de quase uma volta inteira quando na verdade é contínua.
func _phase_distance(from: float, to: float) -> float:
	var raw := absf(to - from)
	return minf(raw, TAU - raw)


## Quanto a fase anda em `ticks` com a exposição fixa em `exposure`, medido pela mesma via que o
## jogo usa — a view, não uma cópia da fórmula.
func _advanced_over(ticks: int, exposure: float) -> float:
	var view := _view()
	var total := 0.0
	var previous := 0.0
	for i in range(1, ticks + 1):
		view._advance_phases(i, exposure)
		var current := view._trail_pulse_phase
		total += _phase_distance(previous, current)
		previous = current
	view.free()
	return total
