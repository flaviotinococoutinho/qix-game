# ADR-0006 — Entrada e feedback não atravessam a fronteira determinística

## Status

Aceita em 2026-09-03.

## Contexto

O shipping pass acrescenta stick analógico, botões, multitouch, áudio e háptica. Esses sistemas
dependem de dispositivo, relógio e APIs de plataforma; gravá-los na simulação quebraria replay e
testes determinísticos.

## Decisão

- `GameInputAdapter` é a única tradução de teclado/InputMap, gamepad e touch para
  `MoveIntent` cardinal.
- `QixTouchControls` expõe estado e eventos de UI, sem chamar `GameSimulation`.
- `QixFeedbackHub` recebe a sessão e `GameEvent` já confirmados e apenas aciona áudio/háptica.
- Throttle, cache, volume, pausa, intensidade, suporte do hardware e tempo de apresentação não
  participam do RNG, bytes canônicos, checksum ou replay.

## Consequências

Dispositivos diferentes podem compartilhar replay e testes. Qualidade sonora, ergonomia e
suporte háptico ainda exigem QA físico porque a fronteira permite testar contratos, não a
percepção nem o driver do aparelho.
