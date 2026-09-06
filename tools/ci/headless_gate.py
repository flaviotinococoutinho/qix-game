#!/usr/bin/env python3
"""Run Godot headless checks with fail-closed diagnostics and retained evidence.

The optional native Fennara editor extension is isolated only with an explicit
flag. Its GDScript runtime helper stays present. This is not native-addon QA.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Iterator, Sequence

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DIAGNOSTIC = re.compile(r"^\s*(?:(?:SCRIPT|SHADER|USER) )?ERROR:", re.MULTILINE)


def error_lines(text: str) -> list[str]:
    """Do not confuse test names, JSON 'errors': [], or warnings with errors."""
    return [line for line in ANSI.sub("", text).splitlines() if DIAGNOSTIC.match(line)]


def run_checked(command: Sequence[str], log: Path, *, cwd: Path) -> dict:
    """Keep the exit code AND inspect stderr/stdout: Godot can log errors then exit 0."""
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(list(command), cwd=cwd, stdout=output,
                                stderr=subprocess.STDOUT, check=False, timeout=300)
    text = log.read_text(encoding="utf-8", errors="replace")
    errors = error_lines(text)
    print(f"{log.name}: exit={result.returncode}, engine_errors={len(errors)}", flush=True)
    # Full import/suite output lives in artifacts; keep the console readable.
    print("\n".join(text.splitlines()[-24:]), flush=True)
    if result.returncode != 0 or errors:
        for line in errors:
            print(line, file=sys.stderr)
        raise RuntimeError(f"headless check failed: {log.name} (see complete log)")
    return {"log": log.name, "exit_code": result.returncode, "engine_errors": len(errors)}


@contextmanager
def optional_editor_extension(project: Path, enabled: bool) -> Iterator[bool]:
    """Temporarily hide the unavailable Linux-editor descriptor; always restore it."""
    descriptor = project / "addons/fennara/fennara.gdextension"
    library = project / "addons/fennara/bin/libfennara.linux.editor.x86_64.so"
    backup = descriptor.with_suffix(".gdextension.ci-disabled")
    if not enabled or library.is_file():
        yield False
        return
    if not descriptor.is_file():
        raise RuntimeError(f"expected optional extension descriptor is missing: {descriptor}")
    if backup.exists():
        raise RuntimeError(f"refusing to overwrite an existing extension backup: {backup}")
    # Fresh CI checkouts have no extension list. Refuse an old registered cache rather
    # than editing somebody's local cache or giving a misleading clean result.
    registry = project / ".godot/extension_list.cfg"
    if registry.exists() and "fennara.gdextension" in registry.read_text(encoding="utf-8"):
        raise RuntimeError("use a fresh checkout for optional native-editor isolation")
    descriptor.rename(backup)
    try:
        print("CI scope: missing Fennara native editor library isolated; runtime scripts retained.", flush=True)
        yield True
    finally:
        backup.rename(descriptor)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--logs", type=Path, required=True)
    parser.add_argument("--isolate-missing-editor-extension", action="store_true")
    args = parser.parse_args(argv)
    project = args.project.resolve()
    logs = args.logs.resolve()
    # Logs must not become imported project assets.
    if logs == project or project in logs.parents:
        parser.error("--logs must be outside the Godot project")
    logs.mkdir(parents=True, exist_ok=True)
    manifest = {"status": "running", "checks": [], "native_editor_qa": False}
    try:
        for name, revision in (("commit", "HEAD"), ("tree", "HEAD^{tree}")):
            manifest[name] = subprocess.check_output(
                ["git", "rev-parse", revision], cwd=project, text=True).strip()
        godot = str(Path(args.godot).expanduser().resolve())
        version = subprocess.check_output([godot, "--version"], text=True).strip()
        if not version.startswith("4.7.2.stable.official"):
            raise RuntimeError(f"wrong Godot engine: {version}")
        manifest["engine"] = version
        base = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(project)]
        with optional_editor_extension(project, args.isolate_missing_editor_extension) as isolated:
            manifest["optional_editor_extension_isolated"] = isolated
            checks = [("import", ["--import"]),
                      ("suite", ["--script", "res://tests/run_tests.gd"]),
                      ("m2", ["--script", "res://tools/verify_m2_capture_route.gd"]),
                      ("hud-geometry", ["--script", "res://tools/verify_hud_row_geometry.gd"])]
            for name, options in checks:
                manifest["checks"].append(run_checked(base + options, logs / f"{name}.log", cwd=project))
        manifest["status"] = "passed"
        return 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        manifest["status"] = "failed"
        manifest["error"] = str(error)
        print(f"::error::{error}", file=sys.stderr)
        return 1
    finally:
        (logs / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(manifest, indent=2), flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
