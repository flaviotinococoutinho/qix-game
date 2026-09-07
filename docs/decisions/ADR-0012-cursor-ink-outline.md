# ADR-0012 — O cursor é lido por um contorno de tinta, não pelas cores que empresta do campo

## Status

Aceita em 2026-09-07.

## Contexto

`tools/verify_palette_contrast.gd` mediu, em 2026-09-05, as três camadas opacas da silhueta 5×5 de
`QixPlayerView._draw` contra os dois chãos em que o jogador realmente anda. Metade da tabela passa
com folga e a outra metade não separa nada. Pior caso sobre as quatro paletas e os quatro modelos
de visão, registrado em `PaletteContrast.CURSOR_KNOWN_DEBT`:

| Par | Pior razão | Pior visão |
|---|---|---|
| `CURSOR_OUTER`×`BOUNDARY` | 1,00:1 | tricromata |
| `CURSOR_CORE`×`BOUNDARY` | 1,04:1 | protanopia |
| `CURSOR_ACCENT`×`BOUNDARY` | 1,12:1 | deuteranopia |

Traduzido para o que o jogador faz: **enquanto ele anda protegido pela borda, "onde eu estou" não
se separa do chão por luminância nenhuma.** Não é só o contorno externo que some — o núcleo, que
existe justamente para dar um centro inequívoco à célula autoritativa, mede 1,04:1. O que sustenta
a leitura hoje é o halo pulsante desenhado *fora* da silhueta, mais o fato de o cursor se mover:
dois canais que falham exatamente quando mais importam, com o cursor parado num canto do campo.

A dívida é **estrutural, não autoral**. `QixPlayerView.sync` atribui `_outer = visual.boundary_color`
literal: a camada externa *é* a cor do chão, por construção, então a razão é 1,00:1 em qualquer
paleta que alguém venha a autorar. Nenhuma escolha de cor conserta isso.

E escolher uma cor nova para a silhueta também não resolve. Sobre `FREE` as três camadas passam com
folga (5,38:1 no pior caso) porque são claras, e `FREE` é o chão mais escuro de cada paleta. Uma
silhueta escura o bastante para separar de `BOUNDARY` perderia os três pares sobre `FREE`, que hoje
passam. Os dois chãos estão em extremos opostos da luminância: **não há cor de silhueta que
satisfaça os dois ao mesmo tempo.** É a mesma forma de problema que a ADR-0011 encontrou na ameaça,
e o item sobreviveu a mais de vinte execuções do loop sem dono por isso.

## Decisão

O cursor ganha um **contorno de tinta de 1 px** desenhado por baixo da silhueta, em
`QixPlayerView` (`INK_REACH` 3,0 contra `BODY_REACH` 2,0). A cruz de tinta é a mesma construção
geométrica da cruz opaca, uma unidade maior, de modo que o contorno feche em volta dos quatro
braços em vez de abrir onde o olho procura a direção.

A tinta é o `free_color` da rodada — o chão ainda não reclamado, a cor mais escura de cada paleta.
É a mesma escolha da ADR-0011, e pela mesma razão: não é uma constante estética nova, pertence à
paleta autorada, e acompanha qualquer rodada futura sem edição de código. Em *Lumen Cartography*,
o cursor é a ponta do estilete sobre a carta, e a tinta é a sombra que ele projeta no papel.

`docs/ART_DIRECTION.md` pedia, em 2026-09-05, “uma borda escura que **não venha da paleta do
campo**”. A decisão diverge nesse detalhe de propósito: uma constante fixa ficaria certa para as
quatro paletas de hoje e erraria na primeira rodada nova de fundo claro, ao passo que `free_color`
é, por definição de cada paleta, o extremo escuro dela. A restrição real era “não venha das três
camadas que a silhueta já empresta”, e é essa que se respeita.

Medido sobre as três rodadas de produção mais a paleta padrão, nas quatro visões:

| Par | Pior razão | Pior visão |
|---|---|---|
| tinta × `BOUNDARY` | 8,93:1 | deuteranopia |

Por paleta, o pior caso é 8,93 (padrão), 9,57 (abyssal_relay), 9,01 (aurora_foundry) e 9,98
(verdant_singularity) — quase três vezes o piso de 3:1 da WCAG 2.1 SC 1.4.11, sem que nenhuma cor
autorada mude. O canal que garante a leitura passa a ser luminância, não matiz.

