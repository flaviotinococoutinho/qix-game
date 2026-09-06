"""One-shot, SHA-pinned integration; removed from the candidate before publication."""
from pathlib import Path
import subprocess

PRS = [(52, '7ce16b23351a46e7f491c2dcf159b558bb7ad5a4'),
       (53, '35245b60e62d2974daf08b5de5d9864e19f08058'),
       (54, '9e44e000a9b24058f5dbe68ebb64985a0c8bdb20')]


def git(*args, check=True):
    return subprocess.run(['git', *args], text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, check=check)


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f'expected exactly one reconciliation anchor: {old!r}')
    return text.replace(old, new, 1)


ledger_path = Path('docs/LOOP_LEDGER.md')
ledger = ledger_path.read_text()
for number, sha in PRS:
    git('fetch', 'origin', f'refs/pull/{number}/head')
    actual = git('rev-parse', 'FETCH_HEAD').stdout.strip()
    if actual != sha:
        raise RuntimeError(f'PR #{number} moved; refusing to integrate an unreviewed head: {actual}')
    result = git('merge', '--no-ff', '--no-commit', sha, check=False)
    print(result.stdout, flush=True)
    conflicts = set(git('diff', '--name-only', '--diff-filter=U').stdout.splitlines())
    if result.returncode not in (0, 1) or conflicts - {'docs/LOOP_LEDGER.md'}:
        raise RuntimeError(f'unexpected merge conflict in PR #{number}: {conflicts}')
    if result.returncode and not conflicts:
        raise RuntimeError(f'merge #{number} failed without a resolvable ledger conflict')
    # Deliberate resolution, not union: keep the already-integrated backlog, then apply
    # the three new PRs' policy/geometry changes once below. Their run records stay intact.
    ledger_path.write_text(ledger)
    git('add', 'docs/LOOP_LEDGER.md')
    git('commit', '-m', f'Merge PR #{number}; reconcile shared ledger in integration follow-up')

start = ledger.index('2. **Liste os PRs abertos')
end = ledger.index('3. **Escolha exatamente', start)
ledger = ledger[:start] + '''2. **Liste os PRs abertos do loop antes de escolher.** Um item com PR aberto não está livre.
   Consulte o estado atual no GitHub. Use `tools/loop/unclaimed_surface.sh` antes de escolher
   (heurística por refs e camada) e `tools/loop/merge_queue_report.sh` depois de escolher.
   Refs de branches não provam, sozinhos, que os respectivos PRs continuam abertos.
''' + ledger[end:]
needle = '   seção existe para impedir que o loop oscile entre duas opções para sempre.\n'
ledger = replace_once(ledger, needle, needle + '''7. **Meta-PR tem teto.** Um PR sobre a fila só é legítimo se trouxer uma medição ainda ausente
   nos meta-PRs abertos e nomear quais supera. Sem evidência nova, registre o achado no relato
   da execução, sem abrir outro PR redundante. Origem: #53 e o censo de posse de 2026-09-06.
   O limite operacional é dois PRs do loop em andamento; com o limite atingido, priorize revisão
   e correção dos existentes, não a geração de uma nova mudança sobre os mesmos arquivos.
''')
ledger = ledger.replace('- [ ] **`BOUNDARY`×`TRAIL`', '- [ ] **[requer sessão humana] `BOUNDARY`×`TRAIL`')
ledger = ledger.replace('- [ ] **Calibrar a curva de exposição', '- [ ] **[requer sessão humana] Calibrar a curva de exposição')
marker = '**A geometria do HUD depende da ordem de construção.**'
if marker in ledger:
    start = ledger.rfind('\n- [', 0, ledger.index(marker)) + 1
    candidates = [p for p in (ledger.find('\n- [', start + 1), ledger.find('\n## ', start + 1)) if p >= 0]
    if not candidates:
        raise RuntimeError('cannot delimit the HUD geometry backlog item')
    end = min(candidates)
    ledger = ledger[:start] + '''- [~] **Geometria real do HUD — #52 integrado no candidato de merge.**
      `tools/verify_hud_row_geometry.gd` mede a construção durante frames, não só as constantes
      no `_initialize()` do runner. O teste horizontal e os comentários corrigidos também
      foram preservados. A sonda passou a fazer parte do CI. Aprovação estética continua humana.
''' + ledger[end:]
header_end = ledger.index('\n\nUm agente')
ledger = '''# LOOP_LEDGER — memória entre execuções do agente

> **Verificado em** 2026-09-06 · base integrada `c4cedb1` (#51), mais #52–#54
> **Alcance:** reconciliação de código e documentação a pedido explícito do mantenedor.
> As evidências finais ficam no workflow Verificação e em seu `manifest.json`, vinculado ao
> commit e à árvore testados. Registros das execuções anteriores são históricos, não contagens
> atuais. Mérito visual, áudio físico e Android real continuam sem validação nesta sessão.

> **Integração autorizada:** `codex/resolve-open-prs-20260906` reúne #51–#54, preservando os
> pais de merge e a resolução #25×#50 já testada. O merge em `main` depende do CI do HEAD final.
> Censos de 16:00Z e 17:01Z foram preservados como histórico; consulte a fila real no GitHub.
''' + ledger[header_end:]
ledger_path.write_text(ledger)

surface = Path('tools/loop/unclaimed_surface.sh')
s = surface.read_text()
s = replace_once(s, 'echo "base:            ${BASE_REF}',
                 'echo "nota: heurística por refs; confirme o estado dos PRs no GitHub."\necho "base:            ${BASE_REF}')
surface.write_text(s)

Path('.github/workflows/resolve-once.yml').unlink()
Path('tools/ci/integrate_once.py').unlink()
git('add', '-A')
git('commit', '-m', 'Reconcile PR ledger and remove one-shot integration worker')
print('CANDIDATE_COMMIT=' + git('rev-parse', 'HEAD').stdout.strip(), flush=True)
