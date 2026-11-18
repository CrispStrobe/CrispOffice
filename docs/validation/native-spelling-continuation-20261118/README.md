# Native spelling continuation — 18 November 2026

## Incremental checkpoint

Work continues on `codex/native-spelling-continuation-20261118` from integrated
main `1e07cb852766f8651815138785be74c64a09ddc0`. PR #159 was merged first with its
expected head `2292548eb69de2dbb5240ab9da59256f362137c6`, bringing in spelling
PR #157, Zotero tags PR #158, native spaCy distribution and the preserved Office
recovery history. See [reconciliation.md](reconciliation.md) and [refs.json](refs.json).

The first product checkpoint omits discretionary U+00AD only from native
checker input. Its UTF-16 results map to the unchanged original source, including
internal layout controls; controls outside each word remain untouched. Original
and projected grapheme boundaries and protected source ranges are both checked.
No-op suggestions that merely move or remove soft hyphens are suppressed.
An empty projected input completes without occupying the shared native lane.

The original 1,078 engine proofing tests and 32 native editor tests passed on
the integrated baseline. Ten new provider tests and two Word review tests fail
on that baseline; all 44 native tests pass after this repair. The review tests
exercise Flutter's default service through controlled channel responses, real
Word correction/undo/redo, and owner-scoped vocabulary. Broader final validation
and the engine follow-up are still in progress at this checkpoint.

The authentic Flutter 3.47.8 / Dart 3.13.7 runtime and 162 pinned hosted archives
were hash-verified; offline workspace resolution retained the 110-package graph.
This report will be completed with final commands, source bindings and raw
evidence. No GitHub Actions, workflow, check or CI-status endpoint was queried,
awaited, dispatched or rerun. Physical-device dictionary quality is not measured
by controlled-channel tests.
