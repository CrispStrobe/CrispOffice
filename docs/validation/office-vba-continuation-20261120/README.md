# Word and PowerPoint VBA continuation — 20 November 2026

## Integration baseline

This continuation starts from remote main
`d040c15a07f652d01e75363031d0efdee6357bda`, including the earlier Word/PowerPoint
source adapter increment. The retained checkpoint branch is
`codex/word-powerpoint-vba-continuation-20261120`.

Before implementation, all live fork branches and all 239 available PR heads
were fetched. Three heads contained new work and were merged with their original
ancestry. Each published tree was checked against its local Git tree before a
non-forced update of the expected remote branch head.

| Incoming head | Work | Remote checkpoint |
| --- | --- | --- |
| `afa9272a6e31e2cbd6b9896c450a7bccfd62c579` | Typing/proofing provider-language cache, draft timing and benchmark corrections | `6b9ca183d5d7370c6fa14d453f00ac28508e20d3` |
| `1d26181b0161d88abe5977f9848ffd4cd99e6259` | PowerPoint default radial focus and final Mail qualification evidence | `4f311d42df1748128f0e4e76b32f427287ec281f` |
| `40a8f8eb76bd9bf51205fa0cb9f576ba497ad76b` | Final Zotero qualification documents and evidence archive | `9aa177ba9abeae7179edd517da8924f16c4c78f4` |

The integrated tree is `3fcf9b0d252371b534a9e994d9252713d646e1ce`.
There were no source conflicts. Omitted circle focus now means centered radial
focus for shapes and backgrounds; this supersedes the earlier fallback behavior
described in the prior VBA increment's integration record. That record remains
an account of its own tested source.

The [branch audit](incoming-branches.json) verifies nine historical equivalents.
Eight have identical full trees to accepted ancestors. The old ODT branch has
identical mode/type/blob entries for all 37 changed paths. The
[complete inclusion receipt](incoming-prs.json) verifies all 239 fetched PR
heads: 225 actual ancestors and 14 exact historical equivalents, with no
uncovered head. It also covers all 23 captured branch refs, including this
continuation: 14 actual ancestors and nine equivalents. Equivalent content is
not claimed as commit ancestry. The [reproducer](audit_inclusion.py) records the
exact source refs used for that comparison.

PR #237's imported performance document still contains unpublished hosted/test
result placeholders. Those placeholders are not validation results. Inherited
Flutter/runtime claims remain limited to their original evidence.

## Development and validation status

This is the initial integration checkpoint. Implementation and final validation
are in progress; no passing result for the new continuation is claimed here.
GitHub Actions, checks, statuses and queued jobs are not an acceptance gate.
Local runtime and source-bound receipts will accompany completed changes.
