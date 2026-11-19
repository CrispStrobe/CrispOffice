# Rejected pre-test guard attempt at `fce543de`

This exact-source qualification attempt remains **FAIL** and
**`accepted_qualification: false`**. It executed **0 application cases and
0 Python test controls**. No result from this attempt contributes to a later
accepted qualification total.

The attempt was bound to source commit
`fce543dedb1217804f67de088ef9c287e8a2edca`, tree
`2c3fe2fad3d692731dc454086d840b0ece747f10`, and ran from
2026-11-19 10:21:20.586984 CET to 10:21:53.351223 CET. See the unchanged
[original execution receipt](execution.json).

## Exact reason for rejection

The locked offline workspace resolution succeeded. The next command, the
delta continuity guard, rejected the resolved Studio dependency graph.
Its expectation accounted for four added edges from `quds_office_studio`:
the three Mail packages and the optional Hunspell workspace package. It
omitted the fifth added edge, **`quds_office_studio` → `url_launcher`**.

The incoming manifest at
`00014577265d1f95d4c016159029510d3a10804b` explicitly declares
`url_launcher: ^6.3.1`. That package was already resolved in the previous
workspace: this was an additional Studio dependency edge, not an unresolved
package or an unexpected package download. The exact added Studio dependencies
were:

- `quds_mail_core`
- `quds_mail_mime`
- `quds_mail_ui`
- `quds_proofing_hunspell`
- `url_launcher`

All 131 prior package mappings remained identical; only the optional
`quds_proofing_hunspell` workspace mapping was added, producing 132 mappings.
The original guard expectation and its rejection are preserved in the raw
evidence. Application tests, Python test controls, and browser compilation
never started.

## What the independent audit establishes

The unchanged [independent audit](independent-audit.json) records
`audit_checks_passed: true` and `recorded_failure_confirmed: true`, while
retaining `accepted_qualification: false`. Its successful checks establish
that the rejection and the original evidence were correctly recorded. They
do not turn the failed qualification into a passing one.

The audit binds 5,115 source inputs to the immutable source commit, confirms
equal before/after source snapshots and equal before/after runtime snapshots
covering 11,171 runtime inputs, and verifies the exact dependency-graph change.
The recorded source head and tracked checkout also remained unchanged during
the attempt. The audit itself executed no application or Python test cases.

## Preserved evidence and archive verification

[evidence.tar.xz](evidence.tar.xz) contains every original file under
`main-delta/v3-final-checks`, the original outer validation log, the independent
rejection audit, and its audit script. Files retain their original bytes and
historical source identity. The small execution and audit JSON files linked
above are byte-identical readable copies of their archived originals.

- [Exact packet selection](packet-selection.json)
- [Archive member index](evidence.index.json)
- [Publication manifest](publication-manifest.json)
- [Independent archive verification](archive-audit.json)

The existing publication packer and archive verifier check canonical relative
member names, regular-file membership, exact archive/index member sets,
payload sizes, SHA-256 hashes, and equality with every original file. Their
archive/member counts are evidence counts, never test counts. No source plan,
product file, or runtime input is changed by this preservation packet.
