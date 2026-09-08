# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-08 · commit `ca74578` · Godot 4.7.2-stable, Linux headless
> **Alcance:** nesta passagem (2026-09-08T02:01Z) reverifiquei **só a topologia da fila e o verde
> das duas árvores**: contagem de PRs abertos (30), quais estão contidos no ramo do #78,
> `run_tests.gd` e `verify_m2_capture_route.gd` em `main` (`ca74578`) e no head do #78
> (`3c9724f`), e o merge de teste dos 10 ramos de fora. Evidência em
> `docs/loop/runs/2026-09-08T020126Z.md`. **O resto deste documento é de 2026-09-06** (commit
> `34634d0`, conferido depois da mescla do #55, que integrou #20–#54) e **não** foi reconferido
> item a item — em particular, o backlog abaixo lista como livres itens que hoje têm PR aberto;
> confira a fila antes de escolher. Mérito visual, áudio físico e Android real continuam sem
> validação nesta sessão.


Um agente de nuvem roda de hora em hora e **começa sem contexto**. Este arquivo é a única
memória que atravessa execuções. Sem ele, a run nº 7 desfaz a nº 3 sem saber que ela existiu.

## Protocolo (obrigatório)

1. **Leia este arquivo inteiro antes de decidir o que fazer.** Ele vem depois do `CLAUDE.md` e
   antes de qualquer edição.
2. **Liste os PRs abertos do loop antes de escolher.** Um item com PR aberto não está livre.
   Consulte o estado atual no GitHub. Use `tools/loop/unclaimed_surface.sh` antes de escolher
   (heurística por refs e camada) e `tools/loop/merge_queue_report.sh` depois de escolher.
   Refs de branches não provam, sozinhos, que os respectivos PRs continuam abertos.
3. **Escolha exatamente UM item** — o de maior prioridade que caiba num PR pequeno e revisável.
   Um PR grande não é produtividade: é uma revisão que não vai acontecer.
4. **Escreva o relato em `docs/loop/runs/<carimbo>.md`** — arquivo novo, seu. Não apense a uma
   tabela de histórico: era ali que toda execução escrevia na mesma linha, e por isso os 78 pares
   de PRs colidiam. Ver `docs/loop/runs/README.md`.
5. **Ajuste o backlog deste arquivo no mesmo PR.** O backlog continua compartilhado de propósito:
   duas execuções que mexem no mesmo item *devem* se encontrar aqui.
6. **Nunca reabra um item de "Decisões fechadas"** sem argumento novo e explícito no PR. Essa
   seção existe para impedir que o loop oscile entre duas opções para sempre.
7. **Meta-PR tem teto.** Um PR sobre a fila só é legítimo se trouxer uma medição ainda ausente
   nos meta-PRs abertos e nomear quais supera. Sem evidência nova, registre o achado no relato
   da execução, sem abrir outro PR redundante. Origem: #53 e o censo de posse de 2026-09-06.
   O limite operacional é dois PRs do loop em andamento; com o limite atingido, priorize revisão
   e correção dos existentes, não a geração de uma nova mudança sobre os mesmos arquivos.

### Legenda do backlog (convenção de #34)

| Marca | Significado |
|---|---|
| `- [ ]` | Livre. Nenhum PR aberto o reivindica. |
| `- [~]` | **Reivindicado por um PR aberto.** Não escolha: o trabalho existe, só não mesclou. |
| `- [x]` | Entregue e mesclado em `main`. |

Quem drena a fila troca por `[x]` os `[~]` que mesclaram. Um `[~]` cujo PR foi fechado sem
mesclar volta a `[ ]`, com uma linha dizendo por quê.

### Ao resolver conflito de documentação

Mantenha a linha `> **Verificado em**` de cada doc — `tests/unit/doc_freshness_header_test.gd`
recusa doc sem cabeçalho. E **não resolva este arquivo por união automática**: o resultado passa
nos testes e mente para o leitor. A integração de 23:00Z produziu 703 linhas com cinco seções de
"estado da fila" contraditórias e três ordens de merge concorrentes. Backlog reconcilia-se à mão.

## Decisões fechadas — não reabrir sem argumento novo

| Decisão | Onde |
|---|---|
| Território é `PackedByteArray` em `BoardState` | `docs/decisions/ADR-0001` |
| Renderer é GL Compatibility | `docs/decisions/ADR-0002` |
| Linguagem é GDScript tipado | `docs/decisions/ADR-0003` |
| Fronteiras de campanha/sessão | `docs/decisions/ADR-0004` |
| Revelação por máscara R8 | `docs/decisions/ADR-0005` |
| Fronteira entrada/feedback | `docs/decisions/ADR-0006` |
| Perfis de boss autoráveis | `docs/decisions/ADR-0007` |
| Transação de conteúdo | `docs/decisions/ADR-0008` |
| Contador de percentagem sobe em degraus | `docs/decisions/ADR-0009` |
| `addons/` só hospeda pasta com estado declarado | `docs/decisions/ADR-0010` |
| A ameaça tem contorno que não depende de cor | `docs/decisions/ADR-0011` |
| Identidade visual é *Lumen Cartography* | `docs/ART_DIRECTION.md` |
| Volfied é referência de gênero, não alvo de clone | `reference/volfied/README.md` |
| Histórico do loop é um arquivo por execução | `docs/loop/runs/README.md` |
| `samples/` e `guide_examples/` podados; `exclude_filter` fica | `docs/loop/runs/`, poda dos demos |
| `antipixel_state_machine/` podado | `docs/loop/runs/2026-09-05T035826Z.md` |

## Backlog — prioridade decrescente

Cada item diz **o que**, **por que importa para a experiência** e **como saber que ficou bom**.
Itens sem critério de pronto não entram aqui.

> **O backlog herdado acabou** com os PRs #1–#18. Tudo abaixo **nasceu das próprias execuções** —
> é dívida que só ficou visível depois que o trabalho foi feito. Confira a fila antes de escolher.

### P0 — a fila e a cadência (nada abaixo importa enquanto isto não anda)

- [x] **Drenar a fila de PRs abertos.** ✅ **Cumprido em 2026-09-06T19:42Z.** `main` está em
      `34634d0` (mescla do #55, que integrou #20–#54) e a fila está em **0 PRs abertos** — os dois
      critérios de pronto, `main` além de `cba520a` e fila ≤ 2, medidos contra o GitHub, não
      inferidos. O caminho foi: #51 integrou #20–#50 à mão; #52–#54 chegaram depois; o #55 reuniu
      tudo preservando os pais de merge e a resolução #25×#50. O #19 drenou os 18 primeiros; o #36
      (16 PRs) e o #42 (22 PRs) nasceram e envelheceram na própria fila sem serem mesclados.
      *Pronto (era):* `main` além de `cba520a` e a fila em ≤ 2 PRs abertos.

      **⚠️ Este parágrafo caducou em horas — leia a nota de 2026-09-08 abaixo antes de agir nele.**
      Dizia que a fila estava vazia e que se podia escolher qualquer item sem colidir. Em
      2026-09-08T02:01Z a fila está em **30 PRs abertos** e quase todo item deste backlog tem dono.

      **A fila de 30 é um merge e três restos, não trinta integrações.** Medido em
      `docs/loop/runs/2026-09-08T020126Z.md`, com a suíte corrida, não por nomes de arquivo:
      o ramo do **#78** (`ai/loop-20260907T140000Z`) é ***fast-forward* de `main`** (`main` é
      ancestral dele, 0 commits do lado de `main`), **já contém 20 dos 30 PRs abertos** — cinco
      deles abertos *depois* do #78 — e está **verde**: 309 testes / 14838 asserções / 0 falhas, e
      `verify_m2_capture_route.gd` com `errors: []` em 17,9 → 82,5 %. Linha de base em `main`:
      262 testes / 12719 asserções / 0 falhas. Dos 10 PRs de fora, **sete não acrescentam um único
      arquivo fora de `docs/`**; só #67 (`addons_manifest_test.gd`), #74 e #83 (`.gitignore`,
      `verificacao.yml`) trazem código. Todo conflito medido é de escrituração.

      **Isto supera o achado do #80** ("o #78 fica vermelho contra o #79"): contra o head de hoje o
      #79 mescla limpo e a suíte fica verde — o código do #79 já está dentro do #78. O #80 mediu um
      head anterior.

      *Próximo ato, e é humano:* mesclar o #78. Enquanto ele não mesclar, #61, #65, #75 e #81 —
      toda a camada de experiência entregue nesta fila — continuam invisíveis para o jogador.

      **O #48 e o #50 pediram que não se abrisse outra integração — "o gargalo é a mão humana,
      não a medição". Estavam certos quanto ao gargalo e errados quanto ao custo de não medir.**
      Esta integração encontrou o que nenhuma medição de fila por nomes de arquivo podia
      encontrar: **#25 e #50 são incompatíveis em código.** O #25 tirou `transition_progress()` de
      `GameSession` (devolvia `float`, invariante 1) e mudou a chamada para um helper da view; o
      #50 acrescentou `_apply_cadence` chamando `session.transition_progress()` — o método que já
      não existe — e o mesmo em `tests/unit/round_transition_cadence_test.gd:117`. Mesclados em
      qualquer ordem, sem esta resolução, a suíte fica **vermelha** com
      `Nonexistent function 'transition_progress'`. Resolvido aqui alimentando a cadência do #50
      com o helper do #25. **Lição para o protocolo:** relatório de fila que cruza *nomes de
      arquivo* não vê conflito semântico entre um PR que remove uma API e outro que a chama —
      só a integração de facto vê. Enquanto a fila passar de ~10, vale reintegrar e medir.

