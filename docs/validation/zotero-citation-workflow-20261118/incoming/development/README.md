# Focused filter-helper development

These two attempts run only `word_live_review_changes_test.dart`. They are
**excluded from full-cohort acceptance and every final passing total**. Each
attempt has its own raw events, source diff, input inventory and process exit.
The integration owner authorized these focused runs while the helper test was
being repaired; the next full 18-suite run still requires a new saved source
commit.

| Attempt | Result | Cause or conclusion |
| --- | --- | --- |
| [1](attempt-1/summary.json) | 7 passed, 6 failed, 0 skipped; exit 1 | Reading public expansion state and opening the real header fixed the hidden-child problem. The six normal-height cases then correctly stopped at the hit-test assertion because the expansion animation had only begun. Both narrow cases passed because scrolling added elapsed frames. |
| [2](attempt-2/summary.json) | 13 passed, 0 failed, 0 skipped; exit 0 | After a real tap, an initial frame starts transitions before the existing bounded 450 ms drain advances them. All cases, including the narrow English and Arabic flows, pass with real hit-testable taps. |

Both attempts passed strict analysis and nonmutating formatting on the changed
test. Source, dependency, runtime and workspace inventories were unchanged
during each attempt. Both have zero missed-tap/layout diagnostics. Attempt 2
has zero error events and every started test finished exactly once. No test case
or assertion was removed; no product file was edited.

The runner records all 550 source paths from the preceding full run and asserts
that only the explicitly authorized helper test differs from frozen base
`00ac2edf606359cea003b4ebb3a5f3aaac7b67cf`. It records the exact diff and hashes
of those changed test bytes, uses the shared Flutter CLI lock, and checks the
same dependency, workspace and runtime paths before/after. It uses the full
runner's event auditor and records the SHA-256 of both scripts.

To reproduce a development attempt, use the restored runtime, checkout that
base, apply the attempt's `source-diff.patch`, then invoke:

```bash
python docs/validation/zotero-citation-workflow-20261118/incoming/development/run_changes_helper.py \
  --output FRESH_DEVELOPMENT_DIRECTORY
```

The helper reads `Expansible.controller.isExpanded` solely to decide whether
the visible header needs a tap. It never expands the controller directly.
Finite transitions use a bounded frame sequence; unresolved proofing-provider
work cannot make this helper wait indefinitely for global settling.

No GitHub Actions, workflow or CI-status endpoint was used.

## Lossless patch storage

The two original `source-diff.patch` files are stored as `source-diff.patch.gz`
to preserve their exact context-line whitespace without treating raw diff syntax
as source-file whitespace. Decompression reproduces the raw patch bytes and
hashes recorded in the unchanged execution summaries. No test events, input
inventories or recorded process exits were rewritten.
