#!/bin/zsh
# Reproduz exports e smoke tests locais sem credenciais de distribuição.
set -u

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h:h}"
GODOT_BIN="${QIX_GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
ANDROID_SDK="${QIX_ANDROID_SDK:-/Users/flaviocoutinho/Library/Android/sdk}"
JDK_ROOT="${QIX_JDK_ROOT:-/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home}"
EDITOR_SETTINGS="${QIX_EDITOR_SETTINGS:-/Users/flaviocoutinho/Library/Application Support/Godot/editor_settings-4.7.tres}"
OUTPUT_ROOT="${QIX_SHIPPING_OUTPUT:-${PROJECT_ROOT}/build/shipping}"
MAC_DIR="${OUTPUT_ROOT}/macos"
ANDROID_DIR="${OUTPUT_ROOT}/android"
REPORT_DIR="${OUTPUT_ROOT}/reports"
MAC_APP="${MAC_DIR}/QIX GAME.app"
MAC_EXECUTABLE="${MAC_APP}/Contents/MacOS/QIX GAME"
MAC_FRAME_REPORT="${REPORT_DIR}/macos-frame-pacing.json"
MAC_METAL_HUD_REPORT="${REPORT_DIR}/macos-metal-hud.json"
MAC_FRAMEBUFFER_REPORT="${REPORT_DIR}/macos-framebuffer.json"
MAC_FRAMEBUFFER_IMAGE="${REPORT_DIR}/macos-framebuffer.png"
MACOS_AUDIO_SMOKE_TIMEOUT_SECONDS="${QIX_MACOS_AUDIO_SMOKE_TIMEOUT_SECONDS:-30}"
APK="${ANDROID_DIR}/qix-game-shipping-qa.apk"
PACKAGE_ID="com.flaviocoutinho.qixgame"
ADB="${ANDROID_SDK}/platform-tools/adb"
EMULATOR="${ANDROID_SDK}/emulator/emulator"
AVD_NAME="${QIX_ANDROID_AVD:-Medium_Phone_API_36.0}"
ANDROID_EMULATOR_GPU="${QIX_ANDROID_EMULATOR_GPU:-host}"
ANDROID_EMULATOR_CORES="${QIX_ANDROID_EMULATOR_CORES:-4}"
ANDROID_EMULATOR_MEMORY_MB="${QIX_ANDROID_EMULATOR_MEMORY_MB:-3072}"
ANDROID_EMULATOR_MIN_FREE_KIB="${QIX_ANDROID_EMULATOR_MIN_FREE_KIB:-3145728}"
ANDROID_READY_STREAK="${QIX_ANDROID_READY_STREAK:-3}"
ANDROID_PROCESS_START_TIMEOUT="${QIX_ANDROID_PROCESS_START_TIMEOUT:-15}"
ANDROID_MAIN_LOOP_TIMEOUT="${QIX_ANDROID_MAIN_LOOP_TIMEOUT:-90}"
ANDROID_SMOKE_SECONDS="${QIX_ANDROID_SMOKE_SECONDS:-30}"
ANDROID_DEVICE_SERIAL_OVERRIDE="${QIX_ANDROID_DEVICE_SERIAL:-}"
ANDROID_ALLOW_PHYSICAL_DEVICE="${QIX_ANDROID_ALLOW_PHYSICAL_DEVICE:-0}"
ANDROID_EMULATOR_PORT_OVERRIDE="${QIX_ANDROID_EMULATOR_PORT:-}"
MIN_FREE_KIB="${QIX_MIN_FREE_KIB:-2097152}"
MAC_THINNER="${SCRIPT_DIR}/thin_macos_bundle_arm64.sh"
PAYLOAD_VERIFIER="${SCRIPT_DIR}/verify_exported_runtime_payload.sh"
ANDROID_JDK_WRAPPER="${SCRIPT_DIR}/with_temporary_android_jdk.sh"
PROBE_REPORT_VALIDATOR="${SCRIPT_DIR}/validate_probe_report.sh"
METAL_HUD_PARSER="${PROJECT_ROOT}/tools/profile/parse_metal_hud.py"

mkdir -p "$MAC_DIR" "$ANDROID_DIR" "$REPORT_DIR"

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
{
	print -r -- "run_id=$run_id"
	print -r -- "started_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	print -r -- "runner_status=running"
} >"${REPORT_DIR}/run-state.txt"
for stage in \
	macos-export macos-thin-arm64 macos-runtime-payload macos-smoke \
	macos-smoke-log-scan macos-audio-smoke macos-audio-smoke-log-scan \
	macos-frame-pacing macos-frame-pacing-log-scan macos-frame-pacing-report \
	macos-metal-hud-parse macos-metal-hud-report \
	macos-framebuffer macos-framebuffer-log-scan macos-framebuffer-report \
	macos-codesign-verify \
	android-export android-archive-test android-runtime-payload android-signature-verify \
	android-readiness android-install android-launch android-main-loop android-survival \
	android-screenshot android-log-scan; do
	print -r -- "not-run" >"${REPORT_DIR}/${stage}.exit-code"
