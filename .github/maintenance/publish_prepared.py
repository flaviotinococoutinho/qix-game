"""Publicação pontual das branches preparadas; nunca altera main nem aprova reviews."""
from __future__ import annotations
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

ROOT = Path.cwd()
TEMP = Path(os.environ['RUNNER_TEMP']) / 'qix-publication'
TEMP.mkdir(parents=True, exist_ok=True)
REPO = 'flaviotinococoutinho/qix-game'
STAGING = 'maintenance/prepared-validation-20260908'

def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()

def api(path: str):
    request = urllib.request.Request('https://api.github.com/repos/' + REPO + path,
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)

def ancestor(parent: str, child: str) -> None:
    subprocess.run(['git', 'merge-base', '--is-ancestor', parent, child], check=True)

payload = json.loads((ROOT / '.github/maintenance/prepared-payload.json').read_text())
prs = payload['prs']
if sorted(p['pr'] for p in prs) != list(range(57, 88)):
    raise RuntimeError('O payload precisa conter exatamente as PRs #57–#87.')
base = payload['base']
if api('/branches/main')['commit']['sha'] != base:
    raise RuntimeError('main avançou: revisar a nova base antes de publicar.')

archive = base64.b64decode(payload['bundle_base64'], validate=True)
if hashlib.sha256(archive).hexdigest() != payload['bundle_sha256']:
    raise RuntimeError('Checksum do bundle divergente.')
bundle = TEMP / 'prepared.bundle'
bundle.write_bytes(archive)
git('bundle', 'verify', str(bundle))
git('bundle', 'unbundle', str(bundle))

for p in prs:
    number = p['pr']
    info = api(f'/pulls/{number}')
    if info['state'] != 'open' or info['base']['ref'] != 'main':
        raise RuntimeError(f'PR #{number} não está mais aberta contra main.')
    if info['head']['repo']['full_name'] != REPO:
        raise RuntimeError(f'PR #{number} mudou de repositório de origem.')
    if info['head']['sha'] != p['original_head'] or info['head']['ref'] != p['branch']:
        raise RuntimeError(f'PR #{number} avançou: nenhum head concorrente será sobrescrito.')
    if not re.fullmatch(r'ai/loop-[A-Za-z0-9TZ]+', p['branch']):
        raise RuntimeError('Ref de publicação fora da lista permitida.')
    for field in ('original_head', 'prepared_head', 'checkpoint', 'tree'):
        if not re.fullmatch(r'[0-9a-f]{40}', p[field]):
            raise RuntimeError('SHA inválido.')
    ancestor(p['original_head'], p['prepared_head'])
    ancestor(base, p['prepared_head'])
    ancestor(p['prepared_head'], p['checkpoint'])
    for head in (p['prepared_head'], p['checkpoint']):
        if git('rev-parse', head + '^{tree}') != p['tree']:
            raise RuntimeError(f'PR #{number}: checkpoint não preserva a árvore testada.')
    tracked = git('ls-tree', '-r', '--name-only', p['prepared_head']).splitlines()
    if any('__pycache__/' in name or name.endswith(('.pyc', '.pyo', '.pyd')) for name in tracked):
        raise RuntimeError(f'PR #{number} ainda rastreia bytecode.')
    if p['failures'] != 0 or p['tests'] <= 0:
        raise RuntimeError(f'PR #{number} não tem evidência local aprovada.')

aggregate = next(p for p in prs if p['pr'] == 78)
for p in prs:
    if p['pr'] != 78:
        ancestor(p['checkpoint'], aggregate['prepared_head'])

project = TEMP / 'candidate'
git('worktree', 'add', '--detach', str(project), aggregate['prepared_head'])
logs = TEMP / 'evidence'
logs.mkdir()
engine = str(Path.home() / 'godot-bin/Godot_v4.7.2-stable_linux.x86_64')
env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1',
           XDG_DATA_HOME=str(TEMP / 'user-data'),
           XDG_CONFIG_HOME=str(TEMP / 'user-config'),
           XDG_CACHE_HOME=str(TEMP / 'user-cache'),
           GODOT_SILENCE_ROOT_WARNING='1')

def command(args: list[str], name: str) -> None:
    with (logs / name).open('w') as stream:
        subprocess.run(args, cwd=project, env=env, stdout=stream,
                       stderr=subprocess.STDOUT, check=True, timeout=300)

command(['python3', '-m', 'unittest', 'discover', '-s', 'tools/ci', '-p', 'test_*.py', '-v'], 'python-ci.log')
command(['python3', '-m', 'unittest', 'discover', '-s', 'tools/profile', '-p', 'test_*.py', '-v'], 'python-profile.log')
command(['python3', 'tools/ci/headless_gate.py', '--godot', engine,
         '--logs', str(logs / 'headless'), '--isolate-missing-editor-extension'], 'gate.log')
for script in sorted((project / 'tools/loop').glob('*.sh')):
    command(['bash', '-n', str(script)], script.stem + '.syntax.log')

suite = (logs / 'headless/suite.log').read_text()
match = re.search(r'(\d+) testes, (\d+) asserções, (\d+) falhas', suite)
if not match or list(map(int, match.groups())) != [aggregate['tests'], aggregate['assertions'], 0]:
    raise RuntimeError('Suíte remota não confirma os resultados da árvore integrada.')
if git('status', '--porcelain', cwd=project):
    raise RuntimeError('A validação alterou arquivos rastreados da árvore candidata.')

# Reconfere os heads imediatamente antes da transação. Sem force e sem bypass de regras.
remote = dict(line.split('\t')[::-1] for line in git('ls-remote', '--heads', 'origin').splitlines())
if remote.get('refs/heads/main') != base:
    raise RuntimeError('main avançou durante o QA.')
for p in prs:
    if remote.get('refs/heads/' + p['branch']) != p['original_head']:
        raise RuntimeError(f"PR #{p['pr']} avançou durante o QA.")
if 'refs/heads/' + STAGING in remote:
    raise RuntimeError('Ref temporária já existe: não sobrescrever.')
refspecs = [p['prepared_head'] + ':refs/heads/' + p['branch'] for p in prs]
refspecs.append(aggregate['checkpoint'] + ':refs/heads/' + STAGING)
subprocess.run(['git', 'push', '--atomic', 'origin', *refspecs], check=True)

report = {'status': 'published', 'base': base, 'main_unchanged': True,
          'formal_approvals': 0, 'merge_into_main': False, 'prs': prs,
          'scope': 'headless; sem QA visual, extensão nativa, áudio físico, Android ou assinatura'}
(logs / 'publication.json').write_text(json.dumps(report, indent=2, ensure_ascii=False))
print(json.dumps(report, ensure_ascii=False))
