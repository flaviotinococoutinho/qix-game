# 04 — C-Chip TC0030CMD

O terceiro processador de Volfied. Faz duas coisas: lê os controlos e as moedas, e responde a
perguntas aritméticas que o 68000 não sabe responder sozinho. Sem ele o jogo não passa do
reset.

Este documento é o tratado do subsistema. O mapa de endereços resumido está em
[`docs/02-mapa-de-memoria.md`](02-mapa-de-memoria.md) §2.11 e §5, e o enquadramento na placa
em [`docs/01-hardware.md`](01-hardware.md) §8; aqui não se repete nenhum dos dois — descreve-se
o **protocolo** e o **firmware**, instrução a instrução, ao nível a que se pode reimplementar.

Fontes, e nada além delas:

| Artefacto | O que dá |
|---|---|
| [`src/cchip/cchip.asm`](../src/cchip/cchip.asm) | a EPROM de 8 KB desmontada por tracado recursivo |
| [`src/cchip/cchip_linear.asm`](../src/cchip/cchip_linear.asm) | varrimento linear especulativo + o relatório que separa código de dados |
| [`build/cchip_map.json`](../build/cchip_map.json) | mapa da EPROM: despacho, alvos externos, 45 acessos à janela |
| [`reference/mame/taitocchip.cpp`](../reference/mame/taitocchip.cpp) e `.h` | o modelo do dispositivo, e o que os seus autores dizem não saber |
| [`reference/mame/volfied.cpp`](../reference/mame/volfied.cpp) | como o chip está ligado nesta placa |
| [`reference/mame/upd7810.cpp`](../reference/mame/upd7810.cpp), `upd7810_opcodes.cpp` | a semântica de cada instrução citada |
| `src/main68k/*.asm` | o outro lado da janela |
| `roms/volfied/cchip_c04-23` | 8192 bytes, SHA-1 `73aa2267eb468c5aa5db67183047e9aef8321215` |

Nos excertos da EPROM foram cortados os comentários automáticos longos que o desmontador
acrescenta no fim da linha; endereço, bytes e instrução estão como na listagem.

---

## 1. O chip

O TC0030CMD é um encapsulamento de 64 pinos com **quatro dies**. A lista vem do cabeçalho de
`taitocchip.cpp`, que a tira dos esquemas de *Operation Wolf*:

| Die | Peça | Papel |
|---|---|---|
| 1 | NEC uPD78C11 + 4 KB de ROM máscara interna | o processador; a ROM interna é assumida igual entre jogos |
| 2 | uPD27C64, EPROM de 8 KB | código específico do jogo — aqui `cchip_c04-23`, o que este projecto desmonta |
| 3 | uPD4464, SRAM de 8 KB | partilhada com o 68000, vista por janelas de 1 KB |
| 4 | ASIC (ULA da NEC) | árbitro do barramento; gera o `/DTACK` (pino 34, `/CDTA`) e guarda 4 bytes de estado |

`volfied.cpp` linha 401 dá o relógio:

```c
TAITO_CCHIP(config, m_cchip, 20_MHz_XTAL / 2); // 20MHz OSC next to C-Chip
```

10 MHz; o 78C11 corre a `DERIVED_CLOCK(1, 1)`, os mesmos 10 MHz.

Os pinos que interessam a Volfied: PA0-PA7, PB0-PB7, PC0-PC7 (três portos de 8 bits
bidireccionais), AN0-AN7 (oito entradas analógicas), `/INT1` (pino 54) e `/NMI` (pino 53). O
cabeçalho anota que AN7 está ligado à massa e AN2 ao VCC externamente, e que `/NMI` é usado no
*Rainbow Islands* — não aqui.

A combinação MODE0/MODE1 do C-Chip é LOW/HIGH: arranca na ROM interna em `$0000-$0FFF` e o
mapa fica sob controlo do MCU. É por isso que a EPROM externa aparece em `$2000` e não em
`$0000`.

O 68000 nunca toca nos pinos. Fala com a SRAM partilhada, e é o firmware do C-Chip que copia
num sentido e no outro, uma vez por frame. Essa indirecção **é** a protecção.

---

## 2. A lacuna: a ROM interna de 4 KB

**A ROM máscara de 4 KB do uPD78C11 não está em `roms/volfied/`.** O único ficheiro do C-Chip
no conjunto é `cchip_c04-23`, 8192 bytes — a EPROM externa. Confirmado por `ls roms/volfied/`
e por `build/cchip_eprom.bin` ser a única imagem do chip que `romtool.py` monta.

O que isso implica, em concreto e não em geral:

1. **Os vectores.** No uPD7810, uma interrupção empilha PSW/PCH/PCL e salta para um endereço
   fixo abaixo de `$0030` (`upd7810_take_irq`, `upd7810.cpp` linhas 835-945). Todos esses
   endereços estão dentro dos 4 KB internos. Não sabemos, por leitura, que vector alcança que
   ponto de entrada da EPROM — só o podemos deduzir pela forma de cada rotina (§9).
2. **CALT e CALF.** `CALT` calcula `$0080 + 2*(opcode & $1F)` e salta pelo ponteiro que lá
   estiver (`upd7810_opcodes.cpp`, `CALT()`); `CALF` salta para `$0800-$0FFF`. As duas tabelas
   são internas. A EPROM usa `CALT` exactamente uma vez, em `$2027`.
3. **Sete rotinas internas** são chamadas de fora e não podem ser lidas (§10).
4. **Ninguém na EPROM escreve o byte de estado da ASIC** que o 68000 espera no arranque —
   e o arranque bloqueia até esse byte valer `$01` (§6.3). É a demonstração mais limpa de que
   a lacuna tem consequências: o handshake de reset não se explica com os artefactos locais.
5. **Existe código órfão na EPROM** que nenhum caminho traçado alcança e que só pode ser
   chamado de dentro (§12, `$2125`).

O MAME tem um dump da ROM interna:

```c
ROM_START( taito_cchip )
	ROM_REGION( 0x1000, "upd7811", 0 )
	// optically extracted, the internal checksum passes, although that doesn't rule out the possibility of error
	ROM_LOAD( "cchip_upd78c11.bin", 0x0000, 0x1000, CRC(43021521) SHA1(73bc4b46cd2d6805ec926f39f22af00e38a3f822) )
ROM_END
```

**Não o verificámos nem o usámos.** É apenas a razão pela qual o MAME consegue correr o jogo e
este projecto não consegue fechar o raciocínio sozinho. Onde este documento disser "a ROM
interna faz X", é dedução a partir de chamadas e de comportamento observável, nunca leitura.

Uma segunda lacuna, de outra natureza: a SRAM de 8 KB e os 4 bytes da ASIC são **voláteis**.
Nada do que lá está pode ser conhecido estaticamente; só se infere de quem escreve e quem lê.

---

## 3. O que o MAME modela — e o que diz não saber

Vale separar as duas coisas, porque metade do que se sabe sobre o C-Chip é modelo e não
medição. O modelo, de `taito_cchip_device`:

```c
void taito_cchip_device::cchip_map(address_map &map)
{
	//map(0x0000, 0x0fff).rom(); // internal ROM of uPD7811
	map(0x1000, 0x13ff).bankrw(m_upd4464_bank);
	map(0x1400, 0x17ff).rw(FUNC(taito_cchip_device::asic_r), FUNC(taito_cchip_device::asic_w));
	map(0x2000, 0x3fff).rom().region("cchip_eprom", 0);
}
```

| Faixa (espaço do 78C11) | Conteúdo |
|---|---|
| `$0000-$0FFF` | ROM máscara interna, 4 KB — **não dumpada** |
| `$1000-$13FF` | janela de 1 KB na SRAM de 8 KB; banco escolhido por `$1600` |
| `$1400-$15FF` | 4 bytes de RAM da ASIC, espelhados (`offset & 3`) |
| `$1600` | selector de banco, **lado do MCU**, 3 bits |
| `$1601-$17FF` | continua a cair em `asic_ram[offset & 3]` na escrita |
| `$2000-$3FFF` | a EPROM de 8 KB — o que está desmontado |
| `$FF00-$FFFF` | RAM interna do 78C11, 256 bytes |

`asic_r` devolve `m_asic_ram[offset & 3]` para `offset < $200` e `$00` daí para cima;
`asic_w`/`asic68_w` tratam `offset == $200` como banco e tudo o resto como escrita em
`m_asic_ram[offset & 3]`. `device_start` põe os quatro bytes a zero e ambos os bancos na
entrada 0.

O que o próprio cabeçalho de `taitocchip.cpp` declara **não** saber, textualmente:

| Registo (vista externa) | Nota do MAME |
|---|---|
| `0x400` | *"unknown, no idea if /DTACK is asserted for R or W here"* |
| `0x401` | *"RW 'test command/status register'"*, `$01` = ok/pronto, `$04` = erro, escrever `$02` arranca o modo de teste; *"very likely handled by the internal rom"*; duas hipóteses alternativas sobre o porto F, ambas marcadas como palpite |
| `0x402-0x5ff` | *"unknown (may be mirror of 0x400 and 0x401?)"* |
| `0x600` | banco, *"only low 3 bits are valid… not sure if readable"* |
| `0x601-0x7ff` | *"unknown"* |

Ou seja: a região da ASIC é modelada por conveniência, não por conhecimento. Tudo o que este
documento disser sobre `$F00801-$F00FFF` além do que o jogo efectivamente usa herda essa
incerteza.

Do lado da placa, `volfied.cpp` liga (linhas 401-410):

```c
m_cchip->in_pa_callback().set_ioport("F00007");
m_cchip->in_pb_callback().set_ioport("F00009");
m_cchip->in_pc_callback().set_ioport("F0000B");
m_cchip->in_ad_callback().set_ioport("F0000D");
m_cchip->out_pb_callback().set(FUNC(volfied_state::counters_w));
```

`out_pa_callback` e `out_pc_callback` **não estão ligados a nada**. E as oito entradas
analógicas são reconstruídas bit a bit a partir de um só porto:

```c
upd.an0_func().set([this] { return BIT(m_in_ad_cb(), 0) ? 0xff : 0; });
```

e assim para AN1-AN7. Isto casa exactamente com o que a EPROM faz em `sub_2028` (§7.3) — é
uma confirmação cruzada independente, porque nenhuma das duas peças foi escrita a olhar para
a outra.

O VBLANK alimenta as duas CPUs ao mesmo tempo:

```c
INTERRUPT_GEN_MEMBER(volfied_state::interrupt)
{
	m_maincpu->set_input_line(4, HOLD_LINE);
	m_cchip->ext_interrupt(ASSERT_LINE);
	m_cchip_irq_clear->adjust(attotime::zero);
}
```

