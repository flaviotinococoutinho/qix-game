# 08 — Ferramentas e reprodução

Como refazer este projecto do zero: preparar o ambiente, conferir as ROMs, montar as imagens
planas, desmontar as três CPUs, extrair os gráficos, correr os testes. E como contribuir uma
anotação nova sem partir nada.

Este documento cobre **o processo**. Os factos sobre o hardware e sobre o jogo estão em
[`reference/HARDWARE_GROUND_TRUTH.md`](../reference/HARDWARE_GROUND_TRUTH.md) e nos
documentos [01](01-hardware.md) a [07](07-texto-e-fonte.md); o contrato a que as ferramentas
obedecem está em [`tools/TOOLING_SPEC.md`](../tools/TOOLING_SPEC.md), que este texto
complementa em vez de repetir. A extracção de gráficos é descrita do ponto de vista do
formato no §9 de [03 — Vídeo](03-video.md); aqui só aparece o lado operacional.

**Tudo o que está abaixo foi corrido nesta máquina.** Onde há um número, foi medido; onde
há um excerto, foi copiado da saída real. O §7 e o §8 dizem o que ficou por provar.

Ambiente da medição: macOS (Darwin 25.2.0, Apple Silicon), CPython 3.12.12 instalado por
`uv` 0.11.23, `capstone` 5.0.9 (a biblioteca embutida reporta-se como 5.0.7), `pillow`
12.3.0.

---

## 1. Reproduzir do zero

### 1.1 O que é preciso

| Requisito | Versão usada | Porquê |
|---|---|---|
| Python | 3.12.12 | as ferramentas usam `match`-free 3.10+, mas o `.venv` está fixado em 3.12 |
| `capstone` | 5.0.9 (pip) | descodificador do 68000; é o **único** desmontador de terceiros usado |
| `pillow` | 12.3.0 | escrita dos PNG |
| `uv` | 0.11.23 | cria o `.venv`; qualquer gestor serve, o `.venv` não tem `pip` instalado |
| ROMs | set `volfied` (World, rev 1), 18 ficheiros | não vêm no repositório |

O Z80 e o uPD78C11 **não** têm desmontador de terceiros: `tools/z80_disasm.py` e
`tools/upd7810_disasm.py` trazem as suas próprias tabelas de opcodes. As do uPD78C11 são
portadas do MAME e a proveniência (ficheiro, blob SHA-1, commit) está no cabeçalho de
[`tools/upd7810_tables.py`](../tools/upd7810_tables.py) e é reconferida por testes.

```bash
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python capstone pillow
```

O `.venv` criado por `uv` **não tem `pip`** — `.venv/bin/python -m pip` falha com
`No module named pip`. Instale sempre com `uv pip install --python .venv/bin/python`.

Nenhuma ferramenta acede à rede em tempo de execução. Nenhuma escreve fora de `build/`,
`src/`, `assets/` e `symbols/*.sym` (nunca dentro de `symbols/fragments/`).

### 1.2 As ROMs

`roms/` e `build/` estão no `.gitignore`; o que se versiona é a análise. Ponha as 18 ROMs
em `roms/volfied/` e confirme:

```
$ .venv/bin/python tools/romtool.py verify
Conjunto: volfied (World, rev 1) — 18 ficheiros em roms/volfied

ficheiro       tamanho  sha1                                      crc32     estado
------------  --------  ----------------------------------------  --------  ------
c04-12-1.30      65536  fca488e86725a0a673332afeb0002f0e77ef2dbf  afb6a058  OK
c04-08-1.10      65536  51b5d0d00ec398ed717154286bec24b05c3f81b8  19f7e66b  OK
...
Resultado: 18/18 ficheiros conferem com a tabela.
```

Se um ficheiro faltar ou um hash não bater, `verify` sai com código 1 e diz **qual**. Não
continue: todas as ferramentas a jusante voltam a conferir e vão falhar mais tarde e pior.

### 1.3 O guião completo

```bash
# 1. Conferir as ROMs e montar as quatro imagens planas
.venv/bin/python tools/romtool.py verify
.venv/bin/python tools/romtool.py build

# 2. (opcional) Ver o mapa da ROM antes de desmontar
.venv/bin/python tools/romtool.py info
.venv/bin/python tools/romtool.py entropy

# 3. Fundir os fragmentos de símbolos das três CPUs
.venv/bin/python tools/merge_symbols.py \
    --fragmentos symbols/fragments/main68k --cobrir 000000:03FFFF
.venv/bin/python tools/merge_symbols.py --fragmentos symbols/fragments/z80 \
    --saida symbols/sound_z80.sym --seccoes symbols/sound_z80_sections.sym
.venv/bin/python tools/merge_symbols.py --fragmentos symbols/fragments/cchip \
    --saida symbols/cchip.sym --seccoes symbols/cchip_sections.sym

# 4. Desmontar
.venv/bin/python tools/m68k_disasm.py --split
.venv/bin/python tools/z80_disasm.py
.venv/bin/python tools/upd7810_disasm.py

# 5. Extrair gráficos
.venv/bin/python tools/gfx_extract.py sprites
.venv/bin/python tools/gfx_extract.py bitmap --strip
.venv/bin/python tools/gfx_extract.py font
.venv/bin/python tools/gfx_extract.py palette

# 6. Testes
.venv/bin/python -m unittest discover -s tools/tests
```

O passo 1 é conveniência, não obrigação: os três desmontadores e o `gfx_extract.py` montam
a imagem de que precisam a partir de `roms/volfied/` se `build/*.bin` faltar. O que o
`romtool.py verify` acrescenta é a conferência ficheiro a ficheiro **antes** de qualquer
montagem, com a mensagem certa quando algo está errado.

Tempo medido nesta máquina, cronometrado de ponta a ponta: **4,2 s** para os passos 1 a 5;
**13,6 s** para os 295 testes do passo 6.

### 1.4 O que cada passo escreve

| Passo | Escreve | Tamanho |
|---|---|---|
| `romtool build` | `build/maincpu.bin`, `audiocpu.bin`, `cchip_eprom.bin`, `pc090oj.bin` | 1 MB, 32 KB, 8 KB, 768 KB |
| `merge_symbols` (68000) | `symbols/main68k.sym`, `symbols/main68k_sections.sym` | 2741 entradas, 153 secções |
| `merge_symbols` (Z80) | `symbols/sound_z80.sym`, `symbols/sound_z80_sections.sym` | 105 entradas, 15 secções |
| `merge_symbols` (C-Chip) | `symbols/cchip.sym`, `symbols/cchip_sections.sym` | 61 entradas, 13 secções |
| `m68k_disasm --split` | `src/main68k/*.asm` (152), `src/main68k/hardware.inc`, `build/m68k_map.json`, `build/m68k_stats.txt` | 55 209 linhas, 870 `equ`, 2,5 MB |
| `z80_disasm` | `src/sound_z80/sound.asm`, `src/sound_z80/hardware.inc`, `build/z80_map.json` | 6261 linhas |
| `upd7810_disasm` | `src/cchip/cchip.asm`, `build/cchip_map.json` | 1272 linhas |
| `gfx_extract` | `assets/**.png` (335), `assets/font_map.json`, `build/proms/*.bin` | 3,3 MB |

Os 152 `.asm` do 68000 são `volfied.asm` (o índice, só `include` e `end`) mais 151 ficheiros
de secção. Há 153 secções e 151 ficheiros porque duas secções partilham nome com outra e
são fundidas no mesmo ficheiro — ver §3.4.

### 1.5 Como saber que correu bem

Quatro SHA-1 fixados nos testes; se estes baterem, a montagem está certa e tudo o resto
assenta em terreno firme:

