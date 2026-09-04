# 02 — Mapa de memória

Volfied tem três processadores e três espaços de endereçamento independentes. Só se tocam por
dois canais estreitos: o latch PC060HA (68000 ↔ Z80) e a janela de SRAM do C-Chip
(68000 ↔ uPD78C11). Este documento descreve os três mapas ao nível do que o **código faz** em
cada faixa, e não apenas do que o driver do MAME declara.

**Âmbito.** Este documento é sobre *espaço de endereços*: que faixas existem, como estão
descodificadas, em que faixa de bytes vive cada dispositivo, e o que é que o código escreve e lê
em cada uma. O funcionamento interno dos dispositivos e os algoritmos que usam estes endereços
estão noutros ficheiros:

| Para saber… | Ver |
|---|---|
| como o PC090OJ, o PC060HA e a paleta funcionam por dentro | [`docs/01-hardware.md`](01-hardware.md) |
| a semântica dos bits da word de VRAM, blitters, flip, cor | [`docs/03-video.md`](03-video.md) |
| o C-Chip como processador: arranque, tarefas, protecção | [`docs/04-c-chip.md`](04-c-chip.md) |
| o driver de som do Z80 e o formato das sequências | [`docs/05-som.md`](05-som.md) |
| as máquinas de estado e o motor de preenchimento | [`docs/06-gameplay.md`](06-gameplay.md) |
| o texto por sprites, a fonte e a tabela de mensagens | [`docs/07-texto-e-fonte.md`](07-texto-e-fonte.md) |
| como regenerar as listagens e os símbolos | [`docs/08-ferramentas-e-reproducao.md`](08-ferramentas-e-reproducao.md) |

O que fica **aqui e só aqui**: as três tabelas de endereços, a tabela de vetores de excepção do
68000 com os 11 vetores `$0011xxxx`, e o mapa da RAM `$100000-$103FFF` reconstruído a partir das
577 entradas `RAMVAR` de [`symbols/main68k.sym`](../symbols/main68k.sym).

**Método.** As faixas vêm de
[`reference/HARDWARE_GROUND_TRUTH.md`](../reference/HARDWARE_GROUND_TRUTH.md), que por sua vez vem
de `reference/mame/volfied.cpp`. Tudo o que aqui se diz sobre *uso* foi lido em
`src/main68k/*.asm`, `src/sound_z80/sound.asm` e `src/cchip/cchip.asm`, ou medido sobre
`build/*.bin` com o Python do projecto. Onde o código sozinho não chega, o comportamento do
dispositivo foi conferido contra `reference/mame/` — e nesses casos digo-o, porque «o MAME faz X»
e «a placa faz X» não são a mesma afirmação.

---

## 0. Convenções

- `$` = hexadecimal. Endereços do 68000 com 6 dígitos; do Z80 e do uPD78C11 com 4.
- Os excertos de código são copiados da listagem gerada em `src/`, retirando só a coluna final
  com os bytes crus quando não é ela que está em causa.
- **Faixas de byte.** Onde o mapa do MAME diz `umask16(0x00ff)`, o dispositivo está ligado a
  D7–D0. Num 68000 big-endian isso é o byte **ímpar** de cada word. As consequências não são
  cosméticas:
  - `move.w` num endereço par **funciona**: afirma /UDS e /LDS, e o dispositivo entrega ou recebe
    a metade baixa da word. O jogo usa isto constantemente (§3.10).
  - `move.b` num endereço **ímpar** funciona: afirma /LDS.
  - `move.b` num endereço **par** afirma só /UDS e **não chega ao dispositivo**. Há exactamente um
    sítio no jogo onde isto acontece (§3.10).
- Quando escrevo «não há referência», quero dizer *não há referência absoluta nem relativa a A5 na
  listagem desmontada*. Acesso indirecto por um registo de endereço calculado não é detectável
  assim, e portanto nunca declaro uma zona morta só com base nisso.
- Tamanhos de variável vêm do campo de tamanho das entradas `RAMVAR`, que é **anotação humana**,
  não medição. Onde detectei um tamanho declarado a mais, digo-o (anexo).

---

## 1. MC68000 — o espaço de endereços

### 1.1 O mapa

O 68000 corre a 8 MHz (32 MHz ÷ 4) e tem 24 linhas de endereço. O que está descodificado:

| Faixa | Ac. | Faixa de bytes | O que é | O que o código lá faz |
|---|---|---|---|---|
| `$000000–$03FFFF` | R | word | ROM de programa, 256 KB | vetores, código, tabelas, dados |
| `$040000–$07FFFF` | — | — | **não descodificado** | nenhum acesso |
| `$080000–$0FFFFF` | R | word | ROM de tiles 8×8, 512 KB | lida **só** pelos blitters da camada bitmap |
| `$100000–$103FFF` | RW | word | RAM principal, 16 KB | **A5 = `$100000`**; tudo o que é global vive aqui |
| `$104000–$1FFFFF` | ? | — | ver §8.1 | nenhum acesso deliberado |
| `$200000–$203FFF` | RW | word | PC090OJ, RAM de sprites, 16 KB | só `$200000–$2007FF` é desenhado; `$201BFE` é registo |
| `$400000–$47FFFF` | RW | word | VRAM da camada bitmap, 512 KB | 2 páginas de 256 KB, uma por jogador; **escrita mascarada** |
| `$500000–$503FFF` | RW | word | Paleta, 8192 × xBGR_555 | bitmap em `$500000–$501FFF`, sprites em `$502000–$503FFF` |
| `$600000–$600001` | W | word | `video_mask` | 15 escritas, só três valores distintos |
| `$700000–$700001` | W | word (escrito com `move.b` em `$700001`) | PC090OJ `sprite_ctrl` | 7 escritas, todas com lixo — na prática um strobe |
| `$D00000–$D00001` | RW | word | W: `video_ctrl` · R: estado de colisão | escreve bits 0/3/6/7; lê bits 5/6/7 |
| `$E00001` | W | byte ímpar | PC060HA `master_port_w` | selector de modo; o jogo só escreve 0 (dados) e 4 (estado/reset) |
| `$E00003` | RW | byte ímpar | PC060HA `master_comm_r/w` | nibbles de/para o Z80 |
| `$F00000–$F007FF` | RW | byte ímpar | C-Chip: janela de 1 KB na SRAM partilhada | entradas, comandos, dados de ronda |
| `$F00800–$F00FFF` | RW | byte ímpar | C-Chip: região da ASIC | `$F00803` = estado, `$F00C01` = banco |
| `$F01000–$FFFFFF` | — | — | **não descodificado** | — |

Duas notas de arrumação:

- A **ROM de sprites** (região `pc090oj`, 768 KB) não está no espaço de endereços de nenhuma CPU.
  O PC090OJ lê-a pelos seus próprios pinos; o 68000 nunca a vê. As duas PROMs também não estão
  mapeadas.
- A coluna «Ac.» corrige o ground truth em dois pontos. A VRAM e a paleta lá aparecem como `W`,
  mas ambas são `.ram()` no MAME e **lêem-se normalmente**. A prova está no próprio jogo: o
  auto-teste escreve e relê `$FFFFFFFF` em toda a VRAM (§3.5), e o motor de preenchimento decide
  o que fazer lendo words de VRAM. O que é write-only é o *registo* `$D00000`, cuja leitura é
  outra coisa.

As constantes com estes nomes estão em
[`src/main68k/hardware.inc`](../src/main68k/hardware.inc), gerado a partir do mapa; é por isso que
a listagem diz `VIDEO_MASK` e não `$00600000`.

### 1.2 Nada acede fora do mapa

Varri a coluna de instrução de toda a listagem (`src/main68k/*.asm`, ignorando a coluna de endereço
e os comentários) à procura de constantes de 5 a 8 dígitos hexadecimais fora das faixas da tabela.
Aparecem 23 valores distintos, e **nenhum é um endereço que o código use**:

| Valor | Ocorr. | O que é |
|---|---|---|
| `$0011xxxx` (11 valores) | 11 | os `dc.l` dos vetores de excepção — dados, não código alcançável (§2.2) |
| `$00104000` | 1 | `cmpa.l #$104000,a0` — limite exclusivo do ciclo de teste da RAM |
| `$00480000` | 1 | `cmpa.l #$480000,a0` — limite exclusivo do ciclo de teste da VRAM |
| `$00040000` | 5 | escrito como `VRAM+$40000`: o deslocamento da segunda página, não um endereço |
| `$001E001E` `$00300002` `$01480002` `$02010201` `$03D003D0` `$04000000` `$48484848` `$7BDE7BDE` `$FFFFFFFF` | 43 | imediatos de dados (`move.l`, `ori.l`, máscaras, padrões de teste) |

Ou seja: o 68000 nunca endereça deliberadamente `$040000-$07FFFF`, `$104000-$1FFFFF`,
`$204000-$3FFFFF`, `$480000-$4FFFFF`, `$504000-$5FFFFF`, `$600002-$6FFFFF`, `$700002-$CFFFFF`,
`$D00002-$DFFFFF`, `$E00004-$EFFFFF` nem `$F01000-$FFFFFF`. As duas únicas constantes que *parecem*
endereços fora do mapa — `$104000` e `$480000` — são limites de comparação, e o acesso pára antes
de lá chegar.

### 1.3 Interrupções

Só existe **uma** fonte de interrupção: o VBLANK, no **nível 4**, autovetorizado (vetor 28,
`$000070` → `$000400`). O mesmo VBLANK levanta `ext_interrupt` no C-Chip, que lá dentro é a
`/INT1` do uPD78C11.

```
irq4_vblank_handler:
        ori.w   #$F00,sr                        ; $000400
        movem.l d0-d7/a0-a4/a6,-(a7)            ; $000404
        move.b  d0,SPRITE_CTRL_B                ; $000408
        jsr     (vblank_service).l              ; $00040E
        move.w  VIDEO_CTRL,$5A(a5)              ; $000414  g_collision_status
```

O `ori.w #$F00,sr` põe a máscara em 7 logo à entrada — o handler não é reentrante e não precisa de
ser: não há outra interrupção. Os 14 registos guardados (`d0-d7/a0-a4/a6`, 56 bytes) mais os 6
bytes do frame de excepção dão 62 bytes de pilha só para entrar.

O que o handler despacha, e as três máquinas de estado, estão em
[`docs/06-gameplay.md`](06-gameplay.md); o ritmo do frame
está em [`docs/01-hardware.md`](01-hardware.md).

### 1.4 Reset, e a limpeza da RAM

```
reset_entry:
        move.w  #$0,VIDEO_CTRL                  ; $0014B8
        move.w  #$FFFF,VIDEO_MASK               ; $0014C0
        lea.l   g_base,a5                       ; $0014C8  A5 = $100000
        lea.l   g_base,a0                       ; $0014CE
        lea.l   g_coin1_credits,a1              ; $0014D4  a1 = $100002
        move.w  #$0,(a0)                        ; $0014DA
        move.w  #$1FFF,d0                       ; $0014DE
loc_0014E2:
        move.w  (a0)+,(a1)+                     ; $0014E2
        subq.w  #$1,d0                          ; $0014E4
        bne.b   loc_0014E2                      ; $0014E6
```

É o idioma clássico de limpar por propagação: zera a primeira word e copia-a para a frente. A
conta fecha exactamente na RAM: uma word em `$100000` mais 8191 words copiadas para
`$100002…$103FFE` = 8192 words = 16 384 bytes. **Toda** a RAM principal fica a zero, incluindo o
espaço da pilha.

Note-se que `lea $100000.l,a5` aparece duas vezes no reset (`$0014C8` para A5, `$0014CE` para a0):
`$100000` é ao mesmo tempo a base de A5 *e* um campo de dados real (`g_coin1_needed`, §4.4.1).