`ext_interrupt` põe `UPD7810_INTF1`. O temporizador de atraso zero limpa-o logo a seguir, ou
seja `/INT1` é modelado como um impulso, não como um nível. **Não há semáforo nenhum** entre
os dois processadores: acordam ambos, no mesmo frame, sobre a mesma memória.

---

## 4. A janela partilhada

### 4.1 Aritmética de endereços

Do lado do 68000 são duas faixas (`volfied.cpp`, linhas 275-276):

```c
map(0xf00000, 0xf007ff).rw(m_cchip, FUNC(taito_cchip_device::mem68_r), FUNC(taito_cchip_device::mem68_w)).umask16(0x00ff);
map(0xf00800, 0xf00fff).rw(m_cchip, FUNC(taito_cchip_device::asic_r), FUNC(taito_cchip_device::asic68_w)).umask16(0x00ff);
```

O `umask16(0x00ff)` é a peça central: **cada byte do C-Chip aparece no byte ímpar de uma word
do 68000.** A conversão, nos dois sentidos:

```
68000 = $F00001 + 2 * (cchip - $1000)      janela de SRAM   $1000-$13FF
68000 = $F00801 + 2 * (cchip - $1400)      região da ASIC   $1400-$17FF

cchip = $1000 + (a68 - $F00001) / 2        a68 ímpar em $F00001-$F007FF
```

Duas consequências práticas que aparecem por todo o código do 68000:

- **Um word de dados do C-Chip ocupa 4 bytes de espaço de endereços do 68000.** É por isso
  que `pal_read_cchip_words` (`$015CD4`, [`palette_effects.asm`](../src/main68k/palette_effects.asm))
  lê o byte alto em `$2(a0)`, o baixo em `$0(a0)` e avança `lea $4(a0),a0`.
- **Um `move.w` num endereço par serve para escrever um byte ímpar.** `boss09` faz
  `move.w #$AA,$F0000A`: o byte baixo da word aterra em `$F0000B`. `move.w #$2,$F00C00`
  aterra em `$F00C01`. O byte alto vai para um endereço não mapeado e perde-se.

`mem68_r`/`mem68_w` indexam a SRAM com `offset & 0x03ff` (ver `taitocchip.h`), pelo que os
`$800` bytes de `$F00000-$F007FF` correspondem exactamente aos `$400` bytes do banco activo.

### 4.2 Os dois registos de banco

Há **dois selectores independentes**, e é isso que torna o protocolo possível:

| Registo | Quem escreve | Onde | Estado inicial |
|---|---|---|---|
| `m_upd4464_bank` | o MCU | `$1600` no espaço do 78C11 | banco 0 (`device_start`) |
| `m_upd4464_bank68` | o 68000 | `$F00C01` | banco 0 (`device_start`) |

Os dois apontam para a mesma SRAM de 8 KB: `configure_entries(0, 8, &m_sharedram[0], 0x400)`.
Bancos diferentes vêem bytes físicos diferentes; bancos iguais vêem o mesmo byte.

A EPROM confirma o seu banco logo à cabeça:

```
entry_201E:
        di                              ; $201E: BA
        mvi     a,$E8                   ; $201F: 69 E8
        mov     (CCHIP_BANK_MCU),a      ; $2021: 70 79 00 16
```

`$E8 & 7 = 0` — banco 0. Só contam os 3 bits baixos (`set_entry(data & 0x7)`). O byte cheio
`$E8` não tem explicação; os 5 bits altos são ignorados pelo modelo do MAME.

O lado do 68000 tem uma rotina dedicada:

```
cchip_select_bank:
        move.b  d0,CCHIP_BANK68                                         ; $0017B8  13c000f00c01
        nop                                                             ; $0017BE  4e71
        nop                                                             ; $0017C0  4e71
        nop                                                             ; $0017C2  4e71
        move.b  d0,$70(a5)              ; g_cchip_bank68_shadow ($100070)  $0017C4  1b400070
        rts                                                             ; $0017C8  4e75
```

### 4.3 A região da ASIC vista do 68000

`asic68_w` só trata `offset == $200` como banco; **qualquer outro offset escreve em
`m_asic_ram[offset & 3]`**. `asic_r` devolve a RAM para `offset < $200` e `$00` daí para
cima. Traduzido para endereços do 68000:

| 68000 | offset | Comportamento no modelo do MAME |
|---|---|---|
| `$F00801` | `$000` | RAM da ASIC byte 0 — R/W |
| `$F00803` | `$001` | RAM da ASIC byte 1 = *test command/status register* — R/W |
| `$F00805`, `$F00807` | `$002`, `$003` | bytes 2 e 3 — R/W |
| `$F00809-$F00BFF` | `$004-$1FF` | espelho dos quatro bytes (`& 3`) |
| `$F00C01` | `$200` | **selector de banco, lado do 68000** — só escrita |
| `$F00C03-$F00FFF` | `$201-$3FF` | escrita cai outra vez em `asic_ram[offset & 3]`; leitura devolve `$00` |

O jogo usa exactamente dois destes endereços: `$F00803` no arranque e `$F00C01`/`$F00C00`
para o banco.

---

## 5. A multiplexagem: mesmos offsets, bancos diferentes

Esta é a ideia central do protocolo, e é fácil de não ver a ler a listagem — porque o
desmontador atribui nomes **por endereço**, e o endereço não diz nada sobre o banco.

Os mesmos offsets `$1000-$1006` servem três coisas incompatíveis:

- **banco 0** — o espelho de entradas e saídas: a fotografia dos portos PA/PB/PC e do A/D que
  o firmware tira uma vez por frame, mais os três bytes que o 68000 quer ver escritos de volta
  nos portos;
- **banco 1** — a caixa de correio do desafio da tabela de ritmos;
- **banco 2** — a caixa de correio da ALU de protecção.

Nunca colidem porque cada tarefa começa por seleccionar o seu banco, e os dois lados
concordam sobre qual é:

```
sub_217B:
        call    introm_select_bank_0    ; $217B: 40 23 0F

rate_table_service:
        call    introm_select_bank_0    ; $225A: 40 23 0F
        ...
        call    introm_select_bank_1    ; $2264: 40 32 0F

prot_alu_command:
        call    introm_select_bank_2    ; $2308: 40 3B 0F
```

e do lado do 68000, para as mesmas três transacções:

```
$00165A  move.b  #$1,CCHIP_BANK68        ; desafio da tabela de ritmos
$01A0B2  move.w  #$2,CCHIP_REG+$400      ; comando da ALU
$000E4C  move.b  #$0,CCHIP_BANK68        ; leitura de entradas
```

Três coincidências independentes entre um firmware e um jogo que foram desmontados
separadamente. É também a prova mais forte de que `$0F23`/`$0F32`/`$0F3B` são mesmo os
selectores de banco 0/1/2 da ROM interna (§10).

### 5.1 Mapa completo dos offsets usados

Coluna **Banco**: qual o banco em que o acesso acontece. Onde diz "N" é o banco variável que
o desafio da tabela de ritmos escolhe (1..7).

| C-Chip | 68000 | Banco | Papel | Escrito por | Lido por |
|---|---|---|---|---|---|
| `$1000` | `$F00001` | 0 | byte de arranque `$FD` | 68000 `$0016D0` | ninguém que se veja |
| `$1000` | `$F00001` | 1 | byte de desafio | 68000 `$001670` (**mas ver §12**) | MCU `$2267` |
| `$1001` | `$F00003` | 0 | byte de arranque `$0F` | 68000 `$0016D8` | — |
| `$1001` | `$F00003` | N ou 1 | resposta ao desafio (`$FF` = falhou) | MCU `$2280` / `$2291` | ninguém no 68000 |
| `$1002` | `$F00005` | 0 | byte de arranque `$FF` | 68000 `$0016E0` | — |
| `$1002` | `$F00005` | 1 | contador `b` da busca = `6 − coluna` | MCU `$226E` | — |
| `$1003` | `$F00007` | 0 | PA lido: b5 START2, b6 START1, b7 SERVICE1 (activo baixo) | MCU `$2180` | 68000 |
| `$1003` | `$F00007` | 1 | contador `c` da busca = `15 − linha` | MCU `$2272` | — |
| `$1004` | `$F00009` | 0 | PB lido: b0 COIN1, b1 COIN2 (activo **alto**, impulso) | MCU `$218C` | 68000 |
| `$1004` | `$F00009` | 2 | comando da ALU; `$00` = ocioso | 68000 `$01A0CA`; limpo pelo MCU em `$234F` | MCU `$230B`, `$2312` |
| `$1005` | `$F0000B` | 0 | PC lido: b0 TILT, b2-b5 joystick 4 vias, b6 botão | MCU `$219A` | 68000 |
| `$1005` | `$F0000B` | 2 | operando A à entrada, **resultado** à saída | 68000 `$01A0BA`, MCU `$2345` | 68000 `$01A0F8` |
| `$1006` | `$F0000D` | 0 | A/D empacotado: manete do P2 em cocktail | MCU `$21A7` | 68000 |
| `$1006` | `$F0000D` | 2 | operando B; devolvido inalterado | 68000 `$01A0C2`, MCU `$2349` | — |
| `$1007` | `$F0000F` | 0 | PA a escrever → copiado para PA | 68000 (nenhum sítio) | MCU `$2184` |
| `$1008` | `$F00011` | 0 | PB a escrever → **XOR `$30`** → PB | 68000 `$00683E` e mais 5 sítios | MCU `$2190` |
| `$1009` | `$F00013` | 0 | PC a escrever → copiado para PC | 68000 (nenhum sítio) | MCU `$219E` |
| `$100A` | `$F00015` | 0 | comando de porta (1/2/3) | 68000 `$0016F8` | MCU `$20DC` |
| `$100B` | `$F00017` | 0 | argumento 0 | 68000 `$0016E8` | MCU `$20F3`/`$2103`/`$2113` |
| `$100C` | `$F00019` | 0 | argumento 1 | 68000 `$0016F0` | MCU `$20FC`/`$210C`/`$211C` |
| `$1010-$104F` | `$F00021-$F0009F` | N | tabela de ritmo, 16 × 3 bytes (só 48 dos 64 copiados são lidos) | MCU `$228A`/`$229B` | 68000 `$008290` |
| `$1010-$10AF` | `$F00021-$F0015F` | 0 | dados da ronda: 160 bytes = 80 words | MCU (5 × `copy32_to_shared`) | 68000 `$015CAA` |
| `$1023` | `$F00047` | 0 | índice de paleta da ronda | MCU `$2244` | 68000 `$015C22` |
| `$13FE` | `$F007FD` | 0 | handshake dos dados de ronda | ambos | ambos |
| `$13FF` | `$F007FF` | 0 | handshake da tabela de ritmos | ambos | ambos |
| `$1400` | `$F00801` | — | RAM da ASIC byte 0; o MCU escreve `$40` uma vez | MCU `$216C` | ninguém |
| `$1401` | `$F00803` | — | estado / comando de teste | **ninguém na EPROM** | 68000 `$0016B0`, `$0016BA` |
| `$1600` | `$F00C01` | — | banco, lado do MCU | MCU `$2021` | — |

