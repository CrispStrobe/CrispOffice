#!/usr/bin/env python3
"""Replay the synthetic transfer fixture through an actual office converter.

This records file-conversion and controlled-callback acceptance. It does not
connect to a running Zotero client or invoke a native Zotero plugin.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--dart", type=Path, required=True)
    parser.add_argument("--package-config", type=Path, required=True)
    parser.add_argument("--soffice", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repository.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    logs = out / "logs"
    logs.mkdir()
    tool = repo / "packages/quds_office_engine/tool/zotero/transfer_acceptance.dart"
    commands = []

    def run(name, command):
        started = time.monotonic()
        result = subprocess.run(
            [str(part) for part in command],
            cwd=repo,
            text=True,
            capture_output=True,
            timeout=180,
        )
        (logs / (name + ".stdout")).write_text(result.stdout)
        (logs / (name + ".stderr")).write_text(result.stderr)
        commands.append({
            "step": name,
            "command": [str(part) for part in command],
            "cwd": str(repo),
            "exit_code": result.returncode,
            "duration_seconds": round(time.monotonic() - started, 3),
        })
        save(out / "commands.json", commands)
        if result.returncode:
            raise RuntimeError(f"{name} failed; inspect {logs}")
        print(name + ": passed", flush=True)
        return result.stdout.strip() or result.stderr.strip()

    def fingerprint():
        files = [
            *sorted((repo / "packages/quds_office_engine/lib").rglob("*.dart")),
            tool,
            repo / "pubspec.yaml",
            repo / "pubspec.lock",
            repo / "packages/quds_office_engine/pubspec.yaml",
        ]
        return {str(path.relative_to(repo)): sha256(path) for path in files}

    before = fingerprint()
    save(out / "source-before.json", before)
    head_before = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repo, text=True
    ).strip()
    dart_version = run("dart-version", [args.dart, "--version"])
    profile = out / "office-profile"
    office = [args.soffice, "--headless", "-env:UserInstallation=" + profile.as_uri()]
    office_version = run("office-version", [*office, "--version"])
    dart = [args.dart, "--packages=" + str(args.package_config.resolve()), tool]
    fixtures = out / "fixtures"
    run("generate", [*dart, "generate", fixtures])
    run("direct-docx", [*dart, "verify", fixtures / "transfer.docx"])

    to_odt = out / "docx-to-odt"
    back_docx = out / "docx-odt-docx"
    from_odt = out / "odt-to-docx"
    for directory in (to_odt, back_docx, from_odt):
        directory.mkdir()
    run("convert-docx-to-odt", [
        *office, "--convert-to", "odt", "--outdir", to_odt,
        fixtures / "transfer.docx",
    ])
    run("convert-odt-back-to-docx", [
        *office, "--convert-to", "docx", "--outdir", back_docx,
        to_odt / "transfer.odt",
    ])
    run("verify-docx-odt-docx", [*dart, "verify", back_docx / "transfer.docx"])
    run("convert-generated-odt-to-docx", [
        *office, "--convert-to", "docx", "--outdir", from_odt,
        fixtures / "transfer.odt",
    ])
    run("verify-odt-docx", [*dart, "verify", from_odt / "transfer.docx"])

    after = fingerprint()
    save(out / "source-after.json", after)
    head_after = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repo, text=True
    ).strip()
    changed = [path for path in sorted(set(before) | set(after))
               if before.get(path) != after.get(path)]
    receipts = {
        name: json.loads((logs / (name + ".stdout")).read_text())
        for name in ("direct-docx", "verify-docx-odt-docx", "verify-odt-docx")
    }
    files = {
        str(path.relative_to(out)): sha256(path)
        for path in sorted(out.rglob("*"))
        if path.is_file() and profile not in path.parents
    }
    result = {
        "accepted": not changed and head_before == head_after,
        "scope": "Actual LibreOffice file conversion and controlled Quds import/format callbacks; no live Zotero/plugin session.",
        "source_head_before": head_before,
        "source_head_after": head_after,
        "source_inputs_unchanged": not changed,
        "source_input_count": len(before),
        "source_inputs_changed": changed,
        "dart_version": dart_version,
        "converter_version": office_version,
        "package_config_sha256": sha256(args.package_config),
        "environment": {name: os.environ.get(name) for name in (
            "TMPDIR", "FLUTTER_ROOT", "PUB_CACHE", "LANG", "LC_ALL",
        )},
        "verification": receipts,
        "files": files,
    }
    save(out / "receipt.json", result)
    if not result["accepted"]:
        raise RuntimeError("Source changed during converter qualification")
    print(json.dumps({"accepted": True, "source_head": head_after,
                      "converter_version": office_version,
                      "output": str(out)}), flush=True)


if __name__ == "__main__":
    main()
