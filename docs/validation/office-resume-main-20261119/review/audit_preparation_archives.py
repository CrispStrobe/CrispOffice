#!/usr/bin/env python3
"""Independently inspect preserved preparation archives, without extracting them."""
from __future__ import annotations
from collections import Counter
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT / "quds_office_suite"


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", "--no-lazy-fetch", "--no-replace-objects", "-C", str(REPO), *args])


def check(value: object, message: str) -> None:
    if not value:
        raise AssertionError(message)


def main() -> None:
    reports = []
    for label, directory, source in (
        ("incoming_e80_preparation", "office-continuation-20261119", "e80beb2ed2fe70397a5a8fff5c9e908b04862f78"),
        ("current_preparation", "office-resume-main-20261119", None),
    ):
        base = Path("docs/validation") / directory / "runtime"
        index_path = base / "preparation-evidence.index.json"
        index_raw = (REPO / index_path).read_bytes()
        index = json.loads(index_raw)
        archive_path = base / index["archive"]
        archive_raw = (REPO / archive_path).read_bytes()
        check(len(archive_raw) == index.get("archive_bytes", index.get("bytes")), f"archive length: {label}")
        check(sha(archive_raw) == index.get("archive_sha256", index.get("sha256")), f"archive digest: {label}")
        rows = index["members"]
        indexed = rows if isinstance(rows, dict) else {row["path"]: row for row in rows}
        check(len(indexed) == len(rows), f"duplicate indexed members: {label}")
        stored = {}
        with tarfile.open(fileobj=io.BytesIO(archive_raw), mode="r:xz") as archive:
            members = archive.getmembers()
            counts = Counter(member.name for member in members)
            check(all(count == 1 for count in counts.values()), f"duplicate tar members: {label}")
            for member in members:
                path = PurePosixPath(member.name)
                check(not path.is_absolute() and ".." not in path.parts, f"unsafe path: {member.name}")
                check(member.isfile(), f"non-regular tar member: {member.name}")
                raw = archive.extractfile(member).read()
                check(member.name in indexed, f"unexpected member: {member.name}")
                record = indexed[member.name]
                check(len(raw) == record["bytes"] == member.size, f"member length: {member.name}")
                check(sha(raw) == record["sha256"], f"member digest: {member.name}")
                stored[member.name] = raw
        check(set(stored) == set(indexed), f"exact membership: {label}")
        if "member_count" in index:
            check(len(stored) == index["member_count"], f"declared count: {label}")
        pins = []
        for path, raw in ((index_path, index_raw), (archive_path, archive_raw)):
            if source:
                check(git("show", source + ":" + str(path)) == raw, f"incoming commit bytes: {path}")
                obj = git("rev-parse", source + ":" + str(path)).decode().strip()
                pin_scope = "incoming_commit"
            else:
                check(git("show", ":" + str(path)) == raw, f"staged bytes: {path}")
                obj = git("rev-parse", ":" + str(path)).decode().strip()
                pin_scope = "index_only_pending_commit"
            pins.append({"path": str(path), "scope": pin_scope, "git_blob": obj, "bytes": len(raw), "sha256": sha(raw)})
        stable_pairs = []
        for name in stored:
            if "source-before.json" in name:
                after = name.replace("source-before.json", "source-after.json")
                if after in stored:
                    check(stored[name] == stored[after], f"preparation source changed: {name}")
                    stable_pairs.append({"before": name, "after": after, "byte_identical": True})
        reports.append({
            "label": label, "source_commit": source, "archive": str(archive_path),
            "archive_bytes": len(archive_raw), "archive_sha256": sha(archive_raw),
            "index": str(index_path), "index_sha256": sha(index_raw),
            "member_count": len(stored), "exact_membership_verified": True,
            "all_member_lengths_and_sha256_verified": True,
            "regular_members_only": True, "unsafe_or_duplicate_members": [],
            "pins": pins, "source_before_after_pairs": stable_pairs,
            "members": [{"path": name, "bytes": len(raw), "sha256": sha(raw)} for name, raw in sorted(stored.items())],
            "passed": True,
        })
    result = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "Archive and index integrity of preparation evidence only. No current gate acceptance, new application execution, external runtime reconstruction, real-account send, installed-platform or browser claim.",
        "script_sha256": sha(Path(__file__).read_bytes()),
        "archives": reports, "archive_count": len(reports),
        "total_members": sum(row["member_count"] for row in reports),
        "all_passed": all(row["passed"] for row in reports),
    }
    output = ROOT / "preparation-archives-independent-audit.json"
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"output": str(output), "all_passed": result["all_passed"], "archives": [{k: row[k] for k in ("label", "member_count", "archive_bytes", "archive_sha256")} for row in reports]}))


if __name__ == "__main__":
    main()