| Imagem | Bytes | SHA-1 |
|---|---|---|
| `build/maincpu.bin` | 1 048 576 | `6994b7ba1e3dfdc6225f57d69f5efb3e0f054265` |
| `build/audiocpu.bin` | 32 768 | `d71062f9d9b11492e13fc93982b95883f564f902` |
| `build/cchip_eprom.bin` | 8 192 | `73aa2267eb468c5aa5db67183047e9aef8321215` |
| `build/pc090oj.bin` | 786 432 | `e4e2d054f27e013f0ce84d16f76355588b9d053b` |

E as contagens que a saída de cada passo imprime:

| Onde | Valor esperado |
|---|---|
| `merge_symbols` (68000) | `Entradas fundidas: 2741`, `Secções: 153`, `CONFLITOS (155)` |
| `m68k_disasm` | `Rotinas: 1774 (instrucoes descodificadas: 24593)`, zona de código `98.4%` classificada |
| `z80_disasm` | `3343 instrucoes`, `510 labels`, `10 tabelas` |
| `upd7810_disasm` | 365 instruções, 772 bytes de código, cobertura 27,64 % da área com conteúdo |
| testes | `Ran 295 tests` |

Repare que **`merge_symbols` reporta 155 conflitos e isso é normal**: o fusor não esconde
desacordos entre agentes, resolve-os por prioridade e imprime a hipótese perdedora. Ver §3.3.

---

## 2. As ferramentas

Todas seguem o mesmo contrato: script executável, `argparse` com `--help` em português,
`-v`/`--verbose` para o diagnóstico, saída determinística, e uma falha alta e explícita em
vez de uma substituição silenciosa.

### 2.1 `tools/romtool.py` — montar e inspeccionar as ROMs

Lê `roms/volfied/`, escreve `build/*.bin`. Contém a tabela de regiões (nome do ficheiro,
offset, tamanho, modo de carga, SHA-1, CRC32) transcrita de `volfied.cpp`.

| Subcomando | Faz |
|---|---|
| `verify` | confere os 18 ficheiros contra a tabela; sai com 1 se algum falhar |
| `build` | monta as quatro regiões; os buracos ficam a `$FF` |
| `info` | os 64 vectores de excepção, SSP/PC de reset, word de região em `$03FFFE` |
| `entropy` | mapa ASCII de entropia por janela deslizante, e a segmentação que dele resulta |

Opções úteis:

| Opção | Onde | Para quê |
|---|---|---|
| `--roms DIR` | global (antes do subcomando) | usar outro conjunto de ROMs |
| `--regiao NOME` | `build` (repetível) | montar só `maincpu`, por exemplo |
| `--out DIR` | `build` | escrever noutro sítio |
| `--image FICH` | `info`, `entropy` | analisar uma imagem já existente em vez de montar |
| `--only-set` | `info` | esconder os vectores a `$00000000` |
| `--window`, `--step`, `--columns` | `entropy` | resolução do mapa (omissão: 256 / 256 / 64) |
| `--start`, `--end` | `entropy` | limitar a faixa (aceita `0x…`) |
| `--smooth`, `--min-run` | `entropy` | agressividade da segmentação (omissão: 8 janelas, 4096 B) |

`entropy` é a ferramenta que separou código de dados sem olhar para uma única instrução, e
o resultado é o que está no `HARDWARE_GROUND_TRUTH`:

```
Segmentação (média móvel de 8 janelas, corrida mínima 4096 B)
início     fim          tamanho   média  classe
---------  ---------  ---------  ------  ----------------------------------
$0000000  $00000FF        256    1.93  baixa/média — código ou tabelas
$0000100  $00003FF        768    0.00  não preenchido (0xFF)
$0000400  $0029BFF     169984    4.71  baixa/média — código ou tabelas
$0029C00  $002FFFF      25600    0.00  não preenchido (0xFF)
$0030000  $00329FF      10752    1.89  muito baixa — tabelas esparsas/padding
$0032A00  $0039DFF      29696    3.78  baixa/média — código ou tabelas
$0039E00  $003FEFF      24832    0.00  não preenchido (0xFF)
$003FF00  $003FFFF        256    1.31  muito baixa — tabelas esparsas/padding
```

`info --only-set` é o que mostra os 11 vectores `$0011xxxx` que apontam para fora do mapa de
memória — restos do sistema de desenvolvimento da Taito, não código a desmontar:

```
2     $000008  $001100CC  Bus error                             fora do mapa
3     $00000C  $001100E8  Address error                         fora do mapa
...
28    $000070  $00000400  Autovector IRQ nível 4 (VBLANK)       ROM de programa
47    $0000BC  $001100B8  TRAP #15                              fora do mapa
```

### 2.2 `tools/merge_symbols.py` — fundir a anotação humana

Lê `symbols/fragments/<cpu>/*.sym` por ordem alfabética, funde-os, adjudica conflitos,
particiona as secções e escreve dois ficheiros gerados. **Nunca escreve nos fragmentos.**

| Opção | Para quê |
|---|---|
| `--fragmentos DIR` | a pasta de fragmentos (omissão: `symbols/fragments`, que não é nenhuma das três CPUs — passe-a sempre) |
| `--saida FICH` | o `.sym` fundido (omissão: `symbols/main68k.sym`) |
| `--seccoes FICH` | o ficheiro `SECTION` gerado (omissão: `symbols/main68k_sections.sym`) |
| `--cobrir INICIO:FIM` | fecha as lacunas para as secções formarem uma partição completa; **obrigatório** para o `--split` do desmontador |
| `--base FICH` | um ficheiro extra lido antes de tudo. Existe por compatibilidade; a curadoria vive num fragmento `00_curado.sym` e essa é a via recomendada |
| `-n`, `--dry-run` | relata sem escrever — a forma segura de ver o efeito de uma edição |
| `-v` | mostra as linhas ignoradas por formato não reconhecido |

`--cobrir` só faz sentido para o 68000, porque só o 68000 tem listagem segmentada. Para o
Z80 e o C-Chip omite-se e as secções ficam a cobrir apenas o que foi nomeado.

### 2.3 `tools/m68k_disasm.py` — o desmontador do 68000

O maior dos seis (2493 linhas). Lê `build/maincpu.bin` mapeada em `$000000` e
`symbols/main68k.sym`; escreve a listagem, o `hardware.inc`, o mapa JSON e o relatório de
cobertura.

Descobre código em três fases, por ordem crescente de especulação:

1. **Travessia recursiva** a partir dos vectores válidos (reset e IRQ 4) e de cada símbolo
   `CODE`/`FUNC`, seguindo `bsr`/`jsr`/`bra`/`bcc`/`dbcc` e as tabelas de salto declaradas.
2. **Tabelas de ponteiros** detectadas por corridas de `long` que caem dentro da região de
   código.
3. **Varrimento linear guardado** dos bytes que sobram, aceite só quando descodifica limpo.

A terceira fase é a que se pode desligar, e vale a pena saber quanto vale:

| | rotinas | zona de código classificada | `UNKNOWN` |
|---|---|---|---|
| omissão | 1774 | 98,4 % | 2704 B |
| `--no-sweep` | 1630 | 96,5 % | 5926 B |

Opções:

