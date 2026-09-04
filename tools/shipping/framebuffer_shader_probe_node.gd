extends Node
## Renderiza os quatro estados da máscara R8 com o shader real, lê o framebuffer e valida
## que apenas CLAIMED preserva o fundo original.

const SHADER_PATH := "res://game/board/board_reveal.gdshader"
const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"
const VIEWPORT_SIZE := Vector2i(64, 16)
const REGION_WIDTH := 16
const BACKGROUND := Color8(41, 103, 211, 255)
const FREE_COLOR := Color("071923")
const BOUNDARY_COLOR := Color("46f5c5")
const TRAIL_COLOR := Color("ffd166")
const TRAIL_HOT_COLOR := Color("fff4b0")

var _report_path := "user://shipping/framebuffer-report.json"
var _image_path := "user://shipping/framebuffer.png"
var _host_game: Node
var _started := false


func start(arguments: PackedStringArray, host_game: Node = null) -> void:
	if _started:
		return
	_started = true
	_host_game = host_game
	_parse_arguments(arguments)
	call_deferred("_run")


func _run() -> void:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		await _finish_error("shader não carregou: %s" % SHADER_PATH)
		return

	var viewport := SubViewport.new()
	viewport.name = "ShippingFramebufferProbe"
	viewport.size = VIEWPORT_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var background_image := Image.create_empty(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y, false, Image.FORMAT_RGBA8)
	background_image.fill(BACKGROUND)
	var background_texture := ImageTexture.create_from_image(background_image)

	var mask_data := PackedByteArray()
	mask_data.resize(VIEWPORT_SIZE.x * VIEWPORT_SIZE.y)
	for y in VIEWPORT_SIZE.y:
		for x in VIEWPORT_SIZE.x:
			@warning_ignore("integer_division")
			mask_data[y * VIEWPORT_SIZE.x + x] = x / REGION_WIDTH
	var mask_image := Image.create_from_data(
		VIEWPORT_SIZE.x,
		VIEWPORT_SIZE.y,
		false,
		Image.FORMAT_R8,
		mask_data,
	)
	var mask_texture := ImageTexture.create_from_image(mask_image)

	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("state_mask", mask_texture)
	material.set_shader_parameter("free_color", FREE_COLOR)
	material.set_shader_parameter("boundary_color", BOUNDARY_COLOR)
	material.set_shader_parameter("trail_color", TRAIL_COLOR)
	material.set_shader_parameter("trail_hot_color", TRAIL_HOT_COLOR)
	material.set_shader_parameter("presentation_tick", 0.0)

	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = background_texture
	sprite.material = material
	viewport.add_child(sprite)

	# A documentação de Viewport exige aguardar frame_post_draw para evitar readback vazio/stale.
	for _frame in 4:
		await RenderingServer.frame_post_draw
	var framebuffer := viewport.get_texture().get_image()
	if framebuffer == null or framebuffer.is_empty():
		viewport.queue_free()
		await _finish_error("readback do framebuffer retornou imagem vazia")
		return

	var samples := {
		"free": framebuffer.get_pixel(8, 8),
		"boundary": framebuffer.get_pixel(24, 8),
		"trail": framebuffer.get_pixel(40, 8),
		"claimed": framebuffer.get_pixel(56, 8),
	}
	var validation := validate_samples(samples, BACKGROUND)
	viewport.queue_free()
	await get_tree().process_frame

	var composition := await _capture_final_board_composition()
	var composition_framebuffer := composition.get("framebuffer") as Image
	var composition_report: Dictionary = composition.duplicate()
	composition_report.erase("framebuffer")
	for assertion in composition_report.get("assertions", PackedStringArray()):
		validation.assertions.append("final: " + String(assertion))
	for failure in composition_report.get("failed_assertions", PackedStringArray()):
		validation.failed_assertions.append("final: " + String(failure))
	if not bool(composition_report.get("passed", false)):
		validation.passed = false

	var image_to_save := composition_framebuffer if composition_framebuffer != null else framebuffer
	var image_error := _save_image(image_to_save, _image_path)
	if image_error != OK:
		validation.failed_assertions.append("não salvou PNG: erro %d" % image_error)
		validation.passed = false
	var report := {
		"schema": "qix.shipping.framebuffer.v1",
		"passed": validation.passed,
		"shader": SHADER_PATH,
		"renderer": {
			"method": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"adapter": RenderingServer.get_video_adapter_name(),
		},
		"synthetic_viewport": {"width": framebuffer.get_width(), "height": framebuffer.get_height()},
		"mask_format": "R8",
		"synthetic_shader": {
			"samples": _serializable_samples(samples),
			"background": _color_record(BACKGROUND),
			"distances_to_background": validation.distances_to_background,
		},
		"final_board_composition": composition_report,
		"assertions": validation.assertions,
		"failed_assertions": validation.failed_assertions,
		"image_path": ProjectSettings.globalize_path(_image_path),
	}
	var report_error := _write_json(_report_path, report)
	if report_error != OK:
		validation.failed_assertions.append(
			"não persistiu relatório JSON: erro %d" % report_error,
		)
		validation.passed = false
		report.passed = false
		report.failed_assertions = validation.failed_assertions
	print("QIX_SHIPPING_FRAMEBUFFER_JSON=" + JSON.stringify(report))
	await _finish(0 if validation.passed and report_error == OK else 1)