- [ ] **A cadência do loop excede a cadência de revisão, e isso é problema de projeto, não de
      execução.** Medido quatro vezes (#31, #36, #40 e esta run): o loop produz 1 PR/h e a revisão
      humana é episódica. Entre 2026-09-05T02:57Z e 2026-09-06T04:56Z a fila foi de 0 a 22 sem que
      `main` andasse; dessas 22 execuções, **cinco** (#30, #31, #34, #36, #40) gastaram a hora
      inteira medindo ou consertando a própria fila em vez de tocar no jogo — ~23 % do esforço
      consumido pelo mecanismo. Enquanto o gargalo for este, nenhuma melhoria de estética chega ao
      jogador. → Opções a avaliar por escrito, sem escolher por conta própria: baixar a frequência
      do agendamento; deixar o loop empilhar commits numa branch de longa duração e abrir **um** PR
      por dia; ou automatizar a integração (o que esta execução fez à mão).
      *Pronto:* uma ADR curta com a política escolhida, e o agendamento ajustado para ela.

      **Continua aberto, e a drenagem de 19:42Z não o resolveu — só zerou o contador.** Custo
      final desta fila, para dimensionar a ADR: 35 PRs (#20–#54) abertos em ~44 h, drenados por
      **quatro** esforços de integração (#36 e #42 morreram na fila; #51 e #55 mesclaram). Sem
      mudança de política, a fila volta a crescer 1 PR/h a partir de agora. Esta é a janela boa
      para escrever a ADR: é a primeira vez que ela pode ser escrita sem competir com a fila que
      descreve.

- [ ] **Dois relatórios de fila onde deve haver um.** `tools/loop/merge_order_report.sh` (#31) e
      `tools/loop/merge_queue_report.sh` (#30) respondem à mesma pergunta e já divergiram na
      contagem. Achado de #31, reconfirmado aqui: os dois existem lado a lado na árvore integrada.
      → Fundir num só, com a contagem correta (a de #30, que exclui PRs já mesclados).
      *Pronto:* um único script em `tools/loop/`, e o protocolo acima apontando para ele.

### P1 — higiene estrutural

- [ ] **Executar as sete remoções decididas na ADR-0010 — uma pasta por PR.** A decisão está
      tomada e a guarda existe (`tests/unit/addons_manifest_test.gd`), mas as sete pastas
      continuam em disco: `GDDraw`, `curve2collision`, `curved_lines_2d`, `guide`,
      `phantom_camera`, `softbody2d`, `yard`. A ADR exige, por remoção, a mesma evidência de posse
      de `uid://` usada na poda dos demos. **Item ideal para uma execução curta** — pequeno,
      mecânico e sete vezes repetível, sem disputar arquivo com ninguém.
      *Pronto:* cada pasta marcada `a-remover` no manifesto saiu, uma por PR, com a evidência no
      corpo.

- [ ] **`docs/TEST_MATRIX.md` está devendo linhas — dívida acumulada de várias execuções.** #21
      reconciliou a matriz à mão contra 174 testes, mas #24, #25, #26, #29, #32, #33, #35, #37,
      #38, #39 e #41 acrescentaram testes depois. A árvore integrada roda **232 testes / 12534
      asserções**. → Reconciliar de novo e, de preferência, atacar a causa: a matriz é contagem
      escrita à mão sobre um runner que varre diretório.
      *Pronto:* a matriz bate com a saída de `run_tests.gd`, ou a contagem é gerada, não digitada.

### P2 — integridade de contexto

- [x] **`session.records` só é preenchido pela via PLAYING→vitória/derrota.** ✅ entregue pelo #49
      (`ai/loop-20260906T115826Z`), integrado aqui: o contrato foi para o cabeçalho de
      `GameSession` e `tests/unit/session_records_contract_test.gd` defende as cinco regras
      (fica vazio até uma rodada acabar de facto; forçar a fase de fora não arquiva nada; ticks
      extras na fase terminal não acrescentam um segundo registro; rodada perdida arquiva com
      `completed false`; o tamanho conta tentativas terminadas, não rodadas visitadas). Verde
      nesta árvore.

- [ ] **O speed-up do jogador está autorado, validado, hasheado — e não existe.** Achado do #47
      (`ai/loop-20260906T100242Z`), integrado aqui já **medido e cercado** por
      `tests/unit/speedup_rules_inert_test.gd`: `GameSimulation.speedup_active` não tem produtor
      (nada lhe escreve `true`) e `MoveIntent` não tem bit de "rápido", então `substeps_speedup`
      (4) e `new_segment_slow_px` (8) nunca são lidos. Variá-los muda o `config_hash` de replay e
      **não muda um único tick** — a tabela está em `docs/loop/runs/2026-09-06T100242Z.md`. O que
      falta é **decisão de design**, que o loop não pode tomar porque não vê nem joga: o jogo tem
      speed-up ou não? *Pronto:* ou existe produtor e teste de comportamento, ou as duas regras
      saem de `GameRules` (o que **invalida replays**, invariante 7 — é ADR, não commit).

- [ ] **`QixAudioDirector.sync` trata música e vozes com guardas diferentes.** Sobra do #46
      (`ai/loop-20260906T085912Z`), que fez a pausa alcançar as oito vozes de SFX — antes ela
      parava só a música e o `death`/`game_over` terminava por cima do campo congelado. As vozes
      passaram a ser comandadas sempre; a música continua atrás de `is_inside_tree()`. No runtime
      real os dois caminhos coincidem, por isso não foi mexido. No mesmo saco: `shutdown()` não
      zera `_paused_voices`. *Pronto:* uma só regra de guarda para música e vozes, com
      `audio_pause_test.gd` a continuar verde.

- [ ] **`game/enemies/boss_behavior_controller.gd` é domínio fora do alcance da guarda.** Achado
      de #36: `domain_purity_test.gd` varre `game/simulation/`, `game/rules/` e `game/session/`,
      mas o controlador do boss é domínio morando em `game/enemies/`, pasta que o invariante 6
      trata como apresentação. Ou o arquivo muda de pasta, ou a varredura passa a conhecê-lo pelo
      nome. *Pronto:* o arquivo está sob uma das duas guardas, e o `CLAUDE.md` diz qual.

- [ ] **`round_visual_definition.gd` é o próximo atrito previsível da guarda de valor real.**
      Achado de #25: é `Resource` de `game/rules/` com campos de cor, e cor é `float` por
      construção. Hoje passa por exceção nomeada na guarda. *Pronto:* ou a exceção está escrita
      onde a guarda é enunciada, ou o visual sai de `game/rules/`.

- [ ] **A guarda de frescor prova presença de cabeçalho, não veracidade do conteúdo.**
      `doc_freshness_header_test.gd` (#6) exige a linha `> **Verificado em**` e fica verde com ela
      presente — mesmo quando o corpo mente. #21 corrigiu `TEST_MATRIX.md`, que afirmava quatro
      contagens concorrentes e passava em tudo; **os demais docs que passaram pela mesma união
      automática não foram auditados**. → (a) auditar os outros documentos contra o código
      integrado; (b) decidir se alguma guarda barata pega contradição interna (ex.: recusar duas
      linhas de tabela com a mesma primeira coluna). *Pronto:* nenhum doc de `docs/` com duas
      afirmações concorrentes sobre o mesmo fato, e a decisão sobre (b) escrita.

### P3 — experiência e estética (o alvo real)

**Entregues nesta fila** — evidência no código integrado, não na prosa do PR: envelope de áudio
por cue (#23, `audio_envelope_test.gd`), contorno de tinta da ameaça (#32, ADR-0011,
`enemy_silhouette_contrast_test.gd`), contraste do cursor medido (#28, `cursor_contrast_test.gd`),
score encenado pelo caminho da área (#27, `game_hud_score_counter_test.gd`), háptica da exposição
(#39, `exposure_haptics_test.gd`), âncora do stick de toque (#33, `touch_stick_anchor_test.gd`),
proa do cursor (#35, `player_view_facing_test.gd`), foco da floritura de captura (#37,
`capture_vfx_focus_test.gd`), trava de eixo analógico (#38, `analog_axis_lock_test.gd`) e fase do
pulso da trilha (#41, `board_pulse_phase_test.gd`).

O que continua aberto:

- [ ] **[requer sessão humana] `BOUNDARY`×`TRAIL` a 1,04:1 — a decisão mais cara do jogo no canal mais frágil.**
      Atravessou as 22 execuções sem dono. A medição de #7 (`docs/ART_DIRECTION.md`, "Contraste
      medido") mostra contorno e trilha com a mesma luminância nas quatro paletas; "estou
      protegido" × "estou desenhando" depende de matiz mais o glint/pulso do shader. Caminhos:
      baixar a luminância de `BOUNDARY`, subir a de `TRAIL`, ou dar ao contorno trama espacial
      mais grossa que sobreviva a 1 px.
      *Pronto:* par acima de 3:1 nas quatro paletas, `PAIR_FLOOR`/`KNOWN_DEBT` e a seção de
      `ART_DIRECTION` reescritos no mesmo commit, e alguém confirmou por captura que o campo não
      ficou lavado. **É o maior item de estética livre do backlog.**

- [ ] **Escolher de onde o cursor tira sua cor.** #28 mediu e provou o problema, mas parou na
      medição. Hoje `QixPlayerView.sync` empresta as três camadas da paleta do campo
      (`boundary_color`, `accent_color`, `trail_hot_color`), e é isso que trava
      `CURSOR_OUTER`×`BOUNDARY` em 1,00:1 para qualquer paleta que alguém autore — com o núcleo em
      1,04–1,12:1, ou seja, nem o centro do cursor separa. Sobre `FREE` as três camadas passam com
      folga (5,4:1 no pior caso), e é isso que restringe o conserto: a candidata precisa subir os
      três `CURSOR_*`×`BOUNDARY` acima de 3:1 **sem** derrubar os `CURSOR_*`×`FREE`, e os dois
      chãos estão em extremos opostos da luminância. Ou a cor fica no meio, ou a silhueta ganha
      borda escura própria que não venha da paleta do campo.
      *Pronto:* os três pares acima de 3:1 nas quatro paletas, com `CURSOR_FLOOR`,
      `CURSOR_KNOWN_DEBT` e a seção de `ART_DIRECTION` reescritos no mesmo commit, e alguém
      confirmou por captura que o cursor não virou um borrão claro sobre o campo.

- [ ] **O canal sonoro da exposição não foi feito.** O item original pedia som **e** háptica ao
      cruzar `TrailExposure.WARNING_RATIO`; #39 entregou só a háptica (`app/haptic_feedback.gd`).
      Falta o cue que suba com a exposição, com prioridade declarada entre vozes — o envelope por
      cue de #23 já dá a ferramenta. *Pronto:* cruzar o limiar é audível, com prioridade
      declarada, **sem alterar checksum**.

- [ ] **`docs/ART_DIRECTION.md` não registra duas decisões visuais já tomadas.** Medido na árvore
      integrada: **zero** ocorrências de `ADR-0011` no documento de arte, embora a ADR decida um
      traço visual da ameaça; e a floritura de captura de #37 também não está escrita lá. Quem lê
      só o documento de arte não encontra nenhuma das duas.
      *Pronto:* as duas decisões referenciadas na seção que lhes corresponde.

- [x] **O tempo da transição entre rodadas não tem ritmo.** ✅ entregue pelo #50
      (`ai/loop-20260906T130328Z`), integrado aqui **com resolução de conflito**: o painel abre em
      ordem de leitura (`_apply_cadence` revela subtítulo → resultado → continuidade → prompt por
      limiares de progresso) e a continuidade entra com uma batida que **decai** em vez de piscar
      (`_beat`, pela mesma razão do ADR-0009: um degrau de um frame é ruído a 60 Hz).
      A cadência é alimentada pelo helper `_transition_progress(session)` da própria view, não por
      `session.transition_progress()` como o #50 escrevia — ver o P0 acima. Invariante 6 defendido
      por `round_transition_cadence_test.gd`: percorre a intro inteira e prova que checksum e
      replay não mexem. **Falta o julgamento estético:** ninguém viu a passagem numa tela.

- [x] **Geometria real do HUD.** ✅ mesclado em `main` pelo #55 (via #52): confirmado que
      `tools/verify_hud_row_geometry.gd` existe na árvore. A sonda mede a construção durante
      frames, não só as constantes no `_initialize()` do runner; o teste horizontal e os
      comentários corrigidos também foram preservados, e a sonda faz parte do CI.
      **Aprovação estética continua humana.**

- [ ] **[requer sessão humana] Calibrar a curva de exposição.** `TrailExposure` usa piso 8 px (o mesmo
      `new_segment_slow_px` do domínio) e teto geométrico `(w+h)/4` = 127 px no campo de produção.
      Justificáveis no papel, nunca vistos em jogo.
- [ ] **Confirmar o ritmo do pulso da trilha.** #41 consertou a matemática da fase; o efeito
      percebido continua por ver.
- [ ] **Confirmar o anel de tinta da ameaça (ADR-0011, #32) numa tela.**
- [ ] **Calibrar `ANALOG_AXIS_SWITCH_MARGIN` com um polegar de verdade** (#38).
- [ ] **Calibrar a âncora flutuante do stick de toque com um polegar de verdade** (#33).
- [ ] **Confirmar o piso de 24 px do foco da captura** (#37) e se a proa do cursor (#35) aponta
      para onde o jogador espera.

## Notas de ambiente (sandbox de nuvem)

Verificado em 2026-09-06: o build Linux headless `4.7.2-stable` baixa sem bloqueio de rede e
reporta `4.7.2.stable.official.ed1daf0bf`. O `--import` obrigatório roda até o fim e **não** exige
mono. Suíte completa (232 testes) em ~6 s; `verify_m2_capture_route.gd` e `profile_board_view.gd`
em segundos. Nesta sessão não há desculpa para PR sem verificação — se uma execução não rodou os
comandos, o motivo tem que ser dito, não omitido.

Ruído esperado, **não** regressão — não gaste uma execução investigando:

- `ERROR: Can't open dynamic library ... libfennara.linux.editor.x86_64.so` seguido de
  `Error loading extension` aparece em **toda** execução headless, inclusive em `main` sem
  alteração. `addons/fennara/bin/` não é versionado (e não deve ser). A suíte passa apesar do erro.
- `[godot_ai game_helper] registered mcp capture` ao final de todo script headless é o autoload de
  ferramental. Não é erro.
- `--import` é obrigatório **também depois de cada troca de branch** que traga script novo, senão
  o cache de `class_name` não conhece a classe e a falha não é a sua mudança.
- **Medir X no runtime do runner é fiável; medir Y não é.** Tudo corre dentro de `_initialize()`,
  antes de a árvore processar um frame, e a altura de um `Label` fica presa a um mínimo obsoleto
  (23 px). Depois do primeiro frame assenta no valor pedido. O comentário `# evita os 23 px padrão`
  em `_add_label` está correto no runtime real; não o "corrija" pelo que o runner mostra.
- **A descoberta de testes em `run_tests.gd` varre diretório.** Dois PRs podem acrescentar arquivos
  de teste sem se tocarem — foi o que permitiu #3 e #5 coexistirem. Prefira arquivo novo a edição
  em arquivo disputado.
- **`exclude_filter` de `guide_examples/**` e `samples/**` fica em `export_presets.cfg` mesmo com
  as pastas podadas.** Um checkout que rebaixe os addons pela AssetLib recria as pastas em disco, e
  o filtro cobre um caminho que o `.gitignore` não cobre. Não "limpe" isso.
- **Integrar a fila é barato; reconciliar o ledger não.** Medido em 04:57Z: os 22 merges de
  #20–#41 produziram **zero** conflitos de código — o único arquivo conflitante, em 20 dos 22, é
  `docs/LOOP_LEDGER.md`. O custo real da drenagem é reescrever o backlog à mão, porque `--ours`
  descarta a entrada de ledger de cada PR e a união automática mente.
- **…mas "zero conflitos de código" não é "zero incompatibilidades".** Corrigido em 14:00Z ao
  integrar #42+#43–#50: dos 8 merges, 7 conflitaram só no ledger, 1 (#44) também em
  `docs/TEST_MATRIX.md`, e o #50 conflitou em `ui/round_transition_view.gd` — mas a incompatibilidade
  cara **não deu conflito nenhum**: o #50 chama `session.transition_progress()` num arquivo de
  teste que o #25 nunca tocou, e o #25 removeu esse método. `git merge` fica verde e a suíte fica
  vermelha. Duas conclusões: (a) só a suíte corrida sobre a árvore integrada prova que a fila
  mescla; (b) um PR que **remove** um símbolo público conflita silenciosamente com todo PR aberto
  que o use — ao remover, `grep` o símbolo nos ramos abertos, não só na árvore.

## Histórico

O histórico é **um arquivo por execução** em [`docs/loop/runs/`](loop/runs/README.md). O `ls` do
diretório é o índice — os nomes são carimbos ISO. Não há tabela aqui, e isso é de propósito: uma
tabela reconstruiria o ponto único onde toda execução escreve na mesma linha.

```bash
ls docs/loop/runs/                     # da mais antiga para a mais recente
grep -rl "BoardView" docs/loop/runs/   # quais execuções já mexeram nisso
```

Medições de fila que valem como referência, fora do formato por execução:
`docs/loop/2026-09-04-fila-verificada.md` (ordem de merge, causa de `#8×#11`) e
`docs/loop/2026-09-04-fila-destravada.md` (o patch aplicado e medido).