| Opção | Para quê |
|---|---|
| `--split` | uma listagem por secção em vez de um `volfied.asm` monolítico; cria o ficheiro de secções se faltar |
| `--clean` | omite a coluna de endereço e bytes crus no fim de cada linha |
| `--no-sweep` | desliga o varrimento linear (só descoberta recursiva) |
| `--code-zone INICIO:FIM` | faixa do relatório de cobertura, hex, **fim exclusivo** (omissão: `000400:029C00`) |
| `--image`, `--rom-dir` | imagem alternativa; se a imagem não existir, é montada a partir das ROMs |
| `--symbols`, `--sections` | outros ficheiros de anotação |
| `--out-dir`, `--json`, `--stats` | outros destinos — a maneira de experimentar sem tocar em `src/` |

A imagem é validada pelo **vector de reset** (`SSP=$00103FFE`, `PC=$000014B8`), não pelo
SHA-1: uma imagem de outro set falha com a mensagem certa, mas uma imagem com um byte
trocado a meio passa. O SHA-1 aparece na cabeça da listagem e é conferido pelos testes.

`--clean` produz a listagem que se daria a um assemblador; a omissão produz a listagem que
se pode **verificar** contra a ROM, porque cada linha carrega o seu endereço e os seus bytes:

```
reset_entry:
        move.w  #$0,VIDEO_CTRL                                          ; $0014B8  33fc000000d00000
        move.w  #$FFFF,VIDEO_MASK                                       ; $0014C0  33fcffff00600000
        lea.l   g_base,a5                                               ; $0014C8  4bf900100000
```

com `--clean`:

```
reset_entry:
        move.w  #$0,VIDEO_CTRL
        move.w  #$FFFF,VIDEO_MASK
        lea.l   g_base,a5
```

O teste que reconstrói a ROM a partir do texto (§5.2) **precisa** da coluna de bytes, logo
não funciona sobre uma listagem `--clean`. Guarde a versão com bytes como a canónica.

O relatório `build/m68k_stats.txt` justifica cada byte que classificou como dados, o que é o
antídoto contra um desmontador que "explica" tudo:

```
Zona de codigo   $000400-$029BFF
  CODE        93884 bytes   55.2%
  DATA        73396 bytes   43.2%
  UNKNOWN      2704 bytes    1.6%
  CLASSIF.   167280 bytes   98.4%

Justificacao dos bytes DATA na zona de codigo
     60452  declarado no .sym
      8155  contiguo a uma referencia
      2910  tabela de ponteiros
      1082  texto ASCII
       356  referenciado pelo codigo
       230  tabela de saltos
       211  enchimento
```

`build/m68k_map.json` (2,5 MB, `schema: volfied/m68k_map/1`) tem uma entrada por rotina com
chamadores, chamados, hardware tocado, variáveis de A5 resolvidas, strings e tabelas. Não o
leia inteiro; consulte-o com `python`/`jq`:

```bash
.venv/bin/python -c "
import json; d=json.load(open('build/m68k_map.json'))
r=[x for x in d['rotinas'] if x['nome']=='snd_send_command'][0]
print(r['hex'], r['hardware'], len(r['chamadores']))"
```

### 2.4 `tools/z80_disasm.py` — o desmontador do Z80

Tabelas de opcodes próprias (o `capstone` não faz Z80), incluindo os prefixos `CB`, `ED`,
`DD`, `FD`, `DDCB`, `FDCB` e as formas não documentadas. Encodings sem mnemónico portável
saem como `defb` com o significado no comentário, para o ficheiro se manter remontável byte
a byte.

Confere sempre SHA-1 **e** CRC32 da imagem de 32 KB; se `build/audiocpu.bin` faltar, cria-a
a partir de `roms/volfied/c04-06.71`.

| Opção | Para quê |
|---|---|
| `--dry-run` | analisa e reporta sem escrever — o modo de exploração |
| `--print-head N` | imprime as primeiras N linhas do `.asm` gerado |
| `--scan-tables` | varredura cega à procura de tabelas de ponteiros; **desligada por omissão** |
| `--min-ptr-entries N` | entradas mínimas para aceitar uma tabela apontada por `ld rr,nn` (omissão: 4) |
| `--min-scan-entries N` | idem para as encontradas por varredura (omissão: 8) |
| `--rom`, `--symbols`, `--asm`, `--inc`, `--map` | caminhos alternativos |

O valor por omissão de `--scan-tables` é uma decisão, não um esquecimento. Medido:

| | tabelas | labels | `PTRTABLE` |
|---|---|---|---|
| omissão | 10 | 510 | 454 B |
| `--scan-tables` | 11 | 519 | 472 B |

A tabela extra cai dentro das sequências de música e não é referida por código nenhum — é um
falso positivo. Ligar a opção degrada a listagem em troca de nada.

A saída resume-se numa linha:

```
z80_disasm: 3343 instrucoes | conteudo gravado 20190/32768 B ($0000-$4EDD; 12578 B de $FF
por gravar) | CODE 6484 (32.11% do conteudo) DATA 11907 (58.97%) PTRTABLE 454 (2.25%)
PADDING 1338 (6.63%) UNKNOWN 7 (0.03%) | 10 tabelas | 9 despachos indirectos | 510 labels
```

Os 7 bytes `UNKNOWN` em 20 190 são o resíduo honesto: 0,03 % da ROM que ninguém conseguiu
classificar.

### 2.5 `tools/upd7810_disasm.py` — o desmontador do C-Chip

Desmonta os 8 KB da EPROM externa do TC0030CMD, mapeada em `$2000-$3FFF` no espaço do
uPD78C11. Modela o *skip* do 78C11 (instruções que saltam a seguinte conforme uma
condição), o que a travessia ingénua perderia.

| Opção | Para quê |
|---|---|
| `--probe-bases` | compara as bases candidatas e sai sem escrever nada |
| `--bases HEX…` | quais as bases a comparar (com `--probe-bases`) |
| `--linear` | varrimento linear **especulativo** da área com conteúdo, com relatório |
| `--linear-asm FICH` | destino do listing especulativo (omissão: `src/cchip/cchip_linear.asm`) |
| `--null-samples N` | amostras por modelo nulo no relatório de `--linear` |
| `--no-skips` | não modela o skip — só para medir quanto é que o skip acrescenta |
| `--entry HEX` | ponto de entrada adicional (repetível) |
| `--head N` | imprime as primeiras N linhas no stdout |
| `--no-verify` | não confere SHA-1/CRC32 (para ROMs alternativas) |

`--probe-bases` é um bom exemplo do tom do projecto: a base **não** é uma hipótese, está no
`cchip_map` do MAME; a sonda existe para mostrar que a ROM concorda com o documento.

```
  base  desp   instr   bytes   cobert   ileg  sobrep  alvo!map  alvo>RAM  jan.part
----------------------------------------------------------------------------------
0x0000     0      87     145     5.2%      0       2         4         1         1
0x1000     8      13      29     1.0%      0       0         0         0         0
0x2000     8     365     772    27.6%      0       0         0         0        45

Melhor hipotese: base 0x2000.
```

A cobertura de 27,6 % também não é sinal de código por descobrir, e `--linear` mostra
porquê: da área com conteúdo, 1872 bytes produzem 3,12 % de opcodes ilegais —
indistinguível dos 3,03 % de bytes aleatórios — e **nenhum** dos seus saltos absolutos
aponta para dentro do código, enquanto o código traçado carrega 7 ponteiros directos para
essa área e nunca lá salta. São tabelas de dados.

O que fica mesmo por resolver é a lacuna conhecida: a ROM máscara interna de 4 KB
(`$0000-$0FFF`) não está dumpada, e com ela faltam os vectores de reset e interrupção, a
tabela `CALT` (`$0080-$00BF`) e a página `CALF` (`$0800-$0FFF`). Ver [04 — C-Chip](04-c-chip.md).

Não existe backend `vasm` para o uPD78C11, e `src/cchip/cchip.asm` diz isso no cabeçalho:
é um listing para leitura humana, não um fonte remontável.

