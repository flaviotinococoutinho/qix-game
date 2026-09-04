#!/bin/zsh
# Reduz um bundle universal exportado pelo Godot para arm64 e refaz a assinatura ad-hoc.
set -eu

if (( $# != 1 )); then
	print -u2 -r -- "uso: ${0:t} /caminho/QIX\ GAME.app"
	exit 2
fi

app="$1"
info_plist="${app}/Contents/Info.plist"

if [[ ! -d "$app" || ! -f "$info_plist" ]]; then
	print -u2 -r -- "bundle macOS inválido: $app"
	exit 2
fi

for command_name in /usr/bin/lipo /usr/bin/codesign /usr/libexec/PlistBuddy; do
	if [[ ! -x "$command_name" ]]; then
		print -u2 -r -- "ferramenta macOS ausente: $command_name"
		exit 2
	fi
done

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
executable="${app}/Contents/MacOS/${executable_name}"
if [[ ! -f "$executable" ]]; then
	print -u2 -r -- "executável declarado no Info.plist não existe: $executable"
	exit 2
fi

before_archs="$(/usr/bin/lipo -archs "$executable")"
before_bytes="$(stat -f %z "$executable")"
if [[ " $before_archs " != *" arm64 "* ]]; then
	print -u2 -r -- "o executável não contém uma fatia arm64: $before_archs"
	exit 1
fi

if [[ "$before_archs" != "arm64" ]]; then
	temporary="$(mktemp "${executable}.arm64.XXXXXX")"
	cleanup() {
		[[ -e "$temporary" ]] && rm -f -- "$temporary"
	}
	trap cleanup EXIT INT TERM HUP

	mode="$(stat -f %Lp "$executable")"
	/usr/bin/lipo "$executable" -thin arm64 -output "$temporary"
	chmod "$mode" "$temporary"
	mv -f -- "$temporary" "$executable"
	trap - EXIT INT TERM HUP
fi

# Alterar uma fatia invalida a assinatura feita pelo exportador. Esta é uma
# assinatura ad-hoc local, adequada ao smoke test, não à distribuição pública.
/usr/bin/codesign --force --deep --sign - --timestamp=none "$app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"

after_archs="$(/usr/bin/lipo -archs "$executable")"
after_bytes="$(stat -f %z "$executable")"
if [[ "$after_archs" != "arm64" ]]; then
	print -u2 -r -- "resultado não é arm64 puro: $after_archs"
	exit 1
fi

print -r -- "before_archs=$before_archs"
print -r -- "after_archs=$after_archs"
print -r -- "before_executable_bytes=$before_bytes"
print -r -- "after_executable_bytes=$after_bytes"
