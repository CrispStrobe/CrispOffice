#!/usr/bin/env python3
"""Qualify incoming build syntax and licence bytes without building macOS code."""

import argparse
import ast
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time


SCRIPT = Path(__file__).resolve()
BUILD = "packages/quds_proofing_spacy/tool/build.py"
SHELL = "packages/quds_office_editor/example/tool/build_macos_app.sh"
LICENSES = "packages/quds_proofing_spacy/licenses"
ASSETS = "packages/quds_office_editor/example/assets/licenses/spacy"
LICENSE_SOURCE_COMMIT = "0e03878b028ec25ed3d84a790633433eafc3bede"
RAW_NOTICE = LICENSES + "/notices/de_core_news_sm-LICENSES_SOURCES"


def identity(path):
    raw = Path(path).read_bytes()
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def now():
    return datetime.now(timezone.utc).isoformat()


def check(repo, name):
    source = (repo / BUILD).read_text()
    tree = ast.parse(source, filename=BUILD)
    if name == "python-build-syntax":
        compile(tree, BUILD, "exec")
        print(json.dumps({"passed": True, "file": BUILD,
                          "ast_parsed": True, "bytecode_compiled_in_memory": True,
                          "product_code_executed": False}))
        return
    constants = {}
    for statement in tree.body:
        if isinstance(statement, ast.Assign):
            for target in statement.targets:
                if isinstance(target, ast.Name) and target.id in ("CRISPEMBED", "PCRE2"):
                    constants[target.id] = ast.literal_eval(statement.value)
    manifest = json.loads((repo / LICENSES / "manifest.json").read_text())
    assert manifest["schema_version"] == 1
    assert manifest["crispembed"] == constants["CRISPEMBED"]
    assert manifest["pcre2"] == constants["PCRE2"]
    expected = manifest["notices"]
    actual_files = {str(p.relative_to(repo / LICENSES))
                    for p in (repo / LICENSES).rglob("*") if p.is_file()}
    assert actual_files == set(expected) | {"manifest.json"}
    verified = []
    by_name = {}
    for relative, digest in sorted(expected.items()):
        path = Path(relative)
        assert not path.is_absolute() and ".." not in path.parts
        full = repo / LICENSES / relative
        assert not full.is_symlink()
        actual = identity(full)
        assert actual["sha256"] == digest, relative
        verified.append({"path": relative, **actual})
        by_name.setdefault(path.name, set()).add(digest)
    mirrored = []
    for path in sorted((repo / ASSETS).glob("*")):
        if not path.is_file():
            continue
        assert not path.is_symlink()
        actual = identity(path)
        assert actual["sha256"] in by_name[path.name], path.name
        mirrored.append({"path": str(path.relative_to(repo)), **actual})
    assert mirrored
    original = subprocess.check_output(
        ["git", "show", LICENSE_SOURCE_COMMIT + ":" + RAW_NOTICE], cwd=repo)
    original_blob = subprocess.check_output(
        ["git", "rev-parse", LICENSE_SOURCE_COMMIT + ":" + RAW_NOTICE],
        cwd=repo, text=True).strip()
    retained = (repo / RAW_NOTICE).read_bytes()
    retained_blob = hashlib.sha1(b"blob " + str(len(retained)).encode() +
                                 b"\0" + retained).hexdigest()
    assert retained == original and retained_blob == original_blob
    raw_notice = {
        "path": RAW_NOTICE, "origin_commit": LICENSE_SOURCE_COMMIT,
        "origin_git_blob": original_blob, "retained_git_blob": retained_blob,
        "origin_sha256": hashlib.sha256(original).hexdigest(),
        "retained_sha256": hashlib.sha256(retained).hexdigest(),
        "bytes": len(retained), "exact_original_bytes_preserved": True,
    }
    print(json.dumps({"passed": True, "crispembed": constants["CRISPEMBED"],
                      "pcre2": constants["PCRE2"], "manifest_complete": True,
                      "verified_notice_count": len(verified), "verified_notices": verified,
                      "studio_mirror_count": len(mirrored), "studio_mirrors": mirrored,
                      "raw_notice_provenance": raw_notice,
                      "product_code_executed": False}))


