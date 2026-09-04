extends TestCase


func test_sync_builds_an_exact_r8_state_mask_and_binds_visual_material() -> void:
	var simulation := _simulation(7, 6)
	var visual := _visual(7, 6)
	var view := QixBoardView.new()
	view._ready()

	view.sync(simulation, visual)

	eq(view.mask_format(), Image.FORMAT_R8, "a máscara deve usar um byte por célula")
	eq(view.mask_size(), Vector2i(7, 6))
	eq(view.mask_bytes(), simulation.board.cells, "a máscara deve ser cópia direta do BoardState")
	var sprite := view.reveal_sprite()
	ok(sprite != null, "a apresentação precisa viver em Sprite2D próprio")
	if sprite != null:
		eq(sprite.position, Vector2(CoordinateSpace.FIELD_ORIGIN))
		eq(sprite.texture, visual.background)
		ok(sprite.material is ShaderMaterial)
		var material := sprite.material as ShaderMaterial
		var mask_uniform := material.get_shader_parameter("state_mask") as Texture2D
		ok(mask_uniform != null, "o shader deve receber a máscara R8")
		if mask_uniform != null:
			eq(mask_uniform.get_instance_id(), view.mask_texture_instance_id())
		eq(material.get_shader_parameter("free_color"), visual.free_color)
		eq(material.get_shader_parameter("boundary_color"), visual.boundary_color)
		eq(material.get_shader_parameter("trail_color"), visual.trail_color)

	view.free()


func test_refresh_reuses_texture_skips_unchanged_board_and_never_mutates_simulation() -> void:
	var simulation := _simulation(9, 8)
	var visual := _visual(9, 8)
	var view := QixBoardView.new()
	view._ready()
	var checksum_before := simulation.board.checksum()
	var version_before := simulation.board.version

	view.sync(simulation, visual)
	var texture_id := view.mask_texture_instance_id()
	view.sync(simulation, visual)
	simulation.board.set_cell(1, 1, BoardState.Cell.TRAIL)
	view.sync(simulation, visual)
	var metrics := view.metrics_snapshot()

	eq(view.mask_texture_instance_id(), texture_id, "ImageTexture deve sobreviver às atualizações")
	eq(metrics.refresh_count, 2)
	eq(metrics.skipped_count, 1)
	eq(metrics.texture_create_count, 1)
	eq(metrics.sample_count, 2)
	eq(metrics.bytes_uploaded, 9 * 8 * 2, "R8 envia exatamente um byte por célula")
	eq(view.mask_bytes(), simulation.board.cells)
	eq(simulation.board.version, version_before + 1, "só a mutação explícita do teste incrementa a versão")
	# O primeiro sync deve ser uma projeção completamente read-only.
	var pristine := _simulation(9, 8)
	eq(checksum_before, pristine.board.checksum())

	view.free()


func test_only_claimed_cells_reveal_the_original_background() -> void:
	ok(not QixBoardView.cell_reveals_background(BoardState.Cell.FREE))
	ok(not QixBoardView.cell_reveals_background(BoardState.Cell.BOUNDARY))
	ok(not QixBoardView.cell_reveals_background(BoardState.Cell.TRAIL))
	ok(QixBoardView.cell_reveals_background(BoardState.Cell.CLAIMED))


func test_profile_ring_buffer_is_bounded_and_reports_percentiles_on_demand() -> void:
	var simulation := _simulation(7, 6)
	var view := QixBoardView.new()
	view._ready()
	view.sync(simulation, _visual(7, 6))
	for i in QixBoardView.PROFILE_SAMPLE_CAPACITY + 7:
		@warning_ignore("integer_division")
		var y := 1 + (i / 5) % 4
		var index := simulation.board.index_of(1 + i % 5, y)
		var state := BoardState.Cell.TRAIL if i % 2 == 0 else BoardState.Cell.FREE
		simulation.board.set_index(index, state)
		view.sync(simulation)
	var metrics := view.metrics_snapshot()

	eq(metrics.sample_count, QixBoardView.PROFILE_SAMPLE_CAPACITY)
	eq(metrics.refresh_count, QixBoardView.PROFILE_SAMPLE_CAPACITY + 8)
	ok(metrics.last_usec >= 0)
	ok(metrics.p50_usec >= 0)
	ok(metrics.p95_usec >= metrics.p50_usec)
	ok(metrics.max_usec >= metrics.p95_usec)

	view.free()


func _simulation(width: int, height: int) -> GameSimulation:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.shield_ticks = 60 * 60
	var definition := RoundDefinition.new()
	definition.field_width = width
	definition.field_height = height
	definition.player_spawn = Vector2i(width / 2, 0)
	definition.boss_start = Vector2i(width / 2, height / 2)
	return GameSimulation.new(rules, definition, 71237)


func _visual(width: int, height: int) -> RoundVisualDefinition:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color("173855"))
	var visual := RoundVisualDefinition.new()
	visual.display_name = "TEST SECTOR"
	visual.background = ImageTexture.create_from_image(image)
	visual.free_color = Color("09131f")
	visual.boundary_color = Color("3cf3c4")
	visual.trail_color = Color("ffd15c")
	return visual
