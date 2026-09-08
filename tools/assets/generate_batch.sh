#!/bin/zsh
# Lote de geração de sprites e texturas pela rota Codex/ChatGPT (image_gen).
# Uso: tools/assets/generate_batch.sh [manifest.tsv] [saida_dir]
# Manifesto TSV: slug<TAB>tamanho<TAB>prompt. Uma geração por linha, sequencial (evita rate limit).
# Cada geração salva <slug>_source.png (resolução nativa) e <slug>.png (tamanho pedido, alfa).
# O log em <saida>/generate.log guarda o exec-id de cada geração para a proveniência.
set -u
MANIFEST="${1:-tools/assets/sprite_manifest.tsv}"
OUT_DIR="${2:-assets/_gen}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$REPO/$OUT_DIR"
LOG="$REPO/$OUT_DIR/generate.log"
STYLE='Style constraints for every image: original design for an indie game called QIX GAME (Lumen Cartography aesthetic: deep navy void, electric cyan, pale gold core light, sparse magenta, bioluminescent cartography); crisp 2D pixel-art game sprite unless told otherwise; orthographic top-down; single subject centered with 1px margin; hard 1px outline in very dark navy so it reads on dark backgrounds; fully transparent background (real alpha, no checkerboard, no white box); no text, no letters, no numbers, no watermark, no signature, no drop shadow; do not imitate any existing game, character, brand or artist.'
while IFS=$'\t' read -r slug size prompt; do
	[[ -z "$slug" || "$slug" == \#* ]] && continue
	if [[ -f "$REPO/$OUT_DIR/$slug.png" ]]; then
		echo "skip $slug (existe)" | tee -a "$LOG"
		continue
	fi
	echo "=== $(date '+%H:%M:%S') gerando $slug ($size)" | tee -a "$LOG"
	codex exec --skip-git-repo-check -s workspace-write -C "$REPO" \
		"Use your image generation tool to create ONE image. $STYLE Subject: $prompt Deliverables: (1) save the generator's full-resolution output unchanged as $OUT_DIR/${slug}_source.png; (2) also save a version resized to exactly ${size} pixels with nearest-neighbour or area filtering (never bilinear blur), keeping the transparent background, as $OUT_DIR/${slug}.png. Finally print one line: GEN_DONE slug=$slug exec_id=<the image generation call id if known> size=<WxH of the second file>." \
		< /dev/null >> "$LOG" 2>&1
	if [[ -f "$REPO/$OUT_DIR/$slug.png" ]]; then
		echo "ok   $slug" | tee -a "$LOG"
	else
		echo "FALHOU $slug" | tee -a "$LOG"
	fi
done < "$REPO/$MANIFEST"
echo "=== lote concluído $(date '+%H:%M:%S')" | tee -a "$LOG"
