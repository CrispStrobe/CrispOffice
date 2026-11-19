#!/usr/bin/env python3
"""Preserve a complete failed gate without presenting its partial results as accepted."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import tarfile


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gate", required=True, type=Path)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    gate, review, output = args.gate.resolve(), args.review.resolve(), args.output.resolve()
    if output == gate or gate in output.parents:
        raise RuntimeError("Output must remain outside the original gate")
    execution = json.loads((gate / "execution.json").read_text())
    native = json.loads((gate / "native/verification.json").read_text())
    if execution.get("status") != "FAIL" or native.get("success") is not False:
        raise RuntimeError("This packer only preserves the failed attempt")
    output.mkdir(parents=True, exist_ok=True)
    archive_path, index_path = output / "failed-attempt.tar.xz", output / "failed-attempt-index.json"
    if archive_path.exists() or index_path.exists():
        raise RuntimeError("Preserve an existing archive/index; choose a fresh output")

    def gather():
        rows, sources = [], {}
        for role, path, relative in [
            *[("gate", path, path.relative_to(gate).as_posix()) for path in [gate, *gate.rglob("*")]],
            ("review_note", review, review.name),
        ]:
            if path.is_symlink():
                raise RuntimeError("Evidence symlink is not allowed: " + str(path))
            member = ("gate" if relative == "." else "gate/" + relative) if role == "gate" else "review/" + relative
            if path.is_dir():
                kind, size, value = "directory", 0, hashlib.sha256(b"").hexdigest()
            elif path.is_file():
                before = path.stat()
                kind, size, value = "file", before.st_size, digest(path)
                after = path.stat()
                if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
                    raise RuntimeError("Original changed while reading: " + str(path))
            else:
                raise RuntimeError("Unsupported evidence entry: " + str(path))
            rows.append({"member": member, "kind": kind, "bytes": size, "sha256": value,
                         "original_role": role, "original_relative_path": relative})
            sources[member] = path
        rows.sort(key=lambda row: row["member"])
        if len(rows) != len(sources):
            raise RuntimeError("Duplicate evidence members")
        return rows, sources

    rows, sources = gather()
    with tarfile.open(archive_path, "w:xz", format=tarfile.PAX_FORMAT, preset=6) as archive:
        for row in rows:
            info = tarfile.TarInfo(row["member"])
            info.uid = info.gid = info.mtime = 0
            info.uname = info.gname = ""
            info.size = row["bytes"]
            if row["kind"] == "directory":
                info.type, info.mode = tarfile.DIRTYPE, 0o755
                archive.addfile(info)
            else:
                info.mode = 0o644
                with sources[row["member"]].open("rb") as stream:
                    archive.addfile(info, stream)
    after, _ = gather()
    if rows != after:
        raise RuntimeError("Evidence changed while packing; preserve this rejected attempt")
    record = {
        "schema": 1, "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "INCOMPLETE_FAILED_QUALIFICATION_ATTEMPT",
        "attempt_source": execution["source_commit"], "attempt_tree": execution["source_tree"],
        "overall_status": execution["status"], "native_receipt_success": native["success"],
        "native_reported_passed_cases": native["passed"],
        "later_outer_node_and_mail_browser_phases_executed": False,
        "historical_or_failed_attempt_cases_added_to_accepted_totals": 0,
        "failure_log": "gate/native/checks/whitespace.log",
        "failure_text": (gate / "native/checks/whitespace.log").read_text(),
        "archive": {"file": archive_path.name, "bytes": archive_path.stat().st_size, "sha256": digest(archive_path),
                    "format": "XZ preset 6 / PAX tar, sorted names, normalized headers; original content unchanged"},
        "member_count": len(rows), "regular_file_count": sum(row["kind"] == "file" for row in rows),
        "directory_count": sum(row["kind"] == "directory" for row in rows),
        "original_file_bytes": sum(row["bytes"] for row in rows), "members": rows,
        "entire_gate_directory_included": True, "excluded_gate_paths": [],
        "originals_unchanged_during_packing": True,
        "observed_original_roots": {"gate": str(gate), "review_note": str(review)},
        "supplement_scope": "Read-only IMAP scaling review, with timings explicitly attributed to this earlier failed gate. No additional test or product change.",
        "packer_sha256": digest(Path(__file__)), "product_code_executed": False, "network_or_github_actions_calls": 0,
    }
    index_path.write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps({"archive": record["archive"], "members": len(rows),
                      "files": record["regular_file_count"], "directories": record["directory_count"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
