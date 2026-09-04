#!/bin/zsh
# Confirma que o pacote contém o fechamento dos autoloads e não leva o binário editor-only.
set -eu

if (( $# != 2 )); then
	print -u2 -r -- "uso: ${0:t} android|macos ARTEFATO"
	exit 2
fi

platform="$1"
artifact="$2"
listing="$(mktemp -t qix-shipping-payload.XXXXXX)"
cleanup() {
	[[ -e "$listing" ]] && rm -f -- "$listing"
}
trap cleanup EXIT INT TERM HUP

case "$platform" in
	android)
		if [[ ! -f "$artifact" ]]; then
			print -u2 -r -- "APK ausente: $artifact"
			exit 2
		fi
		/usr/bin/unzip -Z1 "$artifact" >"$listing"
		;;
	macos)
		if [[ ! -d "$artifact" ]]; then
			print -u2 -r -- "bundle ausente: $artifact"
			exit 2
		fi
		pcks=("$artifact"/Contents/Resources/*.pck(N))
		if (( ${#pcks} != 1 )); then
			print -u2 -r -- "esperava um PCK no bundle; encontrados: ${#pcks}"
			exit 2
		fi
		/usr/bin/strings "${pcks[1]}" >"$listing"
		;;
	*)
		print -u2 -r -- "plataforma não suportada: $platform"
		exit 2
		;;
esac

fennara_scripts=(
	"addons/fennara/runtime/game_capture_helper.gdc"
	"addons/fennara/runtime/runtime_capture_store.gdc"
	"addons/fennara/runtime/runtime_check_runner.gdc"
	"addons/fennara/runtime/runtime_script_context.gdc"
	"addons/fennara/runtime/runtime_input_driver.gdc"
	"addons/fennara/runtime/image_sheet.gdc"
	"addons/fennara/runtime/image_label.gdc"
	"addons/fennara/runtime/runtime_node_snapshot.gdc"
	"addons/fennara/runtime/runtime_physics_query.gdc"
	"addons/fennara/runtime/runtime_query_utils.gdc"
)

godot_ai_scripts=(
	"addons/godot_ai/runtime/game_helper.gdc"
	"addons/godot_ai/runtime/game_logger.gdc"
	"addons/godot_ai/utils/error_codes.gdc"
	"addons/godot_ai/utils/screenshot_encode.gdc"
	"addons/godot_ai/utils/log_backtrace.gdc"
)

missing=0
fennara_present=0
for script_path in "${fennara_scripts[@]}"; do
	if rg -F -q -- "$script_path" "$listing"; then
		print -r -- "present=$script_path"
		(( fennara_present += 1 ))
	else
		print -r -- "absent=$script_path"
	fi
done

if (( fennara_present == 0 )); then
	# A GDExtension Fennara registrada no editor remove seu autoload e runtime
	# do artefato. O smoke-log scan subsequente prova que não restou referência
	# quebrada; este teste impede apenas um fechamento parcialmente empacotado.
	print -r -- "fennara_payload_mode=export_hook_stripped"
elif (( fennara_present == ${#fennara_scripts} )); then
	print -r -- "fennara_payload_mode=complete_runtime_closure"
else
	print -u2 -r -- \
		"fennara_payload_mode=partial_runtime_closure (${fennara_present}/${#fennara_scripts})"
	missing=1
fi

for script_path in "${godot_ai_scripts[@]}"; do
	if rg -F -q -- "$script_path" "$listing"; then
		print -r -- "present=$script_path"
	else
		print -u2 -r -- "missing=$script_path"
		missing=1
	fi
done

if rg -F -q -- "addons/fennara/bin/" "$listing"; then
	print -u2 -r -- "forbidden=addons/fennara/bin/"
	missing=1
else
	print -r -- "absent=addons/fennara/bin/"
fi

exit $missing
