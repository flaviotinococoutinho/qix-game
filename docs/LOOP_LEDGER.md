# LOOP_LEDGER — memória entre execuções do agente

Um agente de nuvem roda de hora em hora e **começa sem contexto**. Este arquivo é a única
memória que atravessa execuções. Sem ele, a run nº 7 desfaz a nº 3 sem saber que ela existiu.

## Protocolo (obrigatório)

1. **Leia este arquivo inteiro antes de decidir o que fazer.** Ele vem depois do `CLAUDE.md` e
   antes de qualquer edição.
2. **Escolha exatamente UM item** do backlog — o de maior prioridade que caiba num PR pequeno e
   revisável. Um PR grande não é produtividade: é uma revisão que não vai acontecer.
3. **Atualize este arquivo dentro do mesmo PR**: mova o item para o histórico, ajuste o backlog
   com o que você aprendeu, registre o que ficou pendente.
4. **Nunca reabra um item de "Decisões fechadas"** sem um argumento novo e explícito no PR. Essa
   seção existe para impedir que o loop oscile entre duas opções para sempre.
5. **Leia "Fila de revisão" antes do backlog.** Um item com PR aberto já foi feito: pegá-lo de
   novo produz um segundo PR que compete com o primeiro pelo mesmo arquivo. Se todos os itens
   estiverem em revisão, o trabalho da execução **não é abrir o 12º PR** — é verificar a fila
   (ver "Verificação de integração", abaixo).

## Fila de revisão — o que já está aberto

Esta seção existe porque a fila cresce mais rápido do que a revisão humana. Sem ela, cada
execução redescobre a fila do zero e, na dúvida, duplica.

