# Direção de arte — Lumen Cartography

> **Verificado em** 2026-09-05 · commit `cba520a` · Godot 4.7.2-stable, Linux headless
> **Alcance:** documento de intenção. A parte mecanizável dele — só `CLAIMED` revela o fundo,
> paleta e máscara R8 — vive em `tests/unit/board_view_test.gd`; hierarquia, ritmo e leitura em
> 240×320 continuam sem verificação automatizada, e ninguém na nuvem consegue ver o jogo.
> Nesta data acrescentou-se a seção “Contraste do cursor contra o chão”, medida por
> `tools/verify_palette_contrast.gd`. A tabela do campo em “Contraste medido” **não** foi
> remedida: continua com a data de 2026-09-04 impressa nela, e nada nesta execução mexeu na
> paleta autorada.
>
> **Emenda de 2026-09-07** · commit `34634d0` · Godot 4.7.2-stable, Linux headless. Acrescentou-se
> “O contorno do cursor”, que transcreve a [ADR-0012](decisions/ADR-0012-cursor-ink-outline.md).
> A tabela de “Contraste do cursor contra o chão” foi **reconferida** hoje pelo mesmo comando e sai
> idêntica à impressa — as suas seis linhas continuam válidas, e por isso a data dentro dela fica
> como está. O que mudou não foi cor autorada nenhuma: foi de onde vem a leitura. Nenhuma paleta,
> regra ou geometria de campo mudou, e nenhum checksum de replay se moveu.

O G2 usa uma identidade original de **cartografia bioluminescente**: o jogador não
“pinta” uma chapa sólida; ele estabiliza regiões de um mapa vivo e revela uma paisagem
cósmica que estava encoberta. A leitura do estado continua imediata mesmo em 240×320.

## Hierarquia visual

1. `TRAIL` é o elemento de maior luminância e pulsa entre amarelo e branco. O pulso **não é
   constante**: acelera e ergue o piso de luminância conforme a trilha se afasta da moldura
   (`TrailExposure`), de modo que a exposição seja legível antes do impacto. O aviso viaja por
   frequência e brilho, nunca por matiz.
2. Jogador e chefe têm silhuetas compactas, núcleos contrastantes e leitura em 1×.
3. `BOUNDARY` desenha o contorno seguro em ciano/verde.
4. `CLAIMED` revela a ilustração original da rodada.
5. `FREE` permanece sob uma cobertura azul-noturna para proteger a legibilidade.
6. HUD e overlays vivem fora do campo e não escondem decisões de movimento.

Os itens 1 e 2 são **intenção, não estado medido**. Em 2026-09-04 `TRAIL` e `BOUNDARY` têm
praticamente a mesma luminância (1,04:1); em 2026-09-05 o “núcleo contrastante” do jogador mediu
1,04–1,12:1 contra `BOUNDARY`, o chão onde ele passa a maior parte da partida. Ver “Contraste
medido” e “Contraste do cursor contra o chão” abaixo antes de tratar a hierarquia como fato.

## Arco das três rodadas

| Rodada | Ambiente | Intenção | Acentos |
|---|---|---|---|
| 1 | Abyssal Relay | entrada legível, profundidade oceânica/cósmica | ciano e turquesa |
| 2 | Aurora Foundry | energia maior, formas minerais e mecânicas abstratas | âmbar e magenta |
| 3 | Verdant Singularity | clímax orgânico, núcleo verde em colapso | verde-lima e coral |

Todas as imagens são composições originais geradas para este projeto, sem personagens,
marcas ou material extraído de ROM. Fontes, prompts resumidos, dimensões, hash e estado
de aprovação ficam em `assets/ASSET-PROVENANCE.md`.

## Contraste medido

Medido em **2026-09-04** por `tools/verify_palette_contrast.gd` (Godot 4.7.2-stable headless,
Linux). O que entra na conta são as cores **como o shader as desenha** — scanline 0,92/1,0 em
`FREE`, glint 0,86/1,0 em `BOUNDARY`, os dois extremos do pulso em `TRAIL` — e não as cores
autoradas. A métrica é a razão de contraste de luminância da WCAG 2.1; cada número é o **pior
caso** entre visão tricromática e as simulações de protanopia, deuteranopia e tritanopia
(matrizes de Machado, Oliveira & Fernandes, 2009, severidade 1,0).

| Par | Padrão | Abyssal Relay | Aurora Foundry | Verdant Singularity | Meta 3:1 |
|---|---|---|---|---|---|
| `FREE`×`BOUNDARY` | 8,93 | 9,57 | 9,01 | 9,98 | ok |
| `FREE`×`TRAIL` | 11,36 | 12,37 | 11,23 | 12,87 | ok |
| `BOUNDARY`×`TRAIL` | 1,04 | 1,04 | 1,05 | 1,04 | **abaixo** |
| `FREE`×`THREAT` | 3,73 | 4,34 | 4,48 | 4,48 | ok |
| `BOUNDARY`×`THREAT` | 1,39 | 1,36 | 1,28 | 1,42 | **abaixo** |
| `TRAIL`×`THREAT` | 2,04 | 1,99 | 1,83 | 2,04 | **abaixo** |

