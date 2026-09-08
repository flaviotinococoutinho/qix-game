# IMPLEMENTATION_STATUS — Atlas Vivo integrado localmente

> **Verificado em** 2026-09-08 · commit `e8307d1` · revisão de código e documentação da integração local
> **Alcance:** Atlas Vivo, bundle remoto #78 e atualização MCP preservados na árvore de integração.
> A suíte final, a composição com os resíduos da fila e as ações no GitHub ainda estão em andamento.
> Nenhuma aprovação de release, aparelho físico ou publicação é inferida deste registro.

## Estado atual

O projeto combina o domínio determinístico do Atlas, campanha ativa com atores/itens e palco
2.5D com as melhorias remotas de contraste, entrada, feedback e guardas. A integração está sendo
validada pelo coordenador. O inventário e os resultados correntes pertencem a
[TEST_MATRIX.md](TEST_MATRIX.md) e ao
[relato de integração](loop/runs/2026-09-08T-mcp-github-integration.md), vinculados à árvore testada;
números de branches anteriores não são somados nem apresentados como resultado final.

O jogo é uma base jogável de produção. O repertório completo de Volfied, produção artística AAA,
calibração humana e distribuição comercial continuam abertos. A
[ADR-0014](decisions/ADR-0014-atlas-lifecycle-depth-stage.md) define a evolução Atlas;
[PROJECT_CONTRACT.md](PROJECT_CONTRACT.md) define o ownership e as fronteiras atuais.

## Implementação presente

| Área | Comportamento implementado | Fonte principal |
|---|---|---|
| Território | movimento em grade, trilha vulnerável, fechamento e captura por plano confirmado | `game/simulation/board/`, `game/simulation/player/` |
| Campanha | três setores, carry de score/vidas, intro/clear/derrota/conclusão e um replay por tentativa | `game/session/`, `content/campaigns/`, `content/rounds/` |
| Chefe | WANDER/PURSUIT/SWEEP, fases por área, perseguição de trilha e confinamento | `BossBehaviorProfile`, `BossState`, `BossMotion`, `BossBehaviorController` |
| Atores menores | vagalumes de fronteira, dardos e brasas de trilha; identidades por spawn e pools limitados | `MinorActorPools`, `WalkerRules`, `DartRules`, `EmberRules` |
| Lifecycle e justiça | DESPAWNED/WARMUP/ACTIVE/DORMANT/DYING; aviso antes de letalidade, graça de respawn e dissipação | `ActorLifecycle`, `ThreatProfile`, regras de cada ator |
| Diretor | pressão por território/tempo, agenda determinística e respiro após captura | `game/simulation/director/` |
| Objetivos e efeitos | balizas capturadas por CLAIMED, cadeia de pontos, VELOCITY/STASIS/SHIELD_FREEZE/PURGE | `game/simulation/objectives/`, `ItemProfile`, `EffectTimers` |
| Conclusão | TARGET/SINGLE_FILL/SEALED, escada de bônus e recompensa sem morte | `ScoreLedger`, `BonusLadder`, `GameSimulation` |
| Replay | RULES_VERSION 4, schema 1; compatibilidade validada antes de reproduzir; dourados com os três perfis | `game/simulation/replay/`, testes de replay/campanha |
| Palco | SubViewport tático, câmera ortográfica, seis GLBs originais e fallback plano | `app/stage/depth_stage.gd`, `assets/models/lumen/` |
| Leitura tática | célula de contato, silhuetas/contornos 2D, previews e estados continuam observáveis com modelos ligados | views player/boss/minor, `ui/debug/actor_trace_overlay.gd` |
| Revelação | máscara R8 reutilizada; somente CLAIMED revela o fundo original | `BoardView`, `board_reveal.gdshader` |
| Feedback | PCM procedural, cues de atores/objetivos, oito vozes priorizadas, exposição compartilhada com háptica | `QixAudioDirector`, `QixProceduralAudioLibrary`, `QixFeedbackHub` |
| Entrada | teclado, D-pad/analógico por device, touch flutuante, histerese, flick, dedup de pausa/confirmação | `GameInputAdapter`, `QixTouchControls` |
| Conteúdo | geração transacional de Resources, WAL/journal, lock, promoção, rollback e recovery | `CampaignContentTransaction`, `tools/build_campaign_content.gd` |
| Ferramental | atualização Godot AI 4.0.2 preservada; Fennara, Blender e ferramentas GitHub na integração | plugin, manifesto de modelos e relato por SHA |

Apresentação observa estado e eventos confirmados. Nem câmera, escala, malha, pulso, áudio,
dispositivo ou relógio de frame decide colisão/captura. A dissipação visual após a vitória não
continua mutando a simulação que a sessão já arquivou.

