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
| Contador de percentagem sobe em degraus | `docs/decisions/ADR-0009` |
| Identidade visual é *Lumen Cartography* | `docs/ART_DIRECTION.md` |
| Volfied é referência de gênero, não alvo de clone | `reference/volfied/README.md` |

## Backlog — prioridade decrescente

Cada item diz **o que**, **por que importa para a experiência** e **como saber que ficou bom**.
Itens sem critério de pronto não entram aqui.

> **Um item já em PR aberto não está livre.** O histórico abaixo só regista o que foi mesclado,
> e as execuções correm de hora em hora enquanto os PRs esperam revisão — em 2026-09-04 havia
> sete PRs do loop abertos ao mesmo tempo, cobrindo todo o P1 e todo o P2. Liste os PRs abertos
> do loop antes de escolher e trate os itens neles como ocupados.

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

- [ ] **A pontuação não acompanha a subida do contador.** `06-gameplay.md §6.3` mostra que no
      original cada degrau do contador **paga pontos**, e é isso que faz o número na barra
      superior pulsar junto com a área. Aqui o score é domínio e chega inteiro num tick, então
      só a percentagem é encenada — o rótulo `S ######` continua saltando. → Avaliar se o HUD
      pode encenar a subida do score pelos mesmos degraus, lendo o valor já confirmado.
      *Pronto:* score e percentagem sobem juntos, sem que o HUD toque no domínio.
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
| 2026-09-04 | P3 curva de percentagem: contador do HUD sobe em degraus (ADR-0009) | `ai/loop-20260904T120237Z` | verde — 137 testes, 11.501 asserções, 0 falhas; rota M2 inalterada (179→825) |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |
