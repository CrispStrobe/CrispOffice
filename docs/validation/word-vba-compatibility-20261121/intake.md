# Initial incoming-work audit

All captured incoming heads are covered by main `e2abbcda6d19f932bfbacc85e0dafd41a3c478f8`
(tree `a8f93226e2ee40fcb22307348176d868f85efadf`). No additional feature merge is
required before this Word VBA increment.

## Captured scope

| Scope | Captured | Ancestor of baseline | Verified historical equivalent |
| --- | ---: | ---: | ---: |
| Fork branch heads | 46 | 36 | 10 |
| Most recently updated fork PR records | 100 | 98 | 2 |
| Upstream branch heads | 4 | 4 | 0 |
| Upstream PR records | 4 | 4 | 0 |

The explicit fork open-PR endpoint returned an empty list. The recent PR list
contains closed PR #202, whose VBA implementation head is already an ancestor.
The latest merged Word section, Mail session, Zotero transfer, proofing
scheduling, and keystroke performance work is included in this baseline.

The API observations were taken before creating the task checkpoint branch.
During intake, `codex/zotero-parity-20261121-next` advanced from the clone's
`fcb3ff13` to `e2abbcda`; the captured API head equals main and needs no merge.
This record is a snapshot. Refresh remote heads before final publication.

## Historical equivalence

These old branches are not ancestors under their original commit identities.
Their content is already represented by accepted ancestor commits. The audit
recomputed the comparisons; it did not merely trust a previous pass.

| Source branch | Source commit | Accepted ancestor | Comparison |
| --- | --- | --- | --- |
| codex/odt-field-continuation-20261117 | c3494576 | 2c47165d | All 37 changed paths |
| docs/ods-color-scale | 58fdddfb | 4eaca83b | Complete Git tree |
| docs/ods-data-bar | 69d14f84 | 52c73ae4 | Complete Git tree |
| feat/ods-color-scale | 74ce9ffb | 4584d5f3 | Complete Git tree |
| feat/ods-data-bar | 0a53b8a7 | b3f41eb4 | Complete Git tree |
| feat/ods-dynamic-validation-links | 68a0db23 | d754bf15 | Complete Git tree |
| feat/ods-icon-sets | 005c708e | c84d5e16 | Complete Git tree |
| feat/ods-time-period-conditions | 7ef09f24 | 34dc6b68 | Complete Git tree |
| integrate/office-union-148 | 3abf8f43 | 4b2b4e78 | Complete Git tree |
| integrate/recent-pptx | ec70b942 | 698209aa | All 3 changed paths |

PR #147 (`cee6e263` → `bb5556e8`) and PR #152
(`da9c956e` → `23f3b420`) also have identical complete-tree replacements in
baseline ancestry. All 15 mappings in the inherited historical-equivalence
table were replayed successfully: 13 complete-tree proofs and 2 changed-path
proofs. Only 12 captured references require these proofs; several references
can identify the same source commit.

[intake.json](intake.json) contains the API URLs, full SHAs, PR metadata,
classifications, complete equivalence mappings, comparison bases, changed-path
lists, Git tree IDs, and exact per-path mode/type/blob IDs. Git object IDs bind
the comparisons to the recorded objects. Historical equivalence is kept
separate from direct ancestry.

## Reproduce locally

Run from the repository root with the captured Git objects available. This
read-only replay disables lazy network fetching and checks the recorded
snapshot against the fixed baseline, independent of subsequent branch movement.

```bash
python3 - <<'PY'
from collections import Counter
import json
import os
from pathlib import Path
import subprocess

os.environ["GIT_NO_LAZY_FETCH"] = "1"
os.environ["GIT_TERMINAL_PROMPT"] = "0"
data = json.loads(Path(
    "docs/validation/word-vba-compatibility-20261121/intake.json"
).read_text())
head = data["baseline"]

def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()

def ancestor(sha):
    result = subprocess.run(["git", "merge-base", "--is-ancestor", sha, head])
    assert result.returncode in (0, 1)
    return result.returncode == 0

assert git("rev-parse", head + "^{tree}") == data["baseline_tree"]
source = data["historical_equivalence_source"]
assert git("rev-parse", source["commit"] + ":" + source["path"]) == source["blob_sha"]
proofs = data["historical_equivalence_proofs"]
for sha, proof in proofs.items():
    replacement = proof["replacement"]
    assert ancestor(replacement)
    assert git("rev-parse", sha + "^{tree}") == proof["source_tree"]
    assert git("rev-parse", replacement + "^{tree}") == proof["replacement_tree"]
    if proof["kind"] == "full_tree":
        assert proof["source_tree"] == proof["replacement_tree"]
    else:
        paths = git("diff", "--name-only", proof["base"], sha).splitlines()
        assert paths == [row["path"] for row in proof["changed_paths"]]
        assert not git("diff", "--name-only", sha, replacement, "--", *paths)
        for row in proof["changed_paths"]:
            for commit in (sha, replacement):
                assert git("ls-tree", commit, "--", row["path"]) == row["git_entry"]

counts = {}
for category in data["counts"]:
    observed = Counter()
    for row in data[category]:
        sha = row.get("sha") or row["head_sha"]
        disposition = ("ancestor" if ancestor(sha)
                       else "verified_equivalent" if sha in proofs else "uncovered")
        assert disposition == row["disposition"]
        observed[disposition] += 1
    assert dict(observed) == data["counts"][category]
    assert not observed["uncovered"]
    counts[category] = dict(observed)
assert data["fork_open_pull_requests"] == []
print(json.dumps({"baseline": head, "counts": counts}, indent=2))
PY
```

No GitHub Actions workflows, runs, checks, statuses, or jobs were queried or
awaited for this audit.

