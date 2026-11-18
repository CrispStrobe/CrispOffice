# Native spelling quality: independent review

## Result and source binding

**Source review accepted: no remaining blocking finding in the reviewed
changes.** Two concrete platform filtering gaps were found in the first
checkpoint and corrected before this conclusion. Runtime cohort results and
compiled parity are recorded separately; this review does not turn source
inspection into a claim of physical-device qualification.

The integration baseline is `1ffcf91a3443caf9a6e8b45a3e6cab3f041831ae`.
The first platform checkpoint was
`86b8b7a394759a72540b05d2ec40f412c1902485`; the engine/UI/reconciliation
checkpoint was `deb6b06975db80ee7eb1e6a762edfa20fba80654`.
The following Git blob IDs bind this conclusion to the reviewed final files:

| File | Git blob |
| --- | --- |
| `packages/quds_office_engine/lib/src/proofing/german_spelling.dart` | `f35c341a2f468351d7e27fa5c2e9277c40c1fc4c` |
| `packages/quds_office_engine/test/proofing/german_spelling_shortlist_test.dart` | `658b4dd2e7173f4e82419598a5f2321c96196080` |
| `packages/quds_office_engine/tool/check_native_spelling.dart` | `f97d679b8f6c9b110a42fd8a268869eae9b66a5d` |
| `packages/quds_office_editor/lib/src/proofing/platform_spelling_provider.dart` | `6f272d8342653a3cf56a38ff23835610d197de59` |
| `packages/quds_office_editor/test/platform_spelling_provider_test.dart` | `e0b81c41ce9c7daac4747eb634e66e982e771534` |
| `packages/quds_office_editor/test/platform_spelling_dialog_test.dart` | `623020250fcd406507d0208e64ac23c128102800` |

## Findings raised and resolved

1. **Invisible native replacements could still erase a word.** The first
   filter accepted format-only strings such as U+200B, U+200E, U+202E and
   U+2066: they are not removed by Dart's whitespace trimming and passed the
   original control-character check. The reviewer reproduced those predicate
   results in the pinned Dart 3.13.7 VM. A review action could therefore appear
   blank while replacing the original word with invisible content.

   The final filter requires a code point outside Unicode mark, format and
   separator categories. It separately rejects bidi formatting controls
   U+202A–U+202E and U+2066–U+2069 even inside an otherwise visible suggestion.
   Regression tests cover these cases and preserve visible Arabic, Hebrew,
   Persian and Indic text, including internal ZWNJ/ZWJ. An issue with no usable
   alternatives remains an issue with an empty replacement list.

2. **Combining marks hid an adjacent identifier edge.** The original two-unit
   lookbehind missed a number or connector followed by a combining mark:
   `42\u0301Feler`, `_\u0301Feler` and `𝟘\u0301Feler`. The reviewer
   confirmed both the failed predicates and valid grapheme boundaries for
   those spans; protected-text detection did not mask the problem.

   The final implementation builds identifier start/end sets during one
   grapheme traversal. A Unicode numeric/connector match is attempted at each
   cluster's start, and native spans use set membership at their boundaries.
   It handles supplementary digits and arbitrarily long marked edges without
   copying or rescanning the paragraph prefix for each finding. The new test
   includes 128 combining marks; separate prose, hyphen-part and CJK controls
   remain covered.

Both corrections were independently inspected after implementation. The new
tests target the actual provider; the review's predicate reproductions are
additional diagnostic evidence, not additional passing cohort counts.

## Engine shortlist and vocabulary review

The engine now applies its existing case transformation before counting
suggestion slots. Distinct lexical entries that display as the same uppercase
or sentence-initial correction share one slot; the search can continue for
another distinct choice. The insertion-ordered set preserves discovery order,
and self-replacements do not consume a slot.

The transformation is unchanged for accepted dictionary candidates.
`personal.contains(value)` is checked first, retaining exact declared owner
spelling, including mixed-case names. No owner vocabulary or document text is
written during suggestion generation. Mid-sentence noun/verb case distinctions
remain separate. The existing dictionary-membership, Swiss-locale and compound
checks still apply.

The candidate budget and fallback limits are unchanged. Continuing past
duplicate displayed forms may consume more of that existing budget; it does
not authorize an unbounded search. Tests cover caps of zero, one, two and five,
stable ordering, exact personal names, a tiny budget, Swiss sharp-s behavior
and source compound separators. This establishes the specified shortlist
behavior, not exhaustive suggestion recall.

## Platform, editor and portable smoke review

Native suggestions retain backend order after filtering. The implementation
inspects at most 64 candidates, rejects entries over 256 UTF-16 units, and
returns at most eight distinct choices. It rejects empty/whitespace-only,
format-only, identical, malformed-surrogate and disallowed-control entries.
Internal spaces, ordinary accent forms and script joiners remain supported.
Malformed source ranges still fail validation; URL/email/backtick protections,
locale selection and native-channel scheduling retain their existing behavior.

The editor tests use the actual Flutter spell-check service with a mocked
native channel. They select a multiword correction from the Word review
dialog, verify exact source coordinates after an emoji, check undo/redo and
confirm that adding an unknown word to owner vocabulary does not edit the
document. A result without usable suggestions does not become a clean report.

The extended portable smoke panel has 25 explicit cases. It checks status,
expected finding count/source, UTF-16 source slices, replacement caps and
the requested correction. Its complete emitted result objects support
comparison across VM, native AOT and JavaScript executions. The smoke panel
does not itself prove population-level German accuracy.

## Limits

This review covers the bound source and its targeted regressions. It does not
claim new physical Android/iOS dictionary acceptance, cancellation of a
still-running OS request, target-device latency, a full application build or
new external-native/model qualification. Historical acceptance panels remain
attributed to their original evidence. No GitHub Actions, check or CI status
endpoint was used.
