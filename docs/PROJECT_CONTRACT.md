# PROJECT_CONTRACT — QIX GAME / Atlas Vivo

> **Verificado em** 2026-09-08 · commit `6d23de4` · integração local de `3c9724f` (#78) em andamento
> **Alcance:** leitura de `project.godot`, arquivos de ownership, presets, plugin e grafo Git.
> Este texto descreve o contrato combinado do Atlas Vivo e das mudanças remotas preservadas.
> Suíte, renderer, exports e publicação da composição final estão **PENDENTES** nesta edição.
> Os resultados anteriores pertencem às respectivas árvores; ver o [relato de integração](loop/runs/2026-09-08T-mcp-github-integration.md).

QIX GAME é o codinome de um jogo territorial original com gramática de Qix, desafios inspirados
em Volfied e identidade própria Lumen Cartography. Atlas Vivo é a evolução local com atores,
objetivos e palco 2.5D, definida na [ADR-0014](decisions/ADR-0014-atlas-lifecycle-depth-stage.md).
O estado de produto, a autoria e os próximos marcos estão em [ATLAS_VIVO.md](ATLAS_VIVO.md).
Paridade integral com Volfied e produção AAA permanecem objetivos de desenvolvimento.

## Engine e stack

| Item | Contrato atual | Fonte |
|---|---|---|
| Engine | Godot **4.7.2-stable**; executável macOS local `/Applications/Godot_mono.app/Contents/MacOS/Godot` | política do projeto; versão executável precisa ser conferida em cada ambiente |
| Linguagem | GDScript tipado; o projeto não usa C# | ADR-0003 e scripts do projeto |
| Simulação | domínio 2D em células, 60 ticks/s, inteiros e ponto fixo 8.8 | `game/simulation/game_simulation.gd`, `project.godot` |
| Apresentação | palco 2.5D com câmera ortográfica e seis modelos GLB originais; fallback plano | `app/stage/depth_stage.gd`, ADR-0014 |
| Renderer | GL Compatibility | `project.godot`, ADR-0002 |
| Espaço lógico | 240×320 retrato; janela usa `canvas_items`, escala inteira | `project.godot` |
| Campo de produção | 225×283 células com moldura; interior 223×281 | `RoundDefinition` e conteúdo de produção |
| Camada tática | SubViewport 720×960; máscara territorial R8; HUD e touch fora do plano 3D | `QixDepthStage`, `BoardView`, ADR-0014 |
| Replay | `RULES_VERSION = 4`, formato de log `SCHEMA_VERSION = 1` | `GameRules`, `ReplayLog` |

A dimensão de uma malha e a projeção da câmera são valores de apresentação. A posição de contato,
a trilha, a captura e a letalidade continuam decididas pelo domínio. Trocar F2, F3 ou F4, escalar
um modelo ou mudar a paleta não pode alterar checksum nem consumir RNG de simulação.

## Alvos e evidência

| Alvo | Estado e limite |
|---|---|
| macOS arm64 | build Atlas local de QA e evidências anteriores em `build/modernization/`; export da composição final pendente |
| Android retrato | alvo mantido; QA histórica da versão 2D está em SHIPPING_PASS; novo palco requer export/perfil e aparelho físico |
| Teclado | adaptador e rota de campanha presentes; confirmação da composição final pendente |
| Gamepad | D-pad/stick, dedup e desconexão têm provas sintéticas; experiência em dispositivo físico continua pendente |
| Multitouch | floating stick, histerese e concorrência têm provas sintéticas; calibração física continua pendente |
| Distribuição | assinatura de distribuição, notarização, AAB/loja e publicação comercial pendentes |

[SHIPPING_PASS.md](SHIPPING_PASS.md) conserva o candidato automatizado de 2026-09-03, com
identidade de runner, tamanhos e limites próprios. [ATLAS_VIVO.md](ATLAS_VIVO.md) conserva as
medidas da evolução local anterior à integração. Nenhum desses resultados certifica sozinho
a árvore combinada, um aparelho diferente ou a qualidade percebida por uma pessoa.

## Raízes e dependências

- Projeto: `/Users/flaviocoutinho/development/qiqix/qix-game`. É um repositório Git válido;
  a referência histórica a `.git` incompleto não descreve a inspeção de 2026-09-08.
- Referência de estudo: `/Users/flaviocoutinho/development/qiqix`, fora da raiz do jogo.
  Este trabalho não modifica ROMs nem incorpora seus bytes ao produto.
- Recursos, caches, logs e exports locais não substituem evidência ligada a um commit/árvore.
  O relato de integração identifica a branch, os commits preservados e o snapshot das PRs.

Código de terceiros fica sob `addons/` e tem estado declarado em
[addons/README.md](../addons/README.md). Os projetos de exemplo `guide_examples/`, `samples/`
e `antipixel_state_machine/` foram removidos do versionamento por decisões anteriores.
Seus filtros de export e regras de ignore permanecem: reinstalar um vendor pode recriar uma
pasta local sem torná-la conteúdo do jogo.

As sete remoções de `curved_lines_2d`, `phantom_camera`, `guide`, `GDDraw`, `yard`, `softbody2d`
e `curve2collision` chegam juntas pelo #78, com os relatos de posse das PRs #60/#62/#63/#64/#66/#72/#73.
A decisão é a ADR-0010; a publicação dessa integração em `main` ainda está pendente.
Contagens anteriores de cenas/classes foram medidas em árvores diferentes e não são copiadas
como inventário atual. O manifesto e sua guarda derivam o estado do disco.

## Ownership

| Camada | Proprietário e caminho | Regra |
|---|---|---|
| Território | `BoardState`, `game/simulation/board/` | única autoridade sobre células `FREE/BOUNDARY/TRAIL/CLAIMED`; `PackedByteArray` |
| Captura | `FloodFillCaptureResolver`, `CapturePlan`, `CaptureError`, em `game/simulation/board/` | resolução pura; plano confirmado é aplicado por BoardState |
| Tick | `GameSimulation.step(intent)` | avança exatamente um tick; ordem normativa no cabeçalho do arquivo |
| Jogador | `PlayerState` e `PlayerMotion`, `game/simulation/player/` | posição, trilha e movimento em grade; sem consulta ao dispositivo |
| Chefe | `BossState`, `BossMotion`, `BossBehaviorController`, `game/simulation/enemies/` | fases, direção e velocidade determinísticas; controller já está dentro da guarda de domínio |
| Atores menores | `ActorLifecycle`, `MinorActorPools`, `WalkerRules`, `DartRules`, `EmberRules`, `game/simulation/enemies/` | IDs por spawn, capacidades e lifecycle; pools limitados; warmup/dormência sem contato letal |
| Diretor | `DirectorState` e `ThreatDirector`, `game/simulation/director/` | agenda determinística, graça de respawn, pressão e limites autoráveis |
| Objetivos | `BeaconState` e `BeaconRules`, `game/simulation/objectives/` | coleta apenas após CLAIMED confirmado; cadeia e item em ordem autoral |
| Relógios | `ShieldClock` e `EffectTimers`, `game/simulation/time/` | contadores inteiros; consumo conforme tick, sem relógio de parede |
| Pontuação | `ScoreLedger` e `BonusLadder`, `game/simulation/scoring/` | economia e encerramentos; BonusLadder é Resource autorável incluído no hash de GameRules |
| Entrada lógica, eventos e replay | `MoveIntent`, `GameEvent`, `DeterministicRng`, `ReplayLog`, `game/simulation/replay/` | xorshift32 com seed explícita; eventos confirmados; compatibilidade antes de reproduzir |
| Regras | `GameRules`, `BossBehaviorProfile`, `ThreatProfile`, `ItemProfile`, `game/rules/` | Resources autoráveis e imutáveis em runtime; bytes canônicos compõem o config_hash |
| Campanha | `CampaignDefinition`, `RoundContent`, `RoundDefinition`, `game/rules/` | ordem, geometria, seed, transições e referências de conteúdo |
| Sessão | `GameSession`, `game/session/` | uma simulação e um replay por rodada; arquiva apenas tentativas encerradas |
| Visual autorável | `RoundVisualDefinition`, `game/rules/` | paleta, fundo e escala de modelos; sem canonical_bytes e fora do tick/hash |
| Palco e views | `QixDepthStage`, `BoardView`, player/boss/minor views, HUD, transição e VFX | observam snapshots/eventos; não mutam domínio; proxies 3D sem colisores |
| Risco apresentado | `TrailExposure`, `game/board/` | traduz trilha confirmada em leitura visual/sonora/háptica; não volta ao domínio |
| Composição | `app/bootstrap.gd` | dirige sessão, injeta conteúdo e conecta adaptadores/apresentação |
| Dispositivos | `GameInputAdapter`, `QixTouchControls` | estado cru, histerese e dedup; entregam MoveIntent ao domínio |
| Feedback | `QixFeedbackHub`, áudio e háptica | efeitos de eventos já confirmados; pausa e redução de movimento não alteram regras |
| Conteúdo gerado | `CampaignContentTransaction` | validação, journal/WAL, lock, promoção, rollback e recovery; fonte em `tools/build_campaign_content.gd` |

`RoundVisualDefinition` e a costura `RoundContent` são exceções declaradas à presença de tipos
visuais em `game/rules/`. Isso não isenta a pasta inteira: a guarda específica verifica que o
visual não tem serializador canônico nem é nomeado pelo domínio. O inventário de serializadores
acompanha os Resources reais de configuração, sem proibir novos perfis por uma contagem fixa.

Na vitória, a sessão arquiva e congela o checksum. A dissipação posterior do Núcleo pertence à
transição visual; não se continua avançando a simulação arquivada para terminar uma animação.
Os contratos de lifecycle, IDs, limite de pools e alterações deliberadas de replay estão na ADR-0014.

## Ferramentas de editor e MCP

| Componente | Estado observado nesta integração | Limite da afirmação |
|---|---|---|
| `godot_ai` | plugin local **4.0.2**, habilitado; atualização preservada em `6d23de4` | `plugin.cfg` e código presentes não provam todas as ferramentas em runtime |
| `fennara` | extensão e helper presentes; integração existente preservada | conexão ao editor e QA nativa dependem de execução no ambiente alvo |
| GitHub | 32 PRs auditadas por `gh` e refs locais; inventário por SHA no relato | leitura e autorização não equivalem a merge realizado nem aprovação independente |
| Blender MCP | biblioteca original e recibos da produção Atlas preservados | evidência datada em ATLAS_VIVO e no manifesto de modelos |

Os autoloads `_fennara_game_capture` e `_mcp_game_helper` são ferramental. Domínio e views não
podem depender deles para uma partida. Os presets e hooks de export controlam o payload por
caminho, sem excluir `addons/**` em bloco. A política precisa ser verificada novamente no export
da composição final, sobretudo após atualizar o plugin; smokes antigos não provam o fechamento
transitivo das dependências da versão 4.0.2.

## Comandos reais

```bash
G=/Applications/Godot_mono.app/Contents/MacOS/Godot
cd /Users/flaviocoutinho/development/qiqix/qix-game

$G --headless --path . --import
$G --headless --audio-driver Dummy --path . --script res://tests/run_tests.gd
$G --headless --path . --script res://tools/verify_m2_capture_route.gd
$G --headless --path . --script res://tools/profile_simulation_step.gd
$G --headless --path . --script res://tools/profile_board_view.gd
$G --headless --path . --script res://tools/build_campaign_content.gd
$G --path . --script res://tools/dev/verify_depth_stage.gd
bash tools/shipping/build_atlas_macos_local.sh
tools/shipping/run_shipping_qa.sh
$G --path . --editor
$G --path .
```

Importar antes da descoberta de classes. Registrar saída completa e inspecionar erros, mesmo
quando o processo devolve zero. O gerador de conteúdo modifica Resources versionados; executar
quando a fonte autoral mudou, preservando seu journal. O probe de palco exige renderer real.

M2 é uma fixture de isolamento territorial, com chefe, diretor e itens explicitamente isolados.
Ela protege a captura; não demonstra dificuldade ou conclusão da campanha. A rota de campanha
ativa, incluindo os quatro itens e replay de cada rodada, está em
`tests/integration/boss_active_campaign_playthrough_test.gd`.

## Portão automático e limites

`.github/workflows/verificacao.yml` usa Godot 4.7.2-stable no Linux e o wrapper
`tools/ci/headless_gate.py`. O wrapper conserva logs, verifica exit code e diagnósticos, importa,
executa a suíte, a rota M2 e a geometria real do HUD. Testes Python do próprio gate e verificação
de sintaxe dos scripts do loop também fazem parte do workflow.

O passo adicional do #83 verifica bytecode no **índice Git**; deve acompanhar a regra de ignore
e a guarda textual. Seu porte para a composição final está registrado no relato da integração.
O CI do evento `pull_request` avalia a composição com a base, não soma resultados de branches
isoladas. Revisão da mesma conta autora não produz aprovação independente no GitHub.

Isolar a extensão nativa de editor Fennara ausente exige a opção explícita do wrapper e um
checkout apropriado. Essa modalidade não valida extensão nativa, GPU, áudio físico, Android,
assinatura ou publicação. Para performance e distribuição, consultar
[PERFORMANCE.md](PERFORMANCE.md) e [SHIPPING_PASS.md](SHIPPING_PASS.md).

## Proveniência e histórico do contrato

Nenhum byte extraído de ROM pode entrar no jogo. Fontes de referência e limites de uso estão em
[reference/volfied/README.md](../reference/volfied/README.md); cada asset tem origem em
[ASSET-PROVENANCE.md](../assets/ASSET-PROVENANCE.md). Biblioteca Blender, fonte e manifest de GLBs
preservam a reprodução dos modelos originais.

O contrato anterior registrava medições de G0/G1 e shipping de 2026-09-03; poda de raízes em
`cba520a`; sete remoções e verificação de Resources visuais em branches remotas de setembro/07.
Esses textos permanecem nos commits e nos relatos individuais. A reconciliação de setembro/08
removeu contagens concorrentes e afirmações antigas de Git inválido, viewport plano e plugin
3.2.4 do contrato corrente, sem transformar resultados históricos em validação do Atlas combinado.
