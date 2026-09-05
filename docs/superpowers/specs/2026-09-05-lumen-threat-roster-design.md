# Atlas Vivo — elenco menor, diretor de ameaça, entrada, definição e placar

> **Verificado em** 2026-09-05 · commit `cba520a` · macOS, Godot 4.7.2-stable Mono, sessão local
> **Alcance:** design sintetizado a partir de um painel de três propostas independentes e três
> juízes (transcrição em `docs/superpowers/specs/panel/`), reconciliado à mão com o código lido em
> `game/`, `app/`, `ui/`, `tests/` e com `reference/volfied/06-gameplay.md`. Nada aqui foi jogado
> por uma pessoa ainda; os números marcados DESIGN_DECISION são hipóteses a calibrar em playtest.

## 0. Pedido do dono e como esta spec o responde

| Pedido | Onde a spec responde |
|---|---|
| melhor experiência, definição melhor | §7 (stretch `canvas_items`, sprites 3×, palco 2.5D), §8 (feedback) |
| roteiro e estilo mais interessantes | §6 (fases nomeadas, setores, condições de setor), §9 (roteiro) |
| atores dinâmicos e inteligentes, agentes menores com padrões e rastreabilidade | §2 (elenco), §3 (diretor), §4 (rastreabilidade como estado do domínio) |
| referências do Volfied | cada número cita `06-gameplay.md §X`; o que é nosso está marcado |
| situações e variações conforme o território é conquistado | §3.3, §5 |
| orgânico, sem muita linearidade | §3 (gatilhos por comportamento), §5.3 (ramos por habilidade, seeds de expedição) |
| input e ações que testam habilidade | §10 |
| guardrail AAA | §11 (testes, catracas, ADRs), §13 (fases com critério de pronto) |
| abstrações, taxonomia, pureza, encapsulamento em granularidade fina | §1 (taxonomia e decomposição do domínio) |
| placar | §12 |
| artefatos modulares | §1.3, §7.4 |
| 2.5D, física, dinâmica | §7.3 (palco 2.5D e física **só** na apresentação) |
| condições artísticas e conceituais de desafio | §6.3 |

## 1. Taxonomia e decomposição do domínio

### 1.1 Princípio

`GameSimulation` hoje concentra jogador, chefe, captura, escudo, pontuação e checksum num
arquivo de 480 linhas. Cada sistema novo o faria crescer. A decomposição abaixo separa **estado**
(objetos pequenos com `canonical_bytes()`), **regras** (funções estáticas puras, sem estado) e
**orquestração** (`GameSimulation.step` só decide a ordem do tick e a arbitragem). O checksum
passa a ser a concatenação dos bytes canônicos de cada estado, em ordem fixa.

Regra de ouro da refatoração: **a fase 0 não muda comportamento**. Os checksums dourados de
`replay_checksum_golden_test.gd` continuam idênticos até o primeiro bump deliberado — o teste
dourado é a prova de que a reorganização preservou o domínio.

### 1.2 Estrutura de pastas (domínio)

```
game/simulation/
  game_simulation.gd          orquestrador: ordem do tick, arbitragem, eventos, checksum composto
  board/     board_state.gd, flood_fill_capture_resolver.gd, capture_plan.gd, capture_error.gd,
             coordinate_space.gd
  player/    player_state.gd (px, py, pdir, trilha, vértice, stall), player_motion.gd (regras
             estáticas; devolve StepResult), trail_exposure? (não — é apresentação, fica em game/board)
  enemies/   boss_state.gd, boss_motion.gd (regras; hoje em BossBehaviorController),
             minor_actor_pools.gd, walker_rules.gd, dart_rules.gd, ember_rules.gd, beacon_rules.gd
  director/  threat_director.gd (regras estáticas; estado em director_state.gd)
  scoring/   score_ledger.gd (score, permille, fills_done, resto, modo), bonus_ladder.gd
  time/      shield_clock.gd (escudo, crítico, congelamento), effect_timers.gd (itens)
  replay/    replay_log.gd, deterministic_rng.gd, game_event.gd, move_intent.gd
game/rules/            Resources autoráveis: game_rules, threat_profile, boss_behavior_profile,
                       round_definition, round_content, campaign_definition, campaign_branch,
                       round_visual_definition, sector_condition
game/session/          game_session.gd, round_start_state.gd, round_run_record.gd
```

