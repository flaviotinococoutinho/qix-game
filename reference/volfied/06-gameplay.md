# 06 — Como o jogo funciona por dentro

A lógica de jogo do Volfied tal como está no código do 68000: a máquina de estados de três
níveis, o laço principal, a estrutura do frame, o movimento do jogador, o algoritmo de
preenchimento de área, a percentagem, a pontuação, as vidas, o escudo, os itens, as 16
rondas e os chefes.

O que **não** está aqui, e onde está:

| Assunto | Documento |
|---|---|
| Placa, IRQ, VRAM, paleta, PC090OJ, PC060HA | [`docs/01-hardware.md`](01-hardware.md) |
| Mapa de endereços, RAM por grupos, armadilhas da listagem | [`docs/02-mapa-de-memoria.md`](02-mapa-de-memoria.md) |
| Camada bitmap, sprites, texto, efeitos de paleta | [`docs/03-video.md`](03-video.md) |
| C-Chip: protocolo, bancos, protecção, tabela de ritmos | [`docs/04-c-chip.md`](04-c-chip.md) |
| Z80, YM2203, fila de comandos de som | [`docs/05-som.md`](05-som.md) |
| Endereços e formatos autoritativos | [`reference/HARDWARE_GROUND_TRUTH.md`](../reference/HARDWARE_GROUND_TRUTH.md) |
| Matéria-prima da anotação (13 agentes) | [`docs/ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md) |

## 0. Convenções

- **`A5 = $100000`** durante todo o jogo. `$xx(a5)` é RAM em `$1000xx`.
- **`A4 = $100800`** em quase todo o código do jogador e do preenchimento. `$xx(a4)` é
  `$1008xx`. Onde isso for verdade, escrevo os dois endereços.
- Os excertos de código são copiados de `src/main68k/*.asm` com a coluna de bytes crus
  cortada. Os endereços no comentário final são os reais.
- **Eixos.** `vram_addr_from_xy` (`$004F7E`) faz `endereço = g_vram_page_ptr + d0*2 + d1*1024`.
  Chamo **x** ao argumento `d0` (o eixo de 512 words por linha, útil de 0 a 319) e **y** ao
  argumento `d1` (o eixo de 256 linhas). Como o ecrã é **ROT270**, o x da VRAM é a vertical
  do monitor. Ver §1.2 de [`02-mapa-de-memoria.md`](02-mapa-de-memoria.md).
- Onde escrevo **conjectura**, é conjectura. O resto foi lido na listagem ou medido sobre
  `build/maincpu.bin`.

---

## 1. Panorama: dois sítios onde corre código

O reset (`reset_entry`, `$0014B8`) termina num laço de duas instruções:

```
loc_00161C:
        bsr.w   vram_deferred_cmd_dispatch                              ; $00161C
        bra.b   loc_00161C                                              ; $001620
```

Não há mais nada no laço principal. Tudo o resto — entradas, lógica, sprites, som — corre
dentro do **IRQ de nível 4 do VBLANK** (`irq4_vblank_handler`, `$000400`).

O laço principal existe por uma razão: executar os trabalhos de VRAM que são **demasiado
longos para caber num frame**. `vram_deferred_cmd_dispatch` (`$005CD6`) despacha um byte de
pedido, `g_vram_cmd` (`$100804`, que é também `$4(a4)` do bloco do jogador):

| `$100804` | Trabalho | Rotina |
|---|---|---|
| 0 | nada | — |
| 1 | preenchimento **armado**, ainda não corre | promovido a 2 em `$0050AA` |
| 2 | **preenchimento de área** | `vram_area_fill`, `$005D2C` |
| 3 | desenha o fundo do nível | `lvl_draw_bg_by_level`, `$006FF4` |
| 4 | desenha o segundo fundo | `lvl_draw_bg2_by_level`, `$007138` |
| 5 | desenha as camadas do fundo | `lvl_draw_bg_layers`, `$006FFC` |
| 6 | idem, variante 2 | `lvl_draw_bg2_layers`, `$007140` |
| 7 | limpa a página 0 da VRAM | `vram_clear_page0`, `$00148C` |

O protocolo é sempre o mesmo: quem quer o trabalho escreve o código em `$100804` e depois
faz `tst.b $804(a5)` até voltar a zero. Só os casos 3–7 são pedidos pelo guião; o caso 2 é
pedido pelo próprio jogador quando fecha a trilha (§5.3).

Enquanto `$100804 == 2` o handler de VBLANK **salta o despacho de estado**: o jogo congela,
mas paleta, sprites e som continuam a ser servidos.

```
        cmpi.b  #$2,$804(a5)            ; g_vram_cmd ($100804)          ; $00044A
        bne.b   loc_000454
        bra.b   loc_000476                                              ; $000452
```

Ou seja: o preenchimento de área corre no laço principal, é interrompido dezenas de vezes
pelo VBLANK, e a lógica de jogo fica parada até ele acabar.

---

## 2. A máquina de estados de três níveis

Três words em RAM, cada uma indexando uma tabela de saltos relativos (`dc.w alvo-tabela`):

| Variável | Nome | Papel |
|---|---|---|
| `$100020` | `g_game_state` | estado de topo (4 valores) |
| `$100022` | `g_seq_mode` | sub-modo, com uma tabela por estado de topo |
| `$100024` | `g_seq_step` | passo dentro do sub-modo |
| `$100038` | `g_seq_delay` | atraso em frames; enquanto for > 0 os despachantes só o decrementam |

O idioma de pausa está no início de `attract_dispatch` (`$000B40`), `game_coinwait_dispatch`
(`$000938`) e `game_state2_dispatch` (`$00053C`):

```
game_state2_dispatch:
        tst.w   $38(a5)                 ; g_seq_delay ($100038)         ; $00053C
        beq.b   loc_000548
        subq.w  #$1,$38(a5)             ; g_seq_delay ($100038)
        rts
```

O despacho é sempre `lea tab(pc),a0 / adda.w d0,a0 / move.w (a0),d0 / lea tab(pc),a0 /
adda.w d0,a0 / jmp (a0)`. Repare-se que `adda.w` **estende o sinal**: uma entrada `$FE3E`
aponta para trás.

### 2.1 Nível 1 — `game_state_jumptable` (`$00046E`, 4 entradas)

| `$100020` | Alvo | Rotina |
|---|---|---|
| 0 | `$000B40` | `attract_dispatch` — atracção |
| 1 | `$000938` | `game_coinwait_dispatch` — moeda inserida / esperar START |
| 2 | `$00053C` | `game_state2_dispatch` — jogo |
| 3 | `$000E2E` | `game_soft_reset` — depois do TILT |

O estado 3 é um reinício por software: espera `g_seq_delay` e recarrega SSP e PC da tabela
de vectores.

```
game_soft_reset:
        tst.w   $38(a5)                                                 ; $000E2E
        beq.b   loc_000E3A
        subq.w  #$1,$38(a5)
        rts
loc_000E3A:
        movea.l (vector_00_initial_ssp).w,a7                            ; $000E3A
        movea.l (vector_01_reset_pc).w,a0                               ; $000E3E
        jmp     (a0)                                                    ; $000E42
```

Quem lá põe é `inp_tilt_check` (`$000E44`), chamado todos os frames pelo VBLANK: lê o bit 0
de `CCHIP_PC` (`$F0000B`), e se o TILT estiver activo apaga o ecrã, cala o som, liga o
lockout das moedas, mostra a mensagem `$15` (`"TILT"`), põe `g_seq_delay = $100` (256
frames) e `g_game_state = 3`.

### 2.2 Nível 2 — uma tabela por estado

**Estado 0 (atracção)** — `attract_jumptable`, `$000B62`, 3 entradas: `$000B68`,
`attract_show_ranking` (`$000C6E`), `$000DAE`.

**Estado 1 (espera de moeda / START)** — `game_coinwait_jumptable`, `$00095A`, 5 entradas:

| `$100022` | Alvo | |
|---|---|---|
| 0 | `$000964` | cai em `game_coinwait_show_prompt` |
| 1 | `$000A10` | `game_start_from_credits` |
| 2 | `$000968` | `game_coinwait_show_prompt` |
| 3 | `$000AD6` | `game_coinwait_music` |
| 4 | `$000AEC` | `sub_000AEC` |

**Estado 2 (jogo)** — `game_state2_jumptable`, `$00055E`, 6 entradas. O desmontador lê os
primeiros bytes como instruções (`ori.b #$0,(a0)+` …) porque valem `00 18 00 00`; os valores
crus são `$0018 $0000 $0314 $03B4 $000C $0012`:

| `$100022` | Alvo | Papel |
|---|---|---|
| 0 | `$000576` | `game_seq0_dispatch` — sequência de entrada em ronda |
| 1 | `$00055E` | **aponta para a própria tabela** — ver §13 |
| 2 | `$000872` | despachante dos passos de entrada em jogo (tabela `$000888`) |
| 3 | `$000912` | `game_play_tick_maybe` — **jogo a decorrer** |
| 4 | `$00056A` → `jmp $003C40` | `game_over_dispatch` |
| 5 | `$000570` → `jmp $0034B0` | `game_roundclear_dispatch` |

### 2.3 Nível 3 — as tabelas de passos

| Modo | Tabela | Entradas | Ficheiro |
|---|---|---|---|
| 2/0 | `game_seq0_jumptable`, `$00058C` | 16 | `src/main68k/game_screen_sequence.asm` |
| 2/2 | `game_play_step_jumptable`, `$000888` | 5 | `src/main68k/game_play_script.asm` |
| 2/3 | — | — | usa `g_seq_step` como contador, não como índice |
| 2/4 | `off_003C56` | 12 | `src/main68k/game_over_and_player_switch.asm` |
| 2/5 | `game_roundclear_jumptable`, `$0034C6` | **35** (`$0034C6-$00350B`) | `game_roundclear_dispatch_and_pal.asm` (entradas 0–29) + `game_roundclear_script.asm` (30–34) |

> A tabela de fim de ronda tem 70 bytes e é a única do jogo que atravessa a fronteira entre
> dois ficheiros gerados por `--split`. As entradas 30–34 vivem em
> `game_roundclear_script.asm`, que começa em `$003502`.

**Modo 2 (`$000888`)** é a entrada em jogo, e é onde vive o resto do editor de inimigos de
desenvolvimento:

| Passo | Alvo | O que faz | Passo seguinte |
|---|---|---|---|
| 0 | `game_enter_round`, `$000892` | paletes de área e do HUD, `g_scene_id = 2`/`3`, `lvl_place_static_objects` + `spr_draw_table_3000` | 4 |
| 1 | `$000900` | `enemy_dev_placer_init` (`$007798`) — **editor de dev** | 2 |
| 2 | `$00090C` | `jmp loc_0078D8` — laço do editor de dev | — |
| 3 | `player_spawn`, `$0008E0` | `$5(a4) = $FF`, `g_task_flags = 1` | **modo 3** |
| 4 | `$0008CA` | `player_entry_animation` (`$00413A`) até `g_player_dir == 4` | 3 |

O caminho normal é 0 → 4 → 3 → modo 3. Com `g_demo_flag` (`$100185`) aceso, o passo 0 salta
por cima de tudo e **cai directamente em `player_spawn`** (`bne.b player_spawn` em
`$0008B8`): não coloca objectos fixos nem corre a animação de entrada. Os passos 1 e 2 não
são alcançados por nenhuma escrita de `g_seq_step` que eu tenha encontrado; ver §13.

O modo 3 é o núcleo:

```
game_play_tick_maybe:
        tst.w   $40(a5)                 ; g_game_active ($100040)       ; $000912
        beq.b   loc_00092C
        cmpi.w  #$4,$24(a5)             ; g_seq_step ($100024)
        bcc.b   loc_00092C
        jsr     task_scheduler_run                                      ; $000920
        addq.w  #$1,$24(a5)
        rts
loc_00092C:
        addq.w  #$1,$302(a5)            ; g_frame_counter ($100302)     ; $00092C
        jsr     (game_ingame_tick).l                                    ; $000930
        rts
```

Nos primeiros quatro frames de jogo só corre o escalonador de tarefas — dá tempo aos guiões
do chefe de arrancar antes de o mundo começar a mexer. Em modo de atracção
(`g_game_active == 0`) o tick completo corre desde o primeiro frame.

### 2.4 O percurso de uma partida

```
reset  ──▶ $100020 = 2, $100022 = 2, $100024 = 0
           (mas a RAM foi limpa antes, logo $100020 volta a 0 na prática: atracção)

atracção (0) ──moeda──▶ espera (1) ──START──▶ game_start_from_credits ($000A10)
                                              g_game_active = 1, g_two_player = 0/1
                                              $100020 = 2, $100022 = 0, $100024 = 0

modo 0  = sequência de entrada em ronda (16 passos, encadeamento abaixo)
modo 2  = 0 → 4 → 3  ─▶  modo 3
modo 3  = jogo. game_ingame_tick uma vez por frame.
   ├─ 80 % / chefe morto / chefe envolvido ─▶ game_abort_to_attract: modo 5, passo $E
   └─ jogador morto ────────────────────────▶ modo 4, passo 0
modo 5  = ecrã de fim de ronda, bónus, carregar a ronda seguinte ─▶ modo 2, passo 0
modo 4  = perder vida / trocar de jogador / GAME OVER ─▶ estado 0
```

A sequência de entrada em ronda (`game_seq0_jumptable`) **não é linear**: cada passo escreve
o seu sucessor em `g_seq_step`. Encadeamento lido a partir de `game_seq_reset_playfield`
(`$0006EC`):

- com `g_game_active != 0`: `0 → 9 → 10 → 11 → 12 → 13 → 14 → 15 → 1 → 2 → 3 → 4 → 5 → modo 2`
- com `g_game_active == 0` (atracção): `0 → 1 → 2 → 3 → 4 → 5 → modo 2`
- reentrada curta depois de perder uma vida: `7 → 8 → 6 → modo 2` (passo 7 mostra a
  mensagem `$10`/`$11` — `"PLAYER 1"`/`"PLAYER 2"` — e espera `$30` frames)

Os pares 9/10, 11/12 e 1/2, 3/4 são sempre "pedir trabalho de VRAM / esperar que `$100804`
volte a 0", com `VIDEO_MASK` a percorrer `$000F` (só a imagem A) → `$FFF0` (tudo menos a
imagem A) → `$FFFF` (tudo). É o duplo buffer por pixel descrito em
[`01-hardware.md`](01-hardware.md).

---

## 3. A estrutura do frame

### 3.1 O handler de VBLANK (`$000400`)

Corpo completo, 30 instruções, por ordem:

1. `ori.w #$f00,sr` — mascara interrupções; `movem.l d0-d7/a0-a4/a6,-(a7)`.
2. `move.b d0,SPRITE_CTRL_B` — escrita com o `d0` que calhou estar no registo (o do código
   interrompido); o registo funciona como strobe. Ver [`01-hardware.md`](01-hardware.md).
3. `jsr vblank_service` (`$0027DA`) — serviço de paleta.
4. `move.w VIDEO_CTRL,$5A(a5)` — lê o status de colisão para `g_collision_status`
   (`$10005A`).
5. Se `g_seq_mode == 3`, **ou** `g_seq_mode == 5 && g_seq_step == $E`:
   `vram_frame_draw_all` (`$004B9C`) + `snd_drain_queue` (`$000520`).
   Caso contrário: só `vram_ctrl_strobe` (`$00144E`).
6. `inp_tilt_check` (`$000E44`), `coin_credit_tick` (`$0066CC`).
7. Se `g_vram_cmd != 2`: despacha `game_state_jumptable` com `pea loc_000476(pc)` + `jmp (a0)`
   — o "retorno" da rotina de estado cai em `loc_000476`.
8. `sys_data_out_tick` (`$006522`), restaura registos, `rte`.

O passo (5) explica uma assimetria importante: **o desenho completo do frame só acontece em
jogo e no passo `$E` do fim de ronda** (que é `game_round_run_frame`, `$003304`). Nos ecrãs
de menu, de bónus e de recordes os sprites são escritos directamente pelos passos do guião,
e a fila de som **não é drenada** — por isso esses ecrãs usam `snd_send_command` (`$000490`)
directamente em vez de `snd_queue_command` (`$0004F4`).

### 3.2 `vram_frame_draw_all` (`$004B9C`)

```
vram_frame_draw_all:
        bsr.w   pal_trail_cycle                                         ; $004B9C  → $005780
        bsr.w   pal_hit_flash_step                                      ; $004BA0  → $006A04
        bsr.w   pal_player_fade_step                                    ; $004BA4  → $00571C
        jsr     pal_flush                                               ; $004BA8  → $014772
        bsr.w   vram_ctrl_strobe                                        ; $004BAE  → $00144E
        cmpi.b  #$1,$86C(a5)            ; g_timeout_state ($10086C)
        beq.b   loc_004BC0
        jsr     spr_flush_shadow                                        ; $004BBA  → $014752
loc_004BC0:
        cmpi.w  #$5,$22(a5)             ; g_seq_mode ($100022)
        beq.w   loc_004C06              ; no fim de ronda pára aqui
```

Em jogo (`g_seq_mode == 3`) continua e desenha, por esta ordem:

1. o objecto do jogador (`spr_draw_obj`, `$008E46`), com `spr_blink_player_slot_maybe`
   (`$004C30`) a fazer piscar a ranhura — **ou**, se `$5(a4) >= 5` (estados `$FD`/`$FE`), a
   tabela de 16 fragmentos em `$103400` (`spr_draw_table_3400`, `$0074F6`);
2. a tabela de 22 objectos fixos em `$103000` (`spr_draw_table_3000`, `$0075B4`);
3. se `g_stage_clear_hud` (`$103844`) for 0: os tiros e faíscas (`$103820`, `$103300`,
   `$103700`).

Quando `$103844 != 0` (ronda ganha por envolvimento do chefe) desenha em vez disso a
mensagem `$78` — **`"FANTASTIC ROUND CLEAR!"`**, decodificada da tabela de mensagens — mas só
nos frames em que o bit 3 de `$103847` está aceso; `$103846` é o contador
`g_stage_clear_timer`, portanto a mensagem pisca com período de 16 frames durante os
`$6E` = 110 frames da espera.

### 3.3 `game_ingame_tick` (`$004E06`) — o frame de jogo

`src/main68k/game_frame.asm`. As três primeiras chamadas correm **sempre**; a partir daí
`$10086F != 0` desvia para `loc_004E54`:

| # | Rotina | Endereço | O que faz |
|---|---|---|---|
| 1 | `player_timer_expire_maybe` | `$004DD4` | conta `$10085E`/`$10085C`; ao chegar a 1 liga `g_player_hit_enable`/`g_trail_hit_enable` |
| 2 | `player_delay_countdown_maybe` | `$004DB6` | conta `$10084D` de 1 a 4 e liga `g_trail_hit_enable` |
| 3 | `inp_read_cchip` | `$004FAE` | lê os controlos (ou reproduz o guião de demo) |
| — | *(salto se `$10086F != 0`)* | `$004E0E` | |
| 4–7 | `player_update` × 1…4 | `$005122` | movimento e desenho da trilha (§4) |
| 8 | `player_stall_counter` | `$00994E` | conta frames em que o jogador não saiu do sítio |
| 9 | `game_round_time_limit` | `$0081FE` | limite de tempo da ronda (§10) |
| 10 | `enemy_spawn_countdown` | `$008246` | acelera a cadência dos tiros (§10) |
| 11 | `enemy_boss_engulfed_check` | `$00558E` | chefe cercado ⇒ ronda ganha (§12.4) |
| — | `loc_004E54` | | |
| 12 | `enemy_update_all` | `$007BFA` | 22 objectos de `$103000` |
| 13 | `enemy_and_spark_update_all` | `$009B8E` | tiros inimigos e faíscas |
| 14 | `hud_area_pct_step` | `$004EB0` | sobe o contador de percentagem e paga os pontos |
| 15 | `game_check_area_target` | `$0032A8` | testa os 80 % |
| 16 | `enemy_explosion_anim_maybe` | `$007BA6` | animação de explosão |
| 17 | `enemy_spawn_walk` | `$008352` | faz nascer inimigos fora do campo |
| 18 | `task_scheduler_run` | `$0145EE` | as 4 co-rotinas (chefe, grupo, comum) |
| 19 | `player_death_sequence` | `$004C7E` | estados `$FE`/`$FD` do jogador |
| 20 | `game_countdown_tick` | `$007F66` | o **escudo** (§9) |
| 21 | `snd_trail_loop_update` | `$00566E` | liga/desliga o som contínuo de desenho |
| 22 | `game_stage_clear_delay` | `$004E86` | espera 110 frames depois do envolvimento |

`$10086F` é levantado pelo fim do escudo (`$00805E`) e pelo envolvimento do chefe
(`$005612`), e limpo em `$00809E`. Além do bloco 4–11, também desliga
`enemy_shots_update_all` (`$0094AE`) e `player_animate_sprite` (`$0057EC`).

O escalonador (18) é a peça que corre os guiões dos chefes: 4 ranhuras de `$40` bytes em
`$101000`, cada passo devolvendo o controlo com `move.w #frames,d7 / lea proximo(pc),a6 /
rts`. Código em `src/main68k/task_scheduler.asm`; descrição em
[`ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md) (banda 02 §1 e banda 05 §1).

---

## 4. O jogador

O objecto do jogador vive em `$100800` e é sempre acedido com `a4 = $100800`. Campos usados
neste documento:

| Offset | Endereço | Papel |
|---|---|---|
| `$04` | `$100804` | `g_vram_cmd` — pedido de trabalho de VRAM (§1) |
| `$05` | `$100805` | estado/direcção: 0 parado, 1..4 direcção, `$FD` a explodir, `$FE` a morrer, `$FF` a nascer |
| `$06` | `$100806` | direcção anterior (para detectar mudanças) |
| `$07` | `$100807` | trinco de compromisso — enquanto for ≠ 0 o joystick é ignorado |
| `$08`/`$09` | `$100808` | divisor de frames e o seu contador |
| `$0D` | `$10080D` | índice no anel de 56 direcções |
| `$0E` | `$10080E` | segmentos que faltam no compromisso actual (2 → 1 → 0) |
| `$0F` | `$10080F` | incremento de direcção entre segmentos |
| `$10`/`$11`/`$12` | `$100810` | as duas recargas do contador de pixels e o contador |
| `$13` | `$100813` | trava de eixo: b1 anula `dx`, b0 anula `dy` |
| `$14`/`$18` | `$100814` | `dx`, `dy` do passo |
| `$16`/`$1A` | `$100816` | **x** (eixo de 320) e **y** (eixo de 256) |
| `$1C` | `$10081C` | células dentro do troço recto actual (usado pelo bisel, §5.6) |
| `$1E` | `$10081E` | contador de pixels de trilha para a pontuação (mod 4) |
| `$1F` | `$10081F` | flag de auto-fecho do preenchimento |
| `$63`/`$64`/`$65` | `$100863` | flags e temporizador de "trilha cortada" |
| `$80` | `$100880` | comprimento do segmento actual de trilha |
| `$96`/`$97` | `$100896` | nº de vértices / **trilha activa** |
| `$9C` | `$10089C` | ponteiro de escrita da lista de vértices |
| `$A0`… | `$1008A0` | lista de vértices, 4 bytes cada; `$A0` = sentinela `$FFFFFFFF` |
| `$A4`/`$A6` | `$1008A4` | **primeiro vértice** = ponto onde a trilha começou |

### 4.1 Nascimento

`loc_005024` (dentro de `inp_read_cchip`) trata o estado `$FF`:

- fora da demo: `x = $13` (19) ou `$12D` (301) com o ecrã espelhado, `y = $7F` (127) — o
  jogador começa **encostado à moldura, a meia altura**;
- na demo: `x`/`y` vêm de `g_respawn_x`/`g_respawn_y` (`$1001A0`/`$1001A2`).

Em qualquer caso repõe a lista de vértices (`$9C(a4) = &$A0(a4)`, `$A0(a4) = $FFFFFFFF`),
envia o comando de som `$10` e limpa `$5(a4)` e `$7(a4)`.

### 4.2 Entradas

`inp_read_cchip` (`$004FAE`) só lê o C-Chip quando `g_game_active` (`$100040`) `!= 0`. Em
atracção salta para `$017DC6` (chamada em `$00501A`), que reproduz um dos quatro guiões
gravados em `$039252`/`$0396C4`/`$0397EC`/`$039C5E` — o modo de demonstração foi
**capturado**, não programado. A rotina gémea de **gravação** está em `$017D40`, com o laço
de escrita em `loc_017D8C`; o ponteiro de escrita é inicializado com `$00039252`, que é ROM,
portanto a gravação é inerte na placa de produção.

A leitura junta `CCHIP_RAM+$A` e `CCHIP_RAM+$C`, complementa ambas, troca-as conforme o
espelhamento, e empacota em `g_input_bits` (`$10002A`) com **b0 = BAIXO, b1 = DIREITA,
b2 = ESQUERDA, b3 = CIMA, b4 = BOTÃO1, activo alto**.

`inp_dir_bits_to_code` (`$0050E6`) converte esse conjunto num código de direcção, e só
aceita **uma** direcção de cada vez (joystick de 4 vias):

| Bits (`$10002A & $F`) | Código |
|---|---|
| `$1` (BAIXO) | 4 |
| `$2` (DIREITA) | 1 |
| `$4` (ESQUERDA) | 2 |
| `$8` (CIMA) | 3 |
| outro / nenhum / combinação | 0 |

Com o ecrã espelhado (`g_screen_noflip == 0`) o código sofre `d1 ^= 3` se `d1 < 3` e
`d1 ^= 7` caso contrário, isto é: `1↔2` e `3↔4`.

`player_read_direction` (`$0050B2`) põe `g_draw_mode` (`$100310`) a partir do bit 4 do
joystick, mas **força-o a `$10` se já houver trilha em construção** (`$97(a4) != 0`) —
largar o botão a meio não interrompe o traço.

### 4.3 O passo de movimento

`player_load_dir_params` (`$005170`) copia 7 bytes de `player_dir_param_table`
(`$005196`, 4 registos de 8 bytes) para o objecto. Bytes crus e efeito:

| Código | Bytes | `$08` | `$0D` | `$0E` | `$0F` | `$10` | `$11` | `$13` | passo resultante |
|---|---|---|---|---|---|---|---|---|---|
| 1 DIREITA | `01 10 02 01 01 01 02 00` | 1 | `$10` | 2 | 1 | 1 | 1 | 2 | trava `dx` ⇒ **y +1** |
| 2 ESQUERDA | `01 0C 02 01 01 01 02 00` | 1 | `$0C` | 2 | 1 | 1 | 1 | 2 | trava `dx` ⇒ **y −1** |
| 3 CIMA | `01 02 02 01 01 01 01 00` | 1 | `$02` | 2 | 1 | 1 | 1 | 1 | trava `dy` ⇒ **x +1** |
| 4 BAIXO | `01 36 02 01 01 01 01 00` | 1 | `$36` | 2 | 1 | 1 | 1 | 1 | trava `dy` ⇒ **x −1** |

`$0D` é um índice em `math_dir56_velocity_table` (`$005AE2`, 56 pares de bytes com sinal), a
mesma tabela que os objectos usam para se moverem em 56 direcções.
`player_velocity_from_dir` (`$00555C`) faz **`índice = $0D − 1`**, lê o par e depois aplica a
trava de `$13(a4)`:

```
player_velocity_from_dir:
        lea.l   math_dir56_velocity_table(pc),a0                        ; $00555C
        subq.w  #$1,d0
        add.w   d0,d0
        adda.w  d0,a0
        clr.w   d1
        btst.b  #$1,$13(a4)                                             ; $005568
        bne.b   loc_005574              ; bit 1 ⇒ dx = 0
        move.b  (a0),d1
        ext.w   d1
loc_005574:
        move.w  d1,$14(a4)
```

Verificado byte a byte na tabela: `$0D=$10 → (4,1)`, `$0D=$0C → (3,−1)`,
`$0D=$02 → (1,−4)`, `$0D=$36 → (−1,−3)`. Com a trava, os quatro códigos degeneram sempre num
passo de **exactamente ±1 pixel num só eixo**. A maquinaria de `$0D`/`$0E`/`$0F` (avançar a
direcção pelo anel de 56 a cada segmento) é genérica e partilhada com os objectos; para o
jogador não curva nada.

**O trinco `$07(a4)`.** Enquanto for ≠ 0 o joystick não é relido e a direcção não é
recarregada. Com `$0E = 2` e `$10 = $11 = $12 = 1`, o ciclo é:

| chamada | `$0E` antes | o que acontece |
|---|---|---|
| 1 | — | `$7 = 1`, `$9 = $8`; move; `$0E` continua 2 → percurso **"parede"** (§4.5b) |
| 2 | 2 | `$12` esgota, `$0E` → 1, `$0D` += `$0F`; move; percurso **"desenho"** (§4.5a) |
| 3 | 1 | `$12` esgota, `$0E` → 0, `clr.b $7(a4)`, **não move** |

Ou seja: cada compromisso vale dois pixels, um deles gasto a testar se ainda se está em
cima de uma parede.

**Velocidade.** `player_update` (`$005122`) é chamada 2 a 4 vezes por frame:

```
        bsr.w   player_update                                           ; $004E14  (1)
        tst.b   $804(a5)                ; fill armado? -> pára
        bne.b   loc_004E44
        bsr.w   player_update                                           ; $004E1E  (2)
        tst.b   $897(a5)                ; g_trail_active
        beq.b   loc_004E30
        cmpi.w  #$8,$880(a5)            ; g_trail_length
        bcs.b   loc_004E44              ; segmento < 8 px -> pára em 2
loc_004E30:
        tst.w   $31A(a5)                ; g_speedup_active
        beq.b   loc_004E44
        bsr.w   player_update                                           ; $004E36  (3)
        tst.b   $804(a5)
        bne.b   loc_004E44
        bsr.w   player_update                                           ; $004E40  (4)
```

**2 chamadas/frame** por omissão, **4** com o item de aceleração (`g_speedup_active`,
`$10031A`), mas nunca 4 nos primeiros 8 pixels de um segmento novo de trilha.

### 4.4 Limites do campo

`player_move_and_draw_trail` (`$0051B6`) calcula duas posições por passo: `(d4,d5)` = a
célula seguinte e `(d0,d1)` = duas células à frente. Depois valida:

```
        cmpi.w  #$13,d4                                                 ; $00524C
        bcs.w   loc_0052FE              ; x >= 19
        cmpi.w  #$12E,d4
        bcc.w   loc_0052FE              ; x <= 301
        cmpi.w  #$F,d5
        bcs.w   loc_0052FE              ; y >= 15
        cmpi.w  #$F0,d5
        bcc.w   loc_0052FE              ; y <= 239
```

Estes quatro números batem exactamente com a moldura desenhada por
`vram_draw_border_frame` (`$0071A4`). Os quatro pares de constantes que ela soma a
`g_vram_page_ptr` são **offsets dentro da página de VRAM**, não endereços de ROM; convertidos
com `offset = x*2 + y*1024` dão:

| Escrita | Offset inicial | Offset final | Em coordenadas |
|---|---|---|---|
| linha de cima | `$003C26` | `$003E5C` | y = 15, x = 19…301 |
| linha de baixo | `$03BC26` | `$03BE5C` | y = 239, x = 19…301 |
| coluna esquerda | `$003C26` | `$03C026` | x = 19, y = 15…239 |
| coluna direita | `$003E5A` | `$03C25A` | x = 301, y = 15…239 |

Todas escritas com o valor `$8040` (bit 15 + bit 6). Fora da moldura,
`vram_init_playfield` (`$007222`) enche mais 3 colunas (x = 16…18, cursor `$2020`) e 2
colunas (x = 302…303, cursor `$225C`) com `$8000`, 240 linhas a partir de y = 8 — as margens
que o MAME mostra como "visível 8–247".

**O interior útil é portanto x ∈ [20, 300] × y ∈ [16, 238] = 281 × 223 = 62 663 pixels.**
Este número volta a aparecer na §6.

### 4.5 A trilha

Há dois caminhos, escolhidos por `cmpi.b #$2,$E(a4)` em `$00526C`.

**(a) A desenhar** (`$0E(a4) != 2`). Testa a célula seguinte (`a1`):

- bit 15 aceso ⇒ já é território conquistado: apaga a marca e pára (`loc_00537A`);
- bit 6 aceso ⇒ é parede: **fecha o circuito** (`loc_0053AC`), limpa a marca e chama
  `player_trail_reset`;
- senão: avança, e escreve na célula **bit 7 e bit 15**:

```
        move.w  d4,$16(a4)                                              ; $00528C
        move.w  d5,$1A(a4)
        bset.b  #$7,$1(a1)              ; bit 7  = trilha em construção ; $005294
        bset.b  #$7,(a1)                ; bit 15 = pixel visível        ; $00529A
        addq.b  #$1,$1E(a4)
        cmpi.b  #$4,$1E(a4)
        bcs.b   loc_0052B6
        clr.b   $1E(a4)
        move.w  #$1,d0
        bsr.w   game_add_score          ; 1 unidade = 10 pontos no ecrã ; $0052B2
loc_0052B6:
        addq.w  #$1,$80(a4)             ; g_trail_length
```

**A cada 4 pixels de trilha o jogo dá 1 unidade de pontuação, isto é, 10 pontos no ecrã.**

**(b) A andar pela parede** (`$0E(a4) == 2`). Testa a célula **duas à frente** (`a0`) e a
seguinte (`a1`):

- ambas com bit 6 ⇒ ainda é parede, continua a andar (`loc_0052D4` só se ambas o forem);
- duas à frente sem bit 6 e `g_draw_mode != 0` ⇒ empilha um vértice e começa a desenhar;
- duas à frente sem bit 6 e `g_draw_mode == 0` ⇒ `clr.b $7(a4)`: o compromisso é
  cancelado e o jogador não sai da parede.

`player_trail_push_vertex` (`$0054BE`) só empilha quando a direcção muda e a mudança é
*legal* (`player_turn_is_legal_maybe`, `$0054A2`: os códigos 1/2 são um eixo e 3/4 o outro;
inverter no mesmo eixo não conta como mudança). Escreve o par `(x, y)` em `(a1)` a partir de
`$9C(a4)`, incrementa `$96(a4)`, liga `$97(a4)` e zera `g_trail_length`.

> `$100897` (`g_trail_active`) só é **escrito** num sítio em toda a ROM:
> `move.b #$1,$97(a4)` em `$00550A`. É **limpo** pelo `clr.w $96(a4)` de
> `player_trail_reset` (`$005FF4`) e de `vram_fill_prepare` (`$005472`), que zeram o par
> `$896`/`$897` de uma vez. Isto resolve a dúvida 3 da banda 05 em
> [`ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md) ("`$100897` nunca é escrito").

### 4.6 Morte

Quando um tiro ou uma faísca toca a trilha ou o jogador, o golpe final é sempre
`$805(a5) = $FE`. `player_death_sequence` (`$004C7E`) trata os dois estados:

- **`$FE`**: limpa a tabela `$103700`, põe `g_timeout_state = 5`, e espalha **16 fragmentos**
  na tabela `$103400` (passo `$20`) com tile `$53`, todos na posição do jogador; passa a
  `$FD`.
- **`$FD`**: anima os fragmentos até todos morrerem; envia o comando de som `$00` (calar).
  Se `$97(a4) == 0` (não havia trilha) renasce onde está. Senão **apaga a trilha andando por
  ela**:

```
loc_004D4E:
        move.w  #$2,d2                                                  ; $004D4E
        btst.b  #$7,$3(a0)              ; há trilha uma coluna à frente?
        bne.b   loc_004D76
        move.w  #$FFFE,d2               ; senão, uma coluna atrás
        btst.b  #$7,-$1(a0)
        bne.b   loc_004D76
        move.w  #$400,d2                ; senão, linha seguinte
        btst.b  #$7,$401(a0)
        bne.b   loc_004D76
        move.w  #$FC00,d2               ; senão, linha anterior
loc_004D76:
        move.w  (a0),d0
        andi.w  #$7F7F,d0               ; apaga bit 15 e bit 7
        move.w  d0,(a0)
        adda.w  d2,a0
        cmpa.l  a1,a0
        beq.b   loc_004D90              ; chegou ao primeiro vértice
```

Percorre a trilha pixel a pixel desde a posição actual até ao primeiro vértice
(`$A4`/`$A6`), limpando bits 15 e 7. **Não há bitmap guardado**: o desfazer é feito seguindo
as próprias marcas de bit 7. O jogador renasce no primeiro vértice
(`g_respawn_x`/`g_respawn_y`, `$1001A0`/`$1001A2`) e o jogo passa a `g_seq_mode = 4`.

---

## 5. O preenchimento de área

É o coração do Qix e é a parte mais interessante do código. Vive em quatro ficheiros:
`src/main68k/vram_fill_arm.asm`, `vram_fill_walk_helpers.asm`, `vram_area_fill_engine.asm`
e `vram_fill_geometry.asm`.

### 5.1 Os bits da word de VRAM

Cada pixel é uma word. A tabela junta o que o MAME documenta com o produtor concreto
encontrado no código (atenção: `bset.b #n,(a0)` mexe no byte **alto** = bits 8..15;
`bset.b #n,$1(a0)` no byte **baixo** = bits 0..7):

| Bit | MAME | Produtor no jogo | Significado prático |
|---|---|---|---|
| 15 | "selecciona imagem A/B" | trilha (`$00529A`), pintura (`$00602C`), blocos de objecto (`$004F4E`) | **pixel conquistado / visível** |
| 14 | "? (usado em cantos 3-D)" | `vram_fill_draw_bevel`, `$006064`/`$006078`/`$00608C` | **canto do biselado** |
| 13 | "? (usado em paredes 3-D)" | `vram_fill_draw_bevel`, `$006046`/`$00604C`/`$006052` | **parede do biselado** |
| 12..9 | imagem B | blitter dos fundos | nibble de cor da imagem B |
| 8 | índice de paleta b10 | `vram_mark_object_block` (`$004F52`), `vram_fill_pass_border` (`$005E94`) | célula ocupada / fronteira já convertida |
| 7 | índice de paleta b9 | `player_move_and_draw_trail` (`$005294`) | **trilha em construção** |
| 6 | índice de paleta b8 | moldura (`$0071A4`), `vram_fill_pass_trail` (`$005F0E`) | **parede / fronteira** |
| 5 | "?" | `vram_fill_mark_arc` (`$005D6C`) | **marcador de rascunho do preenchimento** |
| 4 | "?" | não encontrado | — |
| 3..0 | imagem A | blitter dos fundos | nibble de cor da imagem A |

Os bits 6/7/8 são, no hardware, os bits 8..10 do índice de paleta
(`color = (p[x] << 2) & 0x700`). O jogo usa-os como três flags **e** como selector de banco
de cor ao mesmo tempo: a moldura fica no banco 1, a trilha no banco 2, a fronteira
convertida no banco 4. Os bancos 1–7 e 9–15 da camada bitmap são preenchidos com **uma cor
sólida cada** por `pal_load_area_colors` (`$000F5E`) — são as cores lisas do Qix.

> **Os dois bits "3-D" resolvidos.** O comentário do MAME diz *"'3d' corners & walls are made
> using unknown bits for each line the player draws"*. O produtor é
> `vram_fill_draw_bevel` (`$006038`) e a distinção é exactamente a que o MAME anotou:
> com `$1C(a4) != 0` (meio de um troço recto) acende o **bit 13** em 3 células; com
> `$1C(a4) == 0` (canto / início de troço) acende o **bit 14** e apaga o bit 13, em até 3
> células, parando à primeira em que a máscara `$1C0` (bits 6,7,8) não esteja limpa.
> O passo diagonal vem de `g_fill_bevel_step` (`$10006E`), que `spr_set_screen_flip`
> (`$000EB6`) põe a `$03FE` (+1024−2: uma linha abaixo, uma coluna à esquerda) ou a `$FC02`
> (−1024+2) conforme o espelhamento do ecrã. É um **bisel com fonte de luz fixa**, que
> acompanha a rotação do monitor.

### 5.2 As variáveis do motor

Todas relativas a `a4 = $100800`:

| Offset | Endereço | Papel |
|---|---|---|
| `$1C` | `$10081C` | contador de células dentro do troço recto actual |
| `$1F` | `$10081F` | auto-fecho: partida == chegada |
| `$28`/`$2C` | `$100828` | as duas células vizinhas da chegada, uma de cada lado |
| `$30` | `$100830` | passo do **raio** de teste de paridade |
| `$32` | `$100832` | endereço de VRAM do inimigo grande |
| `$36` | `$100836` | célula de parede onde a trilha **chegou** |
| `$3A` | `$10083A` | ponteiro do lado escolhido |
| `$3E` | `$10083E` | eixo actual do percurso: 0 = colunas (±2), 1 = linhas (±`$400`) |
| `$3F` | `$10083F` | "mão": sinal do passo perpendicular |
| `$40` | `$100840` | célula de VRAM do primeiro vértice = ponto de **partida** |
| `$44`/`$46` | `$100844` | passos que geraram `$28`/`$2C` |
| `$48` | `$100848` | passo do lado escolhido |
| `$4A` | `$10084A` | passo perpendicular de pintura |
| `$88` | `$100888` | endereço do 2.º inimigo grande (só ronda de índice 5) |

Globais: `g_fill_pixel_count` (`$100186`, long), `g_fill_pixel_rest` (`$100188`),
`g_area_permille` (`$100190`), `g_fills_done` (`$1001AF`), `g_fill_dbg_boss_cross`
(`$100316`) e `g_fill_dbg_side_cross` (`$100318`) — os dois últimos guardam as contagens do
raio e não são lidos por ninguém: são um resto de depuração.

### 5.3 Fase 0 — armar (`vram_fill_prepare`, `$0053E6`)

Chamada de `player_move_and_draw_trail` (`$0052FA`) no instante em que a trilha bate numa
parede. À entrada, `a0` = endereço de VRAM do último pixel de trilha.

1. `vram_fill_side_pointers` (`$00551C`): a partir do código de direcção decide o eixo
   (`$3E = 1` para os códigos 3/4, 0 para 1/2) e guarda em `$28`/`$2C` as duas células
   **perpendiculares** à `±$400` (ou `±2`) da chegada, com os passos em `$44`/`$46`.
2. `$30(a4) = vram_dir_step_table[código−1]`, tabela de 8 bytes em `$005480`
   (`FC 00 04 00 FF FE 00 02`):

   | Código | Word | Passo | = |
   |---|---|---|---|
   | 1 | `$FC00` | −1024 | uma linha atrás |
   | 2 | `$0400` | +1024 | uma linha à frente |
   | 3 | `$FFFE` | −2 | uma coluna atrás |
   | 4 | `$0002` | +2 | uma coluna à frente |

   É o passo **oposto** ao do movimento que fechou a trilha.
3. `$32(a4) =` endereço de VRAM do inimigo grande. `g_boss_x`/`g_boss_y`
   (`$101128`/`$101126`) **não** são um endereço: são coordenadas, mascaradas com `$1FE` e
   `$FE` (isto é, arredondadas a par) e espelhadas com `x' = $140 − x`, `y' = $100 − y` se
   `g_screen_noflip == 0`, antes de passarem por `vram_addr_from_xy`.
4. `clr.w $3B0(a5)` (`g_fill_flag_dead` — ver §12.6).
5. **Só quando `g_round_index == 5`**: o mesmo para o segundo inimigo grande
   (`$10209E`/`$10209C`) em `$88(a4)`.
6. `clr.w $96(a4)` (zera vértices + trilha activa) e `$4(a4) = 1`.

O `1` é promovido a `2` na chamada seguinte de `player_read_direction`, que só o faz quando
já existe um compromisso em curso:

```
loc_0050A2:
        cmpi.b  #$1,$4(a4)                                              ; $0050A2
        bne.b   loc_0050B0
        move.b  #$2,$4(a4)                                              ; $0050AA
```

e a partir daí o laço principal apanha-o.

### 5.4 Fase 1 — marcar o arco (`vram_fill_mark_arc`, `$005D56`)

`vram_area_fill` (`$005D2C`) começa por chamar `lvl_objects_unmark_blocks` (`$0075F6`), que
**apaga os blocos 15×15 dos objectos fixos do nível** para não bloquearem o percurso. Depois
calcula `a2 = $40(a4)` (partida, do primeiro vértice) e `a3 = a0 = $36(a4)` (chegada). Se
forem iguais, `vram_fill_selfclose_flag` (`$005CCA`) liga `$1F(a4)` e salta para a fase 2.

Senão, percorre a fronteira (células com bit 6) da chegada até voltar à chegada, dando uma
volta completa. `d4` alterna sempre que o percurso passa pela **partida**, e o bit 5 é
escrito ou apagado conforme a paridade de `d4`:

```
loc_005D66:
        btst.b  #$0,d4                                                  ; $005D66
        bne.b   loc_005D74
        bset.b  #$5,$1(a0)              ; marca de rascunho
        bra.b   loc_005D7A
loc_005D74:
        bclr.b  #$5,$1(a0)
loc_005D7A:
        adda.w  d2,a0
        cmpa.l  a0,a3
        beq.b   vram_fill_choose_side
        cmpa.l  a0,a2
        bne.b   loc_005D88
        eori.w  #$1,d4                                                  ; $005D84
loc_005D88:
        btst.b  #$6,$1(a0)
        bne.w   vram_fill_corner_arc    ; deixou de ser fronteira -> canto
        eori.b  #$1,$3E(a4)             ; troca de eixo e volta a tentar
        suba.w  d2,a0
        bra.b   vram_fill_mark_arc
```

**Resultado: dos dois arcos em que a fronteira fica dividida pela partida e pela chegada,
exactamente um fica com o bit 5 aceso.**

O passo é dado por `vram_fill_step_and_back` (`$0060C6`): `d2 = $400` se `$3E != 0`, senão
`d2 = 2`; avança `a0` e deixa `a1 = a0 − 2·d2`, ou seja a célula anterior. Quando a célula
seguinte deixa de ser fronteira, `vram_fill_corner_arc` (`$005C66`) testa se se trata de um
canto (`vram_fill_corner_test`, `$005C8A`: a célula do eixo actual **e** a do outro eixo são
ambas fronteira) e, se for, roda o eixo (`$3E ^= 1`).

### 5.5 Fase 2 — escolher o lado (`vram_fill_choose_side`, `$005D9C`)

O teste de ponto-em-polígono. `vram_fill_count_crossings` (`$0060E0`) lança um raio a partir
de `a0` com passo `2 × $30(a4)` e conta o que atravessa:

```
vram_fill_count_crossings:
        move.w  $30(a4),d0                                              ; $0060E0
        adda.w  d0,a0
        lsl.w   #$1,d0
        clr.w   d7
loc_0060EA:
        btst.b  #$6,$1(a0)              ; fronteira? -> pára            ; $0060EA
        bne.b   loc_006102
        btst.b  #$7,$1(a0)              ; trilha? -> conta 1
        bne.b   loc_0060FE
loc_0060FA:
        adda.w  d0,a0
        bra.b   loc_0060EA
loc_0060FE:
        addq.w  #$1,d7
        bra.b   loc_0060FA
loc_006102:
        addq.w  #$1,d7                  ; a fronteira conta 1
        btst.b  #$5,$1(a0)              ; ...e mais 1 se for o arco marcado
        beq.b   loc_006114
        tst.b   $1F(a4)                 ; (excepto no auto-fecho)
        bne.b   loc_006114
        addq.w  #$1,d7
```

A **paridade** da contagem diz de que lado da curva fechada está o ponto. O motor faz três
lançamentos:

1. do inimigo grande (`$32(a4)`) → guarda a contagem em `$100316` e a paridade em `d6`;
2. **só na ronda de índice 5**, do segundo inimigo grande (`$88(a4)`): se as duas paridades
   forem diferentes, os dois inimigos ficaram em lados opostos e a fase **termina** —
   `g_round_end_reason = 1`, ou `4` se `g_area_permille < $A` (menos de 1,0 %), seguido de
   `game_abort_to_attract` e `player_trail_reset`;
3. de `$28(a4)` → guarda em `$100318`. Se a paridade for **igual** à do inimigo grande, esse
   lado é o de fora e escolhe-se o outro (`$2C`, passo `$46`); senão escolhe-se `$28`, passo
   `$44`.

**Nunca se preenche o lado onde está o inimigo grande.**

Segue-se a dedução da "mão" (`$3F(a4)`) comparando `$48(a4)` com `vram_fill_axis_pairs`
(`$00600E`, 4 registos de 2 words: `0002/FFFE`, `FFFE/0002`, `FC00/0400`, `0400/FC00`),
indexado pelo código da direcção. Se `$48` não bater com nenhuma das duas:

```
loc_005E50:
        bra.b   loc_005E50              ; assert do programador: trava a máquina  ; $005E50
```

É um `bra *` deixado na ROM final — o mesmo estilo do assert em `$01851A` (banda 04).

### 5.6 Fase 3 — as duas passagens

`vram_fill_set_perp_step` (`$006096`) roda o passo do percurso 90° (`$400 → 2`, `$FC00 → $FFFE`,
`2 → $FC00`, senão `$400`) e nega-o se `$3F(a4) != 0`, pondo o resultado em `$4A(a4)`. É o
passo do **pincel**.

**3a — a fronteira** (`vram_fill_pass_border`, `$005E5E`): percorre o arco escolhido, da
chegada (`$36`) até à partida (`$40`). Em cada célula:

```
loc_005E94:
        bset.b  #$0,(a0)                ; acende o bit 8                ; $005E94
        bclr.b  #$6,$1(a0)              ; apaga o bit 6
        bsr.w   vram_fill_paint_run
        addq.w  #$1,$1C(a4)
        adda.w  d2,a0
        cmpa.l  a0,a2
        beq.b   vram_fill_pass_trail
```

Os pixels desta passagem **não** são contados para a área: já o foram quando eram trilha.

**3b — a trilha** (`vram_fill_pass_trail`, `$005EC4`): inverte `$3F(a4)` (a trilha é
percorrida com a mão contrária), desenha o bisel inicial e percorre a trilha (bit 7) da
chegada até à partida:

```
loc_005F0E:
        bset.b  #$6,$1(a0)              ; a trilha passa a parede       ; $005F0E
        bclr.b  #$7,$1(a0)
        addq.l  #$1,$186(a5)            ; g_fill_pixel_count
        bsr.w   vram_fill_paint_run
```

Cada pixel de trilha convertido conta para a área.

**O pincel** (`vram_fill_paint_run`, `$00601E`) só actua num dos dois eixos:

```
vram_fill_paint_run:
        tst.b   $3E(a4)                                                 ; $00601E
        beq.b   vram_fill_draw_bevel    ; no outro eixo só desenha o bisel
        movea.l a0,a1
        move.w  $4A(a4),d0
loc_00602A:
        adda.w  d0,a1
        bset.b  #$7,(a1)                ; acende o bit 15
        bne.b   vram_fill_draw_bevel    ; já estava aceso -> fim do traço
        addq.l  #$1,$186(a5)
        bra.b   loc_00602A
```

É um preenchimento por varrimento semeado na fronteira: de cada célula do percurso parte um
raio perpendicular que pinta até bater em pixel já pintado. O `bset` devolve o valor
anterior, o que serve ao mesmo tempo de teste de paragem e de garantia de que **cada pixel é
contado uma única vez**.

### 5.7 Fase 4 — contabilidade (`vram_fill_finish`, `$005F42`)

```
vram_fill_finish:
        clr.w   $1C(a4)                                                 ; $005F42
        bsr.w   vram_fill_paint_run
        addq.b  #$1,$1AF(a5)            ; g_fills_done                  ; $005F4A
        move.l  $186(a5),d0             ; g_fill_pixel_count
        divu.w  #$3F,d0                 ; 63 px = 0,1 %                 ; $005F52
        add.w   d0,$190(a5)             ; g_area_permille
        cmpi.b  #$6,$1AF(a5)
        bne.b   loc_005F68
        addi.w  #$6,$190(a5)            ; 6.º preenchimento: +0,6 %     ; $005F62
loc_005F68:
        swap    d0
        move.w  d0,$188(a5)             ; o resto fica para o próximo fill
        clr.w   $186(a5)
```

Depois converte `g_area_permille` (0..1000) para BCD em `$100192`/`$100193`, com dois casos
especiais: valores `< 10` passam directos (o binário coincide com o BCD) e valores `>= 999`
são saturados em `$999`. Marca `$69(a4)` (`$100869`) a 1 — o sinal que faz os inimigos
pequenos verificarem se ficaram dentro da área (§7.3) — e `$4D(a4) = 1`,
`$4E(a4) = $50(a4) = $100`.

Por fim chama `lvl_objects_check_claimed` (`$00762A`) e **cai** — sem `rts` — em
`player_trail_reset` (`$005FE0`), que limpa o estado da trilha e faz `clr.b $4(a4)`,
libertando o laço principal.

> O corte de rotina do desmontador está correcto no ficheiro gerado, mas note-se que
> `$005F42-$00600D` é um só bloco de código: `vram_fill_finish` termina por queda em
> `player_trail_reset`. É a dúvida 5 da banda 01 em
> [`ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md), aqui fechada.

### 5.8 Os objectos do nível

`lvl_objects_unmark_blocks` (`$0075F6`) corre **antes** do percurso e
`lvl_objects_check_claimed` (`$00762A`) **depois**. O segundo testa o bit 15 no centro
(`x+8`, `y+8`) de cada objecto (`vram_test_filled_at_obj`, `$00767C`): se o centro ficou
dentro do território conquistado o objecto é apanhado (`$7(a4) = 1`, ou removido se
`$10(a4) != 0`); senão volta a marcar o bloco 15×15 com `vram_mark_object_block`
(`$004F42`, bits 15 e 8).

### 5.9 O que fica por esclarecer no preenchimento

O mecanismo global está fechado — armar, marcar arco, escolher lado por paridade, converter
a fronteira e a trilha, pintar por varrimento, contabilizar. **A peça que não verifiquei é a
correcção geométrica do percurso em fronteiras complexas.** Concretamente:

- `vram_fill_corner_test` (`$005C8A`) e `vram_fill_turn_step` (`$005CB6`) decidem quando o
  percurso muda de eixo, mas não segui todos os casos (por exemplo, uma fronteira com uma
  saliência de um pixel, ou duas áreas conquistadas que se tocam num canto). Não sei dizer se
  o percurso está garantidamente fechado nesses casos, nem se o `bra *` de `$005E50` é
  alcançável.
- `vram_fill_selfclose_dispatch` (`$005C32`) escolhe se se começa pela fronteira ou pela
  trilha no caso degenerado partida == chegada, olhando para o bit 6 uma célula antes de
  `$3A(a4)`. Percebo a mecânica; não percebo por que razão a escolha é essa.
- A `$1C(a4)` que controla o bisel é incrementada em ambas as passagens e zerada em cada
  mudança de eixo, mas não confirmei que o resultado visual corresponda a "canto" e "parede"
  no sentido geométrico e não apenas no sentido do percurso.

---

## 6. A percentagem

### 6.1 A escala

`divu.w #$3F` em `$005F52`: **63 pixels = 0,1 %**, logo 63 000 pixels = 100 %. O resto da
divisão é guardado em `$100188` e reentra na conta do preenchimento seguinte, por isso não há
perda acumulada.

O interior útil da moldura (§4.4) tem 281 × 223 = **62 663 pixels**. Conquistar tudo dá
`floor(62663 / 63) = 994` décimos, ou seja **99,4 %** — e `994 + 6 = 1000`, isto é 100,0 %,
que a conversão para BCD satura em `$999` = **99,9 %**, exactamente o degrau mais alto da
escada de bónus (§12.6, 500 000 pontos).

> **Conjectura, mas com a aritmética a fechar ao décimo:** o `addi.w #$6,$190(a5)` do sexto
> preenchimento é a compensação do arredondamento da divisão por 63, calibrada para que um
> campo inteiramente conquistado chegue ao topo da escada. Não testei em emulação; quem o
> fizer confirma ou desmente em cinco minutos.

### 6.2 As representações

| Endereço | Nome | Formato |
|---|---|---|
| `$100186` | `g_fill_pixel_count` | long, pixels do preenchimento em curso |
| `$100188` | `g_fill_pixel_rest` | word, resto da divisão por 63 |
| `$100190` | `g_area_permille` | word, 0..1000 (décimos de %) — **o valor verdadeiro** |
| `$100192`/`$100193` | `g_area_pct_target` | 3 dígitos BCD do valor verdadeiro |
| `$10018E`/`$10018F` | `g_area_pct_shown` | 3 dígitos BCD do valor **mostrado**, que sobe passo a passo |
| `$100322` | `g_area_pct_step_delay` | atraso entre passos do contador |

### 6.3 O contador do HUD paga pontos

`hud_area_pct_step` (`$004EB0`) faz subir `g_area_pct_shown` até ao alvo, um passo por
chamada, e cada passo dá pontuação:

| Passo | Condição | Somando (BCD) | Pontos no ecrã | Atraso seguinte |
|---|---|---|---|---|
| dezena de % | `$18F != $193` | `$100` | 1 000 | 1 frame |
| unidade de % | nibble alto de `$18E` != nibble alto de `$192` | `$10` | 100 | 0 |
| décimo de % | resto | `$1` | 10 | 0 |

Resultado líquido: **a área vale 100 pontos por cada 1 %**. Chegar a 85,3 % rende
8 000 + 500 + 30 = 8 530 pontos.

O campo do HUD é o número 4 da tabela `txt_number_field_table` (`$0019EC`), cujo registo de
8 bytes é `03 01 06 A8 00 10 01 8F`: **3 dígitos, fonte alternativa, sprites a partir de
`SPRITE_RAM+$6A8`, ponteiro `$10018F`**. Com `fonte = 1` os dígitos que não são o último
usam tiles `$13E + d` (`txt_number_digit_to_tile`, `$0019C6`).
`txt_show_pct_symbol_maybe` (`$004F30`) escreve `$13E` (o `0` grande) em `SPRITE_RAM+$6B4`
quando essa posição está a zero.

### 6.4 O alvo: 80,0 %

```
game_check_area_target:
        cmpi.b  #$8,$193(a5)            ; g_area_pct_target_hi          ; $0032A8
        bcs.b   loc_0032F6              ; < 80,0 % -> testa o chefe
        cmpi.b  #$1,$1AF(a5)            ; g_fills_done
        beq.b   loc_0032EE              ; 80 % num único fill -> razão 3
        clr.b   $887(a5)                ; razão 0
```

`$193` é o dígito das dezenas de percentagem, logo `>= 8` significa `>= 80,0 %`. Se a área
ainda não chegou lá, testa `$10088C` (`g_boss_defeated_maybe`) e, se estiver aceso, termina
a ronda com razão 2.

### 6.5 O texto "DD.D"

`txt_format_percent` (`$003340`) monta o texto do ecrã de fim de ronda em `$100362..$100365`
a partir de `$100192`/`$100193`:

```
        move.b  #$2E,$364(a5)           ; o ponto decimal, literal      ; $003378
        cmpi.w  #$3939,$362(a5)         ; os dois primeiros dígitos são "99"?
        beq.b   loc_00338E
        move.b  #$30,$365(a5)           ; não -> a casa decimal é forçada a '0'
        rts
loc_00338E:
        move.b  $192(a5),d0             ; sim -> mostra a casa decimal real
        andi.b  #$F,d0
        addi.b  #$30,d0
        move.b  d0,$365(a5)
```

**Abaixo de 99 % o ecrã de fim de ronda trunca para percentagem inteira; só na faixa 99,x
mostra o décimo.** É exactamente a granularidade da escada de bónus (§12.6).

---

## 7. Pontuação

### 7.1 A pontuação está guardada a dividir por 10

`$10019C`/`$10019D`/`$10019E` são 3 bytes BCD com o **byte menos significativo no endereço
mais baixo** (6 dígitos). O ecrã mostra esses 6 dígitos **mais um `'0'` fixo colado à
direita**: decodifiquei a tabela de mensagens sobre `build/maincpu.bin` e as entradas
`$2B`–`$2F` são literalmente `"1ST ......0    ..  ..."`. O campo numérico 0 da tabela
`$0019EC` é `06 00 06 E8 00 10 01 9E` — 6 dígitos a partir de `$10019E`.

Confirmação cruzada independente: a `bonus_life_table` guarda 5000/15000/60000/300000 onde o
MAME documenta 50k/150k/600k/3000k (§8.2).

### 7.2 `game_add_score` (`$00302E`)

Nada acontece se `g_game_active == 0` — em atracção o jogo não pontua. O somando entra em
`d0.w` (BCD) e é espalhado por `$100199` (byte baixo) e `$10019A` (byte alto); `$10019B` é um
terceiro byte que a maior parte dos chamadores deixa a zero, mas que os bónus grandes usam
(§12.6). A soma é feita com três `abcd` encadeados:

```
        lea.l   $19A(a5),a1                                             ; $003042
        lea.l   $19D(a5),a0
        moveq   #$2,d0
        move.w  #$0,ccr
loc_003050:
        abcd.b  -(a1),-(a0)
        addq.l  #$2,a0
        addq.l  #$2,a1
        scc.b   d1
        dbra    d0,loc_003050
        tst.b   d1
        bne.b   loc_003072
        move.l  #$99,d1                 ; transbordo -> satura em 999999
        lea.l   $19C(a5),a1
        move.b  d1,(a1)+
        move.b  d1,(a1)+
        move.b  d1,(a1)
```

Depois compara `{$1B3, $1B2}` (byte alto, byte médio da meta) com `{$19E, $19D}` para a vida
extra — **os dois dígitos mais baixos da pontuação (`$10019C`) são ignorados** — redesenha o
campo numérico do jogador activo (0 ou 1 conforme `g_cur_player`) e chama
`game_update_hiscore` (`$0030CE`).

### 7.3 De onde vêm os pontos

| Fonte | Endereço da chamada | Somando | No ecrã |
|---|---|---|---|
| 4 pixels de trilha | `$0052B2` | `$0001` | 10 |
| cada 0,1 % do contador | `$004F2A` | `$0001` | 10 |
| cada 1 % do contador | `$004F16` | `$0010` | 100 |
| cada 10 % do contador | `$004EE4` | `$0100` | 1 000 |
| inimigo apanhado, 1.º da cadeia | `tbl_capture_chain_points`, `$0214F4` | `$0100` | 1 000 |
| … 2.º / 3.º / 4.º | idem | `$0200` / `$0400` / `$0800` | 2 000 / 4 000 / 8 000 |
| … 5.º / 6.º / 7.º | idem | `$1600` / `$3200` / `$6400` | 16 000 / 32 000 / 64 000 |
| bónus de área no fim da ronda | `$003A48`/`$003A52` | escada de `10` a `500` × 1000 | 10 000 a 500 000 |
| "SEPARATE ROUND CLEAR" | `$00380A` | `$1000` | 10 000 |
| "SPECIAL ROUND CLEAR" | `$00380A` + `$003820` | `$1000` + `$9000` | 100 000 |
| bónus de 1 000 000 | `game_award_1000000`, `$003828` | 20 × `$5000` | 1 000 000 |
| última ronda | `$003B20`/`$003B26` | `$19B = $10`, `d0 = 0` | 1 000 000 |

A tabela da cadeia de capturas (`$0214F4`, valores `0100 0200 0400 0800 1600 3200 6400`
lidos do binário) é indexada por `$2A(a4)`, a posição do inimigo na cadeia do frame.
`enemy_capture_check` (`$021094`) é o mecanismo:

```
loc_0210B0:
        move.w  $C(a4),d0                                               ; $0210B0
        move.w  $E(a4),d1
        jsr     vram_addr_from_xy_016258
        move.w  (a0),d0
        bchg.b  #$F,d0                                                  ; $0210C0
        andi.w  #$8180,d0
        beq.w   loc_0210D8              ; bit15=1, bits 8 e 7 = 0 -> capturado
```

O jogo **não guarda polígonos**: pergunta ao próprio bitmap se o pixel debaixo do inimigo
pertence à zona preenchida. Detalhe que só se vê no código: este teste só corre quando
`g_round_cleared` (`$10086A`) ou `$100869` estiverem activos, e `$100869` é posto a 1 por
`vram_fill_finish` — ou seja, a varredura de inimigos encurralados acontece **logo a seguir
a cada preenchimento**, não continuamente. Cada inimigo capturado no mesmo varrimento recebe
`$2A(a4) = g_capture_chain` (`$102130`) e incrementa-o, e o valor **duplica** a cada inimigo
até 64 000 pelo sétimo.

---

## 8. Vidas e bónus

### 8.1 Número inicial de vidas

`reset_entry` lê `(g_dswb & $30) >> 3` e indexa `lives_table` (`$001622`, bytes
`00 03 00 04 00 05 00 06`) para `g_lives_setting` (`$100042`). **Os DIPs chegam
complementados** (`snd_read_dipswitches`, `$007372`, faz `not.b` antes de guardar), portanto
o valor cru `$30` do DSWB dá índice 0 = 3 vidas, `$20` dá 4, `$10` dá 5 e `$00` dá 6 —
exactamente a tabela do `HARDWARE_GROUND_TRUTH`.

O *cheat* de 32768 vidas está em `$0015CC`: com o bit 6 do DSWB (complementado) aceso,
`g_lives_setting = $8000`.

### 8.2 Bónus de vida

`game_next_bonus_threshold` (`$003110`) escolhe a próxima meta em `bonus_life_table`
(`$003140`, **4 conjuntos de 6 words**, deslocamento `= (g_dswb & 3) * 12`), copia-a para
`$32(a0)` (= `$1001B2` no contexto activo) e avança `$34(a0)` (`$1001B4`), saturando em 5.

Bytes lidos de `build/maincpu.bin` (48 bytes, 24 words):

| Índice | DSWB cru | Words na ROM | Metas no ecrã |
|---|---|---|---|
| 0 | `$03` | `5000 5001 0006 0030 9999 9999` | 50 k · 150 k · 600 k · 3000 k |
| 1 | `$02` | `2000 4000 2001 8004 0024 9999` | 20 k · 40 k · 120 k · 480 k · 2400 k |
| 2 | `$01` | `7000 8002 0014 9999 9999 9999` | 70 k · 280 k · 1400 k |
| 3 | `$00` | `0001 0005 9999 9999 9999 9999` | 100 k · 500 k |

A leitura da word é `{$1B2 = byte alto da word = dígitos médios, $1B3 = byte baixo = dígitos
altos}`; `$9999` é a sentinela "não há mais bónus", testada em `$003088`. Os quatro conjuntos
batem 4/4 com o que o MAME documenta, usando `(~DSW) & 3` como índice.

Ao ganhar uma vida o jogo envia o som `$08`, incrementa `g_lives` (`$100180`) até ao máximo
de 9, e redesenha os ícones.

### 8.3 Ícones de vida

`txt_draw_lives_icons` (`$003170`) desenha até 5 ícones (tile `$149`) em `SPRITE_RAM+$62C`,
com `min(g_lives − 1, 5)`. **Não desenha nada quando `g_round_index >= $F`** — na última
ronda os ícones desaparecem do HUD.

### 8.4 Perder vida e trocar de jogador

O contexto de cada jogador são **128 bytes**: `$100080` (P1), `$100100` (P2) e `$100180`
(activo). `game_switch_to_player1/2` (`$003D86`/`$003D68`) trocam 64 words entre eles.
Campos conhecidos: `+$00` vidas, `+$0A`/`+$0C` escudo e passo do escudo, `+$17`/`+$18`
flags, `+$32` meta de bónus, `+$34` índice de bónus.

`player_lose_life` (`$003CCE`) decrementa `g_lives`; a zero grava a pontuação final; com
vidas restantes e dois jogadores, troca de contexto **e de página de VRAM**:

```
        bsr.w   game_switch_to_player2                                  ; $003D3A
        move.w  #$1,$36(a5)             ; g_cur_player
        move.l  #VRAM+$40000,$6A(a5)    ; g_vram_page_ptr               ; $003D44
```

Cada jogador tem a sua página de 256 KB de VRAM, portanto **a área conquistada de cada um
fica intacta enquanto o outro joga**. Os bits 0 e 1 de `$100047` marcam qual dos jogadores
já está em game over; se o outro estiver, não há troca. Ver
[`02-mapa-de-memoria.md`](02-mapa-de-memoria.md).

---

## 9. O escudo

`hud_draw_countdown_labels` (`$007F4C`) desenha as mensagens `$4C` e `$4D` e o campo
numérico `$15`. A mensagem `$4C` é um registo de códigos de 16 bits (attr `$C5`: bit 7 =
passo de 16 px, bit 6 = códigos de 16 bits) com os tiles `$0228..$022B`; `txt_draw_message`
subtrai `$20` a cada código, portanto os tiles reais são `$0208..$020B`.

**Extraí os quatro tiles de `build/pc090oj.bin` e desenhei-os: lêem-se `SHIELD`.** A
mensagem `$4D` é a string `"..."` — o marcador de três dígitos, na mesma posição de sprite
(`$0600`) do campo numérico `$15`.

Isto identifica o contador que ficara com o nome neutro `g_countdown_bcd` na
[`ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md) (dúvida 1 da banda 02) e explica os valores
"pequenos demais":

- O contador é um par BCD **little-endian por byte**: `$10018A` = os dois dígitos baixos,
  `$10018B` = os dígitos altos. O campo numérico `$15` (`03 00 06 00 00 10 01 8B`) desenha
  3 dígitos lendo o nibble baixo de `$18B`, depois o nibble alto e o baixo de `$18A`.
  `move.w #$9,$18A(a5)` escreve `$18A = $00`, `$18B = $09`, ou seja **900**.
- `game_init_player_context` (`$000B1E`) põe `$A(a0) = 9` e **`$C(a0) = $100`**, isto é
  `$18A = 900` e `$18C = $01`, `$18D = $00`. O decremento é `sbcd` encadeado
  (`lea $18B,a0 / lea $18D,a1 / sbcd -(a1),-(a0)` duas vezes: primeiro `$18A −= $18C`, depois
  `$18B −= $18D` com o empréstimo), portanto **desce de 1 em 1**: 900, 899, 898 …
- O ritmo é `g_countdown_rate` (`$10007B`) frames por unidade. O **único escritor que a
  desmontagem resolve** é a word `move.w (a0),$7A(a5)` em `$0015C8`, que carrega a entrada de
  `bonus_msg_index_table` (`$00162A`, words `000A 000B 0009 0008`) escolhida por
  `(g_dswb & 3)`; e o **único leitor** é o `cmp.b $7B(a5),d0` de `$007FA2`. Ou seja:

  | DSWB cru (bits 0-1) | Bónus de vida | `$10007B` | Escudo dura |
  |---|---|---|---|
  | `$03` | 50 k/150 k/600 k/3000 k | 10 | 9 000 frames ≈ 150 s |
  | `$02` | 20 k/40 k/120 k/480 k/2400 k | 11 | 9 900 frames ≈ 165 s |
  | `$01` | 70 k/280 k/1400 k | 9 | 8 100 frames ≈ 135 s |
  | `$00` | 100 k/500 k | 8 | 7 200 frames ≈ 120 s |

  **O DIP de "bonus life" controla também a duração do escudo.** Não é conjectura sobre o que
  o código faz — é o que ele faz; conjectura seria dizer que é intencional. O nome
  `bonus_msg_index_table` no fragmento de símbolos é enganador: nenhum dos quatro valores é
  usado como índice de mensagem em lado nenhum que eu tenha encontrado, e `$100078`
  (`g_bonus_setting`) e `$10007A` nunca são lidos.
- `game_countdown_set_9` (`$007F44`) põe 900 no início de cada ronda (chamada por
  `game_round_begin`); `game_countdown_floor_3` (`$007F34`) repõe 300 se `$18B < 3`, e é
  chamada uma única vez, em `$003CB4`, no ramo de perder uma vida.
- O escudo **não desce** enquanto houver trilha em construção (`$100897 != 0`) nem enquanto
  `$100882` estiver aceso (o item de "congelar escudo", §11).
- O aviso vermelho dispara quando a word em `$18A` (lida big-endian, `$18A<<8 | $18B`) vale
  exactamente `$0002` — ou seja quando o contador passa por **200**. Abaixo disso (dígito das
  centenas < 2) a paleta pisca a cada tick, alternando `$F00` e `$000` em
  `PALETTE+$20A4/$20A6` (e nos espelhos `+$30A4/$30A6`).

A zero, `game_countdown_tick` liga `$100860`/`$861`/`$862`/`$86F`, envia o som `$1B` e entra
numa máquina de 5 estados em `g_timeout_state` (`$10086C`): 8 piscas de `$20` frames, som
`$01`, e daí para a morte do jogador.

**O que `$860`/`$861`/`$862` fazem** (resolve a dúvida 11 do documento anterior):
`game_task_gate_update` (`$020DD8`) reactiva as tarefas 0, 1 e 2 do escalonador todos os
frames e volta a pará-las se o flag correspondente estiver aceso — `$860` → tarefa 0
(padrão do chefe), `$861` → tarefa 1 (grupo de inimigos), `$862` → tarefa 2 (comum).
`g_timestop_active` (`$100883`) pára só a tarefa 0.

---

## 10. Limite de tempo e ritmo dos inimigos

`game_round_time_limit` (`$0081FE`) conta `g_round_frames` (`$100892`):

| Modo | Limite | ≈ a 60 Hz |
|---|---|---|
| jogo normal | `$2F70` = 12 144 frames | 202 s |
| demonstração (`g_demo_flag` b0) | `$1600` = 5 632 frames | 94 s |

Ao expirar, liga `g_round_over` (`$100890`), recarrega os parâmetros e dispara. A partir daí
`enemy_spawn_countdown` (`$008246`) decrementa `$100872` e, a cada zero, avança
`g_enemy_rate_index` (`$100871`) até ao máximo de `$F`, recarregando velocidade e intervalo e
disparando um tiro (`enemy_shot_fire`, `$009662`).

Os parâmetros vêm de dois sítios, escolhidos por `g_cchip_bank` (`$1008A8`):

- `enemy_rate_from_cchip` (`$008276`) — lê 6 bytes de `CCHIP_RAM+$20 + $871*6` (ver
  [`04-c-chip.md`](04-c-chip.md));
- `enemy_rate_from_table` (`$0082AE`) — `enemy_rate_table` (`$0082C8`, 16 registos de
  `{velocidade.w, intervalo.w}`, lidos do binário):

| Índice | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| velocidade → `$100876` | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 2 | 1 | 1 | `$FF` | `$FF` | `$FF` | `$FF` | `$FF` |
| intervalo (frames) | 384 | 336 | 288 | 240 | 192 | 144 | 96 | 48 | 48 | 48 | 32 | 96 | 72 | 48 | 24 | 3 |

**O que `$FF` significa** (resolve a dúvida 5 do documento anterior): não é uma recarga
enorme, é um **sentinela**. `g_enemy_speed` vai para `$5(a4)` e `$6(a4)` do tiro, e
`enemy_shot_update` (`$0094D8`) testa-o antes de decrementar:

```
loc_00951A:
        tst.b   $7(a4)                                                  ; $00951A
        bne.w   loc_00964C
        cmpi.b  #$FF,$6(a4)                                             ; $009522
        beq.w   loc_0095A8              ; caminho rápido: DOIS passos por frame
        subq.b  #$1,$6(a4)              ; caminho normal: um passo a cada $5 frames
        bne.w   loc_0095A6
```

`loc_0095A8` e `loc_0095F4` executam **dois passos completos por frame**, cada um com o seu
teste de fronteira e o seu teste de corte da trilha. A escada de velocidade é portanto
monótona: um passo a cada 3 frames → cada 2 → cada frame → dois por frame.

Com `$FF`, `enemy_shot_spawn_at_player` (`$009688`) acrescenta ainda `frame & 7` a `$16` e
`$1A` no nascimento (`$0096C2`), dispersando o ponto de partida.

---

## 11. Os itens

Os objectos fixos do nível (§12.3) transportam um "padrão" em `$E(a4)`, escolhido por
`enemy_pick_pattern` (`$007E2E`) e despachado em `loc_007DF4`. O padrão **é o item**:

| `$E(a4)` | Bloco | Efeito |
|---|---|---|
| 0 e 7 | `loc_00874A` | nenhum: movimento por omissão |
| 1 | `loc_0089CA` → `$0089E2` | `g_speedup_active` (`$10031A`) — 4 passos por frame (§4.3) |
| 2 | `loc_008934` → `$008952` | `g_shot_enabled` (`$100884`) — o jogador passa a disparar |
| 3 | `loc_008902` → `$008926` | `g_timestop_active` (`$100883`) com duração em `$10088E` — pára a tarefa 0 (chefe) |
| 4 | `loc_0088C6` → `$0088DA` | `g_killall_active` (`$100886`) durante `$C(a4)` frames |
| 5 | `loc_00889A` → `$0088B8` | `$100882` — **congela o escudo** (§9) |
| 6 | `loc_008784` → `$0087DA` | `g_shot_spread` (`$1008BF`) + `g_shot_enabled`; cancela primeiro qualquer item de padrão 2 já activo (`sub_0087A2`) |

Qual item cada objecto dá **não é fixo**: `enemy_pick_pattern` calcula
`índice = (g_obj_index_outer + (g_area_pct_target & $F)) mod 10` e lê uma de três tabelas de
10 bytes conforme o tipo do objecto (`$6(a4)`) e o modo:

| Tabela | Endereço | Quando | Conteúdo |
|---|---|---|---|
| A | `$007EBA` | tipos != 3 e != 9, em jogo | `05 02 03 05 05 01 05 01 05 05` |
| B | `$007EC4` | tipo 3, em jogo | `FF 05 04 02 01 FF FF 03 02 06` |
| C | `$007ECE` | atracção (`$100040 == 0` ou `$10004C != 0`), 6 entradas | `01 02 03 04 05 FF` |

`$FF` significa "sem item": põe `$10088D = 1` e o padrão fica 0. Em atracção o índice é
`g_obj_index_outer mod 6` (`loc_007E20`), o que faz o modo demo mostrar os cinco itens por
ordem.

---

## 12. As 16 rondas e os chefes

### 12.1 Os dois contadores

| Endereço | Nome | Formato |
|---|---|---|
| `$100198` | `g_round_index` | binário, 0..`$10` |
| `$100197` | `g_round_bcd` | BCD, começa em 1 |

`game_round_advance` (`$003B7A`) incrementa os dois e, se `g_round_index` não chegou a `$10`,
mostra a mensagem `$3D` (`"ROUND .."`) e o campo numérico `$13`. Ao chegar a `$10`,
`sub_003BC4` e `sub_003BE6` desviam para o guião de fim de jogo (`g_seq_step = $1E`).

### 12.2 Ronda → tipo de cenário → chefe

`task_init_round` (`$014648`) faz `g_level_type ($10110A) = round_script_order[g_round_index & $1F]`
e arranca `round_script_table[g_level_type]` na ranhura 0 do escalonador.
`round_script_order` (`$0146A8`) tem 17 words; `round_script_table` (`$0146CA`) 17 ponteiros.
**A ordem em que as rondas aparecem não é a ordem em que os guiões estão na ROM:**

| Ronda (`$198`) | "Area" | Tipo | Rotina de arranque | Ficheiro |
|---|---|---|---|---|
| 0 | 1 | 9 | `boss09_init` `$019F84` | `src/main68k/boss09.asm` |
| 1 | 2 | 0 | `boss00_init` `$018836` | `src/main68k/boss00.asm` |
| 2 | 3 | 2 | `boss02_init` `$021572` | `src/main68k/boss02_core.asm` |
| 3 | 4 | 7 | `boss07_init` `$01962E` | `src/main68k/boss07.asm` |
| 4 | 5 | 4 | `boss04_init` `$018BF8` | `src/main68k/boss04.asm` |
| 5 | 6 | 3 | `boss03_init` `$0228D2` | `src/main68k/boss03_twin_head.asm` |
| 6 | 7 | 10 | `enemy_boss10_init` `$025FC2` | `src/main68k/enemy_boss10_area7.asm` |
| 7 | 8 | 8 | `boss08_init` `$019BE0` | `src/main68k/boss08.asm` |
| 8 | 9 | 6 | `enemy_boss06_init` `$026F7C` | `src/main68k/enemy_boss06_area9.asm` |
| 9 | 10 | 5 | `boss05_init` `$0191C4` | `src/main68k/boss05.asm` |
| 10 | 11 | 13 | `enemy_boss13_start` `$027D70` | `src/main68k/enemy_boss13_area11.asm` |
| 11 | 12 | 12 | `enemy_boss12_init` `$01ADC4` | `src/main68k/enemy_boss12_area12.asm` |
| 12 | 13 | 1 | `enemy_boss01_init` `$024992` | `src/main68k/enemy_boss01_area13.asm` |
| 13 | 14 | 11 | `boss11_init` `$01A68C` | `src/main68k/boss11_parte1.asm` |
| 14 | 15 | 14 | `enemy_boss14_init` `$01B9CC` | `src/main68k/enemy_boss14_area15.asm` |
| 15 | 16 | 15 | `enemy_boss15_init` `$01BD9A` | `src/main68k/enemy_boss15_area16.asm` |
| 16 | — | 16 | `game_ending_script_maybe` `$014856` | `src/main68k/game_ending_script.asm` |

A coluna "Area" é a numeração usada nos nomes dos ficheiros do projecto (`..._area7.asm`) e é
simplesmente `ronda + 1`. Bate 15/15 nos ficheiros que a trazem no nome — o tipo 2 é o único
sem ficheiro com sufixo de área.

O tipo de cenário indexa mais duas tabelas paralelas: `off_020ECE` (teste de colisão do
chefe, 16 entradas) e `tbl_round_end_task` (`$020D98`, fim de ronda, 16 `dc.l`). Decodifiquei
a segunda sobre o binário: todas as entradas valem `$00028C10` **excepto a `[12]`, que é
`$0001B418`** — a área 12 tem uma cutscene de saída própria. O desmontador lê esta tabela
como código (uma fieira de `ori.b #$10,d2`), portanto na listagem ela aparece como
`sub_020D9A`; são dados.

**Confirmação cruzada agradável:** o caso especial dos dois inimigos grandes em
`vram_fill_prepare` (`cmpi.b #$5,$198(a5)`, `$005438`) cai na ronda de índice 5 = área 6 =
tipo 3, cujo ficheiro se chama `boss03_twin_head.asm`. As duas leituras foram feitas por
caminhos independentes e coincidem.

### 12.3 Os objectos fixos do nível

`lvl_place_static_objects` (`$0076B8`) lê a lista da ronda a partir da tabela de 17 ponteiros
em `$007752` e cria até 20 objectos (`$334(a5) = $14`) na tabela `$103000`, que tem 22
ranhuras de `$20` bytes. Cada registo são 3 words `{y, tile, x}`, terminados por `$FFFF`; o
tipo do objecto é `tile − $14E` e a cor da sprite é `tipo + $18`.

**Estas listas ocupam exactamente `$008A4A-$008D8B`** — os 834 bytes que a banda 02 tinha
marcado como "completamente por identificar" e que o desmontador ainda reporta como o maior
bloco sem classificação. Decodifiquei-as sobre `build/maincpu.bin`:

| Ronda | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12–16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ponteiro | `$8A4A` | `$8A70` | `$8A9C` | `$8AB6` | `$8AD6` | `$8B02` | `$8B52` | `$8BC0` | `$8C2E` | `$8CA8` | `$8D22` | `$8D6C` | `$7796` |
| objectos | 6 | 7 | 4 | 5 | 7 | 13 | 18 | 18 | 20 | 20 | 12 | 5 | 0 |
| tipos usados | 0,3 | 3,8 | 8 | 0,8 | 3,8 | 0,3 | 0,8 | 0,3 | 8 | 8 | 0,3 | 3 | — |

São 135 objectos ao todo, com apenas três tipos (0, 3 e 8). As rondas 12 a 16 partilham um
ponteiro para uma lista vazia (`$007796`, que é o `$FFFF` final da própria tabela de
ponteiros). As rondas 8 e 9 usam exactamente o máximo de 20.

### 12.4 Ganhar a ronda por envolvimento

`enemy_boss_engulfed_check` (`$00558E`), chamada uma vez por frame mas activa só quando
`g_frame_counter & 7 == 0` e `g_seq_mode == 3`, converte a posição do inimigo grande em
endereço de VRAM (mesma máscara e mesmo espelhamento de `vram_fill_prepare`) e testa a word:

```
        btst.b  #$7,(a0)                ; bit 15 aceso                  ; $0055D8
        beq.b   loc_005620
        move.w  (a0),d0
        andi.w  #$180,d0                ; bits 7 e 8 apagados
        bne.b   loc_005620
        addq.w  #$1,$3840(a5)           ; g_boss_engulf_frames
        cmpi.w  #$60,$3840(a5)
        bcs.b   loc_00561E
```

O pixel debaixo do inimigo grande tem de ser território conquistado, sem trilha e sem marca
de objecto, durante **96 medições seguidas** — como só se mede de 8 em 8 frames, são 768
frames, cerca de 12,8 s. Qualquer falha zera o contador. Cumprida a condição, arma
`g_stage_clear_pending` (`$103842`), os flags `$860`/`$861`/`$862`/`$86F` e
`g_stage_clear_hud` (`$103844`), que é o que faz aparecer o `"FANTASTIC ROUND CLEAR!"` a
piscar (§3.2). `game_stage_clear_delay` (`$004E86`) espera 110 frames e chama
`game_abort_to_attract` com `g_round_end_reason = 2`.

### 12.5 As cinco razões de fim de ronda

`g_round_end_reason` (`$100887`):

| Valor | Escrito em | Situação |
|---|---|---|
| 0 | `$0032B8` | 80,0 % atingidos com mais de um preenchimento |
| 1 | `$005DC6` | ronda 5: os dois inimigos grandes ficaram separados, com área ≥ 1,0 % |
| 2 | `$0032FC` / `$004EA2` | chefe destruído (`$10088C`) ou envolvido |
| 3 | `$0032EE` | 80,0 % atingidos **num único preenchimento** |
| 4 | `$005DD4` | separação dos dois inimigos grandes com área < 1,0 % |

`game_abort_to_attract` (`$0032BC`) — apesar do nome, é o **fim de ronda** — põe
`g_round_cleared = 1`, envia o som `$02` pela via directa, limpa a fila de som, desliga
`g_player_hit_enable`/`g_trail_hit_enable`, e põe `g_seq_mode = 5`, `g_seq_step = $E`.

### 12.6 O ecrã de fim de ronda

O passo `$E` do modo 5 é `game_round_run_frame` (`$003304`), que continua a desenhar o frame
e a correr as tarefas até `$10086B` ficar aceso; então cala o som e passa ao passo 0.

Passo 0 (`$0036B8`) carrega as cores de área e chama `txt_format_percent`; segue-se o par de
passos `$21`/`$22` (limpar sprites) e o passo 1 (`$0036C8`), que monta o ecrã.

**Razão 0 — o caso normal.** Mostra `$3F` (`"....%!!"`), `$40` (`"CONGRATULATIONS!"`), `$41`
(`"ROUND .. CLEAR"`), o número da ronda, `$42` (`"YOUR PERCENTAGE IS"`), as sete linhas
`$43..$49` (`"99.3% ... ...000PTS"` … `"99.9% ..."`) e `$4A` (`"BONUS ="`). As zonas variáveis
são preenchidas por `txt_draw_ram_string` (`$0031A6`) a partir de `txt_ram_string_table`
(`$0031E0`):

| Registo | Chars | Sprite | Ponteiro | Papel |
|---|---|---|---|---|
| 8 | 4 | `$0168` | `$100362` | a percentagem atingida, cor `$E` |
| 9…`$F` | 4 | `$01A0`…`$04E8` | `$100346`…`$10035E` | as sete percentagens da lista |
| `$10`…`$16` | 3 | `$01E0`…`$0528` | `$100366`…`$100378` | os sete bónus da lista |
| `$17` | 3 | `$05A0` | `$10037B` | o bónus escolhido (`$4B`, `"...000PTS"`) |

Depois entra num ciclo (passos 2 e 3) que faz a lista rolar. `sub_003864` (`$003864`) compara
os 4 bytes ASCII do topo da lista (`$100346`) com os da percentagem atingida (`$100362`)
como um `long` — comparação lexicográfica que funciona porque o formato é `"DD.D"` de
largura fixa — e, enquanto o topo for maior, desloca a lista e traz uma entrada mais baixa.

As duas escadas são lidas **para trás** a partir do fim:

- percentagem: 4 bytes ASCII a partir de `$003467 − 4·i` (`off_003467` = `"99.2"`);
- bónus: 3 bytes ASCII a partir de `$003410 − 3·i` (`percent_ladder_ascii` começa por `"120"`).

Decodificadas do binário, dão 22 degraus (i = 0..21) mais 7 pré-carregados por
`txt_format_percent` a partir de `str_percent_top` (`$0033A0`) e `bonus_points_ascii`
(`$0033BC`):

| % | 80,0 | 81,0 | 82,0 | 83,0 | 84,0 | 85,0 | 86,0 | 87,0 | 88,0 | 89,0 | 90,0 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| bónus (×1000) | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |

| % | 91,0 | 92,0 | 93,0 | 94,0 | 95,0 | 96,0 | 97,0 | 98,0 | 99,0 | 99,1 | 99,2 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| bónus (×1000) | 22 | 24 | 26 | 28 | 30 | 35 | 40 | 50 | 100 | 110 | 120 |

| % | 99,3 | 99,4 | 99,5 | 99,6 | 99,7 | 99,8 | 99,9 |
|---|---|---|---|---|---|---|---|
| bónus (×1000) | 130 | 140 | 150 | 200 | 250 | 300 | 500 |

O pagamento é feito em `sub_003A0E` (`$003A0E`): os três caracteres do bónus escolhido
(`$10037B`/`$37C`/`$37D`) são convertidos em BCD, com os dois últimos a formar o byte alto do
somando e o primeiro (se não for espaço) a ir para `$10019B`. Um bónus `"120"` produz o
somando BCD `$01 $20 $00` = 12 000 guardados = **120 000 pontos no ecrã**.

**Razões ≠ 0.** O passo 1 mostra `$5A` (`"BONUS"`) e:

| Razão | Mensagens | Bónus pago em `sub_0037CA` |
|---|---|---|
| 1 | `$5B` `"SEPARATE ROUND CLEAR!"` + `$5C` `"10000 PTS!!"` | `$1000` = 10 000 |
| 2 | `$5D` `"SPECIAL ROUND CLEAR!"` + `$5E` `"100000PTS!!"` | `$1000` + `$9000` = 100 000 |
| 3 e 4 | `$5D` + `$5E`, e ainda `$6D` `"1000000PTS!!"` na mesma ranhura de sprite | `game_award_1000000` = 1 000 000 |

O ramo é literalmente:

```
loc_0037F8:
        cmpi.b  #$3,$887(a5)            ; g_round_end_reason            ; $0037F8
        bcs.b   loc_003806
        bsr.w   game_award_1000000                                      ; $003800
        bra.b   sub_003824
loc_003806:
        move.w  #$1000,d0                                               ; $003806
        bsr.w   game_add_score
        tst.w   $3B0(a5)                ; g_fill_flag_dead ($1003B0)
        bne.b   loc_00381C
        cmpi.b  #$1,$887(a5)
        beq.b   sub_003824              ; razão 1 fica-se pelos 10 000
loc_00381C:
        move.w  #$9000,d0
        bsr.w   game_add_score
```

Repare-se que a razão 4 (separar os dois inimigos grandes **antes** de conquistar 1 % da
área) paga um milhão, enquanto a razão 1 (a mesma separação, mas já com área conquistada)
paga dez mil.

`g_fill_flag_dead` (`$1003B0`) é **limpo em `$005434` e não é escrito em mais lado nenhum**;
além disso cai dentro da faixa `$100300-$103AFF` que `util_clear_work_ram` (`$0005AC`) zera.
O ramo que ele guarda é portanto morto na prática.

**Última ronda.** `sub_0039CA` põe `g_anim_frame` (`$10004E`) a 1 quando
`g_round_index >= $F`, o que encaminha `sub_003A0E` por três estados extra: mensagem `$6A`
(`"+1000000PTS"`), mensagens `$6B`/`$6C` (`"TOTAL ......."` / `"PTS"`) com a pontuação
copiada para `$10040C..$100412`, 16 piscas, e finalmente `$10019B = $10` com `d0 = 0` — um
somando BCD de `$10 $00 $00` = **1 000 000 de pontos** — antes de pagar também o bónus de
área.

### 12.7 Preparar a ronda seguinte

`game_round_begin` (`$003B48`, passo 8 do modo 5): `VIDEO_MASK = $000F`,
`util_clear_work_ram`, escudo a 900, zera `g_fill_pixel_count`, `g_area_pct_shown`,
`g_area_pct_target` e `g_fills_done`, limpa `g_demo_flag` e guarda o byte baixo da pontuação
em `g_score_at_round_start` (`$10019F`). Segue-se `game_round_advance` (passo 9) e os pares
pedido/espera de VRAM (passos 10–13) até `sub_003BE6` devolver o controlo ao modo 2.

---

## 13. O que não sabemos

1. **A entrada [1] da tabela `$00055E`.** Vale `$0000`, logo aponta para a própria tabela;
   executá-la seria interpretar `00 18 00 00` como código. Ou `g_seq_mode` nunca vale 1 no
   estado 2, ou a tabela tem outra forma. As entradas 0, 2, 3, 4 e 5 estão confirmadas.

2. **Os passos 1 e 2 do modo 2** (`$000900`/`$00090C`) entram no editor de inimigos de
   desenvolvimento. Não encontrei nenhuma escrita de `g_seq_step = 1` que aconteça com
   `g_seq_mode = 2`; a única escrita de `$24(a5) = 1` que existe (`$000610`) pertence ao modo
   0. Como as duas máquinas partilham `g_seq_step`, não posso excluir que uma transição
   deixe o valor 1 lá dentro. Não é código morto provado — é código que não sei alcançar.

3. **A correcção do percurso do preenchimento em fronteiras difíceis** (§5.9), e se o
   `bra *` de `$005E50` é alcançável.

4. **O bónus de `+0,6 %` ao sexto preenchimento.** A aritmética fecha exactamente (§6.1) e
   isso é forte, mas continua a ser inferência: não vi um comentário nem um teste.

5. **`g_difficulty` (`$10003A`).** É lido dos DIPs em `$0015B0` e o **único consumidor no
   68000** que encontrei é `game_init_hiscore_table` (`$00187A`), que escolhe uma das quatro
   tabelas de recordes por omissão. Ou o interruptor de dificuldade só muda a tabela de
   recordes, ou o efeito passa pelo C-Chip (que fornece a tabela de ritmos) e não pelo 68000.
   Não consigo decidir sem a ROM interna de 4 KB do C-Chip.

6. **O nome de `bonus_msg_index_table` (`$00162A`).** Provei o que a tabela faz (§9) e provei
   que `$100078` e `$10007A` não são lidos, mas não sei se `$10007B` foi *pensado* como
   ritmo do escudo ou se o autor reaproveitou um índice de mensagem. Um escritor indirecto
   via `a0` sobre `$10007B` escaparia à minha varredura, que só resolve deslocamentos de A5.

7. **`$1008C0`/`$1008D0`/`$1008E0`.** Os símbolos fundidos chamam-lhes `g_player_shot_0..2`
   e a `$102110`/`$102112` `g_shot_hit`/`g_shot_hit_count`, o que torna coerente a subtracção
   de vida ao chefe em `$020EB0`/`$020EC2`. Mas a banda 05 leu os mesmos endereços como
   "itens apanhados". Não reabri a questão; fica a nota de que as duas leituras existem.

8. **Bit 4 da word de VRAM.** Não encontrei produtor nenhum. Continua "?" como no
   `HARDWARE_GROUND_TRUTH`. O mesmo vale para o bit 7 de `$10005B`, que os chefes 12/14/15
   testam e que o MAME devolve sempre a 0.

9. **Que gráfico corresponde a cada tipo de objecto fixo** (0, 3 e 8) e, portanto, que
   aspecto tem cada item da §11. Sei que padrão dá que efeito e sei que tabela escolhe o
   padrão; não associei tipo → sprite → item visível.

10. **As duas ranhuras extra de `$103000`.** `lvl_place_static_objects` enche no máximo 20,
    mas `enemy_update_all` e `spr_draw_table_3000` percorrem 22. Não determinei quem usa as
    duas últimas.

11. **Qual dos dois eixos se chama "x" no monitor** é uma convenção, não um facto. Verifiquei
    a relação com o endereço de VRAM (`x*2 + y*1024`) e com a moldura do campo; por o ecrã
    ser ROT270, o "x" deste documento é a vertical do monitor. Ver a dúvida 4 da banda 03 em
    [`ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md).

---

## Ver também

- `src/main68k/irq_vblank_dispatch.asm` — o handler e a tabela de estados de topo.
- `src/main68k/game_screen_sequence.asm`, `game_play_script.asm` — os níveis 2 e 3 da
  máquina de estados.
- `src/main68k/game_frame.asm` — `vram_frame_draw_all` e `game_ingame_tick`.
- `src/main68k/player_control.asm` — entradas, `player_update`,
  `player_move_and_draw_trail`, `vram_fill_prepare` (`$004FAE-$0053E5` e `$005488-$005625`).
- `src/main68k/vram_fill_arm.asm`, `vram_fill_walk_helpers.asm`,
  `vram_area_fill_engine.asm`, `vram_fill_geometry.asm` — o preenchimento.
- `src/main68k/player_trail_reset_blk.asm` — `player_trail_reset`, onde o motor cai.
- `src/main68k/vram_addr_math.asm` — `hud_area_pct_step` e a aritmética de endereços.
- `src/main68k/game_score_and_bonus.asm`, `data_bonus_life_table.asm` — pontuação e vidas.
- `src/main68k/game_abort_and_percent_text.asm`,
  `game_roundclear_dispatch_and_pal.asm`, `game_roundclear_script.asm` — fim de ronda.
- `src/main68k/game_countdown.asm` — o escudo e o limite de tempo.
- `src/main68k/enemy_patterns.asm` — os corpos dos padrões, isto é, os itens.
- `src/main68k/task_scheduler.asm` — as co-rotinas e as tabelas das rondas.
- `src/main68k/sprite_dispatch.asm` — objectos fixos do nível e as tabelas de sprites.
