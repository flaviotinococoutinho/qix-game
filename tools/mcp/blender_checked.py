#!/usr/bin/env python3
"""Limite CLI: só publica stdout após Blender encerrar com sucesso.

O blmcp instalado interpreta marcadores sem conferir returncode. Este executável
é passado em BLENDER_PATH; não altera o pacote/vendor. Não instala dependências.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

RESULT = "__BLMCP_RESULT__"
ERROR = "__BLMCP_ERROR__"


def _interrupt(signum, _frame):
    # InterruptedError é consumido/repetido pelo seletor usado por communicate().
    raise RuntimeError(f"Blender CLI interrompido por sinal {signum}")


def _run_blender(command, timeout):
    # O grupo pertence somente a este job; nunca encerra o editor Blender aberto.
    # Windows mantém o fallback de encerramento do processo direto.
    previous_term = signal.signal(signal.SIGTERM, _interrupt)
    try:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, start_new_session=os.name == "posix",
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}) as process:
            try:
                stdout, stderr = process.communicate(timeout=timeout)
            except BaseException:
                try:
                    if os.name == "posix":
                        # Mesmo que Blender já tenha saído, filhos podem manter pipes abertos.
                        os.killpg(process.pid, signal.SIGKILL)
                    else:
                        process.kill()
                except ProcessLookupError:
                    pass
                process.wait()
                raise
            return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    finally:
        signal.signal(signal.SIGTERM, previous_term)


def main(argv=None):
    try:
        executable = os.environ.get("QIX_BLENDER_EXECUTABLE", "")
        if not executable or Path(executable).resolve() == Path(__file__).resolve():
            raise ValueError("QIX_BLENDER_EXECUTABLE exige o Blender real, sem recursão")
        timeout = float(os.environ.get("QIX_BLENDER_CLI_TIMEOUT", "90"))
        if not 0 < timeout <= 105:
            raise ValueError("QIX_BLENDER_CLI_TIMEOUT deve estar entre 0 e 105 segundos")
        result = _run_blender([executable, *(sys.argv[1:] if argv is None else argv)], timeout)
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
