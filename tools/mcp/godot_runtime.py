"""Contratos locais do Godot AI; nenhuma função inicia editor, importa assets ou altera o addon."""
from __future__ import annotations

import configparser
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from typing import Mapping

VERSION = "4.0.2"
HTTP_PORT = 8001
WS_PORT = 9501
PROJECT = Path(__file__).resolve().parents[2]
UV_ARGS = (
    "--isolated", "--no-config", "--no-env-file", "--no-sources", "--no-build",
    "--index-strategy", "first-index", "--keyring-provider", "disabled",
    "--index", "https://pypi.org/simple", "--default-index", "https://pypi.org/simple",
    "--find-links", "https://pypi.org/simple/godot-ai/", "--link-mode", "copy",
    "--from", f"godot-ai=={VERSION}", "godot-ai", "attach",
)
MAX_RESPONSE_BYTES = 262144
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ENGINE_ERROR = re.compile(r"^\s*(?:(?:SCRIPT|SHADER|USER) )?ERROR:", re.MULTILINE)


class IntegrationError(RuntimeError):
    """Mensagem pública sem material de autenticação ou corpos HTTP."""


def validate_port(port: int) -> int:
    if isinstance(port, bool) or not 1024 <= port <= 65535:
        raise IntegrationError("porta deve estar entre 1024 e 65535")
    return port


def resolve_uvx(explicit: str | None = None, *, env: Mapping[str, str] | None = None,
                home: Path | None = None) -> str:
    """Resolve executável existente; não instala e não seleciona pacote Python não fixado."""
    env = os.environ if env is None else env
    home = Path.home() if home is None else home
    override = explicit or env.get("QIX_GODOT_UVX")
    if override:
        candidate = shutil.which(override, path=env.get("PATH", ""))
        if candidate and Path(candidate).is_file():
            return str(Path(candidate).resolve())
        raise IntegrationError("QIX_GODOT_UVX/--uvx não aponta para um executável existente")
    found = shutil.which("uvx", path=env.get("PATH", ""))
    candidates = [Path(found)] if found else []
    candidates += [home / ".local/bin/uvx", home / ".cargo/bin/uvx",
                   Path("/opt/homebrew/bin/uvx"), Path("/usr/local/bin/uvx")]
    # Instalações uv de usuário/cache são fallback; PATH e a opção explícita têm prioridade.
    for base in (home / ".cache/uv", home / "Library/Caches/uv"):
        candidates += [base / "tools/uv/bin/uvx", base / "tools/uv/Scripts/uvx.exe"]
        archive = base / "archive-v0"
        if archive.is_dir():
            candidates += sorted(archive.glob("*/bin/uvx"))[:128]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate.resolve())
    raise IntegrationError("uvx não encontrado; configure QIX_GODOT_UVX com uma instalação existente")


def attach_command(uvx: str, port: int, ws_port: int) -> list[str]:
    validate_port(port)
    validate_port(ws_port)
    if port == ws_port:
        raise IntegrationError("HTTP e WebSocket precisam de portas distintas")
    return [uvx, *UV_ARGS, "--port", str(port), "--ws-port", str(ws_port)]


def launch_environment(env: Mapping[str, str] | None = None) -> dict[str, str]:
    source = os.environ if env is None else env
    # Overrides de resolução não podem contornar a origem e versão fixadas acima.
    result = {key: value for key, value in source.items()
              if not key.startswith("UV_") and key not in ("PYTHONPATH", "PYTHONHOME")}
    result["PYTHONDONTWRITEBYTECODE"] = "1"
    return result


def plugin_version(project: Path) -> str:
    config = configparser.ConfigParser()
    try:
        config.read(project / "addons/godot_ai/plugin.cfg", encoding="utf-8")
    except configparser.Error:
        raise IntegrationError("plugin.cfg inválido") from None
    return config.get("plugin", "version", fallback="").strip('"')


def capability_path(port: int) -> Path:
    if os.environ.get("GODOT_AI_CAPABILITY_DIR") and os.name != "nt":
        directory = Path(os.environ["GODOT_AI_CAPABILITY_DIR"])
    elif sys.platform == "darwin":
        directory = Path.home() / "Library/Application Support/godot-ai/capabilities"
    elif os.name == "nt":
        directory = Path(os.environ.get("LOCALAPPDATA", "")) / "godot-ai/capabilities"
    else:
        directory = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "godot-ai/capabilities"
    return directory / f"http-{port}.json"