Os passos seguintes do reset fixam a ordem de arranque dos três subsistemas: primeiro o Z80
(`SOUND_PORT=4` + `SOUND_COMM=1` seguido de `SOUND_COMM=0` — a transição alto→baixo que solta o
reset), depois a paleta, depois o handshake do C-Chip, depois o apagamento das duas páginas de
VRAM. O laço principal em `$00161C` é literalmente

```
loc_00161C:
        bsr.w   vram_deferred_cmd_dispatch      ; $00161C
        bra.b   loc_00161C                      ; $001620
```

— tudo o resto corre a partir da IRQ.

---

## 2. A tabela de vetores de excepção

`$000000-$0000FF`, 64 vetores de 4 bytes. Dumpei-a directamente de `build/maincpu.bin`; o que se
segue é o conteúdo real, não uma leitura da listagem.

### 2.1 A tabela completa

| Vetor | Endereço | Conteúdo | Significado |
|---|---|---|---|
| 0 | `$000000` | `$00103FFE` | SSP inicial — dois bytes abaixo do topo da RAM |
| 1 | `$000004` | `$000014B8` | PC inicial (`reset_entry`) |
| 2 | `$000008` | `$001100CC` | bus error → **lixo do sistema de desenvolvimento** |
| 3 | `$00000C` | `$001100E8` | address error → idem |
| 4 | `$000010` | `$00110108` | instrução ilegal → idem |
| 5 | `$000014` | `$00110130` | divisão por zero → idem |
| 6 | `$000018` | `$00110150` | CHK → idem |
| 7 | `$00001C` | `$00110174` | TRAPV → idem |
| 8 | `$000020` | `$0011019A` | violação de privilégio → idem |
| 9 | `$000024` | `$001101C4` | trace → idem |
| 10 | `$000028` | `$001101DE` | linha-A (emulador 1010) → idem |
| 11 | `$00002C` | `$00110202` | linha-F (emulador 1111) → idem |
| 12–23 | `$000030–$00005F` | `$FFFFFFFF` | reservados — EPROM apagada |
| 24 | `$000060` | `$FFFFFFFF` | interrupção espúria — EPROM apagada |
| 25 | `$000064` | `$00000000` | autovetor IRQ 1 — não usado |
| 26 | `$000068` | `$00000000` | autovetor IRQ 2 — não usado |
| 27 | `$00006C` | `$00000000` | autovetor IRQ 3 — não usado |
| **28** | **`$000070`** | **`$00000400`** | **autovetor IRQ 4 — o VBLANK, o único IRQ do jogo** |
| 29 | `$000074` | `$00000000` | autovetor IRQ 5 — não usado |
| 30 | `$000078` | `$00000000` | autovetor IRQ 6 — não usado |
| 31 | `$00007C` | `$FFFFFFFF` | autovetor IRQ 7 (não mascarável) — EPROM apagada |
| 32–46 | `$000080–$0000BB` | `$00000000` | TRAP #0 a TRAP #14 — não usados |
| **47** | **`$0000BC`** | **`$001100B8`** | **TRAP #15 → lixo do sistema de desenvolvimento** |
| 48–63 | `$0000C0–$0000FF` | `$FFFFFFFF` | não atribuídos — EPROM apagada |

Duas precisões face ao ground truth, que agrupa os valores de forma mais grosseira: o vetor **31**
(autovetor de nível 7) vale `$FFFFFFFF`, não `$00000000` — ele não está no grupo dos IRQ não
usados; e o preenchimento `$FF` começa em `$0000C0`, não em `$000100`, porque os vetores 48–63 já
são EPROM apagada. Medido:

```
FF $0000C0-$0003FF (832 bytes)
```

### 2.2 Os 11 vetores `$0011xxxx`

Onze vetores apontam para `$0011xxxx`. **`$110000` não existe neste espaço de endereços**: a RAM
acaba em `$103FFF` e a faixa `$104000-$1FFFFF` não está descodificada.

| Ordem no destino | Valor | Vetor | Delta para o seguinte |
|---|---|---|---|
| 1 | `$1100B8` | 47 — TRAP #15 | 20 bytes |
| 2 | `$1100CC` | 2 — bus error | 28 |
| 3 | `$1100E8` | 3 — address error | 32 |
| 4 | `$110108` | 4 — instrução ilegal | 40 |
| 5 | `$110130` | 5 — divisão por zero | 32 |
| 6 | `$110150` | 6 — CHK | 36 |
| 7 | `$110174` | 7 — TRAPV | 38 |
| 8 | `$11019A` | 8 — violação de privilégio | 42 |
| 9 | `$1101C4` | 9 — trace | 26 |
| 10 | `$1101DE` | 10 — linha-A | 36 |
| 11 | `$110202` | 11 — linha-F | — |

O que é **facto medido**: os onze valores são estritamente crescentes quando ordenados, começam em
`$1100B8` e acabam em `$110202`, cobrem 330 bytes, e os intervalos entre eles vão de 20 a 42
bytes. TRAP #15 fica *antes* do bus error, ou seja a ordem no destino não é a ordem na tabela.

O que é **interpretação**: isto tem a forma de uma tabela de handlers de um monitor residente —
onze rotinas curtas e de tamanho parecido, cada uma provavelmente a guardar o contexto e a
imprimir qual foi a excepção. A Taito ligava a placa de desenvolvimento com RAM em `$110000`, e ao
gravar a EPROM final os vetores ficaram como estavam. Não é código a desmontar: **os destinos não
existem nesta placa**. Quem tentar seguir `$1100CC` na listagem não encontra nada porque não há lá
nada.

O que **acontece se uma destas excepções disparar** é uma cadeia previsível, mas não verificada:
o 68000 salta para `$1100CC`, o barramento não é reclamado por ninguém, a leitura provavelmente
devolve `$FFFF` (linhas em alta), `$FFFF` é um opcode de linha-F, que gera a excepção 11, que
salta para `$110202`, e assim por diante até a pilha crescer para dentro dos dados ou o /DTACK
nunca chegar. De uma forma ou de outra a máquina fica inútil. **Não observei isto**: nem em
emulação (o MAME devolve o que devolve para acessos não mapeados) nem em hardware.

Vale a pena reparar que **o jogo não depende de nenhuma destas excepções**. Ele não usa TRAPs, não
usa CHK, não corre em modo utilizador (portanto não há violação de privilégio), e o único
`divu.w` do motor de percentagem divide por `#$3F`, uma constante. Os vetores são inertes desde
que o código esteja correcto — que é exactamente porque ninguém reparou neles antes de gravar.

