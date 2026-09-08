# TEST_MATRIX

> **Verificado em** 2026-09-07 · commit `87bd854` · Godot 4.7.2-stable, Linux headless
> **Alcance:** preparação da PR #67 sobre `ca745780`, com resultados vinculados à árvore nos logs do gate.
> **Resultado:** 263 testes, 12723 asserções, 0 falhas. O inventário abaixo é conferido pelo runner.
> Exportação, assinatura, Android físico e mérito visual/sonoro não foram revalidados.

## Comando canônico da suíte

```bash
python3 tools/ci/headless_gate.py --godot "$GODOT" --logs /tmp/qix-headless --isolate-missing-editor-extension
```

Resultado atual: **263 testes, 12723 asserções, 0 falhas** — árvore preparada sobre
`ca745780`; resultados de outras branches não são intercambiáveis.

**Inventário da suíte (derivado, não digitado):** 49 arquivos de teste · 263 casos `test_*`.

A guarda de inventário, quando presente nesta branch, compara os casos pelo mesmo mecanismo
de descoberta do runner. A contagem de asserções é medida pela execução, não inferida do texto.
Os logs retêm diagnósticos e o código de saída. A extensão nativa opcional ausente é isolada
explicitamente pelo gate; seus scripts runtime permanecem. Isso não é QA da extensão nativa.

As evidências de shipping citadas abaixo pertencem ao run de macOS de **2026-09-03**,
`20260903T065739Z-65912`; não foram substituídas por testes headless. A tabela de cobertura
é descritiva, e o inventário autoritativo continua sendo a descoberta de testes desta árvore.

## Cobertura automatizada

| Área | Evidência coberta |
|---|---|
| `BoardState` | borda inicial, índices, mutações, contagem de área e bytes canônicos |
| `BoardView` | máscara R8 byte a byte, shader/paleta, revelação exclusiva de `CLAIMED`, reutilização da textura, skip sem mudança, telemetria limitada e ausência de mutação do domínio |
| exposição da trilha | curva monótona com piso em `new_segment_slow_px` e teto geométrico, guarda contra campo degenerado, projeção do uniforme `trail_exposure` no shader, nome do aviso no HUD e checksum idêntico ao de um universo sem `sync` |
| RNG | sequência determinística e limites |
| captura | corte cardinal, lado protegido pelo anchor, consolidação da trilha e rejeição pura de auto-interseção |
| simulação | capturas sucessivas até mais de 80%, pontuação, percentual, arbitragem captura×contato nos dois modos, morte, rollback da trilha, reentrada, game over, vitória e bônus |
| sessão | intro/clear temporizados, confirmação sem intent, simulação congelada após vitória, carry de score/vidas, board/replay novos, conclusão e reinício da campanha |
| replay | reprodução determinística, checksum, round-trip binário e rejeição atômica de versão/seed/regras/geometria/estado inicial incompatíveis |
| checksum dourado | valores literais fixados para `RULES_VERSION`, `SCHEMA_VERSION`, seed e `config_hash` das três rodadas de produção, e para o checksum inicial/final/serializado de uma rota de 177 ticks com o chefe ativo — falha quando o contrato de replay se move, verde quando só a apresentação muda (invariantes 7 e 8) |
| entrada | teclado/InputMap, direção única/sobreposição, D-pad, stick com histerese, A/X/Start, estado independente por gamepad, deduplicação InputMap×raw de A/Start, multitouch, disconnect/reset e equivalência canônica gamepad×touch |
| feedback | cues por evento, streams PCM determinísticos, loops distintos e guard frame, buses Music/SFX com limiter, oito vozes, pausa/teardown, prioridade háptica e invariância de replay/checksum; intenção e prioridade declaradas por cue, escada de prioridade do som igual à da háptica, e alocação de voz que recusa cortar um cue mais importante |
| boss | validação dos perfis WANDER/PURSUIT/SWEEP, octantes inteiros, jitter determinístico, reflexão, pulso de velocidade, limites seguros, hash de regras e replay incompatível rejeitado antes da mutação |
| conteúdo | três rodadas ordenadas, IDs/seeds únicos, referências externas separadas, fundos 225×283 aprovados, alvo 80%, curva crescente e três perfis externos de boss |
| geração transacional | shadow staging, lock exclusivo por projeto via loopback, WAL v3 ancorado ao SHA do manifest, hashes/tamanhos de payload/backup, state machine integral, targets terminais, rollback/cache e recovery após interrupção/processo morto |
| apresentação | HUD de campanha, progresso até alvo, contador de percentagem encenado em degraus (escada de denominações, teto e piso de duração, regressão instantânea), intro/clear/game over/campanha/pausa, continuidade de score/vidas entre setores (carry-in na intro, ganho do setor no clear, setores estabilizados nas fases terminais, prompt herdando o acento do próximo setor), VFX de captura/impacto e paleta de jogador/boss sem alterar checksum |
| contraste cromático | luminância WCAG contra referências conhecidas, matrizes de dicromacia colapsando o eixo correto, swatches iguais às modulações do shader, catraca de regressão por par e dívida documentada coerente com a paleta autorada |
| shipping | ícone quadrado, presets sem segredo, filtros, dispatch pela cena principal, smoke de áudio com marker/watchdog, seleção segura do serial, frame pacing e contratos de framebuffer/Metal HUD |
| integração | existência, carga, campanha/feedback/touch ligados, camadas obrigatórias da cena principal, permissão Android de vibração e 60 Hz persistidos no projeto |
| captura de erros | o runner de testes falha por erro de script ocorrido depois de uma asserção, e limpa a janela entre testes |
| invariantes 1 e 4 | varredura estática de `game/simulation`, `game/rules` e `game/session` por símbolo do mundo real (acaso global, relógio, `Input`, `Tween`, física, `await`, `_process`); o próprio scanner é validado contra amostras positivas e negativas, de modo que ele não pode passar sem olhar |
| invariante 10 | SHA-256 de todo arquivo de mídia de `assets`, `game`, `ui`, `app`, `content`, `tools`, `tests` e `reference` conferido contra `assets/ASSET-PROVENANCE.md`; hash declarado sem arquivo correspondente é recusado como órfão salvo em linha `(removido)`; arquivo marcado `(removido)` não pode reaparecer; a checagem é exercitada contra bytes de controle não declarados e o padrão da tabela é validado numa linha sintética, para que uma reformatação não a transforme em laço vazio |

