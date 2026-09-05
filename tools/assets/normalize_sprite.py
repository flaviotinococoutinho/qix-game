#!/usr/bin/env python3
"""Normaliza uma imagem gerada por IA para um sprite/textura do jogo.

Uso:
  uv run --with pillow python tools/assets/normalize_sprite.py SRC DST --size 48x48 \
      [--key-white 235] [--trim] [--pad 2] [--filter box|nearest|lanczos] [--sheet COLSxROWS]

- `--key-white N`: pixels com R,G,B >= N viram transparentes (fontes com fundo branco).
- `--trim`: recorta ao retângulo não transparente antes de redimensionar (preserva proporção,
  centraliza num quadrado).
- `--pad`: margem em pixels **de saída** ao redor do sujeito.
- `--filter`: `box` (padrão; reduz pixel-art sem borrar), `nearest`, `lanczos` (pintura).
- `--sheet COLSxROWS`: trata a fonte como grade uniforme e normaliza cada célula separadamente,
  reconstruindo a folha na saída com células de `--size`.
Imprime dimensões finais, presença de alfa e SHA-256 do arquivo gravado.
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from PIL import Image

FILTERS = {
    "box": Image.Resampling.BOX,
    "nearest": Image.Resampling.NEAREST,
    "lanczos": Image.Resampling.LANCZOS,
}


def key_white(image: Image.Image, threshold: int) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                pixels[x, y] = (r, g, b, 0)
    return image


def trim_to_content(image: Image.Image) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return image
    return image.crop(bbox)


def fit_square(image: Image.Image) -> Image.Image:
    width, height = image.size
    side = max(width, height)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(image, ((side - width) // 2, (side - height) // 2))
    return canvas


def normalize_cell(image: Image.Image, size: tuple[int, int], pad: int, resample: Image.Resampling,
                   trim: bool) -> Image.Image:
    image = image.convert("RGBA")
    if trim:
        image = fit_square(trim_to_content(image))
    inner = (max(1, size[0] - 2 * pad), max(1, size[1] - 2 * pad))
    # Premultiplica para o filtro não arrastar cor de pixels transparentes.
    resized = image.resize(inner, resample=resample)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(resized, (pad, pad))
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("src")
    parser.add_argument("dst")
    parser.add_argument("--size", required=True, help="LARGURAxALTURA da saída (por célula com --sheet)")
    parser.add_argument("--key-white", type=int, default=0)
    parser.add_argument("--trim", action="store_true")
    parser.add_argument("--pad", type=int, default=0)
    parser.add_argument("--filter", choices=sorted(FILTERS), default="box")
    parser.add_argument("--sheet", default="")
    args = parser.parse_args()

    width, height = (int(v) for v in args.size.lower().split("x"))
    resample = FILTERS[args.filter]
    source = Image.open(args.src).convert("RGBA")
    if args.key_white > 0:
        source = key_white(source, args.key_white)

    if args.sheet:
        cols, rows = (int(v) for v in args.sheet.lower().split("x"))
        cell_w, cell_h = source.size[0] // cols, source.size[1] // rows
        out = Image.new("RGBA", (width * cols, height * rows), (0, 0, 0, 0))
        for row in range(rows):
            for col in range(cols):
                cell = source.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
                out.paste(normalize_cell(cell, (width, height), args.pad, resample, args.trim),
                          (col * width, row * height))
    else:
        out = normalize_cell(source, (width, height), args.pad, resample, args.trim)

    dst = Path(args.dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, format="PNG", optimize=True)
    digest = hashlib.sha256(dst.read_bytes()).hexdigest()
    alpha = out.getchannel("A").getextrema()
    print(f"{dst} {out.size[0]}x{out.size[1]} alpha_range={alpha} sha256={digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
