# Generic ODT field reconciliation and controlled evidence

## Final focused result

The reconciled writer passes **543 cases across 33 ODT/ODP/ODF files**, including
all **23 final field controls** and the incoming PR124 field assertion unchanged.
The final 23 controls run against exact incoming main
`13e7172977d671190ba8c3cf964deec4d7473090` produce **20 failures and three passing
controls**. These are fresh source-bound executions, not historical totals.
All **92 XML parts in 23 generated fixtures** validate against the pinned official
ODF 1.3 schemas. Strict analysis and formatting pass.

This is focused provisional evidence for the integrated engine snapshot described
by `final-integration-binding.json` and `final-integrated-source-map.json`.
The complete canonical qualification must run again against the subsequently
published immutable commit, including the final bookmark follow-up. The 543 and
23 counts overlap and must not be added together.

## Retained incoming contract and bounded representation

PR124 introduces native PAGE, NUMPAGES, DATE, TIME and TITLE boundary fields.
Its existing test requires one empty `text:page-number`, one empty
`text:page-count`, and exclusion of their generated cache `99`. That exact test
function is retained, with SHA-256
`02c05a3a91fee21a3b8489c430ed491b316317501b64c0d7b6f0dc87b09c5627`.

The corrected writer recognizes complete, balanced, non-nested, paragraph-local
fields. It joins instruction fragments. A single ordinary cached run or a valid
range with no cached run can become a native empty field. An absent cache uses a
private temporary run; the source model is not changed. Styling, hyperlinks,
bookmarks and comment ownership remain with their source run and story.

The pinned validator accepts native page-count directly in the paragraph, but
rejects its inline span wrapper. Therefore only an unlinked run with default
properties becomes a native NUMPAGES field. Styled or hyperlinked NUMPAGES keeps
its original cached text and styling. The absent direct-properties marker from
actual DOCX import is an empty string, which is accepted alongside null.

Nested, malformed, cross-paragraph, locked, atomic note/picture, inline-break,
multiple-run or whitespace-sensitive field ranges retain visible cached content.
Unknown and citation fields also retain exact authored cached text. The helper
uses no persistent suppression depth, so a malformed field cannot suppress the
next paragraph, header, note or other owned story. It does not claim arbitrary
Word field conversion or editable native field metadata preservation.

## Interaction with hard column breaks and paragraph PAGE fields

The existing paragraph-wide PAGE and styled suffix path remains separate and
owns its single generated PAGE field. Complex native boundary fields go through
the existing inline callback, preserving hard column fragmentation and bookmark
resolution.

Column classification makes a read-only pass through the same field recognition
helper. It records the exact source index of a generated cached run or, for an
uncached field, its separator. These indices count as generated content even
when the source text is empty. A following column break therefore stays after
the generated field. Exact indices avoid ambiguity if a caller reuses the same
run object at multiple source positions.

Four controls were demonstrated negatively against intermediate integrated
snapshots before their corrections: an empty cached run followed by a column
break, plain NUMPAGES imported from actual DOCX, and uncached PAGE/NUMPAGES followed
by a column break. The first snapshot passed 19 and failed two of 21 controls;
the next passed 21 and failed two of 23. The final snapshot passes all 23.

## Preserved development failures and probe corrections

All original raw output and generated fixtures remain archived. The first
launcher failed before assertions because the default temporary directory was
unavailable. A subsequent test-load attempt used two incorrect model constructor
forms; their corrected setup and the reconstructed exact failing test bytes are
retained. Those attempts are not substantive negative controls.

An earlier 17-case probe assumed native fields should retain cached text inside
the native element. It exposed the incoming global suppression defect, but that
assumption conflicted with the explicit PR124 contract. The original upstream
test passed on incoming source and failed once on that exploratory candidate.
The final implementation restored the native-empty-element contract without
changing the incoming test. The broader cache-retention rule applies to unsafe
fallback shapes and unknown/citation fields.

That earlier probe also preserved the original 67/68 schema result for a styled
page-count. The final direct/native versus styled/cached NUMPAGES boundary passes
92/92 parts. The final 23 test bytes were rerun negatively and positively after
the contract and interaction corrections. Earlier exploratory passes are not
added to the final counts.

## Reproduction and evidence integrity

`run_controls.py` records exact commands, test and writer hashes, raw Dart JSON
events, exit codes, fixtures and before/after input checks. `validate_schema.py`
checks both official schema hashes before reading every generated package part.
The archive includes complete source versions needed for the failed probes,
the unchanged incoming field test, final controls, exact patches, source maps,
all receipts and raw events, schema results, and the captured main13 audit.

For the final focused engine snapshot, start with `git archive` of incoming
main13's `packages/quds_office_engine`, then apply the archived
`integrated-overlay` files and removal list. Its archive hash and overlay recipe
are recorded. Rebase the recorded package config to the restored engine path,
using the same recovered SDK and cached dependencies. Other source versions are
recreated by substituting the archived writer and control file named by the
matching receipt. The archive does not duplicate the large runtime or dependency
binaries. Every archive member is read back and verified by size and SHA-256.

No GitHub Actions, workflow, check-run or CI-status endpoint was queried or awaited.
