"""Regressões da integração de projeto; não exigem Godot, uv, rede externa ou addons ativos."""
from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import godot_mcp
import godot_runtime as runtime


class GodotIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = self.enterContext(tempfile.TemporaryDirectory())
        self.root = Path(self.temp).resolve()
        self.project = self.root / "project"
        self.project.mkdir()
        (self.project / "project.godot").write_text('[application]\nconfig/name="QIX"\n')
        plugin = self.project / "addons/godot_ai/plugin.cfg"
        plugin.parent.mkdir(parents=True)
        plugin.write_text('[plugin]\nversion="4.0.2"\n')

    def _executable(self, path, text="#!/bin/sh\nexit 0\n"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o700)
        return path

    def _report(self, **changes):
        return {"schema_version": 1, "total": 2, "assertions": 7, "failures": 0,
                "discovery_errors": 0, **changes}

    def test_explicit_uvx_wins_even_outside_path(self):
        binary = self._executable(self.root / "custom/uvx")
        self.assertEqual(runtime.resolve_uvx(str(binary), env={"PATH": ""}, home=self.root), str(binary))

    def test_broken_explicit_uvx_does_not_silently_fallback(self):
        with self.assertRaises(runtime.IntegrationError):
            runtime.resolve_uvx(str(self.root / "absent"), env={"PATH": os.environ.get("PATH", "")})

    def test_path_precedes_home_fallback(self):
        binary = self._executable(self.root / "bin/uvx")
        self._executable(self.root / ".local/bin/uvx")
        self.assertEqual(runtime.resolve_uvx(env={"PATH": str(binary.parent)}, home=self.root), str(binary))

    def test_user_local_install_is_discovered_without_path(self):
        binary = self._executable(self.root / ".local/bin/uvx")
        self.assertEqual(runtime.resolve_uvx(env={"PATH": ""}, home=self.root), str(binary))

    def test_uv_policy_matches_vendor_and_never_inherits_index_overrides(self):
        command = runtime.attach_command("uvx", 8001, 9501)
        self.assertIn("godot-ai==4.0.2", command)
        self.assertEqual(command[-4:], ["--port", "8001", "--ws-port", "9501"])
        source = (runtime.PROJECT / "addons/godot_ai/utils/uv_resolution_policy.gd").read_text()
        for option in runtime.UV_ARGS[:runtime.UV_ARGS.index("--link-mode")]:
            self.assertIn(option, source)
        env = runtime.launch_environment({"PATH": "safe", "UV_INDEX": "secret", "UV_INSECURE_HOST": "bad", "PYTHONPATH": "inject"})
        self.assertEqual(env, {"PATH": "safe", "PYTHONDONTWRITEBYTECODE": "1"})

    def test_invalid_or_equal_ports_are_rejected(self):
        for ports in [(0, 9500), (8000, 99999), (8000, 8000)]:
            with self.assertRaises(runtime.IntegrationError):
                runtime.attach_command("uvx", *ports)

    def test_doctor_requires_matching_ready_project_and_scrubs_unknown_fields(self):
        server = {"name": "godot-ai", "server_version": "4.0.2", "ws_port": 9500, "token": "secret"}
        session = {"project_path": str(self.project), "readiness": "ready", "plugin_version": "4.0.2", "token": "secret"}
        with patch.object(runtime.LocalMcpReader, "request", return_value=server), patch.object(runtime.LocalMcpReader, "sessions", return_value=[session]), patch.object(runtime, "read_capability", return_value=""):
            result = runtime.doctor(self.project, 8000, 9500)
        self.assertEqual(result["status"], "ready")
        self.assertNotIn("secret", json.dumps(result))
        self.assertFalse(result["tests_validated"])

    def test_doctor_rejects_old_server_and_empty_projects(self):
        server = {"name": "godot-ai", "server_version": "3.2.4", "ws_port": 9500}
        with patch.object(runtime.LocalMcpReader, "request", return_value=server), patch.object(runtime.LocalMcpReader, "sessions", return_value=[]), patch.object(runtime, "read_capability", return_value=""):
            result = runtime.doctor(self.project, 8000, 9500)
        self.assertEqual(result["status"], "failed")
        self.assertIn("server_version_mismatch", result["issues"])
        self.assertIn("project_session_missing", result["issues"])

    def test_doctor_does_not_accept_another_project_or_ws_port(self):
        server = {"name": "godot-ai", "server_version": "4.0.2", "ws_port": 9501}
        with patch.object(runtime.LocalMcpReader, "request", return_value=server), patch.object(runtime.LocalMcpReader, "sessions", return_value=[{"project_path": "/different", "readiness": "ready", "plugin_version": "4.0.2"}]), patch.object(runtime, "read_capability", return_value=""):
            result = runtime.doctor(self.project, 8000, 9500)
        self.assertIn("websocket_port_mismatch", result["issues"])
        self.assertIn("project_session_missing", result["issues"])

    def test_capability_rejects_wrong_permissions_malformed_and_links(self):
        folder = self.root / "private"
        folder.mkdir(mode=0o700)
        record = folder / "http-8000.json"
        record.write_text(json.dumps({"version": 1, "http": "a" * 64}))
        record.chmod(0o600)
        self.assertEqual(runtime.read_capability(record), "a" * 64)
        if os.name == "posix":
            record.chmod(0o644)
            with self.assertRaises(runtime.IntegrationError):
                runtime.read_capability(record)
            record.chmod(0o600)
        record.write_text("[]")
        with self.assertRaises(runtime.IntegrationError):
            runtime.read_capability(record)
        alias = folder / "linked.json"
        alias.symlink_to(record)
        with self.assertRaises(runtime.IntegrationError):
            runtime.read_capability(alias)

    def test_zero_tests_and_missing_counts_never_pass(self):
        for report in [self._report(total=0), self._report(assertions=0), {}, {"total": 0}, self._report(discovery_errors=1), self._report(failures=1), self._report(total=True), self._report(schema_version=True)]:
            self.assertEqual(runtime.assess_test_result(report, 0, "")["status"], "failed")

    def test_exit_and_engine_errors_override_green_json(self):
        for code, log in [(1, ""), (0, "SCRIPT ERROR: parse"), (0, "\x1b[31mERROR:\x1b[0m resource"), (0, "SHADER ERROR: source")]:
            self.assertEqual(runtime.assess_test_result(self._report(), code, log)["status"], "failed")
        self.assertEqual(runtime.assess_test_result(self._report(), 0, "ok script_error_test\nWARNING: optional")["status"], "passed")

    def test_bounded_process_uses_fresh_report_and_retains_evidence(self):
        script = f'''#!{sys.executable}
import json, pathlib, sys
path = pathlib.Path(sys.argv[sys.argv.index('--json') + 1])
path.write_text({json.dumps(json.dumps(self._report()))})
print('ok fixture')
'''
        executable = self._executable(self.root / "fake-godot", script)
        first = runtime.run_tests(self.project, str(executable), self.root / "evidence", "fixture", 3)
        second = runtime.run_tests(self.project, str(executable), self.root / "evidence", "fixture", 3)
        self.assertEqual(first["status"], "passed")
        self.assertNotEqual(first["report"], second["report"])
        self.assertTrue(Path(first["log"]).is_file())

    def test_bounded_process_timeout_is_failure(self):
        executable = self._executable(self.root / "fake-godot", f"#!{sys.executable}\nimport time\ntime.sleep(10)\n")
        result = runtime.run_tests(self.project, str(executable), self.root / "evidence", timeout=0.05)
        self.assertTrue(result["timed_out"])
        self.assertEqual(result["exit_code"], 124)
        self.assertEqual(result["status"], "failed")

    def test_cli_doctor_and_print_command_never_spawn(self):
        with patch.object(godot_mcp, "doctor", return_value={"status": "failed"}), patch.object(godot_mcp, "resolve_uvx", return_value="/uvx"), patch.object(godot_mcp.os, "execve") as spawn, redirect_stdout(io.StringIO()):
            self.assertEqual(godot_mcp.main(["--project", str(self.project), "--doctor"]), 1)
            self.assertEqual(godot_mcp.main(["--project", str(self.project), "--print-command"]), 0)
            spawn.assert_not_called()

    def test_cli_refuses_unbounded_doctor_timeout(self):
        with redirect_stderr(io.StringIO()):
            self.assertEqual(godot_mcp.main(["--project", str(self.project), "--doctor", "--timeout", "900"]), 1)

    def test_cached_uvx_is_fallback_without_path_or_standard_install(self):
        binary = self._executable(self.root / ".cache/uv/archive-v0/package/bin/uvx")
        with patch.object(runtime.os, "access", side_effect=lambda path, _mode: Path(path) == binary):
            self.assertEqual(runtime.resolve_uvx(env={"PATH": ""}, home=self.root), str(binary))

    def test_http_reader_uses_capability_and_sanitizes_error_body(self):
        connection = Mock()
        response = connection.getresponse.return_value
        response.status = 401
        response.read.return_value = b'{"secret":"must-not-leak"}'
        with patch.object(runtime.http.client, "HTTPConnection", return_value=connection):
            with self.assertRaises(runtime.IntegrationError) as failure:
                runtime.LocalMcpReader(8001, token="private-token").request("GET", "/godot-ai/status")
        self.assertNotIn("must-not-leak", str(failure.exception))
        self.assertEqual(connection.request.call_args.args[3]["Authorization"], "Bearer private-token")
        connection.close.assert_called_once()

    def test_mcp_sessions_accepts_json_and_cleans_only_its_http_session(self):
        reader = runtime.LocalMcpReader(8001)
        reader.session = "own-session"
        responses = [
            {"result": {"protocolVersion": "2025-03-26"}}, {},
            {"result": {"contents": [{"text": json.dumps({"sessions": [{"project_path": "/qix"}]})}]}}, {},
        ]
        with patch.object(reader, "request", side_effect=responses) as request:
            sessions = reader.sessions()
        self.assertEqual(sessions, [{"project_path": "/qix"}])
        self.assertEqual(request.call_args_list[-1].args, ("DELETE", "/mcp"))
        self.assertEqual(request.call_args_list[2].args[2]["params"], {"uri": "godot://sessions"})

    def test_http_reader_accepts_bounded_sse_json_rpc_frame(self):
        connection = Mock()
        response = connection.getresponse.return_value
        response.status = 200
        response.read.return_value = b'event: message\ndata: {"jsonrpc":"2.0","id":2,"result":{"contents":[]}}\n\n'
        response.getheader.side_effect = lambda name, default="": "text/event-stream" if name == "Content-Type" else default
        with patch.object(runtime.http.client, "HTTPConnection", return_value=connection):
            result = runtime.LocalMcpReader(8001).request("POST", "/mcp", {"id": 2})
        self.assertEqual(result["result"], {"contents": []})
        response.read.assert_called_once_with(runtime.MAX_RESPONSE_BYTES + 1)

    def test_doctor_authenticates_status_before_listing_sessions(self):
        seen = []
        def request(reader, _method, _path, _payload=None):
            seen.append(reader.token)
            return {"name": "godot-ai", "server_version": "4.0.2", "ws_port": 9501}
        with patch.object(runtime, "read_capability", return_value="private-token"), patch.object(runtime.LocalMcpReader, "request", request), patch.object(runtime.LocalMcpReader, "sessions", return_value=[]):
            result = runtime.doctor(self.project, 8001, 9501)
        self.assertEqual(seen, ["private-token"])
        self.assertNotIn("private-token", json.dumps(result))
        self.assertEqual(result["plugin_port_settings_scope"], "global_editor_settings")


if __name__ == "__main__":
    unittest.main()
