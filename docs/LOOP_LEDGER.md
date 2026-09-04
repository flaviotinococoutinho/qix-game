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
- [ ] **Envelopes de áudio por evento.** `05-som.md` descreve o formato de sequência e o YM2203.
      Traduzir o *comportamento* (ataque curto, cauda, prioridade entre vozes) para os envelopes
      procedurais atuais. *Pronto:* cada cue tem intenção declarada e prioridade documentada.
- [ ] **Acessibilidade cromática.** A barra de qualidade em `ART_DIRECTION.md` exige que estado
      não dependa só de cor. Verificar por simulação de deuteranopia/protanopia se `TRAIL`,
      `BOUNDARY` e `FREE` continuam distinguíveis. *Pronto:* contraste de luminância medido e
      registrado.
- [ ] **A geometria do HUD depende da ordem de construção.** `_add_label` só obtém o retângulo
      pedido porque atribui `size` depois de entrar na árvore; antes do primeiro frame o mínimo
      do `Label` ainda é o do tema (23 px). Funciona, mas é frágil e invisível. → Avaliar
      `custom_minimum_size` explícito ou um `Theme` do HUD com o tamanho de fonte já definido,
      para que a altura não dependa de quando `_ready` corre. *Pronto:* altura correta medida
      dentro do runner, sem a ressalva que `game_hud_layout_test.gd` documenta hoje.

- [ ] **Transição entre rodadas.** Intro/clear existem; avaliar se a *continuidade* (score,
      vidas, ameaça crescente) é sentida ou apenas exibida. *Pronto:* a passagem conta uma
      progressão, não mostra um relatório.

## Histórico

Uma linha por execução. Mais recente no topo. Não apague: um loop que esquece o que tentou
repete o que falhou.

| Data (UTC) | Item | PR | Resultado |
|---|---|---|---|
| 2026-09-04 | P3 tipografia e ritmo do HUD: grade explícita + hierarquia da percentagem | `ai/loop-20260904T150…` | verde — 142 testes, 0 falhas |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |

### O que a execução de 2026-09-04T15 aprendeu

**A banda superior estava mal proporcionada, e havia sobreposição real.** Medido com a fonte
do tema, em pior caso e a 7 px: `Round` ocupava 18 px num retângulo de 34, `Score` 30 em 61 e
`Vitals` 28 em 87 — enquanto `Percent`, a leitura primária, ficava espremida em 50. Pior:
`Round` ia até x=37 e `Score` começava em x=36, ou seja **1 px de sobreposição** que ninguém
via porque ambos são alinhados à esquerda e o texto real não chegava lá. O trilho do escudo
começava em x=151 com o rótulo em x=150.

**Armadilha para quem for escrever teste de HUD nesta base.** No contexto do runner (tudo
corre dentro de `_initialize()`, antes de a árvore processar um frame) a altura de um `Label`
fica presa a um mínimo obsoleto — 23 px, calculado com o tamanho de fonte do tema em vez do
override. Depois do primeiro frame ela assenta no valor pedido. Verificado com sonda
descartável: `Percent size=(86,14), min=(1,13)`. Ou seja: **medir X no runtime é fiável, medir
Y não é.** O comentário `# evita os 23 px padrão` em `_add_label` está correto no runtime real;
não o "corrija" com base no que o runner mostra.

**Nota de coordenação, não de código.** Nesta execução havia **dez PRs do loop abertos e
nenhum mesclado**, todos ramificados do mesmo commit de `main` e todos a editar este ficheiro.
Assim que o primeiro entrar, os outros nove conflitam no `LOOP_LEDGER.md`. Além disso o backlog
está praticamente esgotado: cada item P1/P2/P3 já tem PR aberto, exceto "Transição entre
rodadas". Uma execução futura que não encontre item livre deve preferir **um PR só de ledger**
a inventar trabalho — e vale mais rever/rebasar a fila existente do que aumentá-la.
