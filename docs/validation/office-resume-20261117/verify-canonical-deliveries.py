#!/usr/bin/env python3
"""Read back source-bound evidence archives and exact retained Git objects.

This verifier performs no product tests and never changes a checkout.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def member_map(index):
    entries = index.get("members", index.get("files"))
    if isinstance(entries, list):
        return {entry["path"]: {k: entry[k] for k in ("bytes", "sha256")}
                for entry in entries}
    return entries


def readback(data, index):
    assert len(data) == index["archive_bytes"]
    assert sha(data) == index["archive_sha256"]
    expected = member_map(index)
    assert expected
    prefix = index.get("archive_root", "")
    actual = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
        for item in archive:
            assert not PurePosixPath(item.name).is_absolute()
            assert ".." not in PurePosixPath(item.name).parts
            if item.isdir():
                continue
            assert item.isfile(), item.name
            name = item.name
            if prefix:
                assert name.startswith(prefix + "/"), name
                name = name[len(prefix) + 1:]
            assert name not in actual, name
            body = archive.extractfile(item).read()
            actual[name] = {"bytes": len(body), "sha256": sha(body)}
    assert actual == expected
    assert len(actual) == index.get("archive_member_count", index.get("file_count", len(actual)))
    return {"archive": index["archive"], "archive_bytes": len(data),
            "archive_sha256": sha(data), "members_verified": len(actual),
            "all_member_hashes_and_sizes_match": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--delivery-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    def git_object(commit, path):
        return subprocess.check_output(["git", "-C", str(args.repo), "show", f"{commit}:{path}"])

    deliveries, retained, observed = [], [], set()
    for short in ("4c49b043", "def52d84"):
        directory = args.delivery_root / ("qualified-" + short)
        index = json.loads((directory / f"canonical-qualified-{short}-index.json").read_text())
        data = (directory / index["archive"]).read_bytes()
        result = readback(data, index)
        result.update(source_commit=index["qualified_source_commit"], source_tree=index["qualified_source_tree"])
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
            receipt = archive.extractfile("run/receipt.json").read()
            assert sha(receipt) == index["receipt_sha256"]
            payload = json.loads(receipt)
            assert payload["status"] == "passed"
            assert payload["source_commit"] == index["qualified_source_commit"]
            setup = [m.name for m in archive if m.isfile() and m.name.startswith("setup/")]
            assert any(name.endswith("prepare-canonical.py") for name in setup)
            assert any(name.endswith("prepare-canonical-tools.py") for name in setup)
            assert any(name.endswith("canonical-workspace-setup.json") for name in setup)
            assert any(name.endswith("canonical-pub-get.log") for name in setup)
            result.update(receipt_sha256=sha(receipt), setup_members_verified=len(setup))
        deliveries.append(result)
        for reference in index["prior_archive_references"]:
            key = (reference["available_at_commit"], reference["path"])
            if key in observed:
                continue
            observed.add(key)
            body = git_object(*key)
            assert len(body) == reference["bytes"]
            assert sha(body) == reference["sha256"]
            index_path = reference["path"][:-len(".tar.xz")] + "-index.json"
            prior_index = json.loads(git_object(key[0], index_path))
            check = readback(body, prior_index)
            check.update(commit=key[0], path=key[1], index_path=index_path)
            retained.append(check)

    # Verify the original publication checkpoint, not only later descendants.
    original_commit = "104b239c971ef3b2d62495a27ad04b519398a1fc"
    original_path = "docs/validation/office-continuation-20261117/resumption/qualification-preflight-b32dee6f.tar.xz"
    original_index_path = original_path[:-len(".tar.xz")] + "-index.json"
    original_index = json.loads(git_object(original_commit, original_index_path))
    original = readback(git_object(original_commit, original_path), original_index)
    assert original_index["source_commit"] == "b32dee6f1fb6993c928a466b553226209cf27fb8"
    assert original_index["product_tests_run"] == 0
    original.update(commit=original_commit, path=original_path,
                    index_path=original_index_path,
                    qualified_source=original_index["source_commit"], product_tests_run=0)

    report = {"accepted": True, "product_tests_executed_by_verifier": False,
              "git_objects_read_only": True,
              "delivery_archives": deliveries,
              "retained_archives_at_recorded_commits": retained,
              "original_104b_failed_preflight_and_setup": original,
              "verifier_sha256": sha(Path(__file__).read_bytes())}
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"accepted": True, "delivery_archives": len(deliveries),
                      "retained_git_objects": len(retained),
                      "original_104b_verified": True, "output": str(args.output)}))


if __name__ == "__main__":
    main()
