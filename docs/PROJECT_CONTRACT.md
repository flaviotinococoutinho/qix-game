# PROJECT_CONTRACT — QIX GAME (vertical slice)

> **Verificado em** 2026-09-06 · commit `34634d0` · Godot 4.7.2-stable, Linux headless
> **Alcance:** § Addons remedida nesta data pela remoção de `phantom_camera` (ADR-0010) —
> `uid://`, `class_name` e contagem de cenas conferidos por `git grep` e `git ls-files` antes da
> remoção, e os totais recontados depois. § Raízes foi remedida em 2026-09-05 e **não** foi
> reverificada aqui. Engine, viewport, renderer e tick seguem conferidos em `project.godot`; a
> tabela de ownership, por existência de arquivo. Alvos, tamanhos de export e estado do
> ferramental MCP seguem do run macOS de 2026-09-03 e **não** foram reexecutados.

Registrado no G0 e atualizado no shipping pass em 2026-09-03. Codinome interno; título público ainda não definido.

## Engine e stack

| Item | Valor | Como foi verificado |
|---|---|---|
| Executável | `/Applications/Godot_mono.app/Contents/MacOS/Godot` | `--version` → `4.7.2.stable.mono.official.ed1daf0bf` |
| Versão | **4.7.2-stable** (build mono; o projeto não usa C#) | idem; bate com `engine_policy` do prompt |
| Linguagem | **GDScript tipado** | ADR-0003 |
| Mundo | 2D nativo | perfil padrão do prompt |
| Renderer | **GL Compatibility** | ADR-0002 |
| Simulação | 60 ticks/s, tick fixo, inteiros | `physics/common/physics_ticks_per_second=60` persistido; `QixBootstrap._physics_process` chama um `GameSession.step` por tick não pausado |
| Viewport lógico | 240×320 retrato, `stretch=viewport`, `scale_mode=integer`, `aspect=keep` | `project.godot` |
| Campo histórico | 225×283 incl. moldura; interior 223×281 = 62 663 células | `06-gameplay.md` §4.4 |

## Alvos

| Alvo | Estado |
|---|---|
| macOS desktop (arm64) | candidate QA de 101.199.872 bytes; payload, smoke, áudio 900/900 ticks, frame/Metal, framebuffer, `codesign` e leak scan verdes; assinatura de distribuição/notarização pendentes |
| Android retrato | candidate QA de 40.486.376 bytes assinado ad-hoc; runner iniciou `emulator-5554`, instalou e validou main loop +30 s; aparelho físico, AAB e loja pendentes |
| Teclado | disponível |
| Gamepad | tradução D-pad/stick/botões, estado por device, disconnect e dedup Start/A validados sinteticamente; físico **NOT_EXERCISED** |
| Multitouch | overlay e concorrência de dedos validados sinteticamente; físico **NOT_EXERCISED** |

## Raízes

- `project_root`: `/Users/flaviocoutinho/development/qiqix/qix-game` (projeto novo; o `.git/` encontrado está incompleto e ainda não forma um repositório válido)
- `reference_root`: `/Users/flaviocoutinho/development/qiqix` (`docs/00..08`, `docs/ACHADOS_ANOTACAO.md`, `reference/mame/`)
- Não há `project.godot` nem `.git` em `reference_root`; nada ali é modificado por este projeto.

### Raízes de terceiros

A raiz do repositório hospeda diretórios que **não são do jogo**. A regra é: código de vendor que
o runtime carrega fica versionado; material de estudo que só acompanha o vendor, não.

| Diretório | O que é | Decisão |
|---|---|---|
| `addons/` | código de vendor; parte do runtime ou do ferramental de editor | versionado; inventário por addon é item aberto do loop |
| `guide_examples/` | projeto-exemplo do addon GUIDE (32 cenas, 55 scripts) | **removido** do versionamento; ignorado |
| `samples/` | projeto-exemplo do addon softbody2d (6 cenas, 6 scripts) | **removido** do versionamento; ignorado |
| `antipixel_state_machine/` | máquina de estados de vendor na raiz (3 cenas, 7 scripts) | **removido** do versionamento; ignorado |

`guide_examples/` e `samples/` eram demos: nenhum arquivo de `game/`, `ui/`, `app/`, `tools/`,
`tests/` ou `content/` os referenciava, e os cinco `uid://` que compartilhavam com `addons/` são
**de posse dos addons** — a dependência apontava dos demos para o addon, nunca ao contrário.
Custavam 38 das 43 cenas do repositório e um `class_name` de vendor (`LaserProjectile`) no
namespace global.

`antipixel_state_machine/` não era demo de addon nenhum, e por isso ficou de fora daquela poda:
podia ser dependência real adormecida. Não era, e a medição de 2026-09-05 mostra por quê — quatro
fatos independentes:

1. **Sem consumidor.** Nenhum arquivo de `game/`, `ui/`, `app/`, `tools/`, `tests/` ou `content/`
   citava o caminho, e nenhum dos **12 `uid://`** declarados dentro da pasta aparecia fora dela.
   A posse era toda interna: só as próprias cenas de amostra consumiam os próprios scripts.
2. **Nunca foi instalada.** As cenas de amostra e os três `@icon` apontam para
   `res://addons/antipixel_state_machine/…` — caminho que **não existe** no repositório. A pasta
   foi extraída na raiz em vez de em `addons/`; os `@icon`, que são string literal sem `uid://`,
   ficavam quebrados desde o commit inicial.
3. **Não era addon.** Sem `plugin.cfg` e ausente de `editor_plugins` em `project.godot`: era uma
   biblioteca de scripts solta, não um plugin que o editor pudesse habilitar.
4. **O domínio não poderia consumi-la.** É `extends Node` de ponta a ponta, e o invariante 1
   proíbe `Node`, `Tween` e física em `game/simulation/`, `game/rules/` e `game/session/`. Como
   máquina de estados do domínio ela estava descartada por contrato, não por preferência.

O custo era maior que os 132 KB: cinco `class_name` genéricos — `State`, `StateMachine`,
`StateComponent`, `NodeState`, `PackedSceneState` — ocupando o namespace global do projeto, que já
hospeda `BoardState` e `RoundStartState`. O nome mais óbvio para um tipo de domínio futuro estava
tomado por vendor que ninguém chamava.

Os `exclude_filter` de `export_presets.cfg` continuam listando `guide_examples/**`, `samples/**` e
`antipixel_state_machine/**`, e `tests/integration/shipping_export_test.gd` exige os três. É defesa
deliberada: um checkout que rebaixe os addons pela AssetLib recria as pastas em disco, e o filtro
garante que elas não entrem no payload mesmo assim. Filtro e `.gitignore` cobrem caminhos
diferentes do mesmo risco.

## Ownership

| Camada | Proprietário | Regra |
|---|---|---|
| Território | `BoardState` (`game/simulation/board_state.gd`) | única autoridade; `PackedByteArray`; estados `FREE/BOUNDARY/TRAIL/CLAIMED` |
| Regras | `GameRules` (`game/rules/game_rules.gd`) | `Resource` imutável em runtime |
| Campanha | `CampaignDefinition` + `RoundContent` | ordem, transições e referências autoráveis; uma simulação/replay por rodada |
| Tick | `GameSimulation.step(intent)` | sem `delta`; ordem fixa documentada no arquivo |
| Captura | `FloodFillCaptureResolver` | puro; devolve `CapturePlan` ou `CaptureError`; não muta nada |
| Acaso | `DeterministicRng` | xorshift32 com seed explícita; único ponto de aleatoriedade |
| Apresentação | `BoardView`, `PlayerView`, `EnemyView`, HUD, transição e VFX | observa snapshots/eventos confirmados; não muta a simulação |
| Leitura de risco | `TrailExposure` (`game/board/trail_exposure.gd`) | funções puras de apresentação; traduzem o comprimento da trilha confirmada num escalar 0..1 consumido por `BoardView` e pelo HUD; nenhum valor volta ao domínio nem entra em hash |
| Revelação | `BoardView` + shader R8 | `BoardState.cells` alimenta a máscara; somente `CLAIMED` revela o fundo |
| Composição | `app/bootstrap.gd` | composition root; injeta campanha e dirige a sessão |
| Entrada de dispositivo | `GameInputAdapter` + `QixTouchControls` | estado cru por gamepad, dedup InputMap/evento, teclado/touch agregados; entrega somente `MoveIntent` ao domínio |
| Feedback | `QixFeedbackHub` | observa sessão/eventos confirmados e aciona áudio/háptica sem mutar domínio |
| Boss | `BossBehaviorProfile` + `BossBehaviorController` | Resource autorável; direção/velocidade determinísticas e parte do contrato de replay |
| Geração de conteúdo | `CampaignContentTransaction` | WAL v3 persistente, lock loopback interprocessual, digests/tamanhos, manifest ancorado, máquina de estados, promoção adjacente, rollback e recovery fail-closed |

Autoloads presentes: `_fennara_game_capture` e `_mcp_game_helper` são **ferramental MCP**, não
são consumidos pelo domínio nem pelas views. Os presets fazem exclusões seletivas, não removem
`addons/**` em bloco. O export hook retirou o autoload e os dez scripts de runtime Fennara, e o
verificador confirmou também a ausência de `addons/fennara/bin/`; já o fechamento necessário do
helper Godot AI permaneceu completo, com cinco dependências presentes. Os smokes macOS/Android do
runner `20260903T065739Z-65912` provaram que esse payload inicia sem referência quebrada. Para
distribuição real, a presença do helper Godot AI deve ser uma decisão explícita: removê-lo por
completo ou mantê-lo junto de todo o fechamento necessário.

## Addons — quem é jogo, quem é ferramenta

Inventário verificado em **2026-09-04** contra o checkout de `main` em `74c173a`; a linha de
`phantom_camera` foi atualizada em **2026-09-06** pela remoção que a ADR-0010 decidiu. Existe
porque as pastas em `addons/` não dizem, por si, quais participam do jogo: sem esta tabela, cada
leitor refaz a mesma investigação e alguns concluem errado.

| Addon | Versão | Habilitado em `[editor_plugins]` | Consumido pelo jogo | Destino no export |
|---|---|---|---|---|
| `godot_ai` | 3.2.4 | **sim** (único) | autoload `_mcp_game_helper` | `runtime/` embarca; `clients/`, `custom_tools/`, `debugger/`, `dock_panels/`, `export/`, `handlers/`, `testing/` excluídos |
| `fennara` | 0.4.2 | não é plugin de editor — é `GDExtension` com bibliotecas `*.editor.*` | autoload `_fennara_game_capture` | `runtime/` embarca; `ai/`, `bin/`, `dist/` e o `.gdextension` excluídos |
| `guide` (G.U.I.D.E) | 0.14.0 | não | **nenhum** | excluído em bloco |
| `curved_lines_2d` (Scalable Vector Shapes 2D) | 2.33.3 | não | **nenhum** | excluído em bloco |
| ~~`phantom_camera`~~ | 0.11.0.3 | não | **nenhum** | **removido** do versionamento em 2026-09-06 (ADR-0010); filtro mantido |
| `GDDraw` | 0.2.0 | não | **nenhum** | excluído em bloco |
| `softbody2d` | 1.7.1 | não | **nenhum** | excluído em bloco |
| `curve2collision` | 1.0.0 | não | **nenhum** | excluído em bloco |
| `yard` | 1.2.0 | não | **nenhum** | excluído em bloco |

Como "nenhum" foi verificado — dois testes independentes sobre `app/`, `game/`, `ui/`, `tools/`,
`tests/`, `content/` e `assets/`:

1. Nenhuma dessas árvores contém a string `res://addons/`.
2. Dos `class_name` declarados pelos addons, **nenhum** aparece como palavra nessas árvores. A
   entrada do jogo é `GameInputAdapter` sobre o `InputMap` de `project.godot`, não o G.U.I.D.E.;
   a câmera era fixa em 240×320 mesmo quando `phantom_camera` estava em disco — e por isso ela
   saiu. Recontagem de 2026-09-06 por `git grep -h -E '^class_name ' -- addons | awk '{print $2}'
   | sort -u`: eram **176** em `34634d0` e são **165** depois da saída dos 11 de
   `phantom_camera`. O **174** que esta linha registrava desde 2026-09-04 nunca conferiu com este
   método; a divergência de 2 é anterior a qualquer remoção e fica registrada aqui em vez de ser
   apagada em silêncio — quem quiser fechar a conta precisa dizer qual método usou.

Nenhuma pasta de terceiros vive mais **fora** de `addons/`. As três que viviam — `samples/`
(demos do `softbody2d`), `guide_examples/` (demos do `guide`) e `antipixel_state_machine/` —
foram removidas do versionamento, a última em 2026-09-05.

Consequência prática para quem lê o repositório: das **73** cenas do checkout, **2** são do jogo
— `app/bootstrap.tscn` e `ui/touch/touch_controls.tscn` — e as outras **71** são de terceiros,
todas em `addons/`. Isso vale como regra de leitura, não só como contagem: **um `.tscn` fora de
`addons/` é do jogo.** Antes da poda eram 2 em 145, espalhadas por quatro raízes, e procurar uma
cena do jogo pelo nome devolvia 98 % de ruído; a saída de `phantom_camera` (30 cenas) baixou o
ruído de 98 % para 97 %, o que diz menos sobre esta remoção do que sobre as seis que faltam.

O que esta tabela **não** decide, addon a addon: qual dos dormentes sai a seguir. A **ADR-0010** já
decidiu que os sete saem, um por PR, com posse de `uid://` medida. Os que restam já não entram no
payload (os `exclude_filter` de ambos os presets em `export_presets.cfg` os listam por nome),
então o custo deles é de leitura e de busca, não de bytes entregues ao jogador.

## Comandos reais

```bash
G=/Applications/Godot_mono.app/Contents/MacOS/Godot
cd /Users/flaviocoutinho/development/qiqix/qix-game

$G --headless --path . --import            # obrigatório 1× por checkout (cache de class_name)
$G --headless --audio-driver Dummy --path . --script res://tests/run_tests.gd # testes puros + integração
$G --headless --path . --script res://tools/build_campaign_content.gd          # baseline transacional
$G --headless --path . --script res://tools/profile_board_view.gd              # perfil CPU/R8
$G --headless --path . --script res://tools/verify_palette_contrast.gd         # contraste por estado
tools/shipping/run_shipping_qa.sh                                               # exports + probes
$G --path . --editor                       # abre o editor (liga godot-ai e fennara)
$G --path .                                # roda a cena principal
```

## O que o portão automático cobre

`.github/workflows/verificacao.yml` roda em todo PR contra `main` (e em todo push a `main`).
Ele baixa o Godot 4.7.2-stable headless, confere a versão, importa e executa:

| Comando | No portão | Por quê |
|---|---|---|
| `--import` | sim | sem ele não há cache de `class_name` e toda falha é falsa |
| `tests/run_tests.gd` | sim | sai com 1 se houver falha — é o que torna o portão capaz de ficar vermelho |
| `tools/verify_m2_capture_route.gd` | sim | protege a rota 17,9 → 82,5%, que nenhum teste unitário cobre inteira |
| `tools/profile_board_view.gd` | não | orçamento de performance depende de GPU real; ver `docs/PERFORMANCE.md` |
| `tools/build_campaign_content.gd` | não | gera conteúdo versionado; rodar no CI mascararia baseline desatualizado |
| `tools/shipping/run_shipping_qa.sh` | não | exige SDKs e assinatura; permanece local (`docs/SHIPPING_PASS.md`) |

O portão roda sobre o **merge do PR com a base**, não sobre o head isolado. Essa distinção é o
ponto: onze PRs verificados um a um contra `main` não viram a regressão que só aparece quando
dois deles coexistem.

## Ferramentas MCP observadas na sessão

| Servidor | Versão | Estado no G1 |
|---|---|---|
| `godot-ai` | 3.2.4 | conectado ao editor; runtime, input, inspeção e logs exercitados |
| `fennara` | 0.4.2 | conectado ao editor; diagnósticos direcionados e validação de cena exercitados |
| `github` | remoto | não usado |

Skill `godot-engineering`: **não instalada** nesta máquina. Fallback: diretrizes dos addons e documentação oficial do Godot 4.7.

## Referências ausentes

Os ZIPs de clones citados no prompt (`01-xiq`, `02-quix`, `04..13`) e o manual de Qix para Game Boy **não existem** nesta máquina. Não há adaptação de código de terceiros; `CODE_PROVENANCE.md` só será criado se isso mudar.