done

typeset -i overall=0
typeset -i emulator_started=0
typeset -i emulator_pid=0
typeset -i macos_export_ok=0
typeset -i android_export_ok=0
typeset -i android_smoke_ok=0
device_serial=""

cleanup_emulator() {
	if (( emulator_started == 1 )); then
		if [[ -n "$device_serial" ]]; then
			"$ADB" -s "$device_serial" emu kill >>"${REPORT_DIR}/android-emulator.log" 2>&1 || true
		elif (( emulator_pid > 0 )) && kill -0 "$emulator_pid" 2>/dev/null; then
			kill -TERM "$emulator_pid" 2>/dev/null || true
		fi
		if (( emulator_pid > 0 )); then
			wait "$emulator_pid" 2>/dev/null || true
		fi
		emulator_started=0
	fi
	return 0
}

finalize_runner() {
	local command_status=$?
	cleanup_emulator
	{
		print -r -- "finished_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		print -r -- "runner_exit=$command_status"
		if (( command_status == 0 )); then
			print -r -- "runner_status=complete"
		else
			print -r -- "runner_status=failed"
		fi
	} >>"${REPORT_DIR}/run-state.txt"
	return $command_status
}

trap finalize_runner EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

run_logged() {
	local label="$1"
	shift
	local log="${REPORT_DIR}/${label}.log"
	print -r -- "running" >"${REPORT_DIR}/${label}.exit-code"
	print -r -- "RUN $label: ${(q)@}" | tee "$log"
	"$@" >>"$log" 2>&1
	local code=$?
	print -r -- "EXIT $label: $code" | tee -a "$log"
	print -r -- "$code" >"${REPORT_DIR}/${label}.exit-code"
	if (( code != 0 )); then
		overall=1
	fi
	return $code
}

require_free_space() {
	local label="$1"
	local available_kib
	available_kib="$(df -k "$PROJECT_ROOT" | awk 'NR==2 {print $4}')"
	print -r -- "${label}_free_kib=${available_kib}" >>"${REPORT_DIR}/free-space-checks.txt"
	if (( available_kib < MIN_FREE_KIB )); then
		print -u2 -r -- \
			"Espaço insuficiente antes de ${label}: ${available_kib} KiB livres; mínimo ${MIN_FREE_KIB} KiB"
		return 1
	fi
	return 0
}

scan_runtime_log() {
	local log="$1"
	local findings="$2"
	if rg -n \
		"SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Cannot open file|Could not resolve resource|Invalid call|ObjectDB.*[Ll]eak|[Ll]eak.*ObjectDB" \
		"$log" >"$findings"; then
		return 1
	fi
	print -r -- "no script, resource, parse, invalid-call, or ObjectDB leak errors found" >"$findings"
	return 0
}

