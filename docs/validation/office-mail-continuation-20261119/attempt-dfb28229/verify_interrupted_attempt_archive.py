#!/usr/bin/env python3
"""Independently compare an interrupted attempt archive with its index and originals.

This verifier does not import the packer or the application qualification
runner. Every regular member is read, hashed, and optionally compared directly
with the original bytes. It executes no product code and uses no network.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


def file_hash(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(data)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--index", required=True, type=Path)
    parser.add_argument("--gate", type=Path)
    parser.add_argument("--notice", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    compare = args.gate is not None
    if len({value is not None for value in (args.gate, args.notice)}) != 1:
        parser.error("Supply both --gate and --notice, or neither of them")
    index = json.loads(args.index.read_text())
    expected = {row["member"]: row for row in index["members"]}
    errors, checks, seen, receipts = [], [], set(), {}
    if len(expected) != len(index["members"]) or len(expected) != index["member_count"]:
        errors.append("Duplicate indexed members or inconsistent count")
    archive_hash = file_hash(args.archive)
    if archive_hash != index["archive"]["sha256"] or args.archive.stat().st_size != index["archive"]["bytes"]:
        errors.append("Archive hash/length differs from index")
    expected_names = list(expected)
    if expected_names != sorted(expected_names):
        errors.append("Index is not sorted")
    names, file_count, directory_count = [], 0, 0
    with tarfile.open(args.archive, "r:xz") as archive:
        for member in archive:
            name = member.name.rstrip("/")
            relative = PurePosixPath(name)
            if relative.is_absolute() or ".." in relative.parts or name in seen or name not in expected:
                errors.append("Unsafe/duplicate/unindexed archive member: " + name)
                continue
            seen.add(name)
            names.append(name)
            row = expected[name]
            check = {"member": name, "kind": row["kind"]}
            if member.uid or member.gid or member.mtime or member.uname or member.gname:
                errors.append("Non-normalized member header: " + name)
            original = None
            if compare:
                original_relative = PurePosixPath(row["original_relative_path"])
                if original_relative.is_absolute() or ".." in original_relative.parts:
                    errors.append("Unsafe indexed original path: " + name)
                    continue
                role = row["original_role"]
                if role == "gate":
                    original = args.gate / original_relative
                    if not original.resolve().is_relative_to(args.gate.resolve()):
                        errors.append("Original escapes gate directory: " + name)
                        continue
                elif role == "interruption_notice":
                    original = args.notice
                else:
                    errors.append("Unexpected original role: " + name)
                    continue
            if row["kind"] == "directory":
                directory_count += 1
                correct = (member.isdir() and member.size == row["bytes"] == 0
                           and row["sha256"] == hashlib.sha256(b"").hexdigest()
                           and member.mode == 0o755)
                check["archive_directory_matches_index"] = correct
                if not correct:
                    errors.append("Directory member differs: " + name)
                if original is not None:
                    original_ok = original.is_dir() and not original.is_symlink()
                    check["original_directory_exists"] = original_ok
                    if not original_ok:
                        errors.append("Original directory missing: " + name)
            elif row["kind"] == "file" and member.isfile():
                file_count += 1
                archived = archive.extractfile(member)
                live = None
                original_good = True
                if original is not None:
                    if original.is_file() and not original.is_symlink():
                        live = original.open("rb")
                    else:
                        original_good = False
                digest, byte_count = hashlib.sha256(), 0
                retain_receipt = name == "gate/execution.json"
                retained = []
                while True:
                    block = archived.read(1024 * 1024)
                    if not block:
                        break
                    digest.update(block)
                    byte_count += len(block)
                    if retain_receipt:
                        retained.append(block)
                    if live is not None and live.read(len(block)) != block:
                        original_good = False
                if live is not None:
                    if live.read(1):
                        original_good = False
                    live.close()
                correct = (digest.hexdigest() == row["sha256"] and byte_count == row["bytes"]
                           and member.size == byte_count and member.mode == 0o644)
                check.update(archive_file_matches_index=correct, bytes=byte_count, sha256=digest.hexdigest())
                if not correct:
                    errors.append("Archived file differs from index: " + name)
                if original is not None:
                    check["original_bytes_identical"] = original_good
                    if not original_good:
                        errors.append("Original bytes missing/changed: " + name)
                if retain_receipt:
                    receipts[row["original_role"] if row["original_role"] != "gate" else "execution"] = json.loads(b"".join(retained))
            else:
                errors.append("Unsupported/member type mismatch: " + name)
            checks.append(check)
    if names != sorted(names):
        errors.append("Archive members are not sorted")
    if seen != set(expected):
        errors.append("Missing indexed archive members")
    if file_count != index["regular_file_count"] or directory_count != index["directory_count"]:
        errors.append("File/directory counts differ")
    if compare:
        actual_gate = {"gate"}
        for path in args.gate.rglob("*"):
            if path.is_symlink():
                errors.append("Original gate contains a symlink")
            actual_gate.add("gate/" + path.relative_to(args.gate).as_posix())
        indexed_gate = {name for name, row in expected.items() if row["original_role"] == "gate"}
        if actual_gate != indexed_gate:
            errors.append("Archive does not contain the complete current gate tree")
    execution = receipts.get("execution", {})
    if execution.get("status") == "PASS" or execution.get("status") != index.get("original_outer_receipt_status"):
        errors.append("Original interrupted receipt was relabelled or incorrectly accepted")
    if index.get("reported_external_exit_code") != 130:
        errors.append("External interruption report is not recorded")
    if execution.get("source_commit") != index["attempt_source"] or execution.get("source_tree") != index["attempt_tree"]:
        errors.append("Interrupted-attempt source identities differ")
    if index.get("interrupted_attempt_cases_added_to_accepted_totals") != 0:
        errors.append("Interrupted attempt must contribute zero accepted cases")
    result = {
        "schema": 1, "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "INDEPENDENT_ARCHIVE_INTEGRITY_VERIFICATION",
        "attempt_source": index["attempt_source"], "attempt_tree": index["attempt_tree"],
        "archive_sha256": archive_hash, "index_sha256": file_hash(args.index),
        "verifier_sha256": file_hash(Path(__file__)),
        "member_count": len(checks), "regular_file_count": file_count, "directory_count": directory_count,
        "originals_compared": compare, "checks": checks, "errors": errors,
        "passed": not errors, "product_code_executed": False, "network_or_github_actions_calls": 0,
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": result["passed"], "members": len(checks), "files": file_count,
                      "directories": directory_count, "originals_compared": compare, "errors": errors}))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
