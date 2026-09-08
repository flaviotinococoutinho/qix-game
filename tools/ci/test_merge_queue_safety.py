"""Regressões dos worktrees descartáveis do relatório; nenhum diretório preexistente é apagado."""
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class MergeQueueSafetyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='qix-queue-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        source = Path(__file__).resolve().parents[2] / 'tools/loop/merge_queue_report.sh'
        self.script = self.repo / 'tools/loop/merge_queue_report.sh'
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(source, self.script)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Teste da fila')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        self.base = self.git('rev-parse', 'HEAD').strip()
        (self.repo / 'item.txt').write_text('mudança\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'PR de teste')
        self.git('update-ref', 'refs/remotes/pr/1', 'HEAD')
        self.sentinel = self.root / 'diretorio-do-usuario'
        self.sentinel.mkdir()
        (self.sentinel / 'nao-apagar.txt').write_text('preservar\n')
        self.env = dict(os.environ, QIX_LOOP_BASE_REF=self.base,
                        QIX_LOOP_ORDER_WORKTREE=str(self.sentinel), TMPDIR=str(self.root))

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, text=True)

    def run_report(self, *args, env=None):
        return subprocess.run(['bash', str(self.script), *args], cwd=self.repo,
                              env=env or self.env, capture_output=True, text=True, timeout=30)

    def assert_preserved_and_clean(self):
        self.assertEqual((self.sentinel / 'nao-apagar.txt').read_text(), 'preservar\n')
        self.assertEqual(list(self.root.glob('diretorio-do-usuario.*')), [])
        self.assertEqual(self.git('worktree', 'list', '--porcelain').count('worktree '), 1)

    def test_order_preserves_existing_path_and_cleans_its_own_worktree(self):
        result = self.run_report('--order', '1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('OK        #1', result.stdout)
        self.assert_preserved_and_clean()

    def test_two_orders_never_share_a_worktree(self):
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: self.run_report('--order', '1'), range(2)))
        for result in results:
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_preserved_and_clean()

    def test_invalid_base_preserves_existing_path_and_removes_scratch(self):
        result = self.run_report('--order', '1', env=dict(self.env, QIX_LOOP_BASE_REF='ref-ausente'))
        self.assertNotEqual(result.returncode, 0)
        self.assert_preserved_and_clean()

    def test_verify_propagates_engine_failure_through_output_filters(self):
        engine = self.root / 'fake-godot'
        engine.write_text('#!/usr/bin/env bash\ncase " $* " in *" --import "*) exit 0;; esac\necho "1 testes, 1 asserções, 1 falhas"\nexit 7\n')
        engine.chmod(0o700)
        result = self.run_report('--verify', '1', env=dict(self.env, QIX_GODOT_BIN=str(engine)))
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertEqual(list(self.root.glob('qix-merge-verify.*')), [])
        self.assert_preserved_and_clean()


if __name__ == '__main__':
    unittest.main()
