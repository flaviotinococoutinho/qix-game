# Volfied (Taito, 1989) — verdade de base do hardware

Extraído do driver oficial do MAME (`src/mame/taito/volfied.cpp`, autoria Bryan McPhail /
Nicola Salmoria, licença BSD-3-Clause) e confirmado contra o conjunto de ROMs local.
**Este arquivo é a única fonte autoritativa de endereços.** Nenhuma ferramenta ou documento
deste projeto deve inventar um endereço que não esteja aqui ou que não tenha sido derivado
empiricamente do código.

Set identificado: `volfied` — *Volfied (World, rev 1)*. Todos os 18 CRC32/SHA-1 conferem.

## Placa

| Item | Valor |
|---|---|
| CPU principal | MC68000 @ 8 MHz (XTAL 32 MHz / 4) |
| CPU de som | Z80 @ 4 MHz (XTAL 32 MHz / 8) |
| Áudio | YM2203 @ 4 MHz |
| Protecção | TC0030CMD "C-Chip" — NEC D78C11 (4 KB ROM interna) + 8 KB EPROM + 8 KB DRAM, @ 10 MHz (XTAL 20 MHz / 2) |
| Sprites | PC090OJ |
| Cor | TC0070RGB + PC050CM, paleta xBGR_555, 8192 entradas |
| Áudio latch | PC060HA |
| VRAM | 12 × MB-81461 = 256 KB |
| Tela | 320×256, visível 0–319 × 8–247, 60 Hz, **ROT270** |
| OSC | 32 MHz, 26.686 MHz, 20 MHz |

## Mapa de memória — 68000

| Faixa | Acesso | Função |
|---|---|---|
| `$000000–$03FFFF` | R | ROM de programa (256 KB) |
| `$080000–$0FFFFF` | R | ROM de dados de tiles (512 KB) |
| `$100000–$103FFF` | RW | RAM principal (16 KB) |
| `$200000–$203FFF` | RW | PC090OJ (RAM de sprites) |
| `$400000–$47FFFF` | W | VRAM (mascarada por `video_mask`) |
| `$500000–$503FFF` | W | Paleta (xBGR_555) |
| `$600000–$600001` | W | `video_mask` — máscara de escrita de bits da VRAM |
| `$700000–$700001` | W | PC090OJ `sprite_ctrl` |
| `$D00000–$D00001` | RW | `video_ctrl` (W) / status de colisão (R, MAME devolve `$60`) |
| `$E00001` | W | PC060HA `master_port_w` |
| `$E00003` | RW | PC060HA `master_comm_r/w` |
| `$F00000–$F007FF` | RW | C-Chip — RAM compartilhada (só bytes ímpares, `umask16(0x00ff)`) |
| `$F00800–$F00FFF` | RW | C-Chip — registos ASIC (só bytes ímpares) |

IRQ do 68000: **nível 4** no VBLANK. O mesmo VBLANK dispara `ext_interrupt` no C-Chip.

### Reset vector (verificado no binário)

```
SSP = $00103FFE      (topo da RAM principal)
PC  = $000014B8      (entry point)
```

### Região (word em `$03FFFE`)

| Valor | Versão | Moedas |
|---|---|---|
| `$0001` | Japão | TAITO_COINAGE_JAPAN_OLD, mostra tela de aviso |
| `$0002` | EUA | TAITO_COINAGE_US, mostra logo FBI |
| `$0003` | Mundo (**este set**) | TAITO_COINAGE_WORLD |

Código de moedas em `$00666A`. Tabela de bônus de vida em `$003140` (4 × 6 words, LSB first).
Cheat de 32768 vidas: código em `$0015CC`.

## Mapa de memória — Z80 (som)

| Faixa | Função |
|---|---|
| `$0000–$7FFF` | ROM (`c04-06.71`, 32 KB) |
| `$8000–$87FF` | RAM (2 KB) |
| `$8800` | PC060HA `slave_port_w` |
| `$8801` | PC060HA `slave_comm_r/w` |
| `$9000–$9001` | YM2203 |
| `$9800` | escrita ignorada (função desconhecida) |

IRQ do Z80: vem do YM2203. NMI e RESET vêm do PC060HA.

Portas do YM2203: **porta A = DSWA**, **porta B = DSWB**.
Mixagem MAME: canais 0/1/2 a 0.15, canal 3 (SSG) a 0.60.

## Formato da VRAM

