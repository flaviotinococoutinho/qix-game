extends Node
## Componente de frame pacing executável dentro da cena principal exportada.
##
## O template oficial pode ignorar `--script` contra seu PCK embutido. O
## QixBootstrap cria este Node somente quando o build shipping_qa recebe
## `--shipping-probe=frame-pacing` nos argumentos de usuário.

const DEFAULT_WARMUP_FRAMES := 120
const DEFAULT_SAMPLE_FRAMES := 600
const MAX_GAMEPLAY_WAIT_FRAMES := 600
const FRAME_BUDGET_MS := 16.667

var _output_path := "user://shipping/frame-pacing.json"
var _warmup_frames := DEFAULT_WARMUP_FRAMES
var _sample_frames := DEFAULT_SAMPLE_FRAMES
var _external_gpu_source := ""
var _frame_index := 0
var _gameplay_wait_frames := 0
var _gameplay_started := false
var _intro_skip_requested := false
var _last_frame_usec := 0
var _viewport_rid := RID()
var _game: Node
var _frame_intervals: Array[float] = []
var _render_cpu_times: Array[float] = []
var _render_gpu_times: Array[float] = []
var _frame_setup_cpu_times: Array[float] = []
var _process_times: Array[float] = []
var _physics_times: Array[float] = []
var _draw_calls: Array[float] = []
var _finishing := false
var _started := false


func _ready() -> void:
	set_process(false)


func start(game: Node, arguments: PackedStringArray) -> void:
	if _started:
		return
	_started = true
	_game = game
	_parse_arguments(arguments)
	if not is_instance_valid(_game):
		_finishing = true
		_finish_with_error.call_deferred("cena principal exportada ausente")
		return
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_last_frame_usec = Time.get_ticks_usec()
	set_process(true)
	print(
		"QIX_SHIPPING_FRAME_PACING_START warmup=%d samples=%d entrypoint=main-scene" % [
			_warmup_frames,
			_sample_frames,
		],
	)


func _process(_delta: float) -> void:
	if not is_instance_valid(_game) or _finishing:
		return
	var now_usec := Time.get_ticks_usec()
	if not _is_gameplay_active():
		_last_frame_usec = now_usec
		if _gameplay_started:
			_finishing = true
			set_process(false)
			_finish_with_error.call_deferred("gameplay deixou a fase ativa durante a amostragem")
			return
		_gameplay_wait_frames += 1
		if not _intro_skip_requested:
			Input.action_press(&"ui_accept")
			_intro_skip_requested = true
		elif _gameplay_wait_frames > 1:
			Input.action_release(&"ui_accept")
		if _gameplay_wait_frames >= MAX_GAMEPLAY_WAIT_FRAMES:
			_finishing = true
			set_process(false)
			_finish_with_error.call_deferred(
				"gameplay não ficou ativo após %d frames" % _gameplay_wait_frames,
			)
		return
	if not _gameplay_started:
		_gameplay_started = true
		Input.action_release(&"ui_accept")
		_last_frame_usec = now_usec
		print(
			"QIX_SHIPPING_FRAME_PACING_GAMEPLAY_ACTIVE wait_frames=%d" % _gameplay_wait_frames,
		)
		return
	var interval_ms := (now_usec - _last_frame_usec) / 1000.0
	_last_frame_usec = now_usec
	_drive_safe_boundary_motion()
	if _frame_index >= _warmup_frames:
		_frame_intervals.append(interval_ms)
		_render_cpu_times.append(
			RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid),
		)
		_render_gpu_times.append(
			RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid),
		)
		_frame_setup_cpu_times.append(RenderingServer.get_frame_setup_time_cpu())
		_process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_physics_times.append(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		)
		_draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_frame_index += 1
	if _frame_intervals.size() < _sample_frames:
		return
	_finishing = true
	set_process(false)
	_finish.call_deferred()


func _drive_safe_boundary_motion() -> void:
	var phase := _frame_index % 240
	Input.action_release(&"draw")
	if phase < 120:
		Input.action_press(&"move_left")
		Input.action_release(&"move_right")
	else:
		Input.action_release(&"move_left")
		Input.action_press(&"move_right")


