# Independent native spelling projection review

## Scope

Reviewed `platform_spelling_provider.dart`, the new projection regressions,
and the Word review tests against integrated main
`1e07cb852766f8651815138785be74c64a09ddc0`. The reviewer authored only the two
new Word dialog regressions and their small helper extensions; the provider
implementation and provider projection tests were authored separately.

No blocking source defect was found in the reviewed projection implementation.

## Source mapping and correction safety

- Only U+00AD is omitted from the native request. Literal hyphens, apostrophes,
  no-break spaces, script joiners, line endings and other authored characters
  retain their code units. The original request/document is never normalized
  in place.
- Native offsets are validated as UTF-16 intervals in the checked text. The
  retained-unit map recovers the original start and the end immediately after
  the last retained unit. This includes interior soft hyphens while leaving
  leading/trailing discretionary controls outside the correction.
- Both checked and original grapheme boundaries are required. A valid interval
  after projection alone is insufficient because removing a control can change
  regional-indicator pairing in the original text.
- Protected ranges are computed in both source and checked text. This retains
  source protections while preventing soft hyphens from hiding a URL, email or
  code span from protection. Numeric and connector edges are checked after
  projection, including marked and supplementary digits.
- Exact source no-ops and suggestions that differ only by U+00AD placement are
  rejected before the existing eight-choice limit. This prevents a spelling
  button from silently removing discretionary layout without correcting text.
- Default Flutter spelling-service cache clearing remains inside the shared
  scheduler lane. Projection maps belong to individual requests; identical
  normalized text from different documents does not share source coordinates.
- Empty projected input returns success only after disposal/availability and
  exact-language checks; it does not occupy the native request lane.

## Independent Word regressions

Two tests use Flutter's actual `DefaultSpellCheckService` and a controlled
`SystemChannels.spellCheck` response rather than a replacement provider:

1. `🙂 a\u00adlot.` is sent as `🙂 alot.`; the finding retains source interval
   `(3, 8)` and original `a\u00adlot`. Checking does not edit the document.
   Normalized no-op suggestions are absent. Selecting `a lot` replaces exactly
   that interval; undo restores the original U+00AD and redo restores the
   corrected text.
2. Adding `quds\u00adcloud` through the review UI saves normalized `qudscloud`
   in the owning vocabulary. Reopening plain spelling under that owner hides
   the finding; a different owner still sees the soft-hyphen original. The
   document remains unchanged, no undo entry is created, and the other
   language's vocabulary remains empty.

The baseline run used the unchanged provider blob
`6f272d8342653a3cf56a38ff23835610d197de59`. Both new tests failed precisely
because the native channel received U+00AD; the two pre-existing dialog tests
passed. The baseline process exited 1, with empty stderr. Raw events and
source/test identities are retained in `dialog-baseline.jsonl` and
`dialog-baseline-inputs.json`. The test file passed formatting with zero
changes, preserving the tested bytes.

## Review recommendation

The reviewer requested a separate original-boundary case using regional
indicators `A / U+00AD / BC`, which project to `AB / C`. A native `AB` interval
is valid in projected text but would split original `BC`. The implementation
already rejects that interval. A separate reviewer added
`native correction cannot split a source flag after projection`, exercising
the equally invalid projected `C` interval `(4, 6)` whose mapped start splits
original `BC`. Its raw event stream was inspected: this case and three other
review controls all pass, with zero failures/skips and process exit 0. Strict
analysis reports no issues. The compact `projection-review.json` receipt binds
the exact source/test hashes. The other controls cover alternate soft-hyphen
placement no-ops and availability/language/disposal checks for empty projected
input. The recommendation is resolved.

## Limits

These checks cover source-coordinate safety, controlled native responses and
the real Flutter review workflow. They do not qualify physical Android/iOS
dictionaries, dictionary coverage, live-device performance, or a new spaCy
model/build. No CI endpoint was queried or awaited.
