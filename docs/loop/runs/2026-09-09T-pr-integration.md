# Integração local e remota das PRs #99–#106

Data: 2026-09-09. Pedido explícito do mantenedor: revisar a fila, resolver conflitos,
selecionar a melhor composição, testar localmente e atualizar o GitHub e o checkout.

## Base, segurança e autoria

Checkout inicialmente limpo em `5318d0aa04a244a892e0a16598b85ecfc8cc895e`.
`origin/main` avançara para `a5b2b06240dc3f7d4a8e3979fd9d4fbf1f1f12a4` via #98.
A branch `integrate/pr-review-20260909` nasceu do remoto atualizado. Um `git bundle --all`
e um snapshot JSON foram preservados fora do checkout, em
`../qix-integration-backups/20260909-pr-review/`. Não houve reset destrutivo ou force-push.
Os heads abaixo foram reunidos por merge, preservando commits e relatos originais.
Git/Godot foram centralizados; três agentes fizeram revisão e correções por ownership.
Não houve aprovação simulada da própria conta autora.

## PRs auditadas

| PR | Head de origem | Conteúdo e decisão |
|---|---|---|
| [#99](https://github.com/flaviotinococoutinho/qix-game/pull/99) | `735ed50d0fbb3c254c118e3b2c2af3654be095de` | Procedência das contagens: manter guarda e carimbos, recalcular inventário composto. |
| [#100](https://github.com/flaviotinococoutinho/qix-game/pull/100) | `0093fffbf0070dedb1a4b255ee92113d2a8822db` | Envelope FREE: manter fórmula e pisos medidos; acrescentar guarda por expressão e canal RGB. |
| [#101](https://github.com/flaviotinococoutinho/qix-game/pull/101) | `360d92e4281a4eee8368bf5009dfafe8b0d64d67` | Relato histórico de composição: preservar data, árvore e limites originais. |
| [#102](https://github.com/flaviotinococoutinho/qix-game/pull/102) | `35fcf9de69bc1a1215658ed2037cff6bf0606b51` | Relatos históricos da fila: preservar evidências sem promovê-las a QA atual. |
| [#103](https://github.com/flaviotinococoutinho/qix-game/pull/103) | `e62d7e8fc6128552bfe066d1273a2c719a8cc82c` | Corredor do dardo: manter previsão pura; corrigir teto de48 que ocultava alvo no campo real. |
| [#104](https://github.com/flaviotinococoutinho/qix-game/pull/104) | `905002422b4e7c06f89c795dcf9711efc17ef8e7` | Pausa touch fora do HUD: manter geometria e opacidade; validar posição e hitbox em renderer. |
| [#105](https://github.com/flaviotinococoutinho/qix-game/pull/105) | `a8d7e7fe27421c214f26b699772f4e84083bde5c` | Sincronizador da matriz: manter comando; corrigir validação vazia e descoberta/argumentos inválidos. |
| [#106](https://github.com/flaviotinococoutinho/qix-game/pull/106) | `0455e650e6757374ec80d15b5da84497860b94f0` | Prioridade de alertas: manter regra; encerrar avisos quando sua causa já foi resolvida. |

A PR #98 já em main adiciona uma guarda estática de direção domínio→apresentação. Ela protege
os símbolos e tipos declarados que varre; não é uma análise completa de dependências indiretas
por strings/preload. Não foi encontrada violação atual do contrato.

## Resolução dos conflitos e correções

Os conflitos estavam concentrados no ledger e na matriz compartilhados. A resolução conservou
as intenções de cada delta, sem aplicar ours/theirs global ou união automática. Coberturas novas
foram somadas, números históricos ficaram nos respectivos relatos e o inventário final foi
recalculado pelo runner. O cabeçalho ativo foi reescrito para uma única composição.

O relato de #105 dizia que descartar um carimbo ao resolver um documento também descartaria a
guarda de #99. Essa causalidade não é correta: o teste foi adicionado em arquivo disjunto e
sobrevive ao conflito do documento. A orientação atual preserva o carimbo e a guarda, sem
repetir essa explicação. #101/#102 contêm medições históricas, não mudanças de gameplay.

A revisão encontrou e corrigiu três defeitos que os checks individuais não demonstravam:

- Dardo: `min_range=24` é distância mínima, não máxima. Em 225×283, seed17, o disparo nasce
  em (1,141) mirando (112,141). O teto48 de #103 ocultava o alvo. A previsão percorre até o
  terminal absorvente/vida; usa cache limitado aos slots e invalida por board/versão, pool,
  ID, estado, posição, direção, velocidade e vida. O decremento de warmup não refaz geometria.
  Aritmética inteira de movimento, RNG, regras e goldens continuam preservados.
- HUD: um aviso com prazo restante bloqueava recompensas mesmo após captura, absorção ou
  PURGA resolverem o perigo. Agora a prioridade considera a causa no snapshot confirmado.
  IDs e identidade da simulação impedem confusão por reutilização de slot ou troca de rodada.
- Sincronizador: ausência dos marcadores obrigatórios não pode ser anunciada como matriz em
  dia. Descoberta vazia, erros de carga/inicialização, parâmetro de asserções inválido e
  escrita sobre conteúdo alterado são rejeitados antes de modificar o documento.

A guarda FREE também passou a verificar posição RGB e operações, pois um conjunto de literais
não distingue uma troca de canais. A fórmula é um envelope conservador dos extremos, não uma
medição dos pixels efetivamente exibidos. A dívida BOUNDARY×TRAIL não foi alterada.

## Validação desta composição

Godot 4.7.2 Mono oficial, macOS/Apple M2, 2026-09-09. Logs locais usam prefixo
`/tmp/qix-20260909-`; imagens e app ficam em `build/integration-20260909/`.

| Verificação | Resultado medido nesta composição |
|---|---|
| Suíte GDScript | 463 casos, 20.863 asserções, zero falhas; JSON obrigatório, zero erro de engine na execução |
| Ferramentas Python | 92 testes: CI27 + MCP21 + assets28 + profile16; todos passaram |
| Rota M2 | 5 capturas:179→358→493→780→825‰;12750 pontos,3 vidas; replay arquivado e nova rodada |
| Renderer da campanha | 20 verificações,zero erros; captura real,baliza,seis GLBs,HUD e fallback2D; framebuffer480×640 |
| Renderer das PRs | 16 verificações,zero erros; fixture de dardo com223 células,alvo central,pausa em(198,19),HUD após absorção |
| Contraste | Nenhuma regressão dos pisos;24 combinações abaixo da meta continuam dívida declarada |
| App macOS arm64 | Assinatura ad-hoc estrita válida;900/900 ticks com áudio em19,022s,sem erro observado |
| Assets originais | Seis GLBs válidos,5084 triângulos,361000 bytes; hashes preservados |

As sondas `verify_depth_stage.gd` e `verify_pr_integration.gd` rodaram com OpenGL/Metal
Compatibility real. As imagens foram abertas e inspecionadas. A segunda usa fixtures
explicitamente montadas para tornar visíveis casos difíceis; não se apresenta como partida
humana. O primeiro readback revelou que ligar `touch_enabled` não tornava o overlay desktop
visível; a fixture passou a exigir também `visible` e a sonda foi repetida.

O microbenchmark da view com seis dardos usa240 amostras por condição. Cache:mediana36µs,
p95=39µs; território modificado a cada amostra:mediana2311µs,p95=2509µs,máximo3449µs.
É CPU da view neste Mac, não frame pacing da GPU nem orçamento certificado de Android.
A previsão completa preserva a informação; não se voltou ao corte de alcance para melhorar
esse número. Revisões matemáticas independentes cobriram3840 e8192 combinações em Python;
as regressões GDScript também comparam a consulta contra o movimento real.

A primeira suíte acusou somente cabeçalhos do ledger/matriz fora do formato exigido.
A correção foi aplicada e a execução completa passou; não houve alteração de goldens.
Os testes do sincronizador também recusam overflow de int64 no Markdown.

O import e o export Mono locais produziram código de saída0 **com diagnósticos**: conflito
de inicialização do daemon Fennara com o editor já aberto, e `EditorSettings not instantiated`
ao consultar `export/android/shutdown_adb_on_exit`. Esses passos não são classificados como
passagem limpa. O processo do usuário foi preservado. Suíte, M2 e renderer executaram sem
esses erros; o CI Linux verifica separadamente o import com isolamento explícito da extensão
nativa ausente. Nenhum resultado headless certifica o MCP/editor ou a extensão nativa.

## Publicação

Esta branch de integração preserva todos os oito heads por ancestralidade. A PR de integração
recebe o resultado local e os checks do seu head; o merge só é executado após o CI passar.
O recibo com URL, commit de merge e conferência da fila é publicado na própria PR depois da
operação, para distinguir o documento preparatório da confirmação efetiva no GitHub.
O checkout local de main será avançado por fast-forward para o remoto confirmado.

## Limites e sequência de produto

O objetivo desta entrega é incorporar progresso existente sem regressões e corrigir problemas
observados na composição. Playtest humano, balanceamento dos três setores, toque/gamepad em
hardware alvo, escuta crítica, Android, novos encontros e o repertório completo de Volfied
continuam trabalho de produto. Não se declarou qualidade AAA ou distribuição comercial.
A cadência externa do loop e a decisão de licença não foram alteradas.
