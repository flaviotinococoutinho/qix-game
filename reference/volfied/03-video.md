# 03 — Vídeo

Como o Volfied põe uma imagem no ecrã, do lado do **software**: o que é uma word de VRAM e
como se transforma numa cor, o que são as «imagens A e B», para que serve o `VIDEO_MASK`,
porque é que há duas páginas de VRAM e porque é que elas não são duplo buffer, como se
constrói a lista de sprites do PC090OJ sem nunca programar o `sprite_ctrl`, como funciona a
paleta, e como os gráficos foram extraídos para `assets/`.

**O que este documento não cobre.** A vista de placa (que chip faz o quê, os registos, o
ritmo do frame) está em [`docs/01-hardware.md`](01-hardware.md) §9; as faixas de endereços e
o mapa da RAM estão em [`docs/02-mapa-de-memoria.md`](02-mapa-de-memoria.md) §2.4–2.6; o
**algoritmo de preenchimento de área** — que é quem escreve a maior parte dos pixels — está
em [`docs/06-gameplay.md`](06-gameplay.md) §5. Aqui continua-se a partir desses, ao nível
das rotinas, e liga-se em vez de repetir.

**Método.** A fonte autoritativa de endereços e formatos é
[`reference/HARDWARE_GROUND_TRUTH.md`](../reference/HARDWARE_GROUND_TRUTH.md). Todos os
excertos deste documento foram copiados da listagem gerada em `src/main68k/`; todas as
medições sobre dados (tabelas, mapas, tiles, PROMs) foram refeitas sobre `build/*.bin` com o
Python do projecto e os comandos estão indicados. Onde uma afirmação é conjectura, está
marcada como tal e tem a evidência ao lado. A secção §10 junta o que ficou por resolver.

**Convenções.** `$` = hexadecimal, endereços do 68000 com 6 dígitos. Nos excertos retirei a
coluna final com os bytes crus, para caber na largura; a instrução e o comentário de endereço
são os da listagem. «Entrada de paleta» é o índice de 0 a `$1FFF`; «byte de paleta» é o
endereço absoluto em `$500000+`.

---

## 1. O que compõe um frame

Não há camada de tiles nem camada de texto. O ecrã inteiro são **duas** coisas:

| Camada | Onde vive | Opacidade | Quem escreve |
|---|---|---|---|
| bitmap | VRAM, `$400000–$47FFFF`, uma word por pixel | opaca, cobre todos os pixels | o 68000, pixel a pixel ou por blitter de tiles |
| sprites | RAM do PC090OJ, `$200000–$2007FF` | pen 0 transparente | o 68000, 8 bytes por sprite |

`screen_update` em [`reference/mame/volfied.cpp`](../reference/mame/volfied.cpp) tem três
linhas: limpa a máscara de prioridade, pinta a camada bitmap (que escreve *todos* os pixels)
e desenha os sprites por cima. O `colpri_cb` do Volfied devolve `pri_mask = 0` — comentado no
próprio driver como «sprites over everything». Não há prioridade entre camadas.

Consequência prática: **todo o texto do jogo é sprites** — HUD, mensagens, TEST MODE, staff
roll. Ver [`src/main68k/txt_message_renderer.asm`](../src/main68k/txt_message_renderer.asm),
[`txt_number_renderer.asm`](../src/main68k/txt_number_renderer.asm) e
[`ending_sprites.asm`](../src/main68k/ending_sprites.asm).

### 1.1 O que corre no VBLANK

O IRQ 4 (`irq4_vblank_handler`, `$000400`,
[`src/main68k/irq_vblank_dispatch.asm`](../src/main68k/irq_vblank_dispatch.asm)) só faz o
desenho completo em dois estados do guião:

```
irq4_vblank_handler:
        ori.w   #$F00,sr                                                ; $000400
        movem.l d0-d7/a0-a4/a6,-(a7)                                    ; $000404
        move.b  d0,SPRITE_CTRL_B                                        ; $000408
        jsr     (vblank_service).l                                      ; $00040E
        move.w  VIDEO_CTRL,$5A(a5)      ; g_collision_status ($10005A)  ; $000414
        move.w  $22(a5),d0              ; g_seq_mode ($100022)          ; $00041C
        cmpi.w  #$3,d0                                                  ; $000420
        beq.b   loc_000434                                              ; $000424
        cmpi.w  #$5,d0                                                  ; $000426
        bne.b   loc_00043E                                              ; $00042A
        cmpi.w  #$E,$24(a5)             ; g_seq_step ($100024)          ; $00042C
        bne.b   loc_00043E                                              ; $000432
loc_000434:
        bsr.w   vram_frame_draw_all                                     ; $000434
```

Fora desse caminho, o handler só chama `vram_ctrl_strobe` (`$00043E`). A **camada bitmap não
é redesenhada por frame**: é persistente e é a única cópia do estado do jogador. O que muda
de frame para frame são os pixels que o motor de preenchimento e a trilha escrevem, mais a
paleta e a lista de sprites.

`vram_frame_draw_all` (`$004B9C`,
[`src/main68k/game_frame.asm`](../src/main68k/game_frame.asm)) é a ordem canónica:

| Ordem | Rotina | Endereço | O que faz |
|---|---|---|---|
| 1 | `pal_trail_cycle` | `$005780` | cicla a cor da trilha (§7.3) |
| 2 | `pal_hit_flash_step` | `$006A04` | flash da cor da parede |
| 3 | `pal_player_fade_step` | `$00571C` | fade da cor da parede ao perder vida |
| 4 | `pal_flush` | `$014772` | `pal_fade_step` + `pal_copy_banks` |
| 5 | `vram_ctrl_strobe` | `$00144E` | pulso dos bits 3 e 6 de `VIDEO_CTRL` |
| 6 | `spr_flush_shadow` | `$014752` | copia 96 sprites de `$102350` para `SPRITE_RAM+$180` |
| 7 | — | — | emissores directos de sprites (jogador e quatro tabelas de objectos) |

O passo 6 é saltado se `$10086C` (`g_timeout_state`) valer 1. O passo 7 escolhe entre o
jogador (`spr_draw_obj` com o metasprite de `$1(a4)`) e os destroços (`spr_draw_table_3400`)
conforme `$5(a4)`, e depois chama sempre `spr_draw_table_3000`; se
`$103844` (`g_stage_clear_hud`) for zero, chama ainda `spr_draw_obj_3820_maybe`,
`spr_draw_table_3300` e `spr_draw_table_3700`.

### 1.2 O desenho pesado corre fora do VBLANK

Pintar um fundo inteiro custa 32×28 tiles × 64 pixels = 57 344 escritas de word. Isso não cabe
num VBLANK, e por isso é diferido: o laço principal (`$00161C`) é
`bsr vram_deferred_cmd_dispatch / bra`, e quem quer um desenho escreve um código no byte
`$100804` (`g_vram_cmd`) e fica em espera activa até ele voltar a zero.

`vram_deferred_cmd_dispatch` (`$005CD6`,
[`src/main68k/vram_area_fill_engine.asm`](../src/main68k/vram_area_fill_engine.asm)):

| `$100804` | Acção |
|---|---|
| 2 | `vram_area_fill` — o preenchimento de área ([06 §5](06-gameplay.md)) |
| 3 | `lvl_draw_bg_by_level` (`$006FF4`) — imagem A do round actual |
| 4 | `lvl_draw_bg2_by_level` (`$007138`) — imagem B do round actual |
| 5 | `lvl_draw_bg_layers` (`$006FFC`) — imagem A, índice explícito em `$1008FE` |
| 6 | `lvl_draw_bg2_layers` (`$007140`) — imagem B, índice explícito |
| 7 | `vram_clear_page0` (`$00148C`) |

Todos os casos excepto o 2 fazem `clr.b $804(a5)` no fim. O handler de VBLANK salta o
despacho de estado enquanto `$100804 == 2` (`$00044A`), porque o preenchimento não pode ser
interrompido a meio.

---

## 2. Geometria

### 2.1 Endereçamento e os dois eixos

Três rotinas fazem a mesma conta, com convenções ligeiramente diferentes:

| Rotina | Endereço | Base | Espelhamento |
|---|---|---|---|
| `vram_addr_from_xy` | `$004F7E` | `$10006A` (página activa) | não |
| `vram_addr_from_xy_a1` | `$004F96` | idem, mas lê d4/d5 e devolve em a1 | não |
| `vram_addr_from_xy_016258` | `$016258` | idem | sim, `$100030` |
| `vram_addr_raw` | `$0181D8` | nenhuma (offset puro) | não |

A primeira, em [`src/main68k/vram_addr_math.asm`](../src/main68k/vram_addr_math.asm):

```
vram_addr_from_xy:
        clr.l   d2                                                      ; $004F7E
        clr.l   d3                                                      ; $004F80
        move.w  d0,d2                                                   ; $004F82
        move.w  d1,d3                                                   ; $004F84
        movea.l $6A(a5),a0              ; g_vram_page_ptr ($10006A)     ; $004F86
        lsl.l   #$1,d2                                                  ; $004F8A
        lsl.l   #$8,d3                                                  ; $004F8C
        lsl.l   #$2,d3                                                  ; $004F8E
        or.l    d3,d2                                                   ; $004F90
        adda.l  d2,a0                                                   ; $004F92
```

`endereço = página + linha·$400 + coluna·2`. 512 words por linha, 256 linhas, `$40000` bytes
por página. A inversa `vram_xy_from_offset` (`$004F66`) mascara com `$0003FFFE` — 18 bits,
uma página inteira — e devolve `d0 = (off>>1) & $1FF` (coluna) e `d1 = (off>>10) & $FF`
(linha).

A versão de `$016258` acrescenta o espelhamento de cocktail: com `$100030 == 0`,
`linha ← $FE − linha` e `coluna ← $140 − coluna`. Os dois limites (`$FF` e `$13F`) provam os
domínios: 256 linhas e 320 colunas.

**Os eixos não são x/y no sentido do monitor.** O MAME lê a VRAM assim:

```c
for (int y = 0; y < height; y++) {          // y = LINHA de VRAM, 0..255
    for (int x = 1; x < width + 1; x++)     // x = COLUNA de VRAM, 1..320
        bitmap.pix(y, x - 1) = color;
    p += 512;
}
```

e o ecrã é declarado `ROT270`. Logo:

| Eixo na VRAM | Extensão | Visível | Eixo no monitor |
|---|---|---|---|
| linha, `d1`/`d0` de `$016258` | 0–255 | 8–247 (240) | **horizontal** |
| coluna | 0–319 (a linha física tem 512 words) | 0–319 (320) | **vertical** |

O monitor é 240 de largura por 320 de altura — retrato. Tenha isto presente ao ler qualquer
coordenada da listagem: o jogo raciocina sempre em linha/coluna de VRAM e nunca lhes chama
x/y de forma consistente.

### 2.2 Duas páginas, uma por jogador