func _capture_final_board_composition() -> Dictionary:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	if campaign == null or campaign.rounds.is_empty():
		return _composition_error("campanha oficial não carregou")
	var content := campaign.rounds[0] as RoundContent
	if content == null or content.visual == null or content.visual.background == null:
		return _composition_error("rodada oficial não contém visual/background")
	var simulation := GameSimulation.new(
		content.rules,
		content.round_definition,
		content.seed_value,
	)
	var coordinates := {
		"free": Vector2i(35, 120),
		"boundary": Vector2i(85, 120),
		"trail": Vector2i(130, 120),
		"claimed": Vector2i(180, 120),
	}
	var diagnostic_bands := [
		{"rect": Rect2i(15, 60, 40, 160), "cell": BoardState.Cell.FREE},
		{"rect": Rect2i(65, 60, 40, 160), "cell": BoardState.Cell.BOUNDARY},
		{"rect": Rect2i(110, 60, 40, 160), "cell": BoardState.Cell.TRAIL},
		{"rect": Rect2i(160, 60, 50, 160), "cell": BoardState.Cell.CLAIMED},
	]
	for band_variant in diagnostic_bands:
		var band: Dictionary = band_variant
		var rect: Rect2i = band.rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				simulation.board.set_cell(x, y, int(band.cell))

	var viewport := SubViewport.new()
	viewport.name = "QixFinalBoardCompositionProbe"
	viewport.size = CoordinateSpace.VIEWPORT
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var board_view := QixBoardView.new()
	viewport.add_child(board_view)
	board_view.sync(simulation, content.visual)
	for _frame in 4:
		await RenderingServer.frame_post_draw
	var final_framebuffer := viewport.get_texture().get_image()
	if final_framebuffer == null or final_framebuffer.is_empty():
		viewport.queue_free()
		await get_tree().process_frame
		return _composition_error("QixBoardView produziu framebuffer vazio")
	var source_image := content.visual.background.get_image()
	if source_image == null or source_image.is_empty():
		viewport.queue_free()
		await get_tree().process_frame
		return _composition_error("background oficial não permitiu readback")

	var rendered_samples := {}
	var source_samples := {}
	var serialized_coordinates := {}
	for state_name_variant in coordinates:
		var state_name := String(state_name_variant)
		var field_coordinate: Vector2i = coordinates[state_name]
		var screen_coordinate := CoordinateSpace.field_to_screen(field_coordinate)
		rendered_samples[state_name] = final_framebuffer.get_pixelv(screen_coordinate)
		source_samples[state_name] = source_image.get_pixelv(field_coordinate)
		serialized_coordinates[state_name] = {
			"field": [field_coordinate.x, field_coordinate.y],
			"screen": [screen_coordinate.x, screen_coordinate.y],
		}
	var validation := validate_final_composition(
		rendered_samples,
		source_samples,
		content.visual,
	)
	var result := {
		"passed": validation.passed,
		"pipeline": "GameSimulation.BoardState -> QixBoardView R8 upload -> official background -> board_reveal.gdshader -> SubViewport framebuffer",
		"round_id": String(content.round_id),
		"viewport": {
			"width": final_framebuffer.get_width(),
			"height": final_framebuffer.get_height(),
		},
		"mask_format": "R8" if board_view.mask_format() == Image.FORMAT_R8 else str(board_view.mask_format()),
		"mask_matches_board": board_view.mask_bytes() == simulation.board.cells,
		"coordinates": serialized_coordinates,
		"rendered_samples": _serializable_samples(rendered_samples),
		"source_samples": _serializable_samples(source_samples),
		"distances_to_source": validation.distances_to_source,
		"assertions": validation.assertions,
		"failed_assertions": validation.failed_assertions,
		"framebuffer": final_framebuffer,
	}
	viewport.queue_free()
	await get_tree().process_frame
	return result


