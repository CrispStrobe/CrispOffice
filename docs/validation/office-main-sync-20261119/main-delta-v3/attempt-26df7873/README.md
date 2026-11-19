# Rejected strict-analysis attempt at `26df7873`

This exact-source qualification attempt remains **FAIL** and
**`accepted_qualification: false`**. The independent audit counted **634
successful native application cases** and **21 successful Python controls**,
with zero failed or skipped application cases. A strict-analysis failure
rejected the complete attempt before the Node and browser stages began.
No result from this attempt contributes to a later accepted qualification total.

The attempt was bound to source commit
`26df787326f58a002b62241b7feb52acff089f2f`, tree
`29516c01bee48ee2a940fb36682da70db1dc1eec`, and ran from
2026-11-19 10:33:54.875606 CET to 10:41:35.623719 CET.
See the unchanged [original execution receipt](execution.json).

## Exact reason for rejection

Locked offline workspace resolution, the delta continuity guard, the Python
controls, and all six native application groups completed successfully.
Strict analysis rejected this sole diagnostic from the incoming engine exports:

```text
info - packages/quds_office_engine/lib/quds_office_engine.dart:120:1 - Sort directive sections alphabetically. Try sorting the directives. - directives_ordering
```

The analyzer returned exit code 1. Formatting and whitespace checks succeeded.
The outer driver retained the rejected native receipt and stopped: **Node tests
and browser compilation did not run**. This packet records the original result;
any corrected source requires its own fresh qualification and accepted audit.

## Observed results remain separate from acceptance

| Native application group | Successful cases |
| --- | ---: |
| Hunspell native | 28 |
| Mail cursor integration | 50 |
| Arabic rules | 294 |
| Word language routing and finding merge | 70 |
| Word Arabic/editor integration | 73 |
| Studio integration | 119 |
| **Observed native successes** | **634** |

The Python controls comprise 17 AyaSpell bundle controls and four Hunspell
packaging controls. They are counted separately from application cases.
The independent audit found no malformed reporter lines, raw reporter errors,
or failed/skipped application case events. These observations do not waive the
strict-analysis gate or add any results to accepted totals.

## What the independent audit establishes

The unchanged [independent audit](independent-audit.json) records
`audit_checks_passed: true`, `recorded_failure_confirmed: true`, and an empty
`issues` list, while retaining `accepted_qualification: false`. Its successful
checks establish that the rejection, raw case events, and source/runtime guards
were correctly recorded. They do not turn the failed qualification into a
passing one.

The audit binds **5,116 source inputs** to the immutable source commit and
confirms equal before/after source and runtime snapshots, with **11,171 runtime
inputs** in the stable outer envelope. The original native runner uses its own
narrower snapshot scope; those original counts remain unchanged in its receipt.
The recorded source head and tracked checkout also remained unchanged during
the attempt. The independent audit and this preservation step execute no
application or Python test cases.

## Preserved evidence and archive verification

[evidence.tar.xz](evidence.tar.xz) contains every original file under
`main-delta/v3-qualified-checks`, the original outer validation log
`main-delta/v3-qualified-validation.log`, the completed independent rejection
audit, and its audit script. Files retain their original bytes and historical
source identity. The execution and audit JSON files linked above are
byte-identical readable copies of their archived originals.

- [Exact packet selection](packet-selection.json)
- [Archive member index](evidence.index.json)
- [Publication manifest](publication-manifest.json)
- [Independent archive verification](archive-audit.json)

The existing publication packer and archive verifier check canonical relative
member names, regular-file membership, exact archive/index member sets,
payload sizes, SHA-256 hashes, and equality with every original file. Their
archive/member counts are evidence counts, never test counts. No source plan,
product file, runtime input, prior archive, or original log is changed by this
preservation packet. GitHub Actions were neither queried nor awaited.
