# 05 — Som

O som do Volfied são quatro andares empilhados com quatro ritmos diferentes: uma fila de
bytes na RAM do 68000, um latch de nibbles em silício (PC060HA), um interpretador de
sequências no Z80, e o YM2203. Este documento descreve os quatro do ponto de vista do
*software*, com ênfase no que não está escrito em mais lado nenhum: o formato dos dados
musicais, a máquina de estados dos canais e o inventário do que o jogo pede ao driver.

Fontes usadas e conferidas:
[`src/sound_z80/sound.asm`](../src/sound_z80/sound.asm) (6261 linhas),
[`src/main68k/snd_pc060ha_interface.asm`](../src/main68k/snd_pc060ha_interface.asm),
[`src/main68k/snd_z80_handshake.asm`](../src/main68k/snd_z80_handshake.asm),
[`src/main68k/irq_vblank_dispatch.asm`](../src/main68k/irq_vblank_dispatch.asm),
[`src/main68k/selftest_service_mode.asm`](../src/main68k/selftest_service_mode.asm),
[`build/z80_map.json`](../build/z80_map.json), [`build/m68k_map.json`](../build/m68k_map.json),
a imagem `build/audiocpu.bin` (32 768 bytes, SHA-1
`d71062f9d9b11492e13fc93982b95883f564f902`), e
[`reference/mame/taitosnd.cpp`](../reference/mame/taitosnd.cpp) e
[`reference/mame/volfied.cpp`](../reference/mame/volfied.cpp) para a semântica do latch e a
cablagem das linhas.

**O que já está noutro documento e aqui não se repete:**

- a eléctrica do PC060HA (modos, bits de estado, ordem dos nibbles), o percurso completo dos
  DIP switches e o pulso de reset do Z80 estão em
  [`docs/01-hardware.md` §7](01-hardware.md);
- o mapa de endereços do Z80, a divisão da RAM em contextos e a tabela de secções da ROM de
  som estão em [`docs/02-mapa-de-memoria.md` §4](02-mapa-de-memoria.md).

Endereços de placa: [`reference/HARDWARE_GROUND_TRUTH.md`](../reference/HARDWARE_GROUND_TRUTH.md).
Nenhum endereço aqui foi introduzido sem ter sido lido na listagem ou na imagem.

---

## 1. Panorama

```
   68000                          PC060HA         Z80                      YM2203
   -----                          -------         ---                      ------
 66 sitios de chamada em 60 rotinas
   |
   |  snd_queue_command  $0004F4
   v
 g_snd_queue ($10031C, 6 bytes)
   |  snd_drain_queue  $000520   (1 byte por VBLANK)
   v
 snd_send_if_allowed $000482 -> snd_send_command $000490
                                 modo 0 + 2 nibbles --> NMI $0066
                                                         |
                                                   FIFO de 16 bytes ($8782)
                                                         |
                                                   sub_028A (despacho)
                                                         |
                                             tbl_2500 -> bloco de pedido
                                                         |
                                             bloco de canal -> contexto ($8000..$849F)
                                                         |
                        IRQ do Timer A <---- $04A7 (FM) + $13F4 (SSG) ----> registos
```

| Andar | Ritmo | Onde |
|---|---|---|
| Pedido do jogo | quando calha | 66 sítios de chamada em `src/main68k/` |
| Drenagem da fila | 1 byte por frame (60 Hz), e só em certos estados de ecrã | `snd_drain_queue`, chamada do VBLANK |
| Despacho do comando | assim que o laço principal do Z80 volta | `sub_028A` (`$028A`) |
| Avanço das sequências | Timer A do YM2203, ≈60,9 Hz | IRQ `$0038` → `$0255` |

O desenho tem uma propriedade que vale a pena isolar: **o jogo não sabe nada sobre o
driver**. Escreve um byte numa fila; tudo o resto — que canais usar, com que instrumento, com
que prioridade — está nos dados da ROM do Z80.

---

## 2. O lado do 68000

### 2.1 Os pontos de entrada

| Endereço | Nome | Ficheiro | Sítios de chamada | Função |
|---|---|---|---|---|
| `$000482` | `snd_send_if_allowed` | `irq_vblank_dispatch.asm` | 13 (11 rotinas) | guarda de *demo sounds*; cai em `$000490` |
| `$000490` | `snd_send_command` | `snd_pc060ha_interface.asm` | 10 (10 rotinas) | envia `d0.b` ao Z80 |
| `$0004BA` | `snd_read_reply_byte` | `snd_pc060ha_interface.asm` | 1 | lê a resposta do Z80 (dois nibbles) |
| `$0004F4` | `snd_queue_command` | `snd_pc060ha_interface.asm` | **66 (60 rotinas)** | enfileira `d0.b` |
| `$000520` | `snd_drain_queue` | `snd_pc060ha_interface.asm` | 1 (o VBLANK) | tira um da fila |
| `$007362` | `snd_send_unmute` | `snd_z80_handshake.asm` | 1 | envia `$EF` |
| `$007372` | `snd_read_dipswitches` | `snd_z80_handshake.asm` | 6 (2 rotinas) | máquina de 5 estados |
| `$007452` | `snd_send_byte` | `snd_z80_handshake.asm` | 5 (3 rotinas) | **segunda cópia** de `$000490` |

As contagens são de duas medições independentes que batem certo: varrimento textual dos
`jsr`/`bsr` em `src/main68k/*.asm` (sítios de chamada) e o campo `chamadores` de
`build/m68k_map.json` (rotinas chamadoras). O símbolo `snd_queue_command` aparece 68 vezes na
listagem: 66 chamadas mais o rótulo e o cabeçalho.

`snd_send_byte` (`$007452`) e `snd_send_command` (`$000490`) fazem exactamente a mesma coisa
com código diferente: a primeira endereça o latch por `a3` (`lea SOUND_PORT,a3`, depois
`$2(a3)` e `$3(a3)`), a segunda por endereçamento absoluto. Não há razão funcional para as
duas existirem.

Nota de leitura: `hardware.inc` define `SOUND_PORT equ $E00000` e `SOUND_COMM equ $E00002`,
mas o PC060HA só decodifica os endereços **ímpares** `$E00001` e `$E00003`. As escritas são
`move.w` no endereço par, cujo byte baixo cai no ímpar; as leituras usam `SOUND_COMM_B equ
$E00003` como byte.

### 2.2 As quatro transacções

Toda a comunicação se reduz a quatro formas. Os bits de estado e a semântica de cada modo
estão em [`docs/01-hardware.md` §7](01-hardware.md); o que interessa aqui é quem espera pelo
quê.

| Transacção | Quem | Sequência |
|---|---|---|
| Enviar um comando | 68000 | modo 4; espera `b0 = 0` (o Z80 já leu o par anterior); modo 0; escreve nibble baixo, depois alto |
| Receber uma resposta | 68000 | modo 4; espera `b2 = 1`; modo 0; lê duas vezes (baixo, depois alto); modo 4; espera `b2 = 0` |
| Receber um comando | Z80 | na NMI: modo 5 (NMI off); modo 0; lê duas vezes; … ; modo 6 (NMI on); `retn` |
| Enviar uma resposta | Z80 | modo 0; escreve o byte, `rrca`×4, escreve outra vez (o chip mascara com `&$0F`) |

Duas consequências práticas:

- **O 68000 nunca selecciona os modos 2 ou 3.** Varrendo `src/main68k/*.asm`, as únicas
  escritas em `SOUND_PORT` são `#$4` e `#$0` (mais o par modo 4 + `$01`/`$00` do pulso de
  reset em `$0014E8`/`$001508`). O segundo par de portas do PC060HA nunca é usado, e por isso
  a variável `ram_87A9` do Z80 — que escolheria o par de resposta — é sempre zero e os ramos
  correspondentes (`$009E`–`$00BC` na NMI, `ld a,$02` em `$0234`) nunca correm.
- A espera de `snd_send_command` é real mas nunca morde em jogo: como só sai um byte por
  frame, o latch está sempre vazio quando ele chega. A espera que **de facto** bloqueia é a de
  `snd_read_dipswitches`, no arranque (§2.6).

### 2.3 A guarda de *demo sounds*

Duas camadas verificam a mesma condição:

```
snd_send_if_allowed:
        btst.b  #$3,$2D(a5)             ; $10002D                       $000482  082d0003002d
        beq.b   snd_send_command                                        ; $000488  6706
        tst.w   $40(a5)                 ; g_game_active ($100040)       $00048A  4a6d0040
        beq.b   loc_0004B8                                              ; $00048E  6728
```

`$10002D` é o byte baixo da word `g_dswa` (`$10002C`). Se o bit 3 estiver a **zero** o som
passa sempre; se estiver a **um**, só passa com `g_game_active` diferente de zero.
`loc_0004B8` é literalmente o `rts` de `snd_send_command`.

Os DIPs chegam complementados (`not.b d0` em `$0073E2`). A polaridade fica fixada por duas
outras leituras do mesmo byte, que se podem confrontar com os valores documentados do MAME:

| Evidência | Código | Conclusão |
|---|---|---|
| `btst.b #$2,$2D(a5)` em `$0015E8` salta para o modo de teste quando o bit está a **1** | `reset_and_dipswitch_setup.asm` | DSWA b2 é o Service Mode, activo a baixo (valor de porta `$00` = ligado) |
| `andi.b #$30 / lsr.b #$3` indexa `lives_table` (`$001622`), que é `3, 4, 5, 6` | idem | DSWB `$30` = 3 vidas dá índice 0; bate com a tabela do MAME |

Ou seja: um bit a 1 em `g_dswa`/`g_dswb` corresponde ao valor de porta `$00` do MAME. Pela
mesma convenção, o bit 3 do DSWA a 1 é a posição que o MAME rotula `0x00` — e a posição
`0x00` de *Demo Sounds* é *Off*. O comportamento observado (com o bit a 1 o som só passa
durante o jogo) é exactamente o de "demo sounds desligados". **Conjetura residual:** o nome
do bit vem do macro `TAITO_MACHINE_COCKTAIL_LOC`, que vive num cabeçalho do MAME que não
está copiado em `reference/mame/`; o que está verificado é a mecânica e a polaridade, não a
etiqueta.

### 2.4 A fila — seis slots, não sete

```
snd_queue_command:
        btst.b  #$3,$2D(a5)                                             $0004F4  082d0003002d
        beq.b   loc_000502
        tst.w   $40(a5)                 ; g_game_active ($100040)
        beq.b   loc_00051E
loc_000502:
        movem.l a6,-(a7)                                                $000502  48e70002
        lea.l   $31C(a5),a6             ; g_snd_queue ($10031C)         $000506  4ded031c
        moveq   #$6,d1                                                  $00050A  7206
loc_00050C:
        tst.b   (a6)
        bne.b   loc_000514
        move.b  d0,(a6)                 ; primeiro slot vazio
        bra.b   loc_00051A
loc_000514:
        addq.w  #$1,a6
        subq.w  #$1,d1
        bne.b   loc_00050C
```

`d1` começa em 6 e o teste é `subq`/`bne`, portanto o corpo corre com `a6` em
`$10031C`…`$100321` — **seis** posições. Se as seis estiverem cheias o laço acaba com
`d1 = 0` sem escrever: **o comando é descartado em silêncio**.

`symbols/main68k.sym` declara `g_snd_queue` com 7 bytes; o sétimo (`$100322`) é o início de
`g_area_pct_step_delay` e nunca é tocado por estas rotinas. O próprio ficheiro de símbolos já
regista a observação.

A drenagem, chamada de `$000438`:

```
snd_drain_queue:
        lea.l   $31C(a5),a6             ; g_snd_queue ($10031C)         $000520  4ded031c
        moveq   #$6,d1                                                  $000524  7206
loc_000526:
        tst.b   (a6)
        beq.b   loc_000534
        move.b  (a6),d0
        bsr.w   snd_send_if_allowed                                     $00052C  6100ff54
        clr.b   (a6)
        rts                             ; um por frame, e sai
loc_000534:
        addq.w  #$1,a6
        subq.w  #$1,d1
        bne.b   loc_000526
```

Envia o **primeiro** slot ocupado e retorna. Não é uma FIFO estrita: como a inserção também
procura o primeiro slot livre, um comando inserido num buraco deixado por outro salta à
frente.

### 2.5 Quando é que a fila é drenada

`snd_drain_queue` tem um único chamador, e está dentro de um ramo condicional do VBLANK:

```
$00041C  move.w  $22(a5),d0              ; g_seq_mode ($100022)
$000420  cmpi.w  #$3,d0
$000424  beq.b   loc_000434
$000426  cmpi.w  #$5,d0
$00042A  bne.b   loc_00043E
$00042C  cmpi.w  #$E,$24(a5)             ; g_seq_step ($100024)
$000432  bne.b   loc_00043E
loc_000434:
$000434  bsr.w   vram_frame_draw_all
$000438  bsr.w   snd_drain_queue
```

