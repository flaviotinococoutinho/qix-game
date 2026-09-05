# Performance do board e probes de shipping

> **Verificado em** 2026-09-03 · commit `ab512ef` · Godot 4.7.2-stable.mono, macOS/Apple M2
> **Alcance:** números medidos na máquina local. Nada aqui foi remedido depois: frame pacing e
> GPU dependem de hardware que a sessão de nuvem não tem, e um microbenchmark rodado em outra
> máquina não substituiria estes valores — substituiria a pergunta.

Medição final local em 2026-09-03, Godot 4.7.2-stable Mono, macOS/Apple M2. O
microbenchmark do board é headless; frame pacing e GPU vêm do bundle macOS arm64 exportado no
run `20260903T065739Z-65912` (`runner_status=complete`, `runner_exit=0`,
`overall_exit=0`).

## Perfil isolado do board

Comando reproduzível:

```bash
cd /Users/flaviocoutinho/development/qiqix/qix-game
/Applications/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path /Users/flaviocoutinho/development/qiqix/qix-game \
  --script res://tools/profile_board_view.gd
```

Board real: 225×283 = 63.675 células.

| Caminho | Amostras | Média | p50 | p95 | Máximo | Bytes/refresh |
|---|---:|---:|---:|---:|---:|---:|
| máscara R8, steady-state | 240 | 0,8833 µs | 1 µs | 1 µs | 8 µs | 63.675 |
| RGBA8 legado sintético, `set_pixel()` por célula | 32 | 31.418,3125 µs | 31.160 µs | 32.304 µs | 32.478 µs | 254.700 |
| cold start R8 | 1 | 7 µs | 7 µs | 7 µs | 7 µs | 63.675 |

Nesta execução, a razão p95 observada foi **32.304×**. O ganho estrutural é mais importante que
a razão bruta do cronômetro: o caminho novo elimina 63.675 chamadas `Image.set_pixel()` em
GDScript, reduz em 4× o payload por atualização e reutiliza a textura em steady-state
(`texture_create_count=0`). O board é enviado apenas quando sua identidade ou versão muda;
sincronizações repetidas entram em `skipped_count`.

## Instrumentação em runtime

`QixBoardView.metrics_snapshot()` expõe `refresh_count`, `skipped_count`,
`texture_create_count`, bytes, média, p50, p95 e máximo. O ring buffer mantém no máximo 240
amostras e calcula percentis somente sob demanda. O profiler do Godot recebe:

- `Qix Board/refresh_usec`;
- `Qix Board/refresh_p95_usec`;
- `Qix Board/refresh_count`.

Essa instrumentação é somente de apresentação: nenhum valor temporal chega a
`GameSimulation`, ao RNG, ao checksum ou ao replay.

## Frame pacing da build exportada

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

Resultado final do probe:

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

## GPU e frame pacing pelo Apple Metal HUD

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

## Integridade temporal do smoke de áudio

O runner final também abriu o bundle gráfico com o driver de áudio padrão e feature tag
`shipping_qa`. O bootstrap contou **900/900 physics ticks a 60 Hz** e emitiu exatamente um marker
de conclusão. A duração nominal foi 15 segundos e a duração wall-clock observada, 17 segundos.
O watchdog configurado em 30 segundos não expirou, não enviou sinal e o processo saiu 0.

Esse gate impede que um simples exit code esconda encerramento precoce: ticks solicitados,
concluídos, taxa física, marker, tempo mínimo e watchdog precisam ser coerentes. O timeout é
autorável com `QIX_MACOS_AUDIO_SMOKE_TIMEOUT_SECONDS`; reduzir o valor abaixo da duração real
faz o runner falhar, não aprovar uma amostra truncada.

## Framebuffer do shader final

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