## Verificação de engine, gameplay e conteúdo

| Verificação | Resultado |
|---|---|
| diagnósticos direcionados dos scripts alterados | sem erro ou warning do jogo |
| validação estrutural de `app/bootstrap.tscn` | sem recurso/script ausente, NodePath inválido ou nome duplicado |
| execução headless da cena | sem crash; playback de hardware é desabilitado somente no headless/probes |
| múltiplas capturas e transição real | R1 em cinco capturas, R2 em duas, R3 em três; cada rodada superou o alvo de 80% |
| transições de sessão | `ROUND_INTRO` → `PLAYING` → `ROUND_CLEAR`; score/vidas persistem e board/replay reiniciam por rodada |
| campanha com boss ativo | rota automatizada por intents públicos: zero mortes; scores 13.190 → 23.960 → 36.290; três replays com checksum exato |
| natureza da rota | **automatizada, não humana**; não mede dificuldade, ergonomia, diversão ou balanceamento percebido |
| boss autorável | WANDER, PURSUIT e SWEEP externos, determinísticos, distintos e limitados a velocidade segura |
| áudio PCM | guard frame cobre a leitura one-past-end do loop observada no Android e documentada no Godot #119778 |
| geração autorável | WAL v3 finalizou 16 staged/16 committed; subconjunto direcionado passou 22 testes/353 asserções |
| perfil isolado do board | R8 p50/p95 1/1 µs em 240 amostras; legado sintético 31.160/32.304 µs; speedup p95 32.304× e 4× menos bytes por refresh |
| gamepad multi-device | sticks/botões ficam por `device`; A/confirm e Start/pause são consumidos uma vez mesmo chegando por InputMap e raw |
| guarda de invariantes | o teste fica **vermelho** quando `randi()` e `Time.get_ticks_msec()` são plantados em `game/simulation/game_simulation.gd`, apontando arquivo, linha, regra e invariante; verificado plantando e revertendo a violação |
| guarda de proveniência | vermelha nos três sentidos, verificada plantando e revertendo em 2026-09-06: um PNG não declarado em `ui/` é acusado pelo hash e pelo nome; um byte apenso a `assets/backgrounds/aurora_foundry.png` deixa o arquivo indeclarado **e** torna órfão o hash `57517e7e…` do manifesto; recriar `backgrounds/verdant_singularity.png`, marcado `(removido)`, é recusado |
| log final da suíte | 263 testes, 12723 asserções, 0 falhas, sem warning do jogo sobre `cba520a`; parser Metal HUD 10/10 no run de macOS de 2026-09-03, não reexecutado na nuvem |
| guarda do checksum dourado | provada nos dois sentidos: alterar um default de `BossBehaviorProfile` deixa `config_hash` de R1/R2 e o log serializado vermelhos; trocar `trail_color` de uma rodada mantém os quatro testes verdes |

## Matriz do shipping externo