Isto é, **a fila só é drenada com `g_seq_mode` = 3, ou = 5 com `g_seq_step` = `$E`** — o mesmo
ramo que redesenha a camada bitmap. O modo 3 é posto por `player_spawn` (`$0008F8`,
em `game_play_script.asm`) e por `coin_credit_tick` (`$0067EC`); o 5 por `game_abort_to_attract` (`$0032E6`). Nos restantes
estados de ecrã os pedidos enfileirados ficam parados. As vias directa e guardada
(`$000490`/`$000482`), essas, funcionam em qualquer estado — e é por elas que passam os sons
de menu, moeda e fim de jogo. Ver [`docs/06-gameplay.md`](06-gameplay.md) para o significado
de `g_seq_mode`.

### 2.6 O arranque

O reset dá o pulso na linha de RESET do Z80 (`$0014E8`–`$001510`, ver
[`docs/01-hardware.md` §7.3](01-hardware.md)), envia `$EF` e depois chama
`snd_read_dipswitches` **cinco vezes**, intercaladas com trabalho lento:

```
$001518  jsr (snd_send_unmute).l        ; $EF
$00151E  jsr (snd_read_dipswitches).l   ; passo 0: envia $EE
$001524  ... pal_init_all, pal_patch_four_entries, cchip_boot_handshake ...
$001548  jsr (snd_read_dipswitches).l   ; passo 1: pede $FA, le DSWA
$001554  ... vram_clear_page0 ...
$00155E  jsr (snd_read_dipswitches).l   ; passo 2: pede $FB, le DSWB
$001564  ... vram_clear_page1 ...
$00156E  jsr (snd_read_dipswitches).l   ; passo 3: envia $EF
$001574  jsr (snd_read_dipswitches).l   ; passo 4: rts imediato
$00157A  move.w $2E(a5),d0              ; ja' pode usar g_dswb
```

O passo vive em `$100060` (`g_dsw_read_step`). Os passos 1 e 2 contêm esperas activas pelo
latch; ao intercalá-los com a limpeza da VRAM e com o *handshake* do C-Chip, o código dá
tempo ao Z80. É uma máquina de estados usada como co-rotina, sem escalonador.

Detalhe do passo 1, que mostra que o pedido `$FA` **não** passa por `snd_send_byte`:

```
$0073B6  move.w  #$A,$2(a3)             ; nibble baixo
$0073BC  move.w  #$F,$2(a3)             ; nibble alto  -> byte $FA
```

O mesmo bloco existe para `$FB` em `$007404`/`$00740A`.

### 2.7 O auto-teste e o tocador do modo TEST

`selftest_service_mode.asm` testa o caminho de som de ponta a ponta:

```
$013F4E  move.b  #$F0,d0
$013F52  jsr     (snd_send_byte).l          ; liga o modo eco no Z80
$013F58  lea.l   snd_selftest_pattern(pc),a0
loc_013F5C:
$013F5C  move.b  (a0)+,d2
$013F5E  cmpi.b  #$FF,d2 / beq loc_013F96
$013F64  move.b  d2,d0
$013F66  jsr     (snd_send_command).l
$013F6C  jsr     (snd_read_reply_byte).l    ; d0 = nibble baixo, d1 = nibble alto
$013F72  lsl.b   #$4,d1 / andi.b #$F,d0 / or.b d1,d0
$013F7A  cmp.b   d0,d2 / beq loc_013F5C     ; senao: "SOUND ERROR" e trava
```

O padrão em `$01401C` é `$00,$01,$02,$04,$08,$10,$20,$40,$80,$FF` — zero mais cada bit
isolado: é um teste às linhas do latch, não ao driver. O `$FF` termina o laço e nunca chega a
ser enviado. No fim, `$F0` outra vez (`$013F96`/`$013F9A`) para desligar o eco.

Isto identifica o consumidor de `snd_read_reply_byte`: ele lê **dois nibbles de um byte**,
não duas words.

O modo TEST tem ainda um tocador manual, `test_play_sound_code` (`$014362`), em que o
manípulo esquerda/direita mexe `$1003A6` e o botão 1 envia o código. O filtro é explícito:

```
$014366  tst.b   d0        / beq  -> nada          ; $00 nunca
$01436A  cmpi.b  #$4,d0    / beq  -> nada          ; $04 nunca
$014370  cmpi.b  #$2F,d0   / bcs  -> envia         ; $01-$03 e $05-$2E
$014376  cmpi.b  #$F1,d0   / bcs  -> nada          ; $2F-$F0 nunca
$01437C  cmpi.b  #$FF,d0   / bcc  -> nada          ; $FF nunca
$014382  jsr     (snd_send_command).l              ; $F1-$FE
```

É por aqui, e só por aqui, que os comandos que o jogo nunca envia podem ser ouvidos numa
placa real.

---

## 3. O lado do Z80 — transporte

### 3.1 Reset e inicialização

O vector de reset tem oito bytes e transborda para o vector `RST $08`:

```
reset_entry:
        di                              ; $0000  F3
        im      1                       ; $0001  ED 56
        ld      a,$05                   ; $0003  3E 05
        ld      (PC060HA_PORT),a        ; $0005  32 00 88
rst_08:
        ld      (PC060HA_COMM),a        ; $0008  32 01 88   modo 5 = NMI off
        jp      loc_0181                ; $000B  C3 81 01
```

Isto inutiliza `RST $08` como vector, e `RST $10` a `RST $30` são `nop`. **Não existe uma
única instrução `rst` em toda a ROM de som** (verificado por varrimento da listagem), pelo que
nenhum dos sete vectores de restart é usado. Se um documento afirmar que algo salta para
`$0008`, o mais provável é ter apanhado os bytes `08 00` em `$1773` — que são a word de
parâmetro da entrada 1 de `seq_ext_jumps` (`$176D`).

`loc_0181` faz a inicialização toda: drena o latch (duas leituras em modo 0), põe
`SP = $8800`, limpa `$8000`–`$87FF`, zera `$87A6` (mudo), semeia nove campos de contexto
(`$8011`, `$8012`, `$801B`, `$80BB`, `$8013`, `$80B3` e os três `ctx+$10` das camadas 0 do FM
em `$8150`/`$8270`/`$8390`), escreve `$00` em `$9800`, programa o YM2203 (§4) e entra no laço
principal com a NMI armada.

### 3.2 A NMI: quatro destinos

O esqueleto da NMI e a montagem dos nibbles estão em
[`docs/02-mapa-de-memoria.md` §4.3](02-mapa-de-memoria.md). O que interessa aqui é o
encaminhamento do byte já montado, a partir de `$00D2`:

```
loc_00D2:
        call    sub_0136                ; empurra para a FIFO se < $F0
        jr      nc,loc_0126             ; conseguiu: sai
nmi_read_dipswitch_reply:
        cp      $FA / jr z,$00DF
        cp      $FB / jr nz,loc_0101    ; $FA/$FB: responde ja', dentro da NMI
loc_0101:
        cp      $FF / jr nc,loc_0126    ; $FF: ignorado
        ...                             ; $F0-$FE: copia inline do push da FIFO
loc_0126:
        call    sub_015F                ; regista no anel de $8742
```

| Faixa | Destino |
|---|---|
| `$00`–`$EF` | FIFO circular de 16 bytes em `$8782` (`sub_0136`, `$0136`) |
| `$FA`, `$FB` | respondidos dentro da NMI: registo `a - $EC` do YM2203 (`$0E` = porta A = DSWA, `$0F` = porta B = DSWB) devolvido em dois nibbles |
| `$F0`–`$FE` menos `$FA`/`$FB` | FIFO, por uma cópia inline do mesmo código (`$0105`–`$0125`) |
| `$FF` | descartado |

A FIFO propriamente dita:

```
sub_0136:
        cp      $F0 / jr nc,loc_015D    ; >= $F0 -> carry, nao empurra
        ld      b,a
        ld      a,(ram_8781) / ld c,a   ; indice de leitura
        ld      a,(ram_8780)            ; indice de escrita
        inc     a / and $0F
        cp      c / jr nz,loc_0149
        inc     c                       ; cheio: avanca a leitura, perde o mais antigo
loc_0149:
        ld      l,a / ld h,$00
        ld      (ram_8780),a
        ld      a,c / and $0F / ld (ram_8781),a
        ld      a,b
        ld      bc,ram_8782 / add hl,bc / ld (hl),a
        and     a                       ; carry limpo = empurrado
        ret
```

Em transbordo perde o comando **mais antigo**, não o novo. Com um byte por frame do lado do
68000 e a fila esvaziada por inteiro em cada passagem do laço principal, o caso não ocorre em
jogo.

**A segunda fila.** `sub_015F` (`$015F`) é o mesmo código com índices `$8740`/`$8741`, máscara
`$1F` e buffer em `$8742` — um anel de 32 bytes onde *todos* os bytes aceites são registados.
`build/z80_map.json` conta as referências absolutas: `ram_8742` aparece **uma** vez (`$017B`,
como base de escrita) e `ram_8740`/`ram_8741` duas cada, todas dentro de `sub_015F`. Nada lê
este anel: é um registo de diagnóstico deixado na ROM final.

### 3.3 O laço principal e o modo eco

```
loc_020E:
        di / call sub_028A / ei         ; despacha tudo o que estiver na FIFO
        di
        ld      a,$05 / ld (PC060HA_PORT),a / ld (PC060HA_COMM),a   ; NMI off
        ld      a,(ram_87A7) / bit 0,a / jr z,loc_024A              ; modo eco ligado?
        bit     1,a / jr z,loc_024A                                 ; ha' byte pendente?
        res     1,a / ld (ram_87A7),a
        ld      a,(ram_87A9) / and a / ld a,$00 / jr z / ld a,$02   ; par 0/1 ou 2/3
        ld      (PC060HA_PORT),a
        ld      a,(ram_87A8) / ld (PC060HA_COMM),a                  ; nibble baixo
        rrca x4 / ld (PC060HA_COMM),a                               ; nibble alto
        sub     a / ld (ram_87A9),a
loc_024A:
        ld      a,$06 / ld (PC060HA_PORT),a / ld (PC060HA_COMM),a   ; NMI on
        ei / jr loc_020E
```

O laço não faz mais nada: todo o trabalho de som acontece na IRQ. O `di` não bloqueia a NMI,
por isso o código desarma-a também ao nível do PC060HA (modos 5 e 6) sempre que mexe na FIFO.

O modo eco liga-se e desliga-se com o comando `$F0`:

```
loc_0425:
        ld      a,(ram_87A7) / cpl / and $01 / ld l,a
        ld      a,(ram_87A7) / and $FE / or l
        ld      (ram_87A7),a            ; inverte o bit 0
```

Com o bit 0 de `$87A7` a 1, `sub_028A` desvia **qualquer** byte abaixo de `$E0` para
`$87A8`, põe o bit 1 e não toca nada:

```
        ld      a,(hl) / cp $E0 / jr nc,loc_02D6
        ld      b,a
        ld      a,(ram_87A7) / bit 0,a / ld a,b / jr z,loc_02CD
        ld      (ram_87A8),a            ; guarda para devolver
        ld      a,(ram_87A7) / set 1,a / ld (ram_87A7),a
        jr      sub_028A
```

É exactamente o que o auto-teste do 68000 usa (§2.7).

### 3.4 O despacho (`sub_028A`) — as quatro faixas

`sub_028A` (`$028A`) tira um byte da FIFO e reentra em si próprio até a esvaziar (`jr
sub_028A` em `$02CB`, `$02CF`, `$02D4`, `$02DD`, `$02E1`, `$02E6` — recursão por salto, sem
consumo de pilha).

| Faixa | Tratamento |
|---|---|
| `$00`–`$2E` | `sub_02E8` (`$02E8`): índice em `tbl_2500` (47 entradas de 2 bytes) |
| `$2F`–`$DF` | descartado (`cp $2F / jr nc` em `$02CD`) |
| `$E0`–`$EF` | `sub_0399` (`$0399`): só `$EE` e `$EF` fazem alguma coisa |
| `$F0`–`$FE` | `sub_0413` (`$0413`): tabela de 15 saltos em `$0449` |
| `$FF` | descartado (`cp $FF / jr nc` em `$02DF`) |

Na faixa `$F0`–`$FE` a entrada 0 (`$F0`) vai para `loc_0425` (o eco) e as catorze restantes
para `sub_0436`, que calcula `$255E + 2·(cmd − $F1)`. Como `$255E` fica logo a seguir a
`tbl_2500`, um desmontador vê as duas como uma tabela contígua de 61 ponteiros; são duas
tabelas com dois consumidores diferentes.