F2 alterna 2.5D/plano; F3 mostra diagnóstico de autoria; F4 reduz movimento do palco; M alterna
som. Esses controles não alteram o contrato de replay. Godot AI e Fennara são ferramental,
não dependências para as regras da partida; o payload exportado precisa ser conferido após
atualizações dos plugins.

## Evidência corrente e registros históricos

| Registro | Árvore/época e alcance | Como usar |
|---|---|---|
| Integração de setembro/08 | composição Atlas + remoto + MCP, ainda em validação | consultar TEST_MATRIX e relato por SHA; não afirmar final verde antes do fechamento |
| Atlas local anterior | evolução sobre `a1afb90`, preservada em `0c63665`; testes, campanha ativa, renderer e export QA locais | [ATLAS_VIVO.md](ATLAS_VIVO.md), `build/modernization/REPORT.md` e logs locais |
| Bundle e PRs remotas | cada head auditado tem checks e evidências próprios | inventário de 32 PRs no relato; sucesso individual não certifica a composição |
| Shipping 2D de setembro/03 | runner `20260903T065739Z-65912`, candidate QA macOS e AVD Android | [SHIPPING_PASS.md](SHIPPING_PASS.md); não certifica o palco Atlas nem a versão nova do plugin |
| Geometria/payload | derivados do BoardState e protegidos por guarda documental | [PERFORMANCE.md](PERFORMANCE.md); independentes dos tempos de uma máquina |

A rota de campanha com chefe, diretor e itens ativos está em
`tests/integration/boss_active_campaign_playthrough_test.gd`: exige conclusão dos três setores,
coleta dos quatro tipos de item e reprodução dos replays. Progressões e placares de versões
anteriores à economia Atlas permanecem históricos; os valores correntes vivem no teste e nos
logs da árvore validada. A possibilidade de uma rota sem mortes não substitui um playthrough humano.

M2 é outra prova: desabilita explicitamente chefe/diretor/itens na fixture para isolar território
e transição. Seu resultado não demonstra a dificuldade nem a cobertura de objetivos da campanha.
Probes headless não ouvem áudio, não exercitam ergonomia e não medem a GPU do aparelho alvo.

## Pendências com impacto de produto

- Concluir a validação da composição final e registrar commit/PR/checks/merges reais no relato.
  A autorização já recebida para integração não é uma afirmação de que todas as ações terminaram.
- Jogar os três setores em teclado, gamepad e multitouch; registrar mortes por causa, percepção
  dos avisos, tempo, frustração e compreensão de objetivos. Calibrar por evidência humana.
- Expandir encontros, arenas, armas/dano ao chefe e variações de campanha com contratos e rotas
  regressivas. O elenco completo, os 16 encontros e todos os encerramentos de Volfied não estão entregues.
- Revisar contraste em movimento, arte/animação, acessibilidade e leitura nos tamanhos reais;
  o fallback 2D e o palco 3D precisam permanecer utilizáveis. Ver [ART_DIRECTION.md](ART_DIRECTION.md).
- Fazer audição crítica em fones/alto-falantes e testar rumble/vibração reais. Síntese e mix
  podem ser verificados sem dispositivo, mas isso não aprova loudness, fadiga ou qualidade sonora.
- Perfilar picos de captura, frame pacing, memória, soak, temperatura e lifecycle em aparelhos
  representativos. Percentil aprovado não elimina um pico caro; ver PERFORMANCE.
- Exportar e conferir payload/MCP/runtime da composição final. Os novos GLBs e o plugin 4.0.2
  não são certificados pelos smokes antigos da versão plana.
- Produzir distribuição: Developer ID/notarização no macOS, keystore/AAB/Play Console no Android,
  com seus gates reais. Pacotes locais existentes são QA ad-hoc.
- **Procedência da licença raiz permanece pendente.** A auditoria histórica do #73 identificou
  em LICENSE o aviso MIT `Copyright (c) 2026 seina369` que acompanhava curve2collision. Remover
  o addon não decide a titularidade/licença do código original. Preservar avisos de terceiros
  e obter decisão do mantenedor antes de distribuição; nenhuma licença foi alterada nesta edição.
- Confirmar termos comerciais aplicáveis aos assets gerados. A proveniência técnica está em
  [ASSET-PROVENANCE.md](../assets/ASSET-PROVENANCE.md); presença de hashes não é licença comercial.

Antes de exports grandes, medir espaço disponível e respeitar as verificações dos scripts;
uma observação antiga de disco cheio não descreve a capacidade atual. Editor/import/export
precisam ser coordenados para evitar disputa pelo daemon Fennara e artefatos em uso.
