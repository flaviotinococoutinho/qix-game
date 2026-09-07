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
#   tools/loop/merge_queue_report.sh                 # matriz de conflitos + posse + sobreposições
#   tools/loop/merge_queue_report.sh --claims        # só o mapa de posse (a pergunta do passo 2)
#   tools/loop/merge_queue_report.sh --order         # em que ordem a fila entra, cumulativamente
#   tools/loop/merge_queue_report.sh --order 20 21   # testa uma ordem proposta
#   tools/loop/merge_queue_report.sh --verify 8 11   # junta os dois PRs e roda a suíte
#
# Requer `git` com `merge-tree --write-tree` (>= 2.38) e, para `--verify`, um binário Godot em
# $QIX_GODOT_BIN. Só lê refs remotos: não altera `main`, não altera a árvore de trabalho.
#
# `--order` era `tools/loop/merge_order_report.sh`, arquivo à parte desde o #31. O próprio #31
# registrou por que nasceu separado e o que devia acontecer depois: "arquivo novo em vez de
# `--order` dentro de `merge_queue_report.sh` porque o #30 está mexendo" nele, e "fundir depois
# do #30" (`docs/loop/runs/2026-09-05T150119Z.md`). O #30 mesclou; os dois scripts passaram a
# duplicar a enumeração da fila e a divergir na contagem. A fusão é essa dívida sendo paga.
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${PROJECT_ROOT}" || exit 1

BASE_REF="${QIX_LOOP_BASE_REF:-origin/main}"
GODOT_BIN="${QIX_GODOT_BIN:-godot}"
ORDER_WORKTREE="${QIX_LOOP_ORDER_WORKTREE:-/tmp/qix-merge-order}"

# O ledger é editado por *toda* execução do loop, por contrato. Conflito nele é mecânico e
# esperado; separá-lo do resto é o que torna o relatório legível.
LEDGER_PATH="docs/LOOP_LEDGER.md"

fetch_pr_heads() {
  git fetch --quiet origin "refs/pull/*/head:refs/remotes/pr/*" 2>/dev/null || {
    echo "aviso: não consegui buscar refs/pull/*; usando os refs pr/* já locais" >&2
  }
}

# Um ref em `refs/remotes/pr/` nunca desaparece: `git fetch refs/pull/*` só acrescenta. Depois que
# o #19 levou dezenove PRs para `main`, este relatório passou a anunciar "29 PRs na fila" e 364
# pares em conflito — quase todos entre PRs que já não existem. Um relatório que exagera a fila em
# 19 unidades é pior que nenhum: a execução que o lê conclui que tudo colide e desiste de escolher.
# Um PR mesclado é, por construção, ancestral da base; um PR aberto não é.
#
# Limite conhecido: um PR *fechado sem mesclar* também não é ancestral, e passa por aberto. Não
# houve nenhum até hoje neste repositório; quando houver, o ref sobra no relatório e a correção é
# apagá-lo (`git update-ref -d refs/remotes/pr/<n>`), não afrouxar o teste.
pr_numbers() {
  local n
  for n in $(all_pr_refs); do
    git merge-base --is-ancestor "pr/${n}" "${BASE_REF}" 2>/dev/null && continue
    echo "${n}"
  done
}

all_pr_refs() {
  git for-each-ref --format='%(refname:strip=3)' refs/remotes/pr/ | sort -n
}

