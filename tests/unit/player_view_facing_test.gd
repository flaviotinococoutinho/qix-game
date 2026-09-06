extends TestCase
## A proa do cursor aponta para onde a linha vai — não para baixo sempre.
##
## `QixPlayerView` lê `simulation.pdir`, estado de domínio que já entra no checksum. Isto é
## observação: o teste confirma, a cada volta do trajeto, que o desenho segue o domínio e que
## nenhuma `sync` mexe na simulação.


func test_prow_follows_domain_facing_on_every_axis() -> void:
	var simulation := _simulation()
	var view := QixPlayerView.new()

	# Parado na moldura, sem trilha: não há proa a desenhar.
	view.sync(simulation)
	eq(view.facing_indicator(), PackedVector2Array(), "sem trilha não há proa")

	# (10,0) → desce, vira, desce, volta pela esquerda e sobe: os quatro eixos numa só rota.
	var route := [
		[MoveIntent.Dir.DOWN, Vector2i(10, 1), Vector2(0.0, 1.0)],
		[MoveIntent.Dir.RIGHT, Vector2i(11, 1), Vector2(1.0, 0.0)],
		[MoveIntent.Dir.DOWN, Vector2i(11, 2), Vector2(0.0, 1.0)],
		[MoveIntent.Dir.LEFT, Vector2i(10, 2), Vector2(-1.0, 0.0)],
		[MoveIntent.Dir.LEFT, Vector2i(9, 2), Vector2(-1.0, 0.0)],
		[MoveIntent.Dir.UP, Vector2i(9, 1), Vector2(0.0, -1.0)],
	]
	for leg: Array in route:
		var direction: int = leg[0]
		var cell: Vector2i = leg[1]
		var axis: Vector2 = leg[2]
		var before := simulation.state_checksum()
		simulation.step(MoveIntent.make(direction, true))
		eq(simulation.phase, GameSimulation.Phase.PLAYING, "a rota não pode morrer nem fechar")
		eq(Vector2i(simulation.px, simulation.py), cell)
		view.sync(simulation)
		eq(
			view.facing_indicator(),
			PackedVector2Array([axis * QixPlayerView.FACING_NEAR, axis * QixPlayerView.FACING_FAR]),
			"a proa tem de acompanhar pdir=%d" % direction)
		ne(simulation.state_checksum(), before, "a rota precisa avançar de facto")

	# A regressão que isto fecha: com a proa fixa, andar para a esquerda desenhava para baixo.
	eq(simulation.pdir, MoveIntent.Dir.UP)
	ne(view.facing_indicator()[1], Vector2(0.0, QixPlayerView.FACING_FAR))

	view.free()


func test_sync_never_touches_the_simulation() -> void:
	var simulation := _simulation()
	simulation.step(MoveIntent.make(MoveIntent.Dir.DOWN, true))
	var before := simulation.state_checksum()
	var facing_before := simulation.pdir
	var view := QixPlayerView.new()
	view.sync(simulation)
	view.facing_indicator()
	eq(simulation.state_checksum(), before, "a apresentação observa, nunca muta")
	eq(simulation.pdir, facing_before)
	view.free()


## Campo largo e um subpasso por tick: a rota acima lê-se célula a célula, sem aritmética.
func _simulation() -> GameSimulation:
	var rules := GameRules.new()
	rules.substeps_normal = 1
	var definition := RoundDefinition.new()
	definition.field_width = 21
	definition.field_height = 15
	definition.player_spawn = Vector2i(10, 0)
	definition.boss_start = Vector2i(19, 13)
	return GameSimulation.new(rules, definition, 7)
