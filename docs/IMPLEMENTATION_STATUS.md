# IMPLEMENTATION_STATUS

## Gate atual

**M2 / G2 — VERDE. Shipping candidate técnico — VERDE. Release/hardware — ÂMBAR**
(2026-09-03).

A campanha, a revelação territorial e as transições estão jogáveis. O shipping pass de código
está integrado; suíte, exports locais, smoke e probes terminaram verdes. Isso forma um candidate
técnico local, mas não torna correto chamar o jogo de “AAA” nem fechar o gate de publicação:
hardware real, audição crítica, playthrough por uma pessoa, soak, distribuição e questões legais
continuam pendentes.

## Entregue

- `GameSession` encadeia `ROUND_INTRO → PLAYING → ROUND_CLEAR → próxima rodada`, além de
  `GAME_OVER` e `CAMPAIGN_COMPLETE`, sem avançar uma simulação já encerrada.
- A campanha `lumen_cartography` possui três `RoundContent` autoráveis. Regras, geometria,
  seed, comportamento do boss e visual são Resources separados; cada rodada mantém alvo de
  80% e progride escudo, ameaça e recompensa.
- O boss usa três perfis determinísticos autoráveis: `WANDER`, `PURSUIT` com jitter limitado
  e pulso de 115%, e `SWEEP` com pulso de 125%. O perfil integra o hash canônico das regras,
  replay e checksum; a apresentação pode lê-lo sem mutar o domínio.
- Score e vidas atravessam a transição; board, shield, tick e replay reiniciam para a nova
  rodada. Cada tentativa arquivada retém checksum e replay próprios.
- O replay valida versão, seed, hash de regras/geometria e checksum inicial antes de aceitar
  qualquer mutação.
- `BoardView` envia diretamente os bytes do `BoardState` como máscara `R8`, reutiliza a
  `ImageTexture` e revela o fundo original somente onde o estado é `CLAIMED`.
- Abyssal Relay, Aurora Foundry e Verdant Singularity formam a direção original “Lumen
  Cartography”; fontes, derivados e a revisão rejeitada estão documentados no manifesto de
  assets.
