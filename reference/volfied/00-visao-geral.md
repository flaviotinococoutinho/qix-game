# 00 — Visão geral

Índice da documentação da desmontagem do **Volfied** (Taito, 1989), set `volfied`
(*World, rev 1*). Para o projecto em si — como o correr, como contribuir — veja o
[README](../README.md).

## Por onde começar

Depende do que quer fazer.

| Se quer… | Leia |
|---|---|
| perceber a placa antes de tudo | [01 — A placa](01-hardware.md) |
| encontrar um endereço | [02 — Mapa de memória](02-mapa-de-memoria.md) |
| perceber como o ecrã é desenhado | [03 — Vídeo](03-video.md) |
| perceber a protecção | [04 — C-Chip](04-c-chip.md) |
| mexer na música | [05 — Som](05-som.md) |
| perceber o *jogo* | [06 — Como o jogo funciona](06-gameplay.md) |
| traduzir os textos | [07 — Texto e fonte](07-texto-e-fonte.md) |
| reproduzir tudo do zero | [08 — Ferramentas](08-ferramentas-e-reproducao.md) |

Se só vai ler um, leia o **06**: é onde está o algoritmo de preenchimento de área, que é
o que faz do Volfied um Volfied.

`ACHADOS_ANOTACAO.md` é diferente dos outros: é **material de trabalho em bruto**, o
raciocínio dos agentes que leram o código pela primeira vez. Inclui hipóteses que foram
depois rejeitadas. Não o cite como referência — está lá porque o percurso até uma
conclusão às vezes vale mais do que a conclusão.

## As três CPUs

Volfied não é um jogo de um processador. São três, e cada um tem o seu documento.

```
        ┌──────────────┐  VBLANK   ┌──────────────┐
        │   MC68000    │◀──────────│    vídeo     │
        │    8 MHz     │           │  bitmap +    │
        │   o jogo     │──────────▶│  PC090OJ     │
        └───┬──────┬───┘           └──────────────┘
            │      │
    PC060HA │      │ $F00000-$F00FFF
            ▼      ▼
    ┌────────────┐ ┌──────────────┐
    │  Z80 4 MHz │ │   C-Chip     │
    │  + YM2203  │ │  uPD78C11    │
    │    o som   │ │ protecção +  │
    └────────────┘ │  entradas    │
                   └──────┬───────┘
                          │
                    controlos, moedas, DIPs
```

Repare em duas coisas que não são óbvias:

**O 68000 não vê os controlos nem os DIP switches directamente.** Os controlos passam pelo
C-Chip; os DIP switches são lidos pelo *YM2203* e chegam ao 68000 pela mão do Z80 — e
chegam **complementados**, porque `snd_read_dipswitches` faz `not.b` antes de os guardar.

**O jogo corre quase todo dentro do IRQ de VBLANK.** O laço principal em `$00161C` tem duas
instruções. Tudo o resto acontece uma vez por frame, dentro do handler.

## O que está feito

| | |
|---|---|
| Rotinas do 68000 identificadas | 1774 |
| …com nome humano | 1480 (83%) |
| Variáveis globais nomeadas | 577 |
| Cobertura da zona de código | 98,4% classificada |
| Ficheiros `.asm` por subsistema | 152 |
| Testes | 300 |

## O que não está feito

Uma lista honesta é mais útil do que uma barra de progresso. Cada documento tem a sua
secção *O que não sabemos*; estes são os buracos que atravessam o projecto todo:

1. **A ROM interna de 4 KB do C-Chip não está dumpada.** É a lacuna irredutível: os vectores
   de interrupção, a tabela CALT e a página CALF do uPD78C11 não existem neste conjunto.
   Ver [04](04-c-chip.md).
2. **Não há assemblador instalado.** A listagem foi verificada byte a byte contra a ROM e
   nenhum operando tem sintaxe impossível, mas *remontar e comparar* — a prova definitiva —
   continua por fazer. Ver [08](08-ferramentas-e-reproducao.md).
3. ~~A paleta não é conhecida em repouso.~~ **RESOLVIDO.** A paleta é de facto RAM
   (`$500000`), mas os valores que o jogo lá escreve estão gravados na ROM em `$0RGB` de 4
   bits e são expandidos por `pal_rgb444_to_xbgr555` (`$001042`). As 19 tabelas foram
   extraídas e as 16 paletas de sprite reconstruídas — ver
   [03 — Vídeo](03-video.md) e `tools/palette_extract.py`. Os PNGs em `assets/` usam agora
   as cores verdadeiras, com proveniência por pen em `assets/manifest.json`.
4. **O bit 7 de `$D00000`.** O MAME devolve `$60` fixo; a ROM testa esse bit em 20 sítios,
   todos em código de chefe. Só a placa real responde.
5. **A polaridade do bit de *cabinet*** contradiz o que o macro genérico do MAME documenta.
   Ver a discussão em [01](01-hardware.md).

## Como estes documentos foram escritos

Todo o endereço citado foi verificado contra a listagem ou contra `build/maincpu.bin`.
Um teste automático (`tools/tests/test_docs_consistency.py`) confirma que nenhum
identificador citado é inventado e que nenhum link relativo está morto — foi assim que se
descobriu que `fm_fnum_table` era usada na documentação sem nunca ter sido declarada.

Onde há dúvida, está escrito que há dúvida. Onde há conjectura, está marcada como
conjectura. Um projecto de engenharia inversa que confunde as duas coisas é pior do que
nenhum, porque quem vier a seguir constrói em cima do erro.