func _finish() -> void:
	_release_actions()
	if _viewport_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)
	var frame_stats := summarize_samples(_frame_intervals)
	var gpu_stats := summarize_samples(_render_gpu_times)
	var gpu_measurement_available := float(gpu_stats.get("max_ms", 0.0)) > 0.0
	var external_gpu_requested := _external_gpu_source == "metal-hud"
	var frame_checks := evaluate_frame_pacing_gate(
		frame_stats,
		_frame_intervals.size() >= _sample_frames,
		_is_gameplay_active(),
	)
	var frame_pacing_passed := _all_checks_pass(frame_checks)
	var shipping_checks := frame_checks.duplicate()
	shipping_checks["gpu_measurement_available"] = gpu_measurement_available
	var outcome := classify_outcome(
		frame_checks,
		gpu_measurement_available,
		external_gpu_requested,
	)
	var passed := outcome == "passed"
	var report := {
		"schema": "qix.shipping.frame-pacing.v1",
		"passed": passed,
		"outcome": outcome,
		"frame_pacing_passed": frame_pacing_passed,
		"measurement": "wall-clock frame intervals plus RenderingServer viewport timings in exported main scene; GPU can be delegated to a separately gated Apple Metal HUD report",
		"entrypoint": "exported-main-scene-dispatch",
		"engine_version": Engine.get_version_info(),
		"platform": OS.get_name(),
		"distribution_name": OS.get_distribution_name(),
		"processor": OS.get_processor_name(),
		"renderer": {
			"method": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"vendor": RenderingServer.get_video_adapter_vendor(),
			"api_version": RenderingServer.get_video_adapter_api_version(),
		},
		"display_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"warmup_frames": _warmup_frames,
		"sample_frames": _sample_frames,
		"gameplay_wait_frames": _gameplay_wait_frames,
		"gameplay_active_at_finish": _is_gameplay_active(),
		"frame_budget_ms": FRAME_BUDGET_MS,
		"frame_intervals": frame_stats,
		"render_cpu": summarize_samples(_render_cpu_times),
		"render_gpu": gpu_stats,
		"render_gpu_measurement_available": gpu_measurement_available,
		"external_gpu_source": _external_gpu_source,
		"external_gpu_report_required": external_gpu_requested,
		"frame_setup_cpu": summarize_samples(_frame_setup_cpu_times),
		"process": summarize_samples(_process_times),
		"physics_process": summarize_samples(_physics_times),
		"draw_calls": summarize_samples(_draw_calls),
		"video_memory_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"checks": shipping_checks,
	}
	var report_error := _write_report(report)
	await _shutdown_game_cleanly()
	var measurement_succeeded := passed or (
		external_gpu_requested
		and outcome == "external_gpu_pending"
		and frame_pacing_passed
	)
	get_tree().quit(0 if measurement_succeeded and report_error == OK else 1)


func _finish_with_error(message: String) -> void:
	_release_actions()
	if _viewport_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)
	var report := {
		"schema": "qix.shipping.frame-pacing.v1",
		"passed": false,
		"outcome": "failed",
		"entrypoint": "exported-main-scene-dispatch",
		"error": message,
		"gameplay_wait_frames": _gameplay_wait_frames,
		"gameplay_started": _gameplay_started,
	}
	printerr("QIX_SHIPPING_FRAME_PACING_ERROR " + message)
	_write_report(report)
	await _shutdown_game_cleanly()
	get_tree().quit(1)


