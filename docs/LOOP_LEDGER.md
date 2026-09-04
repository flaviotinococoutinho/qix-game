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

## Notas de ambiente (sandbox de nuvem)

Verificado em 2026-09-04: o build Linux headless `4.7.2-stable` baixa sem bloqueio de rede e
reporta `4.7.2.stable.official.ed1daf0bf`. O `--import` obrigatório roda até o fim (sai com 0,
384 passos de reimport) e **não** exige mono. Suíte completa e `verify_m2_capture_route.gd`
rodam em segundos. Ou seja: nesta sessão não há desculpa para PR sem verificação — se uma
execução futura não rodou os comandos, o motivo tem que ser dito, não omitido.

Ruído esperado na saída: o autoload de ferramental imprime
`[godot_ai game_helper] registered mcp capture` ao final de todo script headless. Não é erro.

## Histórico

Uma linha por execução. Mais recente no topo. Não apague: um loop que esquece o que tentou
repete o que falhou.

| Data (UTC) | Item | PR | Resultado |
|---|---|---|---|
| 2026-09-04 | P1: remoção de `node_2d.tscn` órfão da raiz + levantamento de addons/demos para o backlog | `ai/loop-20260904T*` | verde — 134 testes, 11489 asserções, 0 falhas; rota M2 825‰ |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |
