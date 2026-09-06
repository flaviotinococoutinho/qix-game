extends TestCase

const PRESETS_PATH := "res://export_presets.cfg"
const SHIPPING_ICON_PATH := "res://assets/icons/qix_game_icon.png"


func test_shipping_brand_icon_is_a_square_project_asset() -> void:
	var configured_icon := String(ProjectSettings.get_setting("application/config/icon", ""))
	eq(configured_icon, SHIPPING_ICON_PATH, "o projeto precisa declarar o ícone original de shipping")
	ok(FileAccess.file_exists(SHIPPING_ICON_PATH), "o PNG master do ícone precisa existir em res://")
	if not FileAccess.file_exists(SHIPPING_ICON_PATH):
		return
	var texture := load(SHIPPING_ICON_PATH) as Texture2D
	ok(texture != null, "o ícone precisa ser um PNG importado e legível")
	if texture == null:
		return
	eq(texture.get_width(), texture.get_height(), "ícone de app precisa ser quadrado")
	ok(texture.get_width() >= 1024, "master precisa preservar resolução para export desktop/mobile")


func test_shipping_presets_are_reproducible_and_secret_free() -> void:
	var config := ConfigFile.new()
	eq(config.load(PRESETS_PATH), OK, "export_presets.cfg precisa ser legível")
	if not config.has_section("preset.0") or not config.has_section("preset.1"):
		ok(false, "presets macOS e Android precisam existir")
		return

	_assert_preset(config, "preset.0", "macOS Shipping QA", "macOS")
	_assert_preset(config, "preset.1", "Android Shipping QA", "Android")

	var mac_options := "preset.0.options"
	eq(
		config.get_value(mac_options, "application/bundle_identifier", ""),
		"com.flaviocoutinho.qixgame",
	)
	eq(config.get_value(mac_options, "codesign/codesign", -1), 1, "macOS usa assinatura ad-hoc built-in")
	eq(config.get_value(mac_options, "notarization/notarization", -1), 0, "QA local não tenta notarizar")
	eq(
		config.get_value(mac_options, "binary_format/architecture", ""),
		"universal",
		"o template oficial disponível é universal; o runner reduz o bundle final para arm64",
	)

	var android_options := "preset.1.options"
	eq(
		config.get_value(android_options, "package/unique_name", ""),
		"com.flaviocoutinho.qixgame",
	)
	ok(config.get_value(android_options, "architectures/arm64-v8a", false), "APK QA precisa suportar o AVD arm64")
	ok(not config.get_value(android_options, "architectures/armeabi-v7a", true), "APK QA deve limitar tamanho ao ABI exercitado")
	ok(not config.get_value(android_options, "gradle_build/use_gradle_build", true), "QA usa o template APK versionado da engine")
	var custom_permissions: PackedStringArray = config.get_value(
		android_options,
		"permissions/custom_permissions",
		PackedStringArray(),
	)
	ok(custom_permissions.has("android.permission.VIBRATE"), "feedback háptico handheld requer VIBRATE")
	for section in config.get_sections():
		for key in config.get_section_keys(section):
			var normalized := String(key).to_lower()
			ok(not normalized.contains("password"), "%s não deve persistir senha" % key)
			ok(not normalized.contains("certificate_file"), "%s não deve persistir certificado" % key)
			ok(not normalized.contains("provisioning_profile"), "%s não deve persistir profile" % key)


