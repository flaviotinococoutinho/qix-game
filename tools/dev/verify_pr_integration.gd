extends SceneTree
## QA com renderer real: fixtures controladas das PRs #103/#104/#106.
## Não é uma partida humana nem um teste de dificuldade. A rota real está em verify_depth_stage.

const OUTPUT := "res://build/integration-20260909"
var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)

func touch(index: int, point: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	return event

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var boot := (load("res://app/bootstrap.tscn") as PackedScene).instantiate() as QixBootstrap
	boot.audio_enabled = false
	root.add_child(boot)
	boot.set_physics_process(false)
	boot.set_process_unhandled_input(false)
	boot.session.step(MoveIntent.none(), true)
	var sim := boot.simulation
	# Fixture explícita: jogador no centro e dardo real criado por try_spawn com seed conhecida.
	sim.player.px = 112
	sim.player.py = 141
	sim.shield_ticks = 1200
	var slot := DartRules.try_spawn(sim.pools, sim.board, sim.player.cell(),
		DeterministicRng.new(17), 384, 24, 24, 900, 0)
	check(slot >= 0, "dardo da fixture nasceu")
	if slot < 0:
		boot.free()
		quit(1)
		return
	check(sim.pools.dart_cell(slot) == Vector2i(1, 141), "origem de produção a111 células do alvo")
	boot.touch_controls.touch_enabled = true
	boot.touch_controls.visible = true
	check(boot.touch_controls.is_visible_in_tree(), "overlay de toque visível no renderer")
	boot._sync_views([GameEvent.make(GameEvent.Kind.DART_ARMED, {"slot": slot})])
	var invariant := sim.state_checksum()
	var state := boot.minor_actor_view.presentation_state()
	var path: PackedVector2Array = state.darts[0].path
	check(path.has(CoordinateSpace.field_to_screen(sim.player.cell())), "aviso alcança jogador além de48 células")
	check(path.size() > 100, "percurso completo projetado")
	var pause_rect: Rect2 = boot.touch_controls.chrome_rects().pause.rect
	check(pause_rect.position.y == QixGameHud.TOP_BAR_HEIGHT, "pausa fora da banda superior")
	check(boot.touch_controls.chrome_rects().pause.veil.a <= 0.24, "véu de pausa translúcido")
	boot.touch_controls.handle_event(touch(90, Vector2(214, 14), true))
	check(not boot.touch_controls.consume_pause(), "posição antiga não aciona pausa")
	boot.touch_controls.handle_event(touch(90, Vector2(214, 14), false))
	boot.touch_controls.handle_event(touch(91, pause_rect.get_center(), true))
	check(boot.touch_controls.consume_pause(), "novo centro aciona pausa")
	boot.touch_controls.handle_event(touch(91, pause_rect.get_center(), false))
	var frames: Array[String] = []
	for depth in [true, false]:
		boot.depth_stage.set_enabled(depth)
		boot._sync_views([])
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		check(frame != null and frame.get_width() >= 480, "readback nativo real")
		var filename := "dart-touch-%s.png" % ("2_5d" if depth else "2d")
		frame.save_png(OUTPUT + "/" + filename)
		frames.append(filename)
	check(sim.state_checksum() == invariant, "render e touch não avançam domínio")
	var status := boot.hud.get_node("Status") as Label
	check(status.text == "DARDO ARMADO · DESVIE", "alerta visível durante ameaça")
	sim.pools.retire_dart(slot, MinorActorPools.Reason.ABSORBED, 12)
	var resolved := sim.state_checksum()
	boot._sync_views([GameEvent.make(GameEvent.Kind.DART_ABSORBED, {"slot": slot}),
		GameEvent.make(GameEvent.Kind.CAPTURED, {"filled_delta": 7})])
	check(status.text == "CAPTURA +7", "absorção libera recompensa no HUD real")
	check(sim.state_checksum() == resolved, "resolução visual não muta domínio")
	# Microbenchmark de CPU da view; não é frame pacing da GPU ou medição Android.
	sim.pools.clear_dart(slot)
	sim.pools.set_dart(slot, MinorActorPools.D.STATE, ActorLifecycle.State.DESPAWNED)
	for index in MinorActorPools.MAX_DARTS:
		DartRules.try_spawn(sim.pools, sim.board, sim.player.cell(),
			DeterministicRng.new(17 + index), 384, 24, 24, 900, 0)
	check(sim.pools.alive_darts() == MinorActorPools.MAX_DARTS, "microbenchmark com seis dardos armados")
	var profile := profile_view(boot.minor_actor_view, sim)
	var report := {"assertions": assertions, "errors": failures, "profile_cpu_us": profile,
		"renderer": RenderingServer.get_current_rendering_method(), "fixtures": true,
		"path_cells": path.size(), "pause_rect": str(pause_rect), "screenshots": frames,
		"cache": boot.minor_actor_view.telegraph_cache_state()}
	var file := FileAccess.open(OUTPUT + "/pr-runtime-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("QIX_PR_INTEGRATION ", JSON.stringify(report))
	boot.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func profile_view(view: QixMinorActorView, sim: GameSimulation) -> Dictionary:
	var result := {}
	for changing in [false, true]:
		var samples: Array[int] = []
		for sample in 240:
			if changing:
				sim.board.set_cell(5, 5, BoardState.Cell.CLAIMED if sample % 2 == 0 else BoardState.Cell.FREE)
			var started := Time.get_ticks_usec()
			view.sync(sim)
			samples.append(Time.get_ticks_usec() - started)
		samples.sort()
		result["territory_changes" if changing else "cached"] = {
			"samples": samples.size(), "p50_us": samples[120], "p95_us": samples[228],
			"max_us": samples.back(), "darts": sim.pools.alive_darts()}
	return result
