# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-07 · commit `34634d0` · Godot 4.7.2-stable, Linux headless
> **Alcance:** integração de facto dos **22** PRs abertos (#56–#77) numa branch só, com as
> resoluções à mão e a suíte corrida sobre a árvore acumulada — **288 testes, 14 087 asserções,
> 0 falhas**, contra 262/12 719 na base. `verify_m2_capture_route.gd` (825‰), `profile_board_view.gd`
> (R8 p50/p95 1/1 µs) e `verify_palette_contrast.gd` (catraca verde) reexecutados aqui.
> Relato completo em `docs/loop/runs/2026-09-07T140000Z.md`. Registros anteriores são históricos,
> não contagens atuais. **Nenhum mérito estético foi validado**: esta sessão não vê nem joga o jogo.

> **Estado da fila:** a fila #56–#77 foi integrada pelo PR desta execução
> (`ai/loop-20260907T140000Z`). Enquanto ele não mesclar, os 22 continuam **abertos** — o `[~]` do
> backlog abaixo reflete "reivindicado por esse PR", não "já em `main`". Consulte a fila real no
> GitHub antes de escolher: refs de branch não provam que os PRs continuam abertos.

> **O gargalo, medido pela sexta vez.** #31, #36, #40, a run de 14:00Z de 06-09, o #76 e esta.
> Entre o merge do #55 e agora, `main` **não andou** e a fila foi de 0 a 22 em ~19 h. As sete
> remoções da ADR-0010 estavam entre elas, feitas uma por PR como a ADR pediu — e sete PRs
> corretos, abertos em paralelo, produziram seis conflitos e cinco `.gitignore` incompletos.
> **A cadência é o problema de projeto que o P0 abaixo descreve, e ele continua sem ADR.**

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
| O cursor tem contorno de tinta próprio, não emprestado da paleta | `docs/decisions/ADR-0012` |
| O cursor tem contorno que não depende de cor | `docs/decisions/ADR-0012` |
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

- [~] **Drenar a fila de PRs abertos — a integração que cobre a fila inteira.** Reivindicado pelo
      PR desta execução (`ai/loop-20260907T140000Z`), que integra os **22** abertos (#56–#77) numa
      branch só, com nove resoluções à mão e a suíte verde sobre a árvore final (**288 / 14 087 /
      0 falhas**, contra 262 / 12 719 na base). O #19 drenou 18; o #55 drenou 35; esta drena 22.
      A fila reforma-se em ~19 h, todas as vezes.
      *Pronto:* `main` além de `34634d0` e a fila em ≤ 2 PRs abertos.

      **Lição desta drenagem, que se soma à do #25×#50 (merge verde, suíte vermelha):** uma guarda
      *derivada* pode ficar vermelha no estado que a decisão pediu. O #67 amarrou ao disco o fecho
      da tabela de `addons/`, mas só previu o plural — executadas as sete remoções, a guarda
      recusava zero pastas condenadas, e a segunda asserção (`not doomed.is_empty() or …`) proibia
      por construção a chegada da ADR-0010. Corrigido aqui com o caso zero, sem afrouxar. Ao
      escrever guarda derivada, **inclua o estado final da decisão que ela guarda** — senão o
      último PR da série paga a conta, e o custo aparece só na integração.

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

      **Sexta medição, 2026-09-07T14:00Z: a fila voltou a 22 em ~19 h** (#56–#77) sem que `main`
      andasse, contra o teto de dois do protocolo. E desta vez o custo não foi só a espera: as sete
      remoções da ADR-0010, feitas **exatamente como a ADR mandou** (uma pasta por PR), colidiram
      seis vezes entre si e deixaram cinco `.gitignore` incompletos, porque nenhuma podia ver as
      outras. **Um protocolo que manda serializar e um agendamento que produz em paralelo estão em
      contradição**, e é isso que a ADR pendente tem de resolver — não só a frequência.
      *Pronto:* uma ADR curta com a política escolhida, e o agendamento ajustado para ela.

- [~] **Dois relatórios de fila onde deve haver um.** ✅ resolvido pelo **#71**
      (`ai/loop-20260907T065854Z`), integrado aqui: `merge_order_report.sh` saiu e `--order` entrou
      no `merge_queue_report.sh`. Verificado na árvore integrada: `tools/loop/` tem só
      `merge_queue_report.sh` e `unclaimed_surface.sh`. Vira `[x]` quando a integração mesclar.

### P1 — higiene estrutural

- [~] **Executar as sete remoções decididas na ADR-0010 — uma pasta por PR.** ✅ as **sete**
      saíram, uma por PR como a ADR exige, e estão integradas nesta branch: `curved_lines_2d`
      (#60), `phantom_camera` (#62), `guide` (#63), `GDDraw` (#64), `yard` (#66), `softbody2d`
      (#72), `curve2collision` (#73). `addons/` tem agora **duas** pastas, ambas `ferramenta`.
      Total devolvido, remedido na integração (`git ls-tree -r -l` contra `34634d0`, não copiado
      da prosa dos PRs): **1 397 arquivos, 101 cenas, 6 936 KiB, 122 `class_name`** — o namespace
      global do projeto caiu de 176 para 52 símbolos de addon. Vira `[x]` quando a integração
      mesclar.

      **O item dizia "sete vezes repetível, sem disputar arquivo com ninguém". Era falso, e o
      custo foi medido duas vezes** — pelo #76 (seis abortos em `addons/README.md`) e aqui, ao
      resolver. Três coisas que a próxima série de remoções deve saber:

      1. **A união automática de documento mente alto.** As seis merges deixaram `addons/README.md`
         com sete cabeçalhos `Verificado em` empilhados, quatro frases de fecho contraditórias e
         três tabelas de "Remoções já executadas"; `docs/PROJECT_CONTRACT.md` acumulou **seis**
         contagens de `class_name` incompatíveis (174, 176, 173, 165, 157, 97), nenhuma dizendo por
         que método. **Nada ficou vermelho** — o cabeçalho de frescor estava lá. Os dois documentos
         foram reescritos à mão e os números remedidos no disco.
      2. **Cinco dos sete não protegiam a própria pasta no `.gitignore`.** Só #60 e #62 a
         acrescentam. A proteção dependia da ordem de merge, que é a forma mais silenciosa de não
         existir. As sete estão lá agora, num bloco só.
      3. **O conflito estrutural em `tests/integration/shipping_export_test.gd` foi eliminado, não
         só resolvido:** o bloco `ok(excluded.contains(...))` reescrito por cada remoção virou um
         laço sobre `REMOVED_VENDOR_ADDONS`. Acrescentar uma remoção é uma linha numa lista.

- [~] **`docs/TEST_MATRIX.md` está devendo linhas — dívida acumulada de várias execuções.**
      ✅ a causa foi atacada pelo **#69** (`ai/loop-20260907T050359Z`): a contagem deixou de ser
      digitada e passou a ser derivada, com `tests/unit/test_matrix_inventory_test.gd` a exigir que
      o inventário bata com a varredura do runner **e** que toda afirmação `N testes, M asserções`
      do documento repita os mesmos números. Reconciliado nesta integração para **288 testes /
      14 087 asserções / 54 arquivos**. Vira `[x]` quando a integração mesclar.

      **O preço do #69, medido pelo #76 e confirmado aqui:** a guarda acopla todo PR que acrescente
      teste a todo outro que também acrescente. #61, #74 e #75 exigiram, cada um, uma correção à
      mão da linha derivada **na ordem de merge**, e o número certo só existe depois de correr a
      suíte sobre a árvore acumulada. Três resoluções obrigatórias, não opcionais.

      **E uma propriedade nova, que ninguém tinha visto: a contagem de asserções é
      autorreferente.** A guarda percorre cada afirmação da matriz e gasta asserções em cada uma —
      corrigir a matriz muda o número que a matriz declara. Foram três iterações até estabilizar em
      14 087. Não é instabilidade: é a guarda a medir-se a si própria. Quem reconciliar a matriz
      deve **rodar, escrever, e rodar de novo** até o número parar de se mover.

- [ ] **Guarda derivada tem de cobrir o estado final da decisão que guarda.** Achado de 14:00Z,
      pago duas vezes na mesma integração: a guarda do fecho de `addons/` (#67) ficava vermelha com
      zero pastas condenadas — o estado que a ADR-0010 pediu —, e a guarda da matriz (#69) fica
      vermelha em todo PR que acrescente teste. Ambas são boas guardas com o domínio mal fechado.
      Corrigidas aqui **em `addons_manifest_test.gd`**; a da matriz continua acoplada por
      construção. → Escrever a regra onde as guardas são enunciadas (`docs/TEST_MATRIX.md` §
      inventário, ou o `CLAUDE.md`): **uma guarda derivada declara o que faz nos extremos — zero,
      um, e "outro PR mudou o número" — ou não entra.** E decidir se a do #69 fica como está: o
      acoplamento é o preço de não voltar a "174 testes" por onze PRs, e pode valer a pena pago
      conscientemente.
      *Pronto:* a regra escrita onde o próximo autor de guarda a encontre, e a decisão sobre o #69
      registrada — mantida com o custo assumido, ou afrouxada para avisar em vez de quebrar.

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

- [~] **`QixAudioDirector.sync` trata música e vozes com guardas diferentes.** ✅ resolvido pelo
      **#70** (`ai/loop-20260907T060000Z`), integrado aqui: uma só regra de guarda para música e
      vozes. Vira `[x]` quando a integração mesclar. Verde nesta árvore.

- [~] **`game/enemies/boss_behavior_controller.gd` é domínio fora do alcance da guarda.**
      ✅ resolvido pelo **#68** (`ai/loop-20260907T040000Z`), integrado aqui: o controlador do chefe
      passou a estar sob uma das duas guardas de pureza, medido e fechado. Vira `[x]` quando a
      integração mesclar. Verde nesta árvore.

- [~] **`round_visual_definition.gd` é o próximo atrito previsível da guarda de valor real.**
      ✅ resolvido pelo **#74** (`ai/loop-20260907T100000Z`), integrado aqui: a exceção do visual em
      `game/rules/` deixou de ser nomeada em silêncio e passa a ser paga, com
      `rules_presentation_exception_test.gd`. Vira `[x]` quando a integração mesclar.

- [ ] **A guarda de frescor prova presença de cabeçalho, não veracidade do conteúdo.**
      `doc_freshness_header_test.gd` (#6) exige a linha `> **Verificado em**` e fica verde com ela
      presente — mesmo quando o corpo mente. #21 corrigiu `TEST_MATRIX.md`, que afirmava quatro
      contagens concorrentes e passava em tudo; **os demais docs que passaram pela mesma união
      automática não foram auditados**. → (a) auditar os outros documentos contra o código
      integrado; (b) decidir se alguma guarda barata pega contradição interna (ex.: recusar duas
      linhas de tabela com a mesma primeira coluna). *Pronto:* nenhum doc de `docs/` com duas
      afirmações concorrentes sobre o mesmo fato, e a decisão sobre (b) escrita.

      **(b) tem a primeira resposta, e ela é "sim, quando o fato é derivado".** Em 03:00Z
      (`ai/loop-20260907T030045Z`), `test_removal_totals_match_the_folders_on_disk` passou a derivar
      do disco quantas pastas continuam `a-remover` e quantas cenas somam, conferindo contra a frase
      de fecho de `addons/README.md` — a linha que as cinco remoções abertas contradiziam entre si.
      Provada por mutação: simulada a remoção de `yard` sem atualizar o fecho, a guarda acusa `sete
      (7) mas a tabela declara 6` e `promete 101 cenas, mas o disco tem 92`. **A lição generaliza:
      número derivado escrito à mão é o que envelhece primeiro, e é barato de amarrar; prosa de
      julgamento não é, e não vale tentar.** Os megabytes ficaram deliberadamente de fora — 6,8 MB
      por tamanho de arquivo contra 16 MB por blocos no mesmo checkout, e uma guarda sobre isso
      ficaria vermelha conforme o sistema de arquivos.

      **(a) ganhou a evidência mais forte até agora, em 14:00Z.** Ao integrar as sete remoções,
      `addons/README.md` acabou com **sete cabeçalhos `Verificado em` empilhados**, quatro frases de
      fecho contraditórias e três tabelas de "Remoções já executadas"; `docs/PROJECT_CONTRACT.md`,
      com **seis** contagens de `class_name` incompatíveis (174, 176, 173, 165, 157, 97), nenhuma
      dizendo por que método foi medida. **A suíte ficou verde o tempo todo** — o cabeçalho estava
      lá. Os dois foram reescritos à mão. Isto é (a) demonstrado, não suspeitado: a auditoria dos
      demais `docs/` continua por fazer, e agora sabe-se o que procurar — cabeçalho repetido e
      número derivado sem o comando ao lado.

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

- [~] **Escolher de onde o cursor tira sua cor.** ✅ resolvido pelo **#75**
      (`ai/loop-20260907T110000Z`, **ADR-0012**), integrado aqui: a silhueta ganhou contorno de
      tinta próprio em vez de emprestar as três camadas da paleta do campo. Medido nesta árvore por
      `verify_palette_contrast.gd`: `CURSOR_INK×BOUNDARY` fica em **9,98:1** na pior visão
      (`verdant_singularity`), contra o 1,00:1 que `CURSOR_OUTER×BOUNDARY` trava. A catraca está
      **verde** (nenhum par abaixo do piso registrado). Vira `[x]` quando a integração mesclar.
      **Falta o julgamento estético:** ninguém viu o cursor numa tela — a medição diz que o
      contraste subiu, não que ficou bom.

- [~] **O canal sonoro da exposição não foi feito.** ✅ entregue pelo **#61**
      (`ai/loop-20260906T210208Z`), integrado aqui: cruzar `TrailExposure.WARNING_RATIO` passa a ser
      audível, com prioridade declarada (35, a mesma da háptica do #39), o aviso é recusado quando
      algo mais alto acontece no mesmo tick, e a aresta é lida sem ser consumida — checksum imóvel
      ao longo de oito `sync`. Vira `[x]` quando a integração mesclar. **O som nunca foi ouvido:**
      áudio físico continua sem validação nesta sessão.

- [~] **`docs/ART_DIRECTION.md` não registra duas decisões visuais já tomadas.** ✅ resolvido
      pelo **#65** (`ai/loop-20260907T010048Z`), integrado aqui: o anel de tinta da ameaça
      (ADR-0011) e a floritura de captura (#37) entraram no documento de arte. Vira `[x]` quando a
      integração mesclar. **Nota para a próxima execução:** a **ADR-0012** (contorno do cursor,
      #75) nasceu depois e **ainda não está** referenciada no documento de arte — o mesmo buraco,
      um decisão mais tarde.

- [x] **O tempo da transição entre rodadas não tem ritmo.** ✅ entregue pelo #50
      (`ai/loop-20260906T130328Z`), integrado aqui **com resolução de conflito**: o painel abre em
      ordem de leitura (`_apply_cadence` revela subtítulo → resultado → continuidade → prompt por
      limiares de progresso) e a continuidade entra com uma batida que **decai** em vez de piscar
      (`_beat`, pela mesma razão do ADR-0009: um degrau de um frame é ruído a 60 Hz).
      A cadência é alimentada pelo helper `_transition_progress(session)` da própria view, não por
      `session.transition_progress()` como o #50 escrevia — ver o P0 acima. Invariante 6 defendido
      por `round_transition_cadence_test.gd`: percorre a intro inteira e prova que checksum e
      replay não mexem. **Falta o julgamento estético:** ninguém viu a passagem numa tela.

- [~] **Geometria real do HUD — #52 integrado no candidato de merge.**
      `tools/verify_hud_row_geometry.gd` mede a construção durante frames, não só as constantes
      no `_initialize()` do runner. O teste horizontal e os comentários corrigidos também
      foram preservados. A sonda passou a fazer parte do CI. Aprovação estética continua humana.

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
- **A união automática resolve o conflito e cria a mentira.** Medido em 14:00Z, e é o custo real
  da drenagem: seis merges de remoção deixaram `addons/README.md` com sete cabeçalhos empilhados e
  quatro fechos contraditórios, e `docs/PROJECT_CONTRACT.md` com seis contagens incompatíveis — com
  a suíte **verde**. Documento com tabela que acumula linhas e cabeçalho que se reescreve **não**
  se resolve por script: leia o arquivo inteiro e reescreva. E remeça os números derivados no disco
  (`git ls-tree -r -l`, `grep -rhoE '^class_name …'`) em vez de escolher entre os que os PRs
  trazem: cada PR mediu uma árvore que não é a integrada, e todos podem estar certos e errados ao
  mesmo tempo.

- **A contagem de asserções da matriz é autorreferente.** A guarda do #69 gasta asserções em cada
  afirmação `N testes, M asserções` do documento — corrigir a matriz muda o número que a matriz
  declara. Rode, escreva, rode de novo, até parar de se mover. Em 14:00Z foram três iterações
  (14 091 → 14 087). Não é flake.

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
