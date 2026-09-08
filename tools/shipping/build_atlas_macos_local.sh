#!/bin/bash
# Build de QA local: exporta e revalida a assinatura com as ferramentas do próprio macOS.
set -euo pipefail

atlas_root="$(cd "$(dirname "$0")/../.." && pwd)"
atlas_godot="${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
atlas_output="$atlas_root/build/modernization"
atlas_app="$atlas_output/Lumen Atlas Vivo.app"
mkdir -p "$atlas_output"

"$atlas_godot" --headless --path "$atlas_root" --import > "$atlas_output/import-local.log" 2>&1
"$atlas_godot" --headless --path "$atlas_root" --export-release "macOS Shipping QA" "$atlas_app" \
  > "$atlas_output/export-macos.log" 2>&1
# O assinador integrado produziu DER inválido nesta máquina apesar de codesign --verify passar.
# A assinatura ad-hoc nativa abaixo destina-se apenas a QA do projeto GDScript, sem CLR/JIT.
/usr/bin/codesign --force --deep --sign - --timestamp=none "$atlas_app" \
  > "$atlas_output/codesign-repair.log" 2>&1
/usr/bin/codesign --verify --deep --strict --verbose=2 "$atlas_app" \
  > "$atlas_output/codesign.log" 2>&1
"$atlas_app/Contents/MacOS/QIX GAME" --version > "$atlas_output/export-version.log" 2>&1
printf 'Build local pronta: %s\n' "$atlas_app"
