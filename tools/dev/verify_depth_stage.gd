extends SceneTree
## Verificação com renderer real da composição 2.5D e isolamento do domínio.
## Uso: Godot --path . --script res://tools/dev/verify_depth_stage.gd

var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(message)


func _run() -> void:
	var bootstrap := (load("res://app/bootstrap.tscn") as PackedScene).instantiate() as QixBootstrap
	bootstrap.audio_enabled = false
	root.add_child(bootstrap)
	# Godot habilita callbacks ao entrar na árvore: interromper depois de _ready.
	bootstrap.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var stage := bootstrap.depth_stage
	_check(stage != null, "palco instanciado")
	_check(stage.surface_viewport.size == CoordinateSpace.VIEWPORT*3, "surface nativa 720x960")
	_check(stage.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "câmera ortográfica")
	_check(bootstrap.board_view.get_parent() == stage.surface_root, "board projetado")
	_check(bootstrap.hud.get_parent() == bootstrap, "HUD fora do plano")
	_check(bootstrap.touch_controls.get_parent() == bootstrap, "toque fora do plano")
	_check(stage.presentation_state().loaded_models == 6, "seis modelos importados")
	var controls := bootstrap.round_transition.get_node("Controls") as ColorRect
	var legend := controls.get_node("Legend") as Label
	var previous_bottom := legend.position.y + legend.size.y
	for index in QixRoundTransitionView.CONTROL_LINES.size():
		var row := controls.get_node("Command%d" % index) as Label
		_check(row.position.y >= previous_bottom + 1.0, "comando %d sem sobreposição após layout real" % index)
		previous_bottom = row.position.y + row.size.y
	var initial := bootstrap.simulation.state_checksum()
	stage.set_enabled(false)
	bootstrap._sync_views([])
	_check(bootstrap.board_view.get_parent() == bootstrap, "fallback plano preserva o board")
	_check(bootstrap.player_view.show_body, "corpo 2D visível no fallback")
	stage.set_enabled(true)
	stage.reduced_motion = true
	bootstrap._sync_views([])
	bootstrap.actor_trace.visible = true
	bootstrap.actor_trace.sync(bootstrap.session, bootstrap._input_adapter)
	_check(bootstrap.actor_trace.get_child_count() > 0, "diagnóstico F3 compõe painel no runtime")
	bootstrap.actor_trace.visible = false
	_check(initial == bootstrap.simulation.state_checksum(), "alternância visual preserva checksum")
	stage.reduced_motion = false
	DirAccess.make_dir_recursive_absolute("res://build/modernization")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/modernization/intro-2_5d.png")
	var events := bootstrap.session.step(MoveIntent.none(), true)
	bootstrap._sync_views(events)
	# Rota usa a entrada pública do domínio, sem reposicionar ator ou pintar território.
	for segment in [[MoveIntent.Dir.LEFT, false, 36], [MoveIntent.Dir.DOWN, true, 141]]:
		for tick in int(segment[2]):
			events = bootstrap.session.step(MoveIntent.make(segment[0], segment[1]))
			bootstrap._sync_views(events)
	# Assenta apenas o contador visual, sem gastar escudo ou mover atores no screenshot.
	var captured_checksum := bootstrap.simulation.state_checksum()
	for frame in 64:
		bootstrap.hud.sync(bootstrap.session, false, [])
	await process_frame
	await RenderingServer.frame_post_draw
	_check(bootstrap.simulation.state_checksum() == captured_checksum, "readback não avança gameplay")
	var screenshot := root.get_texture().get_image()
	_check(screenshot != null and screenshot.get_width() >= 480, "framebuffer nativo >=2x lógico na tela disponível")
	_check(bootstrap.simulation.fills_done == 1, "captura real completada")
	_check(bootstrap.simulation.beacons.captured_count() > 0, "captura ativou baliza")
	screenshot.save_png("res://build/modernization/gameplay-2_5d.png")
	var result := {"assertions": _assertions, "errors": _failures, "renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [screenshot.get_width(), screenshot.get_height()], "stage": stage.presentation_state(),
		"permille": bootstrap.simulation.permille, "beacons": bootstrap.simulation.beacons.captured_count()}
	var file := FileAccess.open("res://build/modernization/depth-stage-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print("QIX_DEPTH_STAGE ", JSON.stringify(result))
	bootstrap.free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
