#!/usr/bin/env python3
"""Audit captured refs and 14 historical equivalents using immutable Git data.

Use --head for an actual integrated commit, or repeat --union-head to assess
the graph coverage of a proposed union. A union assessment is explicitly not
evidence that the merge exists or that its conflict resolutions are correct.
Inputs accept `sha ref` (ls-remote) or `ref sha` (for-each-ref). This program
never fetches, checks out, updates refs/index, invokes CI, or executes product
code. Git lazy fetching is disabled; only the JSON output is written.
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


BASELINE = "0e84dc951e7a9e923107d7895fa457cf29a7af71"
PROOF_PATH = "docs/validation/thesaurus-20261118/resume/incoming-audit.json"
SHA1 = re.compile(r"[0-9a-f]{40}\Z")


def digest(data):
    return hashlib.sha256(data).hexdigest()


class Auditor:
    def __init__(self, repo, heads):
        self.repo = repo.resolve()
        self.command_count = 0
        self.heads = list(dict.fromkeys(self.commit(head) for head in heads))
        self.ancestor_cache = {}
        self.entries_cache = {}

    def run(self, *args, allow_false=False):
        self.command_count += 1
        result = subprocess.run(
            ["git", "--no-lazy-fetch", "-C", str(self.repo), *args],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        if result.returncode and not (allow_false and result.returncode == 1):
            raise RuntimeError(
                f"git {' '.join(args)} failed ({result.returncode}): "
                + result.stderr.decode(errors="replace").strip()
            )
        return result

    def raw(self, *args):
        return self.run(*args).stdout

    def text(self, *args):
        return self.raw(*args).decode().strip()

    def commit(self, ref):
        return self.text("rev-parse", "--verify", "--end-of-options", ref + "^{commit}")

    def ancestor(self, old, new):
        key = (old, new)
        if key not in self.ancestor_cache:
            self.ancestor_cache[key] = self.run(
                "merge-base", "--is-ancestor", old, new, allow_false=True
            ).returncode == 0
        return self.ancestor_cache[key]

    def containing_heads(self, commit):
        return [head for head in self.heads if self.ancestor(commit, head)]

    def changed_paths(self, old, new):
        return self.raw(
            "diff", "--no-renames", "--name-only", "-z", old, new, "--"
        ).decode().rstrip("\0").split("\0") if old != new else []

    def entries(self, commit, paths):
        key = (commit, tuple(paths))
        if key not in self.entries_cache:
            entries = {path: None for path in paths}
            data = self.raw("ls-tree", "-z", commit, "--", *paths)
            for raw in data.rstrip(b"\0").split(b"\0"):
                if not raw:
                    continue
                meta, path = raw.decode().split("\t", 1)
                mode, kind, oid = meta.split()
                entries[path] = {"mode": mode, "type": kind, "object": oid}
            self.entries_cache[key] = entries
        return self.entries_cache[key]

    def state(self):
        return {
            "head": self.text("rev-parse", "HEAD"),
            "refs_sha256": digest(self.raw("for-each-ref", "--format=%(refname) %(objectname)")),
            "index_listing_sha256": digest(self.raw("ls-files", "--stage", "-z")),
        }

    def historical_proofs(self):
        proof_bytes = self.raw("show", BASELINE + ":" + PROOF_PATH)
        records = json.loads(proof_bytes)["historical_equivalence"]
        if len(records) != 14 or len({row["sha"] for row in records}) != 14:
            raise ValueError("Expected exactly 14 unique historical proof heads")
        baseline_heads = self.containing_heads(BASELINE)
        results = []
        for old in records:
            sha = old["sha"]
            disposition = old["disposition"]
            row = {
                "branch": old["branch"], "original_commit": sha,
                "historical_disposition": disposition,
                "original_is_ancestor_of_targets": self.containing_heads(sha),
                "baseline_is_ancestor_of_targets": baseline_heads,
            }
            try:
                if disposition == "identical_tree_already_integrated":
                    equivalent = old["equivalent_commit"]
                    row.update(
                        method="exact_complete_tree_identity",
                        equivalent_commit=equivalent,
                        original_tree=self.text("rev-parse", sha + "^{tree}"),
                        equivalent_tree=self.text("rev-parse", equivalent + "^{tree}"),
                        equivalent_is_ancestor_of_targets=self.containing_heads(equivalent),
                    )
                    row["passed"] = (
                        row["original_tree"] == row["equivalent_tree"]
                        and bool(row["equivalent_is_ancestor_of_targets"])
                    )
                elif disposition in (
                    "all_commits_patch_equivalent",
                    "all_changed_files_identical_in_merged_pr_140",
                ):
                    comparison = (
                        BASELINE if disposition == "all_commits_patch_equivalent"
                        else old["equivalent_commit"]
                    )
                    common = self.text("merge-base", sha, comparison)
                    paths = self.changed_paths(common, sha)
                    if not paths or any(not path for path in paths):
                        raise ValueError("Historical delta must have nonempty changed paths")
                    original_entries = self.entries(sha, paths)
                    if disposition == "all_commits_patch_equivalent":
                        # Search reachable historical snapshots, then establish exact
                        # mode/type/blob identity for the COMPLETE recomputed delta.
                        # This deliberately does not reuse an earlier git-cherry result.
                        candidates = self.text(
                            "rev-list", "--full-history", BASELINE, "^" + common,
                            "--", *paths,
                        ).splitlines()
                        equivalent = next(
                            (c for c in candidates if self.entries(c, paths) == original_entries),
                            None,
                        )
                        row["candidate_ancestor_count"] = len(candidates)
                        row["recomputed_original_nonmerge_commits"] = self.text(
                            "rev-list", "--no-merges", sha, "^" + BASELINE
                        ).splitlines()
                        row["historical_patch_result_reused"] = False
                    else:
                        equivalent = old["equivalent_commit"]
                        row["original_changed_path_list_matches"] = (
                            set(paths) == set(old["fresh_changed_files"])
                        )
                    equivalent_entries = self.entries(equivalent, paths) if equivalent else {}
                    row.update(
                        method="exact_complete_delta_path_mode_type_blob_identity",
                        recomputed_merge_base=common,
                        comparison_commit=comparison,
                        complete_delta_paths=paths,
                        equivalent_commit=equivalent,
                        equivalent_is_ancestor_of_targets=(
                            self.containing_heads(equivalent) if equivalent else []
                        ),
                        file_checks=[
                            {
                                "path": path,
                                "original_entry": original_entries[path],
                                "equivalent_entry": equivalent_entries.get(path),
                                "identical": (
                                    equivalent is not None
                                    and original_entries[path] == equivalent_entries.get(path)
                                ),
                            }
                            for path in paths
                        ],
                    )
                    row["passed"] = (
                        bool(row["equivalent_is_ancestor_of_targets"])
                        and all(check["identical"] for check in row["file_checks"])
                        and row.get("original_changed_path_list_matches", True)
                        and bool(baseline_heads)
                    )
                else:
                    raise ValueError("Unsupported historical proof: " + disposition)
            except (RuntimeError, ValueError, KeyError) as exc:
                row.update(passed=False, error=str(exc))
            results.append(row)
        return results, {
            "commit": BASELINE, "path": PROOF_PATH,
            "sha256": digest(proof_bytes),
        }


def canonical_ref(ref, upstream):
    if ref.endswith("^{}"):
        return ref, "peeled_tag_advertisement"
    if ref == "HEAD" or ref.endswith("/HEAD"):
        return ref, "head_alias"
    if re.fullmatch(r"refs/pull/\d+/merge", ref):
        return ref, "synthetic_pull_request_merge"
    if upstream:
        if ref.startswith("refs/remotes/upstream/"):
            ref = "refs/heads/" + ref.removeprefix("refs/remotes/upstream/")
        if ref.startswith("refs/heads/"):
            return ref, "upstream_branch"
        if re.fullmatch(r"refs/pull/\d+/head", ref):
            return ref, "upstream_pull_request_head"
        if ref.startswith("refs/tags/"):
            return ref, "upstream_tag"
        return ref, "unknown"
    if ref.startswith("refs/remotes/origin/"):
        ref = "refs/heads/" + ref.removeprefix("refs/remotes/origin/")
    if ref.startswith("refs/remotes/pr/"):
        ref = "refs/pull/" + ref.removeprefix("refs/remotes/pr/") + "/head"
    if ref.startswith("refs/heads/"):
        return ref, "fork_branch"
    if re.fullmatch(r"refs/pull/\d+/head", ref):
        return ref, "pull_request_head"
    if ref.startswith("refs/tags/"):
        return ref, "tag"
    return ref, "unknown"


def read_captures(fork_files, upstream_files):
    refs, inputs, seen = [], [], {}
    for path, upstream in [(p, False) for p in fork_files] + [(p, True) for p in upstream_files]:
        data = path.read_bytes()
        inputs.append({"file": path.name, "sha256": digest(data), "upstream": upstream})
        for number, line in enumerate(data.decode().splitlines(), 1):
            if not line.strip():
                continue
            fields = line.split()
            if len(fields) != 2:
                raise ValueError(f"{path}:{number}: expected exactly two columns")
            if SHA1.fullmatch(fields[0]):
                sha, ref = fields
            elif SHA1.fullmatch(fields[1]):
                ref, sha = fields
            else:
                raise ValueError(f"{path}:{number}: expected a full SHA-1")
            ref, kind = canonical_ref(ref, upstream)
            namespace = "upstream" if upstream else "fork"
            key = (namespace, ref)
            if key in seen:
                if seen[key] != sha:
                    raise ValueError(f"Conflicting captured heads for {namespace}:{ref}")
                continue
            seen[key] = sha
            refs.append({
                "namespace": namespace, "kind": kind, "ref": ref,
                "object_sha": sha, "capture_file": path.name,
            })
    return refs, inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--head", help="Actual integrated commit")
    target.add_argument("--union-head", action="append", help="Repeat for an anticipated union")
    parser.add_argument("--refs", type=Path, action="append", required=True)
    parser.add_argument("--upstream-refs", type=Path, action="append", default=[])
    parser.add_argument("--expected-total", type=int)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    auditor = Auditor(args.repo, [args.head] if args.head else args.union_head)
    before = auditor.state()
    proofs, proof_source = auditor.historical_proofs()
    by_sha = {row["original_commit"]: row for row in proofs}
    refs, inputs = read_captures(args.refs, args.upstream_refs)
    for row in refs:
        if row["kind"] == "synthetic_pull_request_merge":
            row["classification"] = "excluded_generated_merge_preview"
            continue
        try:
            commit = auditor.commit(row["object_sha"])
            heads = auditor.containing_heads(commit)
            row.update(commit=commit, ancestor_of_targets=heads)
            row["classification"] = (
                "ancestor" if heads else "historical_equivalent"
                if by_sha.get(commit, {}).get("passed") else "unaccounted"
            )
            if row["classification"] == "historical_equivalent":
                row["equivalence_proof_commit"] = commit
        except RuntimeError as exc:
            row.update(classification="missing_or_noncommit_object", error=str(exc))
    actual = [row for row in refs if row["kind"] not in (
        "head_alias", "peeled_tag_advertisement", "synthetic_pull_request_merge"
    )]
    unknown = [row for row in actual if row["classification"] not in (
        "ancestor", "historical_equivalent"
    ) or row["kind"] == "unknown"]
    count_matches = args.expected_total is None or len(actual) == args.expected_total
    passed = not unknown and all(p["passed"] for p in proofs) and count_matches
    after = auditor.state()
    mode = "integrated_commit" if args.head else "anticipated_union"
    report = {
        "schema": 2, "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "target_mode": mode,
        "targets": [{"commit": h, "tree": auditor.text("rev-parse", h + "^{tree}")} for h in auditor.heads],
        "inputs": inputs, "script_sha256": digest(Path(__file__).read_bytes()),
        "counts": dict(Counter(row["kind"] for row in actual)),
        "actual_reference_count": len(actual),
        "expected_reference_count": args.expected_total,
        "expected_reference_count_matches": count_matches,
        "alias_and_peeled_rows_excluded": sum(
            row["kind"] in ("head_alias", "peeled_tag_advertisement") for row in refs
        ),
        "synthetic_pr_merge_rows_excluded": sum(
            row["kind"] == "synthetic_pull_request_merge" for row in refs
        ),
        "excluded_non_source_advertisements": [
            row for row in refs if row["kind"] in (
                "head_alias", "peeled_tag_advertisement", "synthetic_pull_request_merge"
            )
        ],
        "distinct_object_count": len({r["object_sha"] for r in actual}),
        "distinct_commit_count": len({r["commit"] for r in actual if "commit" in r}),
        "classification": dict(Counter(row["classification"] for row in actual)),
        "historical_source_record": proof_source,
        "historical_equivalence_checks": proofs,
        "all_14_historical_equivalences_reverified": all(p["passed"] for p in proofs),
        "historical_heads_remain_nonancestors": all(not p["original_is_ancestor_of_targets"] for p in proofs),
        "unaccounted_refs": unknown, "refs": actual,
        "working_copy_observation": {"before": before, "after": after, "unchanged": before == after},
        "scope": (
            "Immutable captured-ref graph and historical source preservation only. "
            "Exact complete-delta blob/mode identity freshly replaces old patch-equivalence assertions. "
            "Historical equivalents remain non-ancestors. A union projection does not establish "
            "an actual merge tree, conflict resolution, or current product/runtime acceptance. "
            "HEAD aliases, peeled-tag advertisements and GitHub-generated PR merge previews "
            "are explicitly retained as excluded advertisements; branch, tag and PR-head "
            "source references are all accounted for."
        ),
        "git_lazy_fetch_disabled": True, "network_calls": 0,
        "github_actions_calls": 0, "repository_mutations_performed": 0,
        "read_only_git_commands": auditor.command_count,
        "passed": passed,
        "actual_integrated_graph_verified": passed and mode == "integrated_commit",
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report[k] for k in (
        "target_mode", "targets", "counts", "actual_reference_count", "classification",
        "all_14_historical_equivalences_reverified", "historical_heads_remain_nonancestors",
        "unaccounted_refs", "passed", "actual_integrated_graph_verified",
    )}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
