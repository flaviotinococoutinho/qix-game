# `addons/` — o que está aqui e por quê

> **Verificado em** 2026-09-07 · commit `34634d0` · Godot 4.7.2-stable, Linux headless
> **Alcance:** inventário das oito pastas de `addons/` (eram nove; `softbody2d` saiu nesta data),
> cruzado por caminho (`addons/<pasta>`), por `class_name` e por posse de `uid://` contra `game/`,
> `ui/`, `app/`, `tools/`, `tests/`, `content/` e `project.godot`.
> Não julga a qualidade de nenhum addon nem se algum deles resolveria melhor um problema aberto —
> só registra quem consome o quê hoje.

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
| `curve2collision` | `a-remover` | 48 KB para gerar colisão a partir de `Curve2D`. O jogo não usa física. |
| `curved_lines_2d` | `a-remover` | 3,4 MB de vetor escalável e importador de SVG. A arte deste jogo é máscara R8 e shader, não SVG. |
| `fennara` | `ferramenta` | Autoload `_fennara_game_capture` (`project.godot`) e GDExtension de captura para sessões com o editor aberto. `bin/` não é versionado — daí o `Can't open dynamic library` esperado em toda execução headless. |
| `godot_ai` | `ferramenta` | Único plugin habilitado em `[editor_plugins]`, mais o autoload `_mcp_game_helper`. É a ponte MCP das sessões locais. |
| `guide` | `a-remover` | 2,7 MB de motor de entrada unificado. A entrada deste jogo passa por `GameInputAdapter` e pela fronteira da ADR-0006, que não delega a ele. Os demos (`guide_examples/`) já foram podados. |
| `phantom_camera` | `a-remover` | 2,2 MB de direção de câmera. O campo é 240×320 fixo, sem câmera que se mova. |
| `yard` | `a-remover` | 1,1 MB de base de dados de recursos. `content/` já é transacional pela ADR-0008. |

Somadas, as seis pastas `a-remover` que restam ocupam ~11,4 MB e declaram 101 cenas que nenhum
leitor deste jogo precisa abrir.

`softbody2d` (112 KB, 14 arquivos, 0 cenas, 4 `.gd`) saiu em 2026-09-07, executando uma das sete
remoções previstas pela ADR-0010. Era a pasta cuja permanência contradizia o invariante 1 de forma
mais direta: um plugin de corpo mole por Voronoi só tem sentido com física, e o domínio deste jogo
não tem física nenhuma — é ponto fixo 8.8 sobre `PackedByteArray`. Com ela saem três símbolos do
namespace global (`SoftBody2D`, `SoftBody2DRigidBody`, `Voronoi2D`), sendo que `SoftBody2D` é
exatamente o nome que alguém procurando "corpo/colisão" no autocompletar do editor encontraria
primeiro — e encontraria uma resposta errada sobre como este jogo funciona.

A linha de `exclude_filter` **continua** citando `addons/softbody2d/**` nos dois presets, pela
mesma razão que `guide_examples/**` e `samples/**` continuam lá: um checkout que rebaixe o addon
pela AssetLib recria o caminho em disco, e o filtro cobre o que o `.gitignore` não cobre. A guarda
só exige a linha enquanto a pasta é declarada no manifesto; mantê-la é barato e cobre a recaída.

## Como acrescentar um addon

Copie a pasta, acrescente a linha aqui com o estado e o motivo, e rode a suíte. Um addon novo sem
linha falha em `addons_manifest_test.gd` antes de chegar à revisão — que é onde a pergunta "por que
isto está aqui?" custa mais barato de responder.
