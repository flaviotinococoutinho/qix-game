# ADR-0009 — O contador de percentagem sobe em degraus, não salta

## Status

Aceita em 2026-09-04.

## Contexto

`GameSimulation.permille` muda de uma vez: uma captura confirmada some ao valor tudo o que foi
conquistado nesse tick. Até aqui o HUD copiava esse número para o rótulo e para a barra de
objetivo no mesmo tick, então a maior conquista da rota M2 — 49,3 % → 78,0 %, medida em
`tools/verify_m2_capture_route.gd` — aparecia como um rótulo diferente num frame.

O problema não é de exatidão, é de leitura: o jogador arriscou uma trilha longa e o retorno
desse risco passa em 16 ms. O tamanho da conquista fica invisível justamente no momento em que
ele é a recompensa. A mensagem `CAPTURA +N` já existe, mas ela é texto — não dá a sensação de
*quanto* do mapa mudou de dono.

`reference/volfied/06-gameplay.md §6.3` documenta como o original resolve isto: `hud_area_pct_step`
mantém um valor **mostrado** separado do valor **verdadeiro** e sobe-o passo a passo, fechando
primeiro as dezenas de %, depois as unidades, por fim os décimos. O comportamento a extrair é
esse — a escada de denominações, que faz uma conquista grande rolar mais tempo que uma pequena
sem que a subida fique proporcionalmente arrastada. Os números de atraso do original (§6.3: um
frame após um passo de dezena, nenhum nos demais) não servem aqui: lá o contador corria numa
pausa dedicada de fim de ronda e pagava pontos; aqui ele corre durante o jogo e a pontuação é do
domínio.

## Decisão

`QixGameHud` guarda `_shown_permille` e aproxima-o de `simulation.permille` a um degrau por
tick de sincronização, com a escada de denominações de §6.3 e atrasos calibrados para este jogo:

| Degrau | Incremento | Atraso seguinte |
|---|---|---|
| dezena de % | 100 permille | 3 ticks |
| unidade de % | 10 permille | 2 ticks |
| décimo de % | 1 permille | 1 tick |

O rótulo e a barra de objetivo lêem os dois o valor mostrado, para contarem a mesma história.

Só a **subida** é encenada. A primeira leitura e qualquer regressão do valor — rodada nova,
reinício de campanha — assentam de imediato: um contador a descer devagar mostraria território
que o jogador já não tem, o que é pior que não encenar nada.

## Consequências

O contador **atrasa** em relação ao domínio, nunca o antecipa nem o ultrapassa, o que mantém o
invariante 6. Nada disto entra em `game/`: o HUD conta os seus próprios ticks a partir de
snapshots já confirmados, como já fazia com `_flash_ticks`, então checksum e replay não são
tocados (invariante 8).

A calibragem custa tempo de leitura, e esse é o risco a vigiar. Medido em teste: a maior
conquista da rota M2 (28,7 pontos percentuais) fecha em **45 ticks — 0,75 s**; uma conquista
típica de 8 pontos fecha em 24 ticks; o campo inteiro, no pior caso, em menos de um segundo.
Acima disso a encenação deixaria de ser recompensa e viraria espera, por isso
`tests/unit/game_hud_test.gd` fixa o teto em 60 ticks e o piso em 20 — mudar os atrasos sem
mexer nesse teste é mudar a intenção sem dizer.

Um efeito de fronteira fica declarado: ao cruzar o alvo, o estado passa a `ÁREA SEGURA` enquanto
o contador ainda sobe. Isso é intencional — a subida é o fecho da rodada, não um atraso dela —
mas se a leitura vier a incomodar, o remédio é encurtar os atrasos, não voltar ao salto.