### 3.5 Silenciar (`$EE`/`$EF`)

```
sub_0399:
        cp      $EE / jr nz,loc_03B5
        ld      a,$04 / ld (PC060HA_PORT),a
        ld      a,$00 / ld (ram_87A6),a / ld (PC060HA_COMM),a       ; mudo
        ret
loc_03B5:
        cp      $EF / ret nz
        ld      a,$04 / ld (PC060HA_PORT),a
        ld      a,$01 / ld (ram_87A6),a / ld (PC060HA_COMM),a       ; som ligado
```

`$87A6` é consultado num único sítio, `sub_033C` (`$033D`): com o valor a zero, **qualquer
pedido de canal é descartado**. Não silencia o que já está a tocar; impede que comece. A
escrita em `PC060HA_COMM` com o modo 4 seleccionado é, do lado do *slave*, um não-evento
(`case 0x04` de `slave_comm_w` em `taitosnd.cpp` está vazio); não confundir com o modo 4 do
lado do *master*, que é o reset.

### 3.6 Fim de bloco: encadeamento e a resposta que nunca acontece

Quando um bloco de canal chega ao fim (`$06D7` no motor FM, `$15AA` no SSG):

```
sub_0467:
        ld      a,$05 / ...                            ; NMI off
        bit     0,(ix+$04) / jr z,loc_0493             ; ctx+$04 = selector do bloco
        ld      a,$00 / ld (PC060HA_PORT),a
        ld      a,(ix+$03) / ld (PC060HA_COMM),a       ; ctx+$03 = comando original
        rrca x4  / ld (PC060HA_COMM),a
loc_0487:
        ld      a,$04 / ld (PC060HA_PORT),a
        ld      a,(PC060HA_COMM) / bit 2,a / jr nz,loc_0487   ; espera o 68000 ler
loc_0493:
        ld      a,(ix+$08) / call sub_0136             ; ctx+$08 = byte de encadeamento
        jr      c,loc_049E
        call    sub_015F
loc_049E:
        ld      a,$06 / ...                            ; NMI on
```

Duas coisas de uma vez:

1. **Se o selector do bloco for ímpar**, o Z80 devolve ao 68000 o byte de comando que originou
   o pedido e **espera** que o 68000 o leia. Percorrendo os 140 blocos de canal alcançáveis
   das duas tabelas, os selectores usados são `$84`, `$86`, `$8C`, `$8E`, `$90`, `$92`, `$94`
   e `$96` — **todos pares**. Este ramo nunca corre, o que é bom: o 68000 não lê essa resposta
   fora do auto-teste e o Z80 ficaria preso no `jr nz,loc_0487`.
2. O byte `+3` do bloco é reinjectado na FIFO se for `< $F0`, encadeando um segundo comando ao
   fim do primeiro. Nos 140 blocos, esse byte é `$FF` em todos menos cinco:

   | Bloco | Canal / comando de origem | Encadeia |
   |---|---|---|
   | `$2D00` | FM1 camada 1, comando `$07` | `$06` |
   | `$2D80` | FM1 camada 1, comando `$09` | `$0A` |
   | `$30C0` | FM1 camada 1, comando `$16` | `$10` |
   | `$3100` | FM1 camada 1, comando `$17` | `$10` |
   | `$3400` | FM1 camada 1, comando `$23` | `$10` |

   São pares "introdução → tema" montados nos dados, sem o 68000 ter de saber. O encadeamento
   está sempre no bloco do canal FM 1: se estivesse nos três, o comando seguinte seria pedido
   três vezes. **É por aqui, e só por aqui, que o comando `$0A` chega a tocar** — nenhuma
   rotina do jogo o envia.

---

## 4. O relógio do driver

A IRQ do Z80 vem do YM2203 (`ymsnd.irq_handler().set_inputline(m_audiocpu, 0)` em
`volfied.cpp`), em modo 1: `$0038` → `jp $0255`.

```
loc_0255:
        push af/bc/de/hl/ix/iy
loc_025D:
        ld      a,(YM2203_REG) / and $01 / jr z,loc_025D   ; espera a flag do Timer A
        ld      hl,YM2203_REG
        ld      b,$27
        ld      a,(ram_87A0) / bit 0,a
        ld      a,(ram_879F)                               ; = $05
        jr      z,loc_0275 / or $40                        ; modo especial do canal 3
loc_0275:
        or      $10                                        ; rearma a flag do Timer A
        call    sub_0F62
        call    sub_04A7                                   ; motor FM
        call    sub_13F4                                   ; motor SSG
        pop ... / ei / ret
```

A programação do temporizador está no arranque:

```
$01D0  ld a,$2D / ld (YM2203_REG),a     ; escrita so' no porto de endereco: selector de prescaler
$01D5  ld hl,YM2203_REG
$01D8  ld de,$0070 / ld c,e / ld b,$06
$01DE  sla e / rl d / djnz              ; de = $0070 << 6 = $1C00
$01E4  ld b,$24 / ld a,d ($1C) / call sub_0F62   ; reg $24 = TA[9:2]
$01EA  ld b,$25 / ld a,c and $03 ($00)  / call   ; reg $25 = TA[1:0]
$01F2  ld b,$26 / ld a,$C7 / call                ; reg $26 = Timer B
$01F9  ld b,$27 / ld a,$35 / call                ; reg $27
$0200  and $0F / ld (ram_879F),a                 ; $35 & $0F = $05
```

O valor de 10 bits do Timer A é `($1C << 2) | $00` = **112**. O `$35` inicial carrega o
Timer A, activa a sua IRQ e limpa as duas flags; o Timer B recebe `$C7` mas **nunca é
activado** (bits 1 e 3 de `$35` a zero). `$879F` guarda `$05`, que a IRQ reescreve com `|$10`
(limpar a flag) e, em teoria, `|$40` (modo especial do canal 3 — ver §6.5: nunca acontece).

Com o prescaler ÷6 o período do Timer A é `12 × (1024 − 112) / (4 MHz / 6) = 16,42 ms`, ou
seja **≈60,9 Hz**: praticamente o ritmo do frame, coerente com o 68000 enviar um comando por
VBLANK. **A divisão do prescaler não é verificável dentro deste repositório** — o modelo do
YM2203 do MAME não está em `reference/mame/`. Ver §7.4 e §11.

Todas as escritas no YM2203 passam por `sub_0F62` (`$0F62`), documentado em
[`docs/02-mapa-de-memoria.md` §4.4](02-mapa-de-memoria.md), que respeita o bit BUSY nas duas
fases. O motor SSG faz o mesmo à mão, com nove `nop` em vez do teste de BUSY (`$1490`–`$1498`,
`$14B3`–`$14BB`, `$14D1`–`$14D9`, `$14E1`–`$14E9`). Dois estilos, na mesma ROM.

---

## 5. As estruturas de dados

Três níveis, do comando ao fluxo de notas:

```
comando ($00-$2E)  --tbl_2500-->  BLOCO DE PEDIDO  --(N ponteiros)-->  BLOCO DE CANAL
                                                                             |
                                                                    (M registos de faixa)
                                                                             |
                                                                     FLUXO DE SEQUENCIA
```

Contagens, obtidas percorrendo as duas tabelas a partir da imagem: **50** blocos de pedido
distintos, **140** blocos de canal distintos, **136** fluxos distintos (133 FM + 3 SSG).

### 5.1 As duas tabelas de comandos

| Tabela | Endereço | Entradas | Consumidor |
|---|---|---|---|
| `tbl_2500` | `$2500`–`$255D` | 47 (`$00`–`$2E`) | `sub_02E8` (`$02F6`) |
| efeitos | `$255E`–`$2579` | 14 (`$F1`–`$FE`) | `sub_0436` (`$043C`) |

A tabela de efeitos é quase toda repetição:

```
$255E: 2BB0 2B00 2BB0 2B30 2BB0 2B60 2BB0 2BB0 2BB0 2BB0 2BB0 2BB0 2BB0 2BB0
        F1   F2   F3   F4   F5   F6   F7   F8   F9   FA   FB   FC   FD   FE
```

Só três das catorze entradas apontam para blocos próprios — `$F2` → `$2B00`, `$F4` → `$2B30`,
`$F6` → `$2B60`. As outras onze apontam para `$2BB0`, **o mesmo bloco do comando `$00`**, isto
é, "parar tudo". Não são catorze efeitos: são três, mais onze cópias de um silêncio.

### 5.2 Bloco de pedido

O interpretador é `sub_02FE` (`$02FE`). A regra é o primeiro byte:

```
        ld      a,(bc) / and a / ret z      ; 0 = nada a fazer
        cp      $09 / jr c,loc_0309         ; < 9 = e' uma contagem
        call    sub_033C / ret              ; >= 9 = o bloco JA' E' um bloco de canal
```

Quando é uma contagem `N` (1 a 8), seguem-se `N` words little-endian:

| Word | Significado |
|---|---|
| byte alto = `$00` | o byte baixo é um **comando a reinjectar na FIFO** (`$0313`–`$0329`) |
| byte alto ≠ `$00` | é um **ponteiro** para um bloco de canal, processado por `sub_033C` |

O ramo de reinjecção está compilado mas **não há uma única word com o byte alto a zero em
nenhum dos 50 blocos** (verificado por varrimento). Exemplo real, `$2BE0` (comando `$02`):

```
$2BE0  03  00 2C  20 2C  40 2C
       |   |      |      +-- ponteiro 2 -> $2C40
       |   |      +--------- ponteiro 1 -> $2C20
       |   +---------------- ponteiro 0 -> $2C00
       +-------------------- N = 3
```

Os comandos `$03` e `$04` exercitam o outro ramo: `tbl_2500[$03] = $2C50`, cujo primeiro byte
é `$84` (≥ 9), portanto o bloco *é* um bloco de canal.

### 5.3 Bloco de canal e registos de faixa

Cabeçalho fixo de 4 bytes seguido de 3 bytes por faixa. Os destinos vêm de `sub_0615`
(`$0615`, FM) e `ssg_seq_start` (`$14F6`, SSG), que são o mesmo código escrito duas vezes.

| Offset | Conteúdo | Vai para |
|---|---|---|
| `+0` | **selector** `$84`–`$97` | `ctx+$04` |
| `+1` | nibble alto = prioridade, nibble baixo = repetições do bloco (0 → 16) | `ctx+$06` |
| `+2` | número de faixas | `ctx+$07` |
| `+3` | byte de encadeamento (`$FF` = nenhum) | `ctx+$08` |
| `+4`… | registos de faixa, 3 bytes cada | `ctx+$0D`/`$0E` aponta para o corrente |

Registo de faixa (lido por `sub_0640`, `$0640`):

| Byte | Conteúdo | Vai para |
|---|---|---|
| `+0` nibble alto | prioridade da faixa | `ctx+$05` |
| `+0` nibble baixo | repetições da faixa (**0 = repete para sempre**) | `ctx+$0A` |
| `+1`, `+2` | ponteiro para o fluxo de sequência | `ctx+$0B`/`$0C` |

Ainda no `sub_033C`, antes disto: `ctx+$01`/`$02` recebem o ponteiro do bloco e **`ctx+$03`
recebe o byte de comando original** — é ele que `sub_0467` devolveria ao 68000 (§3.6).

O avanço de faixa é `sub_0690` (`$0690`), chamado quando um evento tem duração `$00`:

1. `ctx+$0A` > 1: decrementa e **recarrega o ponteiro da mesma faixa** — a faixa repete;
2. `ctx+$0A` == 0: recarrega sem decrementar — repete para sempre;
3. `ctx+$0A` chegou a 1: decrementa `ctx+$07` e avança 3 bytes no registo de faixa;
4. faixas esgotadas: decrementa `ctx+$06` e recomeça do `+4` do bloco;
5. repetições esgotadas: `ctx+$00 = 0`, reinicializa (`sub_0657`) e chama `sub_0467` (§3.6).

Nos 140 blocos, **todos** têm 1 repetição de bloco; 136 têm uma faixa e 4 têm duas (`$2B50`
do efeito `$F4`, e `$2B80`/`$2B90`/`$2BA0` do `$F6`). O padrão de duas faixas é sempre
"ataque com 1 repetição, corpo com repetição infinita". Das 144 faixas, 121 têm repetição 1 e
23 têm o nibble a zero, isto é, repetem para sempre.

### 5.4 Contextos, camadas e prioridade

`sub_033C` (`$033C`) converte o selector em contexto pela tabela `dat_0385`:

```
dat_0385:
        defb    $00,$80,$A0,$80,$00,$00,$00,$00,$40,$81,$D0,$81,$60,$82,$F0,$82
        defb    $80,$83,$10,$84
```

