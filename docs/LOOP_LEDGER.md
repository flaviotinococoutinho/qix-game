# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-06 · commit `cba520a` · Godot 4.7.2-stable, Linux headless
> **Alcance:** base reconciliada à mão em 2026-09-04 sobre a integração dos 18 PRs do loop
> (#1–#18). Em 2026-09-06T04:03Z foram atualizados o estado da fila no P0, dois itens de P3 sobre
> o pulso da trilha e as notas de ambiente; o resto do backlog **não** foi reconferido nesta
> passagem. O mérito estético de cada mudança continua sem julgamento: o jogo não pode ser jogado
> nem visto num sandbox headless.

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
| Identidade visual é *Lumen Cartography* | `docs/ART_DIRECTION.md` |
| Volfied é referência de gênero, não alvo de clone | `reference/volfied/README.md` |
| Histórico do loop é um arquivo por execução | `docs/loop/runs/README.md` |
| `samples/` e `guide_examples/` podados; `exclude_filter` fica | `docs/loop/runs/`, poda dos demos |

## Backlog — prioridade decrescente

Cada item diz **o que**, **por que importa para a experiência** e **como saber que ficou bom**.
Itens sem critério de pronto não entram aqui.

> **O backlog herdado acabou.** Todos os itens P1, P2 e P3 do ledger de fundação foram entregues
> pelos PRs #1–#18. O que resta abaixo **nasceu das próprias execuções** — é dívida que só ficou
> visível depois que o trabalho foi feito. Confira a fila antes de escolher.

### P0 — a fila (nada abaixo importa enquanto isto não anda)

- [ ] **Drenar a fila de PRs abertos.** Só um humano mescla; o loop não mescla o próprio PR.
      Enquanto `main` não andar, cada execução ou duplica um item já coberto ou trabalha na fila
      em vez de no jogo. A integração dos 18 está medida e verde — ver
      `docs/loop/runs/2026-09-04T230000Z.md` para a ordem e o que ela exige.
      *Pronto:* `main` além de `74c173a` e a fila em ≤ 2 PRs abertos.
      **Estado em 2026-09-06T04:03Z: 22 PRs abertos (#20–#41).** A execução de 02:58Z mediu que
      #20–#39 integram verdes em conjunto; esse dado não precisa ser refeito. O que falta é a
      decisão humana de mesclar, não mais medição — **não gaste outra execução a remedir a fila.**

### P1 — higiene estrutural

- [ ] **`antipixel_state_machine/` é a última raiz de terceiros não decidida.** 3 cenas, 7
      scripts, 132 KB, e nenhum arquivo de `game/`, `ui/`, `app/`, `tools/`, `tests/` ou
      `content/` o referencia (grep de 2026-09-04). O `.gitignore` já recusa o PDF do vendor, o
      que sugere que a pasta entrou sem decisão. Ficou de fora da poda dos demos por disciplina de
      "uma pasta por vez" e porque, ao contrário de `samples/`/`guide_examples/`, ela não é demo
      de um addon presente em `addons/` — pode ser dependência real adormecida.
      *Pronto:* mantida com consumidor nomeado, ou removida com a mesma evidência de posse de
      `uid://` usada na poda.

### P2 — integridade de contexto

- [ ] **Sete addons dormentes, 11,5 MB, 101 cenas** — `guide`, `curved_lines_2d`,
      `phantom_camera`, `GDDraw`, `softbody2d`, `curve2collision`, `yard`. O inventário (#2)
      provou que nenhum é habilitado, nenhum é referenciado e todos já saem no `export_filter`.
      Não é P1 porque `addons/` é pasta que todo leitor de Godot sabe ignorar — mas dependência
      dormente é decisão adiada, não estado neutro, e o próximo leitor não tem como saber se
      `phantom_camera` é lixo ou plano. → ADR curta: remover, ou declarar quais ficam como
      reserva e por quê. *Pronto:* nenhuma pasta em `addons/` sem uma linha que diga por que está lá.
- [ ] **Invariante 1, segunda metade: "só inteiros e ponto fixo 8.8" continua sem guarda.**
      `domain_purity_test.gd` (#3) cobre a primeira metade — símbolo do mundo real citado no
      domínio. A varredura **não** procura `float` porque hoje ficaria vermelha em código legítimo:
      `GameSession.transition_progress()` (`game/session/game_session.gd:37-41`) devolve `float`
      derivado de dois contadores inteiros de tick. Não lê o mundo real, mas também não é ponto
      fixo 8.8 — é conveniência de apresentação morando na sessão. → Mover a conversão para quem
      apresenta (a view já tem os dois inteiros) e então proibir `float` no domínio, ou declarar a
      exceção por escrito no `CLAUDE.md`. *Pronto:* ou a regra entra no scanner, ou a exceção está
      escrita onde o invariante está enunciado.
- [ ] **Invariante 6 ("apresentação observa, nunca muta") não tem guarda mecânica.** Mais difícil
      que o 1 e o 4: não é um símbolo proibido, é uma direção de chamada. → Investigar se uma
      varredura barata prova algo útil (ex.: nenhuma view atribui a campo de `BoardState` ou chama
      `step(`), ou se só um teste de comportamento resolve. *Pronto:* ou a guarda existe, ou está
      registrado por escrito por que ela não é viável estaticamente.
- [ ] **Cobertura dourada só alcança a rodada 1.** `replay_checksum_golden_test.gd` (#5) fixa o
      `config_hash` das três rodadas, mas roda uma única rota (177 ticks, uma captura) na rodada 1.
      R2 e R3 têm perfis de boss diferentes (PURSUIT, SWEEP) cujas trajetórias nenhum checksum
      literal cobre. *Pronto:* cada perfil de boss de produção tem ao menos um checksum final
      fixado, ou uma nota dizendo por que não precisa.
- [ ] **`session.records` só é preenchido pela via PLAYING→vitória/derrota.** Forçar
      `phase = ROUND_CLEAR` num teste não arquiva a rodada — correto, mas não óbvio: custou uma
      asserção errada na execução de 19:00Z. Qualquer apresentação que conte rodadas depende disso.
      → Documentar a regra no cabeçalho de `GameSession`. *Pronto:* o contrato de `records`
      legível sem ler `_archive_current_round`.

### P3 — experiência e estética (o alvo real)

Os itens abaixo nasceram das execuções que entregaram HUD, áudio, contraste e transição. Os três
primeiros **exigem olho humano na tela**: uma sessão headless mede, não aprova.

- [ ] **`BOUNDARY`×`TRAIL` a 1,04:1 — a decisão mais cara do jogo no canal mais frágil.** A
      medição de #7 (`docs/ART_DIRECTION.md`, "Contraste medido") mostra contorno e trilha com a
      mesma luminância nas quatro paletas; "estou protegido" × "estou desenhando" depende de matiz
      mais o glint/pulso do shader. Caminhos: baixar a luminância de `BOUNDARY`, subir a de
      `TRAIL`, ou dar ao contorno trama espacial mais grossa que sobreviva a 1 px.
      *Pronto:* par acima de 3:1 nas quatro paletas, `PAIR_FLOOR`/`KNOWN_DEBT` e a seção de
      `ART_DIRECTION` reescritos no mesmo commit, e alguém confirmou por captura que o campo não
      ficou lavado.
- [ ] **Ameaça sobre borda e trilha depende de forma, não de luminância.** Mesma medição:
      `BOUNDARY`×`THREAT` 1,28–1,42:1 e `TRAIL`×`THREAT` 1,83–2,04:1 no pior caso (deuteranopia).
      Hoje o losango do chefe carrega sozinho a leitura. *Pronto:* ou o par sobe de 3:1, ou está
      escrito qual canal não cromático (contorno escuro, halo, cadência) garante a leitura, com
      teste que o defenda.
- [ ] **O contorno do jogador é a mesma cor do chão em que ele anda.** `QixPlayerView` usa
      `visual.boundary_color` como `_outer`; parado sobre `BOUNDARY`, a silhueta só se separa pelo
      núcleo e pelo halo de `accent_color`. Achado colateral de #7, ainda não quantificado.
      *Pronto:* contraste jogador × chão medido em `BOUNDARY` e em `FREE`, e decisão registrada.
- [ ] **Forma do envelope por intenção.** Metade do item de envelopes ficou fora de #10:
      `QixProceduralAudioLibrary._attack_release` é **o mesmo envelope para os dez cues**, com
      attack e release proporcionais à duração. Consequência medível: `death` (0,42 s) só atinge
      amplitude cheia ~34 ms depois do início, e `game_over` (0,75 s) ~60 ms — um impacto com
      fade-in não é um impacto. Os cues curtos (`trail`, `shield`) não sofrem disso. → Attack e
      release autorados por cue na receita, ao lado de `intent` e `priority`; ataque em
      milissegundos absolutos, não em fração da duração. *Pronto:* teste que mede o frame de pico
      do PCM e exige que os cues de impacto piquem em ≤ 8 ms, mantendo a subida suave dos de anúncio.
- [ ] **Ritmo do risco: som e háptica da exposição.** O canal visual foi feito em #9
      (`TrailExposure`: o pulso da trilha acelera e clareia, o HUD nomeia o limiar) — e só passou a
      funcionar de facto na execução de 04:03Z, que descobriu que a fase do pulso saltava até 6 rad
      por tick e não lia como aceleração. Faltam os
      outros dois canais do item original — um cue que suba com a exposição e um toque háptico ao
      cruzar `TrailExposure.WARNING_RATIO`. Depende do item de envelopes acima, que define
      prioridade entre vozes. *Pronto:* cruzar o limiar é audível e tátil, com prioridade
      declarada, **sem alterar checksum**.
- [ ] **Calibrar a curva de exposição com jogo real.** `TrailExposure` usa piso 8 px (o mesmo
      `new_segment_slow_px` do domínio) e teto geométrico `(w+h)/4` = 127 px no campo de produção.
      Os dois números são justificáveis no papel e **não foram vistos em jogo**.
      *Pronto:* alguém joga as três rodadas e confirma (ou corrige) onde o aviso deve nascer.
- [ ] **O ritmo do pulso da trilha nunca foi visto, só medido.** A execução de 04:03Z consertou a
      *continuidade* da fase (ver abaixo), o que era um defeito objetivo. O que ela não pode julgar
      é o ritmo resultante: 0,20 rad/tick parado e 0,75 rad/tick com exposição saturada, ou seja
      ~1,9 s e ~0,5 s por ciclo. Um pulso lento demais não avisa; rápido demais vira o mesmo ruído
      que acabou de sair. Anda junto com o item de calibrar a curva acima — é a mesma sessão de
      jogo. *Pronto:* alguém joga e confirma (ou corrige) as duas taxas em `QixBoardView`.
- [ ] **A pontuação não acompanha a subida do contador.** `06-gameplay.md §6.3` mostra que no
      original cada degrau do contador **paga pontos**, e é isso que faz o número na barra superior
      pulsar junto com a área. Aqui o score é domínio e chega inteiro num tick, então só a
      percentagem é encenada — o rótulo `S ######` continua saltando. → Avaliar se o HUD pode
      encenar a subida do score pelos mesmos degraus, lendo o valor já confirmado.
      *Pronto:* score e percentagem sobem juntos, sem que o HUD toque no domínio.
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

Verificado em 2026-09-04: o build Linux headless `4.7.2-stable` baixa sem bloqueio de rede e
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
  o cache de `class_name` não conhece a classe e a falha não é a sua mudança.
- **Medir X no runtime do runner é fiável; medir Y não é.** Tudo corre dentro de `_initialize()`,
  antes de a árvore processar um frame, e a altura de um `Label` fica presa a um mínimo obsoleto
  (23 px). Depois do primeiro frame assenta no valor pedido. O comentário `# evita os 23 px padrão`
  em `_add_label` está correto no runtime real; não o "corrija" pelo que o runner mostra.
- **A descoberta de testes em `run_tests.gd` varre diretório.** Dois PRs podem acrescentar arquivos
  de teste sem se tocarem — foi o que permitiu #3 e #5 coexistirem. Prefira arquivo novo a edição
  em arquivo disputado.
- **Para saber o que está livre, use a união dos arquivos da fila, não os títulos dos PRs.** Uma
  linha resolve, e é muito mais barato que remedir a integração:

  ```bash
  git fetch origin '+refs/pull/*/head:refs/remotes/pr/*'
  for n in $(gh pr list --state open --json number -q '.[].number'); do
    git diff --name-only origin/main...refs/remotes/pr/$n
  done | sort -u | grep -v '^docs/loop/runs/' | grep -v LOOP_LEDGER
  ```

  O que **não** aparece nessa lista é território livre. Foi assim que a execução de 04:03Z chegou a
  `game/board/board_view.gd` e ao shader com a fila em 21 PRs — e o defeito que encontrou lá valia
  mais que qualquer item que restava no backlog.
- **O `main` local do checkout pode estar atrasado em relação a `origin/main`.** Em 04:03Z o ref
  `main` apontava para `74c173a` enquanto `origin/main` já estava em `cba520a`; um `git diff
  main..<ramo>` devolveu 375 arquivos de diferença que não existiam. Compare sempre contra
  `origin/main`, depois de `git fetch origin main`.
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
