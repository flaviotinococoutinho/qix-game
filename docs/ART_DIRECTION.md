# Direção de arte — Lumen Cartography

O G2 usa uma identidade original de **cartografia bioluminescente**: o jogador não
“pinta” uma chapa sólida; ele estabiliza regiões de um mapa vivo e revela uma paisagem
cósmica que estava encoberta. A leitura do estado continua imediata mesmo em 240×320.

## Hierarquia visual

1. `TRAIL` é o elemento de maior luminância e pulsa entre amarelo e branco.
2. Jogador e chefe têm silhuetas compactas, núcleos contrastantes e leitura em 1×.
3. `BOUNDARY` desenha o contorno seguro em ciano/verde.
4. `CLAIMED` revela a ilustração original da rodada.
5. `FREE` permanece sob uma cobertura azul-noturna para proteger a legibilidade.
6. HUD e overlays vivem fora do campo e não escondem decisões de movimento.

O item 1 é **intenção, não estado medido**: em 2026-09-04 `TRAIL` e `BOUNDARY` têm praticamente a
mesma luminância (1,04:1). Ver “Contraste medido” abaixo antes de tratar a hierarquia como fato.

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

## Barra de qualidade do slice

- Sem texto embutido, assinatura, watermark ou IP de terceiros.
- Fundo válido exatamente em 225×283, sem crop em runtime.
- Estados territoriais distinguíveis por forma, cor e luminância — cor não é o único
  canal para ameaça e segurança. **Parcialmente atendido**: verdadeiro para `FREE` contra
  `BOUNDARY` e `TRAIL`; ainda não para `BOUNDARY`×`TRAIL` nem para a ameaça sobre esses dois
  chãos. Ver “Contraste medido”.
- Mudanças de rodada têm intro, resultado, confirmação opcional e continuidade clara de
  score/vidas.
- Feedback de captura nasce de eventos confirmados e nunca antecipa resultado do domínio.
- A apresentação pode ser trocada sem alterar checksum ou compatibilidade de replay.

“AAA” neste marco é uma barra de coesão, resposta, legibilidade e mensuração do vertical slice.
O shipping pass acrescenta áudio e feedback, mas o termo ainda não afirma escala de conteúdo,
QA multiplataforma concluído, validação humana/física ou prontidão comercial.