### 2.6 `tools/gfx_extract.py` — gráficos para PNG

Seis subcomandos. O formato e a prova de cada layout estão no §9 de [03 — Vídeo](03-video.md);
aqui fica só o que se corre.

| Subcomando | Escreve | Notas |
|---|---|---|
| `build` | `build/*.bin` | tabela de montagem própria, independente da do `romtool.py` |
| `sprites` | `assets/sprites/` (48 PNG) | 24 bancos de 256 tiles 16×16, cor + cinzento |
| `bitmap` | `assets/tiles/` (34 PNG) | 16 páginas de `$8000` + folha contínua, cor + cinzento |
| `font` | `assets/font/` (250 PNG) + `assets/font_map.json` | duas fontes, 16×16 e 8×8 |
| `palette` | `build/proms/`, `assets/proms/` (2 PNG) | análise das duas PROMs ditas "unused" |
| `contactsheet` | `assets/contactsheet.png` | 40 painéis, 2066×1342 px |

Opções que interessam:

| Opção | Onde | Para quê |
|---|---|---|
| `--strip` | `bitmap` | além das páginas, uma folha única e contínua de 256 px de largura |
| `--tudo` | `bitmap` | lê até `$0FFFFF` em vez de parar no último byte útil (`$0F817F`) |
| `--block N` / `--bank N` | `bitmap` / `sprites` | exporta só um bloco |
| `--individual` | `sprites` | também um PNG por tile |
| `--scale N` | quase todos | ampliação inteira |
| `--raw` | `font` | não roda os tiles 16×16 (mostra-os como estão na ROM) |
| `--strings N` | `font` | quantas strings ASCII da ROM incluir no `font_map.json` |
| `--layout`, `--tile-width`, `--planes`, `--x-step`, … | `sprites`, `bitmap` | testar hipóteses de descodificação sem editar código |
| `--generico` | `sprites`, `bitmap` | força o caminho plano-a-plano lento, usado como referência contra o caminho rápido |

O grupo de opções de layout é a razão pela qual o formato da camada bitmap é *medido* e não
copiado: como o MAME não tem `gfxdecode` para essa região, houve que testar candidatos. O
par `--generico` / caminho rápido é comparado por um teste sobre a ROM real, para a
optimização não poder divergir da referência em silêncio.

`-v` em `bitmap` recalcula e imprime a evidência (costura vertical por número de colunas,
tiles contra bitmap linear, extensão real dos dados) em vez de a afirmar.

Cor: **resolvido**. `tools/palette_extract.py` recupera as paletas da ROM e o
`gfx_extract.py` usa-as. Um PNG com o sufixo `_semipaleta` é o único que continua a usar
uma rampa provisória, e o nome di-lo para não haver engano quando o ficheiro for aberto
sem o manifesto ao lado.

---

## 3. O ciclo `symbols/` → desmontador → `src/`

### 3.1 A regra

```
symbols/fragments/<cpu>/*.sym  ──▶  merge_symbols.py  ──▶  symbols/<cpu>.sym
        (edita-se AQUI)                                    symbols/<cpu>_sections.sym
                                                                  │
                                                                  ▼
                                                          *_disasm.py
                                                                  │
                                                                  ▼
                                                          src/**/*.asm  +  build/*_map.json
```

**As ferramentas nunca escrevem em `symbols/fragments/`.** Tudo o que está à direita das
setas é gerado e pode ser apagado a qualquer momento; o trabalho acumulado são os
fragmentos. Editar `symbols/main68k.sym` directamente funciona até à próxima fusão, que o
reescreve por completo — é um ficheiro gerado, com um cabeçalho a dizê-lo.

### 3.2 Ordem de leitura e o `00_curado`

O fusor lê os fragmentos por ordem alfabética e **o primeiro a declarar um endereço ganha**.
É só isso: não há campo de prioridade, não há metadados. A prioridade é o nome do ficheiro.

```
00_curado.sym          <- curadoria manual, ganha tudo
00_curado_lote0.sym    <- curadoria por lotes, da fase de adjudicação de conflitos
00_curado_lote1.sym
00_curado_lote2.sym
areafill.sym           <- passagem focada no motor de preenchimento
banda00.sym … banda09.sym   <- um agente por faixa de endereços
cchip68k.sym           <- passagem focada no lado 68000 do C-Chip
som68k.sym             <- passagem focada no lado 68000 do som
```

`00_curado.sym` vem antes de `00_curado_lote0.sym` porque `.` (0x2E) ordena antes de `_`
(0x5F), e ambos vêm antes de `areafill.sym` porque `0` ordena antes de `a`. Isto é frágil
por construção — depende do nome — e é por isso que o prefixo `00_` existe: torna a
intenção visível a quem olha para a pasta.

Cabeçalho do ficheiro que decide:

```
# ============================================================================
# Base curada à mão — símbolos do 68000, Volfied (World, rev 1)
# ----------------------------------------------------------------------------
# Este fragmento é lido PRIMEIRO (ordem alfabética), portanto tem prioridade
# sobre o que os agentes de anotação escreveram. É aqui que se corrige um nome
# de que não se gosta, ou se fixa uma decisão sobre um conflito.
#
# symbols/main68k.sym é GERADO a partir daqui + dos outros fragmentos.
# Não edite o ficheiro gerado: edite este.
# ============================================================================
```

### 3.3 Conflitos

Há dois tipos, e nenhum é resolvido em silêncio.

**Mesmo endereço, nomes diferentes.** Fica o do fragmento de menor prioridade
lexicográfica; o outro é reportado no stdout e registado em comentário no topo do ficheiro
gerado.

```
endereço $00168E (FUNC): 00_curado_lote2.sym diz 'cchip_wait_rate_table',
banda00.sym diz 'cchip_wait_ack' — mantido 'cchip_wait_rate_table'
```

**Mesmo nome, endereços diferentes.** Um símbolo tem de ser único, senão a substituição na
listagem fica ambígua. O segundo é renomeado acrescentando o endereço (`nome_0012AB`) e o
facto é reportado.

Casos que **não** são conflito: a mesma coisa dita duas vezes (`CODE 000400 x` e
`FUNC 000400 x`), e vários `COMMENT` no mesmo endereço — `COMMENT` não define símbolo.

Os 155 conflitos actuais não são dívida por pagar: são o registo de que 155 endereços foram
vistos por mais do que um leitor, com leituras diferentes, e de qual venceu. `build/conflitos*.txt`
são instantâneos de uma fusão anterior (145 conflitos) guardados durante a fase de
adjudicação; a contagem viva é a que o comando imprime.

### 3.4 Secções: como uma faixa vira um ficheiro

Uma linha `SECTION <inicio> <fim> <nome>` num fragmento propõe que aquela faixa se chame
assim. Vários agentes cobrem a mesma faixa com granularidades diferentes, e as duas leituras
estão certas — a mais fina é só mais específica. O fusor:

1. corta nos limites de **todas** as secções propostas;
2. dá a cada intervalo o nome da secção **mais pequena** que o cobre (empates pela origem, para
   ser determinístico);
3. junta partes contíguas com o mesmo nome;
4. com `--cobrir`, fecha as lacunas com secções `unclaimed_<endereco>`.

O relatório mostra o que preteriu:

```
SOBREPOSIÇÕES RESOLVIDAS (9):
  $005C32-$005CD5: escolhido vram_fill_walk_helpers (areafill.sym), preterido(s) vram_area_fill (banda01.sym)
  $005CD6-$005FDF: escolhido vram_area_fill_engine (areafill.sym), preterido(s) vram_area_fill (banda01.sym)
  $00600E-$006115: escolhido vram_fill_geometry (areafill.sym), preterido(s) vram_area_fill (banda01.sym)
```