`$10006A` (`g_vram_page_ptr`, long) guarda a base da página activa e toma exactamente dois
valores em toda a ROM: `$400000` e `$440000`. `vram_select_page` (`$00146C`,
[`src/main68k/vram_ctrl_and_clear.asm`](../src/main68k/vram_ctrl_and_clear.asm)) põe o bit 0
de `VIDEO_CTRL` a partir de `$100036` (jogador activo):

```
vram_select_page:
        move.w  $28(a5),d0              ; g_video_ctrl_shadow ($100028) ; $00146C
        tst.w   $36(a5)                 ; g_cur_player ($100036)        ; $001470
        bne.b   loc_001486                                              ; $001474
        andi.w  #$FFFE,d0                                               ; $001476
loc_00147A:
        move.w  d0,VIDEO_CTRL                                           ; $00147A
        move.w  d0,$28(a5)                                              ; $001480
        rts                                                             ; $001484
loc_001486:
        ori.w   #$1,d0                                                  ; $001486
        bra.b   loc_00147A                                              ; $00148A
```

**Não é duplo buffer.** É uma página *por jogador*: num jogo de dois, cada um mantém a sua
área conquistada intacta enquanto o outro joga — a página é o estado do jogador tanto como os
128 bytes de contexto em RAM. O reset limpa as duas (`vram_clear_page0`/`vram_clear_page1`,
`$00148C`/`$0014A2`, `util_fill_longs` com `d1 = 0`, que é o caso degenerado de 65536 voltas
= 256 KB exactos por página).

O duplo buffer existe, mas é **por pixel**, dentro da própria word — é o `VIDEO_MASK` (§4.2).

### 2.3 `VIDEO_CTRL` (`$D00000`), lado da escrita

Cinco escritas e uma leitura em toda a ROM. Os bits usados:

| Bit | Escrito por | Quando |
|---|---|---|
| 0 | `vram_select_page` (`$00146C`) | ao trocar de jogador |
| 3 e 6 | `vram_ctrl_strobe` (`$00144E`) | uma vez por frame, apagados e voltados a acender |
| 7 | `reset_entry` (`bset.b #$7,VIDEO_CTRL_B`, `$0014F8`) | uma única vez, no arranque |

O registo é só de escrita — a leitura do mesmo endereço devolve estado de colisão — e por
isso o jogo mantém uma sombra em `$100028` (`g_video_ctrl_shadow`), inicializada a `$80` em
`$001504`. Depois do primeiro `vram_ctrl_strobe` a sombra vale `$C8`. O lado da leitura
(colisão) está em [`docs/01-hardware.md`](01-hardware.md) §9.4 e não é matéria deste
documento.

### 2.4 O campo de jogo, medido

`vram_draw_border_frame` (`$0071A4`,
[`src/main68k/vram_tilemap_blit.asm`](../src/main68k/vram_tilemap_blit.asm)) desenha a
moldura com a constante `$8040` (bit 15 + bit 6) em quatro traços de endereços absolutos, e
`util_fill_words_until` / `util_fill_column_until` preenchem `[a0, a1)`:

| Traço | Offset inicial | Offset final (exclusivo) | Em (linha, coluna) | Elementos |
|---|---|---|---|---|
| linha de cima | `$003C26` | `$003E5C` | linha 15, colunas 19–301 | 283 words |
| linha de baixo | `$03BC26` | `$03BE5C` | linha 239, colunas 19–301 | 283 words |
| coluna esquerda | `$003C26` | `$03C026` | coluna 19, linhas 15–239 | 225 words |
| coluna direita | `$003E5A` | `$03C25A` | coluna 301, linhas 15–239 | 225 words |

Bate exactamente com os limites de movimento do jogador, em
[`src/main68k/player_control.asm`](../src/main68k/player_control.asm):

```
        cmpi.w  #$13,d4                 ; limites do campo de jogo      ; $00524C
        cmpi.w  #$12E,d4                                                ; $005254
        cmpi.w  #$F,d5                                                  ; $00525C
        cmpi.w  #$F0,d5                                                 ; $005264
```

coluna em `[$13, $12D]` = 19–301, linha em `[$0F, $EF]` = 15–239. `collide_build_box`
(`$01628A`) repete os mesmos quatro números.

Logo o campo de jogo, moldura incluída, são **283 colunas × 225 linhas** de VRAM, que no
monitor é **225 de largura por 283 de altura** — retrato, dentro dos 240×320 visíveis.

Fora da moldura, `vram_init_playfield` (`$007222`) enche com `$8000` (bit 15 só) três colunas
a partir de `$2020` (linha 8, coluna 16) e duas a partir de `$225C` (linha 8, coluna 302),
`$F0` = 240 linhas cada: as colunas 16–18 e 302–303 nascem já «conquistadas».

---

## 3. A word de VRAM

### 3.1 Os bits, e quem os escreve

O layout dos bits e as provas por bit estão em
[`docs/02-mapa-de-memoria.md` §2.5](02-mapa-de-memoria.md). Repito aqui só a tabela de
escritores, porque é o que interessa a quem reimplementa o desenho:

| Bit(s) | MAME | Significado | Escrito por |
|---|---|---|---|
| 15 | selecciona imagem | pixel conquistado → mostra a imagem B | `$0071B4` (`$8040`), `$004F4E`, `$00529A`/`$0052F6`/`$00532C`, `$00723C` (`$8000`) |
| 14 | `?` («cantos 3-D») | nenhuma escrita encontrada | — |
| 13 | `?` («paredes 3-D») | nenhuma escrita encontrada | — |
| 12–9 | imagem B | nibble da imagem revelada | `vram_blit_tile8_b` (`$00733C`) e a variante espelhada |
| 8 | índice de paleta bit 10 | célula ocupada por objecto fixo do nível | `vram_mark_object_block` (`$004F42`), fase A do fill |
| 7 | índice de paleta bit 9 | trilha em construção | `$005294`, `$0052F0`, `$005326` (limpo em `$00538E`, `$0053C8`) |
| 6 | índice de paleta bit 8 | parede / fronteira de área | `vram_draw_border_frame` (`$0071A4`), fase B do fill |
| 5 | `?` | rascunho do motor de preenchimento | `$005D6C` (`bset`), `$005D74` (`bclr`) |
| 4 | `?` | nenhuma escrita encontrada | — |
| 3–0 | imagem A | nibble da imagem por conquistar | `vram_blit_tile8` (`$0070F6`) e a variante espelhada |
| 0 | (LSB da imagem A) | usado como marca por três rotinas de depuração | `$0168A0`, `$0168BC`, `$017CBA`, `$017D2C` |

As escritas de bit isolado usam o truque de endereçar meio-word: `bset.b #$7,(a0)` toca o
byte **alto**, logo o bit 15; `bset.b #$7,$1(a0)` toca o byte baixo, logo o bit 7.

```
; moldura do campo: bit 15 + bit 6
        move.w  #$8040,d0                                               ; $0071B4

; bloco 15x15 de objecto de nivel: bits 15 e 8 (vram_mark_object_block)
        bset.b  #$7,(a0)                                                ; $004F4E
        bset.b  #$0,(a0)                                                ; $004F52

; pixel de trilha: bit 7 (marcador) + bit 15 (visivel)
        bset.b  #$7,$1(a1)                                              ; $005294
        bset.b  #$7,(a1)                                                ; $00529A

; apagar a trilha ao morrer: limpa bits 15 e 7
        andi.w  #$7F7F,d0                                               ; $004D78

; marcador de rascunho do fill: bit 5
        bset.b  #$5,$1(a0)                                              ; $005D6C
        bclr.b  #$5,$1(a0)                                              ; $005D74
```

O bit 0 merece nota. `dbg_plot_row` (`$0168A0`) e `dbg_plot_col` (`$0168BC`) ligam-no e
desligam-no para desenhar caixas no editor de objectos; `vram_ray_to_solid_toggle`
(`$017C98`) e `vram_ray_to_trail_toggle` (`$017D06`) fazem `bchg.b #$0,$1(a0)` em cada pixel
percorrido. Estas duas últimas **não têm chamador** — são as gémeas de depuração de
`vram_ray_to_solid` (`$017C6A`) e `vram_ray_to_trail` (`$017CCC`), que fazem o mesmo
varrimento sem marcar nada. Como o bit 0 é o LSB do nibble da imagem A, marcar com ele muda a
cor do pixel em uma pen.

### 3.2 O cálculo de cor

O que o MAME faz (`refresh_pixel_layer`):

```c
int color = (p[x] << 2) & 0x700;
if (p[x] & 0x8000) {
    color |= 0x800 | ((p[x] >> 9) & 0xf);   // solido: nibble da imagem B
    if (p[x] & 0x2000) color &= ~0xf;       // hack para o bit 13
} else
    color |= p[x] & 0xf;                    // por conquistar: nibble da imagem A
```

Reescrito em campos:

```
imagem = (word >> 15) & 1                 ; 0 = A, 1 = B
banco  = (word >>  6) & 7                 ; bits 8,7,6
nibble = imagem ? (word >> 9) & $F : word & $F
entrada = (imagem << 11) | (banco << 8) | nibble
```

Os índices alcançáveis são `$000–$70F` (imagem A) e `$800–$F0F` (imagem B), sempre com os
bits 4–7 do índice a zero: **16 cores em cada um de 8 bancos espaçados de 256 entradas**,
vezes duas imagens.

E daqui sai a peça central do design da camada bitmap: **os bits lógicos do jogo (parede,
trilha, célula de objecto) são, ao mesmo tempo, os bits de banco de paleta.** Marcar um pixel
como parede não é escrever um flag paralelo a uma cor — é mudar o banco de paleta desse
pixel. Como os bancos 1–7 estão cheios com **uma cor lisa cada**, a parede fica da cor das
paredes sem que exista uma linha de código de desenho a fazê-lo.

As cores lisas vêm de `pal_load_area_colors_alt` (`$000FF6`,
[`src/main68k/spr_pal_video_helpers.asm`](../src/main68k/spr_pal_video_helpers.asm)), que
escreve 7 cores, `$100` entradas cada, a partir de `PALETTE+$200` (entrada `$100`, imagem A
banco 1) **e** de `PALETTE+$1200` (entrada `$900`, imagem B banco 1). A tabela `off_00111E`,
lida de `build/maincpu.bin`, é:

| Banco | Bit da word | Valor `$0RGB` | `xBGR555` | Cor |
|---|---|---|---|---|
| 1 | 6 — parede/moldura | `$00F0` | `$03C0` | verde |
| 2 | 7 — trilha | `$0F00` | `$001E` | vermelho |
| 3 | 6+7 | `$0000` | `$0000` | preto |
| 4 | 8 — célula de objecto | `$0999` | `$4A52` | cinzento |
| 5, 6, 7 | combinações | `$0000` | `$0000` | preto |

A gémea `pal_load_area_colors` (`$000F5E`) usa `off_00112C`, que são **sete words a zero**: é
a versão que apaga o campo (atracção, game over, tilt).