func _write_report(report: Dictionary) -> Error:
	var resolved := ProjectSettings.globalize_path(_output_path)
	var error := DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if error != OK:
		printerr(
			"QIX_SHIPPING_FRAME_PACING_ERROR mkdir=%d path=%s" % [
				error,
				resolved.get_base_dir(),
			],
		)
		return error
	var file := FileAccess.open(resolved, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		printerr(
			"QIX_SHIPPING_FRAME_PACING_ERROR open=%d path=%s" % [open_error, resolved],
		)
		return open_error
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.flush()
	file.close()
	print("QIX_SHIPPING_FRAME_PACING_JSON=" + JSON.stringify(report))
	return OK


func _parse_arguments(arguments: PackedStringArray) -> void:
	for argument in arguments:
		if argument.begins_with("--output="):
			_output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--warmup-frames="):
			_warmup_frames = maxi(2, int(argument.trim_prefix("--warmup-frames=")))
		elif argument.begins_with("--sample-frames="):
			_sample_frames = maxi(30, int(argument.trim_prefix("--sample-frames=")))
		elif argument.begins_with("--external-gpu="):
			_external_gpu_source = argument.trim_prefix("--external-gpu=").strip_edges()


func _release_actions() -> void:
	for action in [&"move_left", &"move_right", &"draw", &"ui_accept"]:
		Input.action_release(action)


func _is_gameplay_active() -> bool:
	if not is_instance_valid(_game):
		return false
	var session = _game.get("session")
	return session != null \
		and session.has_method("is_gameplay_active") \
		and bool(session.call("is_gameplay_active"))


func _shutdown_game_cleanly() -> void:
	if not is_instance_valid(_game):
		return
	var feedback = _game.get_node_or_null("ShippingFeedback")
	if feedback != null and feedback.get("audio") is QixAudioDirector:
		(feedback.get("audio") as QixAudioDirector).shutdown()
	await get_tree().process_frame


static func evaluate_shipping_gate(
	frame_stats: Dictionary,
	gpu_measurement_available: bool,
	enough_samples: bool,
	gameplay_active: bool,
) -> Dictionary:
	var checks := evaluate_frame_pacing_gate(frame_stats, enough_samples, gameplay_active)
	checks["gpu_measurement_available"] = gpu_measurement_available
	return checks


static func evaluate_frame_pacing_gate(
	frame_stats: Dictionary,
	enough_samples: bool,
	gameplay_active: bool,
) -> Dictionary:
	return {
		"enough_samples": enough_samples,
		"gameplay_active": gameplay_active,
		"frame_p95_within_25ms": float(frame_stats.get("p95_ms", INF)) <= 25.0,
		"frame_p99_within_40ms": float(frame_stats.get("p99_ms", INF)) <= 40.0,
		"no_150ms_stall": float(frame_stats.get("max_ms", INF)) <= 150.0,
	}


static func classify_outcome(
	frame_checks: Dictionary,
	gpu_measurement_available: bool,
	external_gpu_requested: bool,
) -> String:
	if not _all_checks_pass(frame_checks):
		return "failed"
	if gpu_measurement_available:
		return "passed"
	if external_gpu_requested:
		return "external_gpu_pending"
	return "inconclusive"


static func _all_checks_pass(checks: Dictionary) -> bool:
	for value in checks.values():
		if not bool(value):
			return false
	return true


static func summarize_samples(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {
			"sample_count": 0,
			"mean_ms": 0.0,
			"p50_ms": 0.0,
			"p95_ms": 0.0,
			"p99_ms": 0.0,
			"max_ms": 0.0,
			"over_16_667_ms": 0,
			"over_20_ms": 0,
			"over_33_333_ms": 0,
		}
	var ordered := samples.duplicate()
	ordered.sort()
	var total := 0.0
	var over_budget := 0
	var over_twenty := 0
	var over_thirty_three := 0
	for sample in samples:
		total += sample
		if sample > FRAME_BUDGET_MS:
			over_budget += 1
		if sample > 20.0:
			over_twenty += 1
		if sample > 33.333:
			over_thirty_three += 1
	return {
		"sample_count": samples.size(),
		"mean_ms": total / samples.size(),
		"p50_ms": _percentile(ordered, 50),
		"p95_ms": _percentile(ordered, 95),
		"p99_ms": _percentile(ordered, 99),
		"max_ms": ordered[-1],
		"over_16_667_ms": over_budget,
		"over_20_ms": over_twenty,
		"over_33_333_ms": over_thirty_three,
	}


static func _percentile(ordered: Array[float], percentile: int) -> float:
	if ordered.is_empty():
		return 0.0
	var rank := ceili((percentile / 100.0) * ordered.size()) - 1
	return ordered[clampi(rank, 0, ordered.size() - 1)]
