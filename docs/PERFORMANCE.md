# Performance — domínio, board e palco Atlas Vivo

> **Verificado em** 2026-09-08 · commit `e8307d1` · revisão estrutural da integração Atlas + remoto + MCP
> **Alcance:** separação entre geometria/payload, orçamento e tempos históricos. Nenhuma medida
> de tempo foi executada por esta edição documental; validação final da composição em andamento.
> As tabelas de setembro/03 e o registro Atlas anterior não certificam o novo head integrado.

## Custo atual e como medir

O domínio continua 2D inteiro. O palco acrescenta SubViewport tático 720×960, câmera ortográfica,
quad de revelação, GLBs e sinais observacionais; HUD/touch permanecem fora do plano. O upload
R8 é uma parte do custo, não o custo do frame 2.5D completo. A atualização Godot AI 4.0.2 também
exige distinguir consumo de editor/ferramental do payload realmente exportado.

O gate de tick em `tests/integration/simulation_step_budget_test.gd` mede 1.200 ticks e fixa
p95 de 300 µs. Esse limite protege o caminho comum; não limita o pior fill nem garante que todo
frame caiba em 16,667 ms. Ampliação de pools/encontros e mudanças de captura exigem medir picos,
percentis e leitura de tela antes de elevar um orçamento.

| Pergunta | Instrumento | Limite |
|---|---|---|
| Custo de step/captura | `tools/profile_simulation_step.gd` | CPU do domínio observada externamente; não mede GPU |
| Preparação/upload da máscara | `tools/profile_board_view.gd` | microbenchmark CPU/R8; não representa frame completo |
| Palco, modelos, fallback e checksum | `tools/dev/verify_depth_stage.gd` | renderer real; prova funcional não é soak |
| Frame pacing exportado | dispatcher da cena principal com `--shipping-probe=frame-pacing` | exigir gameplay ativo, aquecimento e amostras |
| GPU/frame Apple Metal | parser e log do Metal HUD | só valida a máquina e o contexto de captura registrados |
| Aparelho Android | export, profiler nativo e sessão física | AVD e desktop não provam térmica, latência ou throttling |

Os comandos-base estão em [PROJECT_CONTRACT.md](PROJECT_CONTRACT.md). Resultados da composição
final devem ser ligados ao SHA e manifest no
[relato de integração](loop/runs/2026-09-08T-mcp-github-integration.md); contagens dinâmicas de
suíte ficam em [TEST_MATRIX.md](TEST_MATRIX.md).

## Registro Atlas anterior à composição — 2026-09-07

A evolução local sobre a1afb90, preservada em 0c63665, tem evidências próprias em
[ATLAS_VIVO.md](ATLAS_VIVO.md) e `build/modernization/REPORT.md`. O registro inclui:

- 3.600 ticks de simulação: p95 102 µs, p99 123 µs, máximo 34.004 µs. O pico de captura
  continua relevante mesmo com percentis abaixo do gate.
- Export local, 600 frames com limite explícito de 60 FPS: GL p95/p99 18,497/19,691 ms,
  máximo 71,472 ms; Metal p95/p99 19,213/20,784 ms, máximo 22,071 ms.
- Metal HUD: 1.398 pares válidos; GPU p95 0,69 ms, máximo 1,82 ms; frame máximo 38,68 ms,
  zero stalls acima de 150 ms no registro. O parser separa prefixo de startup de stalls reais.

Esses valores descrevem o Atlas antes do bundle e da composição final do plugin. Não substituem
uma nova medição. Os registros seguintes preservam a versão plana anterior, para comparação
com alcance explícito; seus comandos apontam para os respectivos artefatos históricos.

## Perfil isolado do board — geometria atual e tempos históricos

Comando reproduzível — o perfil do board **não** precisa de mono nem de macOS, e é a parte deste
documento que qualquer sessão consegue refazer:

```bash
G=/Applications/Godot_mono.app/Contents/MacOS/Godot   # local; na nuvem, o build Linux headless
$G --headless --path . --script res://tools/profile_board_view.gd
```

Board real: 225×283 = 63.675 células.

Geometria/payload são derivados de BoardState e protegidos por
`tests/unit/performance_doc_geometry_test.gd`. As colunas de tempo desta tabela pertencem ao
registro de **2026-09-03**, commit ab512ef, Godot 4.7.2 Mono, macOS/Apple M2.

