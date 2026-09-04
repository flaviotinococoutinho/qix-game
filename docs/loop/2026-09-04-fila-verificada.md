# A fila de 16 PRs foi medida de ponta a ponta — e fecha verde com um patch de 4 linhas

**Verificado em:** 2026-09-04T21:00Z, contra `origin/main` em `74c173a`
**Executado com:** Godot 4.7.2.stable.official.ed1daf0bf (build Linux headless, baixado no sandbox)

## O achado

A fila do loop tem **16 PRs abertos e zero merges**. Execuções anteriores registaram a saturação
(#12, #14) e apontaram uma "regressão #8 × #11", mas nenhuma tinha medido o que acontece quando os
PRs são efetivamente combinados. Esta execução mediu.

O resultado é melhor do que o registo sugeria:

1. **Os 16 PRs entram limpos em `main`, individualmente.** Nenhum conflita com a base.
2. **Combinados, conflitam apenas em documentação** — nunca em código. Todos os 16 tocam
   `docs/LOOP_LEDGER.md`; oito tocam `docs/TEST_MATRIX.md`; seis, `docs/PROJECT_CONTRACT.md`.
   São conflitos de união (cada PR acrescenta a sua linha), não decisões em disputa.
3. **A única incompatibilidade real de código é #8 × #11, e é no teste, não no jogo.**
4. **Com um patch de 4 linhas nesse teste, os 16 PRs passam juntos**: 174 testes, 11837
   asserções, 0 falhas; rota M2 chegando a 825 permille com `errors: []`.

Ou seja: a fila não está bloqueada por desacordo de design. Está bloqueada por não ter sido
integrada.

## Medições

Baseline em `main` (antes de qualquer merge):

```
134 testes, 11489 asserções, 0 falhas, 4359 ms
```

Isolamento da regressão, cada combinação executada de raiz a partir de `main`:

| Combinação | Resultado |
|---|---|
| só #8 | 137 testes, 11501 asserções, **0 falhas** |
| só #11 | 142 testes, 11524 asserções, **0 falhas** |
| #8 + #11 | 145 testes, 11536 asserções, **2 falhas** |
| #8 + #9 + #11 | 151 testes, 11599 asserções, **2 falhas** (as mesmas — #9 é inocente) |

As duas falhas são sempre:

```
FAIL  game_hud_test.gd::test_percent_counter_climbs_by_denomination_instead_of_snapping
FAIL  game_hud_test.gd::test_percent_counter_snaps_back_when_progress_regresses
```

## Causa exata

`tests/unit/game_hud_test.gd` (introduzido pelo #8) afirma a largura do trilho do objetivo em
**pixels literais** — `6`, `15` e `2`. Esses números não são arbitrários: são
`round(OBJECTIVE_WIDTH × permille / 800)` com o `OBJECTIVE_WIDTH := 50.0` que valia quando o #8
foi escrito.

O #11 alarga o trilho para `OBJECTIVE_WIDTH := 86.0` — deliberadamente, porque a percentagem é a
leitura primária de "quanto falta" e o trilho dela passa a ser o mais largo da banda superior.
Aritmética confirmada:

| `OBJECTIVE_WIDTH` | 100 permille | 234 permille |
|---|---|---|
| 50.0 (o que o #8 assumiu) | 6 | 15 |
| 86.0 (o que o #11 estabelece) | 11 | 25 |

**Nenhum dos dois PRs está errado.** O contador em degraus do #8 e a grade verificável do #11 são
mudanças compatíveis e ambas desejáveis. O que está errado é um teste que fixa um número de layout
que não lhe pertence: qualquer futuro ajuste de grade o quebra outra vez, e por uma razão que não
aparece na mensagem de falha.

## O patch

Derivar a largura da constante em vez de a copiar. Aplicável a `tests/unit/game_hud_test.gd`
**depois** de o #8 entrar (o ficheiro não existe em `main`):

```gdscript
## Largura esperada do trilho do objetivo para uma percentagem mostrada.
## Deriva da constante de layout em vez de fixar pixels: a largura do trilho pertence ao HUD,
## não a este teste, e um número copiado aqui quebra em silêncio quando a grade muda.
func _objective_width_for(shown_permille: int, target_permille: int) -> int:
	var ratio := clampf(float(shown_permille) / float(target_permille), 0.0, 1.0)
	return int(roundf(QixGameHud.OBJECTIVE_WIDTH * ratio))
```

e as três asserções passam a:

```gdscript
eq(int((hud.get_node("ObjectiveFill") as ColorRect).size.x), _objective_width_for(100, 800), ...)
eq(int((hud.get_node("ObjectiveFill") as ColorRect).size.x), _objective_width_for(234, 800))
eq(int((hud.get_node("ObjectiveFill") as ColorRect).size.x), _objective_width_for(30, 800))
```

O teste continua a verificar exatamente o que interessa — que a barra conta a mesma história que o
número — e deixa de verificar uma constante de que não é dono.

## Ordem de merge verificada

Esta sequência foi executada integralmente e termina verde. Os conflitos de documentação
resolvem-se por união (manter os dois lados); nenhum pede decisão.

```
#16  →  #13  →  #1  →  #2  →  #4  →  #3  →  #5  →  #6
     →  #7  →  #8  →  #9  →  #10  →  #11  →  #15  →  #12  →  #14
```

A razão da cabeça da ordem: **#16 primeiro** porque transforma o histórico do ledger num ficheiro
por execução, que é o que elimina o ponto único de conflito dos 16 PRs; **#13 a seguir** porque
instala o portão headless no CI, e a partir daí cada merge seguinte é verificado sozinho em vez de
depender desta medição manual. Os restantes seguem por prioridade do backlog.

Aplicar o patch acima junto do #8 (ou logo após), senão a fila trava no #11.

Resultado final da sequência completa com o patch:

```
174 testes, 11837 asserções, 0 falhas, 5016 ms
verify_m2_capture_route: exit 0, "errors": [], permille chegando a 825
```

## Ressalvas honestas

- **Isto não é uma revisão de mérito.** Foi medido que os 16 PRs são *tecnicamente* combináveis e
  que a suíte passa. Não foi julgado se cada mudança estética é a certa para o jogo — isso continua
  a pedir olhos humanos, e as três rodadas não podem ser jogadas neste sandbox.
- **#12 e #14 ficam provavelmente obsoletos.** São PRs só de ledger que registam a saturação da
  fila; depois de #16 e desta medição, o conteúdo deles é histórico. Vale fechá-los em vez de os
  mergear, se o revisor concordar.
- **O `libfennara.linux.editor.x86_64.so` não existe no sandbox** (binário não versionado, por
  regra do projeto). Os erros de GDExtension no log são pré-existentes, aparecem também em `main`,
  e não afetam nenhum teste.
- **`profile_board_view.gd` não foi executado.** Nenhuma das mudanças medidas toca `BoardView` nem
  a máscara R8; o custo por frame do HUD não é o que esse perfil mede.
- **Nenhum checksum de domínio mudou.** As duas falhas eram de layout de apresentação, e o
  `test_percent_counter_climbs...` do #8 já afirma `state_checksum()` inalterado — invariante 8
  preservado ao longo de toda a sequência.