- Áudio original é sintetizado em PCM no runtime: um loop por rodada, cues de gameplay,
  oito vozes de SFX e buses separados `Qix Master`, `Qix Music` e `Qix SFX`, com limiter e
  volumes autoráveis. Pausa suspende a música e o teardown libera playback/streams. Cada loop
  inclui um guard frame para o bug de acesso one-past-end do Godot 4.7.2
  ([#119778](https://github.com/godotengine/godot/issues/119778)). Runtime headless não abre
  playback; em builds gráficas, os argumentos que silenciam probes são aceitos somente com a
  feature `shipping_qa`, evitando o leak de teardown conhecido
  ([#76745](https://github.com/godotengine/godot/issues/76745)) sem silenciar o jogo normal.
- Háptica observa eventos confirmados, coalesce o pulso de maior prioridade por tick e envia
  rumble ao gamepad e vibração handheld quando a plataforma oferece suporte.
- Teclado/InputMap, D-pad, analógico esquerdo com histerese e overlay touch multitouch convergem
  para o mesmo `MoveIntent` cardinal antes do domínio. Stick, botões e edges são isolados por
  gamepad; desconexão limpa somente aquele device. A arbitragem drena no mesmo tick Start/A que
  chegaram tanto pelo InputMap quanto pelo evento cru, impedindo pausa ou confirmação duplicada.
  A/X desenham, A confirma e Start pausa; touch fornece stick, `DRAW` e pausa.
- HUD, transições, feedback audiovisual e controles são observadores: nenhum relógio de
  apresentação ou estado de dispositivo entra no RNG, replay ou checksum.
- O gerador de campanha monta 16 Resources e os entrega a uma transação WAL v3 persistente. Um
  lock interprocessual por listener loopback serializa geradores cooperantes; payloads/backups
  têm tamanho e SHA-256, e o SHA-256 canônico do manifest é repetido em cada record do journal
  append-only. A máquina de estados completa, a promoção por rename adjacente, o rollback reverso,
  o recovery prévio, a verificação terminal dos targets e a restauração do cache falham fechados
  diante de metadado, sequência ou bytes divergentes.
- Presets de QA macOS arm64 e Android arm64, probes de frame pacing/GPU e framebuffer e um
  runner reproduzível vivem em `export_presets.cfg` e `tools/shipping/`.
- O ícone original está configurado no projeto e nos pacotes de QA.

## Evidências atuais

- Runner headless em Godot 4.7.2 Mono com áudio dummy: **134 testes, 11.489 asserções,
  0 falhas** em 2026-09-03.
- O runner final `20260903T065739Z-65912` terminou `overall_exit=0` e estado `complete`.
  O bundle macOS arm64 ad-hoc tem 101.199.872 bytes; export, thinning, payload, smoke, frame
  pacing, Metal HUD, framebuffer, `codesign` e varredura de leaks passaram.
- O smoke gráfico de áudio macOS concluiu **900/900 callbacks físicos a 60 Hz**, em 17 segundos
  de parede, com driver normal, saída 0 e sem atingir o watchdog de 30 segundos.
- O APK Android ad-hoc tem 40.486.376 bytes e SHA-256
  `db61015cfc6bea849ec41fad6907e1c0af625d8c38866c2e38bc68306c6411e2`;
  export, archive, payload, assinatura, instalação e launch passaram. O próprio runner iniciou e
  selecionou exatamente `emulator-5554`, observou a main loop após 13 segundos e confirmou o
  mesmo processo vivo por mais 30 segundos, com screenshot e logscan verdes. Esse smoke normal
  exerceu o áudio.
- A rota determinística com boss ativo conclui as três rodadas sem mortes usando somente
  intents públicos. Progressão: R1 `17,9 → 35,8 → 49,3 → 71,7 → 86,9%`; R2
  `55,6 → 80,8%`; R3 `35,8 → 64,5 → 82,4%`. Score acumulado após cada rodada:
  `13.190`, `23.960`, `36.290`; os três replays arquivados reconstruíram os checksums finais.
  Essa é uma rota automatizada humanamente executável, não um playthrough humano.
- A rota M2 isolada continua reproduzindo cinco capturas até 82,5% e a transição R1 → R2;
  nela o boss é imobilizado deliberadamente para isolar território e transição.
- O framebuffer test do pacote macOS passou sobre o pipeline final
  `BoardState → R8 → shader → SubViewport framebuffer`: `CLAIMED` revelou o pixel esperado do
  fundo e `FREE`, `BOUNDARY` e `TRAIL` permaneceram cobertos. Relatório e PNG estão em
  `build/shipping/reports/macos-framebuffer.*`; foram 17 asserções e nenhuma falha.
- O microbenchmark headless do board mantém upload R8 de 63.675 bytes por refresh, contra
  254.700 bytes do caminho RGBA8 sintético. Ele mede CPU/preparação, não GPU.
- O profiling do candidate macOS mediu 600 frames em gameplay `PLAYING`: frame p95 18,331 ms,
  p99 20,041 ms e máximo 75,433 ms. O Apple Metal HUD forneceu 1.380 pares válidos, com GPU p95
  0,23 ms, p99 0,29 ms e máximo 0,40 ms; linhas malformadas, métricas órfãs e stalls acima de
  150 ms ficaram todos em zero.
- O gerador oficial concluiu **16 staged / 16 committed**. A transação v3 possui **22 testes e
  353 asserções** para commit/rollback, integridade/autorização, máquina de estados, lock entre
  processos, interrupção abrupta, cache, recovery e targets terminais.

Detalhes, comandos e limites estão em `docs/SHIPPING_PASS.md`, `docs/TEST_MATRIX.md` e
`docs/PERFORMANCE.md`.

## Riscos e pendências abertas

- Repetir o smoke Android em aparelho físico e validar lifecycle, áudio, temperatura, cutouts,
  densidades e comportamento fora do AVD.
- Exercitar gamepad, multitouch e rumble/vibração em hardware real. Os testes atuais usam
  eventos sintéticos e não comprovam mapeamento específico, latência, ergonomia ou suporte do
  dispositivo.
- Fazer audição crítica em caixas/fones e balancear loudness, fadiga, clipping percebido,
  transições musicais e prioridades de SFX. Áudio dummy/asserções não provam qualidade sonora.
- Executar playthrough humano completo com o boss ativo e registrar mortes, duração, pontos de
  frustração, acessibilidade e curva de dificuldade. A rota automatizada não substitui isso.
- Fazer soak e perfil em aparelhos-alvo. O relatório macOS exportado é válido, mas não substitui
  frame pacing, consumo, temperatura e throttling em dispositivos Android representativos.
- Produzir artefatos de distribuição: assinatura Developer ID, notarização e entitlements no
  macOS; keystore de release, AAB, Play Console e testes de loja no Android. Os pacotes atuais são
  QA ad-hoc.
- `.git/` é apenas um esqueleto incompleto: não há `HEAD`, objetos ou refs válidos, portanto
  não é possível produzir diff/commit ou revisar regeneração com segurança equivalente a Git.
- A licença raiz é byte a byte igual à licença do addon `curve2collision`; a licença pretendida
  para o jogo ainda precisa ser confirmada antes de publicar.
- Termos comerciais vigentes das imagens geradas precisam ser confirmados; a proveniência
  técnica está registrada em `assets/ASSET-PROVENANCE.md`.
- Há pouco espaço livre no volume. O runner exige 2 GiB para export e 3 GiB antes de iniciar o
  AVD, mas ainda é recomendável liberar margem adicional antes de repetir os dois pacotes.
- Uma segunda instância/import pode disputar a porta fixa do daemon Fennara e emitir
  `AddrInUse`; execute editor/import/export sequencialmente.

## Próximo gate recomendado

**Release candidate / G3:** validar controles, feedback e performance em hardware-alvo, fazer
audição crítica, soak e playthrough humano com o chefe ativo, fechar licença, proveniência e
repositório e então produzir artefatos assinados/notarizados, AAB e validação em loja. O runner
local verde é pré-condição cumprida, não substituto desses gates.