static func validate_final_composition(
	rendered: Dictionary,
	source: Dictionary,
	visual: RoundVisualDefinition,
) -> Dictionary:
	var failures := PackedStringArray()
	var assertions := PackedStringArray()
	for state_name in [&"free", &"boundary", &"trail", &"claimed"]:
		if not rendered.has(state_name) or not source.has(state_name):
			failures.append("sample final ausente: %s" % state_name)
	if visual == null:
		failures.append("visual final ausente")
	if not failures.is_empty():
		return {
			"passed": false,
			"assertions": assertions,
			"failed_assertions": failures,
			"distances_to_source": {},
		}
	var distances := {}
	for state_name in [&"free", &"boundary", &"trail", &"claimed"]:
		distances[String(state_name)] = _color_distance(
			rendered[state_name],
			source[state_name],
		)
	_assert_probe(
		float(distances.claimed) <= 0.06,
		"CLAIMED coincide com o texel da arte oficial",
		failures,
		assertions,
	)
	_assert_probe(
		float(distances.free) >= 0.08,
		"FREE oculta seu texel da arte oficial",
		failures,
		assertions,
	)
	_assert_probe(
		float(distances.boundary) >= 0.08,
		"BOUNDARY oculta seu texel da arte oficial",
		failures,
		assertions,
	)
	_assert_probe(
		float(distances.trail) >= 0.08,
		"TRAIL oculta seu texel da arte oficial",
		failures,
		assertions,
	)
	_assert_probe(
		_color_distance(rendered.free, visual.free_color) <= 0.18,
		"FREE preserva a paleta autorada após scanline",
		failures,
		assertions,
	)
	_assert_probe(
		_color_distance(rendered.boundary, visual.boundary_color) <= 0.28,
		"BOUNDARY preserva a paleta autorada após glint",
		failures,
		assertions,
	)
	var trail_distance := minf(
		_color_distance(rendered.trail, visual.trail_color),
		_color_distance(rendered.trail, visual.trail_hot_color),
	)
	_assert_probe(
		trail_distance <= 0.30,
		"TRAIL permanece entre as cores autoradas do pulso",
		failures,
		assertions,
	)
	_assert_probe(
		rendered.claimed.a >= 0.98,
		"composição final preserva alpha de CLAIMED",
		failures,
		assertions,
	)
	return {
		"passed": failures.is_empty(),
		"assertions": assertions,
		"failed_assertions": failures,
		"distances_to_source": distances,
	}


static func _composition_error(message: String) -> Dictionary:
	return {
		"passed": false,
		"assertions": PackedStringArray(),
		"failed_assertions": PackedStringArray([message]),
		"distances_to_source": {},
		"framebuffer": null,
	}