O piso de 3:1 é a SC 1.4.11 (Non-text Contrast) da WCAG 2.1, aplicada a componentes de interface
não textuais. Aqui ele é **piso, não meta**: uma célula do campo ocupa cerca de 1 px em 240×320.

Leitura:

- **O chão está resolvido.** `FREE` contra `BOUNDARY` e contra `TRAIL` passa com folga em todos os
  quatro modelos de visão. A pergunta “o que já é meu e onde está a borda” não depende de cor.
- **`BOUNDARY`×`TRAIL` é o buraco real.** A 1,04:1 as duas luminâncias são a mesma; a distinção
  entre “estou protegido” e “estou desenhando” repousa sobre matiz (ciano × âmbar) mais os padrões
  do shader — o glint xadrez do contorno e o pulso temporal da trilha. Sob deuteranopia sobram
  entre 35% e 65% da diferença cromática. É a decisão mais cara do jogo apoiada no canal mais
  frágil.
- **A ameaça sobre borda e trilha depende de forma e movimento.** 1,28–1,42:1 sobre `BOUNDARY` e
  1,83–2,04:1 sobre `TRAIL`, ambos no pior caso em deuteranopia. O losango do chefe e o halo do
  jogador são hoje o que sustenta essas leituras, não a luminância.

Isto é **medição registrada, não correção**. Ajustar a paleta muda o rosto do jogo e pede olho
humano sobre a tela — nenhuma sessão headless pode aprovar essa troca. `PaletteContrast.PAIR_FLOOR`
guarda os números como catraca e `tests/unit/palette_contrast_test.gd` falha se algum par piorar
**ou** se algum deles for consertado sem que esta seção seja reescrita junto.

## Contraste do cursor contra o chão

Medido em **2026-09-05** pelo mesmo comando e pela mesma métrica da seção acima. O que se mede
aqui são as três camadas **opacas** da silhueta 5×5 de `QixPlayerView._draw`, de fora para dentro,
contra os dois chãos em que o jogador realmente anda. O halo fica de fora de propósito: é
desenhado com alfa sobre o campo, então a cor que chega ao olho depende do que está atrás e não é
um valor que esta medição possa afirmar.

| Camada | Cor autorada | Padrão | Abyssal | Aurora | Verdant | Meta 3:1 |
|---|---|---|---|---|---|---|
| `CURSOR_OUTER`×`FREE` | `boundary_color` | 12,19 | 13,08 | 12,28 | 13,67 | ok |
| `CURSOR_ACCENT`×`FREE` | `accent_color` | 6,52 | 6,49 | 5,38 | 8,89 | ok |
| `CURSOR_CORE`×`FREE` | `trail_hot_color` | 15,33 | 16,35 | 15,99 | 15,87 | ok |
| `CURSOR_OUTER`×`BOUNDARY` | `boundary_color` | 1,00 | 1,00 | 1,00 | 1,00 | **abaixo** |
| `CURSOR_ACCENT`×`BOUNDARY` | `accent_color` | 1,37 | 1,46 | 1,65 | 1,12 | **abaixo** |
| `CURSOR_CORE`×`BOUNDARY` | `trail_hot_color` | 1,10 | 1,09 | 1,12 | 1,04 | **abaixo** |

Leitura:

- **Enquanto desenha, o cursor está resolvido.** Sobre `FREE` as três camadas passam da meta em
  todos os quatro modelos de visão, com folga de 5,4:1 no pior caso. A pergunta “onde eu estou”
  não tem problema no momento em que ela é mais tensa.
- **Enquanto anda protegido, nenhuma camada opaca separa.** Sobre `BOUNDARY` as três ficam entre
  1,00 e 1,65:1 em todas as paletas. Isto é mais forte do que se supunha: não é só o contorno que
  some no chão — o núcleo, que existe para dar “centro inequívoco”, mede 1,04–1,12:1. O que
  sustenta a leitura hoje é o halo pulsante de `accent_color` desenhado **fora** da silhueta, mais
  o fato de o cursor se mover.
- **`CURSOR_OUTER`×`BOUNDARY` a 1,00:1 é estrutural, não autoral.** `QixPlayerView.sync` atribui
  `_outer = visual.boundary_color`: a camada externa *é* a cor do chão, por construção. Nenhuma
  paleta que alguém escreva conserta esse par — só mudar de onde a view tira a cor.
  `tests/unit/cursor_contrast_test.gd` fixa essa dependência, para que ela não seja desfeita sem
  que a dívida seja revista.