`domain_purity_test.gd` já varre subpastas; `game/enemies/` (apresentação do chefe) passa a
conter só views, e `boss_behavior_controller.gd` migra para `game/simulation/enemies/` para
entrar na guarda. Um `class_name` por arquivo; `preload` por caminho só onde o ciclo de
dependência exigir.

### 1.3 Fronteiras de leitura (encapsulamento)

- Views e HUD leem um **snapshot**: `GameSimulation` mantém propriedades de fachada
  (`px`, `py`, `trail`, `permille`, `score`, `shield_ticks`…) com getters que delegam aos
  estados. Setters existem só para testes de apresentação e são marcados como tal.
- Nenhuma view chama método que mute; `presentation_views_test` prova checksum idêntico antes
  e depois de cada `sync`.
- Cada estado sabe serializar-se (`canonical_bytes()`), validar-se (`assert` de invariantes
  internos) e reiniciar-se (`reset(...)`). Regras recebem estado + board + rules e devolvem um
  resultado inteiro/enum; nunca leem `rng` sem recebê-lo por parâmetro.

## 2. Elenco (vocabulário Lumen Cartography)

Todos vivem **fora** do `BoardState` (invariante 3) em pools `PackedInt32Array` de tamanho
fixo (`MinorActorPools`): `to_byte_array()` é canônico sem ordenação, zero alocação por tick.
Cada ator existe *sobre* um estado territorial, o que o torna legível a 1 px/célula.

| Ator | Vive em | Movimento | Contato letal | Nasce por | Telegraph |
|---|---|---|---|---|---|
| **Núcleo** (chefe) | FREE | 8.8, 16 direções, perfis WANDER/PURSUIT/SWEEP + **fases por permille** | cruz de 5 células × jogador/trilha | `boss_start` | silhueta por fase; anel de fúria |
| **Vagalume** | BOUNDARY **viva** (com vizinho-8 FREE) | 1 célula por `acc_fp += speed_fp` (≤ 192) | mesma célula do jogador | diretor (escada), acampar | rastro de 6 posições (`peek_path` puro) |
| **Dardo** | FREE (projétil) | reta em 16 direções, subpassos ≤ 256 fp | Chebyshev ≤ 1 do jogador; célula TRAIL ⇒ **corte** | Núcleo, por escada/exposição/acampar | 24 ticks parado, linha 1×5 |
| **Brasa** | índice na `trail` | `acc_fp += 384` (1,5 cél/tick vs 2 do jogador) | índice ≥ `trail.size()-1` | corte de dardo; stall a desenhar ≥ 45 ticks | trilha escurece atrás dela |
| **Baliza** | célula fixa do interior | estática | nenhum | `RoundDefinition.beacon_cells` | anel; sólida ao capturar |

Capacidades: 4 vagalumes, 6 dardos, 4 brasas, 16 balizas (§12.3: 22 ranhuras no original; a
1 px/célula, 14 atores já saturam a leitura). Vagalumes/dardos cujas células deixam de ser
válidas após uma captura apagam (`WALKER_EXTINGUISHED` +500 após 60 ticks dormente;
`DART_ABSORBED` imediato): **território conquistado vira escudo e corredor seguro**.

### 2.1 Núcleo — fases e fúria (enxerto da Proposta 2)

`BossBehaviorProfile` v2: `phase_thresholds_permille = [300, 550]`,
`phase_speed_permille = [1000, 1100, 1200]`, `phase_turn_ticks = [45, 36, 30]`,
`phase_pattern = [base, base, escalado]` (Abyssal WANDER→PURSUIT; Aurora jitter 1→3; Verdant
sweep 3→5). A partir da fase 1, se há trilha e o meio dela está a ≤ 48 células, `next_direction`
mira o meio da trilha (o Volfied faz o tiro nascer junto do jogador, §10; aqui o Núcleo caça a
trilha, que é o que dói). **Fúria emergente:** 6 reflexões numa janela de 60 ticks ⇒
`BOSS_CORNERED`, pulso de velocidade por 90 ticks e um dardo. Velocidade efetiva validada
≤ 256/subpasso. `stasis_ticks` (item Estase) pula o passo do Núcleo.

### 2.2 Justiça mecanizada (enxerto da Proposta 2)

