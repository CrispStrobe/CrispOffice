#!/usr/bin/env python3
"""Seal the committed grammar candidate before its one-shot local evaluation.

This only hashes sources/runtime files. It never imports a model or reads the
qualification cases. The Dart evaluator independently checks the exact source
map, panel digest, baseline closure and exclusive consumed-seal claim.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urljoin, urlparse

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
PROTOCOL = OUT / "protocol.json"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources() -> dict[str, str]:
    paths = {
        ROOT / "pubspec.yaml",
        ROOT / "pubspec.lock",
        ROOT / "packages/quds_office_engine/pubspec.yaml",
        ROOT / "packages/quds_proofing_spacy/pubspec.yaml",
        ROOT / "packages/quds_proofing_spacy/tool/evaluate_grammar.dart",
        PROTOCOL,
    }
    for name in ("quds_office_engine", "quds_proofing_spacy"):
        paths.update(p for p in (ROOT / "packages" / name / "lib").rglob("*")
                     if p.is_file())
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(paths)}


def package_configuration() -> dict:
    path = ROOT / ".dart_tool/package_config.json"
    configuration = json.loads(path.read_text())
    packages = {entry["name"]: entry for entry in configuration["packages"]}
    verified = {}
    for name in ("legacy_doc_parser", "quds_office_engine", "quds_proofing_spacy"):
        entry = packages[name]
        uri = urlparse(urljoin(path.as_uri(), entry["rootUri"]))
        actual = Path(unquote(uri.path)).resolve()
        expected = (ROOT / "packages" / name).resolve()
        if uri.scheme != "file" or actual != expected or entry.get("packageUri") != "lib/":
            raise RuntimeError(f"Unexpected workspace package route: {name}")
        verified[name] = str(expected.relative_to(ROOT))
    return {"sha256": sha(path), "workspace_roots_verified": verified}


def runtime() -> dict:
    library = Path(os.environ["QUDS_SPACY_LIBRARY"])
    bundle = Path(os.environ["QUDS_SPACY_BUNDLE"])
    restored = json.loads((OUT / "runtime/runtime-restoration.json").read_text())
    bundle_hashes = {str(p.relative_to(bundle)): sha(p)
                     for p in sorted(bundle.rglob("*")) if p.is_file()}
    expected_bundle = {name: value["sha256"] for name, value in restored["bundle"].items()}
    if bundle_hashes != expected_bundle:
        raise RuntimeError("Bundle differs from the restored original")
    library_hash = sha(library)
    if library_hash != restored["native_library_sha256"]:
        raise RuntimeError("Native library differs from the accepted binary")
    installed = {str(p.relative_to(library.parent)): sha(p)
                 for p in sorted(library.parent.rglob("*")) if p.is_file()}
    resolved = {}
    for line in subprocess.check_output(["ldd", str(library)], text=True).splitlines():
        match = re.search(r"(?:=>\s*)?(/[^\s]+)", line)
        if match:
            path = Path(match.group(1)).resolve()
            resolved[path.name] = sha(path)
    expected_dependencies = {row["resolved_filename"]: row["sha256"]
                             for row in restored["runtime_dependencies"]}
    if resolved != expected_dependencies:
        raise RuntimeError("Resolved native dependencies differ from the frozen runtime")
    return {
        "native_library_sha256": library_hash,
        "bundle_sha256": bundle_hashes,
        "installed_files_sha256": installed,
        "resolved_dependencies_sha256": resolved,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if head != args.candidate_commit:
        raise RuntimeError("Candidate commit is not current HEAD")
    source = sources()
    subprocess.run(["git", "diff", "--exit-code", "HEAD", "--", *source],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    protocol = json.loads(PROTOCOL.read_text())
    report = {
        "schema": "quds.spacy.grammar.candidate.v1",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "candidate_commit": head,
        "candidate_tree": subprocess.check_output(
            ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip(),
        "qualified_platform": "Linux x86-64/AVX2; de-DE; CPU/F32; PCRE2 10.46",
        "qualification_panel_sha256": protocol["qualification_panel"]["sha256"],
        "protocol_sha256": sha(PROTOCOL),
        "source_sha256": source,
        "package_configuration": package_configuration(),
        "freeze_runner_sha256": sha(Path(__file__)),
        "prequalification_controls": {
            str(p.relative_to(OUT)): sha(p)
            for p in sorted(OUT.rglob("*.json"))
            if p.parent.name.endswith("controls") and
            p.name in ("receipt.json", "summary.json", "completion.json")
        },
        "qualification_started": False,
        "native_acceptance_executions": 0,
        "ci_queries_waits_reruns": 0,
        "policy": "Publish this seal before the first qualification run. Never overwrite it or its consumed claim. No output-informed candidate tuning on this panel.",
        **runtime(),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as handle:
        handle.write(json.dumps(report, indent=2, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    print(json.dumps({"candidate_commit": head, "source_files": len(source),
                      "seal_sha256": sha(args.output), "qualification_started": False}))


if __name__ == "__main__":
    main()