def read_capability(path: Path) -> str:
    """Lê só a credencial HTTP local privada; jamais a inclui em relatório/argv."""
    if not path.exists():
        return ""
    if not path.is_absolute() or any(part.is_symlink() for part in (path, *path.parents)):
        raise IntegrationError("registro de capability deve ser local, absoluto e sem links")
    if os.name != "nt":
        for item in (path, path.parent):
            info = item.stat()
            if info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise IntegrationError("registro de capability não tem proprietário/permissões privados")
    if not path.is_file() or path.stat().st_size > 1024:
        raise IntegrationError("registro de capability inválido")
    try:
        record = json.loads(path.read_text(encoding="ascii"))
    except (ValueError, UnicodeError):
        raise IntegrationError("registro de capability inválido") from None
    if not isinstance(record, dict):
        raise IntegrationError("registro de capability inválido")
    token = record.get("http", "")
    if record.get("version") != 1 or not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9+./=_~-]{32,128}", token):
        raise IntegrationError("registro de capability inválido")
    return token


class LocalMcpReader:
    """Cliente HTTP somente leitura, sem redirects, limitado a loopback e payloads pequenos."""
    def __init__(self, port: int, timeout: float = 4.0, token: str = ""):
        self.port = validate_port(port)
        self.timeout = timeout
        self.token = token
        self.session = ""
        self.protocol = "2025-03-26"

    def request(self, method: str, path: str, payload: dict | None = None) -> dict:
        headers = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        if self.session:
            headers["Mcp-Session-Id"] = self.session
            headers["MCP-Protocol-Version"] = self.protocol
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=self.timeout)
        try:
            connection.request(method, path, json.dumps(payload) if payload is not None else None, headers)
            response = connection.getresponse()
            if not 200 <= response.status < 300:
                raise IntegrationError(f"endpoint local respondeu HTTP {response.status}")
            self.session = response.getheader("Mcp-Session-Id", self.session)
            body = response.read(MAX_RESPONSE_BYTES + 1)
            if len(body) > MAX_RESPONSE_BYTES:
                raise IntegrationError("resposta de diagnóstico excedeu o limite")
            if not body:
                return {}
            text = body.decode("utf-8")
            if "text/event-stream" in response.getheader("Content-Type", ""):
                frames = [line[5:].strip() for line in text.splitlines() if line.startswith("data:")]
                values = [json.loads(frame) for frame in frames]
                value = next((item for item in values if isinstance(item, dict) and item.get("id") == (payload or {}).get("id")), {})
            else:
                value = json.loads(text)
            if not isinstance(value, dict) or "error" in value:
                raise IntegrationError("resposta de diagnóstico não concluiu a operação")
            return value
        except (OSError, ValueError, http.client.HTTPException):
            raise IntegrationError("endpoint de diagnóstico indisponível ou resposta inválida") from None
        finally:
            connection.close()

    def sessions(self) -> list[dict]:
        try:
            init = self.request("POST", "/mcp", {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": self.protocol, "capabilities": {}, "clientInfo": {"name": "qix-doctor", "version": "1"}}})
            self.protocol = init.get("result", {}).get("protocolVersion", self.protocol)
            self.request("POST", "/mcp", {"jsonrpc": "2.0", "method": "notifications/initialized"})
            result = self.request("POST", "/mcp", {"jsonrpc": "2.0", "id": 2, "method": "resources/read", "params": {"uri": "godot://sessions"}})
            for item in result.get("result", {}).get("contents", []):
                data = json.loads(item.get("text", "{}"))
                if isinstance(data, dict) and isinstance(data.get("sessions"), list):
                    return data["sessions"]
            raise IntegrationError("servidor não devolveu uma listagem de projetos válida")
        except (ValueError, TypeError, AttributeError):
            raise IntegrationError("listagem de projetos inválida") from None
        finally:
            if self.session:
                try:
                    self.request("DELETE", "/mcp")
                except IntegrationError:
                    pass


def doctor(project: Path, port: int, ws_port: int, timeout: float = 4.0) -> dict:
    result = {"status": "failed", "expected_version": VERSION, "plugin_version": plugin_version(project),
              "endpoint": f"http://127.0.0.1:{validate_port(port)}", "expected_ws_port": validate_port(ws_port),
              "projects": [], "issues": [], "tests_validated": False,
              "plugin_port_settings_scope": "global_editor_settings",
              "plugin_port_settings": ["godot_ai/http_port", "godot_ai/ws_port"]}
    reader = LocalMcpReader(port, timeout)
    try:
        # v4 autentica também o endpoint de status, usando o registro privado oficial.
        reader.token = read_capability(capability_path(port))
        status = reader.request("GET", "/godot-ai/status")
        result["server"] = {key: status.get(key) for key in
                            ("name", "server_version", "ws_port", "owner_type", "active_lease_count")}
        if status.get("name") != "godot-ai" or status.get("server_version") != VERSION:
            result["issues"].append("server_version_mismatch")
        if status.get("ws_port") != ws_port:
            result["issues"].append("websocket_port_mismatch")
        sessions = reader.sessions()
        for session in sessions:
            if isinstance(session, dict):
                result["projects"].append({key: session.get(key) for key in
                    ("name", "project_path", "plugin_version", "godot_version", "readiness", "play_state")})
        matching = [s for s in result["projects"] if s.get("project_path") and isinstance(s["project_path"], str) and Path(s["project_path"]).resolve() == project.resolve()]
        if not matching:
            result["issues"].append("project_session_missing")
        elif not any(s.get("readiness") == "ready" and s.get("plugin_version") == VERSION for s in matching):
            result["issues"].append("project_session_not_ready_or_incompatible")
    except IntegrationError as error:
        result["issues"].append(str(error))
    if result["plugin_version"] != VERSION:
        result["issues"].append("plugin_version_mismatch")
    if not result["issues"]:
        result["status"] = "ready"
    return result


def assess_test_result(report: dict, exit_code: int, log: str) -> dict:
    """Um resultado sem testes/asserções ou com erro de engine nunca vira aprovação."""
    errors = ENGINE_ERROR.findall(ANSI.sub("", log))
    required = ("total", "assertions", "failures", "discovery_errors")
    valid = isinstance(report, dict) and type(report.get("schema_version")) is int and report.get("schema_version") == 1 and all(
        type(report.get(key)) is int and report[key] >= 0 for key in required)
    passed = valid and exit_code == 0 and report["total"] > 0 and report["assertions"] > 0 and report["failures"] == 0 and report["discovery_errors"] == 0 and not errors
    return {"status": "passed" if passed else "failed", "exit_code": exit_code,
            "valid_report": valid, "engine_errors": len(errors),
            "summary": {key: report.get(key) for key in required} if isinstance(report, dict) else {}}


def run_tests(project: Path, godot: str, output: Path, test_filter: str = "", timeout: float = 300) -> dict:
    """Executa só a suíte explícita, sem import; limita processo e conserva logs fora do projeto."""
    project, output = project.resolve(), output.resolve()
    if output == project or project in output.parents:
        raise IntegrationError("diretório de evidência deve ficar fora do projeto Godot")
    if not 0 < timeout <= 900:
        raise IntegrationError("timeout deve estar entre 0 e 900 segundos")
    executable = shutil.which(godot)
    if not executable:
        raise IntegrationError("executável Godot não encontrado")
    output.mkdir(parents=True, exist_ok=True)
    # Uma pasta exclusiva impede reaproveitar JSON de uma execução anterior.
    run_dir = Path(tempfile.mkdtemp(prefix="qix-tests-", dir=output))
    report_path, log_path = run_dir / "tests.json", run_dir / "godot.log"
    command = [executable, "--headless", "--audio-driver", "Dummy", "--path", str(project),
               "--script", "res://tests/run_tests.gd", "--"]
    if test_filter:
        command.append(test_filter)
    command += ["--json", str(report_path)]
    with log_path.open("w", encoding="utf-8") as log_file:
        process = subprocess.Popen(command, cwd=project, stdout=log_file, stderr=subprocess.STDOUT,
                                   env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}, start_new_session=os.name == "posix")
        timed_out = False
        try:
            exit_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
            process.wait()
            exit_code = 124
        except BaseException:
            # Interromper o wrapper também recolhe apenas o processo/grupo que ele criou.
            if process.poll() is None:
                if os.name == "posix":
                    os.killpg(process.pid, signal.SIGKILL)
                else:
                    process.kill()
                process.wait()
            raise
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        report = {}
    assessment = assess_test_result(report, exit_code, log_path.read_text(encoding="utf-8", errors="replace"))
    assessment.update({"timed_out": timed_out, "log": str(log_path), "report": str(report_path),
                       "scope": "qix_headless_suite", "mcp_editor_validated": False})
    (run_dir / "assessment.json").write_text(json.dumps(assessment, indent=2) + "\n", encoding="utf-8")
    return assessment
