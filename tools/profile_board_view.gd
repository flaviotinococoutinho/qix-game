extends SceneTree
## Microbenchmark reprodutível da projeção de board.
##
## Uso:
##   Godot --headless --path . --script res://tools/profile_board_view.gd
##
## A comparação "legacy_rgba_set_pixel" replica o caminho anterior: loop GDScript por célula,
## Image.set_pixel RGBA8 e ImageTexture.update. O caminho R8 mede apenas updates steady-state;
## nenhum tempo observado entra na simulação.

const OPTIMIZED_SAMPLES := 240
const LEGACY_SAMPLES := 32


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulation := _simulation()
	var visual := _visual(simulation.board.width, simulation.board.height)
	var view := QixBoardView.new()
	root.add_child(view)
	view.sync(simulation, visual) # alocação e upload inicial ficam fora do steady-state
	var cold_start := view.metrics_snapshot()
	view.reset_metrics()

	for i in OPTIMIZED_SAMPLES:
		_toggle_probe_cell(simulation.board, i)
		view.sync(simulation, visual)
	var optimized := view.metrics_snapshot()
	var legacy := _profile_legacy_rgba(simulation.board)
	var optimized_p95 := maxi(int(optimized.p95_usec), 1)
	var report := {
		"board": "%dx%d" % [simulation.board.width, simulation.board.height],
		"cells": simulation.board.cells.size(),
		"method": "headless microbenchmark; steady-state texture updates",
		"cold_start_r8": cold_start,
		"optimized_r8": optimized,
		"legacy_rgba_set_pixel": legacy,
		"p95_speedup": float(legacy.p95_usec) / float(optimized_p95),
		"upload_bytes_per_refresh": {
			"optimized_r8": simulation.board.cells.size(),
			"legacy_rgba8": simulation.board.cells.size() * 4,
		},
	}
	print(JSON.stringify(report, "  "))
	view.queue_free()
	quit(0)


func _simulation() -> GameSimulation:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.shield_ticks = 60 * 60
	var definition := RoundDefinition.new()
	return GameSimulation.new(rules, definition, 0xB04D)


func _visual(width: int, height: int) -> RoundVisualDefinition:
	var visual := RoundVisualDefinition.new()
	visual.display_name = "BOARD PROFILE"
	var asset_path := "res://assets/backgrounds/abyssal_relay.png"
	if ResourceLoader.exists(asset_path):
		var loaded := load(asset_path) as Texture2D
		if loaded != null and loaded.get_width() == width and loaded.get_height() == height:
			visual.background = loaded
	if visual.background == null:
		var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
		image.fill(Color("17324a"))
		visual.background = ImageTexture.create_from_image(image)
	return visual


func _toggle_probe_cell(board: BoardState, iteration: int) -> void:
	var x := 1 + iteration % (board.width - 2)
	@warning_ignore("integer_division")
	var y := 1 + (iteration / (board.width - 2)) % (board.height - 2)
	var state := BoardState.Cell.TRAIL if iteration % 2 == 0 else BoardState.Cell.FREE
	board.set_cell(x, y, state)


func _profile_legacy_rgba(board: BoardState) -> Dictionary:
	var image := Image.create_empty(board.width, board.height, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var samples: Array[int] = []
	for _iteration in LEGACY_SAMPLES:
		var started_usec := Time.get_ticks_usec()
		for index in board.cells.size():
			@warning_ignore("integer_division")
			var y := index / board.width
			var x := index - y * board.width
			image.set_pixel(x, y, _legacy_color(board.cells[index]))
		texture.update(image)
		samples.append(Time.get_ticks_usec() - started_usec)
	return _stats(samples, board.cells.size() * 4)


func _stats(samples: Array[int], bytes_per_refresh: int) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	var maximum := 0
	for sample in samples:
		total += sample
		maximum = maxi(maximum, sample)
	return {
		"sample_count": samples.size(),
		"bytes_per_refresh": bytes_per_refresh,
		"mean_usec": total / float(samples.size()),
		"p50_usec": _percentile(sorted, 50),
		"p95_usec": _percentile(sorted, 95),
		"max_usec": maximum,
	}


func _percentile(sorted_values: Array[int], percentile: int) -> int:
	@warning_ignore("integer_division")
	var index := mini(
		(percentile * sorted_values.size() + 99) / 100 - 1,
		sorted_values.size() - 1,
	)
	return sorted_values[maxi(index, 0)]


func _legacy_color(cell: int) -> Color:
	match cell:
		BoardState.Cell.BOUNDARY:
			return Color("50e3c2")
		BoardState.Cell.TRAIL:
			return Color("ffe66d")
		BoardState.Cell.CLAIMED:
			return Color("28527a")
		_:
			return Color("0c1b26")