`$1023` cai **dentro** do bloco de 160 bytes dos dados de ronda: é o byte alto da word 9.
Não é conflito porque as duas transacções são sequenciais e o 68000 faz sempre os dados
primeiro — ver §8.3.

`build/cchip_map.json` regista **45 acessos** da EPROM à janela, distribuídos assim:
`$1000`×1, `$1001`×2, `$1002`×1, `$1003`×2, `$1004`×4, `$1005`×3, `$1006`×3, `$1007`×1,
`$1008`×1, `$1009`×1, `$100A`×3, `$100B`×3, `$100C`×3, `$1010`×3, `$1023`×1, `$13FE`×9,
`$13FF`×2, `$1400`×1, `$1600`×1.

### 5.2 Armadilha ao ler a listagem

Os símbolos `CC_IN_PA`/`CC_IN_PB`/`CC_IN_PC`/`CC_IN_AD` e `CMD_BYTE`/`CMD_ARG0`/`CMD_ARG1` de
[`symbols/cchip.sym`](../symbols/cchip.sym) estão colados aos endereços `$1003`-`$1006`.
Aparecem, com o mesmo nome, em `$2272`, `$230B`, `$2312`, `$2316`, `$231A`, `$2345`, `$2349` e
`$234F` — sítios onde o MCU **não** está no banco 0 e onde, portanto, o nome descreve o outro
papel. **Confira sempre qual foi o último `introm_select_bank_*` antes de interpretar um
acesso à janela.** O aviso está também no cabeçalho de
[`symbols/fragments/cchip/cchip_side.sym`](../symbols/fragments/cchip/cchip_side.sym).

---

## 6. Arranque

### 6.1 Lado do 68000 — `cchip_boot_handshake` (`$0016B0-$001711`)

Chamado uma vez, de `reset_entry`, em `$001534`
([`reset_and_dipswitch_setup.asm`](../src/main68k/reset_and_dipswitch_setup.asm)).

```
cchip_boot_handshake:
        cmpi.b  #$5,CCHIP_ASIC_STATUS                                   ; $0016B0  0c39000500f00803
        beq.b   loc_00170A                                              ; $0016B8  6750
        cmpi.b  #$1,CCHIP_ASIC_STATUS                                   ; $0016BA  0c39000100f00803
        bne.b   cchip_boot_handshake                                    ; $0016C2  66ec
        bsr.w   cchip_clear_all_banks                                   ; $0016C4  6100004c
        move.w  #$0,d0                                                  ; $0016C8  303c0000
        bsr.w   cchip_select_bank                                       ; $0016CC  610000ea
        move.b  #$FD,CCHIP_RAM+$1                                       ; $0016D0  13fc00fd00f00001
        move.b  #$F,CCHIP_RAM+$3                                        ; $0016D8  13fc000f00f00003
        move.b  #$FF,CCHIP_RAM+$5                                       ; $0016E0  13fc00ff00f00005
        move.b  #$2,CCHIP_RAM+$17                                       ; $0016E8  13fc000200f00017
        move.b  #$0,CCHIP_RAM+$19                                       ; $0016F0  13fc000000f00019
        move.b  #$1,CCHIP_RAM+$15                                       ; $0016F8  13fc000100f00015
        move.b  #$2,CCHIP_ASIC_STATUS                                   ; $001700  13fc000200f00803
        rts                                                             ; $001708  4e75
loc_00170A:
        jsr     (spr_clear_text_area).l                                 ; $00170A  4eb900000e9a
loc_001710:
        bra.b   loc_001710                                              ; $001710  60fe
```

Por ordem:

1. Espera que `$F00803` valha `$01`. Se valer `$05` (pronto **e** erro, segundo o cabeçalho do
   MAME: b0 = ok, b2 = erro) limpa a área de texto e **trava numa `bra` sobre si própria**.
   Sem C-Chip a máquina não sai daqui — é um `bne` de volta ao princípio.
2. `cchip_clear_all_banks` (`$001712`) escreve `$00` nos 1024 bytes ímpares de cada um dos 8
   bancos. Repare que só há **sete** `bsr` explícitos: depois de seleccionar o banco 7 em
   `$001790` a rotina **cai** em `cchip_clear_bank` (`$00179E`), que termina com o `rts`.
   Efeito líquido: os 8 KB de SRAM ficam a zero.
3. Selecciona o banco 0 e escreve `$FD`, `$0F`, `$FF` em `$F00001`, `$F00003`, `$F00005`.
4. Arma a caixa de correio do comando de porta: argumento 0 = `$02`, argumento 1 = `$00`,
   comando = `$01`.
5. Escreve `$02` em `$F00803` — o *"writing a 0x02 here starts test mode"* do cabeçalho de
   `taitocchip.cpp`. Não espera por resposta nenhuma a seguir.

**Observação não explicada.** Os três bytes do passo 3 — `$FD`, `$0F`, `$FF` — são exactamente
os três valores de modo de porto que a EPROM programa em `entry_214F`, e pela mesma ordem
(MA, MB, MC). Mas a EPROM usa imediatos e **nunca lê** `$1000-$1002` no banco 0. Ou é a ROM
interna que os consome, ou é duplicação vestigial de um firmware genérico. `docs/02` chama-lhes
MA/MB/MC; é uma leitura razoável, mas é inferência a partir da coincidência de valores, não
leitura de código.

### 6.2 Lado do C-Chip — `entry_214F` (`$214F-$217A`)

```
entry_214F:
        call    introm_select_bank_0    ; $214F: 40 23 0F
        mvi     pa,$02                  ; $2152: 64 00 02
        mvi     a,$FD                   ; $2155: 69 FD
        mov     ma,a                    ; $2157: 4D D2
        mvi     pb,$F0                  ; $2159: 64 01 F0
        mvi     a,$0F                   ; $215C: 69 0F
        mov     mb,a                    ; $215E: 4D D3
        mvi     pc,$00                  ; $2160: 64 02 00
        mvi     a,$FF                   ; $2163: 69 FF
        mov     mc,a                    ; $2165: 4D D4
        call    sub_217B                ; $2167: 40 7B 21
        mvi     a,$40                   ; $216A: 69 40
        mov     (ASIC_RAM0),a           ; $216C: 70 79 00 14
        mvi     a,$01                   ; $2170: 69 01
        mov     ($FF9B),a               ; $2172: 70 79 9B FF
        mvi     mkl,$D7                 ; $2176: 64 07 D7
        ei                              ; $2179: AA
loc_217A:
        jr      loc_217A                ; $217A: FF
```

MA/MB/MC são máscaras de direcção onde **1 = entrada**. Em `upd7810.cpp`, `WP()`:

```c
case UPD7810_PORTA:
	m_pa_out = data;
	data = (data & ~m_ma) | (m_pa_pullups & m_ma);
	m_pa_out_cb(data);
```

Logo:

| Porto | Máscara | Bits de saída | Latch inicial |
|---|---|---|---|
| PA | `MA = $FD` | só b1 | `$02` |
| PB | `MB = $0F` | b4-b7 | `$F0` |
| PC | `MC = $FF` | nenhum | `$00` |

Os quatro bits de saída de PB são precisamente os que `counters_w` consome:

```c
void volfied_state::counters_w(uint8_t data)
{
	machine().bookkeeping().coin_lockout_w(1, data & 0x80);
	machine().bookkeeping().coin_lockout_w(0, data & 0x40);
	machine().bookkeeping().coin_counter_w(1, data & 0x20);
	machine().bookkeeping().coin_counter_w(0, data & 0x10);
}
```

`MKL = $D7 = %11010111`. No despachante `upd7810_take_irq` um bit a **0** habilita:

| Bit de MKL | Valor em `$D7` | Fonte | Vector |
|---|---|---|---|
| `$08` | 0 | **INTF1** — o pino `/INT1`, ligado ao VBLANK | `$0010` |
| `$20` | 0 | **INTFE0** — captura de evento 0 | `$0018` |
| restantes | 1 | mascarados | — |

`$FF9B` = 1 é o estado de repouso do guarda de reentrância (§7.1). Depois do `ei`, o programa
principal do C-Chip é um `jr` sobre si próprio: **tudo o que o chip faz acontece dentro de
interrupções.**

### 6.3 Quem escreve o byte de estado `$F00803`?

`$F00803` é `asic_ram[1]`, isto é `$1401` do lado do MCU. Da lista de acessos em
`build/cchip_map.json`, a EPROM toca a região da ASIC em **exactamente dois sítios**: `$1400`
(uma vez, `$216C`, valor `$40`) e `$1600` (uma vez, `$2021`). **`$1401` nunca é escrito pela
EPROM.**

`device_start` põe `m_asic_ram[0..3] = 0`. O 68000 fica preso no `bne` de `$0016C2` enquanto
`$F00803 != $01`. Portanto o byte tem de vir de outro lado: da ROM interna (é o que o
cabeçalho de `taitocchip.cpp` supõe — *"very likely handled by the internal rom"*) ou do
hardware da ASIC que ele especula estar ligado aos bits altos do porto F. **Não podemos
decidir sem os 4 KB.** No MAME o jogo arranca porque a ROM interna está lá e escreve o byte;
com os artefactos deste projecto o arranque é inexplicável.

---

## 7. O frame

Todo o código do 68000 que toca no C-Chip corre **dentro** do handler de nível 4
([`irq_vblank_dispatch.asm`](../src/main68k/irq_vblank_dispatch.asm)), que começa em `$000400`
com `ori.w #$f00,sr` e termina em `$000480` com `rte` — máquina de estados do jogo incluída,
despachada por `game_state_jumptable` em `$00046E`. Não há preempção: dentro de um frame, a
sequência de acessos à janela é determinística.

Do lado do C-Chip, todo o trabalho está no handler alcançado pela entrada 0 da tabela de
despacho.

### 7.1 `entry_2093` — o prólogo e o guarda de reentrância