| Verificação | Estado atual | Evidência/limite |
|---|---|---|
| runner canônico | **passou** | run `20260903T065739Z-65912`, `runner_status=complete`, `runner_exit=0`, `overall_exit=0` |
| export macOS ad-hoc | **passou** | bundle atual 101.199.872 bytes, arm64; payload e `codesign --verify --deep --strict` verdes |
| smoke macOS headless/logs | **passou** | cena exportada encerrou normalmente; scans de smoke/frame/framebuffer/áudio sem script/resource/parse/invalid-call ou `ObjectDB` leak |
| smoke macOS com áudio real | **passou** | 900/900 ticks a 60 Hz; nominal 15 s, wall 17 s; 1 marker; watchdog 30 s sem timeout/sinal; saída 0 |
| frame pacing exportado | **passou** | 600 amostras em gameplay ativo; p95 18,331 ms, p99 20,041 ms, máximo 75,433 ms; render CPU p95 0,071 ms; zero stalls ≥150 ms |
| GPU Metal exportada | **passou** | 1.380 pares válidos; GPU p95 0,23 ms, p99 0,29 ms, máximo 0,4 ms; frame p95/p99 16,67 ms, máximo 64,97 ms; malformed/unpaired/stalls = 0 |
| framebuffer exportado | **passou** | 17 asserções, viewport final 240×320, máscara R8 igual ao board; somente `CLAIMED` preservou o texel original amostrado |
| export Android | **passou** | APK 40.486.376 bytes; archive, payload e assinatura debug verdes; SHA-256 `db61015cfc6bea849ec41fad6907e1c0af625d8c38866c2e38bc68306c6411e2` |
| seleção Android | **passou** | `selected_serial=emulator-5554`, `selection_source=runner-started-emulator`; sem seleção implícita de device físico |
| smoke Android/AVD | **passou** | readiness estável, instalação sem streaming, main loop após 13 s, +30 s vivo, screenshot e scan sem crash do pacote/ANR/script/resource |
| regressão do loop PCM | **passou após correção** | o smoke real encontrou `SIGSEGV` no primeiro loop; guard frame aplicado e nova execução passou |
| gamepad e rumble físico | **não executado** | eventos sintéticos cobrem tradução/prioridade, não o hardware |
| multitouch e vibração física | **não executado** | emulador cobre UI/launch, não ergonomia, latência ou atuador real |
| audição crítica | **não executada** | estrutura/mix são validadas; percepção sonora exige escuta física |
| playthrough humano completo | **não executado** | a campanha foi vencida por automação determinística com boss ativo; não por uma pessoa |
| soak/memória/térmica/hardware-alvo | **não executado** | os 30 s são smoke, não soak; faltam aparelhos de referência |
| resize/safe areas/aspect ratios adicionais | **não executado em matriz física** | viewport de referência permanece 240×320 retrato |
| distribuição | **não executada** | faltam notarização/assinatura de distribuição macOS, AAB/Play Console e licenças finais |
| rastreabilidade Git | **bloqueada externamente** | é necessário um repositório Git válido para diff, tag e rollback de release |

Um aparelho físico só entra no runner com os dois parâmetros explícitos
`QIX_ANDROID_DEVICE_SERIAL="SERIAL_EXATO"` e `QIX_ANDROID_ALLOW_PHYSICAL_DEVICE=1`. Sem serial,
o runner aceita um único emulator online ou inicia seu próprio AVD; recusa múltiplos emulators
ambíguos. O uso físico reinstala e encerra o package ID de QA, portanto continua sendo um gate
manual deliberado.

## Leitura correta dos probes

O frame probe é despachado pelo bootstrap da cena principal exportada quando recebe
`--shipping-probe=frame-pacing`. Ele confirma `PLAYING` antes de aquecer/coletar; não usa o
antigo caminho `--script` contra o PCK embutido. Como `RenderingServer` não expôs timing GPU no
Metal, o JSON principal fica em `external_gpu_pending`; o gate composto só passa depois que o
relatório independente do Metal HUD também passa. O runner final verificou ambos, e a suíte
Python do parser passou 10/10.

O playback não é aberto em headless ou probes gráficos curtos por causa do leak de teardown do
Godot #76745. Isso não silencia o runtime normal nem o smoke Android. O scan final macOS não
encontrou `ObjectDB instances were leaked`.

## Exclusões conhecidas dos diagnósticos globais

O scan de todo o projeto atravessa addons de desenvolvimento e, nesta máquina, reporta exemplos
do GUIDE sem o plugin correspondente, C# sem projeto selecionável e entradas antigas do
SoftBody2D no editor. Por isso, o gate usa diagnósticos direcionados para o código do jogo,
validação estrutural da cena, runtime real e runner headless independente dos addons.

Com o editor já aberto, uma segunda instância/import também pode disputar a porta do daemon
Fennara e emitir `AddrInUse`; isso é um conflito de tooling, não uma falha do runtime do jogo.
As verificações de import/editor devem ser executadas sequencialmente.