func test_shipping_probes_and_runner_are_exported_but_build_outputs_are_not() -> void:
	for path in [
		"res://tools/profile/exported_frame_pacing_probe.gd",
		"res://tools/profile/frame_pacing_probe_node.gd",
		"res://tools/profile/parse_metal_hud.py",
		"res://tools/shipping/framebuffer_shader_probe.gd",
		"res://tools/shipping/framebuffer_shader_probe_node.gd",
		"res://tools/shipping/thin_macos_bundle_arm64.sh",
		"res://tools/shipping/with_temporary_android_jdk.sh",
		"res://tools/shipping/verify_exported_runtime_payload.sh",
		"res://tools/shipping/validate_probe_report.sh",
		"res://tools/shipping/run_shipping_qa.sh",
	]:
		ok(FileAccess.file_exists(path), "%s precisa existir" % path)

	var config := ConfigFile.new()
	eq(config.load(PRESETS_PATH), OK)
	for section in ["preset.0", "preset.1"]:
		eq(config.get_value(section, "export_filter", ""), "all_resources")
		var excluded := String(config.get_value(section, "exclude_filter", ""))
		ok(excluded.contains("build/shipping/**"), "%s evita export recursivo" % section)
		ok(not excluded.contains("addons/**"), "%s não pode remover autoloads de runtime" % section)
		ok(excluded.contains("addons/fennara/bin/**"), "%s remove o binário Fennara de editor" % section)
		ok(excluded.contains("addons/fennara/ai/**"), "%s remove integração Fennara de editor" % section)
		ok(excluded.contains("addons/fennara/dist/**"), "%s remove distribuição Fennara" % section)
		ok(excluded.contains("guide_examples/**"), "%s não leva exemplos de plugins" % section)
		ok(excluded.contains("samples/**"), "%s não leva amostras de desenvolvimento" % section)
		ok(
			excluded.contains("antipixel_state_machine/**"),
			"%s não leva a máquina de estados de vendor" % section,
		)
		# Pasta já removida do versionamento (ADR-0010). O filtro fica porque um checkout que
		# rebaixe os addons pela AssetLib a recria em disco, e `.gitignore` não cobre o payload.
		ok(
			excluded.contains("addons/curved_lines_2d/**"),
			"%s não leva o vetor escalável de vendor" % section,
		)
		ok(
			not excluded.contains("addons/fennara/runtime/**"),
			"%s preserva o autoload e dependências Fennara" % section,
		)
		ok(
			not excluded.contains("addons/godot_ai/runtime/**"),
			"%s preserva o helper de runtime Godot AI" % section,
		)
		ok(
			not excluded.contains("addons/godot_ai/utils/**"),
			"%s preserva utilitários usados pelo helper Godot AI" % section,
		)
		ok(excluded.contains("tests/**"), "%s não empacota a suíte de desenvolvimento" % section)
		ok(excluded.contains("reference_root/**"), "%s não empacota material de referência" % section)
		ok(excluded.contains("*.pdf"), "%s não empacota documentos" % section)