Duas consequências de desenho vêm junto, para que o contorno seja um contorno e não um borrão:

- a proa de direção nasce em `FACING_NEAR` 4,0 em vez de 3,0 (`INK_REACH + 1`, como antes era
  `BODY_REACH + 1`). Sem isso ela começaria **dentro** da própria tinta, e a leitura de direção
  competiria com a de posição em vez de a completar. `FACING_FAR` acompanha, de 5,0 para 6,0: o
  comprimento de 2 px que a proa tem desde a sua entrada é preservado;
- o halo pulsante passa de raio 4,0/5,0 para 5,0/6,0, preservando a folga de 1 px que ele tinha
  contra a silhueta antes de o contorno existir. Colado à tinta, o halo lê-se como parte do cursor
  em vez de como respiração em volta dele.

## Consequências

- `PaletteContrast.CURSOR_KNOWN_DEBT` **continua** listando os três pares, e isso é correto: os
  pares cromáticos não melhoraram. O que mudou é que a leitura deixou de depender deles. Fechar a
  dívida cromática continua uma decisão em aberto, agora sem urgência — exatamente o desfecho que a
  ADR-0011 registrou para `BOUNDARY`×`THREAT` e `TRAIL`×`THREAT`.
- `CURSOR_INK`×`BOUNDARY` entra em `CURSOR_PAIRS` e em `CURSOR_FLOOR` (piso 8,92). O par não é
  medido contra `FREE` de propósito: ali a tinta **é** o chão, mede ~1:1 por construção e some — que
  é o desejado, porque sobre `FREE` as camadas opacas já passam com folga. Medi-la como par de
  legibilidade afirmaria uma leitura que o desenho não pretende.
- `tests/unit/cursor_ink_outline_test.gd` é a guarda. Ele falha se alguém trocar a tinta por uma cor
  clara, encolher o contorno até sumir, abrir a cruz de tinta num dos braços, puxar a proa para
  dentro do contorno, ou autorar uma paleta cujo `free_color` deixe de sustentar a leitura.
- Nada disto toca `game/simulation`, `game/rules` ou `game/session`. O contorno é apresentação pura
  sobre um snapshot confirmado (invariante 6), e o teste verifica que sincronizar a silhueta não
  altera `state_checksum()` nem avança o tick (invariante 8). A rota M2 completa sai byte a byte
  igual à de `main`.
- O custo por frame é de dois `draw_rect` opacos a mais num único nó, contra os quatro que a
  silhueta já desenhava. `tools/profile_board_view.gd` **não** cobre este caminho — ele perfila a
  máscara R8 do campo — então este número é contagem de chamadas, não medição.
- O ganho não foi visto numa tela: uma sessão headless mede contraste, não aprova estética. Falta
  alguém confirmar por captura que o contorno lê como contorno e não como um cursor engordado —
  em particular sobre `FREE`, onde tinta e chão quase coincidem e o contorno deve simplesmente
  desaparecer, e no momento em que o cursor sai da borda para começar a trilha, que é quando o
  contorno some e a silhueta assume a leitura sozinha.

## Alternativas consideradas

- **Mover as cores da silhueta para o meio da escala.** É o que `ART_DIRECTION` descrevia como o
  caminho “uma cor no meio”. Uma silhueta de luminância média fica acima de 3:1 de nenhum dos dois
  chãos com folga: trocaria três pares que passam por seis pares medíocres.
- **Deixar o halo carregar a leitura.** É o que acontece hoje, e é o que a medição condena: o halo é
  desenhado com alfa, então a cor que chega ao olho depende do que está atrás, e por isso nem sequer
  é um valor que a medição possa afirmar. Um canal que não se consegue medir não é um canal em que
  se possa confiar.
- **Piscar a silhueta sobre `BOUNDARY`.** Canal temporal, e o cursor já usa `_pulse_step` para o
  halo e para o alerta de escudo crítico. Um terceiro uso do mesmo relógio tornaria o cursor ruidoso
  sem garantir leitura num frame parado — a mesma razão pela qual a ADR-0011 recusou piscar o corpo
  do chefe.
- **Uma constante escura fixa, fora da paleta.** Era a letra do pedido de `ART_DIRECTION`. Recusada
  acima: acerta nas quatro paletas de hoje e erra sozinha na primeira paleta clara que alguém
  autore, enquanto `free_color` acompanha por construção.
