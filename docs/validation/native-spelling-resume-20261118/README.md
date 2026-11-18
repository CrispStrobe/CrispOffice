# Native spelling resume — recovered qualification

The spelling implementation is preserved at `f482b06f`. On resumption, the
spelling branch was fast-forwarded to the qualified Zotero continuation
`fb1fd4dc3edda824c3e043c035dbfad1f0fe0869`. All seven spelling production,
regression and smoke-runner blobs are unchanged by that integration.

Fresh full local regression execution has completed: **1,303 registered tests
passed** across 44 files, with zero failures or skips. Eight pre-existing
grammar fixture rows are repeated, so this is **1,295 distinct suite/name
cases**; all 41 new spelling cases are distinct. The first report treated
duplicate names as a bookkeeping failure; the exact original receipt and
executed runner are retained beside a transparent reparse of the same raw
events. No product tests were repeated for that correction.

The final isolated-baseline, portable/static and remote evidence audits are
still being completed at this incremental checkpoint. Current machine-readable
state is [status.json](status.json). Do not treat this checkpoint as final
qualification.

The [current incoming reconciliation](reconciliation-current.md) accounts for
all 376 observed references and 242 distinct heads. The recovered
[evidence archive](evidence.tar.xz) is indexed by size and SHA-256 in
[evidence-index.json](evidence-index.json). It currently preserves the complete
reconciliation, independent review, runtime restoration and fresh full
regression results.

No GitHub Actions, workflow, check or CI-status endpoint has been queried,
awaited, dispatched or rerun. Remote saves use non-forced expected-head updates.

## Earlier implementation checkpoint

The text below records the earlier checkpoint, before the interruption; its
focused run counts are historical and excluded from current totals.

### Implementation checkpoint — 18 November 2026

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
