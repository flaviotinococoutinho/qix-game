#!/usr/bin/env python3
"""Executa um job local pelo MCP oficial já instalado do Blender e guarda o recibo.

Usar o Python do ambiente que já contém `mcp` e `blmcp`. Nenhuma instalação,
credencial ou alteração da configuração global é feita por este script.
"""
import argparse
import asyncio
import json
import os
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def run(args):
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["BLENDER_PATH"] = args.blender
    server = StdioServerParameters(command=sys.executable, args=["-m", "blmcp"], env=env)
    async with stdio_client(server) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            if not args.code:
                result = await session.list_tools()
            else:
                result = await session.call_tool("execute_blender_code_for_cli", {
                    "blend_file": str(Path(args.blend).resolve()),
                    "code": Path(args.code).read_text(),
                })
            payload = result.model_dump(mode="json")
            if args.receipt:
                Path(args.receipt).parent.mkdir(parents=True, exist_ok=True)
                Path(args.receipt).write_text(json.dumps(payload, indent=2) + "\n")
            print(json.dumps(payload, indent=2))
            if payload.get("isError"):
                raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", required=True)
    parser.add_argument("--blend")
    parser.add_argument("--code")
    parser.add_argument("--receipt")
    args = parser.parse_args()
    if args.code and not args.blend:
        parser.error("--code exige --blend")
    asyncio.run(run(args))
