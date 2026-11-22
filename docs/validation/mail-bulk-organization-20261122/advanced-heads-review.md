# Advanced concurrent heads: integration review

Comparison baseline: `7ea871c890760f17dfa84efe2eec6cf467766153`, our already
reconciled initial integration. Connector comparisons and exact local diffs
were both inspected. No references or remote state were mutated by this audit.

| Branch | Captured head | New material beyond our integrated baseline |
| --- | --- | --- |
| Mail identity reconciliation | `06b4e747c09851048d0b72a958e9114f7c83cc52` | Imports the already-integrated Word suffix work and adds the already-retained destination folder display-name quota fix. Its resulting tree still uses the older unbounded-at-query metadata accumulation, so retain our bounded scan. |
| Word range suffix | `d4317dcc1ecc6c7b70a1773cc121f5639ad99428` | Adds the dated Word qualification report, intake, scripts, evidence index and 1,300,946-byte evidence archive. Incorporates clock/schema fixes we already retained. Remaining source differences are comments and an error explanation; removes duplicate fixture setup. |
| Word extended | `fcabea23fec4d18597ed4293ebd65857bd958b30` | Merge of the two original heads. Relative to our integration, only comments in move_identity_transitions.dart differ. No new VBA capability at this captured head. |

## Recommended resolution

Merge all captured histories normally. Preserve the current bounded destination
metadata scan and exact quota calculation, receipt-preserving savepoint behavior,
clock correction guard and schema fixtures. No new runtime feature needs to be
reapplied. Both move-reconciliation test families are already included.

Accept the newer removal of the second pair of saveView calls in the synchronized
membership test: it already initializes both browse views before saveSync. Our
initial union accidentally retained a duplicate pair afterward. My first quick
message called those lines required setup; this full inspection corrects that
assessment. The earlier pair remains in every compared head.

Take suffix's new documentation/evidence files as source-specific historical
records. Its README distinguishes its accepted Word suites, failed initial
attempt, affected-suite replacements, and the later pending broader Mail gate.
Do not substitute its historical test counts for our current combined-source
qualification. Keep our new bulk source and documentation unchanged.

All three captured heads have identical Studio host lib contents to integrated
7ea, so they introduce no direct conflict with our bulk organization host,
shared dialogs, or tests. Core repository error wording can retain our current
wording. Retain the accurate comment that optional cache writes roll back in a
savepoint, separately from the authoritative receipt.

No GitHub Actions or status/check queue was queried or awaited.