| Selector | Índice | Contexto | Papel |
|---|---|---|---|
| `$84`/`$85` | 0 | `$8000` | SSG, camada 0 |
| `$86`/`$87` | 2 | `$80A0` | SSG, camada 1 |
| `$88`–`$8B` | 4, 6 | `$0000` | **inválidos** — a entrada é rejeitada |
| `$8C`/`$8D` | 8 | `$8140` | FM canal 1, camada 0 |
| `$8E`/`$8F` | `$0A` | `$81D0` | FM canal 1, camada 1 |
| `$90`/`$91` | `$0C` | `$8260` | FM canal 2, camada 0 |
| `$92`/`$93` | `$0E` | `$82F0` | FM canal 2, camada 1 |
| `$94`/`$95` | `$10` | `$8380` | FM canal 3, camada 0 |
| `$96`/`$97` | `$12` | `$8410` | FM canal 3, camada 1 |

O teste de "contexto inexistente" é `cp e` (byte alto igual ao baixo), não um teste a zero; o
bit 0 do selector é mascarado com `$FE` e sobrevive só em `ctx+$04`, onde controla a resposta
ao 68000.

Cada canal do YM2203 tem **duas camadas**: dois contextos independentes que interpretam
sequências ao mesmo tempo e partilham os registos do chip. Quem decide o que se ouve é o motor
de emissão (§6.1): se a camada 0 estiver a tocar (`bit 1` de `ctx+$00`), a camada 1 é saltada
por inteiro. Quando a camada 0 pára, o motor força uma reemissão completa da camada 1
(`ctx+$0F` bit 2, `ctx+$10 = $F0`, `ctx+$12 = $80` ou `$C0`), para que ela recupere o canal
com o estado certo. `$879C` guarda, um bit por canal, "a camada 0 esteve a tocar".

**A prioridade**, dentro do mesmo contexto:

```
        ld      a,(de) / bit 1,a / jr z,loc_0376        ; nao esta' a tocar: aceita
        ld      hl,$0005 / add hl,de / ld l,(hl)        ; l = ctx+$05 = prioridade em curso
        inc bc / ld a,(bc) / dec bc / and $F0 / ld h,a  ; h = prioridade do pedido
        ld      a,l / cp h / jr c,loc_0383              ; l < h -> recusa
```

Aceita quando `ctx+$05 >= nova`. Logo, **valor menor = mais importante**. Confirma-se nos
dados: os blocos de silêncio (`$2BF0`–`$2C60`) têm prioridade 1, o mínimo usado, e por isso
interrompem tudo; as prioridades dos blocos com música vão de 3 a 9.

### 5.5 A tabela dos 47 comandos

Decodificada de `build/audiocpu.bin` seguindo `tbl_2500` → bloco de pedido → blocos de canal;
a coluna "quem envia" vem do varrimento de `src/main68k/*.asm` cruzado com `build/m68k_map.json`.
`C0`/`C1` = camada. As prioridades são todas iguais dentro de cada comando.

| Cmd | Bloco | Contextos | Pri | Fluxos | Quem envia |
|---|---|---|---|---|---|
| `$00` | `$2BB0` | FM1/2/3 C0+C1, SSG C0+C1 | 1 | `$3792`×6, `$379A`×2 | directa: `game_round_run_frame`, `inp_tilt_check`, `player_death_sequence` |
| `$01` | `$2BD0` | FM1/2/3 C0 | 1 | `$3792`×3 | directa: `game_countdown_tick`; guardada: `game_round_clear_start` |
| `$02` | `$2BE0` | FM1/2/3 C1 | 1 | `$3792`×3 | directa: `game_abort_to_attract`, `game_coinwait_music`, `hud_draw_gameover_items`; fila: `snd_cue_alarm_tick`, `sub_029066` |
| `$03` | `$2C50` | SSG C0 | 1 | `$379A` | — |
| `$04` | `$2C60` | SSG C1 | 1 | `$379A` | — |
| `$05` | `$2C70` | FM1/2/3 C1 | 8 | `$37A7` `$3848` `$3899` | guardada: `game_seq_req_task5` |
| `$06` | `$2CB0` | FM1/2/3 C1 | 8 | `$38E3` `$391F` `$395C` | guardada: `game_seq_show_player_msg`; encadeado de `$07` |
| `$07` | `$2CF0` | FM1/2/3 C1 | 8 | `$39CE` `$3A19` `$3A39` | guardada: `sub_0036C8` |
| `$08` | `$2D30` | FM1/2/3 **C0** | 8 | `$3A69` `$3A7D` `$3A91` | guardada: `game_add_score` (vida extra) |
| `$09` | `$2D70` | FM1/2/3 C1 | 8 | `$3AAD` `$3B2D` `$3BAC` | guardada: `sub_003BE6`; fila: `snd_cue_rumble_tick` |
| `$0A` | `$2DB0` | FM1/2/3 C1 | 8 | `$3BFC` `$3E0E` `$3F8D` | **só por encadeamento de `$09`** |
| `$0B` | `$2DF0` | FM1/2/3 C1 | 8 | `$4064` `$40EF` `$4110` | guardada: `game_hiscore_rank_screen` |
| `$0C` | `$2E30` | FM1/2/3 C1 | 8 | `$4147` `$4172` `$4195` | guardada: `game_over_show_msg`, `game_over_show_player_msg` |
| `$0D` | `$2E70` | FM1/2/3 C1 | 7 | `$41B6` `$41DE` `$4206` | fila: `snd_trail_loop_update` |
| `$0E` | `$2EB0` | FM1/2/3 C1 | 7 | `$4242` `$4259` `$4270` | fila: `snd_trail_loop_update` |
| `$0F` | `$2EF0` | FM1/2/3 C1 | 7 | `$4281` `$428F` `$429D` | fila: `spark_spawn_first` |
| `$10` | `$2F30` | FM1/2/3 C1 | 7 | `$42AC` `$42BF` `$42DA` | fila: `inp_read_cchip`, `snd_draw_loop_retrigger`; encadeado de `$16`/`$17`/`$23` |
| `$11` | `$2F70` | FM1/2/3 C0 | 7 | `$42F6` `$4302` `$4316` | fila: `enemy_update_one` |
| `$12` | `$2FB0` | FM1/2/3 C0 | 7 | `$432C` `$4340` `$4354` | fila: `enemy_update_one` |
| `$13` | `$2FF0` | FM1/2/3 C0 | 8 | `$4368` `$4376` `$4384` | — |
| `$14` | `$3030` | FM1/2/3 C0 | 8 | `$4398` `$43AC` `$43C2` | guardada: `player_entry_animation` |
| `$15` | `$3070` | FM1/2/3 C0 | 8 | `$4418` `$4432` `$4451` | guardada: `player_entry_animation` |
| `$16` | `$30B0` | FM1/2/3 C1 | 7 | `$446B` `$4472` `$447B` | fila: `sub_029006` |
| `$17` | `$30F0` | FM1/2/3 C1 | 7 | `$4484` `$4497` `$44AC` | fila: `sub_029066` |
| `$18` | `$3130` | FM1/2/3 C1 | 5 | `$44C1` `$44CC` `$44E2` | fila: `snd_trail_loop_update` |
| `$19` | `$3170` | FM1/2/3 C0 | 5 | `$44FA` `$4541` `$458A` | — |
| `$1A` | `$31B0` | FM1/2/3 C0 | 7 | `$45D3` `$45E6` `$4600` | fila: **26 rotinas** (ver abaixo) |
| `$1B` | `$31F0` | FM1/2/3 C0 | 6 | `$4616` `$4621` `$4631` | fila: `game_countdown_tick` |
| `$1C` | `$3230` | FM1/2/3 C0 | 7 | `$463F` `$4651` `$4665` | fila: `enemy_shot_spawn_at_player`, `enemy_shot_spawn_slot0` |
| `$1D` | `$3270` | FM1/2/3 C0 | 7 | `$4679` `$4687` `$4695` | — |
| `$1E` | `$32B0` | FM1/2/3 C0 | 8 | `$46A3` `$46B6` `$46CB` | fila: 10 rotinas de nascimento de tiro |
| `$1F` | `$32F0` | FM1/2/3 C0 | 8 | `$46EC` `$4709` `$4736` | fila: `enemy_boss07_shot_spawn_or_update`, `enemy_boss10_shot_spawn_b` |
| `$20` | `$3330` | FM1/2/3 C0 | 9 | `$4765` `$4770` `$477E` | fila: `enemy_boss06_roar` |
| `$21` | `$3370` | FM1/2/3 C0 | 9 | `$478C` `$47A0` `$47B8` | — |
| `$22` | `$33B0` | FM1/2/3 C0 | 9 | `$47D6` `$4829` `$487E` | — |
| `$23` | `$33F0` | FM1/2/3 C1 | 4 | `$48D5` `$490C` `$4950` | fila: `snd_cue_alarm_tick` |
| `$24` | `$3430` | FM1/2/3 C0 | 8 | `$4995` `$499E` `$49A7` | fila: `boss02_update` |
| `$25` | `$3470` | FM1/2/3 C0 | 8 | `$49B4` `$49C8` `$49E0` | fila: `boss02_shotwave_spawn_or_update`, `enemy_boss01_shot_spawn`, `enemy_boss06_shots_spawn`, `enemy_boss13_shots_spawn` |
| `$26` | `$34B0` | FM1/2/3 C0 | 8 | `$49F6` `$4A4F` `$4AAA` | fila: `enemy_boss13_move_x`, `sub_019730` |
| `$27` | `$34F0` | FM1/2/3 C0 | 8 | `$4B05` `$4B1A` `$4B33` | fila: `boss03_attack` |
| `$28` | `$3530` | FM1/2/3 C0 | 7 | `$4B4C` `$4B6E` `$4BA9` | fila: `enemy_boss06_wall_hit` |
| `$29` | `$3570` | FM1/2/3 C0 | 8 | `$4BE5` `$4BEE` `$4BFB` | — |
| `$2A` | `$35B0` | FM1/2/3 C1 | 4 | `$4C08` `$4C33` `$4C6C` | — |
| `$2B` | `$35F0` | FM1/2/3 C0 | 4 | `$4CA5` `$4CDA` `$4D12` | directa: `coin_credit_tick` (moeda) |
| `$2C` | `$3630` | FM1/2/3 C0 | 6 | `$4D4E` `$4D5A` `$4D63` | — |
| `$2D` | `$3670` | FM1/2/3 C0 | 6 | `$4D73` `$4D8A` `$4DA9` | — |
| `$2E` | `$36B0` | FM1/2/3 C1 + **SSG C0** | 3 | `$4DC8` `$4E0F` `$4E58` `$4E99` | guardada: `game_round_clear_start` |

As 26 rotinas que enviam `$1A`: `boss02_enemy_st3_die`, `enemy_boss00_shot_st3_fly`,
`enemy_boss04_shot_st1_fly`, `enemy_boss05_shot_st1_fly`, `enemy_boss07_shot_st1_fly`,
`enemy_boss08_shot_st1_fly`, `enemy_boss09_shot_st1_fly`, `enemy_boss11_shot_st1_fly_homing`,
`enemy_grp00_st3_captured`, `enemy_grp01_st3_die`, `enemy_grp03_st3_die`,
`enemy_grp04_st3_captured`, `enemy_grp05_st3_captured`, `enemy_grp06_state_captured`,
`enemy_grp07_st7_captured`, `enemy_grp08_st3_captured`, `enemy_grp09_st3_captured`,
`enemy_grp10_st3_die`, `enemy_grp11_st3_captured`, `enemy_grp12_st3_captured`,
`enemy_grp13_state_captured`, `enemy_grp14_st3_captured`, `enemy_grp15_st3_return_home`,
`enemy_shotwave_b_st1_fly`, `sub_0201AA`, `sub_020984`.

Observações que saem só desta tabela:

- **Onze comandos não têm chamador nenhum**: `$03`, `$04`, `$13`, `$19`, `$1D`, `$21`, `$22`,
  `$29`, `$2A`, `$2C`, `$2D`. Só se ouvem pelo tocador do modo TEST (§2.7). O `$0A`, que
  também não tem chamador, chega a tocar pelo encadeamento de `$09`.
- **Só quatro comandos tocam no SSG** (`$00`, `$03`, `$04`, `$2E`) e três deles só carregam o
  fluxo de silêncio `$379A`. **`$2E` é o único comando do jogo que põe conteúdo no SSG.**
- O `$08` (vida extra) usa a camada 0 e por isso sobrepõe-se ao que estiver na camada 1.
- O `$2E` é o de prioridade mais alta (3) e é enviado uma única vez, de
  `game_round_clear_start` (`$028C82`), logo a seguir ao `$01` (`$028C78`) — "cala a camada 0,
  toca o fim de ronda".

