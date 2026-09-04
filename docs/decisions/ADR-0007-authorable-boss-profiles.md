# ADR-0007 — Comportamentos do boss são Resources determinísticos

## Status

Aceita em 2026-09-03.

## Contexto

Velocidade/cadência isoladas não dão identidade suficiente às rodadas. A campanha precisa de
variedade autorável sem introduzir floats, IA dependente de frame ou divergência de replay.

## Decisão

Cada `GameRules` referencia um `BossBehaviorProfile` externo com um padrão `WANDER`, `PURSUIT`
ou `SWEEP`, parâmetros inteiros de jitter/varredura e pulso periódico de velocidade. O
`BossBehaviorController` decide direção e velocidade usando tick, seed/RNG determinístico,
octantes inteiros e reflexão canônica. O perfil serializado integra os bytes canônicos das
regras.

## Consequências

Design pode variar cada rodada no Inspector e reusar perfis. Alterar um perfil invalida replay
incompatível antes de mutar estado. Novos padrões devem manter decisão inteira/seedada, limites
de velocidade por substep, testes de interior livre e uma rota balanceada legal.
