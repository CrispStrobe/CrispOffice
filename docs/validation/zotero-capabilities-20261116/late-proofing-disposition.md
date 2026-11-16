# Late proofing continuation disposition

This review compares the incoming proofing work with the qualified Zotero
source at `91978efb4f338ccd120a0178d8128369e67572bc`. It does not change the
source identity or scope of the earlier qualification receipts.

| Role | Exact commit |
| --- | --- |
| Previously integrated primary proofing | `52d6ae43b659875e92b06cbabdd8f206aabbad6c` |
| Incoming primary proofing | `f4d52e5b0f04aa0a57cef2074f0b5ee3d2868f48` |
| Earlier alternate resume | `4d395da7c1253dbebfce4a5065fdfd257939ce1c` |
| Intermediate alternate reviewed here | `54155845dfda909981e73f274a2550b265e2498b` |
| Latest alternate at the final incoming cutoff | `ca294cf8668706b45f40031ed9a2db52e5737cd2` |

## Primary integration

Retain the primary `lib/src/embed/word_proofing.dart` session and its existing
controller, dialog and rendering integration. `f4d52e5` continues that design;
it does not install the alternate callback-based session beside it. Its
parents already retain the old alternate `4d395da`, old vendor `95debbc`,
feature `e5daa205`, main `14b13980` and Zotero `039c1e29`. Earlier audit
dispositions remain valid for their recorded source pins; ancestry after this
new integration must be evaluated against the new published checkpoint.

The new primary changes include:

- Controller entry points for document proofing, guarded correction, finding
  navigation and caret lookup. Standard header/footer findings navigate to
  their actual rendered story and synchronize the IME selection afterward.
- Selection-permission checks, page-number field exclusion and cache
  signatures, rejection of unchanged or multiline replacement suggestions,
  and restoration of ignored advisory rules.
- Direction-aware presentation hit testing, trailing caret placement for
  zero-source labels, and a source-paragraph fallback for logical line text.
- Optional Harper installation and verification tooling with source hashes,
  checks for changes during builds, artifact verification before host writes,
  runtime/notice manifests, and packaging regressions. The primary also
  includes the positive-timeout guard and typed native startup failure from
  the older resume branch. Its incoming native/Wasm evidence belongs to the
  source and environment named in those receipts, not automatically to the
  new combined Zotero qualification.

The four production Zotero files (`word_zotero.dart`, `zotero_client.dart`,
`word_zotero_format.dart`, and `word_zotero_dialog.dart`) have identical Git
blobs in `91978efb` and `f4d52e5`. The generated German hyphenation data,
standalone license and generator also match exactly.

## Conflict resolution and selected correctness ports

A diagnostic merge of `91978efb` and `f4d52e5` reported one textual conflict:
`packages/quds_office_editor/lib/src/editor_word/paint_run_text.dart`, in the
nearest-run hit fallback. Resolve it by retaining the explicit discretionary
hyphen case and using incoming `_displayHit` for the remaining presentation
case. Keep both the existing caret regression file and incoming
`word_hyphenation_resume_test.dart`. The auto-merged `CaretEngine` retains
the explicit hyphen guards and the incoming general directional label logic.

Five bounded behaviors from the alternate continuation were adapted to the
existing primary session:

1. **Document replacement:** clear cached provider reports and ignore-once
   state when a host directly replaces `controller.document`, including
   replacement that reuses the same paragraph object. Both `invalidate()` and
   `checkDocument()` enforce this; controller notifications still use the
   same path.
2. **Tracked insertion:** validate the insertion at the original finding end,
   not only the text being marked deleted. Reject insertion affinity into
   adjacent fields, locked/data-bound controls or pending revision content;
   preflight the actual tracked insertion operation before opening history.
3. **Whole-paragraph grapheme boundaries:** reject a correction whose source
   range cuts a grapheme across differently tagged runs. Provider-result
   validation already checks each submitted segment, but that alone cannot
   establish the boundaries of the original paragraph.
