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