run_macos_audio_smoke() {
	local executable="$1"
	local evidence="$2"
	local runtime_log="$3"
	local started_at_utc
	local finished_at_utc
	local started_epoch
	local finished_epoch
	local smoke_exit
	local completion_marker_count
	local completion_line
	local completed_physics_ticks
	local runtime_requested_ticks
	local runtime_physics_ticks_per_second
	local evidence_outcome="failed"
	local coherence_error=""
	local watchdog_timeout_seconds="$MACOS_AUDIO_SMOKE_TIMEOUT_SECONDS"
	local watchdog_timed_out="false"
	local watchdog_termination_signal="none"
	local watchdog_configuration_error=""
	local smoke_pid=0
	local watchdog_deadline_epoch=0
	local watchdog_grace_deadline_epoch=0
	local current_epoch=0
	local requested_physics_ticks=900
	local physics_ticks_per_second=60
	local nominal_runtime_seconds=$((requested_physics_ticks / physics_ticks_per_second))
	started_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	started_epoch="$(date +%s)"
	if [[ "$watchdog_timeout_seconds" != <-> ]] || (( watchdog_timeout_seconds <= 0 )); then
		watchdog_configuration_error="invalid_watchdog_timeout"
		smoke_exit=2
	else
		"$executable" -- --shipping-audio-smoke-ticks=900 &
		smoke_pid=$!
		watchdog_deadline_epoch=$((started_epoch + watchdog_timeout_seconds))
		while kill -0 "$smoke_pid" 2>/dev/null; do
			current_epoch="$(date +%s)"
			if (( current_epoch >= watchdog_deadline_epoch )); then
				watchdog_timed_out="true"
				watchdog_termination_signal="TERM"
				kill -TERM "$smoke_pid" 2>/dev/null || true
				watchdog_grace_deadline_epoch=$((current_epoch + 2))
				while kill -0 "$smoke_pid" 2>/dev/null; do
					current_epoch="$(date +%s)"
					(( current_epoch >= watchdog_grace_deadline_epoch )) && break
					sleep 0.1
				done
				if kill -0 "$smoke_pid" 2>/dev/null; then
					watchdog_termination_signal="KILL"
					kill -KILL "$smoke_pid" 2>/dev/null || true
				fi
				break
			fi
			sleep 0.1
		done
		wait "$smoke_pid" 2>/dev/null
		smoke_exit=$?
		smoke_pid=0
	fi
	finished_epoch="$(date +%s)"
	finished_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	completion_marker_count="$(rg -c \
		"QIX_SHIPPING_AUDIO_SMOKE_COMPLETE requested_ticks=" \
		"$runtime_log" 2>/dev/null || true)"
	completion_marker_count="${completion_marker_count:-0}"
	completion_line="$(rg \
		"QIX_SHIPPING_AUDIO_SMOKE_COMPLETE requested_ticks=" \
		"$runtime_log" 2>/dev/null | tail -n 1 || true)"
	runtime_requested_ticks="$(print -r -- "$completion_line" | awk '{for (i = 1; i <= NF; i++) {split($i, value, "="); if (value[1] == "requested_ticks") {print value[2]; exit}}}')"
	completed_physics_ticks="$(print -r -- "$completion_line" | awk '{for (i = 1; i <= NF; i++) {split($i, value, "="); if (value[1] == "completed_ticks") {print value[2]; exit}}}')"
	runtime_physics_ticks_per_second="$(print -r -- "$completion_line" | awk '{for (i = 1; i <= NF; i++) {split($i, value, "="); if (value[1] == "physics_ticks_per_second") {print value[2]; exit}}}')"

	if [[ -n "$watchdog_configuration_error" ]]; then
		coherence_error="$watchdog_configuration_error"
	elif [[ "$watchdog_timed_out" == "true" ]]; then
		evidence_outcome="timed_out"
		coherence_error="runtime_timeout"
	elif (( smoke_exit != 0 )); then
		coherence_error="runtime_exit_nonzero"
	elif [[ "$completion_marker_count" != <-> ]] || (( completion_marker_count != 1 )); then
		coherence_error="runtime_completion_marker_count"
	elif [[ "$runtime_requested_ticks" != <-> \
			|| "$completed_physics_ticks" != <-> \
			|| "$runtime_physics_ticks_per_second" != <-> ]]; then
		coherence_error="runtime_completion_marker_fields"
	elif (( runtime_requested_ticks != requested_physics_ticks )); then
		coherence_error="runtime_requested_ticks_mismatch"
	elif (( completed_physics_ticks != requested_physics_ticks )); then
		coherence_error="runtime_completed_ticks_mismatch"
	elif (( runtime_physics_ticks_per_second != physics_ticks_per_second )); then
		coherence_error="runtime_physics_rate_mismatch"
	elif (( finished_epoch - started_epoch < nominal_runtime_seconds - 1 )); then
		coherence_error="elapsed_wall_time_too_short"
	else
		evidence_outcome="passed"
	fi
	{
		print -r -- "schema=qix.shipping.macos-audio-smoke.v2"
		print -r -- "started_at_utc=$started_at_utc"
		print -r -- "finished_at_utc=$finished_at_utc"
		print -r -- "requested_physics_ticks=$requested_physics_ticks"
		print -r -- "completed_physics_ticks=${completed_physics_ticks:-unavailable}"
		print -r -- "physics_ticks_per_second=${runtime_physics_ticks_per_second:-unavailable}"
		print -r -- "nominal_runtime_seconds=$nominal_runtime_seconds"
		print -r -- "elapsed_wall_seconds=$((finished_epoch - started_epoch))"
		print -r -- "runtime_completion_markers=$completion_marker_count"
		print -r -- "watchdog_timeout_seconds=$watchdog_timeout_seconds"
		print -r -- "watchdog_timed_out=$watchdog_timed_out"
		print -r -- "watchdog_termination_signal=$watchdog_termination_signal"
		print -r -- "headless=false"
		print -r -- "audio_driver=runtime-default"
		print -r -- "exit_code=$smoke_exit"
		print -r -- "outcome=$evidence_outcome"
		print -r -- "coherence_error=${coherence_error:-none}"
	} >"$evidence"
	if [[ "$evidence_outcome" != "passed" ]]; then
		print -u2 -r -- "Smoke de áudio incoerente: ${coherence_error}; veja $evidence"
		return 1
	fi
	return 0
}

android_serial_is_safe() {
	local serial="$1"
	[[ -n "$serial" && "$serial" == [[:alnum:]]* \
		&& "$serial" != *[^[:alnum:].:_-]* ]]
}

