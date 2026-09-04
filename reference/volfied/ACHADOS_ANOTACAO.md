# Achados da fase de anotação

Consolidação do que os agentes de anotação descobriram ao ler o código real.
Cada secção vem de um agente que trabalhou uma faixa de endereços ou um subsistema.

> Material de trabalho: é a matéria-prima de `docs/`. O que estiver marcado como dúvida
> continua por resolver — não o cite como facto.


---

## Fonte: `/Users/flaviocoutinho/development/qiqix/symbols/fragments/banda00.sym`

Rotinas nomeadas: **100** · incertas: **88**

### Descobertas

## Estrutura de execução

O jogo corre quase todo dentro do IRQ de VBLANK. O laço principal em `$00161C` é só `bsr $005CD6 / bra`. O `irq4_vblank_handler` faz, por esta ordem: lê VIDEO_STATUS para `$10005A`, chama `vblank_service` (paleta), chama `inp_tilt_check`, e despacha uma máquina de estados de TRÊS níveis:

- `$100020` = estado de topo: **0 = atracção, 1 = moeda inserida / carregar START, 2 = a jogar, 3 = tilt → reboot**. Tabela em `$00046E`.
- `$100022` = sub-modo, com uma tabela por estado de topo.
- `$100024` = passo dentro do sub-modo.
- `$100038` = atraso em frames. Os três despachantes começam sempre por `tst.w $38(a5) / subq / rts`, ou seja é assim que o guião pausa.

O estado 3 (`$000E2E`) recarrega SSP e PC do vector de reset e salta — reinício por software, usado depois do TILT.

## Dois jogadores = duas páginas de VRAM

Esta é a descoberta que mais explica o hardware. A VRAM tem 2 telas de 256 KB e o jogo usa **uma por jogador**: `$10006A` guarda `$400000` para o P1 e `$440000` para o P2, `vram_select_page` põe o bit 0 de VIDEO_CTRL a partir de `$100036` (jogador activo), e `game_switch_to_player1/2` trocam 128 bytes de contexto entre `$100080` (P1), `$100100` (P2) e `$100180` (activo). Num jogo de 2 jogadores cada um mantém literalmente a sua área conquistada intacta na sua própria página enquanto o outro joga.

## VIDEO_MASK e as duas "imagens" da camada bitmap

O formato de VRAM do ground truth (bit 15 = selecciona imagem A/B, bits 0-3 = imagem A, bits 9-12 = imagem B) é usado como **duplo buffer por pixel** nas transições de ecrã. O padrão repete-se em 8 sítios: `VIDEO_MASK = $000F` (só escreve na imagem A) → desenha → `$FFF0` (só imagem B + bit de selecção + bits de paleta) → `$FFFF` (tudo). O pedido de transição é o byte `$100804`: quem quer uma transição escreve 3/4/5/6/7 e fica a fazer `tst.b $804(a5)` até voltar a 0. O handler de VBLANK salta o despacho de estado enquanto `$804 == 2`.

## Paleta

`pal_rgb444_to_xbgr555` (`$001042`) converte `$0RGB` de 4 bits para xBGR_555 com `>>7`, `<<2` e `ror.w #5`. O mapa da paleta fica assim:

| Bytes | Entradas | Uso |
|---|---|---|
| `$500000-$500FFF` | `$000-$7FF` | camada bitmap, imagem A, 8 bancos de 256 |
| `$501000-$501FFF` | `$800-$FFF` | camada bitmap, imagem B |
| `$502000-$503FFF` | `$1000-$1FFF` | sprites, bancos de cor `$100-$1F0` |

Os bancos 1-7 (e 9-15) da camada bitmap são preenchidos com **uma cor sólida cada** (`pal_load_area_colors`) — são exactamente as cores lisas das áreas conquistadas do Qix.

## sprite_ctrl nunca é programado

As 5 escritas em `$700001` usam o d0 que calhar estar no registo (no VBLANK é o d0 do código interrompido). O jogo compensa: **todas as rotinas de paleta de sprite escrevem o mesmo bloco de cores 16 vezes com passo `$200`**, cobrindo os 16 bancos possíveis de `sprite_colbank = 0x100 | ((sprite_ctrl & 0x3c) << 2)`. Não interessa o que está no registo, a cor sai certa à mesma. `$700001` funciona na prática como um strobe.

## Texto e números são sprites

Não há camada de tiles de texto: tudo passa pelo PC090OJ.

- `txt_draw_message` (`$001A9C`) lê uma tabela de **121 ponteiros** em `$001B2E`. Cada registo é `{offset na sprite RAM .w, attr .b, coordY inicial .b, coordX .w, chars..., 0}`. O tile é `char - $20`, o espaço salta o slot sem gastá-lo, o bit 7 do attr significa passo de 16 em vez de 8 e o bit 6 significa códigos de 16 bits (usado nos logótipos). Os índices `$35..$3B` levam `+$18` em X.
- `txt_draw_number` (`$00196C`) desenha contadores BCD a partir de 22 registos em `$0019EC` (`{nº dígitos, fonte, offset sprite .w, ponteiro RAM .l}`), com supressão de zeros à esquerda. A fonte alternativa (`flag=1`) usa tiles `$13E+d` excepto no último dígito.

Escrevi um descodificador destas duas tabelas em Python sobre `build/maincpu.bin` e ele produz as 121 mensagens legíveis e faz coincidir cada campo numérico com o buraco de pontos da mensagem correspondente (ex.: msg 43 `"1ST ......0    ..  ..."` tem o buraco em `$200078`, e o campo 6 é exactamente `spr=$0078`). Isso valida o formato, não só o palpite.

## A pontuação está guardada a dividir por 10

`$10019C..$10019E` são 3 bytes BCD com o **byte menos significativo no endereço mais baixo**. O ecrã mostra 6 dígitos **mais um `'0'` fixo colado à direita** (está literalmente nas strings: `"......0"`). Confirmação cruzada: `bonus_life_table` guarda 5000/15000/60000/300000 onde o MAME documenta 50k/150k/600k/3000k.

## Os DIPs chegam complementados

`sub_007372` faz `not.b d0` antes de guardar em `$10002C`/`$10002E`. Ou seja **o valor em RAM é o complemento de bits do que o MAME documenta**. Verificado exaustivamente contra `bonus_life_table`: os 4 conjuntos de 6 words batem 4/4 com `(~DSW) & 3`. Isto vale para toda a leitura de DIPs no resto da desmontagem.

## Vidas, rounds, bónus

- 16 rounds: `$100198` (binário, 0..$10) e `$100197` (BCD, começa em 1). Quando `$198` chega a `$10` o jogo pára de mostrar "ROUND nn" e de desenhar os ícones de vida.
- `game_add_score` faz a soma com `abcd` em 3 bytes, satura em 999999, e a cada passagem compara com `$1001B2` para dar vida extra (som `$08`, máximo 9 vidas) avançando o índice na `bonus_life_table`.
- `game_award_1000000` (`$003828`) dá 1.000.000 de pontos em 20 passos de 50.000 — é o bónus do "perfect/special clear" (msgs `"+1000000PTS"` e `"1000000PTS!!"`).
- A tabela de high scores por omissão depende da **dificuldade** (`$00191B`, 4 conjuntos de 20 bytes) e as iniciais por omissão são iniciais de gente da Taito: `"MTJ" "T.S" "TUK" "OKI" "V.P"`.

## Som

Três camadas: `snd_queue_command` (`$0004F4`, 59 chamadores) mete um byte numa fila de 7 slots em `$10031C`; `snd_drain_queue` tira um por frame no VBLANK; `snd_send_command` (`$000490`) faz o protocolo do PC060HA (porta 4, espera bit 0, porta 0, envia o par de nibbles). A guarda de "demo sounds" está nas duas camadas de cima: com DSWA b3 activo só toca se `$100040` (jogo a decorrer) for diferente de zero.

## Percentagem

Há duas representações: `$10018E-$10018F` (BCD, 3 dígitos, desenhada no HUD por cima de três glifos largos em `$2006A8`) e `$100192-$100193` que `txt_format_percent` converte para o ASCII `"DD.D"` do ecrã de fim de round. A escada de percentagens do bónus está em ASCII em `$003410` (`"80.0"` a `"99.2"`, lida para trás) com os montantes em `$0033BC`.


### Dúvidas em aberto

## 1. Polaridade do bit de cabinet (contradição com o MAME)

O `not.b` em `$0073E2` está provado (a `bonus_life_table` só bate com o complemento). Mas com essa inversão, `$10003C = 0` corresponde a `DSWA raw bit0 = 1`, que o `TAITO_MACHINE_COCKTAIL_LOC` do MAME documenta como **Upright**. E `spr_set_screen_flip` (`$000EB6`) faz exactamente o oposto:

```
$3E==0, $3C!=0 -> sempre orientação normal
$3E==0, $3C==0 -> P1 normal, P2 invertido   <-- comportamento de COCKTAIL
$3E!=0, $3C!=0 -> sempre invertido
$3E!=0, $3C==0 -> P1 invertido, P2 normal
```

Ou o macro genérico do MAME está com a polaridade trocada para este jogo (nunca foi verificado, é aplicado em bloco), ou há uma inversão a mais algures. Não consigo decidir sem ver o lado do Z80. Nomeei a variável `g_cabinet` e descrevi o comportamento observado em vez de afirmar "upright" ou "cocktail".

## 2. `$100052`

Recebe `$AA` no reset, `1` ao iniciar jogo, `2`/`3` ao entrar no round, `$E`/`$F` no game over, `$1F` no tilt. Parece um identificador de cena consumido por código fora da minha faixa. Ficou `g_scene_id_maybe`.

