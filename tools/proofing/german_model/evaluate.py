#!/usr/bin/env python3
"""Reproduce a local, synthetic probe of the pinned unguarded reference runner.

No user documents, live services or application integration are involved.
The model is evaluation-only. The upstream guards are deliberately NOT claimed.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import platform
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parent
REVISION = "8e3b50beef7d775cedb7b876009e88bcf2e8d6af"


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        while part := source.read(1024 * 1024):
            value.update(part)
    return value.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--download", action="store_true", help="Fetch pinned public model artifacts only.")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.model_dir.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ROOT / "artifacts.json").read_text())
    for item in manifest:
        target = args.model_dir / item["file"]
        if not target.exists() and args.download:
            temporary = target.with_name(target.name + ".download")
            with urllib.request.urlopen(item["url"], timeout=120) as response, temporary.open("wb") as output:
                while part := response.read(1024 * 1024):
                    output.write(part)
            temporary.replace(target)
        if not target.exists() or digest(target) != item["sha256"]:
            raise SystemExit(f"Missing or changed pinned input: {target}")
    runner = ROOT / "vendor" / "quickstart.py"
    expected_runner = next(item["sha256"] for item in manifest if item["file"] == "quickstart.py")
    if digest(runner) != expected_runner:
        raise SystemExit("The vendored runner differs from the pinned reference.")

    spec = importlib.util.spec_from_file_location("proofbird_reference", runner)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    started = time.perf_counter()
    model = module.Gector(model=str(args.model_dir))
    startup_seconds = time.perf_counter() - started
    rows = []
    for case in json.loads((ROOT / "cases.json").read_text()):
        begin = time.perf_counter()
        output, suggestions = model.correct(case["input"])
        row = {**case, "output": output, "changed": output != case["input"],
               "seconds": round(time.perf_counter() - begin, 6),
               "suggestions": suggestions, "passes": len(model.passes)}
        if case["kind"] == "error":
            row["exact_expected"] = output == case["expected"]
        else:
            row["preserved"] = not row["changed"]
        rows.append(row)
        print(json.dumps({"id": row["id"], "output": output, "seconds": row["seconds"]}, ensure_ascii=False), flush=True)
    errors = [row for row in rows if row["kind"] == "error"]
    clean = [row for row in rows if row["kind"] == "clean"]
    dependencies = sorted(({
        "name": distribution.metadata["Name"], "version": distribution.version,
        "license": distribution.metadata.get("License-Expression") or distribution.metadata.get("License"),
    } for distribution in importlib.metadata.distributions()), key=lambda value: value["name"].lower())
    report = {
        "schema_version": 1, "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "model": "proofbird/gector-bert-de", "revision": REVISION,
        "upstream_tag": "v2.1.0", "runner": "unmodified quickstart.py; guards omitted by upstream",
        "application_default": False, "providers": model.session.get_providers(),
        "runtime": {"python": sys.version, "platform": platform.platform(), "cpu_count": os.cpu_count(),
                    "dependencies": dependencies},
        "input_sha256": {item["file"]: item["sha256"] for item in manifest},
        "cases_sha256": digest(ROOT / "cases.json"),
        "startup_seconds": round(startup_seconds, 6),
        "summary": {"error_cases": len(errors), "exact_expected_corrections": sum(r["exact_expected"] for r in errors),
                    "clean_cases": len(clean), "clean_cases_changed": sum(r["changed"] for r in clean)},
        "limits": ["Small hand-written synthetic probe, not a benchmark or population accuracy estimate.",
                   "Reference runner does not apply published app guards or OS spelling checks.",
                   "German region-specific false positives must be reviewed; this model is not an enabled provider."],
        "cases": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["summary"], ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