```
entry_2093:
        di                              ; $2093: BA
        push    va                      ; $2094: B0
        push    bc                      ; $2095: B1
        push    de                      ; $2096: B2
        push    hl                      ; $2097: B3
        push    ea                      ; $2098: B4
        mov     a,($FF9B)               ; $2099: 70 69 9B FF
        nei     a,$00                   ; $209D: 67 00
        jr      loc_20BD                ; $209F: DD
        call    sub_20D2                ; $20A0: 40 D2 20
        mvi     a,$00                   ; $20A3: 69 00
        mov     ($FF9B),a               ; $20A5: 70 79 9B FF
        ei                              ; $20A9: AA
        call    sub_217B                ; $20AA: 40 7B 21
        call    sub_21AC                ; $20AD: 40 AC 21
        mvi     a,$01                   ; $20B0: 69 01
        mov     ($FF9B),a               ; $20B2: 70 79 9B FF
        pop     ea                      ; $20B6: A4
        pop     hl                      ; $20B7: A3
        pop     de                      ; $20B8: A2
        pop     bc                      ; $20B9: A1
        pop     va                      ; $20BA: A0
        ei                              ; $20BB: AA
        reti                            ; $20BC: 62
```

`NEI A,$00` é `SKIP_NZ`: engole a instrução seguinte se `A != 0`
(`upd7810_opcodes.cpp`, `NEI_A_xx`). Portanto:

- `$FF9B != 0` → o `jr` é engolido → caminho longo;
- `$FF9B == 0` → `loc_20BD`, caminho curto.

`$FF9B` vale 1 em repouso (posto em `$2172`), passa a 0 em `$20A5` e volta a 1 em `$20B2`.
Como o handler faz `ei` a meio (`$20A9`), um segundo `/INT1` pode chegar antes de o primeiro
acabar; nesse caso apanha `$FF9B == 0` e vai para:

```
loc_20BD:
        sspd    $FFB6                   ; $20BD: 70 0E B6 FF
        lxi     sp,$FFB4                ; $20C1: 04 B4 FF
        call    sub_20D5                ; $20C4: 40 D5 20
        lspd    $FFB6                   ; $20C7: 70 0F B6 FF
```

Guarda o SP em `$FFB6`, troca para uma pilha privada que cresce a partir de `$FFB4`, faz só o
serviço curto e repõe. É defesa contra estouro da RAM interna de 256 bytes.

Os dois caminhos diferem assim (`sub_20D2` é `call $09D0` e **cai** em `sub_20D5`, que é
`call sub_20DC` + `call $0FD5` + `ret`):

| | Longo (`$20A0`) | Curto (`$20C4`) |
|---|---|---|
| `introm_pre_frame_hook` (`$09D0`) | sim | **não** |
| `sub_20DC` — comando de porta | sim | sim |
| `introm_service_frame_tail` (`$0FD5`) | sim | sim |
| `sub_217B` — entradas/saídas/AD | sim | **não** |
| `sub_21AC` — as 8 tarefas | sim | **não** |

Repare na ordem: `sub_20D2` corre com as interrupções ainda desligadas e **antes** de o guarda
ser armado; o guarda cobre exactamente a parte que corre com `ei`.

### 7.2 `sub_217B` — entradas e saídas (`$217B-$21AB`)

O trabalho honesto do chip, e o único sítio onde os pinos são lidos.

```
sub_217B:
        call    introm_select_bank_0    ; $217B: 40 23 0F
        mov     a,pa                    ; $217E: 4C C0
        mov     (CC_IN_PA),a            ; $2180: 70 79 03 10
        mov     a,(CC_OUT_PA)           ; $2184: 70 69 07 10
        mov     pa,a                    ; $2188: 4D C0
        mov     a,pb                    ; $218A: 4C C1
        mov     (CMD_BYTE),a            ; $218C: 70 79 04 10
        mov     a,(CC_OUT_PB)           ; $2190: 70 69 08 10
        xri     a,$30                   ; $2194: 16 30
        mov     pb,a                    ; $2196: 4D C1
        mov     a,pc                    ; $2198: 4C C2
        mov     (CMD_ARG0),a            ; $219A: 70 79 05 10
        mov     a,(CC_OUT_PC)           ; $219E: 70 69 09 10
        mov     pc,a                    ; $21A2: 4D C2
        call    sub_2028                ; $21A4: 40 28 20
        mov     (CMD_ARG1),a            ; $21A7: 70 79 06 10
        ret                             ; $21AB: B8
```

(`CMD_BYTE`/`CMD_ARG0`/`CMD_ARG1` são `$1004`/`$1005`/`$1006` — aqui, no banco 0, são as
entradas PB/PC/AD. Ver §5.2.)

Três pares ler-porto/escrever-espelho e escrever-porto/ler-espelho, mais o A/D. Só PB tem
tratamento especial: `xri a,$30` inverte os bits 4 e 5 antes de irem para o pino. Consequência
exacta, cruzada com `counters_w`:

| Bit em `$F00011` | Depois do XOR | Efeito |
|---|---|---|
| b4 = 1 | PB b4 = 0 | contador 1 **desligado** |
| b4 = 0 | PB b4 = 1 | contador 1 **ligado** |
| b5 | idem | contador 2 |
| b6, b7 | passam directos | lockout 1, lockout 2 (activos altos) |

Isto fecha com [`coin_credit.asm`](../src/main68k/coin_credit.asm): `g_cchip_pb_out`
(`$10001E`) é pulsado 4 frames com o bit 4 a 1 e 4 frames a 0 (`$00681E-$00687E`), e
depositado em `$F00011` a cada mudança. O impulso que chega ao contador mecânico é, portanto,
a metade em que o 68000 tem o bit **a zero**.

### 7.3 `sub_2028` — o A/D empacotado (`$2028-$2091`)

Dois varrimentos de quatro canais, empacotados num só byte:

```
sub_2028:
        mvi     b,$00                   ; $2028: 6A 00
        mvi     anm,$06                 ; $202A: 64 80 06
        mvi     c,$FF                   ; $202D: 6B FF
loc_202F:
        dcr     c                       ; $202F: 53
        jr      loc_202F                ; $2030: FE
        mov     a,cr0                   ; $2031: 4C E0
        eqi     a,$80                   ; $2033: 77 80
        skn     cy                      ; $2035: 48 1A
        jr      loc_203C                ; $2037: C4
        mvi     a,$01                   ; $2038: 69 01
        ora     b,a                     ; $203A: 60 1A
```

…e assim, com `$02`, `$04`, `$08` para CR1-CR3; depois `mvi anm,$0E` em `$205D`, outro atraso,
e `$10`, `$20`, `$40`, `$80` para CR0-CR3 outra vez. Termina com `mov a,b ; ret` em `$2090`.

Três peças de semântica, todas de `upd7810.cpp`/`upd7810_opcodes.cpp`:

- `ANM` bit 0 a 0 escolhe **modo de varrimento**, e nesse modo `m_adrange = (ANM >> 1) & 0x04`.
  `ANM = $06` → `m_adrange = 0` → AN0-AN3 em CR0-CR3; `ANM = $0E` → `m_adrange = 4` →
  AN4-AN7 em CR0-CR3.
- `DCR C` decrementa e **salta a instrução seguinte só no empréstimo**. Com C = `$FF` o par
  `dcr c ; jr` executa 256 voltas. É um atraso à espera da conversão; o modelo do MAME precisa
  de `m_adtot = 192` ciclos por canal com `ANM & 0x10 == 0`, quatro canais.
- `EQI A,$80` é `SKIP_Z` e deixa o carry da subtracção `A - $80`; `SKN CY` salta se o carry
  estiver a 0. Encadeados: o bit só é aceso quando `A > $80`.

Como as funções `anN_func` de `volfied.cpp` devolvem `$FF` ou `$00`, o byte resultante
reproduz `$F0000D` bit a bit — o joystick do jogador 2 em cocktail. (A macro `ZHC_SUB`, que
fixa a convenção do carry, vive em `upd7810.h`, que **não** está em `reference/mame/`; a
direcção acima é a que torna a cadeia consistente com o lado do 68000, que trata `$F0000D`
com a mesma polaridade activa-baixa de `$F0000B` — ver `selftest_service_mode.asm`
`$0141AE`-`$01425E`.)

### 7.4 `sub_20DC` — comando de porta (`$20DC-$2122`)

```
sub_20DC:
        mov     a,(CC_COMMAND)          ; $20DC: 70 69 0A 10
        nei     a,$01                   ; $20E0: 67 01
        jr      loc_20F3                ; $20E2: D0
        mov     a,(CC_COMMAND)          ; $20E3: 70 69 0A 10
        nei     a,$02                   ; $20E7: 67 02
        jr      loc_2103                ; $20E9: D9
        mov     a,(CC_COMMAND)          ; $20EA: 70 69 0A 10
        nei     a,$03                   ; $20EE: 67 03
        jre     loc_2113                ; $20F0: 4E 21
        ret                             ; $20F2: B8
loc_20F3:
        mov     a,(CC_ARG0)             ; $20F3: 70 69 0B 10
        mov     pa,a                    ; $20F7: 4D C0
        nop                             ; $20F9: 00
        nop                             ; $20FA: 00
        nop                             ; $20FB: 00
        mov     a,(CC_ARG1)             ; $20FC: 70 69 0C 10
        mov     pa,a                    ; $2100: 4D C0
        ret                             ; $2102: B8
```

| Comando (`$F00015`) | Porto | Rotina |
|---|---|---|
| `$01` | PA | `$20F3` |
| `$02` | PB | `$2103` |
| `$03` | PC | `$2113` |
| outro | — | `ret` |

Sempre o mesmo padrão: escreve o argumento 0 no porto, três `nop`, escreve o argumento 1. É um
gerador de impulso com largura garantida.

O **único** uso no jogo é o do arranque (comando `$01`, argumentos `$02` e `$00`): a busca por
`CCHIP_RAM+$15` em `src/main68k/` dá um só sítio de escrita, `$0016F8`. Como MA = `$FD` deixa
apenas PA1 como saída, o impulso é PA1 a 1, três instruções, PA1 a 0. A que está ligado esse
pino, não sabemos — `volfied.cpp` não liga `out_pa_callback` a nada.

`sub_20DC` **não limpa** o byte de comando. Fica armado e é reexecutado em todos os frames,
nos dois caminhos do handler. Como o jogo só o escreve uma vez, o impulso repete-se para
sempre a 60 Hz. Não conseguimos dizer se é intencional.

---

## 8. As três tarefas úteis

`sub_21AC` chama oito rotinas por frame:

