# Current Office reference reconciliation

The initial capture was made on 19 November 2026, with fork `main` at
`b070e228a749e22cc8ce2098029a76ab5fb8eccb`. The exact captured advertisements are
`remote-refs-initial.tsv` and `upstream-refs-initial.tsv`; capture metadata is in
`capture-metadata.json`.

The audit covers 461 actual references: 230 fork branches, 190 fork pull-request
heads, 17 fork tags, four upstream branches, four upstream pull-request heads,
and 16 upstream tags. HEAD aliases and peeled-tag advertisements are not counted
as separate references. At the captured main, 429 references are ancestors,
28 are verified historical equivalents, and four are unmerged branches.

| Unmerged branch | Captured commit | Integration relationship |
| --- | --- | --- |
| `codex/office-continuation-20261119` | `10bd0cc4aa720acda4f52d0da882c57b05446435` | Already includes captured main and the `office-main-sync` tip |
| `codex/office-main-sync-20261119` | `1b6d280b6ed41a1e01736a88f6d02431057c8611` | Ancestor of `10bd0cc4` |
| `codex/office-resume-main-20261119` | `004b2ad6342cae7b2fe2750dbba5a9fdcebd3413` | Already includes captured main and the `office-main-integration` tip |
| `codex/office-main-integration-20261119` | `c63558c0b3bc713361771cc29b0d89ecf2fa09a7` | Ancestor of `004b2ad6` |

All 14 historical equivalence proofs were freshly recomputed from immutable Git
objects. They establish exact complete-tree identity or complete changed-path
mode/type/blob identity with a landed ancestor. These historical equivalents
remain non-ancestors; their status is not described as a new merge.

The [integrated audit](integrated-audit.json) passes against actual merge commit
`3119a4598e61f061e7b7633ea4a352d841332b9e`, tree
`c89a6a6511e0cda181186a9dfbdb9f5916e89d58`: **433 ancestor references, 28 historical
equivalents, and zero unaccounted references**. Both continuation tips and their
earlier checkpoints are real ancestors of this integrated commit.

## Merge review

`git merge-tree --write-tree 10bd0cc4 004b2ad6` reports a single textual conflict
in `packages/quds_office_editor/example/test/studio_mail_test.dart`. Product
source merges without textual conflicts. The two continuations carry distinct
historical evidence that must retain its original source attribution.

The test conflict juxtaposes saved-message/file-picker tests and a workspace
language-cycle test with the newer functional IMAP/SMTP dialog tests. The latter
use the current client abstraction. The integrated checkpoint keeps the current
lifecycle and German-localization tests in `studio_mail_test.dart` and preserves
the saved-message tests separately in `studio_saved_mail_test.dart`. Subsequent
source restores an explicit saved-message view and adapts those regressions to
that view, retaining account-free EML use alongside the current account client.
Historical evidence is not relabelled as fresh qualification of the resulting
merge. This audit establishes source-history inclusion only.

## Replay

`audit_refs.py` originated in commit `004b2ad6`, where it was already published.
Its final capture support additionally classifies GitHub's provisional
`refs/pull/<number>/merge` advertisements separately from actual PR heads. These
generated test merges are retained verbatim in the raw advertisement and listed
in the audit's exclusions; every corresponding `refs/pull/<number>/head` remains
in the required graph coverage. The initial receipts retain the script hash
under which they were produced. The script performs only immutable Git reads
and writes its JSON report.
It does not fetch, query GitHub Actions, mutate the index, or execute product
code. `initial-audit.json` is expected to report `passed: false`, because the
four branch tips were not yet integrated into the captured main.

Run against an actual integrated commit after merging both continuations:

```sh
python audit_refs.py --repo /path/to/quds_office_suite \
  --head <integrated-commit> \
  --refs remote-refs-initial.tsv \
  --upstream-refs upstream-refs-initial.tsv \
  --expected-total 461 \
  --output integrated-audit.json
```

A passing reference audit establishes captured-history coverage, not application
runtime correctness. Fresh targeted validation belongs in the continuation's
separate execution record. No GitHub Actions runs, jobs, statuses or queues were
queried or awaited for this audit.

## Bounded pre-freeze capture

The second advertisement capture ran from **11:38:37 to 11:38:45 UTC on
19 November 2026**. Its original bytes are `remote-refs-pre-freeze.tsv` and
`upstream-refs-pre-freeze.tsv`; `pre-freeze-capture.json` binds their acquisition
times and SHA-256 values. `open-prs-pre-freeze.json` records the four open PRs
at that cutoff. This is a bounded capture, not a claim about later concurrent
remote pushes.

It contains **467 actual references**: 232 fork branches, 194 fork PR heads,
17 fork tags, four upstream branches, four upstream PR heads, and 16 upstream
tags. The raw advertisements also preserve two HEAD aliases, seven peeled-tag
rows, and four GitHub provisional PR merge rows. The latter are generated
previews against the base branch; all four corresponding actual PR heads are
included in the required graph coverage.

The cutoff required retaining these newer tips beyond the first integration:

| Source | Captured head |
| --- | --- |
| PR #194, `codex/office-finish-20261119` | `4b8b9e2ecec349542bd34bc7f983e1cf500e8cbf` |
| PR #193, `codex/office-continuation-20261119` | `4cf5831d01ace0ae804a176ec82ff2d27ce7fac3` |
| PR #192, `codex/office-resume-main-20261119` | `79e77725925d937bae944b03aac795ffb3fd967d` |
| `codex/office-final-union-20261119` | `47ce5f726f1a0b1f213b926162528533dc0a3aab` |

`pre-freeze-audit.json` binds the fetched, published integration commit
`b434cf1ec084020dadeb90459e03a9251857d2ee`, tree
`a172821dae92d83b7b19d898701cd1f8607ec5c2`. It passes with **439 ancestor
references, 28 historical equivalents, zero unaccounted references, and all
14 historical proofs recomputed successfully**. The earlier local merge preview
used commit `062150ac1c0c47a7c2c63581f899140c2c9a3059` with the same tree; the
accepted graph receipt uses the published commit identity.

Replay that bounded capture with the same script, using
`--refs remote-refs-pre-freeze.tsv`,
`--upstream-refs upstream-refs-pre-freeze.tsv`, `--expected-total 467`, and an
actual integrated `--head`. Incoming evidence remains tied to its original
execution source; graph inclusion does not convert it into fresh application
qualification.