| Caminho | Amostras | Média | p50 | p95 | Máximo | Bytes/refresh |
|---|---:|---:|---:|---:|---:|---:|
| máscara R8, steady-state | 240 | 0,8833 µs | 1 µs | 1 µs | 8 µs | 63.675 |
| RGBA8 legado sintético, `set_pixel()` por célula | 32 | 31.418,3125 µs | 31.160 µs | 32.304 µs | 32.478 µs | 254.700 |
| cold start R8 | 1 | 7 µs | 7 µs | 7 µs | 7 µs | 63.675 |

Na execução histórica de setembro/03, a razão p95 observada foi **32.304×**. O ganho estrutural é mais importante que
a razão bruta do cronômetro: o caminho novo elimina 63.675 chamadas `Image.set_pixel()` em
GDScript, reduz em 4× o payload por atualização e reutiliza a textura em steady-state
(`texture_create_count=0`). O board é enviado apenas quando sua identidade ou versão muda;
sincronizações repetidas entram em `skipped_count`.

**Remedição em 2026-09-07, Linux headless (nuvem), commit `34634d0`.** As colunas estruturais
saíram idênticas — `225x283`, `63675` células, `63675` bytes/refresh no R8 contra `254700` no
RGBA8 legado, `texture_create_count=0` em steady-state e `1` no cold start, `sample_capacity=240`.
As colunas de tempo, não: a máquina da nuvem deu p95 de `1 µs` no R8 (igual) e `50.978 µs` no
legado (contra `32.304 µs` no M2), cold start de `14 µs` (contra `7 µs`). É o esperado — outra
CPU, outro relógio — e é a razão de a tabela acima continuar a ser a medição do M2 em vez de ser
sobrescrita a cada sessão: **substituir estes valores por uma medição de outra máquina não
responderia à mesma pergunta.** O que a remedição prova é que o *argumento* do R8 (4× menos
payload, textura reutilizada) não depende da máquina, e é justamente essa parte que
`tests/unit/performance_doc_geometry_test.gd` agora amarra ao domínio.

## Instrumentação em runtime

`QixBoardView.metrics_snapshot()` expõe `refresh_count`, `skipped_count`,
`texture_create_count`, bytes, média, p50, p95 e máximo. O ring buffer mantém no máximo 240
amostras e calcula percentis somente sob demanda. O profiler do Godot recebe:

- `Qix Board/refresh_usec`;
- `Qix Board/refresh_p95_usec`;
- `Qix Board/refresh_count`.

Essa instrumentação é somente de apresentação: nenhum valor temporal chega a
`GameSimulation`, ao RNG, ao checksum ou ao replay.

## Frame pacing da build plana exportada — histórico de 2026-09-03

O bootstrap da cena principal cria `frame_pacing_probe_node.gd` somente quando o feature tag
`shipping_qa` e o argumento `--shipping-probe=frame-pacing` estão presentes. O probe confirma
que a sessão alcançou `PLAYING`, aquece 120 frames e coleta 600 amostras; assim a janela não mede
somente `ROUND_INTRO` ou uma apresentação ociosa.

Comando direto correto, usando caminho absoluto e dispatch pela cena principal exportada:

```bash
"/Users/flaviocoutinho/development/qiqix/qix-game/build/shipping/macos/QIX GAME.app/Contents/MacOS/QIX GAME" \
  --audio-driver Dummy --rendering-method mobile -- \
  --shipping-probe=frame-pacing \
  --output="/Users/flaviocoutinho/development/qiqix/qix-game/build/shipping/reports/macos-frame-pacing.json" \
  --warmup-frames=120 --sample-frames=600 \
  --external-gpu=metal-hud
```

Não use `--script res://tools/profile/exported_frame_pacing_probe.gd` no executável exportado:
o template pode ignorar esse override contra o PCK embutido. O entrypoint validado é
`exported-main-scene-dispatch`.

Resultado registrado do probe no runner histórico `20260903T065739Z-65912`:

| Métrica | Resultado |
|---|---:|
| amostras | 600 |
| gameplay ativo ao final | sim |
| frame médio | 16,722615 ms |
| frame p50 | 16,707 ms |
| frame p95 | 18,331 ms |
| frame p99 | 20,041 ms |
| frame máximo | 75,433 ms |
| frames > 20 ms | 7 |
| frames > 33,333 ms | 1 |
| render CPU p95 | 0,071 ms |
| render CPU máximo | 0,504 ms |
| pausas ≥ 150 ms | 0 |