Repare-se que os quatro estados que interessam ao jogo têm todos o bit 15 aceso, portanto
vivem na **imagem B**: as entradas realmente usadas em jogo são `$9xx` (parede), `$Axx`
(trilha) e `$Cxx` (célula de objecto). Três confirmações independentes, todas em §7.3:
`pal_trail_cycle` anima `$A00`/`$A08`, `pal_fade_step` apaga `$900`, `$A00` e `$C00`, e
`pal_hit_flash_step` anima `$900`.

### 3.3 Os bits 4 e 5 — uma hipótese com evidência

Isto é **conjectura**, mas é conjectura com números.

O MAME ignora os bits 4 e 5 da word. Se assim fosse, a camada bitmap usaria 256 das 4096
entradas de paleta que lhe estão reservadas (`$000–$FFF`) e o resto seria lixo. Mas o jogo
mantém sistematicamente **64 entradas por banco 0**, e não 16:

| Rotina | Endereço | O que escreve |
|---|---|---|
| `pal_init_all` | `$000F9A` | 32+32 entradas em `$500000` (`$000–$03F`); 32 de `off_00109E` + 32 de `off_0010DE` em `$501000` (`$800–$83F`) |
| `pal_blackout_bitmap` | `$00383E` | `$40` words em `$500000` e `$40` em `$501000` |
| `pal_fill_bitmap_solid` | `$002764` | `$40` words de `$508A` em cada |
| `pal_player_fade_step` | `$00571C` | `$20` words em `PALETTE+$1200` (`$900–$91F`) |
| `pal_fade_step` | `$0147F0` | 4×16 = 64 entradas em cada um de `$900`, `$A00`, `$C00` |
| `lvl_load_palette` | `$006A74` | a cor do nível em `$500000+slot·2` **e** em `$500040+slot·2`, mais `$501000+slot·2` |

E o conteúdo com que `pal_init_all` semeia as 64 entradas da imagem B é inequívoco (lido do
binário):

| Entradas | Tabela | Conteúdo |
|---|---|---|
| `$800–$80F` | `off_00109E` | 16 × `$0000` |
| `$810` / `$811–$81F` | `off_00109E` | `$0000` / 15 × `$0555` |
| `$820` / `$821–$82F` | `off_0010DE` | `$0000` / 15 × `$0777` |
| `$830` / `$831–$83F` | `off_0010DE` | `$0000` / 15 × `$0555` |

Três blocos de 16 com **pen 0 preta e pens 1–15 numa cor lisa** — a forma exacta de um
sub-banco com pen transparente.

A explicação mais económica é que, no hardware real, **os bits 4 e 5 da word são os bits 4 e
5 do índice de paleta**:

```
entrada = (imagem << 11) | (banco << 8) | (((word >> 4) & 3) << 4) | nibble
```

Isso resolve dois dos quatro «?» do formato documentado e tem três consequências que batem
com o código:

1. a camada bitmap passa a cobrir densamente as entradas `$000–$FFF` — exactamente as 4096
   que não são de sprite — em vez de usar 256 e deixar buracos;
2. explica porque `lvl_load_palette` duplica a cor do nível em `slot` e em `$20+slot`: o
   sub-banco 2 é o que o **bit 5** selecciona, e o bit 5 é o marcador de rascunho que o motor
   de preenchimento põe e tira em pixels ainda por conquistar (imagem A). Com a cópia, marcar
   um pixel com o bit 5 não lhe muda a cor — o rascunho é invisível, que é o que se quer;
3. explica porque o bit 5 precisa de ter cor definida na imagem B (`$820–$82F`).

**Não é um facto.** O MAME ignora esses bits, portanto em emulação estas 48 entradas por
banco são escritas e nunca lidas, e não há forma de testar a hipótese sem a placa. Fica
registada com a evidência para quem a tiver. Ver §10.

---

## 4. Imagens A e B, `VIDEO_MASK` e as transições

### 4.1 O que são as duas imagens

Cada word de VRAM carrega **dois pixels de 4 bits**: o nibble 3–0 (imagem A) e o nibble 12–9
(imagem B). O bit 15 escolhe qual é mostrado. A imagem A é o que se vê antes de conquistar; a
imagem B é o que a área conquistada revela.

As duas vêm de duas tabelas de ponteiros distintas, ambas indexadas por `índice·12`:

| Tabela | Endereço | Lida por | Blitter |
|---|---|---|---|
| A | `$009E8A` (`lvl_picture_ptr_table`) | `lvl_draw_bg_layers` (`$006FFC`) | nibble em bits 3–0 |
| B | `$009F6E` (`off_009F6E`) | `lvl_draw_bg2_layers` (`$007140`) | nibble em bits 12–9 |

As duas tabelas estão a 228 bytes uma da outra = 19 registos de 12 bytes = 19 quadros. Cada
registo são três `dc.l` para mapas de tiles `{cols.w, rows.w, códigos.w…}`. Medido nas 38
entradas (`$009E8A` e `$009F6E`, todas conferidas):

| Ponteiro | Dimensões | Destino em VRAM | No monitor |
|---|---|---|---|
| 0 | **32 × 28** tiles | `+$4040` = linha 16, coluna 32 → linhas 16–239, colunas 32–287 | 224 de largura × 256 de altura |
| 1 e 2 | **2 × 28** tiles | `+$4240` (coluna 288) e `+$4020` (coluna 16) | duas faixas de 224 × 16 |

Qual dos ponteiros 1/2 vai para cada lado depende de `$100030` (flip de cocktail), decidido em
`$00700E` e `$007152`. Os registos são contíguos na ROM: `$00C0EA + 4 + 32·28·2 = $00C7EE`,
que é o ptr0 do registo seguinte.

**A relação entre as duas tabelas.** Comparando registo a registo (os três ponteiros, não só
o primeiro):

```
B[i] == A[i+1]   para i = 0..10 e i = 12..15
B[11] = ($011F86, $011F12, $01268A)   — nao aparece em lado nenhum da tabela A
A[12] = ($00CEF2, $00D5F6, $00D66A)   — nao aparece em lado nenhum da tabela B
B[16] == A[16],  B[17] == A[17],  B[18] == A[18]
```

Em 14 dos 16 quadros jogáveis, **a imagem revelada no round N é a imagem de superfície do
round N+1**. A leitura natural é que a sequência é contínua: conquistar área no round N vai
destapando o quadro que será o fundo do round N+1, e a transição de fim de round só tem de
tornar a imagem B na nova imagem A. A **mecânica é medida**; a interpretação é conjectura.

Os índices 16–18 não são rounds jogáveis. O 17 e o 18 são pedidos explicitamente
(`move.w #$11,$8FE(a5)` em `$00061E` e `$0035C4`; `move.w #$12,$8FE(a5)` em `$00364C`) — são
os ecrãs entre rounds. O 16 é alcançado quando `$100198` (`g_round_index`) chega a `$10`,
altura em que `$003BD4` desvia e não recarrega as cores de área nem o HUD.

Cada round tem também um par de paletas próprio: `lvl_palette_ptr_table` (`$006ADC`) são **38
`dc.l`** = 19 pares `{ptr_A, ptr_B}`, indexados por `round·8` (`lsl.w #$3,d0` em `$006A7A`).
Cada bloco tem 16 cores `$0RGB`, carregadas **uma por frame** por `lvl_load_palette`
(`$006A74`, [`src/main68k/palette_level.asm`](../src/main68k/palette_level.asm)) com
`$100332` (`g_palette_slot`) a contar de 0 a 15 — é isto que produz a subida gradual de cor
ao entrar num round.

### 4.2 `VIDEO_MASK` (`$600000`)

Máscara de escrita **por bit**, e só de escrita: o MAME faz `mem_mask &= m_video_mask` antes
do `COMBINE_DATA`. As leituras não são afectadas, o que é essencial, porque o motor de
preenchimento lê a VRAM constantemente.

Toda a ROM escreve exactamente três valores, cinco vezes cada
(`grep -rn VIDEO_MASK src/main68k/*.asm`):

| Valor | Efeito | Endereços |
|---|---|---|
| `$000F` | só o nibble da imagem A | `$000608`, `$0006F0`, `$0035A2`, `$00362A`, `$003B48` |
| `$FFF0` | tudo menos a imagem A | `$000640`, `$00074C`, `$0035DA`, `$003666`, `$003BB2` |
| `$FFFF` | tudo | `$0014C0` (reset), `$000766`, `$003600`, `$00368C`, `$003BCC` |

A máscara existe porque os blitters escrevem sempre a **word inteira** e nunca fazem
read-modify-write. `vram_blit_tile8` põe o nibble em baixo e lixo em cima; `vram_blit_tile8_b`
põe o nibble em bits 12–9 e **zeros em tudo o resto**. É a máscara que decide o que sobrevive,
e é por isso que a mesma família de rotinas serve para as duas imagens.

Isto tem uma consequência que vale a pena tornar explícita: **carregar a imagem B com a
máscara `$FFF0` reinicia o campo**. Como o blitter escreve zeros nos bits 15, 14, 13, 8, 7, 6,
5 e 4, no fim da passagem todos os pixels ficam com bit 15 = 0 (mostra a imagem A) e banco 0
(sem parede, sem trilha, sem célula de objecto). Não é preciso um passo de limpeza separado.

### 4.3 O protocolo de transição, passo a passo

A sequência é uma máquina de estados de um passo por frame, e aparece três vezes na ROM com a
mesma forma. Em
[`src/main68k/game_roundclear_script.asm`](../src/main68k/game_roundclear_script.asm):

```
sub_00359E ($00359E)  bsr spr_clear_text_area
                      move.w #$F,VIDEO_MASK       ; daqui em diante so' a imagem A
sub_0035B2 ($0035B2)  bsr pal_blackout_bitmap     ; bancos 0 das duas imagens a preto
sub_0035BE ($0035BE)  move.b #$5,$804(a5)         ; pede o desenho da imagem A
                      move.w #$11,$8FE(a5)        ; quadro 17
sub_0035D2 ($0035D2)  tst.b $804(a5) / bne rts    ; espera o laco principal acabar
                      move.w #$FFF0,VIDEO_MASK    ; agora so' a imagem B
sub_0035EA ($0035EA)  move.b #$6,$804(a5)         ; pede o desenho da imagem B
sub_0035F8 ($0035F8)  tst.b $804(a5) / bne rts
                      move.w #$FFFF,VIDEO_MASK    ; liberta a mascara
sub_003610 ($003610)  clr.w $332(a5)              ; recomeca a carga da paleta
                      bsr vram_init_playfield     ; moldura + colunas de fora
```

O mesmo em `$003626…$0036A0` com o quadro 18, e em `$000608…$000766`
([`game_screen_sequence.asm`](../src/main68k/game_screen_sequence.asm)) no arranque de
partida.

