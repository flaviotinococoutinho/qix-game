#!/usr/bin/env python3
"""Launcher MCP portátil. Sem flags inicia stdio; --doctor inspeciona instalação."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

from blender_runtime import RuntimeUnavailable, checked_environment, resolve_runtime


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--doctor", action="store_true")
    mode.add_argument("--discover", action="store_true")
    parser.add_argument("--python", help="Python existente com mcp+blmcp; ou QIX_BLENDER_MCP_PYTHON")
    parser.add_argument("--blender", help="Executável existente; ou BLENDER_PATH")
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--receipt", help="Recibo para --discover")
    args = parser.parse_args(argv)
    try:
        runtime = resolve_runtime(args.python, args.blender)
        env = checked_environment(runtime, args.timeout)
        if args.doctor:
            print(json.dumps({"status": "ok", "runtime": runtime, "installs_performed": 0,
                "guard": env["BLENDER_PATH"], "cli_timeout_seconds": args.timeout}, indent=2))
            return 0
        if args.discover:
            command = [runtime["python"], "-B", str(Path(__file__).resolve().parents[1] / "assets/blender_mcp_job.py"),
                "--python", runtime["python"], "--blender", runtime["blender"], "--timeout", str(args.timeout)]
            if args.receipt:
                command.extend(["--receipt", args.receipt])
            return subprocess.run(command, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}).returncode
        os.execve(runtime["python"], [runtime["python"], "-B", "-m", "blmcp"], env)
    except (RuntimeUnavailable, OSError, ValueError) as error:
        print(f"Blender MCP: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
