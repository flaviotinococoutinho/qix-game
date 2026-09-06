# ADR-0011 — A ameaça é lida por um contorno de tinta, não pela cor do corpo

## Status

Aceita em 2026-09-05.

## Contexto

`tools/verify_palette_contrast.gd` mediu, em 2026-09-04, os seis pares que decidem uma leitura
real do campo. Dois deles falham por larga margem e estão registrados como dívida conhecida em
`PaletteContrast.KNOWN_DEBT`:

| Par | Pior razão | Pior visão |
|---|---|---|
| `BOUNDARY`×`THREAT` | 1,27:1 | deuteranopia |
| `TRAIL`×`THREAT` | 1,82:1 | deuteranopia |

Traduzido para o que o jogador faz: o chefe atravessa a borda de onde ele está protegido, ou passa
por cima da trilha que ele acabou de desenhar, e nenhum dos dois eventos se separa do chão por
luminância. Hoje quem carrega a leitura é a **forma** — o losango contra células de 1 px. Isso
funciona para um tricromata olhando com atenção e falha exatamente quando mais importa: o chefe em
movimento, sobre a borda, no canto do olho.

Subir o par acima de 3:1 mudando `threat_color` não resolve. `BOUNDARY` e `TRAIL` são, as duas,
cores claras — é assim que o campo revelado se lê contra `free_color`, e é o que sustenta
`FREE`×`BOUNDARY` a 8,90:1 e `FREE`×`TRAIL` a 11,20:1. Uma ameaça que ficasse acima de 3:1 dos dois
chãos claros teria de ser escura, e uma ameaça escura sobre `FREE` (que também é escuro) perde o
par que hoje passa. Não há uma cor de corpo que satisfaça os três chãos ao mesmo tempo.

## Decisão

A ameaça ganha um **anel de tinta de 1 px** desenhado por baixo do corpo, em
`QixEnemyView` (`RIM_RADIUS` 5,0 contra `BODY_RADIUS` 4,0).

A tinta é o `free_color` da rodada — o chão ainda não reclamado, a cor mais escura de cada paleta.
Não é uma constante estética nova: é a mesma cor que o campo já usa, então o anel pertence à paleta
autorada e acompanha qualquer rodada futura sem edição de código. Em *Lumen Cartography*, o chefe
é um buraco recortado na carta, e a tinta é a borda desse recorte.

Medido sobre as três rodadas de produção mais a paleta padrão, nas quatro visões:

| Par | Pior razão | Pior visão |
|---|---|---|
| tinta × `BOUNDARY` | 8,93:1 | deuteranopia |
| tinta × `TRAIL` | 11,23:1 | protanopia |
| tinta × `THREAT` (o próprio corpo) | 3,73:1 | protanopia |

O canal que garante a leitura passa a ser luminância, não matiz, e os três pares ficam acima do
piso de 3:1 da WCAG 2.1 SC 1.4.11 sem que nenhuma cor autorada mude.

Duas consequências de desenho vêm junto, para que o anel seja um anel e não quatro arcos:

- os tendrils passam a ser desenhados **antes** do anel, de modo que emergem por trás da silhueta
  em vez de furá-la nos quatro vértices;
- as marcas de padrão (`PURSUIT`, `SWEEP`) nascem em `RIM_RADIUS`, não em `BODY_RADIUS`, para não
  abrir o contorno justamente na direção do movimento.

## Consequências

- `PaletteContrast.KNOWN_DEBT` **continua** listando `BOUNDARY`×`THREAT` e `TRAIL`×`THREAT`, e isso
  é correto: os pares cromáticos não melhoraram. O que mudou é que a leitura deixou de depender
  deles. Fechar a dívida cromática continua sendo uma decisão em aberto, agora sem urgência.
- `tests/unit/enemy_silhouette_contrast_test.gd` é a guarda. Ele falha se o anel encolher até
  sumir, se a tinta deixar de ser o `free_color` autorado, ou se uma paleta nova tiver um
  `free_color` claro demais para sustentar os três pares.
- Nada disto toca `game/simulation`, `game/rules` ou `game/session`. O anel é apresentação pura
  sobre um snapshot confirmado (invariante 6), e o teste verifica que sincronizar a silhueta não
  altera `state_checksum()` nem avança o tick (invariante 8).
- O ganho não foi visto numa tela: uma sessão headless mede contraste, não aprova estética. Falta
  alguém confirmar por captura que o anel lê como contorno e não como uma orla suja em volta do
  chefe — em particular quando ele está sobre `FREE`, onde tinta e chão são quase a mesma cor e o
  anel deve simplesmente desaparecer.

## Alternativas consideradas

- **Baixar a luminância de `threat_color`.** Resolve os dois chãos claros e quebra `FREE`×`THREAT`,
  hoje a 3,70:1. Trocar um par medido por dois é regressão, não melhoria.
- **Halo claro em volta do chefe.** Separaria da borda mas não da trilha, que já é a cor mais clara
  do campo, e competiria com a aura de `accent_color` que comunica o surto de velocidade.
- **Cadência — piscar o corpo.** É um canal temporal, e o chefe já usa `_phase_step` para o
  footprint e para os tendrils. Somar um terceiro uso do mesmo relógio de 16 ticks tornaria a
  silhueta ruidosa sem garantir leitura num frame parado.