Das 153 secções finais, 7 são `unclaimed_` (vectores, enchimento, dados e gráficos que
ninguém reclamou) e 2 chamam-se explicitamente "não classificado":

```
SECTION 000000 0003FF unclaimed_000000
SECTION 004518 00452B unclaimed_004518
SECTION 0149DA 0149DA unclaimed_0149DA
SECTION 01FFE9 020001 unclaimed_01FFE9
SECTION 026FEF 026FEF unclaimed_026FEF
SECTION 029B2E 0350FF unclaimed_029B2E
SECTION 039D8A 03FFFF unclaimed_039D8A
```

As duas de 1 byte (`$0149DA` e `$026FEF`) são cicatrizes de fronteiras de banda: dois agentes
vizinhos pararam com um byte de intervalo entre si.

**Duas secções podem partilhar nome.** `player_control` aparece em `$004FAE-$0053E5` e outra
vez em `$005488-$005625`; `enemy_boss06_area9` em `$026F7C-$026FEE` e `$026FF0-$0276EB`. O
desmontador junta-as num só ficheiro com dois `org`, e o `include` aparece uma vez:

```
; ============================================================================
; player_control.asm - $004FAE-$0053E5, $005488-$005625
; Gerado por tools/m68k_disasm.py --split. Incluido por volfied.asm.
; ============================================================================

        org     $004FAE
```

> **Isto foi um bug, e é a razão de existir um teste.** Enquanto cada faixa escrevia o seu
> próprio ficheiro, a segunda apagava a primeira e o `include` aparecia duas vezes: 1195
> bytes desapareciam da listagem sem que a contagem de bytes emitidos desse por isso, porque
> a emissão corria para as duas faixas e só o *ficheiro* ficava com uma. `TestSplitCobreTudo`
> guarda a correcção verificando, a partir dos cabeçalhos dos 151 ficheiros, que as faixas
> cobrem `$000000-$03FFFF` sem lacunas nem sobreposições e que nenhum `include` se repete.
> Confirmado hoje: `inp_read_cchip`, `player_update` e `player_move_and_draw_trail` estão em
> [`src/main68k/player_control.asm`](../src/main68k/player_control.asm), linhas 18, 173 e 235.

### 3.5 Contribuir uma anotação nova

O ciclo completo, com um exemplo que foi mesmo corrido (num directório de trabalho, para não
tocar em `symbols/`).

**Passo 1 — encontrar algo por nomear.** As rotinas sem nome humano ficam com `sub_XXXXXX`
ou `loc_XXXXXX`. São 273 em 1774 (as restantes 1501, 84,6 %, têm nome).

```bash
.venv/bin/python -c "
import json,re; d=json.load(open('build/m68k_map.json'))
print([x['nome'] for x in d['rotinas']
       if re.fullmatch(r'(sub|loc)_[0-9A-F]+', x['nome'])][:10])"
```

**Passo 2 — ler o código e a evidência.** A rotina em `$00056A` tem uma instrução:

```
; ============================================================================
; sub_00056A   ($00056A-$00056F, 6 bytes, 1 instr.)
; ----------------------------------------------------------------------------
; Descoberta: jumptable:declared
; Chamada por: game_state2_jumptable
; ============================================================================
sub_00056A:
        jmp     (game_over_dispatch).l                                  ; $00056A  4ef900003c40
```

É um trampolim: uma entrada de tabela de salto que reencaminha para `game_over_dispatch`. O
cabeçalho já diz quem a chama e como foi descoberta — não é preciso procurar.

**Passo 3 — escrever no fragmento.** Nunca em `symbols/main68k.sym`. Um fragmento novo, ou
uma linha no `00_curado.sym` se for para ganhar um conflito:

```
FUNC      00056A  game_over_trampoline            ; jmp (game_over_dispatch).l — um só salto
```

**Passo 4 — refundir e desmontar.**

```bash
.venv/bin/python tools/merge_symbols.py \
    --fragmentos symbols/fragments/main68k --cobrir 000000:03FFFF
.venv/bin/python tools/m68k_disasm.py --split
```

**Passo 5 — confirmar.** O nome aparece na definição e em todos os sítios que referenciam
aquele endereço:

```
$ grep -rn 'game_over_trampoline' src/main68k | head -2
src/main68k/game_screen_sequence.asm:48:; game_over_trampoline   ($00056A-$00056F, 6 bytes, 1 instr.)
src/main68k/game_screen_sequence.asm:54:game_over_trampoline:
```

**Passo 6 — correr os testes.** `.venv/bin/python -m unittest discover -s tools/tests`. Se
citar o nome novo em `docs/`, o `test_docs_consistency.py` confirma que ele existe mesmo.

Para experimentar sem tocar em nada:

```bash
.venv/bin/python tools/merge_symbols.py --fragmentos <frag> --cobrir 000000:03FFFF \
    --saida /tmp/x.sym --seccoes /tmp/x_sec.sym
.venv/bin/python tools/m68k_disasm.py --symbols /tmp/x.sym --sections /tmp/x_sec.sym \
    --split --out-dir /tmp/src --json /tmp/x.json --stats /tmp/x.txt
```

Regras de nomenclatura (identificadores em inglês, comentários em português, prefixos por
subsistema) estão no [README](../README.md) e são o que mantém a listagem coerente entre
agentes que nunca falaram uns com os outros.

### 3.6 O que se perde pelo caminho

Uma coisa que não é óbvia e convém saber antes de escrever a anotação: **só a primeira linha
do comentário chega à listagem**.

O fusor preserva comentários de vários parágrafos, quebrando-os em linhas de continuação
iniciadas por `;`:

```
FUNC      0004BA  snd_read_reply_byte       003A  ; le a resposta do Z80. Espera o bit 2 de
        ; SOUND_COMM_B (PORT01_FULL_MASTER, $0004C2), le SOUND_COMM duas vezes (d0 = nibble BAIXO,
        ; d1 = nibble ALTO - a mesma ordem que snd_send_command usa a escrever) e espera o flag
        ; baixar ($0004E0). Que sao nibbles de UM byte esta no unico chamador: $013F72 faz `lsl.b
```

Mas o leitor de símbolos dos desmontadores descarta as linhas de continuação. Na listagem e
no JSON fica só o primeiro pedaço:

```
; ============================================================================
; snd_read_reply_byte   ($0004BA-$0004F3, 58 bytes, 10 instr.)
; ----------------------------------------------------------------------------
; le a resposta do Z80. Espera o bit 2 de
```

A largura do primeiro pedaço é `100 - len(cabeçalho da entrada) - 4`, ou seja depende do
comprimento do nome e do campo de tamanho. Medido em `symbols/main68k.sym`: das 2407
entradas com comentário, **1386 (58 %) têm continuação**, e o pedaço que sobrevive tem
mediana de 46 caracteres.

Consequências práticas:

- Escreva a frase que interessa **primeiro**. As primeiras ~45 letras são as únicas que
  chegam a quem lê a listagem.
- A anotação completa vive em `symbols/main68k.sym` e nos fragmentos. Quem quiser o
  raciocínio inteiro tem de ir lá.
- Isto é um defeito da ferramenta, não uma decisão de formato. Fica registado como tal.

---

## 4. Decisões de formato

### 4.1 O ficheiro `.sym`

Texto simples, uma entrada por linha, `#` inicia comentário de ficheiro, `;` inicia
comentário de entrada. Colunas: **tipo, endereço, nome, [tamanho], `;` comentário**.

