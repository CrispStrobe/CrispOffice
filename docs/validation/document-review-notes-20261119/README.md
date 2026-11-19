# Inline document review continuation — 19 November 2026

**Final local qualification: PASSED.** The combined source at
`8a5dd9baa1884beae3ae69cfe77946adab9d07a6` (tree `842449e617aabd725ff25fdc13b99a25b8a9274e`)
passed **1,283 actual Dart/Flutter cases across 79 suites, with zero failures or
skips**, plus strict analysis, formatting and whitespace checks. The independent
raw-log and source/runtime audit agrees. Another **147 Python controls passed**,
counted separately. GitHub Actions was neither queried nor awaited.

## Review stays beside the edited text

The accepted source retains the full Notes/header review work and integrates
captured Mail, Zotero and thesaurus updates:

- Footnotes/endnotes show spelling, grammar and style underlines inside the
  editable Notes field, with live-checking and coverage status, explicit checks,
  nearby corrections, Ignore once, dictionary actions and finding navigation.
  F7 checks; Alt+F7 and Alt+Shift+F7 move between findings.
- Language/checking targets the actual Notes selection or editable paragraph.
  Keyboard Undo/Redo uses document history; a new draft after Undo cannot be
  overwritten by an abandoned redo branch. Completed manual checks survive a
  history-only commit without rerunning the provider.
- Opening, closing and resizing Writing/Changes preserves the actual Notes
  field, selection, focus and composition. The stable Review layout retains the
  document-pane key and both branches' distinct regression assertions.
- Header/footer editing and navigation select the rendered default, first-page
  or even-page story. Editing chrome paints beneath readable text; selection
  stays within its source story.
- Incoming Zotero native research-list numbering and transactional Undo/Redo
  are included, alongside the captured Mail durable-store and thesaurus work.

The [document review guide](../../document-review.md) describes the complete
workflow. Stored alternate headers/footers absent from the rendered layout and
nested Notes table/frame text outside the flat Notes field remain reviewable in
the pane. Navigation does not change page settings or substitute another story.

## Incoming integration and preservation

The [final bounded capture](incoming/final-bounded-refs.json) closes at
**19 November 2026, 06:30:54 CET**. It combines the initial full API capture with
one final fork/PR Git advertisement refresh, preserving both sets of provenance.
There are **391 references / 253 distinct heads**: 212 fork branches, 175 PR
heads and four upstream branches. The
[verification against the qualified source](incoming/qualified-source-audit.json)
confirms **363 ancestry rows + 28 historical-equivalent rows**, all **14**
independently reverified historical proofs, and **zero missing captured heads**.
Later moving tips are outside this cutoff.

| Incoming continuation | Final integrated captured head |
| --- | --- |
| Mail / PR #172 | `0ce210973f1c86483ffcea9b91c83bbf067575e0` |
| Zotero / PR #173 | `f3b7dc3bf4a994781e40fa89e076ebe485ce3d0d` |
| Thesaurus / PR #174 | `59f13897fd5aafccc234c58f41370dd786703418` |

The incoming heads contained overlapping reconciliation choices. Direct tree and
parent comparisons preserved the combined source's stronger tracked-revision
identity and focus assertions, along with its document-pane key. Equivalent
manual-provider fixtures use one consistent disjoint range. The IME correction
regression covers tracked and untracked edits and separate Undo of correction
and typed draft. The final reconciliation added evidence and replay-runner
hardening without changing the already combined product/test tree.

[Publication checkpoints](publication-checkpoints.json) record the incremental
remote saves. Each update used an exact verified tree, a non-forced expected-head
update and `[skip ci]`. The recovered prior publication at `840362cd` was also
[reverified independently](previous-evidence/saved-evidence-audit.json): its
1,244-case result belongs to the earlier `a7512e94` source and is preserved
separately, never added to this continuation's counts.

## Completed local gate

| Group | Suites | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Engine review and Zotero | 11 | 217 | 0 | 0 |
| Editor review, Notes, headers and Zotero | 49 | 858 | 0 | 0 |
| Studio review and navigation | 9 | 98 | 0 | 0 |
| Mail core | 1 | 9 | 0 | 0 |
| Native Mail store | 7 | 87 | 0 | 0 |
| Mail Node problem handling | 1 | 3 | 0 | 0 |
| Mail reader UI | 1 | 11 | 0 | 0 |
| **Total** | **79** | **1,283** | **0** | **0** |

The [verification receipt](verification.json) binds the actual commands, raw
logs, per-suite results and completed-case inventories. The
[independent audit](independent-audit.json) directly recounts the reporter events
without importing the repository's reporter parser. It verifies:

- All **5,038** source inputs against immutable Git blobs and current bytes.
- All **11,165** runtime/environment inputs against before/after fingerprints
  and actual files. Source, HEAD, index, tracked worktree and runtime remained
  unchanged throughout the gate.
