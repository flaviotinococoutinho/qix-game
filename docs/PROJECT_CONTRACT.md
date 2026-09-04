# PROJECT_CONTRACT — QIX GAME (vertical slice)

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
| `antipixel_state_machine/` | máquina de estados de vendor na raiz (3 cenas, 7 scripts) | mantido por ora; nenhum arquivo do jogo o referencia — decisão pendente no loop |

Os dois removidos eram demos: nenhum arquivo de `game/`, `ui/`, `app/`, `tools/`, `tests/` ou
`content/` os referenciava, e os cinco `uid://` que compartilhavam com `addons/` são **de posse dos
addons** — a dependência apontava dos demos para o addon, nunca ao contrário. Custavam 38 das 43
cenas do repositório e um `class_name` de vendor (`LaserProjectile`) no namespace global.

Os `exclude_filter` de `export_presets.cfg` continuam listando `guide_examples/**` e `samples/**`,
e `tests/integration/shipping_export_test.gd` continua exigindo isso. É defesa deliberada: um
checkout que rebaixe os addons pela AssetLib recria as pastas em disco, e o filtro garante que elas
não entrem no payload mesmo assim. Filtro e `.gitignore` cobrem caminhos diferentes do mesmo risco.

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

## Comandos reais

```bash
G=/Applications/Godot_mono.app/Contents/MacOS/Godot
cd /Users/flaviocoutinho/development/qiqix/qix-game

$G --headless --path . --import            # obrigatório 1× por checkout (cache de class_name)
$G --headless --audio-driver Dummy --path . --script res://tests/run_tests.gd # testes puros + integração
$G --headless --path . --script res://tools/build_campaign_content.gd          # baseline transacional
$G --headless --path . --script res://tools/profile_board_view.gd              # perfil CPU/R8
tools/shipping/run_shipping_qa.sh                                               # exports + probes
$G --path . --editor                       # abre o editor (liga godot-ai e fennara)
$G --path .                                # roda a cena principal
```

## Ferramentas MCP observadas na sessão

| Servidor | Versão | Estado no G1 |
|---|---|---|
| `godot-ai` | 3.2.4 | conectado ao editor; runtime, input, inspeção e logs exercitados |
| `fennara` | 0.4.2 | conectado ao editor; diagnósticos direcionados e validação de cena exercitados |
| `github` | remoto | não usado |

Skill `godot-engineering`: **não instalada** nesta máquina. Fallback: diretrizes dos addons e documentação oficial do Godot 4.7.

## Referências ausentes

Os ZIPs de clones citados no prompt (`01-xiq`, `02-quix`, `04..13`) e o manual de Qix para Game Boy **não existem** nesta máquina. Não há adaptação de código de terceiros; `CODE_PROVENANCE.md` só será criado se isso mudar.