A terceira instância é a que interessa mais, porque é a transição de round propriamente dita
e usa os comandos 3/4 (índice implícito) em vez de 5/6:

```
game_round_begin ($003B48)  move.w #$F,VIDEO_MASK
game_round_advance ($003B7A) move.b #$3,$804(a5)  ; imagem A do NOVO round
                             addq.b #$1,$198(a5)  ; g_round_index
sub_003BAA ($003BAA)         espera; move.w #$FFF0,VIDEO_MASK
sub_003BBC ($003BBC)         move.b #$4,$804(a5)  ; imagem B do novo round
sub_003BC4 ($003BC4)         espera; move.w #$FFFF,VIDEO_MASK
                             bsr pal_load_area_colors_alt
                             bsr game_seq_build_playfield_hud
```

A propriedade que torna isto um duplo buffer real: **enquanto se carrega a imagem A com
`$000F`, o ecrã continua a mostrar a imagem B** nos pixels que têm o bit 15 aceso, e
vice-versa. O jogador nunca vê meia imagem.

---

## 5. Os blitters da camada bitmap

### 5.1 Formato dos tiles e dos mapas

Os fundos são mapas de tiles de **8×8 a 4 bpp, 32 bytes cada**, em `TILE_ROM + código·32` =
`$080000 + código·32`. O cálculo aparece literalmente:

```
        clr.l   d0                                                      ; $0070D0
        move.w  (a3)+,d0                ; codigo de tile vindo do mapa  ; $0070D2
        lsl.l   #$5,d0                  ; x 32                          ; $0070D4
        addi.l  #TILE_ROM,d0                                            ; $0070D6
```

Medido em `build/maincpu.bin`: os dados vão de `$080000` até `$0F817F` (último byte diferente
de `$FF`), ou seja **15 372 tiles**, com um único buraco de 1216 bytes a `$FF` em
`$0BFB40–$0BFFFF` — enchimento no fim do primeiro par de ROMs de dados. (O
`HARDWARE_GROUND_TRUTH` arredonda esse buraco para `$0BFC00–$0BFFFF`; a medição byte a byte
dá `$0BFB40`.)

Os 114 ponteiros das duas tabelas apontam para **60 mapas distintos**, e entre todos usam
**14 540 tiles distintos**, do 32 ao 15 371 — praticamente toda a região, até ao
último tile. **O único tile abaixo de 96 que qualquer mapa refere é o 32**, cujos 32 bytes são
todos zero; na fonte de 8×8 da ROM (§9.2) o tile 32 é o carácter *espaço*. É o tile de
enchimento.

Reprodução:

```bash
.venv/bin/python - <<'EOF'
import struct
d=open('build/maincpu.bin','rb').read()
w=lambda a: struct.unpack_from('>H',d,a)[0]
l=lambda a: struct.unpack_from('>I',d,a)[0]
ptrs={l(b+12*i+4*k) for b in (0x9E8A,0x9F6E) for i in range(19) for k in range(3)}
todos={w(p+4+2*k) for p in ptrs for k in range(w(p)*w(p+2))}
print(len(ptrs), len(todos), min(todos), max(todos), sorted(t for t in todos if t<96))
EOF
```

**Os mapas são telas de ±32 tiles com duplicados removidos.** Ao longo de uma linha do mapa os
códigos crescem quase sempre de 1; de linha para linha o salto é 20–31, nunca 32 fixo. Ou
seja: o desenho original era uma tela contígua de 32 tiles (256 px) de largura e o
empacotador removeu os tiles repetidos. Isso é coerente com a evidência de costura vertical
que `tools/gfx_extract.py` mede na região crua (§9.1), que dá um máximo isolado em 32 colunas.

### 5.2 As quatro variantes

[`src/main68k/vram_tilemap_blit.asm`](../src/main68k/vram_tilemap_blit.asm) tem duas dimensões
de escolha — imagem A ou B, normal ou espelhado — logo quatro rotinas de tile e duas de mapa:

| Rotina | Endereço | Imagem | Sentido |
|---|---|---|---|
| `vram_blit_tile8` | `$0070F6` | A (bits 3–0) | normal |
| `vram_blit_tile8_mirror` | `$0070A6` | A | invertido |
| `vram_blit_tile8_b` | `$00733C` | B (bits 12–9) | normal |
| `vram_blit_tile8_b_mirror` | `$0072E4` | B | invertido |

`vram_blit_tilemap_mirror` (`$007060`) e `vram_blit_tilemap_b_mirror` (`$00729E`) escolhem a
variante logo à entrada com `tst.w $30(a5)`; o nome é enganador — a versão normal está no
ramo `loc_0070C4` (e `loc_00730A` para a imagem B).

O núcleo da variante normal da imagem A:

```
vram_blit_tile8:
        moveq   #$8,d3                  ; 8 linhas do tile              ; $0070F6
loc_0070F8:
        move.w  #$2,d2                                                  ; $0070F8
        moveq   #$8,d1                  ; 8 pixels                      ; $0070FC
        move.l  (a0)+,d0                ; 8 nibbles = uma linha do tile ; $0070FE
loc_007100:
        rol.l   #$4,d0                                                  ; $007100
        move.w  d0,(a1)                 ; word inteira; VIDEO_MASK filtra ; $007102
        adda.w  d2,a1                   ; +2 = coluna de VRAM seguinte  ; $007104
        subq.w  #$1,d1                                                  ; $007106
        bne.b   loc_007100                                              ; $007108
        adda.w  #$3F0,a1                ; $400 - 8*2 = linha seguinte   ; $00710A
```

A variante da imagem B é a mesma com o nibble deslocado antes de escrever:

```
vram_blit_tile8_b:
        ...
loc_007346:
        rol.l   #$4,d0                                                  ; $007346
        move.l  d0,d7                                                   ; $007348
        ror.w   #$7,d7                  ; nibble 3..0 -> bits 12..9     ; $00734A
        andi.w  #$1E00,d7                                               ; $00734C
        move.w  d7,(a1)                                                 ; $007350
```

`ror.w #7` leva o bit 0 ao bit 9 e o bit 3 ao bit 12; `$1E00` são exactamente os bits 12–9.

As variantes «mirror» lêem o tile **de trás para a frente** (`move.l -(a0),d0` a começar em
`tile+$20`, e `ror.l #4` *depois* de escrever, em vez de `rol.l #4` antes) enquanto escrevem
para a frente, e o mapa é percorrido também ao contrário (`move.w -(a3),d0`). O efeito líquido
não é um espelho num eixo: é uma **rotação de 180°** do mapa inteiro — que é o que «flip de
ecrã» significa num monitor rodado.

Passos do mapa: `+$10` por coluna de tiles (8 colunas de VRAM × 2 bytes) e `+$2000` por linha
de tiles (8 linhas × `$400`). O número de colunas fica guardado em `$100324` (`g_blit_cols`)
porque d4 é reutilizado dentro do laço.

### 5.3 O eixo em que os fundos estão guardados

O blitter mapeia **nibble da fonte → coluna de VRAM** e **linha do tile → linha de VRAM**;
o mapa mapeia **coluna do mapa → coluna de VRAM** e **linha do mapa → linha de VRAM**. Como a
coluna de VRAM é o eixo *vertical* do monitor (§2.1), a folha de tiles tal como está guardada
na ROM é a **transposta** da imagem que o jogador vê.

O argumento decisivo é geométrico e não depende de julgar uma imagem: o mapa é 32 × 28 tiles
= 256 colunas × 224 linhas de VRAM, que no monitor são **224 de largura por 256 de altura**.
Retrato, e cabe nos 240 × 320 visíveis. Se fosse ao contrário seriam 256 de largura num ecrã
de 240 — impossível.

Isto importa para `assets/tiles/`: os PNG estão na orientação da VRAM, a 90° do que o jogador
vê. Ver §9.3, e note-se que o docstring de `cmd_bitmap` em `tools/gfx_extract.py` afirma o
contrário («guardados já na orientação final do ecrã»); a afirmação da ferramenta é uma
leitura visual de folhas cruas e não sobrevive ao argumento geométrico acima.

### 5.4 O par de blitters transposto — e o que ele explica

Há um segundo par de blitters de célula 8×8 em
[`src/main68k/vram_bitmap_draw.asm`](../src/main68k/vram_bitmap_draw.asm) com a convenção de
eixos **oposta**:

```
vram_blit_cell8:
        bsr.w   vram_addr_raw                                           ; $0181A8
        adda.l  #VRAM,a0                                                ; $0181AC
        moveq   #$7,d1                                                  ; $0181B2
loc_0181B4:
        move.l  (a1)+,d3                                                ; $0181B4
        moveq   #$7,d0                                                  ; $0181B6
loc_0181B8:
        rol.l   #$4,d3                                                  ; $0181B8
        move.w  d3,d4                                                   ; $0181BA
        andi.w  #$F,d4                                                  ; $0181BC
        andi.w  #$FFF0,(a0)             ; read-modify-write, so' o nibble A ; $0181C0
        or.w    d4,(a0)                                                 ; $0181C4
        lea.l   $400(a0),a0             ; +1 LINHA de VRAM por pixel    ; $0181C6
        dbra    d0,loc_0181B8                                           ; $0181CA
        lea.l   -$2002(a0),a0           ; recua 8 linhas E uma coluna   ; $0181CE
```

Aqui um nibble da fonte avança uma **linha** de VRAM e uma linha da fonte recua uma **coluna**
— transposição em relação ao blitter de fundos, isto é, orientação do **monitor**. O gémeo
`vram_blit_cell8_stencil_maybe` (`$018174`) faz o mesmo com uma cor fixa nos pixels não-zero e
máscara `$FFE0` (cinco bits, não quatro).

O único chamador de `vram_blit_cell8` é `vram_draw_logo_dead_maybe` (`$0181F0`), que desenha
um mapa de 26×11 células a partir de `$020B00` (e `$020000` para a célula vazia) — endereços
que caem dentro do **código** da ROM final — e que não tem chamador nenhum. É resto de uma
build anterior, da mesma família dos vectores `$0011xxxx`
([`docs/02-mapa-de-memoria.md`](02-mapa-de-memoria.md) §2.2).

Isto explica um dado que de outra forma é contraditório: a **fonte de 8×8 na ROM de tiles**
(tiles 0–95, `$080000–$080BFF`) lê-se direita quando descodificada em linha, ou seja está na
orientação do *monitor* e não da VRAM. Foi desenhada para este par de blitters transposto, que
é código morto. E de facto nenhum mapa de round a usa (§5.1). Todo o texto do jogo final é
sprites.

### 5.5 O motor de desenho progressivo (`$018374–$0185A3`)

