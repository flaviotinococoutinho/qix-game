# 07 — Texto e fonte

Volfied não tem camada de tiles de texto. Não tem camada de tiles nenhuma: o vídeo são dois
planos, a bitmap de `$400000` e os sprites do PC090OJ ([`docs/03-video.md`](03-video.md)).
Todo o texto que o jogador vê — HUD, mensagens, ranking, história, TEST MODE, staff roll —
é emitido **um sprite por carácter**.

Este documento cobre o subsistema de texto do 68000: a fonte, a tabela de 121 mensagens em
`$001B2E`, o renderizador de números em `$00196C`, o renderizador de strings em RAM em
`$0031A6`, e o que cada mensagem diz. O significado do que os números representam
(pontuação, percentagem, bónus) está em [`docs/06-gameplay.md`](06-gameplay.md); o formato do
slot de sprite e a orientação dos gráficos estão em [`docs/03-video.md`](03-video.md) §7.

Ficheiros: [`src/main68k/txt_message_renderer.asm`](../src/main68k/txt_message_renderer.asm),
[`src/main68k/txt_message_table_and_strings.asm`](../src/main68k/txt_message_table_and_strings.asm),
[`src/main68k/txt_number_renderer.asm`](../src/main68k/txt_number_renderer.asm),
[`src/main68k/txt_hud_init_and_defaults.asm`](../src/main68k/txt_hud_init_and_defaults.asm),
[`src/main68k/txt_lives_and_initials.asm`](../src/main68k/txt_lives_and_initials.asm).

---

## 1. O princípio: um posiciona, os outros repintam

Só uma rotina escreve as quatro words de um slot de sprite: `txt_draw_message`. Todas as
outras escrevem **a word do código do tile** (offset `+4`) — e, numa delas, também o
atributo — em slots que a mensagem já colocou. É por isso que as strings na ROM têm buracos de pontos:

```
"1ST ......0    ..  ..."
     ^^^^^^     ^^  ^^^
     pontuação  ronda  iniciais
```

Os pontos são placeholders reais — sprites com a cor, o Y e o X certos, e o tile `$0E` ('.').
Depois `txt_draw_number` troca o tile de cada um por um dígito, e `txt_draw_ram_string` troca
os três últimos pelas iniciais. Quem repinta não sabe nada de coordenadas.

| Rotina | Endereço | Escreve | Selecciona por |
|---|---|---|---|
| `txt_draw_message` | `$001A9C` | attr, Y, código, X | índice `d0` numa tabela de 121 |
| `txt_draw_number` | `$00196C` | só o código | índice `d0` numa tabela de 22 |
| `txt_draw_ram_string` | `$0031A6` | attr e código | índice `d0` numa tabela de 25 |
| `txt_draw_lives_icons` | `$003170` | só o código | — (5 slots fixos) |
| `txt_show_pct_symbol_maybe` | `$004F30` | só o código | — (1 slot fixo) |

Consequência prática para quem reimplementar: a ordem importa. Desenhar o número antes da
mensagem que o hospeda perde o número.

**A área de texto limpa-se em bloco.** `spr_clear_text_area` (`$000E9A`,
[`src/main68k/spr_pal_video_helpers.asm`](../src/main68k/spr_pal_video_helpers.asm)) enche
`$200000`–`$20064F` (`$194` longs) com o long `$00000100`, ou seja attr = 0, Y = 256,
código = 0, X = 256 — fora do ecrã. `spr_clear_text_area_short` (`$000EB0`) faz o mesmo só
para `$120` longs (`$200000`–`$20047F`). O HUD fixo vive a partir de `$200650` e sobrevive à
limpeza.

---

## 2. A fonte

### 2.1 A regra

```
$001AE2  move.b  (a0)+,d0            ; carácter ASCII
$001AE4  tst.b   d0
$001AE6  beq.b   loc_001B06          ; 0 termina
$001AE8  cmpi.b  #$20,d0
$001AEC  beq.b   loc_001B02          ; espaço: avança sem gastar slot
$001AEE  addi.w  #$FFE0,d0           ; tile = ASCII - $20
```

`addi.w #$FFE0` é `− $20`. **`tile = ASCII − $20`**, sem excepções, nas cinco rotinas de
texto do jogo. A fonte é a região `pc090oj` a partir do tile 0, tiles de 16×16×4.

O mesmo `− $20` aplica-se no modo de códigos de 16 bits (§3.3): o que está na ROM é sempre
"código do tile mais `$20`". Por isso um `dc.w $0020` no meio de um registo é um espaço, e
uma mensagem que use o tile `$13E` guarda `$015E`.

### 2.2 O inventário de glifos

`assets/font_map.json` mapeia carácter → tile → PNG; os 96 tiles estão em
`assets/font/oj16_sheet.png`. Medido no binário (`build/pc090oj.bin`, caixa envolvente dos
pixels com pen ≠ 0):

| Tiles | ASCII | Conteúdo | Caixa dentro do tile 16×16 |
|---|---|---|---|
| `$00`–`$3A` | `$20`–`$5A` | ` !"#$%&'()*+,-./0-9:;<=>?@A-Z` | linhas 0–7, colunas 0–7 |
| `$3B`–`$40` | `[`, `\`, `]`, `^`, `_`, `` ` `` | as seis peças do logótipo TAITO | praticamente o tile todo |
| `$41`–`$43` | `a`, `b`, `c` | `RO`, `UN`, `D` — rótulo "ROUND" | linhas 1–15, colunas 1–7 |
| `$44`–`$48` | `d`–`h` | `HI`, `GH`, `S`, `CO`, `RE` — "HIGH SCORE" | idem (`$47` é 16×16, ver §7) |
| `$49`–`$4B` | `i`, `j`, `k` | `UP`, `1`, `2` — rótulos "1UP"/"2UP" | idem |
| `$4C`–`$5F` | — | pares de pontos e manchas coloridas (não são texto) | — |

O alfabeto ocupa **8×8 no canto do tile de 16×16**: medi todos os tiles `$00`–`$3A` e nenhum
usa índice de linha ou coluna acima de 7. É por isso que o passo normal do texto é 8 e não
16. Os rótulos de HUD ocupam 16 no eixo das linhas — dois caracteres por tile — e por isso as
mensagens que os usam levam passo 16.

Curiosidade verificada byte a byte: o tile `$43` (o `D` de "ROUND") é **idêntico** ao tile
`$24` (a letra `D` do alfabeto). O jogo usa o `$24`: a mensagem 31 é `$61 $62 $44`, ou seja
`RO`, `UN` e a letra `D` normal. O `$43` ficou por usar.

Três glifos não são o que o ASCII diz — `*` é o sinal de multiplicar, `/` o de dividir e `@`
o símbolo de copyright (por isso as mensagens 1/3/4 lêem-se `"@ TAITO..."` mas mostram `©`).
Isto já está registado em [`docs/03-video.md`](03-video.md) §9.

### 2.3 A fonte grande de dígitos

Fora do bloco de 96 tiles há uma segunda fonte, só com dígitos, verificada descodificando
`build/pc090oj.bin` como 16×16×4 packed MSB:

| Tiles | Conteúdo |
|---|---|
| `$13E`–`$147` | dígitos 0–9 grandes (preenchem o tile todo, 14×16) |
| `$148` | `%` grande |
| `$149` | ícone de vida (usado por `txt_draw_lives_icons`) |
| `$1AF`–`$1BE` | dígitos 3, 2, 1, 0 gigantes, 2×2 tiles cada |
| `$1BF`–`$1F2` | painel 4×13 "WARNING! / SHIELD ENERGY 0" |
| `$208`–`$20B` | a palavra "SHIELD" em quatro tiles largos |
| `$1600`–`$160D` | logótipo TAITO grande, 2×7 tiles |

A fonte grande de `$13E` é a "fonte alternativa" do renderizador de números (§5.2).

### 2.4 O logótipo TAITO e a string ``[\]^_` ``

O registo 0 da tabela de mensagens está em `$001E3A` e os seus bytes são:

```
$001E3A  00 00        offset na RAM de sprites = $0000
$001E3C  80           attr: bit 7 -> passo 16
$001E3D  58           Y inicial = $58
$001E3E  00 38        X = $0038
$001E40  5B 5C 5D 5E 5F 60 00    "[\]^_`" e o terminador
```

Não é lixo nem uma string corrompida: `$5B`–`$60` são os tiles `$3B`–`$40`, as seis peças do
wordmark TAITO, desenhadas com passo 16 porque cada peça ocupa praticamente o tile todo. Qualquer
extractor de ASCII ingénuo encontra ali uma "string" ``[\]^_` ``; `assets/font_map.json` já
regista o caso (`fontes.oj16.logotipo_taito`).

Duas notas honestas sobre esta string:

1. O digest de strings deste projecto reporta-a como ``8[\]^_` `` a começar em `$001E3F`. O `8`
   é o byte baixo da coordenada X (`$0038`) — o heurístico de ASCII come o cabeçalho do
   registo. O mesmo artefacto explica os `p`, `x`, `` ` `` espúrios noutras strings do
   digest. O carácter real começa em `$001E40`.
2. **Nada no jogo chama a mensagem 0.** O logótipo TAITO que aparece no ecrã de título é
   outro: as mensagens 110 e 111 desenham 14 tiles de `$1600`–`$160D`, que descodificados dão
   um "TAITO" muito maior. As seis peças da fonte ficaram sem uso nesta ROM. Ver §9.

---

## 3. `txt_draw_message` (`$001A9C`)

### 3.1 O formato do registo

`txt_message_ptr_table` está em `$001B2E`: 121 × `dc.l` (`$1E4` bytes), a apontar para
registos espalhados por `$001D12`–`$002763`. O registo é:

| Offset | Tamanho | Campo |
|---|---|---|
| `+0` | word | offset na RAM de sprites (somado a `$200000`) |
| `+2` | byte | atributo; bit 7 = passo 16, bit 6 = códigos de 16 bits, bits 3–0 = cor |
| `+3` | byte | Y inicial (word `+2` do slot) |
| `+4` | word | X (word `+6` do slot), constante em toda a mensagem |
| `+6` | … | caracteres (bytes, ou words se o bit 6 estiver aceso), terminados em 0 |

O atributo escrito no slot é o byte com os bits 7 e 6 **já apagados** (`bclr`), estendido a
word — os bits de flip (15 e 14) ficam sempre a zero e sobra só o índice de cor. Valores
usados: `$00`, `$02`, `$05`, `$0B`, `$0E`, `$0F`. Com `sprite_ctrl = 0` isso dá as cores
`$100`–`$10F` (ver [`docs/03-video.md`](03-video.md) §7.5).

### 3.2 O laço de 8 bits

```
txt_draw_message:
        move.w  d0,d1                            ; $001A9C  guarda o índice
        lsl.w   #$2,d0
        lea.l   txt_message_ptr_table(pc),a0
        adda.w  d0,a0
        movea.l (a0),a0                          ; registo
        move.w  (a0)+,d2
        lea.l   PC090OJ_RAM,a1
        adda.w  d2,a1                            ; a1 = $200000 + offset
        clr.w   d3
        move.b  (a0)+,d3                         ; attr
        move.w  #$8,d6                           ; passo
        bclr.b  #$7,d3
        beq.b   loc_001AC4
        move.w  #$10,d6                          ; bit 7 -> passo 16
loc_001AC4:
        clr.w   d4
        move.b  (a0)+,d4                         ; Y
        move.w  (a0)+,d5                         ; X
        bclr.b  #$6,d3
        bne.b   loc_001B08                       ; bit 6 -> laço de 16 bits
        cmpi.b  #$35,d1
        bcs.b   loc_001AE0
        cmpi.b  #$3C,d1
        bcc.b   loc_001AE0
        addi.w  #$18,d5                          ; índices $35..$3B: X += $18
loc_001AE0:
        clr.w   d0
        move.b  (a0)+,d0
        tst.b   d0
        beq.b   loc_001B06                       ; 0 termina
        cmpi.b  #$20,d0
        beq.b   loc_001B02                       ; espaço: não gasta slot
        addi.w  #$FFE0,d0
        move.w  d0,$4(a1)                        ; código
        move.w  d3,(a1)                          ; attr
        move.w  d4,$2(a1)                        ; Y
        move.w  d5,$6(a1)                        ; X
        addq.w  #$8,a1
loc_001B02:
        add.w   d6,d4                            ; avança sempre, escreva ou não
        bra.b   loc_001AE0
```

Três regras que mudam o resultado e que é fácil implementar mal:

1. **O espaço avança a posição mas não consome slot.** Uma mensagem de 22 caracteres com 7
   espaços ocupa 15 slots. Todo o mapa de offsets do HUD depende disto.
2. **Os índices `$35`–`$3B` (53–59) levam `+$18` em X.** São exactamente os mesmos registos
   dos índices 41, 43–47 (os ponteiros repetem-se na tabela); a única diferença é a
   deslocação. O ecrã de entrada de iniciais e o ranking do atracto são o mesmo layout
   desenhado 24 pixels ao lado.
3. **O X é constante e o Y avança.** Não é engano: com `ROT270`, o eixo Y interno do
   PC090OJ é a horizontal do monitor. Ver §3.4.

### 3.3 O laço de 16 bits

Com o bit 6 do atributo, os caracteres são words e a comparação de espaço passa a
`cmpi.w #$20`. O resto é idêntico, incluindo o `− $20`:

```
loc_001B08:
        move.w  (a0)+,d0
        tst.w   d0
        beq.b   loc_001B2C
        cmpi.w  #$20,d0
        beq.b   loc_001B28
        addi.w  #$FFE0,d0
        move.w  d0,$4(a1)
        ...
```

É assim que uma "mensagem" desenha gráficos: o logótipo VOLFIED (mensagens 5–10, tiles
`$103`–`$135`), o painel de aviso do escudo (78–81), os dígitos gigantes (82–89) e o logótipo
TAITO grande (110–111). O ajuste de `+$18` **não** se aplica neste ramo — o teste do índice
está antes do desvio.

### 3.4 Os eixos, com `ROT270`

O slot do PC090OJ é `+0 attr | +2 Y | +4 código | +6 X`
([`docs/03-video.md`](03-video.md) §7.1). O texto avança em Y. No MAME
`ROT270 = SWAP_XY | FLIP_Y`, portanto `screen_x = Y` e `screen_y = altura − X`:

- o **Y** interno é a direcção de leitura (esquerda → direita no monitor);
- o **X** interno é a vertical, e **X maior = mais acima no ecrã**.

A segunda parte confirma-se sozinha nas mensagens 95–105 (o texto de história): as linhas
sucessivas do parágrafo usam X `$120`, `$110`, `$100`, `$0F0` — decrescente, ou seja a
descer. O passo entre linhas é `$10` = 16 pixels, o dobro da altura do glifo.

### 3.5 O truque do Y = `$FF`

As onze linhas de história (95–105) são desenhadas com Y inicial `$FF`, que está fora da
área visível (`8`–`247`). Quem as revela é `sub_0043C8`
([`src/main68k/player_entry_animation.asm`](../src/main68k/player_entry_animation.asm)):

```
sub_0043C8:
        lea.l   SPRITE_RAM+$2,a0        ; word de Y do slot 0
        move.w  $8F8(a5),d0
        adda.w  d0,a0                   ; cursor, avança 8 por chamada
        move.w  (a0),d0
        cmpi.w  #$100,d0
        beq.b   loc_0043E2              ; $100 = slot limpo, não mexe
        addi.w  #$121,d0
        move.w  d0,(a0)
loc_0043E2:
        addq.w  #$8,$8F8(a5)
        rts
```

`$FF + $121 = $220`, e o PC090OJ mascara Y com `$1FF` — dá `$20`. O carácter seguinte estava
em `$107` e vai para `$28`. Um slot por chamada: é uma máquina de escrever, e o mecanismo é
o corte a 9 bits do campo Y. `sub_0043E8` faz o mesmo estilo de retoque somando `$38` a 10
slots a partir de `$200232`.

---

## 4. As 121 mensagens

### 4.1 Quem desenha o quê

Levantado por varrimento das 106 chamadas a `txt_draw_message` na listagem, com o imediato
que carrega `d0` lido caso a caso (há laços e há ramos condicionais — ver §10 para a margem
de erro).

| Índices | Ecrã | Chamador |
|---|---|---|
| 0 | — | nenhum (§9) |
| 1–4 | copyright, por região | `sub_0009DA` `$0009EA`–`$000A0A` |
| 5–10 | logótipo VOLFIED | `attract_loop_script` `$000C2E`–`$000C4C` |
| 11 | `CREDIT 00` no HUD | `$001900`, `$000978`, `$003F90`, `$000C52` |
| 12 | `INSERT COIN(S)` | `attract_loop_script` `$000CA0` (região ≠ 2) |
| 13–15 | `PUSH` + botões | `game_coinwait_script` `$00098A`, `$00099A` |
| 16, 17 | `PLAYER 1` / `PLAYER 2` | `game_screen_sequence` `$0005FE`, `$0006BE` |
| 18–20 | `GAME OVER` | `game_over_and_player_switch` `$003EE6`, `$003E4E`, `$003E5C` |
| 21 | `TILT` | `inp_tilt_check` `$000E84` |
| 22–30 | aviso legal do Japão | `attract_loop_script` `$000DCC`–`$000DFC` |
| 31–39 | HUD do campo | `game_playfield_setup` `$00080E`/`$000814`/`$000820`, `txt_hud_init_and_defaults` `$0018B4`–`$0018F0`, `game_over_and_player_switch` `$003F3E`–`$003F7A` |
| 40 | `COIN ERROR` | `coin_credit` `$0069C2` |
| 41–52 | entrada de iniciais | `hiscore_entry`, laço `$004724`–`$004740` (d0 = `$29`…`$34`) |
| 48, 53–59 | ranking do atracto | `attract_loop_script` `$000CD0`–`$000CFA` |
| 60 | 5 pontos = ícones de vida | `game_playfield_setup` `$000804` |
| 61 | `ROUND ..` | `game_screen_sequence` `$000738`, `game_roundclear_script` `$003B9E` |
| 62 | — | nenhum (§9) |
| 63–75 | fim de ronda | `game_roundclear_script` `$0036F2`–`$0039E4` |
| 76, 77 | rótulo `SHIELD` + valor | `hud_draw_countdown_labels` `$007F54`, `$007F5A` |
| 78–81 | painel `WARNING! / SHIELD ENERGY 0` | `hud_draw_gameover_items` `$008102`–`$008120` |
| 82–89 | dígitos gigantes 3/2/1/0 | `$0081A0`/`$0081AC`, índice `$52 + 2·$86E(a5)` |
| 90–94 | bónus de fim de ronda | `game_roundclear_script` `$00378A`–`$0037AC` |
| 95–105 | texto de história | `player_entry_animation` `$00429E`–`$004394` |
| 106–109 | totais de fim de ronda | `$003A6A`, `$003AB4`, `$003AC0`, `$0037BA` |
| 110, 111 | logótipo TAITO grande | `sub_0009DA` `$0009DE`, `$0009E6` |
| 112–119 | pedido de moedas | `attract_loop_script` `$000CB6` (`$70 + d0`), `game_coinwait_script` `$0009D2` (`$74 + d0`), `spr_load_title_sprites` `$002982` (112) |
| 120 | `FANTASTIC ROUND CLEAR!` | `game_frame` `$004C12` |

Dois índices calculados que vale a pena ler por extenso:

```
$000CA6  move.w  $0(a5),d0          ; moedas por crédito
$000CAA  cmpi.w  #$5,d0
$000CAE  bcs.b   loc_000CB2
$000CB0  clr.w   d0                 ; 5 ou mais -> 0
$000CB2  addi.w  #$70,d0            ; 112 + d0
```

`d0 = 0` (free play) dá a mensagem 112, `TAITO ORIGINAL VIDEO GAME`; 1 a 4 dão
`INSERT n COIN(S) TO START` (113–116). O mesmo padrão em `$0009CE` com base `$74` escolhe
entre 116 e `ADD n COIN(S) TO START` (117–119) conforme as moedas que ainda faltam.

### 4.2 A lista

`attr` é o byte tal como está na ROM (bit 7 = passo, bit 6 = 16 bits, nibble baixo = cor).
`conteúdo` entre aspas é ASCII literal da ROM; sem aspas são códigos de tile já com o `− $20`
aplicado, onde `·n` são n espaços. Gerado a partir de `build/maincpu.bin`.

