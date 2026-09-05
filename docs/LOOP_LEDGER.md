# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-05 · commit `cba520a` · Godot 4.7.2-stable, Linux headless
> **Alcance:** reconciliado à mão sobre a integração dos PRs #20–#35, medida verde (211 testes,
> 12383 asserções, 0 falhas; rota M2 179→825‰ com `errors: []`; catraca de contraste sem par
> abaixo do piso). Cada item do backlog foi reconferido contra o código integrado, não contra
> `main` sozinho. O mérito **estético** de qualquer mudança continua sem julgamento: o jogo não
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

### Ao resolver conflito de documentação

Mantenha a linha `> **Verificado em**` de cada doc — `tests/unit/doc_freshness_header_test.gd`
recusa doc sem cabeçalho. E **não resolva este arquivo por união automática**: o resultado passa
nos testes e mente para o leitor. A integração de 23:00Z produziu 703 linhas com cinco seções de
"estado da fila" contraditórias e três ordens de merge concorrentes. Backlog reconcilia-se à mão.

### A marcação de posse é ruído, não sinal

As execuções de 10:00Z (#26) e 18:00Z (#34) tentaram resolver "o backlog diz livre em item que já
tem dono" escrevendo a posse **dentro do backlog**: `[ocupado pelo PR #22]`, `[~] Reivindicado
pelo PR #29`, `[!] Livre de PR, bloqueado pelo arquivo`. A integração desta execução mostra por
que isso não funciona: no instante em que a fila drena, **toda** marcação vira mentira de uma vez,
e quem lê o backlog não tem como distinguir posse viva de posse fóssil. Pior, a marcação é escrita
no ponto exato do arquivo que mais conflita.

A posse mora no GitHub, que sabe a verdade sem que ninguém a transcreva. O passo 2 do protocolo já
manda consultá-la. Esta reconciliação **removeu** as marcações e não as reintroduz — se uma futura
execução sentir falta delas, o item a atacar é o passo 2, não o backlog.

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
| Destino dos addons dormentes | `docs/decisions/ADR-0010` |
| Ameaça lê-se por forma, não por cor | `docs/decisions/ADR-0011` |
| Identidade visual é *Lumen Cartography* | `docs/ART_DIRECTION.md` |
| Volfied é referência de gênero, não alvo de clone | `reference/volfied/README.md` |
| Histórico do loop é um arquivo por execução | `docs/loop/runs/README.md` |
| `samples/` e `guide_examples/` podados; `exclude_filter` fica | `docs/loop/runs/`, poda dos demos |
| `antipixel_state_machine/` podada — sem consumidor | `docs/loop/runs/2026-09-05T035826Z.md` |
| Posse de item não se escreve no backlog | seção acima |

## Backlog — prioridade decrescente

Cada item diz **o que**, **por que importa para a experiência** e **como saber que ficou bom**.
Itens sem critério de pronto não entram aqui.

### P0 — a fila (nada abaixo importa enquanto isto não anda)

- [ ] **Drenar a fila de PRs abertos — segunda vez.** O #19 drenou os 18 primeiros e `main` andou
      até `cba520a`. Em dezassete horas a fila voltou a **16 PRs** (#20–#35) e `main` não andou
      mais. Esta execução mediu a fila inteira: mesclados em ordem numérica, os 16 **não têm um
      único conflito de código** — o único conflito em qualquer par é este arquivo, que é
      mecânico e esperado por contrato. A árvore integrada dá 211 testes / 12383 asserções / 0
      falhas contra 174 / 11837 em `main` sozinho.
      Enquanto `main` não andar, cada execução nova ou duplica um item já coberto ou colide com a
      fila: os 16 PRs abertos **já reivindicam todos os itens herdados do backlog**.
      *Pronto:* `main` além de `cba520a` e a fila em ≤ 2 PRs abertos.
      Ver `docs/loop/runs/2026-09-05T200000Z.md` para a medição e a ordem verificada.

- [ ] **A cadência do loop excede a cadência de revisão, e isso é um problema de projeto.** Duas
      drenagens em dois dias, ambas por integração de emergência, dizem que uma execução por hora
      produz mais do que um humano mescla. Não é falha de nenhuma execução: é a taxa. Enquanto não
      for resolvida, toda madrugada termina em fila saturada e o loop gasta execuções a medir a
      própria fila em vez de melhorar o jogo. → Opções a avaliar num PR curto: baixar a frequência
      do agendamento; deixar o loop **empilhar** o trabalho num único ramo de longa duração em vez
      de abrir um PR por execução; ou dar ao loop critério explícito para não abrir PR quando a
      fila passa de N. *Pronto:* a taxa de produção do loop e a de revisão estão declaradas por
      escrito, com a regra que as concilia.

### P1 — higiene estrutural

- [ ] **Executar as sete remoções decididas na ADR-0010 — uma pasta por PR.** A decisão está
      tomada (`guide`, `curved_lines_2d`, `phantom_camera`, `GDDraw`, `softbody2d`,
      `curve2collision`, `yard` saem; `fennara` e `godot_ai` ficam como ferramental). Falta
      executá-la. `addons/README.md` e `tests/unit/addons_manifest_test.gd` já guardam o estado,
      então uma remoção que esqueça o manifesto quebra o teste — o que é o comportamento desejado.
      *Pronto:* cada pasta removida com a mesma evidência de posse de `uid://` usada na poda de
      `antipixel_state_machine/`, e o manifesto atualizado no mesmo commit.

### P2 — integridade de contexto

- [ ] **`docs/TEST_MATRIX.md` está devendo quatro linhas — dívida acumulada de três execuções.**
      Nenhum dos testes novos entrou na matriz: `audio_envelope_test.gd` (#23, onset dos cues),
      a segunda metade do invariante 1 em `domain_purity_test.gd` (#25),
      `presentation_purity_test.gd` (#26), `addons_manifest_test.gd` (#29),
      `enemy_silhouette_contrast_test.gd` (#32), `cursor_contrast_test.gd` (#28),
      `touch_stick_anchor_test.gd` (#33), `player_view_facing_test.gd` (#35). Três execuções
      registaram a mesma dívida separadamente, o que é o sintoma: a matriz é o único doc que toda
      execução deveria tocar e nenhuma toca. → Um PR só de matriz, depois da drenagem.
      *Pronto:* todo arquivo em `tests/` tem linha na matriz, e o número de testes que ela declara
      bate com a saída do runner.
- [ ] **`session.records` só é preenchido pela via PLAYING→vitória/derrota.** Forçar
      `phase = ROUND_CLEAR` num teste não arquiva a rodada — correto, mas não óbvio: custou uma
      asserção errada na execução de 19:00Z (do dia 4). Qualquer apresentação que conte rodadas
      depende disso. → Documentar a regra no cabeçalho de `GameSession`. *Pronto:* o contrato de
      `records` legível sem ler `_archive_current_round`.
- [ ] **`game/enemies/boss_behavior_controller.gd` é domínio fora do alcance do guarda.**
      Achado de #26: o controlador decide trajetória de chefe e obedece às regras do domínio, mas
      não mora em `game/simulation/`, `game/rules/` nem `game/session/`, que é o que
      `domain_purity_test.gd` varre. Ou o alcance do guarda cresce, ou o arquivo muda de pasta, ou
      está escrito por que ele é exceção. *Pronto:* uma das três, decidida por escrito.
- [ ] **`round_visual_definition.gd` é o próximo atrito previsível da guarda de valor real.**
      Previsto por #25: é `Resource` autorável em `game/rules/` que carrega números estéticos, e a
      guarda de `float` no domínio vai encontrá-lo assim que alguém lhe acrescentar um campo
      contínuo. *Pronto:* ou a guarda distingue "regra que o domínio lê" de "regra que só a
      apresentação lê", ou a exceção está escrita antes de alguém tropeçar nela.
- [ ] **A guarda de frescor prova presença de cabeçalho, não veracidade do conteúdo.** Achado de
      #21: `doc_freshness_header_test.gd` recusa doc sem `> **Verificado em**`, mas nada impede
      que a data seja antiga, o commit não exista ou o alcance minta. Foi assim que a matriz de
      teste passou em tudo afirmando quatro contagens concorrentes. → Avaliar uma verificação
      barata: o commit citado existe? a data é ≤ hoje? *Pronto:* ou a guarda cresce, ou está
      registado por que a veracidade não é verificável mecanicamente.
- [ ] **Dois relatórios de fila onde deve haver um.** `merge_order_report.sh` (#31) nasceu como
      arquivo novo para não colidir com `merge_queue_report.sh` (#30) na própria fila que ambos
      medem — decisão certa no momento, dívida agora. *Pronto:* um script, com a ordem de merge e
      a matriz de sobreposição, e o outro removido.

### P3 — experiência e estética (o alvo real)

Os primeiros itens **exigem olho humano na tela**: uma sessão headless mede, não aprova.

- [ ] **`BOUNDARY`×`TRAIL` a 1,04:1 — a decisão mais cara do jogo no canal mais frágil.** A
      medição de #7 (`docs/ART_DIRECTION.md`, "Contraste medido") mostra contorno e trilha com a
      mesma luminância nas quatro paletas; "estou protegido" × "estou desenhando" depende de matiz
      mais o glint/pulso do shader. **É o último item herdado que nenhuma execução atacou**, e a
      razão é honesta: o critério de pronto exige captura de tela. Caminhos: baixar a luminância
      de `BOUNDARY`, subir a de `TRAIL`, ou dar ao contorno trama espacial mais grossa que
      sobreviva a 1 px. *Pronto:* par acima de 3:1 nas quatro paletas, `PAIR_FLOOR`/`KNOWN_DEBT` e
      a seção de `ART_DIRECTION` reescritos no mesmo commit, e alguém confirmou por captura que o
      campo não ficou lavado.
- [ ] **Escolher de onde o cursor tira sua cor.** Nasceu da medição de #28: sobre `BOUNDARY`
      nenhuma camada opaca do cursor separa (`CURSOR_OUTER×BOUNDARY` a 1,00:1 nas quatro paletas,
      por construção — `QixPlayerView` usa `visual.boundary_color` como `_outer`). O núcleo e o
      halo carregam sozinhos a leitura. *Pronto:* o cursor tem cor própria declarada ou uma razão
      escrita para partilhar a do chão, e o par medido acima do piso.
- [ ] **Confirmar o anel de tinta numa tela.** `ADR-0011` (#32) dá à ameaça um contorno que não
      depende de cor e está **medido, não visto**. Duas perguntas para o olho: o anel lê-se a 1 px
      sobre `TRAIL`? e some no fundo revelado? *Pronto:* alguém olhou e a ADR ganhou a nota.
- [ ] **`docs/ART_DIRECTION.md` ainda não aponta para a `ADR-0011`.** A seção "Contraste medido"
      continua a descrever a leitura da ameaça como problema aberto. Uma linha. *Pronto:* a seção
      remete para a ADR.
- [ ] **A proa do cursor aponta para a frente por hipótese, não por medida.** #35 corrigiu a proa
      que apontava para baixo em três das quatro direções; que a proa *à frente* seja a leitura
      certa para este jogo continua por confirmar com olho. *Pronto:* visto em jogo, ou a
      alternativa (proa que segue a trilha) avaliada por escrito.
- [ ] **A âncora flutuante do stick precisa de um polegar de verdade.** #33 tirou o passo espúrio
      no instante em que o dedo pousa; o raio morto e a posição da âncora foram escolhidos no
      papel. *Pronto:* alguém jogou com o polegar e confirmou (ou corrigiu) os dois números.
- [ ] **Ritmo do risco: som e háptica da exposição.** O canal visual foi feito em #9
      (`TrailExposure`: o pulso da trilha acelera e clareia, o HUD nomeia o limiar). Faltam os
      outros dois canais — um cue que suba com a exposição e um toque háptico ao cruzar
      `TrailExposure.WARNING_RATIO`. **A dependência caiu:** #23 entregou envelope e prioridade
      autorados por cue, que era o que faltava. *Pronto:* cruzar o limiar é audível e tátil, com
      prioridade declarada, **sem alterar checksum**.
- [ ] **Calibrar a curva de exposição com jogo real.** `TrailExposure` usa piso 8 px (o mesmo
      `new_segment_slow_px` do domínio) e teto geométrico `(w+h)/4` = 127 px no campo de produção.
      Os dois números são justificáveis no papel e **não foram vistos em jogo**.
      *Pronto:* alguém joga as três rodadas e confirma (ou corrige) onde o aviso deve nascer.
- [ ] **O tempo da transição entre rodadas não tem ritmo.** #15 fez a passagem carregar score,
      vidas e o próximo setor, mas a barra de progresso é linear em ticks e nada enfatiza o
      instante em que o número de continuidade aparece. É animação de apresentação, não texto.
      *Pronto:* a passagem tem um acento perceptível no momento da continuidade, sem tocar domínio.
- [ ] **A geometria do HUD depende da ordem de construção.** `_add_label` só obtém o retângulo
      pedido porque atribui `size` depois de entrar na árvore; antes do primeiro frame o mínimo do
      `Label` ainda é o do tema (23 px). Funciona, mas é frágil e invisível. → Avaliar
      `custom_minimum_size` explícito ou um `Theme` do HUD com tamanho de fonte definido, para que
      a altura não dependa de quando `_ready` corre. *Pronto:* altura correta medida dentro do
      runner, sem a ressalva que `game_hud_layout_test.gd` documenta hoje.

## Notas de ambiente (sandbox de nuvem)

Verificado em 2026-09-05: o build Linux headless `4.7.2-stable` baixa sem bloqueio de rede e
reporta `4.7.2.stable.official.ed1daf0bf`. O `--import` obrigatório roda até o fim e **não** exige
mono. Suíte completa e `verify_m2_capture_route.gd` rodam em segundos. Nesta sessão não há
desculpa para PR sem verificação — se uma execução não rodou os comandos, o motivo tem que ser
dito, não omitido.

Ruído esperado, **não** regressão — não gaste uma execução investigando:

- `ERROR: Can't open dynamic library ... libfennara.linux.editor.x86_64.so` seguido de
  `Error loading extension` aparece em **toda** execução headless, inclusive em `main` sem
  alteração. `addons/fennara/bin/` não é versionado (e não deve ser). A suíte passa apesar do erro.
- `[godot_ai game_helper] registered mcp capture` ao final de todo script headless é o autoload de
  ferramental. Não é erro.
- `--import` é obrigatório **também depois de cada troca de branch** que traga script novo, senão
  o cache de `class_name` não conhece a classe e a falha não é a sua mudança. Vale igualmente para
  um worktree novo: o `.godot/` não viaja com ele.
- **Medir X no runtime do runner é fiável; medir Y não é.** Tudo corre dentro de `_initialize()`,
  antes de a árvore processar um frame, e a altura de um `Label` fica presa a um mínimo obsoleto
  (23 px). Depois do primeiro frame assenta no valor pedido. O comentário `# evita os 23 px padrão`
  em `_add_label` está correto no runtime real; não o "corrija" pelo que o runner mostra.
- **A descoberta de testes em `run_tests.gd` varre diretório.** Dois PRs podem acrescentar arquivos
  de teste sem se tocarem — foi o que permitiu #3 e #5 coexistirem, e é por isso que os 16 PRs
  desta fila integram sem um conflito de código. Prefira arquivo novo a edição em arquivo disputado.
- **`exclude_filter` de `guide_examples/**` e `samples/**` fica em `export_presets.cfg` mesmo com
  as pastas podadas.** Um checkout que rebaixe os addons pela AssetLib recria as pastas em disco, e
  o filtro cobre um caminho que o `.gitignore` não cobre. Não "limpe" isso.

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
