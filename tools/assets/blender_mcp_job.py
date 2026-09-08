#!/usr/bin/env python3
"""Discovery ou job MCP com instalação existente, recibo e artefatos verificados."""
import argparse
import asyncio
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "mcp"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from blender_runtime import checked_environment, resolve_runtime
from validate_lumen_models import inspect_glb, validate_manifest


def file_evidence(path):
    data = path.read_bytes()
    return {"path": str(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def artifact_evidence(path):
    evidence = file_evidence(path)
    if evidence["bytes"] == 0:
        raise ValueError(f"Artefato esperado vazio: {path}")
    if path.suffix == ".blend" and not path.read_bytes().startswith(b"BLENDER"):
        raise ValueError(f"Artefato .blend sem cabeçalho Blender: {path}")
    if path.suffix == ".glb":
        evidence["glb_validation"] = inspect_glb(path.read_bytes())
    return evidence


def write_receipt(path, payload):
    if not path:
        return
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                prefix=path.name + ".", suffix=".tmp", delete=False) as output:
            temporary = Path(output.name)
            json.dump(payload, output, indent=2, ensure_ascii=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def job_result(payload):
    if not isinstance(payload, dict) or payload.get("isError") is not False:
        raise ValueError("MCP reportou erro ou não confirmou isError=false")
    result = payload.get("structuredContent")
    if result is None:
        texts = [entry.get("text", "") for entry in payload.get("content", [])
            if isinstance(entry, dict) and entry.get("type") == "text"]
        if len(texts) != 1:
            raise ValueError("MCP não devolveu resultado estruturado único")
        result = json.loads(texts[0])
    if not isinstance(result, dict) or not result:
        raise ValueError("Resultado de job ausente ou inválido")
    if "status" in result and result["status"] not in ("ok", "success"):
        raise ValueError("Job reportou erro interno: " + str(result.get("message", result["status"])))
    if result.get("error"):
        raise ValueError("Job reportou erro interno: " + str(result["error"]))
    return result


async def run(args, runtime):
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client

    env = checked_environment(runtime, args.timeout)
    env["QIX_PROJECT_ROOT"] = str(args.project_root)
    server = StdioServerParameters(command=runtime["python"], args=["-B", "-m", "blmcp"], env=env)
    async with asyncio.timeout(args.timeout + 15):
        async with stdio_client(server) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                if not args.code:
                    result = await session.list_tools()
                else:
                    result = await session.call_tool("execute_blender_code_for_cli", {
                        "blend_file": str(args.blend), "code": args.code.read_text()})
                return result.model_dump(mode="json")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python", help="Python existente com mcp+blmcp; ou QIX_BLENDER_MCP_PYTHON")
    parser.add_argument("--blender", help="Blender existente; ou BLENDER_PATH")
    parser.add_argument("--blend", type=Path)
    parser.add_argument("--code", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--expect-artifact", type=Path, action="append", default=[],
        help="Arquivo que o job precisa criar ou regravar, contido no projeto")
    args = parser.parse_args(argv)
    receipt = {"schema_version": 1, "run_id": str(uuid.uuid4()), "status": "failed", "phase": "preflight",
        "operation": "execute_blender_code_for_cli" if args.code else "list_tools",
        "started_at": datetime.now(timezone.utc).isoformat(), "installs_performed": 0}
    try:
        protected = [args.code, args.blend, *args.expect_artifact,
            args.project_root / "project.godot", args.project_root / "assets/models/lumen/manifest.json"]
        if args.receipt and args.receipt.resolve() in {path.resolve() for path in protected if path}:
            args.receipt = None
            raise ValueError("Recibo não pode sobrescrever entrada ou artefato do projeto")
        # Recibo antigo não pode continuar dizendo sucesso se este processo falhar.
        write_receipt(args.receipt, receipt)
        args.project_root = args.project_root.resolve()
        if not (args.project_root / "project.godot").is_file():
            raise ValueError("--project-root não contém project.godot")
        if args.code:
            if not args.blend:
                raise ValueError("--code exige --blend existente")
            args.code, args.blend = args.code.resolve(), args.blend.resolve()
            if args.blend.suffix != ".blend":
                raise ValueError("--blend exige arquivo .blend")
            receipt["input"] = {"script": file_evidence(args.code), "blend": file_evidence(args.blend)}
            receipt["input"]["blend_hash_scope"] = "disk_before_call"
            receipt["input"]["live_snapshot_possible"] = True
        elif args.expect_artifact:
            raise ValueError("--expect-artifact exige --code")
        artifacts_before = {}
        for artifact in args.expect_artifact:
            path = artifact.resolve()
            if not path.is_relative_to(args.project_root):
                raise ValueError("Artefato esperado fora do projeto")
            artifacts_before[path] = path.stat().st_mtime_ns if path.exists() else None
        runtime = resolve_runtime(args.python, args.blender)
        checked_environment(runtime, args.timeout)
        receipt["runtime"] = runtime
        if Path(sys.executable).absolute() != Path(runtime["python"]).absolute():
            command = [runtime["python"], "-B", str(Path(__file__).resolve()), *(sys.argv[1:] if argv is None else argv)]
            return subprocess.run(command, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                timeout=args.timeout + 35).returncode
        receipt["phase"] = "mcp"
        write_receipt(args.receipt, receipt)
        payload = asyncio.run(run(args, runtime))
        receipt["response"] = payload
        receipt["phase"] = "validate"
        if args.code:
            result = job_result(payload)
            checks = []
            if "assets" in result:
                checks.append(validate_manifest(result, args.project_root))
            for path, previous_mtime in artifacts_before.items():
                if not path.is_file() or path.stat().st_mtime_ns == previous_mtime:
                    raise ValueError(f"Job não criou/regravou artefato esperado: {path}")
                checks.append(artifact_evidence(path))
            if not checks:
                raise ValueError("Job sem artefato verificável: forneça --expect-artifact ou manifesto Lumen")
            receipt["artifact_validation"] = checks
        else:
            names = [tool.get("name") for tool in payload.get("tools", []) if isinstance(tool, dict)]
            if "execute_blender_code_for_cli" not in names:
                raise ValueError("Discovery não encontrou execute_blender_code_for_cli")
            receipt["tools"] = names
        receipt.update({"status": "ok", "phase": "complete"})
    except Exception as error:
        receipt["error"] = str(error)[:4000] or type(error).__name__
    receipt["finished_at"] = datetime.now(timezone.utc).isoformat()
    try:
        write_receipt(args.receipt, receipt)
    except OSError as error:
        receipt.update({"status": "failed", "error": f"Falha ao gravar recibo: {error}"})
    print(json.dumps(receipt, indent=2, ensure_ascii=True))
    return 0 if receipt["status"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
