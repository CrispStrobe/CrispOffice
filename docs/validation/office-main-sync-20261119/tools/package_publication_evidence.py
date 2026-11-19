#!/usr/bin/env python3
"""Package explicitly mapped evidence files, or preserve a prebuilt archive verbatim."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_name(value: str) -> str:
    path = PurePosixPath(value)
    if not value or value == "." or path.is_absolute() or ".." in path.parts or str(path) != value or "\\" in value:
        raise ValueError("Noncanonical relative path: " + repr(value))
    return value


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--spec", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    spec_bytes = args.spec.read_bytes()
    spec = json.loads(spec_bytes)
    if spec.get("schema") != 1 or not spec.get("archives"):
        raise ValueError("Expected schema 1 and a nonempty archives list")
    source = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "--verify", spec["source_commit"] + "^{commit}"], text=True).strip()
    manifest_path = args.manifest.resolve()
    if manifest_path.exists():
        raise FileExistsError("Preserve the prior manifest: " + str(manifest_path))
    targets = []
    for item in spec["archives"]:
        for key in ("archive", "index"):
            target = repo / safe_name(item[key])
            if not target.resolve().is_relative_to(repo) or target.resolve() == manifest_path or target.exists() or target in targets:
                raise ValueError("Unsafe, repeated, or existing output: " + str(target))
            targets.append(target)
    published = []
    for item in spec["archives"]:
        archive_path, index_path = repo / item["archive"], repo / item["index"]
        archive_path.parent.mkdir(parents=True, exist_ok=True)
        index_path.parent.mkdir(parents=True, exist_ok=True)
        reuse = "reuse_archive" in item
        imported = None
        if reuse:
            original_archive = Path(item["reuse_archive"]).resolve()
            original_index = Path(item["reuse_index"]).resolve()
            original_index_bytes = original_index.read_bytes()
            old_index = json.loads(original_index_bytes)
            archive_bytes = original_archive.read_bytes()
            if digest(archive_bytes) != old_index.get("archive_sha256", old_index.get("sha256")) or len(archive_bytes) != old_index.get("archive_bytes", old_index.get("bytes")):
                raise ValueError("Prebuilt archive does not match its original index")
            root = Path(item["original_root"]).resolve()
            mappings = [{"path": row["path"], "original": str(root / safe_name(row["path"]))} for row in old_index["members"]]
            imported = {"archive": str(original_archive), "index": str(original_index), "archive_sha256": digest(archive_bytes), "index_sha256": digest(original_index_bytes)}
        else:
            mappings = item["members"]
        if not mappings:
            raise ValueError("Empty archive selection: " + item["name"])
        names = [safe_name(row["path"]) for row in mappings]
        if len(names) != len(set(names)):
            raise ValueError("Duplicate mapped archive member")
        members, contents = [], {}
        for row in sorted(mappings, key=lambda value: value["path"]):
            original = Path(row["original"])
            if not original.is_absolute() or original.is_symlink() or not original.is_file():
                raise ValueError("Original must be an absolute regular file: " + str(original))
            data = original.read_bytes()
            members.append({"path": row["path"], "original": str(original.resolve()), "bytes": len(data), "sha256": digest(data)})
            contents[row["path"]] = data
        if reuse:
            expected = {row["path"]: row for row in old_index["members"]}
            if len(expected) != len(old_index["members"]):
                raise ValueError("Duplicate prebuilt index member")
            for row in members:
                if row["bytes"] != expected[row["path"]]["bytes"] or row["sha256"] != expected[row["path"]]["sha256"]:
                    raise ValueError("Prebuilt original differs: " + row["path"])
            actual = []
            with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:*") as archive:
                for member in archive:
                    name = safe_name(member.name)
                    if not member.isfile() or member.issparse() or name not in contents:
                        raise ValueError("Invalid prebuilt member: " + name)
                    stream = archive.extractfile(member)
                    assert stream is not None
                    if stream.read() != contents[name]:
                        raise ValueError("Prebuilt member differs from original: " + name)
                    actual.append(name)
            if len(actual) != len(set(actual)) or set(actual) != set(contents):
                raise ValueError("Prebuilt member set differs")
            shutil.copyfile(original_archive, archive_path)
        else:
            with tarfile.open(archive_path, mode="w:xz", format=tarfile.PAX_FORMAT) as archive:
                for row in members:
                    info = tarfile.TarInfo(row["path"])
                    info.size, info.mode, info.mtime = row["bytes"], 0o644, 0
                    archive.addfile(info, io.BytesIO(contents[row["path"]]))
        archive_bytes = archive_path.read_bytes()
        index = {
            "schema": 1, "archive": archive_path.name,
            "archive_bytes": len(archive_bytes), "archive_sha256": digest(archive_bytes),
            "source_commit": item.get("source_commit", source),
            "publication_source_commit": source, "scope": item["scope"], "members": members,
        }
        if imported is not None:
            index["reused_from"] = imported
        write_json(index_path, index)
        published.append({
            "name": item["name"], "archive": item["archive"], "index": item["index"],
            "scope": item["scope"], "source_commit": index["source_commit"],
            "archive_bytes": len(archive_bytes), "archive_sha256": digest(archive_bytes),
            "index_bytes": index_path.stat().st_size, "index_sha256": digest(index_path.read_bytes()),
            "member_count": len(members),
        })
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    write_json(manifest_path, {
        "schema": 1, "source_commit": source,
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "spec_sha256": digest(spec_bytes), "packer_sha256": digest(Path(__file__).read_bytes()),
        "archives": published,
        "scope": "Byte-preserving evidence publication. Archive/member counts are not application test counts. Historical and development evidence retain their separate scopes.",
    })
    print(json.dumps({"manifest": str(manifest_path), "archives": len(published), "members": sum(a["member_count"] for a in published)}))


if __name__ == "__main__":
    main()
