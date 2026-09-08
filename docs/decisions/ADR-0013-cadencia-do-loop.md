# ADR-0013 — A cadência do loop de agente

## Status

**Proposta em 2026-09-07.** Não aceita: a escolha entre as opções abaixo, e o ajuste do
agendamento que ela implica, são do mantenedor. O loop mede e propõe; não muda a própria
frequência.

Supera, quando aceita, o item P0 "A cadência do loop excede a cadência de revisão" do
`docs/LOOP_LEDGER.md`, medido quatro vezes (#31, #36, #40, #55) sem nunca chegar a documento.

## Contexto

### O que foi medido, em 2026-09-07T20:59Z, contra `main` em `34634d0`

`main` parou em `34634d0` às **2026-09-06T19:41Z**. Vinte e cinco horas depois, a fila tem
**29 PRs abertos** (#56–#84), todos em rascunho, abertos entre 2026-09-06T19:45Z e
2026-09-07T20:05Z. Nenhum mesclou. A produção do loop no período é, portanto, **29 PRs contra
zero merges** — não é fila lenta, é fila parada.

A superfície somada desses 29 PRs é de **11.941 linhas** (adições + remoções, excluindo
`addons/`, que é remoção em bloco e não se lê linha a linha). É mais do que uma sessão humana de
revisão consegue absorver, e cresce ~500 linhas por hora enquanto ninguém revisa.

### O achado novo: a fila não é só grande, é desproporcionada

As medições anteriores (#31, #36, #40) contaram **PRs**. Esta conta **o que cada PR alcança**,
classificando os 29 pela camada mais profunda que tocam:

| Alcance do PR | Quantos | Quais |
|---|---|---|
| **Runtime do jogo** (`game/`, `ui/`, `app/`, `content/`) | **6** | #61, #70, #75, #78, #79, #81 |
| Só guarda ou teste (`tests/`) | 9 | #60, #62, #67, #68, #69, #74, #77, #83, #84 |
| Mecanismo, documentação ou poda de `addons/` | 14 | #56, #57, #58, #59, #63, #64, #65, #66, #71, #72, #73, #76, #80, #82 |

**Seis** dos 29 PRs de um dia inteiro de loop mudam algo que o jogador poderia perceber. Os
outros 23 melhoram a defesa do projeto contra si mesmo — o que é trabalho legítimo, e é
exatamente o que o loop faz bem sozinho — mas significa que, mesmo se a fila drenasse hoje
inteira, **79 % do esforço represado não chega ao campo de jogo**.

A leitura honesta é que o gargalo tem dois braços, e as medições anteriores só viram um:

1. **Vazão.** O loop abre ~24 PRs/dia; a revisão é episódica e drena em rajadas (`main` avançou
   em três rajadas em 2026-09-06: 13:58Z, 19:37Z e 19:41Z, e em nenhuma outra hora do dia).
2. **Deriva de alvo.** Quanto mais tempo a fila fica parada, mais a superfície livre encolhe —
   medido em `docs/loop/runs/2026-09-06T170101Z.md`: todo `.gd` de apresentação em `main` já
   tinha dono. Uma execução que não encontra arquivo livre de apresentação escolhe um item de
   mecanismo, o que engrossa a fila sem aproximar o jogo. **O represamento realimenta-se.**

### O que já se tentou, e por que não bastou

- **Integrar a fila à mão** (#19, #55, #78). Funciona e é caro: o custo medido não é o `git
  merge` — é reconciliar `docs/LOOP_LEDGER.md`, que a união automática mente ao resolver. E
  produz um PR de integração que também precisa de um humano para mesclar, então move o gargalo
  sem removê-lo. Pior: um PR de integração envelhece na própria fila (#36 e #42 morreram assim;
  o #78 já está vermelho contra o #79, medido pelo #80).
- **Medir a fila melhor** (#30, #31, #40, #76, #80, mais `tools/loop/`). Necessário e
  insuficiente — e o ledger já lhe pôs um teto no passo 7 do protocolo, precisamente porque a
  medição começou a competir com o trabalho que ela deveria orientar.

## Opções

### A — Baixar a frequência do agendamento

De 1 execução/hora para 1 a cada 4 ou 6 horas (4 a 6 PRs/dia).

- **A favor:** mudança de uma linha, fora do repositório, reversível a qualquer momento. Reduz a
  fila de ~24/dia para ~5/dia, o que cabe numa sessão de revisão.
- **Contra:** trata a vazão e ignora a deriva de alvo. A proporção 6-em-29 fica igual, só menor.
  E não resolve o acoplamento semântico entre PRs abertos, que existe a partir de dois.

### B — Uma branch de longa duração, um PR por dia

O loop empilha um commit por execução em `ai/loop-diario-<AAAA-MM-DD>` e abre **um** PR ao fim do
dia. O relato por execução em `docs/loop/runs/` continua um arquivo por execução, então o
histórico não perde granularidade.

- **A favor:** 1 revisão/dia em vez de 29 filas paralelas. E, decisivo: as incompatibilidades
  semânticas passam a aparecer **na hora**, com a suíte a correr sobre a árvore acumulada. As
  duas que custaram caro — #25×#50 (`transition_progress()` removido por um e chamado por outro)
  e #78×#79 — não deram conflito de `git` nenhum e só apareceram na integração. Numa branch
  única, a segunda execução do dia já as encontra.
- **Contra:** a superfície de revisão diária é a mesma (~12 k linhas); o que muda é ser uma
  revisão em vez de 29. Um commit ruim viaja junto com os bons, e reverter um item exige
  `git revert` de um commit em vez de fechar um PR. Exige que o prompt do agendamento mude —
  mais do que uma linha.

### C — Automatizar a integração

Um job que mescla os PRs verdes do loop numa branch de integração e roda a suíte.

- **A favor:** tira do humano o trabalho que #19, #55 e #78 fizeram à mão.
- **Contra:** **não remove o gargalo, e a parte cara não automatiza.** O custo medido da
  integração é reconciliar o backlog do ledger à mão — está escrito nas notas de ambiente do
  ledger: "a união automática mente". Um robô que resolve `LOOP_LEDGER.md` por união produz um
  documento que passa nos testes e engana quem o lê. E o PR de integração continua a esperar uma
  mão humana.

## Recomendação do loop (não é a decisão)

**B**, com **A** como mitigação imediata se B exigir trabalho de agendamento que o mantenedor não
queira fazer agora. B é o único dos três que ataca os dois braços do gargalo: reduz a fila a 1
PR/dia *e* faz o loop trabalhar sobre a árvore que ele próprio construiu na hora anterior — o que
devolve superfície livre à execução seguinte, em vez de a consumir.

C não é recomendada como resposta ao gargalo. Se for feita, que seja depois de B, como conforto,
não como cura.

## Consequências, se B for aceita

- O passo 7 do protocolo do ledger (teto de meta-PR, limite de dois PRs em andamento) perde
  objeto: com um PR/dia, o limite é estrutural em vez de disciplinar. O passo deve ser reescrito
  no mesmo commit que aceitar esta ADR.
- Uma execução que encontre a árvore do dia vermelha **conserta antes de acrescentar**. Isso é
  novo: hoje cada execução ramifica de um `main` verde e nunca vê o estrago da anterior.
- `docs/loop/runs/` não muda. Continua um arquivo por execução, e continua a ser o índice.

## Como saber que funcionou

Trinta dias depois da aceitação, com a política em vigor:

- `main` avança em pelo menos metade dos dias (hoje: 3 rajadas num dia, zero nas 25 h seguintes).
- A fila fica em ≤ 3 PRs abertos do loop em qualquer amostra (hoje: 29).
- **E a métrica que esta ADR acrescenta:** pelo menos 1 em cada 3 execuções toca `game/`, `ui/`,
  `app/` ou `content/` (hoje: 6 em 29, ou 1 em 4,8).

A terceira é a que importa. As duas primeiras medem a saúde do mecanismo; só a terceira mede se o
mecanismo está a servir o jogo.

## O que esta ADR deliberadamente não decide

A frequência exata em A (4 h? 6 h?) e o formato do carimbo da branch em B. São detalhes de
operação, e escolhê-los aqui daria à proposta um ar de decisão tomada que ela não tem.
