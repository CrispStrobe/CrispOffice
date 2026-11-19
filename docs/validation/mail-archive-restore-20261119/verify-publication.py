#!/usr/bin/env python3
"""Check a publication commit against the accepted source and evidence."""

import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", default="HEAD")
    parser.add_argument("--expected-tree")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    prefix = "docs/validation/mail-archive-restore-20261119/"
    evidence = "1a99845fe628c9e539d4bca7e7c586c5616da267"
    incoming = "cf59efa99232a3fd26cf21ce7f2382402e576f9b"

    def git(*argv):
        return subprocess.check_output(["git", *argv], cwd=repo)

    candidate = git("rev-parse", args.candidate).decode().strip()
    tree = git("rev-parse", candidate + "^{tree}").decode().strip()
    if args.expected_tree:
        assert tree == args.expected_tree
    receipt_bytes = git("show", candidate + ":" + prefix + "final/receipt.json")
    receipt = json.loads(receipt_bytes)
    audit_bytes = git("show", candidate + ":" + prefix + "independent-audit.json")
    audit = json.loads(audit_bytes)
    assert receipt["status"] == audit["status"] == "passed"
    assert audit["mail_receipt_sha256"] == hashlib.sha256(receipt_bytes).hexdigest()
    source = receipt["source_head"]
    assert audit["frozen_source_head"] == source
    for ancestor in (source, evidence, incoming):
        subprocess.run(
            ["git", "merge-base", "--is-ancestor", ancestor, candidate],
            cwd=repo,
            check=True,
        )
    changed = git("diff", "--name-only", source, candidate).decode().splitlines()
    assert all(path.startswith(prefix) for path in changed)
    publication_paths = git("diff", "--name-only", evidence, candidate).decode().splitlines()
    allowed = {
        prefix + name
        for name in (
            "README.md", "publication-check.json", "publication-frontier.json",
            "publication-remote-refs.txt", "verify-publication.py",
        )
    }
    assert set(publication_paths) <= allowed
    inventory = json.loads(gzip.decompress(git(
        "show", candidate + ":" + prefix + "final/source-before.json.gz"
    )))
    entries = {}
    for record in git("ls-tree", "-r", "-z", candidate).split(b"\0"):
        if record:
            metadata, path = record.split(b"\t", 1)
            entries[path.decode()] = metadata.split()[2].decode()
    for path, identity in inventory.items():
        data = (repo / path).read_bytes()
        assert len(data) == identity["bytes"], path
        assert hashlib.sha256(data).hexdigest() == identity["sha256"], path
        git_blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        assert git_blob == entries[path], path
    result = {
        "status": "passed",
        "checked_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "candidate_commit": candidate,
        "candidate_tree": tree,
        "accepted_source_commit": source,
        "accepted_source_tree": receipt["source_tree"],
        "evidence_commit": evidence,
        "integrated_main_commit": incoming,
        "source_evidence_and_incoming_are_ancestors": True,
        "all_changes_since_accepted_source_are_validation_documentation": True,
        "post_evidence_changes": publication_paths,
        "source_inputs_rehashed": len(inventory),
        "source_inputs_match_accepted_inventory_and_candidate_git_blobs": True,
        "mail_receipt_sha256": hashlib.sha256(receipt_bytes).hexdigest(),
        "independent_audit_sha256": hashlib.sha256(audit_bytes).hexdigest(),
        "verified_test_totals": audit["combined_counts"],
        "verified_test_files": audit["combined_unique_test_files"],
        "github_actions_used": False,
        "note": "This check binds the named candidate. The final publication commit adds only the allowlisted documentation; its merge tree is checked again after publication.",
    }
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "candidate": candidate, "tree": tree, "source_inputs": len(inventory)}))


if __name__ == "__main__":
    main()
