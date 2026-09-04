extends TestCase

const FRAME_PROBE_PATH := "res://tools/profile/exported_frame_pacing_probe.gd"
const FRAME_PROBE_NODE_PATH := "res://tools/profile/frame_pacing_probe_node.gd"
const FRAMEBUFFER_PROBE_PATH := "res://tools/shipping/framebuffer_shader_probe.gd"
const FRAMEBUFFER_PROBE_NODE_PATH := "res://tools/shipping/framebuffer_shader_probe_node.gd"


func test_probe_scripts_load_as_export_runtime_main_loops() -> void:
	for path in [FRAME_PROBE_PATH, FRAMEBUFFER_PROBE_PATH]:
		ok(ResourceLoader.exists(path), "%s precisa ser exportável" % path)
		var script := load(path) as GDScript
		ok(script != null, "%s precisa compilar" % path)
		if script != null:
			ok(script.can_instantiate(), "%s precisa ser instanciável" % path)
			var instance = script.new()
			ok(instance is SceneTree, "%s precisa rodar via --script no binário exportado" % path)
			instance.free()


func test_exported_main_scene_probe_nodes_are_loadable_and_share_the_contract() -> void:
	for path in [FRAME_PROBE_NODE_PATH, FRAMEBUFFER_PROBE_NODE_PATH]:
		ok(ResourceLoader.exists(path), "%s precisa entrar no PCK" % path)
		var script := load(path) as GDScript
		ok(script != null and script.can_instantiate(), "%s precisa compilar" % path)
		if script != null and script.can_instantiate():
			var instance = script.new()
			ok(instance is Node, "%s precisa ser hospedável pelo bootstrap" % path)
			instance.free()
	var wrapper := load(FRAME_PROBE_PATH) as GDScript
	var node_script := load(FRAME_PROBE_NODE_PATH) as GDScript
	if wrapper == null or node_script == null:
		return
	var samples: Array[float] = [8.0, 9.0, 10.0, 12.0, 30.0]
	eq(
		node_script.call("summarize_samples", samples),
		wrapper.call("summarize_samples", samples),
		"CLI e entrypoint exportado não podem divergir nos percentis",
	)


func test_frame_pacing_statistics_are_deterministic() -> void:
	var script := load(FRAME_PROBE_PATH) as GDScript
	ok(script != null)
	if script == null:
		return
	var samples: Array[float] = [8.0, 9.0, 10.0, 12.0, 30.0]
	var stats: Dictionary = script.call("summarize_samples", samples)
	eq(stats.sample_count, 5)
	eq(stats.p50_ms, 10.0)
	eq(stats.p95_ms, 30.0)
	eq(stats.max_ms, 30.0)
	eq(stats.over_16_667_ms, 1)


func test_frame_pacing_gate_never_passes_without_gameplay_and_real_gpu_timing() -> void:
	var script := load(FRAME_PROBE_PATH) as GDScript
	ok(script != null)
	if script == null:
		return
	var healthy_stats := {
		"p95_ms": 16.0,
		"p99_ms": 20.0,
		"max_ms": 24.0,
	}
	var no_gpu: Dictionary = script.call(
		"evaluate_shipping_gate",
		healthy_stats,
		false,
		true,
		true,
	)
	ok(not no_gpu.gpu_measurement_available)
	ok(not _all_checks_pass(no_gpu), "ausência de timing GPU deve ser inconclusiva, nunca verde")
	var no_gameplay: Dictionary = script.call(
		"evaluate_shipping_gate",
		healthy_stats,
		true,
		true,
		false,
	)
	ok(not no_gameplay.gameplay_active)
	ok(not _all_checks_pass(no_gameplay), "overlay/intro ocioso não pode satisfazer o perfil")
	var complete: Dictionary = script.call(
		"evaluate_shipping_gate",
		healthy_stats,
		true,
		true,
		true,
	)
	ok(_all_checks_pass(complete))


func test_external_gpu_route_stays_pending_until_the_companion_report_passes() -> void:
	var script := load(FRAME_PROBE_PATH) as GDScript
	ok(script != null)
	if script == null:
		return
	var healthy_stats := {
		"p95_ms": 16.0,
		"p99_ms": 20.0,
		"max_ms": 24.0,
	}
	var frame_checks: Dictionary = script.call(
		"evaluate_frame_pacing_gate",
		healthy_stats,
		true,
		true,
	)
	ok(_all_checks_pass(frame_checks))
	eq(
		script.call("classify_outcome", frame_checks, false, true),
		"external_gpu_pending",
		"telemetria delegada não pode fingir um passe completo",
	)
	eq(script.call("classify_outcome", frame_checks, false, false), "inconclusive")
	eq(script.call("classify_outcome", frame_checks, true, false), "passed")
	frame_checks.gameplay_active = false
	eq(script.call("classify_outcome", frame_checks, false, true), "failed")


func test_framebuffer_assertion_contract_distinguishes_revealed_background() -> void:
	var script := load(FRAMEBUFFER_PROBE_PATH) as GDScript
	ok(script != null)
	if script == null:
		return
	var background := Color8(41, 103, 211, 255)
	var samples := {
		"free": Color("071923"),
		"boundary": Color("46f5c5"),
		"trail": Color("ffd166"),
		"claimed": background,
	}
	var validation: Dictionary = script.call("validate_samples", samples, background)
	ok(validation.passed)
	eq(validation.failed_assertions, PackedStringArray())


func test_final_board_composition_contract_uses_each_source_texel() -> void:
	var script := load(FRAMEBUFFER_PROBE_PATH) as GDScript
	ok(script != null)
	if script == null:
		return
	var visual := RoundVisualDefinition.new()
	visual.free_color = Color("071923")
	visual.boundary_color = Color("46f5c5")
	visual.trail_color = Color("ffd166")
	visual.trail_hot_color = Color("fff4b0")
	var source := {
		"free": Color("b03080"),
		"boundary": Color("3060b0"),
		"trail": Color("20a080"),
		"claimed": Color("d26b3c"),
	}
	var rendered := {
		"free": visual.free_color,
		"boundary": visual.boundary_color,
		"trail": visual.trail_color,
		"claimed": source.claimed,
	}
	var validation: Dictionary = script.call(
		"validate_final_composition",
		rendered,
		source,
		visual,
	)
	ok(validation.passed)
	eq(validation.failed_assertions, PackedStringArray())


func _all_checks_pass(checks: Dictionary) -> bool:
	for value in checks.values():
		if not bool(value):
			return false
	return true
