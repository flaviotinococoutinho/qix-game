# `addons/` — o que está aqui e por quê

> **Verificado em** 2026-09-06 · commit `34634d0` · Godot 4.7.2-stable, Linux headless
> **Alcance:** inventário das oito pastas de `addons/`, cruzado por caminho (`addons/<pasta>`) e
> por `class_name` contra `game/`, `ui/`, `app/`, `tools/`, `tests/`, `content/` e `project.godot`.
> A primeira das sete remoções da ADR-0010 (`curved_lines_2d`) foi executada nesta data, com posse
> de `uid://` medida. Não julga a qualidade de nenhum addon nem se algum deles resolveria melhor um
> Uma das sete remoções da ADR-0010 (`phantom_camera`) foi executada nesta data, com posse de
> `uid://` medida. Não julga a qualidade de nenhum addon nem se algum deles resolveria melhor um
> problema aberto — só registra quem consome o quê hoje.
> **Alcance:** inventário das oito pastas de `addons/`, cruzado por caminho (`addons/<pasta>`), por
> `uid://` e por `class_name` contra `game/`, `ui/`, `app/`, `tools/`, `tests/`, `content/` e
> `project.godot`. A posse de `addons/guide` foi remedida por `grep` antes da remoção desta data.
> Não julga a qualidade de nenhum addon nem se algum deles resolveria melhor um problema aberto —
> só registra quem consome o quê hoje.
> `GDDraw` saiu nesta data pela ADR-0010; as outras seis `a-remover` continuam por remover, uma por
> PR. Não julga a qualidade de nenhum addon nem se algum deles resolveria melhor um problema aberto
> — só registra quem consome o quê hoje.

Uma pasta em `addons/` sem uma linha aqui é uma decisão adiada: quem lê o repositório amanhã não
consegue distinguir dependência real de resto de download. A regra e o porquê estão em
[`docs/decisions/ADR-0010-addons-inventory.md`](../docs/decisions/ADR-0010-addons-inventory.md);
esta tabela é a aplicação dela, e `tests/unit/addons_manifest_test.gd` recusa qualquer divergência
entre a tabela e o disco.

## Estados

| Estado | Significa | O teste exige |
|---|---|---|
| `dependencia` | Código do jogo consome a pasta. | Ao menos um arquivo fora de `addons/` cita `addons/<pasta>`. |
| `ferramenta` | Serve ao editor ou ao agente; nunca entra no pacote. | A pasta é citada em `project.godot` (plugin habilitado ou autoload). |
| `a-remover` | Sem consumidor. Sai numa PR própria, uma pasta por vez. | Nenhuma citação fora de `addons/`, e a pasta consta do `exclude_filter` dos dois presets de export. |

## Inventário

| Pasta | Estado | Por que está aqui |
|---|---|---|
| `curve2collision` | `a-remover` | 48 KB para gerar colisão a partir de `Curve2D`. O jogo não usa física. |
| `fennara` | `ferramenta` | Autoload `_fennara_game_capture` (`project.godot`) e GDExtension de captura para sessões com o editor aberto. `bin/` não é versionado — daí o `Can't open dynamic library` esperado em toda execução headless. |
| `godot_ai` | `ferramenta` | Único plugin habilitado em `[editor_plugins]`, mais o autoload `_mcp_game_helper`. É a ponte MCP das sessões locais. |
| `guide` | `a-remover` | 2,7 MB de motor de entrada unificado. A entrada deste jogo passa por `GameInputAdapter` e pela fronteira da ADR-0006, que não delega a ele. Os demos (`guide_examples/`) já foram podados. |
| `softbody2d` | `a-remover` | 112 KB de corpo mole por Voronoi. Sem física no domínio, por invariante 1. |
| `yard` | `a-remover` | 1,1 MB de base de dados de recursos. `content/` já é transacional pela ADR-0008. |

