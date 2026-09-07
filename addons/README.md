# `addons/` — o que está aqui e por quê

> **Verificado em** 2026-09-07 · commit `34634d0` · Godot 4.7.2-stable, Linux headless
> **Alcance:** inventário das oito pastas de `addons/`, cruzado por caminho (`addons/<pasta>`) e
> por `class_name` contra `game/`, `ui/`, `app/`, `tools/`, `tests/`, `content/` e `project.godot`.
> `curve2collision` saiu do disco nesta data (ADR-0010, 1ª das sete remoções); as outras seis
> continuam marcadas `a-remover` e ainda em disco. Não julga a qualidade de nenhum addon nem se
> algum deles resolveria melhor um problema aberto — só registra quem consome o quê hoje.

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
| `GDDraw` | `a-remover` | 1,9 MB de ferramenta de pintura de textura. Sem consumidor. |
| `curved_lines_2d` | `a-remover` | 3,4 MB de vetor escalável e importador de SVG. A arte deste jogo é máscara R8 e shader, não SVG. |
| `fennara` | `ferramenta` | Autoload `_fennara_game_capture` (`project.godot`) e GDExtension de captura para sessões com o editor aberto. `bin/` não é versionado — daí o `Can't open dynamic library` esperado em toda execução headless. |
| `godot_ai` | `ferramenta` | Único plugin habilitado em `[editor_plugins]`, mais o autoload `_mcp_game_helper`. É a ponte MCP das sessões locais. |
| `guide` | `a-remover` | 2,7 MB de motor de entrada unificado. A entrada deste jogo passa por `GameInputAdapter` e pela fronteira da ADR-0006, que não delega a ele. Os demos (`guide_examples/`) já foram podados. |
| `phantom_camera` | `a-remover` | 2,2 MB de direção de câmera. O campo é 240×320 fixo, sem câmera que se mova. |
| `softbody2d` | `a-remover` | 112 KB de corpo mole por Voronoi. Sem física no domínio, por invariante 1. |
| `yard` | `a-remover` | 1,1 MB de base de dados de recursos. `content/` já é transacional pela ADR-0008. |

Somadas, as seis pastas `a-remover` que restam ocupam 11 456 KiB (~11,2 MB) e declaram 101 cenas que
nenhum leitor deste jogo precisa abrir. Eram sete: `curve2collision` (48 KB, nenhuma cena) saiu em
2026-09-07 — a contagem de cenas não mudou porque ela não declarava nenhuma.

A linha `addons/curve2collision/**` **fica** no `exclude_filter` dos dois presets de export, pela
mesma razão pela qual `guide_examples/**` e `samples/**` ficaram depois da poda dos demos: um
checkout que rebaixe os addons pela AssetLib recria a pasta em disco, e o filtro cobre um caminho
que o `.gitignore` não cobre. O teste não exige mais essa linha — ela é cinto e suspensório.

## Como acrescentar um addon

Copie a pasta, acrescente a linha aqui com o estado e o motivo, e rode a suíte. Um addon novo sem
linha falha em `addons_manifest_test.gd` antes de chegar à revisão — que é onde a pergunta "por que
isto está aqui?" custa mais barato de responder.
