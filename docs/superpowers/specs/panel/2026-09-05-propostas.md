

############ Atlas Vivo — elenco de agentes, diretor de ameaça e entrada de nível AAA para QIX GAME
# Atlas Vivo — proposta de gameplay, elenco e entrada para QIX GAME

> Lente: **sensação AAA, input e legibilidade**. Tudo abaixo respeita os invariantes 1–10 do `CLAUDE.md`; o que os toca (7 e 9) é tratado como decisão com ADR e bump de versão, não como efeito colateral.

## 1. Visão

Hoje o jogo tem um único ator hostil (`GameSimulation` mantém `bx_fp/by_fp` do chefe) e um único gatilho de tensão (o escudo). O jogador aprende o chefe em uma rodada e a partir daí só existe cronômetro. A proposta transforma cada setor num **atlas vivo**: o Núcleo (chefe) continua sendo a única âncora que protege território (§5.5), mas passa a **emitir agentes menores** — correntes que percorrem a borda, fragmentos que vagam no interior, sondas disparadas com aviso, e o pavio da própria trilha quando o cartógrafo hesita. Um **diretor de ameaça** determinístico decide *quando* cada agente nasce, lendo tick, permille e o comportamento do jogador. Em paralelo, a entrada ganha latch de toque, SOCD "último pressionado vence" e buffer de curva codificado no próprio `MoveIntent`, para que o jogo teste habilidade e não tolerância a input perdido.

Três regras de projeto valem para todo item desta proposta:

1. **Nada hostil chega sem nome.** Todo agente tem telegraph de ≥ 30 ticks antes de ser letal, e o HUD nomeia a fase do setor em que ele aparece.
2. **Toda decisão de IA é um fato confirmado.** Agentes emitem `GameEvent.Kind.AI_DECISION` com código de razão; um overlay de depuração lê isso e nada mais.
3. **Presentação não move checksum.** Sprites, overlay, cues e hápticos são adicionados como observadores de snapshot, e `replay_checksum_golden_test.gd` continua sendo a prova.

## 2. Elenco de inimigos