---

## 6. O motor FM

### 6.1 O tick

`sub_04A7` (`$04A7`) corre uma vez por IRQ e faz duas passagens.

**Passagem 1 — emissão** (`$04AD`–`$05AE`), seis blocos quase idênticos, um por contexto:

```
        ld      ix,ram_8140 / ld iy,ram_8159 / ld e,$00
        call    fm_emit_channel                  ; $0CF9
        call    nc,sub_0D97                      ; $0D97 (emissao parcial)
        bit     1,(ix+$00) / jr z,loc_04CD       ; camada 0 a tocar?
        ld      a,($879C) / set 0,a / ld ($879C),a
        jr      loc_0503                         ; SALTA a camada 1
loc_04CD:
        ld      ix,ram_81D0 / ld iy,ram_81E9     ; camada 1, MESMO e (canal 0)
        ...
```

`e` é o número do canal FM (0, 1, 2) e **não é reposto entre camadas**: as duas camadas
escrevem nos mesmos registos. `iy` aponta para `ctx+$19`, o primeiro registo de operador.

**Passagem 2 — avanço das sequências** (`$05AF`–`$05CD`): `sub_05CE` percorre três contextos
com passo `$0120`, primeiro `$8140`/`$8260`/`$8380` (camada 0) e depois
`$81D0`/`$82F0`/`$8410` (camada 1), gravando o índice do canal (0, 1, 2) em `ctx+$09`.

A ordem importa: os registos do YM2203 são escritos com o estado do tick **anterior** e só
depois a sequência avança. É o que mantém a latência constante.

Por contexto, `sub_05CE` faz:

```
        bit     0,(hl) / call nz,sub_0615        ; ctx+$00 bit 0 = arranque pendente
        bit     1,(ix+$00) / jr z,...            ; ctx+$00 bit 1 = a tocar
        ld      a,(ix+$15) / ... dec ...         ; contador de gate
          -> ao chegar a 0: set 7,(ix+$12) / res 6,(ix+$12)   = KEY OFF
        dec     (ix+$13)                         ; contador de duracao
        call    z,sub_06F6                       ; le o proximo evento
        call    sub_0F6F                         ; LFO / envelope por software
```

### 6.2 `ctx+$00`, o byte de estado

Levantado de todas as instruções `bit`/`set`/`res` sobre `(ix+$00)` na listagem:

| Bit | Significado | Posto em | Lido em |
|---|---|---|---|
| 0 | pedido pendente (o bloco ainda não arrancou) | `$0379` (`sub_033C`) | `$05D8` |
| 1 | contexto a tocar | `$0615` (valor inicial `$06`) | `$04BD`, `$05DD`, `$0363`, … |
| 2 | uma nota também dispara key-on | `$0615`; `$CC $A0`/`$A1` (`$0A17`/`$0A22`) | `$07B5`, `$08E5` |
| 3 | este evento já tem nota | nota, `$8F`, `$EE`, `$EF` | limpo em `$0726` |
| 4 | key-on / portamento pendente | `$07BB`, `$08EB`, `$0CEB` | `$072A`, `$0F6F`; limpo em `$0FE0` |
| 5 | evento adiado (segunda nota no mesmo evento) | `$07AC`, `$08C3`, `$0CCA`, `$0CE2` | `$06FD`, `$0805` |
| 6 | o envelope por software produziu valor novo | `$107D` | `$1174` |
| 7 | a última nota foi key-on (e não pausa) | `$07BF`, `$08EF`, `$0CEF`; limpo por `$EE` em `$0CD3` | `$04F0`, `$0546`, `$059C` |

### 6.3 Os registos que o motor escreve

| Registo | Origem | Rotina |
|---|---|---|
| `$24`/`$25` | Timer A = 112 | arranque, `$01E4`/`$01EA` |
| `$26` | Timer B = `$C7` (carregado, nunca activado) | arranque, `$01F2` |
| `$27` | `$879F` (`$05`), com `or $10` e, em teoria, `or $40` | IRQ `$0277`; `$0D1B`/`$0D2B`/`$0DBE`/`$0DCD` |
| `$28` | key off (`a = e`) e key on (`a` = `(ctx+$17 & $F0)` ORed com `e`) | `$0785`, `$0D77`/`$0D88`, `$0E05`/`$0E13` |
| `$30`+n | DT/MULTI, de `(iy+$07) & $7F` | `sub_0EDA` (`$0EDA`) |
| `$40`+n | TL, de `(iy+$06)` **complementado**, `& $7F` | `sub_0EE6` (`$0EE6`) |
| `$50`+n | KS/AR, de `(iy+$09) & $DF` | `sub_0EF3` (`$0EF3`) |
| `$60`+n | D1R, de `(iy+$0A) & $1F` — **o bit 7 (AM) fica sempre 0** | `sub_0EF3` |
| `$70`+n | D2R, de `(iy+$0B) & $1F` | `sub_0EF3` |
| `$80`+n | SL/RR, de `(iy+$0C)` | `sub_0EF3` |
| `$90`/`$94`/`$98`/`$9C` + c | SSG-EG, de `ctx+$4D`…`$50`, `& $0F` | `sub_0F22` (`$0F22`) |
| `$A0`+c / `$A4`+c | F-number / bloco, de `ctx+$41` e `ctx+$44 & $3F` | `sub_0E75` (`$0E75`) |
| `$A8`–`$AE` | frequências dos *slots* do canal 3 | `sub_0E8C` (`$0E8C`) — **nunca corre**, ver §6.5 |
| `$B0`+c | FB/ALG, de `ctx+$18 & $3F` | `sub_0ECE` (`$0ECE`) |

`n` é o deslocamento do operador na numeração do YM2203: operador 1 = `+0`, 2 = `+8`, 3 =
`+4`, 4 = `+$C`. O driver guarda os operadores por ordem 1, 2, 3, 4 em blocos de **13 bytes**
consecutivos (op1 em `ctx+$19`, op2 em `ctx+$26`, op3 em `ctx+$33`, op4 em `ctx+$40`) e faz a
permutação na emissão. `fm_emit_channel` fá-lo andando `iy` de `+$1A` e recuando `-$27` a meio
(`$0D5F`), o que produz a visita op1, op3, op2, op4 com `e` = 0, 4, 8, `$C`; `sub_0E17`
(`$0E17`) faz o mesmo por `push`/`ret` com os deslocamentos `0`, `8`, `4`, `$C` explícitos.

Registos **nunca escritos**: `$22`, `$29`, `$2A`–`$2C`, e `$A8`–`$AE`. Os registos `$07` e
`$08`–`$0A` são escritos, mas pelo motor SSG (§8).

### 6.4 As máscaras de sujidade

Cada contexto tem três bytes de "há coisas por escrever". O mapeamento sai directamente da
word que cada *handler* devolve em `de`: `e` ∈ {1, 2, 3} escolhe `ctx+$0F+e`, e `d` é a
máscara de bits a acender (`loc_0805`, `$0805`).

| Byte | Bits | O que marca |
|---|---|---|
| `ctx+$10` | 0–3 = operador 1–4 | TL mudou → reg `$40`+n |
| | 4, 5, 6 | frequências dos *slots* 1, 2, 3 do canal 3 → regs `$A8`–`$AE` |
| | 7 | nota principal mudou → regs `$A0`/`$A4` |
| `ctx+$11` | 0–3 = operador | DT/MUL mudou → reg `$30`+n |
| | 4–7 = operador | SSG-EG mudou → regs `$90`+ |
| `ctx+$12` | 0–3 = operador | envelope mudou → regs `$50`/`$60`/`$70`/`$80` |
| | 4 | FB/ALG mudou → reg `$B0` |
| | 5 | modo do canal 3 → reg `$27` e `sub_0E8C` |
| | 6 | key **on** a seguir ao key off |
| | 7 | escrever o reg `$28` |

Exemplos verificados: `seqcmd_op1_tl` (`$094E`) devolve `$0101` (bit 0 de `ctx+$10`);
`seqcmd_op1_env` (`$097E`) devolve `$0103` (bit 0 de `ctx+$12`); `seqcmd_note_freq` (`$08BD`)
devolve `$8001` (bit 7 de `ctx+$10`); `seqcmd_slot1_freq` (`$0875`) devolve `$1001` (bit 4 de
`ctx+$10`).

`fm_emit_channel` (`$0CF9`) faz a emissão **completa** e só corre se o bit 2 de `ctx+$0F`
estiver posto (pedido explícito de reemissão, posto pelo carregamento de instrumento em
`$0B2A` e pela recuperação de camada em `$04E7`/`$053D`/`$0593`); devolve carry. `sub_0D97`
(`$0D97`) faz a emissão **incremental** guiada pelas três máscaras e é chamada com `call nc` —
exactamente quando a completa não correu. As máscaras são zeradas nos dois caminhos.

### 6.5 O modo especial do canal 3 nunca é ligado

O bit 0 de `ctx+$17` é o que activaria o modo multi-frequência do canal 3 (reg `$27` com bit
6, e a emissão dos registos `$A8`–`$AE` por `sub_0E8C`). `ctx+$17` só é escrito em três
sítios: `sub_0657` (a zero), o comando `$CC` com operando `$80`–`$9F` (`$0A0C`), e o
carregador de instrumentos (`$0A93`). Nos dois casos o valor é `(operando & $1F)` rodado 4
posições à direita, ou seja o bit 0 só fica a 1 se o bit 4 do operando estiver a 1.

Percorrendo os dados:

- dos 67 instrumentos, **nenhum** tem o bit 4 posto no byte 0;
- em todos os 133 fluxos FM só há dois comandos `$CC` na faixa `$80`–`$9F`: `$88` e `$8F`,
  ambos no bloco do efeito `$F4`. Dão `ctx+$17` = `$80` e `$F0`, com o bit 0 a zero.

Portanto `ram_87A0` bit 0 nunca fica a 1, o reg `$27` nunca leva `|$40`, `sub_0E8C` nunca é
chamada e os registos `$A8`–`$AE` nunca são escritos. Os 25 comandos `$8D` que existem nos
dados (e a total ausência de `$8C` e `$8E`) escrevem campos de contexto que ninguém emite.

### 6.6 Duração e *gate*

Ao ler um evento, `sub_06F6` (`$06F6`) faz:

```
        ld      (ix+$13),a          ; a = duracao em ticks
        ld      e,a
        ld      h,(ix+$16)          ; razao de gate (comando $ED)
        call    seq_mul_gate        ; hl = h * e  (multiplicacao 8x8 por deslocamento, $0C80)
        ld      de,$0080 / add hl,de
        ld      (ix+$15),h          ; gate = (razao * duracao + 128) / 256
```

`ctx+$13` conta os ticks até ao evento seguinte; `ctx+$15` conta os ticks até ao **key off**.
`sub_0657` inicializa `ctx+$16` a zero, e **o comando `$ED` não aparece uma única vez nos
dados**: o *gate* é sempre 0, o teste `ld a,(ix+$15) / and a / jr z` salta sempre a contagem, e
por isso **cada nota toca até ao evento seguinte**. O contador de gate está implementado e
nunca é usado.

---

## 7. O formato das sequências FM

### 7.1 Evento

```
[duracao] [atributo] [operandos] [atributo] [operandos] ... [duracao] ...
```

- **duração**: 1 byte. `$00` termina a faixa (chama `sub_0690`, §5.3).
- **atributo**: 1 byte com o **bit 7 sempre a 1**. O primeiro byte com o bit 7 a 0 termina a
  lista — e esse byte é já a duração do evento seguinte. Não há terminador dedicado.

O leitor é `sub_079B` (`$079B`):

```
sub_079B:
        inc     bc / ld a,(bc)
        bit     7,a / ret z             ; sem bit 7: fim da lista (e proxima duracao)
        and     $0F / cp $0C
        jr      nc,loc_07E9             ; nibble baixo >= $C -> COMANDO
        ...                             ; nibble baixo < $C  -> NOTA
```

O despachante de comandos pré-lê **sempre um operando**:

```
loc_07E9:
        sub     $0C / sla a / ld e,a
        ld      a,(bc) / and $70 / rrca / add a,e
        ld      hl,seq_cmd_jumps / add hl,de
        ld      e,(hl) / inc hl / ld d,(hl)
        ld      hl,loc_0805 / push hl                 ; retorno
        inc     bc / ld a,(bc)                        ; <-- primeiro operando ja' em A
        ex      de,hl / jp (hl)
```

O índice da entrada é `((b & $70) >> 4)·4 + ((b & $0F) − $0C)`; o cálculo acima já o produz em
bytes. A tabela é `seq_cmd_jumps`, 32 entradas em `$081D`–`$085C`.

