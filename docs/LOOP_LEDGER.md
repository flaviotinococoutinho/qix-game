# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-08 · commit `5318d0a` · Godot 4.7.2-stable, Linux headless (sandbox de nuvem)
> **Alcance:** esta revisão do cabeçalho fecha o item de direção do #74 e ajusta o backlog; a fila
> foi conferida no GitHub às 06:00Z e estava em **zero PRs abertos**. Tudo abaixo desta linha é
> histórico preservado, medido nos commits e ambientes que cada bloco declara — não foi reexecutado aqui.
> **Revisão de 2026-09-08T22:00Z** (mesmo ambiente, head `859f4e4` desta branch): corrigido o
> inventário composto #98+#99 que esta PR publicava — `414` casos medidos às 11:00Z, **416** hoje —
> e reescrita a instrução para derivar em vez de copiar. A fila tinha **cinco** PRs abertas nessa
> conferência (#98–#102), acima dos tetos das regras 7 e 8. Alcance: só os dois números e a redação
> ao redor; nada de `game/`, `ui/`, `app/` ou `content/` foi tocado, e nenhum outro bloco histórico
> foi reverificado.
> A integração de `3f2d96e` continua sendo a fonte do estado da fila descrito a seguir.
> **Alcance da integração:** as **33 PRs de origem, #59–#91**, foram incorporadas pela [PR #92](https://github.com/flaviotinococoutinho/qix-game/pull/92).
> Merge efetivo em 2026-09-08T05:33:34Z; as 33 PRs constavam como MERGED e a fila estava vazia na conferência às 05:33:37Z.
> Atlas Vivo (`0c63665`), Godot AI 4.0.2 (`6d23de4`), bundle #78 e resíduos foram preservados por ancestralidade.
> O [CI 34190696324](https://github.com/flaviotinococoutinho/qix-game/actions/runs/34190696324) passou no head `9d02d6f`; a composição validada está incorporada em `main`.
> O [CI pós-merge 34191087087](https://github.com/flaviotinococoutinho/qix-game/actions/runs/34191087087) também passou em `3f2d96e`.
> A execução de 2026-09-08T07:04Z mexeu apenas no backlog e entregou o item #69 de procedência das
> contagens; a integração acima não foi reverificada por ela.

O usuário autorizou explicitamente nesta sessão a modernização, auditoria, revisão, correções,
integração e merges das PRs. Esta execução cumpriu esse escopo amplo: a regra rotineira de um
item por loop não exige uma segunda autorização para o trabalho já solicitado. As mutações Git,
a validação executável e a integração no GitHub foram centralizadas pelo agente coordenador.
O merge acima foi conferido no GitHub; autorização e revisão técnica, por si sós, não o
comprovariam. A mesma conta autora também não pode simular aprovação independente.

O [relato desta integração](loop/runs/2026-09-08T-mcp-github-integration.md) preserva o snapshot
inicial de 32 heads (#59–#90), suas intenções e decisões, e a incorporação posterior do #91,
totalizando 33 PRs de origem. No snapshot inicial, #78 continha integralmente 20 heads,
contando o próprio. Os 12 resíduos foram reconciliados: o passo CI do índice Python de #83
foi portado e as regressões de #90 foram adaptadas ao touch Atlas, preservando os relatos.
O #91 removeu a guarda redundante de arquivamento sem mudar a máquina de fases.
Consultar o GitHub antes de agir: a fila vazia acima é uma observação datada, não um contador automático.

O CI Linux registrou 404 testes do jogo, 19.009 asserções, zero falhas e 92 testes Python
no head `9d02d6f`, árvore `528244e11304dfed4a15d977c4ad014dd2828d87`.
O manifesto confirma `tested_head=true` e `source_unchanged=true`. O reexport macOS arm64 desse
head passou em codesign estrito e executou 900/900 ticks em 17,259 s, sem erro observado.
Renderer, MCP e limites do import/export Mono estão discriminados no relato; merge e QA
ad-hoc não equivalem a distribuição comercial, escuta crítica ou balanceamento humano.

## Histórico preservado e entrega Atlas

- A preparação anterior registrou #57–#87 sobre `ca745780`; censos de 0/22/29/30/31 PRs
  descrevem seus próprios momentos. Relatos e commits originais continuam sendo as fontes.
- Atlas foi desenvolvido sobre `feat/lumen-threat-roster`, base `a1afb90`, preservando o WIP
  de input, pools e diretor. O usuário pediu evolução ampla e uso do MCP Blender.
- O resultado local anterior à composição está preservado em `0c63665`: lifecycle comum,
  IDs/pools, ameaças justas, balizas, quatro itens, bônus, campanha/replay v4, GLBs originais,
  palco 2.5D, F2/F3/F4 e feedback. A decisão corrente é a
  [ADR-0014](decisions/ADR-0014-atlas-lifecycle-depth-stage.md); ADR-0012 continua sendo cursor ink.
- Na árvore Atlas anterior, em macOS, 2026-09-07, foram registrados 260 testes / 13.598 asserções / zero falhas e
  20 verificações em renderer real. A evidência detalhada está em [ATLAS_VIVO.md](ATLAS_VIVO.md).
  Esses números não são o inventário nem o resultado da composição atual.
- Não restaurar goldens v3 ou caminhos anteriores à taxonomia `game/simulation/{board,enemies,
  player,director,objectives,time,scoring,replay}`. O arquivo dourado v4 foi preservado de `0c63665`.
  M2 isola mecanismos e não prova desafio; a campanha ativa possui sua própria rota/replay.

## Protocolo (obrigatório)

1. **Leia este arquivo inteiro antes de decidir o que fazer.** Ele vem depois do `CLAUDE.md` e
   antes de qualquer edição.
2. **Liste os PRs abertos do loop antes de escolher.** Um item com PR aberto não está livre.
   Consulte o estado atual no GitHub. Use `tools/loop/unclaimed_surface.sh` antes de escolher
   (heurística por refs e camada) e `tools/loop/merge_queue_report.sh` depois de escolher.
   Refs de branches não provam, sozinhos, que os respectivos PRs continuam abertos.
3. **No loop rotineiro, escolha exatamente UM item** de maior prioridade que caiba num PR
   revisável. Pedidos explícitos mais amplos do usuário têm precedência, como a integração
   de setembro/08 registrada acima; decomponha esse trabalho com ownership e evidências claras.
4. **Escreva o relato em `docs/loop/runs/<carimbo>.md`** — arquivo novo, seu. Não apense a uma
   tabela de histórico: era ali que toda execução escrevia na mesma linha, e por isso os 78 pares
   de PRs colidiam. Ver `docs/loop/runs/README.md`.
5. **Ajuste o backlog deste arquivo no mesmo PR.** O backlog continua compartilhado de propósito:
   duas execuções que mexem no mesmo item *devem* se encontrar aqui.
6. **Nunca reabra um item de "Decisões fechadas"** sem argumento novo e explícito no PR. Essa
   seção existe para impedir que o loop oscile entre duas opções para sempre.
7. **Meta-PR tem teto.** Um PR sobre a fila só é legítimo se trouxer uma medição ainda ausente
   nos meta-PRs abertos e nomear quais supera. Sem evidência nova, registre o achado no relato
   da execução, sem abrir outro PR redundante. Origem: #53 e o censo de posse de 2026-09-06.
   O limite operacional é dois PRs do loop em andamento; com o limite atingido, priorize revisão
   e correção dos existentes, não a geração de uma nova mudança sobre os mesmos arquivos.
8. **Um só PR do loop que toque testes, enquanto a matriz declarar inventário global.**
   Medido em 2026-09-08T14:00Z sobre o head do #98: `docs/TEST_MATRIX.md` carrega uma linha de
   inventário derivado (`75 arquivos · 411 casos`) e **três** afirmações `N testes, M asserções,
   K falhas` que `test_matrix_inventory_test.gd` obriga a repetirem os mesmos números. Qualquer PR
   que acrescente ou altere um caso reescreve essas mesmas quatro linhas do mesmo arquivo, e é
   isso que faz duas PRs do loop colidirem **por construção**, não por azar. O teto de dois da
   regra 7 vale para PRs que não tocam a suíte; para os que tocam, o teto é **um**.
9. **Não reande a sonda de composição.** Quatro execuções (08:00Z, 09:00Z, 11:00Z, 12:00Z) mediram
   a mesma composição #98 × #99 e publicaram quatro totais de asserções diferentes — 20262, 20256,
   20265, 20272 — porque as guardas de documento assertam por linha varrida e o total **depende do
   texto da própria resolução**. A sonda não converge e o número não é transferível: só o
   inventário derivado — arquivos `*_test.gd` e funções `test_*` — sobrevive à mudança de redação.
   **Mas derive-o, não o copie.** Esta regra publicava `76 arquivos · 414 casos`; era a verdade da
   sonda de 11:00Z e envelheceu sozinha quando o **#99** ganhou dois casos às 16:05Z. Um literal de
   inventário é evidência datada como qualquer outra: quem for mesclar recalcula
   `casos(A) + casos(B) − casos(main)` sobre os heads do momento e confere com o runner.
   Uma execução que encontre o teto
   atingido **escala ao mantenedor** — a fila só anda com um merge, que o loop não pode dar — e
   registra isso no relato, em vez de gastar a hora remedindo o que já está medido.

### Legenda do backlog (convenção de #34)

| Marca | Significado |
|---|---|
| `- [ ]` | Livre. Nenhum PR aberto o reivindica. |
| `- [~]` | **Reivindicado por um PR aberto.** Não escolha: o trabalho existe, só não mesclou. |
| `- [x]` | Entregue e mesclado em `main`. |

Quem drena a fila troca por `[x]` os `[~]` que mesclaram. Um `[~]` cujo PR foi fechado sem
mesclar volta a `[ ]`, com uma linha dizendo por quê.

### Ao resolver conflito de documentação

Mantenha a linha `> **Verificado em**` de cada doc — `tests/unit/doc_freshness_header_test.gd`
recusa doc sem cabeçalho. E **não resolva este arquivo por união automática**: o resultado passa
nos testes e mente para o leitor. A integração de 23:00Z produziu 703 linhas com cinco seções de
"estado da fila" contraditórias e três ordens de merge concorrentes. Backlog reconcilia-se à mão. O #86 mediu perda de itens mesmo com P0–P3 e o total de entradas
preservados: conferir intenção/achados por delta contra a merge-base, não só contagem ou títulos.
Não aplicar `ours`/`theirs` global; preservar a base integrada e reaplicar achados ainda relevantes.

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
| `addons/` só hospeda pasta com estado declarado | `docs/decisions/ADR-0010` |
| A ameaça tem contorno que não depende de cor | `docs/decisions/ADR-0011` |
| Cursor legível com tinta própria | `docs/decisions/ADR-0012-cursor-ink-outline.md` |
| Atlas, lifecycle e palco 2.5D com domínio 2D preservado | `docs/decisions/ADR-0014-atlas-lifecycle-depth-stage.md` |
| Identidade visual é *Lumen Cartography* | `docs/ART_DIRECTION.md` |
| Volfied é referência de gênero, não alvo de clone | `reference/volfied/README.md` |
| Histórico do loop é um arquivo por execução | `docs/loop/runs/README.md` |
| `samples/` e `guide_examples/` podados; `exclude_filter` fica | `docs/loop/runs/`, poda dos demos |
| `antipixel_state_machine/` podado | `docs/loop/runs/2026-09-05T035826Z.md` |

## Backlog — prioridade decrescente

### P0 — integração e capacidade de revisão

- [x] **Integração Atlas + bundle #78 e fila #59–#91, autorizada pelo usuário.**
  A PR #92 foi mesclada em `3f2d96e25f42b8833e53099cce55619f25ec59c5`, preservando os
  33 heads de origem, Atlas e plugin. Resíduos, contratos, testes e documentação foram
  reconciliados na branch isolada, com checks e evidências ligados ao head `9d02d6f`.
  As 33 PRs de origem constam como MERGED; a conferência de fechamento encontrou zero PRs abertas.
- [ ] **Decidir a cadência do loop (#85, ADR-0013 em Proposta).** A PR da proposta foi
  mesclada via #92, mas a recomendação de branch diária não foi aceita automaticamente.
  O item volta a livre porque nenhum PR aberto o reivindica; agendamento externo não foi alterado.
  *Pronto:* decisão do mantenedor registrada e scheduler coerente com ela.
- [ ] **Manter esforço no jogo, não só no mecanismo.** O censo histórico do #85 distingue
  runtime, guardas, documentação e poda. *Pronto:* medir em dez execuções se pelo menos
  uma em cada três modifica `game/`, `ui/`, `app/` ou `content/`.
  **Medido e reprovado em 2026-09-09: 0 de 15** (`docs/loop/runs/2026-09-09T035930Z.md`, na #102).
  A execução de 06:30Z quebrou a série tocando `game/simulation/enemies/` e `game/enemies/`.
  A causa apontada era a fila cheia; a de 06:30Z mostra que a regra 7 não proibia trabalho de
  jogo, porque nenhuma PR aberta toca `game/`, `ui/`, `app/` ou `content/` — o que colide é só
  o inventário derivado de `TEST_MATRIX.md`. Remedir depois da drenagem, com essa distinção.
- [x] **Unificar relatórios da fila (#71, via #92).** `merge_queue_report.sh --order` substitui
  `merge_order_report.sh`; a verificação de sintaxe cobre os scripts do loop. Preservar o
  relatório de superfície, cuja pergunta é diferente. Mudança integrada e CI verde no head `9d02d6f`.

**Lições preservadas:** #55 integrou #20–#54 em `34634d0` e #56 reconciliou esse estado;
35 PRs exigiram quatro esforços, dois superados. A incompatibilidade #25×#50 era semântica:
um PR removeu `GameSession.transition_progress()` e outro ainda o chamava. Já o #67 precisa
aceitar o estado final legítimo da ADR-0010: zero pastas `a-remover`. #78 contém essa resolução.
**Portada para o próprio #67 em 2026-09-08**, para que a guarda não dependesse da ordem de merge:
o head auditado do #67 já trazia `EMPTY_TOTALS_ROW` e a correção de `not doomed.is_empty()` idênticas às
do #78, medidas nos dois sentidos (as sete removidas com o fecho escrito ficam **verdes**; com o
plural sobrevivente ficam **vermelhas**). A guarda deixou de proibir o seu próprio fim. Continua
sem forma, no helper histórico `NUMERALS`, o caso de **uma** pasta restante, que seria alcançado
mesclando as sete uma a uma. A integração entregou o caso zero de uma vez; não há sexta remoção
pendente nem motivo para restaurar pastas só para exercitar esse estado intermediário.
As medições #76, #80 e #86 demonstraram outro acoplamento: a guarda #69 exige atualizar a matriz
para o inventário da **árvore final**, não somar números copiados das descrições dos PRs.

### P1 — higiene estrutural e evidência

- [x] **Sete remoções da ADR-0010 (#60, #62, #63, #64, #66, #72, #73, via #92).** Respectivamente:
  `curved_lines_2d`, `phantom_camera`, `guide`, `GDDraw`, `yard`, `softbody2d`, `curve2collision`.
  #78 consolida a tabela de addons, as contagens, os filtros de export e o caso zero do #67.
  Não remover os filtros de export só porque a pasta saiu: uma reinstalação local pode recriá-la.
  As sete pastas estão ausentes na integração, com manifesto coerente e guardas verdes.
- [x] **Matriz vinculada à árvore (#69; composição observada em #80 e #86, via #92).**
  A descoberta de testes varre diretórios. Contagem e inventário derivados conferem com o
  runner da composição validada; consultar TEST_MATRIX, sem somar os inventários históricos
  dos PRs. Shipping histórico continua identificado como histórico.
- [x] **Não versionar bytecode Python (#83, via #92).** Regras globais `__pycache__/` e `*.py[cod]`,
  remoção do bytecode já rastreado inclusive o acrescentado por #79. A guarda textual não
  consulta o índice Git: conferir também `git ls-files`. Ambos os exames passaram na composição.
  **Os dois exames existem desde 2026-09-08:** a guarda em GDScript prova a regra, e o passo
  «Bytecode de Python fora do índice» de `verificacao.yml` prova o índice com `git ls-files` —
  é ele que apanha o bytecode que #79 traz, porque `.gitignore` não expulsa arquivo já rastreado.

- [x] **Cobrir o parser Metal HUD no gate (#83, via #92).** O passo «Regressões MCP, assets
  e parser Metal» de `verificacao.yml` executa a descoberta Python em `tools/profile`,
  incluindo `test_parse_metal_hud.py`. O CI do head `9d02d6f` passou com essas regressões;
  a cobertura contínua do parser não prova desempenho GPU em hardware alvo.

### P2 — integridade de contexto e contratos

- [x] **Contrato de `session.records` (#49, via #55).** Só tentativas realmente terminadas
  geram registros; forçar uma fase não equivale a executar a transição.
- [x] **Resolver `GameSession._current_archived` (#58, entregue por #91 via #92).** O achado
  perdido na reconciliação foi resolvido removendo o booleano redundante. A máquina de fases
  continua responsável pelo arquivamento. A regressão exige no máximo um registro por passo,
  apenas a partir de PLAYING, e confirma os terminais e todas as tentativas de vitória/derrota.
- [x] **Integrar o contrato de VELOCITY do Atlas (via #92).** O item já é produtor real de aceleração,
  com timer inteiro e piso de velocidade normal no início do segmento. A flag explícita
  `speedup_active` permanece no checksum, sem duplicar o timer. A guarda antiga de regras
  inertes foi adaptada: isolamento sem itens e captura de produção com passo rápido/replay.
  Regressão passou na composição final e o contrato v4 está publicado em main.
- [x] **Pausa e ciclo de vida do áudio (#70, via #92).** Música e vozes usam guarda coerente;
  shutdown solta a pausa. A liberação de vozes deve continuar zerando prazos e rodízio,
  inclusive ao desabilitar áudio, sem depender de shutdown. Regressões verdes incluem pausar,
  desligar/religar som e retomar, preservando a posição de música apenas suspensa.
- [x] **Cobertura de pureza do boss (#68, via #92).** O controller agora está em
  `game/simulation/enemies/boss_behavior_controller.gd`, coberto pela pasta de domínio.
  O scanner ampliado foi preservado e as exceções do caminho antigo foram removidas das guardas.
- [x] **Exceção visual em regras (#74, via #92).** `RoundVisualDefinition` admite cores; isso não
  autoriza outros Resources de domínio a ler `float` ou consumir a apresentação. A costura
  RoundContent também é declarada; serializadores são derivados do grafo real, sem count=2.
- [x] **Guarda geral de direção em `game/session/` (#74).** Resposta medida à pergunta larga de
  `docs/loop/runs/2026-09-07T100000Z.md`: **todas as demais** dependências de apresentação
  passavam. `var _hud: QixGameHud` em `GameSession` e `var _tint := Color("ff00ff")` em
  `GameSimulation` deixavam a suíte inteira verde (404 testes, 19013 asserções, 0 falhas).
  `tests/unit/domain_direction_guard_test.gd` fecha a seta domínio→apresentação com a lista de
  proibidos **derivada** dos `class_name` das pastas de apresentação (uma view nova nasce proibida),
  mais 31 tipos da engine declarados com motivo, mais a proibição de herdar de nó. A cobertura
  nominal do visual foi preservada intacta na guarda irmã. Duas guardas cruzadas impedem a
  duplicação (um nome já acusado por `domain_purity_test.gd` fica vermelho aqui — foi assim que
  `Tween` ficou de fora) e a divergência de `PRESENTATION_DIRS` entre as duas guardas de direção.
  Medição das três mutações plantadas em `docs/loop/runs/2026-09-08T060505Z.md`.
  **Buraco encontrado e fechado na revisão de 10:00Z** (`docs/loop/runs/2026-09-08T100000Z.md`):
  a guarda varria duas pastas digitadas e **não lia `DOMAIN_FILES`** da guarda irmã — a lista que
  a invariante 1 usa para admitir domínio fora das pastas. Um arquivo declarado nas duas listas
  como manda o contrato, contendo `var _hud: QixGameHud` e um `Color`, atravessava a suíte inteira
  **verde** (410 testes, 20252 asserções, 0 falhas): pureza guardada, direção livre. A guarda
  cruzada da irmã não o apanhava porque conhece duas guardas, e esta é a terceira. Agora
  `_domain_files()` funde as pastas com `DOMAIN_FILES`, e
  `test_the_guard_covers_every_domain_file_the_sibling_declares` faz pelo lado do domínio o
  confronto que já existia pelo lado da apresentação: `game/rules/` só fica fora por constar em
  `DOMAIN_DIRS_EXCLUDED_ON_PURPOSE` com motivo escrito. **Lição:** confrontar uma ponta das duas
  guardas e não a outra é meia seta guardada — e o lado não conferido é o que ninguém olha.
  **O que continua sem guarda, de propósito:** um `Variant` nunca anotado, ou um objeto de
  apresentação recebido por parâmetro sem tipo, atravessa as três varreduras. É semântica, não
  sintaxe — só revisão e teste de comportamento alcançam.
  **Revisão de 11:00Z** (`docs/loop/runs/2026-09-08T110042Z.md`): a prosa da matriz dizia
  `6 casos` onde a aritmética dá **7** (411 − 404, e sete funções `test_*` no arquivo) — corrigido.
  E esta PR **conflita** com a **#99** em `LOOP_LEDGER.md` e `TEST_MATRIX.md`: as duas declaram
  `75 arquivos`, contando só a própria guarda. Compostas, a árvore tem **76 arquivos · 416 casos**,
  derivados em 2026-09-08T22:00Z sobre os heads `859f4e4` (#98) e `735ed50` (#99), em Linux
  headless: `411 + 409 − 404`, confirmado contando os arquivos e as funções `test_*` da árvore
  mesclada. **Recalcule antes de usar.** A revisão de 22:00Z encontrou aqui `414`, medido às
  11:00Z e já falso desde 16:05Z, quando o #99 cresceu — ver
  `docs/loop/runs/2026-09-08T220000Z.md`. Quem mesclar o **segundo** precisa
  reconciliar o ledger à mão, derivar o inventário dos heads que estiver mesclando e **reexecutar**
  a suíte para a contagem de asserções: somar as duas ou copiar o número da sonda planta evidência
  falsa, e um inventário literal com data velha planta a mesma coisa mais devagar.
- [x] **Documentação da integração reconciliada (#65, #76, #77, #82, #84, via #92).** Decisões de arte referenciadas,
  geometria atual distinguida de tempos históricos, disponibilidade de Git corrigida,
  seções e chaves de tabela reconciliadas. Guardas e inspeção da integração passaram; a dívida
  específica de contagens históricas em linhas isoladas continua no item abaixo.
  **A guarda textual de contradição foi medida e recusada — não a construa.** O #82 rodou a
  heurística de «duas linhas de tabela com a mesma primeira coluna» sobre 5.020 arquivos `.md`
  (árvore + 79 branches): ela pega o erro do #21 (31 branches com 11.547 vs 11.515 asserções na
  mesma linha), mas com ≈3 % de precisão no repositório — só o `reference/volfied/` dispara ~1.040
  vezes com mapas de registradores legítimos — e ≈48 % mesmo restrita a `docs/*.md`, onde metade
  dos disparos é coluna de categoria. As variantes «`> **Verificado em**` duplicado» e «heading
  repetido» disparam zero vezes. E nenhuma das três pegaria os dois erros que o #82 achou, que são
  *números certos para outra árvore* e *afirmação verdadeira ontem e falsa hoje*. **Derivar vence
  vigiar:** é o caminho do #69, e a matriz derivada desta branch já o exerce. Medição completa em
  `docs/loop/runs/2026-09-07T180244Z.md`.
- [ ] **Procedência da licença raiz (#73).** Preservar o aviso de `IMPLEMENTATION_STATUS`:
  não substituir titularidade ou licença sem decisão do mantenedor e verificação de direitos.
- [x] **Contagem de outro ambiente parece atual fora da matriz (#69).** `SHIPPING_PASS.md` nomeia
  o run no título da seção e carrega uma coluna **Origem** por linha; `TEST_MATRIX.md` e
  `ATLAS_VIVO.md` tiveram suas linhas carimbadas ou marcadas como derivadas.
  `tests/unit/doc_suite_count_provenance_test.gd` guarda a regra: **linha que se lê sozinha** —
  linha de tabela ou início de item de lista — em `docs/*.md` afirmando `N testes`/`M asserções`
  diz ambiente **e** data, ou declara-se derivada da árvore (contagem derivada não leva data,
  senão a guarda plantaria a mentira que existe para impedir).
  **Prosa corrida fica fora de propósito e não deve ser trazida para dentro:** `PERFORMANCE.md`
  qualifica seus números na frase seguinte, e exigir carimbo por linha ali repetiria a heurística
  de baixa precisão que o #82 mediu e recusou. Precisão medida nesta entrega: 8 acusações sobre os
  nove docs vivos, todas verdadeiras, zero falso positivo. Relato em
  `docs/loop/runs/2026-09-08T070425Z.md`.
  A guarda de inventário ficou vermelha com o arquivo novo e a matriz foi **remedida**, não
  copiada: 409 testes / 19.041 asserções / 0 falhas na árvore desta branch, Linux headless.
  **Revisão de 2026-09-08T16:00Z, na mesma branch:** a porta da contagem derivada aceitava a
  palavra `árvore` sozinha, e com isso `134 testes, 11.489 asserções, 0 falhas naquela árvore` —
  os números de macOS de 2026-09-03, sem ambiente nem data — atravessava a suíte **verde**.
  Citar a árvore de onde o número veio é o contrário de declarar procedência: é a doença, com a
  palavra certa dentro. As marcas passaram a nomear **esta** árvore, e a linha viva da árvore
  Atlas neste próprio arquivo — que passava pelo mesmo buraco — foi carimbada. A varredura
  também não descia para as quatro subpastas de `docs/`, e o cabeçalho da guarda só declarava
  duas: as quatro agora constam com motivo, e uma pasta nova fica vermelha até alguém decidir.
  *Continua fora do alcance:* a guarda de inventário confere casos e arquivos contra a árvore,
  mas **não** as asserções — nesta execução `19.044` passou verde antes de a medição dizer
  `19.041`. Fechar isso mudaria o custo de todo PR que mexe em teste; é decisão do mantenedor.

### P3 — experiência e estética

Já estão em `main` via #55: envelopes por cue, contorno da ameaça (ADR-0011), score encenado,
háptica de exposição, âncora flutuante do toque, proa do cursor, foco de captura, trava do eixo
analógico, fase contínua da trilha e cadência de transição. Isso não equivale a aprovação estética.

- [x] **Contorno próprio do cursor (#75, ADR-0012, via #92).** Geometria e contraste
  automatizados preservados para o cursor Atlas sem contaminar o checksum. A aprovação
  humana da leitura em movimento continua no item de QA abaixo.
- [x] **Cue sonoro de exposição (#61, via #92).** Som e háptica leem a mesma aresta confirmada;
  a prioridade do aviso não deve encobrir captura ou morte. Escuta física permanece pendente.
- [x] **Causa da morte no HUD (#79, via #92).** Duração segue a fase DYING e não um prazo fixo;
  a mensagem termina na reentrada, inclusive com duração de morte curta ou longa.
- [x] **Âncora da direção da ameaça (#87, via #92).** Intenção de aderir à silhueta real
  preservada, com a prova adaptada aos corpos/pás/GLBs Atlas. Rumos e direção nula são
  testados sem alterar o domínio nem restaurar o enemy_view antigo para satisfazer o losango.
- [x] **Distribuição das marcas de captura (#81, via #92).** A sequência integrada evita
  ressonância dos passos modulares em focos usuais e preserva contenção, repetibilidade
  e isolamento da apresentação.
- [x] **Geometria real do HUD (#52, via #55).** A sonda executa frames; medir Label apenas
  em `_initialize()` não reproduz sua geometria final.
- [~] **O aviso do dardo mostra o corredor real (achado de 2026-09-09, fora do backlog).**
  O armamento desenhava `direction * 5.0` — cinco células — enquanto `dart_min_range` vale 24 e
  o dardo nasce por backtrack *a partir* do jogador. O alvo não conseguia ler que estava na mira.
  `DartRules.peek_path` é leitura pura com a mesma aritmética de `update()`, e a view desenha o
  corredor só em WARMUP. Teto de 48 células (o dobro de `dart_min_range`) por custo medido: sem
  ele, seis dardos armados custavam 4,768 ms/frame; com ele, 0,54 ms. Corredor que bate no teto
  perde a ponta de seta, porque seta significa «morre aqui». *Pronto:* entregue e verde
  (408/19131, rota M2 intacta, checksum dourado imóvel); **falta** a leitura em tela, que vai
  junto no item de QA humana abaixo. Ver `docs/loop/runs/2026-09-09T063041Z.md`.
- [ ] **Contraste `BOUNDARY`×`TRAIL`.** A dívida de luminância não foi resolvida nesta revisão.
  Medido de novo em 2026-09-08 (Linux headless): 1,04–1,05:1 nas quatro paletas, meta 3:1.
  **Dois caminhos já foram investigados e recusados — não reandar sem argumento novo.** (a) Tinta
  própria, como ADR-0011 e ADR-0012: impossível, porque uma célula de campo é **um pixel lógico**
  (`CoordinateSpace`, campo 225×283 em viewport 240×320) — não há sub-célula onde desenhar
  contorno, e a trilha tem um pixel de largura. (b) Vale do pulso descendo até a luminância de
  `FREE`: separaria de `BOUNDARY`, mas apagaria parte da trilha contra `FREE`, que é o chão onde
  ela passa a partida inteira — piora a legibilidade que o critério manda preservar.
  Sobra a decisão de paleta, com dono humano: escurecer `boundary_color` ou `trail_color` mexe em
  `FREE`×`BOUNDARY` (9,0–10,0:1) e `FREE`×`TRAIL` (11,2–12,9:1), hoje folgados.
  *Pronto:* decisão visual, catracas atualizadas e confirmação numa tela, sem piorar legibilidade.
- [x] **Toque estável (#90, via #92).** Regressões de jitter/arrasto integradas e verdes,
  preservando floating stick, histerese de entrada/saída, margem angular e flick do Atlas.
  Ergonomia em dispositivo real continua no item de QA humana.
- [ ] **QA humana de controles, áudio e composição.** Calibrar margem analógica, toque,
  exposição, pulso, contornos, foco e proa com jogo real. Teste headless não cobre esse mérito.

### P4 — evolução do produto após a integração

- [ ] **Playtest humano dos três setores e calibração por causa de morte.** A rota automática
  prova possibilidade e determinismo, não aprendizado, percepção de justiça ou diversão.
- [ ] **Encontros adicionais, armas e dano ao chefe.** Desenhar contratos e rotas antes de
  expandir campanha, múltiplos chefes ou o repertório completo de Volfied.
- [ ] **Custo de captura e hardware alvo.** Medir picos, frame pacing do palco, temperatura e
  lifecycle Android; provas históricas de shipping plano não certificam os GLBs.

## Ambiente e limites de validação

Godot requerido: 4.7.2-stable. A execução corrente é macOS; o gate remoto usa Linux headless.
Importar uma vez por checkout
antes da suíte; uma classe nova pode exigir nova importação. O gate isola explicitamente o
descritor nativo Fennara ausente, preservando os scripts runtime. Não tratar `ERROR` de startup
como ruído aceitável: o gate deve reprovar diagnósticos inesperados mesmo com exit code zero.
Essa modalidade **não valida a extensão nativa**, render GPU, alto-falantes, Android ou assinatura.

Notas operacionais preservadas do #79: liberar nós de UI em todos os caminhos de teste evita
leaks de Label/TextServer que podem reprovar o gate mesmo com zero falhas de asserção. Medir
layout após frames; a altura de Label em `_initialize()` pode ainda não ter assentado. A opção
de isolar a extensão nativa requer checkout limpo, não editar um cache registrado à força.
A saída dos testes Python pode criar __pycache__; conferir índice e ignorados antes de stage.

## Histórico

Relatos originais: `docs/loop/runs/`. Os commits originais das PRs são mantidos como ancestrais.
A preparação não transforma resultados antigos em evidência atual. Consultar os logs e o
manifesto da execução vinculada ao head/árvore da PR antes de aprovar ou mesclar.