Há outros restos do mesmo sistema de desenvolvimento espalhados pela ROM, documentados noutros
sítios: o gravador de demos que escreve para ROM, o editor de inimigos, o editor de objectos, e um
`bra.b *` de assert. Ver
[`docs/ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md).

### 2.3 Uma armadilha de leitura na listagem

Na listagem gerada, os 20 vetores que valem `$00000000` aparecem assim:

```
vector_25_irq1_autovector:
        dc.l    vector_00_initial_ssp   ; irq1_autovector       $000064
```

`vector_00_initial_ssp` é o símbolo do endereço `$000000`. O substituidor de símbolos viu o valor
`$00000000` e pôs-lhe o nome do que está lá. **Não é um ponteiro para o vetor 0**; é um zero. O
mesmo vale para os vetores 26, 27, 29, 30 e 32–46.

O reinício por software depois do TILT, esse, usa mesmo os vetores como dados:

```
loc_000E3A:
        movea.l (vector_00_initial_ssp).w,a7     ; $000E3A  SSP <- $000000
        movea.l (vector_01_reset_pc).w,a0        ; $000E3E  PC  <- $000004
        jmp     (a0)                             ; $000E42
```

(`.w` = modo absoluto curto: `$0000` estendido com sinal.) Aqui os rótulos estão certos.

---

## 3. Detalhe por faixa (68000)

### 3.1 ROM de programa — `$000000–$03FFFF`

Segmentação medida sobre `build/maincpu.bin` (blocos de `$FF` com 256 bytes ou mais):

| Faixa | Bytes | Conteúdo |
|---|---|---|
| `$000000–$0000BF` | 192 | vetores 0–47 (o preenchimento `$FF` começa no vetor 48) |
| `$0000C0–$0003FF` | 832 | `$FF` (vetores 48–63 + espaço até ao handler) |
| `$000400–$029B2C` | 169 773 | **código e dados entrelaçados**, contíguos, sem um único `$FF` de 256 bytes |
| `$029B2D–$02FFFF` | 25 811 | `$FF` |
| `$030000–$039D86` | 40 327 | listas de tiles e de posição dos meta-sprites, descritores de quadro, dados de sprite do tiro do jogador (`$038CE6`) e os quatro guiões de demo (`$039252`) |
| `$039D87–$03FFBD` | 25 143 | `$FF` |
| `$03FFBE–$03FFFD` | 64 | as quatro tabelas de moedas |
| `$03FFFE–$03FFFF` | 2 | word de região = `$0003` (Mundo) |

O último byte diferente de `$FF` antes do buraco é `$029B2C` — o ground truth arredonda para
`$029BFF`. A cobertura da zona `$000400-$029BFF` está em
[`build/m68k_stats.txt`](../build/m68k_stats.txt): 98,4 % classificada, 55,2 % código.

As **tabelas de moedas** em `$03FFBE` merecem nota porque o ground truth as dá como zona de `$FF`.
São quatro blocos de 16 bytes, cada um com 4 longs `(moedas necessárias .w, créditos dados .w)`:

```
$03FFBE: 00 02 00 03  00 02 00 01  00 01 00 02  00 01 00 01   ranhura 1, Japão
$03FFCE: 00 02 00 03  00 02 00 01  00 01 00 02  00 01 00 01   ranhura 2, Japão
$03FFDE: 00 04 00 01  00 03 00 01  00 02 00 01  00 01 00 01   ranhura 1, resto
$03FFEE: 00 01 00 06  00 01 00 04  00 01 00 03  00 01 00 02   ranhura 2, resto
```

`coinage_setup` (`$00666A`) escolhe o bloco pela word de região e a entrada por
`(~DSWA & $30) >> 2` e `(~DSWA & $C0) >> 4`, e copia os dois longs para `$100000` e `$100004`. Os
valores do bloco «resto» são exactamente `TAITO_COINAGE_WORLD` do MAME: 4/1, 3/1, 2/1, 1/1 na
moeda A e 1/6, 1/4, 1/3, 1/2 na moeda B. Se a região for `$0002` (EUA), o segundo long é
sobreposto pelo primeiro (`$0066BE`).

### 3.2 ROM de tiles — `$080000–$0FFFFF`

Endereçada **só** pelos quatro blitters da camada bitmap, e sempre com a mesma conta:

```
        move.w  (a3)+,d0                ; código do tile
        lsl.l   #$5,d0                  ; × 32
        addi.l  #TILE_ROM,d0            ; + $080000
```

32 bytes por tile = 8×8 pixels a 4 bpp. Os quatro sítios são `$007082`, `$0070D6`, `$0072C0` e
`$00731C` (variantes normal/espelhada × imagem A/imagem B); ver
[`src/main68k/vram_tilemap_blit.asm`](../src/main68k/vram_tilemap_blit.asm) e
[`docs/03-video.md`](03-video.md).

Conteúdo medido:

| Faixa | O que é |
|---|---|
| `$080000–$0BFB3F` | tiles 0–8153, do par `c04-20.7` / `c04-22.9` |
| `$0BFB40–$0BFFFF` | 1216 bytes de `$FF` — tiles 8154–8191, a cauda por usar do primeiro par |
| `$0C0000–$0F817F` | tiles 8192–15371, do par `c04-19.6` / `c04-21.8` |
| `$0F8180–$0FFFFF` | 32 384 bytes de `$FF` |

Os índices de tile vão portanto de 0 a 15 371, dos quais 38 (8154 a 8191) estão vazios — 15 334
com conteúdo. O buraco cai exactamente na fronteira entre os dois pares de EPROMs: o primeiro par
não foi enchido até ao fim. (O ground truth arredonda o buraco para
`$0BFC00-$0BFFFF` e o fim para `$0F81FF`; as fronteiras exactas são as de cima.)

### 3.3 RAM de sprites — `$200000–$203FFF`

O PC090OJ expõe 16 KB, mas **só os primeiros 2 KB são desenhados**: em `pc090oj.cpp`,
`PC090OJ_ACTIVE_RAM_SIZE = 0x800`, percorridos de 4 em 4 words. São **256 sprites de 8 bytes** em
`$200000–$2007FF`.

Todas as referências absolutas da listagem confirmam-no: há 54 offsets distintos, e o maior abaixo
de `$800` é `$778`. Há **uma** excepção, `$201BFE`:

```
        move.w  #$1,SPRITE_RAM+$1BFE    ; $000EDE  orientação normal
        move.w  #$0,SPRITE_RAM+$1BFE    ; $000EF2  ecrã invertido
```

`$1BFE` é o *word offset* `$DFF`, e em `pc090oj.cpp` `word_w` tem um caso especial:
`if (offset == 0xdff) m_ctrl = data;` com «bit 0 is flip control». É o registo de flip do gerador
de sprites, escondido dentro da janela de RAM — quem procurar um registo de flip em `$700000` não
o encontra. Os dois escritores são os dois ramos de `spr_set_screen_flip` (`$000EB6`), sempre em
uníssono com `g_screen_noflip` (`$100030`).

Os 13,5 KB entre `$200800` e `$203FFF` (tirando `$201BFE`) não são referenciados em lado nenhum.

O particionamento dos 2 KB úteis **muda com o modo de jogo**, e por isso não há um mapa único:

| Rotina | Faixa que toca | Quando |
|---|---|---|
| `spr_clear_all_and_seed_row` (`$000F1A`) | enche `$200000–$20077F` com o long `$00000100`, depois semeia slots a partir de `$200778` | reset |
| `spr_clear_text_area` (`$000E9A`) | enche `$200000–$20064F` | mudanças de ecrã |
| `spr_flush_shadow` (`$014752`) | copia `$300` bytes de `$102350` para `$200180–$20047F` (96 sprites) | por frame, em jogo |
| `txt_render_line_sprites` (`$015696`) | anel de escrita que dá a volta em `$200600` de volta a `$200000` (192 slots) | sequência final |
| `spr_clear_to_end` (`$0145D0`) | enche de a3 até `$200730` com o long `$00000180` | modo de teste |

O valor `$180` no word Y é a convenção de «esconder» usada em toda a ROM. Detalhes do registo de
8 bytes e da emissão de sprites em
[`docs/03-video.md`](03-video.md).

### 3.4 VRAM — `$400000–$47FFFF`

512 KB = **duas páginas de 256 KB**, e o jogo usa uma por jogador (não é double buffering):
`$10006A` guarda `$400000` ou `$440000`, e o bit 0 de `video_ctrl` diz ao hardware qual mostrar.

A aritmética está fixada por `vram_addr_from_xy` (`$004F7E`):

```
        movea.l $6A(a5),a0              ; base da página
        lsl.l   #$1,d2                  ; x × 2
        lsl.l   #$8,d3
        lsl.l   #$2,d3                  ; y × 1024
        or.l    d3,d2
        adda.l  d2,a0
```

Logo: **1 word por pixel, 512 words (`$400` bytes) por linha, 256 linhas, `$40000` bytes por
página**. A inversa, `vram_xy_from_offset` (`$004F66`), mascara com `$0003FFFE` — 18 bits — o que
confirma a página de 256 KB pelo lado oposto.

As duas páginas são apagadas separadamente, com `d1 = 0` a dar 65 536 iterações no
`util_fill_longs`:

```
vram_clear_page0:
        lea.l   VRAM,a0                 ; $00148C  $400000
        ...
vram_clear_page1:
        lea.l   VRAM+$40000,a0          ; $0014A2  $440000
```

65 536 longs = 256 KB cada — exactamente uma página, sem sobra.

**A escrita é mascarada, a leitura não.** Em `volfied.cpp`:

```c
void volfied_state::video_ram_w(offs_t offset, uint16_t data, uint16_t mem_mask)
{
    mem_mask &= m_video_mask;
    COMBINE_DATA(&m_video_ram[offset]);
}
```

Só os bits presentes em `video_mask` são alterados. O significado dos bits da word está em
[`docs/03-video.md`](03-video.md).

Uma armadilha de leitura que se paga cara: o código manipula bits de VRAM com `bset.b`/`btst.b`
sobre **bytes**. Em `vram_mark_object_block` (`$004F42`),

```
        bset.b  #$7,(a0)                ; bit 15 da word
        bset.b  #$0,(a0)                ; bit  8 da word
```

`(a0)` é o byte **par**, ou seja o byte alto. Bit 7 do byte alto = bit 15 da word; bit 0 do byte
alto = bit 8. O `adda.w #$3E2,a0` do fim do ciclo é `$400 − 15×2`, o passo de linha menos o que já
se andou.

### 3.5 Verificação: o auto-teste prova a leitura

```
loc_013EF0:
        movea.l #g_base,a0              ; $013EF0  $100000
        move.l  #$FFFFFFFF,d2
loc_013F04:
        cmpa.l  #$104000,a0
        beq.b   loc_013F16
        move.l  d2,(a0)
        move.l  (a0)+,d3
        cmp.l   d2,d3
        bne.b   loc_013F2E              ; "RAM CHECK ERROR" + bra *
        bra.b   loc_013F04
loc_013F16:
        movea.l #VRAM,a0                ; $013F16  $400000
loc_013F1C:
        cmpa.l  #$480000,a0
        ...
```

O teste escreve e relê longs em `$100000–$103FFF` e depois em `$400000–$47FFFF`. Escrever
`$FFFFFFFF` na RAM principal destrói os DIPs guardados, e é por isso que d4/d5 os salvam em
`$013EFC`/`$013F00` e os repõem em `$013F46`.

O teste de ROM que vem antes está morto: `selftest_rom_checksum` (`$013EC2`) soma os longs de
`$000000–$00FFFF` em d2 — só 64 KB dos 256 KB — e **nunca compara d2 com nada**, saltando sempre
para o teste de RAM. `selftest_rom_error_halt` (`$013ED8`) é inalcançável.

### 3.6 Paleta — `$500000–$503FFF`

8192 entradas de 16 bits em formato xBGR_555. O mapa vem do cálculo de cor do MAME, não de uma
convenção nossa: a camada bitmap escreve directamente um índice de 0 a `$FFF` no bitmap, e os
sprites usam `sprite_colbank = 0x100 | ((sprite_ctrl & 0x3c) << 2)` combinado com 4 bits de cor,
o que dá grupos `$100–$1FF` × 16 pens = entradas `$1000–$1FFF`.

| Bytes | Entradas | Uso |
|---|---|---|
| `$500000–$500FFF` | `$000–$7FF` | camada bitmap, imagem A (bit 15 da word de VRAM = 0) |
| `$501000–$501FFF` | `$800–$FFF` | camada bitmap, imagem B (bit 15 = 1) |
| `$502000–$503FFF` | `$1000–$1FFF` | sprites, 16 bancos de cor de 256 entradas |

A estrutura de 16 bancos aparece directamente no código, e é a consequência mais visível de
`sprite_ctrl` nunca ser programado (§3.8):

```
pal_init_all:
        lea.l   PALETTE+$2000,a1        ; $000FD6
        moveq   #$10,d7                 ; 16 vezes
loc_000FDE:
        movea.l a1,a0
        move.w  #$D0,d3
        lea.l   (off_00113A).l,a3
        bsr.w   pal_expand_run
        adda.w  #$200,a1                ; passo de $200 bytes = 256 entradas
        subq.w  #$1,d7
        bne.b   loc_000FDE
```

`$200` bytes = 256 entradas = 16 grupos de cor = exactamente um degrau de `sprite_colbank`. O
mesmo padrão aparece em `pal_load_round_from_cchip` (`$015C94`), que faz 16 iterações com um
avanço total de `$A0 + $160 = $200` por volta.

### 3.7 `$600000` — `video_mask`

Quinze escritas em toda a ROM, e só **três valores**:

| Valor | Vezes | Efeito |
|---|---|---|
| `$000F` | 5 | só o nibble da imagem A (bits 0–3) é alterado |
| `$FFF0` | 5 | tudo menos a imagem A |
| `$FFFF` | 5 | escrita normal |

Os cinco tercetos formam sempre a mesma sequência (`$000F` → desenhar → `$FFF0` → desenhar →
`$FFFF`), que é o protocolo de transição de ecrã descrito em
[`docs/03-video.md`](03-video.md). O reset põe `$FFFF`
em `$0014C0` antes de mais nada.

### 3.8 `$700000` — `sprite_ctrl`, que nunca é programado

Sete escritas, **todas** com a mesma forma:

```
        move.b  d0,SPRITE_CTRL_B        ; $000408, $00153A, $00154E, $001558,
                                        ; $001568, $013FA8, $01438E
```

Nunca há um `move.b #imm` nem um cálculo prévio de d0. A escrita de `$000408` está no VBLANK,
logo a seguir ao `movem`, ou seja o d0 que lá vai é o d0 do **código interrompido**. As outras
seis estão em pontos de espera do reset e do modo de teste, sempre com um d0 herdado.

Consequência: o valor em `sprite_ctrl`, e portanto o banco de cor dos sprites, é indeterminado. O
jogo compensa por força bruta — replica as cores de sprite pelos 16 bancos possíveis (§3.6). Não
determinei que valor chega ao chip num acesso de byte a `$700001` (a função `sprite_ctrl_w` recebe
uma word); só que a origem é lixo. A hipótese de isto ser um kick de watchdog está em §8.6.

### 3.9 `$D00000` — dois registos no mesmo endereço

**Escrita** (`video_ctrl`): cinco instruções em toda a ROM.

| Onde | O que faz |
|---|---|
| `$0014B8` | `move.w #$0,VIDEO_CTRL` — limpa tudo, primeira instrução do reset |
| `$0014F8` | `bset.b #$7,VIDEO_CTRL_B` — põe o bit 7; a sombra fica `$0080` |
| `$001456` / `$001460` | `vram_ctrl_strobe`: limpa os bits 3 e 6 (`andi #$FFB7`) e volta a pô-los (`ori #$48`) |
| `$00147A` | `vram_select_page`: bit 0 = jogador activo |

Como o registo é write-only, o jogo mantém a sombra `g_video_ctrl_shadow` (`$100028`) e faz
read-modify-write sobre ela. Os bits usados são portanto **0, 3, 6 e 7**. O `bset.b` de `$0014F8` é
o caso desconfortável: é um read-modify-write feito pelo 68000 sobre um endereço cuja *leitura* é o
registo de colisão. O que fica lá é o que a leitura devolveu com o bit 7 posto — no MAME `$60 |
$80 = $E0`, na placa o que for.

**Leitura** (estado de colisão): há **uma** leitura em toda a ROM, no VBLANK, e 25 consumidores do
byte baixo:

```
        move.w  VIDEO_CTRL,$5A(a5)      ; $000414
```

| Bit testado | Vezes | Onde |
|---|---|---|
| 5 | 2 | teste de toque em inimigo pequeno |
| 6 | 3 | teste de toque em inimigo grande / na trilha |
| 7 | 20 | código de chefe; nos sítios que segui, inibe uma mudança de tamanho (§8.3) |

O MAME devolve `$0060` fixo. Isso significa que em emulação os bits 5 e 6 estão sempre a 1 (e o
software fia-se noutro teste para decidir se acredita) e o **bit 7 está sempre a 0**. Os 20 sítios
que testam o bit 7 não têm todos a mesma polaridade — 13 seguem com `bne` e 7 com `beq` — pelo que
em emulação 13 saltos nunca são tomados e 7 são sempre tomados: **um dos dois lados de cada um
destes 20 ramos é código que o MAME nunca executa**. É a maior incógnita deste mapa; ver §8.3 e
[`docs/03-video.md`](03-video.md).

### 3.10 `$E00001` / `$E00003` — PC060HA

Dois bytes ímpares. `$E00001` selecciona o modo (o dispositivo aceita 0–4; o jogo só escreve 0 e
4), `$E00003` é o dado. O protocolo, do lado do 68000, é este:

```
snd_send_command:
        move.w  #$4,SOUND_PORT          ; $000490  modo 4 = registo de estado
        btst.b  #$0,SOUND_COMM_B        ; $000498  b0 = PORT01_FULL
        bne.b   snd_send_command
        move.w  #$0,SOUND_PORT          ; $0004A2  modo 0
        move.w  d0,SOUND_COMM           ; $0004AA  nibble BAIXO
        lsr.w   #$4,d0
        move.w  d0,SOUND_COMM           ; $0004B2  nibble ALTO
```

Repare-se em `move.w #$4,SOUND_PORT`, isto é uma escrita de **word** em `$E00000`, um endereço
par: afirma /UDS e /LDS, e o dispositivo, ligado a D7–D0, recebe a metade baixa. É a forma
idiomática de escrever num porto de byte ímpar sem calcular o endereço ímpar. `snd_read_dipswitches`
(`$007372`) faz o mesmo com um registo de base: `lea SOUND_PORT,a3` e depois `$2(a3)`/`$3(a3)`.

Os bits de estado que o jogo usa em `$E00003` no modo 4:

| Bit | Nome no MAME | Uso |
|---|---|---|
| 0 | `PORT01_FULL` | o Z80 ainda não consumiu o par de nibbles — esperar |
| 2 | `PORT01_FULL_MASTER` | o Z80 pôs uma resposta — pode ler |

O modo 4 também é o reset do Z80: `master_comm_w` no modo 4 faz `m_reset_cb(data ? ASSERT : CLEAR)`,
e é por isso que o reset do 68000 escreve 1 e depois 0 (`$0014F0`, `$001510`).

Só duas rotinas leem: `snd_read_reply_byte` (`$0004BA`) e a máquina de estados dos DIPs. Todo o
resto é envio. Detalhe do canal em
[`docs/01-hardware.md`](01-hardware.md) e do driver em
[`docs/05-som.md`](05-som.md).

### 3.11 `$F00000–$F00FFF` — a janela do C-Chip

Duas regiões, ambas em bytes ímpares:

| Faixa 68000 | Endereço no 78C11 | O que é |
|---|---|---|
| `$F00000–$F007FF` | `$1000–$13FF` | janela de **1 KB** num dos 8 bancos da SRAM de 8 KB |
| `$F00800–$F00BFF` | `$1400–$15FF` | 4 bytes de RAM da ASIC, espelhados (`offset & 3`) |
| `$F00C00–$F00C01` | `$1600` | selector de banco, **lado do 68000** |
| `$F00C02–$F00FFF` | `$1601–$17FF` | escrita cai na RAM da ASIC; leitura devolve `$00` |

A conversão é `68000 = $F00001 + 2 × (78C11 − $1000)` para a janela e
`68000 = $F00801 + 2 × (78C11 − $1400)` para a ASIC. Ou seja: **um byte do C-Chip ocupa dois bytes
de endereço do 68000**, e 2 KB de espaço de endereços dão 1 KB de dispositivo.

A prova de que a janela tem mesmo 1 KB está no próprio jogo:

```
cchip_clear_bank:
        lea.l   CCHIP_RAM+$1,a0         ; $00179E  $F00001
        move.w  #$3FF,d0                ; 1024 bytes
loc_0017A8:
        move.b  #$0,(a0)
        adda.l  #$2,a0                  ; passo 2
        dbra    d0,loc_0017A8
```

1024 iterações com passo 2 a começar em `$F00001` acabam em `$F007FF`. E `cchip_clear_all_banks`
(`$001712`) faz isto oito vezes, uma por banco, com três `nop` depois de cada mudança de banco.

**Os dois lados têm registos de banco separados** (`m_upd4464_bank` para o MCU, `m_upd4464_bank68`
para o 68000), ambos a começar no banco 0. Isto é essencial: os mesmos offsets significam coisas
diferentes consoante o banco, e a listagem mostra sempre os nomes do banco 0 (anexo).

Os offsets que o 68000 toca:

| 68000 | 78C11 | Papel (banco 0) | Instrução típica |
|---|---|---|---|
| `$F00001` `$F00003` `$F00005` | `$000`–`$002` | escritos com `$FD`/`$0F`/`$FF` no arranque — os mesmos valores que o C-Chip põe em `MA`/`MB`/`MC` (§6.2); ver [`04-c-chip.md`](04-c-chip.md) | `move.b #imm` |
| `$F00007` | `$003` | `PA` lida pelo C-Chip: START2/START1/SERVICE1 | `btst.b #n,CCHIP_PA` (modo de teste); `move.w CCHIP_RAM+$6,d0` (editor) |
| `$F00009` | `$004` | `PB`: COIN1/COIN2 | `btst.b #n,CCHIP_PB` (modo de teste) |
| `$F0000B` | `$005` | `PC`: TILT + joystick P1 + botão | `move.b CCHIP_PC,d0` (tilt, `$000E54`); `move.w CCHIP_RAM+$A,d0` (jogo) |
| `$F0000D` | `$006` | resultado do A/D: manete P2 em cocktail | `move.w CCHIP_RAM+$C,d1` (jogo); `btst.b` (modo de teste) |
| `$F00011` | `$008` | saída para `PB`: b4/b5 contadores, b6/b7 lockouts | `move.b $1E(a5),…` |
| `$F00015` `$F00017` `$F00019` | `$00A`–`$00C` | comando + 2 argumentos, no arranque | |
| `$F00021 + 6i` | `$010 + 3i` | tabela de ritmo de aparecimento (3 bytes por entrada) | |
| `$F00021…` | `$010…` | 160 bytes = 80 words de paleta da ronda | |
| `$F00047` | `$023` | índice de paleta da ronda | |
| `$F007FD` | `$3FE` | handshake dos dados da ronda | |
| `$F007FF` | `$3FF` | handshake da tabela de ritmo | |
| `$F00803` | ASIC `$401` | estado: b0 = pronto, b2 = erro; escrever 2 arranca o auto-teste | |
| `$F00C01` | ASIC `$600` | selector de banco | `move.b #N,CCHIP_BANK68` |

Repare-se em como o código lê os offsets pares:

```
        move.w  CCHIP_RAM+$A,d0         ; $004FBE  = $F0000A, PAR
```

`$F0000A` é par, mas é um acesso de **word**: /UDS e /LDS ambos afirmados, o byte do C-Chip
(offset `$005`) chega na metade baixa de d0. É o mesmo byte que um `move.b` a `$F0000B` traria.

**A excepção que não funciona.** Há um sítio, e só um, onde o jogo faz um acesso de **byte a um
endereço par** desta janela:

```
        move.b  d1,CCHIP_RAM            ; $001670  13c1 00f00000
```

`$F00000` é par. Com o dispositivo em D7–D0, esta escrita afirma só /UDS e não o selecciona — no
MAME o handler nem chega a ser chamado. O byte que devia lá ficar é o **desafio** que o C-Chip vai
ler em `$1000` do banco 1 para escolher a tabela de ritmo. Ver §8.14 para o que isto implica e o
que continua por verificar.

O ciclo completo desta janela, banco a banco, está em [`docs/04-c-chip.md`](04-c-chip.md).

---

## 4. A RAM principal — `$100000–$103FFF`

Esta é a secção que este documento existe para escrever. As 577 entradas `RAMVAR` de
[`symbols/main68k.sym`](../symbols/main68k.sym) cobrem 8118 dos 16 384 bytes (49,5 %) com nomes
individuais; com o bloco-guarda `g_work_ram` incluído, 90,2 %.

### 4.1 Estrutura macro

```
$100000  ┌────────────────────────────────────────────────┐
         │ $100000-$1002FF  estado permanente da máquina  │  NUNCA limpo em jogo
$100300  ├────────────────────────────────────────────────┤
         │ $100300-$103AFF  "work RAM", 14 336 bytes      │  limpo em bloco por
         │                                                │  util_clear_work_ram
$103B00  ├────────────────────────────────────────────────┤
         │ $103B00-$103FFD  pilha, 1278 bytes             │  cresce para baixo
$103FFE  ├────────────────────────────────────────────────┤  SSP inicial
         │ $103FFE-$103FFF  topo + g_data_out_byte        │
$104000  └────────────────────────────────────────────────┘
```

A fronteira em `$100300` não é uma convenção nossa: é o que a rotina de limpeza diz.

### 4.2 As duas limpezas

**No reset** (§1.4) limpa-se tudo, `$100000-$103FFF`.

**A cada mudança de ecrã ou de ronda** limpa-se só a partir de `$100300`:

```
util_clear_work_ram:
        clr.w   $300(a5)                ; $0005AC  $100300
        lea.l   $300(a5),a0             ; $0005B0
        lea.l   $302(a5),a1             ; $0005B4
        move.w  #$1BFF,d0               ; $0005B8  7167 words
        bsr.w   util_copy_words
```

Uma word em `$100300` mais 7167 copiadas para `$100302…$103AFE` = 7168 words = `$3800` bytes, ou
seja `$100300-$103AFF` exactamente. Chamada por `game_round_begin`,
`game_seq_reset_playfield` e `sub_0006D0`.

Duas consequências que valem por si:

1. Tudo o que tem de sobreviver a uma mudança de ronda — créditos, moedas, DIPs, recordes,
   contextos dos dois jogadores — **tem** de viver abaixo de `$100300`. E vive: as 91 variáveis de
   `$100000` a `$1002FF` são exactamente isso.
2. A limpeza pára em `$103AFF`, deixando 1280 bytes intactos por cima. É onde está a pilha. Não é
   coincidência: se a limpeza chegasse ao fim da RAM, apagaria os endereços de retorno da própria
   rotina que a está a fazer.

### 4.3 Mapa por subsistema

As 577 entradas, agrupadas. As contagens fecham nas 577.

| Faixa | Vars | Subsistema | Sobrevive à limpeza? |
|---|---|---|---|
| `$100000–$10001F` | 20 | moedas, créditos, contadores mecânicos, flancos de entrada | sim |
| `$100020–$10007F` | 39 | estado global do frame: máquina de estados, DIPs, sombra de vídeo, som, ponteiro de página | sim |
| `$100080–$1001FF` | 23 | os três contextos de jogador (P1, P2, activo) | sim |
| `$100200–$1002FF` | 9 | tabela de recordes e reprodução da demo | sim |
| `$100300–$1003FF` | 45 | variáveis de trabalho gerais: HUD, blitter, som, modo de teste | não |
| `$100800–$1008FF` | 73 | a estrutura do jogador (base de A4) | não |
| `$101000–$1020FF` | 37 | escalonador de tarefas, objectos, listas de sprites | não |
| `$102100–$10234F` | 38 | flags de jogo, colisão, paleta, pedidos de som | não |
| `$102350–$10264F` | 1 | sombra de 96 sprites, copiada para `$200180` por frame | não |
| `$102950–$1029DD` | 42 | cena final, caixas de colisão, editor de depuração | não |
| `$1029DE–$102A69` | 1 | 5 tarefas de desenho progressivo de imagem (`$8C` bytes) | não |
| `$102A6A–$102D5D` | 224 | **RAM privada por cenário** — um bloco por chefe/grupo | não |
| `$102D5E–$102D99` | 15 | rajadas de inimigos e tiro do jogador | não |
| `$103000–$103847` | 9 | arrays de objectos | não |
| `$103848–$103FFE` | 0 | espaço livre + pilha | parcialmente |
| `$103FFF` | 1 | `g_data_out_byte` | não |

### 4.4 Detalhe dos blocos

#### 4.4.1 `$100000–$10001F` — moedas e entradas cruas

| Endereço | Nome | O que é |
|---|---|---|
| `$100000` `$100002` | `g_coin1_needed` `g_coin1_credits` | copiados da tabela em `$03FFBE`/`$03FFDE` |
| `$100004` `$100006` | `g_coin2_needed` `g_coin2_credits` | idem, ranhura 2 |
| `$100008` `$10000E` | `g_cchip_pb_prev` `g_cchip_pa_prev` | leituras do frame anterior |
| `$10000A` `$10000C` `$100010` | `g_coin1_edge` `g_coin2_edge` `g_service_edge` | 0..3; 3 = fim do impulso |
| `$100012` `$100014` | `g_coin1_inserted` `g_coin2_inserted` | contagem parcial até dar crédito |
| `$100016` `$100017` | `g_coin*_stuck_frames` | a `$20` dispara o ecrã de COIN ERROR |
| `$100018`–`$10001D` | `g_counter*_pending/phase/timer` | 4 frames por meia onda do impulso |
| `$10001E` | `g_cchip_pb_out` | escrito em `$F00011`: b4/b5 contadores, b6/b7 lockouts |

`$100000` é o caso especial que já apareceu duas vezes: é **ao mesmo tempo** a base de A5 e o
primeiro campo da tabela de moedas. `symbols/main68k.sym` declara lá dois símbolos (`RAM g_base` e
`RAMVAR g_coin1_needed`), o que é uma decisão deliberada, registada no ficheiro de conflitos.

#### 4.4.2 `$100020–$10007F` — o estado global do frame

O bloco mais denso do mapa, e o que se lê mais vezes. Por função:

**Máquina de estados** — `$100020` `g_game_state` (0 = atracção, 1 = moeda/START, 2 = a jogar,
3 = tilt→reboot), `$100022` `g_seq_mode`, `$100024` `g_seq_step`, `$100038` `g_seq_delay`. Os três
níveis de despacho estão em [`docs/06-gameplay.md`](06-gameplay.md).

**Configuração vinda dos DIPs** — `$10002C` `g_dswa` e `$10002E` `g_dswb`, ambos **já
complementados** (`not.b` em `$0073E2` e `$007430`), e os campos já extraídos:
`$10003A` `g_difficulty` = `(DSWB & $0C) >> 2`, `$100042` `g_lives_setting`,
`$100078` `g_bonus_setting` = `DSWB & 3`, `$10003C` `g_cabinet` = `DSWA` b0,
`$10003E` `g_flip_screen` = `DSWA` b1.

**Espelhos de hardware** — `$100028` `g_video_ctrl_shadow` (o que foi escrito em `$D00000`),
`$10005A/$10005B` `g_collision_status` (o que se leu de `$D00000`),
`$100070` `g_cchip_bank68_shadow` (o banco escrito em `$F00C01`, e que **nunca é lido**),
`$10006A` `g_vram_page_ptr` (`$400000` ou `$440000`).

**Entradas já normalizadas** — `$10002A` `g_input_bits`, activo alto, com b0 = BAIXO, b1 = DIREITA,
b2 = ESQUERDA, b3 = CIMA, b4 = BOTÃO1. O empacotamento em `$004FE0-$00500E` é uma confirmação
independente do mapa de pinos do `PC` que o ground truth declara: partindo de `PC` (b0 TILT,
b2 CIMA, b3 BAIXO, b4 ESQ, b5 DIR, b6 BOTÃO), o código faz `lsr.w #1` e depois extrai o bit 2 para
b0, o bit 4 para b1, o bit 3 para b2, o bit 1 para b3 e o bit 5 para b4 — que é exactamente a
permutação certa.

**Porto de saída de dados** — `$100052` `g_data_out_cmd`, `$100054` `g_data_out_payload` (5 bytes),
`$10005C` `g_data_out_step`. Alimentam `sys_data_out_tick` e o byte `$103FFF` (§4.4.9).

#### 4.4.3 `$100080–$1001FF` — os três contextos de jogador

Três blocos de **128 bytes** com o mesmo esquema:

| Faixa | Papel |
|---|---|
| `$100080–$1000FF` | contexto guardado do jogador 1 |
| `$100100–$10017F` | contexto guardado do jogador 2 |
| `$100180–$1001FF` | contexto **activo** |

A troca é literal:

```
game_switch_to_player1:
        lea.l   $180(a5),a0             ; $003D86  activo   -> P2
        lea.l   $100(a5),a1
        moveq   #$40,d0                 ; 64 words = 128 bytes
        bsr.w   util_copy_words
        lea.l   $80(a5),a0              ; $003D94  P1       -> activo
        lea.l   $180(a5),a1
        moveq   #$40,d0
        bsr.w   util_copy_words
```

Num jogo de dois jogadores, cada um tem os seus 128 bytes de estado *e* a sua página de VRAM
(`$400000` / `$440000`) — a área conquistada por um fica intacta enquanto o outro joga.

O conteúdo do contexto activo, pelos nomes que têm prova:

| Endereço | Nome | O que é |
|---|---|---|
| `$100180` | `g_lives` | vidas restantes (máximo 9) |
| `$100185` | `g_demo_flag` | flag de ronda/demo |
| `$100186` `$100188` | `g_fill_pixel_count` (long) `g_fill_pixel_rest` | contagem de pixels preenchidos; 63 px = 0,1 % |
| `$10018A` `$10018C` | `g_countdown_bcd` `g_countdown_step_bcd` | contador BCD decrementado com `sbcd` |
| `$10018E` `$10018F` | `g_area_pct_shown` (+hi) | percentagem **mostrada** no HUD, ×10 em BCD |
| `$100190` | `g_area_permille` | área conquistada em décimos de por cento, 0..1000 |
| `$100192` `$100193` | `g_area_pct_target` (+hi) | percentagem **real** |
| `$100197` `$100198` | `g_round_bcd` `g_round_index` | ronda em BCD e em binário (0..$10) |
| `$100199` `$10019C` | `g_score_addend` `g_score_bcd` | 3 bytes BCD cada |
| `$1001A0` `$1001A2` | `g_respawn_x` `g_respawn_y` | ponto de reentrada |
| `$1001AF` | `g_fills_done` | preenchimentos concluídos |
| `$1001B2` `$1001B4` | `g_bonus_threshold` `g_bonus_index` | próxima vida extra e índice na tabela |
| `$1001B6–$1001FF` | — | 74 bytes do contexto sem nome individual |

#### 4.4.4 `$100200–$1002FF` — recordes e demo

`$100200` `g_hiscore` (3 bytes BCD), `$100203` `g_hiscore_scores` (5 × 3 bytes),
`$100212` `g_hiscore_rounds` (5 bytes), `$100217` `g_hiscore_names` (5 × 3 letras),
`$100226` `g_name_edit_buf`. A seguir, a reprodução do modo de atracção:
`$10022A` `g_demo_started`, `$10022C` `g_demo_script_ptr` (long),
`$100230`/`$100232` `g_demo_input_value`/`g_demo_input_timer`.

Os quatro guiões de demo vivem em **ROM** (`$039252`, `$0396C4`, `$0397EC`, `$039C5E`) e cada word
é `(valor << 11) | duração_em_frames`. O modo de atracção foi *gravado*, não programado — a rotina
gémea de gravação, `demo_record_input` (`$017D40`), continua na ROM, e o seu ponteiro de escrita é
inicializado com `$00039252`, que é **ROM**: na placa é inerte.

`$100234–$1002FF` (204 bytes) não tem referências.

#### 4.4.5 `$100300–$1003FF` — trabalho geral

Primeiro endereço da zona limpa por ronda. Inclui `$100302` `g_frame_counter`,
`$10031C` `g_snd_queue` (a fila de comandos de som, **6 slots úteis** — ver anexo),
`$100324`–`$10032E` (estado do blitter: colunas, cursor, fim de linha, linhas),
`$100346`/`$100362` (os dois buffers de texto da percentagem),
`$10037E`–`$10038E` (ecrã de recordes),
`$100392`–`$1003A2` (ponteiros para as três imagens do nível e para duas paletas),
`$1003A6`–`$1003AE` (estado do modo de teste), `$1003B0` `g_fill_flag_dead` e `$1003B4`
`g_test_text_buffer` (88 bytes).

#### 4.4.6 `$100800–$1008FF` — a estrutura do jogador

`$100800` é a base de A4 em 15 sítios (`lea $800(a5),a4`), e por isso os offsets aqui aparecem na
listagem tanto como `$8xx(a5)` como `$xx(a4)`. As 73 variáveis dividem-se assim:

| Faixa | O que é |
|---|---|
| `$100804` | `g_vram_cmd` — pedido de transição de ecrã; quem pede escreve 3..7 e espera voltar a 0 |
| `$100805`–`$10080C` | direcção, direcção anterior, a mexer, activo |
| `$100814`–`$10081A` | dx, x, dy, y |
| `$10081C`–`$10084A` | o motor de preenchimento: índices, ponteiros dos dois lados, raio, semente, passos |
| `$10084E`–`$100858` | detecção de acerto: no jogador, na trilha, endereço e (x,y) do ponto atingido |
| `$100860`–`$10086E` | flags de fim de vida, temporizadores de timeout |
| `$100871`–`$100876` | ritmo e velocidade de aparecimento de inimigos (o que vem do C-Chip) |
| `$100880`–`$100892` | comprimento da trilha, itens activos, fim de ronda |
| `$100896`–`$1008A6` | a lista de vértices da trilha e o ponto de partida |
| `$1008A8` | `g_cchip_bank` — o banco pedido ao C-Chip |
| `$1008B0`–`$1008BF` | estado de aparecimento, direcção, dispersão do tiro |
| `$1008C0` `$1008D0` `$1008E0` | os três tiros do jogador, 16 bytes cada |
| `$1008FE` | índice da imagem do nível |

`$100900–$100FFF` (1792 bytes) não tem referências.

#### 4.4.7 `$101000–$10234F` — escalonador, objectos e sprites

| Endereço | Tamanho | O que é |
|---|---|---|
| `$101000` | `$100` | `g_tasks` — 4 ranhuras de `$40` bytes do escalonador cooperativo |
| `$101100`–`$101118` | | tarefa corrente, contador de ciclo, PC de retoma, flags |
| `$10110A` | 2 | `g_level_type` — o **tipo de cenário**, não o número da ronda |
| `$10111A` | `$40` | `g_big_enemy` — o objecto do chefe |
| `$101126` `$101128` | 2+2 | `g_boss_y` `g_boss_x` |
| `$10115A` | `$1C0` | `g_obj_pool` — 7 objectos de `$40` bytes |
| `$10131A` | `$300` | `g_boss11_trail` — anel de `$C0` registos de 4 bytes do chefe-serpente |
| `$10161A` | `$CC` | `g_boss11_segments` — 16 segmentos |
| `$10179A` `$101A9A` | `$300` cada | dois bancos de tiros de chefe |
| `$101D9A` | `$168` | `g_spr_parts` — peças de sprite composto, `$C` bytes cada |
| `$10209A`–`$10209E` | | contagem de peças e posição do segundo chefe grande |
| `$1020A0`–`$1020B0` | 5×4 | os cinco ponteiros de partição do buffer de sprites |
| `$1020BC`–`$1020FE` | | índice de silhueta, tabelas de duração, direcção alvo, dano, cor |
| `$102100`–`$10212E` | | flags de jogo: itens apanhados, inimigos vivos, paleta, pedidos de som |
| `$102130` `$102132` | | cadeia de capturas do frame e semáforo da animação de morte |
| `$102136`–`$1021F6` | 3×`$40` | três pares (cópia, trabalho) de banco de paleta de `$20` bytes |
| `$1021FE`–`$102202` | | fora do campo, tocou na trilha, tocou no jogador |
| `$102206` | `$140` | `g_outline_buf` — silhueta copiada por frame |
| `$102346`–`$10234C` | | pedidos de disparo dos grupos de inimigos |

`$101F02–$102099` (408 bytes) e `$1016E6–$101799` (180 bytes) não têm referências.

#### 4.4.8 `$102350–$102FFF` — sombra de sprites, cena e cenários

`$102350` `g_spr_shadow` são 768 bytes = 96 sprites de 8 bytes, copiados para `$200180` uma vez por
frame por `spr_flush_shadow` (§3.3), a menos que `$10212A` `g_spr_flush_disable` esteja posto.

`$102650–$10294F` (768 bytes) não tem referências. É exactamente o mesmo tamanho da sombra, o que
sugere um segundo buffer, mas não encontrei quem lá escreva.

`$102950–$1029DD` são a sequência final (posições, quadros, deslocamentos, rolamento, ponteiro dos
créditos), o motor de texto por sprites (`$10296C` cursor, `$102970`–`$102974` atributo/y/x), a
caixa de colisão (`$102978`–`$102994`) e o editor de depuração (`$1029A0`–`$1029C4`), seguidos dos
ponteiros de emissão de sprites (`$1029D2`, `$1029D6`) e de três variáveis marcadas como código
morto (`$1029D8`–`$1029DC`).

`$1029DE` `g_vram_img_tasks` são `$8C` bytes = **5 tarefas de `$1C`** que desenham imagens grandes
na VRAM a N linhas por frame. O tamanho está provado por `$01849A`, que limpa exactamente `$8C`
bytes; se as cinco estiverem ocupadas, `$01851A` faz `bra.b *` — um assert de desenvolvimento
deixado na ROM final.

**`$102A6A–$102D5D` é a RAM privada por cenário**, e é a maior fatia do mapa: 224 das 577
variáveis. A organização não é «um bloco contíguo por chefe» — é **por papel, com o cenário a
indexar dentro de cada faixa**:

| Faixa | Papel | Cenários |
|---|---|---|
| `$102A6A–$102AF5` | blocos de trabalho `bossNN_work` | 00 (`$C`), 04 (`$22`), 05 (`$18`), 07 (`$16`), 08 (`$C`), 09 (`$26`) |
| `$102AF6–$102B88` | variáveis nomeadas dos chefes com geometria própria | 11 (20 vars), 12 (14), 14 (6), 15 (20) |
| `$102B8A–$102BA2` | contadores de ciclo dos grupos de inimigos | grp00, 04, 05, 07, 08, 09, 11, 12, 14, 15 |
| `$102BA6–$102BE2` | estado dos tiros, 4 vars por cenário | 00, 04, 05, 07, 08, 09, 11 |
| `$102BE4–$102BFF` | as três «ondas de tiro» | shotwave a, b, c |
| `$102C00–$102C0E` | comuns de ronda: contador, flash, limpeza, pedidos de som | — |
| `$102C10–$102D5D` | os cenários que não cabem nas faixas de cima | 02 (14), 03 (19), 01 (3), 10 (16), 06 (21), 13 (13), `bossmv` (4), sementes de aleatório |

O que isto diz sobre o código: **nem um endereço partilhado entre cenários**. Cada um tem as suas
variáveis, mesmo quando faz exactamente a mesma coisa que o vizinho. Isso, mais as tabelas
byte-a-byte idênticas entre os cenários 12 e 15, é a assinatura de código feito por
copiar-colar-ajustar, não por parametrização.

`$102D5E–$102D99` fecha com as rajadas de inimigos (`g_burst_*`) e o tiro do jogador
(`g_shot_cooldown`, `g_shot_button_prev/edge`, `g_shot_idle_frames`, `g_shot_slot_iter`) mais
`$102D8E` `g_rand_seed`.

`$102D9A–$102FFF` (614 bytes) não tem referências.

#### 4.4.9 `$103000–$103FFF` — arrays de objectos, pilha, e o byte que ninguém lê

| Endereço | Tamanho | O que é |
|---|---|---|
| `$103000` | `$20` | `g_dev_cursor_obj` — o cursor do editor de inimigos |
| `$103020` | `$2C0` | `g_enemies` — 22 objectos de `$20` bytes |
| `$103300` | `$100` | `g_sparks` — 8 faíscas de `$20` bytes |
| `$103400` | `$200` | `g_obj_table_debris` — fragmentos da explosão do jogador, 16 × `$20` |
| `$103600`–`$1036FF` | 256 | sem nome |
| `$103700` | `$100` | `g_enemy_shots` — 8 tiros de `$20` bytes |
| `$103820` | `$20` | `g_explosion_obj` |
| `$103840`–`$103846` | | envolvimento do chefe, fase ganha, HUD, temporizador |
| `$103848–$103AFF` | 696 | zona limpa por ronda, sem nomes |
| `$103B00–$103FFD` | 1278 | **pilha** |
| `$103FFE` | 2 | topo da pilha (SSP inicial) |
| `$103FFF` | 1 | `g_data_out_byte` |

A pilha começa em `$103FFE` e cresce para baixo. Como o 68000 decrementa **antes** de escrever, os
bytes `$103FFE` e `$103FFF` nunca são tocados por um `push`. `$103FFF` fica portanto isolado, por
cima da pilha e fora do bloco limpo por ronda — e é onde `sys_data_out_tick` (`$006522`) escreve:

```
        move.b  #$AA,g_data_out_byte    ; $00653C  13fc00aa00103fff
```

A rotina corre **todos os frames** (é a última coisa que o VBLANK faz antes do `rte`) e emite um de
onze códigos (`$00`, `$01`, `$02`, `$03`, `$0E`, `$0F`, `$12`, `$13`, `$1F`, `$20`, `$AA`) sempre
que `$100052` tem um comando pendente — o que acontece em cada moeda, cada início de jogo, cada
ronda, cada game over e cada tilt. O comando `$20` emite ainda cinco bytes um a um: a pontuação
final em BCD e a ronda atingida.

**Não há nenhuma leitura de `$103FFF` na ROM do 68000**, e as outras duas CPUs nem sequer
conseguem endereçar aquele byte. Ver §8.5.

### 4.5 As lacunas

Faixas de `$100000-$103FFF` sem uma única referência absoluta ou relativa a A5 na listagem, com
128 bytes ou mais:

| Faixa | Bytes |
|---|---|
| `$100234–$1002FF` | 204 |
| `$10040C–$1007FF` | 1012 |
| `$100900–$100FFF` | 1792 |
| `$1016E6–$101799` | 180 |
| `$101F02–$102099` | 408 |
| `$102650–$10294F` | 768 |
| `$102D9A–$102FFF` | 614 |
| `$103848–$103FFE` | 1975 (dos quais 1278 são a pilha) |

Isto **não prova** que estão por usar. O jogo escreve em arrays de objectos por ponteiro em
`a0`/`a4` constantemente, e um array declarado com um tamanho pode ser percorrido para lá dele. É
uma lista de sítios por explicar, não uma lista de memória livre.

---

## 5. Z80 de som — o espaço de endereços

| Faixa | O que é |
|---|---|
| `$0000–$7FFF` | ROM `c04-06.71`, 32 KB |
| `$8000–$87FF` | RAM de trabalho, 2 KB |
| `$8800` | PC060HA `slave_port_w` |
| `$8801` | PC060HA `slave_comm_r/w` |
| `$9000` `$9001` | YM2203: selector de registo / dados |
| `$9800` | escrita ignorada pelo MAME — função desconhecida |
| resto | não descodificado |

Interrupções: **IRQ em modo 1** (`$0038`), vinda do YM2203; **NMI** (`$0066`), vinda do PC060HA
quando o 68000 põe um par de nibbles. O reset também vem do PC060HA (modo 4).

### 5.1 A ROM

Medido sobre `build/audiocpu.bin`: o último byte diferente de `$FF` está em **`$4EDD`**. De
`$4EDE` a `$7FFF` são 12 578 bytes de `$FF` — 38,4 % da EPROM está vazia. Cobertura em
[`build/z80_map.json`](../build/z80_map.json): 6484 bytes de código, 11 907 de dados, 454 de
tabelas de ponteiros, 7 por classificar.

O reset é curioso porque **cai para dentro do vetor de RST $08**:

```
reset_entry:
        di                              ; $0000  F3
        im      1                       ; $0001  ED 56
        ld      a,$05                   ; $0003  3E 05
        ld      (PC060HA_PORT),a        ; $0005  32 00 88
rst_08:
        ld      (PC060HA_COMM),a        ; $0008  32 01 88
        jp      loc_0181                ; $000B  C3 81 01
```

O `ld a,$05` + porta + comm é «modo 5 = desligar a NMI». Os RSTs `$10` a `$30` são `nop`; o RST
`$08` está ocupado pela continuação do reset e não é usado como RST.

### 5.2 A RAM

48 endereços distintos são referenciados de forma absoluta. A estrutura sai da tabela de contextos
de canal em `$0385`, que dumpei da ROM:

```
$8000  $80A0  $0000  $0000  $8140  $81D0  $8260  $82F0  $8380  $8410
```

| Faixa | O que é |
|---|---|
| `$8000–$809F` | contexto de canal 0 (selectores `$84`/`$85`) — formato «segundo despacho» |
| `$80A0–$813F` | contexto de canal 1 (selectores `$86`/`$87`) — idem |
| — | as entradas [2] e [3] da tabela valem `$0000` |
| `$8140–$81CF` | contexto 4 |
| `$81D0–$825F` | contexto 5 |
| `$8260–$82EF` | contexto 6 |
| `$82F0–$837F` | contexto 7 |
| `$8380–$840F` | contexto 8 |
| `$8410–$849F` | contexto 9 |
| `$84A0–$873F` | 672 bytes sem referências absolutas |
| `$8740` `$8741` | ponteiros de escrita/leitura do **anel B** |
| `$8742–$8761` | anel B, 32 entradas (`and $1F`) |
| `$8762–$877F` | sem referências |
| `$8780` `$8781` | ponteiros de escrita/leitura do **anel A** |
| `$8782–$8791` | anel A, 16 entradas (`and $0F`) — a fila de comandos |
| `$8792–$87A9` | estado do driver: máscaras, flags de mudo, eco, camada |
| `$87AA–$87FF` | pilha (86 bytes) |

Os seis contextos de `$8140` para cima estão espaçados de `$90` bytes; os dois primeiros, de `$A0`.
O maior offset `(ix+n)` que aparece na listagem é `$71` (o `$61` é o único que falta entre `$00` e
`$71`), portanto pelo menos `$72` bytes de cada contexto são usados.

**Há duas filas, não uma.** A NMI escreve o byte recebido no anel A (`$8782`, 16 entradas) e, a
seguir, chama `sub_015F` (`$015F`) que o escreve *também* no anel B (`$8742`, 32 entradas):

```
loc_0114:
        ld      (ram_8780),a            ; $0117  ponteiro de escrita do anel A
        ...
        ld      bc,ram_8782             ; $0121
        add     hl,bc
        ld      (hl),a                  ; $0125
loc_0126:
        call    sub_015F                ; $0126  -> anel B
```

O anel A é consumido por `sub_028A` (`$028A`), que o lê com o mesmo `and $0F` e despacha o
comando. **O anel B não é lido em lado nenhum da ROM** — é um registo de tudo o que entrou, e
inclui os bytes `$FA`/`$FB` (leitura de DIPs) que nem chegam ao anel A. Ver §8.8.

A pilha é posta no arranque com

```
        ld      sp,PC060HA_PORT         ; $018C  31 00 88
```

que a listagem escreve com o nome do porto porque `$8800` é o valor. **É `ld sp,$8800`**: um byte
acima do fim da RAM, portanto o primeiro `push` escreve em `$87FE`/`$87FF`. Nada tem a ver com o
PC060HA (anexo).

### 5.3 `$9000/$9001` e o caminho dos DIPs

O YM2203 quase nunca é endereçado em absoluto — o driver usa `ld hl,$9000` e depois `(hl)` /
`inc hl`. A excepção que interessa ao mapa de memória é a leitura dos DIP switches, que é a única
via pela qual o 68000 os vê:

```
nmi_read_dipswitch_reply:
        cp      $FA                     ; $00D7
        jr      z,loc_00DF
        cp      $FB                     ; $00DB
        jr      nz,loc_0101
loc_00DF:
        ld      c,a
        sub     $EC                     ; $00E0   $FA->$0E, $FB->$0F
        ld      (YM2203_REG),a          ; $00E2
        nop × 5
        ld      a,(YM2203_DATA)         ; $00EA
```

Os registos `$0E`/`$0F` do YM2203 são as portas A e B do PSG, e é aí que estão fisicamente os DSWA
e DSWB. O byte volta ao 68000 em dois nibbles (`$00F4` e, depois de quatro `rrca`, `$00FB`) e
acaba, complementado, em `$10002C`/`$10002E`.

### 5.4 `$9800`

Duas escritas em toda a ROM:

| Onde | O quê |
|---|---|
| `$01C2` | `ld a,$00` seguido de `ld ($9800),a`, na inicialização |
| `$14C5` | um byte vindo de `(de)`, imediatamente sombrado em `$87A5` |

A segunda está dentro do bloco que emite pares de registos do SSG. O MAME ignora a escrita
(`map(0x9800, 0x9800).nopw(); // ?`). Não tenho hipótese preferida.

---

## 6. uPD78C11 (C-Chip) — o espaço de endereços

O TC0030CMD tem quatro pastilhas: o uPD78C11 com 4 KB de ROM máscara, uma EPROM externa de 8 KB,
uma SRAM uPD4464 de 8 KB e uma ASIC. O mapa que o MCU vê:

| Faixa | O que é | Estado neste projecto |
|---|---|---|
| `$0000–$0FFF` | ROM máscara interna, 4 KB | **não dumpada neste conjunto** |
| `$1000–$13FF` | janela de 1 KB num dos 8 bancos da SRAM | partilhada com o 68000 |
| `$1400–$15FF` | 4 bytes de RAM da ASIC, espelhados (`offset & 3`) | |
| `$1600` | selector de banco da janela, **lado do MCU** | |
| `$1601–$17FF` | escrita cai na RAM da ASIC; leitura devolve `$00` | |
| `$2000–$3FFF` | EPROM externa `cchip_c04-23`, 8 KB | [`src/cchip/cchip.asm`](../src/cchip/cchip.asm) |
| `$FF00–$FFFF` | RAM interna do 78C11, 256 bytes | activada pelo bit 3 do registo MM |

Os vetores do 78C11 (`$0000` reset, `$0004` NMI, `$0008` timers, `$0010` INT1/INT2, `$0018`
eventos, `$0020` A/D, `$0028` série, `$0060` SOFTI) e os destinos de `CALT` (`$0080-$00BF`) e
`CALF` (`$0800-$0FFF`) **estão todos dentro da ROM interna que não temos**.

### 6.1 O que a EPROM externa toca

Contado sobre a listagem:

| Endereço | Acessos | O que é |
|---|---|---|
| `$1000`–`$1002` | 4 | acedidos **no banco 1**: desafio, resposta e contadores da busca |
| `$1003`–`$1006` | 12 | cópias das portas de entrada, escritas todos os frames |
| `$1007`–`$1009` | 3 | valores que o 68000 pôs para irem para as portas de saída |
| `$100A`–`$100C` | 9 | comando + 2 argumentos |
| `$1010` | 3 | destino dos 160 bytes de dados da ronda / 64 bytes de ritmo |
| `$1023` | 1 | índice de paleta da ronda |
| `$13FE` | 9 | handshake dos dados da ronda |
| `$13FF` | 2 | handshake da tabela de ritmo |
| `$1400` | 1 | RAM da ASIC, byte 0 |
| `$1600` | 1 | selector de banco (só no arranque, com `$E8`; `$E8 & 7 = 0`) |
| `$FF9B` `$FFB4` `$FFB6` | 7 | guarda de reentrância e salvaguarda de SP na RAM interna |

### 6.2 A confirmação mais bonita do mapa de portas

O init do C-Chip (`entry_214F`) programa as três portas antes de entregar tudo à interrupção:

```
entry_214F:
        call    introm_select_bank_0    ; $214F
        mvi     pa,$02                  ; $2152
        mvi     a,$FD                   ; $2155
        mov     ma,a                    ; $2157   MA = $FD
        mvi     pb,$F0                  ; $2159
        mvi     a,$0F                   ; $215C
        mov     mb,a                    ; $215E   MB = $0F
        mvi     pc,$00                  ; $2160
        mvi     a,$FF                   ; $2163
        mov     mc,a                    ; $2165   MC = $FF
```

Em `upd7810.cpp`, `data = (m_pa_in & m_ma) | (m_pa_out & ~m_ma)`: **bit a 1 = entrada, bit a 0 =
saída**. Logo:

| Registo | Valor | Significa |
|---|---|---|
| `MA` | `$FD` | PA1 é saída; PA0 e PA2–PA7 são entradas |
| `MB` | `$0F` | PB0–PB3 entradas, **PB4–PB7 saídas** |
| `MC` | `$FF` | PC todo entradas |

`MB = $0F` é uma confirmação independente e exacta do que o ground truth diz sobre a porta B: as
entradas COIN1/COIN2 estão em b0/b1 (dentro dos quatro bits de entrada) e os contadores e lockouts
em b4–b7 (exactamente os quatro bits de saída). E o C-Chip faz `xri a,$30` (`$2194`) antes de pôr o
valor na porta, ou seja inverte os dois bits dos contadores.

O init acaba com `ei` e um `jr` sobre si próprio em `$217A`: **todo o trabalho do C-Chip corre
dentro da interrupção `/INT1`**, que é o VBLANK do 68000.

### 6.3 A janela é bancada — e a listagem não avisa

Os mesmos offsets `$1004`/`$1005`/`$1006` significam:

| Banco | `$1004` | `$1005` | `$1006` |
|---|---|---|---|
| 0 | cópia de `PB` (COIN1/COIN2) | cópia de `PC` (TILT, joystick) | resultado do A/D (P2 cocktail) |
| 2 | comando da ALU de protecção | operando A / resultado | operando B |

E `$1000`–`$1002` são os três bytes de arranque escritos pelo 68000 no banco 0, mas o desafio, a
resposta e os contadores da busca no banco 1. A listagem gerada mostra sempre os rótulos do banco
0 (anexo).

O detalhe do que corre em cada banco está em [`docs/04-c-chip.md`](04-c-chip.md).

---

## 7. Onde os três mapas se tocam

Não há memória partilhada entre as três CPUs a não ser em dois pontos, e ambos são estreitos.

**68000 ↔ Z80, pelo PC060HA.** Quatro nibbles de cada lado, mais um registo de estado. Nada mais
atravessa. O 68000 escreve em `$E00001`/`$E00003`, o Z80 lê em `$8800`/`$8801`. É por aqui que
passam os comandos de som **e** os DIP switches — os DIPs estão fisicamente no YM2203, do lado do
Z80, e chegam ao 68000 depois de um trajecto de quatro pernas descrito em §5.3.

**68000 ↔ uPD78C11, pela SRAM do C-Chip.** 1 KB de cada vez, num dos 8 bancos de uma SRAM de 8 KB,
com **um registo de banco por lado**. O 68000 vê-a em `$F00000-$F007FF` (bytes ímpares), o MCU em
`$1000-$13FF`. Quatro protocolos distintos correm sobre os mesmos endereços, distinguidos pelo
banco e pelo byte de handshake:

| Protocolo | Handshake | Dados |
|---|---|---|
| entradas | nenhum — actualizadas todos os frames | `$F00007`–`$F0000D` |
| saídas (contadores/lockouts) | nenhum | `$F00011` |
| dados/paleta da ronda | `$F007FD` = ronda+1, esperar que mude | 80 words a partir de `$F00021` |
| tabela de ritmo | `$F007FF` = 1, esperar 2 | 3 bytes × 16 a partir de `$F00021` do banco N |

O par mais fechado é o da paleta, e fecha ao byte pelos dois lados: o C-Chip copia 160 bytes para
`$1010` (`round_data_copy`, `$21CF`), e o 68000 lê 80 words a partir de `$F00021` reconstruindo
cada uma a partir de dois bytes ímpares consecutivos:

```
pal_read_cchip_words:
        move.b  $2(a0),d0               ; $015CD4  byte alto
        lsl.w   #$8,d0
        move.b  $0(a0),d0               ; $015CDA  byte baixo
        move.w  d0,(a1)+
        lea.l   $4(a0),a0               ; 4 bytes de 68000 = 2 bytes de C-Chip
        dbra    d1,pal_read_cchip_words
```

80 words × 2 bytes = 160 bytes. Exactamente o que o C-Chip escreveu.

**Z80 ↔ uPD78C11: nada.** Não há caminho nenhum entre os dois.

**O VBLANK toca em dois sítios ao mesmo tempo**: levanta o IRQ 4 do 68000 e a `/INT1` do C-Chip
(`INTERRUPT_GEN_MEMBER(volfied_state::interrupt)`). Os dois processadores acordam no mesmo
instante, e é por isso que os handshakes de espera activa do 68000 (`tst.b CCHIP_RAM+$7FF` em
laço) acabam por terminar.

---

## 8. O que não sabemos

1. **A placa espelha a RAM principal por cima de `$100000`?** A pergunta tem consequências.
   `$1100B8 & $3FFF = $00B8` e `$110202 & $3FFF = $0202`: se a descodificação for só por A23–A20
   (comum em placas desta geração), os vetores `$0011xxxx` aliasavam para `$1000B8`–`$100202`, ou
   seja para o meio das variáveis de moedas, do estado global e da tabela de recordes. Com espelho,
   uma excepção executaria dados de jogo; sem espelho, o 68000 espera por um /DTACK que não vem.
   O MAME não emula espelho (`map(0x100000, 0x103fff)`) e o jogo nunca depende de um. **Não temos
   esquema da placa para decidir.**

2. **O que fazem os bits 3, 6 e 7 de `video_ctrl` na escrita.** `vram_ctrl_strobe` limpa e repõe os
   bits 3 e 6 uma vez por frame, através da sombra; o reset põe o bit 7. O MAME guarda o valor e só
   usa o bit 0. A hipótese de rearme dos latches de colisão é razoável — é o mesmo endereço que,
   lido, dá os bits de colisão — mas não é verificável em emulação.

3. **O bit 7 do estado de colisão (`$10005B`).** Testado em 20 sítios, todos código de chefe. Nos
   que segui (`$018A26` em `boss00_size_step_maybe`, e as três rotinas de redimensionamento
   `$01B02E`/`$01BBEA`/`$01C21E`) o efeito é inibir uma mudança de tamanho do chefe; não verifiquei
   os restantes 16 um a um. O MAME devolve `$0060` fixo, portanto o bit é sempre 0 e metade de cada
   um destes 20 ramos é código morto **em emulação**. O que o bit faz na PCB é uma incógnita, não
   uma adivinhação: o comentário do próprio MAME diz «its purpose is unclear».

4. **O valor real que o `bset.b #$7,VIDEO_CTRL_B` do reset deixa em `video_ctrl`.** É um
   read-modify-write sobre um endereço cuja leitura é o registo de colisão. No MAME dá `$E0`; na
   placa é o que a leitura devolver naquele instante.

5. **`$103FFF`.** Escrito todos os frames que tenham um comando pendente, com onze códigos
   distintos e um payload de cinco bytes com a pontuação e a ronda. **Nenhuma leitura** na ROM do
   68000; as outras duas CPUs não conseguem endereçar aquele byte. Resto do sistema de
   desenvolvimento (como os vetores `$0011xxxx`)? Porto de estatísticas para uma placa-mãe de
   sala? Artefacto? Sem consumidor identificado.

6. **`$700001` é um kick de watchdog?** O padrão de uso — sete escritas com lixo, sempre em pontos
   de espera longa (reset, laços do modo de teste, entrada do VBLANK) — encaixa. Mas nem o driver
   do MAME nem os dispositivos emulados têm watchdog nenhum, e não determinei sequer que valor
   chega ao chip num acesso de byte a `$700001`. Não decidido.

7. **A folga real da pilha.** Do lado do 68000 há um limite implícito de 1278 bytes
   (`$103B00-$103FFD`), imposto pelo fim da limpeza em `$103AFF`; do lado do Z80 há 86 bytes
   (`$87AA-$87FF`). Nenhum dos dois foi medido em execução — são limites aritméticos, não
   profundidades observadas.

8. **O anel B do Z80 (`$8740`/`$8741`/`$8742`, 32 entradas).** É escrito com todos os bytes que a
   NMI aceita, incluindo os `$FA`/`$FB` que não vão para a fila de comandos, e ainda a partir de
   `$049B`. Não encontrei uma única leitura. Registo de diagnóstico? Fila para uma segunda camada
   que nunca foi escrita? Não decidido.

9. **`$84A0–$873F` (672 bytes) e `$8762–$877F` na RAM do Z80** não têm referências absolutas. Podem
   ser buffers alcançados por `ix` (o driver usa `(ix+n)` até `+$71`) ou podem estar por usar.

10. **As oito lacunas da RAM do 68000 (§4.5).** A maior, `$100900-$100FFF`, tem 1792 bytes entre a
    estrutura do jogador e o escalonador. Nenhuma referência absoluta nem via A5 — mas o jogo
    escreve em arrays por ponteiro, e portanto isto não prova que estejam livres.

11. **`$102650–$10294F` (768 bytes)** tem exactamente o tamanho da sombra de sprites que o
    precede. É tentador chamar-lhe um segundo buffer, mas não encontrei quem lá escreva; fica sem
    nome.

12. **`$9800` do lado do Z80.** Escrito duas vezes, ignorado pelo MAME, com sombra em `$87A5`. Sem
    hipótese preferida.

13. **A ROM interna de 4 KB do C-Chip.** Não está neste conjunto. Existe um dump upstream no MAME
    (`cchip_upd78c11.bin`, extraído opticamente), mas até ser acrescentado a este projecto o
    comportamento de `$0000-$0FFF` é observado apenas de fora — incluindo quem escreve o byte de
    «pronto» em `$F00803`, que a EPROM externa nunca toca.

14. **Se a escrita de byte em `$F00000` (§3.11) falha mesmo na placa real.** O raciocínio de
    /UDS-/LDS é sólido e o MAME concorda (o handler mascarado não é chamado). Se falhar, o byte de
    desafio nunca chega ao C-Chip, o `challenge_lookup` não encontra nada e a tabela de ritmo que o
    jogo acaba por ler é a do ramo de falha. **Não observei nem uma coisa nem outra**: não corri o
    emulador com instrumentação nem toquei em hardware. Fica como a lacuna mais concreta e mais
    fácil de fechar deste documento.

---

## Anexo — armadilhas da listagem gerada

Coisas que confundem quem for verificar estes endereços na listagem. Todas confirmadas nos
ficheiros actuais.

**Zeros que aparecem como símbolos.** Os 20 vetores que valem `$00000000` são impressos como
`dc.l vector_00_initial_ssp`, porque `$000000` tem símbolo. Não são ponteiros (§2.3). O mesmo
mecanismo produz `andi.l #region_code,d0` em `$004F66`: o imediato é `$0003FFFE`, a máscara de 18
bits do offset de VRAM, e o substituidor apanhou o símbolo `region_code` (`$03FFFE`) dentro de uma
constante que não é um endereço.

**`ld sp,PC060HA_PORT`.** Em `$018C` do Z80, o valor é `$8800` — o topo da RAM mais um. A listagem
põe-lhe o nome do porto de som porque partilham o valor. É a inicialização da pilha, não um acesso
ao PC060HA.

**`g_base` com o comentário de outra variável.** Em `src/main68k/hardware.inc`, a linha
`g_base equ $100000` traz o comentário «moedas por credito na ranhura 1» — que é de
`g_coin1_needed`. Os dois símbolos partilham o endereço de propósito (§4.4.1) e o gerador juntou o
nome de um com o comentário do outro.

**Nomes do banco 0 aplicados a acessos de outro banco.** Em
[`src/cchip/cchip.asm`](../src/cchip/cchip.asm), os offsets `$1004`/`$1005`/`$1006` recebem sempre
as etiquetas `CMD_BYTE`, `CMD_ARG0` e `CMD_ARG1`. Esses nomes vêm de
`symbols/fragments/cchip/00_curado.sym` e **estão errados mesmo no banco 0**: o código em `$218C`,
`$219A` e `$21A7` escreve-lhes as cópias de `PB`, `PC` e do A/D. Os comentários da mesma linha, que
vêm de uma análise mais recente, já dizem `CC_IN_PB` / `CC_IN_PC` / `CC_IN_AD`. Quem corrigir os
fragmentos deve trocar os três nomes. No banco 2, esses mesmos offsets são comando e operandos da
ALU de protecção. A mesma armadilha existe do lado do 68000:
[`src/main68k/boss09.asm`](../src/main68k/boss09.asm) escreve `$AA` em `CCHIP_RAM+$A` (`$01A0BA`),
`$55` em `CCHIP_RAM+$C` (`$01A0C2`) e o comando `$65` em `CCHIP_RAM+$8` (`$01A0CA`) — os mesmos
três endereços que
[`src/main68k/player_control.asm`](../src/main68k/player_control.asm) usa em `$004FBE`/`$004FC8`
para **ler o joystick**. A diferença está só no banco, seleccionado em `$01A0B2`.

**Equates com o comentário errado.** No cabeçalho de `src/cchip/cchip.asm`, `ASIC_RAM0`,
`ASIC_TEST`, `ASIC_RAM2` e `ASIC_RAM3` têm todos o comentário «selector de banco (3 bits)», que é
do gerador. O selector de banco é só `$1600`; aqueles quatro são os quatro bytes de RAM da ASIC.

**Tamanhos declarados a mais.** O campo de tamanho das `RAMVAR` é anotação humana. Catorze pares
sobrepõem-se; a maioria de propósito (uma word e o seu byte alto, ou um contentor e os seus
campos). Três não são deliberados:

| Símbolo | Declarado | Realidade |
|---|---|---|
| `g_snd_queue` (`$10031C`) | 7 bytes | `snd_queue_command` (`$0004F4`) e `snd_drain_queue` (`$000520`) varrem **6** posições (`moveq #$6,d1` + `subq`/`bne`), ou seja `$10031C-$100321`. `$100322` tem símbolo próprio |
| `boss09_work` (`$102AD2`) | `$26` | acaba em `$102AF7`, dois bytes dentro de `boss11_seg_index` (`$102AF6`) |
| `g_anim_dur_table` (`$1020C6`) | `$A` | sobrepõe `g_anim_dur_table2` (`$1020CE`) em 2 bytes |

**Duas más-desmontagens, agora anotadas em vez de silenciosas.** Duas instruções tinham sido
partidas ao meio numa passagem anterior, criando rotinas que não existem. A listagem actual
descodifica-as bem e deixou o aviso como comentário:

| Endereço | Bytes | O que é | Rótulo fantasma que já não existe |
|---|---|---|---|
| `$007FFC` | `20 3C 00 00 0F 00` | `move.l #$F00,d0`, seis bytes | `sub_008000` começava a meio dela |
| `$0095C4` | `64 00 00 94` | `bcc.w loc_00965A` | `sub_0095C6` era o meio da instrução |

Ambos reconferidos nos bytes crus de `build/maincpu.bin`.

**Nomes de secção duplicados que já não custam nada.** Dois nomes aparecem duas vezes em
[`symbols/main68k_sections.sym`](../symbols/main68k_sections.sym): `player_control`
(`$004FAE-$0053E5` e `$005488-$005625`) e `enemy_boss06_area9` (`$026F7C-$026FEE` e
`$026FF0-$0276EB`). Numa versão anterior do gerador isso fazia o segundo ficheiro escrever por cima
do primeiro e duas faixas de código desapareciam de `src/`. **Já não acontece**: o gerador actual
funde as duas faixas no mesmo ficheiro — o cabeçalho de `src/main68k/player_control.asm` diz
`$004FAE-$0053E5, $005488-$005625` —, `volfied.asm` não tem `include` repetidos, e `inp_read_cchip`
e `enemy_boss06_init` estão ambos lá. Verifiquei os quatro pontos antes de escrever isto.

---

## Ver também

- [`docs/01-hardware.md`](01-hardware.md) — a placa, os dispositivos e o ritmo do frame.
- [`docs/03-video.md`](03-video.md) — a word de VRAM, os blitters, a paleta e os sprites.
- [`docs/04-c-chip.md`](04-c-chip.md) — o C-Chip como processador: arranque, tarefas, protecção.
- [`docs/05-som.md`](05-som.md) — o driver do Z80 e o formato das sequências.
- [`docs/06-gameplay.md`](06-gameplay.md) — as máquinas de estado e o motor de preenchimento.
- [`docs/07-texto-e-fonte.md`](07-texto-e-fonte.md) — o subsistema de texto que ocupa a RAM de
  sprites de §3.3.
- [`docs/08-ferramentas-e-reproducao.md`](08-ferramentas-e-reproducao.md) — como regenerar os
  símbolos e as listagens a que este documento se refere.
- [`docs/ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md) — a matéria-prima: o que cada agente descobriu
  a ler o código, com as dúvidas por fechar.
- [`reference/HARDWARE_GROUND_TRUTH.md`](../reference/HARDWARE_GROUND_TRUTH.md) — a fonte
  autoritativa de endereços.
