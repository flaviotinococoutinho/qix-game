# ADR-0005 — Máscara R8 para revelação do território

**Estado:** aceita (G2, 2026-09-02)

## Contexto

O renderer G1 reconstruía uma imagem RGBA8 de 225×283 e chamava `set_pixel()` para
cada uma das 63.675 células sempre que `BoardState.version` mudava. Além do custo de
CPU, o valor visual de `CLAIMED` era apenas uma cor: não havia como revelar a arte da
rodada sem duplicar a autoridade territorial.

## Decisão

- `BoardState.cells` continua sendo a única fonte de verdade.
- A view reaproveita uma `Image` `FORMAT_R8` e uma `ImageTexture`; os bytes do board
  formam diretamente a máscara e a textura é atualizada somente quando a instância ou
  versão do board muda.
- Um shader `canvas_item` amostra a máscara com filtro nearest. `FREE` recebe cobertura,
  `BOUNDARY` e `TRAIL` recebem cores autoradas, e somente `CLAIMED` exibe o fundo.
- Fundo, paleta, pulso e revelação de transição são apresentação; não retroalimentam a
  simulação e não entram no replay.
- A instrumentação usa `Time.get_ticks_usec()` e um ring buffer passivo. Métricas nunca
  mudam ordem, seed, inputs ou decisões do tick.

## Consequências

- O upload por atualização cai de quatro para um byte por célula e deixa de fazer
  dezenas de milhares de conversões de cor em GDScript.
- A mesma textura é reutilizada entre versões do mesmo board; uma nova alocação ocorre
  apenas ao mudar as dimensões.
- O custo pode ser acompanhado por último valor, média, p95, máximo, contagem de
  refreshes e atualizações ignoradas.
- O shader precisa continuar validado no renderer GL Compatibility e em hardware-alvo.
