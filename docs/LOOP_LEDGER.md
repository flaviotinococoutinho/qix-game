# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-07 · commit `ca745780` · inspeção Git e preparação Linux headless
> **Alcance:** reconciliação da fila #57–#86 solicitada pelo mantenedor. A base já contém #56.
> Este documento descreve a **fila**, não afirma que todas as mudanças estão nesta branch.
> Cada PR preserva seu escopo de código; #78 é o candidato de integração do conjunto.
> Números de teste pertencem à árvore de cada PR e às evidências da preparação, nunca à fila.
> Mérito visual, escuta, Android físico e exportação/assinatura não foram validados.

**Snapshot da preparação:** 30 PRs abertas, #57–#86; `main` em `ca745780`.
Nenhuma aprovação formal ou merge é inferido de suíte verde. A revisão pela mesma conta autora
é recusada pelo GitHub; registrar revisão técnica não substitui a aprovação de outra identidade.
Consultar a fila real antes de agir: este snapshot não é um contador automático.

O histórico original permanece nos commits de cada PR e em `docs/loop/runs/`. Os censos datados
(0, 22, 29 ou 30 PRs) são medições históricas, não estados atuais concorrentes. Esta reconciliação
substitui as instruções contraditórias de drenagem, sem apagar o histórico Git.

## Protocolo (obrigatório)

1. **Leia este arquivo inteiro antes de decidir o que fazer.** Ele vem depois do `CLAUDE.md` e
   antes de qualquer edição.
2. **Liste os PRs abertos do loop antes de escolher.** Um item com PR aberto não está livre.
   Consulte o estado atual no GitHub. Use `tools/loop/unclaimed_surface.sh` antes de escolher
   (heurística por refs e camada) e `tools/loop/merge_queue_report.sh` depois de escolher.
   Refs de branches não provam, sozinhos, que os respectivos PRs continuam abertos.
3. **Escolha exatamente UM item** — o de maior prioridade que caiba num PR pequeno e revisável.
   Um PR grande não é produtividade: é uma revisão que não vai acontecer.
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
"estado da fila" contraditórias e três ordens de merge concorrentes. Backlog reconcilia-se à mão.

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
| Identidade visual é *Lumen Cartography* | `docs/ART_DIRECTION.md` |
| Volfied é referência de gênero, não alvo de clone | `reference/volfied/README.md` |
| Histórico do loop é um arquivo por execução | `docs/loop/runs/README.md` |
| `samples/` e `guide_examples/` podados; `exclude_filter` fica | `docs/loop/runs/`, poda dos demos |
| `antipixel_state_machine/` podado | `docs/loop/runs/2026-09-05T035826Z.md` |

## Backlog — prioridade decrescente

### P0 — integração e capacidade de revisão

- [~] **Preparar a fila #57–#86 e validar o conjunto no #78.** Atualizar cada branch sobre
  `ca745780`, reconciliar documentação e testar também a integração. Preservar commits e
  relatos; não usar force-push, não mesclar `main` e não simular aprovação independente.
  *Pronto:* heads finais sem conflito com a base, evidências por árvore e PRs fora de rascunho.
  A drenagem posterior continua pendente: só trocar para `[x]` depois do merge efetivo.
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

### P2 — integridade de contexto e contratos

- [x] **Contrato de `session.records` (#49, via #55).** Só tentativas realmente terminadas
  geram registros; forçar uma fase não equivale a executar a transição.
- [ ] **Decidir `GameSession._current_archived` (#58).** O achado havia sido perdido numa
  reconciliação. A máquina de fases já limita o arquivamento; trocar a guarda por `false`
  não era distinguido pela suíte histórica. *Pronto:* remover a redundância ou acrescentar
  um caso legítimo que exercite sua função, sem mudar silenciosamente a máquina de fases.
- [ ] **Decidir o speed-up reservado.** `speedup_active` não tem produtor normal; os parâmetros
  ainda afetam o hash de regras. *Pronto:* decisão explícita e testes de comportamento, ou ADR
  de remoção com avaliação de incompatibilidade de replays. Esta preparação não decide isso.
- [~] **Pausa e ciclo de vida do áudio (#70).** Música e vozes usam guarda coerente;
  shutdown solta a pausa. A liberação de vozes deve continuar zerando prazos e rodízio,
  inclusive ao desabilitar áudio, sem depender de shutdown. *Pronto:* regressões verdes.
- [~] **Cobertura de pureza do boss (#68).** O controlador em `game/enemies/` é domínio,
  apesar da pasta; a guarda e o contrato precisam identificá-lo explicitamente.
- [~] **Exceção visual em regras (#74).** `RoundVisualDefinition` admite cores; isso não
  autoriza outros Resources de domínio a ler `float` ou consumir a apresentação.
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
- [~] **Distribuição das marcas de captura (#81).** Evitar ressonância dos passos modulares
  em focos usuais; preservar contenção, repetibilidade e isolamento da apresentação.
- [x] **Geometria real do HUD (#52, via #55).** A sonda executa frames; medir Label apenas
  em `_initialize()` não reproduz sua geometria final.
- [ ] **Contraste `BOUNDARY`×`TRAIL`.** A dívida de luminância não foi resolvida nesta revisão.
  *Pronto:* decisão visual, catracas atualizadas e confirmação numa tela, sem piorar legibilidade.
- [ ] **QA humana de controles, áudio e composição.** Calibrar margem analógica, toque,
  exposição, pulso, contornos, foco e proa com jogo real. Teste headless não cobre esse mérito.

## Ambiente e limites de validação

Godot requerido: `4.7.2.stable.official.ed1daf0bf`, Linux headless. Importar uma vez por checkout
antes da suíte; uma classe nova pode exigir nova importação. O gate isola explicitamente o
descritor nativo Fennara ausente, preservando os scripts runtime. Não tratar `ERROR` de startup
como ruído aceitável: o gate deve reprovar diagnósticos inesperados mesmo com exit code zero.
Essa modalidade **não valida a extensão nativa**, render GPU, alto-falantes, Android ou assinatura.

Duas armadilhas medidas no #79, ambas invisíveis para quem roda só `run_tests.gd`:

- **Suíte verde não é gate verde.** O CI reprovou com `engine_errors=3` e a suíte a 265 testes e
  0 falhas: um `QixGameHud` criado num teste e **não libertado** leva as `Label` filhas consigo, e
  o TextServer reporta `ShapedTextDataAdvanced`/`FontAdvanced` vazados à saída. Regra: todo teste
  que instancia nó de UI chama `free()` **em todos os caminhos**, inclusive o último do método.
  Reproduza o gate antes de empurrar — ele recusa checkout cujo `.godot/extension_list.cfg` já
  registou a fennara, então clone limpo:
  `git clone --local --no-hardlinks -b <branch> <repo> /tmp/fresh && python3 /tmp/fresh/tools/ci/headless_gate.py --godot "$G" --project /tmp/fresh --logs /tmp/gate --isolate-missing-editor-extension`
- **`git add -A` depois de rodar os testes Python do gate versiona bytecode.**
  `python3 -m unittest discover -s tools/ci` cria `tools/ci/__pycache__/`, e foi assim que o #79
  acrescentou dois `.pyc` sem perceber. O `.gitignore` do #83 fecha isto; até ele mesclar, prefira
  `git add` por caminho e confira `git status` antes de fechar o commit.

## Histórico

Relatos originais: `docs/loop/runs/`. Os commits originais das PRs são mantidos como ancestrais.
A preparação não transforma resultados antigos em evidência atual. Consultar os logs e o
manifesto da execução vinculada ao head/árvore da PR antes de aprovar ou mesclar.
