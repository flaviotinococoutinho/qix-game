"""Descoberta de instalação existente; somente stdlib, sem instalação implícita."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent


class RuntimeUnavailable(RuntimeError):
    pass


def executable_path(value, env):
    path = Path(value).expanduser()
    # Não resolve symlinks do Python: isso perderia o pyvenv.cfg do ambiente.
    found = str(path.absolute()) if path.is_file() else shutil.which(value, path=env.get("PATH", ""))
    if not found or not os.access(found, os.X_OK):
        raise RuntimeUnavailable(f"Executável não encontrado ou sem permissão: {value}")
    return found


def probe_python(value, env):
    executable = executable_path(value, env)
    code = ("import importlib.util,importlib.metadata,json,sys; "
        "assert importlib.util.find_spec('mcp') and importlib.util.find_spec('blmcp'); "
        "print(json.dumps({'python_version':sys.version.split()[0],"
        "'mcp_version':importlib.metadata.version('mcp'),"
        "'blmcp_version':importlib.metadata.version('blender-mcp')}))")
    result = subprocess.run([executable, "-B", "-c", code], capture_output=True,
        text=True, timeout=8, env={**env, "PYTHONDONTWRITEBYTECODE": "1"})
    if result.returncode:
        raise RuntimeUnavailable(f"Python não contém mcp e blmcp utilizáveis: {executable}")
    return {"python": executable, **json.loads(result.stdout)}


def resolve_runtime(python=None, blender=None, env=None):
    env = dict(os.environ if env is None else env)
    explicit_python = python or env.get("QIX_BLENDER_MCP_PYTHON")
    home = Path.home()
    candidates = [explicit_python] if explicit_python else [sys.executable,
        str(home / "Library/Application Support/Claude/Claude Extensions/ant.dir.gh.blender.blender-mcp/.venv/bin/python3")]
    info = None
    failures = []
    for candidate in dict.fromkeys(candidates):
        try:
            info = probe_python(candidate, env)
            break
        except (RuntimeUnavailable, OSError, ValueError, subprocess.TimeoutExpired) as error:
            failures.append(str(error))
    if info is None:
        raise RuntimeUnavailable("QIX_BLENDER_MCP_PYTHON/--python não aponta para um ambiente existente com mcp+blmcp. "
            + " | ".join(failures) + ". Nenhuma instalação foi executada.")
    explicit_blender = blender or env.get("BLENDER_PATH")
    candidates = [explicit_blender] if explicit_blender else ["blender-godot", "blender",
        "/Applications/Blender.app/Contents/MacOS/Blender"]
    failures = []
    for candidate in candidates:
        try:
            binary = executable_path(candidate, env)
            if Path(binary).resolve() == (HERE / "blender_checked.py").resolve():
                raise RuntimeUnavailable("BLENDER_PATH deve indicar Blender real, não o guard do projeto")
            result = subprocess.run([binary, "--version"], capture_output=True, text=True,
                timeout=8, env={**env, "PYTHONDONTWRITEBYTECODE": "1"})
            first_line = result.stdout.splitlines()[0] if result.stdout else ""
            if result.returncode or not first_line.startswith("Blender "):
                raise RuntimeUnavailable(f"Executável não respondeu como Blender: {binary}")
            return {**info, "blender": binary, "blender_version": first_line}
        except (RuntimeUnavailable, OSError, subprocess.TimeoutExpired) as error:
            failures.append(str(error))
    raise RuntimeUnavailable("BLENDER_PATH/--blender não aponta para Blender existente. "
        + " | ".join(failures) + ". Nenhuma instalação foi executada.")


def checked_environment(runtime, timeout=90, env=None):
    if not 0 < timeout <= 105:
        raise ValueError("Timeout CLI deve estar entre 0 e 105 segundos (limite MCP: 120)")
    result = dict(os.environ if env is None else env)
    result.update({"PYTHONDONTWRITEBYTECODE": "1",
        "BLENDER_PATH": str(HERE / "blender_checked.py"),
        "QIX_BLENDER_EXECUTABLE": runtime["blender"],
        "QIX_BLENDER_CLI_TIMEOUT": str(timeout),
        "PATH": str(Path(runtime["python"]).parent) + os.pathsep + result.get("PATH", "")})
    return result
