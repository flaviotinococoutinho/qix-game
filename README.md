# QIX GAME (codinome)

Reimaginação original de um jogo territorial (gramática de Qix, sistemas de Volfied). Godot **4.7.2-stable**, GDScript tipado, simulação 2D determinística e apresentação **2.5D**, retrato lógico 240×320.

O vertical slice M2/G2 e o shipping candidate já encadeiam uma campanha autorável de três
rodadas: várias capturas até a meta de 80%, score/vidas carregados entre setores, replay isolado
por rodada, intro/clear reais, HUD/VFX, curva de dificuldade e fundos originais revelados somente
pela área capturada. O chefe alterna entre três perfis determinísticos, e áudio procedural,
háptica, gamepad e touch ficam fora do estado autoritativo/replay. Nenhum asset extraído de ROM é
necessário.

A identidade visual “Lumen Cartography” combina cartografia bioluminescente, máscara
territorial R8, ícone original e três cenários: Abyssal Relay, Aurora Foundry e Verdant
Singularity. Consulte `assets/ASSET-PROVENANCE.md` antes de distribuir.

## Atlas Vivo — integração de 2026-09-08

O jogo ganhou palco ortográfico com seis modelos 3D originais feitos pelo MCP do Blender,
HUD em resolução nativa, atores com identidade e ciclo de vida, diretor de ameaça, balizas,
quatro efeitos temporários e bônus de conclusão. A campanha tem rotas verificadas com chefe,
menores e itens ativos. Regras/replays estão na versão 4; gravações antigas são incompatíveis.

Leia [Atlas Vivo](docs/ATLAS_VIVO.md) para autoria, limites e próximos marcos de produção.
[Integração MCP](docs/MCP_INTEGRATION.md) descreve os launchers, diagnóstico e testes Godot/Blender.
Fontes editáveis e hashes estão em `tools/assets/source/` e `assets/models/lumen/`.
Os relatórios da nova implementação ficam em `build/modernization/`; os números de shipping
mais abaixo são **históricos da apresentação 2D de 2026-09-03**, não certificam esta versão.

## Abrir, executar, testar

Build macOS desta entrega: `build/modernization/Lumen Atlas Vivo.app`.
Reconstrução local com assinatura verificada: `bash tools/shipping/build_atlas_macos_local.sh`.

```bash
G=/Applications/Godot_mono.app/Contents/MacOS/Godot
$G --headless --path . --import                              # 1× por checkout
$G --headless --audio-driver Dummy --path . --script res://tests/run_tests.gd # testes
$G --headless --path . --script res://tools/verify_m2_capture_route.gd # rota 17,9→82,5% + R2
$G --headless --path . --script res://tools/profile_board_view.gd # perfil CPU do board
$G --headless --path . --script res://tools/build_campaign_content.gd # regenera conteúdo transacionalmente
tools/shipping/run_shipping_qa.sh                           # export + smoke/probes macOS/Android
$G --path . --editor                                         # editor (MCP godot-ai + fennara)
$G --path .                                                  # jogar
```

Controles:

- teclado: setas/WASD = direção; Espaço/Z = desenhar; Esc/P = pausa; Enter = confirmar;
- apresentação: F2 = 2D/2.5D; F4 = reduzir movimento; M = som; F3 = diagnóstico de atores;
- gamepad: D-pad ou analógico esquerdo = direção; A/X = desenhar; A = confirmar; Start = pausa;
- touch: stick esquerdo = direção; `DRAW` = desenhar/confirmar; botão superior direito = pausa.

O overlay touch aparece automaticamente em plataformas mobile; no desktop pode ser habilitado
para QA pela propriedade `show_touch_controls_on_desktop` do bootstrap. Gamepad, háptica e
ergonomia multitouch têm cobertura por eventos sintéticos, mas ainda precisam de validação em
dispositivos físicos. O adaptador mantém stick, botões e edges separados por device e consolida
no mesmo tick os sinais duplicados de Start/A recebidos pelo InputMap e pelo evento cru.

O áudio tem streams, mix e contratos automatizados; a audição crítica da mixagem permanece uma
etapa humana. Os loops PCM incluem um guard frame para contornar o acesso one-past-end do Godot
4.7.2 ([#119778](https://github.com/godotengine/godot/issues/119778)). Headless não inicia
playback; em builds gráficas, somente a feature `shipping_qa` reconhece os argumentos reservados
que silenciam probes curtos para evitar o leak de teardown conhecido
([#76745](https://github.com/godotengine/godot/issues/76745)). O runtime normal continua com
áudio, inclusive nos smokes macOS e Android.

## Registro histórico do shipping candidate — 2026-09-03

- suíte final: **134 testes, 11.489 asserções, 0 falhas**;
- runner `20260903T065739Z-65912`: macOS e Android concluídos com `overall_exit=0` e estado
  `complete`;
- macOS: bundle arm64 ad-hoc de 101.199.872 bytes, payload, smoke, `codesign`, frame pacing,
  Metal HUD, framebuffer com 17 asserções e varredura de leaks verdes; o smoke de áudio concluiu
  900/900 ticks físicos a 60 Hz em 17 segundos, sem atingir o watchdog de 30 segundos;
- frame pacing macOS: p95 18,331 ms, p99 20,041 ms e máximo 75,433 ms; o Metal HUD reuniu 1.380
  pares válidos, com GPU p95 0,23 ms, p99 0,29 ms e máximo 0,40 ms, sem linha malformada, métrica
  órfã ou stall acima de 150 ms;
- conteúdo: WAL v3 com lock loopback, âncora SHA-256 do manifest, integridade de payload/backup,
  máquina de estados e verificação terminal; **22 testes, 353 asserções e 16/16 commits**;
- Android: APK ad-hoc de 40.486.376 bytes, SHA-256
  `db61015cfc6bea849ec41fad6907e1c0af625d8c38866c2e38bc68306c6411e2`; o runner iniciou e usou
  exatamente `emulator-5554`, observou a main loop após 13 segundos e manteve o processo vivo por
  mais 30 segundos, com screenshot e logscan verdes.

Esses resultados validam o candidate local, não uma publicação. Aparelho físico, audição
crítica, gamepad/háptica/touch reais, playthrough por uma pessoa, soak, assinatura/notarização,
AAB/loja, licença e integridade do repositório continuam como gates explícitos.

Conteúdo autorável em `content/`; documentação viva em `docs/` (`ART_DIRECTION`,
`PROJECT_CONTRACT`, `TEST_MATRIX`, `IMPLEMENTATION_STATUS`, `SHIPPING_PASS`, `decisions/`).