def sources(repo):
    paths = {repo / BUILD, repo / SHELL}
    paths.update(p for p in (repo / LICENSES).rglob("*") if p.is_file())
    paths.update(p for p in (repo / ASSETS).rglob("*") if p.is_file())
    return {str(p.relative_to(repo)): identity(p) for p in sorted(paths)}


def dependencies():
    paths = {Path(sys.executable).resolve(), Path(shutil.which("bash")).resolve(),
             Path(shutil.which("git")).resolve()}
    paths.update(Path(m.__file__).resolve() for m in tuple(sys.modules.values())
                 if getattr(m, "__file__", None) and Path(m.__file__).is_file()
                 and Path(m.__file__).resolve() != SCRIPT)
    return {str(p): identity(p) for p in sorted(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--head")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", choices=["python-build-syntax", "license-manifest"])
    args = parser.parse_args()
    repo = args.repo.resolve()
    if args.check:
        check(repo, args.check)
        return 0
    if not args.head or not args.output:
        parser.error("--head and --output are required for acceptance")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    if head != args.head:
        raise RuntimeError("source HEAD differs from the frozen checkpoint")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(SCRIPT, output / "executed-runner.py")
    before, deps = sources(repo), dependencies()
    save(output / "inputs-before.json", before)
    save(output / "dependencies-before.json", deps)
    checks = [
        ("macos-shell-syntax", [str(Path(shutil.which("bash")).resolve()), "-n", SHELL]),
        *[(name, [sys.executable, str(SCRIPT), "--repo", str(repo), "--check", name])
          for name in ("python-build-syntax", "license-manifest")],
    ]
    commands = []
    for name, argv in checks:
        start, clock = now(), time.monotonic()
        stdout, stderr = output / (name + ".stdout.log"), output / (name + ".stderr.log")
        timed_out = False
        with stdout.open("wb") as out, stderr.open("wb") as err:
            try:
                result = subprocess.run(argv, cwd=repo, stdout=out, stderr=err,
                                        timeout=45, check=False)
                exit_code = result.returncode
            except subprocess.TimeoutExpired:
                timed_out, exit_code = True, None
        commands.append({"name": name, "argv": argv, "cwd": str(repo),
                         "started_at_utc": start, "finished_at_utc": now(),
                         "elapsed_seconds": round(time.monotonic() - clock, 6),
                         "exit_code": exit_code, "timed_out": timed_out,
                         "interrupted": False,
                         "stdout": {"path": stdout.name, **identity(stdout)},
                         "stderr": {"path": stderr.name, **identity(stderr)}})
    after, deps_after = sources(repo), dependencies()
    save(output / "inputs-after.json", after)
    save(output / "dependencies-after.json", deps_after)
    changed = sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p))
    changed_deps = sorted(p for p in deps.keys() | deps_after.keys() if deps.get(p) != deps_after.get(p))
    head_after = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    result = {
        "schema_version": 1, "source_head": head, "source_head_after": head_after,
        "success": all(c["exit_code"] == 0 for c in commands) and not changed and
                   not changed_deps and head == head_after,
        "scope": "Shell syntax, Python AST/in-memory compilation, manifest source pins, "
                 "13 licence notice hashes and their Studio asset mirrors only. "
                 "No macOS build, codesign, dynamic library load or native model execution.",
        "commands": commands, "changed_source_inputs": changed,
        "changed_dependency_inputs": changed_deps,
        "source_input_count": len(before), "dependency_input_count": len(deps),
        "executed_runner": {"path": "executed-runner.py", **identity(SCRIPT)},
        "test_counts": {"passed": 0, "failed": 0, "skipped": 0},
        "github_actions_used": False,
    }
    save(output / "receipt.json", result)
    print(json.dumps({"success": result["success"], "commands": len(commands),
                      "source_inputs": len(before), "dependencies": len(deps)}, indent=2))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