android_serial_is_emulator() {
	local serial="$1"
	[[ "$serial" == emulator-<-> ]]
}

android_device_state() {
	local serial="$1"
	"$ADB" devices | awk -v target="$serial" '$1 == target {print $2; exit}'
}

android_online_emulators() {
	"$ADB" devices | awk 'NR > 1 && $1 ~ /^emulator-[0-9]+$/ && $2 == "device" {print $1}'
}

android_emulator_port_is_free() {
	local port="$1"
	local serial="emulator-${port}"
	if "$ADB" devices | awk -v target="$serial" '$1 == target {found=1} END {exit !found}'; then
		return 1
	fi
	if command -v lsof >/dev/null 2>&1; then
		if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 \
			|| lsof -nP -iTCP:"$((port + 1))" -sTCP:LISTEN >/dev/null 2>&1; then
			return 1
		fi
	fi
	return 0
}

android_select_emulator_port() {
	local requested="$ANDROID_EMULATOR_PORT_OVERRIDE"
	local candidate
	if [[ -n "$requested" ]]; then
		if [[ "$requested" != <-> ]] \
			|| (( requested < 5554 || requested > 5682 || requested % 2 != 0 )); then
			print -u2 -r -- \
				"QIX_ANDROID_EMULATOR_PORT deve ser um número par entre 5554 e 5682"
			return 1
		fi
		if ! android_emulator_port_is_free "$requested"; then
			print -u2 -r -- "Porta de emulator indisponível: $requested"
			return 1
		fi
		print -r -- "$requested"
		return 0
	fi
	for candidate in {5554..5682..2}; do
		if android_emulator_port_is_free "$candidate"; then
			print -r -- "$candidate"
			return 0
		fi
	done
	print -u2 -r -- "Nenhuma porta livre para emulator entre 5554 e 5682"
	return 1
}

android_wait_until_ready() {
	local serial="$1"
	local streak=0
	local attempt=0
	local sys_boot=""
	local dev_boot=""
	local user_ce=""
	local package_service=""
	while (( attempt < 120 )); do
		attempt=$((attempt + 1))
		sys_boot="$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
		dev_boot="$("$ADB" -s "$serial" shell getprop dev.bootcomplete 2>/dev/null | tr -d '\r')"
		user_ce="$("$ADB" -s "$serial" shell getprop sys.user.0.ce_available 2>/dev/null | tr -d '\r')"
		package_service="$("$ADB" -s "$serial" shell service check package 2>/dev/null | tr -d '\r')"
		if [[ "$sys_boot" == "1" && "$dev_boot" == "1" && "$user_ce" == "true" \
			&& "$package_service" == *"found"* ]]; then
			streak=$((streak + 1))
		else
			streak=0
		fi
		print -r -- \
			"attempt=$attempt sys_boot=${sys_boot:-unset} dev_boot=${dev_boot:-unset} user_ce=${user_ce:-unset} package_service=${package_service:-unset} stable=$streak/$ANDROID_READY_STREAK"
		if (( streak >= ANDROID_READY_STREAK )); then
			"$ADB" -s "$serial" shell cmd package wait-for-handler --timeout 60000
			"$ADB" -s "$serial" shell pm path android >/dev/null
			return $?
		fi
		sleep 2
	done
	return 1
}

android_wait_for_main_loop() {
	local serial="$1"
	local attempt=0
	local process_seen=0
	local process_id=""
	while (( attempt < ANDROID_MAIN_LOOP_TIMEOUT )); do
		process_id="$("$ADB" -s "$serial" shell pidof "$PACKAGE_ID" 2>/dev/null | tr -d '\r')"
		if [[ -n "$process_id" ]]; then
			process_seen=1
		elif (( process_seen == 1 )); then
			print -u2 -r -- "Processo Android encerrou antes da main loop"
			return 1
		fi
		if "$ADB" -s "$serial" logcat -d -v brief 2>/dev/null | rg -q "OnGodotMainLoopStarted"; then
			print -r -- "OnGodotMainLoopStarted após ${attempt}s pid=${process_id:-desconhecido}"
			return 0
		fi
		if (( process_seen == 0 && attempt >= ANDROID_PROCESS_START_TIMEOUT )); then
			print -u2 -r -- \
				"Processo Android não iniciou após ${ANDROID_PROCESS_START_TIMEOUT}s"
			return 1
		fi
		attempt=$((attempt + 1))
		sleep 1
	done
	print -u2 -r -- "OnGodotMainLoopStarted ausente após ${ANDROID_MAIN_LOOP_TIMEOUT}s"
	return 1
}