## 3. `sub_0004BA` (`$0004BA`)

Espera o bit 2 de `SOUND_COMM_B` e lê **duas** words de `SOUND_COMM` para d0/d1. É o único sítio na banda com essa forma, mas quem escreve `g_dswa`/`g_dswb` é `sub_007372` (banda 01), e o único chamador de `$0004BA` é `sub_013ED8` (auto-teste). Ficou `snd_read_two_words_maybe`.

## 4. Entrada `[1]` da tabela `$00055E`

A word vale `$0000`, ou seja aponta para a própria tabela. Ou `g_seq_mode` nunca vale 1 nesse estado, ou o meu desenho da tabela está errado (o desmontador só detectou 1 entrada; eu deduzi 6 a partir dos alvos plausíveis, incluindo dois `jmp` inline em `$00056A` e `$000570` que o desmontador partiu ao meio como "sub_00056E"). As entradas 0, 2, 3, 4 e 5 estão confirmadas.

## 5. `$00321E-$0032A7` e `$003C56`

Blocos que o desmontador leu como código mas que produzem instruções absurdas (`movep.l`, `btst.l d1,` truncado). São quase de certeza tabelas de saltos `dc.w` mal classificadas. Não nomeei nada aí; a SECTION chama-se `unclassified_003_21e`.

## 6. Semântica exacta de `vram_ctrl_strobe` (`$00144E`)

Limpa e volta a pôr os bits 3 e 6 de VIDEO_CTRL uma vez por frame, através da sombra `$100028`. Como VIDEO_STATUS (mesmo endereço, leitura) devolve os bits de colisão 5 e 6, o meu palpite é rearme dos latches de colisão — mas o MAME devolve `$60` fixo na leitura, portanto não há forma de confirmar sem hardware ou sem uma emulação mais fiel. Deixei o nome descritivo (`strobe`) e a hipótese no comentário.

## 7. Os campos `$18A` e `$18C` do contexto do jogador

`game_init_player_context` põe `$18A = 9` e `$18C = $100` mas não encontrei quem os lê dentro da banda. Ficaram sem nome.

## 8. As 82 rotinas sem nome

São sobretudo passos individuais das máquinas de estado (`$003502-$003C35`, 30 entradas) e animadores de objectos em `$004000-$004518` que dependem de campos do registo em `$100800` cuja semântica está definida em código da banda 01 (`$004B9C`, `$004C7E`, `$005122`). Preferi deixá-las como `sub_XXXXXX` a inventar nomes a partir do que elas escrevem.


---

## Fonte: `/Users/flaviocoutinho/development/qiqix/symbols/fragments/banda01.sym`

Rotinas nomeadas: **94** · incertas: **15**

### Descobertas

SEMÂNTICA DOS BITS DA WORD DE VRAM (resolve dois "?" do HARDWARE_GROUND_TRUTH)
Toda a lógica do jogo cabe em 5 bits da word de VRAM:
  bit 15 — pixel conquistado / visível (imagem B). É o que o MAME lê como `p & 0x8000`.
  bit  8 — célula ocupada por objecto fixo do nível (bloco 15x15). sub_004F42 põe, sub_007902 tira.
  bit  7 — trilha em construção. sub_0051B6 põe; sub_004C7E apaga tudo com `andi.w #$7F7F`.
  bit  6 — parede / fronteira de área já conquistada. A moldura do campo é escrita com $8040 (bit15+bit6).
  bit  5 — bit de RASCUNHO do algoritmo de preenchimento (marcador de varrimento). É exactamente o bit que o MAME documenta como "----------x----- ?". Não é gráfico nenhum: é estado temporário do fill.
  A máscara $1C0 (bits 6,7,8) é usada em sub_006038 como "célula ocupada".

GEOMETRIA EXACTA
  vram_addr_from_xy ($004F7E): a0 = g_vram_page + x*2 + y*1024. Logo 512 words por linha, 256 linhas, $40000 bytes por página. vram_xy_from_offset ($004F66) é a inversa exacta com máscara $3FFFE (18 bits) — confirma uma página de 256 KB.
  A moldura do campo é desenhada literalmente por sub_0071A4: $403C26..$403E5C = linha y=15, x=19..301; $43BC26 = y=239. Colunas x=19 e x=301 de y=15 a y=239. Isto bate certinho com os limites de movimento em sub_0051B6 (`cmpi.w #$13,d4` / `#$12E` / `#$F` / `#$F0`).
  Fora da moldura há mais 3 colunas em x=16..18 e 2 em x=302..303, 240 linhas a partir de y=8 — coincide com "visível 8–247" do MAME.
  O flip de ecrã ($30(a5)==0) é x' = 304 - x e y' = 240 - y (sub_008DFA/sub_008E0C usam $13F e $FF menos $F).

A PERCENTAGEM: 63 PIXELS = 0.1 %
  O motor de fill conta em $100186 (long) cada pixel a que põe o bit 15. No fim faz `divu.w #$3F` e soma o quociente a $100190, guardando o resto de volta na word baixa do contador. Logo 63 px = 0.1 %, 63000 px = 100 % — consistente com o campo útil de 283x225.
  $100190 (0..1000, décimos de %) é convertido para BCD em $192/$193, e sub_003340 formata-o como "NN.N" (o '.' é escrito literalmente em $364). O jogo mostra a área com uma casa decimal.
  A vitória é `cmpi.b #$8,$193(a5)` em $0032A8 → 80.0 %. Confirma a regra dos 80 % com o número exacto.
  A percentagem mostrada ($18E/$18F) sobe passo a passo até à alvo, e cada passo dá pontos: +1 por 0.1 %, +$10 por 1 %, +$100 por 10 % (BCD, via sub_00302E). Desenhar a trilha dá ainda 1 ponto por cada 4 pixels.

O ALGORITMO DE PREENCHIMENTO
  1. sub_0053E6 arma o fill: guarda o passo de direcção da trilha e o endereço de VRAM do inimigo grande ($101126/$101128). Só no nível 5 guarda também um segundo inimigo grande ($10209C/$10209E).
  2. sub_0060E0 lança um raio a partir do inimigo grande e conta as fronteiras que atravessa (bits 6 e 7). A PARIDADE dessa contagem decide qual dos dois lados da trilha é o "de fora" — é um teste de ponto-em-polígono clássico. Nunca se preenche o lado onde está o inimigo grande.
  3. No nível 5, se os dois inimigos grandes caírem em lados opostos, o fill é abortado e a fase termina (sub_0032BC).
  4. Duas passagens: uma converte a trilha (bit 7) em parede (bit 6) contando os pixels; outra pinta perpendicularmente (sub_00601E) pondo o bit 15 até bater em pixel já pintado.
  5. Antes do fill desmarcam-se os blocos 15x15 dos objectos do nível (sub_0075F6) e depois remarcam-se (sub_00762A) — os objectos cuja célula ficou conquistada são destruídos. É assim que os itens/instalações do nível são "apanhados" ao conquistar área.

MORTE E TRILHA
  O jogador guarda uma lista de vértices em $1008A0 (4 bytes por vértice); o primeiro vértice ($1008A4/$1008A6) é o ponto onde a trilha começou. Ao morrer, sub_004C7E anda pixel a pixel desde a posição actual até esse ponto seguindo as marcas de bit 7 e limpando bits 15 e 7 — apaga a trilha exactamente pelo caminho que ela fez, sem guardar bitmap nenhum.
  A morte também gera 16 fragmentos (tabela de 16 objectos x $20 bytes em $103400) com tile $53.

VITÓRIA POR ENVOLVIMENTO
  sub_00558E, de 8 em 8 frames, testa o pixel debaixo do inimigo grande: se tiver bit 15 e não tiver bits 7/8 durante $60 medições seguidas, arma a sequência de fase ganha ($103842/$103844) — ou seja, cercar o inimigo grande com área conquistada também ganha o nível.

MOEDAS E C-CHIP
  A tabela de moedas está em $03FFBE (Japão) e $03FFDE (resto), indexada por DSWA & $30 e DSWA & $C0; cada entrada é um long = (moedas necessárias : créditos dados). Vai para $100000/$100002 e $100004/$100006 — repare-se que $100000 é ao mesmo tempo a base de A5 e um campo de dados real.
  sub_0066CC pulsa os contadores mecânicos com 4 frames alto + 4 baixo no byte $10001E, escrito em CCHIP_RAM+$11 ($F00011): b4/b5 = contadores, b6/b7 = lockouts. Confirma a nota da saída PB do C-Chip. Com 9 créditos o lockout liga.
  Se uma moeda ficar presa 32 frames, o jogo limpa o vídeo, mostra a mensagem $28 e faz `bra *` — trava de propósito (ecrã de COIN ERROR).

DIP SWITCHES VIA Z80
  sub_007372 é a prova da nota do ground truth: envia $EE, pede a porta $A, lê dois nibbles de SOUND_COMM, inverte, guarda em $10002C (DSWA); repete com a porta $B para $10002E (DSWB); envia $EF. É uma máquina de estados de 4 passos em $100060, chamada do reset.

BLITTER DA CAMADA BITMAP
  Os fundos são mapas (cols, rows, códigos de tile) e cada tile é 8x8 a 4 bpp, 32 bytes, em $080000 + tile*32. O blitter escreve 2 bytes por pixel e salta $3F0 no fim da linha (=$400 = 1024). Há quatro variantes: normal / espelhada (para o flip) e "imagem A" (nibble nos bits 0-3) / "imagem B" (`ror.w #7` + `andi.w #$1E00`, nibble nos bits 9-12).

