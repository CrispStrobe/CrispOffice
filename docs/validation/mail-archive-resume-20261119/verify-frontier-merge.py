#!/usr/bin/env python3
"""Replay the recorded GUI merge's complete tree without fetching or writing Git."""

import hashlib
import json
import pathlib
import subprocess


HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]


def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=REPO)


def entries(commit):
    result = {}
    for row in git("ls-tree", "-rz", "--full-tree", commit).split(b"\0"):
        if not row:
            continue
        metadata, path = row.split(b"\t", 1)
        result[path] = tuple(metadata.split())
    return result


def tree_sha(files):
    tree = {}
    for path, info in files.items():
        parts = path.split(b"/")
        directory = tree
        for part in parts[:-1]:
            directory = directory.setdefault(part, {})
        directory[parts[-1]] = info

    def digest(directory):
        data = b""
        ordered = sorted(directory.items(), key=lambda item: item[0] +
                         (b"/" if isinstance(item[1], dict) else b""))
        for name, value in ordered:
            if isinstance(value, dict):
                mode, sha = b"40000", digest(value)
            else:
                mode, _kind, encoded_sha = value
                sha = encoded_sha.decode()
            data += mode + b" " + name + b"\0" + bytes.fromhex(sha)
        return hashlib.sha1(b"tree " + str(len(data)).encode() + b"\0" + data).hexdigest()

    return digest(tree)


def main():
    evidence = json.loads((HERE / "post-freeze-gui-observation.json").read_text())
    base, imported = evidence["remote_parents"]
    base_files, imported_files = entries(base), entries(imported)
    reconstructed = dict(base_files)
    paths = []
    for changed in evidence["files"]:
        path = changed["path"].encode()
        mode, kind, sha = imported_files[path]
        paths.append({**changed, "imported_parent_mode": mode.decode(),
                      "imported_parent_type": kind.decode(),
                      "imported_parent_blob": sha.decode(),
                      "equals_imported_parent_blob": sha.decode() == changed["blob"]})
        reconstructed[path] = imported_files[path]
    base_tree = git("rev-parse", base + "^{tree}").decode().strip()
    actual_base, union = tree_sha(base_files), tree_sha(reconstructed)
    parents_ancestors = [subprocess.run(
        ["git", "merge-base", "--is-ancestor", parent, evidence["frozen_source"]],
        cwd=REPO).returncode == 0 for parent in evidence["remote_parents"]]
    result = {
        "schema_version": 1,
        "frozen_source": evidence["frozen_source"],
        "remote_commit": evidence["remote_commit"],
        "parents": evidence["remote_parents"],
        "parents_already_ancestors": parents_ancestors,
        "first_parent_tree": base_tree,
        "first_parent_reconstructed_tree": actual_base,
        "remote_tree": evidence["remote_tree"],
        "union_reconstructed_tree": union,
        "file_count": len(reconstructed), "changed_path_count": len(paths),
        "paths": paths,
        "passed": actual_base == base_tree and union == evidence["remote_tree"] and
                  all(parents_ancestors) and
                  all(path["equals_imported_parent_blob"] for path in paths),
        "proof": "Complete first-parent tree with exactly the API-listed paths replaced "
                 "by the second-parent mode/type/blob entries reconstructs the remote "
                 "Git tree SHA. Both parent commits are ancestors of the frozen source. "
                 "This proves the remote merge has no content other than the two already "
                 "integrated parents; it does not claim the remote merge is an ancestor.",
        "local_ref_or_source_mutation": False,
        "github_actions_queried_or_awaited": False,
    }
    (HERE / "post-freeze-gui-proof.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: value for key, value in result.items() if key != "paths"}, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