- Strict analysis and formatting for all **61** changed Dart files.
- The baseline whitespace check with **20 exact path-and-blob exceptions** for
  unchanged captured logs, raw patches and verbatim notices. No blanket log,
  patch or product-path exclusion is used. Git materialized immutable baseline
  blobs for this comparison; that read-only fetch is preserved in the evidence.
- All seven raw test logs scanned for layout overflow, missed taps, lost pointer
  events and rendering diagnostics: **zero findings**.
- Three fresh real-font captures, also [directly inspected](visual-review.json):
  [desktop Notes](screenshots/notes-inline-desktop.png),
  [enlarged RTL Notes](screenshots/notes-inline-arabic-narrow.png), and
  [even-page header selection](screenshots/header-even-review.png).

### Separate Python controls

| Target | Accepted cases |
| --- | ---: |
| Notes gate accounting | 20 |
| Mail gate accounting | 34 |
| Thesaurus browser harness | 19 |
| Thesaurus workspace binding | 17 |
| Zotero local runner | 32 |
| Thesaurus exporter | 7 |
| Thesaurus targeted replay runner | 14 |
| Native runtime entrypoint/cleanup controls | 4 |
| **Total, counted once** | **147** |

The seven existing targets contribute 143 cases; the runtime repair contributes
four separately qualified cases. The first targeted-runner attempt failed one
fixture because it read a child's `/proc` state immediately after SIGKILL. A
preserved diagnostic observed the child disappear within milliseconds. The
fixture now uses a bounded two-second monotonic observation interval while
retaining the strict disappearance/zombie requirement. Its complete 14-case
rerun passed. The production process-cleanup implementation is unchanged.

The original four-helper observation had successful raw unittest output but no
separately recorded process exit. A limited rerun captured exit zero and
unchanged source/executable hashes. Both original observations remain in the
archive and contribute no additional accepted cases.

## Fresh runtime reproduction repaired and executed

The initial fresh restoration verified the pinned SDK and package archives, then
failed at SQLite initialization. Its smoke entrypoint lived under the root docs
package, which declares no SQLite dependency. Changing only the working directory
did not make Dart discover the native hook.

The corrected restorer stages the exact smoke bytes under the Mail store
member's generated directory, runs genuine `dart run`, and removes only that
temporary probe. No tracked manifest or native mapping is synthesized. The
placement and cleanup controls cover exact bytes, dependency pinning, unrelated
cache preservation and cleanup on failure.

A **complete fresh `--node-tests` restoration passed with process exit zero**
after the diagnostic native outputs were archived, byte-verified and removed.
It verified the full official **1,581,444,364-byte** Flutter **3.47.8** / Dart
**3.13.7** archive, retained **551,242,378 bytes** including the Node compiler,
verified **176** hosted archives and resolved **130** workspace packages with
offline lock enforcement. All four restore commands passed. SQLite **3.54.1**
completed the in-memory FTS5 round trip; the copied library and cached hook
library both match the pinned SHA-256. Node and real text/icon fonts are bound.

The [fresh runtime verification](runtime-verification.json), original failed
receipt, original logs, exact hook input/output snapshots and full 13-file
diagnostic archive preserve the complete repair history. This newly executed
fresh path closes the earlier reproduction limitation; it does not relabel the
historical 18 November setup.

## Evidence and reproduction

- [Complete evidence archive](evidence.tar.xz) and [per-file hashes](evidence-index.json).
- [Final gate receipt](verification.json) and [independent audit](independent-audit.json).
- [Python verification](python-verification.json) and
  [qualified runtime-helper controls](runtime-helper-verification.json).
- [Fresh runtime verification](runtime-verification.json).
- [Frozen 79-suite plan](test-plan.json) and
  [runtime restoration instructions](../document-review-notes-20261118/runtime/README.md).

The archive preserves the original raw logs and receipt bytes, failed attempts,
case inventories, source/runtime manifests, helper execution records, native-hook
snapshots and screenshots. Every archived file is compared byte-for-byte with
its original after compression. Qualification belongs to the frozen source above;
[publication scope](publication-scope.json) verifies that subsequent documentation
and evidence changes leave every bound application, test, plan and executed
validation input unchanged.

To reproduce, check out the qualified commit, restore to an empty directory, and
run the committed plan with all Dart/Flutter groups serially:

```bash
python3 docs/validation/document-review-notes-20261118/runtime/restore_runtime.py \
  --repo /absolute/path/to/quds_office_suite \
  --runtime-root /absolute/path/to/toolchains --node-tests

python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head 8a5dd9baa1884beae3ae69cfe77946adab9d07a6 \
  --base 690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e \
  --plan docs/validation/document-review-notes-20261119/test-plan.json \
  --runtime /absolute/path/to/toolchains \
  --output /absolute/path/to/empty-check-output
```

These selected model/controller/widget/Node checks and rendered fixtures do not
establish full native/web application builds, real browser UI/storage behavior,
physical OS keyboard/IME acceptance, or live Mail/Zotero/provider sessions. The
Node problem-handling suite is not browser UI qualification. Some mock-provider
and coverage text in the RTL fixture remains English; no complete localization
claim is made.
