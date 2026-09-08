"""Finalização autorizada: comentários técnicos e prontidão, nunca APPROVE nem merge."""
from __future__ import annotations
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import time
import urllib.request

REPO = 'flaviotinococoutinho/qix-game'
PREFIX = 'https://api.github.com/repos/' + REPO
EVIDENCE_RUN = 34174939113
MARKER = '<!-- qix-preparation-57-87-20260908 -->'
root = Path(os.environ['RUNNER_TEMP'])
report = json.loads((root / 'preparation-evidence/publication.json').read_text())
output = root / 'qix-final-review'
output.mkdir(parents=True, exist_ok=True)
state = {'recorded_at': datetime.now(timezone.utc).isoformat(), 'base': report['base'],
         'formal_approvals': 0, 'merged_by_this_task': 0, 'prs': [], 'pending': [], 'failures': []}

def save():
    (output / 'readiness.json').write_text(json.dumps(state, indent=2, ensure_ascii=False))

def request(url, method='GET', data=None):
    req = urllib.request.Request(url, method=method,
        data=None if data is None else json.dumps(data).encode(),
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)

def api(path, method='GET', data=None):
    return request(PREFIX + path, method, data)

if report['status'] != 'published' or sorted(p['pr'] for p in report['prs']) != list(range(57, 88)):
    raise RuntimeError('Manifesto de publicação incompleto.')
if api('/branches/main')['commit']['sha'] != report['base']:
    raise RuntimeError('main avançou: esta prontidão precisa ser reavaliada.')

# Confere o CI convencional ligado ao HEAD efetivo, não o CI de um commit anterior.
remaining = {p['pr']: p for p in report['prs']}
checks = {}
for attempt in range(12):
    for number, p in list(remaining.items()):
        info = api(f'/pulls/{number}')
        if info['state'] != 'open' or info['head']['sha'] != p['checkpoint'] or info['base']['sha'] != report['base']:
            state['failures'].append({'pr': number, 'reason': 'head/base/state changed'})
            del remaining[number]
            continue
        commit = api('/commits/' + p['checkpoint'])
        if commit['commit']['tree']['sha'] != p['tree']:
            raise RuntimeError(f'PR #{number}: árvore não corresponde à testada.')
        runs = api('/actions/runs?event=pull_request&per_page=100&head_sha=' + p['checkpoint'])['workflow_runs']
        runs = [r for r in runs if r['path'] == '.github/workflows/verificacao.yml']
        if not runs:
            continue
        run = max(runs, key=lambda r: r['id'])
        if run['status'] != 'completed':
            continue
        if run['conclusion'] != 'success':
            state['failures'].append({'pr': number, 'reason': 'CI not successful', 'run': run['html_url']})
        else:
            checks[number] = run['html_url']
        del remaining[number]
    state['pending'] = sorted(remaining)
    save()
    if not remaining:
        break
    time.sleep(5)

for p in report['prs']:
    number = p['pr']
    if number not in checks:
        continue
    info = api(f'/pulls/{number}')
    if info['head']['sha'] != p['checkpoint'] or info['state'] != 'open':
        state['failures'].append({'pr': number, 'reason': 'concurrent update before review'})
        save()
        continue
    for retry in range(3):
        if info.get('mergeable') is not None:
            break
        time.sleep(2)
        info = api(f'/pulls/{number}')
    if info.get('mergeable') is not True:
        state['failures'].append({'pr': number, 'reason': 'mergeability not confirmed'})
        save()
        continue
    body = (MARKER + '\n### Preparação técnica concluída\n\n'
            f"HEAD `{p['checkpoint']}`; árvore `{p['tree']}`; base `{report['base']}`.\n\n"
            f"Suíte da árvore: **{p['tests']} testes, {p['assertions']} asserções, zero falhas**. "
            f"[CI deste HEAD]({checks[number]}). [Publicação e gate integrado](https://github.com/{REPO}/actions/runs/{EVIDENCE_RUN}).\n\n"
            'Histórico original preservado; sem force-push e sem merge na main. '
            'A integração #78 reúne as 31 PRs preparadas. Preferir o candidato integrado; '
            'mesclas individuais mudam a base e podem exigir nova reconciliação da matriz de testes.\n\n'
            '**Limites:** Linux headless, sem validação visual, áudio físico, Android real, assinatura '
            'ou extensão nativa Fennara ausente. Esta nota é revisão técnica, não aprovação formal independente. '
            'A conexão do mantenedor foi impedida pelo GitHub de aprovar as próprias PRs; nenhuma conta alternativa foi usada para aprovar.\n')
    if number == 57:
        body += '\nA atualização concorrente `c938e81` foi preservada: esta PR continua restrita ao relato documental.\n'
    if number in (70, 78):
        body += '\nCorreção adicional: liberar vozes de áudio também zera prazos e rodízio, com teste de regressão.\n'
    if number in (71, 78):
        body += '\nCorreção adicional: worktrees temporários exclusivos, preservação de diretórios existentes e propagação de falhas da engine; 16 testes Python de CI aprovados.\n'
    if number == 78:
        body += '\nA limpeza de fixtures recusa a raiz do projeto e só remove descendentes do diretório de dados de teste. Licença e ADR-0013 permanecem pendentes de decisão explícita.\n'
    existing = api(f'/issues/{number}/comments?per_page=100')
    if not any(MARKER in (c.get('body') or '') for c in existing):
        comment = api(f'/issues/{number}/comments', 'POST', {'body': body})
        comment_url = comment['html_url']
    else:
        comment_url = next(c['html_url'] for c in existing if MARKER in (c.get('body') or ''))
    if number == 78 and MARKER not in (info.get('body') or ''):
        updated_body = body + '\n<details>\n<summary>Descrição original: snapshot anterior à preparação de #57–#87</summary>\n\n' + (info.get('body') or '') + '\n</details>\n'
        api('/pulls/78', 'PATCH', {'title': 'Prepara e integra #57–#87: conflitos resolvidos e 309 testes verdes', 'body': updated_body})
    if info['draft']:
        result = request('https://api.github.com/graphql', 'POST', {
            'query': 'mutation($id:ID!){markPullRequestReadyForReview(input:{pullRequestId:$id}){pullRequest{number isDraft}}}',
            'variables': {'id': info['node_id']}})
        if result.get('errors'):
            raise RuntimeError(json.dumps(result['errors']))
    latest = api(f'/pulls/{number}')
    state['prs'].append({'number': number, 'head': latest['head']['sha'], 'tree': p['tree'],
                         'draft': latest['draft'], 'mergeable': latest['mergeable'],
                         'state': latest['state'], 'merged': latest['merged'],
                         'ci': checks[number], 'tests': p['tests'], 'assertions': p['assertions'],
                         'technical_review': comment_url, 'url': latest['html_url']})
    save()

state['main_unchanged'] = api('/branches/main')['commit']['sha'] == report['base']
state['open_pr_numbers'] = [p['number'] for p in api('/pulls?state=open&per_page=100')]
state['completed'] = len(state['prs']) == 31 and not state['pending'] and not state['failures'] and state['main_unchanged']
save()
print(json.dumps(state, ensure_ascii=False))
if not state['completed']:
    raise SystemExit('Revisão parcialmente concluída; consultar readiness.json antes de afirmar prontidão total.')
