# SHIPPING_PASS — candidato de QA validado

Atualizado em 2026-09-03 para Godot 4.7.2-stable Mono, macOS arm64 e Android
arm64. O run canônico `20260903T065739Z-65912` terminou com
`runner_status=complete`, `runner_exit=0` e `overall_exit=0`.

## Resultado

O shipping pass implementa e valida automaticamente a superfície pedida: áudio/mix/háptica,
gamepad/touch, três comportamentos autoráveis de chefe, campanha com transições reais, geração
de conteúdo com WAL persistente, export dos dois pacotes, smoke Android, frame pacing/GPU e
readback do framebuffer. A telemetria e o feedback permanecem fora da simulação determinística.

O estado é um **candidato de QA automatizado**, não uma release comercial nem comprovação de
qualidade “AAA” em uso real. O runner e a suíte estão verdes; continuam abertos os gates que só
podem ser fechados por uma pessoa, em hardware-alvo, ou por uma pipeline de distribuição.

## Limites arquiteturais

| Entrada/saída | Camada de shipping | Limite do domínio |
|---|---|---|
| teclado, gamepad, touch | `GameInputAdapter` + `QixTouchControls` | produz somente um `MoveIntent` cardinal por tick |
| eventos confirmados | `QixFeedbackHub` | áudio e háptica observam; não escrevem em `GameSession` |
| perfil do boss | `BossBehaviorProfile` + `BossBehaviorController` | inteiros, seed explícita e bytes canônicos nas regras/replay |
| máscara territorial | `BoardView` + `board_reveal.gdshader` | recebe os bytes R8; somente `CLAIMED` revela o fundo |
| autoria de campanha | `CampaignContentTransaction` | staging, WAL, commit, recovery e rollback fora do runtime de jogo |
| build exportada | probes em `tools/profile` e `tools/shipping` | telemetria não entra em RNG, checksum ou replay; o probe confirma gameplay ativo antes da coleta |

## Áudio, mixagem e háptica

`QixAudioDirector` cria música procedural original distinta para cada rodada e cues para início
de trilha, captura, rejeição, morte, respawn, escudo crítico, início/clear de rodada, game over e
conclusão da campanha. Os streams PCM são determinísticos, pequenos e gerados localmente; oito
vozes formam o pool de SFX. A mix usa:

- `Qix Master` → `Master`, com limiter;
- `Qix Music` → `Qix Master`;
- `Qix SFX` → `Qix Master`;
- volumes lineares autoráveis de master, música e SFX;
- throttle do cue de trilha para evitar repetição excessiva;
- pausa da música e desligamento explícito de playback/streams no teardown.