android_survive_after_main_loop() {
	local serial="$1"
	local elapsed=0
	while (( elapsed < ANDROID_SMOKE_SECONDS )); do
		sleep 1
		elapsed=$((elapsed + 1))
		if ! "$ADB" -s "$serial" shell pidof "$PACKAGE_ID" >/dev/null 2>&1; then
			print -u2 -r -- "Processo Android encerrou ${elapsed}s após a main loop"
			return 1
		fi
		if (( elapsed % 5 == 0 )); then
			print -r -- "Android vivo ${elapsed}/${ANDROID_SMOKE_SECONDS}s após a main loop"
		fi
	done
	return 0
}

capture_android_screenshot() {
	local serial="$1"
	local output="$2"
	"$ADB" -s "$serial" exec-out screencap -p >"$output" || return $?
	[[ -s "$output" ]] || return 1
	file "$output" | rg -q "PNG image data"
}

scan_android_runtime_log() {
	local log="$1"
	local findings="$2"
	local failed=0
	: >"$findings"
	# Tombstones de SIGSEGV/SIGBUS/SIGABRT incluem `>>> ${PACKAGE_ID} <<<` ou
	# `Cmdline: ${PACKAGE_ID}`. Esses marcadores também evitam atribuir ao jogo
	# crashes de serviços do AVD.
	if rg -n \
		"ANR in ${PACKAGE_ID}|Process: ${PACKAGE_ID}|Process ${PACKAGE_ID}.*has died|>>> ${PACKAGE_ID} <<<|Cmdline: ${PACKAGE_ID}" \
		"$log" >>"$findings"; then
		failed=1
	fi
	if rg -n \
		"SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Cannot open file|Could not resolve resource" \
		"$log" >>"$findings"; then
		failed=1
	fi
	if (( failed == 1 )); then
		return 1
	fi
	print -r -- "no package SIGSEGV, SIGBUS, SIGABRT, Java fatal, ANR, script, or resource errors found" \
		>"$findings"
	return 0
}

{
	print -r -- "captured_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	print -r -- "godot=$($GODOT_BIN --version 2>&1)"
	print -r -- "host=$(sw_vers -productVersion) $(uname -m)"
	print -r -- "free_kib=$(df -k "$PROJECT_ROOT" | awk 'NR==2 {print $4}')"
	print -r -- "templates=/Users/flaviocoutinho/Library/Application Support/Godot/export_templates/4.7.2.stable.mono"
	print -r -- "android_sdk=$ANDROID_SDK"
	print -r -- "jdk=$JDK_ROOT"
	print -r -- "editor_settings=$EDITOR_SETTINGS"
	print -r -- "macos_audio_smoke_timeout_seconds=$MACOS_AUDIO_SMOKE_TIMEOUT_SECONDS"
	print -r -- "android_avd=$AVD_NAME"
	print -r -- "android_emulator_gpu=$ANDROID_EMULATOR_GPU"
	print -r -- "android_emulator_cores=$ANDROID_EMULATOR_CORES"
	print -r -- "android_emulator_memory_mb=$ANDROID_EMULATOR_MEMORY_MB"
	print -r -- "android_process_start_timeout=$ANDROID_PROCESS_START_TIMEOUT"
	print -r -- "android_smoke_seconds=$ANDROID_SMOKE_SECONDS"
	print -r -- "android_device_serial_override=${ANDROID_DEVICE_SERIAL_OVERRIDE:-unset}"
	print -r -- "android_allow_physical_device=$ANDROID_ALLOW_PHYSICAL_DEVICE"
	print -r -- "android_emulator_port_override=${ANDROID_EMULATOR_PORT_OVERRIDE:-auto}"
} >"${REPORT_DIR}/environment.txt"

if [[ ! -x "$GODOT_BIN" ]]; then
	print -u2 -r -- "Godot ausente: $GODOT_BIN"
	exit 2
fi

if ! require_free_space "macos-export"; then
	print -r -- "2" >"${REPORT_DIR}/free-space-gate.exit-code"
	exit 2
fi

if run_logged macos-export "$GODOT_BIN" --headless --path "$PROJECT_ROOT" \
	--export-debug "macOS Shipping QA" "$MAC_APP"; then
	macos_export_ok=1
fi

if (( macos_export_ok == 1 )) && [[ -x "$MAC_EXECUTABLE" ]]; then
	if run_logged macos-thin-arm64 "$MAC_THINNER" "$MAC_APP"; then
		run_logged macos-runtime-payload "$PAYLOAD_VERIFIER" macos "$MAC_APP"
		run_logged macos-smoke "$MAC_EXECUTABLE" \
			--headless --audio-driver Dummy --quit-after 180
		run_logged macos-smoke-log-scan scan_runtime_log \
			"${REPORT_DIR}/macos-smoke.log" "${REPORT_DIR}/macos-smoke-findings.txt"
		run_logged macos-audio-smoke run_macos_audio_smoke \
			"$MAC_EXECUTABLE" "${REPORT_DIR}/macos-audio-smoke-evidence.txt" \
			"${REPORT_DIR}/macos-audio-smoke.log"
		run_logged macos-audio-smoke-log-scan scan_runtime_log \
			"${REPORT_DIR}/macos-audio-smoke.log" \
			"${REPORT_DIR}/macos-audio-smoke-findings.txt"
		: >"$MAC_FRAME_REPORT"
		: >"$MAC_METAL_HUD_REPORT"
		run_logged macos-frame-pacing /usr/bin/env \
			MTL_HUD_ENABLED=1 \
			MTL_HUD_LOG_ENABLED=1 \
			MTL_HUD_ENCODER_TIMING_ENABLED=1 \
			MTL_HUD_SHOW_ZERO_METRICS=1 \
			"$MAC_EXECUTABLE" \
			--audio-driver Dummy --rendering-method mobile \
			-- \
			--shipping-probe=frame-pacing \
			--output="$MAC_FRAME_REPORT" \
			--warmup-frames=120 --sample-frames=600 \
			--external-gpu=metal-hud
		run_logged macos-frame-pacing-log-scan scan_runtime_log \
			"${REPORT_DIR}/macos-frame-pacing.log" \
			"${REPORT_DIR}/macos-frame-pacing-findings.txt"
		if run_logged macos-frame-pacing-report "$PROBE_REPORT_VALIDATOR" \
			frame-pacing-external "$MAC_FRAME_REPORT"; then
			if [[ -f "$METAL_HUD_PARSER" ]]; then
				run_logged macos-metal-hud-parse /usr/bin/python3 \
					"$METAL_HUD_PARSER" \
					--input "${REPORT_DIR}/macos-frame-pacing.log" \
					--output "$MAC_METAL_HUD_REPORT"
				run_logged macos-metal-hud-report "$PROBE_REPORT_VALIDATOR" \
					metal-hud "$MAC_METAL_HUD_REPORT"
			else
				print -u2 -r -- "Parser Metal HUD ausente: $METAL_HUD_PARSER"
				print -r -- "1" >"${REPORT_DIR}/macos-metal-hud-parse.exit-code"
				overall=1
			fi
		fi
		: >"$MAC_FRAMEBUFFER_REPORT"
		: >"$MAC_FRAMEBUFFER_IMAGE"
		run_logged macos-framebuffer "$MAC_EXECUTABLE" \
			--audio-driver Dummy -- \
			--shipping-probe=framebuffer \
			--report="$MAC_FRAMEBUFFER_REPORT" \
			--image="$MAC_FRAMEBUFFER_IMAGE"
		run_logged macos-framebuffer-log-scan scan_runtime_log \
			"${REPORT_DIR}/macos-framebuffer.log" \
			"${REPORT_DIR}/macos-framebuffer-findings.txt"
		run_logged macos-framebuffer-report "$PROBE_REPORT_VALIDATOR" \
			framebuffer "$MAC_FRAMEBUFFER_REPORT"
		if command -v codesign >/dev/null 2>&1; then
			run_logged macos-codesign-verify codesign --verify --deep --strict --verbose=2 "$MAC_APP"
		fi
	fi
else
	print -u2 -r -- "Bundle macOS não contém executável: $MAC_EXECUTABLE"
	overall=1
fi

if require_free_space "android-export"; then
	if run_logged android-export "$ANDROID_JDK_WRAPPER" \
		"$EDITOR_SETTINGS" "$JDK_ROOT" "$REPORT_DIR" -- \
		"$GODOT_BIN" --headless --path "$PROJECT_ROOT" \
		--export-debug "Android Shipping QA" "$APK"; then
		android_export_ok=1
	fi
else
	print -r -- "2" >"${REPORT_DIR}/android-free-space-gate.exit-code"
	overall=1
fi

if (( android_export_ok == 1 )) && [[ -f "$APK" ]]; then
	run_logged android-archive-test /usr/bin/unzip -t "$APK"
	run_logged android-runtime-payload "$PAYLOAD_VERIFIER" android "$APK"
	if [[ -x "${ANDROID_SDK}/build-tools/36.0.0/apksigner" ]]; then
		run_logged android-signature-verify \
			"${ANDROID_SDK}/build-tools/36.0.0/apksigner" verify --verbose "$APK"
	fi
else
	print -u2 -r -- "APK não foi produzido: $APK"
	overall=1
fi

