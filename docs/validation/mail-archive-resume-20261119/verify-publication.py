#!/usr/bin/env python3
"""Bind a publication/merge tree to locally accepted mail source inputs.

Read-only: does not modify source, resolve dependencies, query CI or update refs.
Run before publication and again against the fetched remote-main merge commit.
"""

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess


PREFIX = "docs/validation/mail-archive-resume-20261119/"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", default="HEAD")
    parser.add_argument("--expected-tree")
    parser.add_argument("--require-ancestor", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("retain the previous verification and use a new output path")
    repo = Path(__file__).resolve().parents[3]

    def git(*command):
        return subprocess.check_output(["git", *command], cwd=repo)

    candidate = git("rev-parse", "--verify", args.candidate + "^{commit}").decode().strip()
    tree = git("rev-parse", candidate + "^{tree}").decode().strip()
    if args.expected_tree:
        require(tree == args.expected_tree, "Publication tree differs")
    receipt_raw = git("show", candidate + ":" + PREFIX + "final/receipt.json")
    receipt = json.loads(receipt_raw)
    audit_raw = git("show", candidate + ":" + PREFIX + "independent-audit.json")
    audit = json.loads(audit_raw)
    require(receipt["status"] == "passed", "Mail acceptance failed")
    require(audit["status"] == "passed" and not audit["failures"], "Independent audit failed")
    require(receipt.get("github_actions_used") is False and audit.get("github_actions_used") is False,
            "Unexpected GitHub Actions claim")
    source = receipt["source_head"]
    source_tree = git("rev-parse", source + "^{tree}").decode().strip()
    require(source_tree == receipt["source_tree"], "Accepted source tree differs from Git")
    mail_audit = audit["mail"]
    require(mail_audit["source_head"] == source and mail_audit["source_tree"] == source_tree,
            "Independent audit names a different mail source")
    receipt_sha256 = hashlib.sha256(receipt_raw).hexdigest()
    require(mail_audit["receipt_sha256"] == receipt_sha256,
            "Independent audit covers a different mail receipt")
    require(mail_audit["test_counts"] == receipt["test_totals"],
            "Mail test totals differ from independent replay")
    auditor_raw = git("show", candidate + ":" + PREFIX + "audit-validation.py")
    require(hashlib.sha256(auditor_raw).hexdigest() == audit["auditor_sha256"],
            "Published auditor differs from the executed independent audit")
    incoming_raw = git("show", candidate + ":" + PREFIX + "incoming/acceptance-inventory.json")
    incoming = json.loads(incoming_raw)
    incoming_audit = audit["incoming"]
    incoming_sha256 = hashlib.sha256(incoming_raw).hexdigest()
    require(incoming["status"] == "passed", "Incoming acceptance inventory failed")
    require(incoming_sha256 == incoming_audit["inventory_sha256"],
            "Independent audit covers a different incoming inventory")
    require([(g["name"], g["path"]) for g in incoming["accepted_groups"]]
            == [(g["name"], g["path"]) for g in incoming_audit["groups"]],
            "Incoming accepted group inventory differs from independent replay")
    require(audit["replayed_test_executions"]
            == sum(receipt["test_totals"].values()) + sum(incoming_audit["test_counts"].values()),
            "Combined test totals differ from independent replay")
    required = sorted(set([source, audit["current_head"], *args.require_ancestor]))
    for ancestor in required:
        subprocess.run(["git", "merge-base", "--is-ancestor", ancestor, candidate],
                       cwd=repo, check=True)
    changed = git("diff", "--name-only", source, candidate).decode().splitlines()
    require(all(path.startswith("docs/validation/") for path in changed),
            "Changes outside validation documentation: " + repr(changed))

    inventory = json.loads(gzip.decompress(git(
        "show", candidate + ":" + PREFIX + "final/source-before.json.gz")))
    after = json.loads(gzip.decompress(git(
        "show", candidate + ":" + PREFIX + "final/source-after.json.gz")))
    require(inventory == after, "Accepted source inputs changed during testing")
    require(bool(inventory) and len(inventory) == receipt["source_inputs"],
            "Accepted source input count differs")
    require(digest(inventory) == receipt["source_digest"], "Accepted source inventory digest differs")
    for kind in ("source", "dependency", "runtime"):
        binding = mail_audit["bound_inputs"][kind]
        require(binding["inputs"] == receipt[kind + "_inputs"]
                and binding["digest"] == receipt[kind + "_digest"]
                and binding["before_after_equal"] is True
                and binding["current_identity_failures"] == 0,
                "Independent input binding differs: " + kind)
    entries = {}
    for record in git("ls-tree", "-rz", candidate).split(b"\0"):
        if record:
            metadata, path = record.split(b"\t", 1)
            mode, kind, oid = metadata.decode().split()
            entries[path.decode()] = (mode, kind, oid)
    for path, identity in inventory.items():
        data = (repo / path).read_bytes()
        require(len(data) == identity["bytes"], "Input byte length changed: " + path)
        require(hashlib.sha256(data).hexdigest() == identity["sha256"], "Input digest changed: " + path)
        git_blob = hashlib.sha1(
            b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        require(entries[path][1:] == ("blob", git_blob), "Candidate Git blob differs: " + path)
        require(not (repo / path).is_symlink(), "Input replaced by symbolic link: " + path)
        executable = bool((repo / path).stat().st_mode & 0o100)
        require(executable == (entries[path][0] == "100755"), "Input executable mode differs: " + path)

    output = {
        "status": "passed",
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "candidate_commit": candidate,
        "candidate_tree": tree,
        "candidate_parents": git("show", "-s", "--format=%P", candidate).decode().split(),
        "accepted_source_commit": source,
        "accepted_source_tree": source_tree,
        "required_ancestors": required,
        "source_inputs_rehashed": len(inventory),
        "all_source_inputs_match_accepted_inventory_and_candidate_git_blobs": True,
        "all_changes_since_accepted_source_are_validation_documentation": True,
        "changes_since_accepted_source": changed,
        "mail_receipt_sha256": receipt_sha256,
        "independent_audit_sha256": hashlib.sha256(audit_raw).hexdigest(),
        "executed_auditor_sha256": audit["auditor_sha256"],
        "incoming_inventory_sha256": incoming_sha256,
        "accepted_test_executions": audit["replayed_test_executions"],
        "acceptance_receipt_auditor_and_incoming_inventory_are_linked": True,
        "github_actions_used": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps({key: output[key] for key in (
        "status", "candidate_commit", "candidate_tree", "source_inputs_rehashed")}))


if __name__ == "__main__":
    main()
