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
the saved-message tests separately in `studio_saved_mail_test.dart`. The next
product step restores an explicit saved-message view and adapts those regressions
to that view, retaining account-free EML use alongside the current account client.
Historical evidence is not relabelled as fresh qualification of the resulting
merge. This audit establishes source-history inclusion only.

## Replay

`audit_refs.py` is copied unchanged from commit `004b2ad6`, where it was already
published. It performs only immutable Git reads and writes its JSON report.
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