Os checks p95 ≤ 25 ms, p99 ≤ 40 ms, ausência de stall ≥ 150 ms, quantidade de amostras e
gameplay ativo passaram. O `RenderingServer` reportou GPU como indisponível/zero nessa
combinação Metal; por isso o relatório principal declara `external_gpu_pending` e não tenta
converter zero em aprovação. O gate final depende do Metal HUD abaixo.

## GPU e frame pacing pelo Apple Metal HUD — histórico de 2026-09-03

O runner ativa o Metal Performance HUD na mesma execução exportada, captura seu console e
valida o JSON independente `build/shipping/reports/macos-metal-hud.json`.

| Métrica | Resultado |
|---|---:|
| pares válidos GPU/frame | 1.380 |
| pares descartados | 2 markers iniciais de 1.382 candidatos |
| linhas malformed | 0 |
| métricas sem par | 0 |
| pares com stall >150 ms | 0 |
| GPU média | 0,150261 ms |
| GPU p50 | 0,14 ms |
| GPU p95 | 0,23 ms |
| GPU p99 | 0,29 ms |
| GPU máxima | 0,4 ms |
| intervalo de frame p50/p95/p99 | 16,67 / 16,67 / 16,67 ms |
| intervalo de frame máximo | 64,97 ms |

Passaram os thresholds do parser: pelo menos 30 pares; GPU p95 ≤ 8 ms e máxima ≤ 16,667 ms;
frame p95 ≤ 25 ms, p99 ≤ 40 ms e máximo ≤ 150 ms, sem linha malformed nem métrica desemparelhada.
Os testes Python do parser passaram **10/10**. Estes números valem para Apple M2/Metal e este
bundle local; não extrapolam automaticamente para outros Macs ou aparelhos Android.

## Integridade temporal do smoke de áudio — histórico de 2026-09-03

O runner final também abriu o bundle gráfico com o driver de áudio padrão e feature tag
`shipping_qa`. O bootstrap contou **900/900 physics ticks a 60 Hz** e emitiu exatamente um marker
de conclusão. A duração nominal foi 15 segundos e a duração wall-clock observada, 17 segundos.
O watchdog configurado em 30 segundos não expirou, não enviou sinal e o processo saiu 0.

Esse gate impede que um simples exit code esconda encerramento precoce: ticks solicitados,
concluídos, taxa física, marker, tempo mínimo e watchdog precisam ser coerentes. O timeout é
autorável com `QIX_MACOS_AUDIO_SMOKE_TIMEOUT_SECONDS`; reduzir o valor abaixo da duração real
faz o runner falhar, não aprovar uma amostra truncada.

## Framebuffer do shader plano exportado — histórico de 2026-09-03

O bootstrap também despacha `framebuffer_shader_probe_node.gd` pela cena principal exportada.
Comando direto:

```bash
"/Users/flaviocoutinho/development/qiqix/qix-game/build/shipping/macos/QIX GAME.app/Contents/MacOS/QIX GAME" \
  --audio-driver Dummy -- \
  --shipping-probe=framebuffer \
  --report="/Users/flaviocoutinho/development/qiqix/qix-game/build/shipping/reports/macos-framebuffer.json" \
  --image="/Users/flaviocoutinho/development/qiqix/qix-game/build/shipping/reports/macos-framebuffer.png"
```

O relatório exportado passou **17 asserções**. Ele valida a composição final 240×320 com a
máscara R8 byte a byte igual ao `BoardState`, além da fixture sintética 64×16. No readback:

- `CLAIMED` coincidiu exatamente com o texel correspondente da arte oficial;
- `FREE`, `BOUNDARY` e `TRAIL` ocultaram seus texels de origem e mantiveram as paletas esperadas;
- a composição preservou alpha opaco em `CLAIMED`.

Isso comprova o resultado final do shader no bundle testado, em Apple M2/OpenGL3 Compatibility.
Não constitui cobertura visual de todos os GPUs, resoluções ou drivers.

## Limites da evidência

O perfil do board é um microbenchmark headless de CPU/preparação/submissão e o relógio local tem
resolução finita; p95 de 1 µs não representa tempo de GPU nem frame-time total. A comparação
legada reproduz o algoritmo removido, mas não é um build histórico. O Metal HUD e o readback
representam uma única máquina e uma execução curta. Antes de distribuição, repetir profiling,
memória, térmica, framebuffer e piores casos nos aparelhos-alvo, executar soak prolongado e
inspecionar o profiler nativo de cada plataforma.
