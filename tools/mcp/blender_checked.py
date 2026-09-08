#!/usr/bin/env python3
"""Limite CLI: só publica stdout após Blender encerrar com sucesso.

O blmcp instalado interpreta marcadores sem conferir returncode. Este executável
é passado em BLENDER_PATH; não altera o pacote/vendor. Não instala dependências.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

RESULT = "__BLMCP_RESULT__"
ERROR = "__BLMCP_ERROR__"


def main(argv=None):
    try:
        executable = os.environ.get("QIX_BLENDER_EXECUTABLE", "")
        if not executable or Path(executable).resolve() == Path(__file__).resolve():
            raise ValueError("QIX_BLENDER_EXECUTABLE exige o Blender real, sem recursão")
        timeout = float(os.environ.get("QIX_BLENDER_CLI_TIMEOUT", "90"))
        if not 0 < timeout <= 105:
            raise ValueError("QIX_BLENDER_CLI_TIMEOUT deve estar entre 0 e 105 segundos")
        result = subprocess.run([executable, *(sys.argv[1:] if argv is None else argv)],
            capture_output=True, text=True, timeout=timeout,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        if result.returncode != 0:
            raise RuntimeError(f"Blender encerrou com código {result.returncode}: {result.stderr[-2000:]}")
        markers = [line for line in result.stdout.splitlines()
            if line.startswith(RESULT) or line.startswith(ERROR)]
        if len(markers) > 1:
            raise RuntimeError("Blender devolveu múltiplos marcadores; resultado ambíguo")
        if markers and markers[0].startswith(ERROR):
            raise RuntimeError("Blender reportou erro interno: " + markers[0][len(ERROR):][:2000])
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(ERROR + json.dumps(str(error), ensure_ascii=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
