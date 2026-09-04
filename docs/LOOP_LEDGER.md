# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-04 · commit `74c173a` · Godot 4.7.2-stable, Linux headless
> **Alcance:** backlog e histórico conferidos contra os PRs abertos do loop (#1 a #5) na data
> acima. Este documento é reescrito a cada execução — a data aqui marca a última run, não uma
> validação de conteúdo do jogo.

Um agente de nuvem roda de hora em hora e **começa sem contexto**. Este arquivo é a única
memória que atravessa execuções. Sem ele, a run nº 7 desfaz a nº 3 sem saber que ela existiu.

## Protocolo (obrigatório)

1. **Leia este arquivo inteiro antes de decidir o que fazer.** Ele vem depois do `CLAUDE.md` e
   antes de qualquer edição.
2. **Escolha exatamente UM item** do backlog — o de maior prioridade que caiba num PR pequeno e
   revisável. Um PR grande não é produtividade: é uma revisão que não vai acontecer.
3. **Escreva o relato da execução em `docs/loop/runs/<carimbo>.md`** — um arquivo novo, seu, com
   item escolhido, o que mudou, como foi verificado e o que ficou pendente. Não apense ao
   histórico deste arquivo: ele é o ponto onde as execuções colidem. Ver
   `docs/loop/runs/README.md`.
4. **Ajuste o backlog deste arquivo dentro do mesmo PR** com o que você aprendeu, e marque o item
   que atacou. O backlog continua compartilhado de propósito: duas execuções que mexem no mesmo
   item *devem* se encontrar aqui.
5. **Nunca reabra um item de "Decisões fechadas"** sem um argumento novo e explícito no PR. Essa
   seção existe para impedir que o loop oscile entre duas opções para sempre.
5. **Este arquivo mente enquanto os PRs não são mesclados.** O ledger versionado em `main` só
   conhece o trabalho já integrado; itens tratados em PRs abertos continuam parecendo livres.
   Antes de escolher um item, liste os PRs abertos do loop e trate um item já coberto por um PR
   aberto como indisponível. A seção "Em revisão" abaixo é uma cópia de cortesia, não a verdade —
   a verdade é a lista de PRs abertos.

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

## Em revisão — PRs abertos do loop (cópia de cortesia, verificada em 2026-09-04T13Z)

Cada linha corresponde a um item do backlog abaixo que **já tem PR aberto**. Não pegue nenhum
deles. Se um PR for fechado sem mesclar, o item volta ao backlog e esta linha some.

| PR | Item do backlog |
|---|---|
| #1 | `node_2d.tscn` órfão na raiz (P1) |
| #2 | inventário dos nove addons (P1) |
| #3 | varredura estática dos invariantes 1 e 4 (P2) |
| #4 | poda de `samples/` e `guide_examples/` (P1) |
| #5 | checksums dourados de replay, invariantes 7 e 8 (P2) |
| #6 | data de verificação em todo `docs/*.md` (P2) |
| #7 | acessibilidade cromática por estado do campo (P3) |
| #8 | curva de percentagem em degraus (P3) |
| #9 | ritmo do risco: exposição da trilha (P3) — este PR |

Oito PRs abertos e nenhum mesclado é o achado estrutural desta execução: o loop produz mais
rápido do que a revisão absorve, e cada novo PR toca `docs/LOOP_LEDGER.md`, então a fila vai
gerar conflito de merge entre si. **Recomendação ao revisor humano:** mesclar ou fechar a fila
P1 (#1, #2, #4) antes de acumular mais, e mesclar na ordem de abertura para que os conflitos de
ledger sejam triviais.

## Backlog — prioridade decrescente

Cada item diz **o que**, **por que importa para a experiência** e **como saber que ficou bom**.
Itens sem critério de pronto não entram aqui.

### P0 — a fila (nada mais avança enquanto isto não anda)

- [x] **O histórico deste arquivo era o ponto único de conflito da fila.** Toda execução apensava
      uma linha ao mesmo ponto, então os 78 pares de PRs colidiam aqui — nenhum por desacordo
      real. Levantado pela medição do PR #14. → Resolvido: histórico virou um arquivo por
      execução em `docs/loop/runs/`, backlog continua compartilhado de propósito.
      *Pronto:* duas execuções seguidas sem conflito no histórico — vale da próxima em diante;
      os 15 PRs já abertos continuam colidindo entre si na tabela congelada.
- [ ] **Drenar a fila de PRs abertos.** Em 2026-09-04T19:58Z eram 15 (#1–#15), nenhum mesclado,
      `main` ainda em 2 commits. Só um humano mescla; o loop não mescla o próprio PR. Todo item
      deste backlog já tem PR aberto, então cada execução nova ou duplica ou fica no meta.
      → Mesclar na ordem recomendada pelo PR #14 (#13 primeiro, o portão de CI).
      *Pronto:* `main` com mais de 2 commits e a fila em ≤ 2 PRs abertos.
- [ ] **Sobreposição silenciosa do #15 não foi medida.** #15 (transição entre rodadas) chegou
      depois da medição de #14 e toca apresentação, como #8, #9, #10 e #11 — a classe de
      sobreposição que o git aceita e o teste reprova. → Rodar
      `tools/loop/merge_queue_report.sh --verify 15 <n>` (a ferramenta vive no ramo de #14).
      *Pronto:* os pares de #15 classificados como os de #14.
### P0 — destrava a fila (nada abaixo importa enquanto isto não sair)

> **Contexto (2026-09-04T17:00Z): 12 PRs abertos, zero mergeados.** O gargalo deixou de ser
> produzir melhoria e passou a ser integrá-la. Ver a tabela da fila no PR #12, que ainda não
> mergeou. Enquanto a fila não drenar, prefira verificar/integrar a abrir trabalho novo.

- [x] **Nenhum PR rodava verificação automática.** Consultado em 2026-09-04, o repositório não
      tinha `.github/` — nenhum dos doze PRs foi verificado por outra coisa senão uma execução do
      loop rodando Godot à mão. É por isso que a colisão `#8`×`#11` sobreviveu a onze
      verificações: cada uma olhou um PR contra `main`, e ninguém olhou dois juntos.
      → **Feito** em `.github/workflows/verificacao.yml` (PR desta execução). O portão rodou sobre
      o próprio PR que o introduz: `4.7.2.stable.official.ed1daf0bf`, **134 testes / 0 falhas** em
      3122 ms, rota M2 com `errors: []`, job verde em 37 s. A partir daqui, "verifiquei à mão" e
      "está verde" deixam de ser a mesma afirmação.
- [ ] **`tests/unit/game_hud_test.gd` (PR #8) fixa píxeis em vez de derivar da constante.**
      Confirmado nesta execução lendo os dois heads: `#8` afirma `size.x` literal `6`, `15` e `2`
      (linhas 43, 52 e 68), derivados de `OBJECTIVE_WIDTH := 50.0`; `#11` alarga a constante para
      `86.0`. O fill é `roundf(OBJECTIVE_WIDTH * objective_ratio)` nos dois, então nenhuma das
      mudanças está errada — só o teste está afirmando um número que não é dono de afirmar.
      → Derivar o esperado de `QixGameHud.OBJECTIVE_WIDTH`. *Pronto:* `#8` e `#11` juntos passam.
      **Aplicar na branch do próprio `#8`** — um PR separado para isto recria o problema da fila.
- [ ] **A fila precisa drenar antes de crescer.** *Pronto:* menos de três PRs abertos.
> **Um item já em PR aberto não está livre.** O histórico abaixo só regista o que foi mesclado,
> e as execuções correm de hora em hora enquanto os PRs esperam revisão — em 2026-09-04 havia
> sete PRs do loop abertos ao mesmo tempo, cobrindo todo o P1 e todo o P2. Liste os PRs abertos
> do loop antes de escolher e trate os itens neles como ocupados.

### P1 — higiene estrutural (barato, destrava o resto)

- [ ] **`samples/`, `guide_examples/` e `antipixel_state_machine/` (~6,4 MB) são demos e código de
      terceiros na raiz.** Convivem com o código do jogo e poluem toda busca por `.tscn`/`.gd`.
      Levantamento de 2026-09-04: `samples/` (4,0 MB) é demo do addon `softbody2d`;
      `guide_examples/` (2,3 MB) é demo do addon `guide`; `antipixel_state_machine/` (132 KB) é
      addon de terceiros solto fora de `addons/`, **não listado na estrutura do `CLAUDE.md`** e com
      seu próprio `sample/` dentro. Os três já estão em `exclude_filter` nos dois presets de
      export, ou seja, não são shipped — o custo é só de leitura e de busca. → Decidir: podar,
      mover para fora do versionamento, ou documentar por que ficam. *Pronto:* decisão registrada
      e busca por cena do jogo retornando só cenas do jogo.
- [ ] **`addons/` tem nove addons; nenhum é referenciado pelo código do jogo.** Levantamento de
      2026-09-04: `grep -rn "res://addons/"` em `app/ game/ ui/ tools/ tests/ content/ assets/`
      retorna **zero** ocorrências — os únicos vínculos são (a) os dois autoloads de
      `project.godot` (`addons/fennara/runtime/`, `addons/godot_ai/runtime/`), (b) o único plugin
      de editor ligado (`addons/godot_ai/plugin.cfg`) e (c) caches gerados em `.godot/`. O
      `export_filter` já exclui em bloco `GDDraw`, `curve2collision`, `curved_lines_2d`, `guide`,
      `phantom_camera`, `softbody2d` e `yard`, e exclui `fennara`/`godot_ai` só parcialmente — o
      que `PROJECT_CONTRACT.md` §Ownership já discute em prosa. Falta a **tabela**. → Registrar em
      `docs/PROJECT_CONTRACT.md`. *Pronto:* tabela addon → consumidor → shipped/editor-only.
- [ ] **`node_2d.tscn` órfão na raiz.** Cena vazia de 103 bytes, sem referência. É exatamente o
      tipo de resíduo que ensina o próximo leitor que a raiz é um depósito. → Remover, ou
      justificar por escrito se algo depender dela. *Pronto:* raiz sem arquivo não explicado.
- [ ] **Podar as três pastas de demos de terceiros da raiz: `samples/` (4,0 MB, 6 cenas),
      `guide_examples/` (2,3 MB, 32 cenas) e `antipixel_state_machine/` (132 KB, 3 cenas).**
      O inventário de addons (histórico, 2026-09-04) já provou o que faltava saber: nenhuma das
      três tem consumidor no código do jogo, e as três já estão nos `exclude_filter` dos dois
      presets de `export_presets.cfg`. Ou seja, **o custo delas é 100 % de leitura e busca, 0 % de
      payload** — são 41 das 142 cenas de terceiros que enterram as 2 cenas do jogo. `samples/` é
      demo do `softbody2d` e `guide_examples/` é demo do `guide`; se um dia esses addons forem
      usados, o demo se rebaixa do upstream. → Remover, uma pasta por commit, com o porquê no PR.
      *Pronto:* `find . -name '*.tscn'` fora de `addons/` retornando só cenas do jogo.
- [ ] **`addons/` tem nove addons; nem todos parecem usados** (`softbody2d`, `curve2collision`,
      `GDDraw`, `yard`, `curved_lines_2d`, `phantom_camera`). → Mapear quem é realmente carregado
      pelo runtime e quem é ferramenta de editor; registrar em `docs/PROJECT_CONTRACT.md`.
      *Pronto:* tabela addon → consumidor → shipped/editor-only.
      **Em revisão no PR #2** — não pegar de novo até fechar.
- [ ] **`antipixel_state_machine/` é a última raiz de terceiros não decidida.** 3 cenas, 7 scripts,
      132 KB, e **nenhum arquivo de `game/`, `ui/`, `app/`, `tools/`, `tests/` ou `content/` o
      referencia** (verificado por grep em 2026-09-04). O `.gitignore` já recusa o PDF do vendor,
      o que sugere que a pasta entrou sem decisão. Foi deixada de fora da poda dos demos por
      disciplina de "uma pasta por vez" e porque, ao contrário de `samples/`/`guide_examples/`,
      ela não é demo de um addon presente em `addons/` — pode ser dependência real adormecida.
      → Confirmar se algo a carrega em runtime antes de remover. *Pronto:* mantida com
      consumidor nomeado, ou removida com a mesma evidência de posse de `uid://` usada na poda.

### P2 — integridade de contexto

- [ ] **Decidir o destino dos sete addons dormentes** — `guide`, `curved_lines_2d`,
      `phantom_camera`, `GDDraw`, `softbody2d`, `curve2collision`, `yard` (11,5 MB, 101 cenas).
      O inventário provou que nenhum é habilitado, nenhum é referenciado e todos já são excluídos
      do export. Não é P1 porque `addons/` é uma pasta que todo leitor de Godot sabe ignorar — mas
      11,5 MB de dependência dormente é uma decisão adiada, não um estado neutro, e o próximo
      leitor não tem como saber se `phantom_camera` é lixo ou plano. → ADR curta: remover, ou
      declarar quais ficam como reserva e por quê. *Pronto:* nenhuma pasta em `addons/` sem uma
      linha que diga por que ela está lá.
- [ ] **Nenhum `docs/*.md` declara sua data de última verificação.** Documento sem data envelhece
      em silêncio e vira mentira confiante. → Cabeçalho padronizado com data e commit de
      verificação. *Pronto:* todo doc de `docs/` datado.
- [ ] **O repositório não tem CI: `.github/workflows/` não existe.** Verificado em 2026-09-04 no
      PR da guarda de invariantes — os checks do GitHub voltam `total_count: 0`. Consequência: toda
      guarda deste projeto (a suíte inteira, e agora `domain_purity_test.gd`) só roda quando alguém
      lembra de rodar. Um invariante defendido apenas na máquina de quem lembra é meio invariante —
      e o loop de agente, que abre PR atrás de PR, é exatamente quem mais precisa de um verde
      independente. → Workflow mínimo: baixar Godot 4.7.2 headless Linux, `--import`, `run_tests.gd`
      e `verify_m2_capture_route.gd`. Atenção a dois fatos já conhecidos: os erros de
      `libfennara.*.so` são esperados (binário não versionado) e não podem derrubar o job, e o
      export/QA de shipping **não** roda em Linux. *Pronto:* PR do loop nasce com check verde ou
      vermelho sem intervenção humana.
- [ ] **Invariante 1, segunda metade: "só inteiros e ponto fixo 8.8" continua sem guarda.**
      `tests/unit/domain_purity_test.gd` (histórico, 2026-09-04) cobre a primeira metade — símbolo
      do mundo real citado no domínio. A varredura **não** procura `float` porque hoje ela ficaria
      vermelha em código existente e legítimo: `GameSession.transition_progress()`
      (`game/session/game_session.gd:37-41`) devolve `float` derivado de dois contadores inteiros
      de tick. Isso não lê o mundo real, mas também não é ponto fixo 8.8 — é uma conveniência de
      apresentação morando na camada de sessão. → Decidir: mover a conversão para quem apresenta
      (a view já tem os dois inteiros) e então proibir `float` no domínio, ou declarar a exceção
      por escrito no `CLAUDE.md`. *Pronto:* ou a regra `float` entra no scanner, ou a exceção está
      escrita e justificada onde o invariante está enunciado.
- [ ] **Invariante 6 ("apresentação observa, nunca muta") não tem guarda mecânica.** Mais difícil
      que o 1 e o 4: não é um símbolo proibido, é uma direção de chamada. → Investigar se uma
      varredura barata prova algo de útil (ex.: nenhuma view atribui a campo de `BoardState` ou
      chama `step(`), ou se só um teste de comportamento resolve. *Pronto:* ou a guarda existe, ou
      está registrado por escrito por que ela não é viável estaticamente.
- [ ] **Checksum/replay não têm teste de regressão explícito contra mudança estética.** →
      Teste que roda uma rodada, guarda o checksum, e falha se ele mudar sem bump de versão
      declarado. *Pronto:* invariante 8 do `CLAUDE.md` mecanicamente defendido.
- [ ] **Não existe CI: o repositório não tem `.github/workflows/`.** Constatado em 2026-09-04
      pelo PR #5 — zero check runs no PR. Consequência: a única evidência de que a suíte passa é
      o corpo do PR, escrito por quem propôs a mudança; nada revalida no merge, e um PR que
      quebre a suíte entra em `main` sem resistência. Isso é especialmente caro num projeto cujo
      contrato é determinismo e checksum, e cujo agente afirma "verde" a cada hora. → Workflow
      que baixe o Godot 4.7.2 headless, rode `--import` e depois `tests/run_tests.gd` e
      `tools/verify_m2_capture_route.gd`. *Pronto:* um PR com teste quebrado de propósito é
      barrado pelo próprio GitHub, não pela leitura do revisor.

- [ ] **Nenhum `docs/*.md` declara sua data de última verificação.** Documento sem data envelhece
      em silêncio e vira mentira confiante. → Cabeçalho padronizado com data e commit de
      verificação. *Pronto:* todo doc de `docs/` datado.
- [ ] **Os invariantes do `CLAUDE.md` não têm teste que os defenda.** Um invariante só existe se
      algo falha quando ele é violado. → Teste que varra `game/simulation`, `game/rules` e
      `game/session` procurando `randi(`, `randf(`, `RandomNumberGenerator`, `Time.`, `Input.`,
      `delta`, `Tween`. *Pronto:* teste vermelho ao introduzir a violação de propósito.
- [ ] **Cobertura dourada só alcança a rodada 1.** `replay_checksum_golden_test.gd` fixa o
      `config_hash` das três rodadas, mas só roda uma rota (177 ticks, uma captura) na rodada 1.
      R2 e R3 têm perfis de boss diferentes (PURSUIT, SWEEP) cujas trajetórias nenhum checksum
      literal cobre. → Estender a rota dourada para as três rodadas, ou justificar por escrito
      que o `config_hash` basta. *Pronto:* cada perfil de boss de produção tem pelo menos um
      checksum final fixado, ou uma nota dizendo por que não precisa.
**Em revisão não é feito, mas também não é livre.** Um item com PR aberto não deve ser pego de
novo: escolha o próximo. Confirme com `gh pr list --state open` (ou o MCP do GitHub) antes de
decidir — a lista abaixo é a foto da última run, não a verdade corrente.

### P1 — higiene estrutural (barato, destrava o resto)

- [~] **`node_2d.tscn` órfão na raiz.** Cena vazia de 103 bytes, sem referência. É exatamente o
      tipo de resíduo que ensina o próximo leitor que a raiz é um depósito. → Remover, ou
      justificar por escrito se algo depender dela. *Pronto:* raiz sem arquivo não explicado.
      **PR #1 aberto (2026-09-04).**
- [~] **`samples/` e `guide_examples/` (~6 MB) são demos de addons de terceiros.** Convivem com o
      código do jogo e poluem toda busca por `.tscn`/`.gd`. → Decidir: podar, mover para fora do
      versionamento, ou documentar por que ficam. *Pronto:* decisão registrada e busca por cena
      do jogo retornando só cenas do jogo. **PR #4 aberto (2026-09-04).**
- [~] **`addons/` tem nove addons; nem todos parecem usados** (`softbody2d`, `curve2collision`,
      `GDDraw`, `yard`, `curved_lines_2d`, `phantom_camera`). → Mapear quem é realmente carregado
      pelo runtime e quem é ferramenta de editor; registrar em `docs/PROJECT_CONTRACT.md`.
      *Pronto:* tabela addon → consumidor → shipped/editor-only. **PR #2 aberto (2026-09-04).**

### P2 — integridade de contexto

- [~] **Os invariantes do `CLAUDE.md` não têm teste que os defenda.** Um invariante só existe se
      algo falha quando ele é violado. → Teste que varra `game/simulation`, `game/rules` e
      `game/session` procurando `randi(`, `randf(`, `RandomNumberGenerator`, `Time.`, `Input.`,
      `delta`, `Tween`. *Pronto:* teste vermelho ao introduzir a violação de propósito.
      **PR #3 aberto (2026-09-04).**
- [~] **Checksum/replay não têm teste de regressão explícito contra mudança estética.** →
      Teste que roda uma rodada, guarda o checksum, e falha se ele mudar sem bump de versão
      declarado. *Pronto:* invariante 8 do `CLAUDE.md` mecanicamente defendido.
      **PR #5 aberto (2026-09-04).**

### P3 — experiência e estética (o alvo real)

- [ ] **A pontuação não acompanha a subida do contador.** `06-gameplay.md §6.3` mostra que no
      original cada degrau do contador **paga pontos**, e é isso que faz o número na barra
      superior pulsar junto com a área. Aqui o score é domínio e chega inteiro num tick, então
      só a percentagem é encenada — o rótulo `S ######` continua saltando. → Avaliar se o HUD
      pode encenar a subida do score pelos mesmos degraus, lendo o valor já confirmado.
      *Pronto:* score e percentagem sobem juntos, sem que o HUD toque no domínio.
- [ ] **Ritmo do risco: trilha longa deve doer.** Verificar se o custo de uma trilha longa está
      legível *antes* da morte (luminância, som, háptica) e não só no impacto. *Pronto:* o jogador
      consegue nomear o momento em que ficou exposto.
- [ ] **Curva de percentagem e feedback de progresso.** `06-gameplay.md` descreve como o Volfied
      calcula e apresenta a percentagem em passos discretos. Comparar com o `permille` atual e
      avaliar se a leitura de progresso no HUD tem a mesma clareza de "quanto falta".
      *Pronto:* ADR ou nota com o número adotado e a citação da seção de origem.
- [ ] **Ritmo do risco: som e háptica da exposição.** O canal visual foi feito (`TrailExposure`,
      PR #9): o pulso da trilha acelera e clareia, e o HUD nomeia o limiar. Faltam os outros dois
      canais que o item original citava — um cue de áudio que suba com a exposição e um toque
      háptico ao cruzar `TrailExposure.WARNING_RATIO`. Depende do item de envelopes de áudio
      abaixo, que define prioridade entre vozes. *Pronto:* cruzar o limiar é audível e tátil, com
      prioridade declarada, sem alterar checksum.
- [ ] **Calibrar a curva de exposição com jogo real.** `TrailExposure` usa piso 8 px (o mesmo
      `new_segment_slow_px` do domínio) e teto geométrico `(w+h)/4` = 127 px no campo de produção.
      Os dois números são justificáveis no papel e **não foram vistos em jogo** — a sessão de
      nuvem não roda o jogo. *Pronto:* alguém joga as três rodadas e confirma (ou corrige) onde
      o aviso deve nascer.
- [ ] **Tipografia e ritmo do HUD.** `07-texto-e-fonte.md` mostra um HUD construído sprite a
      sprite. Avaliar espaçamento, alinhamento e hierarquia do HUD atual em 240×320 — texto que
      compete com o campo é ruído. *Pronto:* HUD legível em 1× sem esconder decisão de movimento.
- [ ] **Envelopes de áudio por evento.** `05-som.md` descreve o formato de sequência e o YM2203.
      Traduzir o *comportamento* (ataque curto, cauda, prioridade entre vozes) para os envelopes
      procedurais atuais. *Pronto:* cada cue tem intenção declarada e prioridade documentada.
- [ ] **`BOUNDARY`×`TRAIL` a 1,04:1 — a decisão mais cara do jogo no canal mais frágil.** A
      medição de 2026-09-04 (`docs/ART_DIRECTION.md`, “Contraste medido”) mostra contorno e trilha
      com a mesma luminância nas quatro paletas; “estou protegido” × “estou desenhando” depende de
      matiz mais o glint/pulso do shader. Resolver mexe no rosto do jogo e **exige olho humano na
      tela** — uma sessão headless mede, não aprova. Caminhos: baixar a luminância de `BOUNDARY`,
      subir a de `TRAIL`, ou dar ao contorno uma trama espacial mais grossa que sobreviva a 1 px.
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
      núcleo e pelo halo de `accent_color`. Achado colateral da medição, ainda não quantificado.
      *Pronto:* contraste jogador × chão medido em `BOUNDARY` e em `FREE`, e decisão registrada.
- [ ] **Forma do envelope por intenção.** Metade do item "envelopes de áudio" ficou de fora do PR
      de prioridade: `QixProceduralAudioLibrary._attack_release` é **o mesmo envelope para os dez
      cues**, com attack e release proporcionais à duração. Consequência medível: `death` (0,42 s)
      só atinge amplitude cheia ~34 ms depois do início, e `game_over` (0,75 s) ~60 ms — um
      impacto com fade-in não é um impacto. Os cues curtos (`trail`, `shield`) não sofrem disso.
      → Attack/release autorados por cue na receita, ao lado de `intent` e `priority`; ataque em
      milissegundos absolutos, não em fração da duração. *Pronto:* teste que mede o frame de pico
      do PCM e exige que os cues de impacto piquem em ≤ 8 ms, e que os de anúncio mantenham a
      subida suave que já têm.
- [ ] **Acessibilidade cromática.** A barra de qualidade em `ART_DIRECTION.md` exige que estado
      não dependa só de cor. Verificar por simulação de deuteranopia/protanopia se `TRAIL`,
      `BOUNDARY` e `FREE` continuam distinguíveis. *Pronto:* contraste de luminância medido e
      registrado.
- [ ] **Transição entre rodadas.** Intro/clear existem; avaliar se a *continuidade* (score,
      vidas, ameaça crescente) é sentida ou apenas exibida. *Pronto:* a passagem conta uma
      progressão, não mostra um relatório.

## Notas de ambiente (sandbox de nuvem)

Verificado em 2026-09-04: o build Linux headless `4.7.2-stable` baixa sem bloqueio de rede e
reporta `4.7.2.stable.official.ed1daf0bf`. O `--import` obrigatório roda até o fim (sai com 0,
384 passos de reimport) e **não** exige mono. Suíte completa e `verify_m2_capture_route.gd`
rodam em segundos. Ou seja: nesta sessão não há desculpa para PR sem verificação — se uma
execução futura não rodou os comandos, o motivo tem que ser dito, não omitido.

Ruído esperado na saída: o autoload de ferramental imprime
`[godot_ai game_helper] registered mcp capture` ao final de todo script headless. Não é erro.
## Pendências conhecidas

- **Cinco PRs do loop estão abertos e `main` não andou desde `74c173a`.** O loop produz mais
  rápido do que a revisão acontece, e todos os PRs saem do mesmo commit: espere conflito em
  `docs/LOOP_LEDGER.md` a cada merge. Ao resolver, mantenha a linha `> **Verificado em**` de cada
  doc — `tests/unit/doc_freshness_header_test.gd` recusa doc sem cabeçalho.
- **P3 é a próxima fronteira e nenhum item dele foi tocado.** Quando os P1/P2 acima estiverem
  mesclados, o loop deixa de fazer higiene e passa a mexer em experiência: aí valem em dobro os
  invariantes 6 e 8, porque estética que muda checksum é vazamento para o domínio.

## Histórico

**A tabela abaixo está congelada. Não apense nada a ela.** O histórico agora é um arquivo por
execução em [`docs/loop/runs/`](loop/runs/README.md) — a tabela era o ponto onde toda execução
escrevia na mesma linha, e por isso todo par de PRs do loop colidia aqui (78 conflitos em 78
pares, medidos no PR #14). Não apague as linhas antigas nem os arquivos de execução: um loop que
esquece o que tentou repete o que falhou.

| Data (UTC) | Item | PR | Resultado |
|---|---|---|---|
| 2026-09-04 | P0 · portão de verificação headless em GitHub Actions | (este) | verde no runner real (134/0); sonda confirmou que o portão fica vermelho |
| 2026-09-04 | P1: remoção de `node_2d.tscn` órfão da raiz + levantamento de addons/demos para o backlog | `ai/loop-20260904T*` | verde — 134 testes, 11489 asserções, 0 falhas; rota M2 825‰ |
| 2026-09-04 | P1 `addons/`: inventário addon → consumidor → destino no export, em `PROJECT_CONTRACT.md` | #2 | verde — 134 testes / 11 489 asserções / 0 falhas; rota M2 179→825 ‰ |
| 2026-09-04 | P1 `node_2d.tscn` órfão | #1 | em revisão (aberto por outra execução; não reivindicado aqui) |
| 2026-09-04 | P1: poda de `samples/` e `guide_examples/` (demos de vendor) + § Raízes de terceiros no contrato | #4 | verde — 134 testes, 11489 asserções, 0 falhas; rota 17,9→82,5% com `errors: []` |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |

### Notas da execução de 2026-09-04 (poda dos demos)

O que ficou provado e não precisa ser reinvestigado:

- **A dependência apontava só para dentro.** Os 5 `uid://` que `samples/`/`guide_examples/`
  compartilhavam com o resto do repositório são **de posse de `addons/`** (guide e softbody2d):
  os demos referenciavam os addons, nunca o contrário. Por isso a remoção não quebrou nada.
- **O custo era real, não só estético.** As duas pastas eram 38 das 43 cenas do repositório — o
  jogo em si tem 2 (`app/bootstrap.tscn`, `ui/`) — e `guide_examples/virtual_sticks/projectile/`
  registrava `class_name LaserProjectile` no namespace **global** do projeto.
- **Os `exclude_filter` foram mantidos de propósito.** `export_presets.cfg` e
  `tests/integration/shipping_export_test.gd` seguem citando `guide_examples/**` e `samples/**`.
  Não é resíduo: um checkout que rebaixe os addons pela AssetLib recria as pastas em disco, e o
  filtro cobre um caminho que o `.gitignore` não cobre. **Não "limpar" isso numa execução futura.**
- **Ruído de ambiente a ignorar na nuvem.** Todo `--import` aqui emite 3 erros de
  `GDExtension dynamic library not found` para `addons/fennara/bin/libfennara.linux.editor.x86_64.so`.
  O binário é gitignored por decisão registrada; verificado por A/B que o erro aparece igual **com
  e sem** a mudança. Não é regressão e não vale investigar de novo.
- **O critério de pronto do item foi cumprido só em parte, e isso é deliberado.** Buscar por cena
  ainda devolve `addons/**` (101 cenas de vendor, item do PR #2) e `antipixel_state_machine/`
  (3 cenas, agora item próprio no backlog). O que sumiu foi a poluição que não tinha dono.
| 2026-09-04 | P2 guarda mecânica dos invariantes 1 e 4: `tests/unit/domain_purity_test.gd` | (este) | verde — 138 testes / 11 547 asserções / 0 falhas; vermelho comprovado com violação plantada e revertida |
| 2026-09-04 | P1 `addons/`: inventário addon → consumidor → destino no export | #2 | aberto por outra execução; não reivindicado aqui |
| 2026-09-04 | P1 `node_2d.tscn` órfão | #1 | aberto por outra execução; não reivindicado aqui |
| 2026-09-04 | P2: cabeçalho de verificação em todo `docs/*.md` + guarda em teste | (esta branch) | verde — 136 testes, 11.513 asserções, 0 falhas |
| 2026-09-04 | P3 curva de percentagem: contador do HUD sobe em degraus (ADR-0009) | `ai/loop-20260904T120237Z` | verde — 137 testes, 11.501 asserções, 0 falhas; rota M2 inalterada (179→825) |
| 2026-09-04 | P3 ritmo do risco: `TrailExposure`, pulso da trilha por exposição, aviso nomeado no HUD | #9 | verde (140 testes, 11.552 asserções, 0 falhas; rota M2 179→825‰; `p95` do BoardView em 1 µs) |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |

### Notas de execução — 2026-09-04 (guarda de invariantes)

- **Escolha do item.** Os dois P1 restantes já tinham PR aberto (#1 e #2) e #2 reescreve o item
  de poda de `samples/`/`guide_examples/` no backlog. Atacar qualquer um deles seria duplicar ou
  conflitar, então esta execução subiu para o P2 disjunto de ambos.
- **Por que o scanner limpa comentário e literal antes de casar.** A varredura ingênua sugerida no
  backlog (`delta`, `Input.`, `Tween` como palavras cruas) acusa código legítimo: `delta` é o
  **inteiro** de pontuação em `_add_score`, e o cabeçalho de `game_simulation.gd` cita "Input,
  Tween" justamente para dizer que não os usa. Um teste que grita no código correto é desligado na
  segunda semana — por isso `_strip_comments_and_strings` existe, e por isso `delta` cru não é
  regra: quem entra é `_process`/`_physics_process`/`get_process_delta_time`, que é por onde o
  delta de quadro realmente entraria.
- **Por que o scanner testa a si mesmo.** Uma guarda estática que erra o caminho ou a regex vira um
  teste verde permanente que não olha nada — falha silenciosa pior que a ausência do teste. Daí as
  amostras positivas/negativas e a asserção de que a varredura encontrou arquivos.
- **Ambiente.** Godot 4.7.2-stable Linux headless (não-mono) baixado no sandbox; `--import` rodado.
  Os erros de `libfennara.linux.editor.x86_64.so` na saída são pré-existentes e esperados — o
  binário do GDExtension não é versionado. `tools/profile_board_view.gd` **não** foi executado:
  nada nesta mudança toca `BoardView`, a máscara R8 ou custo por quadro.
| 2026-09-04 | P2: teste dourado de checksum/replay (invariantes 7 e 8) | #5 | verde — 138 testes, 11.515 asserções, 0 falhas; guarda provada vermelha com domínio perturbado e verde com cor perturbada |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |

### Fila de revisão — leia antes de escolher item

O loop abre PR mais rápido do que a revisão humana mescla. Em 2026-09-04T09:00Z havia **cinco
PRs abertos e nenhum mesclado**, todos com base no commit inicial:

| PR | Item do backlog |
|---|---|
| #1 | P1 — cena órfã `node_2d.tscn` |
| #2 | P1 — inventário dos nove addons |
| #3 | P2 — varredura estática dos invariantes 1 e 4 |
| #4 | P1 — poda de `samples/` e `guide_examples/` |
| #5 | P2 — checksum dourado (invariantes 7 e 8) |

Consequências práticas para a próxima execução:

1. **Confira os PRs abertos antes de escolher** (`gh pr list --state open`, ou o equivalente MCP).
   Um item já coberto por PR aberto não está livre só porque o checkbox do backlog continua vazio —
   o backlog não é atualizado até o merge.
2. **Espere conflito em `docs/`.** Todo PR do loop toca `LOOP_LEDGER.md`, e vários tocam
   `TEST_MATRIX.md`. A contagem final da suíte nesse arquivo (`138 testes, 11.515 asserções`) é
   válida para o #5 isolado; quem mesclar depois precisa recontar, não somar de cabeça.
3. **Prefira arquivos novos a edições em arquivos disputados.** A descoberta de testes em
   `run_tests.gd` varre diretório, então dois PRs podem acrescentar arquivos de teste sem
   se tocarem — foi o que permitiu #3 e #5 coexistirem.
| 2026-09-04 | P3 acessibilidade cromática: medição de contraste por estado, catraca e registro | ai/loop-20260904T110520Z | verde; dívida encontrada e registrada |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |

### Notas da execução de 2026-09-04 11h

Todos os itens P1 e P2 deste backlog já tinham PR aberto (#1 a #6) e nenhum deles estava mesclado.
Por isso a execução subiu para P3 em vez de duplicar trabalho. **Uma próxima execução deve olhar
`gh pr list --state open` antes de escolher: o backlog abaixo ainda descreve P1/P2 como pendentes
porque esses PRs vivem em branches, não em `main`.**

O item de acessibilidade cromática foi entregue como o critério pedia — *medido e registrado* —,
não como correção de paleta. Trocar cor de estado sem ver a tela seria escrever no rosto do jogo
sem olhar para ele; os três itens que nasceram da medição estão no topo de P3 com o que falta.
| 2026-09-04 | P3 envelopes de áudio, parte 1: cada cue declara intenção e prioridade; alocação de voz deixa de ser rodízio cego | `ai/loop-20260904T140000Z` | verde — 138 testes, 11555 asserções, 0 falhas; rota M2 byte-idêntica |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |

### Notas da execução de 2026-09-04T14Z

- O `main` deste checkout ainda é o commit de fundação: **nove PRs do loop estão abertos e nenhum
  foi mesclado** (`#1`–`#9`). Isso significa que o backlog abaixo continua mostrando como abertos
  itens que já têm PR: P1 inteiro (`#1`, `#2`, `#4`), P2 inteiro (`#3`, `#5`, `#6`) e três de P3
  (`#7` contraste, `#8` percentagem, `#9` trilha longa). **Antes de escolher um item, confira
  `gh pr list --state open`** — o ledger do `main` não sabe o que está em revisão.
- Restam sem PR aberto, em P3: *tipografia e ritmo do HUD*, *transição entre rodadas* e a parte 2
  dos envelopes (acima).
- Achado que motivou o PR desta execução: `QixHapticFeedback` já tinha uma escada de prioridade
  (morte 100 … respawn 30) e escolhia **um** pulso por tick, mas `QixAudioDirector` despachava
  todos os cues num rodízio cego de oito vozes. Som e háptica podiam discordar sobre qual era o
  acontecimento do tick, e o cue mais frequente podia truncar o mais importante. A escada agora é
  uma só, com teste que falha se as duas divergirem.
