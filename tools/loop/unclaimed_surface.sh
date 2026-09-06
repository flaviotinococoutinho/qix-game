#!/usr/bin/env bash
# Mede a *superfície livre*: quais arquivos de código de `main` nenhum PR aberto do loop toca.
#
# Por que existe: `merge_queue_report.sh` responde "quem colide com quem" depois de a execução
# ter escolhido o que fazer. Esta pergunta vem antes — "sobrou algo para eu mexer sem pisar num
# PR aberto?". Com a fila represada, a resposta pode ser *nada*, e é melhor descobrir isso em
# dois segundos do que depois de uma hora de trabalho que vai conflitar.
#
# O censo de posse (`docs/loop/2026-09-06-censo-de-posse.md`) mede posse por *item de backlog*.
# Este script mede posse por *arquivo*, que é a unidade em que o conflito realmente acontece:
# dois PRs podem atacar itens diferentes do backlog e ainda assim reescrever o mesmo `.gd`.
#
# Uso:
#   tools/loop/unclaimed_surface.sh            # resumo + lista da superfície livre
#   tools/loop/unclaimed_surface.sh --claimed  # também lista quem reivindica cada arquivo
#
# Só lê refs remotos: não altera `main` nem a árvore de trabalho.
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${PROJECT_ROOT}" || exit 1

BASE_REF="${QIX_LOOP_BASE_REF:-origin/main}"
BRANCH_GLOB="${QIX_LOOP_BRANCH_GLOB:-refs/remotes/origin/ai/loop-*}"

SHOW_CLAIMED=0
[ "${1:-}" = "--claimed" ] && SHOW_CLAIMED=1

# Camadas em que uma execução pode realmente trabalhar. `docs/` fica de fora de propósito: o
# ledger é editado por toda execução por contrato, e conflito nele é mecânico e esperado.
CODE_PATHS=(app game ui tools tests content)

fetch_branches() {
  git fetch --quiet origin "+refs/heads/ai/loop-*:refs/remotes/origin/ai/loop-*" 2>/dev/null || {
    echo "aviso: não consegui buscar refs/heads/ai/loop-*; usando os refs já locais" >&2
  }
  git fetch --quiet origin main 2>/dev/null || true
}

loop_branches() {
  git for-each-ref --format='%(refname:short)' "${BRANCH_GLOB}" | sort
}

# Arquivos de código que um ramo toca, relativo à base.
touched_code() {
  git diff --name-only "${BASE_REF}...$1" -- "${CODE_PATHS[@]}" 2>/dev/null
}

# Arquivos de código que existem hoje na base.
base_code() {
  git ls-tree -r --name-only "${BASE_REF}" -- "${CODE_PATHS[@]}" \
    | grep -E '\.(gd|gdshader|tres|tscn|sh)$'
}

fetch_branches

branches="$(loop_branches)"
if [ -z "${branches}" ]; then
  echo "nenhum ramo ai/loop-* encontrado em ${BRANCH_GLOB}" >&2
  exit 1
fi

claimed_file="$(mktemp)"
owners_file="$(mktemp)"
trap 'rm -f "${claimed_file}" "${owners_file}"' EXIT

# Ramos já mesclados continuam existindo como refs e produzem diff vazio contra a base. Contar
# só os que ainda contribuem evita anunciar uma fila maior do que a real.
contributing=0
for branch in ${branches}; do
  short="${branch#origin/}"
  touched=0
  while IFS= read -r path; do
    [ -n "${path}" ] || continue
    touched=1
    printf '%s\n' "${path}" >>"${claimed_file}"
    printf '%s\t%s\n' "${path}" "${short}" >>"${owners_file}"
  done < <(touched_code "${branch}")
  contributing=$((contributing + touched))
done

sort -u "${claimed_file}" -o "${claimed_file}"

base_list="$(mktemp)"
trap 'rm -f "${claimed_file}" "${owners_file}" "${base_list}"' EXIT
base_code | sort -u >"${base_list}"

total_base="$(wc -l <"${base_list}" | tr -d ' ')"
# Só conta como "reivindicado" o que existe na base: um arquivo *novo* trazido por um PR não
# reduz a superfície livre de quem trabalha sobre `main`.
claimed_in_base="$(comm -12 "${base_list}" "${claimed_file}" | wc -l | tr -d ' ')"
free_list="$(comm -23 "${base_list}" "${claimed_file}")"
free_count="$(printf '%s\n' "${free_list}" | grep -c . || true)"

echo "base:            ${BASE_REF} ($(git rev-parse --short "${BASE_REF}"))"
echo "ramos do loop:   $(printf '%s\n' "${branches}" | grep -c .) ($(printf '%s' "${contributing}") ainda à frente da base)"
echo "arquivos na base: ${total_base}"
echo "reivindicados:    ${claimed_in_base}"
echo "superfície livre: ${free_count}"
echo

# A contagem global engana: o que decide se uma execução tem trabalho é *em que camada* a
# superfície livre está. Apresentação livre significa que dá para mexer na experiência sem
# tocar em checksum; só domínio livre significa que toda mudança invalida replay.
# Os prefixos seguem a tabela de ownership de docs/PROJECT_CONTRACT.md.
layer_of() {
  case "$1" in
    app/*|ui/*|game/board/*|game/player/*|game/vfx/*|game/audio/*|game/enemies/*_view.gd) echo "apresentação" ;;
    game/simulation/*|game/rules/*|game/session/*|game/enemies/*)                          echo "domínio" ;;
    content/*)                                                                             echo "conteúdo" ;;
    tests/*)                                                                               echo "testes" ;;
    tools/*)                                                                               echo "ferramental" ;;
    *)                                                                                     echo "outro" ;;
  esac
}

echo "por camada (livres/total na base):"
for layer in "apresentação" "domínio" "conteúdo" "testes" "ferramental" "outro"; do
  total=0
  free=0
  while IFS= read -r path; do
    [ "$(layer_of "${path}")" = "${layer}" ] || continue
    total=$((total + 1))
    grep -qxF "${path}" "${claimed_file}" || free=$((free + 1))
  done <"${base_list}"
  [ "${total}" -gt 0 ] || continue
  marker=""
  [ "${free}" -eq 0 ] && marker="   <- congelada pela fila"
  printf '  %-14s %3d/%-3d%s\n' "${layer}" "${free}" "${total}" "${marker}"
done
echo

if [ "${free_count}" -eq 0 ]; then
  echo "SUPERFÍCIE LIVRE VAZIA — nenhuma mudança de código evita colidir com a fila."
  echo "Nesse estado a única ação que devolve o loop ao jogo é mesclar. Ver o item P0 do ledger."
  exit 0
fi

echo "superfície livre (arquivos que nenhum PR aberto toca):"
printf '%s\n' "${free_list}" | sed 's/^/  /'

if [ "${SHOW_CLAIMED}" -eq 1 ]; then
  echo
  echo "reivindicados, com dono:"
  while IFS= read -r path; do
    owners="$(awk -F'\t' -v p="${path}" '$1 == p { printf "%s ", $2 }' "${owners_file}")"
    printf '  %s\t%s\n' "${path}" "${owners}"
  done < <(comm -12 "${base_list}" "${claimed_file}")
fi