- Todo ator nasce em `WARMUP` (vagalume 30, dardo 24 ticks), desenhado e inofensivo.
- Nenhum spawn a menos de 16 células (Manhattan) do jogador, nem no tick de um fechamento.
- `respawn_grace_ticks = 60` após reentrada: atores menores não matam (o Núcleo continua letal —
  §3.3 #1–2 `g_player_hit_enable`).
- Teste de justiça: 600 ticks parado em qualquer rodada ⇒ nenhuma morte por ator; e nenhum
  contato letal de ator antes do fim do seu warmup, em 3 seeds.

## 3. Diretor de ameaça

Regras estáticas em `threat_director.gd`; estado em `DirectorState` (`threat_index`,
`dart_countdown`, `walker_countdown`, `overtime`, `calm_ticks`, `exposure_fired`).

```
time_index   = min(6, tick / 900)          # 15 s por degrau
area_index   = min(6, permille / 125)      # 0..6 até 80 %
overtime_idx = overtime ? 1 + (tick - limit) / 300 : 0
threat_index = clamp(time + area + pressure_bonus + overtime - calm, 0, 15)
```

Escada de 16 entradas em `ThreatProfile` (forma de `enemy_rate_table`, §10):

| idx | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dardo: intervalo | 384 | 336 | 288 | 240 | 192 | 144 | 96 | 72 | 60 | 48 | 40 | 96 | 72 | 48 | 32 | 24 |
| dardo: fp/tick | 85 | 85 | 85 | 85 | 85 | 85 | 85 | 85 | 128 | 256 | 256 | 512 | 512 | 512 | 512 | 512 |
| vagalume: fp/tick | 64 | 64 | 72 | 80 | 88 | 96 | 104 | 112 | 120 | 128 | 136 | 144 | 152 | 160 | 176 | 192 |
| vagalumes máx. | 1 | 1 | 1 | 2 | 2 | 2 | 2 | 3 | 3 | 3 | 3 | 4 | 4 | 4 | 4 | 4 |

Piso 24 e não 3 (§10): vinte dardos por segundo é mangueira, não teste de habilidade. O respiro
no índice 11 (intervalo volta a 96 quando a velocidade dobra) é a forma do original.

### 3.1 Gatilhos

| Gatilho | Condição | Reação | Origem |
|---|---|---|---|
| tempo | `dart_countdown` zera | dardo; recarga `interval[idx]` | §10 |
| tempo | `walker_countdown` zera e `alive < max[idx]` | vagalume | §10 forma |
| território | cada 12,5 % | `area_index` +1 | §10 traduzido |
| território | **cada captura** | `dart_countdown` recarrega ao intervalo cheio | "capturar compra respiro" |
| território | captura ≥ 150 ‰ | `calm_ticks = 300` (índice −1) | §12.5 recompensa fechar grande |
| comportamento | stall a desenhar ≥ 45 | brasa em `trail[0]` | §3.3 #8 |
| comportamento | stall na borda ≥ 240 | `dart_countdown = 0` | §3.3 #8 |
| comportamento | trilha ≥ 68 células (≈ `TrailExposure.WARNING_RATIO`, teste de alinhamento) | `dart_countdown /= 2` uma vez por trilha | aviso do HUD ganha consequência |
| comportamento | 4 capturas seguidas < 15 ‰ | índice +1 (anti-tartaruga) | DESIGN_DECISION |
| tempo | `tick ≥ 5400` (90 s) | `OVERTIME_STARTED`; índice sobe a cada 300 | §10 limite de ronda |
| fúria | 6 reflexões / 60 ticks | `BOSS_CORNERED` + dardo | emergente |

O diretor é o **único** consumidor novo do `rng`, em posição fixa do tick. Nunca aloca por
tick: muta contadores in place e o spawn escreve no pool.

### 3.2 Escada por rodada

`pressure_bonus` por rodada: 0 / 1 / 3. R1 chega ao índice 12 antes do overtime — o primeiro
setor é calibrado para ensinar (fases nomeadas do §6.1 introduzem um ator por capítulo).

### 3.3 O que muda quando o território é conquistado

| Conquista | Consequência mecânica |
|---|---|
| cada 12,5 % | dardos mais frequentes, vagalumes mais rápidos e numerosos |
| cada captura | dardos sobre CLAIMED apagam; vagalumes em fronteira morta apagam em 60 ticks; brasas morrem; recarga do dardo |
| 30 % / 55 % | fases do Núcleo: mais rápido, vira antes, caça a trilha |
| balizas cercadas | itens por ordem de captura (`(baliza + fills_done) % 10`, §11) e cadeia dobrada (§7.3) |
| `free_remaining ≤ 400` no commit | **Núcleo selado** (§12.4: lá 96 medições porque o chefe podia sair; aqui o bolsão não cresce) ⇒ `ROUND_WON{SEALED}` |

## 4. Rastreabilidade

- **Estado, não inferência:** cada slot de ator guarda `cause` (por que nasceu: LADDER, CAMP,
  EXPOSURE, CORNERED, STREAK, CUT, STALL) e `last_reason` (última decisão: KEEP, TURN_HAND,
  REVERSE, DORMANT, ARMED, FIRED…). Entram no checksum — são fatos do domínio.
- **Eventos:** `WALKER_SPAWNED{slot,cause,x,y}`, `DART_ARMED/FIRED/ABSORBED`, `TRAIL_CUT`,
  `EMBER_IGNITED/EXTINGUISHED`, `WALKER_EXTINGUISHED`, `THREAT_LEVEL_CHANGED{index,trigger}`,
  `OVERTIME_STARTED`, `BOSS_PHASE_CHANGED`, `BOSS_CORNERED`, `BEACON_CAPTURED{index,chain,points}`,
  `ITEM_STARTED/ENDED`, `BOSS_SEALED`, `PLAYER_STALLING`. Todos apensados ao fim do enum.
- **Telegraph puro:** `WalkerRules.peek_path(board, slot, n)` é estática e usada pela view para
  desenhar o rastro futuro — o telegraph é igual ao passo real por construção.
- **Overlay de depuração** (`ui/debug/ai_trace_overlay.gd`, F3 / toque longo em pausa): lista
  slots com kind, cause, last_reason, índice do diretor e próximo gatilho, estado da entrada
  (primário, fallback, latch). Só lê snapshot e eventos.

## 5. Não-linearidade

1. **Três razões de fim** (§12.5): `TARGET`, `SINGLE_FILL` (alvo com `fills_done == 1`),
   `SEALED`. Bônus por escada §12.6 ×0,1 (800→1000 … 900→2000, 950→3000, 990→10000,
   999→50000); `SEALED` 10× a base; `SINGLE_FILL` 100×; sem morte na rodada +25 %.
2. **Itens por ordem** e **caça a vagalumes**: o mesmo mapa rende partidas diferentes sem RNG
   extra.
3. **Ramos por habilidade** (enxerto da Proposta 3): `CampaignDefinition.branches:
   Array[CampaignBranch]{from_round_id, condition, to_round_id}` com condições `SEALED`,
   `SINGLE_FILL`, `PERCENT_AT_LEAST(n)`, `NO_DEATH`. `GameSession._tick_clear` avalia sobre o
   `RoundRunRecord` arquivado (função pura do registro; replay por rodada intacto, ADR-0004).
   Setores de ramo: **Umbral Drift** (após `SEALED`/`SINGLE_FILL` em Abyssal Relay) e
   **Ferrous Choir** (≥ 900 ‰ em Aurora Foundry). A campanha canônica continua 3 rodadas; os
   ramos são descobertas, e o placar registra a rota.
4. **Seeds de expedição:** `RoundContent.seed_pool` (4 seeds); o modo Expedição (app) monta a
   campanha com seed alternada. Dourados fixam só a seed canônica.

## 6. Roteiro, fases e condições de setor

### 6.1 Fases nomeadas (HUD, enxerto da Proposta 3)

| Permille | Fase | O que entra |
|---|---|---|
| 0–299 | CALIBRAÇÃO | Núcleo e balizas; escada temporal mínima |
| 300–549 | CORRENTES | Núcleo fase 1; vagalumes na fronteira |
| 550–749 | REAÇÃO | Núcleo fase 2; dardos por exposição |
| 750–799 | COLAPSO | vagalumes 1 passo/tick; pulso do Núcleo ×½; selamento possível |
| ≥ 800 | SETOR ESTABILIZADO | fim |

### 6.2 Setores

| Setor | Perfil | Frase de intro |
|---|---|---|
| Abyssal Relay | WANDER, pressão 0 | "O relé ainda transmite. Estabilize 80 % antes que o escudo apague." |
| Aurora Foundry | PURSUIT, pressão 1 | "A forja se defende: dardos vêm das bordas, vagalumes patrulham a linha." |
| Verdant Singularity | SWEEP, pressão 3 | "O núcleo colapsa. Sele-o — ou saia com 80 % e viva com isso." |
| Umbral Drift (ramo) | SWEEP lento, escalada agressiva, ECLIPSE | "Aqui a luz é sua e acaba com você." |
| Ferrous Choir (ramo) | PURSUIT jitter 3, balizas em corredores, TREMOR | "Seis balizas cantam. Cada corredor é uma aposta." |

### 6.3 Condições de setor (artísticas e conceituais)

`SectorCondition` é um `Resource` **só de apresentação**, referenciado por
`RoundVisualDefinition.condition`, e por isso não toca checksum (invariante 8). Ele muda o que
o jogador **vê**, não o que o domínio calcula — é desafio de percepção, autorável por setor:

- **ECLIPSE:** FREE é escuro além de um raio de luz ao redor do jogador e um halo ao redor do
  Núcleo; balizas capturadas acendem faróis fixos. Raio em células, autorável.
- **TREMOR:** o palco 2.5D treme em pulsos ligados ao índice de ameaça; dificulta ler
  distâncias sem mudar posições.
- **MIRAGEM:** o Núcleo deixa imagens residuais (afterimages) por 12 ticks; o jogador precisa
  distinguir o corpo real (o que pisca com o tick).
- **MARÉ:** o fundo revelado respira (parallax vertical) em ciclo de 600 ticks.

Condições que mudam regras (velocidades, escadas, escudo) **não** são `SectorCondition`: vivem
em `ThreatProfile`/`GameRules` e entram no contrato de replay.

## 7. Definição visual, sprites e palco 2.5D

### 7.1 Stretch

`window/stretch/mode = canvas_items`, `scale_mode = integer`, `aspect = keep`. HUD, overlay,
stick virtual e sprites em resolução nativa; o campo é um `Sprite2D` 225×283 com filtro nearest
em escala inteira (uma célula = um quadrado inteiro). O `board_reveal.gdshader` troca padrões
por `FRAGCOORD` por `UV × mask_size` para que scanline e glint mantenham o período. Validado
por captura (`tools/dev/screenshot_probe.gd --stretch=canvas_items`) antes da troca.

### 7.2 Sprites (rota Codex/ChatGPT, skill `generative-image-assets`)

Autorados a **3× a célula** e desenhados com `scale = 1/3` e filtro linear; o fallback
procedural continua em toda view (a suíte headless não depende de PNG).

| Asset | Tamanho | Frames |
|---|---|---|
| Núcleo por fase (3 setores × 3 fases) | 48×48 | 4 idle + 2 fúria |
| Vagalume | 15×15 | 4 (rotação) |
| Dardo | 15×15 + cauda 24×6 | 2 |
| Brasa | 12×12 | 4 |
| Baliza (dormente/ativa/capturada) | 24×24 | 3 |
| Ícones de item (4) | 18×18 | 1 |
| Emblemas de setor (5) | 64×64 | 1 |
| Fundos Umbral Drift e Ferrous Choir | 225×283 | 1 |
| Jogador (drone cartógrafo) | 24×24 | 4 idle + 2 desenhando |

Proveniência (ferramenta, prompt, exec-id, SHA-256, rubrica) em `assets/ASSET-PROVENANCE.md`.

### 7.3 Palco 2.5D e física na apresentação

`app/stage/depth_stage.gd` (`Node3D`): o `SubViewport` de 240×320 com a apresentação 2D atual
(board, atores, VFX) é aplicado a um quad 3D com câmera ortográfica levemente inclinada
(≤ 8°), `WorldEnvironment` com glow (Compatibility suporta glow desde o 4.3), duas camadas
de parallax atrás (nebulosa gerada) e luz pontual seguindo o jogador. Eventos confirmados
disparam **punch** (captura), **shake** (morte, `BOSS_CORNERED`) e **tilt** (dardo disparado)
por contadores de tick, nunca por relógio. Partículas de captura usam `GPUParticles2D` no
SubViewport (física de apresentação: gravidade e amortecimento nos fragmentos). HUD, transição
e toque ficam num `CanvasLayer` acima, nítidos. Nada disso lê ou escreve a simulação — só
snapshots e eventos (invariantes 6 e 8), e o probe de framebuffer continua testando o pipeline
2D isolado.

### 7.4 Artefatos modulares

- Uma cena por view (`game/board/board_view.tscn`, `game/enemies/actor_view.tscn`,
  `ui/hud.tscn`, `ui/round_transition.tscn`, `ui/scoreboard.tscn`, `app/stage/depth_stage.tscn`);
  `app/bootstrap.tscn` só compõe.
- Sprites em `assets/sprites/<ator>/` com `AtlasTexture` por frame; paletas e condições em
  `content/visuals/`; perfis de ameaça em `content/rules/threat_*.tres`; ramos em
  `content/campaigns/`.
- `tools/build_campaign_content.gd` gera 5 setores, perfis e ramos pela transação v3.

## 8. Feedback por evento

Cues novos (`QixProceduralAudioLibrary`, com `intent`, `priority`, **attack/release em ms
absolutos** — fecha o item de envelopes do ledger): `dart_armed`, `dart_fired`, `trail_cut`,
`ember`, `walker`, `walker_trapped`, `beacon` (+2 semitons por elo), `item`, `threat_up`,
`phase`, `cornered`, `sealed`, `overtime`. Háptica: `trail_cut` 60, `dart_armed` 35,
`beacon` 45, `phase` 35, `cornered` 55 — entre `shield` (50) e `death` (100).

## 9. Roteiro

O jogador é um **cartógrafo de luz** estabilizando as folhas de um atlas que resiste. O Núcleo é
a corrente que apaga o mapa; vagalumes são faróis corrompidos que percorrem as linhas já
traçadas; dardos são a resposta do Núcleo à exposição; brasas são a própria tinta da trilha a
arder quando a mão hesita; balizas são instrumentos de cartógrafos anteriores — estabilizá-las
devolve o que eles deixaram. Cada setor abre com uma frase (§6.2) e fecha com a razão do fim
(ALVO · CORTE ÚNICO · NÚCLEO SELADO) e a escada de bônus rolando (§12.6, apresentação).

## 10. Entrada e habilidade

Tudo no adaptador (`app/`) e no toque (`ui/touch`), exceto o fallback, que é regra de domínio:

- **Latência:** `Input.use_accumulated_input = false` no bootstrap;
  `input_devices/buffering/agile_event_flushing = true` no projeto. Probe
  `tools/profile/input_latency_probe_node.gd` sob `shipping_qa` mede evento → `px` (ticks) e
  evento → `PlayerView.position` (frames); metas p95 ≤ 33 ms, p99 ≤ 50 ms.
- **Latch de toque:** um press visto entre dois ticks conta no tick seguinte (hoje um toque
  < 16,7 ms não existe).
- **SOCD último-pressionado vence** por número de sequência de evento (inteiro; sem relógio).
- **Buffer de curva sem estado no domínio** (enxerto da Proposta 3): `MoveIntent.fallback`
  nos bits 4–6 do byte de replay (bit 7 reservado). O adaptador compõe primário = direção
  tocada nos últimos 6 ticks ainda não consumida (consumida quando `pdir` passa a ser ela),
  senão o vencedor SOCD; fallback = direção mantida ou solta há ≤ 4 ticks. O domínio
  (`PlayerMotion.substep`) devolve `StepResult {BLOCKED, MOVED, CLOSED}` e tenta o fallback
  **só** quando o primário devolve BLOCKED. Replays antigos têm bits 4–6 zerados ⇒ idênticos.
  `ReplayLog.SCHEMA_VERSION` fica 1; a mudança de regra entra no bump de `RULES_VERSION`.
- **Touch:** stick flutuante (centro no toque inicial), histerese de setor (entra 11 px / sai
  7 px; troca de cardinal só além de ±10°), flick = latch de 1 tick.
- **Verbos:** mover e desenhar. A habilidade testada é direção, tempo e leitura.

## 11. Guardrail de qualidade

- **Contrato de replay:** dois bumps deliberados — `RULES_VERSION` 3 (fases 1–2: entrada +
  elenco + diretor + fases do Núcleo) e 4 (fase 3: balizas, itens, razões, escada;
  `DEFINITION_VERSION` 2; `PROFILE_VERSION` 2). Cada bump: ADR + dourados atualizados no mesmo
  commit, com rota dourada por setor de produção (fecha a dívida P2 do ledger).
- **Pureza:** `game/simulation/enemies` na varredura; regra de `float` no domínio
  (`GameSession.transition_progress()` migra para a view).
- **Justiça:** teste de warmup/raio seguro/600 ticks parado (§2.2).
- **Custo do tick:** `tools/profile_simulation_step.gd` com catraca p95 ≤ 300 µs com os pools
  cheios; `simulation_step_budget_test` falha acima disso.
- **Reprodutibilidade:** `random_intent_replay_roundtrip_test` (3 seeds × 5 setores × 1 800
  ticks de intents por `DeterministicRng` de teste → serializa → reproduz → checksum igual).
- **Contraste:** pares `FREE×VAGALUME`, `BOUNDARY×VAGALUME`, `TRAIL×BRASA` no `PAIR_FLOOR` 3:1.
- **Visual:** `tools/dev/screenshot_probe.gd` produz capturas por fase; aprovação humana das
  capturas é registrada em `docs/loop/runs/`.
- **Docs:** cabeçalho de verificação em todo doc tocado; `IMPLEMENTATION_STATUS`,
  `TEST_MATRIX`, `PERFORMANCE`, `ART_DIRECTION`, `PROJECT_CONTRACT` (ownership), `content/README`,
  `LOOP_LEDGER` (backlog reescrito) e ADRs 0010–0014.

## 12. Placar

`app/scoreboard/scoreboard_store.gd` (app, não domínio): `user://scoreboard.json` com até
10 entradas `{initials, score, sectors_cleared, route, reason_of_end, seed_mode, date}` e o
melhor por setor. `ui/scoreboard_view.gd`: entrada de iniciais (3 letras; cima/baixo troca a
letra, esquerda/direita a posição, confirmar fecha; no toque, o stick faz o mesmo) ao fim de
campanha ou game over quando o score entra no top 10; a tela de placar abre no início (antes
da intro do setor 1) por 5 s ou até confirmar. O HUD mostra `HI` com o melhor score. O
arquivo é escrito por transação simples (temp + rename). Nada disso entra na simulação.

## 13. Fases de entrega e critério de pronto

| Fase | Entregáveis | Pronto quando |
|---|---|---|
| **F0 — taxonomia e guardrail** (sem bump) | decomposição do §1, `game/simulation/enemies` na pureza, regra de float, `transition_progress` na view, dourados R2/R3, `profile_simulation_step`, round-trip aleatório | suíte verde, **dourados idênticos**, p95 medido |
| **F1 — entrada** (bump 3, junto com F2) | latch, SOCD, fallback bits 4–6, `StepResult`, touch, `use_accumulated_input`, probe de latência, ADR-0010 | testes do adaptador e do fallback verdes; probe roda |
| **F2 — elenco e diretor** (bump 3) | pools, vagalume/dardo/brasa, `ThreatProfile`, diretor, fases e fúria do Núcleo, justiça, eventos, checksum, actor view procedural, cues, ADR-0011 | rota humana sem morte por setor, teste de justiça, dourados novos, p95 ≤ 300 µs |
| **F3 — balizas, itens, razões, escada** (bump 4) | `DEFINITION_VERSION` 2, itens e timers, escudo com piso, razões, escada de bônus, `SEALED`, transição rolando a escada, ADR-0012 | testes de itens/razões, conteúdo regenerado pela transação |
| **F4 — definição e palco** | `canvas_items`, shader por UV, sprites gerados e aprovados, actor/telegraph views com sprites, HUD (fases, ameaça, itens, HI), overlay de rastreio, palco 2.5D, condições de setor, ADR-0013 | capturas aprovadas em `docs/loop/runs/`, framebuffer probe verde, contraste verde |
| **F5 — atlas e placar** | ramos, 2 setores novos (fundos, perfis, balizas), seeds de expedição, placar, `build_campaign_content` com 5 setores, ADR-0014 | rota automatizada por ramo, transação 100 % committed, placar persiste e reabre |
| **F6 — evidência** | docs, matriz, status, performance, ledger, shipping QA local | `run_shipping_qa.sh` verde; matriz reflete o que foi e o que não foi exercitado |

Sem olho humano na tela, cada fase é **medida**, não aprovada. As capturas da sonda visual são
a evidência mínima; o playtest humano é o gate final e fica listado como pendente na matriz.
