extends TestCase
## Ritmo do risco: uma trilha longa precisa doer *antes* do impacto. Estes testes defendem a
## leitura de exposição — a curva, sua projeção no shader e o nome que ela ganha no HUD — e
## garantem que nada disso vaza para o domínio (invariantes 6 e 8).


func test_ratio_is_zero_until_committed_and_saturates_across_the_field() -> void:
	# Campo de produção: piso 8 px (GameRules.new_segment_slow_px), teto (225+283)/4 = 127.
	eq(TrailExposure.ceiling_px(225, 283, 8), 127)
	eq(TrailExposure.ratio(0, 8, 225, 283), 0.0, "trilha ausente não é exposição")
	eq(TrailExposure.ratio(8, 8, 225, 283), 0.0, "o compromisso curto ainda é recuperável")
	ok(TrailExposure.ratio(9, 8, 225, 283) > 0.0, "passado o piso, a exposição começa a subir")
	eq(TrailExposure.ratio(127, 8, 225, 283), 1.0, "uma travessia inteira satura")
	eq(TrailExposure.ratio(4000, 8, 225, 283), 1.0, "a curva é limitada em 1.0")

	var previous := -1.0
	for length in range(0, 200, 7):
		var current := TrailExposure.ratio(length, 8, 225, 283)
		ok(current >= previous, "a exposição nunca pode cair enquanto a trilha só cresce")
		previous = current


func test_warning_threshold_lands_mid_field_and_is_named_once() -> void:
	# Metade da faixa exposta: 8 + 0,5 × (127 − 8) = 67,5 ⇒ o aviso nasce em 68 px.
	ok(not TrailExposure.is_warning(TrailExposure.ratio(67, 8, 225, 283)))
	ok(TrailExposure.is_warning(TrailExposure.ratio(68, 8, 225, 283)))


func test_ceiling_never_collapses_on_small_boards() -> void:
	# Num campo minúsculo o teto geométrico ficaria abaixo do piso; a curva não pode dividir por
	# zero nem inverter, senão um teste de unidade em 7×6 explodiria em produção.
	eq(TrailExposure.ceiling_px(7, 6, 8), 9)
	eq(TrailExposure.ratio(0, 8, 7, 6), 0.0)
	eq(TrailExposure.ratio(9, 8, 7, 6), 1.0)
	eq(TrailExposure.ceiling_px(0, 0, 0), 1, "geometria degenerada ainda produz um teto usável")


func test_null_or_idle_simulation_reads_as_no_exposure() -> void:
	eq(TrailExposure.of_simulation(null), 0.0)
	var simulation := _simulation()
	ok(not simulation.trail_active)
	eq(TrailExposure.of_simulation(simulation), 0.0, "sem trilha ativa não há exposição")


func test_board_view_projects_exposure_without_touching_the_simulation() -> void:
	var simulation := _simulation()
	var view := QixBoardView.new()
	view._ready()

	view.sync(simulation)
	eq(view.last_trail_exposure(), 0.0)
	eq(_shader_exposure(view), 0.0, "sem trilha o shader recebe exposição zero")

	_draw_down(simulation, 4)
	var checksum_before := simulation.state_checksum()
	view.sync(simulation)
	var short_exposure := view.last_trail_exposure()
	eq(short_exposure, TrailExposure.of_simulation(simulation))
	eq(_shader_exposure(view), short_exposure, "o shader recebe exatamente a leitura da view")

	_draw_down(simulation, 30)
	view.sync(simulation)
	var long_exposure := view.last_trail_exposure()
	ok(long_exposure > short_exposure, "trilha mais longa precisa projetar mais exposição")
	ok(TrailExposure.is_warning(long_exposure), "68 px de trilha já é o território do aviso")

	# Invariantes 6 e 8: a apresentação leu, não mutou — e a leitura não entra no checksum.
	eq(simulation.state_checksum(), _replayed_checksum(simulation.trail.size()),
		"sync não pode alterar o estado autoritativo")
	ne(checksum_before, simulation.state_checksum(), "o teste realmente avançou a simulação")

	view.free()


func test_hud_names_the_moment_the_trail_becomes_exposed() -> void:
	var hud := QixGameHud.new()
	hud._ready()
	var simulation := _simulation()

	_draw_down(simulation, 4)
	hud.sync(simulation, false, [])
	eq((hud.get_node("Status") as Label).text, "FECHE NA BORDA",
		"trilha curta continua com a instrução neutra")

	_draw_down(simulation, 30)
	hud.sync(simulation, false, [])
	eq((hud.get_node("Status") as Label).text, "EXPOSTO · VOLTE À BORDA",
		"passado o limiar, o HUD dá nome à exposição")

	hud.free()


# --- apoio -------------------------------------------------------------------------------------

## Geometria de produção com o chefe parado: o risco em teste é o comprimento da trilha, não o
## acaso do chefe. A coluna de desenho (x = 112) só encontraria o chefe em y ≈ 141.
func _simulation() -> GameSimulation:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.shield_ticks = 60 * 600
	return GameSimulation.new(rules, RoundDefinition.new(), 4177)


func _draw_down(simulation: GameSimulation, ticks: int) -> void:
	for _i in ticks:
		simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	eq(simulation.phase, GameSimulation.Phase.PLAYING, "o roteiro do teste não pode morrer")
	ok(simulation.trail_active, "o roteiro do teste precisa manter a trilha ativa")


## Reexecuta o mesmo roteiro num universo limpo: se `sync` tivesse mutado algo, os checksums
## divergiriam.
func _replayed_checksum(expected_trail_length: int) -> PackedByteArray:
	var pristine := _simulation()
	while pristine.trail.size() < expected_trail_length:
		pristine.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	eq(pristine.trail.size(), expected_trail_length, "o roteiro precisa ser reproduzível")
	return pristine.state_checksum()


func _shader_exposure(view: QixBoardView) -> float:
	var material := view.reveal_sprite().material as ShaderMaterial
	return float(material.get_shader_parameter("trail_exposure"))