Cinco tarefas de `$1C` bytes em `$1029DE` que pintam uma imagem grande na VRAM ao longo de
vários frames. O despacho é por `$12(a1)` numa tabela de 6 ponteiros (`vram_img_mode_table`,
`$0183A8`): o modo 1 usa índices de célula em byte e máscara `$FFE0`, os modos 0 e 2–5 usam
índices em word e máscara `$FFF0`. `vram_blit_row_4bpp` (`$01851E`) e `vram_blit_row_scaled`
(`$01853E`) usam a convenção transposta do §5.4. O tamanho `$8C = 5 × $1C` está confirmado por
`$01849A`, que limpa exactamente `$8C` bytes. Se as cinco ranhuras estiverem ocupadas,
`vram_img_task_alloc` (`$018504`) cai num `bra.b *` em `$01851A` — um *assert* de
desenvolvimento que trava a máquina, deixado na ROM.

**Este motor não pode correr.** `vram_img_dst_addr` (`$018586`) calcula o destino assim:

```
vram_img_dst_addr:
        move.w  $0(a1),d0                                               ; $018586
        move.w  $2(a1),d1                                               ; $01858A
        add.w   $8(a1),d0                                               ; $01858E
        add.w   $A(a1),d1                                               ; $018592
        jsr     vram_addr_from_xy_016258                                ; $018596
        adda.l  #VRAM,a0                                                ; $01859C
```

`vram_addr_from_xy_016258` já devolve `a0 = $10006A + offset`, isto é já `$400000` ou
`$440000`. Somar `#VRAM` outra vez dá `$800000`+, que não está mapeado. Junte-se a isso que
nem `vram_img_tasks_update` (`$018374`) nem `vram_img_task_start` (`$0184D0`) têm chamador em
`build/m68k_map.json`, e que o primeiro começa com `bset.b #$0,(a6)` num ficheiro onde a6
guarda ponteiros de código — provável fronteira de rotina mal cortada. Descrevo o mecanismo;
não afirmo que ele corre.

---

## 6. Sprites — PC090OJ

### 6.1 O registo e o mapa da RAM

256 slots de 8 bytes em `$200000–$2007FF` (o MAME mapeia 16 KB mas só desenha
`PC090OJ_ACTIVE_RAM_SIZE = $800`). Formato conferido contra
[`reference/mame/pc090oj.cpp`](../reference/mame/pc090oj.cpp) e contra os emissores do jogo:

| Offset | Campo | Tratamento no MAME |
|---|---|---|
| `+0` | atributo: b15 flipY, b14 flipX, b3–b0 índice de cor | `color = (data & 0x000f) \| sprite_colbank` |
| `+2` | Y | `& $1FF`; `> $140` → `−$200` |
| `+4` | código do tile | `& $1FFF` |
| `+6` | X | `& $1FF`; `> $140` → `−$200` |

> O comentário do Raine no topo de `pc090oj.cpp` diz «byte 0 bit 6 = Flip Y, bit 7 = Flip X»,
> o que trocaria os dois bits. O **código** diz `flipy = data & 0x8000` e
> `flipx = data & 0x4000`, e os emissores do jogo (`bchg #$6` para X, `bchg #$7` para Y no
> byte alto) concordam com o código. Segui o código.

Esconder um sprite é escrever `$180` na word de Y — 384 é maior que `$140` e portanto é tratado
como −128, fora do ecrã. `spr_hide_range` (`$017BC2`,
[`src/main68k/mem_helpers.asm`](../src/main68k/mem_helpers.asm)) é a rotina canónica:

```
spr_hide_range:
        subq.w  #$1,d0                                                  ; $017BC2
loc_017BC4:
        move.w  #$180,$2(a0)                                            ; $017BC4
        lea.l   $8(a0),a0                                               ; $017BCA
        dbra    d0,loc_017BC4                                           ; $017BCE
```

O reset usa outra convenção: `spr_clear_all_and_seed_row` (`$000F1A`) enche `$1E0` longs a
partir de `$200000` com `$00000100` — attr 0, Y = 256, código 0, X = 256. O código 0 é o
carácter *espaço* da fonte de sprites, portanto o sprite existe mas não pinta nada.

Regiões identificadas (o maior offset absoluto usado pelo código de jogo é `SPRITE_RAM+$778`;
o resto do bloco de 16 KB nunca é tocado, tirando o registo de controlo):

| Faixa | Slots | Uso |
|---|---|---|
| `$200000–$2005FF` | 0–191 | pool circular do renderizador de texto do final (`$014DE0` põe o cursor `$10296C` em `$200000`; `$0156D2` e `$015728` dão a volta em `$200600`) |
| `$200000`, `$2000E0`, `$200100`, `$200140`, `$200480` | — | destinos dos seis emissores de metasprite; o jogador e os destroços partilham `$200000` porque são exclusivos (§6.2) |
| `$200180–$20047F` | 48–143 | destino do buffer-sombra de 96 sprites copiado de `$102350` por `spr_flush_shadow` |
| `$200600–$200777` | 192–238 | HUD: percentagem (`+$6A8`, `+$6B4`), moldura (`+$6B8`/`+$6BA`/`+$6BE`), vidas (`+$62C`), rótulos (`+$650`, `+$656`, `+$69E`, `+$6E8`, `+$72E`) |
| `$200778–$2007FF` | 239–255 | 14 + 3 slots semeados pelo reset com código 0 e X = `$160` (fora do ecrã) |
| `$201BFE` | — | registo de controlo do PC090OJ (offset de word `$DFF`), bit 0 = flip |

`spr_clear_text_area` (`$000E9A`) limpa `$194` longs = 202 slots; a versão curta (`$000EB0`)
limpa `$120` longs = 144 slots.

### 6.2 Dois emissores

**Metasprites de tabela** — `spr_draw_obj` (`$008E46`,
[`src/main68k/spr_metasprite_engine.asm`](../src/main68k/spr_metasprite_engine.asm)). d0 é um
id que indexa `spr_metasprite_table` (`$008E5E`), uma tabela de offsets de 2 bytes
auto-relativos. Medido no binário: a primeira entrada vale `$00EC`, logo o primeiro registo
está em `$008F4A` e a tabela tem **118 entradas** (ids 0–117). Cada registo é uma lista de
peças de 6 bytes terminada em `$FFFF`:

```
word attr | byte dy | word dcode | byte dx
```

`spr_emit_metasprite` (`$008D8C`) escreve as quatro words na ordem attr/Y/code/X, soma
`$2(a4)` ao código e a posição do objecto aos deslocamentos, e aplica o flip por software. Os
primeiros bytes reais, lidos do binário em `$008F4A`: `00 01 F9 00 02 F7 FF FF` = attr
`$0001`, dy −7, código +`$0002`, dx −9, fim.

O **bit 8 do atributo** (bit 0 do byte alto) manda negar o deslocamento quando o ecrã está
invertido — `spr_flip_offset_y` (`$008E1E`) e `spr_flip_offset_x` (`$008E2E`) fazem
`btst.b #$0,d4` sobre `attr >> 8`.

`$10033C` (`g_spr_pos_mode`) escolhe onde está a posição do objecto: 0 → `$16(a4)`/`$1A(a4)`;
1 → `$8(a4)`/`$4(a4)`. `spr_draw_obj_xy8` (`$008E3E`) é o mesmo ponto de entrada com a flag a 1.

Os seis emissores em [`src/main68k/sprite_dispatch.asm`](../src/main68k/sprite_dispatch.asm)
e em `game_frame.asm` fixam a partição da RAM de sprites (a última coluna é o `d2` passado a
`spr_emit_metasprite`, isto é o número de slots reservados por objecto):

| Emissor | Endereço | Tabela em RAM | Destino | Peças/objecto |
|---|---|---|---|---|
| jogador (de `vram_frame_draw_all`) | `$004BE2` | `$100800` (`g_player`) | `$200000` | 1 |
| `spr_draw_table_3400` (destroços) | `$0074F6` | `$103400` | `$200000` | 1 |
| `spr_draw_table_3700` | `$0074B2` | `$103700` | `$200100` | 1 |
| `spr_draw_table_3300` | `$007538` | `$103300` | `$200140` | 1 |
| `spr_draw_obj_3820_maybe` | `$007586` | `$103820` | `$2000E0` | 4 |
| `spr_draw_table_3000` | `$0075B4` | `$103000` | `$200480` | 2 |

**Objectos do motor de jogo** — `spr_build_object` (`$017F4C`,
[`src/main68k/spr_engine.asm`](../src/main68k/spr_engine.asm)), **20 chamadores**. Um «frame»
de sprite é uma indirecção de quatro níveis
([`src/main68k/spr_frame_tables.asm`](../src/main68k/spr_frame_tables.asm)):

```
$10110A (g_level_type, 0..15)
  -> spr_frame_desc_sets ($0185B8, 16 dc.l) -> bloco de descritores em $0329CA..$035068
     word[0] = indice maximo de frame; descritores de 8 bytes a partir de +$2
       [0].b -> spr_tile_list_offsets ($01860C, 184 words) -> lista (attr, codigo) em $030000+off
       [1].b -> spr_off_list_offsets  ($018790,  83 words) -> lista (contagem, dy, dx...) em $031B74+off
       [2].w ajuste de Y   [4].w ajuste de X   [6].w codigo de tile de base
```

`spr_frame_desc_ptr` (`$0185A4`) satura o índice de frame contra `word[0]` antes de indexar —
um frame fora de gama devolve o último, não lixo.

O emissor é escolhido por um modo 0–3 em `spr_emit_flip_table` (`$01803C`):

| Modo | Rotina | O que faz |
|---|---|---|
| 0 | `spr_emit_group_noflip` (`$01804C`) | escreve attr/cor/código/Y/X directamente |
| 1 | `spr_emit_group_flipx` (`$018086`) | `bchg.b #$6,$0(a0)` (= bit 14) e nega o eixo X com `−$10` |
| 2 | `spr_emit_group_flipy` (`$0180D0`) | `bchg.b #$7,$0(a0)` (= bit 15), idem no eixo Y |
| 3 | `spr_emit_group_flipxy` (`$01811A`) | os dois |

A compensação de `−$10` é a mesma dos 16 pixels do MAME. Em todos os modos a cor entra como
`move.b d3,$1(a0)` — o byte baixo do atributo é substituído por inteiro, portanto o byte alto
é o único que carrega os bits de flip. `spr_emit_group` (`$01802A`) troca d3 pelo conteúdo de
`$1020FA` (`g_spr_color_override`) se este for diferente de zero — é o mecanismo de «piscar»
dos chefes.

`spr_hide_leftovers` (`$01800C`) compara o número de sprites emitidos (`$1029D6`) com o do
frame anterior (`$2A(a4)`) e esconde a diferença — é assim que um objecto que encolhe não
deixa lixo no ecrã.

### 6.3 Flip de ecrã

Duas coisas acontecem ao mesmo tempo, controladas pela mesma variável `$100030`
(`g_screen_noflip`), decidida em `spr_set_screen_flip` (`$000EB6`) a partir de `$10003E`,
`$10003C` e do jogador activo (tabela completa em
[`docs/01-hardware.md`](01-hardware.md) §6.4):

