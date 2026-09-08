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

- [~] **Concluir integração Atlas + bundle #78 e fila #59–#90, autorizada pelo usuário.**
  Branch isolada `integrate/atlas-mcp-20260908`, com Atlas e plugin preservados antes do merge.
  Resolver conflitos por contrato, portar resíduos úteis (#83/#90 e relatos), validar a árvore
  final e realizar a integração GitHub autorizada. Não usar `theirs` global, force-push ou
  aprovação fictícia. *Pronto:* commit/PR final, checks e evidências ligados ao SHA, merges
  efetivos registrados e PRs substituídas reconciliadas. Até lá o estado permanece `[~]`.
- [~] **Decidir a cadência do loop (#85, ADR-0013 em Proposta).** A recomendação de branch
  diária não foi aceita automaticamente. Agendamento externo não foi alterado.
  *Pronto:* decisão do mantenedor registrada e scheduler coerente com ela.
- [ ] **Manter esforço no jogo, não só no mecanismo.** O censo histórico do #85 distingue
  runtime, guardas, documentação e poda. *Pronto:* medir em dez execuções se pelo menos
  uma em cada três modifica `game/`, `ui/`, `app/` ou `content/`.
- [~] **Unificar relatórios da fila (#71).** `merge_queue_report.sh --order` substitui
  `merge_order_report.sh`; a verificação de sintaxe cobre os scripts do loop. Preservar o
  relatório de superfície, cuja pergunta é diferente. *Pronto:* mudança integrada e CI verde.

**Lições preservadas:** #55 integrou #20–#54 em `34634d0` e #56 reconciliou esse estado;
35 PRs exigiram quatro esforços, dois superados. A incompatibilidade #25×#50 era semântica:
um PR removeu `GameSession.transition_progress()` e outro ainda o chamava. Já o #67 precisa
aceitar o estado final legítimo da ADR-0010: zero pastas `a-remover`. #78 contém essa resolução.
As medições #76, #80 e #86 demonstraram outro acoplamento: a guarda #69 exige atualizar a matriz
para o inventário da **árvore final**, não somar números copiados das descrições dos PRs.

### P1 — higiene estrutural e evidência

- [~] **Sete remoções da ADR-0010 (#60, #62, #63, #64, #66, #72, #73).** Respectivamente:
  `curved_lines_2d`, `phantom_camera`, `guide`, `GDDraw`, `yard`, `softbody2d`, `curve2collision`.
  #78 consolida a tabela de addons, as contagens, os filtros de export e o caso zero do #67.
  Não remover os filtros de export só porque a pasta saiu: uma reinstalação local pode recriá-la.
  *Pronto:* ausência das sete pastas na integração, manifesto coerente e guardas verdes.
- [~] **Matriz vinculada à árvore (#69; composição observada em #80 e #86).** A descoberta
  de testes varre diretórios. *Pronto:* contagem e inventário derivado conferem com o runner
  em cada branch e no #78. Shipping histórico continua identificado como histórico.
- [~] **Não versionar bytecode Python (#83).** Regras globais `__pycache__/` e `*.py[cod]`,
  remoção do bytecode já rastreado inclusive o acrescentado por #79. A guarda textual não
  consulta o índice Git: conferir também `git ls-files`. *Pronto:* ambos os exames verdes.
  **Os dois exames existem desde 2026-09-08:** a guarda em GDScript prova a regra, e o passo
  «Bytecode de Python fora do índice» de `verificacao.yml` prova o índice com `git ls-files` —
  é ele que apanha o bytecode que #79 traz, porque `.gitignore` não expulsa arquivo já rastreado.

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
- [~] **Integrar o contrato de VELOCITY do Atlas.** O item já é produtor real de aceleração,
  com timer inteiro e piso de velocidade normal no início do segmento. A flag explícita
  `speedup_active` permanece no checksum, sem duplicar o timer. A guarda antiga de regras
  inertes foi adaptada: isolamento sem itens e captura de produção com passo rápido/replay.
  *Pronto:* regressão na composição final e publicação do contrato v4 em main.
- [~] **Pausa e ciclo de vida do áudio (#70).** Música e vozes usam guarda coerente;
  shutdown solta a pausa. A liberação de vozes deve continuar zerando prazos e rodízio,
  inclusive ao desabilitar áudio, sem depender de shutdown. *Pronto:* regressões verdes.
- [~] **Cobertura de pureza do boss (#68).** O controller agora está em
  `game/simulation/enemies/boss_behavior_controller.gd`, coberto pela pasta de domínio.
  Preservar o scanner ampliado e remover exceções do caminho antigo nas duas guardas.
- [~] **Exceção visual em regras (#74).** `RoundVisualDefinition` admite cores; isso não
  autoriza outros Resources de domínio a ler `float` ou consumir a apresentação. A costura
  RoundContent também é declarada; serializadores são derivados do grafo real, sem count=2.
- [~] **Documentação coerente (#65, #76, #77, #82, #84).** Decisões de arte referenciadas,
  geometria atual distinguida de tempos históricos, disponibilidade de Git corrigida,
  seções e chaves de tabela sem contradição. *Pronto:* guardas e inspeção da integração verdes.
- [ ] **Procedência da licença raiz (#73).** Preservar o aviso de `IMPLEMENTATION_STATUS`:
  não substituir titularidade ou licença sem decisão do mantenedor e verificação de direitos.

### P3 — experiência e estética

Já estão em `main` via #55: envelopes por cue, contorno da ameaça (ADR-0011), score encenado,
háptica de exposição, âncora flutuante do toque, proa do cursor, foco de captura, trava do eixo
analógico, fase contínua da trilha e cadência de transição. Isso não equivale a aprovação estética.

- [~] **Contorno próprio do cursor (#75, ADR-0012).** Testar geometria e contraste sem
  contaminar o checksum. Validação visual continua pendente após a integração.
- [~] **Cue sonoro de exposição (#61).** Som e háptica leem a mesma aresta confirmada;
  a prioridade do aviso não deve encobrir captura ou morte. Escuta física permanece pendente.
- [~] **Causa da morte no HUD (#79).** Duração segue a fase DYING e não um prazo fixo;
  a mensagem termina na reentrada, inclusive com duração de morte curta ou longa.
- [~] **Âncora da direção da ameaça (#87).** Preservar a intenção de aderir à silhueta real,
  adaptando a prova aos corpos/pás/GLBs Atlas. Não restaurar enemy_view antigo para satisfazer
  expectativas do losango; testar rumos e direção nula sem alterar o domínio.
- [~] **Distribuição das marcas de captura (#81).** Evitar ressonância dos passos modulares
  em focos usuais; preservar contenção, repetibilidade e isolamento da apresentação.
- [x] **Geometria real do HUD (#52, via #55).** A sonda executa frames; medir Label apenas
  em `_initialize()` não reproduz sua geometria final.
- [ ] **Contraste `BOUNDARY`×`TRAIL`.** A dívida de luminância não foi resolvida nesta revisão.
  *Pronto:* decisão visual, catracas atualizadas e confirmação numa tela, sem piorar legibilidade.
- [~] **Toque estável (#90).** Portar regressões de jitter/arrasto sem perder floating stick,
  histerese de entrada/saída, margem angular e flick do Atlas. Publicação ainda pendente.
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
