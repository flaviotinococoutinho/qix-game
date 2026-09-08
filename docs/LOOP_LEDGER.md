# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-08 · commit `6d23de4` · inspeção Git e integração local em andamento
> **Alcance:** fila observada de **32 PRs abertas, #59–#90**, `main` em `6136ebb`.
> Atlas Vivo (`0c63665`) e Godot AI 4.0.2 (`6d23de4`) estão preservados em commits locais.
> A branch `integrate/atlas-mcp-20260908` recebe o bundle #78 (`3c9724f`) e deltas úteis.
> Suíte, renderer/export da composição final e merges no GitHub estão **PENDENTES** nesta edição.

O usuário autorizou explicitamente nesta sessão a modernização, auditoria, revisão, correções,
integração e merges das PRs. Esta execução cumpre esse escopo amplo: a regra rotineira de um
item por loop não exige uma segunda autorização para o trabalho já solicitado. As mutações Git,
a validação executável e a integração no GitHub são centralizadas pelo agente coordenador.
Autorização e revisão técnica não são afirmações de que um merge já aconteceu; a mesma conta
autora também não pode simular aprovação independente.

O [relato desta integração](loop/runs/2026-09-08T-mcp-github-integration.md) registra os 32 heads,
intenções, decisões e evidências por árvore. O #78 contém integralmente 20 heads, contando o
próprio. Dos 12 restantes, #83 tem um passo CI de índice Python a portar; #90 exige adaptar
os testes/intenção ao touch Atlas. Os demais resíduos são sobretudo documentais ou equivalentes.
Consultar o GitHub antes de agir: o snapshot datado não é um contador automático.

## Histórico preservado e entrega Atlas

- A preparação anterior registrou #57–#87 sobre `ca745780`; censos de 0/22/29/30/31 PRs
  descrevem seus próprios momentos. Relatos e commits originais continuam sendo as fontes.
- Atlas foi desenvolvido sobre `feat/lumen-threat-roster`, base `a1afb90`, preservando o WIP
  de input, pools e diretor. O usuário pediu evolução ampla e uso do MCP Blender.
- O resultado local anterior à composição está preservado em `0c63665`: lifecycle comum,
  IDs/pools, ameaças justas, balizas, quatro itens, bônus, campanha/replay v4, GLBs originais,
  palco 2.5D, F2/F3/F4 e feedback. A decisão corrente é a
  [ADR-0014](decisions/ADR-0014-atlas-lifecycle-depth-stage.md); ADR-0012 continua sendo cursor ink.
- Na árvore Atlas anterior foram registrados 260 testes / 13.598 asserções / zero falhas e
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

- [x] **Concluir integração Atlas + bundle #78 e fila #59–#90.** ✅ mesclado (#92). `main` em
  `3f2d96e`, **0 PRs abertos** no momento da conferência, suíte **404 / 19 009 / 0 falhas** corrida
  sobre `main`. O bundle #78 está dentro (`d13aead` é ancestral de `main`) e `addons/` ficou com as
  duas pastas `ferramenta`.