| # | registo | spr | attr | passo | Y | X | conteúdo |
|---|---|---|---|---|---|---|---|
| 0 | `$001E3A` | `$0000` | `$80` | 16 | `$58` | `$038` | $3B–$40 (logótipo TAITO) |
| 1 | `$001E48` | `$0040` | `$00` | 8 | `$20` | `$028` | `"@ TAITO CORPORATION 1989"` |
| 2 | `$001E68` | `$0138` | `$00` | 8 | `$30` | `$018` | `"ALL RIGHTS RESERVED"` |
| 3 | `$001E82` | `$0040` | `$00` | 8 | `$18` | `$028` | `"@ 1989 TAITO AMERICA CORP."` |
| 4 | `$001EA4` | `$0040` | `$00` | 8 | `$08` | `$028` | `"@ 1989 TAITO CORPORATION JAPAN"` |
| 5 | `$001ECA` | `$01C0` | `$CB` | 16 | `$18` | `$0E8` | $103 ·10 $104–$105 |
| 6 | `$001EEC` | `$01D8` | `$CB` | 16 | `$18` | `$0D8` | $106–$109 ·5 $10A–$10D |
| 7 | `$001F0E` | `$0218` | `$CB` | 16 | `$18` | `$0C8` | $10E–$11A |
| 8 | `$001F30` | `$0280` | `$CB` | 16 | `$18` | `$0B8` | $11B–$127 |
| 9 | `$001F52` | `$02E8` | `$CB` | 16 | `$18` | `$0A8` | · $128–$132 · |
| 10 | `$001F74` | `$0340` | `$CB` | 16 | `$18` | `$098` | · $133 ·8 $134–$135 · |
| 11 | `$001F96` | `$06A8` | `$00` | 8 | `$A8` | `$000` | `"CREDIT 00"` |
| 12 | `$001FA6` | `$0000` | `$00` | 8 | `$48` | `$0C8` | `"INSERT COIN(S)"` |
| 13 | `$001FBC` | `$0000` | `$00` | 8 | `$68` | `$0E0` | `"PUSH"` |
| 14 | `$001FC8` | `$0020` | `$00` | 8 | `$30` | `$0C8` | `"ONLY 1 PLAYER BUTTON"` |
| 15 | `$001FE4` | `$0020` | `$00` | 8 | `$30` | `$0C8` | `"1 OR 2 PLAYER BUTTON"` |
| 16 | `$002000` | `$0000` | `$00` | 8 | `$60` | `$0D0` | `"PLAYER 1"` |
| 17 | `$002010` | `$0000` | `$00` | 8 | `$60` | `$0D0` | `"PLAYER 2"` |
| 18 | `$002020` | `$0000` | `$00` | 8 | `$58` | `$0C8` | `"GAME OVER"` |
| 19 | `$002030` | `$0000` | `$00` | 8 | `$38` | `$0A8` | `"PLAYER 1 GAME OVER"` |
| 20 | `$00204A` | `$0000` | `$00` | 8 | `$38` | `$0A8` | `"PLAYER 2 GAME OVER"` |
| 21 | `$002064` | `$0000` | `$00` | 8 | `$70` | `$0D0` | `"TILT"` |
| 22 | `$002070` | `$0000` | `$00` | 8 | `$68` | `$0F8` | `"NOTICE"` |
| 23 | `$00207E` | `$0030` | `$00` | 8 | `$28` | `$0E0` | `"THIS GAME IS FOR USE IN"` |
| 24 | `$00209C` | `$00C0` | `$00` | 8 | `$18` | `$0D0` | `"JAPAN ONLY.SALES,EXPORT,OR"` |
| 25 | `$0020BE` | `$0188` | `$00` | 8 | `$28` | `$0C0` | `"OPERATION OUTSIDE THIS"` |
| 26 | `$0020DC` | `$0228` | `$00` | 8 | `$30` | `$0B0` | `"TERRITORY MAY VIOLATE"` |
| 27 | `$0020F8` | `$02C0` | `$00` | 8 | `$10` | `$0A0` | `"INTERNATIONAL COPYRIGHT AND"` |
| 28 | `$00211A` | `$0388` | `$00` | 8 | `$40` | `$090` | `"TRADEMARK LAWS AND"` |
| 29 | `$002134` | `$0408` | `$00` | 8 | `$28` | `$080` | `"THE VIOLATOR SUBJECT TO"` |
| 30 | `$002152` | `$04A8` | `$00` | 8 | `$40` | `$070` | `"SEVERE PENALTIES."` |
| 31 | `$00216A` | `$06C0` | `$80` | 16 | `$10` | `$000` | $41–$42 $24 → `ROUND` |
| 32 | `$002174` | `$0680` | `$80` | 16 | `$58` | `$138` | $44–$48 → `HIGH SCORE` |
| 33 | `$002180` | `$0718` | `$80` | 16 | `$18` | `$138` | $4A $49 $10 → `1UP` + `0` |
| 34 | `$00218A` | `$0760` | `$80` | 16 | `$C0` | `$138` | $4B $49 $10 → `2UP` + `0` |
| 35 | `$002194` | `$06A8` | `$C0` | 16 | `$64` | `$002` | $13E $13E $13E (percentagem) |
| 36 | `$0021A2` | `$06D8` | `$00` | 8 | `$40` | `$000` | `"00"` |
| 37 | `$0021AC` | `$0650` | `$00` | 8 | `$60` | `$130` | `"000000"` |
| 38 | `$0021BA` | `$06E8` | `$00` | 8 | `$08` | `$130` | `"000000"` |
| 39 | `$0021C8` | `$0730` | `$00` | 8 | `$B0` | `$130` | `"000000"` |
| 40 | `$0021D6` | `$0000` | `$00` | 8 | `$58` | `$0C8` | `"COIN ERROR"` |
| 41 | `$0021E8` | `$0000` | `$00` | 8 | `$58` | `$0B0` | `"SCORE       NAME"` |
| 42 | `$002200` | `$0048` | `$80` | 16 | `$88` | `$0B0` | $41–$42 $24 → `ROUND` |
| 43 | `$00220A` | `$0060` | `$00` | 8 | `$28` | `$0A0` | `"1ST ......0    ..  ..."` |
| 44 | `$002228` | `$00D8` | `$00` | 8 | `$28` | `$090` | `"2ND ......0    ..  ..."` |
| 45 | `$002246` | `$0150` | `$00` | 8 | `$28` | `$080` | `"3RD ......0    ..  ..."` |
| 46 | `$002264` | `$01C8` | `$00` | 8 | `$28` | `$070` | `"4TH ......0    ..  ..."` |
| 47 | `$002282` | `$0240` | `$00` | 8 | `$28` | `$060` | `"5TH ......0    ..  ..."` |
| 48 | `$0022A0` | `$02C0` | `$00` | 8 | `$30` | `$0F8` | `"GREAT FIVE WARRIORS!"` |
| 49 | `$0022BC` | `$02C0` | `$0F` | 8 | `$30` | `$0F8` | `"ENTER YOUR INITIALS !"` |
| 50 | `$0022D8` | `$0370` | `$0F` | 8 | `$38` | `$0E0` | `"SCORE         NAME"` |
| 51 | `$0022F2` | `$03B8` | `$8F` | 16 | `$70` | `$0E0` | $41–$42 $24 → `ROUND` |
| 52 | `$0022FC` | `$03D0` | `$00` | 8 | `$28` | `$0D0` | `"......0     ..   ..."` |
| 53 | `$0021E8` | `$0000` | `$00` | 8 | `$58` | `$0B0`+`$18` | `"SCORE       NAME"` |
| 54 | `$002200` | `$0048` | `$80` | 16 | `$88` | `$0B0`+`$18` | $41–$42 $24 |
| 55 | `$00220A` | `$0060` | `$00` | 8 | `$28` | `$0A0`+`$18` | `"1ST ......0    ..  ..."` |
| 56 | `$002228` | `$00D8` | `$00` | 8 | `$28` | `$090`+`$18` | `"2ND ......0    ..  ..."` |
| 57 | `$002246` | `$0150` | `$00` | 8 | `$28` | `$080`+`$18` | `"3RD ......0    ..  ..."` |
| 58 | `$002264` | `$01C8` | `$00` | 8 | `$28` | `$070`+`$18` | `"4TH ......0    ..  ..."` |
| 59 | `$002282` | `$0240` | `$00` | 8 | `$28` | `$060`+`$18` | `"5TH ......0    ..  ..."` |
| 60 | `$002318` | `$0628` | `$C2` | 16 | `$A8` | `$FFFE` | $E $E $E $E $E (ícones de vida) |
| 61 | `$00232A` | `$0000` | `$00` | 8 | `$60` | `$0E0` | `"ROUND .."` |
| 62 | `$00233A` | `$0000` | `$00` | 8 | `$68` | `$0E0` | `"READY!"` |
| 63 | `$002348` | `$0168` | `$0E` | 8 | `$B8` | `$0B8` | `"....%!!"` |
| 64 | `$002356` | `$0000` | `$0E` | 8 | `$40` | `$0F0` | `"CONGRATULATIONS!"` |
| 65 | `$00236E` | `$0080` | `$0F` | 8 | `$48` | `$0E0` | `"ROUND .. CLEAR"` |
| 66 | `$002384` | `$00E8` | `$00` | 8 | `$20` | `$0B8` | `"YOUR PERCENTAGE IS"` |
| 67 | `$00239E` | `$01A0` | `$00` | 8 | `$38` | `$0A0` | `"99.3% ... ...000PTS"` |
| 68 | `$0023B8` | `$0240` | `$00` | 8 | `$38` | `$098` | `"99.4% ... ...000PTS"` |
| 69 | `$0023D2` | `$02C8` | `$00` | 8 | `$38` | `$090` | `"99.5% ... ...000PTS"` |
| 70 | `$0023EC` | `$0350` | `$00` | 8 | `$38` | `$088` | `"99.6% ... ...000PTS"` |
| 71 | `$002406` | `$03D8` | `$00` | 8 | `$38` | `$080` | `"99.7% ... ...000PTS"` |
| 72 | `$002420` | `$0460` | `$00` | 8 | `$38` | `$078` | `"99.8% ... ...000PTS"` |
| 73 | `$00243A` | `$04E8` | `$00` | 8 | `$38` | `$070` | `"99.9% ... ...000PTS"` |
| 74 | `$002454` | `$0570` | `$0E` | 8 | `$40` | `$048` | `"BONUS ="` |
| 75 | `$002462` | `$05A0` | `$0E` | 8 | `$80` | `$048` | `"...000PTS"` |
| 76 | `$002472` | `$05E0` | `$C5` | 16 | `$08` | `$008` | $208–$20B → `SHIELD` |
| 77 | `$002482` | `$0600` | `$05` | 8 | `$48` | `$008` | `"..."` |
| 78 | `$00248C` | `$0180` | `$C0` | 16 | `$18` | `$0E8` | $1BF–$1CB |
| 79 | `$0024AE` | `$01E8` | `$C0` | 16 | `$18` | `$0D8` | $1CC–$1D8 |
| 80 | `$0024D0` | `$0250` | `$C0` | 16 | `$18` | `$0C8` | $1D9–$1E5 |
| 81 | `$0024F2` | `$02B8` | `$C0` | 16 | `$18` | `$0B8` | $1E6–$1F2 |
| 82 | `$002514` | `$05E0` | `$C0` | 16 | `$70` | `$0B8` | $1B5–$1B6 (`3`, metade de cima) |
| 83 | `$002520` | `$05F0` | `$C0` | 16 | `$70` | `$0A8` | $1BD–$1BE (`3`, metade de baixo) |
| 84 | `$00252C` | `$05E0` | `$C0` | 16 | `$70` | `$0B8` | $1B3–$1B4 (`2`) |
| 85 | `$002538` | `$05F0` | `$C0` | 16 | `$70` | `$0A8` | $1BB–$1BC (`2`) |
| 86 | `$002544` | `$05E0` | `$C0` | 16 | `$70` | `$0B8` | $1B1–$1B2 (`1`) |
| 87 | `$002550` | `$05F0` | `$C0` | 16 | `$70` | `$0A8` | $1B9–$1BA (`1`) |
| 88 | `$00255C` | `$05E0` | `$C0` | 16 | `$70` | `$0B8` | $1AF–$1B0 (`0`) |
| 89 | `$002568` | `$05F0` | `$C0` | 16 | `$70` | `$0A8` | $1B7–$1B8 (`0`) |
| 90 | `$002574` | `$00E0` | `$00` | 8 | `$68` | `$080` | `"BONUS"` |
| 91 | `$002580` | `$0110` | `$00` | 8 | `$30` | `$0A0` | `"SEPARATE ROUND CLEAR!"` |
| 92 | `$00259C` | `$01C0` | `$00` | 8 | `$50` | `$060` | `"10000 PTS!!"` |
| 93 | `$0025AE` | `$0110` | `$00` | 8 | `$30` | `$0A0` | `"SPECIAL ROUND CLEAR!"` |
| 94 | `$0025CA` | `$01C0` | `$00` | 8 | `$50` | `$060` | `"100000PTS!!"` |
| 95 | `$0025DC` | `$0050` | `$00` | 8 | `$FF` | `$120` | `"IT WAS A LONG TRIP...."` |
| 96 | `$0025FA` | `$00E0` | `$00` | 8 | `$FF` | `$110` | `"THE SPACESHIP "MONOTROS""` |
| 97 | `$00261A` | `$0190` | `$00` | 8 | `$FF` | `$100` | `"RETURNED TO HIS PLANET,"` |
| 98 | `$002638` | `$0230` | `$0E` | 8 | `$FF` | `$0F0` | `""VOLFIED"."` |
| 99 | `$00264A` | `$0080` | `$00` | 8 | `$FF` | `$120` | `"BUT, VOLFIED HAD ALREADY"` |
| 100 | `$00266A` | `$0140` | `$00` | 8 | `$FF` | `$110` | `"CHANGED INTO RUINS FROM"` |
| 101 | `$002688` | `$01F0` | `$00` | 8 | `$FF` | `$100` | `"INVASION OF ALIENS!"` |
| 102 | `$0026A2` | `$0080` | `$00` | 8 | `$FF` | `$120` | `"AT THE TIME, HE CAUGHT  "` |
| 103 | `$0026C2` | `$0138` | `$00` | 8 | `$FF` | `$110` | `""SOS" FROM UNDERGROUND."` |
| 104 | `$0026E0` | `$01E0` | `$00` | 8 | `$FF` | `$100` | `"HE DECIDED TO RESCUE THE"` |
| 105 | `$002700` | `$0280` | `$00` | 8 | `$FF` | `$0F0` | `"PEOPLE FROM THE ALIENS!"` |
| 106 | `$00271E` | `$05E8` | `$0F` | 8 | `$70` | `$038` | `"+1000000PTS"` |
| 107 | `$002730` | `$05E8` | `$0E` | 8 | `$40` | `$038` | `"TOTAL  ......."` |
| 108 | `$002746` | `$0228` | `$0E` | 8 | `$B0` | `$038` | `"PTS"` |
| 109 | `$002750` | `$01C0` | `$00` | 8 | `$50` | `$060` | `"1000000PTS!!"` |
| 110 | `$001D30` | `$0358` | `$C5` | 16 | `$48` | `$048` | $1600–$1606 (logótipo TAITO grande) |
| 111 | `$001D46` | `$0390` | `$C5` | 16 | `$48` | `$038` | $1607–$160D |
| 112 | `$001D5C` | `$0440` | `$00` | 8 | `$1C` | `$028` | `"TAITO ORIGINAL VIDEO GAME"` |
| 113 | `$001D7C` | `$0000` | `$00` | 8 | `$50` | `$0C8` | `"INSERT COIN"` |
| 114 | `$001D8E` | `$0000` | `$00` | 8 | `$20` | `$0C8` | `"INSERT 2 COINS TO START"` |
| 115 | `$001DAC` | `$0000` | `$00` | 8 | `$20` | `$0C8` | `"INSERT 3 COINS TO START"` |
| 116 | `$001DCA` | `$0000` | `$00` | 8 | `$20` | `$0C8` | `"INSERT 4 COINS TO START"` |
| 117 | `$001DE8` | `$0000` | `$00` | 8 | `$30` | `$0C8` | `"ADD 1 COIN TO START"` |
| 118 | `$001E02` | `$0000` | `$00` | 8 | `$30` | `$0C8` | `"ADD 2 COINS TO START"` |
| 119 | `$001E1E` | `$0000` | `$00` | 8 | `$30` | `$0C8` | `"ADD 3 COINS TO START"` |
| 120 | `$001D12` | `$00E0` | `$00` | 8 | `$28` | `$0A0` | `"FANTASTIC ROUND CLEAR!"` |