func test_shipping_runner_requires_structured_probe_outcomes_and_quiet_smoke_audio() -> void:
	var runner := FileAccess.get_file_as_string("res://tools/shipping/run_shipping_qa.sh")
	var validator := FileAccess.get_file_as_string(
		"res://tools/shipping/validate_probe_report.sh",
	)
	ok(runner.contains("--headless --audio-driver Dummy --quit-after 180"))
	for metal_setting in [
		"MTL_HUD_ENABLED=1",
		"MTL_HUD_LOG_ENABLED=1",
		"MTL_HUD_ENCODER_TIMING_ENABLED=1",
		"MTL_HUD_SHOW_ZERO_METRICS=1",
	]:
		ok(runner.contains(metal_setting), "runner precisa ativar %s" % metal_setting)
	ok(runner.contains("--rendering-method mobile"))
	ok(not runner.contains("--script res://tools/profile/exported_frame_pacing_probe.gd"))
	ok(not runner.contains("--script res://tools/shipping/framebuffer_shader_probe.gd"))
	ok(runner.contains("--shipping-probe=frame-pacing"))
	ok(runner.contains("--shipping-probe=framebuffer"))
	ok(runner.contains("--external-gpu=metal-hud"))
	ok(runner.contains("parse_metal_hud.py"))
	var frame_run := runner.find("run_logged macos-frame-pacing /usr/bin/env")
	var frame_gate := runner.find("run_logged macos-frame-pacing-report")
	var metal_parse := runner.find("run_logged macos-metal-hud-parse")
	var metal_gate := runner.find("run_logged macos-metal-hud-report")
	ok(frame_run >= 0 and frame_run < frame_gate, "JSON de frame deve ser validado após o probe")
	ok(frame_gate < metal_parse, "parser GPU só roda após validar external_gpu_pending")
	ok(metal_parse < metal_gate, "JSON Metal HUD deve ser validado após o parser")
	ok(runner.contains("run_logged macos-framebuffer-report"))
	ok(
		runner.contains("run_logged macos-frame-pacing-log-scan"),
		"log gráfico de frame pacing também precisa passar pelo scanner de runtime",
	)
	ok(
		runner.contains("run_logged macos-framebuffer-log-scan"),
		"log gráfico de framebuffer também precisa passar pelo scanner de runtime",
	)
	ok(
		runner.contains("ObjectDB.*[Ll]eak"),
		"scanner precisa cobrir a redação real do aviso de leak do ObjectDB",
	)
	ok(
		runner.contains("run_logged macos-audio-smoke"),
		"runner deve reproduzir o smoke gráfico auditável com áudio normal",
	)
	var audio_smoke_run := runner.find("run_logged macos-audio-smoke run_macos_audio_smoke")
	var audio_smoke_scan := runner.find("run_logged macos-audio-smoke-log-scan")
	ok(audio_smoke_run >= 0 and audio_smoke_run < audio_smoke_scan)
	if audio_smoke_run >= 0 and audio_smoke_scan > audio_smoke_run:
		var audio_smoke_invocation := runner.substr(
			audio_smoke_run,
			audio_smoke_scan - audio_smoke_run,
		)
		ok(
			not audio_smoke_invocation.contains("--audio-driver Dummy"),
			"smoke gráfico precisa exercitar o driver de áudio normal",
		)
	ok(
		runner.contains("--shipping-audio-smoke-ticks=900"),
		"smoke de áudio precisa solicitar 900 callbacks físicos ao bootstrap exportado",
	)
	ok(
		not runner.contains('"$executable" --quit-after 900'),
		"--quit-after conta iterações do loop principal e não prova ticks físicos",
	)
	ok(
		runner.contains("elapsed_wall_seconds="),
		"evidência do smoke deve registrar duração de parede observada",
	)
	for evidence_field in [
		"schema=qix.shipping.macos-audio-smoke.v2",
		"requested_physics_ticks=",
		"completed_physics_ticks=",
		"physics_ticks_per_second=",
		"nominal_runtime_seconds=",
		"runtime_completion_markers=",
	]:
		ok(runner.contains(evidence_field), "evidência semântica requer %s" % evidence_field)
	ok(
		runner.contains("QIX_SHIPPING_AUDIO_SMOKE_COMPLETE"),
		"runner precisa validar a conclusão emitida pelo contador físico do runtime",
	)
	ok(
		runner.contains("completion_marker_count != 1"),
		"marcador ausente ou duplicado deve falhar o estágio",
	)
	ok(
		runner.contains("completed_physics_ticks != requested_physics_ticks"),
		"evidência divergente entre ticks solicitados e concluídos deve falhar",
	)
	ok(
		runner.contains("audio_driver=runtime-default"),
		"evidência deve registrar que o smoke não silenciou o áudio normal",
	)
	ok(
		runner.contains(
			'MACOS_AUDIO_SMOKE_TIMEOUT_SECONDS="${QIX_MACOS_AUDIO_SMOKE_TIMEOUT_SECONDS:-30}"',
		),
		"watchdog externo do smoke precisa de default autorável e finito",
	)
	ok(
		runner.contains('"$executable" -- --shipping-audio-smoke-ticks=900 &'),
		"runtime do smoke precisa ser supervisionado como processo externo",
	)
	for watchdog_contract in [
		"kill -TERM",
		"kill -KILL",
		"watchdog_timeout_seconds=",
		"watchdog_timed_out=",
		"watchdog_termination_signal=",
		'print -r -- "outcome=$evidence_outcome"',
		'evidence_outcome="timed_out"',
		'coherence_error="runtime_timeout"',
	]:
		ok(runner.contains(watchdog_contract), "watchdog sem contrato %s" % watchdog_contract)
	ok(runner.contains("with_temporary_android_jdk.sh"))
	ok(runner.contains("QIX_ANDROID_EMULATOR_GPU"), "AVD deve permitir backend host autorável")
	ok(runner.contains("-gpu \"$ANDROID_EMULATOR_GPU\""), "smoke evita fallback lento do AVD")
	ok(runner.contains("getprop dev.bootcomplete"), "sys.boot_completed sozinho não garante Android estável")
	ok(runner.contains("getprop sys.user.0.ce_available"), "smoke espera o usuário desbloqueado")
	ok(runner.contains("cmd package wait-for-handler --timeout"), "PackageManager precisa drenar o handler")
	ok(runner.contains("install --no-streaming --no-incremental"), "instalação separa push do PackageManager")
	ok(
		runner.contains("QIX_ANDROID_PROCESS_START_TIMEOUT"),
		"launch assíncrono precisa de uma janela própria antes de exigir PID",
	)
	ok(
		runner.contains("process_seen"),
		"ausência transitória de PID não pode ser confundida com morte do processo",
	)
	ok(runner.contains("OnGodotMainLoopStarted"), "janela de sobrevivência começa na main loop, não no launch")
	ok(runner.contains("QIX_ANDROID_SMOKE_SECONDS"), "tempo de sobrevivência deve ser configurável")
	ok(
		runner.contains("QIX_ANDROID_DEVICE_SERIAL"),
		"seleção de device Android deve exigir override nominal explícito",
	)
	ok(
		runner.contains("QIX_ANDROID_ALLOW_PHYSICAL_DEVICE"),
		"hardware físico deve exigir segundo opt-in explícito",
	)
	ok(
		runner.contains("android_serial_is_emulator"),
		"seleção automática deve aceitar somente serial emulator-*",
	)
	ok(
		not runner.contains('NR > 1 && $2 == "device" {print $1; exit}'),
		"runner não pode escolher o primeiro device adb, que pode ser um telefone",
	)
	ok(
		runner.contains('if [[ -x "$ADB" && -f "$APK" ]]'),
		"override físico explícito não deve depender da presença do binário de emulator",
	)
	ok(runner.contains("runner_status=complete"), "run-state precisa fechar explicitamente quando todos os gates passam")
	ok(runner.contains("runner_status=failed"), "run-state precisa distinguir término com falha")
	for native_crash_marker in ["SIGSEGV", "SIGBUS", "SIGABRT", ">>> ${PACKAGE_ID} <<<", "Cmdline: ${PACKAGE_ID}"]:
		ok(runner.contains(native_crash_marker), "scanner Android cobre %s" % native_crash_marker)
	ok(validator.contains("expect_string outcome external_gpu_pending"))
	ok(validator.contains("expect_string outcome passed"))
	ok(validator.contains("frame_pacing_passed"))
	ok(validator.contains("external_gpu_report_required"))
	ok(validator.contains("checks.nonzero_gpu_signal"))
	ok(validator.contains("metal_hud_valid_pairs"))
	ok(validator.contains("final_board_composition.passed"))
	ok(validator.contains("final_board_composition.mask_matches_board"))
	ok(validator.contains("failed_assertions"))


func _assert_preset(config: ConfigFile, section: String, expected_name: String, expected_platform: String) -> void:
	eq(config.get_value(section, "name", ""), expected_name)
	eq(config.get_value(section, "platform", ""), expected_platform)
	ok(config.get_value(section, "runnable", false), "%s precisa ser executável" % expected_name)
	eq(config.get_value(section, "custom_features", ""), "shipping_qa")