NÚMEROS DO JOGO
  16 níveis ($100198 incrementa e compara com $10). A tabela de recordes tem 5 entradas de 3 bytes BCD, 5 bytes de "ronda atingida" e 5 nomes de 3 letras. O anel de caracteres da entrada de iniciais é A..Z, '.', '!', espaço. O ecrã de recordes desiste após 600 frames sem input e termina aos 2880 frames.
  Só os níveis 0..11 têm objectos fixos (as entradas 12..15 da tabela de ponteiros apontam todas para uma lista vazia).
  As velocidades dos objectos vêm de tabelas de 56 pares (dx,dy) — uma volta completa em 56 direcções, com 3 anéis de velocidade.


### Dúvidas em aberto

1. $103FFF / sys_data_out_tick ($006522). Todos os frames esta rotina escreve um byte em $103FFF (o último byte da RAM principal, acima do topo da pilha) conforme um comando em $100052, e no comando $20 emite 5 bytes com a pontuação BCD e o número da ronda. NENHUM ponto do código do 68000 lê $103FFF. Não consigo dizer para quem é: pode ser um resto do sistema de desenvolvimento da Taito (como os vectores $0011xxxx), um porto de estatísticas/bookkeeping, ou um artefacto de emulação de placa. Deixei o nome com descrição factual e sem inventar consumidor.

2. sub_004DB6 / sub_004DD4 ($84D, $84E, $850, $85C, $85E). São claramente contadores que ao expirar levantam flags, e os endereços caem dentro da estrutura do jogador ($4D..$5E de a4, os mesmos campos que sub_005CD6 inicializa a $100 depois de um fill). Suspeito fortemente de temporizadores de power-up/arma, mas não fui à banda que trata das armas para confirmar, por isso ficaram com _maybe.

3. sub_004F30 ($13E em SPRITE_RAM+$6B4) e sub_004C30 ($180 na sprite 1 conforme um bit do contador de frames). Percebo o mecanismo mas não vi o sprite renderizado, por isso não sei se é o símbolo "%", um dígito, ou o piscar de invulnerabilidade. Ambos com _maybe.

4. $100197 vs $100198. $198 é seguramente o índice de nível (0..$F, indexa paletas, fundos e objectos). $197 é outro contador, saturado em $16 (22) ao gravar na tabela de recordes, e usado no "payload" de saída de dados. Chamei-lhe g_round_number, mas não determinei se conta voltas ao ciclo de 16 níveis ou algo mais.

5. sub_005C32 ($005C32-$005C89) está no digest como rotina mas é na prática um bloco de ramos do preenchimento, alcançado por `bne.w loc_005C32` de dentro de sub_005CD6. Dei-lhe nome de FUNC para não deixar buraco, mas o corte de rotina do desmontador está errado ali: $005C32-$006121 e $005CD6-$005FDF são um só motor.

6. $0058FE, $0059B4 e $005196 são dados desmontados como código (movep, btst.l com operandos absurdos). Marquei-os como DATA mas só inferi o formato de $005196 (4x8 bytes de parâmetros de direcção) pela rotina que os lê.

7. $100000 tem dois significados legítimos ao mesmo tempo (base de A5 e primeiro campo da tabela de moedas). O ficheiro principal já tem `RAM 100000 g_base`; as minhas RAMVAR g_coin1_units/g_coin1_credits sobrepõem-se a ele de propósito. Quem juntar os fragmentos tem de decidir como representar isso — deixei nota no cabeçalho da secção.

8. Não investiguei $10031A, $100235, $100869 além do mecanismo local, nem a semântica dos flags $860/$861/$862/$86F que a sequência de vitória levanta.


---

## Fonte: `/Users/flaviocoutinho/development/qiqix/symbols/fragments/banda02.sym`

Rotinas nomeadas: **91** · incertas: **17**

### Descobertas

## 1. O jogo corre sobre um escalonador cooperativo de 4 tarefas (co-rotinas)

Bloco de tarefa: $40 bytes, 4 slots em $101000. Campos: +$00 activo ($FFFF), +$02 frames de espera, +$04 endereco de retoma, +$08 contexto d0-d6/a0-a4 (48 bytes de movem.l).

Uma tarefa devolve o controlo com o idioma `move.w #frames,d7 / lea proximo_passo(pc),a6 / rts` — o escalonador guarda d7 no campo de espera e a6 no campo de PC. Isto explica por que razao dezenas de "rotinas" da listagem parecem nao ter chamador nenhum: sao passos de script, entrados por `jsr (a6)` a partir de um ponteiro guardado em RAM. Toda a seccao $014856-$0149D9 (e presumivelmente $015xxx-$028xxx) e' escrita neste estilo.

API: task_start($01470E), task_stop($014724), task_set_delay($01472E), task_set_active($014738), task_slot_ptr($014744).

## 2. Ha' 17 "rondas": 16 jogaveis + 1 script final

`task_init_round` ($014648) faz `$110A(a5) = round_script_order[$198(a5) & $1F]` e arranca `round_script_table[$110A]` no slot 0.
- round_script_order ($0146A8) = 17 words: 9,0,2,7,4,3,10,8,6,5,13,12,1,11,14,15,16 — ou seja a ordem em que as rondas aparecem nao e' a ordem em que os scripts estao na ROM.
- round_script_table ($0146CA) = 17 dc.l. A entrada [16] e' $014856, que so' e' alcancavel na 17ª ronda — quase de certeza a sequencia de fim de jogo.

## 3. Semantica de dois bits da VRAM (o coracao do Qix)

`sub_004F7E` da' `endereco = $6A(a5) + x*2 + y*$400`, confirmando 512 words por linha.
- **bit 15** da word = territorio conquistado (a "imagem B" do HARDWARE_GROUND_TRUTH). `vram_box_hits_filled` ($0086FC) percorre o perimetro de uma caixa de 14x14 a testar este bit para decidir se um inimigo pode nascer/andar ali. `sub_004F42` poe os bits 15 e 8 num bloco 15x15; `vram_erase_box` ($007902) limpa exactamente os mesmos dois bits.
- **bit 7** da word = pixel da trilha em construcao. Duas confirmacoes independentes: `spark_follow_trail` ($009DCA) anda pela trilha a testar `btst.b #$7,$1(a0)` e muda de direccao quando o bit desaparece; `enemy_shot_update` ($0094D8) usa o mesmo teste para detectar que um tiro cortou a trilha.

## 4. Como o jogo mata o jogador

Cadeia completa: um tiro acerta na trilha -> `$851(a5)=1` e `$852(a5)=endereco na VRAM` -> `spark_spawn_first` ($0099AC) converte esse endereco em (x,y) com sub_004F66 e guarda em `$856/$858(a5)` -> nascem 8 "faiscas" em $103300 que percorrem a trilha ate esse ponto -> `spark_update` ($009BC4) mata o jogador a menos de 2 px. Em paralelo `enemy_shot_update` mata-o directamente a menos de 4 px. O golpe final e' sempre `$805(a5) = $FE`.

## 5. Os tiros do inimigo nascem fora do ecra, apontados ao jogador

`enemy_shot_pick_dir` ($00988E) escolhe um de 12 vectores conforme o quadrante do jogador (d0<$A0, d1<$80) com uma rotacao dada por `$68(a5)`. `enemy_shot_backtrack` ($0098CC) recua 2*(dx,dy) a partir da posicao do jogador ate sair de x=[8,$138) y=[6,$FA), e depois nega o vector — ou seja, calcula onde o tiro tem de nascer fora do ecra para passar exactamente pelo jogador. Em modo demo ($40(a5)==0) a direccao e' fixa.

Area de jogo em coordenadas cruas: x=[$18,$128) e y=[$16,$EA) para inimigos ($00841A); x=[8,$138) y=[6,$FA) para o nascimento de tiros.

## 6. Motor de metasprites e flip de ecra por software

`spr_draw_obj` ($008E46, d0 = id 0..$FF) le a tabela em $008E5E e emite as 4 words que o PC090OJ espera (attr / y / code / x, confirmado contra reference/mame/pc090oj.cpp). Registo: word attr (bit 15 flipy, bit 14 flipx, bits 0-3 cor, bit 8 = "espelhar o deslocamento"), byte dy, word dcode somado a $2(a4), byte dx; termina em attr $FFFF.

`$33C(a5)` escolhe onde esta a posicao do objecto: 0 -> $16/$1A (objectos "grandes": jogador, faiscas, tiros), 1 -> $8/$4 (objectos de $20 bytes: inimigos). `spr_draw_obj_xy8` ($008E3E) e' so' o mesmo com a flag a 1.

O flip de ecra e' feito em software com a **mesma formula do MAME**: `x = $13F - x - $F` e `y = $FF - y - $F` (isto e', 320-x-16 e 256-y-16), controlado por `$30(a5)`.

Para esconder um sprite, o jogo escreve **y = $180** (fora da area util, tratado como negativo pelo hardware). `spr_clear_to_end` ($0145D0) enche a RAM de sprites com longs $00000180.

## 7. Auto-teste e TEST MODE completos, com o teste de ROM morto

$013EC2 soma todos os longs de $000000-$00FFFF em d2 — e **nunca compara d2 com nada**, saltando sempre para o teste de RAM. Consequencia: $013ED8 ("ROM CHECK ERROR") ficou inalcancavel. O teste de RAM (escreve/rele $FFFFFFFF em $100000-$103FFF e em VRAM $400000-$47FFFF) e o teste de som (envia $F0 e cada bit isolado, le o eco com sub_0004BA) continuam vivos.

