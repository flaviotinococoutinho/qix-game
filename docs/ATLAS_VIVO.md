# Atlas Vivo — jogo, autoria e direção de produção

> **Verificado em** 2026-09-07 · commit `a1afb90` · macOS Apple M2, Godot 4.7.2 Mono e Blender 5.2.0 LTS
> **Alcance:** implementação local sobre essa base, ainda sem commit próprio; testes e probes atuais em `build/modernization/`. Produção AAA, paridade integral com Volfied e QA de aparelhos físicos não foram concluídos.

## O que está jogável

Três setores com perfis distintos de chefe, alvo de 80%, pressão por tempo/território e quatro
balizas por setor. O jogador escolhe onde cortar, quanto arriscar na trilha e quais objetivos
cercar. Capturas eliminam ameaças absorvidas pelo território e compram respiro no diretor.

| Elemento | Desafio e resposta do jogador |
|---|---|
| Cartógrafo | anda na malha segura; desenhar cria uma trilha vulnerável; fechar consolida território |
| Núcleo | WANDER, PURSUIT ou SWEEP; fases por área, caça à trilha e fúria por confinamento |
| Vagalume | percorre fronteira viva; o preview mostra a trajetória real; território pode isolá-lo |
| Dardo | nasce com aviso e só depois dispara; pode cortar a trilha e gerar brasa |
| Brasa | avança na trilha; nasce com aviso; movimento e fechamento evitam alcançá-la |
| Baliza | capturada apenas quando sua célula se torna CLAIMED; gera cadeia de pontos e item |
| Impulso | velocidade temporária; muda quanto o jogador percorre por tick |
| Estase | suspende movimento do Núcleo pelo número integral de ticks anunciado |
| Escudo suspenso | suspende o gasto do escudo; não concede imunidade contra colisões |
| Purga | neutraliza ameaças menores e restaura um piso de escudo |
| Conclusão | TARGET, SINGLE_FILL e SEALED, com escada de bônus e recompensa sem morte |

Todo aviso nasce de estado/evento confirmado. Warmup e dormência não são letais; a graça de
reentrada vale durante todo seu último tick. A brasa não aparece matando no mesmo instante do
corte. Concluir com três vidas é possível com chefe, diretor e itens ativos: a rota automatizada
está em `tests/integration/boss_active_campaign_playthrough_test.gd`; ela também exige os quatro
tipos de item e reproduz os três replays finais. Isso não substitui calibrar a experiência humana.

## Jogar e observar

Build local macOS: `build/modernization/Lumen Atlas Vivo.app`. Para reconstruí-la, execute
`bash tools/shipping/build_atlas_macos_local.sh`. O script exporta, reassina com o `codesign`
nativo e verifica tanto o bundle quanto a execução de `--version`. A primeira assinatura
integrada passou em `codesign --verify`, mas o AMFI rejeitou seus entitlements DER ao executar;
o recibo e o reparo estão registrados no relatório local. A assinatura é ad-hoc para QA.
Ver [exportação macOS no Godot](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html)
para a etapa de distribuição.

Abra `project.godot` no Godot 4.7.2 ou execute a cena principal. Setas/WASD movem, Espaço/Z
desenham, Enter confirma e Esc/P pausa. F2 alterna palco 2.5D/vista plana, F4 reduz movimento
visual e M alterna som. Gamepad e touch seguem o adaptador existente. F3 é diagnóstico de
autoria, com identidades, estados e decisões atuais, não um comando de gameplay.

O campo mantém uma célula por unidade lógica. A janela passa a desenhar texto e HUD em
resolução nativa; na tela local o framebuffer observado foi 480×640. A superfície tática interna
é 720×960. Os modelos têm geometria 3D real, materiais PBR e componentes separados, posicionados
pela mesma conversão do campo. O tamanho da malha é apresentação; o ponto de contato continua
na grade. Há sinalização tática mesmo com os corpos 3D ligados e fallback 2D.

## Onde autorar

| Necessidade | Fonte |
|---|---|
| nova rodada, posição de balizas, seed, curva por setor | `tools/build_campaign_content.gd`, `ROUND_SPECS` |
| movimento, escudo, score e arbitragem | `game/rules/game_rules.gd` |
| fases, caça e fúria do chefe | `game/rules/boss_behavior_profile.gd` |
| escada de spawns, intervalos, graça, warmup e dormência | `game/rules/threat_profile.gd` |
| ciclo de itens, durações e piso de escudo | `game/rules/item_profile.gd` |
| economia de conclusão | `game/simulation/scoring/bonus_ladder.gd` |
| tamanho de cada modelo e paleta | `game/rules/round_visual_definition.gd`, `content/visuals/` |
| geometria original reproduzível | `tools/assets/build_lumen_models.py` |
| edição artística no Blender | `tools/assets/source/lumen_actor_library.blend` |
| modelos entregues ao Godot | `assets/models/lumen/*.glb` e `manifest.json` |

Depois de mudar a fonte do conteúdo, execute `tools/build_campaign_content.gd` pela engine:
o gerador valida e promove Resources usando a transação com journal existente. Mudanças diretas
nos `.tres` gerados podem ser sobrescritas pela próxima geração. Do mesmo modo, o gerador Python
reconstrói a biblioteca geométrica; alterações artísticas manuais no `.blend` devem ser exportadas
separadamente ou incorporadas ao script antes de regenerá-lo.