Notas de leitura:

- As aspas dentro das mensagens 96, 98 e 103 são o carácter `"` (`$22`) mesmo — a fonte tem
  glifo para ele.
- A mensagem 102 acaba com dois espaços; não é erro de transcrição, estão na ROM.
- As mensagens 41 e 50 (`SCORE ... NAME`) dizem o mesmo mas diferem no número de espaços,
  na cor e na posição: são o cabeçalho da lista e o cabeçalho da linha em edição.
- A mensagem 60 tem X = `$FFFE` (−2) e cinco tiles `$0E` — são os placeholders dos cinco
  ícones de vida, que `txt_draw_lives_icons` (`$003170`) repinta com o tile `$149` escrevendo
  em `SPRITE_RAM+$62C`, que é a word de código do slot `$628`. O primeiro slot da mensagem 60
  é exactamente `$628`.
- **O painel do escudo.** Os 52 tiles das mensagens 78–81, descodificados como quatro linhas
  de 13, dão em claro `WARNING!` na linha de cima e `SHIELD ENERGY 0` na de baixo. Com a
  mensagem 76 (`SHIELD`) e o campo numérico 21 (§5.3), isto identifica o contador
  `g_countdown_bcd` (`$10018A`) do HUD como **energia do escudo** — a dúvida que ficou por
  resolver em [`docs/ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md) (banda 02, ponto 1). Ver §9.

---

## 5. `txt_draw_number` (`$00196C`)

### 5.1 A tabela de 22 campos

`txt_number_field_table` está em `$0019EC`, 22 registos de 8 bytes (`$B0` bytes,
`$0019EC`–`$001A9B`):

| Offset | Campo |
|---|---|
| `+0` byte | número de dígitos |
| `+1` byte | fonte: 0 = normal, ≠ 0 = alternativa |
| `+2` word | offset na RAM de sprites |
| `+4` long | ponteiro para o byte BCD **mais significativo** |

O ponteiro aponta para o topo e o laço anda para trás (`subq.l #1,a2`), porque os contadores
BCD do jogo estão guardados com o byte menos significativo no endereço mais baixo.

| # | registo | díg. | fonte | spr | ponteiro | variável | desenhado por |
|---|---|---|---|---|---|---|---|
| 0 | `$0019EC` | 6 | 0 | `$06E8` | `$10019E` | `g_score_bcd` (1UP) | `$0018EA`, `$003F74`, `$000AAC`, `$000AB8` |
| 1 | `$0019F4` | 6 | 0 | `$0730` | `$10019E` | `g_score_bcd` (2UP) | `$0018F6`, `$003F80`, `$0030BE`, `$000ACA` |
| 2 | `$0019FC` | 6 | 0 | `$0650` | `$100202` | `g_hiscore` | `$0018DE`, `$003F68`, `$0030EE` |
| 3 | `$001A04` | 2 | 0 | `$06D8` | `$100197` | `g_round_bcd` | `$00081A` |
| 4 | `$001A0C` | 3 | 1 | `$06A8` | `$10018F` | `g_area_pct_shown` | `$00083E`, `$004EEA` |
| 5 | `$001A14` | 2 | 0 | `$06D8` | `$100027` | `g_credits` | `$001906`, `$00097E`, `$000A62`, `$000C58`, `$0067B2`, `$003F96` |
| 6 | `$001A1C` | 6 | 0 | `$0078` | `$100205` | `g_hiscore_scores[0]` | laço `$0049AE` (6→15), `$000D00` |
| 7 | `$001A24` | 6 | 0 | `$00F0` | `$100208` | `g_hiscore_scores[1]` | idem |
| 8 | `$001A2C` | 6 | 0 | `$0168` | `$10020B` | `g_hiscore_scores[2]` | idem |
| 9 | `$001A34` | 6 | 0 | `$01E0` | `$10020E` | `g_hiscore_scores[3]` | idem |
| 10 | `$001A3C` | 6 | 0 | `$0258` | `$100211` | `g_hiscore_scores[4]` | idem |
| 11 | `$001A44` | 2 | 0 | `$00B0` | `$100212` | `g_hiscore_rounds[0]` | idem |
| 12 | `$001A4C` | 2 | 0 | `$0128` | `$100213` | `g_hiscore_rounds[1]` | idem |
| 13 | `$001A54` | 2 | 0 | `$01A0` | `$100214` | `g_hiscore_rounds[2]` | idem |
| 14 | `$001A5C` | 2 | 0 | `$0218` | `$100215` | `g_hiscore_rounds[3]` | idem |
| 15 | `$001A64` | 2 | 0 | `$0290` | `$100216` | `g_hiscore_rounds[4]` | idem |
| 16 | `$001A6C` | 6 | 0 | `$03D0` | `$10019E` | `g_score_bcd` (linha em edição) | laço `$004746` (16→17) |
| 17 | `$001A74` | 2 | 0 | `$0408` | `$100197` | `g_round_bcd` | idem |
| 18 | `$001A7C` | 2 | 0 | `$06E8` | `$100337` | `g_dev_enemy_count` | `$0079C2`, `$007A6C` |
| 19 | `$001A84` | 2 | 0 | `$0028` | `$100197` | `g_round_bcd` | `$00073E`, `$003BA4` |
| 20 | `$001A8C` | 2 | 0 | `$00A8` | `$100197` | `g_round_bcd` | `$003704` |
| 21 | `$001A94` | 3 | 0 | `$0600` | `$10018B` | `g_countdown_bcd` | `$007F60`, `$007FC8` |

O campo 18 é do editor de inimigos que ficou na ROM final (`enemy_dev_placer`); usa o mesmo
`spr` do campo 0, ou seja escreve por cima dos dois primeiros dígitos da pontuação do 1UP.

### 5.2 O laço, a ordem dos nibbles e a supressão de zeros

```
loc_00198E:
        cmpi.b  #$1,d0
        bne.b   loc_001996
        moveq   #$1,d5          ; último dígito: força "significativo"
loc_001996:
        btst.b  #$0,d0
        beq.b   loc_0019AE
        move.b  (a2),d1         ; contagem ímpar -> nibble BAIXO
        andi.w  #$F,d1
        bsr.w   txt_number_digit_to_tile
        move.w  d1,$4(a1)
        subq.l  #$1,a2          ; e recua um byte
        bra.b   loc_0019BE
loc_0019AE:
        move.b  (a2),d1         ; contagem par -> nibble ALTO
        lsr.b   #$4,d1
        andi.w  #$F,d1
        bsr.w   txt_number_digit_to_tile
        move.w  d1,$4(a1)
loc_0019BE:
        addq.l  #$8,a1          ; slot seguinte
        subq.w  #$1,d0
        bne.b   loc_00198E
```

O contador `d0` conta de N até 1 e a paridade escolhe o nibble: com N par começa no nibble
alto do byte apontado, com N ímpar começa no nibble baixo. Em ambos os casos o primeiro
dígito emitido é o mais significativo e o último é as unidades. Um campo de N dígitos lê
`ceil(N/2)` bytes, a acabar no ponteiro.

```
txt_number_digit_to_tile:
        tst.w   d5
        bne.b   loc_0019D4
        tst.w   d1
        bne.b   loc_0019D4
        move.w  #$0,d1          ; zero à esquerda -> tile 0 (o glifo do espaço)
        rts
loc_0019D4:
        moveq   #$1,d5
        tst.b   d6
        bne.b   loc_0019E0
loc_0019DA:
        addi.w  #$10,d1         ; fonte normal: '0' é ASCII $30 -> tile $10
        rts
loc_0019E0:
        cmpi.w  #$1,d0
        beq.b   loc_0019DA      ; fonte alternativa, mas o ÚLTIMO dígito é normal
        addi.w  #$13E,d1        ; fonte alternativa: dígitos grandes
        rts
```

- **Supressão de zeros à esquerda:** enquanto `d5` for 0 e o dígito for 0, o tile é 0 — o
  glifo do espaço, ou seja o placeholder da mensagem fica em branco. O `cmpi.b #$1,d0` no
  topo do laço garante que o último dígito é sempre impresso, portanto um valor zero mostra
  `0` e não vazio.
- **Fonte normal:** `tile = $10 + dígito`, que é exactamente `ASCII('0') − $20 + dígito`.
- **Fonte alternativa:** `tile = $13E + dígito` (dígitos grandes, §2.3) excepto no último
  dígito, que volta à fonte normal. Só o campo 4 (a percentagem) a usa: dois dígitos grandes
  e o das décimas pequeno. Os detalhes do que a percentagem significa estão em
  [`docs/06-gameplay.md`](06-gameplay.md) §6.

### 5.3 O campo 21 e a energia do escudo

`hud_draw_countdown_labels` (`$007F4C`,
[`src/main68k/game_countdown.asm`](../src/main68k/game_countdown.asm)) desenha a mensagem 76
(`SHIELD`, quatro tiles largos), a mensagem 77 (três pontos) e o campo 21 por cima dos
pontos. O campo tem 3 dígitos e ponteiro `$10018B`, portanto lê o nibble baixo de `$10018B`
(centenas) e os dois nibbles de `$10018A` (dezenas e unidades).

Isto explica um valor que parecia estranho: `game_countdown_set_9` (`$007F44`) faz
`move.w #$9,$18A(a5)`, o que em big-endian põe `$00` em `$18A` e `$09` em `$18B` — no ecrã
lê-se **900**. `game_countdown_floor_3` (`$007F34`) compara `$18B(a5)` com 3, ou seja o piso
é **300**.

---

## 6. `txt_draw_ram_string` (`$0031A6`)

A terceira rotina: como `txt_draw_message`, mas o texto vem da RAM e as coordenadas não são
tocadas. Registos de 8 bytes em `txt_ram_string_table` (`$0031E0`), com
`{nº chars .b, attr .b, offset sprite .w, ponteiro .l}`:

```
loc_0031C8:
        clr.w   d1
        move.b  (a2),d1
        addi.w  #$FFE0,d1       ; a mesma regra: tile = ASCII - $20
        move.w  d1,$4(a1)       ; código
        move.w  d2,(a1)         ; attr
        addq.l  #$1,a2
        addq.l  #$8,a1
        subq.w  #$1,d0
        bne.b   loc_0031C8
```

Não há terminador nem caso especial para o espaço: escreve exactamente N slots. São 25
registos (`$0031E0`–`$0032A7`, 200 bytes):

| # | chars | attr | spr | ponteiro | uso |
|---|---|---|---|---|---|
| 0–4 | 3 | `$00` | `$00C0`, `$0138`, `$01B0`, `$0228`, `$02A0` | `$100217`+3k | `g_hiscore_names`, as 5 iniciais do ranking |
| 5–7 | 1 | `$00` | `$0418`, `$0420`, `$0428` | `$100226`, `$100227`, `$100228` | `g_name_edit_buf`, as 3 letras em edição |
| 8 | 4 | `$0E` | `$0168` | `$100362` | percentagem "DD.D" do HUD de fim de ronda |
| 9–15 | 4 | `$00` | `$01A0`, `$0240`, `$02C8`, `$0350`, `$03D8`, `$0460`, `$04E8` | `$100346`+4k | escada de percentagens |
| 16–22 | 3 | `$00` | `$01E0`, `$0280`, `$0308`, `$0390`, `$0418`, `$04A0`, `$0528` | `$100366`+3k | montantes do bónus |
| 23 | 3 | `$0E` | `$05A0` | `$10037B` | montante do bónus escolhido |
| 24 | 7 | `$0E` | `$0610` | `$10040C` | total |

Chamadores: `hiscore_entry` (laços `$00475C` para 5–7 e `$0049C4` para 0–4, mais
`$004AC8`/`$004B04`/`$004B2A`/`$004B42` durante a edição), `attract_loop_script`
`$000D3C`–`$000D54` (0–4) e `game_roundclear_script` (`$003718`–`$00376C` para 8 e 16–22,
`$0038C6`–`$003914` para 9–22, `$0039EA` para 23 e `$003ABA` para 24). O conteúdo dos textos de percentagem e bónus é montado por `txt_format_percent`
(`$003340`) e está descrito em [`docs/06-gameplay.md`](06-gameplay.md) §6.5 e §11.6.

> **Anotação a corrigir.** `symbols/main68k.sym` declara `txt_ram_string_table` com `003E`
> bytes ("8 x 8 bytes"). São 25 registos, `$C8` bytes. Por causa disso os registos 8–24
> aparecem hoje como um bloco anónimo em
> [`src/main68k/unclassified_003_21e.asm`](../src/main68k/unclassified_003_21e.asm)
> (`$00321E`–`$0032A7`). O byte a seguir, `$0032A8`, é mesmo código
> (`game_check_area_target`).

---

## 7. As três rotinas a trabalhar juntas

A linha "1ST" do ranking, do princípio ao fim. A mensagem 43 é
`"1ST ......0    ..  ..."`, com `spr = $0060`, Y = `$28`, X = `$0A0`, passo 8.

| Caracteres | Slots consumidos | Quem repinta |
|---|---|---|
| `1`, `S`, `T` | `$0060`, `$0068`, `$0070` | — |
| espaço | nenhum (Y avança 8) | — |
| `......` | `$0078`…`$00A0` | campo numérico **6** (`spr = $0078`, 6 dígitos, `g_hiscore_scores[0]`) |
| `0` | `$00A8` | — (é o zero fixo: a pontuação está guardada a dividir por 10) |
| 4 espaços | nenhum | — |
| `..` | `$00B0`, `$00B8` | campo numérico **11** (`spr = $00B0`, 2 dígitos, `g_hiscore_rounds[0]`) |
| 2 espaços | nenhum | — |
| `...` | `$00C0`, `$00C8`, `$00D0` | registo de string **0** (`spr = $00C0`, 3 chars, `g_hiscore_names`) |

Os três offsets batem certo ao byte. Fiz esta simulação para as 121 mensagens e as 47
entradas das duas tabelas de campos: **todos** os slots iniciais e todos os slots seguintes
de cada campo existem no conjunto de slots que alguma mensagem pinta, e o carácter que lá
está é `.` ou `0`. É a validação mais forte que se pode fazer do formato sem emular.

O mesmo padrão explica o resto do HUD: a mensagem 11 (`CREDIT 00`) hospeda o campo 5, as
mensagens 37/38/39 (`000000`) hospedam os campos 2/0/1, a mensagem 35 (três `$13E`) hospeda o
campo 4, a mensagem 61 (`ROUND ..`) hospeda o campo 19, a 65 (`ROUND .. CLEAR`) o campo 20 e
a 77 (`...`) o campo 21.

Um detalhe de alinhamento que só se percebe olhando para os números:
`game_init_hiscore_table` (`$00187A`) faz `subq.w #$8` a `SPRITE_RAM+$69E`, `+$72E` e `+$776`
logo a seguir a desenhar as mensagens 32, 33 e 34. Esses endereços são a word de **X**
(offset `+6`) de um slot cada, e o motivo é sempre o mesmo: os rótulos largos vivem na coluna
X `$138` e os dígitos na coluna X `$130`, 8 pixels ao lado.

- Mensagem 34 (`2UP` + `0`): o slot afectado é o do `0`, que passa de X `$138` para `$130` —
  a coluna dos seis dígitos da pontuação (mensagem 39). O `0` fica em Y `$E0`, logo a seguir
  ao último dígito, em `$D8`. É o zero fixo da pontuação. O mesmo para a mensagem 33.
- Mensagem 32 (`HIGH SCORE`): o slot afectado é o do tile `$47`, e este tile é especial —
  é o único rótulo que usa as 16 colunas. Tem três blocos de pixels: `CO` nas colunas 9–15
  (linhas 1–7 e 9–15) e um `0` nas colunas 1–7, linhas 9–15. Com X = `$130`, o `CO` cai em
  X `$139`–`$13F` (coluna dos rótulos) e o `0` cai em X `$131`–`$137` (coluna dos dígitos),
  Y `$91`–`$97` — a célula logo a seguir ao sexto dígito da melhor pontuação. Um único tile
  carrega o `CO` de "SCORE" e o zero fixo do HIGH SCORE, e o `subq` põe cada metade na sua
  coluna.

---

## 8. Os outros caminhos de texto

Não passam por nenhuma das tabelas acima, mas usam a mesma fonte e a mesma regra `− $20`.

**TEST MODE** — `txt_draw_string_sprites` (`$014556`,
[`src/main68k/selftest_service_mode.asm`](../src/main68k/selftest_service_mode.asm)):

```
txt_draw_string_sprites:
        clr.w   d2
        move.b  (a2)+,d2
        cmpi.b  #$FF,d2         ; $FF termina
        beq.b   loc_014576
        subi.w  #$20,d2
        beq.b   loc_014570      ; espaço: só avança
        move.w  #$0,(a3)+       ; attr
        move.w  d0,(a3)+        ; Y
        move.w  d2,(a3)+        ; código
        move.w  d1,(a3)+        ; X
loc_014570:
        addi.w  #$8,d0
        bra.b   txt_draw_string_sprites
```

O chamador passa a2 (texto), a3 (cursor na RAM de sprites), d0 (Y) e d1 (X). Os rótulos do
TEST MODE são registos `{word Y, word X, texto…, $FF}` a partir de `$0143B4`.

**Staff roll / final** — `txt_render_line_sprites` (`$015696`,
[`src/main68k/ending_sprites.asm`](../src/main68k/ending_sprites.asm)) tem uma
mini-linguagem: `$CD` termina a linha, `$18 nn` muda a cor para `nn − $24`, `$16 nn` repete
nn vezes um código de 16 bits que vem a seguir, `$20` avança 8 sem escrever, e qualquer outro
byte é `carácter − $20`. Mantém cursor, cor, Y e X em `$10296C`–`$102974` e o cursor de
sprites dá a volta em `SPRITE_RAM+$600` — 192 slots de texto.

**A fonte de 8×8 da ROM de tiles** (`maincpu` `$080000`, `tile = ASCII` sem subtracção)
existe, está extraída em `assets/font/rom8/`, e **não é usada por nada** no jogo final. A
demonstração está em [`docs/03-video.md`](03-video.md) §7.3.

---

## 9. Achados e correcções desta passagem

1. **`g_countdown_bcd` é a energia do escudo.** Os tiles das mensagens 78–81 lêem
   `WARNING!` / `SHIELD ENERGY 0` e os da mensagem 76 lêem `SHIELD`; o campo numérico 21
   desenha `$10018A`/`$10018B` ao lado do rótulo. Somando a isso a leitura de nibbles do §5.2
   (o `move.w #$9` mostra 900, o piso mostra 300), a dúvida registada em
   [`docs/ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md) (banda 02, ponto 1) fica respondida
   pelo lado gráfico. Nota de honestidade: o que verifiquei foi o *texto do rótulo* e a
   aritmética do campo; não emulei o jogo para ver o número a descer no ecrã.
2. **`hud_draw_gameover_items` (`$0080FE`) está mal nomeada** — desenha o painel de aviso do
   escudo, não itens de game over. E as mensagens 82–89 são os dígitos gigantes `3`, `2`,
   `1`, `0` (dois tiles em cima, dois em baixo, por dígito), escolhidos por
   `d0 = $52 + 2·g_timeout_step` e desenhados aos pares — uma contagem 3-2-1-0 de `$40`
   frames por passo. Se o bit 0 de `$303(a5)` estiver a 1, em vez de desenhar chama
   `spr_hide_block_5E0` (`$0080F2`), que esconde os oito slots a partir de `SPRITE_RAM+$5E0`:
   o dígito pisca.
3. **`txt_refresh_hud_attrs` (`$0017D2`) não escreve atributos, escreve X.** Os destinos são
   `SPRITE_RAM+$656` e `SPRITE_RAM+$6EE`, que são `slot+6`, e os valores das tabelas
   (`$0130`/`$0138` na normal, `$012E`/`$0136` na de flip) são as mesmas coordenadas X que as
   mensagens do HUD usam, menos 2 na versão espelhada. O nome e o comentário do símbolo, e os
   comentários de `hud_attr_table_normal`/`hud_attr_table_flip`, deviam falar de X.
4. **`txt_ram_string_table` está declarada com 62 bytes e tem 200** (§6).
5. **Duas mensagens sem chamador nesta ROM:** a 0 (o wordmark TAITO de seis tiles da fonte) e
   a 62 (`READY!`). Para a 62 procurei `#$3E,d0` em toda a listagem do 68000 e não existe;
   nenhum dos quatro sítios com índice calculado pode produzir 62. Para a 0, os únicos
   `moveq #$0,d0` perto de uma chamada são de `txt_draw_number`.
6. **A mensagem 3 (`© 1989 TAITO AMERICA CORP.`) tem chamador mas nunca aparece neste set:**
   `sub_0009DA` escolhe 1 / 3 / 4 conforme `region_code` valer 1 (Japão), 2 (EUA) ou outro, e
   `$03FFFE` desta ROM vale `$0003` (Mundo), que cai no `else` da mensagem 4.

Nenhuma destas correcções foi aplicada a `symbols/fragments/` — ficam aqui registadas para
quem editar os fragmentos a seguir.

---

## 10. O que não sabemos

**1. Que gráfico são as mensagens 5–10 e 78–81, exactamente.** Descodifiquei os tiles e
leio "VOLFIED" no primeiro bloco e "WARNING! / SHIELD ENERGY 0" no segundo, mas montei-os
fora do emulador, com uma paleta artificial e com a minha interpretação dos eixos. A leitura
das palavras é inequívoca; a montagem exacta (que tile fica onde) não foi verificada contra
uma captura de ecrã.

**2. Porque é que a mensagem 60 tem X = −2.** Os cinco ícones de vida ficam com X = `$FFFE`,
que o PC090OJ trata como −2. Metade do sprite fica fora do ecrã, ou o `x_offset` do
dispositivo compensa. Não confirmei qual.

**3. Quantas mensagens estão realmente vivas.** O levantamento do §4.1 é um varrimento de
texto sobre a listagem, com casos de ramo condicional resolvidos à mão (a mensagem 16, por
exemplo, só aparece se se ler o `moveq #$10,d0` que fica antes de um `beq`). Um índice que
venha de uma tabela ou de um registo escapa-lhe. Não encontrei nenhum caso desses, mas não
posso provar que não existe.

**4. A ordem exacta dos eixos com `ROT270`.** A direcção de leitura (Y interno → horizontal)
está provada pelo próprio texto. O sinal da vertical (X maior = mais acima) vem da definição
`ROT270 = SWAP_XY | FLIP_Y` do MAME mais a coerência das linhas de história; não o verifiquei
numa captura.

**5. O que faz o `%` do tile `$148`.** A mensagem 63 usa o `%` pequeno (`$05`, ASCII `%`) e
`txt_show_pct_symbol_maybe` escreve `$13E` — o `0` grande — na posição do segundo dígito. Não
encontrei quem escreva `$148`.