static func validate_samples(samples: Dictionary, background: Color) -> Dictionary:
	var failures := PackedStringArray()
	var assertions := PackedStringArray()
	var required := [&"free", &"boundary", &"trail", &"claimed"]
	for name in required:
		if not samples.has(name):
			failures.append("sample ausente: %s" % name)
	if not failures.is_empty():
		return {
			"passed": false,
			"assertions": assertions,
			"failed_assertions": failures,
			"distances_to_background": {},
		}

	var free: Color = samples.free
	var boundary: Color = samples.boundary
	var trail: Color = samples.trail
	var claimed: Color = samples.claimed
	var distances := {
		"free": _color_distance(free, background),
		"boundary": _color_distance(boundary, background),
		"trail": _color_distance(trail, background),
		"claimed": _color_distance(claimed, background),
	}
	_assert_probe(distances.claimed <= 0.04, "CLAIMED preserva RGB original", failures, assertions)
	_assert_probe(distances.free >= 0.25, "FREE cobre o fundo", failures, assertions)
	_assert_probe(distances.boundary >= 0.25, "BOUNDARY não revela o fundo", failures, assertions)
	_assert_probe(distances.trail >= 0.20, "TRAIL não revela o fundo", failures, assertions)
	_assert_probe(free.r < 0.16 and free.g < 0.22 and free.b < 0.28, "FREE usa cobertura escura", failures, assertions)
	_assert_probe(boundary.g > 0.60 and boundary.g > boundary.r + 0.20, "BOUNDARY mantém leitura verde", failures, assertions)
	_assert_probe(trail.r > 0.65 and trail.g > 0.45, "TRAIL mantém leitura quente", failures, assertions)
	_assert_probe(claimed.a >= 0.98, "CLAIMED preserva alpha opaco", failures, assertions)
	var nearest_covered := minf(distances.free, minf(distances.boundary, distances.trail))
	_assert_probe(distances.claimed + 0.15 < nearest_covered, "somente CLAIMED coincide com o fundo", failures, assertions)
	return {
		"passed": failures.is_empty(),
		"assertions": assertions,
		"failed_assertions": failures,
		"distances_to_background": distances,
	}


static func _assert_probe(
	condition: bool,
	message: String,
	failures: PackedStringArray,
	assertions: PackedStringArray,
) -> void:
	assertions.append(message)
	if not condition:
		failures.append(message)


static func _color_distance(left: Color, right: Color) -> float:
	var delta := Vector3(left.r - right.r, left.g - right.g, left.b - right.b)
	return delta.length()


static func _serializable_samples(samples: Dictionary) -> Dictionary:
	var result := {}
	for key in samples:
		result[String(key)] = _color_record(samples[key])
	return result


static func _color_record(color: Color) -> Dictionary:
	return {
		"hex": color.to_html(true),
		"rgba": [color.r, color.g, color.b, color.a],
	}


func _save_image(image: Image, path: String) -> int:
	var resolved := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if error != OK:
		return error
	return image.save_png(resolved)


func _write_json(path: String, report: Dictionary) -> Error:
	var resolved := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if error != OK:
		printerr("QIX_SHIPPING_FRAMEBUFFER_ERROR mkdir=%d path=%s" % [error, resolved.get_base_dir()])
		return error
	var file := FileAccess.open(resolved, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		printerr("QIX_SHIPPING_FRAMEBUFFER_ERROR open=%d path=%s" % [open_error, resolved])
		return open_error
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.flush()
	file.close()
	return OK


func _finish_error(message: String) -> void:
	var report := {
		"schema": "qix.shipping.framebuffer.v1",
		"passed": false,
		"error": message,
	}
	printerr("QIX_SHIPPING_FRAMEBUFFER_ERROR " + message)
	_write_json(_report_path, report)
	print("QIX_SHIPPING_FRAMEBUFFER_JSON=" + JSON.stringify(report))
	await _finish(1)


func _parse_arguments(arguments: PackedStringArray) -> void:
	for argument in arguments:
		if argument.begins_with("--report="):
			_report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--image="):
			_image_path = argument.trim_prefix("--image=")


func _finish(exit_code: int) -> void:
	_shutdown_host_audio()
	var tree := get_tree()
	if tree == null:
		return
	# O AudioServer precisa observar o stop/null dos streams antes do teardown final.
	await tree.process_frame
	tree.quit(exit_code)


func _shutdown_host_audio() -> void:
	if not is_instance_valid(_host_game):
		return
	var pending: Array[Node] = [_host_game]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is QixAudioDirector:
			(current as QixAudioDirector).shutdown()
		for child in current.get_children():
			if child is Node:
				pending.append(child)
