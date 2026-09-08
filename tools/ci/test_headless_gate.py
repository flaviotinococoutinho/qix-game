"""Regression tests for the CI gate, independent of Godot and network access."""
from pathlib import Path
from contextlib import redirect_stdout, redirect_stderr
import io
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from headless_gate import error_lines, optional_editor_extension, run_checked
import headless_gate as gate


class HeadlessGateTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(redirect_stdout(io.StringIO()))
        self.enterContext(redirect_stderr(io.StringIO()))

    def test_official_mono_and_standard_have_explicit_supported_variants(self):
        verify = getattr(gate, "verified_engine_version", None)
        self.assertIsNotNone(verify)
        self.assertEqual(verify("4.7.2.stable.mono.official.ed1daf0bf")["variant"], "mono")
        self.assertEqual(verify("4.7.2.stable.official.ed1daf0bf")["variant"], "standard")

    def test_dirty_worktree_has_its_own_digest_not_the_head_tree(self):
        describe = getattr(gate, "source_receipt", None)
        self.assertIsNotNone(describe)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            file = root / "project.godot"
            file.write_text("before")
            status = b""
            def git_output(command, **kwargs):
                if command[1] == "rev-parse":
                    return b"commit-id\n" if command[-1] == "HEAD" else b"head-tree-id\n"
                if command[1] == "status":
                    return status
                if "--cached" in command:
                    return b"project.godot\0"
                return b""
            with patch.object(gate.subprocess, "check_output", side_effect=git_output):
                before = describe(root)
                file.write_text("after")
                status = b" M project.godot\0"
                after = describe(root)
        self.assertFalse(before["dirty"])
        self.assertTrue(after["dirty"])
        self.assertEqual(before["head_tree"], after["head_tree"])
        self.assertNotEqual(before["worktree_sha256"], after["worktree_sha256"])

    def test_suite_json_rejects_zero_tests_even_when_exit_is_zero(self):
        validate = getattr(gate, "validate_suite_result", None)
        self.assertIsNotNone(validate)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "suite.json"
            path.write_text(json.dumps({"schema_version": 1, "total": 0, "assertions": 0,
                "failures": 0, "discovery_errors": 0, "exit_code": 0, "filter": "", "tests": []}))
            with self.assertRaises(RuntimeError):
                validate(path)

    def test_main_requires_json_and_labels_dirty_source_before_and_after(self):
        commands = []
        source = {"head_commit": "head", "head_tree": "tree", "dirty": True,
            "worktree_sha256": "worktree", "status_sha256": "status"}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            project, logs = root / "project", root / "logs"
            project.mkdir()
            def process(command, log, **kwargs):
                commands.append(command)
                if "--json" in command:
                    Path(command[command.index("--json") + 1]).write_text(json.dumps(self.valid_suite()))
                return {"log": log.name, "exit_code": 0, "engine_errors": 0}
            with patch.object(gate, "source_receipt", return_value=source), \
                    patch.object(gate, "run_checked", side_effect=process), \
                    patch.object(gate.subprocess, "check_output", return_value="4.7.2.stable.mono.official.ed1daf0bf"):
                result = gate.main(["--godot", "/fixture/Godot", "--project", str(project), "--logs", str(logs)])
            manifest = json.loads((logs / "manifest.json").read_text())
        self.assertEqual(result, 0)
        self.assertIn("--json", commands[1])
        self.assertEqual(manifest["source_before"], source)
        self.assertEqual(manifest["source_after"], source)
        self.assertTrue(manifest["source_unchanged"])
        self.assertFalse(manifest["tested_head"])
        self.assertEqual(commands[0][-3:], ["--import", "--lsp-port", "0"])
        self.assertNotIn("--lsp-port", commands[1])

    @staticmethod
    def valid_suite():
        return {"schema_version": 1, "total": 1, "assertions": 3,
            "failures": 0, "discovery_errors": 0, "exit_code": 0, "filter": "",
            "tests": [{"file": "res://tests/unit/fixture_test.gd", "name": "test_fixture",
                "assertions": 3, "failed": False, "messages": []}]}

    def test_engine_policy_rejects_close_versions_custom_builds_and_extra_text(self):
        for version in ("4.7.20.stable.official.ed1daf0bf", "4.7.2.dev.mono.official.ed1daf0bf",
                "4.7.2.stable.custom.ed1daf0bf", "4.7.2.stable.officially",
                "4.7.2.stable.official.ed1daf0bf.extra", "4.7.2.stable.official\nERROR: bad"):
            with self.subTest(version=version), self.assertRaises(RuntimeError):
                gate.verified_engine_version(version)

    def test_suite_json_accepts_complete_valid_records(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "suite.json"
            path.write_text(json.dumps(self.valid_suite()))
            report = gate.validate_suite_result(path)
        self.assertEqual(report["total"], 1)
        self.assertEqual(report["assertions"], 3)
        self.assertEqual(len(report["sha256"]), 64)

    def test_suite_json_rejects_missing_or_malformed_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "suite.json"
            with self.assertRaises(RuntimeError):
                gate.validate_suite_result(path)
            path.write_text("not-json")
            with self.assertRaises(RuntimeError):
                gate.validate_suite_result(path)

    def test_suite_json_rejects_partial_inconsistent_and_failed_results(self):
        mutations = [lambda data: data.update({"filter": "fixture"}),
            lambda data: data.update({"total": True}),
            lambda data: data.update({"assertions": 4}),
            lambda data: data.update({"discovery_errors": 1}),
            lambda data: data["tests"][0].update({"failed": True}),
            lambda data: data["tests"][0].update({"assertions": 0}),
            lambda data: data.update({"tests": []}),
            lambda data: data.update({"total": 2, "assertions": 6, "tests": data["tests"] * 2})]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "suite.json"
            for index, mutate in enumerate(mutations):
                with self.subTest(index=index):
                    data = self.valid_suite()
                    mutate(data)
                    path.write_text(json.dumps(data))
                    with self.assertRaises(RuntimeError):
                        gate.validate_suite_result(path)

    def test_main_cannot_pass_by_reusing_old_suite_json(self):
        source = {"head_commit": "head", "head_tree": "tree", "dirty": False,
            "worktree_sha256": "same", "status_sha256": "same"}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            project, logs = root / "project", root / "logs"
            project.mkdir()
            logs.mkdir()
            (logs / "suite.json").write_text(json.dumps(self.valid_suite()))
            with patch.object(gate, "source_receipt", return_value=source), \
                    patch.object(gate, "run_checked", return_value={"exit_code": 0, "engine_errors": 0}), \
                    patch.object(gate.subprocess, "check_output", return_value="4.7.2.stable.official.ed1daf0bf"):
                result = gate.main(["--godot", "/fixture/Godot", "--project", str(project), "--logs", str(logs)])
            manifest = json.loads((logs / "manifest.json").read_text())
        self.assertEqual(result, 1)
        self.assertEqual(manifest["status"], "failed")
        self.assertFalse(manifest["tested_head"])

    def test_source_change_during_clean_checks_prevents_a_pass(self):
        before = {"head_commit": "head", "head_tree": "tree", "dirty": False,
            "worktree_sha256": "before", "status_sha256": "before"}
        after = {**before, "dirty": True, "worktree_sha256": "after"}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            project, logs = root / "project", root / "logs"
            project.mkdir()
            def process(command, log, **kwargs):
                if "--json" in command:
                    Path(command[command.index("--json") + 1]).write_text(json.dumps(self.valid_suite()))
                return {"exit_code": 0, "engine_errors": 0}
            with patch.object(gate, "source_receipt", side_effect=[before, after]), \
                    patch.object(gate, "run_checked", side_effect=process), \
                    patch.object(gate.subprocess, "check_output", return_value="4.7.2.stable.official.ed1daf0bf"):
                result = gate.main(["--godot", "/fixture/Godot", "--project", str(project), "--logs", str(logs)])
            manifest = json.loads((logs / "manifest.json").read_text())
        self.assertEqual(result, 1)
        self.assertFalse(manifest["source_unchanged"])
        self.assertFalse(manifest["tested_head"])
        self.assertEqual(manifest["source_before"]["head_tree"], manifest["source_after"]["head_tree"])

    def test_clean_output_and_negative_test_names_are_not_errors(self):
        self.assertEqual(error_lines('PASS script_error_capture_test\n{"errors": []}\nWARNING: optional'), [])

    def test_engine_error_is_found(self):
        self.assertEqual(error_lines('ERROR: missing library\n  at: loader'), ['ERROR: missing library'])

    def test_native_daemon_panic_is_fatal_without_an_error_prefix(self):
        line = "thread 'main' (1710912) panicked at crates/fennara-daemon/runtime_daemon/mod.rs:93:10:"
        self.assertEqual(error_lines(line + "\nfailed to bind fennara daemon: AddrInUse"), [line])

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