2 telas × 256 linhas × 512 colunas × 16 bits. `video_ctrl & 1` seleciona a tela
(offset `+$20000` words). Bits de cada word:

```
x---------------  seleciona imagem (A ou B)
-x--------------  ? (usado em cantos "3-D")
--x-------------  ? (usado em paredes "3-D")
---xxxx---------  imagem B
-------xxx------  índice de paleta, bits 8..10
----------x-----  ?
-----------x----  ?
------------xxxx  imagem A
```

Cálculo de cor no MAME:
```c
color = (p[x] << 2) & 0x700;
if (p[x] & 0x8000) {
    color |= 0x800 | ((p[x] >> 9) & 0xf);
    if (p[x] & 0x2000) color &= ~0xf;   // hack
} else
    color |= p[x] & 0xf;
```

Os bits "3-D" aparecem pretos sólidos na PCB real — provável código de protótipo desativado.

## Sprites — PC090OJ

Banco de cor: `sprite_colbank = 0x100 | ((sprite_ctrl & 0x3c) << 2)`.
Prioridade: sprites por cima de tudo (`pri_mask = 0`).

## C-Chip — portas de entrada

| Porta | Endereço 68000 | Bits |
|---|---|---|
| `PA` | `$F00007` | b5=START2, b6=START1, b7=SERVICE1 (activo baixo) |
| `PB` | `$F00009` | b0=COIN1, b1=COIN2 (activo **alto**, impulso) |
| `PC` | `$F0000B` | b0=TILT, b2=CIMA, b3=BAIXO, b4=ESQ, b5=DIR, b6=BOTÃO1 (activo baixo, 4-way) |
| `AD` | `$F0000D` | cocktail P2: b1=CIMA, b2=BAIXO, b4=DIR, b5=BOTÃO1, b7=ESQ |

Saída `PB` do C-Chip → contadores/travas de moeda:
b4=counter1, b5=counter2, b6=lockout1, b7=lockout2.

DSWA e DSWB chegam ao 68000 **através do Z80**, gravados em `$10002C` e `$10002E`
(isto é, `$2C(A5)` e `$2E(A5)` — **A5 = `$100000`**, um ponteiro de base global importante).

## DIP switches

### DSWB (`$10002E`)

| Bits | Função | Valores |
|---|---|---|
| `0x03` | Bônus de vida | `02`=20k/40k/120k/480k/2400k · `03`=50k/150k/600k/3000k · `01`=70k/280k/1400k · `00`=100k/500k |
| `0x0C` | Dificuldade | `08`=Fácil · `0C`=Médio · `04`=Difícil · `00`=Muito difícil |
| `0x30` | Vidas | `30`=3 · `20`=4 · `10`=5 · `00`=6 |
| `0x40` | 32768 vidas (cheat) | `40`=off · `00`=on |
| `0x80` | Idioma | `80`=Japonês · `00`=Inglês |

## Mapa das ROMs (região `maincpu`, 1 MB)

Intercalado por byte: o ficheiro em offset par fornece o **byte alto** (D15-D8).

| Offset | Par (alto) | Ímpar (baixo) | Tamanho |
|---|---|---|---|
| `$00000` | `c04-12-1.30` | `c04-08-1.10` | 64 KB cada |
| `$20000` | `c04-11-1.29` | `c04-25-1.9` | 64 KB cada |
| `$80000` | `c04-20.7` | `c04-22.9` | 128 KB cada |
| `$C0000` | `c04-19.6` | `c04-21.8` | 128 KB cada |

`$00000–$3FFFF` = código; `$80000–$FFFFF` = dados gráficos da camada bitmap.

## Mapa das ROMs (região `pc090oj`, 768 KB — sprites 16×16)

| Offset | Par | Ímpar | Tamanho |
|---|---|---|---|
| `$00000` | `c04-16.2` | `c04-18.4` | 128 KB cada |
| `$40000` | `c04-15.1` | `c04-17.3` | 128 KB cada |
| `$80000` | `c04-10.15` | `c04-09.14` | 64 KB cada |
| `$A0000` | *(reload de `c04-10.15`)* | *(reload de `c04-09.14`)* | espelho |

## Outras regiões

- `audiocpu`: `c04-06.71` em `$0000`, 32 KB.
- `cchip:cchip_eprom`: `cchip_c04-23` em `$0000`, 8 KB.
- `proms` (**não usadas** pelo MAME): `c04-4-1.3` (MB7116H) e `c04-5.75` (MB7124E), 512 B cada.
  **Resolvido empiricamente** (`tools/romtool.py`): em `c04-4-1.3` todos os 512 bytes são
  `<= $0F`, ou seja é mesmo uma PROM 512×4 com o nibble alto a zero. `c04-5.75` usa os 8 bits
  (máximo `$FF`), logo é 512×8. Em nenhuma das duas a 1ª metade é igual à 2ª — não são
  duplicações, os 512 bytes são todos significativos.

---

# Achados empíricos (derivados do binário, não do MAME)

Tudo abaixo foi medido a partir de `build/maincpu.bin` por `tools/romtool.py`.

## Tabela de vetores de exceção

| Vetor | Endereço | Valor | Nota |
|---|---|---|---|
| 0 | `$000000` | `$00103FFE` | SSP inicial — topo da RAM |
| 1 | `$000004` | `$000014B8` | PC inicial |
| 28 | `$000070` | `$00000400` | **Autovector IRQ nível 4 (VBLANK)** — o handler principal |
| 2–11, 47 | — | `$0011xxxx` | **fora do mapa de memória** (a RAM acaba em `$103FFF`) |
| 12–24, 48–63 | — | `$FFFFFFFF` | EPROM apagada |
| TRAPs #0–#14, IRQ 1/2/3/5/6 | — | `$00000000` | não usados |

Os vetores `$0011xxxx` (`$1100B8` para TRAP #15, mais `$1100CC`, `$1100E8`, `$110108`,
`$110130`, `$110150`, `$110174`, `$11019A`, `$1101C4`, `$1101DE`, `$110202`) são restos dos
handlers do **sistema de desenvolvimento** usado pela Taito, deixados na EPROM final. Na PCB
real, qualquer uma destas exceções trava a máquina. **Não são código a desmontar.**

## Segmentação real da ROM de programa

| Faixa | Conteúdo |
|---|---|
| `$000000–$0000FF` | tabela de vetores |
| `$000100–$0003FF` | `$FF` (vazio) |
| `$000400–$029BFF` | **código** — 169 984 bytes contíguos; não há código depois disto |
| `$029C00–$02FFFF` | `$FF` |
| `$030000–$0329FF` | tabelas esparsas (entropia 1.89) |
| `$032A00–$039DFF` | dados estruturados (entropia 3.78) |
| `$039E00–$03FEFF` | `$FF` |
| `$03FFFE` | word de região = `$0003` (Mundo) |
| `$040000–$07FFFF` | buraco da região — nenhum ficheiro carrega aqui |
| `$080000–$0F81FF` | gráficos da camada bitmap; buraco de 1 KB em `$0BFC00–$0BFFFF` |
| `$0F8200–$0FFFFF` | `$FF` |

Repare que os gráficos acabam em `$0F81FF`, **não** em `$0FFFFF`.

## Início do handler de VBLANK (`$000400`)

```
$000400  ori.w   #$f00,sr                 ; mascara interrupções
$000404  movem.l d0-d7/a0-a4/a6,-(a7)     ; salva contexto
$000408  move.b  d0,$700001.l             ; PC090OJ sprite_ctrl
$00040E  jsr     $27da.l
$000414  move.w  $d00000.l,$5a(a5)        ; status de colisão -> $10005A
```

Isto dá dois símbolos de graça: `irq4_vblank_handler` em `$000400` e um campo de RAM em
`$10005A` que guarda o status de colisão lido do hardware.

## Início do reset (`$0014B8`) — confirma A5

```
$0014B8  move.w  #$0,$d00000.l            ; video_ctrl = 0
$0014C0  move.w  #$ffff,$600000.l         ; video_mask = todos os bits
$0014C8  lea     $100000.l,a5             ; A5 = base global
$0014CE  lea     $100000.l,a0             ; começa a limpar a RAM
```

## SHA-1 das imagens montadas (contrato estável, fixado nos testes)

| Imagem | Tamanho | SHA-1 |
|---|---|---|
| `maincpu.bin` | 1 048 576 | `6994b7ba1e3dfdc6225f57d69f5efb3e0f054265` |
| `audiocpu.bin` | 32 768 | `d71062f9d9b11492e13fc93982b95883f564f902` |
| `cchip_eprom.bin` | 8 192 | `73aa2267eb468c5aa5db67183047e9aef8321215` |
| `pc090oj.bin` | 786 432 | `e4e2d054f27e013f0ce84d16f76355588b9d053b` |