O ecra de TEST MODE nao usa camada de texto nenhuma: e' tudo sprites. `txt_draw_string_sprites` ($014556) emite um sprite por caractere com `code = char - $20`, avanca 8 em y, salta o espaco e termina em $FF. Os rotulos vivem em registos `{word y, word x, texto..., $FF}` a partir de $0143B4 — isto explica os "x", "p", "`", "P", "@" espurios no inicio de algumas strings do digest: sao o byte baixo da coordenada x.

`test_dsw_to_hl` ($0142D8) converte os 8 bits de um DIP em 8 caracteres 'H'($48)/'L'($4C), o que casa com os rotulos "L:ON" / "H:OFF".

## 8. Ha' um editor de inimigos de desenvolvimento deixado na ROM

Modo `$22(a5)=2` (tabela off_00055E) tem a sua propria tabela de estados em off_000888. Estado 1 = `enemy_dev_placer_init` ($007798): desenha uma grelha de linhas na VRAM, cria um cursor e poe 3 icones em SPRITE_RAM+$600. Estado 2 = laco em loc_0078D8. O cursor anda de 2 ou 4 px de 8 em 8 frames; com x<8 a faixa de y escolhe um dos 3 tipos de inimigo ($6(a4)=0/3/8); no flanco de largar o botao coloca ou remove um inimigo, mantendo um contador BCD em $336(a5) que e' redesenhado no campo $12 do HUD. Com o cursor em x>=$12E sai para o estado 3.

Nao encontrei nenhum sitio no jogo normal que ponha `$24(a5)=1`, por isso e' provavelmente inacessivel numa PCB de producao.

## 9. Ritmo de aparecimento vindo do C-Chip

`enemy_rate_from_cchip` ($008276) escreve `$8A8(a5)` em CCHIP_REG+$401 (banco), espera 3 nops, e le 6 bytes de `CCHIP_RAM+$20 + $871(a5)*6` para tirar velocidade e intervalo. Ha' um caminho alternativo puramente em ROM (`enemy_rate_from_table`, $0082AE, tabela em $0082C8) escolhido por `$8A8(a5)`. E' um dos poucos sitios em que o C-Chip serve de tabela de dados e nao so' de leitura de entradas.

## 10. Os 41 KB de $009E7A-$013EC1 sao dados, nao texto

As 172 "strings" que o digest atribui a esta banda sao sequencias de words crescentes (codigos de tile) que o extractor de ASCII confunde com pares de caracteres imprimiveis. A estrutura real: tabela de 114 dc.l em $009E8A, lida em $007004 como **3 ponteiros por ronda** (`$198(a5)` ou `$8FE(a5)` x $C). Cada ponteiro aponta para um registo de $74 bytes = `{word modo ($0002 ou $0020), word $001C, 56 words de codigos de tile}`. sub_006FFC desenha os tres na VRAM em `$6A(a5)` + $4020 / $4040 / $4240 (linha 16, colunas 16/32/288) e `$30(a5)` troca qual vai para a esquerda e qual para a direita — cocktail.

## 11. Duas mas-desmontagens confirmadas nos bytes crus

- `$007FFC-$008001` sao uma unica instrucao `move.l #$F00,d0` (bytes 20 3C 00 00 0F 00). O que a listagem chama `sub_008000` comeca a meio dessa instrucao e nao e' rotina.
- `$0095C4` sao os bytes 64 00 00 94 = `bcc.w loc_00965A`, continuacao de sub_0095A8. `sub_0095C6` nao existe.

Ambas verificadas lendo build/maincpu.bin directamente. Valeria a pena dar estes dois enderecos ao desmontador como "nao e' inicio de rotina".


### Dúvidas em aberto

**1. O que e' exactamente o contador `$18A(a5)` (`g_countdown_bcd`).** A mecanica esta 100% clara — decrementado com dois `sbcd` encadeados por `$18C(a5)` a cada `$7B(a5)` frames, redesenhado no campo $15 do HUD por sub_00196C, pisca a paleta a vermelho ($F00) quando vale 2 e a 0 arranca a maquina de estados `$86C(a5)` que acaba com `$890(a5)=1`. O que nao consegui decidir e' **o que representa no ecra** (tempo restante? energia? combustivel?). Duas coisas atrapalham: (a) a ordem dos `sbcd` (`lea $18B,a0 / lea $18D,a1 / sbcd -(a1),-(a0)` acede primeiro a $18A e so' depois a $18B) sugere armazenamento little-endian por byte, mas o codigo tambem le a mesma coisa como word big-endian em $007FCC; (b) `move.w #$3,$18A(a5)` e `move.w #$9,$18A(a5)` sao valores pequenos demais para um relogio em segundos BCD. Deixei o nome neutro (`g_countdown_bcd`) em vez de arriscar `g_time_left`. Resolve-se olhando para o registo $15 da tabela off_0019EC (numero de digitos) e para o item de HUD correspondente — trabalho da banda 01.

**2. Os corpos dos padroes de movimento em $0087A2-$008A49 e o bloco $008A4A-$008D8B.** Identifiquei o despacho (loc_007DF4 mapeia `$E(a4)`=1..7 para sete alvos) e li so' o corpo do padrao por omissao ($00874A). Marquei os outros seis com COMMENT ("corpo do padrao N") em vez de os nomear, porque nao verifiquei o que cada um faz. Os 834 bytes de $008A4A-$008D8B ficaram completamente por identificar — o desmontador marcou-os "sem evidencia" e nao encontrei referencia nenhuma. Podem ser dados de trajectoria ou codigo nao alcancado pela descoberta recursiva.

**3. `$8A4/$8A6(a5)` — chamei-lhes `g_boss_x_maybe`/`g_boss_y_maybe`.** Sao a origem dos tiros do slot 0 e das faiscas, e sao usados junto com `$898/$89A(a5)` como velocidade. E' consistente com o inimigo grande central, mas nao segui o codigo que os escreve (esta fora da banda) para confirmar.

**4. A seccao $014856-$0149D9 e' mesmo o final do jogo?** A prova estrutural e' solida: e' a entrada [16] de uma tabela de 17 scripts em que so' 16 rondas sao jogaveis. Mas nao consegui confirmar o conteudo, porque o script chama sub_0157A8, sub_015742, sub_01528A e sub_015334, todos fora da banda. Deixei os nove passos com sufixo `_maybe`. Tambem nao percebi o que `$72(a5)` significa — o script espera que passe por 1, 2 e 3, portanto ha' outra tarefa a conduzi-lo.

**5. O registo de $74 bytes apontado por `lvl_picture_ptr_table`.** Confirmei o formato `{word $0002/$0020, word $001C, 56 words}` e que sub_006FFC desenha tres deles na VRAM em posicoes fixas, mas nao li sub_007060 (o desenhador, fora da banda), portanto nao sei se as 56 words sao indices de tile 16x16 do TILE_ROM ou outra coisa, nem o que significa o primeiro word. Alem disso, 114 registos x $74 = $53A8 bytes nao chegam para os $9E70 da regiao: ha' mais dados de outro tipo la' dentro (a julgar pelo digest, blocos de words estritamente crescentes de 256 words, muito maiores que $74). O nome `lvl_picture_records` que dei ao bloco todo e' portanto generoso; so' o inicio esta verificado.

**6. Nao verifiquei se o editor de inimigos e' realmente inacessivel.** Procurei escritas de `$24(a5)=1` na listagem inteira e a unica que encontrei ($000610, em sub_0005DA) pertence a **outra** maquina de estados (a de off_00058C, seleccionada por um `$22(a5)` diferente). Como os dois despachantes partilham a mesma variavel `$24(a5)`, nao posso excluir que uma transicao de modo deixe o valor 1 la' de propria e caia no editor. Disse isto por palavras no cabecalho da seccao 1 do fragmento em vez de afirmar "codigo morto".

**7. O nibble de direccao lido em `CCHIP_RAM+$6`.** `enemy_dev_cursor_move` le o byte de $F00007 (que o HARDWARE_GROUND_TRUTH documenta como CCHIP_PA, com so' os bits 5/6/7 conhecidos) e usa os **bits 0..3** como direccoes. O MAME marca esses quatro bits como IPT_UNKNOWN. Nao sei se sao pinos reais do porto A ou bytes que o firmware do C-Chip escreve na RAM partilhada — a ROM interna de 4 KB do C-Chip nao esta dumpada, por isso e' provavelmente inresolvel com os artefactos actuais. Note-se que o codigo de jogo a serio usa outro caminho (`sub_004FAE` le `CCHIP_RAM+$A` e `+$C` e cozinha tudo para `$2A(a5)`), o que reforca que o editor e' codigo antigo.


---

## Fonte: `/Users/flaviocoutinho/development/qiqix/symbols/fragments/banda03.sym`

Rotinas nomeadas: **184** · incertas: **18**

### Descobertas

O rótulo do digest ("gestor de sprites") está errado. A banda 03 é cinco subsistemas distintos, e a maior parte do que interessa é o motor de jogo, não sprites.

1) FORMATO DA VRAM — resolvido, e resolve os "?" do HARDWARE_GROUND_TRUTH.
   `vram_addr_from_xy` ($016258) faz a0 = $6A(a5) + ((y&$FF)<<10) + ((x&$1FF)<<1).
   Logo: 1 word por pixel, $400 bytes ($200 words... na verdade 512 pixels) por linha,
   256 linhas, e $6A(a5) guarda a base da página activa (o bit0 de VIDEO_CTRL escolhe qual).
   Os testes de bit espalhados por toda a banda dão o significado de dois bits do word:
     bit 15 = pixel pertence à ÁREA JÁ CAPTURADA (é o mesmo bit que o MAME chama
              "seleciona imagem A/B" — por isso a área capturada revela a fotografia de fundo);
     bit  7 = pixel pertence à TRILHA EM CONSTRUÇÃO (é o bit do meio do campo de índice
              de paleta, bits 6-8; a trilha tem cor própria).
   `vram_scan_to_solid` ($016230) procura "bit15=1 E bit7=0" = parede sólida.
   `vram_scan_to_trail` ($016246) procura bit7=1 = a trilha que mata.
   O bit 0 é usado pelo editor de depuração para desenhar caixas na VRAM.

2) SISTEMA DE COORDENADAS. Há dois eixos e o código nunca lhes chama x/y:
   $C(a4) e $81A(a5) = eixo de 0..255 (linha da VRAM, Y do PC090OJ, HORIZONTAL no monitor);
   $E(a4) e $816(a5) = eixo de 0..319 (coluna da VRAM, X do PC090OJ, VERTICAL no monitor,
   porque o ecrã é ROT270). A área de jogo é ($0F,$EF) x ($13,$12D) — confirmado
   independentemente em `play_area_bounds_check` ($016E50) e em `collide_build_box` ($01628A).
   $30(a5) é o flag de espelhamento (cocktail/flip): quando é 0 todas as conversões passam a
   ($FE-y, $140-x).

