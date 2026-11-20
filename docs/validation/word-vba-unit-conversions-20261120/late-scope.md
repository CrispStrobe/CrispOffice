# Late active-work scope

After the fixed initial intake of 311 references and the Word implementation
checkpoint `dd8e73a7`, a read-only refresh found four additional active branch
heads. Initial main remained `c954d00d`. These later snapshots are recorded
separately from the completed initial reconciliation.

| Branch | Captured head | Disposition |
| --- | --- | --- |
| `codex/word-vba-measurements-20261120` | `4d0086aba52fc804424145d8eabe3c4c1c10f201` | Preserved; deferred active overlapping Word implementation |
| `codex/word-vba-unit-conversions-20261120` | `e08635b3f21c60ad21888821050dc97c2dbf7086` | Preserved; deferred named-argument and alternative conversion work |
| `work/mail-bulk-actions-20261120` | `69ab514b57a4d6d4db062d802eb853c2691d80fe` | Preserved; deferred new Mail bulk coordinator and overlapping Word snapshot |
| `work/mail-bulk-flags-20261120` | `0cc6316c61efd8b39a9cb0cfed6b2879f7865d48` | Preserved; deferred active Mail intake checkpoint |

The complete open-PR list contained only this increment's PR #271 at the check.
No PR for any of these four workstream heads was present at capture.
[late-scope.json](late-scope.json) records the exact parent lists, changed-file
inventories, comparison counts and per-head reasons.

The measurements branch already includes `dd8e73a7` as a direct parent, but
chooses a Set/switch implementation with a different metric fallback operation
order and additional fixtures/portable driver. The other Word branch adds
named arguments, changes evaluator canonicalization and uses conflicting
measurement test/example paths. Combining those variants requires coherent
source reconciliation and validation; this increment does not adopt them
piecemeal. Its reviewed contract remains one positional numeric argument.

The Mail branches introduce or prepare foreground bulk operations and carry
overlapping Word code. This Word increment does not claim fresh Mail or
combined-implementation qualification. One concurrent Word commit reports its
own development passes; those were not reverified and are not included in
this increment's validation totals.

The branch refresh counted 37 current branches: five new branches including
this continuation, and one removed older macOS branch. The removed branch's
captured head remains an actual ancestor of initial main. Other initially
captured branch heads were unchanged.

The initial 311-reference reconciliation and these four later deferrals are
both retained: **zero exclusions in the initial snapshot after the reviewed
`332d7b26` merge resolution; four explicitly deferred later active heads;
zero unclassified late heads.** A final remote-main refresh remains required,
and any actual main advance must be incorporated before publication.
No Actions run, check, status or queue was queried or waited on.
