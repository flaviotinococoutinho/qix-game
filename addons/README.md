# `addons/` — o que está aqui e por quê

> **Verificado em** 2026-09-07 · commit `34634d0` · Godot 4.7.2-stable, Linux headless
> **Alcance:** inventário das duas pastas que restam em `addons/`, cruzado por caminho
> (`addons/<pasta>`) e por `class_name` contra `game/`, `ui/`, `app/`, `tools/`, `tests/`,
> `content/` e `project.godot`. As **sete** remoções previstas pela ADR-0010 foram executadas —
> a tabela § Remoções já executadas traz a contagem de cada uma remedida contra a árvore de
> `origin/main` em `34634d0`, não copiada da prosa dos PRs. Não julga a qualidade de nenhum addon
> nem se algum deles resolveria melhor um problema aberto — só registra quem consome o quê hoje.

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

O estado `a-remover` continua no vocabulário mesmo sem nenhuma pasta o usando hoje: é ele que dá a
um addon novo sem consumidor um lugar onde esperar a decisão, em vez de ficar em disco sem linha.

## Inventário

| Pasta | Estado | Por que está aqui |
|---|---|---|
| `fennara` | `ferramenta` | Autoload `_fennara_game_capture` (`project.godot`) e GDExtension de captura para sessões com o editor aberto. `bin/` não é versionado — daí o `Can't open dynamic library` esperado em toda execução headless. |
| `godot_ai` | `ferramenta` | Único plugin habilitado em `[editor_plugins]`, mais o autoload `_mcp_game_helper`. É a ponte MCP das sessões locais. |

Nenhuma pasta `a-remover` resta: as sete saíram. Somadas, ocupavam **6 936 KiB** versionados e
declaravam **101 cenas** que nenhum leitor deste jogo precisava abrir — toda busca por "cena deste
jogo" atravessava-as primeiro.

## Remoções já executadas

A ADR-0010 decide que cada `a-remover` sai numa PR própria, com a mesma evidência de posse de
`uid://` usada na poda dos demos. As sete foram feitas assim, uma por PR, e integradas juntas:

| Pasta | PR | Arquivos | Cenas | KiB | `class_name` | Posse |
|---|---|---|---|---|---|---|
| `curved_lines_2d` | #60 | 296 | 42 | 2 589 | 17 | Nenhum dos 170 `uid://` citado fora da pasta; nenhum `class_name` em `game/`, `ui/`, `app/`, `tools/`, `tests/`, `content/` ou `project.godot`. A arte deste jogo é máscara R8 e shader, não SVG. |
| `phantom_camera` | #62 | 203 | 30 | 1 455 | 11 | Nenhum dos 122 `uid://` citado fora da pasta; mais 13 fontes C# que este build não-mono nem compila. O campo é 240×320 fixo: não há câmera que se mova. |
| `guide` | #63 | 549 | 19 | 1 096 | 79 | Nenhum dos 289 `uid://` citado fora da pasta. A entrada passa por `GameInputAdapter` e pela fronteira da ADR-0006, que não delega a ele. Era a maior devolução de namespace global das sete. |
| `GDDraw` | #64 | 218 | 1 | 961 | 10 | Ferramenta de pintura de textura, sem consumidor. |
| `yard` | #66 | 108 | 9 | 757 | 1 | Base de dados de recursos; `content/` já é transacional pela ADR-0008. |
| `softbody2d` | #72 | 14 | 0 | 62 | 3 | Corpo mole por Voronoi só tem sentido com física, e o domínio é ponto fixo 8.8 sobre `PackedByteArray` (invariante 1). Levava `SoftBody2D` no namespace global — o primeiro resultado de quem procurasse "corpo/colisão" no autocompletar, e uma resposta errada sobre como este jogo funciona. |
| `curve2collision` | #73 | 9 | 0 | 16 | 1 | Colisão a partir de `Curve2D`. O jogo não usa física. |

As contagens acima foram remedidas contra `origin/main` em `34634d0` no momento da integração
(`git ls-tree -r -l`), não copiadas do corpo de cada PR: abertos em paralelo, os sete escreviam
totais que se contradiziam, porque cada um media a árvore com as outras seis pastas ainda dentro.

O `exclude_filter` de uma pasta removida **fica** em `export_presets.cfg`, e
`tests/integration/shipping_export_test.gd` exige-o por preset, pela mesma razão que
`guide_examples/**` e `samples/**` ficaram depois da poda dos demos: um checkout que rebaixe os
addons pela AssetLib recria a pasta em disco, e `.gitignore` protege o commit, não o payload de
export. Não "limpe" isso.

`.gitignore` cobre as sete pelo mesmo motivo — mas **não** as esconde: reaparecendo em disco, a
pasta fica sem linha neste manifesto e `addons_manifest_test.gd` fica vermelho, que é exatamente a
barreira que a ADR-0010 quis comprar. Quem decidir manter uma delas escreve a linha com o estado
novo e faz `git add -f`.

## Como acrescentar um addon

Copie a pasta, acrescente a linha aqui com o estado e o motivo, e rode a suíte. Um addon novo sem
linha falha em `addons_manifest_test.gd` antes de chegar à revisão — que é onde a pergunta "por que
isto está aqui?" custa mais barato de responder.