Um handler que não queira operandos começa por `dec bc`, desfazendo a pré-leitura.

### 7.2 Notas

Quando o nibble baixo é `< $0C`, o atributo **é** a nota e não tem operandos:

- nibble baixo = semitom (0–11), índice em `fm_fnum_table` (`$085D`);
- bits 6–4 = bloco (oitava); `and $70 / rrca` converte `bloco<<4` em `bloco<<3`, que é a
  posição do campo no registo `$A4`.

O bit 3 de `ctx+$00` marca "este evento já tem nota". Se já estiver posto, o handler põe o bit
5 e **adia**: no tick seguinte, `sub_06F6` vê esse bit, faz `dec bc` para reprocessar o mesmo
ponto do fluxo e usa `ctx+$14` (o comando `$CE`) como duração. É o mecanismo para escrever
duas notas seguidas dentro do mesmo bloco de atributos.

**Só que o comando `$CE` nunca aparece nos dados.** Com `ctx+$14 = 0` (o valor de
`sub_0657`), `sub_06F6` faz `and a / jr nz` sobre a duração zero e cai em `sub_0690`, isto é,
o adiamento terminaria a faixa. Descodificando os 133 fluxos, **nenhum produz um evento
adiado** — o mecanismo está implementado e os dados nunca o exercitam.

O bit 2 de `ctx+$00` (posto pelo comando `$CC` com operando `$A0`, limpo com `$A1`) faz a nota
disparar também um key-on (`set 4` + `set 7`).

### 7.3 Os 32 comandos e o comprimento dos operandos

A coluna "op." conta os bytes de operando **incluindo** o que o despachante pré-lê.

| Byte | Idx | Rotina | Op. | Efeito |
|---|---|---|---|---|
| `$8C` | 0 | `$0875` | 1–2 | F-number do *slot* 1 do canal 3 → `ctx+$19`…`$1D` |
| `$8D` | 1 | `$088D` | 1–2 | *slot* 2 → `ctx+$26`…`$2A` |
| `$8E` | 2 | `$08A5` | 1–2 | *slot* 3 → `ctx+$33`…`$37` |
| `$8F` | 3 | `$08BD` | 0–2 | nota principal → `ctx+$40`…`$44` |
| `$9C` | 4 | `$092A` | 1 | DT/MUL do operador 1 → `ctx+$20` (reg `$30`) |
| `$9D` | 5 | `$0933` | 1 | operador 2 → `ctx+$2D` |
| `$9E` | 6 | `$093C` | 1 | operador 3 → `ctx+$3A` |
| `$9F` | 7 | `$0945` | 1 | operador 4 → `ctx+$47` |
| `$AC` | 8 | `$094E` | 1 | TL do operador 1 → `ctx+$1E`/`$1F` |
| `$AD` | 9 | `$095A` | 1 | operador 2 → `ctx+$2B`/`$2C` |
| `$AE` | 10 | `$0966` | 1 | operador 3 → `ctx+$38`/`$39` |
| `$AF` | 11 | `$0972` | 1 | operador 4 → `ctx+$45`/`$46` |
| `$BC` | 12 | `$097E` | 5 | envelope do operador 1 → `ctx+$21`…`$25` |
| `$BD` | 13 | `$0994` | 5 | operador 2 → `ctx+$2E`…`$32` |
| `$BE` | 14 | `$09AA` | 5 | operador 3 → `ctx+$3B`…`$3F` |
| `$BF` | 15 | `$09C0` | 5 | operador 4 → `ctx+$48`…`$4C` |
| `$CC` | 16 | `$09EB` | 1 | multiplexado — ver abaixo |
| `$CD` | 17 | `$0A48` | 4 | TL dos quatro operadores de uma vez |
| `$CE` | 18 | `$0A72` | 1 | `ctx+$14` = duração do evento adiado |
| `$CF` | 19 | `$0A78` | 1 | carrega o instrumento nº *op* |
| `$DC` | 20 | `$0B32` | 3 | LFO de altura → `ctx+$51`…`$58` |
| `$DD` | 21 | `$0B57` | 1 + *popcount*(op) | valores por máscara a partir de `ctx+$59` |
| `$DE` | 22 | `$0B87` | 2 | envelope por software → `ctx+$63`…`$6D` |
| `$DF` | 23 | `$0C04` | 1 + *popcount*(op & `$8F`) (+ *popcount*(op & `$70`) só no canal 3) | ranhuras a partir de `ctx+$72` |
| `$EC` | 24 | `$0C60` | 1 | `ctx+$70`/`$71` |
| `$ED` | 25 | `$0C6C` | 1 | razão de *gate* → `ctx+$16` |
| `$EE` | 26 | `$0CC3` | **0** | pausa: marca o evento como preenchido, sem nota; key off |
| `$EF` | 27 | `$0CDB` | **0** | re-arme de tecla (bits 3, 4 e 7 de `ctx+$00`) |
| `$FC`–`$FF` | 28–31 | `$0CF6` | 1 | consomem um operando e não fazem nada |

Nos comandos 0–3, o segundo operando só é consumido se o primeiro tiver o **bit 7 posto** e o
nibble baixo `< $C` (`seq_fnum_lookup`, `$08F7`): é o *detune* fino, somado ao F-number com o
sinal dado pelo bit 7 do segundo byte. O `$8F` consome **zero** operandos quando o bit 3 de
`ctx+$00` já está posto (adia, §7.2).

**O comando `$CC`** é uma multiplexagem pelo operando:

| Operando | Efeito |
|---|---|
| bit 7 = 0 | `ctx+$18` = ((op & `$70`) `rrca`) \| (op & `$07`) → FB/ALG (reg `$B0`) |
| `$80`–`$9F` | `ctx+$17` = (op & `$1F`) rodado 4 à direita → máscara de *slots* do key-on e modo do canal 3 |
| `$A0` | põe o bit 2 de `ctx+$00` (nota dispara key-on) |
| `$A1` | limpa esse bit |
| bit 6 = 1 | `ctx+$4D + ((op & $30) >> 4)` = nibble baixo do operando → SSG-EG do operador |

**Verificação do formato.** Escrevi um descodificador estático com esta tabela de operandos e
apliquei-o aos 133 fluxos FM alcançáveis pelas duas tabelas de comandos. Resultado: os 133
descodificam sem erro até um byte de duração `$00`, num total de 1924 eventos e 1109 notas; e
119 dos 133 acabam exactamente onde o fluxo seguinte começa. Os 14 casos restantes deixam para
trás 1, 2, 5, 13 ou 20 bytes — restos de versões anteriores (por exemplo, `$3A69` acaba em
`$3A7A` e deixa `EE 00` até `$3A7D`; `$4206` acaba em `$422D` e deixa 20 bytes que formam um
fluxo completo mas inalcançável). A contiguidade quase perfeita é a evidência de que os
comprimentos de operando acima estão certos: um único erro desalinharia todos os fluxos a
jusante.

### 7.4 A tabela de F-numbers

`fm_fnum_table`, `$085D`–`$0874`, 12 words little-endian:

| Índice | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| F-number | 617 | 654 | 692 | 734 | 777 | 823 | 872 | 924 | 979 | 1038 | 1099 | 1165 |

Os quocientes entre entradas consecutivas vão de 1,05810 a 1,06069, contra `2^(1/12)` =
1,05946; o quociente entre a última e a primeira é 1,88817, contra `2^(11/12)` = 1,88775. É
uma escala cromática temperada arredondada a inteiros — isto verifica-se sem assumir nada
sobre relógios.

Assumindo o prescaler ÷6 e usando `f = fnum · 2^(bloco−1) · (4 MHz / 6) / 2^20`, o bloco 2 dá,
por índice: 784,6 / 831,6 / 879,9 / 933,3 / 988,0 / 1046,5 / 1108,8 / 1174,9 / 1244,9 /
1319,9 / 1397,5 / 1481,4 Hz — todas a menos de 2,1 *cents* de uma nota temperada com A = 440
Hz, e o índice 5 exactamente em Dó6 (1046,50 Hz). A tabela está portanto ancorada com o
**índice 0 = Sol** e o **índice 2 = Lá**. Este teste confirma a afinação, **não** o prescaler:
÷3 daria a mesma escala uma oitava acima, e ÷2 cairia a uns 3 *cents* de outra nota
temperada.

### 7.5 Instrumentos

`fm_patch_table` (`$1B00`–`$1B85`): 67 ponteiros de 16 bits, espaçados exactamente de `$21`,
para registos de **33 bytes** em `$1C00`–`$24A2`. `seqcmd_load_patch` (`$0A78`) copia-os para
o contexto:

| Bytes do patch | Transformação | Destino |
|---|---|---|
| `+0` | `& $1F`, rodado 4 à direita | `ctx+$17` (máscara de *slots*, modo do canal 3) |
| `+1` | ((`&$70`) `rrca`) \| (`&$07`) | `ctx+$18` (FB/ALG) |
| `+2` … `+8` | operador **1** | `ctx+$1E`/`$1F` (TL) e `ctx+$20`…`$25` |
| `+9` … `+$0F` | operador **3** | `ctx+$38`/`$39` e `ctx+$3A`…`$3F` |
| `+$10` … `+$16` | operador **2** | `ctx+$2B`/`$2C` e `ctx+$2D`…`$32` |
| `+$17` … `+$1D` | operador **4** | `ctx+$45`/`$46` e `ctx+$47`…`$4C` |
| — | quatro zeros | `ctx+$4D`…`$50` (SSG-EG) |
| `+$1E`, `+$1F`, `+$20` | reencaminhados para `seqcmd_pitch_lfo`, `seqcmd_bitmask_block`, `seqcmd_soft_envelope`, `seqcmd_slot_table` e `ctx+$70`/`$71` | LFO / envelope por software |

**Os operadores estão guardados por ordem de *slot* do hardware, não por número de
operador**: 1, 3, 2, 4. Sai da aritmética de `$0AA2` (`+$06`), `$0AB6` (`+$12`), `$0ACA`
(`−$15`) e `$0ADE` (`+$12`) sobre os ponteiros de contexto, e é coerente com a ordem de
emissão de `fm_emit_channel` (§6.3).

O bloco de 7 bytes de cada operador é `TL, DT/MUL, (0), KS/AR, D1R, D2R, SL/RR`. A cauda
(`+$1E`…`+$20`) é variável em geral — `seqcmd_pitch_lfo` consome mais dois bytes se `+$1E` for
diferente de zero, e por aí adiante — mas **nos 67 instrumentos a cauda é `00 00 00`**, o que
fixa o registo em 33 bytes.

Exemplo, o instrumento 0 (`$1C00`):

```
0F 60 | 23 70 00 9C 03 08 FF | 23 61 00 DC 03 08 FF | 12 41 00 5F 0A 08 FF | 12 71 80 5F 0C 08 FF | 00 00 00
|  |    operador 1             operador 3             operador 2             operador 4             cauda
|  +--- $60 -> ctx+$18 = $30 -> FB = 6, ALG = 0
+------ $0F -> ctx+$17 = $F0 (os quatro operadores recebem key-on)
```

**Atenção à assimetria do TL.** O carregador guarda `cpl(byte) & $7F` no contexto e `sub_0EE6`
volta a complementar na emissão, portanto **o byte do patch é o valor directo do registo
`$40`**. Já os comandos `$AC`–`$AF` e `$CD` guardam o operando **sem** complementar, portanto
nas sequências o TL está invertido: `$00` sai como `$7F` (atenuação máxima, silêncio) e `$7F`
sai como `$00` (máximo volume). É isso que permite ao fluxo de silêncio usar `CD 00 00 00 00`.

O bloco de 13 bytes por operador dentro do contexto (base `ctx+$19 + 13k`, para onde aponta
`iy`):

| Offset | Conteúdo |
|---|---|
| `+0` | F-number baixo (preparado) |
| `+1` | F-number baixo (activo) → reg `$A9`/`$AA`/`$A8`, ou `$A0`+c no operador 4 |
| `+2` | F-number alto (preparado) |
| `+3` | bloco `<< 3` |
| `+4` | bloco \| F-number alto (activo) → reg `$AD`/`$AE`/`$AC`, ou `$A4`+c |
| `+5` | TL alvo |
| `+6` | TL actual → reg `$40`+n |
| `+7` | DT/MULTI → reg `$30`+n |
| `+8` | sempre 0 (o primeiro operando de `$BC`–`$BF` é mascarado com `$00` em `$09D6`) |
| `+9` | KS/AR → reg `$50`+n |
| `+$A` | D1R → reg `$60`+n |
| `+$B` | D2R → reg `$70`+n |
| `+$C` | SL/RR → reg `$80`+n |

