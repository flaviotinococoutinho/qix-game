#!/usr/bin/env bash
# Responde à única pergunta que a fila precisa: **em que ordem dá para mesclar**, e onde a
# corrente arrebenta.
#
# Por que não bastava `merge_queue_report.sh`: aquele relatório é *par a par* sobre `main`. Cada
# PR do loop nasce do mesmo `main` e, sozinho, mescla limpo — a matriz de pares fica verde e a
# fila parece saudável. Mas ninguém mescla um PR sozinho: mescla-se um depois do outro, e o
# segundo já encontra o ledger reescrito pelo primeiro. Medido em 2026-09-05 com 11 PRs abertos:
# 11 de 11 limpos contra `main`, e apenas 3 sobrevivem à sequência.
#
# Este script simula a fila cumulativamente, num worktree descartável, e diz onde parar.
#
# Uso:
#   tools/loop/merge_order_report.sh              # ordem cronológica (a que um humano tentaria)
#   tools/loop/merge_order_report.sh 20 21 28     # testa uma ordem proposta
#
# Só lê refs remotos e escreve num worktree temporário: não altera `main` nem a árvore de
# trabalho. Não resolve nada — resolver o ledger por união automática é decisão fechada contra
# (ver `docs/LOOP_LEDGER.md`, "Ao resolver conflito de documentação").
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${PROJECT_ROOT}" || exit 1

BASE_REF="${QIX_LOOP_BASE_REF:-origin/main}"
WORKTREE="${QIX_LOOP_ORDER_WORKTREE:-/tmp/qix-merge-order}"

git fetch --quiet origin "refs/pull/*/head:refs/remotes/pr/*" 2>/dev/null \
  || echo "aviso: não consegui buscar refs/pull/*; usando os refs pr/* já locais" >&2

# `refs/pull/*/head` guarda **todo** PR que já existiu, mesclado ou não. Um PR já mesclado é
# ancestral da base e mescla de novo como no-op, inflando a fila com trabalho que já acabou —
# foi assim que um relatório anterior anunciou 29 PRs onde havia 10. Ancestralidade responde
# isso sem depender do `gh`: se a base já contém aquele head, ele não está na fila.
in_queue() { ! git merge-base --is-ancestor "pr/$1" "${BASE_REF}" 2>/dev/null; }

if [ "$#" -gt 0 ]; then
  PRS="$*"
else
  # Cronológica: o número do PR cresce com o tempo, e é nessa ordem que a fila se formou.
  PRS=""
  for pr in $(git for-each-ref --format='%(refname:strip=3)' refs/remotes/pr/ | sort -n); do
    in_queue "${pr}" && PRS="${PRS}${pr} "
  done
fi
[ -n "${PRS// /}" ] || { echo "nenhum PR na fila"; exit 0; }

rm -rf "${WORKTREE}"
git worktree remove --force "${WORKTREE}" 2>/dev/null
git worktree prune
git worktree add --quiet --detach "${WORKTREE}" "${BASE_REF}" || exit 1

echo "== Ordem de merge sobre ${BASE_REF} =="
echo "Fila: ${PRS}"
echo

clean=0
blocked=""
for pr in ${PRS}; do
  if git -C "${WORKTREE}" merge --no-edit --quiet "pr/${pr}" >/dev/null 2>&1; then
    echo "  OK        #${pr}"
    clean=$((clean + 1))
  else
    files=$(git -C "${WORKTREE}" diff --name-only --diff-filter=U | tr '\n' ' ')
    echo "  CONFLITO  #${pr}  em: ${files}"
    blocked="${blocked} ${pr}"
    git -C "${WORKTREE}" merge --abort 2>/dev/null
  fi
done

echo
echo "-- Veredito --"
echo "  ${clean} PR(s) entram em sequência sem trabalho manual."
if [ -n "${blocked}" ]; then
  echo "  Precisam de resolução à mão, nesta ordem:${blocked}"
  echo "  O ledger reconcilia-se à mão, por decisão fechada. Um merge por vez, lendo o backlog."
else
  echo "  A fila inteira entra limpa."
fi

git worktree remove --force "${WORKTREE}" 2>/dev/null
git worktree prune