- [ ] **Decidir a cadência do loop (#85, ADR-0013).** ⚠️ **Voltou a `[ ]`, e não virou `[x]`.** O
  PR mesclou e `docs/decisions/ADR-0013-cadencia-do-loop.md` está no repositório — mas o seu Status
  diz **"Proposta em 2026-09-07. Não aceita"**. O que mesclou foi o *documento que propõe*, não a
  *decisão*. Promovê-lo porque o arquivo existe seria confundir *o texto chegou* com *a decisão foi
  tomada*. **Só o mantenedor pode fechá-lo:** nenhuma execução do loop pode escolher a própria
  cadência. E é o item que fecha a torneira — a fila chegou a zero duas vezes e, da primeira,
  reformou-se em ~19 h.
  *Pronto:* Status da ADR-0013 mudado para aceita, com a opção escolhida, e o agendamento externo
  ajustado a ela no mesmo commit.
- [ ] **Manter esforço no jogo, não só no mecanismo.** O censo histórico do #85 distingue
  runtime, guardas, documentação e poda. *Pronto:* medir em dez execuções se pelo menos
  uma em cada três modifica `game/`, `ui/`, `app/` ou `content/`.
- [x] **Unificar relatórios da fila (#71).** ✅ conferido em `main`: `tools/loop/` tem só
  `merge_queue_report.sh` e `unclaimed_surface.sh`; `merge_order_report.sh` saiu e a verificação de
  sintaxe do CI cobre a pasta inteira.

**Lições preservadas:** #55 integrou #20–#54 em `34634d0` e #56 reconciliou esse estado;
35 PRs exigiram quatro esforços, dois superados. A incompatibilidade #25×#50 era semântica:
um PR removeu `GameSession.transition_progress()` e outro ainda o chamava. Já o #67 precisa
aceitar o estado final legítimo da ADR-0010: zero pastas `a-remover`. #78 contém essa resolução.
**Portada para o próprio #67 em 2026-09-08**, para que a guarda não dependa da ordem de merge:
o head do #67 traz agora `EMPTY_TOTALS_ROW` e a correção de `not doomed.is_empty()` idênticas às
do #78, medidas nos dois sentidos (as sete removidas com o fecho escrito ficam **verdes**; com o
plural sobrevivente ficam **vermelhas**). A guarda deixou de proibir o seu próprio fim. Continua
sem forma o caso de **uma** pasta restante, alcançável só mesclando as sete uma a uma — está dito
no comentário de `NUMERALS`, e quem mesclar a sexta escreve o singular.
As medições #76, #80 e #86 demonstraram outro acoplamento: a guarda #69 exige atualizar a matriz
para o inventário da **árvore final**, não somar números copiados das descrições dos PRs.

### P1 — higiene estrutural e evidência

- [x] **Sete remoções da ADR-0010 (#60, #62, #63, #64, #66, #72, #73).** ✅ conferido em `main`:
  `addons/` tem `README.md`, `fennara` e `godot_ai` — as sete saíram. Manifesto coerente e
  `addons_manifest_test.gd` verde, já com o caso zero. Os filtros de export **ficam**: uma
  reinstalação local recria a pasta e `.gitignore` não cobre o payload.
- [x] **Matriz vinculada à árvore (#69; composição observada em #80 e #86).** ✅ conferido em
  `main`: a matriz declara **74 arquivos · 404 casos**, o disco tem 74 arquivos de teste e o runner
  varreu 404 casos / 19 009 asserções. Os três números coincidem sobre a mesma árvore.
- [x] **Não versionar bytecode Python (#83).** ✅ conferido nos **dois** exames que o item exigia:
  `git ls-files` devolve **zero** arquivos `__pycache__`/`.pyc` rastreados, e `verificacao.yml` tem
  o passo que prova o índice — a guarda textual sozinha não apanha arquivo já rastreado, que era
  exatamente o buraco.
- [ ] **Cobrir o parser Metal HUD no gate (#83).** O workflow inspecionado descobre testes
  Python em tools/ci, enquanto `tools/profile/test_parse_metal_hud.py` tem regressões próprias
  ampliadas pelo Atlas. *Pronto:* executar essas regressões na CI ou registrar uma exclusão
  fundamentada junto ao workflow; não confundir validação manual com cobertura contínua.

### P2 — integridade de contexto e contratos

- [x] **Contrato de `session.records` (#49, via #55).** Só tentativas realmente terminadas
  geram registros; forçar uma fase não equivale a executar a transição.
- [ ] **Decidir `GameSession._current_archived` (#58).** O achado havia sido perdido numa
  reconciliação. A máquina de fases já limita o arquivamento; trocar a guarda por `false`
  não era distinguido pela suíte histórica. *Pronto:* remover a redundância ou acrescentar
  um caso legítimo que exercite sua função, sem mudar silenciosamente a máquina de fases.
- [x] **Integrar o contrato de VELOCITY do Atlas.** ✅ conferido em `main`: `speedup_active` deixou
  de ser flag sem produtor — `game/simulation/game_simulation.gd:336` lê-a junto de
  `effects.active(ItemProfile.Kind.VELOCITY)`, e `tests/integration/atlas_gameplay_test.gd` cobre a
  rota. **Isto fecha, de lado, a dívida P2 mais antiga do backlog:** "o speed-up está autorado,
  validado, hasheado — e não existe" (achado do #47). A pergunta de design que o loop não podia
  responder — o jogo tem speed-up ou não? — foi respondida com **sim**, por um produtor real, em
  vez de apagar as regras de `GameRules` (o que teria invalidado replays, invariante 7).
- [x] **Pausa e ciclo de vida do áudio (#70).** ✅ conferido em `main`: guarda coerente para música
  e vozes, `shutdown` solta a pausa, e `tests/unit/audio_pause_test.gd` defende as regressões.
- [x] **Cobertura de pureza do boss (#68).** ✅ conferido em `main`, e resolvido pela via melhor:
  o controlador **mudou-se** para `game/simulation/enemies/boss_behavior_controller.gd`, onde a
  varredura por diretório já o alcança, em vez de ganhar um nome na lista de exceções —
  `DOMAIN_FILES` ficou **vazio**. **Mover para dentro do domínio é preferível a nomear uma
  exceção**, e é a lição que este item deixa. O `CLAUDE.md` ficou a descrever o caminho antigo; o
  **#94** corrige isso.
- [x] **Exceção visual em regras (#74).** ✅ conferido em `main`:
  `tests/unit/rules_presentation_exception_test.gd` faz a exceção ser paga em vez de nomeada em
  silêncio. A costura RoundContent é declarada e os serializadores derivam do grafo real.
- [ ] **Guarda de direção em `game/session/` (#74).** Pureza nominal de símbolos não prova
  que a sessão nunca lê apresentação. O achado histórico está em
  `docs/loop/runs/2026-09-07T100000Z.md`; ampliar a prova de dependências com uma mutação
  que leia `content.visual`, sem misturar esse trabalho à alteração de lifecycle.
- [x] **Documentação coerente (#65, #76, #77, #82, #84).** ✅ conferido em `main`: `ART_DIRECTION`
  referencia ADR-0011 e ADR-0012, e `doc_freshness_header_test.gd` continua verde. **Mas o
  mecanismo que estes PRs atacam continua aberto** — ver o item novo de censos deriváveis no P2.
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
- [ ] **Dois censos que dão para derivar, e que já mentiram.** Achado de 08-09, pelo lado negativo
  do "derivar vence vigiar" do #82: o cabeçalho deste ledger afirmava 32 PRs abertos com a fila em
  zero (corrigido pelo **#96**), e o invariante 1 do `CLAUDE.md` apontava um arquivo para uma pasta
  de onde ele saíra (corrigido pelo **#94**) — os dois **com a suíte inteiramente verde**, porque
  nenhuma guarda os alcança. Ao contrário da contradição textual que o #82 mediu e recusou, estes
  **são** deriváveis: (a) o número de PRs abertos vem da API do GitHub, que o relatório de fila já
  consulta; (b) o caminho de um arquivo citado num documento confere-se com `FileAccess.file_exists`.
  (b) é a mais barata e protege o documento que toda execução lê primeiro.
  *Pronto:* uma guarda que recuse caminho de repositório citado em `CLAUDE.md` ou `docs/*.md` que
  não exista em disco — e a decisão, escrita, sobre se vale amarrar (a) ao censo da fila.

- [ ] **Procedência da licença raiz (#73).** Preservar o aviso de `IMPLEMENTATION_STATUS`:
  não substituir titularidade ou licença sem decisão do mantenedor e verificação de direitos.
- [ ] **Contagem de outro ambiente parece atual fora da matriz (#69).** `IMPLEMENTATION_STATUS.md`
  e `SHIPPING_PASS.md` citam **134 testes, 11.489 asserções** do run de macOS de 2026-09-03. O
  número é verdadeiro **por ser histórico**, e por isso a guarda de inventário do #69 não o
  alcança: forçá-lo a bater com a árvore de hoje falsificaria evidência que a nuvem não reproduz.
  O risco é de leitura — nada **na linha** avisa que aquilo é outro ambiente e outra data.
  *Pronto:* toda contagem de suíte em `docs/` diz, na própria linha, de que ambiente e data veio,
  ou é derivada da árvore.

### P3 — experiência e estética

Já estão em `main` via #55: envelopes por cue, contorno da ameaça (ADR-0011), score encenado,
háptica de exposição, âncora flutuante do toque, proa do cursor, foco de captura, trava do eixo
analógico, fase contínua da trilha e cadência de transição. Isso não equivale a aprovação estética.

- [x] **Contorno próprio do cursor (#75, ADR-0012).** ✅ em `main`, com
  `cursor_ink_outline_test.gd`. **Nunca foi visto numa tela.**
- [x] **Cue sonoro de exposição (#61).** ✅ em `main`, com `exposure_audio_cue_test.gd`: som e
  háptica leem a mesma aresta confirmada. **Nunca foi ouvido.**
- [x] **Causa da morte no HUD (#79).** ✅ em `main`, com `death_status_duration_test.gd`: a duração
  segue a fase DYING em vez de um prazo fixo inventado pelo HUD.
- [x] **Âncora da direção da ameaça (#87).** ✅ em `main`, com `enemy_facing_mark_anchor_test.gd`.
  **Nunca foi visto numa tela.**
- [x] **Distribuição das marcas de captura (#81).** ✅ em `main`, com
  `capture_vfx_marker_spread_test.gd`. **Nunca foi visto numa tela.**
- [x] **Toque estável (#90).** ✅ em `main`, com `touch_axis_lock_test.gd`. **Nunca foi tocado por
  um polegar de verdade.**

> **Os `[x]` acima significam "o código está em `main` e uma guarda o defende" — nada mais.** É o
> sentido estrito da legenda ("entregue e mesclado"). Quatro deles são decisões **estéticas** cujo
> mérito nenhuma execução do loop pode julgar: a sessão de nuvem não vê nem ouve o jogo. A dívida
> vive no item de QA humana abaixo, que continua `[ ]` de propósito — marcar estética como
> entregue por ter teste verde seria a mesma confusão entre *o texto chegou* e *a decisão foi
> tomada* que a ADR-0013 sofre no P0.

- [x] **Geometria real do HUD (#52, via #55).** A sonda executa frames; medir Label apenas
  em `_initialize()` não reproduz sua geometria final.
- [ ] **Contraste `BOUNDARY`×`TRAIL`.** A dívida de luminância não foi resolvida nesta revisão.
  *Pronto:* decisão visual, catracas atualizadas e confirmação numa tela, sem piorar legibilidade.
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
