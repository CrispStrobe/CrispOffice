# Captured-source reconciliation for the Word VBA extension

The captured sources are fully accounted for at fixed integrated commit
`75f694d5e42049f356ba52b26329d199bfb7c2aa`, tree
`b05bbf48aaa6189c8c297866b4b39263004ca85f`. There are **zero uncovered captured
refs**. This record concerns source inclusion at that commit. Later publication
and integrated runtime qualification have separate receipts.

`reconciliation.json` contains the individual refs, exact SHAs, original parent
lists, historical-equivalence proofs, compared Git entries, input hashes, and
frozen-source hashes. The verification used local objects with
`GIT_NO_LAZY_FETCH=1`; it did not refresh remote refs or inspect GitHub Actions.

## Snapshot coverage

The original Word intake was serialized at `2026-11-21 07:16:45 UTC` from API
observations made before creating the task checkpoint branch. Rechecking that
unchanged capture against the fixed integrated commit gives:

| Original capture | Refs | Ancestors | Verified historical equivalents | Uncovered |
| --- | ---: | ---: | ---: | ---: |
| Fork branch heads | 46 | 36 | 10 | 0 |
| Recent fork PR heads | 100 | 98 | 2 | 0 |
| Upstream branch heads | 4 | 4 | 0 | 0 |
| Upstream PR heads | 4 | 4 | 0 | 0 |

The integrated Zotero intake also captured every fork PR head, with snapshot
timestamp `2026-11-21T07:15:28.806356+00:00`. Its pinned replay script independently
recomputed all historical proofs and coverage:

| Complete capture | Refs | Ancestors | Verified historical equivalents | Uncovered |
| --- | ---: | ---: | ---: | ---: |
| External fork branch heads | 46 | 36 | 10 | 0 |
| All fork PR heads | 288 | 274 | 14 | 0 |
| Upstream branch heads | 4 | 4 | 0 | 0 |
| **External total** | **338** | **314** | **24** | **0** |
| Intake checkpoint, recorded separately | 1 | 1 | 0 | 0 |

These populations overlap; the two tables must not be added. The empty open-PR
response in the original intake is an observation at that initial capture, not a
claim about the remote repository at publication time.

### Historical equivalence

All 15 recorded candidate mappings were recomputed: 13 have identical complete
Git trees; two have identical entries for every path changed by the original
source relative to its recorded base. Every replacement commit is an ancestor
of the fixed integrated commit. Original commits that are not ancestors remain
classified as historical equivalents, rather than being relabeled as ancestors.

The two bounded changed-path proofs are:

| Original source | Retained replacement | Compared paths |
| --- | --- | ---: |
| `c34945761e7991f5fe49037d79529acdd260b31c` | `2c47165d01d01cc883135a434ac9f6591ce6e770` | 37 |
| `ec70b9423febefcb9b104629d2ad48b0c96e9082` | `698209aaa6e7f1350b6541df5eb192b7b233443d` | 3 |

Their bases are respectively `e3a38789359adaa33b2da1345c952fa1c2d8aebb` and
`c954d00d2fc85604ae394674bca91ea8a1dede0e`. The JSON records every compared path,
mode, object type, and object SHA. Canonical entry-map SHA-256 values are
`1c470480ee517d204b26eceedf9db6a9337ba213a6b8743bdb239ba80c71cd0c`
and `0443b86c1119aaa43fb9cfd2f61d5eea0df8a804c66381a002fc020afa9a1af5`.
These proofs assert equality for those changed paths, not equality of the two
entire trees.

## Late captured integration and source parents

All four late snapshots and each of their immediate original parents are
ancestors of the fixed integrated commit:

| Snapshot | Retained head |
| --- | --- |
| Zotero table-cell range replacement | `a6095c304ad2d6935f2ae6f8b74412038d19f142` |
| Mail sync foundation | `278fa78d59f219965a50f025dbdb11d1b7b98676` |
| App Store screenshots | `e8d23a3a770037f7309e239e3ef6fe3bf570039a` |
| Saved-Mail Close action correction | `9cfad3920f9afb3ca1620df429fa41e33f3db8e6` |

The initial main `e2abbcda6d19f932bfbacc85e0dafd41a3c478f8`, earlier Zotero
snapshot `674ce9701e185971388fc2e517d305689ccba471`, earlier Mail runner snapshot
`d9d75300f7eec0eeecc8fdee05bc02fb6ad3db0b`, Word source checkpoint
`4b47520ae44dc545b898713d6e22370b66767acd`, and published final guard checkpoint
`6aa7b259819eaba4fe372809c9f0ae8df9edcc6b` are also ancestors, together with their
immediate parents. The JSON preserves all parent SHAs explicitly.

The local late-review baseline `41fcdf540bc0e93274ddb2f2030bbd2a609c90c9` is
**not** an ancestor. Its published counterpart
`6aa7b259819eaba4fe372809c9f0ae8df9edcc6b` is retained and has exactly the same
tree, `67125be188751a91d241ef7dcd0748ef0b275f60`, and the same sole parent,
`4b47520ae44dc545b898713d6e22370b66767acd`. This separate equality check binds the
local source review to the published guard without claiming that their commit
identities are equal.

### Late review findings

The earlier read-only three-way merge previews were clean for each of the four
late heads, including the Mail/Close-fix overlap. Actual retained ancestry above
is the integration proof. The concise source review is preserved in the JSON:

- **Zotero:** adds exact ownership checks and research-content replacement
  across multiple paragraphs inside one table cell, plus engine and editor
  regression tests. Its incoming README reported 121 focused tests and an
  editor controller pass; the intake review did not independently execute those
  tests. The affected engine suites and editor controller suite require
  qualification on the final integrated source.
- **Mail:** adds schema-v8 mailbox sync state, atomic page checkpoints, bounded
  observers, stable cached identities, provider adapters, cancellation/drain
  behavior, and a native sync dialog. Store migration/sync tests and four native
  Studio suites were included. The new delta did not contain a source-bound
  final qualification receipt; real-SQLite store tests and Flutter host/dialog
  tests were identified as the relevant gates.
- **Screenshots:** adds six 2880-by-1800 PNG release images and test-only capture
  gate changes. All six integrated image blobs match their independently
  recorded capture SHA-256 values. This audit did not rerender the images.
- **Close action:** suppresses a duplicate command-bar Close while saved-message
  view supplies its own action, retaining ordinary account-view Close. The
  overlapping Mail edits merged cleanly; saved-Mail and sync-host/dialog suites
  remain the relevant behavioral qualification.

These are source-review findings and qualification targets. This intake audit
does not turn incoming README statements or commit messages into independent
test-pass claims; the coordinating work record reports actual integrated gates.

## Native source freeze

Each file below still matches both the fixed integrated commit and the current
worktree bytes at reconciliation time:

| File under `packages/quds_office_engine/` | SHA-256 |
| --- | --- |
| `lib/src/automation/operations/word_header_footer_guard.dart` | `3e564faa171594515f463cfdf01752274dd46a7b756308a6136624b6a72160fa` |
| `lib/src/automation/operations/word_steps.dart` | `af9b3f18201301c3fa9399d61c72f4201259636b757e84d72f50103bffeec58b` |
| `test/office_macro_word_headers_footers_test.dart` | `c0681a5a81ae64f1d357b4e60ae10ba14c7dd901c3d6f09b025660b977653f6a` |

## Reproduce the captured-ref proof

Run the following from the repository root with the captured Git objects
available locally. It extracts the replay inputs from the pinned commit, checks
their recorded hashes, and runs the existing audit without fetching or reading
moving remote refs. The temporary output is compared with the complete receipt
stored in `reconciliation.json`.

```python
import hashlib, json, os, pathlib, subprocess, sys, tempfile

repo = pathlib.Path.cwd()
record = json.loads((repo / "docs/validation/word-vba-compatibility-20261121/reconciliation.json").read_text())
target = record["target"]
env = dict(os.environ, GIT_NO_LAZY_FETCH="1")

def git(*args):
    return subprocess.check_output(["git", *args], cwd=repo, env=env)

assert git("rev-parse", target + "^{tree}").decode().strip() == record["target_tree"]
with tempfile.TemporaryDirectory(prefix="quds-ref-reconciliation-") as folder:
    dest = pathlib.Path(folder)
    for binding in record["source_bindings"]:
        data = git("show", target + ":" + binding["path"])
        assert hashlib.sha256(data).hexdigest() == binding["sha256"]
        assert git("rev-parse", target + ":" + binding["path"]).decode().strip() == binding["blob_sha"]
        if "/zotero-table-cell-ranges-20261121/intake/" in binding["path"]:
            (dest / pathlib.Path(binding["path"]).name).write_bytes(data)
    output = dest / "coverage.json"
    subprocess.run([
        sys.executable, str(dest / "audit_refs.py"), "--repo", str(repo),
        "--head", target, "--snapshot", str(dest / "snapshot.json"),
        "--candidates", str(dest / "historical-candidates.json"),
        "--output", str(output),
    ], check=True, env=env)
    replay = json.loads(output.read_text())
    assert replay == record["complete_captured_refs_recheck"]

def is_ancestor(sha):
    result = subprocess.run(["git", "merge-base", "--is-ancestor", sha, target], cwd=repo, env=env)
    assert result.returncode in (0, 1)
    return result.returncode == 0

for category in record["initial_api_snapshot_recheck"]["categories"].values():
    for ref in category["refs"]:
        if ref["disposition"] == "ancestor":
            assert is_ancestor(ref["sha"])
        else:
            proof = replay["proofs"][ref["sha"]]
            assert not is_ancestor(ref["sha"])
            assert proof["identical"] and proof["replacement_is_ancestor"]
for source in record["late_captured_heads"] + record["original_source_checkpoints"]:
    assert is_ancestor(source["sha"])
    assert git("show", "-s", "--format=%P", source["sha"]).decode().split() == [p["sha"] for p in source["original_parents"]]
    assert all(is_ancestor(p["sha"]) for p in source["original_parents"])
for source in record["frozen_native_sources"]:
    assert hashlib.sha256(git("show", target + ":" + source["path"])).hexdigest() == source["expected_sha256"]
print("Captured snapshots covered; source hashes match the fixed commit.")
```

The worktree hash observations are historical freeze evidence; the replay
checks the immutable committed sources so it remains usable after subsequent
development. No workflows, runs, checks, statuses, or jobs were queried or
awaited for this reconciliation. No product files, index, refs, or checkouts
were changed.
