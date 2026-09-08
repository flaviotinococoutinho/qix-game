#!/usr/bin/env python3
"""Run Godot headless checks with fail-closed diagnostics and retained evidence.

The optional native Fennara editor extension is isolated only with an explicit
flag. Its GDScript runtime helper stays present. This is not native-addon QA.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import Iterator, Sequence

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DIAGNOSTIC = re.compile(r"^\s*(?:(?:SCRIPT|SHADER|USER) )?ERROR:", re.MULTILINE)
NATIVE_PANIC = re.compile(r"^\s*thread '[^']+'(?: \(\d+\))? panicked at ")
ENGINE_VERSION = re.compile(r"4\.7\.2\.stable(?P<mono>\.mono)?\.official(?:\.[0-9a-f]{9})?")


def verified_engine_version(version: str) -> dict:
    """Aceita somente as duas variantes oficiais da versão contratada."""
    match = ENGINE_VERSION.fullmatch(version)
    if not match:
        raise RuntimeError(f"wrong Godot engine: {version}")
    return {"version": version, "variant": "mono" if match["mono"] else "standard"}


def source_receipt(project: Path) -> dict:
    """Descreve HEAD e conteúdo em disco separadamente, sem escrever no índice Git.

O digest cobre arquivos rastreados e não ignorados; caches ignorados não são fonte.
Gitlinks/diretórios rastreados são rejeitados para não alegar hash de submódulos.
"""
    def git(*args: str) -> bytes:
        return subprocess.check_output(["git", *args], cwd=project, timeout=30,
            env={**os.environ, "GIT_OPTIONAL_LOCKS": "0"})
    head_commit = git("rev-parse", "HEAD").decode("ascii").strip()
    head_tree = git("rev-parse", "HEAD^{tree}").decode("ascii").strip()
    status_before = git("status", "--porcelain=v1", "-z", "--untracked-files=all")
    tracked = set(git("ls-files", "--cached", "-z").split(b"\0")) - {b""}
    untracked = set(git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0")) - {b""}
    digest = hashlib.sha256()
    for raw in sorted(tracked | untracked):
        relative = os.fsdecode(raw)
        path = project / relative
        if path.is_symlink():
            record = [relative, "symlink", os.readlink(path)]
        elif not path.exists():
            record = [relative, "missing"]
        else:
            before = path.stat()
            if not stat.S_ISREG(before.st_mode):
                raise RuntimeError(f"cannot fingerprint tracked directory/submodule: {relative}")
            content = hashlib.sha256()
            with path.open("rb") as source:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    content.update(block)
            after = path.stat()
            if (before.st_mtime_ns, before.st_size, before.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino):
                raise RuntimeError(f"source changed while fingerprinting: {relative}")
            record = [relative, "file", bool(before.st_mode & 0o111), before.st_size, content.hexdigest()]
        digest.update(json.dumps(record, ensure_ascii=True, separators=(",", ":")).encode("ascii") + b"\n")
    status_after = git("status", "--porcelain=v1", "-z", "--untracked-files=all")
    if status_before != status_after:
        raise RuntimeError("Git status changed while fingerprinting source")
    return {"head_commit": head_commit, "head_tree": head_tree, "dirty": bool(status_after),
        "worktree_sha256": digest.hexdigest(), "status_sha256": hashlib.sha256(status_after).hexdigest(),
        "tracked_paths": len(tracked), "untracked_paths": len(untracked),
        "scope": "tracked-and-untracked-not-ignored-files-v1"}


def validate_suite_result(path: Path) -> dict:
    """O processo limpo só é evidência de suíte quando o JSON confirma cada teste."""
    try:
        data = path.read_bytes()
        result = json.loads(data)
        if not isinstance(result, dict) or type(result.get("schema_version")) is not int or result["schema_version"] != 1:
            raise ValueError("unsupported suite schema")
        for field in ("total", "assertions", "failures", "discovery_errors", "exit_code"):
            if type(result.get(field)) is not int or result[field] < 0:
                raise ValueError(f"invalid suite count: {field}")
        if result["total"] == 0 or result["assertions"] < result["total"]:
            raise ValueError("suite executed no tests/assertions")
        if result["failures"] or result["discovery_errors"] or result["exit_code"]:
            raise ValueError("suite reported failures")
        if result.get("filter") != "":
            raise ValueError("CI requires an unfiltered suite")
        tests = result.get("tests")
        if not isinstance(tests, list) or len(tests) != result["total"]:
            raise ValueError("suite total differs from test records")
        identities = set()
        assertions = 0
        for test in tests:
            if not isinstance(test, dict) or test.get("failed") is not False:
                raise ValueError("test record missing or failed")
            if type(test.get("assertions")) is not int or test["assertions"] <= 0:
                raise ValueError("test record has no assertions")
            identity = (test.get("file"), test.get("name"))
            if not all(isinstance(item, str) and item for item in identity) or identity in identities:
                raise ValueError("duplicate/invalid test identity")
            identities.add(identity)
            assertions += test["assertions"]
        if assertions != result["assertions"]:
            raise ValueError("suite assertions differ from test records")
        return {"json": path.name, "sha256": hashlib.sha256(data).hexdigest(),
            "total": result["total"], "assertions": assertions,
            "failures": 0, "discovery_errors": 0, "filter": ""}
    except (OSError, ValueError, TypeError, KeyError) as error:
        raise RuntimeError(f"invalid suite evidence {path.name}: {error}") from error


def error_lines(text: str) -> list[str]:
    """Do not confuse test names, JSON 'errors': [], or warnings with errors."""
    return [line for line in ANSI.sub("", text).splitlines()
        if DIAGNOSTIC.match(line) or NATIVE_PANIC.match(line)]


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
    manifest = {"schema_version": 2, "status": "running", "checks": [],
        "native_editor_qa": False, "tested_head": False}
    try:
        manifest["source_before"] = source_receipt(project)
        godot = str(Path(args.godot).expanduser().resolve())
        version = subprocess.check_output([godot, "--version"], text=True, timeout=15).strip()
        manifest["engine_verification"] = verified_engine_version(version)
        manifest["engine"] = version
        base = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(project)]
        suite_json = logs / "suite.json"
        # Uma execução sem JSON novo não pode aproveitar o resultado anterior.
        suite_json.unlink(missing_ok=True)
        with optional_editor_extension(project, args.isolate_missing_editor_extension) as isolated:
            manifest["optional_editor_extension_isolated"] = isolated
            # Override só desta instância: porta efêmera, sem editar EditorSettings.
            # Godot 4.7.2: main.cpp aceita 0; LSP usa port_override >= 0.
            checks = [("import", ["--import", "--lsp-port", "0"]),
                      ("suite", ["--script", "res://tests/run_tests.gd", "--", "--json", str(suite_json)]),
                      ("m2", ["--script", "res://tools/verify_m2_capture_route.gd"]),
                      ("hud-geometry", ["--script", "res://tools/verify_hud_row_geometry.gd"])]
            for name, options in checks:
                manifest["checks"].append(run_checked(base + options, logs / f"{name}.log", cwd=project))
                if name == "suite":
                    manifest["suite"] = validate_suite_result(suite_json)
        manifest["status"] = "passed"
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        manifest["status"] = "failed"
        manifest["error"] = str(error)
        print(f"::error::{error}", file=sys.stderr)
    finally:
        if "source_before" in manifest:
            try:
                manifest["source_after"] = source_receipt(project)
                manifest["source_unchanged"] = manifest["source_before"] == manifest["source_after"]
                if not manifest["source_unchanged"]:
                    manifest["status"] = "failed"
                    manifest["source_error"] = "source changed during checks; results are not for one stable worktree"
                manifest["tested_head"] = (manifest["status"] == "passed" and manifest["source_unchanged"]
                    and not manifest["source_before"]["dirty"])
            except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                manifest["status"] = "failed"
                manifest["source_error"] = str(error)
        (logs / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(manifest, indent=2), flush=True)
    return 0 if manifest["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
