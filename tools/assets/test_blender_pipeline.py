"""Contratos da integração Blender, sem MCP/Blender nos testes unitários."""
import os
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
JOB = ROOT / "tools/assets/blender_mcp_job.py"
GUARD = ROOT / "tools/mcp/blender_checked.py"
LAUNCHER = ROOT / "tools/mcp/blender_mcp.py"


def job_module():
    spec = importlib.util.spec_from_file_location("qix_job", JOB)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def guard_fixture(script, timeout="90"):
    with tempfile.TemporaryDirectory() as folder:
        fake = Path(folder) / "fake blender"
        fake.write_text("#!/bin/sh\n" + script)
        fake.chmod(0o755)
        return subprocess.run([sys.executable, str(GUARD)], capture_output=True, text=True,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1",
                "QIX_BLENDER_EXECUTABLE": str(fake), "QIX_BLENDER_CLI_TIMEOUT": timeout}, timeout=5)


class BlenderPipelineTest(unittest.TestCase):
    def test_help_does_not_require_mcp_in_current_python(self):
        result = subprocess.run([sys.executable, str(JOB), "--help"],
            capture_output=True, text=True, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--blender", result.stdout)

    def test_crashed_blender_cannot_publish_a_success_marker(self):
        with tempfile.TemporaryDirectory() as folder:
            fake = Path(folder) / "fake-blender"
            fake.write_text('#!/bin/sh\nprintf \'__BLMCP_RESULT__{"ok":true}\\n\'\nexit 9\n')
            fake.chmod(0o755)
            result = subprocess.run([sys.executable, str(GUARD), "--background"],
                capture_output=True, text=True, env={**os.environ,
                "PYTHONDONTWRITEBYTECODE": "1", "QIX_BLENDER_EXECUTABLE": str(fake)})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("__BLMCP_RESULT__", result.stdout)
        self.assertIn("__BLMCP_ERROR__", result.stdout)
        self.assertIn("9", result.stdout)

    def test_explicit_missing_python_fails_without_falling_back(self):
        result = subprocess.run([sys.executable, str(LAUNCHER), "--doctor",
            "--python", "/qix-does-not-exist/python"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("QIX_BLENDER_MCP_PYTHON", result.stderr)
        self.assertIn("não", result.stderr)

    def test_internal_error_is_failure_even_when_mcp_transport_succeeded(self):
        module = job_module()
        classify = getattr(module, "job_result", None)
        self.assertIsNotNone(classify, "adapter precisa classificar resultado de aplicação")
        with self.assertRaisesRegex(ValueError, "erro"):
            classify({"isError": False, "structuredContent": {"status": "error", "message": "fixture"}})

    def test_failed_preflight_replaces_stale_success_receipt(self):
        with tempfile.TemporaryDirectory() as folder:
            receipt = Path(folder) / "receipt.json"
            receipt.write_text('{"status":"ok"}')
            result = subprocess.run([sys.executable, str(JOB), "--python", "/qix-missing/python",
                "--receipt", str(receipt)], capture_output=True, text=True)
            payload = json.loads(receipt.read_text())
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(payload["status"], "failed")
        self.assertEqual(payload["schema_version"], 1)
        self.assertIn("QIX_BLENDER_MCP_PYTHON", payload["error"])

    def test_receipt_cannot_overwrite_the_input_blend(self):
        with tempfile.TemporaryDirectory() as folder:
            blend = Path(folder) / "source.blend"
            original = b"BLENDER-source-must-survive"
            blend.write_bytes(original)
            result = subprocess.run([sys.executable, str(JOB), "--python", "/qix-missing/python",
                "--blend", str(blend), "--receipt", str(blend)], capture_output=True, text=True)
            preserved = blend.read_bytes()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(preserved, original)

    def test_guard_releases_single_result_after_clean_exit(self):
        result = guard_fixture("printf '__BLMCP_RESULT__{\"ok\":true}\\n'\n")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, '__BLMCP_RESULT__{"ok":true}\n')

    def test_guard_rejects_conflicting_markers_even_at_exit_zero(self):
        result = guard_fixture("printf '__BLMCP_RESULT__{}\\n__BLMCP_ERROR__\"boom\"\\n'\n")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("__BLMCP_RESULT__", result.stdout)

    def test_guard_rejects_internal_error_even_at_exit_zero(self):
        result = guard_fixture("printf '__BLMCP_ERROR__\"boom\"\\n'\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("erro interno", result.stdout)

    def test_guard_timeout_is_failure(self):
        result = guard_fixture("exec sleep 2\n", timeout="0.05")
        self.assertEqual(result.returncode, 1)
        self.assertIn("__BLMCP_ERROR__", result.stdout)
        self.assertIn("timed out", result.stdout)

    def _assert_guard_reaps_descendants(self, interrupt):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            late = root / "late-artifact"
            ready = root / "process-group"
            child = root / "child.py"
            child.write_text("import pathlib,time\ntime.sleep(1.2)\npathlib.Path("
                + repr(str(late)) + ").write_text('late mutation')\n")
            fake = root / "fake-blender"
            fake.write_text(f"#!{sys.executable}\nimport os,pathlib,subprocess,sys,time\n"
                + "subprocess.Popen([sys.executable,'-B'," + repr(str(child))
                + "],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n"
                + "pathlib.Path(" + repr(str(ready)) + ").write_text(str(os.getpgrp()))\n"
                + "time.sleep(5)\n")
            fake.chmod(0o700)
            proc = subprocess.Popen([sys.executable, "-B", str(GUARD)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                start_new_session=True, env={**os.environ,
                    "PYTHONDONTWRITEBYTECODE": "1", "QIX_BLENDER_EXECUTABLE": str(fake),
                    "QIX_BLENDER_CLI_TIMEOUT": "10" if interrupt else "0.5"})
            try:
                deadline = time.monotonic() + 2
                while not ready.exists() and proc.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(ready.exists(), "fixture deve iniciar o descendente")
                if interrupt:
                    proc.send_signal(signal.SIGTERM)
                stdout, _stderr = proc.communicate(timeout=3)
                self.assertEqual(proc.returncode, 1)
                self.assertIn("__BLMCP_ERROR__", stdout)
                self.assertFalse(late.exists(), "nenhum artefato no momento da falha")
                time.sleep(1.3)
                self.assertFalse(late.exists(), "descendente não pode gravar após falha do guard")
            finally:
                # Também limpa os processos quando executado contra a implementação defeituosa.
                groups = {proc.pid}
                if ready.exists():
                    groups.add(int(ready.read_text()))
                for group in groups:
                    try:
                        os.killpg(group, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                proc.communicate(timeout=3)

    @unittest.skipUnless(os.name == "posix", "process groups são o contrato POSIX")
    def test_guard_timeout_prevents_late_descendant_artifact(self):
        self._assert_guard_reaps_descendants(interrupt=False)

    @unittest.skipUnless(os.name == "posix", "process groups são o contrato POSIX")
    def test_guard_interruption_prevents_late_descendant_artifact(self):
        self._assert_guard_reaps_descendants(interrupt=True)

    def test_unconfirmed_or_empty_result_is_not_success(self):
        module = job_module()
        for payload in ({}, {"isError": True}, {"isError": False, "structuredContent": {}},
                {"isError": False, "structuredContent": {"status": "pending"}},
                {"isError": False, "content": [{"type": "text", "text": "not json"}]}):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                module.job_result(payload)

    def test_text_result_is_accepted_when_it_is_one_valid_dictionary(self):
        self.assertEqual(job_module().job_result({"isError": False,
            "content": [{"type": "text", "text": '{"status":"ok","value":42}'}]}),
            {"status": "ok", "value": 42})

    def test_expected_glb_must_be_structurally_valid_not_just_nonempty(self):
        validate = getattr(job_module(), "artifact_evidence", None)
        self.assertIsNotNone(validate)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "invalid.glb"
            path.write_bytes(b"nonempty but not glTF")
            with self.assertRaises(ValueError):
                validate(path)

    def test_transport_success_cannot_reuse_stale_artifact(self):
        module = job_module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "project.godot").write_text("config_version=5")
            blend = root / "input.blend"
            blend.write_bytes(b"BLENDERfixture")
            code = root / "job.py"
            code.write_text('result={"status":"ok"}')
            receipt = root / "receipt.json"
            async def transport(*args):
                return {"isError": False, "structuredContent": {"status": "ok"}}
            with patch.object(module, "resolve_runtime", return_value={"python": sys.executable, "blender": "fixture"}), \
                    patch.object(module, "run", side_effect=transport), contextlib.redirect_stdout(io.StringIO()):
                exit_code = module.main(["--project-root", str(root), "--code", str(code),
                    "--blend", str(blend), "--expect-artifact", str(blend), "--receipt", str(receipt)])
            payload = json.loads(receipt.read_text())
        self.assertEqual(exit_code, 1)
        self.assertEqual(payload["status"], "failed")
        self.assertIn("não criou/regravou", payload["error"])

    def test_doctor_honors_explicit_existing_paths_with_spaces(self):
        with tempfile.TemporaryDirectory() as folder:
            python = Path(folder) / "python fixture"
            blender = Path(folder) / "blender fixture"
            python.write_text('#!/bin/sh\nprintf \'{"python_version":"fixture","mcp_version":"1","blmcp_version":"1"}\\n\'\n')
            blender.write_text('#!/bin/sh\nprintf \'Blender fixture\\n\'\n')
            python.chmod(0o755)
            blender.chmod(0o755)
            result = subprocess.run([sys.executable, str(LAUNCHER), "--doctor"],
                capture_output=True, text=True, env={**os.environ,
                "QIX_BLENDER_MCP_PYTHON": str(python), "BLENDER_PATH": str(blender)})
            payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload["runtime"]["python"], str(python))
        self.assertEqual(payload["runtime"]["blender"], str(blender))
        self.assertEqual(payload["installs_performed"], 0)


if __name__ == "__main__":
    unittest.main()