### 7.6 Dois fluxos desmontados

`$3716`, a primeira faixa do bloco `$2B50` (efeito `$F4`):

```
01              duracao 1
CC 88           ctx+$17 = $80 (so' o operador 1 recebe key-on)
CC 10           ctx+$18 = $08 (FB = 1, ALG = 0)
AC 00           TL op1 = 0   (emitido como $7F)
9C 01           DT/MUL op1 = 1
BC 00 00 00 00 00   envelope op1 todo a zero
AD 00 / 9D 01 / BD 00 00 00 00 00      idem operador 2
AE 00 / 9E 01 / BE 00 00 00 00 00      idem operador 3
AF 7F / 9F 01 / BF 00 1F 00 00 00      operador 4: TL $7F (maximo), D1R $1F
C9              NOTA: semitom 9, bloco 4
00              duracao 0 -> fim da faixa
```

Um evento único que programa o canal inteiro e toca uma nota. A duração `$00` manda
`sub_0690` avançar para a faixa 1 do bloco (`10 45 37` → fluxo `$3745`, repetição infinita),
que é simplesmente `7F 00`: um evento de 127 ticks sem atributos, em ciclo — o sustentar.

O fluxo de silêncio, `$3792`, usado por todos os comandos de paragem:

```
01              duracao 1
EE              pausa (0 operandos): marca key off
CD 00 00 00 00  TL dos quatro operadores = 0 -> emitido como $7F = atenuacao maxima
00              duracao 0 -> fim
```

E o início de `$37A7` (comando `$05`, canal FM 1), para se ver música a sério:

```
07  A7 CF 00 AF 6E DC 0B B8 01 DD 80 32   dur 7: nota sol2, instrumento 0, TL op4 = $6E,
                                          LFO de altura, bloco por mascara
07  A4        dur 7: nota mi2
07  A9        dur 7: nota la2
07  A4  07 AB  07 A9  07 A4  07 A7  07 A4  07 A9  07 A4  07 AB ...
```

— um arpejo em semicolcheias de 7 ticks (≈115 ms cada).

### 7.7 O que os dados usam de facto

Contagem sobre os 133 fluxos FM:

| Comando | Ocorrências | | Comando | Ocorrências |
|---|---|---|---|---|
| nota (`$8x`–`$Fx` com nibble `<$C`) | 1109 | | `$CD` TL×4 | 63 |
| `$AF` TL op4 | 271 | | `$DE` envelope sw | 47 |
| `$8F` fnum principal | 164 | | `$DF` ranhuras | 47 |
| `$CF` instrumento | 140 | | `$CC` modo/FB-ALG | 27 |
| `$EE` pausa | 130 | | `$8D` fnum *slot* 2 | 25 |
| `$DD` bloco por máscara | 77 | | `$AD` TL op2 | 22 |
| `$DC` LFO de altura | 67 | | `$BF` env op4 | 14 |
| `$BC`/`$BD`/`$BE` | 5/5/3 | | `$9C`–`$9F`, `$AC`, `$AE` | 2 cada |

**Nunca usados nos dados:** `$8C`, `$8E`, `$CE`, `$EC`, `$ED`, `$EF`, `$FC`, `$FD`, `$FE`,
`$FF`. As oitavas usadas vão de 0 a 7, com concentração em 2 (319 notas) e 4 (297). Dos 67
instrumentos, 64 são referenciados; os índices 5, 7 e 50 não são usados por fluxo nenhum.

---

## 8. O motor e o formato SSG

### 8.1 Contextos e registos-sombra

O SSG tem contextos próprios (`$8000` e `$80A0`) e um tick próprio, `sub_13F4` (`$13F4`),
chamado logo a seguir ao motor FM na mesma IRQ. Não passa por `sub_04A7` nem por `sub_05CE`,
e o arranque de bloco é `ssg_seq_start` (`$14F6`), um duplicado de `sub_0615`.

Os registos do YM2203 estão espelhados dentro do contexto:

| Offset | Registo do chip |
|---|---|
| `ctx+$14`, `+$15` | `$00`, `$01` — período do canal A (fino, grosso) |
| `ctx+$16`, `+$17` | `$02`, `$03` — canal B |
| `ctx+$18`, `+$19` | `$04`, `$05` — canal C |
| `ctx+$1A` | `$06` — período do ruído |
| `ctx+$1B` | `$07` — misturador |
| `ctx+$1C`, `+$1D`, `+$1E` | `$08`, `$09`, `$0A` — volumes A, B, C |
| `ctx+$1F`, `+$20` | `$0B`, `$0C` — período do envelope |
| `ctx+$21` | `$0D` — forma do envelope |
| `ctx+$22` | a porta `$9800` |

`ctx+$11` é a máscara de sujidade dos registos `$00`–`$0A` (bit 0 = par `$00`/`$01`, bit 1 =
`$02`/`$03`, bit 2 = `$04`/`$05`, bits 3–7 = `$06`…`$0A`), lida por `ssg_emit_regs_00_0A`
(`$1473`); `ctx+$12` é a dos restantes (bit 0 = `$0B`/`$0C`, bit 1 = `$0D`, bit 2 = a porta
`$9800`), lida por `ssg_emit_regs_0B_0D` (`$14A2`).

O arranque põe `ctx+$1B = $3F` nos dois contextos (`$01B2`, `$01B5`) — tudo cortado — e o
comando de misturador mascara sempre com `$3F` (`$1742`), pelo que **os bits 6 e 7 do registo
`$07` ficam permanentemente a zero**: as duas portas de I/O do YM2203 são sempre entradas. É o
que garante que a leitura dos DIP switches (§2.6) funciona a qualquer momento.

O mascaramento entre camadas é mais simples do que no FM: se o contexto `$8000` estiver a
tocar, o `$80A0` nem chega a emitir (`$1407`–`$1412`); quando o `$8000` pára, `$879D` força
`$80B1 = $FF` e `$80B2 = $03` (as duas máscaras do `$80A0` cheias), o que reescreve tudo.

### 8.2 O formato

```
[$F0 opcional] [duracao] [comando] [operandos] ... [byte < $40] [duracao] ...
```

`seq_ssg_read_event` (`$15C9`) trata um `$F0` inicial como prefixo a saltar antes da duração;
uma duração `$00` termina a faixa. O despachante `seq_cmd2_dispatch` (`$15EA`) termina no primeiro byte
com `b & $C0 == 0`, isto é, no primeiro byte `< $40`:

```
seq_cmd2_dispatch:
        inc     bc / ld a,(bc)
        and     $C0 / ret z                     ; fim da lista
        ld      a,(bc) / and $F0 / sub $40
        rrca / rrca / rrca                      ; indice em BYTES (entradas de 2)
        ld      hl,seq_cmd2_jumps / add hl,de
        ...
        ld      a,(bc) / and $0F / jp (hl)      ; nibble baixo em A
```

Como qualquer byte `< $40` termina a lista, uma duração `>= $40` teria de ser precedida do
prefixo `$F0`. É exactamente para isso que serve o comando `$F0` (`ssgext_end_event`,
`$16CE`): faz `dec bc`, o que deixa o ponteiro **sobre o próprio `$F0`**, e a sua entrada na
tabela tem o parâmetro `$8000`, cujo bit 7 em `d` faz `ssgcmd_extended` sair por `bit 7,d /
ret nz` (`$168E`) em vez de continuar a lista. No tick seguinte, `seq_ssg_read_event` vê o
`$F0`, salta-o e lê a duração. O mesmo byte fecha um evento e abre o outro.

Doze comandos, escolhidos pelo nibble **alto**; o nibble baixo é o primeiro dado:

| Byte | Rotina | Op. | Efeito |
|---|---|---|---|
| `$4x` | `$1606` | 1 | `ctx+$15` = x (reg `$01`), operando → `ctx+$14` (reg `$00`) |
| `$5x` | `$1614` | 1 | canal B (regs `$03`/`$02`) |
| `$6x` | `$1621` | 1 | canal C (regs `$05`/`$04`) |
| `$7x` | `$162E` | 1 | `ctx+$1F` = x`<<4` (reg `$0B`), operando → `ctx+$20` (reg `$0C`) |
| `$8x` | `$163F` | 0 | volume A = x (reg `$08`) |
| `$9x` | `$164F` | 0 | volume B (reg `$09`) |
| `$Ax` | `$165F` | 0 | volume C (reg `$0A`) |
| `$Bx` | `$166F` | 0 | `ctx+$22` = x → porta `$9800` |
| `$Cx` `$Dx` `$Ex` | `$1677`/`$167C`/`$1681` | 0 | sem efeito |
| `$Fx` | `$1686` | var. | comando estendido, `x` indexa `seq_ext_jumps` |

Os estendidos vivem em `seq_ext_jumps` (`$176D`), 16 entradas de 4 bytes: ponteiro mais uma
word que serve de máscara de sujidade **ou** de deslocamento no contexto. `sub_16BA` (`$16BA`)
pré-lê um operando para todos eles.

| Byte | Rotina | Parâmetro | Op. | Efeito |
|---|---|---|---|---|
| `$F0` | `$16CE` | `$8000` | 0 | `dec bc` — fim do evento (ver acima) |
| `$F1` | `$16D0` | `$0008` | 1 | `ctx+$1A` = op `& $1F` → reg `$06` (período do ruído) |
| `$F2` | `$16D6` | `$0044` | 2 | aplica um registo da tabela `$2700` em `ctx+$44` |
| `$F3` | `$16E4` | `$0200` | 1 | forma do envelope (`ctx+$21` = op`&7`\|`$08`) e re-arme dos três canais |
| `$F4` `$F5` `$F6` | `$1738` | `$0023` `$002E` `$0039` | 2 | tabela `$2800` em `ctx+$23`/`$2E`/`$39` |
| `$F7` | `$1742` | `$0010` | 1 | `ctx+$1B` = op `& $3F` → reg `$07` (misturador) |
| `$F8` `$F9` `$FA` | `$1748` | `$004F` `$005A` `$0065` | 2 | tabela `$2700` em `ctx+$4F`/`$5A`/`$65` |
| `$FB`–`$FE` | `$176C` | `$0000` | 1 | consomem um byte, sem efeito |
| `$FF` | `$1752` | `$0000` | 1 | zera o campo indicado por `dat_17AD[op & $0F]` |

Os que passam por `sub_17BD` (`$F2`, `$F4`–`$F6`, `$F8`–`$FA`) lêem um segundo operando
(`$17D4`) e depois copiam um registo de **5 bytes** da tabela (`$2700` ou `$2800`, passo 5,
índice = primeiro operando `& $7F`) para `iy+$03`…`$08`. É o mesmo desenho de
`seq_env_load_record` (`$0BA8`) do lado FM, sobre a tabela `$2600`.

`dat_17AD` (`$17AD`) é `00 00 44 00 23 2E 39 00 4F 5A 65 00 00 00 00 00` — exactamente os
deslocamentos de `$F2`, `$F4`–`$F6` e `$F8`–`$FA`, o que confirma que `$FF` é o "desligar"
correspondente a cada um.

### 8.3 Os três fluxos, desmontados

Há exactamente três fluxos SSG em toda a ROM, e estão todos aqui.

**`$379A`** — silêncio, usado pelos comandos `$00`, `$03` e `$04`:

```
01              duracao 1
F7 FF           $F7: misturador = $FF & $3F = $3F (tom e ruido cortados nos 3 canais)
40 00           periodo A = $000
50 00           periodo B = $000
60 00           periodo C = $000
80 90 A0        volumes A, B, C = 0
00              byte < $40 -> fim da lista; e' tambem a proxima duracao = 0 -> fim da faixa
```

**`$3700`** — alcançado só pelo efeito `$F2` (que nenhuma rotina do jogo envia), com repetição
infinita:

```
F0 F0           prefixo + duracao $F0 (240 ticks, ~3,9 s)
   F7 FE        misturador = $3E: so' o TOM do canal A passa
   40 D5        periodo A = $0D5
   50 00        periodo B = 0
   60 00        periodo C = 0
   90 A0        volumes B e C = 0
   8F           volume A = 15
   F0           fim do evento
F0 F0           prefixo + duracao $F0
   8D           volume A = 13
   F0           fim do evento
F0 78           prefixo + duracao $78
   F7 FF        misturador = $3F (tudo cortado)
   80           volume A = 0
00              duracao 0 -> fim da faixa
```

Um tom contínuo no canal A, dois patamares de volume e silêncio. É um sinal de teste, não
música.

**`$4E99`** — o único fluxo SSG com conteúdo disparado pelo jogo (comando `$2E`), e o último
bloco útil da ROM (`$4E99`–`$4EDD`):

