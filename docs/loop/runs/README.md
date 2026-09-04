# Histórico do loop — um arquivo por execução

Cada execução do agente de melhoria contínua escreve **um arquivo novo** aqui e não toca nos
arquivos das outras. Nome: `<carimbo UTC ISO compacto>.md`, o mesmo carimbo do ramo
`ai/loop-<carimbo>` — ex.: `2026-09-04T195819Z.md` para `ai/loop-20260904T195819Z`.

## Por que arquivos em vez de uma tabela

O `docs/LOOP_LEDGER.md` tinha uma tabela de histórico onde toda execução apensava uma linha, no
mesmo ponto. Como todas ramificam do mesmo `main`, **todo par de PRs do loop colide ali** — a
medição do PR #14 encontrou 78 conflitos em 78 pares, e nenhum deles era desacordo real: eram
duas execuções escrevendo fatos diferentes na mesma linha.

Um arquivo por execução remove esse ponto de colisão. Duas execuções paralelas criam dois
arquivos distintos e mesclam sem conflito. O que continua compartilhado — e por isso continua
podendo conflitar — é o **backlog** do ledger, e isso é correto: duas execuções que mexem no
mesmo item do backlog *devem* se encontrar.

## O que escrever

Curto e verificável. Um leitor futuro precisa responder "isso já foi tentado?" sem abrir o PR:

- **Item** escolhido e de onde veio (backlog do ledger, ou fora dele com a justificativa).
- **O que mudou**, em quais arquivos.
- **Como foi verificado**: comandos rodados e o que a saída disse. O que *não* pôde ser
  verificado, dito explicitamente — a suíte headless é a única evidência que o loop tem.
- **O que ficou pendente**, para o backlog não perder o fio.

Não apague arquivos antigos. Um loop que esquece o que tentou repete o que falhou.

## Não há índice aqui, e isso é de propósito

A tentação óbvia é manter uma tabela-índice neste README. Ela reconstruiria exatamente o
problema: um ponto único onde toda execução apensa uma linha. O índice é a **listagem do
diretório** — os nomes são carimbos ISO, então `ls` já ordena cronologicamente:

```bash
ls docs/loop/runs/            # todas as execuções, da mais antiga para a mais recente
ls -r docs/loop/runs/ | head  # as últimas, primeiro
grep -rl "BoardView" docs/loop/runs/   # quais execuções já mexeram nisso
```

A regra geral: **arquivo por execução para fatos, seção compartilhada só para o que precisa ser
negociado.** O backlog do ledger precisa; o relato de uma execução, não.