```
loc_000ED8:
        move.w  #$1,$30(a5)             ; g_screen_noflip ($100030)     ; $000ED8
        move.w  #$1,SPRITE_RAM+$1BFE                                    ; $000EDE
        move.w  #$3FE,$6E(a5)           ; g_fill_bevel_step ($10006E)   ; $000EE6
        rts                                                             ; $000EEC
loc_000EEE:
        clr.w   $30(a5)                                                 ; $000EEE
        move.w  #$0,SPRITE_RAM+$1BFE                                    ; $000EF2
        move.w  #$FC02,$6E(a5)                                          ; $000EFA
```

e, em software, `spr_flip_y` (`$008DFA`) e `spr_flip_x` (`$008E0C`) aplicam `y = $FF − y − $F`
e `x = $13F − x − $F` quando `$100030 == 0` — a mesma fórmula que o MAME aplica quando
`!(m_ctrl & 1)`. As duas transformações compõem-se e as posições voltam ao sítio, mas os bits
de espelhamento do tile só são invertidos uma vez, pelo hardware. É a dúvida 2 de
[`docs/01-hardware.md`](01-hardware.md) §11 e continua por resolver.

A mesma variável comanda ainda: qual das duas tiras de HUD vai para cada lado (`$00700E`,
`$007152`), qual variante de blitter é usada (`$007060`), o espelhamento do endereçamento de
VRAM (`$01625C`), o sinal do passo de bisel do preenchimento (`$3FE` ↔ `$FC02`, que são
`±($400 − 2)`) e a troca das portas de entrada do C-Chip (`$004FD0`).

### 6.4 `sprite_ctrl` (`$700000`) — porque nunca é programado, e como o jogo compensa

O banco de cor dos sprites é

```c
sprite_colbank = 0x100 | ((sprite_ctrl & 0x3c) << 2);   // $100, $110, ... $1F0
color          = (attr & 0x000f) | sprite_colbank;      // $100..$1FF
```

ou seja **16 réplicas possíveis, espaçadas de `$10` cores = 256 entradas de paleta**. Os bits
2–5 do registo escolhem a réplica.

Há **sete** instruções em toda a ROM que escrevem em `$700001`, e nenhuma delas carrega d0
antes:

| Endereço | Rotina | d0 vem de |
|---|---|---|
| `$000408` | `irq4_vblank_handler` | o **contexto interrompido** — o `movem.l` guarda d0 mas não o inicializa |
| `$00153A` | `reset_entry` | o que `cchip_boot_handshake` deixou |
| `$00154E` | `reset_entry` | o que `snd_read_dipswitches` deixou |
| `$001558` | `reset_entry` | `vram_clear_page0` acabou de fazer `move.l #$0,d0` → **0** |
| `$001568` | `reset_entry` | `vram_clear_page1` → **0** |
| `$013FA8` | laço de espera do START1 no TEST MODE | o que `test_build_char_grid` deixou |
| `$01438E` | `test_frame_delay` (`$01438A`) | **65 536 escritas seguidas** como atraso |

A última merece atenção:

```
test_frame_delay:
        clr.w   $3AA(a5)                ; g_test_delay_counter ($1003AA) ; $01438A
loc_01438E:
        move.b  d0,SPRITE_CTRL_B                                        ; $01438E
        subi.w  #$1,$3AA(a5)                                            ; $014394
        bne.b   loc_01438E                                              ; $01439A
```

Um registo de configuração não se escreve 65 536 vezes num laço de atraso. Na prática
`$700001` funciona como um **strobe cujo valor é ignorado**.

**A compensação.** Onze rotinas carregam paleta de sprite, e **todas** escrevem o mesmo bloco
de cores 16 vezes, com passo `$200` bytes — exactamente as 256 entradas que separam duas
réplicas consecutivas:

| Rotina | Endereço | Base | Entradas por réplica | Cores cobertas |
|---|---|---|---|---|
| `pal_init_all` | `$000F9A` | `PALETTE+$2000` | `$D0` = 208 | `$100`–`$10C` |
| `pal_load_bank_2020` | `$00137A` | `PALETTE+$2020` | `$40` = 64 | `$101`–`$104` |
| `pal_load_bank_2180` | `$00139C` | `PALETTE+$2180` | 16 | `$10C` |
| `pal_load_bank_2140` | `$0013BE` | `PALETTE+$2140` | 16 | `$10A` |
| `pal_load_bank_2140_alt` | `$0013E0` | `PALETTE+$2140` | 16 | `$10A` |
| `pal_load_bank_2160` | `$001402` | `PALETTE+$2160` | 16 | `$10B` |
| `pal_load_bank_21C2` | `$00346C` | `PALETTE+$21C2` | 1 | `$10E`, pen 1 |
| `pal_load_bank_21E2` | `$00348C` | `PALETTE+$21E2` | 1 | `$10F`, pen 1 |
| `pal_load_title_colors` | `$002988` | `PALETTE+$2160` | 8 | `$10B`, pens 0–7 |
| `vblank_service` | `$0027DA` | `PALETTE+$2160` | 16 | `$10B` |
| `pal_load_round_from_cchip` | `$015C94` | `PALETTE+$2160` | 80 | `$10B`–`$10F` |

O idioma é sempre o mesmo:

```
pal_load_bank_2180:
        lea.l   PALETTE+$2180,a1                                        ; $00139C
        moveq   #$10,d7                 ; 16 replicas                   ; $0013A2
loc_0013A4:
        movea.l a1,a0
        move.w  #$10,d3                 ; 16 cores                      ; $0013A6
        lea.l   (off_0012BA).l,a3
        bsr.w   pal_expand_run
        adda.w  #$200,a1                ; +256 entradas = proxima replica ; $0013B4
        subq.w  #$1,d7
        bne.b   loc_0013A4
```

Em `pal_load_round_from_cchip` o passo aparece dividido: 80 words escritas (`$A0` bytes) mais
`lea $160(a1),a1` = `$200`.

**Quem reimplementar** pode tratar `$700000` como *no-op* e usar `sprite_colbank = $100`: o
resultado visual é idêntico, porque as 16 réplicas garantem que qualquer valor do registo dá
as mesmas cores. Depois do reset o registo fica de facto a 0 (`$001568` escreve o d0 = 0 de
`vram_clear_page1`); a partir do primeiro VBLANK passa a ser imprevisível.

---

## 7. Paleta

### 7.1 Mapa

8192 entradas de 16 bits em `$500000–$503FFF`, formato **xBGR_555** (bits 0–4 R, 5–9 G, 10–14
B, bit 15 ignorado). O mapa sai directamente das duas fórmulas de cor, sem sobreposição:

| Bytes | Entradas | Camada |
|---|---|---|
| `$500000–$500FFF` | `$000–$7FF` | bitmap, imagem A — 8 bancos de 256 |
| `$501000–$501FFF` | `$800–$FFF` | bitmap, imagem B — 8 bancos de 256 |
| `$502000–$503FFF` | `$1000–$1FFF` | sprites — cores `$100`–`$1FF`, 16 pens cada |

Conversão entre byte e cor de sprite: `byte = $502000 + (cor − $100)·32 + pen·2`.

Todos os offsets de `PALETTE+` que aparecem na listagem, traduzidos:

| Offset | Entrada | O que é |
|---|---|---|
| `PALETTE_RAM` | `$000` | imagem A, banco 0, pen 0 |
| `+$40` | `$020` | imagem A, banco 0, cópia da cor do nível (§3.3) |
| `+$200` | `$100` | imagem A, banco 1 (parede) |
| `+$1000` | `$800` | imagem B, banco 0 |
| `+$1200` | `$900` | imagem B, banco 1 (parede) |
| `+$1400` / `+$1410` | `$A00` / `$A08` | imagem B, banco 2 (trilha), duas metades |
| `+$1800` | `$C00` | imagem B, banco 4 (célula de objecto) |
| `+$2000` | `$1000` | sprite, cor `$100`, pen 0 — réplica 0 |
| `+$2020` / `+$2140` / `+$2160` / `+$2180` | `$1010` / `$10A0` / `$10B0` / `$10C0` | sprite, cores `$101` / `$10A` / `$10B` / `$10C`, réplica 0 |
| `+$21C2` / `+$21E2` | `$10E1` / `$10F1` | sprite, cores `$10E` / `$10F`, pen 1 |
| `+$20A2`/`+$20A4`/`+$20A6` | `$1051`/`$1052`/`$1053` | sprite, cor `$105`, pens 1–3 — réplica 0 |
| `+$3180` | `$18C0` | sprite, cor `$18C` = a mesma `$10C` na **réplica 8** |
| `+$30A2`/`+$30A4`/`+$30A6` | `$1851`/… | cor `$185` = `$105` na réplica 8 |
| `+$3380`/`+$3560`/`+$3580`/`+$35A0`/`+$35E0`/`+$3980`/`+$39A0` | — | réplicas 9, 10 e 12 (§7.4) |

### 7.2 Conversão de cor

O jogo guarda as cores em `$0RGB` — 4 bits por componente — e converte na hora.
`pal_rgb444_to_xbgr555` (`$001042`):

```
        move.w  d0,d2                                                   ; $001042
        andi.w  #$F00,d0                                                ; $001044
        lsr.w   #$7,d0                  ; R -> bits 1..4                ; $001048
        move.w  d2,d1                                                   ; $00104A
        andi.w  #$F0,d1                                                 ; $00104C
        lsl.w   #$2,d1                  ; G -> bits 6..9                ; $001050
        andi.w  #$F,d2                                                  ; $001052
        ror.w   #$5,d2                  ; B -> bits 11..14              ; $001056
        or.w    d1,d0                                                   ; $001058
        or.w    d2,d0                                                   ; $00105A
```

O bit menos significativo de cada componente fica sempre a zero. Não é desleixo: é a folga que
os fades usam, subtraindo um degrau com as máscaras `$001E` (R), `$03C0` (G) e `$7800` (B).
Confirmação independente: as tabelas que já estão em xBGR555 (como a do flash de dano, que
escreve `$7BDE` = `01111 01111 01111`) têm o LSB a zero em todos os componentes.

Três rotinas encadeadas fazem toda a carga:

```
pal_next_color   ($001040)  move.w (a3)+,d0  e cai em pal_rgb444_to_xbgr555
pal_expand_run   ($001034)  d3 cores convertidas de (a3)+ para (a0)+
util_fill_words  ($000F02)  d1 x  move.w d0,(a0)+     (para os bancos lisos)
```

### 7.3 O que corre por frame

**`pal_trail_cycle`** (`$005780`,
[`src/main68k/fx_palette_sound.asm`](../src/main68k/fx_palette_sound.asm)) anima a cor da
trilha. Um contador de 0 a `$17` em `$68(a4)` indexa uma tabela de 12 words **já em xBGR555**
(`$0057D4`), e o bit 0 do contador escolhe qual metade do banco recebe a cor:

