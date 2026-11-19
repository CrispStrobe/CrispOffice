#!/usr/bin/env python3
"""Preserve an externally interrupted gate and its untouched original receipts."""

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
    parser.add_argument("--notice", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    gate, notice_path, output = args.gate.resolve(), args.notice.resolve(), args.output.resolve()
    if output == gate or gate in output.parents:
        raise RuntimeError("Output must remain outside the original gate")
    execution = json.loads((gate / "execution.json").read_text())
    notice = json.loads(notice_path.read_text())
    if execution.get("status") == "PASS" or notice.get("reported_external_exit_code") != 130:
        raise RuntimeError("Interrupted evidence must not be classified as a passing gate")
    if execution.get("source_commit") != notice.get("attempt_source"):
        raise RuntimeError("Interruption notice and original gate source differ")
    output.mkdir(parents=True, exist_ok=True)
    archive_path, index_path = output / "interrupted-attempt.tar.xz", output / "interrupted-attempt-index.json"
    if archive_path.exists() or index_path.exists():
        raise RuntimeError("Preserve an existing archive/index; choose a fresh output")

    def gather():
        rows, sources = [], {}
        for role, path, relative in [
            *[("gate", path, path.relative_to(gate).as_posix()) for path in [gate, *gate.rglob("*")]],
            ("interruption_notice", notice_path, notice_path.name),
        ]:
            if path.is_symlink():
                raise RuntimeError("Evidence symlink is not allowed: " + str(path))
            member = ("gate" if relative == "." else "gate/" + relative) if role == "gate" else "notice/" + relative
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
        "classification": "INTERRUPTED_INCOMPLETE_QUALIFICATION_ATTEMPT",
        "attempt_source": execution["source_commit"], "attempt_tree": execution["source_tree"],
        "original_outer_receipt_status": execution["status"],
        "reported_external_exit_code": notice["reported_external_exit_code"],
        "later_outer_node_and_mail_browser_phases_executed": False,
        "interrupted_attempt_cases_added_to_accepted_totals": 0,
        "interruption_notice": "notice/" + notice_path.name,
        "original_receipts_rewritten": False,
        "archive": {"file": archive_path.name, "bytes": archive_path.stat().st_size, "sha256": digest(archive_path),
                    "format": "XZ preset 6 / PAX tar, sorted names, normalized headers; original content unchanged"},
        "member_count": len(rows), "regular_file_count": sum(row["kind"] == "file" for row in rows),
        "directory_count": sum(row["kind"] == "directory" for row in rows),
        "original_file_bytes": sum(row["bytes"] for row in rows), "members": rows,
        "entire_gate_directory_included": True, "excluded_gate_paths": [],
        "originals_unchanged_during_packing": True,
        "observed_original_roots": {"gate": str(gate), "interruption_notice": str(notice_path)},
        "supplement_scope": "External interruption report transcribed separately. Original RUNNING/partial receipts remain unchanged; exit130 is attributed to the coordinator report.",
        "packer_sha256": digest(Path(__file__)), "product_code_executed": False, "network_or_github_actions_calls": 0,
    }
    index_path.write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps({"archive": record["archive"], "members": len(rows),
                      "files": record["regular_file_count"], "directories": record["directory_count"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