```
CODE      0014B8  reset_entry                     ; PC do reset vector; SSP=$00103FFE
FUNC      00666A  coinage_setup                   ; escolhe a tabela de moedas conforme a região
DATA      003140  bonus_life_table       0030     ; 4 conjuntos x 6 words, LSB first
RAM       100000  g_base                          ; base de A5
IO        200000  PC090OJ_RAM                     ; $200000-$203FFF RAM de sprites
COMMENT   0015CC                                  ; DSWB bit 6: cheat de 32768 vidas
```

Dez tipos: `CODE`, `FUNC`, `DATA`, `RAM`, `RAMVAR`, `IO`, `COMMENT`, `JUMPTABLE`, `STRING`,
`PTRTABLE`. Um tipo desconhecido **falha alto** no desmontador (`ValueError` com ficheiro e
linha), e é apenas avisado no fusor — assimetria deliberada: o fusor tem de conseguir
sobreviver a um fragmento meio escrito, o desmontador não pode inventar.

Endereços em hexadecimal sem prefixo, com o número de dígitos que for natural. `COMMENT` não
tem nome e não define símbolo — daí poderem coexistir vários no mesmo endereço.

Porquê texto e não JSON: é a camada que humanos editam, e tem de sobreviver a `grep`, a um
`diff` legível e a uma edição a meio de um ficheiro de 371 KB. O JSON é a saída, não a
entrada.

### 4.2 Tamanho: entradas ou bytes

O campo de tamanho **conta unidades diferentes conforme o tipo**, e isto é a decisão de
formato mais fácil de errar:

| Tipo | O tamanho conta | Largura de cada unidade |
|---|---|---|
| `JUMPTABLE` | entradas | 2 bytes (deslocamento word) |
| `PTRTABLE` | entradas | 4 bytes (long) |
| `DATA` | bytes | 1 |
| `STRING` | bytes | 1 |

O valor é lido em **hexadecimal**. `JUMPTABLE 0016A2 seq_cmd_jumps 000C` são 12 entradas =
24 bytes; `DATA 003140 bonus_life_table 0030` são 48 bytes = 4 × 6 words, que é o que a
tabela de bónus de vida ocupa (`SECTION 003140 00316F data_bonus_life_table` confirma-o).

> O exemplo em `tools/TOOLING_SPEC.md` escreve `DATA 0003140 bonus_life_table 0018` para
> essa mesma tabela. `$18` = 24 bytes, metade do que a tabela ocupa — o exemplo do
> documento contradiz a regra que ele próprio enuncia. O fragmento curado e o ficheiro de
> secções usam `0030`, e é `0030` que está certo.

### 4.3 `ENTRADAS:PASSO`

Uma tabela cujas entradas não tenham o passo natural declara-o com `ENTRADAS:PASSO`, onde o
passo é em **bytes e decimal** — a única parte do formato que não é hexadecimal. Há uma
ocorrência real, no driver de som:

```
JUMPTABLE 00176D  seq_ext_jumps  0010:4  ; 16 entradas de 4 bytes (ponteiro + parâmetro)
```

Sem isto o desmontador leria os parâmetros como se fossem endereços e seguiria alvos
inexistentes.

**Ressalva verificada:** só `tools/z80_disasm.py` honra o passo. `tools/m68k_disasm.py`
analisa o campo (`Symbol.step`) mas nunca o usa: em `add_declared_table` a entrada `i` está
sempre em `endereco + 2*i`. Hoje isto não faz mal — nenhuma `JUMPTABLE` do 68000 declara
passo — mas uma que declarasse seria lida com o passo errado, em silêncio.

### 4.4 `SECTION` e a partição completa

```
SECTION <inicio> <fim> <nome>
```

Hexadecimal, **fim inclusivo**. As linhas `SECTION` vivem nos mesmos fragmentos que os
símbolos mas são recolhidas à parte e escritas em `symbols/<cpu>_sections.sym`.

O `--split` do desmontador exige que cada byte de `$000000-$03FFFF` pertença a
**exactamente uma** secção: sem isso haveria bytes por emitir ou emitidos duas vezes. Como
os agentes só nomearam a zona de código, as lacunas têm de ser fechadas — é o que
`--cobrir 000000:03FFFF` faz, gerando `unclaimed_<endereco>`. Secções sobrepostas no
ficheiro final são um erro: `parse_sections_file` levanta excepção.

### 4.5 O estilo do assembly emitido

Sintaxe alvo `vasmm68k_mot` (Motorola) para o 68000, `sjasmplus` para o Z80. Mnemónicos e
registos em minúsculas, constantes em `$1234`, mnemónico na coluna 9, operandos na 17,
comentário na 41, endereço e bytes crus no fim.

Duas substituições fazem quase toda a diferença entre uma listagem útil e um despejo de
números:

- **`A5 = $100000`.** O reset faz `lea $100000.l,a5` e daí em diante todo o acesso a
  variáveis globais é `$xx(a5)`. A listagem resolve o deslocamento, mostra o endereço
  absoluto em comentário e usa o nome quando existe.
- **Registos de hardware nomeados.** Todo o acesso absoluto às faixas de I/O passa a
  constante de `src/main68k/hardware.inc`.

Os dados também são emitidos de forma remontável, incluindo as tabelas de salto relativas:

```
        dcb.b   768,$FF                 ; enchimento de 768 bytes       $000100
        dc.w    attract_dispatch-game_state_jumptable  ; [0] -> $000B40  $00046E
        dc.b    "MTJT.STUKOKIV.P"       ; 15 bytes de texto             $00190C
```

Contagem de directivas na listagem monolítica: 7389 `dc.b`, 1020 `dc.l`, 90 `dc.w`, 11
`dcb.b`, um `org`, um `include`, um `end`.

A listagem é **ASCII puro** — sem acentos, incluindo nos comentários. É por isso que os
comentários em `src/` estão sem acentuação enquanto os `.sym` e os `docs/` os têm: os
assembladores não gostam de UTF-8 e a transliteração é feita à saída.

Cada linha absoluta que o assemblador poderia encurtar (mudando os bytes gerados) leva a
forma `(nome).l` explícita, para o resultado ser o mesmo tamanho que a ROM.

### 4.6 `hardware.inc`

Gerado, não editável à mão: 870 `equ` em três blocos — regiões do mapa de memória, registos
com nome próprio, e os nomes vindos de `symbols/main68k.sym` (incluindo os deslocamentos de
A5 observados no código).

```
RAM_BASE         equ $100000            ; RAM principal (16 KB) - A5 aponta aqui
SPRITE_RAM       equ $200000            ; PC090OJ: RAM de sprites
VIDEO_MASK       equ $600000            ; Mascara de escrita de bits da VRAM
```

Verificado: nenhum nome repetido, nenhum nome que colida com um mnemónico do 68000. Um
mesmo endereço pode ter dois nomes (`RAM_BASE` e `g_base` valem ambos `$100000`), o que é
legítimo — são `equ`, não etiquetas.

Uma verruga: em 585 das 870 linhas o comentário cola-se ao valor (`equ $100000; texto`), sem
espaço antes do `;`. Em sintaxe Motorola o `;` termina a expressão e não deve dar problema,
mas isto é exactamente o tipo de coisa que só uma montagem real confirma. Ver §7.

---

## 5. Os testes

```bash
.venv/bin/python -m unittest discover -s tools/tests
```

Sem dependências externas. 13,6 s.

### 5.1 Distribuição

