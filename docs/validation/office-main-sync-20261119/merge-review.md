# Concurrent-head reconciliation

## Captured heads

The focused application qualification executes at
`0b8f8f7f78fbf4e2e26671ecf9a0d858c38ca75c`. During that gate, the direct
remote advertisement captured three later histories:

| Incoming history | Head | Decision |
| --- | --- | --- |
| Main / merged Arabic PR #176 | `f059065fa622da8cee7824d66d29a2aff414d529` | Preserve merge ancestry; its Arabic publication and metadata are already included |
| Mail completion documentation / PR #172 | `199690563b206948871ea0279f5e59f686265f8b` | Preserve history and the completed original evidence; keep the more explicit historical-source wording from this continuation |
| Current Office reconciliation / PR #177 | `c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e` | Preserve history, checkpoint report and all seven offline Python controls |

The direct tree comparison between the application qualification source and
PR #177 has **zero changed Dart paths**. Its only product-directory difference
is the Store README. That document keeps this continuation's latest pointers
and distinction between historical and fresh results. PR #172 adds no new
application code.

## Arabic overlap

Both independently written fixes restrict `upload_folder` to the exact manifest
filenames plus `manifest.json`. This continuation retains its qualified builder
bytes, including the corrected `license: other`, `license_name: mpl-1.1` and
license-link metadata from the later Arabic publication. The incoming older
card metadata is superseded by that captured publication.

The five local controls remain in `test_build_bundle.py`. The seven incoming
controls are retained as `test_build_bundle_incoming.py`; only the filename,
provenance docstring and assertion for equivalent planned-adapter wording are
adapted. Both suites run against the same unchanged builder. Their scenarios
overlap; twelve Python test executions are not twelve distinct product features.

The incoming checkpoint README is retained with a historical-provenance banner.
Its pending qualification wording describes that captured checkpoint, while the
current report holds the later acceptance result.

## Qualification continuity

The reconciliation preserves every input selected by the frozen VM and Node
plans, including the source inventories, original tests, dependency declarations,
qualification plans and runners. The incoming additional Python file receives
its own fresh source-bound gate. The final independent audit must verify this
continuity against the published commit and remote main; it must not silently
relabel earlier application runs as new executions.

No GitHub Actions status, workflow, job or check endpoint is queried. Remote
branch updates reject an unexpected head and retain all incoming parents.
