# LOOP_LEDGER — memória entre execuções do agente

Um agente de nuvem roda de hora em hora e **começa sem contexto**. Este arquivo é a única
memória que atravessa execuções. Sem ele, a run nº 7 desfaz a nº 3 sem saber que ela existiu.

## Protocolo (obrigatório)

1. **Leia este arquivo inteiro antes de decidir o que fazer.** Ele vem depois do `CLAUDE.md` e
   antes de qualquer edição.
2. **Rode `tools/loop/merge_queue_report.sh` antes de escolher.** Ele diz quais itens já têm PR
   aberto e, sobretudo, em que arquivos a sua mudança vai colidir em silêncio com a fila. Escolher
   sem olhar a fila é como o par `#8×#11` nasceu.
3. **Escolha exatamente UM item** do backlog — o de maior prioridade que caiba num PR pequeno e
   revisável. Um PR grande não é produtividade: é uma revisão que não vai acontecer.
4. **Atualize este arquivo dentro do mesmo PR**: mova o item para o histórico, ajuste o backlog
   com o que você aprendeu, registre o que ficou pendente.
5. **Nunca reabra um item de "Decisões fechadas"** sem um argumento novo e explícito no PR. Essa
   seção existe para impedir que o loop oscile entre duas opções para sempre.

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

## Fila de merge — medida em 2026-09-04T18:00Z

**A fila está travada: 13 PRs abertos, nenhum mesclado, `main` ainda com 2 commits.** Todos os
13 ramificam do mesmo `main` e todos editam este arquivo — logo **os 78 pares conflitam**, sem
exceção. Cada execução do loop acrescenta um PR e nenhum sai; o trabalho já feito só vale
quando alguém mesclar.

Reproduza com `tools/loop/merge_queue_report.sh` (não altera `main` nem a árvore de trabalho):

| Classe | Pares | Leitura |
|---|---|---|
| Conflito só no ledger | 78 de 78 | mecânico: todo run escreve aqui, por contrato |
| Conflito fora do ledger | `#3×#5`, `#3×#9`, `#7×#8` — todos em `docs/TEST_MATRIX.md` | linhas apensas no mesmo ponto; resolução trivial |
| **Sobreposição silenciosa** | `#8×#9`, `#8×#11`, `#9×#11` — todos em `ui/game_hud.gd` | o git aceita; o teste é que decide |

### A regressão #8 × #11 — medida, não suposta

`#8×#11` funde **sem conflito textual** e quebra dois testes
(`QIX_GODOT_BIN=... tools/loop/merge_queue_report.sh --verify 8 11`):

```
FAIL  game_hud_test.gd::test_percent_counter_climbs_by_denomination_instead_of_snapping
FAIL  game_hud_test.gd::test_percent_counter_snaps_back_when_progress_regresses
145 testes, 11536 asserções, 2 falhas
```

A asserção que cai é *"a barra conta a mesma história que o número"*: esperado 6 px, obtido 11;
esperado 15, obtido 25. A lógica do contador de #8 está intacta — o que quebrou é que o teste de
#8 **fixa larguras em pixels derivadas do grid anterior**, e #11 re-autora exatamente esses
números ao dar ao HUD uma grade explícita. Nenhum dos dois PRs pode ver isso sozinho.

`#8×#9` e `#9×#11` passam (0 falhas). Só o par `#8×#11` é incompatível.

### Ordem de merge recomendada

1. **#13 primeiro** (portão headless em CI). Mesclado por último, ele não verifica nada; mesclado
   primeiro, todos os outros passam a ser checados sozinhos.
2. **#1 e #4** — remoções puras (cena órfã, demos de vendor). Zero sobreposição com código.
3. **#6, depois #2** — #6 dá cabeçalho de data a todos os docs; #2 escreve por cima em
   `PROJECT_CONTRACT.md` sem conflito.
4. **#3 e #5** — só testes. O conflito `#3×#5` em `TEST_MATRIX.md` são duas linhas apensas: manter
   as duas.
5. **#7 e #10** — contraste e áudio, sem sobreposição.
6. **HUD, nesta ordem: #9, depois #11, e só então #8 rederivado.** #8 não pode entrar como está:
   o teste dele precisa ler as constantes de grade que #11 introduz em vez de repetir 6 e 15 à mão.
7. **#12** — só ledger; superseded por esta seção. Fechar ou absorver.

## Backlog — prioridade decrescente

Cada item diz **o que**, **por que importa para a experiência** e **como saber que ficou bom**.
Itens sem critério de pronto não entram aqui.

### P0 — a fila (nada mais avança enquanto isto não anda)

- [ ] **Drenar a fila de 13 PRs.** Só um humano pode mesclar; o loop não mescla o próprio PR. Até
      lá cada execução produz trabalho que não chega ao jogo, e o custo de integração cresce.
      → Mesclar na ordem acima. *Pronto:* `main` com mais de 2 commits e a fila em ≤ 2 PRs abertos.
- [ ] **Este arquivo é o ponto único de conflito da fila.** 78 de 78 pares colidem aqui porque
      toda execução apensa uma linha ao mesmo ponto do "Histórico" e marca o mesmo backlog. →
      Mitigar movendo o histórico para um arquivo por execução (`docs/loop/runs/<carimbo>.md`),
      deixando o ledger com decisões e backlog. Mitiga, não resolve: o backlog continua
      compartilhado. *Pronto:* duas execuções seguidas do loop sem conflito no histórico.
- [ ] **Nenhum PR do loop mede a própria colisão com os outros abertos.** Cada execução verifica
      a sua mudança contra `main`, nunca contra a fila. → Rodar
      `tools/loop/merge_queue_report.sh` no passo de orientação, antes de escolher o item.
      *Pronto:* sobreposição silenciosa detectada no run que a cria, não três runs depois.

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

## Histórico

Uma linha por execução. Mais recente no topo. Não apague: um loop que esquece o que tentou
repete o que falhou.

| Data (UTC) | Item | PR | Resultado |
|---|---|---|---|
| 2026-09-04T18:00 | Fora do backlog: mediu a fila travada (13 PRs, 78/78 pares em conflito), isolou a regressão `#8×#11` e deixou `tools/loop/merge_queue_report.sh` para a próxima execução | este | verde (suíte em `main`: 134 testes, 0 falhas) |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |
