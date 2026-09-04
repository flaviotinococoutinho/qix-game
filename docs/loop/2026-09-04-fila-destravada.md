# 2026-09-04 — a fila destrava: o patch prescrito pelo #17 foi aplicado e medido

**Execução:** 2026-09-04T22:01Z · **Base:** `origin/main` em `74c173a` · **PR tocado:** #8

## O que esta execução fez

Aplicou no #8 o patch que o #17 tinha **descrito em texto mas não aplicado**, e mediu que a
combinação antes vermelha fecha verde.

Não é um item novo do backlog. Todos os itens de P1, P2 e P3 já têm PR aberto (#1–#11, #15), mais
cinco de infraestrutura do loop (#12, #13, #14, #16, #17): 17 PRs abertos e **zero merges**. O
gargalo não é "o que fazer a seguir", é integração — e o único obstáculo técnico conhecido era uma
regressão de teste que ninguém tinha corrigido.

## O achado do #17, verificado de raiz

Não se aceitou a medição anterior como dada; reproduziu-se.

| Combinação | Resultado medido nesta execução |
|---|---|
| `main` (baseline) | 134 testes, 11489 asserções, **0 falhas** |
| #8 sozinho | 137 testes, 11501 asserções, **0 falhas** |
| #8 + #11 (antes do patch) | 145 testes, 11536 asserções, **2 falhas** |
| **#8 + patch + #11** | 145 testes, 11536 asserções, **0 falhas** |

A causa confirma-se exatamente como o #17 descreveu: `tests/unit/game_hud_test.gd` afirmava a
largura do trilho do objetivo em píxeis literais — `6`, `15`, `2` — que são
`roundf(OBJECTIVE_WIDTH × permille / target)` com o `OBJECTIVE_WIDTH := 50.0` vigente quando o #8
foi escrito. O #11 alarga deliberadamente para `86.0`, porque a percentagem é a leitura primária de
"quanto falta". Nenhum dos dois PRs está errado: o teste é que fixa uma constante de layout de que
não é dono.

## O que mudou no #8

Um ficheiro, 24 inserções, 4 remoções — `tests/unit/game_hud_test.gd`. As três asserções literais
passam a chamar `_assert_bar_agrees_with_number()`, que deriva a largura esperada do **texto do
rótulo** (o número que o jogador lê) e do `target_permille` da simulação, com tolerância de 1 px
para o arredondamento.

Nenhuma linha de `ui/game_hud.gd` foi tocada, e nenhuma linha de domínio: o patch é inteiramente de
teste.

## Por que derivar, e não só atualizar os números para 11/25/3

Atualizar os literais faria a suíte passar hoje e voltaria a quebrar no próximo ajuste de grade,
com a mesma mensagem inútil. A promessa que o teste existe para defender — *a barra conta a mesma
história que o número* — não depende da largura do trilho. Afirmá-la diretamente torna o teste
imune a decisões de layout que não lhe pertencem, sem perder poder de deteção.

**Controlo negativo (obrigatório: um invariante só existe se algo falha quando é violado).**
Desligar a barra do valor no HUD (`× 0.5` em `_objective_fill.size.x`) faz o teste falhar com:

```
no primeiro degrau: a barra mede 3 px, mas o número 10.0% pede 6 px
no valor confirmado: a barra mede 7 px, mas o número 23.4% pede 15 px
```

A mensagem passa a nomear o defeito. A versão anterior dizia apenas `esperado: 6, obtido: 11`, que
é precisamente o que fez esta regressão custar três execuções do loop a diagnosticar.

## Como foi verificado

Godot `4.7.2.stable.official.ed1daf0bf`, build Linux headless, baixado no sandbox. `--import`
corrido uma vez por checkout e novamente após cada troca de combinação.

```
tests/run_tests.gd          (#8 + patch + #11): 145 testes, 11536 asserções, 0 falhas, 4070 ms
verify_m2_capture_route.gd  (#8 + patch + #11): exit 0
                            permille 179 → 358 → 493 → 780 → 825, round_one_score 12750
```

**Não verificado, explicitamente:**

- `profile_board_view.gd` não foi executado — o patch não toca `BoardView` nem a máscara R8.
- `run_shipping_qa.sh` não foi executado (precisa de SDKs e assinatura; indisponível no sandbox).
- **A sequência dos 16 PRs não foi remedida.** Mediu-se o par que estava vermelho (#8 × #11); a
  medição do conjunto completo continua a ser a do #17.
- **O mérito estético de cada PR não foi julgado.** O jogo não pode ser jogado nem visto aqui.

## Risco

O patch é de teste, não de jogo: não toca domínio, apresentação, regras nem conteúdo. Nenhum
checksum foi alterado — o próprio `test_percent_counter_climbs...` continua a afirmar
`state_checksum()` inalterado (invariante 8 preservado).

O que o revisor deve olhar:

1. **Esta execução fez push numa branch que não abriu** (`ai/loop-20260904T120237Z`, do #8). Foi
   deliberado: o patch só faz sentido sobre o #8, e o #17 tinha-o prescrito explicitamente. O commit
   está isolado e é revertível.
2. **A tolerância de 1 px** absorve o arredondamento; não mascara um erro de escala, como o controlo
   negativo demonstra.
3. **A ordem de merge do #17 continua válida**, agora sem o obstáculo do #8 × #11.

## O que fica pendente

- **Drenar a fila.** 17 PRs abertos, zero merges, e nenhuma execução do loop pode mergear (limite
  rígido: nunca mesclar o próprio PR). Isto exige um humano. Enquanto não acontecer, cada execução
  nova ou duplica um item já coberto ou trabalha na fila em vez de no jogo.
- **#12, #14 e possivelmente #17** são PRs só de registo sobre a saturação; depois do #16 e desta
  medição, o conteúdo é histórico. Talvez valha fechá-los em vez de os mergear.
