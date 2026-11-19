#!/usr/bin/env python3
"""Independently verify exact evidence member sets, original bytes, and optional Git publication."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_relative(name: str) -> bool:
    path = PurePosixPath(name)
    return bool(name) and name != "." and not path.is_absolute() and ".." not in path.parts and str(path) == name and "\\" not in name


def audit(repo: Path, manifest_path: Path, published: str | None, manifest_git_path: str | None) -> dict:
    failures: list[str] = []

    def require(value: bool, message: str) -> None:
        if not value:
            failures.append(message)

    def git(*args: str) -> bytes:
        return subprocess.check_output(["git", "-C", str(repo), *args])

    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    require(manifest.get("schema") == 1, "Manifest schema must be 1")
    entries = manifest["archives"]
    require(bool(entries), "Manifest must select at least one archive")
    source = git("rev-parse", "--verify", manifest["source_commit"] + "^{commit}").decode().strip()
    publication = None
    publication_checks = None
    if published is not None:
        publication = git("rev-parse", "--verify", published + "^{commit}").decode().strip()
        git_path = manifest_git_path or str(manifest_path.relative_to(repo))
        require(canonical_relative(git_path), "Manifest Git path must be canonical and relative")
        publication_checks = {
            "manifest_bytes_equal_git_blob": git("show", publication + ":" + git_path) == manifest_bytes,
            "qualified_source_is_ancestor": subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", source, publication], capture_output=True).returncode == 0,
        }
        for key, valid in publication_checks.items():
            require(valid, "Publication: " + key)
    paths = [row[key] for row in entries for key in ("archive", "index")]
    require(len(paths) == len(set(paths)), "Archive/index paths must be unique")
    results = []
    for item in entries:
        require(canonical_relative(item["archive"]) and canonical_relative(item["index"]), "Noncanonical archive/index path: " + item["name"])
        archive_path, index_path = repo / item["archive"], repo / item["index"]
        require(archive_path.resolve().is_relative_to(repo) and index_path.resolve().is_relative_to(repo), "Archive/index leaves repository: " + item["name"])
        archive_bytes, index_bytes = archive_path.read_bytes(), index_path.read_bytes()
        index = json.loads(index_bytes)
        checks = {
            "index_schema": index.get("schema") == 1,
            "archive_name_matches_index": index["archive"] == archive_path.name,
            "archive_size_matches_index_and_manifest": len(archive_bytes) == index["archive_bytes"] == item["archive_bytes"],
            "archive_hash_matches_index_and_manifest": sha(archive_bytes) == index["archive_sha256"] == item["archive_sha256"],
            "index_size_matches_manifest": len(index_bytes) == item["index_bytes"],
            "index_hash_matches_manifest": sha(index_bytes) == item["index_sha256"],
            "source_identity_matches_manifest": index.get("source_commit") == item.get("source_commit"),
            "publication_source_matches_manifest": index.get("publication_source_commit") == source,
            "scope_matches_manifest": index["scope"] == item["scope"],
        }
        if publication is not None:
            checks.update(
                archive_bytes_equal_published_git_blob=git("show", publication + ":" + item["archive"]) == archive_bytes,
                index_bytes_equal_published_git_blob=git("show", publication + ":" + item["index"]) == index_bytes,
            )
        expected_rows = index["members"]
        expected = {row["path"]: row for row in expected_rows}
        checks["unique_index_member_paths"] = len(expected) == len(expected_rows)
        checks["indexed_member_count_matches_manifest"] = len(expected_rows) == item["member_count"]
        for name in expected:
            require(canonical_relative(name), item["name"] + ": noncanonical indexed member " + repr(name))
        member_results, names = [], []
        with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:*") as archive:
            for member in archive:
                names.append(member.name)
                if not canonical_relative(member.name) or not member.isfile() or member.issparse():
                    failures.append(item["name"] + ": unsafe or nonregular member " + repr(member.name))
                    continue
                row = expected.get(member.name)
                if row is None:
                    failures.append(item["name"] + ": unindexed member " + member.name)
                    continue
                stream = archive.extractfile(member)
                assert stream is not None
                data = stream.read()
                original = Path(row["original"])
                original_ok = original.is_absolute() and original.is_file() and not original.is_symlink()
                original_bytes = original.read_bytes() if original_ok else None
                member_checks = {
                    "tar_size_matches_payload_and_index": member.size == len(data) == row["bytes"],
                    "payload_hash_matches_index": sha(data) == row["sha256"],
                    "original_is_absolute_regular_file": original_ok,
                    "original_bytes_equal_archived_payload": original_bytes == data,
                }
                for key, valid in member_checks.items():
                    require(valid, item["name"] + "/" + member.name + ": " + key)
                member_results.append({"path": member.name, "original": str(original), "bytes": len(data), "sha256": sha(data), "checks": member_checks})
        checks.update(
            unique_archive_member_paths=len(names) == len(set(names)),
            exact_archive_and_index_member_path_sets=set(names) == set(expected),
            all_indexed_members_verified=len(member_results) == len(expected_rows),
        )
        if "reused_from" in index:
            reused = index["reused_from"]
            old_archive = Path(reused["archive"]).read_bytes()
            old_index_bytes = Path(reused["index"]).read_bytes()
            old_index = json.loads(old_index_bytes)
            normalize = lambda rows: sorted((r["path"], r["bytes"], r["sha256"]) for r in rows)
            checks.update(
                prebuilt_archive_bytes_preserved=old_archive == archive_bytes,
                prebuilt_archive_hash_preserved=sha(old_archive) == reused["archive_sha256"],
                prebuilt_index_hash_preserved=sha(old_index_bytes) == reused["index_sha256"],
                prebuilt_index_member_identities_preserved=normalize(old_index["members"]) == normalize(expected_rows),
            )
        for key, valid in checks.items():
            require(valid, item["name"] + ": " + key)
        results.append({"name": item["name"], "archive": item["archive"], "index": item["index"], "scope": item["scope"], "source_commit": item.get("source_commit"), "archive_sha256": sha(archive_bytes), "index_sha256": sha(index_bytes), "checks": checks, "member_count": len(member_results), "members": member_results})
    return {
        "schema": 1, "status": "PASS" if not failures else "FAIL",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": source, "publication_commit": publication,
        "manifest_sha256": sha(manifest_bytes), "auditor_sha256": sha(Path(__file__).read_bytes()),
        "archive_count": len(results), "verified_member_count": sum(row["member_count"] for row in results),
        "publication_checks": publication_checks, "archives": results, "failures": failures,
        "scope": {"exact_member_sets_and_hashes": True, "compared_to_original_files": True, "published_git_blobs_checked": publication is not None, "archive_members_extracted_to_disk": False, "application_tests_executed": False, "application_events_recounted": False, "branch_inventories_captured": False, "github_actions_accessed": False, "counts": "Counts describe archives and evidence members only, never application tests."},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--published")
    parser.add_argument("--manifest-git-path")
    args = parser.parse_args()
    if args.manifest_git_path and not args.published:
        parser.error("--manifest-git-path requires --published")
    try:
        report = audit(args.repo.resolve(), args.manifest.resolve(), args.published, args.manifest_git_path)
    except Exception as error:
        report = {"schema": 1, "status": "FAIL", "failures": [repr(error)], "auditor_sha256": sha(Path(__file__).read_bytes())}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("status", "source_commit", "publication_commit", "archive_count", "verified_member_count", "failures") if key in report}))
    if report["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
