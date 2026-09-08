# Integração GitHub, MCP e Atlas Vivo — 2026-09-08

> **Verificado em** 2026-09-08 · commit `3f2d96e` · GitHub, CI Linux, editor e runtime macOS
> **Alcance:** snapshot inicial das 32 PRs #59–#90, ampliado com #91 durante a execução.
> **Concluído:** PR #92 mesclada; todas as 33 PRs #59–#91 constam MERGED; fila aberta zerada em 05:33:37Z.

## Pedido e autorização

O usuário pediu evolução ampla para um jogo desafiador, apresentação moderna 2.5D e atores
escaláveis com ciclos de vida. Autorizou também auditoria/revisão, correções, integração e merges
das PRs. O trabalho foi decomposto entre agentes; Git, execução Godot e ações no GitHub ficaram
centralizados pelo coordenador. Este relato não converte autorização em prova de execução,
nem revisão técnica da mesma conta em aprovação independente.

## Âncoras e preservação

| Referência | Identidade | Papel |
|---|---|---|
| Atlas antes da preservação | `a1afb904df7652f6b870111794573a9f7c8989d1` | base com taxonomia e WIP autoral |
| Atlas preservado | `0c63665` | código, conteúdo, arte e evidências locais anteriores à composição |
| Plugin preservado | `6d23de4` | Godot AI 4.0.2, separado do Atlas |
| Branch de integração | `integrate/atlas-mcp-20260908` | composição isolada, sem reescrever histórico alheio |
| main observada | `6136ebb104a940e8dd5549f2fef20b1bc6d750c3` | estado remoto durante a auditoria |
| Bundle #78 | `3c9724f556856861b936ac43662b019945856eb6` | agregado remoto preservado como ancestral na integração |
| Base histórica da preparação | `ca745780ad3242695ba7411416da87c6b490c609` | origem de grande parte dos diffs das PRs |

Antes da integração, main e o #78 tinham respectivamente **2 e 117 commits exclusivos**.
A afirmação antiga de fast-forward, presente em relatos de fila, é histórica. O bundle contém
124 commits desde sua merge-base e 1.480 arquivos no diff completo. O auditor usou refs que o
coordenador já havia obtido, sem checkout/fetch/merge próprio.

O snapshot de `gh pr view --repo flaviotinococoutinho/qix-game` inclui bodies, arquivos, commits
e checks por head. Para evitar truncamento silencioso do limite de 100 itens de gh, os arquivos
e contagens completas foram expandidos por git diff/rev-list. São **32 PRs / 3.115 entradas de
arquivos**, contando a repetição entre branches. Os 32 heads coincidiam com a lista inicial.
O estado observado das PRs era OPEN/CONFLICTING; isso não prevê o resultado após a reconciliação.

## Inventário de intenção e decisão

As decisões abaixo preservam a análise feita antes do merge. A seção de conclusão registra
o resultado efetivo, com SHA, checks e recibo individual de estado das 33 PRs.

