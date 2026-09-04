#!/bin/zsh
# Valida estrutura e outcome dos JSONs de profiling; exit code isolado não basta.
set -u

if (( $# != 2 )); then
	print -u2 -r -- \
		"uso: ${0:t} frame-pacing|frame-pacing-external|metal-hud|framebuffer RELATORIO.json"
	exit 2
fi

kind="$1"
report="$2"

if [[ ! -s "$report" ]]; then
	print -u2 -r -- "relatório ausente ou vazio: $report"
	exit 1
fi
if ! /usr/bin/plutil -convert json -o /dev/null "$report" >/dev/null 2>&1; then
	print -u2 -r -- "JSON inválido: $report"
	exit 1
fi

raw_value() {
	local key="$1"
	local expected_type="$2"
	/usr/bin/plutil -extract "$key" raw -expect "$expected_type" "$report" 2>/dev/null
}

expect_true() {
	local key="$1"
	local value
	value="$(raw_value "$key" bool)" || {
		print -u2 -r -- "campo booleano ausente/inválido: $key"
		return 1
	}
	if [[ "$value" != "true" ]]; then
		print -u2 -r -- "gate falso: $key=$value"
		return 1
	fi
	print -r -- "$key=true"
	return 0
}

expect_false() {
	local key="$1"
	local value
	value="$(raw_value "$key" bool)" || {
		print -u2 -r -- "campo booleano ausente/inválido: $key"
		return 1
	}
	if [[ "$value" != "false" ]]; then
		print -u2 -r -- "gate deveria ser falso: $key=$value"
		return 1
	fi
	print -r -- "$key=false"
	return 0
}

expect_string() {
	local key="$1"
	local expected="$2"
	local value
	value="$(raw_value "$key" string)" || {
		print -u2 -r -- "campo string ausente/inválido: $key"
		return 1
	}
	if [[ "$value" != "$expected" ]]; then
		print -u2 -r -- "valor inesperado: $key=${value:-ausente}; esperado=$expected"
		return 1
	fi
	print -r -- "$key=$value"
	return 0
}

expect_empty_array() {
	local key="$1"
	local value
	value="$(
		/usr/bin/plutil -extract "$key" json -o - "$report" 2>/dev/null \
			| tr -d '[:space:]'
	)" || value=""
	if [[ "$value" != "[]" ]]; then
		print -u2 -r -- "$key não está vazio: ${value:-ausente}"
		return 1
	fi
	print -r -- "$key=[]"
	return 0
}

validate_frame_sample_count() {
	local sample_frames sample_count
	sample_frames="$(raw_value sample_frames integer)" || sample_frames=""
	sample_count="$(raw_value frame_intervals.sample_count integer)" || sample_count=""
	if [[ -z "$sample_frames" || -z "$sample_count" || "$sample_count" != "$sample_frames" ]]; then
		print -u2 -r -- \
			"amostragem incompleta: sample_count=${sample_count:-ausente} sample_frames=${sample_frames:-ausente}"
		return 1
	fi
	print -r -- "sample_count=$sample_count"
	return 0
}

failures=0
case "$kind" in
	frame-pacing)
		expect_string schema "qix.shipping.frame-pacing.v1" || failures=1
		expect_string outcome passed || failures=1
		for key in \
			passed frame_pacing_passed gameplay_active_at_finish \
			render_gpu_measurement_available \
			checks.enough_samples checks.gameplay_active checks.gpu_measurement_available \
			checks.frame_p95_within_25ms checks.frame_p99_within_40ms checks.no_150ms_stall; do
			expect_true "$key" || failures=1
		done
		validate_frame_sample_count || failures=1
		;;
	frame-pacing-external)
		expect_string schema "qix.shipping.frame-pacing.v1" || failures=1
		expect_string outcome external_gpu_pending || failures=1
		expect_string external_gpu_source metal-hud || failures=1
		expect_string renderer.method mobile || failures=1
		for key in \
			frame_pacing_passed gameplay_active_at_finish external_gpu_report_required \
			checks.enough_samples checks.gameplay_active \
			checks.frame_p95_within_25ms checks.frame_p99_within_40ms checks.no_150ms_stall; do
			expect_true "$key" || failures=1
		done
		for key in passed render_gpu_measurement_available checks.gpu_measurement_available; do
			expect_false "$key" || failures=1
		done
		validate_frame_sample_count || failures=1
		;;
	metal-hud)
		expect_string schema "qix.shipping.metal-hud.v1" || failures=1
		expect_string outcome passed || failures=1
		expect_string source "Apple Metal Performance HUD console log" || failures=1
		expect_string unit milliseconds || failures=1
		expect_true passed || failures=1
		for key in \
			checks.metal_hud_lines_present checks.minimum_valid_pairs \
			checks.nonzero_gpu_signal checks.gpu_p95_within_budget \
			checks.gpu_max_within_budget checks.frame_interval_p95_within_budget \
			checks.frame_interval_p99_within_budget checks.frame_interval_max_within_budget; do
			expect_true "$key" || failures=1
		done
		expect_empty_array failed_checks || failures=1
		valid_pairs="$(raw_value parsing.valid_pairs integer)" || valid_pairs=""
		minimum_pairs="$(raw_value requirements.minimum_valid_pairs integer)" || minimum_pairs=""
		frame_samples="$(raw_value frame_interval_ms.sample_count integer)" || frame_samples=""
		gpu_samples="$(raw_value gpu_time_ms.sample_count integer)" || gpu_samples=""
		if [[ -z "$valid_pairs" || -z "$minimum_pairs" || -z "$frame_samples" || -z "$gpu_samples" ]] \
			|| (( valid_pairs < minimum_pairs )) \
			|| [[ "$frame_samples" != "$valid_pairs" || "$gpu_samples" != "$valid_pairs" ]]; then
			print -u2 -r -- \
				"pares Metal HUD inválidos: valid=${valid_pairs:-ausente} minimum=${minimum_pairs:-ausente} frame=${frame_samples:-ausente} gpu=${gpu_samples:-ausente}"
			failures=1
		else
			print -r -- "metal_hud_valid_pairs=$valid_pairs"
		fi
		;;
	framebuffer)
		expect_string schema "qix.shipping.framebuffer.v1" || failures=1
		for key in \
			passed final_board_composition.passed final_board_composition.mask_matches_board; do
			expect_true "$key" || failures=1
		done
		expect_empty_array failed_assertions || failures=1
		expect_empty_array final_board_composition.failed_assertions || failures=1
		image_path="$(raw_value image_path string)" || image_path=""
		if [[ -z "$image_path" || ! -s "$image_path" ]]; then
			print -u2 -r -- "PNG de readback ausente ou vazio: ${image_path:-ausente}"
			failures=1
		else
			png_signature="$(/usr/bin/od -An -tx1 -N8 "$image_path" | tr -d '[:space:]')"
			if [[ "$png_signature" != "89504e470d0a1a0a" ]]; then
				print -u2 -r -- "readback não possui assinatura PNG: $image_path"
				failures=1
			else
				print -r -- "image_path=$image_path"
			fi
		fi
		;;
	*)
		print -u2 -r -- "tipo de relatório não suportado: $kind"
		exit 2
		;;
esac

exit $failures
