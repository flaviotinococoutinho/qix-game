"""Regression tests for the CI gate, independent of Godot and network access."""
from pathlib import Path
from contextlib import redirect_stdout, redirect_stderr
import io
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from headless_gate import error_lines, optional_editor_extension, run_checked


class HeadlessGateTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(redirect_stdout(io.StringIO()))
        self.enterContext(redirect_stderr(io.StringIO()))

    def test_clean_output_and_negative_test_names_are_not_errors(self):
        self.assertEqual(error_lines('PASS script_error_capture_test\n{"errors": []}\nWARNING: optional'), [])

    def test_engine_error_is_found(self):
        self.assertEqual(error_lines('ERROR: missing library\n  at: loader'), ['ERROR: missing library'])

    def test_script_and_shader_errors_are_found(self):
        self.assertEqual(len(error_lines('SCRIPT ERROR: Invalid call\nSHADER ERROR: invalid source')), 2)

    def test_ansi_diagnostics_are_found(self):
        self.assertEqual(error_lines('\x1b[31mERROR:\x1b[0m failure'), ['ERROR: failure'])

    def test_clean_process_passes_and_keeps_full_log(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = run_checked([sys.executable, '-c', 'print("clean")'], root / 'run.log', cwd=root)
            self.assertEqual(result['exit_code'], 0)
            self.assertEqual((root / 'run.log').read_text(), 'clean\n')

    def test_zero_exit_with_engine_error_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaises(RuntimeError):
                run_checked([sys.executable, '-c', 'print("ERROR: broken")'], root / 'run.log', cwd=root)

    def test_nonzero_exit_without_engine_error_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaises(RuntimeError):
                run_checked([sys.executable, '-c', 'raise SystemExit(7)'], root / 'run.log', cwd=root)

    def test_descriptor_is_restored_after_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            descriptor = root / 'addons/fennara/fennara.gdextension'
            descriptor.parent.mkdir(parents=True)
            descriptor.write_text('native descriptor')
            with self.assertRaisesRegex(RuntimeError, 'simulated'):
                with optional_editor_extension(root, True) as isolated:
                    self.assertTrue(isolated)
                    self.assertFalse(descriptor.exists())
                    raise RuntimeError('simulated')
            self.assertEqual(descriptor.read_text(), 'native descriptor')

    def test_existing_library_is_not_hidden(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            library = root / 'addons/fennara/bin/libfennara.linux.editor.x86_64.so'
            library.parent.mkdir(parents=True)
            library.write_bytes(b'fixture')
            with optional_editor_extension(root, True) as isolated:
                self.assertFalse(isolated)

    def test_existing_backup_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            descriptor = root / 'addons/fennara/fennara.gdextension'
            descriptor.parent.mkdir(parents=True)
            descriptor.write_text('original')
            descriptor.with_suffix('.gdextension.ci-disabled').write_text('keep')
            with self.assertRaises(RuntimeError):
                with optional_editor_extension(root, True):
                    self.fail('must not enter')
            self.assertEqual(descriptor.read_text(), 'original')

    def test_missing_descriptor_is_not_silently_ignored(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(RuntimeError):
                with optional_editor_extension(Path(temp), True):
                    self.fail('must not enter')

    def test_registered_local_cache_is_not_modified(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            descriptor = root / 'addons/fennara/fennara.gdextension'
            descriptor.parent.mkdir(parents=True)
            descriptor.write_text('original')
            registry = root / '.godot/extension_list.cfg'
            registry.parent.mkdir()
            registry.write_text('res://addons/fennara/fennara.gdextension\n')
            with self.assertRaises(RuntimeError):
                with optional_editor_extension(root, True):
                    self.fail('must not enter')
            self.assertTrue(descriptor.exists())


if __name__ == '__main__':
    unittest.main()
