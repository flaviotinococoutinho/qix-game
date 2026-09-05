#!/usr/bin/env bash
# Mede a saúde da fila de PRs abertos do loop: quem conflita com quem, e — mais importante —
# quais pares se juntam *sem* conflito textual mas mexem no mesmo arquivo de código.
#
# Por que existe: o agente de loop roda de hora em hora e abre um PR por execução, todos
# ramificados do mesmo `main`. Enquanto nada é mesclado, a fila cresce e o git só sabe avisar
# do conflito literal. A colisão que custa caro é a outra: dois PRs reescrevem o mesmo widget,
# o merge textual passa, e o teste de um deles quebra sem que nenhum dos dois PRs veja.
#
# Uso:
#   tools/loop/merge_queue_report.sh                 # matriz de conflitos + sobreposições
#   tools/loop/merge_queue_report.sh --verify 8 11   # junta os dois PRs e roda a suíte
#
# Requer `git` com `merge-tree --write-tree` (>= 2.38) e, para `--verify`, um binário Godot em
# $QIX_GODOT_BIN. Só lê refs remotos: não altera `main`, não altera a árvore de trabalho.
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${PROJECT_ROOT}" || exit 1

BASE_REF="${QIX_LOOP_BASE_REF:-origin/main}"
GODOT_BIN="${QIX_GODOT_BIN:-godot}"

# O ledger é editado por *toda* execução do loop, por contrato. Conflito nele é mecânico e
# esperado; separá-lo do resto é o que torna o relatório legível.
LEDGER_PATH="docs/LOOP_LEDGER.md"

fetch_pr_heads() {
  git fetch --quiet origin "refs/pull/*/head:refs/remotes/pr/*" 2>/dev/null || {
    echo "aviso: não consegui buscar refs/pull/*; usando os refs pr/* já locais" >&2
  }
}

pr_numbers() {
  git for-each-ref --format='%(refname:strip=3)' refs/remotes/pr/ | sort -n
}

# Arquivos que ambos os PRs tocam, ignorando docs. Duas mãos no mesmo .gd é a colisão que o
# merge textual esconde.
shared_code_files() {
  local a="$1" b="$2"
  comm -12 \
    <(git diff --name-only "${BASE_REF}...pr/${a}" | grep -E '\.(gd|tscn|tres|gdshader)$' | sort) \
    <(git diff --name-only "${BASE_REF}...pr/${b}" | grep -E '\.(gd|tscn|tres|gdshader)$' | sort)
}

# Constrói uma árvore com os PRs pedidos mesclados sobre a base, resolvendo o conflito do
# ledger pela base (ele não participa de nenhum teste). Ecoa o caminho do worktree.
build_worktree() {
  local dir="$1"; shift
  rm -rf "${dir}"
  git worktree remove --force "${dir}" 2>/dev/null
  git worktree add --quiet --detach "${dir}" "${BASE_REF}" || return 1
  local p
  for p in "$@"; do
    git -C "${dir}" merge --no-edit --quiet "pr/${p}" >/dev/null 2>&1
    if git -C "${dir}" status --porcelain | grep -q "^UU ${LEDGER_PATH}"; then
      git -C "${dir}" checkout --ours "${LEDGER_PATH}" >/dev/null 2>&1
      git -C "${dir}" add "${LEDGER_PATH}"
    fi
    if git -C "${dir}" status --porcelain | grep -q '^UU '; then
      echo "  conflito real (fora do ledger) ao juntar pr/${p}:" >&2
      git -C "${dir}" status --porcelain | grep '^UU ' | sed 's/^/    /' >&2
      return 1
    fi
    git -C "${dir}" commit --no-edit --quiet >/dev/null 2>&1
  done
}

cmd_verify() {
  local dir="/tmp/qix-merge-queue-verify"
  echo "== Verificação: PRs $* juntos sobre ${BASE_REF} =="
  build_worktree "${dir}" "$@" || { echo "não foi possível montar a árvore combinada"; return 1; }
  if ! command -v "${GODOT_BIN}" >/dev/null 2>&1 && [ ! -x "${GODOT_BIN}" ]; then
    echo "Godot não encontrado em '${GODOT_BIN}'; defina QIX_GODOT_BIN. Árvore montada em ${dir}."
    return 2
  fi
  "${GODOT_BIN}" --headless --path "${dir}" --import >/dev/null 2>&1
  "${GODOT_BIN}" --headless --audio-driver Dummy --path "${dir}" \
    --script res://tests/run_tests.gd 2>&1 | grep -E '^(ok|FAIL)|testes,' | grep -vE '^ok'
}

cmd_report() {
  fetch_pr_heads
  local prs; prs=$(pr_numbers)
  if [ -z "${prs}" ]; then echo "nenhum PR aberto encontrado em refs/remotes/pr/"; return 0; fi

  echo "== Fila de merge sobre ${BASE_REF} =="
  echo "PRs na fila: $(echo "${prs}" | tr '\n' ' ')"
  echo
  echo "-- Conflitos que NÃO são o ledger (exigem decisão humana) --"
  local real=0 a b out rest
  for a in ${prs}; do for b in ${prs}; do
    [ "${a}" -lt "${b}" ] || continue
    out=$(git merge-tree --write-tree --name-only --merge-base="${BASE_REF}" "pr/${a}" "pr/${b}" 2>&1) && continue
    rest=$(echo "${out}" | grep '^CONFLICT' | grep -v "${LEDGER_PATH}")
    if [ -n "${rest}" ]; then
      echo "  #${a} x #${b}: $(echo "${rest}" | sed 's/CONFLICT ([a-z]*): Merge conflict in //' | tr '\n' ' ')"
      real=$((real + 1))
    fi
  done; done
  [ "${real}" -eq 0 ] && echo "  (nenhum)"

  echo
  echo "-- Sobreposição silenciosa: mesmo arquivo de código, sem conflito textual --"
  echo "   Estes são os pares a verificar com --verify: o git aceita o merge, o teste é que decide."
  local silent=0 shared
  for a in ${prs}; do for b in ${prs}; do
    [ "${a}" -lt "${b}" ] || continue
    shared=$(shared_code_files "${a}" "${b}")
    if [ -n "${shared}" ]; then
      echo "  #${a} x #${b}: $(echo "${shared}" | tr '\n' ' ')"
      silent=$((silent + 1))
    fi
  done; done
  [ "${silent}" -eq 0 ] && echo "  (nenhuma)"

  echo
  echo "-- Conflito no ledger (mecânico: toda execução escreve nele) --"
  local ledger=0
  for a in ${prs}; do for b in ${prs}; do
    [ "${a}" -lt "${b}" ] || continue
    git merge-tree --write-tree --name-only --merge-base="${BASE_REF}" "pr/${a}" "pr/${b}" >/dev/null 2>&1 \
      || ledger=$((ledger + 1))
  done; done
  echo "  ${ledger} pares conflitam (de $(echo "${prs}" | wc -l | tr -d ' ') PRs na fila)"
}

case "${1:-}" in
  --verify) shift; cmd_verify "$@" ;;
  ""|--report) cmd_report ;;
  *) echo "uso: $0 [--report] | --verify <pr> <pr> [...]" >&2; exit 64 ;;
esac
