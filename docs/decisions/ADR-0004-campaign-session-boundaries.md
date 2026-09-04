# ADR-0004 — Fronteiras de campanha, rodada e replay

**Estado:** aceita (G2, 2026-09-02)

## Contexto

`GameSimulation` já era determinística, mas representava uma única tentativa de uma
única rodada. Encadear fases diretamente dentro dela misturaria regras de território,
tempo de apresentação, troca de conteúdo e persistência de campanha no mesmo checksum.
Também tornaria o replay ambíguo: uma mudança visual ou uma transição animada poderia
alterar o domínio.

## Decisão

- `GameSimulation` continua dona de exatamente uma rodada e de seus ticks de gameplay.
- `GameSession` fica um nível acima e controla `ROUND_INTRO`, `PLAYING`, `ROUND_CLEAR`,
  `GAME_OVER` e `CAMPAIGN_COMPLETE`.
- Cada rodada recebe uma `GameSimulation` e um `ReplayLog` novos. Score e vidas passam
  explicitamente por `RoundStartState`; o registro arquivado preserva uma cópia desse
  estado inicial; board, shield, seed, tick e replay reiniciam.
- `CampaignDefinition` ordena recursos `RoundContent`. Cada entrada referencia regras,
  geometria/seed e apresentação autoráveis.
- Ticks de intro/clear e o comando de confirmação não são intents de gameplay e nunca
  entram no replay.
- O contrato de replay é validado antes da primeira mutação: versão das regras, seed,
  hash de regras/geometria e checksum inicial precisam coincidir.
- `RoundVisualDefinition` não participa de hash ou checksum. Trocar fundo, cores ou
  textos não invalida uma execução determinística.

## Consequências

- Uma rodada encerrada não continua avançando silenciosamente durante a transição.
- Os replays ficam pequenos, isolados e auditáveis por rodada.
- A campanha pode ser balanceada no Inspector ou por arquivos `.tres` sem alterar o
  código do domínio.
- Um replay de rodada posterior é reproduzido com o `RoundStartState` arquivado; a
  igualdade também é assegurada pelo checksum inicial.
- Transições e VFX podem evoluir independentemente, desde que permaneçam observadores.