Somadas, as seis pastas `a-remover` ocupam ~7,9 MB e declaram 59 cenas que nenhum leitor deste
Somadas, as seis pastas `a-remover` ocupam ~9,3 MB e declaram 71 cenas que nenhum leitor deste
| `phantom_camera` | `a-remover` | 2,2 MB de direção de câmera. O campo é 240×320 fixo, sem câmera que se mova. |
| `softbody2d` | `a-remover` | 112 KB de corpo mole por Voronoi. Sem física no domínio, por invariante 1. |
| `yard` | `a-remover` | 1,1 MB de base de dados de recursos. `content/` já é transacional pela ADR-0008. |

Somadas, as seis pastas `a-remover` ocupam ~8,8 MB e declaram 82 cenas que nenhum leitor deste
jogo precisa abrir.
Somadas, as seis pastas `a-remover` que restam ocupam ~9,4 MB e declaram 100 cenas que nenhum
leitor deste jogo precisa abrir. Eram sete, ~11,3 MB e 101 cenas até a saída de `GDDraw`.

A linha de `exclude_filter` de `export_presets.cfg` **continua citando as pastas já removidas**, e
isso é deliberado: um checkout que rebaixe os addons pela AssetLib recria a pasta em disco, e o
filtro cobre um caminho que o `.gitignore` não cobre. É a mesma razão pela qual `guide_examples/**`
e `samples/**` seguem lá depois da poda dos demos. Não "limpe" isso.

## Remoções já executadas

A ADR-0010 decide que cada `a-remover` sai numa PR própria, com a mesma evidência de posse de
`uid://` usada na poda dos demos. Feitas até aqui:

| Pasta | Quando | Evidência |
|---|---|---|
| `curved_lines_2d` | 2026-09-06 | 296 arquivos, 3,4 MB, 42 cenas, 17 `class_name`. Os **170 `uid://`** declarados dentro dela não aparecem **nenhuma vez** fora dela no repositório versionado; nenhum dos 17 `class_name` é citado em `game/`, `ui/`, `app/`, `tools/`, `tests/`, `content/` ou `project.godot`; a única citação do caminho era o próprio `exclude_filter`. Ver `docs/loop/runs/2026-09-06T195841Z.md`. |
| `phantom_camera` | 2026-09-06 | 203 arquivos, 2,2 MB, 30 cenas, 11 `class_name`. Os **122 `uid://`** declarados dentro dela não aparecem **nenhuma vez** fora dela no repositório versionado; nenhum dos 11 `class_name` é citado em `game/`, `ui/`, `app/`, `tools/`, `tests/`, `content/` ou `project.godot`; a única citação do caminho era o próprio `exclude_filter`. Ver `docs/loop/runs/2026-09-06T215930Z.md`. |

O `exclude_filter` de uma pasta removida **fica** em `export_presets.cfg`, e
`tests/integration/shipping_export_test.gd` passa a exigi-lo por preset: um checkout que rebaixe
os addons pela AssetLib recria a pasta em disco, e `.gitignore` não cobre o payload de export.
A ADR-0010 manda tirar as pastas `a-remover` **uma por PR**. Esta tabela existe para que a próxima
execução saiba o que já saiu sem reler o `git log`, e para que a evidência de posse fique junto da
decisão em vez de só no corpo de um PR mesclado.

| Pasta | Quando | Evidência de posse |
|---|---|---|
| `guide` | 2026-09-06 | 289 `uid://` declarados, **0** citados fora da pasta; 79 `class_name`, **0** citados em `game/`, `ui/`, `app/`, `tools/`, `tests/`, `content/` ou `project.godot`; única citação do caminho era o `exclude_filter`. |

A linha do `exclude_filter` **não** sai junto com a pasta: um checkout que rebaixe os addons pela
AssetLib recria o diretório em disco, e `.gitignore` não cobre o payload de export. Reaparecendo,
`addons_manifest_test.gd` fica vermelho por pasta sem linha no inventário — que é exatamente a
barreira que a ADR-0010 quis comprar.

## Como acrescentar um addon

Copie a pasta, acrescente a linha aqui com o estado e o motivo, e rode a suíte. Um addon novo sem
linha falha em `addons_manifest_test.gd` antes de chegar à revisão — que é onde a pergunta "por que
isto está aqui?" custa mais barato de responder.
