# ADR-0001 — Representação do território

**Estado:** aceita (G0, 2026-09-02)

## Contexto
O prompt exige uma única autoridade territorial com estados mutuamente exclusivos, testável sem cena, e proíbe que textura, TileMap, malha ou física sejam fonte de verdade. O starter disponível traz `vendor/polygon2d-fracture` (clip/área de polígonos).

## Alternativas
1. **Grade de células em `PackedByteArray`** (1 byte/célula, 225×283 = 63 675 bytes), flood fill BFS a partir dos anchors.
2. Polígonos (`Geometry2D` / polygon2d-fracture): território como união de polígonos, área por triangulação.
3. `TileMapLayer` como estado.

## Decisão
**Opção 1.** Coincide com o modelo do original (word por pixel, §5.1 de `06-gameplay.md`), dá contagem exata de células para o percentual, permite checksum canônico trivial e flood fill com fila pré-alocada. Polígonos introduzem float e casos degenerados (auto-interseção devolve área 0 na lib vendorizada); TileMap viola a regra de fonte de verdade.

## Consequências
- Indexação `y * width + x`; moldura = anel externo em `BOUNDARY`; interior 223×281.
- `BoardView` deriva uma `ImageTexture` da grade; nunca o contrário.
- `VolfiedParityCaptureResolver` (opcional, pós-G1) pode operar sobre a mesma grade.
