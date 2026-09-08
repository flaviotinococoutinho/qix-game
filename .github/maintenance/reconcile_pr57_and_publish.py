"""Conciliação estritamente fixada à atualização #57 revisada pelo mantenedor."""
from __future__ import annotations
import json
import os
from pathlib import Path
import re
import runpy
import subprocess

ROOT = Path.cwd()
CONFIG = ROOT / '.github/maintenance'
BASE = 'ca745780ad3242695ba7411416da87c6b490c609'
NEW_HEAD = 'c938e8176660a7cadded6598967264e9c6403f3c'
NEW_TREE = 'a6724387b14e537fa91bc828890cc68d8a44bb5c'
REPORT = 'docs/loop/runs/2026-09-06T194332Z.md'
REPORT_BLOB = 'fa9efd629b5a2dd4f3fee7d95c294b149eb4c9ee'
AGGREGATE_TREE = '88cbcca0e6f421177c450ec938fbf69f9eb3cabf'

def git(*args: str) -> str:
    return subprocess.check_output(['git', *args], text=True).strip()

plan = json.loads((CONFIG / 'branch-plan.json').read_text())
p57 = next(p for p in plan['prs'] if p['pr'] == 57)
p78 = next(p for p in plan['prs'] if p['pr'] == 78)
if plan['base'] != BASE or p57['original_head'] != '5effaace9e37d036b8a05f571a33dddb6e574ae7':
    raise RuntimeError('Plano não corresponde ao snapshot revisado.')
git('fetch', '--no-tags', 'origin', 'refs/pull/57/head')
if git('rev-parse', NEW_HEAD + '^{tree}') != NEW_TREE:
    raise RuntimeError('Árvore concorrente não corresponde à revisão.')
if git('diff', '--name-only', BASE, NEW_HEAD).splitlines() != [REPORT]:
    raise RuntimeError('A PR #57 deixou de ser exclusivamente o relato revisado.')
if git('rev-parse', NEW_HEAD + ':' + REPORT) != REPORT_BLOB:
    raise RuntimeError('O relato diverge do texto revisado.')

# Mantém exatamente a árvore atual de #57, sem reinserir ledger, matriz ou limpeza de bytecode.
p57.update(original_head=NEW_HEAD, tree=NEW_TREE, changes=[], verified_head=NEW_HEAD)
if p78['tree'] != '1d5b202a416aceaf4ec8a81017515c21c33c0b0f':
    raise RuntimeError('Integração de origem inesperada.')
plan['paths'].append(REPORT)
p78['changes'].append([len(plan['paths']) - 1, '100644', REPORT_BLOB])
p78['tree'] = AGGREGATE_TREE
p78.pop('verified_head', None)
(CONFIG / 'branch-plan.json').write_text(json.dumps(plan))

# Revalida o head documental com dados de usuário isolados, antes de qualquer escrita remota.
temp = Path(os.environ['RUNNER_TEMP']) / 'qix-pr57-current'
project = temp / 'candidate'
temp.mkdir(parents=True, exist_ok=True)
git('worktree', 'add', '--detach', str(project), NEW_HEAD)
logs = Path(os.environ['RUNNER_TEMP']) / 'qix-publication/evidence/pr57-current'
logs.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1',
           XDG_DATA_HOME=str(temp / 'user-data'), XDG_CONFIG_HOME=str(temp / 'user-config'),
           XDG_CACHE_HOME=str(temp / 'user-cache'), GODOT_SILENCE_ROOT_WARNING='1')
engine = str(Path.home() / 'godot-bin/Godot_v4.7.2-stable_linux.x86_64')
with (logs / 'gate.log').open('w') as output:
    subprocess.run(['python3', 'tools/ci/headless_gate.py', '--godot', engine,
                    '--logs', str(logs / 'headless'), '--isolate-missing-editor-extension'],
                   cwd=project, env=env, stdout=output, stderr=subprocess.STDOUT,
                   check=True, timeout=300)
text = (logs / 'headless/suite.log').read_text()
match = re.search(r'(\d+) testes, (\d+) asserções, (\d+) falhas', text)
if not match or list(map(int, match.groups())) != [262, 12719, 0]:
    raise RuntimeError('O novo head da PR #57 não confirma sua referência de testes.')

# A árvore de #57 é idêntica à revisada pelo autor; a higiene de bytecode
# continua obrigatória nas demais 30 branches e no agregado, sem ampliar seu escopo.
publisher = CONFIG / 'publish_prepared.py'
source = publisher.read_text()
original = "    if any('__pycache__/' in name or name.endswith(('.pyc', '.pyo', '.pyd')) for name in tracked):"
replacement = "    if not (number == 57 and p['tree'] == 'a6724387b14e537fa91bc828890cc68d8a44bb5c') and any('__pycache__/' in name or name.endswith(('.pyc', '.pyo', '.pyd')) for name in tracked):"
if source.count(original) != 1 or source.count('\nlogs.mkdir()\n') != 1:
    raise RuntimeError('Contrato do publicador mudou: interromper em vez de relaxar a verificação.')
source = source.replace(original, replacement).replace('\nlogs.mkdir()\n', '\nlogs.mkdir(exist_ok=True)\n')
publisher.write_text(source)
# O publicador conserva as comparações de HEAD de TODAS as branches, inclusive a #57 nova.
runpy.run_path(str(CONFIG / 'reconstruct_prepared.py'), run_name='__main__')
