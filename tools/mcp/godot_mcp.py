#!/usr/bin/env python3
"""Godot AI portátil: stdio por padrão; --doctor só lê; --test executa a suíte QIX explícita."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

from godot_runtime import (HTTP_PORT, WS_PORT, PROJECT, IntegrationError, attach_command,
                           doctor, launch_environment, plugin_version, resolve_uvx, run_tests, VERSION)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--doctor", action="store_true")
    mode.add_argument("--print-command", action="store_true", help="mostra argv sem iniciar servidor")
    mode.add_argument("--test", action="store_true", help="executa somente o runner de testes do projeto")
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--port", type=int, default=HTTP_PORT)
    parser.add_argument("--ws-port", type=int, default=WS_PORT)
    parser.add_argument("--uvx", help="executável uvx existente; alternativa: QIX_GODOT_UVX")
    parser.add_argument("--godot", default=os.environ.get("QIX_GODOT_BIN", "godot"))
    parser.add_argument("--filter", default="")
    parser.add_argument("--output", type=Path, help="diretório externo ao projeto para evidência de --test")
    parser.add_argument("--timeout", type=float, help="doctor: 4 segundos por requisição; teste: 300 segundos")
    args = parser.parse_args(argv)
    try:
        project = args.project.resolve()
        if not (project / "project.godot").is_file():
            raise IntegrationError("--project deve apontar para o projeto Godot")
        if args.timeout is not None and not 0 < args.timeout <= 900:
            raise IntegrationError("timeout deve estar entre 0 e 900 segundos")
        if args.doctor:
            if args.timeout is not None and args.timeout > 10:
                raise IntegrationError("doctor aceita no máximo 10 segundos por requisição")
            result = doctor(project, args.port, args.ws_port, args.timeout or 4)
            print(json.dumps(result, indent=2, ensure_ascii=False))
            return 0 if result["status"] == "ready" else 1
        if args.test:
            if args.output is None:
                raise IntegrationError("--test requer --output para reter evidência fora do projeto")
            result = run_tests(project, args.godot, args.output, args.filter, args.timeout or 300)
            print(json.dumps(result, indent=2, ensure_ascii=False))
            return 0 if result["status"] == "passed" else 1
        if plugin_version(project) != VERSION:
            raise IntegrationError("versão do plugin difere da versão fixada no launcher")
        command = attach_command(resolve_uvx(args.uvx), args.port, args.ws_port)
        if args.print_command:
            print(json.dumps(command, indent=2))
            return 0
        # stdout pertence exclusivamente ao MCP. Toda orientação usa stderr.
        os.chdir(project)
        os.execve(command[0], command, launch_environment())
    except (IntegrationError, OSError) as error:
        print(f"Godot MCP: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