Os agentes menores vivem num `EnemyRoster` (`game/simulation/enemy_roster.gd`) com **8 slots fixos** e iteração em ordem de slot — ocupação **fora** do `BoardState` (invariante 3). Cada slot é um `EnemyState` (`game/simulation/enemy_state.gd`): `kind, alive, x_fp, y_fp, dir_index, speed_fp, timer, aux, grace_ticks_left, last_reason`. Decisões puras ficam em `MinorAgentController` (`game/enemies/minor_agent_controller.gd`), irmão do `BossBehaviorController` existente. Todo agente nasce com `spawn_grace_ticks = 30` (não letal; tradução do atraso de `g_player_hit_enable`/`g_trail_hit_enable` de §3.3 #1–2) e é desenhado translúcido nesse período.

| Agente | Papel | Movimento | Onde vive | Contato | Spawn | Telegraph | Rastreio |
|---|---|---|---|---|---|---|---|
| **Núcleo** (chefe, existente) | âncora que protege território; emissor dos demais | 8.8, 16 direções, `boss_speed_fp` 96–128/subpasso, perfis WANDER/PURSUIT/SWEEP (ADR-0007) | FREE | cruz de 5 células × jogador ou TRAIL → letal | `boss_start` | pulso de velocidade já visível; **novo**: anel de *windup* de 30 ticks antes de cada sonda | `BOSS_WINDUP_STARTED{target}`, `AI_DECISION{agent:BOSS, reason}` |
| **Brasa** (corrente de borda) | pressão sobre o retorno à borda; anti-tartaruga | 1 célula a cada `ember_step_ticks = 2` (30 cél/s; jogador anda 120) | **BOUNDARY** apenas; grafo de fronteira, que cresce com as capturas | célula da Brasa == célula do jogador → letal; nunca toca TRAIL | pares em `player_spawn`, sentidos opostos, aos 250‰ e por gatilho de *farming* | cauda de cinza de 3 células atrás + brilho de 3 células à frente; zumbido cresce a < 12 células do jogador | `EMBER_TURN_JUNCTION`, `EMBER_REVERSE_DEAD_END`, `EMBER_KEEP_HEADING` |
| **Lampejo** (fragmento) | ocupa espaço; **capturável** — a recompensa em cadeia de §7.3 | 8.8, 8 direções (índices pares da tabela de 16), `flicker_speed_fp = 64`, 2 subpassos, só vira em `tick % 24 == 0` (pisca ao virar) | FREE; reflete como o chefe | célula == jogador ou reflexão em TRAIL → letal; **não** é âncora | o Núcleo "solta" 2 aos 650‰; diretor repõe por rung | piscar de 24 ticks = a única janela em que muda de rumo; linha reta previsível entre piscadas | `FLICKER_BLINK_TURN`, `FLICKER_REFLECT_H/V`, `ENEMY_DIED{cause:CAPTURED}` |
| **Sonda** (projétil) | pune trilha longa; tensão à distância | reta em 16 direções, `shot_speed_fp = 192`, 2 subpassos (1,5 cél/tick), vida 240 ticks | projétil em FREE; morre em BOUNDARY/CLAIMED | TRAIL ou jogador → letal e morre | disparada pelo Núcleo após *windup* de 30 ticks, alvo **travado no início do windup** (é isso que a torna desviável); a partir de 500‰ e por trilha ≥ 96 células | anel crescente no Núcleo + linha pontilhada até o alvo travado, som de carga ascendente | `SHOT_FIRED{slot}`, `AI_DECISION{reason:SHOT_AIM_LOCKED}` |
| **Pavio** (fusível da trilha) | gramática Qix: hesitar custa | 1 célula/tick ao longo de `trail[]` (60 cél/s vs 120 do jogador) | **TRAIL** (índice na trilha, sem célula própria) | `fuse_index >= trail.size()-1` → letal | arma quando `player_stall_ticks >= 20` com trilha ativa (§3.3 #8 tem contador de paralisia; o número é nosso); congela quando o jogador anda, retoma ao parar | 20 ticks de aviso: HUD "PAVIO ACESO", células atrás do pavio viram cinza; *tick-tock* | `FUSE_ARMED`, `FUSE_HALTED`, `FUSE_RESUMED` |
| **Baliza** (objeto fixo) | obstáculo + item (§5.8, §11, §12.3) | estático | bloco 7×7 em `obstacle_mask` (raio 3; §5.8 usa 15×15, grande demais para 225 de largura) | trilha bloqueada (como CLAIMED); chefe/lampejo refletem | `RoundDefinition.beacons` | ícone dormente → "estabilizando" quando a trilha a cerca | `BEACON_STABILIZED{index}`, `ITEM_COLLECTED` |

**Regra de encurralados (§7.3):** logo após cada `_commit_capture`, o roster é varrido; Lampejo ou Sonda cuja célula virou CLAIMED morre e paga `chain_points[k]` = 1 000·2^k (1 000 … 64 000, k = 0..6), com `capture_chain` zerado a cada captura. Essa é a recompensa que faz o jogador *querer* cercar fragmentos em vez de só fugir deles.

## 3. Diretor de ameaça

`ThreatDirector` (`game/simulation/threat_director.gd`), função pura `decide(sim_snapshot, profile, rng) -> Array[Decision]`, corre no passo 4 do tick (antes dos inimigos, como `enemy_spawn_countdown` antes de `enemy_update_all` em §3.3 #10/#12). Parâmetros vêm de `ThreatProfile` (`game/rules/threat_profile.gd`, `THREAT_VERSION = 1`, hashado em `GameRules.canonical_bytes`).

O diretor mantém um **rung** 0..11 — a forma é a escada monótona de `enemy_rate_table` (§10: 16 índices, intervalo 384→3 frames, velocidade 1 passo/3 frames → 2 passos/frame). Por rung: `shot_interval_ticks` = [—,—,—,—,240,210,180,150,120,96,72,48], `flicker_respawn_ticks` = [—,—,—,—,—,900,720,600,480,360,300,240], `max_alive` = [0,0,2,2,3,3,4,4,5,5,6,6].

Gatilhos (todos inteiros, todos emitem `THREAT_RUNG_CHANGED{rung, trigger}`):

- **Por tick:** +1 a cada `director_ladder_interval_ticks = 600` em PLAYING (também durante a trilha — o escudo pausa, a pressão não). Quando `shield_ticks ≤ 25 %` do total: +2 ("o setor destabiliza"; tradução do limite de ronda de §10, que ao expirar acelera os tiros).
- **Por permille:** ao cruzar 250, 500, 650, 750: +1 e `SECTOR_PHASE_CHANGED{phase}` (ver §4).
- **Por comportamento do jogador:**
  - `player_stall_ticks ≥ 20` com trilha → arma o Pavio (não muda rung).
  - trilha ≥ `exposure_shot_trail_px = 96` → o Núcleo inicia windup imediatamente, ignorando o intervalo (a exposição já é visível pelo `TrailExposure`; agora ela tem consequência).
  - 3 capturas seguidas com `filled_delta < 2 %` (`farming_capture_permille = 20`, `farming_streak = 3`) → par de Brasas ("correntes reagem ao cartógrafo tímido").
  - captura ≥ 150‰ num só fechamento → `director_calm_ticks = 300` de rung −1 (respiro; §12.5 razão 3 recompensa o fechamento grande com bônus — aqui a recompensa é tempo).
- **Limites:** `max_minor_enemies = 6` vivos (o original tem 22 ranhuras, §12.3; a 1 px/célula seis já saturam a leitura), rung ≤ 11.

## 4. Variações por território conquistado

| Permille | Fase (HUD) | O que muda |
|---|---|---|
| 0–249 | CALIBRAÇÃO | só Núcleo e Balizas; a rodada ensina o perfil do chefe |
| 250 | CORRENTES | par de Brasas nasce em `player_spawn`; a borda deixa de ser refúgio absoluto |
| 500 | REAÇÃO | Núcleo passa a disparar Sondas (windup 30 ticks) |
| 650 | FRAGMENTAÇÃO | Núcleo solta 2 Lampejos; **escalada de perfil**: `BossBehaviorProfile` v2 ganha `escalate_at_permille = 650`, `escalated_pattern`, `escalated_turn_every_ticks` (Abyssal: WANDER→PURSUIT; Aurora: PURSUIT jitter 1→3; Verdant: SWEEP 3→5 passos) |
| 750 | COLAPSO | Brasas a `ember_step_ticks_collapse = 1`; pulso do chefe encurta (`pulse_period_ticks` × ½); começa a checagem de **envolvimento** |

**Envolvimento (§12.4):** o original exige o pixel sob o chefe conquistado por 96 medições de 8 em 8 frames (768 frames). Aqui o chefe nunca fica sob CLAIMED (é âncora), então a tradução é por região: `plan.free_remaining` — já calculado pelo resolver — ≤ `engulf_region_cells = 626` (1,0 % do interior de 62 663; §12.5 usa 1,0 % como limiar) durante `engulf_hold_ticks = 180` consecutivos → `ROUND_WON{reason: ENGULFED}` com `engulf_bonus = 10 × completion_bonus` (§12.6: 100 000 contra o piso de 10 000). O contador é visível: anel de cerco pulsando ao redor do Núcleo e status "NÚCLEO CERCADO 3…2…1".

## 5. Não-linearidade

- **Campanha em grafo, sessão determinística.** `CampaignDefinition` ganha `branches: Array[CampaignBranch]` (`from_round_id, condition, to_round_id`; condições: `ENGULFED`, `PERCENT_AT_LEAST(n)`, `SINGLE_FILL`, `ALWAYS`). `GameSession._tick_clear` escolhe o primeiro ramo cuja condição o `RoundRunRecord` satisfaz; sem ramo, segue a ordem. A escolha é função pura do registro arquivado — replay por rodada intacto (ADR-0004 preservada).
- **Dois setores de ramo:** *Umbral Drift* (alcançado ao envolver o Núcleo de Abyssal Relay) e *Ferrous Choir* (≥ 900‰ em Aurora Foundry). Campanha canônica continua com 3 rodadas; os ramos são "descobertas".
- **Seeds de expedição:** `RoundContent.seed_pool: PackedInt32Array` (4 seeds autoradas). O modo Expedição, escolhido no app, monta uma `CampaignDefinition` com seed alternada; o cabeçalho do replay já carrega a seed, então nada muda no contrato. Os dourados fixam só a seed canônica.
- **Eventos de setor:** as fases de §4 são gatilhos por permille, não por tempo — duas partidas com rotas diferentes vivem sequências diferentes de agentes com o mesmo conteúdo.

## 6. Itens e efeitos

Balizas estabilizadas (centro dentro do `claimed_indices` de um `CapturePlan`, como `lvl_objects_check_claimed` em §5.8) dão um item pela fórmula de §11: `índice = (beacon_index + (target_permille & 0xF)) mod 10` sobre `beacon_item_table` de 10 entradas, mesma forma da tabela A (`05 02 03 05 05 01 05 01 05 05`) com nossos efeitos:

| Item | Efeito | Duração | Origem |
|---|---|---|---|
| ESTABILIZADOR | escudo não decresce | 480 ticks | §11 padrão 5 |
| ACELERADOR | `substeps_speedup` (4/tick, nunca nos 8 px iniciais) | 600 ticks | §11 padrão 1, §4.3 |
| PARADA | Núcleo congela (agentes menores não) | 240 ticks | §11 padrão 3 |
| PURGA | mata Lampejos/Sondas vivos (paga cadeia) + imunidade a agentes menores | 120 ticks | §11 padrão 4 |
| SELO DE TRAÇO | Sondas atravessam a trilha sem cortá-la (Núcleo ainda corta) | 360 ticks | original — substitui os padrões 2/6 (tiro do jogador), que não cabem na gramática |

`item_ticks: PackedInt32Array(5)` no estado; `speedup_active` passa a ser derivado de `item_ticks[SPEEDUP] > 0`.

## 7. Fim de rodada e bônus

`RoundEndReason { TARGET, ENGULFED, SINGLE_FILL }` no `ROUND_WON` (§12.5). Bônus de área pela escada de §12.6, expressa em décimos de `completion_bonus`: `area_bonus_ladder` = [(800,10),(810,11)…(900,20),(910,22),(920,24),(930,26),(940,28),(950,30),(960,35),(970,40),(980,50),(990,100),(991,110)…(999,500)]. R1 a 80,0 % paga 1 000; a 99,9 % paga 50 000. `SINGLE_FILL` (alvo atingido com `fills_done == 1`) paga 100 × `completion_bonus` (§12.6 razão 3). A tela de resultado **rola a escada** até a percentagem atingida ficar no topo (§12.6, `sub_003864`) — presentação pura em `QixRoundTransitionView`, encenada em ticks como o contador de ADR-0009.

## 8. Input e habilidade

**Diagnóstico atual.** `QixBootstrap._physics_process` chama `GameInputAdapter.sample()` uma vez por tick e `sample_from_state` lê nível (`Input.is_action_pressed`). Um toque de teclado mais curto que 16,7 ms entre dois ticks **não existe** para o jogo; `handle_event` só rastreia joypad. `choose_direction` resolve sobreposição pela direção atual, depois por ordem canônica UP>RIGHT>DOWN>LEFT — não pelo que o jogador acabou de fazer.

**Latch de borda.** `handle_event` passa a registrar `InputEventKey` e `InputEventJoypadButton` das ações de movimento; um press visto entre amostras conta como pressionado na próxima (`TAP_LATCH_TICKS = 1`). Em `_ready`, `Input.use_accumulated_input = false` para que eventos não sejam fundidos dentro do frame (propriedade existente; confirmar comportamento no 4.7.2 com o probe abaixo).

**SOCD "último pressionado vence".** Cada direção guarda o número de sequência do press (contador monotônico de eventos, sem relógio). Primário = maior sequência entre as mantidas. §4.2 mostra o original recusando combinações (código 0); aqui, com stick virtual e teclado, sobreposição é o caso comum e o jogador merece que a intenção mais recente vença.

**Buffer de curva e fallback.** `MoveIntent` ganha `fallback: int` codificado nos **bits 4–6** do byte de replay (bit 7 reservado = 0; `from_byte` decodifica e satura em NONE). Presentação compõe: *primário* = direção tocada nos últimos `TURN_BUFFER_TICKS = 6` ainda não consumida (consumida quando `simulation.pdir` passa a ser ela — `sample(preferred_direction)` já recebe `pdir`), senão o vencedor SOCD; *fallback* = a mais recente entre as outras direções mantidas ou soltas há ≤ `RELEASE_MEMORY_TICKS = 4` (cobre o stick que salta de RIGHT para DOWN sem sobreposição). Domínio: `_player_substep` passa a devolver `StepResult { BLOCKED, MOVED, CLOSED }`; se o primário devolve BLOCKED e `fallback != NONE`, tenta o fallback no mesmo subpasso. Replays antigos têm bits 4–6 zerados → fallback NONE → comportamento idêntico; ainda assim é mudança de regra e entra no bump de `RULES_VERSION`.

**Orçamento de latência.** Evento → próximo `_physics_process` (≤ 16,7 ms) → `session.step` → `_sync_views` no mesmo frame → apresentação. Meta: intenção refletida no tick seguinte (exatamente 1 tick) e evento→pixel p95 ≤ 33 ms, p99 ≤ 50 ms. Medição: `tools/profile/input_latency_probe_node.gd` sob `shipping_qa` (mesmo despacho e JSON do `frame_pacing_probe_node.gd`), injetando `InputEventKey` via `Input.parse_input_event` e medindo ticks até `px` mudar e frames até `QixPlayerView.position` mudar.

**Ações.** DRAW mantém-se em A/X/Espaço/Z/botão touch; confirmar/pausa como hoje. Nenhuma ação nova de botão: a habilidade testada é direção, tempo e leitura, não vocabulário.

## 9. Roteiro e estilo

O jogador é um **cartógrafo de luz** estabilizando setores de um atlas que resiste. O Núcleo é a instabilidade central; as **Brasas** são correntes que correm pelas linhas já estabilizadas; os **Lampejos** são estilhaços que o Núcleo solta ao encolher; as **Sondas** são a resposta dele à exposição; o **Pavio** é a própria trilha perdendo coerência quando a mão para; as **Balizas** são instrumentos de cartógrafos anteriores — estabilizá-las devolve o que eles deixaram.

Setores: Abyssal Relay ("Cartografe o sinal perdido…"), Aurora Foundry, Verdant Singularity (existentes) + **Umbral Drift** (ramo oculto, âmbar sobre índigo, 4 Balizas em cruz, Núcleo SWEEP lento com escalada agressiva) + **Ferrous Choir** (ramo difícil, cobre e cinza-verde, 6 Balizas em duas fileiras que forçam corredores). Fases nomeadas no HUD (`_status_text`): CALIBRAÇÃO · CORRENTES · REAÇÃO · FRAGMENTAÇÃO · COLAPSO · NÚCLEO CERCADO.

## 10. Impacto no domínio

**Novos campos em `GameSimulation` (todos `int`/8.8):** `roster: EnemyRoster` (8 × `EnemyState`), `beacon_alive: PackedByteArray`, `obstacle_mask: PackedByteArray` (derivado da definição; não entra no checksum), `director_rung`, `director_interval_left`, `director_calm_ticks`, `boss_shot_windup_left`, `boss_shot_interval_left`, `boss_shot_target: Vector2i`, `player_stall_ticks`, `fuse_index` (−1 = inativo), `item_ticks: PackedInt32Array(5)`, `engulf_ticks_left`, `boss_region_cells`, `capture_chain`, `respawn_grace_ticks_left` (= 60; contatos não letais após reentrada, jogador piscando), `round_end_reason`.

**Bytes canônicos no `state_checksum()`**, apensados após o `vals` atual, nesta ordem: `[director_rung, director_interval_left, director_calm_ticks, boss_shot_windup_left, boss_shot_interval_left, boss_shot_target.x, boss_shot_target.y, player_stall_ticks, fuse_index, engulf_ticks_left, boss_region_cells, capture_chain, respawn_grace_ticks_left, round_end_reason]` como s32 LE; depois `item_ticks` (5 × s32); depois 8 slots × `[kind, alive, x_fp, y_fp, dir_index, speed_fp, timer, aux, grace_ticks_left]` (9 × s32, slots mortos zerados); depois `beacon_alive` cru. `last_reason` **não** entra: é diagnóstico.

**Eventos novos em `GameEvent.Kind`:** `AI_DECISION{agent, slot, reason, from_dir, to_dir}` (emitido só se `simulation.trace_ai` — flag fora do checksum e das regras, ligada pelo bootstrap de depuração), `ENEMY_SPAWNED{kind, slot, x, y, trigger}`, `ENEMY_DIED{kind, slot, cause}`, `ENEMY_CAPTURED_CHAIN{slot, chain_index, points}`, `BOSS_WINDUP_STARTED{tx, ty, ticks}`, `SHOT_FIRED{slot}`, `FUSE_ARMED/FUSE_HALTED/FUSE_RESUMED`, `THREAT_RUNG_CHANGED{rung, trigger}`, `SECTOR_PHASE_CHANGED{phase, permille}`, `ITEM_COLLECTED/ITEM_EXPIRED{kind}`, `BEACON_STABILIZED{index}`, `BOSS_ENGULF_STARTED/BOSS_ENGULF_BROKEN`; `ROUND_WON` ganha `reason`.

**Ordem do tick (cabeçalho normativo reescrito):**
1. canonicaliza o intent (trilha ativa força draw; fallback só é lido se o primário bloquear);
2. subpassos do jogador (com fallback), contato contra chefe, roster e Sonda no estado atual, `player_stall_ticks`;
3. fechamento → `CapturePlan` (resolver intacto — invariante 5);
4. **diretor**: rung, spawns em slots livres, windup do Núcleo;
5. inimigos em ordem estável: chefe → Pavio → Brasas → Lampejos → Sondas, cada um testando todo segmento varrido;
6. arbitragem `lethal_contact_wins` (inalterada);
7. aplica o plano; **varredura de encurralados** (cadeia), Balizas estabilizadas → itens, `boss_region_cells ← plan.free_remaining`;
8. itens (decremento), escudo (respeita ESTABILIZADOR), envolvimento, score, condição de rodada;
9. eventos confirmados.

**Versões:** `GameRules.RULES_VERSION` 2→3; `RoundDefinition.DEFINITION_VERSION` 1→2 (`beacons`, `beacon_radius`); `BossBehaviorProfile.PROFILE_VERSION` 1→2 (escalada e sonda); `ThreatProfile.THREAT_VERSION` = 1 (novo, dentro de `GameRules.canonical_bytes`); `ReplayLog.SCHEMA_VERSION` **fica 1** (formato binário idêntico; incompatibilidade já é capturada por `rules_version`). `replay_checksum_golden_test.gd`: `GOLDEN_RULES_VERSION = 3`, novos `config_hash` e checksums, e **rotas douradas para R2 e R3** (dívida P2 do ledger). ADRs: 0010 (entrada: latch, SOCD, fallback no byte), 0011 (roster e ocupação fora do board), 0012 (diretor e fases), 0013 (campanha em grafo), 0014 (`canvas_items` e sprites). Ao tocar `GameSession`, `transition_progress()` (float) migra para a view, fechando o item P2 da invariante 1.

## 11. Apresentação e assets

- **Stretch.** `window/stretch/mode = canvas_items`, `scale_mode = integer`, `aspect = keep`: HUD, overlay e stick virtual nítidos em resolução nativa; o campo continua sendo um `Sprite2D` 225×283 com `TEXTURE_FILTER_NEAREST` em escala inteira — célula = quadrado inteiro de pixels. O `board_reveal.gdshader` troca padrões baseados em `FRAGCOORD` por `UV × mask_size`, senão scanline e glint mudam de período com a escala. `framebuffer_shader_probe_node.gd` passa a amostrar pela transformação lógica→nativa.
- **Fonte.** Uma fonte pixel OFL (proveniência em `ASSET-PROVENANCE.md`) para HUD e overlay; `custom_minimum_size` explícito fecha o item P3 do ledger sobre `_add_label`.
- **Sprites (skill `generative-image-assets`, 3× célula, PNG, fundo transparente, sem texto):** Núcleo 48×48 × 8 frames × 5 setores (idle 4, surto 2, windup 2); Brasa 12×12 × 4; Lampejo 12×12 × 6 (ciclo de piscar); Sonda 12×12 × 4 + rastro 24×6; Pavio 12×12 × 4; Baliza 24×24 × 3 estados; ícones de item 18×18 × 5; fundos 225×283 para Umbral Drift e Ferrous Choir. Views mantêm o `_draw` procedural como fallback quando a textura falta (a suíte headless não depende de PNG). `QixAgentView` (`game/enemies/agent_view.gd`) e `QixTelegraphView` (`game/enemies/telegraph_view.gd`) observam `roster` e `boss_shot_*`.
- **Overlay de rastreabilidade** `QixAiTraceOverlay` (`ui/debug/ai_trace_overlay.gd`, F3 ou toque longo no botão de pausa): por slot — kind, razão da última decisão, alvo travado; rung e próximo gatilho do diretor; estado da entrada (primário, fallback, toques latched, vencedor SOCD); ring buffer de 60 ticks de `AI_DECISION`. Só lê snapshot e eventos.
- **Feedback por evento:** cues `windup` (ascendente 0,5 s), `shot`, `ember_near` (loop de proximidade, distância calculada na view), `fuse` (tique-taque), `enemy_caught` (+2 semitons por índice de cadeia), `item`, `rung_up` (drone desce), `phase` (banner), `engulf` (crescendo). Hápticos: windup 40 ms leve, pavio 2×30 ms, captura em cadeia 60 ms, fase 120 ms. Attack/release por cue em ms absolutos — fecha o item de envelopes do ledger.

## 12. Plano de testes

Unitários (arquivo novo por área, para o runner de `tests/run_tests.gd` descobrir sem conflito): `enemy_roster_test`, `minor_agent_controller_test` (Brasa em fronteira sintética 12×12 com junção e beco; Lampejo reflete e só vira em `tick % 24`; Sonda morre em CLAIMED; Pavio congela/retoma e mata em `trail.size()-1`), `threat_director_test` (rungs por tick/permille/comportamento, teto de vivos, calmaria), `move_intent_fallback_test` (byte round-trip bits 4–6, saturação), `input_latch_socd_test` (toque sub-tick, último-vence, buffer consumido por `pdir`, memória de soltura), `capture_chain_test` (1 000…64 000), `beacon_item_test` (fórmula §11, durações), `engulf_test` (626/180, quebra ao crescer), `campaign_branch_test`, `ai_trace_overlay_test` e `telegraph_view_test` (checksum idêntico com e sem view), `domain_purity_test` ganha regra de `float` no domínio.

Integração: golden R1/R2/R3 com roster ativo; `roster_campaign_playthrough_test` (rota humana sem morte nos 3 setores + 2 ramos, com rastreio ligado); `random_intent_replay_roundtrip_test` (3 seeds × 5 setores × 1 800 ticks de intents por `DeterministicRng` de teste → serializa → reproduz → checksum igual); `simulation_step_budget_test` (`step()` p95 ≤ 300 µs com 6 agentes, medido por `tools/profile_simulation_step.gd`); probe de latência no `run_shipping_qa.sh` com limiares p95 ≤ 33 ms / p99 ≤ 50 ms; `verify_m2_capture_route.gd` mantém a rota 179→825‰ com o diretor imobilizado na cópia de QA.

## 13. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Picos de dificuldade (rung + fases + Pavio ao mesmo tempo) | `max_alive` por rung, `director_calm_ticks`, grace de 30/60 ticks; playtest humano na F7 com o overlay ligado para ver *qual* gatilho matou |
| Legibilidade a 1 px/célula com 6 agentes | sprites em resolução nativa via `canvas_items`; contorno escuro obrigatório (dívida `BOUNDARY×THREAT` de `ART_DIRECTION`); `palette_contrast_test` ganha pares agente×chão |
| Invalidação de replays e churn de dourados | um único bump coordenado (F2), ADR-0011 explícita, dourados R1–R3 atualizados no mesmo commit |
| `canvas_items` quebra shader e probe de framebuffer | ADR-0014 com antes/depois medido; padrões por UV; probe reescrito antes da troca |
| Custo do tick em GDScript | contato O(1) por agente por subpasso; varredura só após captura; `simulation_step_budget_test` como catraca |
| Sprites gerados por IA sem coesão | prompts por setor a partir de `ART_DIRECTION.md`, aprovação humana registrada em `ASSET-PROVENANCE.md`, fallback procedural sempre presente |
| Escopo | fases entregáveis isoladamente; F1 e F2 já mudam a sensação sozinhas |

## 14. Fases de entrega

- **F0 — Guardrail:** dourados R2/R3, regra de `float` no `domain_purity_test`, ADR-0010/0011 aprovadas, `profile_simulation_step.gd`.
- **F1 — Entrada:** latch, SOCD, buffer/fallback, `StepResult`, probe de latência, bump `RULES_VERSION = 3` (o único bump; F2 entra na mesma versão antes do merge).
- **F2 — Roster central:** `EnemyRoster`, Brasa, Lampejo, contato, encurralados/cadeia, checksum estendido, `QixAgentView` procedural.
- **F3 — Diretor:** rung, fases, Pavio, Sondas com windup, envolvimento, `QixTelegraphView`, cues/hápticos novos.
- **F4 — Balizas, itens, escada de bônus, razões de fim, rolagem da escada.**
- **F5 — Campanha em grafo:** `CampaignBranch`, Umbral Drift e Ferrous Choir, seeds de expedição.
- **F6 — Definição visual:** `canvas_items`, fonte, sprites gerados, overlay de rastreabilidade.
- **F7 — Calibração humana:** três rodadas jogadas, `TrailExposure` e gatilhos ajustados, `IMPLEMENTATION_STATUS` e `TEST_MATRIX` reescritos com evidência.

## PARÂMETROS
spawn_grace_ticks = 30 (agente recém-nascido não é letal; tradução do atraso de g_player_hit_enable/g_trail_hit_enable, §3.3 #1-2)
respawn_grace_ticks = 60 (jogador imune após reentrada; mesmo mecanismo de §3.3 #1, valor nosso)
ember_step_ticks = 2 (Brasa a 30 cél/s contra 120 do jogador; DESIGN_DECISION)
ember_step_ticks_collapse = 1 (fase COLAPSO ≥ 750‰; DESIGN_DECISION)
ember_spawn_permille = 250 (fase CORRENTES; DESIGN_DECISION)
flicker_speed_fp = 64 (0,25 cél/subpasso, 2 subpassos; DESIGN_DECISION)
flicker_turn_every_ticks = 24 (Lampejo só vira ao piscar — telegraph; DESIGN_DECISION)
flicker_spawn_permille = 650, flicker_spawn_count = 2 (fase FRAGMENTAÇÃO)
shot_windup_ticks = 30 (anel de carga visível antes da Sonda; DESIGN_DECISION pela lente de legibilidade)
shot_speed_fp = 192 (0,75 cél/subpasso, 2 subpassos = 1,5 cél/tick; DESIGN_DECISION)
shot_lifetime_ticks = 240
shot_enable_permille = 500 (fase REAÇÃO)
exposure_shot_trail_px = 96 (trilha longa força windup imediato; ≈ 3/4 do teto de TrailExposure de 127)
stall_arm_ticks = 20 (Pavio arma após 1/3 s parado com trilha; §3.3 #8 tem contador de paralisia, valor nosso)
fuse_cells_per_tick = 1 (60 cél/s; o jogador em movimento sempre escapa)
max_minor_enemies = 6 (original tem 22 ranhuras, §12.3; reduzido pela leitura a 1 px/célula)
roster_slots = 8
chain_points = 1000, 2000, 4000, 8000, 16000, 32000, 64000 (§7.3 tbl_capture_chain_points, dobra até o 7.º)
engulf_region_cells = 626 (1,0 % do interior de 62 663; limiar de 1,0 % em §12.5)
engulf_hold_ticks = 180 (tradução dos 768 frames de §12.4 para rodadas de 30 s)
engulf_bonus_multiplier = 10 × completion_bonus (§12.6: 100 000 vs piso 10 000)
single_fill_bonus_multiplier = 100 × completion_bonus (§12.6 razão 3: 1 000 000)
area_bonus_ladder = (800,10)…(900,20),(910,22),(920,24),(930,26),(940,28),(950,30),(960,35),(970,40),(980,50),(990,100),(991,110)…(999,500) em décimos de completion_bonus (§12.6)
director_ladder_interval_ticks = 600 (+1 rung a cada 10 s de PLAYING; forma de §10)
director_rung_max = 11
director_shield_low_permille = 250 (+2 rungs quando o escudo cai a 25 %; §10 acelera tiros ao expirar o limite)
phase_permille = 250, 500, 650, 750
farming_capture_permille = 20, farming_streak = 3 (par de Brasas contra capturas mínimas repetidas)
calm_capture_permille = 150, director_calm_ticks = 300 (rung −1 após captura grande)
shot_interval_by_rung = —,—,—,—,240,210,180,150,120,96,72,48 (escada monótona de §10)
flicker_respawn_by_rung = —,—,—,—,—,900,720,600,480,360,300,240
max_alive_by_rung = 0,0,2,2,3,3,4,4,5,5,6,6
beacon_radius = 3 (bloco 7×7; §5.8 usa 15×15)
beacon_item_table = FREEZE,WARD,TIMESTOP,FREEZE,FREEZE,SPEEDUP,FREEZE,SPEEDUP,FREEZE,FREEZE; índice = (beacon_index + (target_permille & 0xF)) mod 10 (§11 tabela A)
item_ticks: SHIELD_FREEZE = 480 (§11 p.5), SPEEDUP = 600 (§11 p.1/§4.3), TIMESTOP = 240 (§11 p.3), KILLALL_IMMUNITY = 120 (§11 p.4), TRAIL_WARD = 360 (original)
escalate_at_permille = 650 (BossBehaviorProfile v2)
TAP_LATCH_TICKS = 1 (press entre amostras conta na próxima)
TURN_BUFFER_TICKS = 6 (100 ms de buffer de curva; consumido quando pdir passa a ser a direção)
RELEASE_MEMORY_TICKS = 4 (direção solta recentemente ainda serve de fallback para stick que salta)
intent byte: bits 0-2 direção, bit 3 draw, bits 4-6 fallback, bit 7 reservado = 0
latency budget: 1 tick de simulação; evento→pixel p95 ≤ 33 ms, p99 ≤ 50 ms
step_budget_usec_p95 = 300 (GameSimulation.step com 6 agentes)
overlay_ring_ticks = 60
ember_near_radius_cells = 12 (cue de proximidade, presentação)
sprite_scale = 3 (Núcleo 48×48×8, Brasa/Lampejo/Pavio/Sonda 12×12, Baliza 24×24×3, ícones 18×18×5)
RULES_VERSION = 3, DEFINITION_VERSION = 2, PROFILE_VERSION = 2, THREAT_VERSION = 1, SCHEMA_VERSION = 1 (mantido)

## RISCOS
Picos de dificuldade quando rung, fase e Pavio coincidem — mitigar com max_alive por rung, calmaria de 300 ticks, grace de 30/60 ticks e playtest humano com o overlay para identificar o gatilho letal.
Legibilidade a 1 px/célula com até 6 agentes — mitigar com sprites em resolução nativa (canvas_items), contorno escuro obrigatório e novos pares agente×chão em palette_contrast_test; BOUNDARY×THREAT já está abaixo de 3:1 em ART_DIRECTION.
Invalidação de todos os replays e churn dos valores dourados — um único bump coordenado (RULES_VERSION 3) com ADR-0011 e atualização de R1/R2/R3 no mesmo commit; F1 e F2 entram na mesma versão.
Troca para canvas_items pode quebrar o shader (padrões por FRAGCOORD) e o probe de framebuffer que assume viewport 240×320 — reescrever padrões por UV×mask_size e o probe antes da troca, com ADR-0014 medida.
Custo do tick em GDScript com roster, diretor e varredura — contato O(1) por agente/subpasso, varredura só após captura, e simulation_step_budget_test como catraca (p95 ≤ 300 µs).
Input.use_accumulated_input e o comportamento de parse_input_event no 4.7.2 não foram verificados nesta sessão — validar com o probe de latência antes de afirmar ganho.
Sprites gerados por IA sem coesão com Lumen Cartography — prompts derivados de ART_DIRECTION, aprovação humana registrada em ASSET-PROVENANCE e fallback procedural permanente nas views.
Campanha em grafo e seeds de expedição aumentam superfície de conteúdo sem olho humano na nuvem — ramos entram só com rota de playthrough automatizada e ficam fora dos dourados canônicos.
Escopo grande para o loop de PRs pequenos — cada fase é entregável isolada; F1 (entrada) e F2 (roster) mudam a sensação sozinhas e podem parar ali.


############ Diretor de Ameaça Lumen: elenco menor, escada §10 e rodadas com duas faces
# Diretor de Ameaça Lumen — proposta de design e engenharia

## 1. Visão

Hoje o jogo tem um único ator (o chefe, `boss_*` em `GameSimulation`), uma única pressão de tempo (o escudo) e um único fim de rodada (80‰ → `ROUND_WON`). A rota humana de `boss_active_campaign_playthrough_test.gd` fecha as três rodadas sem morrer. Isso é um vertical slice, não um jogo que testa habilidade.

A proposta adiciona **um diretor de ameaça** e **quatro atores menores** que vivem fora do `BoardState` (invariante 3), todos em inteiros/8.8, todos rastreáveis na tela porque cada um só existe *sobre* um estado territorial: vagalumes sobre `BOUNDARY`, dardos sobre `FREE`, brasas sobre `TRAIL`, balizas em células fixas do interior. O território conquistado deixa de ser só percentual: absorve dardos, encurrala vagalumes, acende balizas e pode **selar o Núcleo**. O fim da rodada ganha três razões e uma escada de bônus. A entrada ganha corner-assist, SOCD por último-pressionado e stick flutuante.

Tudo é `GameSimulation.step(intent)` em um tick, ordem documentada, `DeterministicRng` único, checksum canônico. Mudar isto invalida replays — é uma decisão, registrada em **ADR-0010** com `RULES_VERSION` 2→3 e `DEFINITION_VERSION` 1→2.

Vocabulário de Lumen Cartography: **Núcleo** (chefe), **Vagalume** (faísca de fronteira), **Dardo** (tiro), **Brasa** (faísca de trilha/pavio), **Baliza** (objeto fixo), itens **Impulso**, **Estase**, **Âncora**, **Pulso Lúmen**.

## 2. Elenco de inimigos

Os pools são `PackedInt32Array` de tamanho fixo (Volfied usa 22 ranhuras de `$20` bytes, §12.3): `walkers` = 4×4, `darts` = 6×6, `embers` = 4×3. Tamanho fixo ⇒ `to_byte_array()` é canônico sem ordenar nada. Novo arquivo `game/simulation/minor_actor_pools.gd` (`MinorActorPools`, `RefCounted`) com `STRIDE_*`, `MAX_*`, `canonical_bytes()`, `clear()`. Regras puras em `game/simulation/boundary_walker_rules.gd`, `dart_rules.gd`, `ember_rules.gd`, `beacon_rules.gd` (estáticas, no molde de `BossBehaviorController`), todos em `game/simulation/` para que `domain_purity_test.gd` os varra automaticamente.

### 2.1 Núcleo (existente)
Sem mudança de movimento. Ganha `stasis_ticks` (pula `_boss_update`) e o **selamento** (§3 abaixo). Continua anchor de `FloodFillCaptureResolver` (§5.5 do Volfied: nunca se preenche o lado do inimigo grande).

### 2.2 Vagalume de Borda (Sparx da gramática Qix)
- **Papel:** nega a fronteira como lugar seguro; cerca o jogador entre a borda e o Núcleo.
- **Onde vive:** só em células `BOUNDARY` **vivas** (com ao menos um vizinho-8 `FREE`). Fronteira morta (borda entre `CLAIMED` e moldura) é corredor seguro — recompensa espacial da conquista.
- **Movimento:** `[x, y, dir(0..3 na ordem de BoardState.NEIGHBOR_*), acc_fp]`. Por tick `acc_fp += walker_speed_fp`; enquanto `acc_fp >= 256` dá um passo. Ordem de candidatos `[dir, dir+bias, dir−bias, dir+2]`, primeiro `BOUNDARY` vivo vence. Velocidade máxima 192 (0,75 célula/tick) — o jogador anda 2 células/tick; o vagalume ameaça por encurralar, não por correr.
- **Contato:** célula igual à do jogador, testada a cada subpasso do jogador (passo 2) e a cada passo do vagalume (4c). Subpassos de 1 célula ⇒ sem tunelamento.
- **Spawn:** `round_def.walker_spawn` (padrão: meio da base, `(112, 282)`); `bias` alterna +1/−1 entre spawns (dois vagalumes partem em sentidos opostos, como em Qix). Recusado se o jogador estiver a menos de 12 células; reagendado em 60 ticks. Cadência e máximo vêm da escada (§3).
- **Padrão/telegraph:** determinístico depois de nascer (o RNG só escolhe o instante); “reto vence” torna a rota previsível; a view desenha um rastro de 6 posições.
- **Rastreabilidade:** está sempre sobre uma linha ciano; nunca entra em `TRAIL`.
- **Encurralamento:** sem vizinho vivo por `walker_dormant_ticks = 60` ⇒ apaga, `WALKER_EXTINGUISHED`, +500 pontos. Capturar bem vira caçar.

### 2.3 Dardo (tiro do Núcleo, ACHADOS §5, §10)
- **Papel:** força o jogador a se mover mesmo na borda; pune acampar.
- **Onde vive:** projétil 8.8 sobre `FREE`. `[x_fp, y_fp, dir_index(0..15), speed_fp, warmup_ticks, alive]`.
- **Spawn (backtrack, ACHADOS §5):** escolhe `dir = rng.next_below(16)`; anda a partir da célula do jogador ao longo de `−dir` (tabela `DIRECTION_X/Y` de `BossBehaviorController`, passo de 256) enquanto a célula for `FREE`; nasce na última `FREE` se o alcance ≥ `dart_min_range = 24`; senão tenta `(dir+3)&15`, até 16 vezes. O dardo passa **exatamente** pela posição do jogador no instante do disparo — desviar 2 células basta.
- **Telegraph:** `dart_warmup_ticks = 24` parado e visível (`DART_ARMED`), depois `DART_FIRED`.
- **Movimento:** `n = (speed_fp + 255) / 256` subpassos de `speed_fp / n` — a escada §10 “um passo a cada 3 frames → 2 → 1 → dois por frame” vira 85 → 128 → 256 → 512 fp/tick.
- **Contato:** a cada subpasso, Chebyshev ≤ `dart_contact_radius = 1` do jogador ⇒ letal (`DART_CONTACT`); célula `TRAIL` ⇒ `TRAIL_CUT` + acende Brasa nesse índice (ACHADOS §4: tiro corta trilha ⇒ nascem faíscas). Célula não-`FREE` ⇒ apaga (`DART_ABSORBED`): **território conquistado absorve dardos**.
- **Rastreabilidade:** linha 1×5 orientada por `dir`, anel de carga durante o warmup.

### 2.4 Brasa (faísca de trilha; pavio de Qix; `player_stall_counter` §3.3)
- **Onde vive:** índice na `trail`. `[index, acc_fp, alive]`.
- **Movimento:** `acc_fp += ember_speed_fp (384)`; cada 256 avança um índice rumo à cabeça. O jogador estende a 2 células/tick; a brasa só ganha quando ele para ou vira demais.
- **Contato:** `index >= trail.size() − 1` (o jogador está sobre a cabeça) ⇒ `EMBER_CONTACT`.
- **Spawn:** (a) corte por dardo, no índice do corte; (b) **stall**: `stall_ticks >= 45` com trilha ativa ⇒ brasa em `trail[0]` (§3.3, contador de frames parado; o valor 45 é nosso: 0,75 s parado a meio de um traço é decisão, não pausa).
- **Morte:** captura aplicada ou `_undo_trail()` ⇒ todas apagam.

### 2.5 Baliza (objeto fixo §5.8/§12.3, item §11)
- **Onde vive:** `round_def.beacon_cells: PackedInt32Array` (pares x,y; ≤ 16; interior; ≥ 8 células da moldura; não sobre `boss_start`). Estado `beacons_captured: int` (bitmask).
- **Regra:** após `apply_capture_plan`, cada baliza cuja célula ficou `CLAIMED`/`BOUNDARY` é capturada (§5.8: testa o centro após o preenchimento). Cadeia no mesmo commit paga `[1000, 2000, 4000, 8000, 16000, 32000, 64000]` (§7.3, mesma escala de tela — nossos 10 pts/4 px e 100 pts/1 % já são os do original).
- **Item:** `item_table[(beacon_index + fills_done) % 10]` (§11: índice = objeto + alvo, mod 10). O **mesmo** ponto dá itens diferentes conforme a ordem de captura — não-linearidade barata e legível.

## 3. Diretor de ameaça (`game/simulation/threat_director.gd`)

Funções estáticas puras; estado em `GameSimulation`: `threat_index`, `dart_countdown`, `walker_countdown`, `stall_ticks`, `overtime`.

```
time_index   = min(6, tick / 900)                        # 15 s por degrau
area_index   = min(6, permille / 125)                    # 0..6 até 80 %
overtime_idx = overtime ? 1 + (tick − 5400) / 300 : 0    # §10: índice avança por countdown
threat_index = min(15, time_index + area_index + threat_pressure_bonus + overtime_idx)
```

`threat_pressure_bonus` por rodada: 0 / 1 / 3. R1 chega a 12; R3 a 15 antes do overtime.

**Escada (16 entradas, autorável em `GameRules`, formato §10):**

| idx | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dardo: intervalo (ticks) | 384 | 336 | 288 | 240 | 192 | 144 | 96 | 72 | 60 | 48 | 40 | 96 | 72 | 48 | 32 | 24 |
| dardo: velocidade fp/tick | 85 | 85 | 85 | 85 | 85 | 85 | 85 | 85 | 128 | 256 | 256 | 512 | 512 | 512 | 512 | 512 |
| vagalume: fp/tick | 64 | 64 | 72 | 80 | 88 | 96 | 104 | 112 | 120 | 128 | 136 | 144 | 152 | 160 | 176 | 192 |
| vagalumes máx. | 1 | 1 | 1 | 2 | 2 | 2 | 2 | 3 | 3 | 3 | 3 | 4 | 4 | 4 | 4 | 4 |

Os intervalos 384→48 e o “respiro” no índice 11 (intervalo volta a 96 quando a velocidade salta para dois passos por frame) são a forma de `enemy_rate_table` §10. O piso é 24, não 3: 20 dardos/s é mangueira, não teste de habilidade num campo de 1 px por célula.

**Gatilhos:**
- *Por tick:* `dart_countdown −= 1`; ao chegar a 0, spawn e recarga com `interval[threat_index]`. `walker_countdown` idem com `walker_spawn_interval = 600` enquanto `alive < max_walkers[idx]`.
- *Por permille:* `area_index` sobe a cada 12,5 %; cada captura aplicada **recarrega** `dart_countdown` ao intervalo cheio — capturar compra respiro.
- *Por comportamento:* stall a desenhar ≥ 45 ⇒ brasa; stall na borda ≥ `camp_dart_ticks = 240` ⇒ `dart_countdown = 0`; trilha atingindo `exposure_dart_px = 68` células (≈ `TrailExposure.WARNING_RATIO`, verificado por teste) ⇒ `dart_countdown /= 2` uma vez por trilha — a exposição que o HUD já nomeia passa a chamar fogo.
- *Overtime:* `round_time_limit_ticks = 5400` (90 s). O original usa 12 144 frames (§10); aqui o escudo de 30 s pausa durante a trilha, então 90 s é o limite deste jogo. `OVERTIME_STARTED` uma vez.

**Itens temporizados (§11 traduzidos):** Impulso = `speedup_ticks = 600` (reaproveita `_player_substeps()` e a regra dos 8 px, §4.3); Estase = `stasis_ticks = 300` (pausa só o Núcleo, como `g_timestop_active` pausa a tarefa 0); Âncora = `anchor_ticks = 600` (escudo não desce, `$100882`); Pulso Lúmen = `lumen_ticks = 180` (apaga todos os atores e bloqueia spawns). O “tiro do jogador” (§11 padrão 2/6) fica fora: exigiria segunda ação.

## 4. Variações por território conquistado

| Conquista | O que muda mecanicamente |
|---|---|
| Cada 12,5 % | `area_index` +1: dardos mais frequentes, vagalumes mais rápidos/numerosos |
| Cada captura | dardos sobre células agora `CLAIMED` apagam; vagalumes sobre fronteira morta ficam dormentes → apagam em 60 ticks; brasas morrem; `dart_countdown` recarrega |
| Balizas cercadas | itens por ordem de captura; cadeia dobrando |
| `plan.free_remaining <= boss_seal_cells (400)` | **Núcleo selado** (§12.4 traduzido: lá exigia 96 medições a cada 8 frames porque o chefe podia sair; aqui o bolsão não cresce, então é imediato) ⇒ `ROUND_WON` razão `SEALED` |
| Fronteira morta cresce | corredores seguros contra vagalumes; dardos ainda cruzam `FREE` |

## 5. Não-linearidade

1. **Três razões de fim (§12.5):** `TARGET` (80 % em mais de um fill), `SINGLE_FILL` (80 % num único fill), `SEALED`. Bônus distintos (§7).
2. **Setores com duas faces:** `RoundContent.rules_variants: Array[GameRules]` (opcional). `RoundStartState.rules_variant: int` entra no checksum inicial; `GameSession._start_current_round` escolhe `rules_variants[variant]` quando a rodada anterior terminou por `SEALED`/`SINGLE_FILL`. A face B (“Maré Baixa”, “Fundição”, “Colapso”) tem `threat_pressure_bonus` +2 e escada de bônus ×2. O array de rodadas continua linear; só as regras trocam, e o `config_hash` por rodada continua válido.
3. **Itens dependentes da ordem** (§2.5) e **caça a vagalumes** (§2.2): o mesmo mapa rende partidas diferentes sem RNG extra.
4. **Eventos de campo:** overtime, exposição, acampamento — reagem ao jogador, não a um roteiro.

## 6. Itens e efeitos

| Item | Tabela (`item_table`, §11 forma `05 02 03 05 05 01 05 01 05 05`) | Efeito | Ticks |
|---|---|---|---|
| Âncora | posições 0,3,4,6,8,9 | escudo congela | 600 |
| Pulso Lúmen | 1 (substitui o tiro) | apaga atores, bloqueia spawns | 180 |
| Estase | 2 | Núcleo parado | 300 |
| Impulso | 5,7 | 4 subpassos, nunca nos 8 px iniciais | 600 |

Eventos `ITEM_STARTED {item, ticks}` / `ITEM_ENDED {item}`. HUD mostra o timer em degraus como o contador de percentagem (ADR-0009).

## 7. Fim de rodada e bônus

`completion_bonus` vira base da **escada §12.6** em `area_bonus_ladder` (pares permille→bônus), na escala ×0,1 do original para caber na economia atual (trilha 10, área 100/1 %, base 1000): 800→1000, 810→1100 … 900→2000, 910→2200, 920→2400, 930→2600, 940→2800, 950→3000, 960→3500, 970→4000, 980→5000, 990→10000, 991→11000 … 995→15000, 996→20000, 997→25000, 998→30000, 999→50000. `SEALED` paga 10× a base (§12.5/12.6 razão 2 = 10× o bônus de 80 %); `SINGLE_FILL` 100× (razão 3). `ROUND_WON.data` ganha `reason` e `bonus`. O HUD pode encenar a escada rolando como §12.6 — apresentação, sem tocar domínio.

## 8. Input e habilidade

- **Latência:** o caminho já é 1 tick (`_physics_process` a 60 Hz amostra `Input` e eventos entregues antes do tick). Em `QixBootstrap._ready`: `Input.use_accumulated_input = false` (drags do stick por evento, não por frame); em `project.godot`: `input_devices/buffering/agile_event_flushing = true` (mobile). `physics/common/physics_jitter_fix = 0` só depois de medir com o probe de frame pacing.
- **Buffer de curva (domínio, regra):** `corner_assist_ticks = 6` em `GameRules`. Se o intent é perpendicular a `pdir` e a célula está bloqueada, `_player_substep` continua em `pdir` e guarda `turn_buffer_dir/turn_buffer_ticks`; no primeiro subpasso em que a curva é possível, vira. Estado no checksum; replays antigos invalidados (já estão, pelo bump).
- **Tap persistence (adaptador):** direção tocada e solta em < 4 ticks persiste 4 ticks em `GameInputAdapter`; entra no log como intent normal.
- **SOCD:** opostos simultâneos ⇒ **último pressionado vence** (rastreado por device em `handle_event`, inclusive teclado via `event.is_action_pressed`); perpendiculares ⇒ `pdir` mantém prioridade (comportamento atual de `choose_direction`) e o corner-assist resolve o resto. Neutro seria parar — e parar acende a brasa.
- **Touch:** stick flutuante (centro = ponto do toque inicial em `_press`), histerese de setor (entra na cardinal a 11 px, sai a 7 px; troca de setor só além de ±10°), DRAW mantém raio 39 px × 1,35.
- **Ações:** mover + DRAW (segurar; forçado com trilha ativa, §4.2). Opcional (fase 5): **Traço Fino** (gramática Qix: desenho lento vale 2× a área) no bit 4 do intent — `ReplayLog.SCHEMA_VERSION` 1→2, `trail_slow_px` no checksum.

## 9. Roteiro e estilo

Os setores mantêm os nomes de `ART_DIRECTION.md`; as faces B são “Relé Abissal — Maré Baixa”, “Forja Auroral — Fundição”, “Singularidade Verdejante — Colapso”. Narrativa curta em `RoundVisualDefinition.subtitle` (só apresentação): R1 “O relé ainda transmite. Estabilize 80 % antes que o escudo apague.” R2 “A forja se defende: dardos vêm das bordas, vagalumes patrulham a linha.” R3 “O núcleo colapsa. Sele-o — ou saia com 80 % e viva com isso.” O cartógrafo não pinta: estabiliza um mapa vivo que reage a cada medição.

## 10. Impacto no domínio

**Novos campos em `GameSimulation` (todos `int`):** `threat_index, dart_countdown, walker_countdown, stall_ticks, overtime, speedup_ticks` (substitui `speedup_active`), `stasis_ticks, anchor_ticks, lumen_ticks, beacons_captured, round_end_reason, turn_buffer_dir, turn_buffer_ticks, exposure_dart_fired`; `actors: MinorActorPools`.

**Checksum (`state_checksum`)**, após `boss_effective_speed_fp` e antes de `rng.state, trail.size()`: os 14 inteiros acima na ordem listada; depois `actors.canonical_bytes()` (walkers 64 B + darts 144 B + embers 48 B, fixo) e a trilha. `DeathReason` ganha `DART_CONTACT, WALKER_CONTACT, EMBER_CONTACT`.

**Eventos novos (apêndice do enum, ints existentes intactos):** `THREAT_LEVEL_CHANGED, OVERTIME_STARTED, WALKER_SPAWNED, WALKER_EXTINGUISHED, DART_ARMED, DART_FIRED, DART_ABSORBED, TRAIL_CUT, EMBER_IGNITED, EMBER_EXTINGUISHED, BEACON_CAPTURED, ITEM_STARTED, ITEM_ENDED, BOSS_SEALED`.

**Ordem do tick (cabeçalho normativo de `game_simulation.gd`):**
1. canonicaliza (trilha força draw; corner-assist promove curva pendente);
2. subpassos do jogador: trilha, contato contra Núcleo **e atores** por célula exata; atualiza `stall_ticks`;
3. fechamento → `CapturePlan`;
4. Núcleo (pulado se `stasis_ticks > 0`);
4b. `ThreatDirector`: índice, overtime, countdowns, spawns (único uso do RNG fora do chefe);
4c. atores em ordem estável: vagalumes → dardos (corte acende brasa) → brasas;
5. arbitragem (`lethal_contact_wins`);
6. aplica plano; balizas → itens/cadeia; dardos sobre não-`FREE` apagam; brasas morrem; vagalumes revalidam; selamento;
7. escudo (pausa com trilha **ou Âncora**), timers de item, score, razão de fim;
8. eventos.

**`GameRules` (`canonical_bytes` estendido):** `round_time_limit_ticks, overtime_step_ticks, threat_time_step_ticks, threat_pressure_bonus, ladder_dart_interval[16], ladder_dart_speed_fp[16], ladder_walker_speed_fp[16], ladder_max_walkers[16], walker_spawn_interval_ticks, walker_dormant_ticks, walker_trap_points, dart_warmup_ticks, dart_min_range, dart_contact_radius, ember_speed_fp, stall_ignite_ticks, camp_dart_ticks, exposure_dart_px, boss_seal_cells, beacon_chain_points[7], item_table[10], item_*_ticks×4, area_bonus_ladder, sealed_bonus_multiplier, single_fill_bonus_multiplier, corner_assist_ticks`. `validation_errors` cobre: velocidades ≤ 512 (dardo) e ≤ 256 (vagalume), escadas com 16 entradas, `item_table` com 10, escada de bônus crescente.

**`RoundDefinition` v2:** `beacon_cells: PackedInt32Array`, `walker_spawn: Vector2i` — em `canonical_bytes`.

**`RoundContent`/`RoundStartState`:** `rules_variants`, `rules_variant` (checksum inicial).

**Versões:** `GameRules.RULES_VERSION` 3 (e +1 por fase que mude comportamento), `RoundDefinition.DEFINITION_VERSION` 2, `BossBehaviorProfile.PROFILE_VERSION` inalterado, `ReplayLog.SCHEMA_VERSION` 2 **só** se o Traço Fino entrar. `tests/integration/replay_checksum_golden_test.gd` atualizado no mesmo commit de cada bump, com a justificativa escrita no PR.

## 11. Apresentação e assets

`QixActorView` (`game/enemies/actor_view.gd`, `Node2D`) desenha procedural, lendo `simulation.actors` e `beacon_cells` — a 1 px por célula, sprite texturizado perde para forma+halo. Dívida de contraste de `ART_DIRECTION.md` (BOUNDARY×THREAT 1,28–1,42:1) orienta: vagalume = losango 3×3 `threat_color` com **contorno 1 px `free_color`** e núcleo branco; dardo = linha 1×5 `threat_color` com anel de carga; brasa = pixel branco + anel escuro sobre a trilha; baliza = anel 5×5 `accent_color`, sólido quando capturada. `palette_contrast_test` ganha os pares `FREE×WALKER_OUTLINE` e `TRAIL×EMBER` com piso 3:1.

Assets por IA (skill `generative-image-assets`, proveniência em `assets/ASSET-PROVENANCE.md`): 3 fundos de face B, 225×283, mesmas paletas com acento deslocado; folha de ícones de item 4×2 (16×16, 128×32) para HUD e baliza; 3 emblemas de Núcleo 64×64 para a intro; 1 folha de glifos de razão de fim (SELADO / ÚNICO / ALVO) 96×24. Áudio: cues `dart_armed`, `dart_fired`, `trail_cut`, `ember`, `beacon`, `item`, `sealed` na `QixProceduralAudioLibrary`, com prioridade declarada; háptica curta em `TRAIL_CUT` e `DART_ARMED`.

## 12. Plano de testes

- **Unit (novos):** `threat_director_test` (monotonia em tick e permille, teto 15, overtime, recarga por captura); `boundary_walker_rules_test` (só `BOUNDARY` viva, reto-vence, reversão, dormência→apagar, determinismo A/B); `dart_rules_test` (backtrack passa pela célula do jogador, warmup imóvel, subpassos ≤ 256, absorção, corte gera brasa no índice certo); `ember_rules_test` (avança, morre na captura/undo, mata na cabeça); `beacon_rules_test` (captura pós-commit, `(i+fills)%10`, cadeia dobrando); `items_test` (Impulso respeita 8 px; Estase zera Núcleo; Âncora congela escudo; Lúmen limpa pools); `round_end_reason_test` (escada, SEALED, SINGLE_FILL); `corner_assist_test`; `minor_actor_pools_test` (checksum idêntico para estados idênticos com histórico de spawn diferente); `input_adapter_test` (+SOCD último-vence, tap persistence); `touch_controls_test` (+stick flutuante, histerese de setor); `exposure_alignment_test` (`TrailExposure.ratio(68, 8, 225, 283) >= WARNING_RATIO`).
- **Integração:** golden atualizado (a rota de 177 ticks não recebe dardo antes do tick 384 nem vagalume antes de 600 — continua sem morte); rota humana re-autorada mantendo “zero mortes”; `boss_campaign_balance_test` ganha “nenhuma morte por ator nos primeiros 600 ticks parado” (justiça do telegraph); `game_session_test` com variante de regras e razão de fim.
- **Ferramentas:** `tools/verify_threat_ladder.gd` — 7200 ticks parado por rodada, imprime dardos/10 s, vagalumes vivos, índice; `tools/verify_m2_capture_route.gd` zera a escada na cópia QA (já duplica regras) para isolar captura.
- **Guardas existentes:** `domain_purity_test` varre os arquivos novos; `doc_freshness_header_test` exige cabeçalho nos docs tocados; `presentation_views_test` prova que `QixActorView.sync` não altera checksum.

## 13. Riscos e mitigação

- **Balanço sem olho humano:** headless mede, não aprova. Mitigação: métricas de sobrevivência nas rotas, `verify_threat_ladder`, gate de playtest antes de fechar cada fase; escada e timers 100 % em `.tres`.
- **Dardo mata na borda:** pode parecer injusto no touch. Mitigação: 24 ticks de telegraph, mira na posição do disparo, raio 1, teste “600 ticks parado sem morte por ator”.
- **Corner-assist muda rotas gravadas:** documentado na ADR; rotas re-autoradas; um `corner_assist_ticks = 0` reproduz o comportamento antigo.
- **Bloat de checksum/CPU:** +256 B por checksum; vagalume ≤ 8 leituras por passo, dardo ≤ 2 subpassos, balizas só no commit. O BFS continua o caminho quente.
- **Fila do loop (P0 do `LOOP_LEDGER`):** cada fase é um PR pequeno; nada desta proposta entra enquanto a fila não drenar.
- **`SCHEMA_VERSION`:** só o Traço Fino a toca; fica opcional e por último.

## 14. Fases de entrega

1. **Fundação (RULES_VERSION 3, ADR-0010):** `ThreatDirector`, `MinorActorPools` vazios, campos e checksum, `stall_ticks`, corner-assist, eventos `THREAT_LEVEL_CHANGED/OVERTIME_STARTED`, golden atualizado, `verify_threat_ladder`. Adaptador: SOCD, tap persistence, stick flutuante, `use_accumulated_input`.
2. **Vagalumes:** regras, spawn, encurralamento, `QixActorView`, contraste, cues.
3. **Dardos e Brasas:** backtrack, warmup, corte de trilha, stall, exposição, câmping; rota humana re-autorada.
4. **Balizas, itens, razões e escada:** `DEFINITION_VERSION` 2, conteúdo das três rodadas (4/6/8 balizas), HUD de item e bônus rolando.
5. **Faces B e polimento:** `rules_variants`, fundos e emblemas por IA, Traço Fino opcional (`SCHEMA_VERSION` 2), playtest humano registrado em `docs/loop/runs/`.

## PARÂMETROS
RULES_VERSION = 3 (invariante 7; bump por fase que mude comportamento)
DEFINITION_VERSION = 2 (beacon_cells e walker_spawn entram no canonical_bytes)
MAX_WALKERS = 4, STRIDE 4 (x, y, dir, acc_fp) — pools fixos, §12.3 22 ranhuras
MAX_DARTS = 6, STRIDE 6 (x_fp, y_fp, dir_index, speed_fp, warmup_ticks, alive)
MAX_EMBERS = 4, STRIDE 3 (trail_index, acc_fp, alive)
MAX_BEACONS = 16 (bitmask em beacons_captured)
threat_time_step_ticks = 900 (15 s por degrau; teto 6)
area_index divisor = 125 permille (teto 6 até 80 %)
threat_pressure_bonus = 0 / 1 / 3 por rodada (face B: +2)
round_time_limit_ticks = 5400 (90 s; §10 usa 12 144 frames com escudo de 150 s)
overtime_step_ticks = 300 (§10: índice avança por countdown até 15)
ladder_dart_interval = [384,336,288,240,192,144,96,72,60,48,40,96,72,48,32,24] (§10 forma; piso 24 em vez de 3)
ladder_dart_speed_fp = [85×8,128,256,256,512×5] (§10: 1 passo/3 frames → /2 → /1 → 2 por frame)
ladder_walker_speed_fp = [64,64,72,80,88,96,104,112,120,128,136,144,152,160,176,192] (≤ 256: nunca salta célula)
ladder_max_walkers = [1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,4]
walker_spawn_interval_ticks = 600; walker_spawn_min_player_distance = 12 células; reagendamento 60 ticks
walker_dormant_ticks = 60; walker_trap_points = 500
dart_warmup_ticks = 24 (telegraph 0,4 s)
dart_min_range = 24 células (backtrack, ACHADOS §5)
dart_contact_radius = 1 (Chebyshev; ACHADOS §4 usa <4 px, reduzido para célula de 1 px)
dart substeps = (speed_fp + 255) / 256, cada um ≤ 256
ember_speed_fp = 384 (1,5 célula/tick contra 2 do jogador)
stall_ignite_ticks = 45 (§3.3 player_stall_counter)
camp_dart_ticks = 240 (parado na borda 4 s)
exposure_dart_px = 68 (≈ TrailExposure.WARNING_RATIO 0,5 com piso 8 e teto 127; teste de alinhamento)
boss_seal_cells = 400 (§12.4 traduzido para free_remaining do CapturePlan)
beacon_chain_points = [1000,2000,4000,8000,16000,32000,64000] (§7.3 tbl_capture_chain_points)
item_table = [ÂNCORA,LÚMEN,ESTASE,ÂNCORA,ÂNCORA,IMPULSO,ÂNCORA,IMPULSO,ÂNCORA,ÂNCORA] (§11 tabela A, tiro substituído por Lúmen); índice (beacon+fills_done)%10
item_speedup_ticks = 600; item_stasis_ticks = 300; item_anchor_ticks = 600; item_lumen_ticks = 180
area_bonus_ladder: 800→1000 … 900→2000, 950→3000, 980→5000, 990→10000, 999→50000 (§12.6 ×0,1)
sealed_bonus_multiplier = 10; single_fill_bonus_multiplier = 100 (§12.5 razões 2 e 3)
corner_assist_ticks = 6 (domínio; 0 reproduz comportamento antigo)
tap_persistence_ticks = 4 (adaptador)
touch: dead zone entra 11 px / sai 7 px; histerese de setor ±10°
balizas por rodada = 4 / 6 / 8; distância mínima da moldura 8 células
checksum adicional ≈ 14×4 + 256 bytes

## RISCOS
Balanço não pode ser aprovado headless: a escada, o telegraph e as velocidades precisam de playtest humano registrado antes de fechar cada fase; headless só mede sobrevivência de rotas.
Dardos letais na borda podem ler como injustos no touch; mitigado por 24 ticks de telegraph, mira na posição do disparo, raio 1 e teste de 600 ticks parado sem morte por ator.
Corner-assist e atores mudam rotas gravadas (golden, rota humana, M2): todas precisam de re-autoria no mesmo PR, com justificativa escrita; corner_assist_ticks = 0 e escada zerada reproduzem o comportamento antigo para QA.
Cada fase invalida replays (RULES_VERSION +1): aceitável agora, mas o projeto ainda não tem replays de usuário; deve ficar explícito na ADR-0010.
Fila P0 do LOOP_LEDGER: enquanto os PRs abertos não drenarem, qualquer fase colidirá em game_simulation.gd, game_rules.gd e no golden; fases devem ser PRs pequenos e sequenciais.
Legibilidade a 1 px por célula: contorno escuro e halo são hipótese; a catraca de palette_contrast_test garante piso 3:1 mas não substitui olho humano na tela.
SCHEMA_VERSION 2 (Traço Fino) muda o formato binário do log: deixado opcional e por último para não misturar com os bumps de regras.
Backtrack de dardo custa até 16×283 leituras por spawn; raro, mas deve ser medido em profile_board_view ou probe equivalente se a escada chegar ao índice 15 em overtime.


############ Atlas Vivo — setores que reagem ao jogador (elenco menor, diretor de ameaça, grafo de campanha)
# Atlas Vivo — proposta de gameplay para o QIX GAME

> Lente: **organicidade e não-linearidade**. Tudo abaixo é inteiro ou ponto fixo 8.8, passa pelo `DeterministicRng`, entra no checksum e é reproduzível em `tests/run_tests.gd`. Referências ao Volfied citam `reference/volfied/06-gameplay.md §X` e são traduzidas para *Lumen Cartography*.

## 1. Visão

Hoje o setor é um duelo limpo: um cartógrafo, um Núcleo, um escudo. A proposta transforma o setor num **organismo que responde ao que o jogador faz**: uma trilha comprida atrai um Eco; acampar na moldura chama uma Vigia; um corte de 10 % faz o Núcleo semear patrulhas na fronteira que acabou de nascer; o Núcleo muda de fase conforme o mapa fecha e entra em fúria quando fica encurralado. Entre setores, o jogador escolhe a rota num atlas em grafo, e a seed decide onde as Balizas (itens) nascem. Três regras de qualidade valem para tudo:

1. **Nada mata sem 30 ticks de aviso visível** (`spawn_warmup_ticks = 30`): todo inimigo nasce em estado `WARMUP`, inofensivo e desenhado.
2. **Nenhuma reação nasce a menos de 16 células do jogador** (`spawn_safe_radius = 16`, Manhattan) nem no tick de um fechamento.
3. **Todo inimigo tem causa e intenção legíveis**: `cause` (por que nasceu) e `intent_cell` (para onde vai) são estado do domínio, não inferência da view.

## 2. Elenco de inimigos

| Ator | Vive em | Movimento | Contato letal | Capacidade |
|---|---|---|---|---|
| **Núcleo** (chefe, existente) | `FREE` | 8.8, 16 direções, `boss_substeps` | centro + cruz (`boss_contact_cells()`) | 1 |
| **Vigia** | `BOUNDARY` | 1 célula a cada `vigia_step_every_ticks` | mesma célula ou adjacente cardinal ao jogador | 4 |
| **Eco** (projétil) | `FREE` | 8.8, 16 direções, `eco_substeps = 1` | Manhattan ≤ 2 | 3 |
| **Fagulha** | `TRAIL` (índice na `trail`) | ±1 índice a cada `fagulha_step_every_ticks` | índice == `trail.size() - 1` (a célula do jogador) | 8 |

O roster tem `MAX_ENEMY_SLOTS = 24` (Volfied percorre 22 ranhuras em `$103000`, §3.3 #12; 24 dá folga e alinha). Inimigos **não** vivem no `BoardState`: ficam em `EnemyRoster` (arrays empacotados por slot), iterados em ordem de slot, e o spawn ocupa sempre o menor slot livre — ordem estável, invariante 3 intacto.

### Núcleo — fases por permille
- **Papel:** âncora do resolver (§5.5, já implementado) e fonte de Ecos.
- **Fases:** `phase_thresholds_permille = [300, 550]` → fase 0 *Latente*, 1 *Desperto*, 2 *Encurralado*. Por fase: `phase_speed_permille = [1000, 1100, 1200]`, `phase_turn_ticks = [45, 36, 30]` (os mesmos passos que hoje separam R1→R3, agora dentro de uma rodada). Velocidade efetiva = `boss_speed_fp × fase × pulso / 1000²`, validada ≤ 256 por subpasso (128×1,2×1,25 = 192 no pior setor atual).
- **Inteligência:** a partir da fase 1, se `trail_active` e o meio da trilha (`trail[trail.size()/2]`) está a ≤ `boss_sense_cells = 48` do Núcleo, o próximo `next_direction` aponta para esse meio em vez do jogador (o Volfied faz o tiro nascer junto do jogador, §10 `enemy_shot_spawn_at_player`; aqui o Núcleo caça a trilha, que é o que dói). Decisão pura em `BossBehaviorController.next_direction` com um `context` a mais.
- **Encurralado (emergente):** o domínio conta reflexões numa janela (`cornered_window_ticks = 60`, `cornered_reflections = 6`). Ao atingir, emite `BOSS_CORNERED`, aplica pulso de `pulse_speed_permille` por `cornered_burst_ticks = 90` e dispara 1 Eco. Um Núcleo espremido bate mais nas paredes — o jogador sente que o apertou.
- **Telegraph:** a `QixEnemyView` já lê `boss_dir_index`; a fase muda a silhueta (anéis 1/2/3) e a cor do núcleo (`trail_hot_color` → branco).
- **Rastreável:** `threat_phase` e `cornered_reflections` são campos do checksum.

### Vigia — patrulha da fronteira
- **Papel:** pune acampar e defende a fronteira recém-criada. Comportamento extraído das faíscas do Volfied (andam sobre células marcadas testando o bit da trilha, `ACHADOS_ANOTACAO.md` banda 02) e da gramática de Qix (patrulha de borda).
- **Movimento:** só pisa em `BOUNDARY`. Regra de mão fixa por slot (`hand = slot & 1`): ordem de escolha `[frente, mão, contramão, trás]` sobre `NEIGHBOR_DX/DY`. Modo **caçadora** quando o jogador está a ≤ `vigia_sense_cells = 40`: escolhe o vizinho `BOUNDARY` que minimiza Manhattan até o jogador (greedy, O(4), sem BFS). Duas Vigias na mesma célula invertem o sentido (`vigia_reverse_on_meet = true`) — mantém-nas espalhadas.
- **Spawn:** em `RoundDefinition.vigia_gates` (células da moldura autoradas) ou nas duas pontas de uma trilha recém-consolidada (`plan.trail_indices[0]` e último). Sempre a ≥ 16 células do jogador.
- **Contato:** jogador na mesma célula ou adjacente cardinal (o jogador só toca a fronteira quando anda por ela ou no primeiro vértice da trilha).
- **Telegraph:** `VigiaWalker.peek_path(board, x, y, heading, hand, 8)` é estática e pura; a view a chama sobre o snapshot para desenhar 8 células de rastro futuro. Warmup de 30 ticks com anel pulsante.
- **Rastreável:** `cause ∈ {STALL, BIG_CAPTURE, PHASE, TIME_LADDER}`; `age_ticks`.

### Eco — o projétil do Núcleo
- **Papel:** a cadência do §10 (`enemy_rate_table`) traduzida: é o que faz o tempo pesar.
- **Movimento:** nasce na célula do Núcleo, direção quantizada por `nearest_direction_index` (mira no meio da trilha se houver trilha, senão no jogador, com jitter `rng.next_below(3) - 1` passos), reflete em `BOUNDARY/CLAIMED` com `reflected_horizontal/vertical`. Vida `eco_life_ticks = 900`, depois `DYING` 12 ticks.
- **Escada:** `eco_interval_ticks = [384, 336, 288, 240, 192, 144, 96, 72, 48, 36]` e `eco_speed_fp = [85, 85, 85, 85, 85, 128, 128, 256, 256, 256]` (§10: um passo a cada 3 frames → cada 2 → cada frame; a cauda `$FF` de dois passos por frame fica fora porque a 1 px por célula seria ilegível). Índice = `max(índice temporal, permille / 100)`.
- **Corte:** Eco que entra numa célula `TRAIL` regista `pending_trail_cut_index`, morre e gera Fagulhas (cadeia tiro → corte → faíscas de `ACHADOS` banda 02). Se no mesmo tick a captura for válida, o corte é nulo — a trilha já virou fronteira.
- **Telegraph:** linha de intenção de 12 px na direção, warmup 30 ticks parado sobre o Núcleo.
- **Rastreável:** `cause ∈ {LONG_TRAIL, TIME_LADDER, CORNERED, STREAK}`.

### Fagulha — a trilha queimando
- **Papel:** transforma "fui cortado" em "tenho 2 segundos para fechar". Volfied gera 8 (`ACHADOS`); aqui `fagulhas_per_cut = 4`, duas para cada lado do corte — 8 pontos de 1 px viram ruído.
- **Movimento:** índice `k` na `trail`; `dir = ±1`; passo a cada `fagulha_step_every_ticks = 2` (0,5 célula/tick contra 2 do jogador: quem continua desenhando escapa, quem hesita morre). Em `k == 0` inverte; vida `fagulha_life_ticks = 600`.
- **Morte:** captura aplicada (`_commit_capture`) ou `_undo_trail` matam todas; `ENEMY_DESTROYED{cause: TRAIL_GONE}`.
- **Telegraph:** a própria trilha escurece atrás da Fagulha (o shader recebe `trail_burn_index` como uniform de apresentação).

## 3. Diretor de ameaça

`ThreatDirector` é uma classe pura em `game/simulation/threat_director.gd`: recebe `(tick, permille, contadores, ThreatProfile, rng)` e devolve `Array[SpawnOrder]`; `GameSimulation` aplica. Roda no passo 8 do tick (§10 abaixo), **depois** da captura do tick, para reagir a ela no mesmo tick.

| Gatilho | Condição (inteiros) | Reação | Origem |
|---|---|---|---|
| Escada temporal | `tick ≥ pressure_start_ticks = 3600`; a cada `eco_interval_ticks[idx]` dispara 1 Eco e `idx += 1` (máx. 9) | Eco `TIME_LADDER` | §10: a escada começa ao expirar o limite (12 144 frames lá; 60 s aqui, rodadas são mais curtas) |
| Escada por permille | `idx = max(idx, permille / 100)` | cadência sobe com o mapa fechado | §10 traduzido: conquistar aumenta a pressão |
| Fase do Núcleo | cruzar `[300, 550]`‰ | `THREAT_PHASE_CHANGED`; 1 Vigia por gate ativo (`phase_vigias = [0, 1, 2]`) | DESIGN_DECISION |
| Trilha longa | `trail.size() ≥ long_trail_px = 96` (o HUD já avisa em `TrailExposure.WARNING_RATIO` ≈ 67 células — o aviso vem antes da punição) | 1 Eco mirando o meio da trilha; repete a cada 120 ticks enquanto a trilha viver | §10 spawn junto do jogador |
| Acampar | `stall_ticks ≥ stall_trigger_ticks = 180` (jogador sem mudar de célula), repete a cada 120 | 1 Vigia no gate mais distante, modo caçadora | §3.3 #8 `player_stall_counter` |
| Captura grande | `filled_delta × 1000 / interior ≥ big_capture_permille = 100` | 2 Vigias nas pontas da nova fronteira (`BIG_CAPTURE`) + cadeia de pontos por inimigos envolvidos | §7.3 cadeia; §12.5 |
| Beliscar | `small_capture_streak ≥ 4` capturas consecutivas < `small_capture_permille = 15` | `idx += 1`, 1 Eco `STREAK` | DESIGN_DECISION (anti-tartaruga) |
| Encurralado | `cornered_reflections ≥ 6` em 60 ticks | `BOSS_CORNERED`, pulso 90 ticks, 1 Eco | emergente |

Tetos: `max_active_ecos = 3`, `max_active_vigias = 4`, `max_fagulhas = 8`; `spawn_block_ticks_left` (após KILLALL) bloqueia tudo. O diretor nunca consome `rng` fora da sua chamada, e a ordem de gatilhos é a da tabela — determinismo por construção.

## 4. Variações por território conquistado

- **0–299 ‰ (Latente):** só o Núcleo e a escada temporal. O jogador aprende o setor.
- **300–549 ‰ (Desperto):** Núcleo 1,1×, caça a trilha, 1 Vigia por gate ativo. A fronteira já é comprida o bastante para a Vigia importar.
- **550–799 ‰ (Encurralado):** Núcleo 1,2×, virada a cada 30 ticks, 2 Vigias/gate, `eco_rate_floor = 4`. É onde o Núcleo bate mais nas paredes e a fúria aparece sozinha.
- **Fronteira recém-criada:** toda captura ≥ 10 % semeia Vigias nas pontas da trilha consolidada — o lugar onde o jogador vai voltar a desenhar. Ele aprende a cortar e sair.
- **Inimigos envolvidos:** após `_commit_capture`, Ecos cuja célula virou `CLAIMED` morrem com cadeia `enemy_chain_points = [500, 1000, 2000, 4000, 8000]` (dobra como em §7.3, cortada no 5.º para caber na economia de 10 pts/‰). Capturas grandes que engolem Ecos são o *jackpot* orgânico.
- **Balizas** fora do lado do Núcleo são apanhadas pela captura (§5.8: centro dentro do território) — cada corte é também uma escolha de item.

## 5. Não-linearidade

**Campanha em grafo.** `RoundContent.next_round_ids: Array[StringName]` (0 = terminal, 1 = linear, 2 = escolha). `CampaignDefinition.validation_errors()` exige ids existentes, DAG (DFS) e que todo caminho termine. `GameSession` ganha a fase `SECTOR_CHOICE` entre `ROUND_CLEAR` e `ROUND_INTRO`: `intent.direction` `LEFT/RIGHT` move o destaque, `confirm` fixa. A escolha vai para `RoundRunRecord.next_choice` (sessão, não `ReplayLog` — o replay de rodada continua isolado, ADR-0004). O grafo inicial:

```
Abyssal Relay → {Aurora Foundry | Tidal Archive} → {Verdant Singularity | Hollow Meridian} → Lumen Apex
```

Rotas mais duras têm `completion_bonus` maior e mostram glifos de ameaça derivados do `ThreatProfile` (leitura, não mutação).

**Variação por seed.** Em `reset_round`, o diretor consome `rng` para (a) escolher `active_item_slots = 3` entre os ≤ 5 `item_slots` autorados e (b) sortear o tipo de cada Baliza com `item_table[(slot + rng.next_below(10)) % 10]` (§11: o item não é fixo, o índice mistura posição e alvo). O rastro do RNG já muda com a rota do jogador (WANDER/jitter consomem `rng`), então dois jogadores no mesmo seed veem o mesmo setor até divergirem — replayável, não previsível.

**Fins de rodada.** `ROUND_WON.data.reason ∈ {TARGET, SINGLE_CUT}`: `SINGLE_CUT` quando a captura que cruza o alvo tem delta ≥ `special_cut_permille = 300` (§12.5 razão 3: 80 % num único preenchimento) e paga `special_cut_multiplier = 5`×. Um segundo caminho de vitória (`SEALED`, §12.4, 96 medições a cada 8 ticks) fica reservado para o setor gêmeo de duas âncoras (§5.5, ronda 5), que exige `CapturePlan.anchors_split` no resolver — fase 5, opcional.

## 6. Itens e efeitos

Balizas: nós de 5×5 em `FREE` que **não bloqueiam** nada (evita um 5.º estado no `BoardState` e ADR-0001). Apanhadas quando o centro vira `CLAIMED` (§5.8). Tipos e durações em ticks, todos em `ThreatProfile`:

| Tipo | Efeito | Origem |
|---|---|---|
| `SPEEDUP` | `speedup_ticks_left = 600`; liga o `speedup_active` que já existe e ninguém aciona | §11 padrão 1, §4.3 |
| `TIMESTOP` | `timestop_ticks_left = 300`: Núcleo e emissão de Ecos param; Vigias e Fagulhas não | §11 padrão 3 ("pára a tarefa 0") |
| `SHIELD_FREEZE` | `shield_freeze_ticks_left = 600`: escudo não desce | §11 padrão 5, §9 |
| `KILLALL` | destrói todo inimigo menor (pontos de cadeia) + `spawn_block_ticks_left = 120` | §11 padrão 4 |
| `NONE` | vazio (a seed pode negar) | §11 `$FF` |

`item_table = [FREEZE, TIMESTOP, SPEEDUP, FREEZE, KILLALL, SPEEDUP, FREEZE, NONE, TIMESTOP, FREEZE]` — mesma **distribuição** do original (congelar é comum, matar tudo é raro), conteúdo próprio. Tiro do jogador (§11 padrões 2/6) fica fora: dilui o verbo territorial. Escudo após morte: `shield_respawn_mode = FLOOR` repõe `max(restante, shield_floor_ticks = 600)` (§9 `game_countdown_floor_3`: 300 de 900 = 1/3); R1 mantém `FULL`.

## 7. Fim de rodada e bônus

Escada de §12.6 traduzida para a economia local (área paga 10 pts/‰): `bonus_ladder_permille = [1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000, 2200, 2400, 2600, 2800, 3000, 3500, 4000, 5000, 10000]` indexada por `(permille − 800) / 10` (80…99 %), 100 % → 12000. Bônus = `completion_bonus × ladder / 1000`; `SINGLE_CUT` ×5; morte zero na rodada paga `no_death_bonus_permille = 250` a mais. O `ROUND_WON` carrega `reason`, `ladder_index`, `bonus`; a `QixRoundTransitionView` encena a escada subindo (mesmo mecanismo do ADR-0009, observando valores já confirmados).

## 8. Input e habilidade

Tudo em `app/` e `ui/`; o domínio continua recebendo um `MoveIntent` de 1 byte e o replay grava o intent **resultante** — nenhuma dessas mudanças toca checksum.

- **Latência:** `input_devices/buffering/agile_event_flushing = true` no `project.godot` e `Input.use_accumulated_input = false` no `_ready` do `QixBootstrap` (eventos chegam antes de cada `_physics_process`, não acumulados). Alvo: 1 tick (16,7 ms) entre evento e `step`, medido pelo probe de frame pacing existente com um evento sintético.
- **Tap latch:** `handle_event` passa a registar `event.is_action_pressed("move_*")`/`"draw"` num latch por tick; um toque mais curto que um tick ainda produz um tick de intent. Hoje `sample()` só lê `Input.is_action_pressed` e perde o toque.
- **Buffer de curva:** a última direção perpendicular pressionada fica guardada por `turn_buffer_ticks = 6` (100 ms). `sample(simulation)` observa o snapshot (`board.get_cell` da célula-alvo, `trail_active`, `pdir`): se a curva ainda não é legal, emite a direção corrente; quando vira legal, emite a curva. A view observa; o domínio decide.
- **SOCD:** "último pressionado vence" nos dois eixos, com ordem de pressão medida pelo contador de ticks do adaptador (inteiro, incrementado pelo bootstrap — nunca relógio). Inversão instantânea no mesmo eixo é a habilidade central de escapar de uma Fagulha.
- **Touch:** histerese angular no stick (entrar 0,42 / sair 0,28 do raio, como o analógico), *flick* = latch de 1 tick, e `DRAW` com pulso háptico de 40 ms ao confirmar `TRAIL_STARTED`.
- **Verbos:** continuam dois (mover, desenhar). O teste de habilidade vem dos atores, não de botões novos.

## 9. Roteiro e estilo

Setores são folhas de um atlas bioluminescente que o cartógrafo estabiliza; o Núcleo é a corrente que apaga o mapa; Vigias são faróis corrompidos que percorrem as linhas já traçadas; Ecos são pulsos que o Núcleo emite; Fagulhas são a tinta da trilha a arder; Balizas são marcos que a cartografia recupera.

| Setor | Perfil | Frase |
|---|---|---|
| ABYSSAL RELAY | WANDER, diretor mínimo, `FULL` | "Cartografe o sinal perdido sob a corrente escura." (existente) |
| AURORA FOUNDRY | PURSUIT, Ecos cedo (`pressure_start_ticks = 2400`) | existente |
| TIDAL ARCHIVE | WANDER lento, 4 gates, Vigias caçadoras desde a fase 0 | "As marés guardam cada linha que você já traçou." |
| VERDANT SINGULARITY | SWEEP, tudo ligado | existente |
| HOLLOW MERIDIAN | PURSUIT, escada de Ecos a partir do índice 4, `long_trail_px = 72` | "Um meridiano vazio devolve cada pulso que recebe." |
| LUMEN APEX | SWEEP 3 fases, `eco_substeps = 2` no índice 9, `FLOOR` | "Feche o atlas. O Núcleo já sabe o seu nome." |

## 10. Impacto no domínio

**Arquivos novos (todos varridos por `domain_purity_test.gd`):** `game/simulation/enemy_roster.gd` (`EnemyRoster`), `game/simulation/threat_director.gd`, `game/simulation/vigia_walker.gd` (estático, puro), `game/simulation/item_state.gd`, `game/rules/threat_profile.gd` (`ThreatProfile extends Resource`, `PROFILE_VERSION := 1`, `validation_errors()`, `canonical_bytes()` com arrays prefixadas por tamanho). Adicionar `res://game/enemies` aos `DOMAIN_DIRS` do scanner: `boss_behavior_controller.gd` é domínio e hoje está fora da guarda.

**Campos novos em `GameSimulation` (todos s32):** `stall_ticks, threat_phase, eco_rate_index, eco_spawn_countdown, cornered_reflections, cornered_window_left, small_capture_streak, last_capture_permille_delta, capture_chain, timestop_ticks_left, killall_ticks_left, shield_freeze_ticks_left, speedup_ticks_left, spawn_block_ticks_left, pending_trail_cut_index, round_end_reason` + `roster: EnemyRoster` + `items: ItemState`. `DeathReason` ganha `ECO_CONTACT, VIGIA_CONTACT, FAGULHA_CONTACT`.

**Checksum (`state_checksum`)**, após `trail.size()` em `vals`: os 16 inteiros acima na ordem listada; depois `roster.canonical_bytes()` = `u32 count` + 24 slots × 8 s32 `{kind, state, x_fp, y_fp, dir_index, speed_fp, age_ticks, aux}` (slots vazios zerados — tamanho fixo, 772 bytes); depois `items.canonical_bytes()` = `u32 count` + n × 4 s32 `{kind, cx, cy, state}`. Ordem fixa, LE, nunca Dictionary.

**Ordem do tick (novo cabeçalho normativo):**
1. canonicaliza o intent;
2. subpassos do jogador (`_player_substep`) + `stall_ticks`;
3. fechamento → `CapturePlan` (TRAIL ativa até a arbitragem);
4. Núcleo (`_boss_update`, conta reflexões, respeita `timestop`);
5. inimigos menores em ordem de slot (`_enemies_update`): Vigias, Ecos (marcam corte), Fagulhas; cada um testa contato e avança `WARMUP → ARMED`;
6. arbitragem: `lethal_contact_wins` inalterado; contato de qualquer ator é `lethal`;
7. aplica o plano (`_commit_capture`) e faz a **varredura pós-captura**: inimigos em `CLAIMED` morrem com cadeia (§7.3: "logo a seguir a cada preenchimento, não continuamente"), Fagulhas morrem, Balizas com centro `CLAIMED` são apanhadas, corte pendente é anulado; sem plano, corte pendente gera Fagulhas;
8. diretor de ameaça (`_director_update`): gatilhos da tabela, spawns, timers de efeito;
9. escudo (respeita `shield_freeze_ticks_left`);
10. condição de rodada (`_check_round_end`: alvo, `reason`, escada de bônus);
11. eventos confirmados.

**Eventos novos em `GameEvent.Kind`:** `ENEMY_SPAWNED{slot,kind,x,y,cause}`, `ENEMY_ARMED{slot}`, `ENEMY_DESTROYED{slot,kind,cause,chain,points}`, `TRAIL_CUT{x,y}`, `THREAT_PHASE_CHANGED{phase,permille}`, `BOSS_CORNERED{reflections}`, `PLAYER_STALLING{ticks}`, `ITEM_PICKED{kind,x,y}`, `EFFECT_STARTED{effect,ticks}`, `EFFECT_ENDED{effect}`; sessão: `SECTOR_CHOICE_STARTED{options}`, `SECTOR_CHOSEN{round_id}`. `ROUND_WON` ganha `reason, ladder_index, bonus`.

**Versões:** `GameRules.RULES_VERSION` 2→3 (uma vez, na fase 1; fase 2 → 4), `RoundDefinition.DEFINITION_VERSION` 1→2 (`item_slots`, `vigia_gates`), `BossBehaviorProfile.PROFILE_VERSION` 1→2 (fases), `ThreatProfile.PROFILE_VERSION` = 1, `ReplayLog.SCHEMA_VERSION` **fica 1** (o byte do intent não muda; o cabeçalho já rejeita `rules_version` diferente). `GameRules.canonical_bytes()` anexa `threat_profile.canonical_bytes()` depois do perfil do chefe. ADRs: **ADR-0010** (elenco menor, diretor, itens, escada — um só bump), **ADR-0011** (campanha em grafo), **ADR-0012** (latch/buffer/SOCD, emenda ao ADR-0006). `replay_checksum_golden_test.gd` atualizado no mesmo commit de cada bump, com uma rota dourada por setor de produção.

## 11. Apresentação e assets

Views continuam observadoras: `QixEnemyView` passa a desenhar o roster inteiro por slot (≤ 24 primitivas, custo desprezível); `ui/threat_strip.gd` lista inimigos vivos por glifo de causa; `ui/sector_choice_view.gd` desenha o atlas. Cores novas em `RoundVisualDefinition`: `vigia_color`, `eco_color`, `fagulha_color`, `beacon_color`. **Guardrail de contraste:** Vigia vive sobre `BOUNDARY`, onde a ameaça atual mede 1,28–1,42:1 (`ART_DIRECTION.md`); a Vigia usa núcleo escuro + aro branco (canal de luminância) e entra em `PaletteContrast.PAIR_FLOOR` com piso 3:1 contra `BOUNDARY` nas quatro paletas.

Sprites gerados por IA (skill `generative-image-assets`), originais, com proveniência em `assets/ASSET-PROVENANCE.md`, todos com margem de 1 px e leitura em 1×:

| Asset | Tamanho | Frames |
|---|---|---|
| Núcleo por fase | 16×16 | 3 fases × 4 |
| Vigia | 5×5 | 4 (rotação de 90°) |
| Eco | 3×3 + cauda 7×3 | 2 |
| Fagulha | 3×3 | 4 |
| Balizas (5 tipos) | 7×7 | 2 (latente/ativa) |
| Ícones de setor (6) | 24×24 | 1 |
| Fundos novos (3 setores) | 225×283 | 1 |

Áudio (`QixProceduralAudioLibrary.CUE_RECIPES`): `eco_fire`, `trail_cut`, `fagulha`, `vigia`, `enemy_captured` (subindo meio-tom por elo da cadeia), `item_pick`, `phase_up`, `cornered`, `special_clear`, `sector_choice`. Háptica (`QixHapticFeedback`): `trail_cut` prioridade 60, `enemy_captured` 45, `phase_up` 35 — entre `shield` (50) e `death` (100) já existentes.

## 12. Plano de testes

Tudo em `tests/unit` e `tests/integration`, descoberto por `run_tests.gd`, arquivo novo por tema (evita colisão com a fila do loop).

- `enemy_roster_test`: capacidade 24, menor slot livre, ordem de iteração, `canonical_bytes` estável e de tamanho fixo.
- `vigia_walker_test`: nunca sai de `BOUNDARY` em 3 000 ticks × 3 seeds com capturas reais; regra de mão em T; inversão ao encontrar; caçadora reduz Manhattan; `peek_path` coincide com o passo real.
- `eco_test`: reflexão idêntica à do chefe; corte marca `pending_trail_cut_index`; captura no mesmo tick anula o corte; morre em `CLAIMED` com cadeia `[500…8000]`.
- `fagulha_test`: nasce 2+2 no corte, avança 1/2 tick, inverte em `k=0`, mata só em `k == trail.size()-1`, some em `_undo_trail` e em captura.
- `threat_director_test` (puro): cada linha da tabela do §3 com contadores injetados; tetos; `spawn_safe_radius`; nenhum spawn no tick de fechamento; warmup de 30 ticks antes de qualquer contato letal (**fairness**).
- `boss_phase_test`: limiares, velocidades ≤ 256, caça à trilha, `BOSS_CORNERED` em cenário sintético de 6 reflexões.
- `item_state_test`: sorteio por seed, apanha por centro `CLAIMED`, quatro efeitos e timers, `speedup_active` finalmente ligado.
- `round_end_ladder_test`: 20 degraus, `SINGLE_CUT` ×5, `no_death_bonus`, `FLOOR` do escudo.
- `game_session_graph_test`: DAG válido/inválido, `SECTOR_CHOICE` com LEFT/RIGHT/confirm, `next_choice` arquivado, replay de cada rodada intacto.
- `input_adapter_test` (ampliado): tap latch, buffer de 6 ticks com snapshot injetado, SOCD último-vence, histerese do touch — tudo via `sample_from_state`.
- `replay_checksum_golden_test`: `GOLDEN_RULES_VERSION` 3, `config_hash` das 6 rodadas, checksum inicial/final/serializado de uma rota por setor com diretor ativo.
- `boss_active_campaign_playthrough_test` (ampliado): rota autorada sem morte para **cada** rota do grafo; `boss_campaign_balance_test`: caps do diretor nunca excedidos em 5 000 ticks parados.
- `tools/profile_simulation_step.gd`: p95 de `step()` com 24 inimigos ≤ 300 µs; `palette_contrast_test`: novos pares no `PAIR_FLOOR`; `doc_freshness_header_test`: docs tocados.

## 13. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Pico de dificuldade injusto | warmup 30 ticks, raio seguro 16, tetos por tipo, teste de fairness; rota autorada sem morte por setor |
| Replays antigos invalidados | decisão explícita: um bump por fase, ADR-0010, dourados no mesmo commit |
| Ruído visual a 1 px/célula | 4 Fagulhas (não 8), silhuetas 3–5 px, piso 3:1 medido, olho humano antes de aprovar |
| Vigia presa em geometria estranha | regra de mão com `trás` como último recurso + teste de 3 000 ticks com capturas reais |
| Custo do tick | O(24) por tick, BFS só na captura (já existe), perfil headless com meta |
| Escopo | fases pequenas, `RULES_VERSION` só sobe nas fases 1 e 2 |
| Ergonomia do touch não verificável headless | contratos testados; QA físico listado como pendente no `TEST_MATRIX` |
| Calibração dos inteiros no papel | toda constante vive em `ThreatProfile`; fase 4 é playtest humano com ajuste sem código |

## 14. Fases de entrega

- **F0 — entrada (sem bump):** ADR-0012, latch, buffer, SOCD, touch, settings; testes do adaptador. PR pequeno.
- **F1 — elenco e diretor (`RULES_VERSION` 3):** `ThreatProfile`, `EnemyRoster`, Vigia/Eco/Fagulha, fases do Núcleo, encurralado, eventos, checksum, `QixEnemyView` do roster, cues; ADR-0010; dourados; rota R1 sem morte. Diretor em R1 com perfil mínimo para não mudar o "sentir" de entrada.
- **F2 — itens, escada e razões (`RULES_VERSION` 4):** Balizas, efeitos, `speedup`, `FLOOR`, escada de bônus, `SINGLE_CUT`, transição encenando a escada.
- **F3 — atlas (sem bump):** grafo, `SECTOR_CHOICE`, `sector_choice_view`, três setores novos (perfis, fundos, sprites), ADR-0011, `build_campaign_content.gd` com 6 `ROUND_SPECS`, rotas autoradas por caminho.
- **F4 — guardrail:** perfil de `step()`, contraste dos novos pares, playtest humano das seis folhas, calibração em `ThreatProfile`, `TEST_MATRIX`/`IMPLEMENTATION_STATUS`/`ART_DIRECTION`/`ASSET-PROVENANCE` atualizados, `LOOP_LEDGER` com os itens P3 reescritos.
- **F5 (opcional):** setor gêmeo com `anchors_split` e vitória `SEALED` (§5.5/§12.4).

## PARÂMETROS
MAX_ENEMY_SLOTS = 24 (Volfied percorre 22 ranhuras em $103000, §3.3 #12; 24 dá folga)
spawn_warmup_ticks = 30 (0,5 s de aviso visível antes de qualquer contato letal; DESIGN_DECISION de justiça)
spawn_safe_radius = 16 (Manhattan; nenhum spawn perto do jogador; DESIGN_DECISION)
max_active_ecos = 3, max_active_vigias = 4, max_fagulhas = 8 (tetos de legibilidade a 1 px/célula)
phase_thresholds_permille = [300, 550] (fases Latente/Desperto/Encurralado; DESIGN_DECISION)
phase_speed_permille = [1000, 1100, 1200] e phase_turn_ticks = [45, 36, 30] (os passos que hoje separam R1→R3, agora dentro da rodada; pico validado ≤ 256/subpasso)
boss_sense_cells = 48 (raio em que o Núcleo passa a mirar o meio da trilha; DESIGN_DECISION)
cornered_window_ticks = 60, cornered_reflections = 6, cornered_burst_ticks = 90 (estado emergente de fúria; DESIGN_DECISION)
eco_interval_ticks = [384, 336, 288, 240, 192, 144, 96, 72, 48, 36] (§10 enemy_rate_table: 384→48 em passos de 48, cauda encurtada)
eco_speed_fp = [85, 85, 85, 85, 85, 128, 128, 256, 256, 256] com eco_substeps = 1 (§10: 1 passo/3 frames → 1/2 → 1/1; a cauda $FF de 2 px/frame fica fora por legibilidade)
pressure_start_ticks = 3600 (§10: a escada começa ao expirar o limite; 12 144 frames lá, 60 s aqui porque as rodadas são mais curtas)
eco_kill_radius = 2 Manhattan (Volfied mata a 4 px, ACHADOS banda 02; reduzido para casar com o footprint de raio 1 do chefe)
eco_life_ticks = 900, eco_dying_ticks = 12 (DESIGN_DECISION)
fagulhas_per_cut = 4 (Volfied gera 8, ACHADOS banda 02; metade para não virar ruído a 1 px)
fagulha_step_every_ticks = 2, fagulha_life_ticks = 600 (0,5 célula/tick contra 2 do jogador: fechar escapa, hesitar morre)
vigia_step_every_ticks = [2, 2, 1] por fase, vigia_sense_cells = 40, vigia_reverse_on_meet = 1 (DESIGN_DECISION inspirada na patrulha de borda de Qix)
long_trail_px = 96 (acima do aviso do HUD em TrailExposure.WARNING_RATIO ≈ 67 células, teto 127; o aviso precede a punição)
long_trail_repeat_ticks = 120 (DESIGN_DECISION)
stall_trigger_ticks = 180, stall_repeat_ticks = 120 (§3.3 #8 player_stall_counter; limiar próprio)
big_capture_permille = 100 (10 % num corte semeia 2 Vigias nas pontas da nova fronteira; §12.5 espírito da captura grande)
small_capture_permille = 15, small_capture_streak_trigger = 4 (anti-tartaruga; DESIGN_DECISION)
enemy_chain_points = [500, 1000, 2000, 4000, 8000] (§7.3 dobra por elo; cortado no 5.º para a economia de 10 pts/‰)
item_slots ≤ 5 por rodada, active_item_slots = 3 (variação por seed; DESIGN_DECISION)
item_table = [FREEZE, TIMESTOP, SPEEDUP, FREEZE, KILLALL, SPEEDUP, FREEZE, NONE, TIMESTOP, FREEZE] (§11: distribuição com congelar comum e matar-tudo raro; índice = (slot + rng) mod 10)
speedup_ticks = 600 (§11 padrão 1 → §4.3 4 subpassos), timestop_ticks = 300 (§11 padrão 3, só o chefe), shield_freeze_ticks = 600 (§11 padrão 5 / §9), killall_spawn_block_ticks = 120 (§11 padrão 4)
shield_floor_ticks = 600 com shield_respawn_mode = FLOOR (§9 game_countdown_floor_3: 300 de 900 = 1/3 de 1800)
bonus_ladder_permille = [1000,1100,…,2000,2200,2400,2600,2800,3000,3500,4000,5000,10000], 100 % → 12000 (§12.6 escada 10→100 ×1000 escalada ÷10 para 10 pts/‰)
special_cut_permille = 300, special_cut_multiplier = 5 (§12.5 razão 3: 80 % num único preenchimento; ×5 em vez de 1 000 000 para caber na economia)
no_death_bonus_permille = 250 (DESIGN_DECISION)
turn_buffer_ticks = 6 (100 ms de buffer de curva no adaptador; DESIGN_DECISION)
touch_angle_hysteresis = 0.42/0.28 do raio (mesma histerese do stick analógico já em GameInputAdapter)
step_p95_budget_usec = 300 (meta de tools/profile_simulation_step.gd com 24 inimigos)

## RISCOS
Pico de dificuldade injusto quando vários gatilhos disparam juntos (trilha longa + fase + escada): mitigado por tetos por tipo, warmup de 30 ticks, raio seguro de 16 células, teste de fairness e rota autorada sem morte por setor.
Invalidação de replays existentes: é decisão deliberada, um bump de RULES_VERSION por fase de domínio com ADR-0010 e dourados atualizados no mesmo commit; sem isso o invariante 7 vira carimbo.
Ruído visual a 1 px por célula com até 24 atores: 4 Fagulhas em vez de 8, silhuetas de 3–5 px, `vigia_color` com piso 3:1 sobre BOUNDARY no `PAIR_FLOOR`, e aprovação humana em tela antes de fechar a fase 4.
Vigia presa ou oscilando em geometrias de fronteira complexas (T duplos, corredores de 1 célula): regra de mão com `trás` como último recurso e teste de 3 000 ticks com capturas reais em 3 seeds.
Custo do tick com roster cheio em GDScript: O(24) por tick e BFS só na captura; `tools/profile_simulation_step.gd` fixa p95 ≤ 300 µs e falha o gate se estourar.
Escopo grande demais para a fila do loop de agentes: fases pequenas, arquivos de teste novos por tema, `RULES_VERSION` só sobe em F1 e F2, e o `LOOP_LEDGER` recebe os itens antes de qualquer PR.
Ergonomia de touch/latência real não verificável headless: contratos testados via `sample_from_state`; QA físico permanece listado como NOT_EXERCISED no `TEST_MATRIX`.
Calibração dos inteiros feita no papel: toda constante vive em `ThreatProfile` autorável, então o playtest humano da fase 4 ajusta sem mudar código — mas cada ajuste é um bump de contrato e precisa de dourado novo.
