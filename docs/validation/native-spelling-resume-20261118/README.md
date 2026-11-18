# Native spelling resume — 18 November 2026

Work continues on `codex/native-spelling-resume-20261118` after reconciling
all captured incoming branches and pull requests. The integrated baseline is
`4dceb86e9fae51877bb5b7dc01e7a8bc721cb6ea`.

## Checkpoint status

This is an incremental implementation checkpoint; final qualification is in
progress. The native platform adapter now protects identifiers reported by the
system dictionary as whole spans, as well as fragments that contain a numeric
or connector character. Its existing adjacent-identifier protections remain.
The per-request grapheme index supports logarithmic lookup in arbitrary native
result order. Ordinary prose, explicit hyphen parts and CJK dictionary spans
remain reviewable.

The eight new native tests include Word review through Flutter's real default
spelling service with controlled method-channel responses. The unchanged
baseline reproduces seven behavioral nonpasses and one passing control. After
the repair, the initial four-file native selection passes 52 substantive tests,
zero failures or skips. These development results will be superseded by the
final source-bound qualification and archived raw evidence.

German spelling now recognizes the remaining decomposed letters in the shipped
dictionary (ë/Ë and š/Š), and composes accents after removing discretionary soft
hyphens. Original and projected link, email, code, identifier and grapheme
protections prevent partial corrections without changing the original tokenizer
or finding offsets. Personal and ignored vocabulary shares canonical comparison.

Independent review identified Unicode Prepend characters before numeric or
connector markers within one grapheme. Both checkers now examine the complete
grapheme when collecting those markers. The final focused German file passes
25 tests; the five independent native tests pass after the repair. Three native
Word-session tests cover canonical vocabulary, persistence, owner/locale
boundaries and cache invalidation. These focused runs overlap final acceptance.

The portable smoke panel contains 48 cases. Final complete engine/editor,
isolated baseline, strict analysis and VM/native/JavaScript validation will run
against the next saved implementation checkpoint. See [independent review](review.md)
and the [dictionary audit](dictionary-audit.json).

## Incoming work

[Reconciliation](reconciliation.md) and [the complete reference inventory](refs.json)
account for all 372 captured incoming references, representing 241 distinct
heads. No incoming head remains unresolved. Main's merged spelling, Zotero and
spaCy changes are retained, together with document-review hardening and stable
golden host selection.

Checkpoints are saved through non-forced expected-head GitHub updates and use
`[skip ci]`. No GitHub Actions, workflow, check-run or CI-status endpoint is
queried, awaited, dispatched or rerun.