O primeiro smoke Android com áudio real encontrou um `SIGSEGV` nativo na thread `AudioTrack`
ao alcançar o fim do primeiro loop PCM. A correção adiciona um guard frame que repete a primeira
amostra e posiciona `loop_end` nesse frame válido, contornando a leitura one-past-end documentada
no [Godot #119778](https://github.com/godotengine/godot/issues/119778). O APK corrigido iniciou a
main loop, permaneceu vivo pelos 30 segundos exigidos e passou screenshot e scan de log.

Playback continua habilitado no jogo normal, inclusive no smoke Android. Ele é suprimido apenas
em runtime headless e nos probes gráficos curtos, para não atribuir ao jogo o leak de teardown de
`AudioStreamPlaybackWAV` registrado no
[Godot #76745](https://github.com/godotengine/godot/issues/76745). Além do smoke automatizado,
o bundle macOS completou 900/900 physics ticks a 60 Hz com driver de áudio normal: 15 segundos
nominais, 17 segundos de wall time, um marker de conclusão, watchdog de 30 segundos sem timeout
e código de saída 0. Os logs finais do macOS não contêm assinatura de leak de `ObjectDB`.

`QixHapticFeedback` escolhe somente o pulso de maior prioridade quando vários eventos ocorrem
no mesmo tick, escala a intensidade configurada e despacha rumble fraco/forte ao gamepad e
vibração handheld. O preset Android pede `android.permission.VIBRATE`.

Cobertura atual: geração PCM e guard frame, loops, cues, buses, limiter, prioridade/coalescência,
volumes e invariância da simulação passam na suíte. Pendente: escuta crítica em fones/caixas,
calibração de loudness/clipping percebido e resposta háptica em controles/aparelhos reais.

## Gamepad e touch

| Ação | Teclado | Gamepad | Touch |
|---|---|---|---|
| mover | setas/WASD | D-pad ou analógico esquerdo | stick virtual esquerdo |
| desenhar | Espaço/Z | A ou X | manter `DRAW` |
| confirmar | Enter | A | toque em `DRAW` |
| pausar | Esc/P | Start | botão superior direito |

O analógico usa limiar de entrada 0,42 e liberação 0,28 para evitar instabilidade perto da dead
zone. O adaptador preserva a direção preferida durante diagonais/sobreposição e mantém stick,
D-pad e botões pressionados separadamente por `device`, para que desconectar ou soltar um
controle não apague o estado de outro. A composição deduplica A/confirm e Start/pause quando o
mesmo evento chega simultaneamente pelo `InputMap` e pelo caminho raw do gamepad. O overlay
aceita stick e `DRAW` por dedos diferentes e só fica visível automaticamente em builds mobile;
no desktop, `show_touch_controls_on_desktop=true` serve para QA.

Cobertura atual: D-pad, stick, botões, múltiplos gamepads independentes, deduplicação de A/Start
e multitouch são exercitados com `InputEvent` sintético; gamepad e touch produzem o mesmo byte
canônico de intent. O smoke em emulador também comprovou o overlay touch renderizado e o
reinício por toque. Pendente: gamepad físico, aparelhos touch reais, rumble/vibração,
remapeamento por família de controle, safe areas, densidades, latência e ergonomia.

## Boss e campanha

Cada rodada referencia um perfil externo:

| Rodada | Perfil | Variação |
|---|---|---|
| Abyssal Relay | `WANDER` | deriva determinística, sem pulso de velocidade |
| Aurora Foundry | `PURSUIT` | mira o octante do jogador, jitter limitado a 1 passo; pulso 115% por 60/360 ticks |
| Verdant Singularity | `SWEEP` | varredura de 3 passos; pulso 125% por 48/240 ticks |

Validação e replay incluem o perfil; trocar padrão ou pulso torna um replay incompatível antes
de qualquer mutação. Testes verificam limites, reflexões, posição no interior livre, velocidade
máxima segura e determinismo de seed.

A rota `boss_active_campaign_playthrough_test.gd` é **automatizada**, mantém o boss ativo e usa
somente `GameSession.step(MoveIntent)` públicos. Ela conclui R1 em cinco capturas, R2 em duas e
R3 em três, sem mortes, com progressão final de 86,9%, 80,8% e 82,4%. Scores acumulados: 13.190,
23.960 e 36.290. Os três replays reproduzem o checksum final exato.

Essa rota prova um caminho legal e determinístico. **Ela não é um playthrough humano e não
prova dificuldade percebida, ergonomia, balanceamento ou diversão.** O gate manual deve registrar:

1. três partidas completas por esquema de controle relevante;
2. duração e mortes por rodada, causa da morte e uso do escudo;
3. entendimento das transições, alvo e feedback do boss;
4. picos de frustração, fadiga sonora/tátil e legibilidade em movimento;
5. problemas de acessibilidade, tamanho touch e contraste;
6. ajustes propostos como Resources, seguidos de replay/suíte completos.

## Gerador de conteúdo transacional

`build_campaign_content.gd` cria em memória 16 Resources ordenados e os entrega a
`CampaignContentTransaction`. O protocolo `qix.campaign-content-transaction.v3`:

1. adquire um lock exclusivo por projeto com `TCPServer` em loopback e mantém o socket do kernel
   aberto durante recovery/execute; o diretório `.txn_active.lock` é metadado diagnóstico, não
   uma lease baseada em relógio;
2. recupera qualquer transação incompleta antes de iniciar outra; metadado stale só é removido
   depois que o novo processo detém o guardião loopback;
3. rejeita entries ou paths vazios, duplicados, com traversal, extensão imprópria ou fora de
   `res://`/`user://`;
4. serializa os payloads e recarrega um grafo-sombra inteiramente no staging estável
   `user://qix-campaign-content-staging/txn_active`;
5. persiste tamanho e SHA-256 de cada payload/backup no `manifest.json`; cada registro do WAL
   append-only `journal.jsonl` ancora o SHA-256 canônico desse manifest;
6. valida todas as linhas do WAL como uma máquina de estados integral — `prepared`, progresso
   `committing`, `committed` ou `rolled_back` — com contagem monotônica, terminal único e nenhum
   registro posterior ao terminal;
7. promove bytes já validados por rename adjacente, sem resserializar sobre o destino oficial;
8. restaura existentes, remove novos e devolve ownership do cache de Resources em rollback;
9. antes de aceitar um terminal persistido, valida que cada target tem exatamente o estado,
   tamanho e hash declarados e que não restou arquivo temporário;
10. em nova execução, reverte um commit parcial abandonado antes de prosseguir; inconsistência
    de manifest, WAL ou target falha de modo fechado.

Comando canônico:

```bash
cd /Users/flaviocoutinho/development/qiqix/qix-game
/Applications/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path /Users/flaviocoutinho/development/qiqix/qix-game \
  --script res://tools/build_campaign_content.gd
```

O run final registrou **16 staged e 16 committed**. A suíte direcionada da transação passou
**22 testes e 353 asserções**, cobrindo concorrência entre processos, retomada de lock stale,
commit, rollback byte a byte, remoção de destinos novos, cache, validação de paths, integridade
de manifest/WAL/payload/backup, todos os arcos da state machine, estado terminal dos targets e
recovery após interrupção injetada. O WAL torna a recuperação persistente entre processos;
falha do próprio volume ou perda simultânea dos targets e de todos os artefatos de staging
continuam fora da garantia. Git ainda é necessário para revisão, diff, autoria e rollback de
release.

## Export e QA reproduzível

Pré-requisitos observados nesta máquina:

- `/Applications/Godot_mono.app/Contents/MacOS/Godot` 4.7.2 Mono;
- templates `4.7.2.stable.mono`;
- JDK Temurin 17;
- Android SDK com platform-tools/emulator/build-tools e AVD configurado;
- pelo menos 3 GiB livres para iniciar o AVD pelo runner.

Execução canônica:

```bash
cd /Users/flaviocoutinho/development/qiqix/qix-game
tools/shipping/run_shipping_qa.sh
```

Variáveis opcionais incluem `QIX_GODOT_BIN`, `QIX_ANDROID_SDK`, `QIX_JDK_ROOT`,
`QIX_SHIPPING_OUTPUT`, `QIX_MIN_FREE_KIB`, `QIX_MACOS_AUDIO_SMOKE_TIMEOUT_SECONDS`,
`QIX_ANDROID_AVD`, `QIX_ANDROID_EMULATOR_PORT`, GPU/CPU/memória do emulador e os timeouts
Android. O watchdog do smoke de áudio usa 30 segundos por padrão e falha se os 900 ticks não
terminarem com exatamente um marker coerente.

Por segurança, o runner não escolhe silenciosamente um aparelho físico. Um device real exige
serial nominal e opt-in duplo, sabendo que o runner reinstala (`adb install -r`) e depois encerra
o pacote de QA:

```bash
cd /Users/flaviocoutinho/development/qiqix/qix-game
QIX_ANDROID_DEVICE_SERIAL="SERIAL_EXATO" \
QIX_ANDROID_ALLOW_PHYSICAL_DEVICE=1 \
tools/shipping/run_shipping_qa.sh
```

Sem serial explícito, ele aceita um único emulator online; com mais de um, falha por ambiguidade;
sem nenhum, escolhe uma porta livre e inicia seu próprio AVD. O run final registrou
`selected_serial=emulator-5554` e `selection_source=runner-started-emulator`.

O runner:

1. exporta e afina o bundle macOS para arm64, verifica payload e executa smoke headless;
2. executa o smoke gráfico de áudio real sob watchdog e valida ticks, taxa física, marker, tempo
   decorrido e log antes de aceitá-lo;
3. despacha frame pacing e framebuffer pela **cena principal exportada**, via argumentos depois
   de `--`, e não via `--script` contra o PCK embutido;
4. combina 600 amostras do probe com o Metal Performance HUD e verifica o bundle com `codesign`;
5. exporta APK Android arm64 debug, testa o ZIP, payload e assinatura;
6. seleciona um serial sem ambiguidade, espera boot, usuário CE e package handler estáveis antes
   de instalar sem streaming;
7. só inicia a janela de sobrevivência depois de observar `OnGodotMainLoopStarted` — 13 segundos
   após o launch no run final — evitando a antiga race; então espera 30 segundos, captura
   screenshot e faz scan do logcat;
8. grava exit codes, ambiente, seleção do device, tamanhos, arquitetura e hash em
   `build/shipping/reports/`.

Os presets são de QA: sem identidade/certificado de distribuição, notarização, Play Console ou
credenciais de publicação.

## Evidência final registrada

| Artefato | Resultado | Interpretação correta |
|---|---|---|
| suíte headless | 134 testes, 11.489 asserções, 0 falhas | contratos e integrações locais verdes, sem warning na repetição final |
| transação de conteúdo | 22 testes, 353 asserções; gerador 16 staged/16 committed | WAL v3, lock, integridade e recovery verdes |
| parser Metal HUD | 10 testes Python, 10 aprovados | parser rejeita linhas/pairs incoerentes antes do gate GPU |
| macOS | 101.199.872 bytes, arm64, payload/smokes/codesign verdes | bundle QA atual validado localmente; assinatura é ad-hoc, não de distribuição |
| smoke macOS gráfico | 900/900 ticks a 60 Hz; nominal 15 s, wall 17 s; 1 marker; watchdog 30 s sem timeout; saída 0 | áudio real/runtime-default atravessou o loop PCM; não substitui escuta crítica |
| frame pacing exportado | 600 amostras, gameplay ativo; p95 18,331 ms, p99 20,041 ms, máx. 75,433 ms | gate de frame pacing passou e não houve stall ≥150 ms |
| Metal HUD | 1.380 pares; GPU p95 0,23 ms, p99 0,29 ms, máx. 0,4 ms; zero malformed/unpaired/stalls | gate GPU local passou em Apple M2/Metal |
| framebuffer exportado | 17 asserções, 240×320, máscara R8 igual ao board | `CLAIMED` preservou o texel do fundo no resultado final do shader |
| Android APK | 40.486.376 bytes; SHA-256 `db61015cfc6bea849ec41fad6907e1c0af625d8c38866c2e38bc68306c6411e2` | archive/payload/assinatura debug verdes |
| smoke Android | `emulator-5554`, iniciado pelo runner; main loop após 13 s + 30 s vivo, screenshot e scan limpos | seleção e emulador passaram; isso não substitui aparelho físico nem soak |
| logs finais | sem script/resource/parse/invalid-call ou `ObjectDB` leak nos gates | ausência das assinaturas procuradas, não prova ausência de todo problema possível |

Relatórios: `build/shipping/reports/result.txt`, `run-state.txt`,
`macos-audio-smoke-evidence.txt`, `macos-frame-pacing.json`, `macos-metal-hud.json`,
`macos-framebuffer.json`, `android-device-selection.txt`, `android-smoke.png` e respectivos
logs/exit codes.

## Checklist para fechar o gate comercial/humano

- [x] runner final com `overall_exit=0` e estado `complete`;
- [x] macOS arm64, payload, smoke headless, áudio real com watchdog, log scans e `codesign --verify` verdes;
- [x] gameplay ativo, frame pacing/GPU e framebuffer verdes nesse bundle;
- [x] seleção inequívoca do serial e Android APK, archive/payload/assinatura, instalação, main loop, +30 s, screenshot e log scan verdes no AVD;
- [ ] APK/AAB repetido em aparelhos Android físicos de referência;
- [ ] gamepad, multitouch e háptica validados em hardware;
- [ ] audição crítica e balanceamento de mix documentados;
- [ ] playthrough completo por uma pessoa com boss ativo e rodada de balanceamento;
- [ ] soak, memória, térmica e frame pacing nos aparelhos-alvo;
- [ ] resize/safe areas/aspect ratios e acessibilidade nos alvos finais;
- [ ] licença do jogo e termos comerciais dos assets confirmados;
- [ ] repositório Git válido para diff, tag e rollback de release;
- [ ] assinatura/notarização macOS, AAB, Play Console e pipeline de loja definidos.
