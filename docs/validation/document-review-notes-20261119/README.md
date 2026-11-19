# Inline document review continuation — 19 November 2026

**Current combined qualification: pending.** The prior Notes/header review
checkpoint was fully published, but two related branches advanced afterward.
This continuation integrates those changes before requalifying the combined
source. No GitHub Actions result is queried or awaited.

## Saved work recovered and verified

Published commit `840362cd74a3d4b4365cf2bc9a2ae326225009c3` contains the original
final archive and all three screenshots. The independent
[saved-evidence audit](previous-evidence/saved-evidence-audit.json) verifies
129 archive members, 5,012 frozen source inputs, 11,165 recorded runtime inputs,
and 1,244 actual passing Dart/Flutter cases across 77 suites at source
`a7512e94da8208123aa2df5f5c2c0354d079ddc7`. The separate 56 Python cases and
documentation-only publication scope were also checked. These remain historical
results for that source, not passing evidence for the new integration.

## Incoming work integrated first

The bounded [snapshot](incoming/captured-refs.json), captured at
2026-11-19T05:23:39.688Z (06:23:39 CET), contains 391 references and 253 distinct
heads: 212 fork branches, 175 PR heads, and four upstream branches. Compared with
the previous capture, only the Zotero and thesaurus external heads advanced.

| Incoming branch | Integrated head | Saved merge |
| --- | --- | --- |
| Thesaurus / shared review and research lists | `7e4adc08fce78fb95524f304962f9c1804e18691` | `7a006981fa0948ac0a39347dbb123d0ef98be128` |
| Zotero final continuation | `0abd0e592ad607a88a6a7db6a5bf235939efa5b9` | `2c17906cc52efcaa518a87805de7fc88b05d2d43` |

[Initial integration verification](incoming/post-integration-audit.json)
accounts for all captured references: 363 by ancestry and 28 by 14 independently
reverified historical equivalents. There are no missing captured heads. Later
branch advances are outside this initial cutoff.

The final fork/PR advertisement refresh at **06:30:54 CET** captured three
concurrent reconciliation heads: Mail `0ce210973f1c86483ffcea9b91c83bbf067575e0`,
thesaurus `59f13897fd5aafccc234c58f41370dd786703418`, and Zotero
`f3b7dc3bf4a994781e40fa89e076ebe485ce3d0d`. They are integrated in saved commit
`bb241a34a1722a44b29f51fdce4be64e0ffc47b9`. The
[final bounded snapshot](incoming/final-bounded-refs.json) retains the original
API capture and later Git advertisement provenance. Its
[immutable verification](incoming/final-integrated-audit.json) again confirms
391 references, 253 heads, all 14 historical proofs, and zero missing heads.
Qualification uses this final cutoff rather than following later moving tips.

## Combined behavior and conflict resolution

The review branch retains inline Notes spelling, grammar and style findings;
correction, ignore and dictionary actions; explicit and live checks; exact Notes
language ranges; document-level keyboard Undo/Redo; settled manual-provider
coverage; and default/first/even header/footer ownership.

Incoming native Zotero research-list numbering and transactional Undo/Redo are
included. Review uses the incoming stable `Flex` layout while retaining the
existing document-pane key. Both the Review layout identity checks and the
review branch's wide/narrow resize and real-font screenshot regressions remain.
The IME correction test now exercises tracked and untracked edits, original
revision identity, and separate Undo of the correction and typed draft. The
Notes citation fixture retains visible-field and focus assertions.

Equivalent manual-provider fixtures use one consistent disjoint range.
Distinct assertions from both branches were preserved. The last three heads
contained overlapping reconciliation choices: their changed product files were
compared directly with the combined source, and the existing document key,
tracked-revision identity assertions and stronger focus assertions were retained.
That final merge leaves the combined product/test tree byte-identical to
`2c17906c`, while adding the incoming qualification records and hardened
thesaurus replay runner. Source review found no additional concrete product
defect; runtime validation remains required.

## Local gate

The committed [plan](test-plan.json) requests 79 suites: the prior 77 plus
`word_list_numbering_snapshot_test.dart` and `word_zotero_note_list_test.dart`.
It also requests strict analysis, formatting and baseline whitespace checks.
Five incoming verbatim notice copies use the same Git blobs as the already
preserved notices; all 20 whitespace exceptions name exact paths and blobs.

The first fresh combined runtime restoration verified the official pinned SDK
and dependency archives, then failed at its native SQLite smoke because the
root-level entrypoint's owning package has no SQLite dependency. The corrected
restorer stages the exact probe bytes in the Mail store member's generated
directory, runs the genuine native hook, and removes only that temporary probe.
The corrected smoke and four offline placement/cleanup controls passed. A
complete fresh restoration into an empty runtime directory is now running after
preserving and removing only the diagnostic native cache outputs. The original
failure and probe records remain separate from final acceptance.

The full gate will run against one clean, remotely saved source commit with
before/after source and runtime fingerprints. Raw logs, actual case inventories,
runtime provenance and an independent audit will accompany its result.

## Scope

Stored alternate headers/footers absent from the rendered layout and nested
Notes table/frame content outside the flat Notes field remain pane-only.
These local tests do not establish full native/web builds, browser interaction,
physical OS keyboard/IME behavior, or live Mail/Zotero/provider interoperability.
