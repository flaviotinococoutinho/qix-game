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
| 2026-09-04 | P2 guarda mecânica dos invariantes 1 e 4: `tests/unit/domain_purity_test.gd` | (este) | verde — 138 testes / 11 547 asserções / 0 falhas; vermelho comprovado com violação plantada e revertida |
| 2026-09-04 | P1 `addons/`: inventário addon → consumidor → destino no export | #2 | aberto por outra execução; não reivindicado aqui |
| 2026-09-04 | P1 `node_2d.tscn` órfão | #1 | aberto por outra execução; não reivindicado aqui |
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
