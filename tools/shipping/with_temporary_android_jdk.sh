#!/bin/zsh
# Executa um export Android com java_sdk_path temporário e restaura EditorSettings byte a byte.
set -u

if (( $# < 5 )) || [[ "$4" != "--" ]]; then
	print -u2 -r -- \
		"uso: ${0:t} EDITOR_SETTINGS JDK_ROOT REPORT_DIR -- COMANDO [ARGUMENTOS...]"
	exit 2
fi

settings_file="$1"
jdk_root="$2"
report_dir="$3"
shift 4

if [[ "$settings_file" != /* || ! -f "$settings_file" ]]; then
	print -u2 -r -- "EditorSettings absoluto e existente é obrigatório: $settings_file"
	exit 2
fi
if [[ "$jdk_root" != /* || ! -x "$jdk_root/bin/java" ]]; then
	print -u2 -r -- "JDK absoluto e válido é obrigatório: $jdk_root"
	exit 2
fi
if [[ "$jdk_root" == *$'\n'* || "$jdk_root" == *'"'* || "$jdk_root" == *'&'* || "$jdk_root" == *'|'* ]]; then
	print -u2 -r -- "caminho do JDK contém caractere não suportado"
	exit 2
fi
if [[ ! -d "$report_dir" ]]; then
	print -u2 -r -- "diretório de relatórios não existe: $report_dir"
	exit 2
fi

# Não altere preferências enquanto uma instância gráfica do editor puder salvá-las.
active_editor_pids="$(
	ps -axo pid=,comm=,args= \
		| awk '$2 == "Godot" && index($0, "--headless") == 0 {print $1}'
)"
if [[ -n "$active_editor_pids" ]]; then
	print -r -- "$active_editor_pids" >"${report_dir}/android-jdk-transaction.editor-active-pids.txt"
	print -u2 -r -- "Godot Editor ativo; transação de java_sdk_path recusada"
	exit 3
fi
print -r -- "none" >"${report_dir}/android-jdk-transaction.editor-active-pids.txt"

match_count="$(rg -c '^export/android/java_sdk_path = ' "$settings_file" || true)"
if [[ "$match_count" != "1" ]]; then
	print -u2 -r -- \
		"esperava exatamente uma chave export/android/java_sdk_path; encontrei ${match_count:-0}"
	exit 2
fi

transaction_dir="$(mktemp -d -t qix-android-jdk-settings.XXXXXX)"
backup_file="${transaction_dir}/editor_settings.backup"
candidate_file="${transaction_dir}/editor_settings.candidate"
delta_file="${transaction_dir}/editor_settings.diff"
cp -p "$settings_file" "$backup_file"

shasum -a 256 "$backup_file" >"${report_dir}/android-jdk-transaction.before.sha256"
stat -f 'mode=%Sp uid=%u gid=%g size=%z mtime=%m' "$backup_file" \
	>"${report_dir}/android-jdk-transaction.before.stat"

restore_settings() {
	local command_status=$?
	local restore_ok=1
	if ! cp -p "$backup_file" "$settings_file"; then
		restore_ok=0
	fi
	shasum -a 256 "$settings_file" >"${report_dir}/android-jdk-transaction.after.sha256"
	stat -f 'mode=%Sp uid=%u gid=%g size=%z mtime=%m' "$settings_file" \
		>"${report_dir}/android-jdk-transaction.after.stat"
	if ! cmp -s "$backup_file" "$settings_file"; then
		restore_ok=0
	fi
	printf 'restore_cmp=%s\ncommand_status=%s\n' \
		"$(( 1 - restore_ok ))" "$command_status" \
		>"${report_dir}/android-jdk-transaction.restore.txt"
	if (( restore_ok == 0 )); then
		command_status=125
	fi
	rm -f -- "$candidate_file" "$delta_file" "$backup_file"
	rmdir "$transaction_dir" 2>/dev/null || true
	trap - EXIT INT TERM HUP
	exit "$command_status"
}

trap restore_settings EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

/usr/bin/sed \
	"s|^export/android/java_sdk_path = .*$|export/android/java_sdk_path = \"${jdk_root}\"|" \
	"$backup_file" >"$candidate_file"

diff -U 0 "$backup_file" "$candidate_file" >"$delta_file"
diff_status=$?
changed_lines="$(rg -c '^[+-]export/android/java_sdk_path = ' "$delta_file" || true)"
unexpected_lines="$(
	rg '^[+-]' "$delta_file" \
		| rg -v '^--- |^\+\+\+ |^[+-]export/android/java_sdk_path = ' \
		|| true
)"
if (( diff_status != 1 )) || [[ "$changed_lines" != "2" || -n "$unexpected_lines" ]]; then
	print -u2 -r -- "a transação recusou uma alteração diferente da chave java_sdk_path"
	exit 2
fi

cp "$candidate_file" "$settings_file"
if ! rg -F -x -q -- "export/android/java_sdk_path = \"${jdk_root}\"" "$settings_file"; then
	print -u2 -r -- "java_sdk_path temporário não foi aplicado"
	exit 2
fi
shasum -a 256 "$settings_file" >"${report_dir}/android-jdk-transaction.modified.sha256"

JAVA_HOME="$jdk_root" "$@"
exit $?
