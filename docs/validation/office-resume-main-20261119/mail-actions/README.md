# Main 666 Mail-action checkpoint

This checkpoint reconciles main `666e9a2ea46f7aeaaa1d01b60aabea0c2fe6f0fd` with the accepted-source evidence publication `ae5bb49cd9167c73086cc45428a8d52b18b96412`. It is an incremental preservation checkpoint. Related draft PRs #191 and #192 were discovered during the final read-only check and are being reconciled separately before the final main merge.

## Changes

Reply and Forward quote the decoded message held by the bounded reader, because the selected list item is an envelope and may contain no body. The incoming action labels and layouts remain. Mark-read owns the pending action before awaiting its flag write and checks client/session generation before mutating local flags or UI state. Replaced-session completions cannot mutate the old envelope or release a replacement operation.

The typed post-submission handler remains: a confirmed SMTP submission followed by cleanup failure clears the submitted draft and does not become an uncertain retry. These action changes add five regression cases for full-body Reply/Forward, mark-read ownership, and stale success/error after reconnect.

## Validation and exact limitation

Strict analysis with fatal infos and warnings passed for the three changed Dart files. [The receipt](analysis-receipt.json) binds their current SHA-256 values; [the log](analysis.log) contains the output. The independent [preservation audit](preservation-audit.json) confirms the reviewed union, additive test tokens, incoming strings and 5,172 unchanged remaining tracked product entries.

The attempted focused runtime reproduction executed **zero product cases**. Flutter failed during suite loading because it could not create `flutter_test_fonts.` on a full host filesystem (ENOSPC). The intended RED phase is retained under its original filenames, but it is an infrastructure startup failure, not a behavioral regression result. No GREEN run or fresh frozen runtime qualification was completed for this checkpoint. The source was restored to the reviewed implementation and checked against the strict-analysis hashes.

Only untracked generated test caches were removed in an attempt to recover space; tracked source, evidence and pinned runtime inputs were preserved. The host still reported zero writable bytes. Publication therefore uses the GitHub Git-data API with independently computed object hashes, without a local tree write.

Prior accepted qualifications retain their own sources and are not added together:

| Qualified source | Accepted execution count | Distinct case identities | Distinct suites |
| --- | ---: | ---: | ---: |
| `0bd53e3e2b0d75ae48a4d7807dcddd123ab477f9` | 1,898 | 1,327 | 68 |
| `0f16754c278aa83cc79d5777e5b45d3f739e5469` | 404 | 395 | 28 |
| This Mail-action checkpoint | 0 runtime cases executed | 0 | 0 |

The first qualification is recorded in [final/](../final/README.md); the second in [main-refresh/](../main-refresh/README.md). Neither qualifies the later main666 actions.

## Evidence and replay

[The evidence archive](review-and-startup-evidence.tar.xz) preserves incoming snapshots and diff, both independent reviews, prepared patches, the additive test proposal, strict analysis, the startup reporter and its receipt. [The member index](review-and-startup-evidence.index.json) records exact bytes and SHA-256 hashes. The current application/test blobs are recorded in the preservation audit.

The [pending plan](pending-native-plan.json) selects the same eight modular Mail suites as the earlier accepted plan and includes the five new cases through the current test file. It has **not been executed** on this checkpoint. On a host with working storage, use the existing pinned runtime and `run_checks.py` workflow with this checkpoint's commit as `--head`, main666 as `--base`, and this pending plan. Keep output/runtime directories outside a clean source worktree.

Actual browser rendering/persistence, installed OS/IME behavior, live external Mail/Zotero services, Word/LibreOffice interoperability and real morphology backend/language-bundle acceptance remain separate.

No GitHub Actions run, job, queue or status was queried, dispatched or awaited.