| Módulo | Testes | O que cobre |
|---|---|---|
| `test_upd7810_disasm.py` | 76 | tabelas de opcodes contra o MAME, descodificação, semântica do skip |
| `test_m68k_disasm.py` | 62 | descodificação, descoberta, substituição de símbolos, saídas |
| `test_z80_disasm.py` | 58 | os 256 opcodes de cada prefixo, tabelas, cobertura da ROM |
| `test_gfx_extract.py` | 43 | layout, montagem, rotação, invariantes da ROM, mapa da fonte |
| `test_romtool.py` | 31 | tabela de regiões, verify, build, vectores, entropia |
| `test_merge_symbols.py` | 21 | análise, fusão, conflitos, secções, round-trip da formatação |
| `test_docs_consistency.py` | 4 | a documentação não inventa nomes nem links |
| **total** | **295** | |

Testa-se o que é objectivamente verificável: hashes, round-trips, invariantes de tabelas de
opcode, e igualdade entre um caminho rápido e um caminho de referência. Não se testa se um
nome de rotina está *certo* — isso não é testável, é revisão.

### 5.2 O teste que reconstrói a ROM a partir do texto

`test_a_listagem_reproduz_a_rom_byte_a_byte` é a garantia mais forte que existe sem um
assemblador. Lê o **texto** de `volfied.asm`, e para cada linha:

- se tem coluna de bytes crus, usa-os;
- se é `dc.b` de string, usa os caracteres entre aspas;
- se é `dc.b`, `dc.w`, `dc.l` ou `dcb.b` de expressões, **avalia as expressões** — resolve
  símbolos contra o `hardware.inc` e contra as etiquetas da própria listagem, e faz as
  subtracções das tabelas de salto relativas;

depois exige que o endereço de cada linha seja exactamente o fim da anterior (sem lacunas
nem sobreposições), que os bytes batam com `build/maincpu.bin`, e que a soma termine em
`$040000`. Mais de 30 000 linhas emitidas.

Nota importante sobre o que isto prova: para as **linhas de dados** é uma remontagem
verdadeira, porque os operandos são avaliados. Para as **instruções** não é: os bytes vêm da
coluna que o próprio desmontador escreveu. O teste prova que a listagem *cobre* a ROM
exactamente, não que o texto do mnemónico se volte a montar nesses bytes. Ver §7.

### 5.3 O teste que confere cada símbolo contra os bytes

`test_cada_simbolo_vale_o_endereco_que_os_bytes_codificam` fecha metade da lacuna anterior.
Para cada linha de instrução, descodifica os bytes crus com o `capstone` **sem passar pelo
desmontador**, resolve o texto do operando com o `hardware.inc` e as etiquetas da listagem, e
exige que o número resolvido seja exactamente o que os bytes codificam. Cobre endereçamento
absoluto longo e curto, deslocamentos de branch e modos relativos ao PC. Mais de 5000
operandos verificados.

Foi este teste que apanhou `btst.b #$0,SOUND_COMM` — um nome certo a valer `$E00002` numa
instrução que acede a `$E00003`. Um símbolo com o valor errado é a falha mais perigosa deste
projecto, porque parece correcta.

### 5.4 O teste de consistência da documentação

`test_docs_consistency.py` constrói o universo de todos os identificadores que o projecto
define — símbolos de `symbols/**.sym`, etiquetas e nomes de ficheiro de `src/**.asm`, `equ`
de `src/**.inc`, e identificadores do MAME em `reference/mame/` — e verifica que:

1. nenhum identificador citado em backticks em `docs/*.md` com um dos prefixos do projecto é
   inventado;
2. nenhum link relativo em `docs/*.md` está morto;
3. nenhuma cerca de código ficou por fechar.

`ACHADOS_ANOTACAO.md` é excluído da regra 1 por ser material de trabalho em bruto: contém
nomes que os agentes consideraram e **rejeitaram**, e citá-los ali é o comportamento certo.

Foi assim que se descobriu que `fm_fnum_table` e `seq_cmd2_dispatch` eram usados pela
documentação sem nunca terem sido declarados nos símbolos. A correcção não foi apagar o
texto: foi ir ao código, confirmar que as duas coisas existem, e declará-las no
`00_curado.sym` do Z80 com a prova no comentário.

Um efeito colateral a ter em conta: o universo inclui as etiquetas de
`src/cchip/cchip_linear.asm`. Nomes que só existem lá dentro passam a regra 1 hoje e
deixariam de passar se esse ficheiro fosse regenerado — ver §8.

### 5.5 Estado actual

**295 de 295 passam** (`Ran 295 tests in 13.562s ... OK`).

Chegou lá durante a escrita deste documento, e o percurso vale mais do que o resultado.
Enquanto os documentos 07 e 08 ainda não existiam, `docs/00-visao-geral.md` já os indexava e
o teste de links falhava com três entradas:

```
AssertionError: links relativos mortos:
  00-visao-geral.md: [07 — Texto e fonte] -> 07-texto-e-fonte.md
  00-visao-geral.md: [08 — Ferramentas] -> 08-ferramentas-e-reproducao.md
  00-visao-geral.md: [08] -> 08-ferramentas-e-reproducao.md
```

É exactamente para isto que o teste serve: um índice que promete um documento que não existe
é uma mentira pequena, e sem guarda automática ninguém dá por ela.

Três erros na saída (`ERROR faixa vazia: $1000..$1000`, `ERROR ... esperados 1048576 bytes`,
`WARNING ... seccoes.sym não existia`) são **esperados**: são testes que verificam que a
ferramenta falha alto perante entrada inválida, e o que se vê é a mensagem de erro a ser
produzida como devia.

---

## 6. Determinismo

O contrato diz "mesma entrada → bytes idênticos", e isso foi verificado, não assumido. Cada
ferramenta foi corrida com destinos alternativos e a saída comparada byte a byte com o que
está no repositório:

| Comparação | Resultado |
|---|---|
| `merge_symbols` (68000) → `symbols/main68k.sym` + `_sections.sym` | idêntico |
| `merge_symbols` (Z80) → `symbols/sound_z80.sym` + `_sections.sym` | idêntico |
| `merge_symbols` (C-Chip) → `symbols/cchip.sym` + `_sections.sym` | idêntico |
| `m68k_disasm --split` → os 152 ficheiros de `src/main68k/` | idêntico (`diff -rq` limpo) |
| `m68k_disasm` → `build/m68k_map.json`, `build/m68k_stats.txt` | idêntico |
| `z80_disasm` → `src/sound_z80/sound.asm`, `hardware.inc`, `build/z80_map.json` | idêntico |
| `upd7810_disasm` → `src/cchip/cchip.asm`, `build/cchip_map.json` | idêntico |
| `gfx_extract sprites/bitmap/font/palette/contactsheet` → os 335 PNG + `font_map.json` | idêntico (SHA-1 de 337 ficheiros antes e depois) |

Duas conclusões:

1. `src/`, `build/*.json` e `assets/` estão **em sincronia** com os fragmentos de símbolos
   deste momento. Não há saída obsoleta escondida — com uma excepção, no §8.
2. `romtool.py` e `gfx_extract.py` montam as imagens com tabelas independentes uma da outra,
   e chegam aos mesmos quatro SHA-1. Não é uma verificação totalmente independente (ambas
   conferem contra o mesmo contrato de hash), mas apanha um erro de transcrição numa delas.

---

## 7. "Remontável" continua por provar

O `TOOLING_SPEC` diz que a listagem do 68000 "deve ser remontável" com `vasmm68k_mot`, e a do
Z80 com `sjasmplus`. **Isso não foi demonstrado.**

### 7.1 Não há assemblador instalado