Para criar outro tipo de ator, defina estado/canonicalização, capacidade e regra pura no domínio;
acrescente eventos após os IDs existentes; implemente leitura em snapshot/view e o proxy de
apresentação; cubra warmup, contato, captura, morte, reuso e replay. Aumentar capacidade de pools
exige medir tick e leitura de tela. A malha, Tween ou uma simulação de física visual jamais pode
decidir contato/captura. Ver ADR-0014.

## Biblioteca Blender e reprodução

Geometria original sem bytes de ROM, texturas externas ou provedores pagos. São seis modelos,
com 260–1.380 triângulos por asset; tamanhos/hashes e nomes de componentes estão no manifest.
Peças como `Core`, `Crown`, `WingLeft/Right`, `Rail`, `Thruster` e `Receiver` são editáveis.
O render de inspeção está em `build/modernization/lumen-models-gallery.png`.

O MCP oficial instalado é acessado por `tools/assets/blender_mcp_job.py`, usando o Python que
já contém `mcp` e `blmcp`. A ferramenta descoberta é `execute_blender_code_for_cli`; o recibo
fica em `build/modernization/blender-models-receipt.json`. O job usa um `.blend` vazio local e
`QIX_PROJECT_ROOT`, preserva bytecode fora do bundle assinado e não altera preferências globais.

## Barra de qualidade e próximos marcos

Esta entrega é uma base de produção evoluída e jogável. O termo AAA é um objetivo de produção,
não o resultado de um refactor ou de um total de testes. Para avançar com critérios objetivos:

1. **Calibração humana:** terminar os três setores com teclado/gamepad/touch; medir mortes por
   causa, entendimento de avisos, duração e atalhos. Ajustar perfis por evidência, não só rapidez.
2. **Repertório de desafios:** planejar e validar encontros distintos, incluindo armas/tiros,
   dano ao chefe, mais de um chefe, variações de arena e campanha maior. Os 16 encontros de
   Volfied, seu elenco completo e todos os seus encerramentos não foram reproduzidos aqui.
3. **Produção artística:** diretor de arte, animações de componentes, efeitos e som por setor;
   validar silhueta/contraste em movimento e preservar proveniência de cada asset.
4. **Ferramentas de conteúdo:** edição de arenas, perfis por dificuldade, catalogação de atores,
   validação de placements e rotas regressivas de campanha antes de acrescentar dezenas de fases.
5. **Performance e lançamento:** soak, frame pacing nas cenas de pico, aparelhos Android físicos,
   temperatura/lifecycle, acessibilidade, localização, controles remapeáveis, saves/configurações
   e distribuição assinada. Evidência antiga de shipping 2D não certifica o novo palco.

## Evidência reproduzível

- Suíte final: **260 testes, 13.598 asserções, zero falhas** em 8.133 ms.
- Renderer GL Compatibility real: **20 verificações**, seis modelos carregados, captura
  de 17,9%, coleta de baliza, layout assentado e checksum preservado na troca de apresentação.
- Campanha ativa: três setores completos com três vidas; score acumulado 46.045,
  dez balizas e todos os quatro tipos de item; replays finais reproduzidos pela suíte.
- Simulação: 3.600 ticks, p95 **102 µs**, p99 **123 µs**, máximo **34.004 µs**.
  O percentil aprovado não elimina o pico; capturas caras continuam alvo de otimização.
- Build exportada: assinatura ad-hoc nativa e abertura verificadas. Em 600 frames com limite
  explícito de 60 FPS, p95/p99 GL **18,497/19,691 ms** (máximo 71,472 ms); Metal
  **19,213/20,784 ms** (máximo 22,071 ms). O relatório externo de GPU é separado;
  um probe com `external_gpu_pending` sozinho jamais certifica esse gate.
- Metal HUD: **1.398 pares válidos**, GPU p95 **0,69 ms**, máximo **1,82 ms**;
  frame máximo **38,68 ms**, zero stalls acima de 150 ms e todos os checks aprovados.
  O parser teve **16 testes Python** aprovados: descarta somente o prefixo de relógio com
  startup/PID/histórico completos e preserva stalls reais e logs sem contexto.


- Áudio no export: smoke de **900/900 ticks a 60 Hz**, exit 0 e log sem erros/leaks;
  audição crítica permanece pendente.

- `tests/run_tests.gd`: domínio, integração, replay, input, áudio, layout e import dos GLBs.
  O runner agora reprova também erros de compilação/instanciação durante a descoberta.
- `tools/dev/verify_depth_stage.gd`: renderer real, modelos, captura/coleta, fallback e checksum.
- `tools/shipping/framebuffer_shader_probe.gd`: somente CLAIMED revela o fundo original.
- `tools/profile_board_view.gd` e `tools/profile_simulation_step.gd`: limites de CPU.
- `tools/verify_m2_capture_route.gd`: isolamento territorial; nessa cópia de QA chefe/diretor/itens
  são desabilitados explicitamente. Não usar esse resultado como prova da dificuldade da campanha.

Capturas/relatórios em `build/modernization/` são locais e ignorados por Git. O export atual,
quando presente nessa pasta, é uma build de QA local, não um pacote de loja.
