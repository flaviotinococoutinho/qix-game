# Integração autorizada da fila #20–#54 e reforço do CI

> **Verificado em** 2026-09-06 · commit `d72182b` · Godot 4.7.2-stable, Linux headless
> **Alcance:** integração de código, testes automatizados e sondas headless. Não inclui gameplay
> humano, julgamento visual, áudio em dispositivo físico, Android real ou exports de distribuição.

## Origem e integração

O mantenedor solicitou explicitamente resolver as PRs abertas e fazer ajustes. A PR #55 usa a
árvore da #51 (`c4cedb1`) e preserva sua resolução semântica #25×#50: a fração da transição fica
na apresentação, sem reintroduzir `float` em `GameSession`.

As PRs posteriores foram mescladas por SHA, sem squash nem force-push:

| PR | HEAD revisado | Entrega preservada |
|---|---|---|
| #52 | `7ce16b23351a46e7f491c2dcf159b558bb7ad5a4` | sonda da geometria real do HUD, teste horizontal e comentários corrigidos |
| #53 | `35245b60e62d2974daf08b5de5d9864e19f08058` | regra contra meta-PR redundante, censo e registro histórico |
| #54 | `9e44e000a9b24058f5dbe68ebb64985a0c8bdb20` | relatório de superfície por refs, critérios de QA humano e registro histórico |

Os conflitos dessas três integrações ficaram em `docs/LOOP_LEDGER.md`. A resolução manteve o
backlog integrado da #51, incorporou as políticas novas e não reintroduziu contagens antigas
como se fossem o estado atual. Os relatos individuais foram preservados. O relatório de
superfície agora explicita que refs não substituem a consulta do estado das PRs no GitHub.

O executor temporário de integração foi removido antes de publicar o candidato. Ele escreveu
somente na branch de integração, depois dos testes, e não fez merge de PR nem escreveu em main.
O workflow permanente continua com `contents: read`.

## Ajustes permanentes no CI

`tools/ci/headless_gate.py` valida a engine, preserva logs completos e reprova diagnósticos
`ERROR`, `SCRIPT ERROR` e `SHADER ERROR` mesmo quando o processo retorna zero. A execução
registra commit, árvore, engine e resultado em `manifest.json`; os artefatos ficam retidos por
14 dias. O código de saída continua obrigatório: falhas de asserção não dependem do detector
de diagnósticos.

A extensão nativa opcional Fennara do editor é isolada explicitamente em checkout limpo
quando o binário Linux está ausente. O descritor é restaurado mesmo após falha. Nenhum addon
foi excluído do repositório e os scripts de runtime continuam presentes. Esta modalidade
não valida a extensão nativa. Cache local já registrado é recusado, não reescrito.

A sonda `tools/verify_hud_row_geometry.gd` passou a ser obrigatória, junto à importação,
suíte completa e rota M2. O protocolo limita o trabalho em andamento do loop a duas PRs;
isso não altera, por si só, o agendamento externo do agente.

## Evidência executada

Workflow de integração: `34055494019`; job: `101546524748`.
Commit efetivamente testado: `d72182ba3c98b9bfcb79c470b76e9a8a37048bc6`.
Árvore efetivamente testada: `f34ede1804b8b95aced0dff693b56cf23e9cf897`.
Engine: `4.7.2.stable.official.ed1daf0bf`.

| Verificação | Resultado observado |
|---|---|
| Regressões Python do verificador | 12 testes, zero falhas; também executados localmente |
| Importação | saída 0, zero diagnósticos de erro da engine |
| Suíte GDScript | 262 testes, 12.719 asserções, zero falhas |
| Rota M2 | 179→358→493→780→825‰; `errors: []`; 12.750 pontos; nova rodada sem ticks de replay |
| Geometria do HUD | seis linhas de texto dentro das barras em quatro frames consecutivos |
| Sintaxe de `unclaimed_surface.sh` | `bash -n` aprovado |

A rota M2 usa uma fixture de boss imobilizado; não é playtest humano nem medida de dificuldade.
A suíte inclui, separadamente, testes de campanha e replays com boss ativo.

A primeira tentativa de integração encontrou um cabeçalho do ledger fora do formato exigido
pela guarda de documentação. A falha foi corrigida e a suíte inteira foi repetida; o resultado
acima é da tentativa corrigida. As evidências não misturam os dois candidatos.

Este registro é uma mudança somente documental posterior ao candidato medido. O merge da
#55 deve usar o CI do HEAD que contém também este registro, não apenas a medição acima.

## Limites que continuam abertos

Legibilidade e identidade visual, sensação de controle em aparelho físico, mixagem ouvida,
calibração da exposição ao risco e QA de distribuição continuam exigindo validação própria.
O campo de speed-up reservado e a compatibilidade de replay não foram alterados por este ajuste.