if [[ -x "$ADB" && -f "$APK" ]] && (( android_export_ok == 1 )); then
	"$ADB" start-server >>"${REPORT_DIR}/android-adb.log" 2>&1
	typeset -i smoke_prereq_ok=1
	typeset -i should_start_emulator=0
	device_selection_source=""
	{
		print -r -- "schema=qix.shipping.android-device-selection.v1"
		print -r -- "captured_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		print -r -- "requested_serial=${ANDROID_DEVICE_SERIAL_OVERRIDE:-unset}"
		print -r -- "physical_device_double_opt_in=$ANDROID_ALLOW_PHYSICAL_DEVICE"
	} >"${REPORT_DIR}/android-device-selection.txt"

	if [[ "$ANDROID_ALLOW_PHYSICAL_DEVICE" != "0" \
		&& "$ANDROID_ALLOW_PHYSICAL_DEVICE" != "1" ]]; then
		print -u2 -r -- "QIX_ANDROID_ALLOW_PHYSICAL_DEVICE deve ser 0 ou 1"
		print -r -- "refused=invalid-physical-device-opt-in" \
			>>"${REPORT_DIR}/android-device-selection.txt"
		smoke_prereq_ok=0
		overall=1
	elif [[ -n "$ANDROID_DEVICE_SERIAL_OVERRIDE" ]]; then
		if ! android_serial_is_safe "$ANDROID_DEVICE_SERIAL_OVERRIDE"; then
			print -u2 -r -- "Serial Android contém caracteres inválidos"
			print -r -- "refused=invalid-explicit-serial" \
				>>"${REPORT_DIR}/android-device-selection.txt"
			smoke_prereq_ok=0
			overall=1
		elif ! android_serial_is_emulator "$ANDROID_DEVICE_SERIAL_OVERRIDE" \
			&& [[ "$ANDROID_ALLOW_PHYSICAL_DEVICE" != "1" ]]; then
			print -u2 -r -- \
				"Device físico recusado; exija serial nominal e QIX_ANDROID_ALLOW_PHYSICAL_DEVICE=1"
			print -r -- "refused=physical-device-without-double-opt-in" \
				>>"${REPORT_DIR}/android-device-selection.txt"
			smoke_prereq_ok=0
			overall=1
		elif [[ "$(android_device_state "$ANDROID_DEVICE_SERIAL_OVERRIDE")" != "device" ]]; then
			print -u2 -r -- "Device Android explícito não está online: $ANDROID_DEVICE_SERIAL_OVERRIDE"
			print -r -- "refused=explicit-device-not-online" \
				>>"${REPORT_DIR}/android-device-selection.txt"
			smoke_prereq_ok=0
			overall=1
		else
			device_serial="$ANDROID_DEVICE_SERIAL_OVERRIDE"
			device_selection_source="explicit-serial"
		fi
	else
		online_emulators="$(android_online_emulators)"
		online_emulator_count="$(print -r -- "$online_emulators" | awk 'NF {count++} END {print count + 0}')"
		if (( online_emulator_count == 1 )); then
			device_serial="$(print -r -- "$online_emulators" | awk 'NF {print; exit}')"
			device_selection_source="sole-online-emulator"
		elif (( online_emulator_count > 1 )); then
			print -u2 -r -- \
				"Mais de um emulator online; defina QIX_ANDROID_DEVICE_SERIAL explicitamente"
			print -r -- "refused=ambiguous-online-emulators" \
				>>"${REPORT_DIR}/android-device-selection.txt"
			smoke_prereq_ok=0
			overall=1
		else
			should_start_emulator=1
		fi
	fi

	if (( smoke_prereq_ok == 1 && should_start_emulator == 1 )); then
		if [[ ! -x "$EMULATOR" ]]; then
			print -u2 -r -- "Emulator Android ausente: $EMULATOR"
			print -r -- "refused=emulator-binary-unavailable" \
				>>"${REPORT_DIR}/android-device-selection.txt"
			overall=1
			smoke_prereq_ok=0
		fi
	fi

	if (( smoke_prereq_ok == 1 && should_start_emulator == 1 )); then
		available_kib="$(df -k "$PROJECT_ROOT" | awk 'NR==2 {print $4}')"
		print -r -- "android-emulator_free_kib=${available_kib}" \
			>>"${REPORT_DIR}/free-space-checks.txt"
		if (( available_kib < ANDROID_EMULATOR_MIN_FREE_KIB )); then
			print -u2 -r -- \
				"Espaço insuficiente para AVD: ${available_kib} KiB livres; mínimo ${ANDROID_EMULATOR_MIN_FREE_KIB} KiB"
			print -r -- "2" >"${REPORT_DIR}/android-readiness.exit-code"
			overall=1
			smoke_prereq_ok=0
		else
			emulator_port="$(android_select_emulator_port)"
			if [[ -z "$emulator_port" ]]; then
				print -r -- "refused=no-safe-emulator-port" \
					>>"${REPORT_DIR}/android-device-selection.txt"
				overall=1
				smoke_prereq_ok=0
			else
				device_serial="emulator-${emulator_port}"
				device_selection_source="runner-started-emulator"
				"$EMULATOR" -avd "$AVD_NAME" -port "$emulator_port" \
					-no-window -no-audio -no-boot-anim -no-snapshot-save \
					-gpu "$ANDROID_EMULATOR_GPU" -cores "$ANDROID_EMULATOR_CORES" \
					-memory "$ANDROID_EMULATOR_MEMORY_MB" \
					>"${REPORT_DIR}/android-emulator.log" 2>&1 &
				emulator_pid=$!
				emulator_started=1
			fi
		fi
	fi

	if (( smoke_prereq_ok == 1 )); then
		for _attempt in {1..90}; do
			[[ "$(android_device_state "$device_serial")" == "device" ]] && break
			sleep 2
		done
		{
			print -r -- "selected_serial=$device_serial"
			print -r -- "selection_source=$device_selection_source"
			print -r -- "is_emulator=$(android_serial_is_emulator "$device_serial" && print true || print false)"
			print -r -- "physical_device_double_opt_in=$ANDROID_ALLOW_PHYSICAL_DEVICE"
			print -r -- "state=$(android_device_state "$device_serial")"
		} >>"${REPORT_DIR}/android-device-selection.txt"
		if [[ "$(android_device_state "$device_serial")" != "device" ]] \
			|| ! run_logged android-readiness \
			android_wait_until_ready "$device_serial"; then
			smoke_prereq_ok=0
			overall=1
		fi
	fi

	typeset -i installed=0
	typeset -i launched=0
	typeset -i main_loop_started=0
	typeset -i survived=0
	typeset -i screenshot_ok=0
	typeset -i log_scan_ok=0
	if (( smoke_prereq_ok == 1 )); then
		# Evita que o diálogo do sistema sobre immersive mode cubra a captura do jogo.
		"$ADB" -s "$device_serial" shell settings put secure immersive_mode_confirmations confirmed \
			>/dev/null 2>&1 || true
		"$ADB" -s "$device_serial" logcat -c
		if run_logged android-install "$ADB" -s "$device_serial" \
			install --no-streaming --no-incremental -r "$APK"; then
			installed=1
		fi
		if (( installed == 1 )) && run_logged android-launch \
			"$ADB" -s "$device_serial" shell monkey -p "$PACKAGE_ID" \
			-c android.intent.category.LAUNCHER 1; then
			launched=1
		fi
		if (( launched == 1 )); then
			if run_logged android-main-loop android_wait_for_main_loop "$device_serial"; then
				main_loop_started=1
			fi
			if (( main_loop_started == 1 )) && run_logged android-survival \
				android_survive_after_main_loop "$device_serial"; then
				survived=1
			fi
			if (( survived == 1 )) && run_logged android-screenshot \
				capture_android_screenshot "$device_serial" "${REPORT_DIR}/android-smoke.png"; then
				screenshot_ok=1
			fi
			"$ADB" -s "$device_serial" logcat -d -v threadtime \
				>"${REPORT_DIR}/android-logcat.txt"
			if run_logged android-log-scan scan_android_runtime_log \
				"${REPORT_DIR}/android-logcat.txt" "${REPORT_DIR}/android-runtime-scan.txt"; then
				log_scan_ok=1
			fi
			cp "${REPORT_DIR}/android-runtime-scan.txt" "${REPORT_DIR}/android-fatal-scan.txt"
			"$ADB" -s "$device_serial" shell am force-stop "$PACKAGE_ID" >/dev/null 2>&1 || true
		fi
		if (( installed == 1 && launched == 1 && main_loop_started == 1 \
			&& survived == 1 && screenshot_ok == 1 && log_scan_ok == 1 )); then
			android_smoke_ok=1
		else
			overall=1
		fi
	fi

	if (( emulator_started == 1 )); then
		cleanup_emulator
	fi
else
	print -r -- "Android smoke não disponível: verifique APK e adb" \
		>"${REPORT_DIR}/android-smoke-skipped.txt"
	overall=1
fi

{
	print -r -- "overall_exit=$overall"
	print -r -- "macos_export_ok=$macos_export_ok"
	print -r -- "android_export_ok=$android_export_ok"
	print -r -- "android_smoke_ok=$android_smoke_ok"
	if (( macos_export_ok == 1 )) && [[ -d "$MAC_APP" ]]; then
		print -r -- "macos_bundle_bytes=$(du -sk "$MAC_APP" | awk '{print $1 * 1024}')"
	fi
	if (( macos_export_ok == 1 )) && [[ -x "$MAC_EXECUTABLE" ]]; then
		print -r -- "macos_archs=$(/usr/bin/lipo -archs "$MAC_EXECUTABLE")"
	fi
	if (( android_export_ok == 1 )) && [[ -f "$APK" ]]; then
		print -r -- "android_apk_bytes=$(stat -f %z "$APK")"
		print -r -- "android_apk_sha256=$(shasum -a 256 "$APK" | awk '{print $1}')"
	fi
} >"${REPORT_DIR}/result.txt"

exit $overall