```
3F              duracao $3F
  F7 00         misturador = $00: tom E ruido activos nos tres canais
  48 79         periodo A = $879
  57 56         periodo B = $756
  67 88         periodo C = $788
  8D 9D AD      volumes A, B, C = 13
  B4            porta $9800 = 4
  F1 1F         periodo do ruido = $1F
3F 3F 3F 3F 3F  mais cinco eventos de $3F ticks sem comandos (sustenta)
0A 8B 9B AB     -10 ticks-  volumes = 11
0A 8A 9A AA                 10
0A 89 99 A9                  9
0A 88 98 A8                  8
0A 87 97 A7                  7
05 86 96 A6     - 5 ticks-   6
05 85 95 A5                  5
05 84 94 A4                  4
05 83 93 A3                  3
05 82 92 A2                  2
05 81 91 A1                  1
01 80 90 A0                  0
00              fim
```

Um acorde de três tons com ruído sobreposto, 378 ticks (≈6,2 s a 60,9 Hz) a sustentar e um
desvanecimento linear de 12 degraus em 81 ticks (≈1,3 s). É a única vez que o gerador de ruído
do YM2203 é usado no jogo, e o `B4` em `$4EA5` é a **única** escrita em `$9800` comandada por
dados em toda a ROM.

---

## 9. O mapa da ROM de som

Segmentação de `build/z80_map.json`, convertida para hexadecimal e confirmada contra a imagem.
Conteúdo real: `$0000`–`$4EDD` (20 190 bytes); de `$4EDE` a `$7FFF` são 12 578 bytes de `$FF`.

| Faixa | Tipo | O que é |
|---|---|---|
| `$0000`–`$000D` | código | reset (transborda para `RST $08`) |
| `$000E`–`$000F` | — | dois bytes `00` |
| `$0010`–`$003A` | código | `RST $10`…`$30` (só `nop`) e `jp $0255` do vector de IRQ |
| `$003B`–`$0065` | vazio | até ao vector de NMI |
| `$0066`–`$0384` | código | NMI, filas, inicialização, laço principal, IRQ, despacho |
| `$0385`–`$0398` | dados | `dat_0385`, 10 words de contexto |
| `$0399`–`$0447` | código | `$EE`/`$EF`, `sub_03C6`, `$F0`–`$FE` |
| `$0448` | — | um `$C9` órfão |
| `$0449`–`$0466` | tabela | 15 saltos de `$F0`–`$FE` |
| `$0467`–`$081C` | código | fim de bloco, tick FM, faixas, leitor de eventos |
| `$081D`–`$085C` | tabela | `seq_cmd_jumps`, 32 entradas |
| `$085D`–`$0874` | dados | `fm_fnum_table` |
| `$0875`–`$0CBE` | código | os 32 handlers de comando FM |
| `$0CBF`–`$0CC2` | — | `2E 00 63 C9`, fragmento morto |
| `$0CC3`–`$10FE` | código | pausa, re-arme, emissão, LFO, envelope por software |
| `$10FF`–`$110E` | tabela | 8 saltos de forma de LFO |
| `$110F`–`$16A1` | código | envelope, aplicação por ranhura, tick e leitor SSG |
| `$16A2`–`$16B9` | tabela | `seq_cmd2_jumps`, 12 entradas |
| `$16BA`–`$176C` | código | handlers SSG estendidos |
| `$176D`–`$17AC` | tabela | `seq_ext_jumps`, 16 entradas de 4 bytes |
| `$17AD`–`$17BC` | dados | `dat_17AD` |
| `$17BD`–`$1A87` | código | aplicação de envelopes |
| `$1A88`–`$1AFF` | vazio | |
| `$1B00`–`$1B85` | tabela | `fm_patch_table`, 67 ponteiros |
| `$1B86`–`$1BFF` | vazio | |
| `$1C00`–`$24A2` | dados | 67 instrumentos de 33 bytes |
| `$24A3`–`$24FF` | vazio | |
| `$2500`–`$2579` | tabela | 47 comandos + 14 efeitos |
| `$257A`–`$25FF` | vazio | |
| `$2600`–`$26BD` | dados | 20 registos de envelope + os passos que apontam (`$2680`–`$26BD`) |
| `$26BE`–`$26FF` | vazio | |
| `$2700`–`$2781` | dados | tabela SSG (só o registo 0 preenchido) |
| `$2782`–`$27FF` | vazio | |
| `$2800`–`$2885` | dados | tabela SSG (só o registo 0 preenchido) |
| `$2886`–`$2AFF` | vazio | |
| `$2B00`–`$36FF` | dados | 50 blocos de pedido + 140 blocos de canal |
| `$3700`–`$4EDD` | dados | 136 fluxos de sequência (6110 bytes de música) |
| `$4EDE`–`$7FFF` | `$FF` | EPROM apagada — 38,4 % da ROM |

---

## 10. Código morto e achados

**`sub_03C6` (`$03C6`–`$0412`, 77 bytes) é inalcançável.** É chamado de um único sítio:

```
sub_033C:
        ld      l,a
        ld      a,(ram_87A6) / and a / ret z
        cp      $F0 / jr c,loc_034A
        call    sub_03C6                  ; $0346
```

`$87A6` tem quatro referências em toda a ROM: três escritas (`$00` em `$01A5` e `$03AE`, `$01`
em `$03BF`) e a leitura acima. Como o valor é sempre `$00` ou `$01`, o `and a / ret z` trata o
zero e o `jr c` é sempre tomado. Os 77 bytes — que fariam o arranque directo de um contexto
SSG — nunca correm.

**A cópia de portamento dos *slots* do canal 3 nunca corre.** Em `sub_0F6F`:

```
        ld      a,(ix+$09)              ; $0F75  indice do canal: 0, 1 ou 2
        cp      $03                     ; $0F78
        jr      nz,loc_0FB4             ; $0F7A
```

`ctx+$09` só é escrito em `sub_05CE` (`$05CE` põe 0; `$0610` põe 1 e 2), pelo que **nunca vale
3**. As outras quatro comparações do mesmo campo na ROM são `cp $02` (`$0BF2`, `$0C33`,
`$1199`, `$1245`) — o valor certo para "canal 3". É, com toda a probabilidade, um erro de um
no código original; o efeito prático é nulo, porque o modo especial do canal 3 também nunca é
ligado (§6.5).

**O anel de 32 bytes em `$8742`** é escrito por `sub_015F` a cada comando aceite e nunca lido
(§3.2).

**`$84A0`–`$873F`** (672 bytes) e **`$8762`–`$877F`** (30 bytes) não são tocados por nada: o
anel de diagnóstico ocupa `$8742`–`$8761` (índice mascarado com `$1F`) e a FIFO ocupa
`$8782`–`$8791` (máscara `$0F`). São limpos no arranque e ficam por usar.

**As tabelas `$2700` e `$2800`** têm um único registo preenchido cada (`00 00 FF 80 27` e
`00 00 FF 80 28`, apontando para `$2780` = `80 30 00` e `$2880` = `80 76 80 79 80 00`); o
resto é zero. Os comandos que as indexariam (`$F2`, `$F4`–`$F6`, `$F8`–`$FA`) **não aparecem
em nenhum dos três fluxos SSG**. Parecem restos do título de origem do driver.

**Artefactos do desmontador.** Cinco `ld rr,nn` com constantes que calham em cima de endereços
com nome e são impressas como se fossem ponteiros. Nenhuma delas é um endereço:

| Endereço | Como aparece | O que é |
|---|---|---|
| `$08F3` | `ld de,ram_8001` | `ld de,$8001` — máscara `$80` para `ctx+$10` |
| `$0956` | `ld de,loc_0101` | `ld de,$0101` |
| `$09BC` | `ld de,loc_0403` | `ld de,$0403` |
| `$0CD7` | `ld de,ram_8003` | `ld de,$8003` |
| `$1820` | `ld de,loc_0114` | `ld de,$0114` |

(Os `ld bc,sub_0EDA`/`sub_0EE6`/`sub_0EF3` em `$0DD6`–`$0DF3` **são** ponteiros de código a
sério: `sub_0E17` guarda-os em `$8798` e chama-os por `push`/`ret`.)

**Nomes errados nos símbolos.** `seqcmd_op1_tl_target`…`seqcmd_op4_tl_target` (`$092A`,
`$0933`, `$093C`, `$0945`) escrevem `ctx+$20`/`$2D`/`$3A`/`$47`, que é `iy+$07` de cada
operador; `sub_0EDA` (`$0EDA`) emite esse byte para o registo `$30`+n, que é DT/MULTI. O "TL
alvo" é `ctx+$1E`/`$2B`/`$38`/`$45`, escrito pelos comandos `$AC`–`$AF`. Os nomes certos
seriam `seqcmd_opN_dtmul` — a correcção pertence a `symbols/fragments/z80/`.

---

## 11. O que não sabemos

**A porta `$9800`.** Duas escritas na ROM (`$01C2`, `$14C5`) e um comando de sequência
dedicado (`$Bx`). O MAME ignora-a (`nopw()`). Nos dados a porta recebe `$00` no arranque e
`$04` uma única vez, no fluxo `$4E99` (§8.3) — verificado por descodificação dos três fluxos
SSG. Dois valores em toda a vida da máquina não chegam para deduzir o que a porta controla.
Ver também [`docs/01-hardware.md` §7.4](01-hardware.md).

**O prescaler do YM2203.** `$2D` é escrito no porto de endereço sem dado, o que na folha de
dados é a selecção de prescaler; nenhuma fonte primária dentro deste repositório o confirma
(`reference/mame/` não inclui o modelo do YM2203). O cálculo do Timer A em §4 e a análise de
afinação em §7.4 assumem ÷6 e são mutuamente consistentes, mas ÷3 dá a mesma música uma oitava
acima e é igualmente consistente com os dados.

**A que sons correspondem os 47 comandos.** Sabemos que rotina do jogo envia cada código e que
fluxos cada um dispara. Não corri o driver, portanto não tenho nomes ("explosão", "captura",
"disparo") para nenhum. O contexto de chamada na tabela de §5.5 é factual; interpretá-lo como
nome de som é conjectura.

**Os campos de contexto acima de `ctx+$4D`.** `ctx+$51`–`$58` (LFO de altura), `ctx+$59`–`$62`
(valores por máscara do comando `$DD`), `ctx+$63`–`$6D` (envelope por software), `ctx+$6E`–`$71`
e as ranhuras a partir de `ctx+$72` são escritos pelos comandos e lidos por `sub_0FE5`
(`$0FE5`), `sub_1097` (`$1097`), `sub_10B3` (`$10B3`) e `sub_116B` (`$116B`), que não
desmontei em detalhe. O que está estabelecido: `sub_10B3` mantém um acumulador de 16 bits
(`ctx+$54`/`$55`) somado de um passo (`ctx+$56`/`$57`) e escolhe uma forma de onda por
`ctx+$58 & $07` numa tabela de 8 saltos em `$10FF` — é o vibrato; `sub_0FE5` percorre uma
lista de passos apontada por `ctx+$67`/`$68` com um índice em `ctx+$69` que incrementa de 1
por passo, e o resultado sai em `ctx+$6F`; `sub_116B` aplica esse resultado às ranhuras e
acende bits 4–7 de `ctx+$10`. A semântica campo a campo está por levantar.

**A tabela `$2600`.** 20 registos de 5 bytes, todos `00 00 FF <ponteiro>`, com ponteiros para
`$2680`–`$26BD`, onde estão os passos propriamente ditos, em pares de bytes de 3 em 3. Os
comandos `$DE` usam 17 dos 20 registos (índices 0–4, 6–15, 17, 18). A forma está clara; o que
cada byte significa musicalmente, não.

**O ramo de reinjecção dos blocos de pedido** (`$0313`–`$0329`) e **o ramo de resposta ao
68000** em `sub_0467` (`$0475`–`$0492`) estão compilados mas nenhum dado deste jogo os activa.
Provavelmente são código partilhado com outro título da mesma família de drivers — a mesma
explicação que serve para as tabelas `$2700`/`$2800` vazias e para os comandos `$CE`/`$ED`
implementados e nunca usados. **Isto é conjectura**: não há nada no binário que o prove.

**A prioridade `ctx+$05` versus `bloco+1`.** A comparação em `$0372`–`$0374` põe frente a
frente o nibble de prioridade do **registo de faixa em curso** e o do **cabeçalho do bloco
novo**. Em todos os blocos os dois nibbles coincidem, portanto a distinção nunca se manifesta.

**Os 14 casos de bytes sobrantes entre fluxos** (§7.3). Interpreto-os como restos de versões
anteriores dos dados porque descodificam como fragmentos de sequência bem formados e ninguém
lhes aponta. Não é uma prova.
