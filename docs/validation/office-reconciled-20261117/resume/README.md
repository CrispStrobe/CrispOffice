# ODT column-boundary follow-up — 17 November 2026

**Status: source and earlier evidence are saved remotely; final merged-source qualification is blocked by an execution-workspace outage.** The source checkpoint is `9e21e4c08a0a7f04c165dedc316038038b2c47d4`. Draft [PR #144](https://github.com/CrispStrobe/quds_office_suite/pull/144) targets `main`. The final 217-file broad run and 14-file portable run have no observed final receipts, so this report does not claim complete qualification.

The pasted ODT handoff was already published in PR #140. This session resumed from PR #143 at `947a6b572f3e95359b80d785e1a232e824fa723b`, fetched all 175 remote branch heads and all 143 PR heads, and captured them in `incoming-refs.json`. Main `2c47165d01d01cc883135a434ac9f6591ce6e770` is included.

PR #143 advanced while the first checkpoint was being saved. The further sheet-format and recovered-evidence commits through `83f8c380f9271b6bf34a300c3aedc19442cb61f1` were fetched and integrated. This continuation uses the dedicated remote branch `codex/odt-column-boundary-followup-20261117` so ongoing PR #143 writes do not compete. The separate native spaCy PR #139 remains separately owned, following the existing reconciliation decision.

## Source changes

A leading inline column break must remain separate from the paragraph that establishes a multi-column section. Previously only the first document section retained an empty source fragment. Later multi-column sections could combine the column and section/page boundaries on one paragraph, losing the column break to page/master precedence. The writer now retains that source fragment for any multi-column section start.

Eight marker controls demonstrate the loss on the pre-fix writer: later next-page, continuous, odd-page, and even-page sections, each with and without an explicit paragraph page-break flag. A standalone explicit-page control preserves native precedence away from a section boundary. Bookmark order, text, section ownership, and model immutability remain explicit assertions.

The exact older imported-DOCX control also contains a later two-column section and two authored column breaks. Rendering its unchanged raw DOCX confirms right-column placement on page two followed by a left-column continuation on page three. Its old coalescing assertion was stale and is corrected to preserve the empty source fragment plus both breaks. With final test bytes, the incoming writer fails these nine controls and passes the other twelve cases across the two boundary suites.

The initially saved candidate `e95cb0ce562a39c7d3cddebff248c43eefe6442b` also separated an explicit paragraph page break from a leading inline column break. Independent rendering of the actual WordSerializer DOCX showed left-column placement for that case, while the candidate ODT put it in the right column. That proposed behavior was withdrawn; the final change is limited to the four independently confirmed section cases. The intermediate five-failure structural run is not presented as five product defects.

A restored column-style test expected negative gaps to be exported, contrary to the existing writer and `odt_section_columns_test.dart` contract. Its assertion now preserves that existing conservative profile: omit the unsupported negative gap attribute while preserving count, visible text, source value, zero normalization, and style precision. This is a test reconciliation, not a new negative-gap behavior or a claim that the ODF grammar forbids signed lengths. ODF 1.3 section 19.233 and the official RNG declare `fo:column-gap` as `length`:

- https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html
- https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/OpenDocument-v1.3-schema-rng.html

## Current merged source

Main advanced during verification. Commit `9e21e4c08a0a7f04c165dedc316038038b2c47d4` cleanly merges main `16e2477ff93f7a1ec5c6ed78491f2716ce4d1658` into the continuation. The latest refresh captured all 177 branch heads and 144 PR heads in `incoming-refresh.json`. The main merge brings its grammar, lexicon, ODF whitespace/extraction, spreadsheet controls and release evidence. The ODT writer remains byte-identical to `9b33bec0`.

One inherited editor grammar scenario expected the older `de.grammar.verb-case` identifier. It now expects the documented `de.grammar.verb-object-case` identifier while keeping the exact replacement, corrected text, clean recheck, undo and redo assertions. All 32 tests in that editor file passed on the merged working tree; the complete before/after evidence is archived remotely.

The draft now targets main so already-landed main changes are excluded from its diff. It also includes the still-unmerged work inherited from #143. That PR remains open and untouched; its later merge will narrow the overlapping diff.

## Qualification and evidence status

The restored runtime is Flutter 3.47.8 / Dart 3.13.7 with the locked 108-package graph and the exact native library/model hashes required by the unchanged qualification runner.

| Check on the merged source | Last observed result | Durable raw evidence |
| --- | --- | --- |
| Five strict-analysis scopes | Each command passed | Final run receipt unavailable after outage |
| Formatter and Python controls | Both commands passed | Final run receipt unavailable after outage |
| Complete 217-file qualification | Started; final outcome unobserved | Not uploaded |
| Portable 14-file Node selection | Started; final outcome unobserved | Not uploaded |
| Retained independent consumers | 40 fixtures and 160 XML-part checks reported passing | Archive completed locally; upload did not start |
| New boundary consumers | Four strict layouts plus one bounded precedence control reported passing, across 15 PDF variants and 10 reopen checks | Packaging did not start |

The execution server disconnected and recovery timed out; the environment then explicitly reported unavailable. The source checkpoint had already been saved remotely and the checkout was clean before execution. No available tool could restore execution access. Observed stdout and archive metadata are preserved in [interruption-observations.json](interruption-observations.json); these records do not substitute for unavailable raw receipts or input maps.

Seven earlier evidence archives and their indexes are present remotely. They include the nine expected pre-fix failures and 21 passing focused VM/Node cases; 207 passing portable tests at `622f58c8`; the 32-test editor correction; retained and scoped consumer outputs; pinned runtime recovery; and the original failed/rejected attempts. Counts overlap and are not additive. Their source attribution is retained in [verification.json](verification.json).

## Independent review and limits

[peer-review.json](peer-review.json) records no blocking finding in the inspected product change, test reconciliations or incoming-main merge. It explicitly leaves release acceptance false until final merged-source qualification can be recovered or reproduced and audited.

Native DOCX comparisons use LibreOffice rather than a live Microsoft Word installation. The standalone page-precedence control deliberately records a preexisting follower-balancing difference; it does not claim full native layout equivalence. The exact raw-DOCX control compares column/page order while preserving the documented Letter/A4 default-paper distinction. Two unavailable private PDF fixture early returns are excluded from substantive broad-run pass counts. A VM-only fixture-export helper remains in the VM cohort and outside the portable selection.

## Resume from this checkpoint

[recovery-handoff.md](recovery-handoff.md) records the exact source, runtime, commands, pending gates and last known evidence paths. Recover intact receipts if execution access returns; otherwise rerun the unchanged gates on one clean frozen commit, verify input stability, archive the results and save them remotely before marking the draft qualified.

GitHub Actions, workflow, check-run and CI-status endpoints were not queried, awaited or rerun. Commits were saved incrementally with `[skip ci]`. The remaining blocker is execution access, not publication permission.
