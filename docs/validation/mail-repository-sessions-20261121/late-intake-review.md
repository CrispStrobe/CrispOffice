# Late intake review for repository mailbox sessions

Observed cutoff: **2026-11-21T06:03:26.415841+00:00**. The four immutable heads below are the intake boundary; later active-branch changes require a separate review. Remote main at intake is `84046975f286407e3c62e5e5352bc16bc89c0d26`; our committed Mail checkpoint is `6ec90c8a3acdc8fb5878f1decef0131e478e6b1d`.

## Recommended integration order

| Order | Branch snapshot | Readiness |
| --- | --- | --- |
| 1 | `perf/keystroke-trace-20261121` at `1460876e` | Small coherent follow-up; local syntax/fixture gate required. |
| 2 | `codex/word-vba-sections-20261121` at `a250152a` | Coherent implementation and substantial tests; this snapshot lacks final local qualification receipts. Qualify before main. |
| 3 | `codex/zotero-transfer-20261121` at `3da241d5` | Implementation checkpoint now includes model/editor integration and tests. Qualification is explicitly in progress; run focused gates before main. |
| 4 | `feat/proofing-scheduling-20261121` at `5fcdb2db` | Three explicit WIP commits, but complete scheduler/settings/test paths are present and no implementation TODO or Unimplemented stub was found. Broad semantic change needs local qualification and documentation completion before main. |

All four `git merge-tree --write-tree --name-only` simulations against the committed Mail head exited **0 with no conflicts**. The simulations did not modify the worktree, index or refs. The pending Mail UI paths do not overlap these incoming deltas. Zotero/proofing share `office_controller.dart` at separate locations; their pairwise simulation is also conflict-free. Textual mergeability is not runtime qualification.

The sections snapshot supersedes the initially reported `e44710e6`: `a250152a` adds the reproducible local-gate script and portable precision cases. It already contains our `c375becb` store/layout checkpoint. Preserve that ancestry and its replacement-layout retry correction.

## perf/keystroke-trace-20261121

Focus the profile harness and assert real layout work; pair GC begin/end trace events and separate NotifyIdle.

2 files changed, 33 insertions(+), 7 deletions(-).

**Minimum local gate:**

- Python syntax check and synthetic report fixture covering complete GC events, matched begin/end, nested same-name events and NotifyIdle exclusion.
- Analyze typing_profile_test.dart. Do not claim actual profile-device timing unless that integration harness runs on a target.

**Remaining boundaries:**

- No performance measurement is implied by merging instrumentation.

## codex/word-vba-sections-20261121

Word VBA section orientation/start controls, precision guards, compiler mappings, native transactional operations, example and portable smoke harness. Includes the Mail c375becb checkpoint by ancestry.

22 files changed, 5550 insertions(+), 64 deletions(-).

**Minimum local gate:**

- Engine strict analysis of lib/src/automation plus changed tests/tool/macros.
- Native tests: office_macro_word_orientation_test, office_macro_word_section_start_test, office_vba_word_sections_test, office_vba_word_sections_integration_test, office_vba_word_page_setup_test, office_vba_word_page_setup_integration_test, word_section_clone_fidelity_test and word_structure_integrity_test.
- Run actual word_sections.bas and word_page_setup.bas through supplied VM and compiled-JavaScript smoke harnesses; compare outputs (reproduce.py documents the defines).

**Remaining boundaries:**

- The committed reproduce.py is a qualification recipe, not evidence of a run at this head.

## codex/zotero-transfer-20261121

Staged Zotero document export/import, carrier model, native field restoration, editor controls and undo/identity preservation. Restores original placeholder callback after tracing upstream caller.

24 files changed, 10385 insertions(+), 40 deletions(-).

**Minimum local gate:**

- Strict engine/editor analysis including exhaustive Zotero command switches.
- Engine tests: word_zotero_transfer_session_test, zotero_transfer_protocol_test, word_zotero_citing_test, zotero_citing_test, zotero_add_note_protocol_test, word_zotero_add_note_test and word_zotero_document_data_test.
- Editor tests: word_zotero_transfer_controller_test, word_zotero_transfer_dialog_test, word_zotero_citing_controller_test, word_zotero_citing_dialog_test and word_zotero_add_note_controller_test.

**Remaining boundaries:**

- Branch README still states model/editor/interoperability qualification is in progress.
- Installed Word/LibreOffice/Zotero interoperability and direct native ODT reference-mark import remain separate.
- Prior fb692a7f non-exhaustive command-switch issue is fixed in this snapshot; the speculative placeholder contract change is removed.

## feat/proofing-scheduling-20261121

Provider-category scheduling, word/sentence completion checks, pause/idle work, visible-paragraph prioritization, persisted Studio settings and expanded scheduler tests.

11 files changed, 1709 insertions(+), 326 deletions(-).

**Minimum local gate:**

- Strict editor, engine proofing, Hunspell and Studio settings analysis.
- Editor tests: word_typing_proofing_schedule_test, word_proofing_session_test, word_incremental_proofing_test, word_proofing_capture_cache_test, word_proofing_priority_test, word_manual_proofing_test, word_draft_proofing_test and platform_spelling_provider_test.
- Studio example test: studio_settings_test. Engine: proofing/office_proofing_test, proofing/office_proofing_merge_test and proofing/german_spelling_test. Hunspell: hunspell_provider_test.
- Add the referenced docs/proofing/scheduling.md or correct the source link; record the new public scheduling/provider-category APIs in appropriate package changelogs.

**Remaining boundaries:**

- No new qualification receipt or changelog entry exists in these WIP commits.
- word_proofing.dart cites docs/proofing/scheduling.md, which is absent at the pinned head.
- About 924 changed lines in the scheduler plus settings/provider changes warrant existing manual/draft/cache regression coverage.

## Review conclusion

No newly introduced implementation TODO/FIXME/Unimplemented stubs were found in the reviewed deltas. Zotero transfer placeholders are protocol data, and its unsupported-content guards reject protected or ambiguous fields explicitly. The Zotero/Proofing WIP labels should not be treated as completion evidence: qualify their current source and finish the small documentation gaps before including them in main. If a targeted gate fails, repair the concrete issue before publication rather than silently claiming the branch was already qualified.

The exact commits, all changed paths and blob identities, pending-work overlap check and merge simulation outputs are retained in [late-intake-review.json](late-intake-review.json). This review ran no product tests and did not query or await GitHub Actions. No source, branch or remote was mutated.