# Arquivos cuja posse importa para quem vai escolher um item. Fora: o ledger (toda execução
# escreve nele, por contrato) e os relatos por execução (arquivo novo por run, nunca disputado).
claimable_files() {
  git diff --name-only "${BASE_REF}...pr/${1}" \
    | grep -v "^${LEDGER_PATH}\$" \
    | grep -v '^docs/loop/runs/'
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

# O mapa de posse responde à pergunta que o passo 2 do protocolo do ledger faz antes de escolher
# um item: "o arquivo que eu preciso tocar já tem dono na fila?". Sem ele a resposta custa um
# `git diff` por PR aberto, à mão — e a execução que não paga esse custo escolhe um item que já
# está em voo. A matriz de conflitos não substitui isto: ela só cruza PR com PR, e o que a
# execução tem em mãos é um item de backlog, não um PR.
print_claims() {
  local prs="$1" p
  echo "-- Posse de arquivos: o que a fila já reivindica --"
  echo "   Item de backlog cujo arquivo aparece aqui **não está livre**, mesmo com o checkbox vazio."
  if [ -z "${prs}" ]; then echo "  (fila vazia: nenhum arquivo reivindicado)"; return 0; fi
  for p in ${prs}; do
    claimable_files "${p}" | sed "s|\$| ${p}|"
  done | sort | awk '
    # Uma raiz inteira reivindicada por um só PR (a poda de um vendor, por exemplo) rende dezenas
    # de linhas que respondem todas à mesma pergunta. Acima de COLAPSO arquivos vira uma linha; o
    # leitor continua sabendo que qualquer arquivo sob aquela raiz tem dono. O limiar é alto de
    # propósito: `tests/` recebe arquivo novo a cada execução e não pode ser colapsada.
    function flush(   ) { if (prev != "") { printf "  %s  <- %s\n", prev, acc; prev = "" } }
    BEGIN { COLAPSO = 8 }
    { f[NR] = $1; o[NR] = $2
      seg = $1
      if (index(seg, "/") > 0) sub(/\/.*/, "", seg); else seg = ""
      s[NR] = seg
      if (seg != "") cnt[seg " " $2]++ }
    END {
      for (i = 1; i <= NR; i++) {
        key = s[i] " " o[i]
        if (s[i] != "" && cnt[key] >= COLAPSO) {
          if (!(key in seen)) {
            seen[key] = 1; flush()
            printf "  %s/…  <- #%s  (%d arquivos)\n", s[i], o[i], cnt[key]
          }
          continue
        }
        if (f[i] != prev) { flush(); prev = f[i]; acc = "#" o[i] }
        else acc = acc " #" o[i]
      }
      flush()
    }'
}

cmd_claims() {
  fetch_pr_heads
  print_claims "$(pr_numbers)"
}

# A pergunta que a matriz par-a-par não responde: **em que ordem dá para mesclar**, e onde a
# corrente arrebenta. Cada PR do loop nasce do mesmo `main` e, sozinho, mescla limpo — a matriz
# de `cmd_report` fica verde e a fila parece saudável. Mas ninguém mescla um PR sozinho:
# mescla-se um depois do outro, e o segundo já encontra o ledger reescrito pelo primeiro. Medido
# em 2026-09-05 com 11 PRs abertos: 11 de 11 limpos contra a base, e apenas 3 sobrevivem à
# sequência. Origem: #31.
#
# Diferença deliberada para `build_worktree`, e a razão de as duas funções coexistirem: aqui o
# conflito do ledger **não** é resolvido. `--verify` pergunta "o código combinado passa nos
# testes?" e descarta o ledger porque ele não entra em teste nenhum; `--order` pergunta "onde a
# corrente arrebenta para quem vai mesclar à mão?", e o ledger é justamente o elo que arrebenta.
# Resolver aqui apagaria o achado. Não resolve nada, por isso: reconciliar o ledger por união
# automática é decisão fechada contra (`docs/LOOP_LEDGER.md`, "Ao resolver conflito de
# documentação").
cmd_order() {
  fetch_pr_heads
  local prs
  # Com argumentos, testa a ordem proposta **verbatim** — inclusive um PR fora da fila, que é
  # como se pergunta "e se eu mesclasse este antes?". Sem argumentos, ordem cronológica: o
  # número do PR cresce com o tempo, e é nessa ordem que a fila se formou.
  if [ "$#" -gt 0 ]; then prs="$*"; else prs="$(pr_numbers)"; fi
  [ -n "${prs// /}" ] || { echo "nenhum PR na fila"; return 0; }

  rm -rf "${ORDER_WORKTREE}"
  git worktree remove --force "${ORDER_WORKTREE}" 2>/dev/null
  git worktree prune
  git worktree add --quiet --detach "${ORDER_WORKTREE}" "${BASE_REF}" || return 1

  echo "== Ordem de merge sobre ${BASE_REF} =="
  echo "Fila: $(echo "${prs}" | tr '\n' ' ')"
  echo

  local clean=0 blocked="" pr files
  for pr in ${prs}; do
    if git -C "${ORDER_WORKTREE}" merge --no-edit --quiet "pr/${pr}" >/dev/null 2>&1; then
      echo "  OK        #${pr}"
      clean=$((clean + 1))
    else
      files=$(git -C "${ORDER_WORKTREE}" diff --name-only --diff-filter=U | tr '\n' ' ')
      echo "  CONFLITO  #${pr}  em: ${files}"
      blocked="${blocked} ${pr}"
      git -C "${ORDER_WORKTREE}" merge --abort 2>/dev/null
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

  git worktree remove --force "${ORDER_WORKTREE}" 2>/dev/null
  git worktree prune
}

cmd_report() {
  fetch_pr_heads
  local prs; prs=$(pr_numbers)
  local merged; merged=$(( $(all_pr_refs | wc -l) - $(echo "${prs}" | grep -c . ) ))
  if [ -z "${prs}" ]; then echo "nenhum PR aberto encontrado em refs/remotes/pr/"; return 0; fi

  echo "== Fila de merge sobre ${BASE_REF} =="
  echo "PRs na fila: $(echo "${prs}" | tr '\n' ' ')"
  echo "(${merged} refs em refs/remotes/pr/ já são ancestrais de ${BASE_REF}: mesclados, fora da conta)"
  echo
  print_claims "${prs}"
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
  --claims) cmd_claims ;;
  --order)  shift; cmd_order "$@" ;;
  ""|--report) cmd_report ;;
  *) echo "uso: $0 [--report] | --claims | --order [<pr> ...] | --verify <pr> <pr> [...]" >&2
     exit 64 ;;
esac
