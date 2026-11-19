#!/usr/bin/env python3
"""Archive explicitly selected diagnostic originals without changing their bytes.

This is development evidence, not aggregate application qualification. The
selection file is explicit; no recursive runtime or repository collection occurs.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def stable_read(path: Path) -> tuple[bytes, int]:
    before = path.stat()
    if path.is_symlink() or not path.is_file():
        raise RuntimeError("Expected an ordinary file: " + str(path))
    data = path.read_bytes()
    after = path.stat()
    identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns)
    if identity(before) != identity(after) or len(data) != before.st_size:
        raise RuntimeError("Original changed while reading: " + str(path))
    return data, before.st_mtime_ns


def reporter_observations(data: bytes) -> dict:
    """Describe raw events; never turn diagnostic logs into accepted results."""
    event_counts = Counter()
    tests, completions, suites = {}, {}, {}
    non_json, unknown_json = 0, 0
    terminal, errors, duplicate_ids = [], [], []
    for line_number, line in enumerate(data.decode("utf-8", errors="replace").splitlines(), 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            non_json += 1
            continue
        if not isinstance(event, dict) or not isinstance(event.get("type"), str):
            unknown_json += 1
            continue
        kind = event["type"]
        event_counts[kind] += 1
        if kind == "suite":
            suite = event.get("suite", {})
            if isinstance(suite, dict):
                suites[suite.get("id")] = suite.get("path")
        elif kind == "testStart":
            test = event.get("test", {})
            if isinstance(test, dict):
                tests[test.get("id")] = test
        elif kind == "testDone":
            test_id = event.get("testID")
            if test_id in completions:
                duplicate_ids.append(test_id)
            completions[test_id] = event
        elif kind == "error":
            errors.append({"line": line_number, "test_id": event.get("testID")})
        elif kind == "done":
            terminal.append({k: event[k] for k in ("success", "time") if k in event})
    visible = {
        test_id: test for test_id, test in tests.items()
        if test.get("hidden") is not True and not test.get("name", "").startswith("loading ")
    }
    results = Counter(
        completions[test_id].get("result", "missing_result")
        for test_id in visible if test_id in completions
    )
    skipped = [test_id for test_id in visible
               if completions.get(test_id, {}).get("skipped") is True]
    return {
        "interpretation": "Descriptive raw-event observations only; not accepted qualification.",
        "event_counts": dict(sorted(event_counts.items())),
        "visible_test_starts": len(visible),
        "visible_completion_results": dict(sorted(results.items())),
        "visible_skipped_completions": len(skipped),
        "unfinished_visible_test_ids": sorted(set(visible) - set(completions)),
        "duplicate_completion_test_ids": duplicate_ids,
        "reporter_errors": errors,
        "terminal_done_events": terminal,
        "non_json_lines": non_json,
        "other_json_lines": unknown_json,
        "suite_paths": sorted({p for p in suites.values() if isinstance(p, str)}),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-root", required=True, type=Path)
    parser.add_argument("--selection", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root, output = args.original_root.resolve(), args.output.resolve()
    selection_bytes = args.selection.read_bytes()
    selection = json.loads(selection_bytes)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "development-evidence.tar.gz"
    index_path = output / "development-index.json"
    if archive.exists() or index_path.exists():
        raise RuntimeError("Preserve an existing archive/index; choose a fresh output directory")
    paths = [row["path"] for row in selection["files"]]
    if paths != sorted(set(paths)):
        raise RuntimeError("Selection must contain unique, sorted relative paths")
    members, original_bytes = [], {}
    for row in selection["files"]:
        relative = PurePosixPath(row["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise RuntimeError("Unsafe original path")
        path = root / relative
        if path.resolve().is_relative_to(root) is False:
            raise RuntimeError("Original leaves the specified root")
        data, modified_ns = stable_read(path)
        member = "originals/" + relative.as_posix()
        entry = {
            "member": member, "original_relative_path": relative.as_posix(),
            "role": row["role"], "bytes": len(data), "sha256": sha256(data),
            "original_mtime_ns_at_capture": modified_ns,
            "mtime_is_not_a_claim_about_run_time": True,
            "exact_application_source_commit": None,
            "source_boundary": row["source_boundary"],
            "accepted_combined_source_result": False,
        }
        if path.suffix == ".jsonl":
            entry["reporter_observations"] = reporter_observations(data)
        if "note" in row:
            entry["note"] = row["note"]
        members.append(entry)
        original_bytes[member] = data
    with archive.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as tar:
                for entry in members:
                    info = tarfile.TarInfo(entry["member"])
                    info.size = entry["bytes"]
                    info.mode = 0o644
                    info.uid = info.gid = info.mtime = 0
                    info.uname = info.gname = ""
                    tar.addfile(info, io.BytesIO(original_bytes[entry["member"]]))
    index = {
        "schema": 1,
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "DEVELOPMENT_ONLY_NOT_ACCEPTED_AGGREGATE_QUALIFICATION",
        "original_root_at_capture": str(root),
        "selection_sha256": sha256(selection_bytes),
        "builder_sha256": sha256(Path(__file__).read_bytes()),
        "archive": {"file": archive.name, "bytes": archive.stat().st_size,
                    "sha256": sha256(archive.read_bytes()),
                    "format": "gzip mtime=0, tar sorted members, normalized headers; original member bytes unchanged"},
        "member_count": len(members),
        "original_bytes_total": sum(row["bytes"] for row in members),
        "members": members,
        "omitted_rebuildable_artifacts": selection.get("omitted_rebuildable_artifacts", []),
        "source_boundary": "These were exploratory executions while source was being edited or reconciled. No complete source/runtime snapshot bound each run. A passing diagnostic is not qualification of a later combined commit.",
        "recorded_process_exit_codes": "Not reconstructed when absent from the original files.",
        "historical_diagnostic_passes_added_to_accepted_counts": 0,
        "github_actions_queried_or_awaited": False,
    }
    index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"archive": str(archive), "members": len(members),
                      "bytes": archive.stat().st_size, "index": str(index_path)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