4. **Empty complex fields:** exclude generated insertion points in closed or
   spanning empty complex-field paragraphs, including a paragraph that closes
   a field opened earlier. Ordinary blank paragraphs remain checkable and
   support legitimate insertion suggestions.
5. **Story-specific undo selection:** bind caret restoration to the original
   comment or header/footer story as well as the shared caret object. Undo and
   redo update the corrected source while preserving the selection in another
   story opened afterward; returning to the corrected story still restores
   its original selection on undo.

These changes preserve the current session API, original document metadata,
source text on rejection and undo history. They do not introduce the alternate
session or renderer.

## Focused verification

Six new regressions in `word_proofing_test.dart` compiled and failed
behaviorally before the guards: two direct-document replacement paths kept
one provider request instead of making two; three tracked-boundary cases
incorrectly remained applicable; and a correction across a combining
grapheme split by language runs incorrectly remained applicable.

After the changes, **75 tests passed** across:

```text
word_proofing_test.dart
word_proofing_ui_test.dart
word_proofing_context_test.dart
word_hyphenation_caret_test.dart
word_hyphenation_paint_test.dart
word_hyphenation_resume_test.dart
```

This includes the six new cases, the earlier four real-layout caret
regressions, incoming primary regressions and existing UI/context coverage.
The focused result must not be added again to a later cohort that contains
these files. Formatting and whitespace checks passed; final strict analysis
and combined host qualification are recorded separately.

A subsequent bounded check added three separate regressions for the last two
behaviors above. All three compiled and failed before those final guards:
an empty-field insertion was actually applied, and switching either comments
or header/footer stories caused undo to restore selection anchor `7` from
the corrected story instead of preserving the current story's anchor `1`.
Afterward, the same six-file cohort passed **78 tests**, including all nine
new regressions. The earlier six-case control logs and 75-test result were
preserved; the additional before/after controls are separate. The 78-test run
supersedes, rather than adds to, the overlapping 75-test cohort.

## Latest alternate: retained differences

`ca294cf` continues the separate `lib/src/proofing/word_proofing.dart`
architecture and alternate renderer/dialog APIs. It merges the newer ODS,
Zotero and primary proofing histories while retaining that architecture.
It is not a patch-equivalent substitute for the integrated primary, and a
whole-branch merge would require resolving competing session and rendering
implementations. Retain its exact remote head and evidence; do not claim all
of its behavior was incorporated by the selected ports above.

Distinct retained behavior includes whole-grapheme provider segmentation
across language/noProof runs, reuse only of complete provider reports, and
additional renderer/session test interfaces. The selected global correction
guard does not claim to implement the alternate segmentation policy.

The latest `ca294cf` delta also contains an engine difference handled
separately from these session regressions:

- `word_style_cascade.dart` normalizes an omitted `noProof` on/off value to
  true, so a higher style layer's `<w:noProof/>` overrides inherited explicit
  false. Its dedicated `word_comment_proofing_styles_test.dart` exercises
  this. The exact twelve-line engine correction and incoming four-test fixture
  were also integrated. The baseline compiled with three behavioral failures;
  all four new tests plus fifteen existing style/layout cases then passed.
  See [the bounded control receipt](late-controls/no-proof/receipt.json).

The already-enabled hyphenation/default-language fix is already represented
by the primary controller's comparison of both the hyphenation flag and saved
language. The latest alternate's page-number metadata, half-open issue ranges,
comment style traversal and replacement-dialog lifetime changes substantially
overlap the retained primary implementation. Optional Harper tooling should
retain the primary's stronger pre-copy artifact and build-stability checks.

This review used fetched local Git objects. It made no additional fetch,
commit, ref update or GitHub Actions query. Mainline ODS/documentation
integration and the final incoming inventory are recorded separately.

Raw negative-control logs are archived losslessly as `.log.gz` files under
`late-controls/`; `gzip -dk` restores the original names and bytes referenced
by their receipts. Passing logs remain plain text. These focused runs are
excluded from the later combined qualification total.