**Estado em 2026-09-04T16:00Z: 11 PRs abertos, nenhum mergeado — o backlog inteiro está em
revisão.** Cada PR saiu de `main` de forma independente e todos editam este arquivo, então
**mergear qualquer um deixa os outros dez em conflito** (só neste arquivo, e em
`docs/TEST_MATRIX.md` para os PRs #5, #8 e #9 — nenhum `.gd` conflita textualmente).

| PR | Item do backlog | Testes no próprio head |
|---|---|---|
| #1 | P1 · cena órfã `node_2d.tscn` | 134 testes, 0 falhas |
| #2 | P1 · inventário dos nove addons | 134 testes, 0 falhas |
| #3 | P2 · varredura estática dos invariantes 1 e 4 | 138 testes, 0 falhas |
| #4 | P1 · poda de `samples/` e `guide_examples/` | 134 testes, 0 falhas |
| #5 | P2 · checksums dourados de replay | 138 testes, 0 falhas |
| #6 | P2 · data de verificação em cada doc | 136 testes, 0 falhas |
| #7 | P3 · contraste por estado do campo | 141 testes, 0 falhas |
| #8 | P3 · percentagem em degraus | 137 testes, 0 falhas |
| #9 | P3 · ritmo do risco na trilha longa | 140 testes, 0 falhas |
| #10 | P3 · intenção e prioridade dos cues | 138 testes, 0 falhas |
| #11 | P3 · grade verificável do HUD | 142 testes, 0 falhas |

Quem mergear: preferir a ordem `#1, #2, #4` (higiene, diff mecânico), depois `#3, #5, #6`
(testes de invariante), por fim os de apresentação. Antes de `#8` e `#11` juntos, ler o achado
abaixo.

### Verificação de integração — o que um PR sozinho não vê

Cada PR foi verificado contra `main` isoladamente. Isso não diz nada sobre o que acontece
quando dois deles coexistem. Com os onze aplicados juntos (conflitos de doc resolvidos à mão),
a suíte dá **3 falhas** que nenhum head individual acusa:

- **`#8` × `#11` — regressão real, merge textualmente limpo.** `#11` alarga
  `OBJECTIVE_WIDTH` de `50.0` para `86.0` ao dar grade ao HUD; `tests/unit/game_hud_test.gd`,
  de `#8`, afirma a largura do preenchimento em píxeis literais (`6`, `15`, `2`) derivados da
  largura antiga. O git não vê conflito porque `#8` não toca na constante e `#11` não toca no
  contador. *Correção:* o teste de `#8` deve derivar o esperado de `GameHud.OBJECTIVE_WIDTH`
  em vez de fixar píxeis — a intenção do teste ("a barra conta a mesma história que o número")
  é uma razão, não uma medida. Enquanto isso não for feito, **`#8` e `#11` não devem ser
  mergeados um sem o outro ser reverificado.**
- **`#6` — falha latente na resolução de conflito.** O teste de frescor exige cabeçalho de
  verificação nas primeiras seis linhas de todo `docs/*.md`. Qualquer resolução de conflito
  neste arquivo ou em `docs/TEST_MATRIX.md` que descarte o cabeçalho quebra a suíte. Resolver
  conflito de doc aqui é preservar o cabeçalho, não escolher um lado.

Pares verificados: `#8+#9` e `#9+#11` ficam verdes; `#8+#11` dá as duas falhas acima.

**Procedimento** (uma execução que encontra a fila saturada deve repeti-lo, não abrir PR novo):
`git fetch origin '+refs/pull/*/head:refs/remotes/pr/*'`, mergear os heads numa branch
descartável, `--import`, rodar `tests/run_tests.gd`, e registrar aqui o que só aparece junto.

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
| Identidade visual é *Lumen Cartography* | `docs/ART_DIRECTION.md` |
| Volfied é referência de gênero, não alvo de clone | `reference/volfied/README.md` |

## Backlog — prioridade decrescente

Cada item diz **o que**, **por que importa para a experiência** e **como saber que ficou bom**.
Itens sem critério de pronto não entram aqui.

### P0 — destrava a fila (nada abaixo importa enquanto isto não sair)

- [ ] **A fila de revisão está saturada: 11 PRs abertos, zero mergeados.** O gargalo deixou de
      ser produzir melhoria e passou a ser integrá-la. Cada PR novo empilha mais um conflito
      neste arquivo e adia a chegada dos onze anteriores ao jogo. → Enquanto a fila não drenar,
      a execução deve **verificar integração e registrar** (ver "Fila de revisão"), não abrir
      trabalho novo. *Pronto:* fila abaixo de três PRs abertos.
- [ ] **`tests/unit/game_hud_test.gd` (PR #8) fixa píxeis em vez de derivar da constante.**
      Faz o teste falhar quando `#11` alarga `OBJECTIVE_WIDTH`, embora nenhuma das duas mudanças
      esteja errada. Um teste que quebra por um número que ele não é dono de afirmar treina o
      leitor a ignorá-lo. → Derivar o esperado de `GameHud.OBJECTIVE_WIDTH`. *Pronto:* `#8` e
      `#11` juntos passam. **Aplicar na branch do próprio `#8`** — abrir um PR separado para
      isto recria o problema que esta seção descreve.
- [ ] **Nenhum PR do repositório roda verificação automática.** Consultado em 2026-09-04, o PR #12
      tem zero check runs; nenhum dos doze foi verificado por outra coisa senão uma execução do
      loop rodando Godot à mão. É por isso que a colisão `#8`×`#11` sobreviveu a onze
      verificações: cada uma olhou um PR contra `main`, e ninguém olhou dois PRs juntos. → Um
      workflow que baixe o Godot 4.7.2 headless, rode `--import`, `tests/run_tests.gd` e
      `tools/verify_m2_capture_route.gd` no *merge* do PR com a base. *Pronto:* um PR que quebra
      a suíte fica vermelho sozinho, sem depender de alguém lembrar de olhar.

### P1 — higiene estrutural (barato, destrava o resto)

- [ ] **`node_2d.tscn` órfão na raiz.** Cena vazia de 103 bytes, sem referência. É exatamente o
      tipo de resíduo que ensina o próximo leitor que a raiz é um depósito. → Remover, ou
      justificar por escrito se algo depender dela. *Pronto:* raiz sem arquivo não explicado.
- [ ] **`samples/` e `guide_examples/` (~6 MB) são demos de addons de terceiros.** Convivem com o
      código do jogo e poluem toda busca por `.tscn`/`.gd`. → Decidir: podar, mover para fora do
      versionamento, ou documentar por que ficam. *Pronto:* decisão registrada e busca por cena
      do jogo retornando só cenas do jogo.
- [ ] **`addons/` tem nove addons; nem todos parecem usados** (`softbody2d`, `curve2collision`,
      `GDDraw`, `yard`, `curved_lines_2d`, `phantom_camera`). → Mapear quem é realmente carregado
      pelo runtime e quem é ferramenta de editor; registrar em `docs/PROJECT_CONTRACT.md`.
      *Pronto:* tabela addon → consumidor → shipped/editor-only.

### P2 — integridade de contexto

- [ ] **Nenhum `docs/*.md` declara sua data de última verificação.** Documento sem data envelhece
      em silêncio e vira mentira confiante. → Cabeçalho padronizado com data e commit de
      verificação. *Pronto:* todo doc de `docs/` datado.
- [ ] **Os invariantes do `CLAUDE.md` não têm teste que os defenda.** Um invariante só existe se
      algo falha quando ele é violado. → Teste que varra `game/simulation`, `game/rules` e
      `game/session` procurando `randi(`, `randf(`, `RandomNumberGenerator`, `Time.`, `Input.`,
      `delta`, `Tween`. *Pronto:* teste vermelho ao introduzir a violação de propósito.
- [ ] **Checksum/replay não têm teste de regressão explícito contra mudança estética.** →
      Teste que roda uma rodada, guarda o checksum, e falha se ele mudar sem bump de versão
      declarado. *Pronto:* invariante 8 do `CLAUDE.md` mecanicamente defendido.

### P3 — experiência e estética (o alvo real)

- [ ] **Curva de percentagem e feedback de progresso.** `06-gameplay.md` descreve como o Volfied
      calcula e apresenta a percentagem em passos discretos. Comparar com o `permille` atual e
      avaliar se a leitura de progresso no HUD tem a mesma clareza de "quanto falta".
      *Pronto:* ADR ou nota com o número adotado e a citação da seção de origem.
- [ ] **Ritmo do risco: trilha longa deve doer.** Verificar se o custo de uma trilha longa está
      legível *antes* da morte (luminância, som, háptica) e não só no impacto. *Pronto:* o jogador
      consegue nomear o momento em que ficou exposto.
- [ ] **Tipografia e ritmo do HUD.** `07-texto-e-fonte.md` mostra um HUD construído sprite a
      sprite. Avaliar espaçamento, alinhamento e hierarquia do HUD atual em 240×320 — texto que
      compete com o campo é ruído. *Pronto:* HUD legível em 1× sem esconder decisão de movimento.
- [ ] **Envelopes de áudio por evento.** `05-som.md` descreve o formato de sequência e o YM2203.
      Traduzir o *comportamento* (ataque curto, cauda, prioridade entre vozes) para os envelopes
      procedurais atuais. *Pronto:* cada cue tem intenção declarada e prioridade documentada.
- [ ] **Acessibilidade cromática.** A barra de qualidade em `ART_DIRECTION.md` exige que estado
      não dependa só de cor. Verificar por simulação de deuteranopia/protanopia se `TRAIL`,
      `BOUNDARY` e `FREE` continuam distinguíveis. *Pronto:* contraste de luminância medido e
      registrado.
- [ ] **Transição entre rodadas.** Intro/clear existem; avaliar se a *continuidade* (score,
      vidas, ameaça crescente) é sentida ou apenas exibida. *Pronto:* a passagem conta uma
      progressão, não mostra um relatório.

## Ambiente da nuvem — ruído conhecido, não regressão

Não gaste uma execução investigando isto:

- `ERROR: Can't open dynamic library ... libfennara.linux.editor.x86_64.so` seguido de
  `Error loading extension: 'res://addons/fennara/fennara.gdextension'` aparece em **toda**
  execução headless, inclusive em `main` sem nenhuma alteração. `addons/fennara/bin/` não é
  versionado (e não deve ser). A suíte passa apesar do erro; ele não é sinal de nada.
- `--import` é obrigatório **também depois de cada troca de branch** que traga script novo,
  senão o cache de `class_name` não conhece a classe e a falha não é a sua mudança.

## Histórico

Uma linha por execução. Mais recente no topo. Não apague: um loop que esquece o que tentou
repete o que falhou.

| Data (UTC) | Item | PR | Resultado |
|---|---|---|---|
| 2026-09-04 | Fila saturada: verificação de integração dos 11 PRs abertos; achado `#8`×`#11` | (este) | nada de código mudou; 3 falhas só na combinação |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |
