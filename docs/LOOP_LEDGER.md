# LOOP_LEDGER — memória entre execuções do agente

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

**A tabela abaixo está congelada. Não apense nada a ela.** O histórico agora é um arquivo por
execução em [`docs/loop/runs/`](loop/runs/README.md) — a tabela era o ponto onde toda execução
escrevia na mesma linha, e por isso todo par de PRs do loop colidia aqui (78 conflitos em 78
pares, medidos no PR #14). Não apague as linhas antigas nem os arquivos de execução: um loop que
esquece o que tentou repete o que falhou.

| Data (UTC) | Item | PR | Resultado |
|---|---|---|---|
| 2026-09-04 | P0 · portão de verificação headless em GitHub Actions | (este) | verde no runner real (134/0); sonda confirmou que o portão fica vermelho |
| 2026-09-04 | P1: remoção de `node_2d.tscn` órfão da raiz + levantamento de addons/demos para o backlog | `ai/loop-20260904T*` | verde — 134 testes, 11489 asserções, 0 falhas; rota M2 825‰ |
| 2026-09-03 | Fundação: repo git válido, `CLAUDE.md`, `reference/volfied/`, este ledger | — (commit inicial) | verde |