3) ESTRUTURA DO ACTOR (A4) — deduzida de ~30 rotinas:
   $02 direcção 0..31 · $04 fase do padrão · $06 recarga · $08 temporizador · $0A velocidade
   $0C eixo 256 · $0E eixo 320 · $14/$16 posição anterior · $18 cor · $1E código base do sprite
   $22 máscara de colisão (b0=baixo b1=direita b2=esquerda b3=cima — a MESMA ordem de bits
   que o joystick empacotado) · $28 código final do sprite · $2C índice de animação ·
   $30 mínimo de $2C · $3A passo entre quadros. E `actor_sprite_code_from_frame` ($016EF8)
   dá a fórmula do sprite: $28 = $2C * $3A + $1E.

4) MOTOR DE MOVIMENTO POR PADRÕES DE BITS (não é aritmética de vectores).
   Cada uma das 32 direcções tem um par de padrões de 16 bits; em cada passo, um bit a 1
   significa "anda 1 pixel neste eixo". `math_accumulate_pattern_bits` ($016D7C) conta os bits
   de N posições consecutivas a partir de uma fase guardada no actor. As diagonais usam $EDDB
   (12 bits em 16 = 0,75 ≈ 1/√2), ou seja, a VELOCIDADE É NORMALIZADA — o Volfied não tem o
   defeito clássico de andar mais depressa na diagonal. Existe uma segunda tabela
   (`tbl_step_pattern_square`, $016C6E) sem normalização, com o eixo maior sempre a $FFFF.
   A velocidade é escolhida por nível 0..15 numa rampa (`tbl_speed_levels`): dos níveis 0-7 é
   "1 pixel a cada N frames", dos 8-15 é "N pixels por frame". Há duas cópias da rampa
   desfasadas de um degrau, e `actor_set_speed_level` troca de tabela quando o nível pedido
   daria a mesma velocidade — histerese para garantir que acelerar muda sempre alguma coisa.

5) TABELA DE ARCTAN. Os 56 "textos" que o extractor encontrou entre $01732F e $01791F são
   uma tabela de 56x28 bytes = 56x56 valores de 4 bits, não texto. `math_aim_dir_fine`
   ($0172A0) indexa-a com (|Δ256|>>3)*28 + (|Δ320|>>3)>>1 e escolhe o nibble pela paridade.
   O valor é round(atan(Δ320/Δ256) * 8/90°), 0..8 = um quadrante de 32 direcções; os sinais
   dos deltas fazem a reflexão para os outros três quadrantes. Verifiquei numericamente:
   linha 1 = 0,4,6,6,7,7,7 == atan(1..)*8/90 arredondado. Existe também uma versão barata
   (`math_aim_dir_coarse`, $017932) que só compara |Δ| com razões 2:1 e 1:2 e dá 16 direcções.

6) COLISÃO. `collide_field` ($015D36) monta uma caixa cujos limites dependem do QUADRO DE
   ANIMAÇÃO (tabela de 8 bytes indexada por $2C(a4)), satura-a na área de jogo, e sonda os
   lados na VRAM em duas passagens (lados opostos). O resultado é uma máscara de paredes em
   $22(a4); `actor_undo_move_on_hit` ($0179BE) repõe a coordenada do eixo bloqueado e
   `actor_bounce_dir` ($016DC8) reflecte a direcção — inverte 180° se as duas paredes de um
   canto foram atingidas, senão espelha. Os bits de colisão vêm de tabelas por quadrante
   ($016118, $01614C, $016E1E, $016E26).
   O hardware ajuda: $5A(a5) (já conhecido) tem no byte baixo b5 = tocou inimigo pequeno,
   b6 = tocou inimigo grande; o software só confia nisso quando $897(a5) != 0.
   O jogador tem 3 tiros ($8C0/$8D0/$8E0, 16 bytes cada, [0]=estado 1=vivo/2=acertou).

7) O C-CHIP FORNECE DADOS DO NÍVEL, não só entradas. `pal_load_round_from_cchip` ($015C94)
   escreve round+1 em CCHIP_RAM+$7FD, fica em espera activa até o C-Chip alterar esse byte
   (handshake) e depois lê 80 words de CCHIP_RAM+$21 para a paleta. Como só os bytes ímpares
   estão mapeados, um word do C-Chip ocupa 4 bytes de endereço (byte alto em +2, baixo em +0).
   Este é o único sítio da banda onde o C-Chip é usado para outra coisa que não input.

8) PALETA. Formato xBGR555 mas o jogo só usa os 4 bits altos de cada componente (máscaras
   $001E/$03C0/$7800), deixando os LSB a zero — o que dá margem para os efeitos: fade por
   subtração de um degrau, fade cruzado degrau a degrau, e duas conversões monocromáticas
   (vermelha e âmbar) escolhidas pelo número do round (4, 5 e $B usam a âmbar; $10 nenhuma).

9) O EDITOR DE DEPURAÇÃO DA TAITO ficou na ROM final ($0163BA-$016A55). Menu com as linhas
   SIZE LU / SIZE RD / CENTER / ZOOM / PATTERN / ANIME / ANM MAX / ROUND / OPT: permite mover
   os pontos da silhueta de um objecto, mudar o código do sprite, o passo de animação e o
   round (recarregando a paleta do C-Chip). Desenha as caixas directamente na VRAM comutando
   o bit 0 dos pixels. Há ainda um GRAVADOR DE DEMO ($017D40) que faz RLE do joystick para
   $00039252 — que é ROM, portanto inerte na placa real: mais um resto do sistema de
   desenvolvimento, como os vectores $0011xxxx.

10) TEXTO POR SPRITES. Não há camada de tiles neste jogo: todo o texto é sprites de 8 bytes,
    espaçados 8 pixels, com código = ASCII-$20. `txt_render_line_sprites` ($015696) interpreta
    $CD=fim de linha, $18 nn=cor, $16 nn=repetir, $20=espaço, e o cursor dá a volta em
    SPRITE_RAM+$600 (192 sprites reservados para texto). Esconder um sprite é escrever $180
    no word Y (offset +2) — convenção usada em toda a ROM.

11) O FINAL DO JOGO está aqui inteiro: um script de co-rotinas onde cada passo termina com
    `move.w #frames,d7 ; lea proximo(pc),a6 ; rts`. Mostra o staff roll (MITSUJI, KOBAYASHI,
    TSUKANO, OKI, SANUKI, KURIKI, IWABUCHI, OGURA, OHARA, NAGAI) e depois o texto de história
    letra a letra, com o caractere actual em banco de cor $E e o anterior a baixar para $C.


### Dúvidas em aberto

1. `pal_mark_round_entry_maybe` ($015C0A). Faz o handshake com o C-Chip (round+$81), lê um
   índice de CCHIP_RAM+$47 e faz OR de $8000, $400 e $20 em oito posições da paleta
   ($503380, $5033A0, $503980, $5039A0, $503580, $5035A0, $5035E0, $503560). O problema é que
   $400 e $20 são os bits menos significativos de B e de G — o jogo usa só os 4 bits altos de
   cada componente, portanto o efeito visual é quase nulo — e $8000 é o bit "x" que o
   xBGR_555 ignora. Ou estes bits têm outro significado que não descobri, ou é uma marcação
   que sobrou. Deixei o nome com _maybe.

2. `pal_load_round_from_cchip` ($015C94) escreve as MESMAS 80 words do C-Chip em 16 linhas de
   paleta espaçadas de 256 entradas (a0 é restaurado a cada iteração com `movea.l a2,a0`).
   Confirmei a leitura três vezes; é mesmo o mesmo bloco replicado 16 vezes. Não percebi
   porquê — pode ser que a paleta esteja organizada em 16 bancos que precisam todos das mesmas
   cores de base, ou pode ser um bug/desperdício. Documentei o comportamento, não a intenção.

3. Polaridade de $2A(a5) e do flanco em `dbg_input_edge` ($0164B2). A conta é
   $29A2 = (~actual) & anterior, mas quem consome ($0163BA) age quando o bit está a ZERO, o
   que só faz sentido se $2A(a5) estiver na polaridade contrária à que `inp_read_joy_packed`
   devolve. Como $2A(a5) é escrito fora da minha banda, não consegui fechar isto. A ORDEM dos
   bits (b0=baixo b1=direita b2=esquerda b3=cima b4=botão) está sólida — confirmada em três
   sítios independentes — mas a polaridade de $2A(a5) fica por confirmar.

4. Qual dos dois eixos é "x" e qual é "y" é uma escolha, não um facto. Evitei x/y nos nomes
   das rotinas (uso "eixo de 256" e "eixo de 320") mas mantive g_player_x/g_player_y para as
   variáveis do jogador, com o comentário a dizer que, por ser ROT270, g_player_x é a
   vertical no monitor. Se a convenção do projecto for a do monitor e não a da VRAM, estes
   dois nomes têm de trocar.

5. Rotinas sem chamador que deixei com _maybe por não conseguir provar quem as usa:
   `collide_probe_length_alt_maybe` ($0161CE), `actor_turn_90_on_wall_maybe` ($016F0A),
   `collide_step_bytes_alt_maybe` ($01637E). São variantes literais de rotinas vizinhas com
   uma constante diferente (>>2 em vez de /3; passo de 8 em vez de $10; outra tabela).
   Podem ser código morto ou podem ser chamadas por ponteiro a partir de tabelas noutras
   bandas — quem apanhar as bandas $018xxx-$021xxx deve verificar.

6. Ficaram 14 entradas do digest sem nome. Quatro delas não são rotinas: $01728C (é a tabela
   de 10 words que marquei como DATA), $016E22, $016B10 e $0167C6 (bytes de dados que o
   desmontador leu como instruções). As restantes dez são `rts` isolados, passos triviais da
   cadeia do final, ou fragmentos de 10-16 bytes sem conteúdo que justifique um nome.

7. O bloco $015888-$0159E7 (HUD "TIME STOP") usa $883/$88E/$88F/$897(a5) mas quem lhes escreve
   está fora da banda. Nomeei-os pelo uso observado (item activo, temporizador 0..$F0, pisca,
   usar colisão do hardware) e não pela escrita, que não vi.

8. A rotina real da tabela de arctan começa em $0172A0, não em $01728C como o desmontador
   indica — os 20 bytes anteriores são a tabela `tbl_actor_param_by_frame` lida por
   `actor_load_param_from_frame` ($01727A). Vale a pena corrigir isso no gerador antes da
   próxima passagem, senão a listagem continua a mostrar cinco `ori.b #$4,d4` falsos.


---

## Fonte: `/Users/flaviocoutinho/development/qiqix/symbols/fragments/banda04.sym`

Rotinas nomeadas: **69** · incertas: **127**

### Descobertas

O rotulo do digest ("provavel leitura de entradas") esta enganado. Esta faixa e' o MOTOR DE SPRITES do jogo mais as maquinas de estado de sete inimigos grandes. So duas rotinas tocam o C-Chip e nao e' para ler controlos.

1) MOTOR DE SPRITES (o achado com mais alcance). sub_017F4C ($017F4C, 20 chamadores) constroi a lista PC090OJ do objecto em a4. Um "frame" de sprite e' uma indireccao de quatro niveis:
   $110A(a5) (0..15, conjunto grafico da area) -> off_0185B8 -> tabela de descritores em $0329CA..$035068
   descritor de 8 bytes: [0]=indice da lista de tiles, [1]=indice da lista de offsets, [2].w ajuste Y, [4].w ajuste X, [6].w base do codigo de tile
   [0] -> word_01860C -> lista de (atributo,codigo) em $030000+
   [1] -> word_018790 -> lista de (contagem, dx, dy...) em $031B74+
   Isto explica a segmentacao dos dados que o romtool ja tinha medido: $030000-$031B73 sao listas de tiles, $031B74-$0329xx sao listas de posicao, $0329CA+ sao os descritores.
   O espelhamento e' feito por quatro variantes despachadas em $01802A por um modo 0..3, e coincide bit a bit com pc090oj.cpp: bchg #6 do byte alto = bit14 = flipx, bchg #7 = bit15 = flipy, e a coordenada correspondente e' negada com -$10 (a mesma compensacao de 16 pixels do MAME).

2) O ARRAY DE OBJECTOS. $10111A e' um array de 8 objectos de $40 bytes. [0] e' o inimigo grande; [1..7] sao os pequenos, inicializados por sub_017F0A a partir de $10115A com passo $40. Mapeei os campos: +$02 direccao (32 direccoes), +$06 periodo de passo, +$08.l acumulador, +$0C Y, +$0E X, +$14/$16 posicao anterior, +$18 cor, +$1A contador de frame, +$1C indice no script, +$1E frame, +$20 modo de flip, +$22 mascara de colisao com a area preenchida, +$28 frame de sprite, +$2A sprites emitidos no frame anterior, +$2C linha de animacao, +$3A frames por linha. O indice de sprite e' sempre $28 = $2C*$3A + $1E ($016EF8).

3) SPRITES COMPOSTOS. $101D9A e' uma lista de "pecas" de $C bytes (+0 activo, +2 Y, +4 X, +6 frame, +8 cor, +A flip) e $10209A e' a contagem. Chefes grandes tem 2, 3, $E ou $1D pecas. Ha cinco ponteiros de lista de sprites ($1020A0..$1020B0), um por tarefa/camada; no jogo o ponteiro 0 aponta para SPRITE_RAM+$3C8, nos ecras de chefe para buffers em RAM principal.

4) UM CHEFE POR AREA, COM PROTECCAO NUM DELES. $100198&$1F (numero da area) indexa off_0146A8 -> $110A(a5) -> off_0146CA (17 rotinas de init) e off_020ECE (16 rotinas de forma de colisao). Cada init regista tres tarefas com sub_01470E: prioridade 2 (padrao/campo, $01E9AC..$01FA62), 1 (grupo de inimigos, $01C4AA..$01D60C) e 3 ($020B9E, comum). Cada chefe tem RAM privada e sequencial a partir de $102A6A — nao e' uma uniao, sao faixas distintas.
   O chefe 9 e' o unico da faixa que faz um DESAFIO DE PROTECCAO ao C-Chip antes de aparecer: selecciona o banco 2 da SRAM partilhada, escreve $AA e $55 como argumentos e $65 como comando, e depois espera em laco ate ler $7C. E o ciclo de combate volta a passar por essa verificacao todas as vezes ($01A1F4 salta para $01A0E6, que reinstala $01A0F0). Se o C-Chip nao responder, o chefe nunca ataca.

5) ENDERECAMENTO DA VRAM E ROT270. A rotina partilhada sub_016258 confirma os dois eixos: d0 e' a linha (0..255, passo $400 bytes = 512 words) e d1 a coluna (0..319, porque o espelhamento faz $140-d1 e $13F=319). $10006A guarda a base da pagina de VRAM a desenhar (VRAM ou VRAM+$40000, as duas paginas de $20000 words do formato documentado) e $100030 e' a flag de espelhamento. Nos blitters 8x8 o laco interno anda +$400 (linha seguinte) e o externo -$2002 (recua 8 linhas E uma coluna): as celulas sao desenhadas rodadas, coerente com o monitor vertical.

6) MOTOR DE DESENHO DE IMAGENS NA BITMAP. Cinco tarefas de $1C bytes em $1029DE desenham imagens grandes na VRAM progressivamente (N linhas por frame). O tamanho $8C = 5 x $1C esta provado por $01849A, que limpa exactamente $8C bytes. Se as cinco estiverem ocupadas, $01851A faz `bra.b *` — um assert de desenvolvimento que trava a maquina, deixado na ROM final.

7) CODIGO MORTO E RASTO DO KIT DE DESENVOLVIMENTO. $018174/$0181F0 desenham um mapa de 26x11 celulas 8x8 (um logotipo) mas nao tem chamadores e a base de tiles que usam ($020B00, e $020000 para a celula vazia) cai dentro de CODIGO na ROM final. E' quase de certeza restos de uma build anterior — a mesma familia de restos que os vectores $0011xxxx. As "strings" que o digest reporta em $0182C1+ sao esse mapa, nao texto.

8) ENTRADA E DEMO. $10002A e' o estado de controlos ja normalizado (b0=BAIXO b1=DIREITA b2=ESQUERDA b3=CIMA b4=BOTAO1, activo alto), montado em $004FE0-$00500E a partir de CCHIP_PC. Quando $100040 = 0 o jogo NAO le o C-Chip: sub_017DC6 reproduz um script gravado ($22C(a5) aponta para $039252 / $0396C4 / $0397EC / $039C5E), em que cada word e' (valor<<11) | duracao_em_frames. Ha ate a rotina gemea de GRAVACAO em $017D8C, que escreve o mesmo formato — o modo de atraccao foi capturado, nao programado.

9) TRUQUE DE COMPILACAO. sub_017BDE e' um trampolim com dados em linha: tira o endereco de retorno da pilha, copia dai N words e salta para depois deles. Todos os inits de chefe usam-no para carregar a tabela de duracoes de animacao ($1020C6, 5 words). Isto faz o desmontador perder o `lea` seguinte em quatro dos sete chefes — as entradas reais sao $018C6E, $01921A, $019680 e $019C36, nao $018C72/$01921E/$019684/$019C3A.


### Dúvidas em aberto

1) NAO nomeei os ~120 estados individuais das maquinas de estado dos chefes ($018926, $018CE4, $0192D0, $01977E, $019CD2, $01A7FC e companhia). O padrao e' claro — `move.w #N,d7 / lea proximo(pc),a6 / rts`, com d7 = frames de espera e a6 = proximo estado — mas sem ver cada chefe a mexer no ecra nao consigo justificar se um estado e' "entrar", "carregar", "disparar" ou "recuar". Preferi deixar sub_XXXXXX a inventar. Sao a maior fatia das 124 rotinas sem nome.

2) $1020F2 ficou _maybe. Cada init de chefe escreve-lhe 0, 9, $D ou $F, mas o unico leitor ($015D8E) so faz `tst.w` e, se for diferente de zero, encolhe a caixa de colisao em 3 de cada lado. Nao encontrei nenhum sitio que use o VALOR, so o zero/nao-zero — ou ha um leitor que me escapou, ou os valores distintos sao residuo.

3) Bit 7 de $10005B (byte baixo do status de colisao lido de VIDEO_CTRL). E' testado em $018A26 e $01A20A e altera o comportamento do chefe, mas o MAME devolve fixo $60 (bits 5 e 6), portanto o bit 7 e' sempre 0 em emulacao e nao consigo dizer o que significa na PCB real. Fica documentado como incognita, nao adivinhado.

4) $018174 e $0181F0: chamei-lhes codigo morto porque nao tem chamadores e a base de tiles que usam ($020B00) cai dentro de codigo. Mas nao excluo que sejam chamados por um ponteiro que o desmontador nao resolveu. Marquei _maybe/_dead_maybe em vez de os apagar da analise.

5) Nao identifiquei que AREA do jogo corresponde a cada indice de chefe. Sei que off_0146A8 mapeia area -> indice (area 0 -> chefe 9, area 1 -> chefe 0, area 4 -> chefe 4, ...), mas nao sei os nomes dos planetas do Volfied, e associar "chefe 9" a um nome seria invencao.

6) Os quatro scripts de demo ($039252/$0396C4/$0397EC/$039C5E) ficaram com DATA sem tamanho — sao terminados por $FFFF e nao os percorri ate ao fim. Alguem da banda de dados devera medi-los.

7) A escolha entre os quatro scripts depende de `btst #1,$2D(a5)` (bit 1 do byte baixo de g_dswa) e `btst #0,$235(a5)`. Nao sei o que o bit 1 do DSWA e' neste set — a tabela de DIPs do HARDWARE_GROUND_TRUTH so documenta DSWB. Deixei a condicao no comentario sem lhe dar significado.

8) $102105, escrito por boss_place_and_reset e lido em $020F84, ficou sem nome: um so leitor, longe da banda, e nao percebi para que serve.


---

## Fonte: `/Users/flaviocoutinho/development/qiqix/symbols/fragments/banda05.sym`

Rotinas nomeadas: **213** · incertas: **11**

### Descobertas

MATERIAL PARA docs/ — o que esta banda revela sobre a arquitectura do jogo.

## 1. Há um escalonador cooperativo de corrotinas (não é só "game loop")

`sub_0145EE` ($0145EE) percorre 4 ranhuras de tarefa de $40 bytes a partir de $101000.
Cada ranhura tem: $0 activa, $2 atraso em frames, $4 PC de retoma, $8.. cópia de d0-d6/a0-a4.
Quando o atraso chega a 0, restaura os registos, faz `jsr (a6)` no PC guardado, e depois
guarda o **a6 devolvido** como novo PC e o **d7 devolvido** como novo atraso.

Por isso o idioma que aparece centenas de vezes nesta banda:

        move.w  #N,d7
        lea     proxima_rotina(pc),a6
        rts                      ; = "dorme N frames, retoma em proxima_rotina"

Consequência prática: quase todas as 224 "rotinas" desta banda **não são funções** — são
estados de máquinas de estado escritas como corrotinas. Isso explica a densidade anómala de
rotinas de 10-30 bytes e a ausência de hardware directo.

`sub_01470E` cria uma tarefa (d1 = ranhura 0-3, d0 = PC inicial); `sub_014724`/`sub_014738`
param/retomam ranhuras.

## 2. As fases são escolhidas por um "tipo de cenário", não pelo número da ronda

`$100198` = ronda 0..15 (incrementada em $003B90, comparada com $10 → 16 áreas).
`sub_014648` ($014648) faz `$10110A = off_0146A8[$198 & $1F]`, ou seja:

    ronda:  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
    tipo :  9  0  2  7  4  3 10  8  6  5 13 12  1 11 14 15

`$10110A` (tipo de fase) indexa TRÊS tabelas de ponteiros paralelas:
  * `off_0146CA` ($0146CA, 17 entradas) — rotina de ARRANQUE do chefe da fase
  * `off_020ECE` ($020ECE, 16 entradas) — rotina de TESTE DE COLISÃO do chefe, por frame
  * `off_020D98` ($020D98, 16 entradas) — rotina de FIM DE RONDA (todas iguais a $028C10
    excepto a entrada [12], que é $01B418: a área 12 tem uma sequência de saída própria)

Cada tipo de fase ocupa um bloco contíguo de código com o par (init, hit-test) nos dois
extremos. Verifiquei o padrão em todos: tipo 11 = $01A68C/$01AD12, tipo 12 = $01ADC4/$01B8DE,
tipo 14 = $01B9CC/$01BD7C, tipo 15 = $01BD9A/$01C45C. Também tem bloco privado de RAM:
tipo 11 → $102AF6-$102B1C, tipo 12 → $102B1E-$102B44, tipo 14 → $102B46-$102B54,
tipo 15 → $102B56-$102B88. Nem um único endereço partilhado entre eles. Isto (mais tabelas
byte-a-byte idênticas, ver ponto 7) diz que os cenários foram escritos por
copiar-colar-ajustar, não por parametrização.

## 3. Sistema de objectos: um chefe + um "pool" de 7 objectos

  $10111A  inimigo grande / chefe, 1 objecto de $40 bytes; instalado por $017EDA a partir
           de um registo de 6 bytes (dir.b, X.b, Y.w, $2D.b, $2105.b)
  $10115A  7 objectos de $40 bytes; instalados de uma vez por $017F0A a partir de uma
           tabela de 7 registos de 4 bytes (dir.b, X.b, Y.w) — X byte 0 = ranhura vazia
  $101D9A  lista de "pedidos de sprite" de $C bytes, expandida por $017F4C
  $102350  buffer de 96 sprites x 8 bytes, copiado para SPRITE_RAM+$180 por $014752

Campos do objecto (a4), deduzidos de dezenas de sítios:
  $0  activo ($FFFF vivo, $FFFE a morrer, 0 livre)
  $2  direcção 0..31 (32 direcções; `andi.w #$1F` por todo o lado)
  $4  temporizador de desaparecimento
  $6  recarga do passo (velocidade: quanto menor, mais rápido)
  $8.l acumulador de sub-pixel do movimento
  $C  X no eixo de 256 px   |  $E  Y no eixo de 320 px
  $10/$12 offset do sprite  |  $14/$16 posição do frame anterior
  $18 atributo/cor  |  $1A duração do frame  |  $1C índice na sequência  |  $1E frame
  $22 máscara das bordas atingidas (devolvida por $015CF4)
  $28 tile base  |  $2A índice na cadeia de captura  |  $2C ESTADO (índice de despacho)
  $30 tamanho/frame mínimo  |  $32..$3C campos livres por tipo de fase

## 4. O sistema de coordenadas está mesmo rodado

`sub_021518` ($021518) escreve o registo do PC090OJ e revela o mapeamento:
  +0 attr (b15 flipY, b14 flipX, b0-3 cor)   ← $18(a4)
  +2 Y do hardware                            ← $C(a4) + $10(a4)
  +4 tile                                     ← $28(a4) + $1E(a4)
  +6 X do hardware                            ← $E(a4) + $12(a4)

Isto é, o `$C(a4)` do código é o **Y do hardware** (eixo de 256) e o `$E(a4)` é o **X do
hardware** (eixo de 320). Confirmado três vezes:
  * $016E50 valida $C em [16,238] e $E em [20,300] — o campo de jogo útil
  * $016ED4 devolve a posição do jogador mascarada com $FF (para $C) e $1FF (para $E)
  * $016258 calcula o endereço de VRAM como base + $C*1024 + $E*2 (512 words por linha,
    exactamente o formato de VRAM do HARDWARE_GROUND_TRUTH)
Escrever isto em docs/ evita que a próxima pessoa se engane em todos os cálculos.

## 5. Como os inimigos morrem: a captura de área é resolvida lendo a VRAM

`sub_021094` ($021094) é chamada por TODOS os inimigos pequenos, uma vez por frame:
lê o word de VRAM na posição do inimigo, inverte o bit 15, faz `andi.w #$8180` e, se o
resultado for **zero**, mata o inimigo. Ou seja: o jogo não guarda polígonos de área
capturada — pergunta ao próprio bitmap se o pixel debaixo do inimigo já pertence à zona
preenchida (bit 15 = "imagem B" aceso, bits 8 e 7 da paleta apagados).

Ao matar, guarda `$2A(a4) = $102130` e incrementa $102130. Como $102130 é zerado no início
de cada varrimento, $2A é a posição do inimigo na **cadeia de capturas do frame** — é isso
que $021446 usa para escolher o valor de pontos na tabela $0214F4. Fica assim explicada a
mecânica de bónus por encurralar vários inimigos de uma vez.

Há ainda um semáforo global $102132: só um inimigo de cada vez toca a animação de morte
(e o comando de som $1A), os outros esperam no estado "capturado".

## 6. As três formas de colisão

  * $015CF4 / $015CEA / $015D36 — traça a silhueta do objecto contra o bitmap e devolve
    `$22(a4)` = máscara das bordas atingidas. É o que alimenta $016DC8 (ressalto) e
    $0179BE (desfaz o movimento no eixo bloqueado).
  * $015E36 (usa o bit 5 de $10005B) e $015E5E (bit 6) — testes de "toquei em quê":
      $102202 = tocou o JOGADOR ($015EE4; põe $10084F se $10084E permitir)
      $102200 = tocou a LINHA em construção ($015FB4; põe $100851/$100852)
      $102110/$102112 = apanhou um dos 3 itens em $1008C0/$1008D0/$1008E0
    Os bits 5 e 6 são exactamente os que o MAME devolve fixos em $60 no registo $D00000.
  * $015FE0 — teste de caixa contra os itens.

**Achado sobre o bit 7 de $D00000** (o MAME comenta "its purpose is unclear"): as três
rotinas de redimensionamento de chefe desta banda ($01B02E, $01BBEA, $01C21E) fazem
`btst.b #$7,$5B(a5)` e, se o bit estiver aceso, **saltam o encolher** do chefe. Como o MAME
devolve sempre $60, no emulador o chefe encolhe sempre. É a única utilização do bit 7 que
encontrei; vale a pena registar em docs/ como pista para quem tiver a placa real.

## 7. Chefes: crescem quando ficam encurralados

Os chefes dos tipos 12, 14 e 15 têm `$2C(a4)` = tamanho/forma 0..8. Cada ciclo conta os
ressaltos em paredes ($2B2A / $2B52 / $2B62); se passar de $F (ou $14 no tipo 14) o chefe
**cresce** até 8, senão **encolhe** até $30(a4). O tamanho escolhe: o tile base (d3 =
$2C*7 no tipo 12, $2C*$C+$60 no tipo 15), o deslocamento vertical e a amplitude do
balanço (tabelas $01B268/$01B27A e $01C2CE/$01C2E0), e a animação da "boca"
($01B14C / $01C15E, 3 tamanhos x 16 frames de (flip, tile)).

Note-se que **$01B14C e $01C15E são 192 bytes byte-a-byte idênticos**, e $01B248 é
funcionalmente igual a $01C2AE, $01B0F0 a $01C102, $01B02E a $01C21E. O chefe da área 16
(final) é um clone do da área 12 com uma segunda máquina de ataque acrescentada ($2B84
para um ataque, $2B86 para o outro, cada uma com a sua tabela de 3 ponteiros).

## 8. O chefe-serpente (tipo 11, área 14)

O único chefe com geometria própria. Usa um **anel de rasto**: $10131A guarda $C0 registos
de 4 bytes (dx, dy, direcção) escritos pela cabeça a cada frame ($01AAE2), e 16 segmentos
em $10161A+$C ($01AA34) seguem-no lendo posições atrasadas do anel, com uma distância
mínima que depende do tamanho ($01AAA4). O índice do anel avança módulo $C0 ($01AB3E).
A ordem de desenho ($01AB88) intercala as duas metades (0,9,1,10,2,11,...) para os
segmentos não se sobreporem mal. Quando o chefe leva dano, uma "onda" de cor $D percorre
os segmentos um a um ($2B12/$2B14/$2B16 em $01AC58).

## 9. Fim de ronda da área 12: uma cutscene inteira em corrotinas

$01B418 (off_020D98[12]) limpa a RAM de sprites, cria a tarefa de flash de paleta $01B7F8,
e encadeia 11 estados: o chefe voa para o centro exacto do campo ($80,$A0 — verificado em
$01B562/$01B596/$01B5C6), assenta pixel a pixel, abre-se, desenha um efeito de "túnel"
com 9 sprites directos deslocados por $2B44 de -$20 até $A0 ($01B622 + tabelas $01B67A e
$01B690), fecha-se, e por fim cria $01B820 que faz o fade de paleta.

O fade ($01B8B0) é reutilizável e vale um símbolo próprio: sobre 16 words de paleta
xBGR555 subtrai um passo a cada componente não nula, com as máscaras $001E (vermelho),
$03C0 (verde) e $7800 (azul).

## 10. Vocabulário partilhado que esta banda usa constantemente

  $0004F4  enfileira um comando de som (d0.b) na fila de 7 bytes em $10031C; o VBLANK
           drena-a em $000520. (O comando $1A é "inimigo pequeno destruído".)
  $016D92  passo de movimento: decrementa $8(a4), recarrega de $6(a4), converte a direcção
           $2(a4) em (dx,dy) e soma a $C/$E
  $016DC8  ressalta: ajusta $2(a4) a partir da máscara de bordas em d0
  $0179E2  guarda a posição anterior em $14/$16  |  $0179BE desfaz o movimento no eixo
           bloqueado (bits 9 e 6 de $22(a4))
  $016EA8  = $016ED4 (posição do jogador) + $017932 (ângulo de 32 direcções) → $1020F0
  $016EB2  sentido de rotação mais curto (±1) → $1020EE
  $017268  $1A(a4) = tabela de durações $1020C6[$1E(a4)]
  $017BDE  copia N words **de dados inline colocados a seguir ao jsr** para (a1) e salta
           por cima deles — é isto que produz as pseudo-rotinas `ori.b #$5,d5` na listagem
  $017E72  instala o template de 20 words do objecto  |  $017BC2 esconde sprites (Y=$180)
  $021502  pisca (alterna o bit 0 de $1F(a4) de 7 em 7 frames)
  $021518  escreve o sprite directo no buffer  |  $021084 apaga 4 sprites
  $0213FA  animação de explosão  |  $021446 mostrador de pontos + soma ao score ($00302E)


### Dúvidas em aberto

## O que não fechei, e porquê

1. **$1020A0/$20A4/$20A8/$20AC/$20B0 — as 5 partições do buffer de sprites.**
   Cada tipo de fase reparte $102350 de maneira diferente ($01AE40, $01BA3A, $01BE28) e os
   valores não batem certo entre si (o tipo 12 dá 42 sprites à primeira partição, o tipo 15
   dá 8). Sei que $20A4 é a partição dos inimigos pequenos (é sempre esse o a3 dos ciclos)
   e que $20A0 é o ponteiro de escrita usado por $017F4C, mas não consegui provar o papel de
   $20A8/$20AC/$20B0 sem ler as tarefas dos tiros ($020006, $0203F2, $02068A) que estão
   noutras bandas. Deixei nomes neutros `g_spr_partN_ptr`.

2. **$102126 — chamei-lhe `g_boss_hp_maybe`.** É posto a $7F uma única vez ($014648) e a
   única subtracção que encontrei é em $020EB0/$020EC2, proporcional ao número de itens
   apanhados ($102112, x32 se $1008BF). Quando fica negativo, $020CC8 marca $10088C. Faz
   sentido como "resistência do chefe", mas o mecanismo (apanhar itens tira vida ao chefe?)
   é estranho o suficiente para eu não afirmar sem confirmar com $020E54 em detalhe.

3. **$100897 nunca é escrito na zona desmontada.** É lido em 10 sítios e comanda a mudança
   de "andar em linha recta" para "perseguir o jogador" ($01C6B6, $01C958, $01CD00, $01D326)
   e um caminho extra em $015EA2. Deve ser escrito indirectamente (via a0 sobre o bloco
   $100800) ou por uma rotina que a varredura não alcançou. Fica `_maybe`.

4. **$01C4F0 (`enemy_grp00_update`) só percorre 4 das 7 ranhuras** (`move.w #$4,$2B8A(a5)`),
   apesar de $01C4AA nascer 7 inimigos com a tabela $01C4CA (28 bytes = 7 registos, e
   $017F0A lê sempre 7). Ou há outra tarefa a tratar das ranhuras 4-6 no bloco do tipo 0
   ($018836, fora da banda), ou é um bug original. Não consigo decidir daqui.

5. **Quatro rotinas sem chamador nenhum**, marcadas com sufixo `_unused`:
   $01B576 (rodar um passo para uma direcção dada), $01C096 e $01C0B8 (testes de estado de
   ataque do chefe 15, análogos aos do chefe 12 que SÃO usados) e $01CD6E (perseguição do
   jogador do grupo 5). O padrão sugere restos do "copiar-colar" entre cenários, mas não
   excluo que sejam alcançadas por um `movea.l` calculado que a varredura não resolveu.

6. **$102346 / $102348 / $10234C** — os chefes 12/14/15 põem-nos a $FFFF para "disparar" e
   esperam que voltem a zero. Quem os limpa é a tarefa do tiro, noutra banda; por isso não
   lhes dei nome (só $10234A, que é claramente o tipo de tiro).

7. **Os descritores de silhueta em $035262/$0352B2/$035302/$0353C2/$0354B2/$035502/$035892/
   $0358E2/$035932** (e $01B92C/$01B97C, que estão dentro da minha banda) são registos de 8
   bytes lidos por $015CF4/$015E36/$015E5E. Percebi que são a "forma" do objecto contra o
   bitmap e que $2C(a4)*$20 os indexa por frame ($017A16), mas não decodifiquei o
   significado dos 8 bytes de cada registo. Marquei-os como DATA sem descrever o formato.

8. **$102B26 e $102B28 (tipo 12) e $102B5E/$102B60 (tipo 15)** são inicializados e nunca
   mais lidos dentro da banda. Não lhes dei RAMVAR para não inventar semântica.

9. Não editei `symbols/main68k.sym` e evitei pôr FUNC em endereços fora de $01A901-$01D558,
   mesmo nas rotinas de serviço que descrevi (($0004F4, $015CF4, $016D92, $017F4C, $021094,
   $021518, ...). Sugiro que quem consolidar os fragmentos lhes dê nome a partir do que está
   em 'descobertas' — são o vocabulário partilhado por praticamente todas as bandas.