As seis linhas acima **continuam nestes números** e os três pares sobre `BOUNDARY` continuam em
`PaletteContrast.CURSOR_KNOWN_DEBT`: nenhuma cor autorada mudou desde a medição.
`PaletteContrast.CURSOR_FLOOR` guarda-os como catraca e `CURSOR_KNOWN_DEBT` faz o conserto de
qualquer um dos três **falhar** o teste até que esta seção seja reescrita junto. O que mudou em
2026-09-07 é que a leitura deixou de repousar sobre eles — ver “O contorno do cursor”.

## O contorno do cursor

Decidido em **2026-09-07** pela [ADR-0012](decisions/ADR-0012-cursor-ink-outline.md), em resposta
direta à dívida da tabela acima. A seção anterior deste documento propunha a restrição de projeto:
subir os três `CURSOR_*`×`BOUNDARY` acima de 3:1 **sem** derrubar os `CURSOR_*`×`FREE` que hoje
passam. Ela não tem solução em cor de silhueta, e é por isso que o item atravessou mais de vinte
execuções sem dono: os dois chãos estão em extremos opostos da luminância — `BOUNDARY` é claro
porque é assim que o campo revelado se lê, `FREE` é o mais escuro de cada paleta — e a silhueta
tem de separar dos dois.

Por isso o cursor não é lido pelas cores que empresta do campo, e sim por um **contorno de tinta de
1 px** desenhado por baixo dele em `QixPlayerView` (`INK_REACH` 3,0 contra `BODY_REACH` 2,0). A
tinta é o `free_color` da própria rodada, como no anel da ameaça: nenhuma constante estética nova
entra no jogo, e o contorno acompanha qualquer paleta futura sem edição de código. Em *Lumen
Cartography*, o cursor é a ponta do estilete sobre a carta, e a tinta é a sombra que ele projeta no
papel — sobre `FREE`, onde tinta e chão coincidem, o contorno some, e é isso que se quer: ali as
três camadas opacas já passam com folga de 5,38:1.

| Par | Padrão | Abyssal | Aurora | Verdant | Meta 3:1 |
|---|---|---|---|---|---|
| `CURSOR_INK`×`BOUNDARY` | 8,93 | 9,57 | 9,01 | 9,98 | ok |

Pior caso por paleta sobre os quatro modelos de visão, medido por `tools/verify_palette_contrast.gd`
em 2026-09-07 — quase três vezes a meta, com a leitura ancorada em luminância em vez de matiz.

Duas consequências de desenho vêm junto, para que o contorno seja um contorno e não um cursor
engordado: a proa de direção nasce em `FACING_NEAR` 4,0 em vez de 3,0, para não começar dentro da
própria tinta, preservando os seus 2 px de comprimento; e o halo pulsante passa de raio 4,0/5,0
para 5,0/6,0, preservando a folga de 1 px que ele tinha contra a silhueta — colado à tinta, ele
leria como parte do cursor em vez de como respiração em volta dele.

`tests/unit/cursor_ink_outline_test.gd` é a guarda, e o contorno é apresentação pura: sincronizar a
silhueta não altera `state_checksum()` nem avança o tick. **Falta o julgamento estético** — ninguém
viu o contorno numa tela, em particular no instante em que o cursor deixa a borda para começar a
trilha e a tinta se dissolve no chão.

## Barra de qualidade do slice

- Sem texto embutido, assinatura, watermark ou IP de terceiros.
- Fundo válido exatamente em 225×283, sem crop em runtime.
- Estados territoriais distinguíveis por forma, cor e luminância — cor não é o único
  canal para ameaça e segurança. **Parcialmente atendido**: verdadeiro para `FREE` contra
  `BOUNDARY` e `TRAIL`; ainda não para `BOUNDARY`×`TRAIL` nem para a ameaça sobre esses dois
  chãos. Ver “Contraste medido”.
- Jogador e chefe com “núcleos contrastantes” e leitura em 1×. **Parcialmente atendido**:
  verdadeiro para o cursor sobre `FREE` (5,4:1 no pior caso); sobre `BOUNDARY` nenhuma camada
  opaca do cursor separa por luminância. Ver “Contraste do cursor contra o chão”.
- Mudanças de rodada têm intro, resultado, confirmação opcional e continuidade clara de
  score/vidas.
- Feedback de captura nasce de eventos confirmados e nunca antecipa resultado do domínio.
- A apresentação pode ser trocada sem alterar checksum ou compatibilidade de replay.

“AAA” neste marco é uma barra de coesão, resposta, legibilidade e mensuração do vertical slice.
O shipping pass acrescenta áudio e feedback, mas o termo ainda não afirma escala de conteúdo,
QA multiplataforma concluído, validação humana/física ou prontidão comercial.
