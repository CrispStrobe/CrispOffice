#!/usr/bin/env python3
"""Independently verify every development archive member and optional original."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--index", required=True, type=Path)
    parser.add_argument("--original-root", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    index_bytes = args.index.read_bytes()
    index = json.loads(index_bytes)
    digest = lambda data: hashlib.sha256(data).hexdigest()
    archive_bytes = args.archive.read_bytes()
    expected = {row["member"]: row for row in index["members"]}
    errors, checks = [], []
    if len(expected) != len(index["members"]) or len(expected) != index["member_count"]:
        errors.append("Index has duplicate members or an inconsistent member count")
    if len(archive_bytes) != index["archive"]["bytes"] or digest(archive_bytes) != index["archive"]["sha256"]:
        errors.append("Archive length/hash differs from index")
    seen = set()
    with tarfile.open(args.archive, "r:gz") as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if not member.isfile() or path.is_absolute() or ".." in path.parts or member.name in seen:
                errors.append("Unexpected/unsafe/duplicate archive entry: " + member.name)
                continue
            seen.add(member.name)
            if member.name not in expected:
                errors.append("Unindexed archive entry: " + member.name)
                continue
            row = expected[member.name]
            stream = archive.extractfile(member)
            data = stream.read()
            good = len(data) == row["bytes"] and digest(data) == row["sha256"]
            check = {"member": member.name, "archive_member_bytes_match_index": good}
            if not good:
                errors.append("Archive member differs from index: " + member.name)
            if args.original_root is not None:
                relative = PurePosixPath(row["original_relative_path"])
                if relative.is_absolute() or ".." in relative.parts:
                    errors.append("Unsafe original path: " + str(relative))
                    continue
                original = args.original_root / relative
                if not original.resolve().is_relative_to(args.original_root.resolve()):
                    errors.append("Original path leaves the specified root: " + str(relative))
                    continue
                if original.is_file() and not original.is_symlink():
                    original_bytes = original.read_bytes()
                    original_good = original_bytes == data
                    check.update(original_bytes_match_archive=original_good,
                                 original_sha256=digest(original_bytes))
                else:
                    original_good = False
                    check["original_bytes_match_archive"] = False
                if not original_good:
                    errors.append("Original missing/changed: " + str(original))
            checks.append(check)
    for missing in sorted(set(expected) - seen):
        errors.append("Missing archive member: " + missing)
    record = {
        "schema": 1, "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "ARCHIVE_INTEGRITY_ONLY_NOT_APPLICATION_QUALIFICATION",
        "archive_sha256": digest(archive_bytes), "index_sha256": digest(index_bytes),
        "verifier_sha256": digest(Path(__file__).read_bytes()),
        "expected_member_count": len(expected), "checked_member_count": len(checks),
        "originals_compared": args.original_root is not None,
        "original_root": str(args.original_root.resolve()) if args.original_root else None,
        "checks": checks, "errors": errors, "passed": not errors,
        "product_code_executed": False, "network_or_github_actions_calls": 0,
    }
    args.output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": record["passed"], "members": len(checks),
                      "originals_compared": record["originals_compared"], "errors": errors}))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