| PR | Head SHA auditado | Intenção | Decisão de integração |
|---|---|---|---|
| [#59](https://github.com/flaviotinococoutinho/qix-game/pull/59) | `f402010b7eff0da4afbbfb7b83ffbe4100499795` | Evidência de verificação do #55 e reconciliação de base | Preservar relato histórico via #78; não mesclar separadamente. O head inteiro já pertence ao bundle. |
| [#60](https://github.com/flaviotinococoutinho/qix-game/pull/60) | `3d853faf65d4576bc9fd3ef18b2076458a3eaaca` | Remover curved_lines_2d sem consumidor | Preservar remoção via #78 e manifesto agregado. Não remover plugins efetivamente usados pelo Atlas. |
| [#61](https://github.com/flaviotinococoutinho/qix-game/pull/61) | `10000f582eea577ea6ca1e42a3e78de3473424a4` | Som da primeira travessia do limiar de exposição | Preservar cruzamento único compartilhado áudio/háptica e prioridade. Mesclar com receitas de itens/atores e envelopes Atlas, sem substituir a biblioteca inteira. |
| [#62](https://github.com/flaviotinococoutinho/qix-game/pull/62) | `cb4d44f64c8b0ca59f465aa82aed1409e29f8551` | Remover phantom_camera sem consumidor | Preservar remoção via #78, manter câmera própria do palco 2.5D. |
| [#63](https://github.com/flaviotinococoutinho/qix-game/pull/63) | `c8a8ed69e6314a261b9ccc970419b4f01b88bbc3` | Remover guide sem consumidor | Preservar remoção via #78 e referências de licença históricas. |
| [#64](https://github.com/flaviotinococoutinho/qix-game/pull/64) | `4275a3804a89af630e9ada4ed9661777ca6a892e` | Remover GDDraw sem consumidor | Preservar remoção via #78. Não confundir ferramentas atuais GodotAI/fennara com os sete vendors dormentes. |
| [#65](https://github.com/flaviotinococoutinho/qix-game/pull/65) | `acc3635ba18318525accf0e682a72c452fd1fa11` | Atualizar direção de arte para tinta e foco | Conteúdo principal em #78. Portar correção editorial residual da matriz somente se ainda aplicável; reescrever direção atual para palco Atlas, não copiar status visual antigo. |
| [#66](https://github.com/flaviotinococoutinho/qix-game/pull/66) | `bbaa8d2de779648fc82285212b0db7a8a5b893d5` | Remover yard sem consumidor | Preservar remoção via #78 e manifesto final sem pastas a-remover. |
| [#67](https://github.com/flaviotinococoutinho/qix-game/pull/67) | `22d0b453b5048d4dc7f392d9945df8198fad407e` | Derivar manifesto de addons do disco | Código do último commit porta a solução de zero pastas já existente em #78; diferença funcional nula, comentário NUMERALS corrigido fora do bundle. Preservar comentário e relato, não mesclar o ledger antigo. |
| [#68](https://github.com/flaviotinococoutinho/qix-game/pull/68) | `04f9394577437c18158103d238908d4fddbb5a90` | Fechar lacuna do BossBehaviorController na guarda de domínio | Preservar scanner ampliado e prova de cobertura entre guardas. Atlas moveu controller para game/simulation/enemies; remover exceção/DOMAIN_FILES no caminho antigo e usar replay/deterministic_rng.gd. |
| [#69](https://github.com/flaviotinococoutinho/qix-game/pull/69) | `78f7ff10e1554036c541ed751233f52458872d53` | Derivar inventário TEST_MATRIX dos testes atuais | Teste é byte a byte igual ao #78. Preservar e regenerar inventário após integração; portar somente achados/prosa residual relevantes. Contagens históricas não provam árvore atual. |
| [#70](https://github.com/flaviotinococoutinho/qix-game/pull/70) | `72d6dc33709835140403103903a656c3ddf0430d` | Pausar música e vozes com mesma guarda | Testes estão em #78; biblioteca do bundle acumula também #61. Preservar is_instance_valid, relógios de pausa e reset shutdown, adaptados aos envelopes/canais Atlas. Resíduo é correção do relato. |
| [#71](https://github.com/flaviotinococoutinho/qix-game/pull/71) | `2852767dab6afae6ed6b70f8df44a53051e97aab` | Consolidar relatório de fila e ordem de merge | Preservar ferramenta e seus testes de segurança via #78; usar novo snapshot para decisões, nunca confiar na ordem histórica embutida nos relatos. |
| [#72](https://github.com/flaviotinococoutinho/qix-game/pull/72) | `477cfd5080f7d4656ec228553afc96881a1d8171` | Remover softbody2d sem consumidor | Preservar remoção via #78 e licença/auditoria histórica. |
| [#73](https://github.com/flaviotinococoutinho/qix-game/pull/73) | `8637f32944ee1e794f05872b3beeb8c67ee93942` | Remover curve2collision e registrar lacuna de licença | Preservar remoção e achado histórico via #78. Não apagar evidência de licença ao atualizar status. |
| [#74](https://github.com/flaviotinococoutinho/qix-game/pull/74) | `559f73b78ad95666916800af02af5685ad4b7009` | Fechar exceção de apresentação em game/rules | Teste e UID já são idênticos no #78. Preservar as exceções declaradas RoundVisualDefinition e sua costura RoundContent, validar novos Resources puros ItemProfile/BonusLadder/ThreatProfile. Resíduo é ledger/.gitignore editorial. |
| [#75](https://github.com/flaviotinococoutinho/qix-game/pull/75) | `0034b2f94dee0235819925f60ded33f66395c4cd` | Contorno de tinta legível do cursor | Preservar requisito de contraste e testes adaptados à silhueta Atlas. Não restaurar cruz antiga 5x5 nem apagar estados/mesh player. Colisão ADR-0012 com lifecycle local exige IDs e links exclusivos. |
| [#76](https://github.com/flaviotinococoutinho/qix-game/pull/76) | `7b7f65ce5764026a03d703b0f1c261a1b36dcf7a` | Analisar conflitos/precedências da fila | Preservar relatório como histórico via #78, substituir recomendações operacionais por grafo atual deste inventário. |
| [#77](https://github.com/flaviotinococoutinho/qix-game/pull/77) | `ed6d527427386996bf809d27f7b12296971313c3` | Derivar geometria/payload em PERFORMANCE | Preservar guarda de geometria/bytes e labels exigidos; tempos de renderer no documento precisam corresponder ao palco Atlas, separados das medidas antigas. |
| [#78](https://github.com/flaviotinococoutinho/qix-game/pull/78) | `3c9724f556856861b936ac43662b019945856eb6` | Bundle reconciliado de #57 a #87 | Integrar como base de qualidade numa branch isolada preservando Atlas e plugin já commitados. Resolver manualmente domínio v4, apresentação moderna e docs; não usar theirs global. Não é fast-forward da main atual: 2 commits exclusivos main e 117 exclusivos bundle. |
| [#79](https://github.com/flaviotinococoutinho/qix-game/pull/79) | `7b829946626d9e02e9c1ed14afd6965408c76241` | Causa da morte durar fase DYING | Código HUD e teste iguais no #78. Preservar duração ligada à fase e incluir causas WALKER/DART/EMBER Atlas. Resíduo são notas de ambiente/relato, não outra implementação. |
| [#80](https://github.com/flaviotinococoutinho/qix-game/pull/80) | `1f2bfcc3f6caa4d9c99d35ffc0991c2683bc4f2f` | Medir divergência da fila #78/#79 e matriz | Preservar evidência histórica via #78; não portar contagens antigas para TEST_MATRIX atual. |
| [#81](https://github.com/flaviotinococoutinho/qix-game/pull/81) | `cfb4ff56be6da749c53d256a65f27e6bee8a770a` | Distribuição de marcadores sem colapso nas larguras 37/71 | Preservar sequência R2 determinística local à apresentação e testes; evita concentração causada pelos strides modulares, sem consumir RNG de domínio. |
| [#82](https://github.com/flaviotinococoutinho/qix-game/pull/82) | `78066735a5613c5aeb401bfebd2b265d9a147023` | Auditar documentação, guardas textuais e licenças | Conteúdo principal em #78. Preservar achado residual de guarda textual recusada e limitações das provas; não restaurar números/status antigos. |
| [#83](https://github.com/flaviotinococoutinho/qix-game/pull/83) | `4aa65ed31af405de70c714b39e9066e4693e30ef` | Remover/ignorar bytecode Python e verificar índice | Guarda GDScript e remoções já em #78; último commit 4aa65ed adiciona passo CI Bytecode de Python fora do índice, AUSENTE no bundle. Portar esse passo e manter justificativa reunida às regras de ignore; registrar teste do parser Metal fora do gate. |
| [#84](https://github.com/flaviotinococoutinho/qix-game/pull/84) | `98b55950cbf223794ce53ec429f8e6a0c9cb19f2` | Detectar cabeçalhos e linhas contraditórias nos docs | Preservar guarda estrutural via #78. Ela verifica duplicação textual/tabelas, não verdade factual nem atualidade; reconciliar ledger/manual. |
| [#85](https://github.com/flaviotinococoutinho/qix-game/pull/85) | `f0cb3e8625abfcd2f0d7db066c4b8ab5d8215c4d` | Propor cadência do loop em ADR-0013 | Preservar como proposta auditável via #78. Não tratar proposta como autorização para automações/publicações; respeitar fluxo atual do mantenedor. |
| [#86](https://github.com/flaviotinococoutinho/qix-game/pull/86) | `c5abda5c837dbcc787e018af146ea4033f9ff369` | Restaurar achados perdidos do ledger | Portar seletivamente os achados dos dois commits fora de #78; preservar narrativa atual Atlas. Substituir ledger inteiro apagaria progresso e recolocaria backlog obsoleto. |
| [#87](https://github.com/flaviotinococoutinho/qix-game/pull/87) | `7c994041e8f0fd0829748a89900542cb5e2812ae` | Ancorar indicador de direção na borda do losango | Preservar princípio geométrico e regressão onde aplicável. Atlas usa corpo/pás/mesh diferentes: não restaurar enemy_view antigo nem remover ciclos de vida para satisfazer testes do losango. |
| [#88](https://github.com/flaviotinococoutinho/qix-game/pull/88) | `1a141443b893402ed49d12ddcd665d99a9c534d3` | Snapshot de posse da fila | Preservar novo relato 2026-09-08T005759Z.md como evidência histórica. Reconciliar só delta útil do ledger, não mesclar estado inteiro. |
| [#89](https://github.com/flaviotinococoutinho/qix-game/pull/89) | `d4774b8179fe94a48c9f17dc911e56aad06bc0cc` | Censo de um bundle e resíduos entre 30 PRs | Preservar novo relato 2026-09-08T020126Z.md com data. Alegação de fast-forward tornou-se histórica após main avançar a 6136ebb; este audit cobre 32 PRs atuais. |
| [#90](https://github.com/flaviotinococoutinho/qix-game/pull/90) | `23ea0064234ff65c445d254a408ed6aab7386f5b` | Travar eixo touch reutilizando resolvedor analógico | Preservar testes de jitter/arrasto e razão de histerese, adaptados à API Atlas. Não substituir touch moderno: Atlas já tem entrada11/saída7, margem angular10graus, floating stick e flick latch. Relato 2026-09-08T030236Z.md é novo. |

## Grupos, dependências e resíduos

- Heads integralmente contidos no #78: #59, #60, #61, #62, #63, #64, #66, #68, #71, #72,
  #73, #75, #76, #77, #78, #80, #81, #84, #85 e #87.
- Heads não ancestrais do bundle: #65, #67, #69, #70, #74, #79, #82, #83, #86, #88, #89 e #90.
- #67 porta a solução zero-addons já existente em #78; o resíduo é comentário/relato.
  Guardas de #69/#74, HUD de #79 e testes de #70/#83 já estão byte a byte no bundle.
- #83 acrescenta em `4aa65ed` o passo CI de detecção de bytecode **no índice Git**, ausente
  no bundle auditado. Ignore e guarda textual não expulsam bytes já rastreados.
- #90 precisa portar regressões de jitter/arrasto sem substituir o touch Atlas, que já tem
  histerese de entrada/saída, margem angular, âncora flutuante e flick latch.
- #88/#89/#90 têm novos relatos fora do bundle. #67/#70/#79/#83/#86 atualizam relatos existentes;
  selecionar seus deltas preserva a evidência sem restaurar um ledger obsoleto inteiro.
- O #86 demonstrou que cabeçalhos e número de itens podem sobreviver enquanto os achados são
  substituídos. A reconciliação atual preserva identidade e intenção, sem usar união automática.

## Resoluções locais e fronteiras preservadas

1. **Domínio e replay:** GameRules v4, taxonomia sob game/simulation e os contratos Atlas
   de IDs/lifecycle, warmup, captura, respawn, balizas, timers e bônus foram preservados.
   O arquivo `replay_checksum_golden_test.gd` ficou byte a byte igual ao Atlas de `0c63665`
   na entrega do agente de domínio; os literais antigos de volta pelo perímetro não substituem
   os dourados atuais com captura e chefe ativo nos três perfis.
2. **Sessão:** incorporado `transition_elapsed_ticks()` inteiro. O consumo de progresso em
   float permanece na view. A sessão arquivada não avança para animar dissipação terminal.
3. **Guardas:** scanner ampliado de pureza mantido; removida exceção do caminho antigo do boss.
   Resources canônicos são descobertos pelo grafo real de GameRules/RoundDefinition, sem
   contagem fixa que proíba expansão. A prova visual varia paleta, fundo, texto e seis escalas.
4. **VELOCITY:** comentários e teste remoto de speed-up inerte foram atualizados. Os três casos
   isolados sem itens permanecem; o caso de produção exige captura, aceleração e replay.
5. **Apresentação:** manter a intenção de contraste, âncoras, pausa, causa da morte, foco de
   captura e avisos remotos, adaptando os testes às silhuetas e aos ciclos do Atlas. Teste antigo
   de cruz/losango não autoriza apagar o palco ou restaurar actors sem lifecycle.
6. **Documentação:** ADR-0012 permanece cursor ink; Atlas usa ADR-0014. O contrato atual remove
   afirmações concorrentes de cenas, Git inválido, plugin 3.2.4 e stretch=viewport. Detalhes
   históricos continuam nos respectivos commits/relatos, inclusive limites de export/licença.
7. **Vendors/MCP:** as sete remoções dormentes não autorizam apagar GodotAI/fennara. O plugin
   4.0.2 preservado necessita validação de integração e export; source presente não prova runtime.

## Evidência conhecida antes da validação final

| Evidência | Árvore e resultado conhecido | Limite |
|---|---|---|
| Atlas local | preservado em `0c63665`; registro de 260 testes, 13.598 asserções, zero falhas e 20 verificações no renderer | anterior ao bundle/plugin combinado; logs locais em build/modernization |
| Campanha Atlas | três setores, três vidas, dez balizas, quatro itens e replays finais; registro em ATLAS_VIVO | possibilidade e determinismo, sem substituir playtest humano |
| Checks das PRs | snapshot de checks individuais por head nos JSONs de auditoria | não valida a composição final nem aprovação independente |
| Resolução dos sete arquivos do domínio | busca de markers e git diff --check sem problemas; dourado comparado byte a byte a `0c63665` | leitura estática, sem Godot executado por esse agente |
| Auditoria da fila | metadata/body/ancestralidade e inventário completo por SHA | snapshot datado; reconsultar antes de ações remotas |

Arquivos locais de auditoria: `/tmp/qix-20260908-pr-audit.json`,
`/tmp/qix-20260908-pr-audit.md` e `/tmp/qix-20260908-pr-audit-data/`. São artefatos locais,
não anexos publicados; a tabela acima conserva as identidades/intenção necessárias no repositório.
O JSON registra, por arquivo, blobs, presença no bundle e comparação com o worktree anterior
à integração. Esses campos de comparação local não descrevem o worktree após as resoluções.

## Validação da composição local

| Etapa | Estado desta edição | Evidência final |
|---|---|---|
| Resolução integral do merge | CONCLUÍDA | 33 heads ancestrais da integração; PR91 chegou durante o trabalho e foi incorporada em `ecc6a23` |
| Suíte explícita do projeto | PASSOU | 404 testes, 19.009 asserções, zero falhas, zero erros de engine; JSON novo e validado |
| Testes Python | PASSARAM | 27 CI + 21 Godot MCP + 28 Blender/assets + 16 parser/perfil = 92; índice sem bytecode |
| Campanha ativa/replays v4 | PASSOU NA SUÍTE | boss_active_campaign_playthrough e goldens v4 preservados; M2 separado também passou |
| Renderer 2.5D e fallback | PASSOU | 20 asserções, seis modelos carregados, captura real de 17,9%, baliza ativa e checksum preservado; evidência versionada em docs/evidence/2026-09-08 |
| Godot AI MCP | READY | plugin/servidor4.0.2, sessão QIX exata, oito leituras finais de editor/cena/seis GLBs sem erro |
| Blender MCP | PASSOU | discovery26tools + job real com .blend novo verificado; seis GLBs:5.084triângulos/361.000bytes |
| Aplicativo macOS de QA | RUNTIME VALIDADO | reexport do head `9d02d6f`, arm64 ad-hoc, codesign estrito; 900/900 ticks com áudio real em 17,259 s, saída zero e sem erro de engine |
| Import/export CLI local Mono | LIMITAÇÃO REGISTRADA | geração de recursos/pacote termina, mas teardown registra ERROR de EditorSettings Android; não classificado como gate verde |
| CI e merge GitHub | CONCLUÍDOS | CI 34190696324 passou na mesma árvore; PR #92 mesclada em `3f2d96e`, todas as 33 PRs MERGED |
| Distribuição comercial | FORA DESTE ACEITE | não inferir de build ad-hoc nem de merge |

## PR91, revisão independente e correções adicionais

A PR [#91](https://github.com/flaviotinococoutinho/qix-game/pull/91), head
`25327ed694a60ee6dd36355a4164627886483ad9`, surgiu após o snapshot inicial. Remove o booleano
redundante de arquivamento e verifica que cada passo cria no máximo um registro, somente a
partir de PLAYING. A integração acrescentou provas de que ambas as rotas de teste chegam ao
terminal previsto e arquivam todas as tentativas, evitando um falso verde por rota incompleta.
O relato original permanece em `2026-09-08T040000Z.md`.

A revisão independente encontrou dois defeitos reais na combinação:

- Pausar → desligar/religar som → retomar deixava a música parada. Corrigido o início do stream
  parado na retomada; a música apenas suspensa preserva sua posição. Regressões cobrem os três
  caminhos de pausa, carregamento durante pausa e som mantido desabilitado.
- O timeout do wrapper Blender deixava um processo descendente gravar depois do recibo de
  falha. O limite POSIX agora encerra o grupo do job em timeout/SIGTERM; regressões reais tentam
  gravar o artefato tardio e confirmam sua ausência. O fallback Windows é explicitamente menor.

## Recuperação MCP e alcance das alterações de cliente

Godot AI estava com plugin4.0.2 e servidor3.2.4 em8000/9500. Foram adotadas8001/9501 para a
conexão atual; somente as duas EditorSettings de porta foram alteradas, com backup e preservação
das cenas abertas. O Retry oficial da migração resolveu um timeout do probe Claude e repinou
somente a entrada godot-ai em seis configurações globais reconhecidas. As configurações de
projeto com wrappers e a entrada Blender foram preservadas. O vendor foi conferido contra o
manifesto oficial assinado:283arquivos, zero divergências/extras. Procedimento e rollback:
[godot_recovery.md](../../../tools/mcp/godot_recovery.md).

O import CLI concorrente encontrou o LSP ocupado; `--lsp-port 0` removeu essa colisão. A engine
Mono local ainda registra uma falha de encerramento do exporter Android depois de destruir
EditorSettings. Recovery mode acrescentou erro do HotReloadAssemblyWatcher e foi rejeitado
como solução. O gate mantém esses erros/panics fatais; importação e modelo foram verificados
no editor conectado e no renderer, e o CI Linux verifica sua própria execução limpa.

## Conclusão no GitHub

A [PR #92](https://github.com/flaviotinococoutinho/qix-game/pull/92) foi mesclada pela interface
Chrome do GitHub em **2026-09-08 05:33:34 UTC**, com merge commit
`3f2d96e25f42b8833e53099cce55619f25ec59c5`. O head revisado foi
`9d02d6fcea6a70791a906720e7defbb46860b00b`; o histórico foi preservado por merge commit.
A API confirmou todas as **33 PRs #59–#91 em MERGED** às 05:33:36–37Z e nenhuma PR aberta.
O [recibo do GitHub](../../evidence/2026-09-08/github-merge.json) conserva os estados,
heads e horários individuais. A ancestralidade de cada head foi reconferida contra origin/main.

O [CI 34190696324](https://github.com/flaviotinococoutinho/qix-game/actions/runs/34190696324)
passou com Godot 4.7.2 standard no Linux. O checkout de pull_request usa o merge provisório
`4b5c5b7b22be94c8b36780cb1fab40168ba30113`; sua árvore
`528244e11304dfed4a15d977c4ad014dd2828d87` é idêntica à árvore do head `9d02d6f`.
O [manifesto CI](../../evidence/2026-09-08/ci-manifest.json) registra `tested_head=true`,
`source_unchanged=true`, worktree limpo antes/depois e zero erros em import, suíte, M2 e HUD.
A suíte executou 404 testes e 19.009 asserções; as regressões Python somam 92 testes.
O [CI pós-merge da main 34191087087](https://github.com/flaviotinococoutinho/qix-game/actions/runs/34191087087)
também terminou com sucesso, agora no merge commit efetivo `3f2d96e`.

A main local foi atualizada por fast-forward para `3f2d96e`, preservando a branch de integração
e o backup anterior. Este fechamento documental é posterior ao merge: reconcilia o ledger,
publica os recibos e mantém pendências de decisão humana separadas de mudanças já entregues.
Seu próprio PR registra os checks e a publicação desse fechamento.

O [recibo do aplicativo final](../../evidence/2026-09-08/native-runtime.json) corresponde à
reexportação de `9d02d6f`, depois da integração da PR91. O aplicativo de QA está em
`build/integration-20260908/Lumen Atlas Integrado.app`. A assinatura nativa ad-hoc foi refeita
e verificada depois de reduzir o binário a arm64. O smoke de áudio iniciou e concluiu 900 ticks
a 60 ticks/s, com saída zero, sem diagnósticos fatais. Esse pacote é de QA local; o resultado
não substitui notarização nem revisão humana de desafio e mix de som.

Para novas mudanças, repetir apenas as verificações pertinentes e os gates exigidos sobre
a nova árvore. Os resultados desta seção são históricos vinculados aos SHAs acima; não
atualizar números dourados sem explicar uma mudança deliberada no contrato de regras.

## Continuações automáticas após o merge

Enquanto o fechamento era publicado, três execuções automáticas abriram novas PRs. São
posteriores à consulta de fila vazia das 05:33:37Z; o snapshot original de 33 PRs não foi
reescrito. O fechamento [#95](https://github.com/flaviotinococoutinho/qix-game/pull/95) incorpora
os três heads por ancestralidade, além dos recibos e da reconciliação completa do ledger:

| PR | Head auditado | Resolução |
|---|---|---|
| #93 | `92659ed028929ae247b8eb9fb576d06e7330d7d3` | Preservada medição Linux adicional. Corrigidas inferências de ausência anterior de testes, de speed-up sem produtor e de igualdade com dourados anteriores ao Atlas. |
| #94 | `86d46d2a4d3582c342b2c144993777926712c48a` | Corrigido invariante 1 do CLAUDE.md para a taxonomia atual, incluindo a exceção explícita UNGUARDED_BY_DESIGN; relato preservado. |
| #96 | `29bb7ad727073a4079d91cd075461e401f714e95` | Preservada medição adicional e absorvido o fechamento P0 pelo ledger reconciliado; ausência de GPU da execução não invalida QA macOS anterior. |

Os conflitos ocorreram no ledger, cujo fechamento por intenção foi preservado. Nenhuma dessas
continuações altera runtime, conteúdo, assets ou configurações MCP. Ao concluir o #95, seu
registro no GitHub fornece o merge SHA, checks do head final e nova conferência da fila.
