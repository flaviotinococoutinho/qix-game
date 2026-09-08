"""Transporte textual verificável das árvores testadas; nunca reconstrói por aproximação."""
from __future__ import annotations
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess

ROOT = Path.cwd()
WORK = Path(os.environ['RUNNER_TEMP']) / 'qix-reconstruction'
WORK.mkdir(parents=True, exist_ok=True)
CONFIG = ROOT / '.github/maintenance'
plan = json.loads((CONFIG / 'branch-plan.json').read_text())


def git(*args: str, data: str | None = None, env: dict | None = None) -> str:
    result = subprocess.run(['git', *args], input=data, text=True, cwd=ROOT,
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    return result.stdout.strip()


def sha(value: str) -> str:
    if not re.fullmatch('[0-9a-f]{40}', value):
        raise RuntimeError('SHA inválido no plano.')
    return value


for filename in ('blobs-a.json', 'blobs-b.json'):
    for blob in json.loads((CONFIG / filename).read_text()):
        expected = sha(blob['sha'])
        if 'text' in blob:
            content = blob['text']
        else:
            original = subprocess.check_output(['git', 'cat-file', 'blob', sha(blob['base'])], cwd=ROOT).decode('utf-8')
            pieces = []
            for chunk in blob['chunks']:
                if isinstance(chunk, str):
                    pieces.append(chunk)
                else:
                    start, length = chunk
                    if not isinstance(start, int) or not isinstance(length, int) or start < 0 or length < 0 or start + length > len(original):
                        raise RuntimeError('Intervalo de delta inválido.')
                    pieces.append(original[start:start + length])
            content = ''.join(pieces)
        actual = git('hash-object', '-w', '--stdin', data=content)
        if actual != expected:
            raise RuntimeError(f'Blob divergente: esperado {expected}, reconstruído {actual}. Nenhuma PR foi alterada.')

paths = plan['paths']
if len(paths) != len(set(paths)) or any('\n' in path or '\t' in path or path.startswith('/') or '..' in Path(path).parts for path in paths):
    raise RuntimeError('Lista de caminhos inválida.')
prs = plan['prs']
if sorted(p['pr'] for p in prs) != list(range(57, 88)):
    raise RuntimeError('O escopo precisa ser exatamente #57–#87.')


def commit(tree: str, parents: list[str], message: str) -> str:
    args = ['-c', 'user.name=Preparação assistida do mantenedor',
            '-c', 'user.email=review@users.noreply.github.com', 'commit-tree', tree]
    for parent in parents:
        args.extend(['-p', parent])
    return git(*args, '-m', message)


for p in prs:
    index = WORK / f'index-{p["pr"]}'
    if index.exists():
        index.unlink()
    env = dict(os.environ, GIT_INDEX_FILE=str(index))
    git('read-tree', sha(p['original_head']), env=env)
    entries = []
    for path_index, mode, blob_sha in p.pop('changes'):
        if mode not in ('0', '100644', '100755', '120000'):
            raise RuntimeError('Modo de arquivo fora do contrato.')
        object_sha = '0' * 40 if mode == '0' else sha(blob_sha)
        entries.append(f'{mode} {object_sha}\t{paths[path_index]}\n')
    git('update-index', '--index-info', data=''.join(entries), env=env)
    tree = git('write-tree', env=env)
    if tree != sha(p['tree']):
        raise RuntimeError(f'Árvore divergente na PR #{p["pr"]}: {tree} != {p["tree"]}. Nenhuma PR foi alterada.')
    if p['pr'] == 78:
        continue
    parents = [p['original_head']]
    if subprocess.run(['git', 'merge-base', '--is-ancestor', plan['base'], p['original_head']], cwd=ROOT).returncode:
        parents.append(plan['base'])
    p['prepared_head'] = commit(tree, parents, f'Prepara PR #{p["pr"]}: reconcilia a base e a revisão, preservando o histórico original')
    p['checkpoint'] = commit(tree, [p['prepared_head']], f'Atesta árvore revisada da PR #{p["pr"]}, sem alterar conteúdo')

aggregate = next(p for p in prs if p['pr'] == 78)
parents = [aggregate['original_head']] + [p['checkpoint'] for p in prs if p['pr'] != 78]
aggregate['prepared_head'] = commit(aggregate['tree'], parents, 'Integra preparação das PRs #57–#87: conflitos conciliados, árvores verificadas e históricos originais preservados')
aggregate['checkpoint'] = commit(aggregate['tree'], [aggregate['prepared_head']], 'Atesta candidato integrado das PRs #57–#87, sem alteração de conteúdo')
reference = 'refs/heads/reconstruction-verified-snapshot'
git('update-ref', reference, aggregate['checkpoint'])
bundle = WORK / 'prepared.bundle'
git('-c', 'pack.window=250', 'bundle', 'create', str(bundle), reference, '^' + plan['base'], *['^' + p['original_head'] for p in prs])
raw = bundle.read_bytes()
payload = {'base': plan['base'], 'prs': prs, 'bundle_sha256': hashlib.sha256(raw).hexdigest(),
           'bundle_base64': base64.b64encode(raw).decode()}
(CONFIG / 'prepared-payload.json').write_text(json.dumps(payload))
# O publicador independente reconfere heads remotos, ancestralidade, árvore, suíte e concorrência.
runpy.run_path(str(CONFIG / 'publish_prepared.py'), run_name='__main__')