```
pal_trail_cycle_table:   $000A $0012 $001A $00DE $01DE $02DE $03DE $02DE
                         $01DE $00DE $001A $0012
```

`$000A`/`$0012`/`$001A` são vermelhos cada vez mais claros; a partir de `$00DE` o vermelho está
no máximo e o verde sobe até `$03DE` (amarelo). Oito entradas de cada vez, em `PALETTE+$1400`
(`$A00`) ou `PALETTE+$1410` (`$A08`).

**`pal_hit_flash_step`** (`$006A04`) usa `$100869` como passo 1–`$10`. Nos passos 1–8 escreve
`move.l #$7BDE7BDE,(a0)` em `PALETTE+$1200 + (passo−1)·4` — varre as 16 entradas de `$900` a
branco, duas por frame. Nos passos 9–`$10` varre-as de volta com `$03D0` (verde, a cor da
parede) ou `$001E` (vermelho) se `$10086C` (`g_timeout_state`) for ≥ 3.

**`pal_player_fade_step`** (`$00571C`) escreve `$20` = 32 entradas iguais a partir de
`PALETTE+$1200`, avançando um passo só nos frames em que `g_frame_counter & $C == 0` (quatro
frames em cada dezasseis, `$00572A`), e percorrendo uma tabela de 12 words em `$005768`
(`$0340 $02C0 $0240 $01C0 $0140 $0000 $000A $000E $0012 $0016 $001A $001E`) — do verde a zero
e de volta pelo vermelho. Pára quando `$75(a4)` chega a `$C`.

**`pal_flush`** (`$014772`,
[`src/main68k/frame_flush.asm`](../src/main68k/frame_flush.asm)) é `pal_fade_step` +
`pal_copy_banks`.

`pal_fade_step` (`$0147F0`), quando `$102128` está armado, limpa 64 entradas a partir de
`PALETTE+$1200` (`$900`), `PALETTE+$1400` (`$A00`) e `PALETTE+$1800` (`$C00`) — parede, trilha
e célula de objecto — com quatro `util_clear_32b` cada.

`pal_copy_banks` (`$01477C`) copia blocos de **32 bytes = 16 entradas** de três sombras em RAM
para a paleta, e cada sombra tem **duas versões** a `$20` bytes de distância — a normal e a
derivada:

| Sombra | Derivada | Destino | Selector |
|---|---|---|---|
| `$102136` | `$102156` | `PALETTE_RAM` (`$000`) | `$1021F6` |
| `$102176` | `$102196` | `PALETTE+$1000` (`$800`) | `$1021F8` |
| `$1021B6` | `$1021D6` | `PALETTE+$2180` **e** `PALETTE+$3180` | `$1021FA` |

As sombras e as derivadas são preenchidas uma vez por round por `pal_snapshot_and_derive`
(`$015A40`, [`src/main68k/palette_effects.asm`](../src/main68k/palette_effects.asm)), que copia
o estado actual dos três bancos e produz a versão derivada com:

- `pal_tint_from_green` (`$015B4C`) para os dois bancos da bitmap: `R = (G>>5) + $0A`, saturado
  em `$1E` quando transborda, e os bits 11–14 do azul apagados (`andi.w #$87FF`, portanto o
  bit 10 sobrevive);
- `pal_to_mono_red` (`$015ADE`) ou `pal_to_mono_amber` (`$015B12`) para o banco de sprites,
  escolhido por `$10110A` (`g_level_type`): âmbar nos tipos 4, 5 e `$B`; **nenhum** no tipo
  `$10`; vermelho em todos os outros. Ambos fazem a média dos três componentes de 4 bits e
  recolocam-na só no campo R (mono vermelho) ou nos campos R e G (mono âmbar).

Trocar de versão é somar `$20` ao ponteiro de origem — é assim que o ecrã inteiro «pisca» para
monocromático quando o jogador leva dano, com três `move.l` por banco e nenhuma conversão.

> **Assimetria por explicar.** `pal_copy_banks` escreve o banco de sprites em `PALETTE+$2180`
> e `PALETTE+$3180`, que são as réplicas **0 e 8** de `sprite_colbank` — duas das dezasseis.
> `game_seq_build_playfield_hud` (`$0007D2`) faz o mesmo com a cor `$105`: escreve em
> `+$20A2`/`+$20A4`/`+$20A6` e em `+$30A2`/`+$30A4`/`+$30A6`, réplicas 0 e 8. Todas as outras
> rotinas de paleta de sprite replicam 16 vezes (§6.4). Se `sprite_ctrl` calhar noutro valor,
> estas animações não acompanham. Duas instâncias independentes do mesmo padrão — não
> encontrei explicação.

### 7.4 A paleta que vive dentro do C-Chip

`pal_load_round_from_cchip` (`$015C94`) escreve `g_level_type + 1` em `CCHIP_RAM+$7FD`
(`$F007FD`), espera em laço até o C-Chip alterar esse byte, e depois lê **80 words** de
`CCHIP_RAM+$21` para `PALETTE+$2160`, replicando 16 vezes com passo `$200`:

```
pal_load_round_from_cchip:
        move.w  $110A(a5),d0            ; g_level_type ($10110A)        ; $015C94
        addi.w  #$1,d0                                                  ; $015C98
        move.b  d0,CCHIP_RAM+$7FD                                       ; $015C9C
loc_015CA2:
        cmp.b   CCHIP_RAM+$7FD,d0                                       ; $015CA2
        beq.b   loc_015CA2                                              ; $015CA8
        lea.l   CCHIP_RAM+$21,a0                                        ; $015CAA
        lea.l   PALETTE+$2000,a1                                        ; $015CB0
        lea.l   $160(a1),a1                                             ; $015CB6
        move.w  #$F,d2                                                  ; $015CBA
```

Como só os bytes ímpares da janela do C-Chip estão mapeados, cada word ocupa 4 bytes de espaço
de endereços — `pal_read_cchip_words` (`$015CD4`) lê o byte alto em `$2(a0)`, o baixo em
`$0(a0)` e avança `lea $4(a0),a0`. **Sem C-Chip funcional o jogo fica preso nesse laço e não
tem cores de sprite.** Os detalhes do outro lado estão em
[`docs/04-c-chip.md`](04-c-chip.md).

`pal_mark_round_entry_maybe` (`$015C0A`) faz um handshake parecido (`g_level_type + $81`), lê
um índice de `CCHIP_RAM+$47`, duplica-o (`lsl.w #$1`) e faz OR de `$8000` em `$503380` e
`$5033A0`, de `$8000` em `$503980` e `$5039A0`, de `$400` em `$503580` e `$5035A0`, e de `$20`
em `$5035E0` e `$503560` — todas indexadas pelo índice. `$8000` é o bit ignorado do xBGR555;
`$400` e `$20` são os LSB de B e de G, que o jogo deixa sempre a zero. O efeito visual é nulo
ou quase.

O mesmo padrão aparece uma segunda vez, e desta vez no reset: `pal_patch_four_entries`
(`$001424`, chamada só por `reset_entry`) faz

```
pal_patch_four_entries:
        lea.l   PALETTE+$338C,a1                                        ; $001424
        ori.w   #$8000,(a1)                                             ; $00142A
        lea.l   PALETTE+$358C,a1                                        ; $00142E
        ori.w   #$400,(a1)                                              ; $001434
        lea.l   PALETTE+$398C,a1                                        ; $001438
        ori.w   #$8000,(a1)                                             ; $00143E
        lea.l   PALETTE+$35EC,a1                                        ; $001442
        ori.w   #$20,(a1)                                               ; $001448
```

`$338C` é a cor `$19C` pen 6 (réplica 9), `$358C` a cor `$1AC` pen 6 (réplica 10), `$398C` a
cor `$1CC` pen 6 (réplica 12) e `$35EC` a cor `$1AF` pen 6 (réplica 10). Duas rotinas
independentes, os mesmos três valores invisíveis, as mesmas réplicas 9/10/12. Parecem marcas,
não cores, e nada as lê. Continua por explicar; os sufixos `_maybe` ficam.

---

## 8. Temporização do varrimento

O driver do MAME limita-se a `set_refresh_hz(60)` e nunca usa o oscilador de 26.686 MHz. As
duas PROMs que o `volfied.cpp` declara como `"proms"` e marca **unused** não são PROMs de cor
— a paleta é RAM em `$500000` e uma PROM de 512×4 ou 512×8 não a poderia conter. São o
**gerador de sincronismo H/V da placa**. Reproduz-se com:

```bash
.venv/bin/python tools/gfx_extract.py -v palette
```

| PROM | Tipo | Bits | Período (bit 0 desce uma vez) | Bit 1 a 1 |
|---|---|---|---|---|
| `c04-5.75` | MB7124E | 8 | **423** clocks (reset em `$1A6`) | **320** clocks (`$010–$14F`) |
| `c04-4-1.3` | MB7116H | 4 | **261** linhas (reset em `$104`) | **240** linhas |

Assumindo o divisor `/4` no oscilador de vídeo (6.6715 MHz), `6.6715 MHz / (423 × 261) =
60.43 Hz`. Os 320 × 240 activos batem exactamente com a área que o MAME declara
(`set_size(320, 256)`, `set_visarea(0, 319, 8, 247)`). **O divisor `/4` é uma suposição da
ferramenta**, mas o facto de a conta cair em 320 × 240 e ~60 Hz é corroboração forte. Traços
gráficos em `assets/proms/`.

---

## 9. Os gráficos extraídos (`assets/`)

### 9.1 Formatos e proveniência

| Região | Layout | Origem do formato |
|---|---|---|
| `pc090oj`, 768 KB | 16×16, 4 bpp packed MSB, 128 bytes/tile, 6144 tiles | cadeia `volfied.cpp` → `pc090oj.cpp` (`gfx_16x16x4_packed_msb`) → `emu/video/generic.cpp` |
| `maincpu $080000–$0F817F` | 8×8, 4 bpp packed MSB, 32 bytes/tile, 15 372 tiles | **não existe no MAME** — medido por `tools/gfx_extract.py` |

Em ambos: 2 pixels por byte, **nibble alto = pixel da esquerda**.

Os últimos 128 KB da região `pc090oj` são um espelho exacto dos 128 KB anteriores
(`c04-10.15`/`c04-09.14` carregados duas vezes) — verificado:
`d[0x80000:0xA0000] == d[0xA0000:0xC0000]`. Só 5120 dos 6144 tiles são distintos.

O layout da camada bitmap não vem de fonte nenhuma — o MAME nunca a descodifica, porque é o
68000 que lê a ROM e copia para a VRAM. `tools/gfx_extract.py bitmap` recalcula e imprime a
evidência:

