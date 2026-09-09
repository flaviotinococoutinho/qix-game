# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-08 · commit `3f2d96e` · integração concluída em `main`
> **Alcance:** as **33 PRs de origem, #59–#91**, foram incorporadas pela [PR #92](https://github.com/flaviotinococoutinho/qix-game/pull/92).
> Merge efetivo em 2026-09-08T05:33:34Z; as 33 PRs constavam como MERGED e a fila estava vazia na conferência às 05:33:37Z.
> Atlas Vivo (`0c63665`), Godot AI 4.0.2 (`6d23de4`), bundle #78 e resíduos foram preservados por ancestralidade.
> O [CI 34190696324](https://github.com/flaviotinococoutinho/qix-game/actions/runs/34190696324) passou no head `9d02d6f`; a composição validada está incorporada em `main`.
> O [CI pós-merge 34191087087](https://github.com/flaviotinococoutinho/qix-game/actions/runs/34191087087) também passou em `3f2d96e`.
>
> A execução de 2026-09-09T08:08Z acrescentou itens ao backlog e marcou como `[~]` os que já
> tinham PR aberta. **A data acima não mudou de propósito:** aquela integração não foi
> reverificada aqui, e trocar o carimbo faria a evidência de 09-08 parecer medida hoje.

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
  **Medição do #102: 0 de 15 execuções tocaram essas pastas.** As duas execuções seguintes
  romperam a série — o #103 em `game/enemies/` e `game/simulation/enemies/`, e a de
  2026-09-09T08:08Z em `ui/touch/`. O item fica aberto porque a razão de uma em cada três
  ainda não se cumpriu na janela de dez; quem contar, conte a partir do #102.
- [ ] **A fila do loop está acima do teto e só o mantenedor a destrava.** Em 2026-09-09T08:08Z
  havia **seis PRs abertas** (#98–#103), todas em rascunho, todas com a suíte headless verde,
  nenhuma em conflito; o teto do protocolo é dois. O loop não mescla as próprias PRs e não há
  PR vermelha para consertar, então nenhuma execução resolve isto sozinha. *Pronto:* fila em
  dois ou menos, por merge ou por fechamento explicado.
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
- [~] **Guarda geral de direção em `game/session/` (#74).** Reivindicado pela **PR #98**, aberta
  e verde. Não escolher. O texto original do item segue abaixo.
  O acesso a `content.visual`
  já é recusado pela guarda integrada de regras/apresentação. O achado ainda aberto em
  `docs/loop/runs/2026-09-07T100000Z.md` é mais amplo: quais outras dependências de apresentação
  podem ser lidas pela sessão sem a guarda nominal perceber? *Pronto:* ampliar a prova de
  direção com uma violação plantada dessa outra dependência, preservando a cobertura do visual.
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
- [~] **Contagem de outro ambiente parece atual fora da matriz (#69).** Reivindicado pela
  **PR #99**, aberta e verde. Não escolher. O texto original do item segue abaixo.
  `IMPLEMENTATION_STATUS.md`
  passou a separar a evidência Atlas dos registros históricos e a apontar para TEST_MATRIX.
  `SHIPPING_PASS.md` ainda cita **134 testes, 11.489 asserções** do run de macOS de 2026-09-03
  sem repetir a data e o ambiente na própria linha da tabela. O
  número é verdadeiro **por ser histórico**, e por isso a guarda de inventário do #69 não o
  alcança: forçá-lo a bater com a árvore de hoje falsificaria evidência que a nuvem não reproduz.
  O risco é de leitura — nada **na linha** avisa que aquilo é outro ambiente e outra data.
  *Pronto:* toda contagem de suíte em `docs/` diz, na própria linha, de que ambiente e data veio,
  ou é derivada da árvore.

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
- [ ] **Contraste `BOUNDARY`×`TRAIL`.** A dívida de luminância não foi resolvida nesta revisão.
  *Pronto:* decisão visual, catracas atualizadas e confirmação numa tela, sem piorar legibilidade.
  A **PR #100** mexe no mesmo tooling de contraste (envelope de `FREE`) sem reivindicar este par:
  quem pegar este item, conte com conflito em `tools/palette_contrast.gd`.
- [x] **O chrome do toque não cobre mais instrumento do HUD (2026-09-09T08:08Z).** A pausa era
  desenhada a 58 % começando em y=10, dentro dos 19 px da banda superior, sobre 32 dos 82 px do
  trilho do escudo e o pé das vitais. Passou a encostar por baixo da banda, derivando
  `TOP_BAR_HEIGHT`, com o véu na família de 24 % do resto do overlay.
  `tests/unit/touch_hud_occlusion_test.gd` lê `chrome_rects()` — a mesma função que `_draw()` usa
  — e mede contra os nós reais do HUD. **Ler `size.y` de um `Label` no runner mede 23 px, não
  `TEXT_HEIGHT`**: a guarda usa X do nó e Y da linha declarada, e quem escrever guarda de layout
  aqui cai no mesmo buraco se não fizer igual. O que ficou **medido e aceito, não resolvido**:
  os arcos do stick e da ação cruzam a linha de texto do rodapé (35,8 px dos 91 do título,
  17,6 px dos 139 do status) — recuar reabriria a ergonomia fechada em #90. Falta confirmação
  numa tela do novo lugar da pausa.
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