Verificado nesta máquina: `vasmm68k_mot`, `vasm`, `m68k-elf-as`, `sjasmplus`, `z80asm`,
`asl` e `asm68k` não estão em `PATH`, e o Homebrew não tem nenhum deles instalado. Não é uma
questão de correr um comando: falta a ferramenta.

### 7.2 O que os testes provam e o que não provam

| Afirmação | Estado |
|---|---|
| A listagem cobre `$000000-$03FFFF` sem lacunas nem sobreposições | **provado** (§5.2) |
| Os bytes declarados por cada linha são os da ROM | **provado** (§5.2) |
| As directivas de dados (`dc.b/w/l`, `dcb.b`) reproduzem os bytes quando os operandos são avaliados | **provado** — é uma remontagem verdadeira dessas linhas |
| Cada símbolo que aparece num operando vale o endereço que os bytes codificam | **provado** (§5.3, 5000+ operandos) |
| A listagem é ASCII puro, tem `include`, `org` e `end` | **provado** |
| Nenhum operando sai com registo vazio ou sintaxe impossível | **provado** (teste dedicado) |
| **O texto dos mnemónicos, dado a `vasmm68k_mot`, produz os mesmos 262 144 bytes** | **por provar** |

A última linha é a que interessa e é a que falta. Tudo o resto é circunstancial: prova que a
listagem *descreve* a ROM correctamente, não que um assemblador concorde com a descrição.

### 7.3 Como fechar a prova

```bash
# 1. Instalar vasm (ex.: brew install vasm, ou compilar de sources)
# 2. Gerar a listagem sem a coluna de bytes, que não é sintaxe válida
.venv/bin/python tools/m68k_disasm.py --clean --out-dir build/asm \
    --json build/asm/map.json --stats build/asm/stats.txt
# 3. Montar em binário plano
vasmm68k_mot -Fbin -o build/asm/volfied.bin build/asm/volfied.asm
# 4. Comparar com os primeiros 256 KB da imagem
cmp <(head -c 262144 build/maincpu.bin) build/asm/volfied.bin
```

Enquanto o passo 4 não sair limpo, "remontável" é uma intenção de projecto, não um facto.
O mesmo vale para o Z80 com `sjasmplus`, e não vale de todo para o C-Chip: não existe backend
`vasm` para o uPD78C11 e `src/cchip/cchip.asm` declara-se explicitamente como listing de
leitura, não fonte.

### 7.4 Riscos concretos já identificados

Não são conjecturas gerais; são coisas que se vêem nos ficheiros e que uma montagem real
resolveria num minuto.

1. **Dois `org` que recuam na listagem segmentada.** Porque duas secções partilham nome e são
   fundidas num só ficheiro (§3.4), a ordem dos `include` deixa de ser monótona em endereço.
   Medido: exactamente 2 recuos, `vram_fill_arm.asm` a fazer `org $0053E6` depois de
   `$005626`, e `unclaimed_026FEF.asm` a fazer `org $026FEF` depois de `$0276EC`. Com
   `-Fbin`, o comportamento do `vasm` perante um `org` que recua não foi testado. A listagem
   **monolítica** (sem `--split`) não tem este problema: tem um único `org $000000` e é
   estritamente linear — é a que se deve usar para a prova do §7.3.
2. **Comentário colado ao valor em 585 `equ` do `hardware.inc`** (§4.6). Deve ser aceite; não
   foi confirmado.
3. **Linhas longas.** A mais comprida do `hardware.inc` tem 123 caracteres, a mais comprida
   da listagem tem 251. Assembladores antigos truncam.
4. **Um símbolo por endereço, mas dois nomes por valor.** `RAM_BASE` e `g_base` valem ambos
   `$100000`. Legítimo, mas nunca passou por um assemblador.
5. **Os `defb` do Z80.** Encodings sem mnemónico portável são emitidos como bytes com o
   significado em comentário, precisamente para a remontagem bater. Isso é o desenho certo,
   e continua por confirmar.

---

## 8. O que não sabemos

**A prova de remontagem.** É a lacuna principal deste documento e está toda no §7. Não há
assemblador instalado; "remontável" é uma propriedade desenhada e testada por aproximação,
nunca demonstrada por montar e comparar.

**`src/cchip/cchip_linear.asm` está desactualizado.** É o único artefacto gerado que **não**
está em sincronia. O guião do §1.3 não passa `--linear`, logo o ficheiro nunca é regenerado.
Verificado: o ficheiro em `src/` é de 10 horas antes do `symbols/cchip.sym` actual, e uma
regeneração hoje muda 248 linhas — todas nomes de etiqueta. As que lá estão vêm de um
conjunto de símbolos que já não existe:

```
  actual em src/            regenerado hoje
  cchip_dispatch:           entry_2000:
  irq_int1_entry            entry_2093
  bank_select_entry         entry_201E
```

Não corrigi isto porque não é claro qual é a versão certa: os nomes antigos são mais
informativos do que os automáticos, e a decisão correcta é provavelmente declará-los em
`symbols/fragments/cchip/00_curado.sym` — o que exige rever o que cada um significa, e isso é
trabalho de análise, não de reprodução. Quem o fizer deve saber que os nomes antigos hoje
entram no universo do `test_docs_consistency.py` (§5.4) só por estarem nesse ficheiro.

**`build/bandas/*.json` não são reproduzíveis.** São os digests por faixa que a fase de
anotação deu a cada agente. Nenhuma ferramenta em `tools/` os escreve, e o script que os
produziu não está no repositório. São recortes de um `m68k_map.json` de então: uma
re-extracção ingénua do mapa actual dá 187 rotinas para a banda 00 contra as 188 do digest.
São um instantâneo histórico, não um artefacto vivo. `build/conflitos*.txt` estão no mesmo
caso (145 conflitos contra os 155 de hoje).

**Números que divergem entre documentos.** Medido hoje, com o comando ao lado:

| Grandeza | Medido | Comando | Onde diverge |
|---|---|---|---|
| PNG em `assets/` | 335 | `find assets -name '*.png' \| wc -l` | o README diz 336 |
| entradas `FUNC` | 1480 | `grep -c '^FUNC' symbols/main68k.sym` | o README diz 1481 |
| rotinas com nome não automático | 1501 de 1774 (84,6 %) | contagem sobre `build/m68k_map.json` | README e 00 dizem 83 % |
| testes | 295 | `unittest discover` | o README diz 287 |

As três primeiras não são erros graves — são instantâneos de momentos diferentes de um
projecto que ainda se mexe. Ficam aqui para quem precisar de um número saber qual é o
comando que o produz, em vez de escolher entre dois documentos.

**A justificação de 2704 bytes na zona de código.** O relatório de cobertura diz `UNKNOWN
2704 bytes 1.6%` e lista os cinco maiores blocos, o maior dos quais é
`$008A4A-$008D8B` (834 bytes). Não sabemos o que são. Aparecem no ficheiro de secção que os
contém, emitidos como `dc.b`, e a listagem reproduz a ROM na mesma.

**Se o varrimento linear inventa rotinas.** As 99 rotinas descobertas por `sweep` (§2.3)
descodificam limpo e não se sobrepõem a nada, mas nenhuma tem chamador conhecido. Podem ser
código morto, podem ser alvos de despacho indirecto que o analisador não resolveu, e podem
ser dados que por acaso descodificam. `--no-sweep` mostra a listagem sem elas, e a diferença
de cobertura (98,4 % contra 96,5 %) é a medida da aposta.

**O comportamento do `vasm` perante os dois `org` que recuam.** §7.4, ponto 1. É a única das
cinco preocupações desse ponto que tem uma consequência prática já visível: se o `vasm` não
gostar, a listagem segmentada não é montável como está, e a monolítica é a via.