```
extensão: último byte != $FF em $0F817F; 32384 bytes a $FF até $0FFFFF
enchimento $0BFB40-$0BFFFF: 1216 bytes, valores distintos ['$FF'] (fim do 1.º par de ROMs)
cidade $0A8000       suavidade vertical: tiles 8x8 = 1.016 | linear 256 px = 2.658
maquinaria $0D8000   suavidade vertical: tiles 8x8 = 1.027 | linear 256 px = 2.017
cenário $0F0000      suavidade vertical: tiles 8x8 = 1.591 | linear 256 px = 3.579
costura vertical em cidade $0A8000: 16=0.161 24=0.169 28=0.158 30=0.153 32=0.429
                                    34=0.158 36=0.168 40=0.167 48=0.158 64=0.153
                                    -> máximo em 32 colunas (256 px)
```

O pico isolado em 32 colunas (0.429 contra ~0.16 de base) é o argumento para a largura da
folha; a razão de ~2.6× na suavidade vertical é o argumento para tiles em vez de bitmap
linear. Mas veja-se §5.1: a folha de 32 é a tela de origem, não a estrutura que o jogo usa —
o que o jogo usa é o mapa, e os mapas saltam 20–31 tiles por linha por causa da remoção de
duplicados.

### 9.2 O que está em `assets/`

Contagem medida agora (`find assets -name '*.png' | wc -l` = **335**; o `README.md` diz 336):

| Pasta | Ficheiros | Comando |
|---|---|---|
| `assets/sprites/` | 48 = 24 bancos de 256 tiles × (cor + cinzento) | `gfx_extract.py sprites` |
| `assets/tiles/` | 34 = 16 páginas de `$8000` bytes + 1 folha contínua, × 2 | `gfx_extract.py bitmap --strip` |
| `assets/font/` | 250 = 59 glifos `oj16` + 64 glifos `rom8` + 4 folhas, × 2 | `gfx_extract.py font` |
| `assets/proms/` | 2 traços das PROMs de sincronismo | `gfx_extract.py palette` |
| `assets/contactsheet.png` | 1 | `gfx_extract.py contactsheet` |

As cores são as **verdadeiras**, recuperadas da ROM. Durante algum tempo este projecto
usou rampas artificiais por se ter concluído que a paleta, sendo RAM em `$500000`, não
seria conhecível estaticamente. A premissa é verdadeira e a conclusão não se segue: os
valores que o jogo escreve nessa RAM estão gravados na ROM.

O jogo guarda cada cor como `$0RGB`, 4 bits por componente, e expande-a com
`pal_rgb444_to_xbgr555` (`$001042`): cada nibble aterra num campo de 5 bits do formato
`xBGR_555` **com o bit menos significativo sempre a zero**. Daí uma propriedade que vale a
pena reter — **o branco máximo deste jogo é `#F7F7F7`, não `#FFFFFF`**.

`tools/palette_extract.py` encontra os carregadores pelas chamadas a `pal_expand_run`
(`$001034`) e `pal_next_color` (`$001040`), por onde toda a cor passa obrigatoriamente, o
que torna a descoberta completa por construção. Encontrou 19 tabelas e reconstruiu as 16
paletas de sprite aplicando-as por ordem de carregamento.

Qual das 16 pinta um dado sprite depende dos 4 bits baixos do seu atributo, que só existem
em tempo de execução — estaticamente não se pode saber. Por isso
`gfx_extract.py sprites --todas-paletas` grava cada banco sob as 16, e
`assets/manifest.json` regista, por ficheiro e por pen, de que endereço da ROM veio a cor.

`assets/font_map.json` liga carácter → índice de tile → PNG para as duas fontes:

| Fonte | Região | Regra | Intervalo | Rotação no PNG |
|---|---|---|---|---|
| `oj16` | `pc090oj $000000` | `tile = ASCII − $20` | `$20`–`$5A` (59 glifos) | **sim**, 270° |
| `rom8` | `maincpu $080000` | `tile = ASCII` | `$20`–`$5F` (64 glifos) | não |

Três glifos não correspondem ao seu ASCII: `*` é o sinal de multiplicar, `/` é o de dividir e
`@` é o símbolo de copyright. O logótipo TAITO ocupa os tiles 59–64 da fonte `oj16` e está
escrito na ROM como a string `"[\]^_`"` em `$001E40` — o extractor verifica esses bytes e
falha se não baterem.

### 9.3 Orientação dos PNG — leia isto antes de usar os assets

Só os PNG da fonte `oj16` saem rodados. Concretamente:

| Pasta | Orientação do PNG | Porquê |
|---|---|---|
| `assets/font/oj16*` | monitor (rodado 270° pelo extractor) | `_exportar_fonte` chama `rodar_270` |
| `assets/sprites/bank*` | **crua** (tal como está na ROM, deitada) | `cmd_sprites` não roda |
| `assets/font/rom8*` | monitor (a fonte de 8×8 está guardada direita) | §5.4 |
| `assets/tiles/bg*` | **VRAM** (a 90° do monitor) | §5.3 |

Confirma-se olhando: `assets/font/oj16_sheet.png` mostra o alfabeto e «TAITO» direitos;
`assets/sprites/bank00.png` mostra o mesmo alfabeto deitado. Os tiles de sprite estão
guardados rodados porque o PC090OJ os desenha em coordenadas cruas e é o `ROT270` do monitor
que os endireita; os fundos estão guardados na orientação da VRAM porque é o blitter do 68000
que transpõe.

---

## 10. O que não sabemos

**1. Os bits 4 e 5 da word de VRAM (§3.3).** A hipótese de que são os bits 4 e 5 do índice de
paleta explica quatro coisas independentes: as 64 entradas por banco 0 mantidas por seis
rotinas, os três sub-bancos lisos com pen 0 transparente semeados em `$810`/`$820`/`$830`, a
duplicação da cor do nível em `$000+slot` e `$020+slot`, e o facto de o bit 5 (rascunho do
fill) precisar de cor definida. Também faria a bitmap cobrir densamente as 4096 entradas que
lhe estão reservadas. O MAME ignora-os, portanto não é testável em emulação.

**2. Os bits 13 e 14.** O driver diz «3-D corners»/«3-D walls» e que na PCB saem pretos
sólidos. Nesta ROM **nenhuma escrita os toca** — nem as constantes imediatas (`$8040`,
`$8000`), nem os blitters (que escrevem zeros aí), nem nenhum `bset`. O *hack* do MAME
(`if (p & 0x2000) color &= ~0xf`) é código morto para este set.

**3. `vram_ctrl_strobe` (`$00144E`).** Apaga e repõe os bits 3 e 6 de `VIDEO_CTRL` uma vez por
frame, através da sombra `$100028`. Como a *leitura* do mesmo endereço devolve bits de
colisão, a hipótese razoável é rearme dos latches — mas o MAME devolve `$60` fixo. O nome é
descritivo do que a rotina faz, não do que provoca. Igual à dúvida 5 de
[`docs/01-hardware.md`](01-hardware.md) §11.

**4. O duplo flip dos sprites (§6.3).** Por resolver — [`01-hardware.md`](01-hardware.md) §11,
ponto 2.

**5. A assimetria das réplicas 0 e 8 (§7.3).** `pal_copy_banks` e
`game_seq_build_playfield_hud` escrevem só duas das dezasseis réplicas de `sprite_colbank`,
enquanto onze outras rotinas escrevem as dezasseis. Duas instâncias, o mesmo par de réplicas,
nenhuma explicação.

**6. As marcas invisíveis na paleta (§7.4).** `pal_mark_round_entry_maybe` (`$015C0A`) e
`pal_patch_four_entries` (`$001424`) põem `$8000`, `$400` e `$20` em entradas das réplicas 9,
10 e 12. `$8000` é ignorado pelo formato; `$400` e `$20` são LSB que o jogo nunca usa. Nada as
lê. Sem explicação.

**7. O motor de desenho progressivo `$018374–$0185A3` (§5.5).** Sem chamador identificado, com
uma fronteira de rotina suspeita em `$018374`, e com um cálculo de destino que soma a base da
VRAM duas vezes. Descrito, não creditado.

**8. O offset de 1 pixel do MAME.** `refresh_pixel_layer` percorre `x` de 1 a `width+1` e
escreve em `x−1`, com o comentário «*Hmm, 1 pixel offset is needed to align properly with
sprites*». É um ajuste empírico do emulador. Quem reimplementar tem de decidir de que lado está
o erro — pode ser que a coluna 0 da VRAM simplesmente não seja varrida na placa, o que seria
coerente com os 423 clocks de linha contra 320 activos (§8).

**9. O tamanho real da VRAM.** O espaço mapeado são `$80000` bytes = duas páginas de `$40000`,
e o jogo limpa as duas por inteiro. O cabeçalho do driver diz «12 × MB-81461 (256k VRAM)», que
não fecha com nenhum dos dois números. Discutido em [`01-hardware.md`](01-hardware.md) §11,
ponto 6; não acrescento nada.

**10. Como se dividem TC0070RGB e PC050CM.** Nenhum tem registo no mapa de memória e nenhuma
linha de código os toca. Para reimplementar basta tratar a saída como «entrada de paleta →
RGB de 5 bits por componente».

**11. Se a sequência de 19 quadros é mesmo contínua (§4.1).** A relação `B[i] == A[i+1]` está
medida e é exacta em 14 dos 16 rounds jogáveis. A *interpretação* — que conquistar área vai
destapando o cenário do round seguinte — é conjectura, e as duas excepções (`B[11]` é um
quadro que nunca é superfície; `A[12]` é uma superfície que nunca é revelada) não estão
explicadas.

---

## Anexo — notas sobre a listagem gerada

**1. As duas lacunas do particionamento foram resolvidas.**
[`docs/01-hardware.md`](01-hardware.md) traz uma nota final a dizer que `src/main68k/` não
cobria `$004FAE–$0053E5` nem `$026F7C–$026FEE`, por causa de dois nomes de ficheiro
duplicados em `volfied.asm`. Na listagem actual isso já não acontece:
`src/main68k/player_control.asm` declara `$004FAE-$0053E5, $005488-$005625` e contém
`player_move_and_draw_trail` (`$0051B6`). Verificado com:

```bash
grep -o 'include "[^"]*"' src/main68k/volfied.asm | sort | uniq -c | awk '$1>1'   # vazio
```

e com um varrimento das 153 faixas declaradas nos cabeçalhos dos 152 ficheiros `.asm`
(`player_control.asm` declara duas), que não deixa buracos entre `$000400` e `$029BFF`. Por
isso os excertos de `$0051B6` neste documento vêm da listagem, não de uma desmontagem à parte.

**2. `vram_xy_from_offset` (`$004F66`) mostra `andi.l #region_code,d0`.** O desmontador
substituiu a constante `$0003FFFE` por um símbolo cujo valor coincide, mas que aqui não tem
nada a ver com a região — é a máscara de uma página de VRAM. Bug cosmético que continua.

**3. `vram_blit_tilemap_mirror` (`$007060`) e `vram_blit_tilemap_b_mirror` (`$00729C`)** são os
pontos de entrada dos **dois** casos, normal e espelhado — o nome sugere só um. O ramo normal
está em `loc_0070C4` e `loc_00730A`.
