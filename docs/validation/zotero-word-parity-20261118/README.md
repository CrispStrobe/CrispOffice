# Zotero Word-style workflow continuation — saved checkpoint, final qualification pending

## Status

The native research-note, direct-command and reference-navigation upgrade is saved on `codex/zotero-word-parity-20261118` and proposed in [draft PR #173](https://github.com/CrispStrobe/quds_office_suite/pull/173).

The integrated application checkpoint is [`a8029e95401ecef674fcbd920f78d2eb68ea89c0`](https://github.com/CrispStrobe/quds_office_suite/commit/a8029e95401ecef674fcbd920f78d2eb68ea89c0). **There is no completed final exact-source test total for this checkpoint.** Shared executor disk exhaustion prevented the final run and the incoming locked-dependency refresh. The PR remains a draft for that reason. GitHub Actions were never queried, polled or awaited.

## Implemented workflows

| Workflow | Behavior |
| --- | --- |
| Add Zotero research note | Studio **Insert → References → Add Zotero note**, or the references workspace's **Document → Add note from Zotero…**, invokes Zotero's native note picker. Supported note text and active citation placeholders are staged together and inserted at a valid body caret as one undoable operation. |
| Rich research-note content | Retains supported paragraphs, empty paragraphs, soft breaks, heading levels 1–6, character formatting, safe links and default annotation-export wrappers. Citation placeholders become active fields and participate in later refresh/bibliography operations. |
| Return to writing | Direct ribbon and keyboard commands show compact progress and return to the resulting body/Notes caret after success, cancellation, a declined formatting review or a completed no-op. Errors remain visible with **Return to document**. The ordinary workspace remains open for browsing. |
| Go to reference | A Document field menu can reveal and select an existing citation or complete bibliography in supported body/table/Notes locations. This does not dirty the document or add undo history and works in read-only selecting mode. |
| Existing workflow compatibility | Preserves the preceding body/Notes citation editing, document preferences, bibliography, refresh and keyboard command APIs. The new `closeAfterCommand` dialog argument defaults to false. |
| Transaction safeguards | Rejects stale targets and unsupported Add Note insertion contexts. Picker cancellation discards staged temporary fields/preferences. Body and Notes composition blocks command entry; a new composition invalidates an outstanding transaction. |

The [user and embedding guide](../../zotero-support.md) describes supported content, exact menu paths, APIs, and refusal behavior.

## Bugs found during development and independent review

1. At one body anchor, new Add Note citations and an existing citation converted between footnote and endnote could receive a staged ordering inconsistent with the applied document. The comparator now puts newly inserted note text before the converted original field. Both conversion directions have regressions checking staged, applied and DOCX-reopened order.
2. A body IME composition could reach a native command before the dialog's transaction checks. Command entry is now guarded before opening a modal or committing pending Notes edits. Transaction identity includes the composing range.
3. Automatic modal focus restoration called `attachInput`, which reconstructed the input value and cleared a composition that started during native work. The reconnection path now preserves the existing complete input value only when its target/selection identity, model text and bounds remain valid. Ordinary caret/edit synchronization keeps its existing behavior. This final fix passed strict analysis, but its focused runtime regressions remain unexecuted because the executor became unavailable.
4. The viewing-mode references workspace initially inherited a mutation-only gate. Browsing is available in viewing/selecting modes, while mutations retain their editing-mode gate.

## Reconciliation before work and at the bounded refresh

The initial local audit captured **386 refs** before implementation and accounted for all of them at published integration baseline `aad56eb498aa4839ad5bb11fd35d9f734d2ca397`: 358 ancestors and 28 historical equivalent refs at 14 heads.

A bounded refresh at **20:43:35 UTC / 21:43:35 CET on 18 November 2026** captured **389 refs**: 212 fork branches, 173 PR heads and four upstream branches. It found newer Mail, review and thesaurus heads while this work was in progress.

The final integration preserves four parents:

- Zotero checkpoint `55c02534868b13e1eb0b5c9391d133e9bac57ecb`
- Mail `8a6105a7ec217b48105d171703c8d0294c7d2dc6`
- Document review `840809bbe23f95815a5ddcd2a7ee76c250b9fb8c`
- Thesaurus `7c4f8bfa67b69e6fa4d8809724ae036cdcde492f`

All 14 review changes had identical blobs already present in Mail. All 50 later thesaurus changes were disjoint from Mail's changes since their common base. The merge retains the newer compact ribbon's `mainAxisSize` line alongside Zotero's command guards.

GitHub object verification checked **131 expected changed paths** from the preserved Zotero checkpoint, with **127 incoming blobs matching exactly**, three new reconciliation files, and the combined ribbon file verified byte-for-byte against the constructed result. All 46 binary/text acceptance blobs are retained through the existing thesaurus tree object.

The refreshed accounting is **361 refs by ancestry, 28 historical equivalents, zero unaccounted**. This is a transitive proof using the complete baseline audit, preserved ancestry, exact new parents, and explicit main/PR #169 ancestry comparisons. The executor failure prevented a fresh local rerun over all 389 refs after integration; that distinction is recorded in [the verification receipt](reconciliation/integration-verification.json).

Evidence:

- [Initial reconciliation](reconciliation/README.md)
- [Refreshed exact inventory](reconciliation/refresh-captured-refs.json)
- [Ref changes](reconciliation/refresh-delta.json)
- [Incoming content/merge proof](reconciliation/refresh-merge-proof.json)
- [Published integration verification](reconciliation/integration-verification.json)

This is a bounded observation; it does not claim to include remote changes created after that capture.

## Local verification completed before the interruption

The following are development results, **not disjoint counts and not a final result for the integrated checkpoint**:

| Development selection | Recorded result |
| --- | --- |
| Add Note protocol/model initial regressions | 46 passed before the later two ordering regressions were added |
| Add Note / note insertion / preference flow after the ordering fix | 87 passed, including both new ordering cases |
| Navigation, Notes and related compatibility selection | 77 passed before the later IME additions |
| Navigation/controller with the first four IME cases | 27 passed |
| Direct-command workflow selection before two later IME cases | 20 passed |
| Add Note controller / undo / serialization selection | 15 passed |
| Studio composition shortcut and saved ribbon callback | One focused regression passed |
| Changed controller/Notes/navigation source and tests | Strict analysis passed before the executor failure |
| Final IME reconnection change | Strict analysis passed; five reconnect cases and the UI return-path regression still need execution |

Other development compatibility and Studio shortcut checks also completed. These overlapping runs must not be added into a claimed distinct total. The earlier 1,489-test Notes continuation belongs to its original source checkpoint and is not this increment's result.

The planned final selection in [plan.json](plan.json) contains **77 distinct test files** (32 engine, 38 editor, seven Studio) and 19 analysis/format targets. The [runner](run_local.py) records exact commands and raw JSON events, requires zero errors/failures/skips/unfinished cases, and compares source/runtime/dependency fingerprints before and after every frozen-source run.

The prepared runtime was Flutter **3.47.8** / Dart **3.13.7**. Its original 168 verified hosted-package receipts matched the pre-Mail lock union. Incoming Mail changes add eight workspace lock entries; the final merged lock has been preserved unchanged, but that runtime refresh has not run. This report does not claim those eight entries were installed.

The optional 360 × 720 / 1.8 text-scale progress/error render was visually inspected successfully before the final fixes. Its local images/logs were not included in the remote checkpoint because the filesystem reader subsequently became unavailable. It is excluded from every test total.

## Executor failure and preservation boundary

After a test loader reported `No space left on device`, 376,056,280 bytes of verified untracked generated caches were removed without touching source, SDK, dependency cache or Git data. Shared free space continued falling while this workspace remained approximately 2.6 GiB. The sandbox helper then refused even read-only process startup.

A requested fallback cleanup outside the sandbox was rejected by the workspace's granular approval policy, which disallows sandbox escalation. Desktop runtime recovery was also unavailable. Subsequent file readers failed at the same sandbox setup boundary.

Product fixes, tests, guide changes and the incoming integration were saved through the authenticated GitHub connector. [The recovery checkpoint record](recovery-checkpoint.md) identifies which product edits were reconstructed exactly and why test formatting/wording still needs reconciliation with the inaccessible staged tree. **The local checkout is not synchronized with the final remote head.** Original pending files and development logs remain in that workspace; no hard reset or destructive cleanup was performed.

## Required completion steps

1. Restore normal executor capacity. Fetch the published branch and preserve/compare the existing local modifications before synchronizing; do not discard the original staged files or logs.
2. Reconcile the recovered test wrapping/wording with the original staged tree `eff63c16b872b0bf0c45394c543e4666375ec4ad`, then format and analyze the selected files.
3. Materialize the incoming Mail lock additions by their recorded archive hashes and run enforced locked dependency resolution without changing the lock.
4. Run the focused UI composition-return and five controller reconnection regressions first. Resolve any actual failure before freezing a new checkpoint.
5. Run the 77-file local plan on a clean, saved application commit. Run the relevant incoming Mail/thesaurus checks or document exact source-equivalent inherited qualification separately.
6. Publish raw results, source/runtime fingerprints and an independent count/hash review. Only then mark PR #173 ready.

With a restored pinned runtime and a clean frozen source commit:

```bash
python3 docs/validation/zotero-word-parity-20261118/run_local.py \
  --repo "$PWD" \
  --expect-commit <saved-application-commit> \
  --output docs/validation/zotero-word-parity-20261118/results-final
```

The output directory must be new. Do not use GitHub Actions as a gate or wait for it.

## Acceptance limits

Add Note requires a supported collapsed body caret. Unsupported images, lists, tables, arbitrary formatting and unconverted/invalid placeholders are refused as one transaction. Research-note insertion is separate from editing citations inside existing footnotes/endnotes.

Supported model/controller tests include DOCX serialization and reopening through Quds' engine. This continuation has not performed new live Zotero/account testing, an installed application/OS shortcut acceptance run, or actual Word/LibreOffice reopening. Those remain separate acceptance steps.
