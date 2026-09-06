# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-06 · commit `cba520a` · Godot 4.7.2-stable, Linux headless
> **Alcance:** reconciliado à mão sobre a integração dos 22 PRs abertos do loop (#20–#41) sobre
> `cba520a` — a árvore medida é a integração, não `main` sozinho —, medida
> verde (232 testes, 12534 asserções, 0 falhas; rota M2 179→825‰ com `errors: []`; perfil de
> `BoardView` p95 = 2 µs). Cada item abaixo foi reconferido contra o **código integrado**, não
> contra a prosa do PR que o reivindicou. O mérito estético continua **não** julgado: o jogo não
> pode ser jogado nem visto num sandbox headless.

Um agente de nuvem roda de hora em hora e **começa sem contexto**. Este arquivo é a única
memória que atravessa execuções. Sem ele, a run nº 7 desfaz a nº 3 sem saber que ela existiu.

## Protocolo (obrigatório)

1. **Leia este arquivo inteiro antes de decidir o que fazer.** Ele vem depois do `CLAUDE.md` e
   antes de qualquer edição.
2. **Liste os PRs abertos do loop antes de escolher.** Um item com PR aberto **não está livre**,
   mesmo com o checkbox vazio: o backlog só reflete o que chegou a `main`. Use
   `tools/loop/merge_queue_report.sh` — ele diz, além disso, em que arquivos a sua mudança vai
   colidir em silêncio com a fila. Foi por não olhar a fila que o par `#8×#11` nasceu.
3. **Escolha exatamente UM item** — o de maior prioridade que caiba num PR pequeno e revisável.
   Um PR grande não é produtividade: é uma revisão que não vai acontecer.
4. **Escreva o relato em `docs/loop/runs/<carimbo>.md`** — arquivo novo, seu. Não apense a uma
   tabela de histórico: era ali que toda execução escrevia na mesma linha, e por isso os 78 pares
   de PRs colidiam. Ver `docs/loop/runs/README.md`.
5. **Ajuste o backlog deste arquivo no mesmo PR.** O backlog continua compartilhado de propósito:
   duas execuções que mexem no mesmo item *devem* se encontrar aqui.
6. **Nunca reabra um item de "Decisões fechadas"** sem argumento novo e explícito no PR. Essa
   seção existe para impedir que o loop oscile entre duas opções para sempre.

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

- [~] **Drenar a fila de PRs abertos — terceira vez.** Reivindicado pelo PR desta execução
      (`ai/loop-20260906T045700Z`), que integra #20–#41 numa branch só, com o ledger reconciliado
      à mão e medida verde. O #19 drenou os 18 primeiros; a fila voltou a 22 em 30 h. Só um humano
      mescla, e o loop não mescla o próprio PR.
      *Pronto:* `main` além de `cba520a` e a fila em ≤ 2 PRs abertos.

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

- [ ] **`session.records` só é preenchido pela via PLAYING→vitória/derrota.** Forçar
      `phase = ROUND_CLEAR` num teste não arquiva a rodada — correto, mas não óbvio: custou uma
      asserção errada na execução de 19:00Z. Qualquer apresentação que conte rodadas depende disso.
      → Documentar a regra no cabeçalho de `GameSession`. *Pronto:* o contrato de `records`
      legível sem ler `_archive_current_round`. **Livre** — três execuções o listaram e nenhum dos
      22 PRs o tocou.

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

- [ ] **`BOUNDARY`×`TRAIL` a 1,04:1 — a decisão mais cara do jogo no canal mais frágil.**
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

- [ ] **O tempo da transição entre rodadas não tem ritmo.** #15 fez a passagem carregar score,
      vidas e o próximo setor, mas a barra de progresso é linear em ticks e nada enfatiza o
      instante em que o número de continuidade aparece. É animação de apresentação, não texto.
      *Pronto:* a passagem tem um acento perceptível no momento da continuidade, sem tocar domínio.
      **Livre** — nenhum dos 22 PRs tocou `ui/round_transition_view.gd`.

- [ ] **A geometria do HUD depende da ordem de construção.** `_add_label` só obtém o retângulo
      pedido porque atribui `size` depois de entrar na árvore; antes do primeiro frame o mínimo do
      `Label` ainda é o do tema (23 px). Funciona, mas é frágil e invisível. → Avaliar
      `custom_minimum_size` explícito ou um `Theme` do HUD com tamanho de fonte definido, para que
      a altura não dependa de quando `_ready` corre. *Pronto:* altura correta medida dentro do
      runner, sem a ressalva que `game_hud_layout_test.gd` documenta hoje.

### P4 — a dívida que só um humano com o jogo aberto pode pagar

Seis itens acumulados. **Nenhuma execução headless pode fechá-los** — estão aqui para não se
perderem, não para serem escolhidos. Uma sessão de jogo de vinte minutos fecha os seis de uma vez.

- [ ] **Calibrar a curva de exposição.** `TrailExposure` usa piso 8 px (o mesmo
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
- **Integrar a fila é barato; reconciliar o ledger não.** Medido nesta execução: os 22 merges de
  #20–#41 produziram **zero** conflitos de código — o único arquivo conflitante, em 20 dos 22, é
  `docs/LOOP_LEDGER.md`. O custo real da drenagem é reescrever o backlog à mão, porque `--ours`
  descarta a entrada de ledger de cada PR e a união automática mente.

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
