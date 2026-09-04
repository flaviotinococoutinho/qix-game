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