```
sub_21AC:
        call    round_data_service      ; $21AC: 40 C5 21
        call    rate_table_service      ; $21AF: 40 5A 22
        call    prot_alu_command        ; $21B2: 40 08 23
        call    frame_task_stub_4       ; $21B5: 40 54 23
        call    frame_task_stub_5       ; $21B8: 40 58 23
        call    frame_task_stub_6       ; $21BB: 40 5C 23
        call    frame_task_stub_7       ; $21BE: 40 60 23
        call    frame_task_stub_8       ; $21C1: 40 64 23
        ret                             ; $21C4: B8
```

Os cinco últimos (`$2354`, `$2358`, `$235C`, `$2360`, `$2364`) são todos, literalmente,
`call introm_select_bank_0 ; ret`. Parece a moldura genérica de um firmware de C-Chip com oito
ranhuras de tarefa, de que Volfied só usa três. O primeiro deles tem, ainda assim, efeito
prático: repõe o banco 0 que `prot_alu_command` deixa em 2.

### 8.1 `prot_alu_command` — a protecção (`$2308-$2353`)

Setenta e seis bytes. É a peça que dá nome ao chip.

```
prot_alu_command:
        call    introm_select_bank_2    ; $2308: 40 3B 0F
        mov     a,(CMD_BYTE)            ; $230B: 70 69 04 10
        nei     a,$00                   ; $230F: 67 00
        ret                             ; $2311: B8
        mov     c,(CMD_BYTE)            ; $2312: 70 6B 04 10
        mov     a,(CMD_ARG0)            ; $2316: 70 69 05 10
        mov     b,(CMD_ARG1)            ; $231A: 70 6A 06 10
        sllc    c                       ; $231E: 48 07
        jr      loc_2323                ; $2320: C2
        ana     a,b                     ; $2321: 60 8A
loc_2323:
        sllc    c                       ; $2323: 48 07
        jr      loc_2328                ; $2325: C2
        ora     a,b                     ; $2326: 60 9A
loc_2328:
        sllc    c                       ; $2328: 48 07
        jr      loc_232D                ; $232A: C2
        add     a,b                     ; $232B: 60 C2
loc_232D:
        sllc    c                       ; $232D: 48 07
        jr      loc_2332                ; $232F: C2
        sub     a,b                     ; $2330: 60 E2
loc_2332:
        sllc    c                       ; $2332: 48 07
        jr      loc_2337                ; $2334: C2
        xra     a,b                     ; $2335: 60 92
loc_2337:
        sllc    c                       ; $2337: 48 07
        jr      loc_233C                ; $2339: C2
        adi     a,$30                   ; $233A: 46 30
loc_233C:
        sllc    c                       ; $233C: 48 07
        jr      loc_2340                ; $233E: C1
        nop                             ; $233F: 00
loc_2340:
        sllc    c                       ; $2340: 48 07
        jr      loc_2345                ; $2342: C2
        nega                            ; $2343: 48 3A
loc_2345:
        mov     (CMD_ARG0),a            ; $2345: 70 79 05 10
        mov     (CMD_ARG1),b            ; $2349: 70 7A 06 10
        mvi     a,$00                   ; $234D: 69 00
        mov     (CMD_BYTE),a            ; $234F: 70 79 04 10
        ret                             ; $2353: B8
```

**Não é uma tabela de comandos: o comando é uma máscara de bits e cada bit liga uma
operação.** `SLLC C` desloca C à esquerda através do carry e salta a instrução seguinte se o
bit que saiu era 1:

```c
void upd7810_device::SLLC_C()
{
	PSW = (PSW & ~CY) | ((C >> 7) & CY);
	C <<= 1;
	SKIP_CY;
}
```

Como a instrução seguinte é sempre um `jr` que passa por cima da operação, **a operação
executa-se quando o bit está a 1**. Os bits são consumidos do 7 para o 0 e A vai sendo
transformada em cadeia:

| Bit | Operação | Bytes | Nota |
|---|---|---|---|
| b7 | `ana a,b` — `A &= B` | `60 8A` | |
| b6 | `ora a,b` — `A \|= B` | `60 9A` | |
| b5 | `add a,b` — `A += B` | `60 C2` | soma de 8 bits, sem carry para fora |
| b4 | `sub a,b` — `A -= B` | `60 E2` | |
| b3 | `xra a,b` — `A ^= B` | `60 92` | |
| b2 | `adi a,$30` — `A += $30` | `46 30` | constante fixa |
| b1 | `nop` — nada | `00` | o `jr` em `$233E` é `C1`, salto de 1 byte |
| b0 | `nega` — `A = -A` | `48 3A` | `A = ~A + 1` |

Contrato completo, tudo no **banco 2**:

| Byte | À entrada | À saída |
|---|---|---|
| `$1004` = `$F00009` | máscara de comando; `$00` = ocioso | `$00` (feito) |
| `$1005` = `$F0000B` | operando A | **resultado** |
| `$1006` = `$F0000D` | operando B | B, inalterado |

A tarefa corre em todos os frames e sai imediatamente quando o comando é `$00`. Repare que
nesse caso **sai com o banco do MCU em 2**; é `frame_task_stub_4` que o repõe.

#### Verificação numérica

O jogo faz uma única pergunta, no chefe da primeira área
([`boss09.asm`](../src/main68k/boss09.asm)):

```
boss09_cchip_challenge_send:
        move.w  #$2,CCHIP_REG+$400                                      ; $01A0B2  33fc000200f00c00
        move.w  #$AA,CCHIP_RAM+$A                                       ; $01A0BA  33fc00aa00f0000a
        move.w  #$55,CCHIP_RAM+$C                                       ; $01A0C2  33fc005500f0000c
        move.w  #$65,CCHIP_RAM+$8                                       ; $01A0CA  33fc006500f00008
        clr.w   CCHIP_REG+$400                                          ; $01A0D2  427900f00c00
```

Banco 2; `$F0000B` (= `$1005`) ← `$AA`; `$F0000D` (= `$1006`) ← `$55`; `$F00009` (= `$1004`)
← `$65`; banco 0. Os operandos primeiro, o comando por último — a ordem certa para uma caixa
de correio sem semáforo.

Com `C = $65 = %01100101`, `A = $AA`, `B = $55`:

| Bit | Estado | Operação | A |
|---|---|---|---|
| — | — | inicial | `$AA` |
| b7 = 0 | — | — | `$AA` |
| b6 = 1 | executa | `$AA \| $55` | `$FF` |
| b5 = 1 | executa | `$FF + $55 = $154` | `$54` |
| b4 = 0 | — | — | `$54` |
| b3 = 0 | — | — | `$54` |
| b2 = 1 | executa | `$54 + $30` | `$84` |
| b1 = 0 | — | — | `$84` |
| b0 = 1 | executa | `-$84` | **`$7C`** |

E do outro lado:

```
boss09_cchip_challenge_wait:
        move.w  #$2,CCHIP_REG+$400                                      ; $01A0F0  33fc000200f00c00
        move.w  CCHIP_RAM+$A,d0                                         ; $01A0F8  303900f0000a
        andi.w  #$FF,d0                                                 ; $01A0FE  024000ff
        clr.w   CCHIP_REG+$400                                          ; $01A102  427900f00c00
        cmpi.w  #$7C,d0                                                 ; $01A108  0c40007c
        bne.b   loc_01A0E6                                              ; $01A10C  66d8
```

`$7C`. O valor esperado pelo 68000 é exactamente o que a EPROM produz, calculado a partir das
instruções e reproduzido por simulação sobre a ROM (ver "verificado"). Nenhuma nota do MAME
foi usada nesta cadeia.

Três notas sobre este sítio:

- O `andi.w #$FF` existe porque `move.w CCHIP_RAM+$A` lê uma word cujo byte alto (`$F0000A`)
  não está mapeado.
- `loc_01A0E6` (`$01A0E6`) reinstala `boss09_cchip_challenge_wait` como estado do actor, pelo
  que a verificação **repete-se todos os frames** até passar. Sem C-Chip o chefe aparece e
  nunca ataca.
- O envio (`$01A0A8`, em `boss09_state_init`) acontece uma só vez. O ciclo de combate volta a
  passar por `loc_01A0E6`, mas isso é uma **releitura** do `$1005` do banco 2, que continua a
  valer `$7C` porque ninguém lá escreve entretanto. Não é um novo desafio.

### 8.2 `rate_table_service` — o segundo desafio (`$225A-$22A7`)

Esta transacção tem duas metades: um desafio de tabela (a protecção) e a entrega de uma tabela
de dados (o pretexto).

**O pedido, lado do 68000** — `cchip_request_rate_table` (`$001632-$00168D`), chamado de
[`game_countdown.asm`](../src/main68k/game_countdown.asm) `$0081D2` quando `$872(a5)` chega a
`$3E`:

```
cchip_request_rate_table:
        move.b  #$0,CCHIP_BANK68                                        ; $001632  13fc000000f00c01
        nop  nop  nop
loc_001640:
        tst.b   CCHIP_RAM+$7FF                                          ; $001640  4a3900f007ff
        bne.b   loc_001640                                              ; $001646  66f8
        move.w  $302(a5),d0             ; g_frame_counter ($100302)     $001648  302d0302
        andi.w  #$7,d0                                                  ; $00164C  02400007
        tst.w   d0                                                      ; $001650  4a40
        bne.b   loc_001656                                              ; $001652  6602
        moveq   #$7,d0                                                  ; $001654  7007
loc_001656:
        move.b  d0,$8A8(a5)             ; g_cchip_bank ($1008A8)        $001656  1b4008a8
        move.b  #$1,CCHIP_BANK68                                        ; $00165A  13fc000100f00c01
        nop  nop  nop
        move.b  #$7F,d1                                                 ; $001668  123c007f
        subq.w  #$1,d0                                                  ; $00166C  5340
        bchg.b  d0,d1                                                   ; $00166E  0141
        move.b  d1,CCHIP_RAM                                            ; $001670  13c100f00000
        move.b  #$0,CCHIP_BANK68                                        ; $001676  13fc000000f00c01
        nop  nop  nop
        move.b  #$1,CCHIP_RAM+$7FF                                      ; $001684  13fc000100f007ff
        rts                                                             ; $00168C  4e75
```

`N = frame_counter & 7`, e `7` se der 0 — nunca 0, o que importa porque `g_cchip_bank == 0`
é o sinalizador de "ainda não houve transacção" (ver mais abaixo). O byte de desafio é `$7F`
com o bit `N-1` invertido. **A escrita em `$F00000` é um endereço par; ver §12.**

`cchip_wait_rate_table` (`$00168E-$0016AF`, chamado em `$0081E0` quando `$872(a5)` chega a
`$3F`) espera `$F007FF == 2` e repõe-no a 0.

**A resposta, lado do C-Chip:**

```
rate_table_service:
        call    introm_select_bank_0    ; $225A: 40 23 0F
        mov     a,($13FF)               ; $225D: 70 69 FF 13
        eqi     a,$01                   ; $2261: 77 01
        ret                             ; $2263: B8
        call    introm_select_bank_1    ; $2264: 40 32 0F
        mov     a,(SHARED_RAM)          ; $2267: 70 69 00 10
        call    challenge_lookup        ; $226B: 40 4D 2A
        mov     ($1002),b               ; $226E: 70 7A 02 10
        mov     (CC_IN_PA),c            ; $2272: 70 7B 03 10
        push    va                      ; $2276: B0
        mov     a,b                     ; $2277: 0A
        inr     a                       ; $2278: 41
        call    select_bank_from_a      ; $2279: 40 38 2A
        pop     va                      ; $227C: A0
        nei     a,$FF                   ; $227D: 67 FF
        jr      loc_228E                ; $227F: CE
        mov     ($1001),a               ; $2280: 70 79 01 10
        lxi     hl,tbl_spawn_rate_b     ; $2284: 34 D8 22
        lxi     de,$1010                ; $2287: 24 10 10
        mvi     c,$3F                   ; $228A: 6B 3F
        block                           ; $228C: 31
        jr      loc_229E                ; $228D: D0
loc_228E:
        call    introm_select_bank_1    ; $228E: 40 32 0F
        mov     ($1001),a               ; $2291: 70 79 01 10
        lxi     hl,tbl_round_data       ; $2295: 34 98 23
        lxi     de,$1010                ; $2298: 24 10 10
        mvi     c,$3F                   ; $229B: 6B 3F
        block                           ; $229D: 31
loc_229E:
        call    introm_select_bank_0    ; $229E: 40 23 0F
        mvi     a,$02                   ; $22A1: 69 02
        mov     ($13FF),a               ; $22A3: 70 79 FF 13
        ret                             ; $22A7: B8
```

`BLOCK` copia `C+1` bytes de `(HL)` para `(DE)` com ambos a avançar (`upd7810.cpp` linha 195:
`13(C+1) (DE)+ <- (HL)+, C <- C - 1, until CY`). `C = $3F` → **64 bytes**.

`challenge_lookup` (`$2A4D-$2A68`) procura o byte numa tabela de **16 linhas × 7 colunas** em
`$2A69` (112 bytes). `DCR B`/`DCR C` só saltam no empréstimo, o que dá exactamente 7 colunas e
16 linhas. Ao acertar devolve `A = tbl_challenge_reply[c]` com `b = 6 − coluna` e
`c = 15 − linha`; ao falhar devolve `A = $FF` com `b = $FF`.

`select_bank_from_a` (`$2A38`) é um salto indexado:

```
select_bank_from_a:
        sll     a                       ; $2A38: 48 25
        table                           ; $2A3A: 48 A8
        jb                              ; $2A3C: 21
tbl_bank_routines:
        db      $23,$0F,$32,$0F,$3B,$0F,$44,$0F,$4E,$0F,$58,$0F,$62,$0F,$6C,$0F; $2A3D
```

`TABLE` lê `C = RM(PC + A + 1)` e `B = RM(PC + A + 2)`; com o PC já a apontar para o `jb`
(`$2A3C`), o endereço é `$2A3D + 2·banco`. `JB` faz `PC = BC`. Os oito destinos são `$0F23`,
`$0F32`, `$0F3B`, `$0F44`, `$0F4E`, `$0F58`, `$0F62`, `$0F6C` — todos na ROM interna. É um
salto, não uma chamada: o `ret` da rotina interna regressa a quem chamou
`select_bank_from_a`.

Na falha, `b = $FF` e `inr a` transborda; `INR_A` faz `SKIP_CY`, portanto o
`call select_bank_from_a` é **engolido** e o MCU fica no banco 1.

#### A estrutura da tabela de desafios, resolvida

Um varrimento sobre a ROM (ver "verificado") mostra que as 16 linhas obedecem todas à mesma
regra:

```
tbl_challenge[linha][coluna] = tbl_challenge_reply[15 - linha]  XOR  (1 << (6 - coluna))
```

Ou seja: **o desafio é uma base com um bit trocado; a resposta é a base; o banco é o número do
bit trocado, mais um.** As 16 bases, por ordem de linha, são `$7F`, `$78`, `$66`, `$1E`, `$55`,
`$4B`, `$33`, `$2D`, `$00`, `$07`, `$19`, `$61`, `$2A`, `$34`, `$4C`, `$52`. A linha 0 é
`$3F $5F $6F $77 $7B $7D $7E` — as sete variantes de `$7F`, e a única que este jogo pede.
Simulando `challenge_lookup` sobre os bytes reais para os sete desafios que
`cchip_request_rate_table` constrói:

| N pedido | Desafio `$7F ^ (1<<(N-1))` | Resposta | `b` | Banco `b+1` |
|---|---|---|---|---|
| 1 | `$7E` | `$7F` | 0 | 1 |
| 2 | `$7D` | `$7F` | 1 | 2 |
| 3 | `$7B` | `$7F` | 2 | 3 |
| 4 | `$77` | `$7F` | 3 | 4 |
| 5 | `$6F` | `$7F` | 4 | 5 |
| 6 | `$5F` | `$7F` | 5 | 6 |
| 7 | `$3F` | `$7F` | 6 | 7 |

O banco que o MCU escolhe é sempre o N que o 68000 pediu. As linhas 1-15 nunca são pedidas
por esta ROM de 68000 — a linha 8, base `$00`, é `$40 $20 $10 $08 $04 $02 $01`.

Feito o teste, o MCU copia 64 bytes para `$1010`:

| Resultado | Origem | Banco de destino |
|---|---|---|
| acertou | `tbl_spawn_rate_b` (`$22D8`) | `b + 1` |
| falhou (`$FF`) | `tbl_round_data` (`$2398`) | 1 |

e termina com banco 0 e `$13FF = 2`, que é o que `cchip_wait_rate_table` espera.

#### O que o 68000 faz com isso

`enemy_rate_from_cchip` (`$008276`,
[`enemy_spawn_scheduler.asm`](../src/main68k/enemy_spawn_scheduler.asm)) selecciona o banco
guardado e lê 16 registos de 3 bytes:

```
enemy_rate_from_cchip:
        move.b  $8A8(a5),d0             ; g_cchip_bank ($1008A8)        $008276  102d08a8
        move.b  d0,CCHIP_BANK68                                         ; $00827A  13c000f00c01
        nop  nop  nop
        clr.w   d0                                                      ; $008286  4240
        move.b  $871(a5),d0             ; g_enemy_rate_index ($100871)  $008288  102d0871
        mulu.w  #$6,d0                                                  ; $00828C  c0fc0006
        lea.l   CCHIP_RAM+$20,a0                                        ; $008290  41f900f00020
        adda.w  d0,a0                                                   ; $008296  d0c0
        move.b  $1(a0),d0                                               ; $008298  10280001
        move.b  d0,$876(a5)             ; g_enemy_speed ($100876)       $00829C  1b400876
        move.b  $3(a0),$872(a5)         ; $100872                       $0082A0  1b6800030872
        move.b  $5(a0),$873(a5)         ; $100873                       $0082A6  1b6800050873
        rts                                                             ; $0082AC  4e75
```

`índice × 6` no espaço do 68000 = `índice × 3` no do C-Chip; `+1/+3/+5` são os três bytes do
registo. Velocidade em `$876(a5)`, intervalo de 16 bits em `$872/$873(a5)`.

**E a tabela do C-Chip é a mesma que já está na ROM do 68000.** Verificado byte a byte: os 64
bytes de `enemy_rate_table` (`$0082C8`) são os 48 de `tbl_spawn_rate_b` com um `$00` de
enchimento à frente de cada registo de 3 bytes. E existe um caminho alternativo sem C-Chip
nenhum, `enemy_rate_from_table` (`$0082AE`), escolhido em `$008224` e `$00825E` por
`g_cchip_bank == 0`:

```
        tst.b   $8A8(a5)                ; g_cchip_bank ($1008A8)        $008224  4a2d08a8
        bne.b   loc_008230                                              ; $008228  6606
        bsr.w   enemy_rate_from_table                                   ; $00822A  61000082
```

Como `cchip_request_rate_table` nunca guarda 0, o caminho da ROM só serve até à primeira
transacção. Conclusão: **esta transacção não entrega dado nenhum que o 68000 já não tenha.**
É protecção pura — dados duplicados para justificar uma ida ao chip.

Detalhe: a cópia de 64 bytes a partir de `$22D8` ultrapassa em 16 bytes os 48 que
`tbl_spawn_rate_b` ocupa, e esses 16 bytes são os primeiros de `prot_alu_command`
(`40 3B 0F 70 69 04 10 67 00 B8 70 6B 04 10 70 69`). É inofensivo: `$871(a5)` está limitado a
`$0F` em `$008252`, portanto o 68000 nunca indexa além do registo 15.

### 8.3 `round_data_service` — dados da ronda (`$21C5-$2259`)

Duas metades governadas por um byte de handshake, `$13FE` (68000: `$F007FD`):

| Estado de `$13FE` | Corre |
|---|---|
| bit7 = 0 **e** bits 0-4 ≠ 0 | `round_data_copy` (`$21CF`) — copia 160 bytes, depois `$13FE = $80` |
| bit7 = 1 **e** bits 0-4 ≠ 0 | `round_palette_index` (`$2227`) — escreve `$1023`, depois `$13FE = $00` |
| bits 0-4 = 0 | nada |

(`OFFI` é `SKIP_Z` sobre `A & imm`, `ONI` é `SKIP_NZ`; nos dois casos a instrução engolida é
um `ret`.)

A origem é `HL = tbl_round_data + ($13FE − 1)·$60`, calculada com `mul c` e `dadd ea,hl` em
`$21E6-$21EC`. O destino é sempre `DE = $1010`. Depois, `nei a,$11` separa dois caminhos, e o
resultado é sempre **160 bytes** (5 × `copy32_to_shared`, que é `mvi c,$1F ; block` = 32
bytes):

| Ronda | Bytes `$1010`+ | Conteúdo |
|---|---|---|
| `$01`-`$10` | `$00-$1F` | `round_data_prefix` (`$2378`, 32 bytes) |
| | `$20-$3F` | registo `[0..31]` |
| | `$40-$5F` | `round_data_prefix` outra vez |
| | `$60-$7F` | registo `[32..63]` |
| | `$80-$9F` | registo `[64..95]` |
| `$11` | `$00-$9F` | 160 bytes seguidos a partir de `$2998` |

Para a ronda `$11` a fórmula dá `$2398 + $10·$60 = $2998`, e 160 bytes a partir daí terminam
exactamente em `$2A37` — o byte anterior a `select_bank_from_a`. É por isso que
`symbols/cchip.sym` declara `round17_data` com `$A0` bytes e não `$60`: a ronda 17 lê 64 bytes
para lá do tamanho de um registo, e esses 64 bytes existem e estão lá para isso.

Do lado do 68000, `pal_load_round_from_cchip` (`$015C94`,
[`palette_effects.asm`](../src/main68k/palette_effects.asm)):

```
pal_load_round_from_cchip:
        move.w  $110A(a5),d0            ; g_level_type ($10110A)        $015C94  302d110a
        addi.w  #$1,d0                                                  ; $015C98  06400001
        move.b  d0,CCHIP_RAM+$7FD                                       ; $015C9C  13c000f007fd
loc_015CA2:
        cmp.b   CCHIP_RAM+$7FD,d0                                       ; $015CA2  b03900f007fd
        beq.b   loc_015CA2                                              ; $015CA8  67f8
        lea.l   CCHIP_RAM+$21,a0                                        ; $015CAA  41f900f00021
```

Escreve `g_level_type + 1`, gira em espera activa **enquanto o byte não mudar**, e lê 80 words
a partir de `$F00021` — 80 × 2 = 160 bytes do lado do C-Chip. Fecha exactamente. (As 80 words
são depois replicadas por 16 linhas de paleta, com `a0` reposto a cada volta em `$015CC8`;
isso é assunto da paleta, não do C-Chip.)

`round_palette_index` indexa `tbl_round_palette_index` (`$2368`, 16 bytes:
`0F 01 06 0F 09 06 06 0F 08 01 0A 01 01 08 06 0A`) com `($13FE & $1F) − 1` e deixa o resultado
em `$1023`. Do outro lado, `pal_mark_round_entry_maybe` (`$015C0A`) escreve
`g_level_type + $81` — o mesmo número, com o bit 7 posto — espera, e lê `$F00047`.

#### A ordem importa

`$1023` fica **dentro** do bloco de 160 bytes: é o byte alto da word 9
(`$1011 + 2·9 = $1023`). Se o índice de paleta fosse pedido antes dos dados, a cópia
apagava-o. Os dois sítios que fazem estas chamadas fazem-nas na ordem certa:

| Chamador | Dados | Índice |
|---|---|---|
| `task_scheduler.asm` | `$014664` | `$014670` |
| `debug_object_editor.asm` | `$0167B8` | `$0167BE` |

E o protocolo é auto-consistente: depois da cópia `$13FE = $80` (bit 7 posto), o que faz o
ramo da cópia sair de imediato até o 68000 voltar a escrever um valor com bit 7 a 0.

---

## 9. A tabela de despacho e os oito pontos de entrada

Os primeiros 24 bytes da EPROM são oito `jmp` de 3 bytes. A ROM interna alcança-os; não
sabemos por que via.

| Entrada | Slot | Destino | O que lá está | Termina em |
|---|---|---|---|---|
| 0 | `$2000` | `$2093` | prólogo completo, guarda de reentrância, todo o trabalho do frame | `reti` |
| 1 | `$2003` | `$2142` | `di`, 5 × `push va`, 5 × `pop va`, `ei` — handler vazio, mas com duração | `reti` |
| 2 | `$2006` | `$2092` | um único byte, `B8` | `ret` |
| 3 | `$2009` | `$201E` | `di`, banco ← 0, `A = 0`, `calt ($0080)`, **cai** em `sub_2028` | `ret` |
| 4 | `$200C` | `$214F` | inicialização de portos + `ei` + laço ocioso | nunca regressa |
| 5, 6, 7 | `$200F`, `$2012`, `$2015` | `$201E` | o mesmo que a 3 | `ret` |

`$2018-$201D` são seis bytes `$00` entre a tabela e `entry_201E`.

**O que se pode afirmar pela forma.** As entradas 0 e 1 terminam em `reti` e só fazem sentido
alcançadas por um vector de interrupção; as entradas 2, 3, 5, 6 e 7 terminam em `ret` e só
fazem sentido chamadas com `call`; a 4 não regressa e é o caminho de arranque. A entrada 0 é o
único sítio onde os pinos são amostrados, o que a torna o candidato óbvio a handler de INT1 —
o VBLANK. A entrada 1, sendo um handler vazio mas não instantâneo, é o candidato natural a
INTFE0, a outra fonte que `MKL = $D7` habilita; **isto é conjectura**, sustentada só na
contagem (duas fontes habilitadas, duas entradas que acabam em `reti`).

Nota sobre a entrada 3: `CALT` é uma chamada (empilha PC), portanto a execução regressa a
`$2028` e continua pela rotina do A/D, devolvendo em A o byte de 8 canais. Uma entrada que
repõe o banco 0 e devolve o estado das entradas analógicas é um serviço plausível — mas faz
`di` sem `ei`, o que não bate certo com uma subrotina normal. Sem os 4 KB não se resolve.

---

## 10. O que a ROM interna faz, deduzido

Sete alvos internos são chamados pela EPROM. De `external_targets` em
`build/cchip_map.json`:

| Endereço | Nome em `symbols/cchip.sym` | Chamado de | Evidência |
|---|---|---|---|
| `$0F23` | `introm_select_bank_0` | `$214F`, `$217B`, `$21C5`, `$225A`, `$229E`, `$2354`, `$2358`, `$235C`, `$2360`, `$2364` | prólogo de tudo o que fala com o banco 0 |
| `$0F32` | `introm_select_bank_1` | `$2264`, `$228E` | os dois sítios do desafio; o 68000 põe o banco 1 em `$00165A` |
| `$0F3B` | `introm_select_bank_2` | `$2308` | a ALU; o 68000 põe o banco 2 em `$01A0B2` |
| `$0F44`, `$0F4E`, `$0F58`, `$0F62`, `$0F6C` | bancos 3 a 7 | nenhuma chamada directa | aparecem por ordem em `tbl_bank_routines` (`$2A3D`) |
| `$09D0` | `introm_pre_frame_hook` | `$20D2` | só no caminho longo do handler |
| `$0FD5` | `introm_service_frame_tail` | `$20D8` | nos dois caminhos, depois do comando de porta |
| `$0975` | `introm_hl_add_a_maybe` | `$2240` | entre `ani a,$1F ; sui a,$01` e `ldax (hl)` |
| `$096B` | `introm_de_add_a_maybe` | `$2A64` | entre `mov a,c` e `ldax (de)` |

Mais o destino de `calt ($0080)` em `$2027`, que é a entrada 0 da tabela CALT.

A identificação dos oito primeiros é forte: são oito rotinas, para oito bancos de 1 KB, numa
tabela ordenada, e o uso bate com o lado do 68000 em três pontos independentes (§5). Os nomes
`*_add_a_maybe` são **conjectura de uso**: nos dois sítios A é claramente um índice e a
instrução seguinte é um `ldax` indirecto, o que só faz sentido se a rotina somar A ao par de
registos. É plausível e não está confirmado.

O espaçamento das oito rotinas de banco (`$0F23`, depois +15, +9, +9, +10, +10, +10, +10)
sugere corpos muito curtos, da ordem de `mvi a,imm ; mov ($1600),a ; ret` mais alguma coisa.
Não passamos daqui.

---

## 11. Contrato mínimo para reimplementar

Se o objectivo for substituir o chip por código (num port ou num emulador de alto nível), isto
é o que tem de acontecer, e nada mais é observável pelo jogo:

**No reset**

1. Responder `$01` em `$F00803` até o 68000 escrever lá `$02`. (Sem isto o jogo trava em
   `$0016B0`.) Nunca responder `$05`.
2. Aceitar, sem efeito visível, as escritas de `$FD`/`$0F`/`$FF` em `$F00001`/`$F00003`/
   `$F00005` e a limpeza dos 8 KB.

**Em cada VBLANK**, com o banco do MCU em 0:

3. `$1003 ← PA`, `$1004 ← PB`, `$1005 ← PC`, `$1006 ←` byte com os 8 canais A/D (bit *n* = bit
   *n* do porto `$F0000D`).
4. `PA ← $1007`, `PB ← $1008 XOR $30`, `PC ← $1009`.
5. Se `$100A ∈ {1,2,3}`: escrever `$100B` e depois `$100C` no porto PA/PB/PC correspondente,
   com um atraso entre os dois. Não limpar `$100A`.
6. Tarefa dos dados de ronda (banco 0), sobre `$13FE`: bit7=0 e bits0-4≠0 → montar os 160
   bytes em `$1010` e pôr `$13FE = $80`; bit7=1 e bits0-4≠0 → escrever
   `tbl_round_palette_index[(v & $1F) - 1]` em `$1023` e pôr `$13FE = $00`.
7. Tarefa da tabela de ritmos (banco 0 → 1 → N): se `$13FF == 1`, ler o desafio de `$1000` do
   banco 1, procurá-lo na tabela 16×7, escrever a resposta em `$1001` do banco `b+1`, copiar
   64 bytes de `tbl_spawn_rate_b` para `$1010` desse banco (ou de `tbl_round_data` para o
   banco 1, se falhar), voltar ao banco 0 e pôr `$13FF = 2`.
8. Tarefa da ALU (banco 2): se `$1004 != 0`, aplicar a cadeia de operações de §8.1 a
   `A = $1005` com `B = $1006`, escrever o resultado em `$1005`, B em `$1006` e `$00` em
   `$1004`.
9. Repor o banco 0 no fim.

Os dois registos de banco são independentes e ambos arrancam em 0. A janela do 68000 é de
bytes ímpares. Nada mais da região da ASIC é usado.

---

## 12. Anomalias verificadas

**A escrita do desafio num endereço par.** Em `cchip_request_rate_table`:

```
        move.b  d1,CCHIP_RAM                                            ; $001670  13c100f00000
```

`$F00000` é **par**. Com `umask16(0x00ff)`, o modelo do MAME só liga a metade baixa do
barramento — só endereços ímpares — pelo que a escrita não chega ao chip. Todos os outros
acessos do jogo à janela usam endereços ímpares, ou words cujo byte baixo aterra em ímpar.

Há duas leituras, e não conseguimos escolher entre elas com os artefactos locais:

- **Se o modelo do MAME descrever a placa**, o desafio nunca é escrito. O MCU lê `$1000` do
  banco 1 e encontra `$00`, deixado por `cchip_clear_all_banks`. Confirmámos por varrimento
  dos 112 bytes que **`$00` não existe em `tbl_challenge`**, portanto `challenge_lookup`
  devolveria sempre `$FF`, o MCU ficaria no banco 1 e copiaria dados de paleta, enquanto o
  68000 iria ler o banco N — que continua a zeros desde o arranque.
- **Se o `/CS` do C-Chip não for filtrado por `/LDS`** na placa real, a escrita chega: o pino
  A0 do chip está ligado ao A1 do 68000, pelo que `$F00000` e `$F00001` são o mesmo byte, e o
  68000 duplica o dado nas duas metades do barramento durante uma escrita de byte. Nesse caso
  o desafio funciona como pretendido.

O esquema da placa não está neste repositório e não instrumentámos o MAME. **Fica como
questão em aberto, não como facto**; as consequências de cada leitura estão acima e são
verificáveis por quem tenha o hardware ou um MAME com trace.

**Código órfão em `$2123-$2141`.** O varrimento linear
([`src/cchip/cchip_linear.asm`](../src/cchip/cchip_linear.asm) linhas 298-312) descodifica
estes bytes como dois `ret` isolados seguidos de uma rotina perfeitamente coerente:

```
[?]         mvi     a,$00                   ; $2125: 69 00
[?]         mov     etmm,a                  ; $2127: 4D CC
[?]         mvi     eom,$07                 ; $2129: 64 83 07
[?]         mvi     a,$40                   ; $212C: 69 40
[?]         mov     mcc,a                   ; $212E: 4D D1
[?]         lxi     ea,$00C8                ; $2130: 44 C8 00
[?]         dmov    etm0,ea                 ; $2133: 48 D2
[?]         lxi     ea,$01F4                ; $2135: 44 F4 01
[?]         dmov    etm1,ea                 ; $2138: 48 D3
[?]         mvi     a,$3C                   ; $213A: 69 3C
[?]         mov     etmm,a                  ; $213C: 4D CC
[?]         ori     eom,$08                 ; $213E: 64 9B 08
[?]         ret                             ; $2141: B8
```

Isto não são dados: é a programação do contador de eventos de 16 bits do 78C11 — comparadores
ETM0 = 200 e ETM1 = 500, `ETMM = $3C` (conta o relógio interno, reinicia quando `ECNT == ETM1`,
comuta CO0 nas duas comparações) e a saída ligada em EOM. Nenhum caminho traçado lá chega; só
pode ser chamada da ROM interna. `volfied.cpp` não liga nada aos pinos CO. É a demonstração
mais limpa de que a lacuna é real e tem consequências.

**A convenção dos três `nop` não é universal.** Um censo sobre as 25 escritas do 68000 em
`$F00C01` (21) e `$F00C00` (4) — todas as ocorrências do endereço na zona de código, filtradas
contra a listagem para excluir os falsos positivos que são dados:

| Seguida de 3 `nop` | Sem `nop` nenhum |
|---|---|
| as 13 escritas de `cchip_interface.asm` (`$001632`, `$001676`, `$00168E`, `$001712`, `$001724`, `$001736`, `$001748`, `$00175A`, `$00176C`, `$00177E`, `$001790`, `$0017B8`, e `$00165A`) | `$000A10` `game_coinwait_script` |
| `$00665C` `inp_cchip_bank_select` | `$000E4C` `inp_tilt_check` |
| `$00827A` `enemy_rate_from_cchip` | `$004FB6` `inp_read_cchip` |
| | `$0066CC`, `$0068E6`, `$006904` `coin_credit` |
| | `$01A0B2`, `$01A0D2`, `$01A0F0`, `$01A102` `boss09` |

Quinze sítios com atraso, dez sem — e em `$000E4C` e `$004FB6` a instrução imediatamente a
seguir à escrita do banco já lê a janela (`$000E54` lê `$F0000B`; `$004FBE` lê `$F0000A`).
Portanto **o atraso não é exigido pelo hardware** (ou, se for,
o jogo viola-o rotineiramente). Parece convenção de um autor e não de outro. O mesmo padrão de
três `nop` aparece do lado do MCU, entre as duas escritas de um comando de porta (§7.4), onde
tem uma função clara: dar largura ao impulso.

**Higiene de banco.** `enemy_rate_from_cchip` (`$008276`) selecciona o banco N e **não repõe
0**. As rotinas que lêem a janela sem seleccionar banco nenhum — `palette_effects` (`$015C12`,
`$015C18`, `$015C22`, `$015C9C`, `$015CA2`, `$015CAA`), `selftest_service_mode`
(`$0140E8`-`$01425E`, `$01457C`, `$0145A8`), `debug_menu_display` (`$016A5C`),
`enemy_dev_placer` (`$007ACE`, `$007AF8`) e `inp_read_coin_service` (`$006922`, `$006948`) —
dependem de o banco de repouso ser 0. Em contrapartida, `inp_tilt_check` (`$000442` no handler
de VBLANK) e `coin_credit_tick` (`$000446`) forçam o banco 0 logo à cabeça, o que garante que
o estado de repouso é restabelecido pelo menos uma vez por frame, **antes** de a máquina de
estados do jogo correr; `inp_read_cchip` (`$004FB6`) faz o mesmo antes de ler o joystick. É por isso que o descuido de `enemy_rate_from_cchip` não morde: entre
ele e a leitura seguinte que não selecciona banco passa sempre um VBLANK — desde que as duas
não caiam no mesmo passo do handler. Não encontrámos caminho em que caiam (pertencem a estados
diferentes da tabela de saltos), mas **não provámos que não existe**.

**A ronda 17 e a tabela de 16.** `round_palette_index` indexa uma tabela de 16 bytes com
`($13FE & $1F) − 1`. Para a ronda `$11` o índice é 16 — um byte para lá do fim, que calha em
`round_data_prefix[0]` (`$2378`) = `$00`. Não sabemos se é intencional.

**`tbl_spawn_rate_a` sem dono.** Os 48 bytes em `$22A8` têm a mesma forma que
`tbl_spawn_rate_b` mas valores diferentes (intervalos mais longos), e nenhum `lxi hl` da EPROM
lhes aponta. Ou é uma tabela de dificuldade alternativa que este jogo não usa, ou é código
morto. O varrimento linear conclui, com modelos nulos, que toda a área `$2368-$2A37` são dados
e não código órfão: 3.12% de opcodes ilegais contra 3.03% de bytes aleatórios, e **zero**
saltos ou chamadas para dentro da área com conteúdo, contra 37 em 56 no código traçado.

---

## 13. O que não sabemos

1. **Os 4 KB da ROM interna.** Não estão no conjunto local. Tudo o que este documento diz
   sobre eles é dedução a partir de chamadas e comportamento. O MAME tem uma extracção óptica
   que não verificámos nem usámos.
2. **Quem escreve o byte de estado `$F00803`.** A EPROM não escreve `$1401` em sítio nenhum, e
   o 68000 fica preso até lá ler `$01`. Tem de vir da ROM interna ou do hardware da ASIC. Não
   podemos decidir.
3. **A que vector corresponde cada entrada da tabela de despacho.** Só sabemos, pela forma,
   quais podem ser handlers e quais são subrotinas (§9).
4. **O que faz `calt ($0080)`** em `$2027`, com `A = 0`, e por que razão a rotina que o chama
   faz `di` sem `ei`.
5. **Os corpos das doze rotinas internas.** Os nomes em `symbols/cchip.sym` são hipóteses de
   uso — fortes para os oito selectores de banco, fracas para `introm_pre_frame_hook`,
   `introm_service_frame_tail` e os dois `*_add_a_maybe`.
6. **A que está ligado PA1**, o único pino de saída do porto A, e o que significa o impulso
   `$02` → `$00` que o comando de porta lhe aplica em todos os frames desde o arranque.
7. **Se INTFE0 é mesmo a entrada 1** da tabela de despacho, e o que gera o evento.
8. **Se a escrita em `$F00000` chega ao chip** na placa real (§12). Só medição ou o esquema
   resolvem.
9. **Quem consome os três bytes de arranque** (`$FD`, `$0F`, `$FF`) em `$1000-$1002` do banco
   0, dado que a EPROM programa MA/MB/MC com imediatos.
10. **Quem chama a rotina de temporizadores em `$2125`**, e para quê — os pinos CO não estão
    ligados a nada no driver.
11. **Se o comando de porta reexecutado a cada frame** é intencional ou descuido.
12. **O comportamento real da ASIC** fora do que `taitocchip.cpp` modela: o registo `$400`, os
    espelhos, e em que acessos é que o `/DTACK` é ou não afirmado. O cabeçalho do MAME diz
    *"no idea"* em quatro pontos distintos.
13. **Se o `$E8` escrito em `$1600`** tem significado nos 5 bits que o modelo ignora.

---

## Ver também

- [`docs/01-hardware.md`](01-hardware.md) §8 — o C-Chip no contexto da placa e das três CPUs.
- [`docs/02-mapa-de-memoria.md`](02-mapa-de-memoria.md) §2.11 e §5 — a janela e o espaço do
  78C11 em forma de tabela de endereços.
- [`reference/HARDWARE_GROUND_TRUTH.md`](../reference/HARDWARE_GROUND_TRUTH.md) — portas de
  entrada, DIP switches, mapa das ROMs.
- [`docs/ACHADOS_ANOTACAO.md`](ACHADOS_ANOTACAO.md) — "Moedas e C-Chip" (linha 173), "Ritmo de
  aparecimento vindo do C-Chip" (§9 da banda02), o nibble de direcção em `$F00007` (banda03,
  dúvida 7) e o desafio do chefe 9 (banda04).
- [`src/cchip/cchip.asm`](../src/cchip/cchip.asm) — a listagem, com o cabeçalho que justifica a
  base `$2000` instrução a instrução.
- [`symbols/fragments/cchip/`](../symbols/fragments/cchip/) — a camada de anotação; é aqui que
  se corrigem nomes, não em `symbols/cchip.sym`, que é gerado.
- O outro lado da janela: [`cchip_interface.asm`](../src/main68k/cchip_interface.asm),
  [`boss09.asm`](../src/main68k/boss09.asm),
  [`palette_effects.asm`](../src/main68k/palette_effects.asm),
  [`enemy_spawn_scheduler.asm`](../src/main68k/enemy_spawn_scheduler.asm),
  [`coin_credit.asm`](../src/main68k/coin_credit.asm),
  [`inp_tilt_check.asm`](../src/main68k/inp_tilt_check.asm),
  [`selftest_service_mode.asm`](../src/main68k/selftest_service_mode.asm),
  [`game_countdown.asm`](../src/main68k/game_countdown.asm).
